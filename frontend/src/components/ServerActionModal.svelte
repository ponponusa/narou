<!--
  サーバーアクション実行中モーダル
  
  サーバーの再起動・停止実行時に進行状況を表示
-->
<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { getServerStatus } from '../lib/api';
  import { isServerStopped } from '../lib/stores/serverStatus';

  interface Props {
    action: 'restart' | 'stop' | null;
    onClose?: () => void;
  }

  let { action = $bindable(null), onClose }: Props = $props();
  
  let status = $state<'processing' | 'checking' | 'completed' | 'error'>('processing');
  let message = $state('');
  let checkInterval: number | null = null;
  let checkAttempts = $state(0);
  let maxAttempts = 30; // 最大30秒間チェック

  $effect(() => {
    if (action === 'restart') {
      status = 'processing';
      message = 'サーバーを再起動しています...';
      startRestartCheck();
    } else if (action === 'stop') {
      status = 'processing';
      message = 'サーバーを停止しています...';
      startStopCheck();
    }
  });

  onDestroy(() => {
    if (checkInterval) {
      clearInterval(checkInterval);
    }
  });

  function startRestartCheck() {
    checkAttempts = 0;
    status = 'checking';
    message = 'サーバーの再起動を確認中...';

    // 3秒待ってからチェック開始
    setTimeout(() => {
      checkInterval = window.setInterval(async () => {
        checkAttempts++;
        
        try {
          const serverStatus = await getServerStatus();
          
          if (serverStatus.backend.running) {
            // サーバーが起動した
            status = 'completed';
            message = 'サーバーの再起動が完了しました';
            // 初回ロードフラグをリセット（次回リロード時に待機させる）
            sessionStorage.removeItem('novelListLoaded');
            if (checkInterval) {
              clearInterval(checkInterval);
            }
          } else if (checkAttempts >= maxAttempts) {
            // タイムアウト
            status = 'error';
            message = 'サーバーの再起動確認がタイムアウトしました';
            if (checkInterval) {
              clearInterval(checkInterval);
            }
          }
        } catch (error) {
          // エラーは再起動中の一時的な切断の可能性があるので継続
          if (checkAttempts >= maxAttempts) {
            status = 'error';
            message = 'サーバーとの接続に失敗しました';
            if (checkInterval) {
              clearInterval(checkInterval);
            }
          }
        }
      }, 1000);
    }, 3000);
  }

  function startStopCheck() {
    checkAttempts = 0;
    status = 'checking';
    message = 'サーバーの停止を確認中...';

    // 2秒待ってからチェック開始
    setTimeout(() => {
      checkInterval = window.setInterval(async () => {
        checkAttempts++;
        
        try {
          await getServerStatus();
          
          // まだ応答がある場合は継続
          if (checkAttempts >= maxAttempts) {
            status = 'error';
            message = 'サーバーの停止確認がタイムアウトしました';
            if (checkInterval) {
              clearInterval(checkInterval);
            }
          }
        } catch (error) {
          // 接続エラー = サーバーが停止した
          status = 'completed';
          message = 'サーバーが正常に停止しました';
          isServerStopped.set(true); // グローバル状態を更新
          if (checkInterval) {
            clearInterval(checkInterval);
          }
        }
      }, 1000);
    }, 2000);
  }

  function handleReload() {
    window.location.reload();
  }

  function handleClose() {
    action = null;
    if (onClose) {
      onClose();
    }
  }
</script>

{#if action}
  <!-- モーダル背景（操作不可） -->
  <div class="fixed inset-0 bg-black bg-opacity-75 z-50 flex items-center justify-center">
    <!-- モーダルコンテンツ -->
    <div class="bg-white dark:bg-gray-800 rounded-lg shadow-2xl p-8 max-w-md w-full mx-4">
      <div class="text-center">
        <!-- アイコン・スピナー -->
        {#if status === 'processing' || status === 'checking'}
          <div class="mb-6">
            <svg class="animate-spin h-16 w-16 mx-auto text-blue-600 dark:text-blue-400" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
          </div>
        {:else if status === 'completed'}
          <div class="mb-6">
            <svg class="h-16 w-16 mx-auto text-green-600 dark:text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
            </svg>
          </div>
        {:else if status === 'error'}
          <div class="mb-6">
            <svg class="h-16 w-16 mx-auto text-red-600 dark:text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
            </svg>
          </div>
        {/if}

        <!-- メッセージ -->
        <h3 class="text-xl font-semibold text-gray-900 dark:text-white mb-2">
          {#if action === 'restart'}
            サーバー再起動
          {:else}
            サーバー停止
          {/if}
        </h3>
        
        <p class="text-gray-600 dark:text-gray-400 mb-6">
          {message}
        </p>

        <!-- 進行状況 -->
        {#if status === 'checking'}
          <div class="mb-6">
            <div class="text-sm text-gray-500 dark:text-gray-400">
              確認中... ({checkAttempts}/{maxAttempts}秒)
            </div>
          </div>
        {/if}

        <!-- アクションボタン -->
        {#if status === 'completed'}
          <div class="space-y-3">
            {#if action === 'restart'}
              <button
                onclick={handleReload}
                class="w-full px-6 py-3 bg-blue-600 hover:bg-blue-700 text-white font-medium rounded-lg transition-colors cursor-pointer"
              >
                Web UIを再読み込み
              </button>
            {:else}
              <button
                onclick={handleClose}
                class="w-full px-6 py-3 bg-gray-600 hover:bg-gray-700 text-white font-medium rounded-lg transition-colors cursor-pointer"
              >
                閉じる
              </button>
              <p class="text-sm text-gray-500 dark:text-gray-400">
                このページを閉じてください
              </p>
            {/if}
          </div>
        {:else if status === 'error'}
          <button
            onclick={handleClose}
            class="w-full px-6 py-3 bg-gray-600 hover:bg-gray-700 text-white font-medium rounded-lg transition-colors cursor-pointer"
          >
            閉じる
          </button>
        {/if}
      </div>
    </div>
  </div>
{/if}
