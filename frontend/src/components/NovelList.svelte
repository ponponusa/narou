<!--
  小説リストコンポーネント
  
  小説データをテーブル形式で表示し、各種操作を提供
-->
<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import {
    getNovels,
    downloadNovels,
    downloadNovel,
    downloadEpub,
    convertNovels,
    convertNovel,
    freezeNovel,
    unfreezeNovel,
    toggleFreeze,
    removeNovels,
    deleteNovel,
    getTagList,
  } from "../lib/api";
  import type { Novel, TagInfo } from "../types/api";
  import { getPushServer } from "../lib/pushserver";
  import { progressStore } from "../lib/progressStore";
  import { isServerStopped } from "../lib/stores/serverStatus";
  import { measurePerformance, PerformanceMarker } from "../lib/performance";
  import AddNovelModal from "./AddNovelModal.svelte";
  import TagModal from "./TagModal.svelte";
  import ConversionSettingsModal from "./ConversionSettingsModal.svelte";
  import NovelDetailModal from "./NovelDetailModal.svelte";
  import NovelUpdateModal from "./NovelUpdateModal.svelte";
  import ConsolePanel from "./ConsolePanel.svelte";
  import Toast from "./Toast.svelte";
  import LoadingScreen from "./LoadingScreen.svelte";
  import MultiSelectDropdown from "./MultiSelectDropdown.svelte";

  let novels = $state<Novel[]>([]);
  let allNovels = $state<Novel[]>([]); // 全データを保持
  let toast: Toast;
  let loading = $state(true);
  let error = $state<string | null>(null);
  let selectedIds = $state<Set<number>>(new Set());
  let totalCount = $state(0);
  let allTags = $state<TagInfo[]>([]);
  let pushServer = getPushServer();
  let addNovelModal: AddNovelModal;
  let tagModal: TagModal;
  let conversionSettingsModal: ConversionSettingsModal;
  let novelDetailModal: NovelDetailModal;
  let novelUpdateModal: NovelUpdateModal;
  let consolePanel = $state<ConsolePanel>();
  let retryCount = $state(0);
  let maxRetries = 10; // 最大10回リトライ（約20秒）
  let isInitialLoad = $state(true); // 初回ロードフラグ
  let initialLoadDelay = 2000; // 初回ロード時の待機時間（2秒）

  // フィルター・ソート設定
  let currentPage = $state(0);
  let pageSize = $state(50);
  
  // 実際に適用されるフィルタ（検索ボタン押下時に反映）
  let filterText = $state("");
  let selectedTag = $state<string[]>([]);
  let selectedSite = $state<string[]>([]);
  let selectedStatus = $state<string[]>([]);
  
  // フォーム入力中の一時的な値
  let draftFilterText = $state("");
  let draftSelectedTag = $state<string[]>([]);
  let draftSelectedSite = $state<string[]>([]);
  let draftSelectedStatus = $state<string[]>([]);
  
  // フィルタ処理中フラグ
  let isFiltering = $state(false);
  let sortBy = $state<
    | "id"
    | "title"
    | "author"
    | "sitename"
    | "updated_at"
    | "status"
    | "tags"
    | "episode_count"
    | "total_chars"
    | "avg_chars_per_episode"
    | "newest_article_date"
    | "last_update"
    | ""
  >("updated_at");
  let sortOrder = $state<"asc" | "desc">("desc");
  let availableSites = $state<string[]>([]);

  // 検索フォームの折りたたみ状態（デフォルトは折りたたみ）
  let isSearchFormCollapsed = $state(true);

  // アクション処理中の状態管理
  let processingNovelIds = $state<Set<number>>(new Set());

  // 確認ダイアログの状態
  let showConfirmDialog = $state(false);
  let confirmDialogConfig = $state<{
    title: string;
    message: string;
    onConfirm: () => void;
  } | null>(null);

  // 列表示設定の型定義
  interface ColumnVisibility {
    id: boolean;
    updated_at: boolean; // 更新日
    newest_article_date: boolean; // 最新話掲載日
    last_update: boolean; // 更新チェック日
    title: boolean;
    author: boolean;
    sitename: boolean;
    status: boolean;
    tags: boolean;
    episode_count: boolean; // 話数
    total_chars: boolean; // 文字数
    avg_chars_per_episode: boolean; // 平均文字数
  }

  // 列表示設定（デフォルト：レスポンシブ対応）
  let columnVisibility = $state<ColumnVisibility>({
    id: true,
    updated_at: true,
    newest_article_date: true,
    last_update: false,
    title: true,
    author: true,
    sitename: true,
    status: true,
    tags: true,
    episode_count: false,
    total_chars: false,
    avg_chars_per_episode: false,
  });

  // 列表示設定モーダルの開閉状態
  let showColumnSettings = $state(false);

  // スクロール位置管理
  let showScrollTopButton = $state(false);

  // 設定の保存キー
  const SETTINGS_KEY = "narou-novel-list-settings";
  const COLUMN_VISIBILITY_KEY = "narou-column-visibility";

  // 設定をlocalStorageに保存
  function saveSettings() {
    try {
      const settings = {
        pageSize,
        selectedTag: selectedTag,
        selectedSite: selectedSite,
        selectedStatus: selectedStatus,
        sortBy,
        sortOrder,
      };
      localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
    } catch (err) {
      console.error("設定の保存に失敗しました:", err);
    }
  }

  // 列表示設定をlocalStorageに保存
  function saveColumnVisibility() {
    try {
      localStorage.setItem(
        COLUMN_VISIBILITY_KEY,
        JSON.stringify(columnVisibility)
      );
    } catch (err) {
      console.error("列表示設定の保存に失敗しました:", err);
    }
  }

  // 設定をlocalStorageから復元
  function loadSettings() {
    try {
      const saved = localStorage.getItem(SETTINGS_KEY);
      if (saved) {
        const settings = JSON.parse(saved);
        pageSize = settings.pageSize ?? 50;
        // 下位互換性：文字列の場合は配列に変換
        selectedTag = Array.isArray(settings.selectedTag) ? settings.selectedTag : (settings.selectedTag ? [settings.selectedTag] : []);
        selectedSite = Array.isArray(settings.selectedSite) ? settings.selectedSite : (settings.selectedSite ? [settings.selectedSite] : []);
        selectedStatus = Array.isArray(settings.selectedStatus) ? settings.selectedStatus : (settings.selectedStatus ? [settings.selectedStatus] : []);
        sortBy = settings.sortBy ?? "updated_at";
        sortOrder = settings.sortOrder ?? "desc";
        
        // draft変数も初期化
        draftSelectedTag = [...selectedTag];
        draftSelectedSite = [...selectedSite];
        draftSelectedStatus = [...selectedStatus];
      }
    } catch (err) {
      console.error("設定の読み込みに失敗しました:", err);
    }
  }

  // 列表示設定をlocalStorageから復元
  function loadColumnVisibility() {
    try {
      const saved = localStorage.getItem(COLUMN_VISIBILITY_KEY);
      if (saved) {
        const savedVisibility = JSON.parse(saved);
        columnVisibility = { ...columnVisibility, ...savedVisibility };
      } else {
        // 初回起動時：デバイスサイズに応じたデフォルト設定を適用
        applyResponsiveDefaults();
      }
    } catch (err) {
      console.error("列表示設定の読み込みに失敗しました:", err);
      applyResponsiveDefaults();
    }
  }

  // デバイスサイズに応じたデフォルト設定を適用
  function applyResponsiveDefaults() {
    const isMobile = window.innerWidth < 768;
    if (isMobile) {
      // スマホ向け：ID、タイトル、著者、状態のみ表示
      columnVisibility = {
        id: true,
        updated_at: false,
        newest_article_date: false,
        last_update: false,
        title: true,
        author: true,
        sitename: false,
        status: true,
        tags: false,
        episode_count: false,
        total_chars: false,
        avg_chars_per_episode: false,
      };
    } else {
      // PC/タブレット向け：ID、更新日、最新話掲載日、タイトル、著者、掲載サイト、タグ、状態を表示
      columnVisibility = {
        id: true,
        updated_at: true,
        newest_article_date: true,
        last_update: false,
        title: true,
        author: true,
        sitename: true,
        status: true,
        tags: true,
        episode_count: false,
        total_chars: false,
        avg_chars_per_episode: false,
      };
    }
    saveColumnVisibility();
  }

  // 列表示設定をリセット
  function resetColumnVisibility() {
    applyResponsiveDefaults();
  }

  // すべての列を表示
  function showAllColumns() {
    columnVisibility = {
      id: true,
      updated_at: true,
      newest_article_date: true,
      last_update: true,
      title: true,
      author: true,
      sitename: true,
      status: true,
      tags: true,
      episode_count: true,
      total_chars: true,
      avg_chars_per_episode: true,
    };
    saveColumnVisibility();
  }

  // すべての列を非表示（必須カラムのみ表示）
  function hideAllColumns() {
    columnVisibility = {
      id: true, // 必須
      updated_at: false,
      newest_article_date: false,
      last_update: false,
      title: true, // 必須
      author: true, // 必須
      sitename: true, // 必須
      status: false,
      tags: false,
      episode_count: false,
      total_chars: false,
      avg_chars_per_episode: false,
    };
    saveColumnVisibility();
  }

  // 列の表示/非表示を切り替え（モーダルから）
  function handleColumnToggle(column: keyof ColumnVisibility, value: boolean) {
    // タイトルは常に表示（非表示にできない）
    if (column === "title") return;

    // オブジェクト全体を再代入してリアクティビティを確保
    columnVisibility = {
      ...columnVisibility,
      [column]: value,
    };
    saveColumnVisibility();
  }

  // 列の表示/非表示を切り替え（レガシー用）
  function toggleColumn(column: keyof ColumnVisibility) {
    // タイトルは常に表示（非表示にできない）
    if (column === "title") return;

    columnVisibility = {
      ...columnVisibility,
      [column]: !columnVisibility[column],
    };
    saveColumnVisibility();
  }

  // 表示中の列数を取得
  const visibleColumnCount = $derived(
    Object.values(columnVisibility).filter((v) => v).length
  );

  // === Svelte 5 Runes: リアクティブな派生データ ===
  // タグインデックス（タグ名 → Novel IDのSet）
  // 通常の変数でメモ化（$state不要）
  let tagIndexCache: {
    novels: Novel[];
    index: Map<string, Set<number>>;
  } | null = null;
  
  const tagIndex = $derived.by(() => {
    // キャッシュが有効（allNovelsの参照が同じ）ならそのまま返す
    if (tagIndexCache && tagIndexCache.novels === allNovels) {
      console.log('[Tag Index] Using cache');
      return tagIndexCache.index;
    }

    // 新規構築
    const index = measurePerformance(
      "Build Tag Index",
      () => {
        const newIndex = new Map<string, Set<number>>();

        // 最適化: for...of の代わりに通常のforループを使用
        const novelsLength = allNovels.length;
        for (let i = 0; i < novelsLength; i++) {
          const novel = allNovels[i];
          const tags = novel.tags;
          if (!tags) continue;
          
          const tagsLength = tags.length;
          for (let j = 0; j < tagsLength; j++) {
            const tag = tags[j];
            let tagSet = newIndex.get(tag);
            if (!tagSet) {
              tagSet = new Set<number>();
              newIndex.set(tag, tagSet);
            }
            tagSet.add(novel.id);
          }
        }

        console.log(
          `[Tag Index] Built index: ${newIndex.size} unique tags, ${allNovels.length} novels`
        );
        
        return newIndex;
      },
      1 // 1ms以上でログ出力
    );
    
    // キャッシュを更新（通常の代入なのでOK）
    tagIndexCache = { novels: allNovels, index };
    
    return index;
  });

  // ステップ1: フィルタリング
  const filteredNovels = $derived.by(() => {
    return measurePerformance(
      "Filter Novels",
      () => {
        let result = allNovels;
        const marker = new PerformanceMarker();
        marker.start();

        // 1. タグフィルタ（最も絞り込み効果が高い）を最初に適用
        if (selectedTag.length > 0) {
          // 複数タグのOR検索（いずれかのタグを持つ小説）
          const matchingNovelIds = new Set<number>();
          for (const tag of selectedTag) {
            if (tagIndex.has(tag)) {
              const tagNovelIds = tagIndex.get(tag)!;
              tagNovelIds.forEach(id => matchingNovelIds.add(id));
            }
          }
          result = result.filter((n) => matchingNovelIds.has(n.id));
          marker.mark("tag");
        }

        // 2. サイトフィルタ（選択肢が少ない）
        if (selectedSite.length > 0) {
          result = result.filter((n) => selectedSite.includes(n.sitename));
          marker.mark("site");
        }

        // 3. 状態フィルタ
        if (selectedStatus.length > 0) {
          result = result.filter((n) => selectedStatus.includes(n.status));
          marker.mark("status");
        }

        // 4. テキスト検索（最もコストが高い）を最後に
        if (filterText) {
          const query = filterText.toLowerCase();
          result = result.filter(
            (n) =>
              n.title?.toLowerCase().includes(query) ||
              n.author?.toLowerCase().includes(query)
          );
          marker.mark("text");
        }

        marker.end(`Filter: ${allNovels.length} → ${result.length}`, 5);
        return result;
      },
      5
    );
  });

  // ステップ2: ソート
  const sortedNovels = $derived.by(() => {
    // フィルタ結果が0件の場合は即座に空配列を返す
    if (filteredNovels.length === 0) return [];
    
    return measurePerformance(
      "Sort Novels",
      () => {
        const sorted = [...filteredNovels];

        if (!sortBy) return sorted;

        sorted.sort((a, b) => {
      let aVal: string | number = "";
      let bVal: string | number = "";

      switch (sortBy) {
        case "id":
          aVal = a.id || 0;
          bVal = b.id || 0;
          break;
        case "title":
          aVal = a.title || "";
          bVal = b.title || "";
          break;
        case "author":
          aVal = a.author || "";
          bVal = b.author || "";
          break;
        case "sitename":
          aVal = a.sitename || "";
          bVal = b.sitename || "";
          break;
        case "updated_at":
          aVal = a.last_update || 0;
          bVal = b.last_update || 0;
          break;
        case "status":
          aVal = a.status || "";
          bVal = b.status || "";
          break;
        case "tags":
          // タグでソート（最初のタグで比較）
          aVal = a.tags && a.tags.length > 0 ? a.tags[0] : "";
          bVal = b.tags && b.tags.length > 0 ? b.tags[0] : "";
          break;
        case "episode_count":
          aVal = a.general_all_no || 0;
          bVal = b.general_all_no || 0;
          break;
        case "total_chars":
          aVal = a.length || 0;
          bVal = b.length || 0;
          break;
        case "avg_chars_per_episode":
          aVal =
            a.length && a.general_all_no ? a.length / a.general_all_no : 0;
          bVal =
            b.length && b.general_all_no ? b.length / b.general_all_no : 0;
          break;
        case "newest_article_date":
          aVal = a.general_lastup || 0;
          bVal = b.general_lastup || 0;
          break;
        case "last_update":
          aVal = a.last_update || 0;
          bVal = b.last_update || 0;
          break;
      }

      if (aVal < bVal) return sortOrder === "asc" ? -1 : 1;
      if (aVal > bVal) return sortOrder === "asc" ? 1 : -1;
      return 0;
    });

    return sorted;
      },
      3
    );
  });

  // ステップ3: ページング情報
  const totalPages = $derived(Math.ceil(sortedNovels.length / pageSize));
  const totalFiltered = $derived(sortedNovels.length);

  // ステップ4: 表示データ（スライス）
  const displayNovels = $derived.by(() => {
    const start = currentPage * pageSize;
    const end = start + pageSize;
    return sortedNovels.slice(start, end);
  });

  // novelsを表示用データに同期（既存のテンプレートとの互換性のため）
  $effect(() => {
    novels = displayNovels;
  });
  // === リアクティブな派生データここまで ===

  // スクロールイベントハンドラー
  function handleScroll() {
    // ページを300px以上スクロールしたらボタンを表示
    if (typeof window !== "undefined") {
      showScrollTopButton = window.scrollY > 300;
    }
  }

  // トップに戻る
  function scrollToTop() {
    if (typeof window !== "undefined") {
      window.scrollTo({
        top: 0,
        behavior: "smooth",
      });
    }
  }

  /**
   * 文字数を整形（1万字以上は「万字」表記）
   */
  function formatCharCount(count: number | null | undefined): string {
    if (!count) return "-";
    if (count >= 10000) {
      return `${(count / 10000).toFixed(1)}万字`;
    }
    return count.toLocaleString();
  }

  /**
   * 日付を整形（YYYY/MM/DD<br>HH:MM形式）
   */
  function formatDateTime(
    timestamp: number | string | null | undefined
  ): string {
    if (!timestamp) return "-";
    const ts =
      typeof timestamp === "string" ? parseInt(timestamp, 10) : timestamp;
    const date = new Date(ts * 1000);
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, "0");
    const day = String(date.getDate()).padStart(2, "0");
    const hours = String(date.getHours()).padStart(2, "0");
    const minutes = String(date.getMinutes()).padStart(2, "0");
    return `${year}/${month}/${day}<br>${hours}:${minutes}`;
  }

  onMount(async () => {
    // sessionStorageで初回ロードかどうかを判定
    const hasLoaded = sessionStorage.getItem("novelListLoaded");
    if (hasLoaded === "true") {
      // 既に一度ロード済み（ページリロード）の場合はウェイトをスキップ
      isInitialLoad = false;
    }

    // 設定を復元
    loadSettings();
    loadColumnVisibility();

    // モーダルにToast参照を渡す
    if (conversionSettingsModal && toast) {
      conversionSettingsModal.setToast(toast);
    }
    if (novelDetailModal && toast) {
      novelDetailModal.setToast(toast);
    }

    // loadNovelsを優先、loadTagsは並行して実行（待たない）
    await loadNovels();
    loadTags(); // awaitしない - バックグラウンドで実行

    // PushServerイベントリスナー設定
    pushServer.on("table.reload", handleTableReload);
    pushServer.on("tag.updateCanvas", handleTagUpdate);

    // スクロールイベントリスナー追加
    window.addEventListener("scroll", handleScroll);
  });

  onDestroy(() => {
    // イベントリスナー解除
    pushServer.off("table.reload", handleTableReload);
    pushServer.off("tag.updateCanvas", handleTagUpdate);

    // ブラウザ環境でのみwindowにアクセス
    if (typeof window !== "undefined") {
      window.removeEventListener("scroll", handleScroll);
    }
  });

  function openAddNovelModal() {
    addNovelModal.open();
  }

  function openNovelDetail(novel: Novel) {
    novelDetailModal.open(novel, {
      onUpdate: () => {
        loadNovels();
      },
      onDelete: () => {
        loadNovels();
      },
      onTagEdit: (novelId: number) => {
        const targetNovel = novels.find((n) => n.id === novelId);
        if (targetNovel) {
          tagModal.open([targetNovel.id], targetNovel.title, loadNovels);
        }
      },
      onConversionSettings: (novelId: number, title: string) => {
        conversionSettingsModal.open(novelId, title, loadNovels);
      },
    });
  }

  function handleTableReload() {
    console.log("[NovelList] Table reload triggered");
    loadNovels();
  }

  function handleTagUpdate() {
    console.log("[NovelList] Tag update triggered");
    loadTags();
  }

  async function loadTags() {
    try {
      allTags = await getTagList();
    } catch (err) {
      const message =
        err instanceof Error ? err.message : "タグリストの取得に失敗しました";
      toast?.show(message, "error");
      console.error("タグリストの取得エラー:", err);
    }
  }

  async function loadNovels() {
    console.log('[NovelList] loadNovels started');
    const startTime = performance.now();
    
    loading = true;
    error = null;

    // 初回ロード時はバックエンドの起動を待つため2秒待機
    if (isInitialLoad) {
      console.log(
        `初回ロード: バックエンド起動を待機中... (${initialLoadDelay / 1000}秒)`
      );
      await new Promise((resolve) => setTimeout(resolve, initialLoadDelay));
      isInitialLoad = false;
      // 初回ロード完了フラグをセット
      sessionStorage.setItem("novelListLoaded", "true");
    }

    try {
      console.log('[NovelList] Fetching novels from API...');
      const fetchStartTime = performance.now();
      
      // 全データを一度に取得（gzip圧縮済み）
      const response = await getNovels();
      
      console.log(`[NovelList] API fetch completed in ${(performance.now() - fetchStartTime).toFixed(2)}ms`);

      // 成功したらリトライカウントをリセット
      retryCount = 0;

      console.log('[NovelList] Processing novels data...');
      const processStartTime = performance.now();
      
      // 全データをallNovelsに格納
      // $derivedが自動的にフィルタ・ソート・ページングを再計算
      allNovels = response.novels;
      totalCount = response.total;

      // サイト一覧を抽出（フィルター用）
      const sites = new Set(
        allNovels.map((n) => n.sitename).filter(Boolean)
      );
      availableSites = Array.from(sites).sort();

      console.log(`[NovelList] Data processing completed in ${(performance.now() - processStartTime).toFixed(2)}ms`);
      console.log(`[NovelList] loadNovels total: ${(performance.now() - startTime).toFixed(2)}ms`);

      loading = false; // 成功時のみloadingをfalseに
    } catch (err) {
      console.error("小説リストの取得エラー:", err);

      // HTTPステータスコードをチェック
      const status = (err as any).status;
      const isServerError = status >= 500 && status !== 503; // 503は除外（サービス準備中）

      // 503エラーまたは接続エラーの判定
      // TypeError: Failed to fetch や NetworkError など
      const isConnectionError =
        status === 503 ||
        (!isServerError &&
          (err instanceof TypeError || // fetch失敗時
            (err instanceof Error &&
              (err.message.includes("Failed to fetch") ||
                err.message.includes("NetworkError") ||
                err.message.includes("fetch") ||
                err.message.includes("network")))));

      if (isConnectionError && retryCount < maxRetries) {
        retryCount++;
        console.log(
          `サーバー接続をリトライ中... (${retryCount}/${maxRetries})`
        );

        // エラートーストを表示（初回のみ）
        if (retryCount === 1) {
          toast?.show("小説リストの取得に時間がかかっています...", "info");
        }

        // 2秒後に再試行（loadingはtrueのまま維持）
        setTimeout(() => {
          loadNovels();
        }, 2000);
        return; // loadingはtrueのまま、エラー表示をスキップ
      }

      // 最大リトライ回数に達した場合、または接続エラー以外の場合はエラー表示
      const message =
        err instanceof Error ? err.message : "小説リストの取得に失敗しました";
      error = message;
      loading = false;
      retryCount = 0; // リトライカウンターをリセット

      // エラートーストを表示
      if (isServerError) {
        toast?.show("サーバーエラーが発生しました: " + message, "error");
      } else if (!isConnectionError) {
        toast?.show(message, "error");
      } else {
        toast?.show(
          "サーバーに接続できませんでした。しばらくしてから再度お試しください。",
          "error"
        );
      }
    }
  }

  function toggleSelection(id: number) {
    const newSet = new Set(selectedIds);
    if (newSet.has(id)) {
      newSet.delete(id);
    } else {
      newSet.add(id);
    }
    selectedIds = newSet;
  }

  function selectAll() {
    if (selectedIds.size === novels.length && novels.length > 0) {
      selectedIds = new Set();
    } else {
      selectedIds = new Set(novels.map((n) => n.id));
    }
  }

  async function handleDownload() {
    if (selectedIds.size === 0) {
      toast?.show("小説を選択してください", "warning");
      return;
    }
    // 更新オプションモーダルを開く
    novelUpdateModal?.open();
  }

  /**
   * 更新モーダルからの確認処理
   */
  async function handleUpdateConfirm(
    mode: "update" | "force-download",
    options: { 
      convertAfterUpdate?: boolean;
      createBackup?: boolean;
      includeFrozen?: boolean;
      filterByTags?: string[];
    }
  ) {
    let targetIds = Array.from(selectedIds);
    const isForceDownload = mode === "force-download";
    
    // タグフィルターや凍結フィルターが適用されている場合、対象小説を絞り込む
    if (options.filterByTags || options.includeFrozen !== undefined) {
      const filteredNovels = novels.filter(novel => {
        if (!selectedIds.has(novel.id)) return false;
        
        // タグフィルター
        if (options.filterByTags && options.filterByTags.length > 0) {
          const novelTags = novel.tags || [];
          const hasMatchingTag = options.filterByTags.some(tag => novelTags.includes(tag));
          if (!hasMatchingTag) return false;
        }
        
        // 凍結フィルター（includeFrozenがfalseの場合、凍結中を除外）
        if (options.includeFrozen === false && novel.frozen) {
          return false;
        }
        
        return true;
      });
      
      targetIds = filteredNovels.map(n => n.id);
      
      if (targetIds.length === 0) {
        toast?.show("指定した条件に一致する小説がありません", "warning");
        return;
      }
    }
    
    try {
      console.log(`[NovelList] Starting ${mode} for ${targetIds.length} novels:`, targetIds, "options:", options);

      // バックアップオプションの警告表示（実装は今後）
      if (options.createBackup) {
        console.warn("[NovelList] Backup option is not yet implemented");
        // TODO: バックアップ機能の実装
      }

      // 進捗状態を設定
      targetIds.forEach((id) => {
        progressStore.setProgress(id, "waiting", "キュー待ち...");
      });

      // API呼び出し（バックグラウンド処理開始）
      // convertAfterUpdateオプションをAPIに渡す
      await downloadNovels(targetIds, isForceDownload, options.convertAfterUpdate || false);

      const action = isForceDownload ? "再取得" : "更新";
      const convertMessage = options.convertAfterUpdate ? "（更新後に自動変換を実行します）" : "";
      toast?.show(`${targetIds.length}件の${action}を開始しました${convertMessage}`, "success");
      selectedIds = new Set();

      // 注意: 実際の進捗はPushServerイベントから更新されます
    } catch (err) {
      const message = err instanceof Error ? err.message : "不明なエラー";
      // エラー状態に設定
      targetIds.forEach((id) => {
        progressStore.setProgress(id, "error", message);
      });
      const action = isForceDownload ? "再取得" : "更新";
      toast?.show(`${action}に失敗しました: ${message}`, "error");
    }
  }

  async function handleForceDownload() {
    if (selectedIds.size === 0) {
      toast?.show("小説を選択してください", "warning");
      return;
    }
    const ids = Array.from(selectedIds);
    try {
      console.log("[NovelList] Starting download for IDs:", ids);

      // 進捗状態を設定
      ids.forEach((id) => {
        progressStore.setProgress(id, "waiting", "キュー待ち...");
      });

      // API呼び出し（バックグラウンド処理開始）
      await downloadNovels(ids);

      toast?.show("更新を開始しました", "success");
      selectedIds = new Set();

      // 注意: 実際の進捗はPushServerイベントから更新されます
    } catch (err) {
      const message = err instanceof Error ? err.message : "不明なエラー";
      // エラー状態に設定
      ids.forEach((id) => {
        progressStore.setProgress(id, "error", message);
      });
      toast?.show(`更新に失敗しました: ${message}`, "error");
    }
  }

  async function handleConvert() {
    if (selectedIds.size === 0) {
      toast?.show("小説を選択してください", "warning");
      return;
    }
    const ids = Array.from(selectedIds);
    try {
      ids.forEach((id) => {
        progressStore.setProgress(id, "waiting", "キュー待ち...");
      });

      await convertNovels(ids);

      toast?.show("変換を開始しました", "success");
      selectedIds = new Set();
    } catch (err) {
      const message = err instanceof Error ? err.message : "不明なエラー";
      ids.forEach((id) => {
        progressStore.setProgress(id, "error", message);
      });
      toast?.show(`変換に失敗しました: ${message}`, "error");
    }
  }

  async function handleRemove() {
    if (selectedIds.size === 0) {
      toast?.show("小説を選択してください", "warning");
      return;
    }
    if (!confirm(`選択した ${selectedIds.size} 件の小説を削除しますか？`)) {
      return;
    }
    try {
      await removeNovels(Array.from(selectedIds));
      toast?.show("削除しました", "success");
      selectedIds = new Set();
      await loadNovels();
    } catch (err) {
      const message = err instanceof Error ? err.message : "不明なエラー";
      toast?.show(`削除に失敗しました: ${message}`, "error");
    }
  }

  function handleTagEdit() {
    if (selectedIds.size === 0) {
      toast?.show("小説を選択してください", "warning");
      return;
    }
    tagModal.open(Array.from(selectedIds), null, () => loadNovels());
  }

  /**
   * 一括凍結/解除
   */
  async function handleToggleFreeze() {
    if (selectedIds.size === 0) {
      toast?.show("小説を選択してください", "warning");
      return;
    }

    // 選択された小説の凍結状態を確認
    const selectedNovels = novels.filter((n) => selectedIds.has(n.id));
    const frozenCount = selectedNovels.filter((n) => n.frozen).length;
    const unfrozenCount = selectedNovels.length - frozenCount;

    let action = "";
    let confirmMessage = "";
    
    if (frozenCount > unfrozenCount) {
      action = "解除";
      confirmMessage = `選択した ${selectedIds.size} 件の小説の凍結を解除しますか？`;
    } else {
      action = "凍結";
      confirmMessage = `選択した ${selectedIds.size} 件の小説を凍結しますか？`;
    }

    showConfirm(`${action}の確認`, confirmMessage, async () => {
      try {
        await toggleFreeze(Array.from(selectedIds));
        toast?.show(`${action}しました`, "success");
        selectedIds = new Set();
        await loadNovels();
      } catch (err) {
        const message = err instanceof Error ? err.message : "不明なエラー";
        toast?.show(`${action}に失敗しました: ${message}`, "error");
      }
      closeConfirmDialog();
    });
  }

  function handleSearch() {
    console.log('[NovelList] handleSearch started');
    const startTime = performance.now();
    
    // フィルタ処理中フラグをON
    isFiltering = true;
    
    // setTimeoutを使ってスピナーを表示
    setTimeout(() => {
      console.log('[NovelList] Applying filters...');
      const filterStartTime = performance.now();
      
      // draft変数から実際のフィルタ変数に反映
      filterText = draftFilterText;
      selectedTag = [...draftSelectedTag];
      selectedSite = [...draftSelectedSite];
      selectedStatus = [...draftSelectedStatus];
      currentPage = 0;
      
      console.log(`[NovelList] Filters applied in ${(performance.now() - filterStartTime).toFixed(2)}ms`);
      
      saveSettings();
      
      console.log(`[NovelList] handleSearch total: ${(performance.now() - startTime).toFixed(2)}ms`);
      
      // フィルタ処理完了後、次のフレームでスピナーをOFF
      requestAnimationFrame(() => {
        isFiltering = false;
      });
    }, 100); // スピナーが見えるように100msに変更
  }

  function handleSort(
    column:
      | "id"
      | "title"
      | "author"
      | "sitename"
      | "updated_at"
      | "status"
      | "tags"
      | "episode_count"
      | "total_chars"
      | "avg_chars_per_episode"
      | "newest_article_date"
      | "last_update"
  ) {
    if (sortBy === column) {
      sortOrder = sortOrder === "asc" ? "desc" : "asc";
    } else {
      sortBy = column;
      sortOrder = "asc";
    }
    currentPage = 0; // ソート変更時は先頭ページへ
    saveSettings();
    // $derivedが自動的に再計算するのでloadNovels不要
  }

  function clearFilters() {
    // draftと実際のフィルタの両方をクリア
    draftFilterText = "";
    draftSelectedTag = [];
    draftSelectedSite = [];
    draftSelectedStatus = [];
    filterText = "";
    selectedTag = [];
    selectedSite = [];
    selectedStatus = [];
    sortBy = "updated_at";
    sortOrder = "desc";
    currentPage = 0;
    saveSettings();
    loadNovels();
  }

  function changePageSize(newSize: number) {
    pageSize = newSize;
    currentPage = 0;
    saveSettings();
    // $derivedが自動的に再計算するのでloadNovels不要
  }

  /**
   * 確認ダイアログを表示
   */
  function showConfirm(title: string, message: string, onConfirm: () => void) {
    confirmDialogConfig = { title, message, onConfirm };
    showConfirmDialog = true;
  }

  /**
   * 確認ダイアログを閉じる
   */
  function closeConfirmDialog() {
    showConfirmDialog = false;
    confirmDialogConfig = null;
  }

  /**
   * 個別タグ編集モーダルを開く
   */
  function handleSingleTagEdit(novelId: number) {
    const novel = novels.find((n: Novel) => n.id === novelId);
    tagModal?.open([novelId], novel?.title || null, () => loadNovels());
  }

  /**
   * 個別変換設定モーダルを開く
   */
  function handleConversionSettings(novelId: number) {
    const novel = novels.find((n: Novel) => n.id === novelId);
    conversionSettingsModal?.open(novelId, novel?.title || "");
  }

  /**
   * EPUBダウンロード
   */
  async function handleDownloadEpub(novelId: number) {
    try {
      processingNovelIds.add(novelId);
      processingNovelIds = new Set(processingNovelIds);

      const downloadUrl = `http://localhost:5678/api/v2/novels/${novelId}/epub`;
      const response = await fetch(downloadUrl);

      if (!response.ok) {
        toast?.show("EPUBのダウンロードに失敗しました", "error");
        return;
      }

      // Content-Dispositionヘッダーからファイル名を取得
      const contentDisposition = response.headers.get("Content-Disposition");
      let filename = `novel_${novelId}.epub`;

      if (contentDisposition) {
        const filenameMatch = contentDisposition.match(
          /filename\*=UTF-8''(.+)/
        );
        if (filenameMatch) {
          // RFC 5987形式のデコード
          filename = decodeURIComponent(filenameMatch[1]);
        } else {
          // 通常のfilename形式も試す
          const normalMatch = contentDisposition.match(/filename="?([^"]+)"?/);
          if (normalMatch) {
            filename = normalMatch[1];
          }
        }
      }

      // Blobとしてダウンロード
      const blob = await response.blob();
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      window.URL.revokeObjectURL(url);
      document.body.removeChild(a);

      toast?.show("EPUBをダウンロードしました", "success");
    } catch (err) {
      console.error("EPUB download error:", err);
      toast?.show("EPUBのダウンロードに失敗しました", "error");
    } finally {
      processingNovelIds.delete(novelId);
      processingNovelIds = new Set(processingNovelIds);
    }
  }

  /**
   * 個別再取得
   */
  async function handleRedownloadNovel(novelId: number, novelTitle: string) {
    showConfirm(
      "再取得の確認",
      `「${novelTitle}」を再取得しますか？`,
      async () => {
        try {
          processingNovelIds.add(novelId);
          processingNovelIds = new Set(processingNovelIds);

          // 強制更新（force=true）
          await downloadNovel(novelId, true);

          toast?.show("再取得を開始しました", "success");
        } catch (err) {
          console.error("Redownload error:", err);
          toast?.show("再取得の開始に失敗しました", "error");
        } finally {
          processingNovelIds.delete(novelId);
          processingNovelIds = new Set(processingNovelIds);
        }
        closeConfirmDialog();
      }
    );
  }

  /**
   * 個別変換
   */
  async function handleConvertNovel(novelId: number, novelTitle: string) {
    showConfirm("変換の確認", `「${novelTitle}」を変換しますか？`, async () => {
      try {
        processingNovelIds.add(novelId);
        processingNovelIds = new Set(processingNovelIds);

        await convertNovel(novelId);

        toast?.show("変換を開始しました", "success");
      } catch (err) {
        console.error("Convert error:", err);
        toast?.show("変換の開始に失敗しました", "error");
      } finally {
        processingNovelIds.delete(novelId);
        processingNovelIds = new Set(processingNovelIds);
      }
      closeConfirmDialog();
    });
  }

  /**
   * 個別凍結
   */
  async function handleFreezeNovel(
    novelId: number,
    currentFrozen: boolean,
    novelTitle: string
  ) {
    const action = currentFrozen ? "解除" : "凍結";
    showConfirm(
      `${action}の確認`,
      `「${novelTitle}」を${action}しますか？`,
      async () => {
        try {
          processingNovelIds.add(novelId);
          processingNovelIds = new Set(processingNovelIds);

          if (currentFrozen) {
            await unfreezeNovel(novelId);
          } else {
            await freezeNovel(novelId);
          }

          toast?.show(`${action}しました`, "success");
          loadNovels();
        } catch (err) {
          console.error("Freeze error:", err);
          toast?.show(`${action}に失敗しました`, "error");
        } finally {
          processingNovelIds.delete(novelId);
          processingNovelIds = new Set(processingNovelIds);
        }
        closeConfirmDialog();
      }
    );
  }

  /**
   * 個別削除
   */
  async function handleDeleteNovel(novelId: number, novelTitle: string) {
    showConfirm(
      "削除の確認",
      `「${novelTitle}」を削除しますか？この操作は取り消せません。`,
      async () => {
        try {
          processingNovelIds.add(novelId);
          processingNovelIds = new Set(processingNovelIds);

          await deleteNovel(novelId);

          toast?.show("削除しました", "success");
          loadNovels();
        } catch (err) {
          console.error("Delete error:", err);
          toast?.show("削除に失敗しました", "error");
        } finally {
          processingNovelIds.delete(novelId);
          processingNovelIds = new Set(processingNovelIds);
        }
        closeConfirmDialog();
      }
    );
  }

  /**
   * タグの色に対応するCSSクラスを取得
   */
  function getTagColorClass(tagName: string): string {
    const tagInfo = allTags.find((t) => t.name === tagName);
    const color = tagInfo?.color || "white";

    const colorMap: Record<string, string> = {
      red: "bg-red-100 dark:bg-red-900 text-red-800 dark:text-red-200",
      blue: "bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200",
      green:
        "bg-green-100 dark:bg-green-900 text-green-800 dark:text-green-200",
      yellow:
        "bg-yellow-100 dark:bg-yellow-900 text-yellow-800 dark:text-yellow-200",
      magenta: "bg-pink-100 dark:bg-pink-900 text-pink-800 dark:text-pink-200",
      cyan: "bg-cyan-100 dark:bg-cyan-900 text-cyan-800 dark:text-cyan-200",
      white: "bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200",
    };
    return colorMap[color] || colorMap.white;
  }

  /**
   * 文字列を指定した長さで切り詰める
   */
  function truncateText(text: string, maxLength: number = 12): string {
    if (!text) return "";
    if (text.length <= maxLength) return text;
    return text.substring(0, maxLength) + "…";
  }

  function nextPage() {
    if (currentPage < totalPages - 1) {
      currentPage++;
      // $derivedが自動的に再計算するのでloadNovels不要
    }
  }

  function prevPage() {
    if (currentPage > 0) {
      currentPage--;
      // $derivedが自動的に再計算するのでloadNovels不要
    }
  }

  function goToPage(page: number) {
    if (page >= 0 && page < totalPages) {
      currentPage = page;
      // $derivedが自動的に再計算するのでloadNovels不要
    }
  }

