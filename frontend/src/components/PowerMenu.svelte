<!--
  電源メニューコンポーネント
  
  サーバーの状態表示・再起動・停止を行うドロップダウンメニュー
-->
<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { getServerStatus, restartServer, stopServer } from '../lib/api';
  import type { ServerStatus } from '../lib/api';
  import ServerActionModal from './ServerActionModal.svelte';

  let isOpen = $state(false);
  let serverStatus = $state<ServerStatus | null>(null);
  let isLoading = $state(false);
  let statusInterval: number | null = null;
  let isMounted = $state(false);
  let currentAction = $state<'restart' | 'stop' | null>(null);

  onMount(() => {
    isMounted = true;
    loadServerStatus();
    // 5秒ごとにステータスを更新
    statusInterval = window.setInterval(loadServerStatus, 5000);
    
    // クリック外でメニューを閉じる
    document.addEventListener('click', handleOutsideClick);
    
    return () => {
      if (statusInterval) {
        clearInterval(statusInterval);
      }
      document.removeEventListener('click', handleOutsideClick);
    };
  });

  onDestroy(() => {
    if (statusInterval) {
      clearInterval(statusInterval);
    }
    if (isMounted) {
      document.removeEventListener('click', handleOutsideClick);
    }
  });

  async function loadServerStatus() {
    try {
      serverStatus = await getServerStatus();
      console.log('サーバーステータス:', JSON.stringify(serverStatus, null, 2));
    } catch (error) {
      console.error('サーバーステータスの取得に失敗:', error);
    }
  }

  function handleOutsideClick(event: MouseEvent) {
    const target = event.target as HTMLElement;
    if (!target.closest('.power-menu-container')) {
      isOpen = false;
    }
  }

  function toggleMenu(event: MouseEvent) {
    event.stopPropagation();
    isOpen = !isOpen;
  }

  async function handleRestart() {
    if (!confirm('サーバーを再起動しますか？\n\n再起動後、このページは自動的にリロードされます。')) {
      return;
    }

    isLoading = true;
    try {
      await restartServer();
      isOpen = false;
      currentAction = 'restart';
      // モーダルがpollingチェックとリロードを処理
    } catch (error: any) {
      console.error('サーバーの再起動に失敗:', error);
      alert(error?.message || 'サーバーの再起動に失敗しました');
      isLoading = false;
    }
  }

  async function handleStop() {
    if (!confirm('サーバーを停止しますか？\n\n停止後、このページは表示できなくなります。')) {
      return;
    }

    isLoading = true;
    try {
      await stopServer();
      isOpen = false;
      currentAction = 'stop';
    } catch (error: any) {
      console.error('サーバーの停止に失敗:', error);
      alert(error?.message || 'サーバーの停止に失敗しました');
    } finally {
      isLoading = false;
    }
  }

  function getStatusText(): string {
    if (!serverStatus) return '確認中...';
    
    if (serverStatus.backend.running && serverStatus.frontend.running) {
      return '起動中（フルモード）';
    } else if (serverStatus.backend.running) {
      return '起動中（バックエンドのみ）';
    } else {
      return '状態不明';
    }
  }

  function getStatusColor(): string {
    if (!serverStatus) return 'text-gray-500';
    
    if (serverStatus.backend.running) {
      return 'text-green-600 dark:text-green-400';
    } else {
      return 'text-red-600 dark:text-red-400';
    }
  }
</script>

<div class="power-menu-container relative">
  <button
    class="p-2 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors cursor-pointer relative"
    onclick={toggleMenu}
    title="サーバー管理"
  >
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5.636 18.364a9 9 0 010-12.728m12.728 0a9 9 0 010 12.728m-9.9-2.829a5 5 0 010-7.07m7.072 0a5 5 0 010 7.07M13 12a1 1 0 11-2 0 1 1 0 012 0z" />
    </svg>
    
    <!-- ステータスインジケーター -->
    {#if serverStatus}
      <span class="absolute top-1 right-1 w-2 h-2 rounded-full {serverStatus.backend.running ? 'bg-green-500' : 'bg-red-500'}"></span>
    {/if}
  </button>

  {#if isOpen}
    <div class="absolute right-0 mt-2 w-72 bg-white dark:bg-gray-800 rounded-lg shadow-lg border border-gray-200 dark:border-gray-700 z-50">
      <!-- ステータス表示 -->
      <div class="px-4 py-3 border-b border-gray-200 dark:border-gray-700">
        <h3 class="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-2">サーバーステータス</h3>
        
        <div class="space-y-2 text-sm">
          <div class="flex items-center justify-between">
            <span class="text-gray-600 dark:text-gray-400">全体:</span>
            <span class="{getStatusColor()} font-medium">{getStatusText()}</span>
          </div>
          
          {#if serverStatus}
            <div class="flex items-center justify-between">
              <span class="text-gray-600 dark:text-gray-400">バックエンド:</span>
              <span class="{serverStatus.backend.running ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'}">
                {serverStatus.backend.running ? '起動中' : '停止中'}
                {#if serverStatus.backend.pid}
                  <span class="text-xs text-gray-500">(PID: {serverStatus.backend.pid})</span>
                {/if}
              </span>
            </div>
            
            <div class="flex items-center justify-between">
              <span class="text-gray-600 dark:text-gray-400">フロントエンド:</span>
              <span class="{serverStatus.frontend.running ? 'text-green-600 dark:text-green-400' : 'text-gray-500 dark:text-gray-500'}">
                {serverStatus.frontend.running ? '起動中' : '停止中'}
                {#if serverStatus.frontend.pid}
                  <span class="text-xs text-gray-500">(PID: {serverStatus.frontend.pid})</span>
                {/if}
              </span>
            </div>
          {/if}
        </div>
      </div>

      <!-- アクションボタン -->
      <div class="p-2">
        <button
          class="w-full px-4 py-2 text-left text-sm text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors cursor-pointer flex items-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed"
          onclick={handleRestart}
          disabled={isLoading}
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
          サーバーを再起動
        </button>
        
        <button
          class="w-full px-4 py-2 text-left text-sm text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-900/20 rounded transition-colors cursor-pointer flex items-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed"
          onclick={handleStop}
          disabled={isLoading}
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
          サーバーを停止
        </button>
      </div>

      {#if isLoading}
        <div class="px-4 py-2 text-xs text-center text-gray-500 dark:text-gray-400 border-t border-gray-200 dark:border-gray-700">
          処理中...
        </div>
      {/if}
    </div>
  {/if}
</div>

<!-- サーバーアクション実行中モーダル -->
<ServerActionModal bind:action={currentAction} />

