<!--
  ヘッダーコンポーネント
  
  ナビゲーションバーとアクションボタンを提供
-->
<script lang="ts">
  import { getVersion } from '../lib/api';
  import { onMount, onDestroy } from 'svelte';
  import { getPushServer } from '../lib/pushserver';

  let version = $state('...');
  let bootsnap = $state(false);
  let queueSize = $state(0);
  let isConnected = $state(false);
  let pushServer = getPushServer();

  onMount(async () => {
    try {
      const versionData = await getVersion();
      version = versionData.narou;
      bootsnap = false; // TODO: APIから取得
    } catch (error) {
      console.error('バージョン情報の取得に失敗:', error);
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
  <nav class="container mx-auto px-4 py-3">
    <div class="flex items-center justify-between">
      <div class="flex items-center space-x-4">
        <h1 class="text-2xl font-bold text-blue-600 dark:text-blue-400">
          Narou.rb MOD
          {#if bootsnap}
            <span class="text-yellow-500" title="Bootsnap enabled">⚡︎</span>
          {/if}
          <span class="text-sm text-gray-500 ml-2">WEB UI</span>
        </h1>
        <span class="text-xs text-gray-500 dark:text-gray-400">
          v{version}
        </span>
        
        <!-- 接続状態インジケーター -->
        <div class="flex items-center gap-2">
          <div 
            class="w-2 h-2 rounded-full {isConnected ? 'bg-green-500' : 'bg-red-500'}"
            title={isConnected ? 'PushServer接続中' : 'PushServer未接続'}
          ></div>
          {#if queueSize > 0}
            <span class="text-xs px-2 py-1 bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200 rounded">
              処理中: {queueSize}
            </span>
          {/if}
        </div>
      </div>
      
      <div class="flex items-center space-x-2">
        <a
          href="/"
          class="px-4 py-2 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors"
        >
          小説一覧
        </a>
        <a
          href="/settings"
          class="px-4 py-2 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors"
        >
          設定
        </a>
        <button
          class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors"
          onclick={() => window.location.reload()}
        >
          更新
        </button>
      </div>
    </div>
  </nav>
</header>
