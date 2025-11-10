<!--
  タスクキューコンポーネント
  
  ダウンロード・変換タスクの進捗状況をリアルタイム表示
-->
<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { progressStore, type ProgressInfo } from '../lib/progressStore';
  import { getPushServer, type EchoMessage } from '../lib/pushserver';
  import { cancelTask as apiCancelTask } from '../lib/api';

  /**
   * タスク情報
   */
  interface TaskInfo extends ProgressInfo {
    novelId: number | 'NEW';
    title: string;
    author: string;
    startTime: Date;
    endTime?: Date;
  }

  // ローカルストレージキー
  const STORAGE_KEY = 'narou-task-queue';
  const COLLAPSED_KEY = 'narou-task-queue-collapsed';

  // タスクリスト
  let tasks = $state<TaskInfo[]>([]);
  
  // ソート設定
  let sortBy = $state<'status' | 'startTime' | ''>('startTime');
  let sortOrder = $state<'asc' | 'desc'>('asc');
  
  // 折りたたみ状態（デフォルトは折りたたみ）
  let isCollapsed = $state(true);

  /**
   * タスクをlocalStorageに保存
   */
  function saveTasks() {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(tasks));
    } catch (err) {
      console.error('タスクの保存に失敗:', err);
    }
  }

  /**
   * タスクをlocalStorageから読み込み
   */
  function loadTasks() {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved) {
        const loaded = JSON.parse(saved);
        // Date型を復元
        tasks = loaded.map((task: any) => ({
          ...task,
          startTime: new Date(task.startTime),
          endTime: task.endTime ? new Date(task.endTime) : undefined,
        }));
      }
      
      // 折りたたみ状態を復元
      const collapsedSaved = localStorage.getItem(COLLAPSED_KEY);
      if (collapsedSaved !== null) {
        isCollapsed = JSON.parse(collapsedSaved);
      }
    } catch (err) {
      console.error('タスクの読み込みに失敗:', err);
    }
  }
  
  /**
   * 折りたたみ状態を保存
   */
  function saveCollapsedState() {
    try {
      localStorage.setItem(COLLAPSED_KEY, JSON.stringify(isCollapsed));
    } catch (err) {
      console.error('折りたたみ状態の保存に失敗:', err);
    }
  }
  
  /**
   * 折りたたみ状態をトグル
   */
  function toggleCollapse() {
    isCollapsed = !isCollapsed;
    saveCollapsedState();
  }

  /**
   * タスクを追加
   */
  export function addTask(novelId: number | 'NEW', title: string, author: string, status: ProgressInfo['status'] = 'waiting') {
    const newTask: TaskInfo = {
      novelId,
      title,
      author,
      status,
      startTime: new Date(),
      updatedAt: Date.now(),
    };
    tasks = [...tasks, newTask];
    saveTasks();
    
    // キューが積まれたら自動展開
    if (isCollapsed) {
      isCollapsed = false;
      saveCollapsedState();
    }
  }

  /**
   * タスク状態を更新
   */
  export function updateTaskStatus(novelId: number | 'NEW', status: ProgressInfo['status'], message?: string) {
    tasks = tasks.map(task => {
      if (task.novelId === novelId) {
        const updated = {
          ...task,
          status,
          message,
          updatedAt: Date.now(),
        };
        
        // 完了またはエラー時に終了時刻を記録
        if (status === 'completed' || status === 'error') {
          updated.endTime = new Date();
        }
        
        return updated;
      }
      return task;
    });
    saveTasks();
  }

  /**
   * タスクを削除（キャンセル）
   */
  async function cancelTask(novelId: number | 'NEW') {
    if (novelId === 'NEW') {
      // NEW の場合はローカルから削除のみ
      tasks = tasks.filter(task => task.novelId !== novelId);
      saveTasks();
      return;
    }
    
    try {
      // バックエンドにキャンセルリクエスト送信
      await apiCancelTask(novelId);
      
      // ローカルのタスクリストから削除
      tasks = tasks.filter(task => task.novelId !== novelId);
      saveTasks();
      
      // progressStoreからもクリア
      progressStore.clearProgress(novelId);
    } catch (err) {
      console.error('タスクのキャンセルに失敗:', err);
      // エラーが発生してもローカルからは削除
      tasks = tasks.filter(task => task.novelId !== novelId);
      saveTasks();
    }
  }

  /**
   * すべてのタスクをキャンセル
   */
  async function cancelAllTasks() {
    try {
      // バックエンドにキャンセルリクエスト送信
      await apiCancelTask(0); // IDに関係なく全タスクキャンセル
      
      // ローカルのタスクリストをクリア
      tasks = [];
      saveTasks();
      
      // テーブルを折りたたむ
      isCollapsed = true;
      saveCollapsedState();
      
      // progressStoreをクリア
      progressStore.clearAll();
    } catch (err) {
      console.error('タスクのキャンセルに失敗:', err);
      // エラーが発生してもローカルからはクリア
      tasks = [];
      saveTasks();
      isCollapsed = true;
      saveCollapsedState();
    }
  }

  /**
   * 完了/エラータスクをクリア
   */
  function clearCompleted() {
    tasks = tasks.filter(task => task.status !== 'completed' && task.status !== 'error');
    saveTasks();
  }

  /**
   * ソート処理
   */
  function handleSort(column: 'status' | 'startTime') {
    if (sortBy === column) {
      sortOrder = sortOrder === 'asc' ? 'desc' : 'asc';
    } else {
      sortBy = column;
      sortOrder = 'asc';
    }
    applySorting();
  }

  /**
   * ソートを適用
   */
  function applySorting() {
    if (!sortBy) return;

    tasks = [...tasks].sort((a, b) => {
      let aVal: any;
      let bVal: any;

      switch (sortBy) {
        case 'status':
          const statusOrder: Record<string, number> = {
            'waiting': 1,
            'downloading': 2,
            'converting': 3,
            'completed': 4,
            'error': 5,
          };
          aVal = statusOrder[a.status] || 0;
          bVal = statusOrder[b.status] || 0;
          break;
        case 'startTime':
          aVal = a.startTime.getTime();
          bVal = b.startTime.getTime();
          break;
      }

      if (aVal < bVal) return sortOrder === 'asc' ? -1 : 1;
      if (aVal > bVal) return sortOrder === 'asc' ? 1 : -1;
      return 0;
    });
  }

  /**
   * 状態バッジのスタイルを取得
   */
  function getStatusBadgeClass(status: ProgressInfo['status']): string {
    switch (status) {
      case 'waiting':
        return 'bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200 animate-pulse';
      case 'downloading':
        return 'bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200 animate-pulse';
      case 'converting':
        return 'bg-purple-100 dark:bg-purple-900 text-purple-800 dark:text-purple-200 animate-pulse';
      case 'completed':
        return 'bg-green-100 dark:bg-green-900 text-green-800 dark:text-green-200';
      case 'error':
        return 'bg-red-100 dark:bg-red-900 text-red-800 dark:text-red-200';
      default:
        return 'bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200';
    }
  }

  /**
   * 状態ラベルを取得
   */
  function getStatusLabel(status: ProgressInfo['status']): string {
    switch (status) {
      case 'waiting':
        return 'WAIT';
      case 'downloading':
        return 'DL';
      case 'converting':
        return '変換中';
      case 'completed':
        return '完了';
      case 'error':
        return 'ERROR';
      default:
        return status;
    }
  }
  
  /**
   * アクティブなタスク数を取得（待機中/DL中/変換中）
   */
  const activeTaskCount = $derived(
    tasks.filter(t => t.status === 'waiting' || t.status === 'downloading' || t.status === 'converting').length
  );

  onMount(() => {
    loadTasks();
    
    // progressStoreからの更新を監視
    const unsubscribeProgress = progressStore.subscribe(progressMap => {
      // progressMapの変更をtasksに反映
      Object.entries(progressMap).forEach(([novelIdStr, progress]) => {
        const novelId = parseInt(novelIdStr);
        const existingTask = tasks.find(t => t.novelId === novelId);
        if (existingTask) {
          updateTaskStatus(novelId, progress.status, progress.message);
        }
      });
    });
    
    // PushServerからのechoイベントを監視
    const pushServer = getPushServer();
    const echoHandler = (data: EchoMessage) => {
      handleEchoMessage(data);
    };
    pushServer.on('echo', echoHandler);
    
    return () => {
      unsubscribeProgress();
      pushServer.off('echo', echoHandler);
    };
  });
  
  /**
   * PushServerのechoメッセージから進捗を検出
   */
  function handleEchoMessage(data: EchoMessage) {
    const message = data.body;
    
    // 小説IDを抽出
    const idMatch = message.match(/ID[:：]\s*(\d+)/i);
    if (!idMatch) return;
    
    const novelId = parseInt(idMatch[1]);
    const task = tasks.find(t => t.novelId === novelId);
    if (!task) return;
    
    // 処理状態を判定
    // 1. DL開始: "ID:123　タイトル のDL開始"
    if (/のDL開始/.test(message)) {
      progressStore.setProgress(novelId, 'downloading', 'ダウンロード中...');
    }
    // 2. 変換開始: "ID:123　タイトル の変換を開始"
    else if (/の変換を開始/.test(message)) {
      progressStore.setProgress(novelId, 'converting', '変換中...');
    }
    // 3. 変換終了: "縦書用の変換が終了しました"
    else if (/変換が終了しました|変換しました/.test(message)) {
      progressStore.setProgress(novelId, 'completed', '完了');
    }
    // 4. エラーメッセージ
    else if (/エラー|error|失敗|failed/.test(message)) {
      progressStore.setProgress(novelId, 'error', message);
    }
    // 5. 章のダウンロード進捗（"第n部分"）
    else if (/第[\d０-９]+部分/.test(message)) {
      // 既にDL中でない場合のみ状態変更
      if (task.status === 'idle' || task.status === 'waiting') {
        progressStore.setProgress(novelId, 'downloading', 'ダウンロード中...');
      }
    }
  }
