<!--
  ヘッダーコンポーネント
  
  ナビゲーションバーとアクションボタンを提供
-->
<script lang="ts">
  import { getVersion, getSettings } from '../lib/api';
  import { onMount, onDestroy } from 'svelte';
  import { getPushServer } from '../lib/pushserver';
  import ThemeToggle from './ThemeToggle.svelte';
  import PowerMenu from './PowerMenu.svelte';

  let version = $state('...');
  let bootsnap = $state(false);
  let queueSize = $state(0);
  let isConnected = $state(false);
  let hasAozoraEpub3 = $state<boolean | null>(null);
  let pushServer = getPushServer();
  let currentPath = $state('/');

  onMount(async () => {
    // 現在のパスを取得
    currentPath = window.location.pathname;
    
    try {
      const versionData = await getVersion();
      version = versionData.narou;
      bootsnap = false; // TODO: APIから取得
    } catch (error) {
      console.error('バージョン情報の取得に失敗:', error);
    }

    // 設定を取得してaozoraepub3dirの状態をチェック
    try {
      const settings = await getSettings();
      const aozoraepub3dir = settings.global?.aozoraepub3dir?.value || settings.local?.aozoraepub3dir?.value;
      hasAozoraEpub3 = !!aozoraepub3dir && aozoraepub3dir !== '';
    } catch (error) {
      console.error('設定の取得に失敗:', error);
      hasAozoraEpub3 = null;
    }

    // PushServerイベントリスナー設定
    pushServer.on('connected', handleConnected);
    pushServer.on('disconnected', handleDisconnected);
    pushServer.on('notification.queue', handleQueueNotification);
  });

  onDestroy(() => {
    pushServer.off('connected', handleConnected);
    pushServer.off('disconnected', handleDisconnected);
    pushServer.off('notification.queue', handleQueueNotification);
  });

  function handleConnected() {
    isConnected = true;
  }

  function handleDisconnected() {
    isConnected = false;
  }

  function handleQueueNotification(data: [number, number]) {
    const [webWorkerSize, workerSize] = data;
    queueSize = webWorkerSize + workerSize;
  }
</script>

<header class="bg-white dark:bg-gray-800 shadow-md">
  <nav class="container mx-auto px-2.5 py-3">
    <div class="flex items-center justify-between">
      <div class="flex items-center space-x-4">
        <!-- ロゴ（クリック可能） -->
        <a href="/" class="flex items-baseline space-x-2 cursor-pointer hover:opacity-80 transition-opacity">
          <h1 class="text-2xl font-bold text-blue-600 dark:text-blue-400">
            Narou.rb MOD
            {#if bootsnap}
              <span class="text-yellow-500" title="Bootsnap enabled">⚡︎</span>
            {/if}
          </h1>
        </a>
        
        <!-- 接続状態インジケーター -->
        <div class="flex items-baseline gap-6 mx-4">
          <!-- PushServer状態 -->
          <div class="flex items-baseline gap-1.5">
            <i 
              class="fas fa-server text-xs {isConnected ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'}"
              title={isConnected ? 'PushServer接続中' : 'PushServer未接続'}
            ></i>
            <span class="text-xs text-gray-600 dark:text-gray-400">Push</span>
          </div>
          
          <!-- AozoraEpub3設定状態 -->
          {#if hasAozoraEpub3 !== null}
            <div class="flex items-baseline gap-1.5">
              <i 
                class="fas fa-retweet text-xs {hasAozoraEpub3 ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'}"
                title={hasAozoraEpub3 ? '青空文庫epub3変換ツールのパスが設定されています' : '青空文庫epub3変換ツールのパスが設定されていません'}
              ></i>
              <span class="text-xs text-gray-600 dark:text-gray-400">Aozora</span>
            </div>
          {/if}
        </div>
        
        <!-- キューサイズ表示 -->
        <div>
          {#if queueSize > 0}
            <span class="text-xs px-2 py-1 bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200 rounded">
              処理中: {queueSize}
            </span>
          {/if}
        </div>
      </div>
      
      <div class="flex items-center space-x-2">
        <ThemeToggle />
        
        <!-- 電源メニュー -->
        <PowerMenu />
        
        <!-- 更新ボタン（アイコンのみ） -->
        <button
          class="p-2 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors cursor-pointer"
          onclick={() => window.location.reload()}
          title="ページを更新"
        >
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
        </button>
        
        <!-- ナビゲーションボタン -->
        <a
          href="/"
          class="px-3 py-1.5 text-sm font-medium rounded transition-colors cursor-pointer {currentPath === '/' || currentPath === '/index.html' ? 'bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300' : 'text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700'}"
        >
          小説リスト
        </a>
        <a
          href="/settings"
          class="px-3 py-1.5 text-sm font-medium rounded transition-colors cursor-pointer {currentPath === '/settings' || currentPath === '/settings/' || currentPath === '/settings/index.html' ? 'bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300' : 'text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700'}"
        >
          設定
        </a>
      </div>
    </div>
  </nav>
</header>
