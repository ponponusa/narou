<!--
  進捗表示コンポーネント
  
  ダウンロード・変換などの進捗をリアルタイムで表示
-->
<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { getPushServer, type EchoMessage } from '../lib/pushserver';

  let consoleMessages = $state<string[]>([]);
  let isVisible = $state(false);
  let queueSize = $state(0);
  let pushServer = getPushServer();

  onMount(() => {
    // PushServer接続
    pushServer.connect();

    // エコーメッセージをキャプチャ
    pushServer.on('echo', (data: EchoMessage) => {
      if (!data.no_history) {
        const message = stripTermColor(data.body);
        consoleMessages = [...consoleMessages, message].slice(-100); // 最新100件のみ保持
        
        // メッセージが追加されたら自動的に表示
        if (!isVisible) {
          isVisible = true;
        }
        
        // 自動スクロール
        setTimeout(() => {
          const console = document.getElementById('progress-console');
          if (console) {
            console.scrollTop = console.scrollHeight;
          }
        }, 10);
      }
    });

    // キュー通知
    pushServer.on('notification.queue', (data: [number, number]) => {
      const [webWorkerSize, workerSize] = data;
      queueSize = webWorkerSize + workerSize;
      
      // キューが空になったら数秒後に自動で閉じる
      if (queueSize === 0 && isVisible) {
        setTimeout(() => {
          if (queueSize === 0) {
            // isVisible = false;
          }
        }, 3000);
      }
    });
  });

  onDestroy(() => {
    // コンポーネント破棄時に切断
    pushServer.disconnect();
  });

  function stripTermColor(text: string): string {
    // TermColorタグを除去
    return text.replace(/<\/?[a-z]+>/gi, '');
  }

  function toggleVisibility() {
    isVisible = !isVisible;
  }

  function clearConsole() {
    consoleMessages = [];
  }
</script>

<!-- 進捗表示ウィンドウ -->
{#if isVisible}
  <div class="fixed bottom-4 right-4 w-96 bg-white dark:bg-gray-800 rounded-lg shadow-2xl border border-gray-200 dark:border-gray-700 z-50">
    <!-- ヘッダー -->
    <div class="flex items-center justify-between px-4 py-3 bg-gray-100 dark:bg-gray-700 rounded-t-lg border-b border-gray-200 dark:border-gray-600">
      <div class="flex items-center gap-2">
        <div class="w-3 h-3 rounded-full {queueSize > 0 ? 'bg-green-500 animate-pulse' : 'bg-gray-400'}"></div>
        <h3 class="font-semibold text-gray-900 dark:text-gray-100">
          進捗状況
        </h3>
        {#if queueSize > 0}
          <span class="text-xs px-2 py-1 bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200 rounded">
            {queueSize} 件処理中
          </span>
        {/if}
      </div>
      <div class="flex items-center gap-2">
        <button
          onclick={clearConsole}
          class="text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
          title="ログをクリア"
        >
          🗑️
        </button>
        <button
          onclick={toggleVisibility}
          class="text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
          title="閉じる"
        >
          ✕
        </button>
      </div>
    </div>

    <!-- コンソール -->
    <div
      id="progress-console"
      class="h-64 overflow-y-auto p-3 bg-gray-50 dark:bg-gray-900 font-mono text-xs text-gray-800 dark:text-gray-200"
    >
      {#if consoleMessages.length === 0}
        <div class="text-center text-gray-500 dark:text-gray-400 py-8">
          処理待機中...
        </div>
      {:else}
        {#each consoleMessages as message}
          <div class="whitespace-pre-wrap break-all">{message}</div>
        {/each}
      {/if}
    </div>
  </div>
{/if}

<!-- フローティングボタン -->
{#if !isVisible && queueSize > 0}
  <button
    onclick={toggleVisibility}
    class="fixed bottom-4 right-4 w-14 h-14 bg-blue-600 text-white rounded-full shadow-lg hover:bg-blue-700 transition-all z-40 flex items-center justify-center"
    title="進捗を表示"
  >
    <div class="relative">
      <span class="text-xl">📊</span>
      <span class="absolute -top-2 -right-2 w-5 h-5 bg-red-500 text-white text-xs rounded-full flex items-center justify-center">
        {queueSize}
      </span>
    </div>
  </button>
{/if}