</script>

<div class="bg-white dark:bg-gray-800 rounded-lg shadow-md mb-4 md:mx-2.5 lg:mx-12">
  <!-- ヘッダー（常に表示） -->
  <div class="p-4 border-b border-gray-200 dark:border-gray-700">
    <div class="flex items-center justify-between">
      <div class="flex items-center gap-3">
        <button
          onclick={toggleCollapse}
          class="text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-100 transition-colors"
          title={isCollapsed ? '展開' : '折りたたむ'}
        >
          <svg class="w-5 h-5 transform transition-transform {isCollapsed ? '' : 'rotate-90'}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
          </svg>
        </button>
        <h2 class="text-base font-semibold text-gray-900 dark:text-gray-100">
          タスクキュー
        </h2>
        {#if tasks.length > 0}
          <span class="px-2 py-1 text-xs rounded bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200">
            {tasks.length}件
          </span>
        {/if}
        {#if activeTaskCount > 0}
          <span class="px-2 py-1 text-xs rounded bg-green-100 dark:bg-green-900 text-green-800 dark:text-green-200 animate-pulse">
            処理中: {activeTaskCount}件
          </span>
        {/if}
      </div>
      <button
        onclick={cancelAllTasks}
        class="px-3 py-1 text-sm bg-red-600 text-white rounded hover:bg-red-700 transition-colors disabled:bg-gray-400 disabled:cursor-not-allowed"
        disabled={tasks.length === 0}
      >
        タスクをキャンセル
      </button>
    </div>
  </div>

  <!-- テーブル（折りたたみ可能） -->
  {#if !isCollapsed}
    <div class="p-4">
      {#if tasks.length === 0}
        <div class="text-center py-8 text-gray-600 dark:text-gray-400">
          <p>タスクはありません</p>
        </div>
      {:else}
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
        <thead class="bg-gray-50 dark:bg-gray-700">
          <tr>
            <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap">
              <button
                onclick={() => handleSort('status')}
                class="flex items-center gap-1 hover:text-gray-700 dark:hover:text-gray-100"
              >
                状態
                {#if sortBy === 'status'}
                  <span>{sortOrder === 'asc' ? '▲' : '▼'}</span>
                {/if}
              </button>
            </th>
            <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap">
              小説ID
            </th>
            <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap">
              タイトル
            </th>
            <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap">
              著者名
            </th>
            <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap">
              <button
                onclick={() => handleSort('startTime')}
                class="flex items-center gap-1 hover:text-gray-700 dark:hover:text-gray-100"
              >
                開始時刻
                {#if sortBy === 'startTime'}
                  <span>{sortOrder === 'asc' ? '▲' : '▼'}</span>
                {/if}
              </button>
            </th>
            <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap">
              終了時刻
            </th>
          </tr>
        </thead>
        <tbody class="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700">
          {#each tasks as task (task.novelId + '_' + task.startTime.getTime())}
            <tr class="hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors">
              <td class="px-4 py-3 text-sm">
                <span 
                  class="px-2 py-1 text-xs rounded whitespace-nowrap {getStatusBadgeClass(task.status)}"
                  title={task.message}
                >
                  {getStatusLabel(task.status)}
                </span>
              </td>
              <td class="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">
                {task.novelId}
              </td>
              <td class="px-4 py-3 text-sm font-medium text-gray-900 dark:text-gray-100">
                {task.title}
              </td>
              <td class="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">
                {task.author}
              </td>
              <td class="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">
                {task.startTime.toLocaleTimeString('ja-JP')}
              </td>
              <td class="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">
                {task.endTime ? task.endTime.toLocaleTimeString('ja-JP') : '-'}
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
      {/if}
    </div>
  {/if}
</div>