</script>

<div class="relative">
  <!-- サーバー停止時のオーバーレイとメッセージ -->
  {#if $isServerStopped}
    <div
      class="absolute inset-0 bg-gray-900 bg-opacity-75 z-20 flex items-center justify-center"
    >
      <div class="text-center text-white px-4">
        <svg
          class="w-16 h-16 mx-auto mb-4"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
          ></path>
        </svg>
        <h2 class="text-2xl font-bold mb-2">サーバーが停止しています</h2>
        <p class="text-gray-300">
          再度操作するには、ヘッダーの電源メニューからサーバーを起動してください。
        </p>
      </div>
    </div>
  {/if}

  <div class="container mx-auto px-2.5 py-6">
    <!-- フィルター・検索バー -->
    <div class="bg-white dark:bg-gray-800 rounded-lg shadow-md mb-4">
      <!-- ヘッダー（常に表示） -->
      <div
        class="flex items-center justify-between p-4 cursor-pointer"
        onclick={() => (isSearchFormCollapsed = !isSearchFormCollapsed)}
        onkeydown={(e) =>
          (e.key === "Enter" || e.key === " ") &&
          (isSearchFormCollapsed = !isSearchFormCollapsed)}
        role="button"
        tabindex="0"
        aria-label="検索フォームの表示切替"
      >
        <h5 class="text-base font-semibold text-gray-700 dark:text-gray-300">
          <i class="fas fa-search mr-2"></i>
          検索・フィルター
        </h5>
        <button
          class="text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 transition-colors"
          aria-label={isSearchFormCollapsed
            ? "検索フォームを展開"
            : "検索フォームを折りたたむ"}
          tabindex="-1"
        >
          <i class="fas fa-chevron-{isSearchFormCollapsed ? 'down' : 'up'}"></i>
        </button>
      </div>

      <!-- フォーム本体（折りたたみ可能） -->
      {#if !isSearchFormCollapsed}
        <div class="p-4 pt-0">
          <div class="grid grid-cols-1 lg:grid-cols-6 gap-3">
            <!-- テキスト検索 -->
            <div class="lg:col-span-2">
              <label
                for="filterText"
                class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1"
              >
                検索
              </label>
              <input
                id="filterText"
                type="text"
                bind:value={draftFilterText}
                onkeydown={(e) => e.key === "Enter" && handleSearch()}
                placeholder="タイトル、著者..."
                class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded dark:bg-gray-700 dark:text-white"
              />
            </div>

            <!-- タグフィルター -->
            <div>
              <MultiSelectDropdown
                id="tagFilter"
                label="タグ"
                bind:value={draftSelectedTag}
                options={allTags.map(tag => ({
                  value: tag.name,
                  label: tag.name,
                  count: tag.count
                }))}
                placeholder="すべて"
              />
            </div>

            <!-- サイトフィルター -->
            <div>
              <MultiSelectDropdown
                id="siteFilter"
                label="サイト"
                bind:value={draftSelectedSite}
                options={availableSites.map(site => ({
                  value: site,
                  label: site
                }))}
                placeholder="すべて"
              />
            </div>

            <!-- 状態フィルター -->
            <div>
              <MultiSelectDropdown
                id="statusFilter"
                label="状態"
                bind:value={draftSelectedStatus}
                options={[
                  { value: '凍結', label: '凍結' },
                  { value: '完結', label: '完結' },
                  { value: '削除', label: '削除' },
                  { value: '中断', label: '中断' }
                ]}
                placeholder="すべて"
              />
            </div>

            <!-- アクション -->
            <div class="flex items-end gap-2">
              <button
                onclick={handleSearch}
                disabled={isFiltering}
                class="flex-1 px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
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
                class="px-4 py-2 bg-gray-600 text-white rounded hover:bg-gray-700 transition-colors"
                title="フィルターをクリア"
              >
                ✕
              </button>
            </div>
          </div>

          <!-- アクティブフィルター表示 -->
          {#if filterText || selectedTag || selectedSite || selectedStatus || sortBy}
            <div class="mt-3 flex flex-wrap gap-2 items-center">
              <span class="text-xs text-gray-600 dark:text-gray-400"
                >フィルター:</span
              >
              {#if filterText}
                <span
                  class="px-2 py-1 text-xs bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200 rounded whitespace-nowrap"
                >
                  検索: {filterText}
                </span>
              {/if}
              {#if selectedTag}
                <span
                  class="px-2 py-1 text-xs bg-purple-100 dark:bg-purple-900 text-purple-800 dark:text-purple-200 rounded whitespace-nowrap"
                >
                  タグ: {selectedTag}
                </span>
              {/if}
              {#if selectedSite}
                <span
                  class="px-2 py-1 text-xs bg-indigo-100 dark:bg-indigo-900 text-indigo-800 dark:text-indigo-200 rounded whitespace-nowrap"
                >
                  サイト: {selectedSite}
                </span>
              {/if}
              {#if selectedStatus}
                <span
                  class="px-2 py-1 text-xs bg-green-100 dark:bg-green-900 text-green-800 dark:text-green-200 rounded whitespace-nowrap"
                >
                  状態: {selectedStatus}
                </span>
              {/if}
              {#if sortBy}
                <span
                  class="px-2 py-1 text-xs bg-orange-100 dark:bg-orange-900 text-orange-800 dark:text-orange-200 rounded whitespace-nowrap"
                >
                  ソート: {sortBy === "id"
                    ? "ID"
                    : sortBy === "title"
                      ? "タイトル"
                      : sortBy === "author"
                        ? "著者"
                        : sortBy === "sitename"
                          ? "サイト"
                          : sortBy === "updated_at"
                            ? "更新日"
                            : sortBy === "status"
                              ? "状態"
                              : sortBy === "tags"
                                ? "タグ"
                                : "不明"} ({sortOrder === "asc"
                    ? "昇順"
                    : "降順"})
                </span>
              {/if}
            </div>
          {/if}
        </div>
      {/if}
    </div>

    <!-- アクションバー -->
    <div class="bg-white dark:bg-gray-800 rounded-lg shadow-md p-4 mb-4">
      <div class="flex flex-wrap gap-4 items-center justify-between">
        <div class="flex gap-2 flex-wrap items-center">
          <!-- 小説追加ボタン -->
          <button
            onclick={openAddNovelModal}
            class="px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 transition-colors"
          >
            <i class="fas fa-plus"></i> 小説を追加
          </button>

          <!-- 更新・変換グループ -->
          <div class="flex gap-2">
            <button
              onclick={handleDownload}
              disabled={selectedIds.size === 0}
              class="px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors"
              title="更新オプションを選択"
            >
              <i class="fas fa-sync"></i> 更新
            </button>
            <button
              onclick={handleConvert}
              disabled={selectedIds.size === 0}
              class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors"
            >
              <i class="fas fa-file-export"></i> 変換
            </button>
          </div>

          <!-- 編集・管理グループ -->
          <div class="flex gap-0 border border-gray-300 dark:border-gray-600 rounded overflow-hidden">
            <button
              onclick={handleTagEdit}
              disabled={selectedIds.size === 0}
              class="px-4 py-2 bg-purple-600 text-white hover:bg-purple-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors border-r border-purple-700"
              title="タグを編集"
            >
              <i class="fas fa-tags"></i> タグ
            </button>
            <button
              onclick={handleToggleFreeze}
              disabled={selectedIds.size === 0}
              class="px-4 py-2 bg-yellow-600 text-white hover:bg-yellow-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors border-r border-yellow-700"
              title="凍結/凍結解除を切り替え"
            >
              <i class="fas fa-snowflake"></i> 凍結
            </button>
            <button
              onclick={handleRemove}
              disabled={selectedIds.size === 0}
              class="px-4 py-2 bg-red-600 text-white hover:bg-red-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors"
              title="削除"
            >
              <i class="fas fa-trash-alt"></i> 削除
            </button>
          </div>
        </div>

        <!-- 選択数表示（右端のみ） -->
        {#if selectedIds.size > 0}
          <div class="text-sm font-medium text-gray-700 dark:text-gray-300 bg-blue-50 dark:bg-blue-900/20 px-3 py-1 rounded">
            <i class="fas fa-check-square text-blue-600 dark:text-blue-400"></i> {selectedIds.size}件選択中
          </div>
        {/if}
      </div>
    </div>

    <!-- テーブルコントロール -->
    <div class="flex justify-end items-center gap-3 mb-3">
      <button
        onclick={selectAll}
        class="px-3 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors text-xs"
        title="全ての小説を選択/解除"
      >
        <i class="fas fa-check-square"></i> 全て選択/解除
      </button>
      <button
        onclick={() => (showColumnSettings = !showColumnSettings)}
        class="px-3 py-2 bg-gray-600 text-white rounded hover:bg-gray-700 transition-colors text-xs"
        title="列の表示設定"
      >
        <i class="fas fa-cog"></i> カラム設定表示
      </button>
    </div>

    <!-- 列表示設定モーダル -->
    {#if showColumnSettings}
      <!-- svelte-ignore a11y_click_events_have_key_events -->
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <div
        class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50"
        onclick={() => (showColumnSettings = false)}
      >
        <!-- svelte-ignore a11y_click_events_have_key_events -->
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div
          class="bg-white dark:bg-gray-800 rounded-lg shadow-xl p-6 max-w-md w-full mx-4"
          onclick={(e) => e.stopPropagation()}
        >
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-semibold text-gray-900 dark:text-gray-100">
              列の表示設定
            </h3>
            <button
              onclick={() => (showColumnSettings = false)}
              class="text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
            >
              ✕
            </button>
          </div>

          <div class="space-y-3 mb-6">
            <label
              class="flex items-center gap-3 p-2 bg-gray-100 dark:bg-gray-700 rounded cursor-not-allowed"
            >
              <input
                type="checkbox"
                checked={true}
                disabled
                class="w-4 h-4 rounded"
              />
              <span class="text-sm text-gray-700 dark:text-gray-300"
                >ID <span class="text-xs text-gray-500">（必須）</span></span
              >
            </label>

            <label
              class="flex items-center gap-3 p-2 hover:bg-gray-50 dark:hover:bg-gray-700 rounded cursor-pointer"
            >
              <input
                type="checkbox"
                checked={columnVisibility.updated_at}
                onchange={(e) =>
                  handleColumnToggle(
                    "updated_at",
                    (e.target as HTMLInputElement).checked
                  )}
                class="w-4 h-4 rounded"
              />
              <span class="text-sm text-gray-700 dark:text-gray-300"
                >更新日</span
              >
            </label>

            <label
              class="flex items-center gap-3 p-2 hover:bg-gray-50 dark:hover:bg-gray-700 rounded cursor-pointer"
            >
              <input
                type="checkbox"
                checked={columnVisibility.newest_article_date}
                onchange={(e) =>
                  handleColumnToggle(
                    "newest_article_date",
                    (e.target as HTMLInputElement).checked
                  )}
                class="w-4 h-4 rounded"
              />
              <span class="text-sm text-gray-700 dark:text-gray-300"
                >最新話掲載日</span
              >
            </label>

            <label
              class="flex items-center gap-3 p-2 hover:bg-gray-50 dark:hover:bg-gray-700 rounded cursor-pointer"
            >
              <input
                type="checkbox"
                checked={columnVisibility.last_update}
                onchange={(e) =>
                  handleColumnToggle(
                    "last_update",
                    (e.target as HTMLInputElement).checked
                  )}
                class="w-4 h-4 rounded"
              />
              <span class="text-sm text-gray-700 dark:text-gray-300"
                >更新チェック日</span
              >
            </label>

            <label
              class="flex items-center gap-3 p-2 bg-gray-100 dark:bg-gray-700 rounded cursor-not-allowed"
            >
              <input
                type="checkbox"
                checked={true}
                disabled
                class="w-4 h-4 rounded"
              />
              <span class="text-sm text-gray-700 dark:text-gray-300"
                >タイトル <span class="text-xs text-gray-500">（必須）</span
                ></span
              >
            </label>

            <label
              class="flex items-center gap-3 p-2 bg-gray-100 dark:bg-gray-700 rounded cursor-not-allowed"
            >
              <input
                type="checkbox"
                checked={true}
                disabled
                class="w-4 h-4 rounded"
              />
              <span class="text-sm text-gray-700 dark:text-gray-300"
                >著者 <span class="text-xs text-gray-500">（必須）</span></span
              >
            </label>

            <label
              class="flex items-center gap-3 p-2 bg-gray-100 dark:bg-gray-700 rounded cursor-not-allowed"
            >
              <input
                type="checkbox"
                checked={true}
                disabled
                class="w-4 h-4 rounded"
              />
              <span class="text-sm text-gray-700 dark:text-gray-300"
                >掲載サイト <span class="text-xs text-gray-500">（必須）</span
                ></span
              >
            </label>

            <label
              class="flex items-center gap-3 p-2 hover:bg-gray-50 dark:hover:bg-gray-700 rounded cursor-pointer"
            >
              <input
                type="checkbox"
                checked={columnVisibility.status}
                onchange={(e) =>
                  handleColumnToggle(
                    "status",
                    (e.target as HTMLInputElement).checked
                  )}
                class="w-4 h-4 rounded"
              />
              <span class="text-sm text-gray-700 dark:text-gray-300">状態</span>
            </label>

            <label
              class="flex items-center gap-3 p-2 hover:bg-gray-50 dark:hover:bg-gray-700 rounded cursor-pointer"
            >
              <input
                type="checkbox"
                checked={columnVisibility.tags}
                onchange={(e) =>
                  handleColumnToggle(
                    "tags",
                    (e.target as HTMLInputElement).checked
                  )}
                class="w-4 h-4 rounded"
              />
              <span class="text-sm text-gray-700 dark:text-gray-300">タグ</span>
            </label>

            <label
              class="flex items-center gap-3 p-2 hover:bg-gray-50 dark:hover:bg-gray-700 rounded cursor-pointer"
            >
              <input
                type="checkbox"
                checked={columnVisibility.episode_count}
                onchange={(e) =>
                  handleColumnToggle(
                    "episode_count",
                    (e.target as HTMLInputElement).checked
                  )}
                class="w-4 h-4 rounded"
              />
              <span class="text-sm text-gray-700 dark:text-gray-300">話数</span>
            </label>

            <label
              class="flex items-center gap-3 p-2 hover:bg-gray-50 dark:hover:bg-gray-700 rounded cursor-pointer"
            >
              <input
                type="checkbox"
                checked={columnVisibility.total_chars}
                onchange={(e) =>
                  handleColumnToggle(
                    "total_chars",
                    (e.target as HTMLInputElement).checked
                  )}
                class="w-4 h-4 rounded"
              />
              <span class="text-sm text-gray-700 dark:text-gray-300"
                >文字数</span
              >
            </label>

            <label
              class="flex items-center gap-3 p-2 hover:bg-gray-50 dark:hover:bg-gray-700 rounded cursor-pointer"
            >
              <input
                type="checkbox"
                checked={columnVisibility.avg_chars_per_episode}
                onchange={(e) =>
                  handleColumnToggle(
                    "avg_chars_per_episode",
                    (e.target as HTMLInputElement).checked
                  )}
                class="w-4 h-4 rounded"
              />
              <span class="text-sm text-gray-700 dark:text-gray-300"
                >平均文字数</span
              >
            </label>
          </div>

          <div class="flex gap-2 mb-4">
            <button
              onclick={showAllColumns}
              class="flex-1 px-3 py-2 text-sm bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors"
            >
              すべて表示
            </button>
            <button
              onclick={hideAllColumns}
              class="flex-1 px-3 py-2 text-sm bg-gray-600 text-white rounded hover:bg-gray-700 transition-colors"
            >
              最小限
            </button>
            <button
              onclick={resetColumnVisibility}
              class="flex-1 px-3 py-2 text-sm bg-orange-600 text-white rounded hover:bg-orange-700 transition-colors"
            >
              リセット
            </button>
          </div>

          <div class="text-xs text-gray-500 dark:text-gray-400 text-center">
            表示中: {visibleColumnCount}列 / 選択: {selectedIds.size}件
          </div>
        </div>
      </div>
    {/if}

    <!-- 小説リストテーブル -->
    <div>
      {#if loading}
        <LoadingScreen
          message="小説リストを読み込んでいます..."
          {retryCount}
          {maxRetries}
          {isInitialLoad}
        />
      {:else if error}
        <div
          class="bg-red-100 dark:bg-red-900 border border-red-400 dark:border-red-700 text-red-700 dark:text-red-200 px-4 py-3 rounded"
        >
          <p class="font-bold">エラー</p>
          <p>{error}</p>
        </div>
      {:else if novels.length === 0}
        <div class="text-center py-12 text-gray-600 dark:text-gray-400">
          <p>小説が登録されていません</p>
        </div>
      {:else}
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow-md">
          <table
            class="min-w-full divide-y divide-gray-200 dark:divide-gray-700"
          >
            <thead class="bg-gray-50 dark:bg-gray-700">
              <tr>
                {#if columnVisibility.id}
                  <th
                    class="px-3 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-600"
                    onclick={() => handleSort("id")}
                  >
                    <span class="flex items-center gap-1">
                      ID
                      {#if sortBy === "id"}
                        <i class="fas fa-sort-{sortOrder === 'asc' ? 'up' : 'down'} text-blue-500"></i>
                      {:else}
                        <i class="fas fa-sort text-gray-400"></i>
                      {/if}
                    </span>
                  </th>
                {/if}
                {#if columnVisibility.updated_at}
                  <th
                    class="px-3 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-600"
                    onclick={() => handleSort("updated_at")}
                  >
                    <span class="flex items-center gap-1">
                      更新日
                      {#if sortBy === "updated_at"}
                        <i class="fas fa-sort-{sortOrder === 'asc' ? 'up' : 'down'} text-blue-500"></i>
                      {:else}
                        <i class="fas fa-sort text-gray-400"></i>
                      {/if}
                    </span>
                  </th>
                {/if}
                {#if columnVisibility.newest_article_date}
                  <th
                    class="px-3 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-600"
                    onclick={() => handleSort("newest_article_date")}
                  >
                    <span class="flex items-center gap-1">
                      <div class="flex flex-col">
                        <span>最新話</span>
                        <span>掲載日</span>
                      </div>
                      {#if sortBy === "newest_article_date"}
                        <i class="fas fa-sort-{sortOrder === 'asc' ? 'up' : 'down'} text-blue-500"></i>
                      {:else}
                        <i class="fas fa-sort text-gray-400"></i>
                      {/if}
                    </span>
                  </th>
                {/if}
                {#if columnVisibility.last_update}
                  <th
                    class="px-3 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-600"
                    onclick={() => handleSort("last_update")}
                  >
                    <span class="flex items-center gap-1">
                      更新チェック日
                      {#if sortBy === "last_update"}
                        <i class="fas fa-sort-{sortOrder === 'asc' ? 'up' : 'down'} text-blue-500"></i>
                      {:else}
                        <i class="fas fa-sort text-gray-400"></i>
                      {/if}
                    </span>
                  </th>
                {/if}
                <th
                  class="px-3 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-600"
                  onclick={() => handleSort("title")}
                >
                  <span class="flex items-center gap-1">
                    タイトル
                    {#if sortBy === "title"}
                      <i class="fas fa-sort-{sortOrder === 'asc' ? 'up' : 'down'} text-blue-500"></i>
                    {:else}
                      <i class="fas fa-sort text-gray-400"></i>
                    {/if}
                  </span>
                </th>
                <th
                  class="px-3 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-600"
                  onclick={() => handleSort("author")}
                >
                  <span class="flex items-center gap-1">
                    著者
                    {#if sortBy === "author"}
                      <i class="fas fa-sort-{sortOrder === 'asc' ? 'up' : 'down'} text-blue-500"></i>
                    {:else}
                      <i class="fas fa-sort text-gray-400"></i>
                    {/if}
                  </span>
                </th>
                <th
                  class="px-3 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-600"
                  onclick={() => handleSort("sitename")}
                >
                  <span class="flex items-center gap-1">
                    掲載サイト
                    {#if sortBy === "sitename"}
                      <i class="fas fa-sort-{sortOrder === 'asc' ? 'up' : 'down'} text-blue-500"></i>
                    {:else}
                      <i class="fas fa-sort text-gray-400"></i>
                    {/if}
                  </span>
                </th>
                {#if columnVisibility.status}
                  <th
                    class="px-3 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-600"
                    onclick={() => handleSort("status")}
                  >
                    <span class="flex items-center gap-1">
                      状態
                      {#if sortBy === "status"}
                        <i class="fas fa-sort-{sortOrder === 'asc' ? 'up' : 'down'} text-blue-500"></i>
                      {:else}
                        <i class="fas fa-sort text-gray-400"></i>
                      {/if}
                    </span>
                  </th>
                {/if}
                {#if columnVisibility.tags}
                  <th
                    class="px-3 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-600"
                    onclick={() => handleSort("tags")}
                  >
                    <span class="flex items-center gap-1">
                      タグ
                      {#if sortBy === "tags"}
                        <i class="fas fa-sort-{sortOrder === 'asc' ? 'up' : 'down'} text-blue-500"></i>
                      {:else}
                        <i class="fas fa-sort text-gray-400"></i>
                      {/if}
                    </span>
                  </th>
                {/if}
                {#if columnVisibility.episode_count}
                  <th
                    class="px-3 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-600"
                    onclick={() => handleSort("episode_count")}
                  >
                    <span class="flex items-center gap-1">
                      話数
                      {#if sortBy === "episode_count"}
                        <i class="fas fa-sort-{sortOrder === 'asc' ? 'up' : 'down'} text-blue-500"></i>
                      {:else}
                        <i class="fas fa-sort text-gray-400"></i>
                      {/if}
                    </span>
                  </th>
                {/if}
                {#if columnVisibility.total_chars}
                  <th
                    class="px-3 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-600"
                    onclick={() => handleSort("total_chars")}
                  >
                    <span class="flex items-center gap-1">
                      文字数
                      {#if sortBy === "total_chars"}
                        <i class="fas fa-sort-{sortOrder === 'asc' ? 'up' : 'down'} text-blue-500"></i>
                      {:else}
                        <i class="fas fa-sort text-gray-400"></i>
                      {/if}
                    </span>
                  </th>
                {/if}
                {#if columnVisibility.avg_chars_per_episode}
                  <th
                    class="px-3 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-600"
                    onclick={() => handleSort("avg_chars_per_episode")}
                  >
                    <span class="flex items-center gap-1">
                      平均文字数
                      {#if sortBy === "avg_chars_per_episode"}
                        <i class="fas fa-sort-{sortOrder === 'asc' ? 'up' : 'down'} text-blue-500"></i>
                      {:else}
                        <i class="fas fa-sort text-gray-400"></i>
                      {/if}
                    </span>
                  </th>
                {/if}
                <th
                  class="px-3 py-2 text-center text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap w-40"
                >
                  アクション
                </th>
              </tr>
            </thead>
            <tbody
              class="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700"
            >
              {#each novels as novel (novel.id)}
                <tr
                  class="transition-colors cursor-pointer {selectedIds.has(
                    novel.id
                  )
                    ? 'bg-blue-100 dark:bg-blue-900'
                    : 'hover:bg-gray-100 dark:hover:bg-gray-600'}"
                  onclick={(e) => {
                    // リンクやボタンのクリックは除外
                    if (
                      e.target instanceof HTMLElement &&
                      (e.target.tagName === "A" ||
                        e.target.tagName === "BUTTON" ||
                        e.target.closest("a") ||
                        e.target.closest("button"))
                    ) {
                      return;
                    }
                    toggleSelection(novel.id);
                  }}
                >
                  {#if columnVisibility.id}
                    <td class="px-3 py-2 text-sm">{novel.id}</td>
                  {/if}
                  {#if columnVisibility.updated_at}
                    <td
                      class="px-3 py-2 text-xs text-gray-600 dark:text-gray-400"
                    >
                      {@html formatDateTime(novel.last_update)}
                    </td>
                  {/if}
                  {#if columnVisibility.newest_article_date}
                    <td
                      class="px-3 py-2 text-xs text-gray-600 dark:text-gray-400"
                    >
                      {@html formatDateTime(novel.general_lastup)}
                    </td>
                  {/if}
                  {#if columnVisibility.last_update}
                    <td
                      class="px-3 py-2 text-xs text-gray-600 dark:text-gray-400"
                    >
                      {@html formatDateTime(novel.last_update)}
                    </td>
                  {/if}
                  <td class="px-3 py-2 text-sm font-medium max-w-md">
                    <div class="flex flex-col gap-1">
                      <div class="flex items-center gap-2">
                        <button
                          onclick={() => openNovelDetail(novel)}
                          class="text-blue-600 dark:text-blue-400 hover:underline wrap-break-word text-left font-medium"
                        >
                          {(typeof novel.promo_tags_title === "string" &&
                            novel.promo_tags_title.trim()) ||
                            novel.title}
                        </button>
                        {#if novel.frozen}
                          <span
                            class="text-xs bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200 px-2 py-1 rounded whitespace-nowrap"
                            >凍結</span
                          >
                        {/if}
                      </div>
                      {#if novel.promo_tags && novel.promo_tags.length > 0}
                        <div class="flex flex-wrap gap-1">
                          {#each novel.promo_tags as promoTag}
                            <span
                              class="px-2 py-0.5 text-xs rounded bg-amber-100 dark:bg-amber-900 text-amber-800 dark:text-amber-200 whitespace-nowrap"
                              title={promoTag}
                            >
                              {truncateText(promoTag, 12)}
                            </span>
                          {/each}
                        </div>
                      {/if}
                    </div>
                  </td>
                  <td
                    class="px-3 py-2 text-xs text-gray-600 dark:text-gray-400"
                  >
                    {#if novel.author_url}
                      <a
                        href={novel.author_url}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="text-blue-600 dark:text-blue-400 hover:underline"
                      >
                        {novel.author}
                      </a>
                    {:else}
                      {novel.author}
                    {/if}
                  </td>
                  <td
                    class="px-3 py-2 text-xs text-gray-600 dark:text-gray-400"
                  >
                    {#if novel.site_top_url}
                      <a
                        href={novel.site_top_url}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="text-blue-600 dark:text-blue-400 hover:underline"
                      >
                        {novel.sitename}
                      </a>
                    {:else}
                      {novel.sitename}
                    {/if}
                  </td>
                  {#if columnVisibility.status}
                    <td class="px-3 py-2 text-sm">
                      <div class="flex flex-wrap gap-1">
                        {#if novel.frozen}
                          <span
                            class="px-2 py-1 text-xs rounded bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200 whitespace-nowrap"
                          >
                            凍結
                          </span>
                        {/if}
                        {#if novel.status}
                          <span
                            class="px-2 py-1 text-xs rounded bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200 whitespace-nowrap"
                          >
                            {novel.status}
                          </span>
                        {/if}
                        {#if novel.novel_type}
                          <span
                            class="px-2 py-1 text-xs rounded bg-indigo-100 dark:bg-indigo-900 text-indigo-800 dark:text-indigo-200 whitespace-nowrap"
                          >
                            {novel.novel_type}
                          </span>
                        {/if}
                      </div>
                    </td>
                  {/if}
                  {#if columnVisibility.tags}
                    <td class="px-3 py-2 text-sm">
                      <div class="flex flex-wrap gap-1">
                        {#each novel.tags || [] as tag}
                          <span
                            class="px-2 py-1 text-xs rounded whitespace-nowrap {getTagColorClass(
                              tag
                            )}"
                            title={tag}
                          >
                            {truncateText(tag, 12)}
                          </span>
                        {/each}
                      </div>
                    </td>
                  {/if}
                  {#if columnVisibility.episode_count}
                    <td
                      class="px-3 py-2 text-sm text-gray-600 dark:text-gray-400"
                    >
                      {novel.general_all_no ? novel.general_all_no : "-"}
                    </td>
                  {/if}
                  {#if columnVisibility.total_chars}
                    <td
                      class="px-3 py-2 text-sm text-gray-600 dark:text-gray-400"
                    >
                      {formatCharCount(novel.length)}
                    </td>
                  {/if}
                  {#if columnVisibility.avg_chars_per_episode}
                    <td
                      class="px-3 py-2 text-sm text-gray-600 dark:text-gray-400"
                    >
                      {novel.general_all_no && novel.length
                        ? formatCharCount(
                            Math.floor(novel.length / novel.general_all_no)
                          )
                        : "-"}
                    </td>
                  {/if}
                  <td
                    class="px-3 py-2 text-sm w-32 sm:w-20 overflow-visible"
                    onclick={(e) => e.stopPropagation()}
                  >
                    <div class="flex items-center justify-center gap-2">
                      {#if processingNovelIds.has(novel.id)}
                        <div
                          class="animate-spin rounded-full h-5 w-5 border-b-2 border-blue-600"
                        ></div>
                      {:else}
                        <!-- デスクトップ表示（md以上） -->
                        <div
                          class="hidden md:flex items-center gap-1 flex-wrap"
                        >
                          <!-- EPUBダウンロード -->
                          <button
                            onclick={() => handleDownloadEpub(novel.id)}
                            class="p-1.5 text-gray-600 hover:text-blue-600 dark:text-gray-400 dark:hover:text-blue-400 transition-colors cursor-pointer"
                            title="EPUBをダウンロード"
                          >
                            <i class="fas fa-download"></i>
                          </button>

                          <!-- 再取得 -->
                          <button
                            onclick={() =>
                              handleRedownloadNovel(novel.id, novel.title)}
                            class="p-1.5 text-gray-600 hover:text-green-600 dark:text-gray-400 dark:hover:text-green-400 transition-colors cursor-pointer"
                            title="再取得"
                          >
                            <i class="fas fa-cloud-download-alt"></i>
                          </button>

                          <!-- 変換再実行 -->
                          <button
                            onclick={() =>
                              handleConvertNovel(novel.id, novel.title)}
                            class="p-1.5 text-gray-600 hover:text-purple-600 dark:text-gray-400 dark:hover:text-purple-400 transition-colors cursor-pointer"
                            title="変換再実行"
                          >
                            <i class="fas fa-file-export"></i>
                          </button>

                          <!-- その他メニュー -->
                          <div class="relative group">
                            <button
                              class="p-1.5 text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-100 transition-colors cursor-pointer"
                              title="その他"
                            >
                              <i class="fas fa-ellipsis-v"></i>
                            </button>
                            <div
                              class="absolute right-0 mt-1 w-48 bg-white dark:bg-gray-800 rounded-lg shadow-lg border border-gray-200 dark:border-gray-700 opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all z-50"
                            >
                              <button
                                onclick={(e) => {
                                  e.stopPropagation();
                                  handleSingleTagEdit(novel.id);
                                }}
                                class="w-full px-4 py-2 text-left text-sm hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors cursor-pointer"
                              >
                                <i class="fas fa-tags"></i> タグ編集
                              </button>
                              <button
                                onclick={(e) => {
                                  e.stopPropagation();
                                  handleConversionSettings(novel.id);
                                }}
                                class="w-full px-4 py-2 text-left text-sm hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors cursor-pointer"
                              >
                                <i class="fas fa-cog"></i> 個別設定
                              </button>
                              <button
                                onclick={() =>
                                  handleFreezeNovel(
                                    novel.id,
                                    novel.frozen,
                                    novel.title
                                  )}
                                class="w-full px-4 py-2 text-left text-sm hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors cursor-pointer"
                              >
                                <i
                                  class="fas fa-{novel.frozen
                                    ? 'unlock'
                                    : 'lock'}"
                                ></i>
                                {novel.frozen ? "凍結を解除" : "凍結する"}
                              </button>
                              <div
                                class="border-t border-gray-200 dark:border-gray-700"
                              ></div>
                              <button
                                onclick={() =>
                                  handleDeleteNovel(novel.id, novel.title)}
                                class="w-full px-4 py-2 text-left text-sm text-red-600 dark:text-red-400 font-bold hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors cursor-pointer"
                              >
                                <i class="fas fa-trash-alt"></i> 削除
                              </button>
                            </div>
                          </div>
                        </div>

                        <!-- モバイル表示（md未満）: 全てハンバーガーメニュー内 -->
                        <div class="md:hidden relative group">
                          <button
                            class="p-1.5 text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-100 transition-colors cursor-pointer"
                            title="アクション"
                          >
                            <i class="fas fa-ellipsis-v"></i>
                          </button>
                          <div
                            class="absolute right-0 mt-1 w-48 bg-white dark:bg-gray-800 rounded-lg shadow-lg border border-gray-200 dark:border-gray-700 opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all z-50"
                          >
                            <button
                              onclick={() => handleDownloadEpub(novel.id)}
                              class="w-full px-4 py-2 text-left text-sm hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors cursor-pointer"
                            >
                              <i class="fas fa-download"></i> EPUBダウンロード
                            </button>
                            <button
                              onclick={() =>
                                handleRedownloadNovel(novel.id, novel.title)}
                              class="w-full px-4 py-2 text-left text-sm hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors cursor-pointer"
                            >
                              <i class="fas fa-sync"></i> 再取得
                            </button>
                            <button
                              onclick={() =>
                                handleConvertNovel(novel.id, novel.title)}
                              class="w-full px-4 py-2 text-left text-sm hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors cursor-pointer"
                            >
                              <i class="fas fa-redo"></i> 変換再実行
                            </button>
                            <div
                              class="border-t border-gray-200 dark:border-gray-700"
                            ></div>
                            <button
                              onclick={(e) => {
                                e.stopPropagation();
                                handleSingleTagEdit(novel.id);
                              }}
                              class="w-full px-4 py-2 text-left text-sm hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors cursor-pointer"
                            >
                              <i class="fas fa-tags"></i> タグ編集
                            </button>
                            <button
                              onclick={(e) => {
                                e.stopPropagation();
                                handleConversionSettings(novel.id);
                              }}
                              class="w-full px-4 py-2 text-left text-sm hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors cursor-pointer"
                            >
                              <i class="fas fa-cog"></i> 個別設定
                            </button>
                            <button
                              onclick={() =>
                                handleFreezeNovel(
                                  novel.id,
                                  novel.frozen,
                                  novel.title
                                )}
                              class="w-full px-4 py-2 text-left text-sm hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors cursor-pointer"
                            >
                              <i
                                class="fas fa-{novel.frozen
                                  ? 'unlock'
                                  : 'lock'}"
                              ></i>
                              {novel.frozen ? "凍結を解除" : "凍結する"}
                            </button>
                            <div
                              class="border-t border-gray-200 dark:border-gray-700"
                            ></div>
                            <button
                              onclick={() =>
                                handleDeleteNovel(novel.id, novel.title)}
                              class="w-full px-4 py-2 text-left text-sm text-red-600 dark:text-red-400 font-bold hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors cursor-pointer"
                            >
                              <i class="fas fa-trash-alt"></i> 削除
                            </button>
                          </div>
                        </div>
                      {/if}
                    </div>
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>

          <!-- ページネーション -->
          <div
            class="bg-gray-50 dark:bg-gray-700 px-3 py-2 border-t border-gray-200 dark:border-gray-600"
          >
            <div
              class="flex flex-col sm:flex-row items-center justify-between gap-3"
            >
              <!-- 表示情報と件数選択 -->
              <div class="flex items-center gap-4">
                <div class="text-sm text-gray-700 dark:text-gray-300">
                  {#if totalFiltered > 0}
                    全 {totalFiltered} 件中 {currentPage * pageSize + 1} - {Math.min(
                      (currentPage + 1) * pageSize,
                      totalFiltered
                    )} 件を表示
                    {#if totalFiltered < totalCount}
                      <span class="text-xs text-gray-500 dark:text-gray-400"
                        >（{totalCount}件から絞り込み）</span
                      >
                    {/if}
                  {:else}
                    0 件
                  {/if}
                </div>
                <div class="flex items-center gap-2">
                  <label
                    for="pageSize"
                    class="text-sm text-gray-700 dark:text-gray-300"
                    >表示件数:</label
                  >
                  <select
                    id="pageSize"
                    bind:value={pageSize}
                    onchange={() => changePageSize(pageSize)}
                    class="px-2 py-1 border border-gray-300 dark:border-gray-600 rounded dark:bg-gray-600 dark:text-white text-sm"
                  >
                    <option value={10}>10</option>
                    <option value={25}>25</option>
                    <option value={50}>50</option>
                    <option value={100}>100</option>
                  </select>
                </div>
              </div>

              <!-- ページネーションコントロール -->
              <div class="flex gap-1">
                <button
                  onclick={() => {
                    currentPage = 0;
                    loadNovels();
                  }}
                  disabled={currentPage === 0}
                  class="px-3 py-1.5 bg-white dark:bg-gray-600 text-gray-700 dark:text-gray-200 border border-gray-300 dark:border-gray-500 rounded hover:bg-gray-50 dark:hover:bg-gray-500 disabled:opacity-50 disabled:cursor-not-allowed transition-colors font-medium"
                  title="最初のページ"
                >
                  ⟪
                </button>
                <button
                  onclick={prevPage}
                  disabled={currentPage === 0}
                  class="px-3 py-1.5 bg-white dark:bg-gray-600 text-gray-700 dark:text-gray-200 border border-gray-300 dark:border-gray-500 rounded hover:bg-gray-50 dark:hover:bg-gray-500 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                >
                  ‹ 前へ
                </button>

                <!-- ページ番号表示 -->
                {#if totalFiltered > 0}
                  {@const maxVisible = 5}
                  {@const half = Math.floor(maxVisible / 2)}

                  {@const startPage = (() => {
                    if (totalPages <= maxVisible) return 0;
                    if (currentPage <= half) return 0;
                    if (currentPage >= totalPages - half - 1)
                      return totalPages - maxVisible;
                    return currentPage - half;
                  })()}

                  {@const endPage = Math.min(
                    totalPages - 1,
                    startPage + maxVisible - 1
                  )}

                  {#if startPage > 0}
                    <button
                      onclick={() => goToPage(0)}
                      class="px-3 py-1.5 bg-white dark:bg-gray-600 text-gray-700 dark:text-gray-200 border border-gray-300 dark:border-gray-500 rounded hover:bg-gray-50 dark:hover:bg-gray-500 transition-colors"
                    >
                      1
                    </button>
                    {#if startPage > 1}
                      <span class="px-2 py-1.5 text-gray-500 dark:text-gray-400"
                        >…</span
                      >
                    {/if}
                  {/if}

                  {#each Array.from({ length: endPage - startPage + 1 }, (_, i) => startPage + i) as page}
                    <button
                      onclick={() => goToPage(page)}
                      class="min-w-10 px-3 py-1.5 {page === currentPage
                        ? 'bg-blue-600 text-white font-semibold'
                        : 'bg-white dark:bg-gray-600 text-gray-700 dark:text-gray-200'} border border-gray-300 dark:border-gray-500 rounded hover:bg-blue-500 hover:text-white transition-colors"
                    >
                      {page + 1}
                    </button>
                  {/each}

                  {#if endPage < totalPages - 1}
                    {#if endPage < totalPages - 2}
                      <span class="px-2 py-1.5 text-gray-500 dark:text-gray-400"
                        >…</span
                      >
                    {/if}
                    <button
                      onclick={() => goToPage(totalPages - 1)}
                      class="px-3 py-1.5 bg-white dark:bg-gray-600 text-gray-700 dark:text-gray-200 border border-gray-300 dark:border-gray-500 rounded hover:bg-gray-50 dark:hover:bg-gray-500 transition-colors"
                    >
                      {totalPages}
                    </button>
                  {/if}
                {/if}

                <button
                  onclick={nextPage}
                  disabled={currentPage >= totalPages - 1}
                  class="px-3 py-1.5 bg-white dark:bg-gray-600 text-gray-700 dark:text-gray-200 border border-gray-300 dark:border-gray-500 rounded hover:bg-gray-50 dark:hover:bg-gray-500 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                >
                  次へ ›
                </button>
                <button
                  onclick={() => goToPage(totalPages - 1)}
                  disabled={currentPage >= totalPages - 1}
                  class="px-3 py-1.5 bg-white dark:bg-gray-600 text-gray-700 dark:text-gray-200 border border-gray-300 dark:border-gray-500 rounded hover:bg-gray-50 dark:hover:bg-gray-500 disabled:opacity-50 disabled:cursor-not-allowed transition-colors font-medium"
                  title="最後のページ"
                >
                  ⟫
                </button>
              </div>
            </div>
          </div>
        </div>
      {/if}
    </div>
  </div>
</div>

<!-- 小説追加モーダル -->
<AddNovelModal bind:this={addNovelModal} />

<!-- タグ編集モーダル -->
<TagModal bind:this={tagModal} />

<!-- 小説更新オプションモーダル -->
<NovelUpdateModal 
  bind:this={novelUpdateModal} 
  selectedCount={selectedIds.size}
  selectedIds={selectedIds}
  allNovels={novels}
  onConfirm={handleUpdateConfirm}
/>

<!-- 個別変換設定モーダル -->
<ConversionSettingsModal bind:this={conversionSettingsModal} />

<!-- 小説詳細モーダル -->
<NovelDetailModal bind:this={novelDetailModal} />

<!-- 確認ダイアログ -->
{#if showConfirmDialog && confirmDialogConfig}
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50"
    onclick={closeConfirmDialog}
  >
    <!-- svelte-ignore a11y_click_events_have_key_events -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div
      class="bg-white dark:bg-gray-800 rounded-lg shadow-xl p-6 max-w-md w-full mx-4"
      onclick={(e) => e.stopPropagation()}
    >
      <h3 class="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-4">
        {confirmDialogConfig.title}
      </h3>
      <p class="text-gray-700 dark:text-gray-300 mb-6">
        {confirmDialogConfig.message}
      </p>
      <div class="flex justify-end gap-3">
        <button
          onclick={closeConfirmDialog}
          class="px-4 py-2 bg-gray-200 dark:bg-gray-700 text-gray-800 dark:text-gray-200 rounded hover:bg-gray-300 dark:hover:bg-gray-600 transition-colors"
        >
          キャンセル
        </button>
        <button
          onclick={confirmDialogConfig.onConfirm}
          class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors"
        >
          実行
        </button>
      </div>
    </div>
  </div>
{/if}

<!-- コンソールパネル -->
<ConsolePanel bind:this={consolePanel} />

<!-- トップに戻るボタン -->
{#if showScrollTopButton}
  {@const consolePanelOpen = consolePanel?.getIsOpen?.() ?? false}
  <button
    onclick={scrollToTop}
    class="fixed z-40 w-12 h-12 bg-blue-600 hover:bg-blue-700 text-white rounded-full shadow-lg transition-all duration-300 hover:scale-110 flex items-center justify-center"
    style={consolePanelOpen
      ? "bottom: calc(1px + 38vh); right: 1rem;"
      : "bottom: 62px; right: 1rem;"}
    title="トップに戻る"
    aria-label="トップに戻る"
  >
    <i class="fas fa-arrow-up text-lg"></i>
  </button>
{/if}

<!-- トースト通知 -->
<Toast bind:this={toast} />
