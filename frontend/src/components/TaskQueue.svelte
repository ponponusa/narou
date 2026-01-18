<!--
  タスクキュー専用ページコンポーネント

  サーバータスクの詳細一覧と管理UI
  - フィルタリング機能
  - ソート機能
  - ページング機能
  - タスク操作（キャンセル）
-->
<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import { getPushServer } from "../lib/pushserver";
  import {
    getTasks,
    getTaskSummary,
    cancelTaskById,
    type Task,
    type TaskSummary,
    type TaskStatus,
    type TaskType,
  } from "../lib/api";

  // フィルタ・ソート設定
  // 実際に適用されるフィルタ（検索ボタン押下時に反映）
  let searchText = $state("");
  let statusFilter = $state<TaskStatus | "">("");

  // フォーム入力中の一時的な値
  let draftSearchText = $state("");
  let draftStatusFilter = $state<TaskStatus | "">("");

  // フィルタ処理中フラグ
  let isFiltering = $state(false);

  let sortBy = $state<
    | "created_at"
    | "started_at"
    | "status"
    | "type"
    | "novel_id"
    | "novel_title"
    | "novel_author"
  >("status");
  let sortOrder = $state<"asc" | "desc">("desc");

  // ページング設定
  let currentPage = $state(1);
  let itemsPerPage = $state(20);

  // タスクデータ
  let allTasks = $state<Task[]>([]);
  let taskSummary = $state<TaskSummary | null>(null);

  // ローディング状態
  let isLoading = $state(true);
  let error = $state<string | null>(null);

  // 定期更新タイマー
  let updateTimer: ReturnType<typeof setInterval> | null = null;

  // PushServer接続
  let pushServerUnsubscribe: (() => void) | null = null;

  /**
   * サマリーデータから全タスクを抽出
   */
  function extractTasksFromSummary(summary: TaskSummary): Task[] {
    const tasks: Task[] = [];
    if (summary.current) tasks.push(summary.current);
    if (summary.convert_current) tasks.push(summary.convert_current);
    if (summary.queued) tasks.push(...summary.queued);
    if (summary.convert_queued) tasks.push(...summary.convert_queued);
    if (summary.recent_completed) tasks.push(...summary.recent_completed);
    if (summary.recent_failed) tasks.push(...summary.recent_failed);
    return tasks;
  }

  /**
   * 既存のタスク配列とサマリーをマージ（差分更新）
   * - 新規タスク: 追加
   * - 既存タスク: 更新
   * - サマリーに含まれない古いタスク: 保持（初回ロード時のデータ）
   */
  function mergeTasks(existing: Task[], summary: TaskSummary): Task[] {
    // 既存タスクをMapに変換（id → Task）
    const taskMap = new Map(existing.map((t) => [t.id, t]));

    // サマリーから全タスクを抽出して更新
    const incomingTasks = extractTasksFromSummary(summary);
    for (const task of incomingTasks) {
      taskMap.set(task.id, task);
    }

    // 配列に戻す
    return Array.from(taskMap.values());
  }

  /**
   * サマリーデータでタスクを差分更新
   */
  function updateTasksFromSummary(summary: TaskSummary) {
    allTasks = mergeTasks(allTasks, summary);
    taskSummary = summary;
  }

  // === Svelte 5 Runes: リアクティブな派生データ ===
  // ステップ1: フィルタリング
  const filteredTasks = $derived.by(() => {
    let tasks = allTasks;

    // テキスト検索フィルタ
    if (searchText.trim()) {
      const search = searchText.toLowerCase();
      tasks = tasks.filter(
        (t) =>
          t.novel_id?.toString().includes(search) ||
          t.novel_title?.toLowerCase().includes(search) ||
          t.novel_author?.toLowerCase().includes(search)
      );
    }

    // ステータスフィルタ
    if (statusFilter) {
      tasks = tasks.filter((t) => t.status === statusFilter);
    }

    return tasks;
  });

  // ステップ2: ソート
  const sortedTasks = $derived.by(() => {
    const tasks = [...filteredTasks];

    tasks.sort((a, b) => {
      let aVal: any;
      let bVal: any;

      if (sortBy === "created_at") {
        aVal = new Date(a.created_at).getTime();
        bVal = new Date(b.created_at).getTime();
      } else if (sortBy === "started_at") {
        aVal = a.started_at ? new Date(a.started_at).getTime() : 0;
        bVal = b.started_at ? new Date(b.started_at).getTime() : 0;
      } else if (sortBy === "status") {
        aVal = a.status;
        bVal = b.status;
      } else if (sortBy === "type") {
        aVal = a.type;
        bVal = b.type;
      } else if (sortBy === "novel_id") {
        aVal = a.novel_id || 0;
        bVal = b.novel_id || 0;
      } else if (sortBy === "novel_title") {
        aVal = a.novel_title || "";
        bVal = b.novel_title || "";
      } else if (sortBy === "novel_author") {
        aVal = a.novel_author || "";
        bVal = b.novel_author || "";
      }

      if (sortOrder === "asc") {
        return aVal < bVal ? -1 : aVal > bVal ? 1 : 0;
      } else {
        return aVal > bVal ? -1 : aVal < bVal ? 1 : 0;
      }
    });

    return tasks;
  });

  // ステップ3: ページング情報
  const totalPages = $derived(Math.ceil(sortedTasks.length / itemsPerPage));
  const totalFiltered = $derived(sortedTasks.length);

  // ステップ4: 表示データ（スライス）
  const paginatedTasks = $derived.by(() => {
    const start = (currentPage - 1) * itemsPerPage;
    const end = start + itemsPerPage;
    return sortedTasks.slice(start, end);
  });
  // === リアクティブな派生データここまで ===

  /**
   * タスクを取得
   */
  async function fetchTasks() {
    try {
      isLoading = true;
      error = null;

      // 全タスクを取得（gzip圧縮済み）
      const tasks = await getTasks();
      allTasks = tasks;

      // サマリーも取得
      taskSummary = await getTaskSummary();

      // $derivedが自動的にフィルタ・ソート・ページングを再計算
    } catch (err) {
      console.error("[TaskQueuePage] Failed to fetch tasks:", err);
      error = "タスクの取得に失敗しました";
    } finally {
      isLoading = false;
    }
  }

  /**
   * カラムヘッダークリックでソート
   */
  function handleColumnSort(column: typeof sortBy) {
    if (sortBy === column) {
      // 同じカラムをクリックした場合は順序を反転
      sortOrder = sortOrder === "asc" ? "desc" : "asc";
    } else {
      // 異なるカラムをクリックした場合は降順から開始
      sortBy = column;
      sortOrder = "desc";
    }
    currentPage = 1; // ソート変更時は先頭ページへ
    // $derivedが自動的に再計算するのでapplyFiltersAndSort不要
  }

  /**
   * 検索実行（フィルタ適用）
   */
  function handleSearch() {
    // フィルタ処理中フラグをON
    isFiltering = true;

    // 少し遅延させてスピナーを表示
    setTimeout(() => {
      // draft変数から実際のフィルタ変数に反映
      searchText = draftSearchText;
      statusFilter = draftStatusFilter;
      currentPage = 1; // 最初のページに戻る

      // フィルタ処理完了後、次のフレームでスピナーをOFF
      requestAnimationFrame(() => {
        isFiltering = false;
      });
    }, 10);
  }

  /**
   * フィルタクリア
   */
  function clearFilters() {
    draftSearchText = "";
    draftStatusFilter = "";
    searchText = "";
    statusFilter = "";
    currentPage = 1;
  }

  /**
   * ページ変更
   */
  function goToPage(page: number) {
    if (page < 1 || page > totalPages) return;
    currentPage = page;
    // $derivedが自動的に再計算するのでapplyPagination不要
  }

  /**
   * タスクステータスの表示文字列
   */
  function getStatusLabel(status: TaskStatus): string {
    const labels: Record<TaskStatus, string> = {
      queued: "待機中",
      running: "実行中",
      completed: "完了",
      failed: "失敗",
      canceled: "キャンセル",
    };
    return labels[status] || status;
  }

  /**
   * タスクステータスのCSSクラス
   */
  function getStatusClass(status: TaskStatus): string {
    const classes: Record<TaskStatus, string> = {
      queued: "bg-gray-500",
      running: "bg-blue-500 animate-pulse",
      paused: "bg-yellow-500",
      completed: "bg-green-500",
      failed: "bg-red-500",
      canceled: "bg-gray-400",
    };
    return classes[status] || "bg-gray-500";
  }

  /**
   * タスク種別の表示文字列
   */
  function getTypeLabel(type: TaskType): string {
    const labels: Record<TaskType, string> = {
      download: "取得",
      convert: "変換",
      update: "更新チェック",
      remove: "削除",
    };
    return labels[type] || type;
  }

  /**
   * タスク種別のCSSクラス
   */
  function getTypeClass(type: TaskType): string {
    const classes: Record<TaskType, string> = {
      download:
        "bg-indigo-100 text-indigo-800 dark:bg-indigo-900/30 dark:text-indigo-300",
      convert:
        "bg-purple-100 text-purple-800 dark:bg-purple-900/30 dark:text-purple-300",
      update:
        "bg-cyan-100 text-cyan-800 dark:bg-cyan-900/30 dark:text-cyan-300",
      remove:
        "bg-orange-100 text-orange-800 dark:bg-orange-900/30 dark:text-orange-300",
    };
    return (
      classes[type] ||
      "bg-gray-100 text-gray-800 dark:bg-gray-900/30 dark:text-gray-300"
    );
  }

  /**
   * タスクをキャンセル
   */
  async function handleCancelTask(taskId: string) {
    if (!confirm("このタスクをキャンセルしますか？")) return;

    try {
      await cancelTaskById(taskId);
      await fetchTasks();
    } catch (err) {
      console.error("タスクのキャンセルに失敗:", err);
      alert("タスクのキャンセルに失敗しました");
    }
  }

  /**
   * 日時フォーマット
   */
  function formatDateTime(dateString: string | undefined): string {
    if (!dateString) return "-";
    const date = new Date(dateString);
    return date.toLocaleString("ja-JP", {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
  }

  /**
   * マウント時の処理
   */
  onMount(async () => {
    // 初回データ取得（全タスクをAPIから取得）
    await fetchTasks();

    // 定期更新（30秒ごと、フォールバック用）
    updateTimer = setInterval(fetchTasks, 30000);

    // PushServer通知を購読（差分更新）
    const pushServer = getPushServer();
    if (pushServer) {
      const listener = (data: TaskSummary) => {
        // notification.task.updated イベントのデータを直接使用して差分更新
        // APIリクエストなしでリアルタイム更新
        if (data) {
          updateTasksFromSummary(data);
        }
      };
      pushServer.on("notification.task.updated", listener);
      pushServerUnsubscribe = () =>
        pushServer.off("notification.task.updated", listener);
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
  <div class="mb-6 flex flex-col sm:flex-row sm:items-center sm:gap-4">
    <h1
      class="text-2xl font-bold text-gray-900 dark:text-gray-100 flex items-center gap-2"
    >
      <svg
        class="w-8 h-8 flex-shrink-0"
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
      タスクキュー管理
    </h1>
    <p class="text-gray-600 dark:text-gray-400 mt-1 sm:mt-0">
      サーバータスクの詳細一覧と管理
    </p>
  </div>

  <!-- サマリーカードとフィルタ・ソートコントロール -->
  <div class="mb-6">
    <div class="flex flex-col lg:flex-row gap-4">
      <!-- サマリーカード -->
      {#if taskSummary}
        <div class="grid grid-cols-2 lg:grid-cols-6 gap-3 lg:w-2/3">
          <button
            onclick={() => {
              draftStatusFilter = "running";
              handleSearch();
            }}
            class="bg-blue-50 dark:bg-blue-900/20 rounded-lg p-3 hover:bg-blue-100 dark:hover:bg-blue-900/30 transition-colors cursor-pointer text-left"
          >
            <div class="flex flex-col items-center justify-center h-full">
              <div class="text-xs text-blue-600 dark:text-blue-400 mb-1">
                更新中
              </div>
              <div class="text-xl font-bold text-blue-700 dark:text-blue-300">
                {taskSummary.current ? 1 : 0}
              </div>
            </div>
          </button>
          <button
            class="bg-purple-50 dark:bg-purple-900/20 rounded-lg p-3 cursor-default"
            disabled
          >
            <div class="flex flex-col items-center justify-center h-full">
              <div class="text-xs text-purple-600 dark:text-purple-400 mb-1">
                変換中
              </div>
              <div
                class="text-xl font-bold text-purple-700 dark:text-purple-300"
              >
                {taskSummary.convert_current ? 1 : 0}
              </div>
            </div>
          </button>
          <button
            onclick={() => {
              draftStatusFilter = "queued";
              handleSearch();
            }}
            class="bg-gray-50 dark:bg-gray-700/50 rounded-lg p-3 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors cursor-pointer text-left"
          >
            <div class="flex flex-col items-center justify-center h-full">
              <div class="text-xs text-gray-600 dark:text-gray-400 mb-1">
                待機中
              </div>
              <div class="text-xl font-bold text-gray-700 dark:text-gray-300">
                {taskSummary.queued.length +
                  (taskSummary.convert_queued?.length || 0)}
              </div>
            </div>
          </button>
          <button
            onclick={() => {
              draftStatusFilter = "completed";
              handleSearch();
            }}
            class="bg-green-50 dark:bg-green-900/20 rounded-lg p-3 hover:bg-green-100 dark:hover:bg-green-900/30 transition-colors cursor-pointer text-left"
          >
            <div class="flex flex-col items-center justify-center h-full">
              <div class="text-xs text-green-600 dark:text-green-400 mb-1">
                完了
              </div>
              <div class="text-xl font-bold text-green-700 dark:text-green-300">
                {taskSummary.completed_count}
              </div>
            </div>
          </button>
          <button
            onclick={() => {
              draftStatusFilter = "failed";
              handleSearch();
            }}
            class="bg-red-50 dark:bg-red-900/20 rounded-lg p-3 hover:bg-red-100 dark:hover:bg-red-900/30 transition-colors cursor-pointer text-left"
          >
            <div class="flex flex-col items-center justify-center h-full">
              <div class="text-xs text-red-600 dark:text-red-400 mb-1">
                失敗
              </div>
              <div class="text-xl font-bold text-red-700 dark:text-red-300">
                {taskSummary.failed_count}
              </div>
            </div>
          </button>
        </div>
      {/if}

      <!-- フィルタ・ソートコントロール -->
      <div class="bg-white dark:bg-gray-800 rounded-lg shadow-md p-4 lg:w-1/3">
        <div class="flex flex-col sm:flex-row gap-4 items-end">
          <!-- テキスト検索 -->
          <div class="flex-1">
            <input
              id="search-text"
              type="text"
              bind:value={draftSearchText}
              onkeydown={(e) => e.key === "Enter" && handleSearch()}
              placeholder="小説ID、タイトル、著者名"
              class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100"
            />
          </div>

          <!-- ステータスフィルタ -->
          <div class="sm:w-40">
            <select
              id="status-filter"
              bind:value={draftStatusFilter}
              class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100"
            >
              <option value="">ステータス</option>
              <option value="queued">待機中</option>
              <option value="running">実行中</option>
              <option value="completed">完了</option>
              <option value="failed">失敗</option>
              <option value="canceled">キャンセル</option>
            </select>
          </div>

          <!-- 検索ボタン -->
          <div class="flex items-end gap-2">
            <button
              onclick={handleSearch}
              disabled={isFiltering}
              class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
            >
              {#if isFiltering}
                <i class="fas fa-spinner fa-spin"></i>
                <span>検索中...</span>
              {:else}
                <i class="fas fa-search"></i>
                <span>検索</span>
              {/if}
            </button>
            <button
              onclick={clearFilters}
              class="px-4 py-2 bg-gray-600 text-white rounded-md hover:bg-gray-700 transition-colors"
              title="フィルターをクリア"
            >
              ✕
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- タスク一覧 -->
  <div class="bg-white dark:bg-gray-800 rounded-lg shadow-md overflow-hidden">
    {#if isLoading}
      <div class="p-8 text-center">
        <div
          class="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500"
        ></div>
        <p class="mt-2 text-gray-600 dark:text-gray-400">読み込み中...</p>
      </div>
    {:else if error}
      <div class="p-8 text-center text-red-600 dark:text-red-400">
        <i class="fas fa-exclamation-circle text-4xl mb-2"></i>
        <p>{error}</p>
      </div>
    {:else}
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-gray-700 whitespace-nowrap">
            <tr>
              <th
                class="px-3 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-600"
                onclick={() => handleColumnSort("status")}
              >
                <span class="flex items-center gap-1">
                  ステータス
                  {#if sortBy === "status"}
                    <i
                      class="fas fa-sort-{sortOrder === 'asc'
                        ? 'up'
                        : 'down'} text-blue-500"
                    ></i>
                  {:else}
                    <i class="fas fa-sort text-gray-400"></i>
                  {/if}
                </span>
              </th>
              <th
                class="px-3 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-600"
                onclick={() => handleColumnSort("type")}
              >
                <span class="flex items-center gap-1">
                  種別
                  {#if sortBy === "type"}
                    <i
                      class="fas fa-sort-{sortOrder === 'asc'
                        ? 'up'
                        : 'down'} text-blue-500"
                    ></i>
                  {:else}
                    <i class="fas fa-sort text-gray-400"></i>
                  {/if}
                </span>
              </th>
              <th
                class="px-3 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-600"
                onclick={() => handleColumnSort("novel_id")}
              >
                <span class="flex items-center gap-1">
                  小説ID
                  {#if sortBy === "novel_id"}
                    <i
                      class="fas fa-sort-{sortOrder === 'asc'
                        ? 'up'
                        : 'down'} text-blue-500"
                    ></i>
                  {:else}
                    <i class="fas fa-sort text-gray-400"></i>
                  {/if}
                </span>
              </th>
              <th
                class="px-3 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-600"
                onclick={() => handleColumnSort("novel_title")}
              >
                <span class="flex items-center gap-1">
                  タイトル
                  {#if sortBy === "novel_title"}
                    <i
                      class="fas fa-sort-{sortOrder === 'asc'
                        ? 'up'
                        : 'down'} text-blue-500"
                    ></i>
                  {:else}
                    <i class="fas fa-sort text-gray-400"></i>
                  {/if}
                </span>
              </th>
              <th
                class="px-3 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-600"
                onclick={() => handleColumnSort("novel_author")}
              >
                <span class="flex items-center gap-1">
                  著者名
                  {#if sortBy === "novel_author"}
                    <i
                      class="fas fa-sort-{sortOrder === 'asc'
                        ? 'up'
                        : 'down'} text-blue-500"
                    ></i>
                  {:else}
                    <i class="fas fa-sort text-gray-400"></i>
                  {/if}
                </span>
              </th>
              <th
                class="px-3 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase"
              >
                進捗
              </th>
              <th
                class="px-3 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-600"
                onclick={() => handleColumnSort("created_at")}
              >
                <span class="flex items-center gap-1">
                  作成日時
                  {#if sortBy === "created_at"}
                    <i
                      class="fas fa-sort-{sortOrder === 'asc'
                        ? 'up'
                        : 'down'} text-blue-500"
                    ></i>
                  {:else}
                    <i class="fas fa-sort text-gray-400"></i>
                  {/if}
                </span>
              </th>
              <th
                class="px-3 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase"
              >
                経過時間
              </th>
              <th
                class="px-3 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase"
              >
                アクション
              </th>
            </tr>
          </thead>
          <tbody
            class="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700"
          >
            {#if paginatedTasks.length === 0}
              <tr>
                <td
                  colspan="9"
                  class="px-4 py-8 text-center text-gray-600 dark:text-gray-400"
                >
                  <i class="fas fa-inbox text-4xl mb-2 block"></i>
                  現在、処理中のタスクはありません。
                </td>
              </tr>
            {:else}
              {#each paginatedTasks as task}
                <tr class="hover:bg-gray-50 dark:hover:bg-gray-700/50">
                  <td class="px-3 py-2 whitespace-nowrap">
                    <span
                      class="px-2 py-1 text-xs rounded text-white {getStatusClass(
                        task.status
                      )}"
                    >
                      {getStatusLabel(task.status)}
                    </span>
                  </td>
                  <td class="px-3 py-2 whitespace-nowrap">
                    <span
                      class="px-2 py-1 text-xs rounded font-medium {getTypeClass(
                        task.type
                      )}"
                    >
                      {getTypeLabel(task.type)}
                    </span>
                  </td>
                  <td
                    class="px-3 py-2 whitespace-nowrap text-xs text-gray-900 dark:text-gray-100"
                  >
                    {task.novel_id || "-"}
                  </td>
                  <td
                    class="px-4 py-3 text-xs text-gray-900 dark:text-gray-100"
                  >
                    <div class="max-w-xs">
                      <div class="font-medium truncate">
                        {task.novel_title || "-"}
                      </div>
                      {#if task.message}
                        <div
                          class="text-xs text-gray-500 dark:text-gray-400 mt-1 truncate"
                        >
                          {task.message}
                        </div>
                      {/if}
                    </div>
                  </td>
                  <td
                    class="px-4 py-3 text-xs text-gray-900 dark:text-gray-100"
                  >
                    <div class="max-w-xs truncate">
                      {task.novel_author || "-"}
                    </div>
                  </td>
                  <td class="px-3 py-2 whitespace-nowrap text-xs">
                    {#if task.progress > 0}
                      <div class="w-24">
                        <div
                          class="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2"
                        >
                          <div
                            class="bg-blue-500 h-2 rounded-full transition-all duration-300"
                            style="width: {task.progress}%"
                          ></div>
                        </div>
                        <div class="text-gray-500 dark:text-gray-400 mt-1">
                          {task.progress.toFixed(1)}%
                        </div>
                      </div>
                    {:else}
                      <span class="text-gray-400 dark:text-gray-500">-</span>
                    {/if}
                  </td>
                  <td
                    class="px-4 py-3 text-xs text-gray-500 dark:text-gray-400"
                  >
                    <div class="whitespace-nowrap">
                      {#if task.created_at}
                        {@const date = new Date(task.created_at)}
                        <div>
                          {date.toLocaleDateString("ja-JP", {
                            year: "numeric",
                            month: "2-digit",
                            day: "2-digit",
                          })}
                        </div>
                        <div>
                          {date.toLocaleTimeString("ja-JP", {
                            hour: "2-digit",
                            minute: "2-digit",
                            second: "2-digit",
                          })}
                        </div>
                      {:else}
                        -
                      {/if}
                    </div>
                  </td>
                  <td
                    class="px-3 py-2 whitespace-nowrap text-xs text-gray-900 dark:text-gray-100"
                  >
                    {task.elapsed_time.toFixed(1)}秒
                  </td>
                  <td class="px-3 py-2 whitespace-nowrap text-sm">
                    <div class="flex gap-1">
                      {#if task.status === "queued" || task.status === "running"}
                        <button
                          onclick={() => handleCancelTask(task.id)}
                          class="p-1.5 text-gray-600 hover:text-red-600 dark:text-gray-400 dark:hover:text-red-400 transition-colors cursor-pointer"
                          title="キャンセル"
                        >
                          <i class="fas fa-times"></i>
                        </button>
                      {/if}
                    </div>
                  </td>
                </tr>
              {/each}
            {/if}
          </tbody>
        </table>
      </div>

      <!-- ページネーション -->
      {#if totalPages > 1}
        <div
          class="px-3 py-2 bg-gray-50 dark:bg-gray-700 border-t border-gray-200 dark:border-gray-600"
        >
          <div class="flex items-center justify-between">
            <div class="text-sm text-gray-700 dark:text-gray-300">
              {#if totalFiltered > 0}
                {totalFiltered}件中 {(currentPage - 1) * itemsPerPage + 1} - {Math.min(
                  currentPage * itemsPerPage,
                  totalFiltered
                )}件を表示
                {#if totalFiltered < allTasks.length}
                  <span class="text-xs text-gray-500 dark:text-gray-400">
                    （{allTasks.length}件から絞り込み）
                  </span>
                {/if}
              {:else}
                0件
              {/if}
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
                    class="px-3 py-1 text-sm rounded border {currentPage ===
                    page
                      ? 'bg-blue-500 text-white border-blue-500'
                      : 'border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700'}"
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
