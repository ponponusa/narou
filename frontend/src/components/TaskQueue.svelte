<!--
  タスクキューコンポーネント
  
  ダウンロード・変換タスクの進捗状況をリアルタイム表示
-->
<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import { progressStore, type ProgressInfo } from "../lib/progressStore";
  import { getPushServer, type EchoMessage } from "../lib/pushserver";
  import {
    cancelTask as apiCancelTask,
    cancelTaskById,
    pauseTask,
    resumeTask,
    getTaskSummary,
    type Task,
    type TaskSummary,
  } from "../lib/api";

  /**
   * タスク情報（ローカル管理用）
   */
  interface TaskInfo extends ProgressInfo {
    novelId: number | "NEW";
    title: string;
    author: string;
    startTime: Date;
    endTime?: Date;
    taskId?: string; // バックエンドのタスクID
  }

  // ローカルストレージキー
  const STORAGE_KEY = "narou-task-queue";
  const COLLAPSED_KEY = "narou-task-queue-collapsed";

  // タスクリスト（ローカル管理）
  let tasks = $state<TaskInfo[]>([]);

  // バックエンドからのタスク情報
  let backendTaskSummary = $state<TaskSummary | null>(null);

  // ソート設定
  let sortBy = $state<"status" | "startTime" | "">("status");
  let sortOrder = $state<"asc" | "desc">("asc");

  // 折りたたみ状態（デフォルトは折りたたみ）
  let isCollapsed = $state(true);

  // 定期更新用のタイマー
  let updateTimer: ReturnType<typeof setInterval> | null = null;

  /**
   * タスクをlocalStorageに保存
   */
  function saveTasks() {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(tasks));
    } catch (err) {
      console.error("タスクの保存に失敗:", err);
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
      console.error("タスクの読み込みに失敗:", err);
    }

    // 初期ソート適用
    applySorting();
  }

  /**
   * 折りたたみ状態を保存
   */
  function saveCollapsedState() {
    try {
      localStorage.setItem(COLLAPSED_KEY, JSON.stringify(isCollapsed));
    } catch (err) {
      console.error("折りたたみ状態の保存に失敗:", err);
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
  export function addTask(
    novelId: number | "NEW",
    title: string,
    author: string,
    status: ProgressInfo["status"] = "waiting"
  ) {
    console.log(
      `[TaskQueue] Adding task: ID=${novelId}, title="${title}", author="${author}", status=${status}`
    );

    const newTask: TaskInfo = {
      novelId,
      title,
      author,
      status,
      startTime: new Date(),
      updatedAt: Date.now(),
    };
    tasks = [...tasks, newTask];
    applySorting();
    saveTasks();

    console.log(`[TaskQueue] Task added. Total tasks: ${tasks.length}`);

    // キューが積まれたら自動展開
    if (isCollapsed) {
      isCollapsed = false;
      saveCollapsedState();
    }
  }

  /**
   * タスク状態を更新
   */
  export function updateTaskStatus(
    novelId: number | "NEW",
    status: ProgressInfo["status"],
    message?: string
  ) {
    let statusChanged = false;

    tasks = tasks.map((task) => {
      if (task.novelId === novelId) {
        // ステータスが変更されたかチェック
        if (task.status !== status) {
          statusChanged = true;
        }

        const updated = {
          ...task,
          status,
          message,
          updatedAt: Date.now(),
        };

        // 完了またはエラー時に終了時刻を記録
        if (status === "completed" || status === "error") {
          updated.endTime = new Date();
        }

        return updated;
      }
      return task;
    });

    // ステータスが変更された場合のみ保存とソートを行う
    // メッセージのみの更新（進捗表示など）では行わないことでちらつきを防止
    if (statusChanged) {
      saveTasks();
      applySorting();
    }
  }

  /**
   * バックエンドからタスク情報を取得
   */
  async function fetchBackendTasks() {
    try {
      backendTaskSummary = await getTaskSummary();
    } catch (err) {
      console.error("[TaskQueue] Failed to fetch backend tasks:", err);
    }
  }

  /**
   * タスクを削除（キャンセル）
   */
  async function cancelTask(novelId: number | "NEW") {
    if (novelId === "NEW") {
      // NEW の場合はローカルから削除のみ
      tasks = tasks.filter((task) => task.novelId !== novelId);
      saveTasks();
      return;
    }

    try {
      // バックエンドにキャンセルリクエスト送信
      await apiCancelTask(novelId);

      // ローカルのタスクリストから削除
      tasks = tasks.filter((task) => task.novelId !== novelId);
      saveTasks();

      // progressStoreからもクリア
      progressStore.clearProgress(novelId);
    } catch (err) {
      console.error("タスクのキャンセルに失敗:", err);
      // エラーが発生してもローカルからは削除
      tasks = tasks.filter((task) => task.novelId !== novelId);
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
      console.error("タスクのキャンセルに失敗:", err);
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
    tasks = tasks.filter(
      (task) => task.status !== "completed" && task.status !== "error"
    );
    saveTasks();
  }

  /**
   * バックエンドタスクをキャンセル
   */
  async function cancelBackendTask(taskId: string) {
    try {
      await cancelTaskById(taskId);
      // タスク情報を更新
      await fetchBackendTasks();
    } catch (err) {
      console.error("タスクのキャンセルに失敗:", err);
      alert("タスクのキャンセルに失敗しました");
    }
  }

  /**
   * バックエンドタスクを一時停止
   */
  async function pauseBackendTask(taskId: string) {
    try {
      await pauseTask(taskId);
      // タスク情報を更新
      await fetchBackendTasks();
    } catch (err) {
      console.error("タスクの一時停止に失敗:", err);
      alert("タスクの一時停止に失敗しました");
    }
  }

  /**
   * バックエンドタスクを再開
   */
  async function resumeBackendTask(taskId: string) {
    try {
      await resumeTask(taskId);
      // タスク情報を更新
      await fetchBackendTasks();
    } catch (err) {
      console.error("タスクの再開に失敗:", err);
      alert("タスクの再開に失敗しました");
    }
  }

  /**
   * ソート処理
   */
  function handleSort(column: "status" | "startTime") {
    if (sortBy === column) {
      sortOrder = sortOrder === "asc" ? "desc" : "asc";
    } else {
      sortBy = column;
      sortOrder = "asc";
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
        case "status":
          // 実行中（DL > 変換中） > 待機中 > 完了 > エラー
          const statusOrder: Record<string, number> = {
            downloading: 1,
            converting: 2,
            waiting: 3,
            completed: 4,
            error: 5,
          };
          // 定義されていないステータスは後ろに回す
          aVal = statusOrder[a.status] || 99;
          bVal = statusOrder[b.status] || 99;
          break;
        case "startTime":
          aVal = a.startTime.getTime();
          bVal = b.startTime.getTime();
          break;
      }

      if (aVal < bVal) return sortOrder === "asc" ? -1 : 1;
      if (aVal > bVal) return sortOrder === "asc" ? 1 : -1;
      return 0;
    });
  }

  /**
   * 状態バッジのスタイルを取得
   */
  function getStatusBadgeClass(status: ProgressInfo["status"]): string {
    switch (status) {
      case "waiting":
        return "bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200 animate-pulse";
      case "downloading":
        return "bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200 animate-pulse";
      case "converting":
        return "bg-purple-100 dark:bg-purple-900 text-purple-800 dark:text-purple-200 animate-pulse";
      case "completed":
        return "bg-green-100 dark:bg-green-900 text-green-800 dark:text-green-200";
      case "error":
        return "bg-red-100 dark:bg-red-900 text-red-800 dark:text-red-200";
      default:
        return "bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200";
    }
  }

  /**
   * 状態ラベルを取得
   */
  function getStatusLabel(status: ProgressInfo["status"]): string {
    switch (status) {
      case "waiting":
        return "WAIT";
      case "downloading":
        return "DL";
      case "converting":
        return "変換中";
      case "completed":
        return "完了";
      case "error":
        return "ERROR";
      default:
        return status;
    }
  }

  /**
   * アクティブなタスク数を取得（待機中/DL中/変換中）
   */
  const activeTaskCount = $derived(
    tasks.filter(
      (t) =>
        t.status === "waiting" ||
        t.status === "downloading" ||
        t.status === "converting"
    ).length
  );

  onMount(() => {
    loadTasks();

    // バックエンドタスク情報を取得
    fetchBackendTasks();

    // 定期的にバックエンドタスク情報を更新（5秒ごと）
    updateTimer = setInterval(() => {
      fetchBackendTasks();
    }, 5000);

    // progressStoreからの更新を監視
    const unsubscribeProgress = progressStore.subscribe((progressMap) => {
      // progressMapの変更をtasksに反映
      Object.entries(progressMap).forEach(([novelIdStr, progress]) => {
        const novelId = parseInt(novelIdStr);
        const existingTask = tasks.find((t) => t.novelId === novelId);
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
    pushServer.on("echo", echoHandler);

    // PushServerからのnotification.queueイベントを監視
    const queueHandler = (
      data: number[] | { webWorkerSize?: number; workerSize?: number }
    ) => {
      handleQueueNotification(data);
    };
    pushServer.on("notification.queue", queueHandler);

    // PushServerからのnotification.task.updatedイベントを監視
    const taskUpdatedHandler = (data: TaskSummary) => {
      handleTaskUpdated(data);
    };
    pushServer.on("notification.task.updated", taskUpdatedHandler);

    return () => {
      if (updateTimer) {
        clearInterval(updateTimer);
      }
      unsubscribeProgress();
      pushServer.off("echo", echoHandler);
      pushServer.off("notification.queue", queueHandler);
      pushServer.off("notification.task.updated", taskUpdatedHandler);
    };
  });

  /**
   * PushServerのnotification.task.updatedイベントを処理
   */
  function handleTaskUpdated(data: TaskSummary) {
    console.log("[TaskQueue] Task updated notification received:", data);
    backendTaskSummary = data;
  }

  /**
   * PushServerのnotification.queueイベントを処理
   * バックエンドから [webWorkerSize, workerSize] の配列が送られてくる
   */
  function handleQueueNotification(
    data: number[] | { webWorkerSize?: number; workerSize?: number }
  ) {
    console.log("[TaskQueue] Queue notification received:", data);

    let webWorkerSize = 0;
    let workerSize = 0;

    if (Array.isArray(data)) {
      // 配列形式: [webWorkerSize, workerSize]
      [webWorkerSize, workerSize] = data;
    } else {
      // オブジェクト形式
      webWorkerSize = data.webWorkerSize || 0;
      workerSize = data.workerSize || 0;
    }

    // タスクキューのサイズが0になったら完了タスクをクリアする等の処理を追加可能
    // 現時点ではログ出力のみ
    console.log(
      `[TaskQueue] WebWorker queue: ${webWorkerSize}, Worker queue: ${workerSize}`
    );
  }

  /**
   * PushServerのechoメッセージから進捗を検出
   */
  function handleEchoMessage(data: EchoMessage) {
    const message = data.body;

    // 小説IDを抽出
    const idMatch = message.match(/ID[:：]\s*(\d+)/i);

    // IDが含まれる場合の処理
    if (idMatch) {
      const novelId = parseInt(idMatch[1]);
      const task = tasks.find((t) => t.novelId === novelId);
      if (!task) return;

      // 処理状態を判定
      // 1. DL開始: "ID:123　タイトル のDL開始"
      if (/のDL開始/.test(message)) {
        progressStore.setProgress(novelId, "downloading", "ダウンロード中...");
      }
      // 2. 変換開始: "ID:123　タイトル の変換を開始"
      else if (/の変換を開始/.test(message)) {
        progressStore.setProgress(novelId, "converting", "変換中...");
      }
      // 3. 章のダウンロード進捗（"第n部分"）
      else if (/第[\d０-９]+部分/.test(message)) {
        // 既にDL中でない場合のみ状態変更
        if (task.status === "idle" || task.status === "waiting") {
          progressStore.setProgress(
            novelId,
            "downloading",
            "ダウンロード中..."
          );
        }
      }
      // 4. エラーメッセージ
      else if (/エラー|error|失敗|failed/i.test(message)) {
        progressStore.setProgress(novelId, "error", message);
      }
      return;
    }

    // IDが含まれない場合の処理（変換完了メッセージなど）
    // 最も新しいDL中/変換中のタスクを対象にする
    const activeTask = tasks.find(
      (t) => t.status === "downloading" || t.status === "converting"
    );

    if (!activeTask) return;

    // 変換開始メッセージ（IDなし）: "タイトル の変換を開始"
    if (/の変換を開始/.test(message) && activeTask.status === "downloading") {
      progressStore.setProgress(
        activeTask.novelId as number,
        "converting",
        "変換中..."
      );
    }
    // 変換完了メッセージ: "縦書用の変換が終了しました" or "変換しました"
    else if (
      /変換が終了しました|変換しました/.test(message) &&
      activeTask.status === "converting"
    ) {
      progressStore.setProgress(
        activeTask.novelId as number,
        "completed",
        "完了"
      );
    }
    // エラーメッセージ
    else if (/エラー|error|失敗|failed/i.test(message)) {
      progressStore.setProgress(activeTask.novelId as number, "error", message);
    }
  }
</script>

<div class="bg-white dark:bg-gray-800 rounded-lg shadow-md mb-4 lg:mx-12">
  <!-- ヘッダー（常に表示） -->
  <div
    class="flex items-center justify-between p-4 cursor-pointer border-b border-gray-200 dark:border-gray-700"
    onclick={toggleCollapse}
    onkeydown={(e) => (e.key === "Enter" || e.key === " ") && toggleCollapse()}
    role="button"
    tabindex="0"
    aria-label="タスクキューの表示切替"
  >
    <div class="flex items-center gap-3">
      <h3 class="text-base font-semibold text-gray-700 dark:text-gray-300">
        <i class="fas fa-tasks mr-2"></i>
        タスクキュー
      </h3>
      {#if tasks.length > 0}
        <span
          class="px-2 py-1 text-xs rounded bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200"
        >
          {tasks.length}件
        </span>
      {/if}
      {#if activeTaskCount > 0}
        <span
          class="px-2 py-1 text-xs rounded bg-green-100 dark:bg-green-900 text-green-800 dark:text-green-200 animate-pulse"
        >
          処理中: {activeTaskCount}件
        </span>
      {/if}
    </div>
    <div class="flex items-center gap-2">
      <button
        onclick={(e) => {
          e.stopPropagation();
          cancelAllTasks();
        }}
        class="px-3 py-1 text-sm bg-red-600 text-white rounded hover:bg-red-700 transition-colors disabled:bg-gray-400 disabled:cursor-not-allowed cursor-pointer mr-2"
        disabled={tasks.length === 0}
      >
        リストをクリア
      </button>
      <button
        class="text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 transition-colors"
        aria-label={isCollapsed
          ? "タスクキューを展開"
          : "タスクキューを折りたたむ"}
        tabindex="-1"
      >
        <i class="fas fa-chevron-{isCollapsed ? 'down' : 'up'}"></i>
      </button>
    </div>
  </div>

  <!-- テーブル（折りたたみ可能） -->
  {#if !isCollapsed}
    <div class="p-4 space-y-6">
      <!-- バックエンドタスク情報 -->
      {#if backendTaskSummary}
        <div class="space-y-4">
          <h4
            class="text-sm font-semibold text-gray-700 dark:text-gray-300 border-b pb-2"
          >
            <i class="fas fa-server mr-2"></i>
            サーバータスク状態
          </h4>

          <!-- 実行中タスク -->
          {#if backendTaskSummary.current}
            <div class="bg-blue-50 dark:bg-blue-900/20 rounded-lg p-3">
              <div class="flex items-start gap-3">
                <span
                  class="px-2 py-1 text-xs rounded bg-blue-500 text-white animate-pulse"
                >
                  実行中
                </span>
                <div class="flex-1 min-w-0">
                  <div
                    class="font-medium text-gray-900 dark:text-gray-100 truncate"
                  >
                    {backendTaskSummary.current.novel_title ||
                      `タスク ${backendTaskSummary.current.type}`}
                  </div>
                  {#if backendTaskSummary.current.novel_author}
                    <div class="text-sm text-gray-600 dark:text-gray-400">
                      {backendTaskSummary.current.novel_author}
                    </div>
                  {/if}
                  <div class="text-xs text-gray-500 dark:text-gray-500 mt-1">
                    {backendTaskSummary.current.type} | 経過時間: {backendTaskSummary.current.elapsed_time.toFixed(
                      1
                    )}秒
                  </div>
                  {#if backendTaskSummary.current.progress > 0}
                    <div class="mt-2">
                      <div
                        class="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2"
                      >
                        <div
                          class="bg-blue-500 h-2 rounded-full transition-all duration-300"
                          style="width: {backendTaskSummary.current.progress}%"
                        ></div>
                      </div>
                      <div
                        class="text-xs text-gray-600 dark:text-gray-400 mt-1"
                      >
                        進捗: {backendTaskSummary.current.progress.toFixed(1)}%
                        {#if backendTaskSummary.current.total_steps}
                          ({backendTaskSummary.current
                            .current_step}/{backendTaskSummary.current
                            .total_steps})
                        {/if}
                      </div>
                    </div>
                  {/if}
                  {#if backendTaskSummary.current.message}
                    <div class="text-xs text-gray-600 dark:text-gray-400 mt-1">
                      {backendTaskSummary.current.message}
                    </div>
                  {/if}
                </div>
                <div class="flex gap-1">
                  {#if backendTaskSummary.current.status === "running"}
                    <button
                      onclick={() =>
                        pauseBackendTask(backendTaskSummary!.current!.id)}
                      class="px-2 py-1 text-xs rounded bg-yellow-500 hover:bg-yellow-600 text-white"
                      title="一時停止"
                    >
                      <i class="fas fa-pause"></i>
                    </button>
                  {/if}
                  <button
                    onclick={() =>
                      cancelBackendTask(backendTaskSummary!.current!.id)}
                    class="px-2 py-1 text-xs rounded bg-red-500 hover:bg-red-600 text-white"
                    title="キャンセル"
                  >
                    <i class="fas fa-times"></i>
                  </button>
                </div>
              </div>
            </div>
          {/if}

          <!-- キュー待ちタスク -->
          {#if backendTaskSummary.queued.length > 0}
            <div>
              <div
                class="text-xs font-medium text-gray-600 dark:text-gray-400 mb-2"
              >
                キュー待ち ({backendTaskSummary.queued.length}件)
              </div>
              <div class="space-y-2">
                {#each backendTaskSummary.queued.slice(0, 5) as task (task.id)}
                  <div
                    class="bg-gray-50 dark:bg-gray-700/50 rounded p-2 text-sm"
                  >
                    <div class="flex items-center gap-2">
                      {#if task.status === "paused"}
                        <span
                          class="px-2 py-0.5 text-xs rounded bg-yellow-500 text-white"
                        >
                          一時停止
                        </span>
                      {:else}
                        <span
                          class="px-2 py-0.5 text-xs rounded bg-gray-400 text-white"
                        >
                          待機中
                        </span>
                      {/if}
                      <span
                        class="font-medium text-gray-900 dark:text-gray-100 truncate flex-1"
                      >
                        {task.novel_title || `タスク ${task.type}`}
                      </span>
                      <span class="text-xs text-gray-500 dark:text-gray-500">
                        {task.type}
                      </span>
                      <div class="flex gap-1">
                        {#if task.status === "paused"}
                          <button
                            onclick={() => resumeBackendTask(task.id)}
                            class="px-2 py-0.5 text-xs rounded bg-green-500 hover:bg-green-600 text-white"
                            title="再開"
                          >
                            <i class="fas fa-play"></i>
                          </button>
                        {:else}
                          <button
                            onclick={() => pauseBackendTask(task.id)}
                            class="px-2 py-0.5 text-xs rounded bg-yellow-500 hover:bg-yellow-600 text-white"
                            title="一時停止"
                          >
                            <i class="fas fa-pause"></i>
                          </button>
                        {/if}
                        <button
                          onclick={() => cancelBackendTask(task.id)}
                          class="px-2 py-0.5 text-xs rounded bg-red-500 hover:bg-red-600 text-white"
                          title="キャンセル"
                        >
                          <i class="fas fa-times"></i>
                        </button>
                      </div>
                    </div>
                  </div>
                {/each}
                {#if backendTaskSummary.queued.length > 5}
                  <div
                    class="text-xs text-gray-500 dark:text-gray-500 text-center"
                  >
                    他 {backendTaskSummary.queued.length - 5} 件
                  </div>
                {/if}
              </div>
            </div>
          {/if}
        </div>
        <div class="border-t border-gray-200 dark:border-gray-700 pt-4"></div>
      {/if}

      <!-- ローカルタスク履歴 -->
      <div>
        <h4
          class="text-sm font-semibold text-gray-700 dark:text-gray-300 border-b pb-2 mb-4"
        >
          <i class="fas fa-history mr-2"></i>
          タスク履歴（ローカル）
        </h4>

        {#if tasks.length === 0}
          <div class="text-center py-8 text-gray-600 dark:text-gray-400">
            <p>タスクはありません</p>
          </div>
        {:else}
          <div class="overflow-x-auto">
            <table
              class="min-w-full divide-y divide-gray-200 dark:divide-gray-700"
            >
              <thead class="bg-gray-50 dark:bg-gray-700">
                <tr>
                  <th
                    class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap"
                  >
                    <button
                      onclick={() => handleSort("status")}
                      class="flex items-center gap-1 hover:text-gray-700 dark:hover:text-gray-100"
                    >
                      状態
                      {#if sortBy === "status"}
                        <span>{sortOrder === "asc" ? "▲" : "▼"}</span>
                      {/if}
                    </button>
                  </th>
                  <th
                    class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap"
                  >
                    小説ID
                  </th>
                  <th
                    class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap"
                  >
                    タイトル
                  </th>
                  <th
                    class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap"
                  >
                    著者名
                  </th>
                  <th
                    class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap"
                  >
                    <button
                      onclick={() => handleSort("startTime")}
                      class="flex items-center gap-1 hover:text-gray-700 dark:hover:text-gray-100"
                    >
                      開始時刻
                      {#if sortBy === "startTime"}
                        <span>{sortOrder === "asc" ? "▲" : "▼"}</span>
                      {/if}
                    </button>
                  </th>
                  <th
                    class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap"
                  >
                    終了時刻
                  </th>
                </tr>
              </thead>
              <tbody
                class="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700"
              >
                {#each tasks as task (task.novelId + "_" + task.startTime.getTime())}
                  <tr
                    class="hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors"
                  >
                    <td class="px-4 py-3 text-sm">
                      <span
                        class="px-2 py-1 text-xs rounded whitespace-nowrap {getStatusBadgeClass(
                          task.status
                        )}"
                        title={task.message}
                      >
                        {getStatusLabel(task.status)}
                      </span>
                    </td>
                    <td
                      class="px-4 py-3 text-sm text-gray-600 dark:text-gray-400"
                    >
                      {task.novelId}
                    </td>
                    <td
                      class="px-4 py-3 text-sm font-medium text-gray-900 dark:text-gray-100"
                    >
                      {task.title}
                    </td>
                    <td
                      class="px-4 py-3 text-sm text-gray-600 dark:text-gray-400"
                    >
                      {task.author}
                    </td>
                    <td
                      class="px-4 py-3 text-sm text-gray-600 dark:text-gray-400"
                    >
                      {task.startTime.toLocaleTimeString("ja-JP")}
                    </td>
                    <td
                      class="px-4 py-3 text-sm text-gray-600 dark:text-gray-400"
                    >
                      {task.endTime
                        ? task.endTime.toLocaleTimeString("ja-JP")
                        : "-"}
                    </td>
                  </tr>
                {/each}
              </tbody>
            </table>
          </div>
        {/if}
      </div>
    </div>
  {/if}
</div>
