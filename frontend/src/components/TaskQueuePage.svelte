<!--
  タスクキュー専用ページコンポーネント
  
  サーバータスクの詳細一覧と管理UI
  - フィルタリング機能
  - ソート機能
  - ページング機能
  - タスク操作（キャンセル、一時停止、再開）
-->
<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { getPushServer, type EchoMessage } from '../lib/pushserver';
  import { 
    getTasks, 
    getTaskSummary,
    cancelTaskById, 
    pauseTask, 
    resumeTask,
    type Task, 
    type TaskSummary,
    type TaskStatus 
  } from '../lib/api';

  // フィルタ・ソート設定
  let statusFilter = $state<TaskStatus | ''>('');
  let sortBy = $state<'created_at' | 'started_at' | 'status'>('created_at');
  let sortOrder = $state<'asc' | 'desc'>('desc');
  
  // ページング設定
  let currentPage = $state(1);
  let itemsPerPage = $state(20);
  
  // タスクデータ
  let allTasks = $state<Task[]>([]);
  let filteredTasks = $state<Task[]>([]);
  let paginatedTasks = $state<Task[]>([]);
  let taskSummary = $state<TaskSummary | null>(null);
  
  // ローディング状態
  let isLoading = $state(true);
  let error = $state<string | null>(null);
  
  // 定期更新タイマー
  let updateTimer: ReturnType<typeof setInterval> | null = null;
  
  // PushServer接続
  let pushServerUnsubscribe: (() => void) | null = null;

  /**
   * タスクを取得
   */
  async function fetchTasks() {
    try {
      isLoading = true;
      error = null;
      
      // 全タスクを取得（制限なし）
      const tasks = await getTasks();
      allTasks = tasks;
      
      // サマリーも取得
      taskSummary = await getTaskSummary();
      
      applyFiltersAndSort();
    } catch (err) {
      console.error('[TaskQueuePage] Failed to fetch tasks:', err);
      error = 'タスクの取得に失敗しました';
    } finally {
      isLoading = false;
    }
  }

  /**
   * フィルタとソートを適用
   */
  function applyFiltersAndSort() {
    // フィルタ適用
    let tasks = allTasks;
    if (statusFilter) {
      tasks = tasks.filter(t => t.status === statusFilter);
    }
    
    // ソート適用
    tasks = [...tasks].sort((a, b) => {
      let aVal: any;
      let bVal: any;
      
      if (sortBy === 'created_at') {
        aVal = new Date(a.created_at).getTime();
        bVal = new Date(b.created_at).getTime();
      } else if (sortBy === 'started_at') {
        aVal = a.started_at ? new Date(a.started_at).getTime() : 0;
        bVal = b.started_at ? new Date(b.started_at).getTime() : 0;
      } else if (sortBy === 'status') {
        aVal = a.status;
        bVal = b.status;
      }
      
      if (sortOrder === 'asc') {
        return aVal < bVal ? -1 : aVal > bVal ? 1 : 0;
      } else {
        return aVal > bVal ? -1 : aVal < bVal ? 1 : 0;
      }
    });
    
    filteredTasks = tasks;
    
    // ページングを適用
    applyPagination();
  }

  /**
   * ページングを適用
   */
  function applyPagination() {
    const start = (currentPage - 1) * itemsPerPage;
    const end = start + itemsPerPage;
    paginatedTasks = filteredTasks.slice(start, end);
  }

  /**
   * ページ数を計算
   */
  $derived totalPages = Math.ceil(filteredTasks.length / itemsPerPage);

  /**
   * フィルタ変更時
   */
  function handleFilterChange() {
    currentPage = 1; // 最初のページに戻る
    applyFiltersAndSort();
  }

  /**
   * ソート変更時
   */
  function handleSortChange() {
    applyFiltersAndSort();
  }

  /**
   * ページ変更
   */
  function goToPage(page: number) {
    if (page < 1 || page > totalPages) return;
    currentPage = page;
    applyPagination();
  }

  /**
   * タスクステータスの表示文字列
   */
  function getStatusLabel(status: TaskStatus): string {
    const labels: Record<TaskStatus, string> = {
      queued: '待機中',
      running: '実行中',
      paused: '一時停止',
      completed: '完了',
      failed: '失敗',
      canceled: 'キャンセル',
    };
    return labels[status] || status;
  }

  /**
   * タスクステータスのCSSクラス
   */
  function getStatusClass(status: TaskStatus): string {
    const classes: Record<TaskStatus, string> = {
      queued: 'bg-gray-500',
      running: 'bg-blue-500 animate-pulse',
      paused: 'bg-yellow-500',
      completed: 'bg-green-500',
      failed: 'bg-red-500',
      canceled: 'bg-gray-400',
    };
    return classes[status] || 'bg-gray-500';
  }

  /**
   * タスクをキャンセル
   */
  async function handleCancelTask(taskId: string) {
    if (!confirm('このタスクをキャンセルしますか？')) return;
    
    try {
      await cancelTaskById(taskId);
      await fetchTasks();
    } catch (err) {
      console.error('タスクのキャンセルに失敗:', err);
      alert('タスクのキャンセルに失敗しました');
    }
  }

  /**
   * タスクを一時停止
   */
  async function handlePauseTask(taskId: string) {
    try {
      await pauseTask(taskId);
      await fetchTasks();
    } catch (err) {
      console.error('タスクの一時停止に失敗:', err);
      alert('タスクの一時停止に失敗しました');
    }
  }

  /**
   * タスクを再開
   */
  async function handleResumeTask(taskId: string) {
    try {
      await resumeTask(taskId);
      await fetchTasks();
    } catch (err) {
      console.error('タスクの再開に失敗:', err);
      alert('タスクの再開に失敗しました');
    }
  }

  /**
   * 日時フォーマット
   */
  function formatDateTime(dateString: string | undefined): string {
    if (!dateString) return '-';
    const date = new Date(dateString);
    return date.toLocaleString('ja-JP', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
  }

  /**
   * マウント時の処理
   */
  onMount(async () => {
    // 初回データ取得
    await fetchTasks();
    
    // 定期更新（5秒ごと）
    updateTimer = setInterval(fetchTasks, 5000);
    
    // PushServer通知を購読
    const pushServer = getPushServer();
    if (pushServer) {
      pushServerUnsubscribe = pushServer.subscribe((data: EchoMessage) => {
        if (data['notification.task.updated']) {
          fetchTasks();
        }
      });
    }
  });

  /**
   * アンマウント時の処理
   */
  onDestroy(() => {
    if (updateTimer) {
      clearInterval(updateTimer);
      updateTimer = null;
    }
    
    if (pushServerUnsubscribe) {
      pushServerUnsubscribe();
      pushServerUnsubscribe = null;
    }
  });
</script>

<div class="container mx-auto px-4 py-6 max-w-7xl">
  <!-- ページヘッダー -->
  <div class="mb-6">
    <h1 class="text-2xl font-bold text-gray-900 dark:text-gray-100 mb-2">
      <i class="fas fa-tasks mr-2"></i>
      タスクキュー管理
    </h1>
    <p class="text-gray-600 dark:text-gray-400">
      サーバータスクの詳細一覧と管理
    </p>
  </div>

  <!-- サマリーカード -->
  {#if taskSummary}
    <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
      <div class="bg-blue-50 dark:bg-blue-900/20 rounded-lg p-4">
        <div class="text-sm text-blue-600 dark:text-blue-400 mb-1">実行中</div>
        <div class="text-2xl font-bold text-blue-700 dark:text-blue-300">
          {taskSummary.current ? 1 : 0}
        </div>
      </div>
      <div class="bg-gray-50 dark:bg-gray-700/50 rounded-lg p-4">
        <div class="text-sm text-gray-600 dark:text-gray-400 mb-1">待機中</div>
        <div class="text-2xl font-bold text-gray-700 dark:text-gray-300">
          {taskSummary.queued.length}
        </div>
      </div>
      <div class="bg-green-50 dark:bg-green-900/20 rounded-lg p-4">
        <div class="text-sm text-green-600 dark:text-green-400 mb-1">完了</div>
        <div class="text-2xl font-bold text-green-700 dark:text-green-300">
          {taskSummary.recent_completed.length}
        </div>
      </div>
      <div class="bg-red-50 dark:bg-red-900/20 rounded-lg p-4">
        <div class="text-sm text-red-600 dark:text-red-400 mb-1">失敗</div>
        <div class="text-2xl font-bold text-red-700 dark:text-red-300">
          {taskSummary.recent_failed.length}
        </div>
      </div>
    </div>
  {/if}

  <!-- フィルタ・ソートコントロール -->
  <div class="bg-white dark:bg-gray-800 rounded-lg shadow-md p-4 mb-6">
    <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
      <!-- ステータスフィルタ -->
      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
          ステータス
        </label>
        <select
          bind:value={statusFilter}
          onchange={handleFilterChange}
          class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100"
        >
          <option value="">すべて</option>
          <option value="queued">待機中</option>
          <option value="running">実行中</option>
          <option value="paused">一時停止</option>
          <option value="completed">完了</option>
          <option value="failed">失敗</option>
          <option value="canceled">キャンセル</option>
        </select>
      </div>

      <!-- ソート項目 -->
      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
          ソート
        </label>
        <select
          bind:value={sortBy}
          onchange={handleSortChange}
          class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100"
        >
          <option value="created_at">作成日時</option>
          <option value="started_at">開始日時</option>
          <option value="status">ステータス</option>
        </select>
      </div>

      <!-- ソート順 -->
      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
          順序
        </label>
        <select
          bind:value={sortOrder}
          onchange={handleSortChange}
          class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100"
        >
          <option value="desc">降順</option>
          <option value="asc">昇順</option>
        </select>
      </div>
    </div>
  </div>

  <!-- タスク一覧 -->
  <div class="bg-white dark:bg-gray-800 rounded-lg shadow-md overflow-hidden">
    {#if isLoading}
      <div class="p-8 text-center">
        <div class="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500"></div>
        <p class="mt-2 text-gray-600 dark:text-gray-400">読み込み中...</p>
      </div>
    {:else if error}
      <div class="p-8 text-center text-red-600 dark:text-red-400">
        <i class="fas fa-exclamation-circle text-4xl mb-2"></i>
        <p>{error}</p>
      </div>
    {:else if paginatedTasks.length === 0}
      <div class="p-8 text-center text-gray-600 dark:text-gray-400">
        <i class="fas fa-inbox text-4xl mb-2"></i>
        <p>タスクはありません</p>
      </div>
    {:else}
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-gray-700">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase">
                ステータス
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase">
                タイプ
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase">
                タイトル
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase">
                進捗
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase">
                作成日時
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase">
                経過時間
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase">
                操作
              </th>
            </tr>
          </thead>
          <tbody class="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700">
            {#each paginatedTasks as task}
              <tr class="hover:bg-gray-50 dark:hover:bg-gray-700/50">
                <td class="px-4 py-3 whitespace-nowrap">
                  <span class="px-2 py-1 text-xs rounded text-white {getStatusClass(task.status)}">
                    {getStatusLabel(task.status)}
                  </span>
                </td>
                <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-900 dark:text-gray-100">
                  {task.type}
                </td>
                <td class="px-4 py-3 text-sm text-gray-900 dark:text-gray-100">
                  <div class="max-w-md">
                    <div class="font-medium truncate">{task.novel_title || '-'}</div>
                    {#if task.novel_author}
                      <div class="text-xs text-gray-500 dark:text-gray-400 truncate">{task.novel_author}</div>
                    {/if}
                    {#if task.message}
                      <div class="text-xs text-gray-500 dark:text-gray-400 mt-1">{task.message}</div>
                    {/if}
                  </div>
                </td>
                <td class="px-4 py-3 whitespace-nowrap text-sm">
                  {#if task.progress > 0}
                    <div class="w-24">
                      <div class="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2">
                        <div 
                          class="bg-blue-500 h-2 rounded-full transition-all duration-300"
                          style="width: {task.progress}%"
                        ></div>
                      </div>
                      <div class="text-xs text-gray-500 dark:text-gray-400 mt-1">
                        {task.progress.toFixed(1)}%
                      </div>
                    </div>
                  {:else}
                    <span class="text-gray-400 dark:text-gray-500">-</span>
                  {/if}
                </td>
                <td class="px-4 py-3 whitespace-nowrap text-xs text-gray-500 dark:text-gray-400">
                  {formatDateTime(task.created_at)}
                </td>
                <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-900 dark:text-gray-100">
                  {task.elapsed_time.toFixed(1)}秒
                </td>
                <td class="px-4 py-3 whitespace-nowrap text-sm">
                  <div class="flex gap-1">
                    {#if task.status === 'running'}
                      <button
                        onclick={() => handlePauseTask(task.id)}
                        class="px-2 py-1 text-xs rounded bg-yellow-500 hover:bg-yellow-600 text-white"
                        title="一時停止"
                      >
                        <i class="fas fa-pause"></i>
                      </button>
                    {/if}
                    {#if task.status === 'paused'}
                      <button
                        onclick={() => handleResumeTask(task.id)}
                        class="px-2 py-1 text-xs rounded bg-green-500 hover:bg-green-600 text-white"
                        title="再開"
                      >
                        <i class="fas fa-play"></i>
                      </button>
                    {/if}
                    {#if task.status === 'queued' || task.status === 'running' || task.status === 'paused'}
                      <button
                        onclick={() => handleCancelTask(task.id)}
                        class="px-2 py-1 text-xs rounded bg-red-500 hover:bg-red-600 text-white"
                        title="キャンセル"
                      >
                        <i class="fas fa-times"></i>
                      </button>
                    {/if}
                  </div>
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>

      <!-- ページネーション -->
      {#if totalPages > 1}
        <div class="px-4 py-3 bg-gray-50 dark:bg-gray-700 border-t border-gray-200 dark:border-gray-600">
          <div class="flex items-center justify-between">
            <div class="text-sm text-gray-700 dark:text-gray-300">
              {filteredTasks.length}件中 {((currentPage - 1) * itemsPerPage) + 1} - {Math.min(currentPage * itemsPerPage, filteredTasks.length)}件を表示
            </div>
            <div class="flex gap-2">
              <button
                onclick={() => goToPage(currentPage - 1)}
                disabled={currentPage === 1}
                class="px-3 py-1 text-sm rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                前へ
              </button>
              
              <!-- ページ番号 -->
              {#each Array.from({ length: Math.min(5, totalPages) }, (_, i) => {
                const maxPages = 5;
                const half = Math.floor(maxPages / 2);
                let start = Math.max(1, currentPage - half);
                let end = Math.min(totalPages, start + maxPages - 1);
                start = Math.max(1, end - maxPages + 1);
                return start + i;
              }) as page}
                {#if page <= totalPages}
                  <button
                    onclick={() => goToPage(page)}
                    class="px-3 py-1 text-sm rounded border {currentPage === page ? 'bg-blue-500 text-white border-blue-500' : 'border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700'}"
                  >
                    {page}
                  </button>
                {/if}
              {/each}
              
              <button
                onclick={() => goToPage(currentPage + 1)}
                disabled={currentPage === totalPages}
                class="px-3 py-1 text-sm rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                次へ
              </button>
            </div>
          </div>
        </div>
      {/if}
    {/if}
  </div>
</div>

<style>
  /* 追加のスタイルが必要な場合はここに記述 */
</style>
