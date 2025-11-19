<!--
  ヘッダーコンポーネント
  
  ナビゲーションバーとアクションボタンを提供
-->
<script lang="ts">
  import { getVersion, getSettings } from "../lib/api";
  import { onMount, onDestroy } from "svelte";
  import { getPushServer } from "../lib/pushserver";
  import { isServerStopped } from "../lib/stores/serverStatus";
  import ThemeToggle from "./ThemeToggle.svelte";
  import PowerMenu from "./PowerMenu.svelte";
  import MobileMenu from "./MobileMenu.svelte";

  let version = $state("...");
  let bootsnap = $state(false);
  let queueSize = $state(0);
  let isConnected = $state(false);
  let hasAozoraEpub3 = $state<boolean | null>(null);
  let pushServer = getPushServer();
  let currentPath = $state("/");

  onMount(async () => {
    // 現在のパスを取得
    currentPath = window.location.pathname;

    try {
      const versionData = await getVersion();
      version = versionData.narou;
      bootsnap = false; // TODO: APIから取得
    } catch (error) {
      console.error("バージョン情報の取得に失敗:", error);
    }

    // 設定を取得してaozoraepub3dirの状態をチェック
    try {
      const settings = await getSettings();
      const aozoraepub3dir =
        settings.global?.aozoraepub3dir?.value ||
        settings.local?.aozoraepub3dir?.value;
      hasAozoraEpub3 = !!aozoraepub3dir && aozoraepub3dir !== "";
    } catch (error) {
      console.error("設定の取得に失敗:", error);
      hasAozoraEpub3 = null;
    }

    // PushServerイベントリスナー設定
    pushServer.on("connected", handleConnected);
    pushServer.on("disconnected", handleDisconnected);
    pushServer.on("notification.queue", handleQueueNotification);
  });

  onDestroy(() => {
    pushServer.off("connected", handleConnected);
    pushServer.off("disconnected", handleDisconnected);
    pushServer.off("notification.queue", handleQueueNotification);
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
        <a
          href="/"
          class="flex items-baseline space-x-2 cursor-pointer hover:opacity-80 transition-opacity"
        >
          <h1 class="text-2xl font-bold text-blue-600 dark:text-blue-400">
            Narou.rb MOD
            {#if bootsnap}
              <span class="text-yellow-500" title="Bootsnap enabled">⚡︎</span>
            {/if}
          </h1>
        </a>

        <!-- 接続状態インジケーター -->
        <div class="flex items-baseline gap-6 mx-4">
          <!-- キューサイズ表示 -->
          <div>
            {#if queueSize > 0}
              <span
                class="text-xs px-2 py-1 bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200 rounded"
              >
                処理中: {queueSize}
              </span>
            {/if}
          </div>
        </div>
      </div>

      <div class="flex items-center space-x-2">
        <!-- デスクトップメニュー（md以上で表示） -->
        <div class="hidden md:flex items-center space-x-2">
          <!-- ナビゲーションボタン（アイコン） -->
          <a
            href="/"
            class="p-2 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors {currentPath ===
              '/' || currentPath === '/index.html'
              ? 'bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300'
              : ''} {$isServerStopped
              ? 'opacity-50 cursor-not-allowed pointer-events-none'
              : 'cursor-pointer'}"
            title="小説リスト"
          >
            <svg
              class="w-5 h-5"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"
              />
            </svg>
          </a>

          <a
            href="/tasks"
            class="relative p-2 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors {currentPath ===
              '/tasks' ||
            currentPath === '/tasks/' ||
            currentPath === '/tasks/index.html'
              ? 'bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300'
              : ''} {$isServerStopped
              ? 'opacity-50 cursor-not-allowed pointer-events-none'
              : 'cursor-pointer'} flex items-center justify-center"
            title="タスクキュー"
          >
            <svg
              class="w-5 h-5"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01"
              />
            </svg>
            {#if queueSize > 0}
              <span
                class="absolute top-1 right-1 block h-2.5 w-2.5 rounded-full ring-2 ring-white dark:ring-gray-800 bg-red-500"
              ></span>
            {/if}
          </a>

          <a
            href="/settings"
            class="p-2 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors {currentPath ===
              '/settings' ||
            currentPath === '/settings/' ||
            currentPath === '/settings/index.html'
              ? 'bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300'
              : ''} {$isServerStopped
              ? 'opacity-50 cursor-not-allowed pointer-events-none'
              : 'cursor-pointer'}"
            title="設定"
          >
            <svg
              class="w-5 h-5"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
              />
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
              />
            </svg>
          </a>

          <!-- 更新ボタン（アイコンのみ） -->
          <button
            class="p-2 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors {$isServerStopped
              ? 'opacity-50 cursor-not-allowed'
              : 'cursor-pointer'}"
            onclick={() => window.location.reload()}
            title="ページを更新"
            disabled={$isServerStopped}
          >
            <svg
              class="w-5 h-5"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
              />
            </svg>
          </button>

          <!-- 電源メニュー -->
          <PowerMenu />

          <div class="ml-2">
            <ThemeToggle />
          </div>
        </div>

        <!-- モバイルメニュー（md未満で表示） -->
        <MobileMenu />
      </div>
    </div>
  </nav>
</header>
