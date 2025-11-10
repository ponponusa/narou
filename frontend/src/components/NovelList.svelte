<!--
  小説リストコンポーネント
  
  小説データをテーブル形式で表示し、各種操作を提供
-->
<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { getNovels, downloadNovels, convertNovels, removeNovels, getTagList } from '../lib/api';
  import type { Novel, TagInfo } from '../types/api';
  import { getPushServer } from '../lib/pushserver';
  import { progressStore } from '../lib/progressStore';
  import AddNovelModal from './AddNovelModal.svelte';
  import TagModal from './TagModal.svelte';
  import ConsolePanel from './ConsolePanel.svelte';
  import Toast from './Toast.svelte';
  import TaskQueue from './TaskQueue.svelte';

  let novels = $state<Novel[]>([]);
  let toast: Toast;
  let loading = $state(true);
  let error = $state<string | null>(null);
  let selectedIds = $state<Set<number>>(new Set());
  let totalCount = $state(0);
  let allTags = $state<TagInfo[]>([]);
  let pushServer = getPushServer();
  let addNovelModal: AddNovelModal;
  let tagModal: TagModal;
  let consolePanel: ConsolePanel;
  let taskQueue: TaskQueue;

  // フィルター・ソート設定
  let currentPage = $state(0);
  let pageSize = $state(50);
  let filterText = $state('');
  let selectedTag = $state<string>('');
  let selectedSite = $state<string>('');
  let selectedStatus = $state<string>('');
  let sortBy = $state<'id' | 'title' | 'author' | 'sitename' | 'updated_at' | 'status' | 'tags' | ''>('updated_at');
  let sortOrder = $state<'asc' | 'desc'>('desc');
  let availableSites = $state<string[]>([]);

  // 列表示設定の型定義
  interface ColumnVisibility {
    id: boolean;
    updated_at: boolean;          // 更新日
    newest_article_date: boolean;  // 最新話掲載日
    last_update: boolean;          // 更新チェック日
    title: boolean;
    author: boolean;
    sitename: boolean;
    status: boolean;
    tags: boolean;
    episode_count: boolean;        // 話数
    total_chars: boolean;          // 文字数
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

  // 設定の保存キー
  const SETTINGS_KEY = 'narou-novel-list-settings';
  const COLUMN_VISIBILITY_KEY = 'narou-column-visibility';

  // 設定をlocalStorageに保存
  function saveSettings() {
    try {
      const settings = {
        pageSize,
        selectedTag,
        selectedSite,
        selectedStatus,
        sortBy,
        sortOrder,
      };
      localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
    } catch (err) {
      console.error('設定の保存に失敗しました:', err);
    }
  }

  // 列表示設定をlocalStorageに保存
  function saveColumnVisibility() {
    try {
      localStorage.setItem(COLUMN_VISIBILITY_KEY, JSON.stringify(columnVisibility));
    } catch (err) {
      console.error('列表示設定の保存に失敗しました:', err);
    }
  }

  // 設定をlocalStorageから復元
  function loadSettings() {
    try {
      const saved = localStorage.getItem(SETTINGS_KEY);
      if (saved) {
        const settings = JSON.parse(saved);
        pageSize = settings.pageSize ?? 50;
        selectedTag = settings.selectedTag ?? '';
        selectedSite = settings.selectedSite ?? '';
        selectedStatus = settings.selectedStatus ?? '';
        sortBy = settings.sortBy ?? 'updated_at';
        sortOrder = settings.sortOrder ?? 'desc';
      }
    } catch (err) {
      console.error('設定の読み込みに失敗しました:', err);
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
      console.error('列表示設定の読み込みに失敗しました:', err);
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
      id: true,          // 必須
      updated_at: false,
      newest_article_date: false,
      last_update: false,
      title: true,       // 必須
      author: true,      // 必須
      sitename: true,    // 必須
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
    if (column === 'title') return;
    
    // オブジェクト全体を再代入してリアクティビティを確保
    columnVisibility = {
      ...columnVisibility,
      [column]: value
    };
    saveColumnVisibility();
  }

  // 列の表示/非表示を切り替え（レガシー用）
  function toggleColumn(column: keyof ColumnVisibility) {
    // タイトルは常に表示（非表示にできない）
    if (column === 'title') return;
    
    columnVisibility = {
      ...columnVisibility,
      [column]: !columnVisibility[column]
    };
    saveColumnVisibility();
  }

  // 表示中の列数を取得
  const visibleColumnCount = $derived(
    Object.values(columnVisibility).filter(v => v).length
  );

  onMount(async () => {
    // 設定を復元
    loadSettings();
    loadColumnVisibility();
    
    await Promise.all([loadNovels(), loadTags()]);
    
    // PushServerイベントリスナー設定
    pushServer.on('table.reload', handleTableReload);
    pushServer.on('tag.updateCanvas', handleTagUpdate);
  });

  onDestroy(() => {
    // イベントリスナー解除
    pushServer.off('table.reload', handleTableReload);
    pushServer.off('tag.updateCanvas', handleTagUpdate);
  });

  function openAddNovelModal() {
    addNovelModal.open();
  }

  function handleTableReload() {
    console.log('[NovelList] Table reload triggered');
    loadNovels();
  }

  function handleTagUpdate() {
    console.log('[NovelList] Tag update triggered');
    loadTags();
  }

  async function loadTags() {
    try {
      allTags = await getTagList();
    } catch (err) {
      const message = err instanceof Error ? err.message : 'タグリストの取得に失敗しました';
      toast?.show(message, 'error');
      console.error('タグリストの取得エラー:', err);
    }
  }

  async function loadNovels() {
    loading = true;
    error = null;
    try {
      const response = await getNovels({
        page: currentPage + 1, // API v2 は 1-indexed
        per_page: pageSize,
        filter: filterText,
      });
      
      // クライアント側でのフィルタリング（タグ、サイト、状態）
      let filteredNovels = response.novels;
      
      if (selectedTag) {
        filteredNovels = filteredNovels.filter(novel => 
          novel.tags && novel.tags.includes(selectedTag)
        );
      }
      
      if (selectedSite) {
        filteredNovels = filteredNovels.filter(novel => 
          novel.sitename === selectedSite
        );
      }
      
      if (selectedStatus) {
        filteredNovels = filteredNovels.filter(novel => 
          novel.status === selectedStatus
        );
      }
      
      // サイト一覧を抽出（フィルター用）
      const sites = new Set(response.novels.map(n => n.sitename).filter(Boolean));
      availableSites = Array.from(sites).sort();
      
      // クライアント側でのソート
      if (sortBy) {
        filteredNovels.sort((a, b) => {
          let aVal: string | number = '';
          let bVal: string | number = '';
          
          switch (sortBy) {
            case 'id':
              aVal = a.id || 0;
              bVal = b.id || 0;
              break;
            case 'title':
              aVal = a.title || '';
              bVal = b.title || '';
              break;
            case 'author':
              aVal = a.author || '';
              bVal = b.author || '';
              break;
            case 'sitename':
              aVal = a.sitename || '';
              bVal = b.sitename || '';
              break;
            case 'updated_at':
              aVal = a.last_update || 0;
              bVal = b.last_update || 0;
              break;
            case 'status':
              aVal = a.status || '';
              bVal = b.status || '';
              break;
            case 'tags':
              // タグでソート（最初のタグで比較）
              aVal = (a.tags && a.tags.length > 0) ? a.tags[0] : '';
              bVal = (b.tags && b.tags.length > 0) ? b.tags[0] : '';
              break;
          }
          
          if (aVal < bVal) return sortOrder === 'asc' ? -1 : 1;
          if (aVal > bVal) return sortOrder === 'asc' ? 1 : -1;
          return 0;
        });
      }
      
      novels = filteredNovels;
      totalCount = response.total;
    } catch (err) {
      const message = err instanceof Error ? err.message : '小説リストの取得に失敗しました';
      error = message;
      toast?.show(message, 'error');
      console.error('小説リストの取得エラー:', err);
    } finally {
      loading = false;
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
      selectedIds = new Set(novels.map(n => n.id));
    }
  }

  async function handleDownload() {
    if (selectedIds.size === 0) {
      toast?.show('小説を選択してください', 'warning');
      return;
    }
    const ids = Array.from(selectedIds);
    try {
      // タスクキューに登録（WAIT状態）
      ids.forEach(id => {
        const novel = novels.find(n => n.id === id);
        if (novel) {
          taskQueue?.addTask(id, novel.title, novel.author, 'waiting');
          progressStore.setProgress(id, 'waiting', 'キュー待ち...');
        }
      });
      
      // API呼び出し（バックグラウンド処理開始）
      await downloadNovels(ids);
      
      toast?.show('更新を開始しました', 'success');
      selectedIds = new Set();
      
      // 注意: 実際の進捗はPushServerイベントから更新されます
    } catch (err) {
      const message = err instanceof Error ? err.message : '不明なエラー';
      // エラー状態に設定
      ids.forEach(id => {
        progressStore.setProgress(id, 'error', message);
      });
      toast?.show(`更新に失敗しました: ${message}`, 'error');
    }
  }

  async function handleForceDownload() {
    if (selectedIds.size === 0) {
      toast?.show('小説を選択してください', 'warning');
      return;
    }
    const ids = Array.from(selectedIds);
    try {
      ids.forEach(id => {
        const novel = novels.find(n => n.id === id);
        if (novel) {
          taskQueue?.addTask(id, novel.title, novel.author, 'waiting');
          progressStore.setProgress(id, 'waiting', 'キュー待ち...');
        }
      });
      
      await downloadNovels(ids, true);
      
      toast?.show('再取得を開始しました', 'success');
      selectedIds = new Set();
    } catch (err) {
      const message = err instanceof Error ? err.message : '不明なエラー';
      ids.forEach(id => {
        progressStore.setProgress(id, 'error', message);
      });
      toast?.show(`再取得に失敗しました: ${message}`, 'error');
    }
  }

  async function handleConvert() {
    if (selectedIds.size === 0) {
      toast?.show('小説を選択してください', 'warning');
      return;
    }
    const ids = Array.from(selectedIds);
    try {
      ids.forEach(id => {
        const novel = novels.find(n => n.id === id);
        if (novel) {
          taskQueue?.addTask(id, novel.title, novel.author, 'waiting');
          progressStore.setProgress(id, 'waiting', 'キュー待ち...');
        }
      });
      
      await convertNovels(ids);
      
      toast?.show('変換を開始しました', 'success');
      selectedIds = new Set();
    } catch (err) {
      const message = err instanceof Error ? err.message : '不明なエラー';
      ids.forEach(id => {
        progressStore.setProgress(id, 'error', message);
      });
      toast?.show(`変換に失敗しました: ${message}`, 'error');
    }
  }

  async function handleRemove() {
    if (selectedIds.size === 0) {
      toast?.show('小説を選択してください', 'warning');
      return;
    }
    if (!confirm(`選択した ${selectedIds.size} 件の小説を削除しますか？`)) {
      return;
    }
    try {
      await removeNovels(Array.from(selectedIds));
      toast?.show('削除しました', 'success');
      selectedIds = new Set();
      await loadNovels();
    } catch (err) {
      const message = err instanceof Error ? err.message : '不明なエラー';
      toast?.show(`削除に失敗しました: ${message}`, 'error');
    }
  }

  function handleTagEdit() {
    if (selectedIds.size === 0) {
      toast?.show('小説を選択してください', 'warning');
      return;
    }
    tagModal.open(Array.from(selectedIds));
  }

  function handleSearch() {
    currentPage = 0;
    loadNovels();
  }
  
  function handleFilterChange() {
    currentPage = 0;
    saveSettings();
    loadNovels();
  }
  
  function handleSort(column: 'id' | 'title' | 'author' | 'sitename' | 'updated_at' | 'status' | 'tags') {
    if (sortBy === column) {
      sortOrder = sortOrder === 'asc' ? 'desc' : 'asc';
    } else {
      sortBy = column;
      sortOrder = 'asc';
    }
    saveSettings();
    loadNovels();
  }
  
  function clearFilters() {
    filterText = '';
    selectedTag = '';
    selectedSite = '';
    selectedStatus = '';
    sortBy = 'updated_at';
    sortOrder = 'desc';
    currentPage = 0;
    saveSettings();
    loadNovels();
  }

  function changePageSize(newSize: number) {
    pageSize = newSize;
    currentPage = 0;
    saveSettings();
    loadNovels();
  }

  /**
   * タグの色に対応するCSSクラスを取得
   */
  function getTagColorClass(tagName: string): string {
    const tagInfo = allTags.find(t => t.name === tagName);
    const color = tagInfo?.color || 'white';
    
    const colorMap: Record<string, string> = {
      red: 'bg-red-100 dark:bg-red-900 text-red-800 dark:text-red-200',
      blue: 'bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200',
      green: 'bg-green-100 dark:bg-green-900 text-green-800 dark:text-green-200',
      yellow: 'bg-yellow-100 dark:bg-yellow-900 text-yellow-800 dark:text-yellow-200',
      magenta: 'bg-pink-100 dark:bg-pink-900 text-pink-800 dark:text-pink-200',
      cyan: 'bg-cyan-100 dark:bg-cyan-900 text-cyan-800 dark:text-cyan-200',
      white: 'bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200',
    };
    return colorMap[color] || colorMap.white;
  }

  /**
   * 文字列を指定した長さで切り詰める
   */
  function truncateText(text: string, maxLength: number = 12): string {
    if (!text) return '';
    if (text.length <= maxLength) return text;
    return text.substring(0, maxLength) + '…';
  }

  function nextPage() {
    if ((currentPage + 1) * pageSize < totalCount) {
      currentPage++;
      loadNovels();
    }
  }

  function prevPage() {
    if (currentPage > 0) {
      currentPage--;
      loadNovels();
    }
  }
</script>

<div class="container mx-auto px-4 py-6">
  <!-- フィルター・検索バー -->
  <div class="bg-white dark:bg-gray-800 rounded-lg shadow-md p-4 mb-4 md:mx-2.5 lg:mx-12">
    <div class="grid grid-cols-1 lg:grid-cols-6 gap-3">
      <!-- テキスト検索 -->
      <div class="lg:col-span-2">
        <label for="filterText" class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
          検索
        </label>
        <input
          id="filterText"
          type="text"
          bind:value={filterText}
          onkeydown={(e) => e.key === 'Enter' && handleSearch()}
          placeholder="タイトル、著者..."
          class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded dark:bg-gray-700 dark:text-white"
        />
      </div>
      
      <!-- タグフィルター -->
      <div>
        <label for="tagFilter" class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
          タグ
        </label>
        <select
          id="tagFilter"
          bind:value={selectedTag}
          onchange={handleFilterChange}
          class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded dark:bg-gray-700 dark:text-white"
        >
          <option value="">すべて</option>
          {#each allTags as tag}
            <option value={tag.name}>{tag.name} ({tag.count})</option>
          {/each}
        </select>
      </div>
      
      <!-- サイトフィルター -->
      <div>
        <label for="siteFilter" class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
          サイト
        </label>
        <select
          id="siteFilter"
          bind:value={selectedSite}
          onchange={handleFilterChange}
          class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded dark:bg-gray-700 dark:text-white"
        >
          <option value="">すべて</option>
          {#each availableSites as site}
            <option value={site}>{site}</option>
          {/each}
        </select>
      </div>
      
      <!-- 状態フィルター -->
      <div>
        <label for="statusFilter" class="block text-sm font-medium mb-1 text-gray-700 dark:text-gray-300">
          状態
        </label>
        <select
          id="statusFilter"
          bind:value={selectedStatus}
          onchange={handleFilterChange}
          class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded dark:bg-gray-700 dark:text-white"
        >
          <option value="">すべて</option>
          <option value="凍結">凍結</option>
          <option value="完結">完結</option>
          <option value="削除">削除</option>
          <option value="中断">中断</option>
        </select>
      </div>
      
      <!-- アクション -->
      <div class="flex items-end gap-2">
        <button
          onclick={handleSearch}
          class="flex-1 px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors"
        >
          検索
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
        <span class="text-sm text-gray-600 dark:text-gray-400">フィルター:</span>
        {#if filterText}
          <span class="px-2 py-1 text-xs bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200 rounded whitespace-nowrap">
            検索: {filterText}
          </span>
        {/if}
        {#if selectedTag}
          <span class="px-2 py-1 text-xs bg-purple-100 dark:bg-purple-900 text-purple-800 dark:text-purple-200 rounded whitespace-nowrap">
            タグ: {selectedTag}
          </span>
        {/if}
        {#if selectedSite}
          <span class="px-2 py-1 text-xs bg-indigo-100 dark:bg-indigo-900 text-indigo-800 dark:text-indigo-200 rounded whitespace-nowrap">
            サイト: {selectedSite}
          </span>
        {/if}
        {#if selectedStatus}
          <span class="px-2 py-1 text-xs bg-green-100 dark:bg-green-900 text-green-800 dark:text-green-200 rounded whitespace-nowrap">
            状態: {selectedStatus}
          </span>
        {/if}
        {#if sortBy}
          <span class="px-2 py-1 text-xs bg-orange-100 dark:bg-orange-900 text-orange-800 dark:text-orange-200 rounded whitespace-nowrap">
            ソート: {
              sortBy === 'id' ? 'ID' : 
              sortBy === 'title' ? 'タイトル' : 
              sortBy === 'author' ? '著者' : 
              sortBy === 'sitename' ? 'サイト' : 
              sortBy === 'updated_at' ? '更新日' :
              sortBy === 'status' ? '状態' :
              sortBy === 'tags' ? 'タグ' :
              '不明'
            } ({sortOrder === 'asc' ? '昇順' : '降順'})
          </span>
        {/if}
      </div>
    {/if}
  </div>

  <!-- アクションバー -->
  <div class="bg-white dark:bg-gray-800 rounded-lg shadow-md p-4 mb-4 md:mx-2.5 lg:mx-12">
    <div class="flex flex-wrap gap-4 items-center justify-between">
      <div class="flex gap-2 flex-wrap">
        <button
          onclick={openAddNovelModal}
          class="px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 transition-colors"
        >
          ➕ 小説を追加
        </button>
        <button
          onclick={handleDownload}
          disabled={selectedIds.size === 0}
          class="px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors"
        >
          � 更新 ({selectedIds.size})
        </button>
        <button
          onclick={handleForceDownload}
          disabled={selectedIds.size === 0}
          class="px-4 py-2 bg-green-700 text-white rounded hover:bg-green-800 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors"
        >
          ♻️ 再取得 ({selectedIds.size})
        </button>
        <button
          onclick={handleConvert}
          disabled={selectedIds.size === 0}
          class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors"
        >
          📖 変換 ({selectedIds.size})
        </button>
        <button
          onclick={handleTagEdit}
          disabled={selectedIds.size === 0}
          class="px-4 py-2 bg-purple-600 text-white rounded hover:bg-purple-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors"
        >
          🏷️ タグ編集 ({selectedIds.size})
        </button>
        <button
          onclick={handleRemove}
          disabled={selectedIds.size === 0}
          class="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors"
        >
          🗑️ 削除 ({selectedIds.size})
        </button>
      </div>
      
      <div class="text-sm text-gray-600 dark:text-gray-400">
        {selectedIds.size > 0 ? `${selectedIds.size}件選択中` : `${totalCount}件の小説`}
      </div>
    </div>
  </div>

  <!-- タスクキュー -->
  <TaskQueue bind:this={taskQueue} />

  <!-- テーブルコントロール -->
  <div class="flex justify-end items-center gap-3 mb-3 md:mx-2.5 lg:mx-12">
    <button
      onclick={selectAll}
      class="px-3 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors text-sm"
      title="全ての小説を選択"
    >
      ☑️ 全て選択
    </button>
    <button
      onclick={() => showColumnSettings = !showColumnSettings}
      class="px-3 py-2 bg-gray-600 text-white rounded hover:bg-gray-700 transition-colors text-sm"
      title="列の表示設定"
    >
      ⚙️ カラム設定表示
    </button>
  </div>

  <!-- 列表示設定モーダル -->
  {#if showColumnSettings}
    <!-- svelte-ignore a11y_click_events_have_key_events -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50" onclick={() => showColumnSettings = false}>
      <!-- svelte-ignore a11y_click_events_have_key_events -->
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <div class="bg-white dark:bg-gray-800 rounded-lg shadow-xl p-6 max-w-md w-full mx-4" onclick={(e) => e.stopPropagation()}>
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold text-gray-900 dark:text-gray-100">列の表示設定</h3>
          <button
            onclick={() => showColumnSettings = false}
            class="text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
          >
            ✕
          </button>
        </div>

        <div class="space-y-3 mb-6">
          <label class="flex items-center gap-3 p-2 bg-gray-100 dark:bg-gray-700 rounded cursor-not-allowed">
            <input
              type="checkbox"
              checked={true}
              disabled
              class="w-4 h-4 rounded"
            />
            <span class="text-sm text-gray-700 dark:text-gray-300">ID <span class="text-xs text-gray-500">（必須）</span></span>
          </label>

          <label class="flex items-center gap-3 p-2 hover:bg-gray-50 dark:hover:bg-gray-700 rounded cursor-pointer">
            <input
              type="checkbox"
              checked={columnVisibility.updated_at}
              onchange={(e) => handleColumnToggle('updated_at', (e.target as HTMLInputElement).checked)}
              class="w-4 h-4 rounded"
            />
            <span class="text-sm text-gray-700 dark:text-gray-300">更新日</span>
          </label>

          <label class="flex items-center gap-3 p-2 hover:bg-gray-50 dark:hover:bg-gray-700 rounded cursor-pointer">
            <input
              type="checkbox"
              checked={columnVisibility.newest_article_date}
              onchange={(e) => handleColumnToggle('newest_article_date', (e.target as HTMLInputElement).checked)}
              class="w-4 h-4 rounded"
            />
            <span class="text-sm text-gray-700 dark:text-gray-300">最新話掲載日</span>
          </label>

          <label class="flex items-center gap-3 p-2 hover:bg-gray-50 dark:hover:bg-gray-700 rounded cursor-pointer">
            <input
              type="checkbox"
              checked={columnVisibility.last_update}
              onchange={(e) => handleColumnToggle('last_update', (e.target as HTMLInputElement).checked)}
              class="w-4 h-4 rounded"
            />
            <span class="text-sm text-gray-700 dark:text-gray-300">更新チェック日</span>
          </label>

          <label class="flex items-center gap-3 p-2 bg-gray-100 dark:bg-gray-700 rounded cursor-not-allowed">
            <input
              type="checkbox"
              checked={true}
              disabled
              class="w-4 h-4 rounded"
            />
            <span class="text-sm text-gray-700 dark:text-gray-300">タイトル <span class="text-xs text-gray-500">（必須）</span></span>
          </label>

          <label class="flex items-center gap-3 p-2 bg-gray-100 dark:bg-gray-700 rounded cursor-not-allowed">
            <input
              type="checkbox"
              checked={true}
              disabled
              class="w-4 h-4 rounded"
            />
            <span class="text-sm text-gray-700 dark:text-gray-300">著者 <span class="text-xs text-gray-500">（必須）</span></span>
          </label>

          <label class="flex items-center gap-3 p-2 bg-gray-100 dark:bg-gray-700 rounded cursor-not-allowed">
            <input
              type="checkbox"
              checked={true}
              disabled
              class="w-4 h-4 rounded"
            />
            <span class="text-sm text-gray-700 dark:text-gray-300">掲載サイト <span class="text-xs text-gray-500">（必須）</span></span>
          </label>

          <label class="flex items-center gap-3 p-2 hover:bg-gray-50 dark:hover:bg-gray-700 rounded cursor-pointer">
            <input
              type="checkbox"
              checked={columnVisibility.status}
              onchange={(e) => handleColumnToggle('status', (e.target as HTMLInputElement).checked)}
              class="w-4 h-4 rounded"
            />
            <span class="text-sm text-gray-700 dark:text-gray-300">状態</span>
          </label>

          <label class="flex items-center gap-3 p-2 hover:bg-gray-50 dark:hover:bg-gray-700 rounded cursor-pointer">
            <input
              type="checkbox"
              checked={columnVisibility.tags}
              onchange={(e) => handleColumnToggle('tags', (e.target as HTMLInputElement).checked)}
              class="w-4 h-4 rounded"
            />
            <span class="text-sm text-gray-700 dark:text-gray-300">タグ</span>
          </label>

          <label class="flex items-center gap-3 p-2 hover:bg-gray-50 dark:hover:bg-gray-700 rounded cursor-pointer">
            <input
              type="checkbox"
              checked={columnVisibility.episode_count}
              onchange={(e) => handleColumnToggle('episode_count', (e.target as HTMLInputElement).checked)}
              class="w-4 h-4 rounded"
            />
            <span class="text-sm text-gray-700 dark:text-gray-300">話数</span>
          </label>

          <label class="flex items-center gap-3 p-2 hover:bg-gray-50 dark:hover:bg-gray-700 rounded cursor-pointer">
            <input
              type="checkbox"
              checked={columnVisibility.total_chars}
              onchange={(e) => handleColumnToggle('total_chars', (e.target as HTMLInputElement).checked)}
              class="w-4 h-4 rounded"
            />
            <span class="text-sm text-gray-700 dark:text-gray-300">文字数</span>
          </label>

          <label class="flex items-center gap-3 p-2 hover:bg-gray-50 dark:hover:bg-gray-700 rounded cursor-pointer">
            <input
              type="checkbox"
              checked={columnVisibility.avg_chars_per_episode}
              onchange={(e) => handleColumnToggle('avg_chars_per_episode', (e.target as HTMLInputElement).checked)}
              class="w-4 h-4 rounded"
            />
            <span class="text-sm text-gray-700 dark:text-gray-300">平均文字数</span>
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
  <div class="md:mx-2.5 lg:mx-12">
  {#if loading}
    <div class="text-center py-12">
      <div class="inline-block animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
      <p class="mt-4 text-gray-600 dark:text-gray-400">読み込み中...</p>
    </div>
  {:else if error}
    <div class="bg-red-100 dark:bg-red-900 border border-red-400 dark:border-red-700 text-red-700 dark:text-red-200 px-4 py-3 rounded">
      <p class="font-bold">エラー</p>
      <p>{error}</p>
    </div>
  {:else if novels.length === 0}
    <div class="text-center py-12 text-gray-600 dark:text-gray-400">
      <p>小説が登録されていません</p>
    </div>
  {:else}
    <div class="bg-white dark:bg-gray-800 rounded-lg shadow-md overflow-hidden">
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-gray-700">
            <tr>
              {#if columnVisibility.id}
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap">
                <button
                  onclick={() => handleSort('id')}
                  class="flex items-center gap-1 hover:text-gray-700 dark:hover:text-gray-100"
                >
                  ID
                  {#if sortBy === 'id'}
                    <span>{sortOrder === 'asc' ? '▲' : '▼'}</span>
                  {/if}
                </button>
              </th>
              {/if}
              {#if columnVisibility.updated_at}
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap">
                <button
                  onclick={() => handleSort('updated_at')}
                  class="flex items-center gap-1 hover:text-gray-700 dark:hover:text-gray-100"
                >
                  更新日
                  {#if sortBy === 'updated_at'}
                    <span>{sortOrder === 'asc' ? '▲' : '▼'}</span>
                  {/if}
                </button>
              </th>
              {/if}
              {#if columnVisibility.newest_article_date}
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">
                <div class="flex flex-col">
                  <span>最新話</span>
                  <span>掲載日</span>
                </div>
              </th>
              {/if}
              {#if columnVisibility.last_update}
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap">
                更新チェック日
              </th>
              {/if}
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap">
                <button
                  onclick={() => handleSort('title')}
                  class="flex items-center gap-1 hover:text-gray-700 dark:hover:text-gray-100"
                >
                  タイトル
                  {#if sortBy === 'title'}
                    <span>{sortOrder === 'asc' ? '▲' : '▼'}</span>
                  {/if}
                </button>
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap">
                <button
                  onclick={() => handleSort('author')}
                  class="flex items-center gap-1 hover:text-gray-700 dark:hover:text-gray-100"
                >
                  著者
                  {#if sortBy === 'author'}
                    <span>{sortOrder === 'asc' ? '▲' : '▼'}</span>
                  {/if}
                </button>
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap">
                <button
                  onclick={() => handleSort('sitename')}
                  class="flex items-center gap-1 hover:text-gray-700 dark:hover:text-gray-100"
                >
                  掲載サイト
                  {#if sortBy === 'sitename'}
                    <span>{sortOrder === 'asc' ? '▲' : '▼'}</span>
                  {/if}
                </button>
              </th>
              {#if columnVisibility.status}
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
              {/if}
              {#if columnVisibility.tags}
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap">
                <button
                  onclick={() => handleSort('tags')}
                  class="flex items-center gap-1 hover:text-gray-700 dark:hover:text-gray-100"
                >
                  タグ
                  {#if sortBy === 'tags'}
                    <span>{sortOrder === 'asc' ? '▲' : '▼'}</span>
                  {/if}
                </button>
              </th>
              {/if}
              {#if columnVisibility.episode_count}
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap">
                話数
              </th>
              {/if}
              {#if columnVisibility.total_chars}
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap">
                文字数
              </th>
              {/if}
              {#if columnVisibility.avg_chars_per_episode}
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider whitespace-nowrap">
                平均文字数
              </th>
              {/if}
            </tr>
          </thead>
          <tbody class="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700">
            {#each novels as novel (novel.id)}
              <tr 
                class="transition-colors cursor-pointer {selectedIds.has(novel.id) ? 'bg-blue-100 dark:bg-blue-900' : 'hover:bg-gray-50 dark:hover:bg-gray-700'}"
                onclick={(e) => {
                  // リンクやボタンのクリックは除外
                  if (e.target instanceof HTMLElement && 
                      (e.target.tagName === 'A' || e.target.tagName === 'BUTTON' || 
                       e.target.closest('a') || e.target.closest('button'))) {
                    return;
                  }
                  toggleSelection(novel.id);
                }}
              >
                {#if columnVisibility.id}
                <td class="px-4 py-3 text-sm">{novel.id}</td>
                {/if}
                {#if columnVisibility.updated_at}
                <td class="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">
                  {#if novel.last_update}
                    <div class="flex flex-col">
                      <span>{new Date(Number(novel.last_update) * 1000).toLocaleDateString('ja-JP')}</span>
                      <span class="text-xs text-gray-500 dark:text-gray-500">{new Date(Number(novel.last_update) * 1000).toLocaleTimeString('ja-JP', { hour: '2-digit', minute: '2-digit' })}</span>
                    </div>
                  {:else}
                    <span class="text-gray-400 dark:text-gray-600">-</span>
                  {/if}
                </td>
                {/if}
                {#if columnVisibility.newest_article_date}
                <td class="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">
                  {#if novel.general_lastup}
                    {new Date(Number(novel.general_lastup) * 1000).toLocaleDateString('ja-JP')}
                  {:else}
                    <span class="text-gray-400 dark:text-gray-600">-</span>
                  {/if}
                </td>
                {/if}
                {#if columnVisibility.last_update}
                <td class="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">
                  {#if novel.last_update}
                    {new Date(Number(novel.last_update) * 1000).toLocaleDateString('ja-JP')}
                  {:else}
                    <span class="text-gray-400 dark:text-gray-600">-</span>
                  {/if}
                </td>
                {/if}
                <td class="px-4 py-3 text-sm font-medium max-w-md">
                  <div class="flex flex-col gap-1">
                    <div class="flex items-center gap-2">
                      <a 
                        href={novel.toc_url} 
                        target="_blank" 
                        rel="noopener noreferrer" 
                        class="text-blue-600 dark:text-blue-400 hover:underline break-words"
                      >
                        {(typeof novel.promo_tags_title === 'string' && novel.promo_tags_title.trim()) || novel.title}
                      </a>
                      {#if novel.frozen}
                        <span class="text-xs bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200 px-2 py-1 rounded whitespace-nowrap">凍結</span>
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
                <td class="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">{novel.author}</td>
                <td class="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">{novel.sitename}</td>
                {#if columnVisibility.status}
                <td class="px-4 py-3 text-sm">
                  <div class="flex flex-wrap gap-1">
                    {#if novel.frozen}
                      <span class="px-2 py-1 text-xs rounded bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200 whitespace-nowrap">
                        凍結
                      </span>
                    {/if}
                    {#if novel.status}
                      <span class="px-2 py-1 text-xs rounded bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200 whitespace-nowrap">
                        {novel.status}
                      </span>
                    {/if}
                    {#if novel.novel_type}
                      <span class="px-2 py-1 text-xs rounded bg-indigo-100 dark:bg-indigo-900 text-indigo-800 dark:text-indigo-200 whitespace-nowrap">
                        {novel.novel_type}
                      </span>
                    {/if}
                  </div>
                </td>
                {/if}
                {#if columnVisibility.tags}
                <td class="px-4 py-3 text-sm">
                  <div class="flex flex-wrap gap-1">
                    {#each novel.tags || [] as tag}
                      <span 
                        class="px-2 py-1 text-xs rounded whitespace-nowrap {getTagColorClass(tag)}"
                        title={tag}
                      >
                        {truncateText(tag, 12)}
                      </span>
                    {/each}
                  </div>
                </td>
                {/if}
                {#if columnVisibility.episode_count}
                <td class="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">
                  {novel.general_all_no ? novel.general_all_no : '-'}
                </td>
                {/if}
                {#if columnVisibility.total_chars}
                <td class="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">
                  {novel.length ? novel.length.toLocaleString() : '-'}
                </td>
                {/if}
                {#if columnVisibility.avg_chars_per_episode}
                <td class="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">
                  {novel.general_all_no && novel.length ? Math.floor(novel.length / novel.general_all_no).toLocaleString() : '-'}
                </td>
                {/if}
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
      
      <!-- ページネーション -->
      <div class="bg-gray-50 dark:bg-gray-700 px-4 py-3 border-t border-gray-200 dark:border-gray-600">
        <div class="flex flex-col sm:flex-row items-center justify-between gap-4">
          <!-- 表示情報と件数選択 -->
          <div class="flex items-center gap-4">
            <div class="text-sm text-gray-700 dark:text-gray-300">
              全 {totalCount} 件中 {currentPage * pageSize + 1} - {Math.min((currentPage + 1) * pageSize, totalCount)} 件を表示
            </div>
            <div class="flex items-center gap-2">
              <label for="pageSize" class="text-sm text-gray-700 dark:text-gray-300">表示件数:</label>
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
              onclick={() => { currentPage = 0; loadNovels(); }}
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
            {#if totalCount > 0}
              {@const totalPages = Math.ceil(totalCount / pageSize)}
              {@const maxVisible = 5}
              {@const half = Math.floor(maxVisible / 2)}
              
              {@const startPage = (() => {
                if (totalPages <= maxVisible) return 0;
                if (currentPage <= half) return 0;
                if (currentPage >= totalPages - half - 1) return totalPages - maxVisible;
                return currentPage - half;
              })()}
              
              {@const endPage = Math.min(totalPages - 1, startPage + maxVisible - 1)}
              
              {#if startPage > 0}
                <button
                  onclick={() => { currentPage = 0; loadNovels(); }}
                  class="px-3 py-1.5 bg-white dark:bg-gray-600 text-gray-700 dark:text-gray-200 border border-gray-300 dark:border-gray-500 rounded hover:bg-gray-50 dark:hover:bg-gray-500 transition-colors"
                >
                  1
                </button>
                {#if startPage > 1}
                  <span class="px-2 py-1.5 text-gray-500 dark:text-gray-400">…</span>
                {/if}
              {/if}
              
              {#each Array.from({ length: endPage - startPage + 1 }, (_, i) => startPage + i) as page}
                <button
                  onclick={() => { currentPage = page; loadNovels(); }}
                  class="min-w-[2.5rem] px-3 py-1.5 {page === currentPage ? 'bg-blue-600 text-white font-semibold' : 'bg-white dark:bg-gray-600 text-gray-700 dark:text-gray-200'} border border-gray-300 dark:border-gray-500 rounded hover:bg-blue-500 hover:text-white transition-colors"
                >
                  {page + 1}
                </button>
              {/each}
              
              {#if endPage < totalPages - 1}
                {#if endPage < totalPages - 2}
                  <span class="px-2 py-1.5 text-gray-500 dark:text-gray-400">…</span>
                {/if}
                <button
                  onclick={() => { currentPage = totalPages - 1; loadNovels(); }}
                  class="px-3 py-1.5 bg-white dark:bg-gray-600 text-gray-700 dark:text-gray-200 border border-gray-300 dark:border-gray-500 rounded hover:bg-gray-50 dark:hover:bg-gray-500 transition-colors"
                >
                  {totalPages}
                </button>
              {/if}
            {/if}
            
            <button
              onclick={nextPage}
              disabled={(currentPage + 1) * pageSize >= totalCount}
              class="px-3 py-1.5 bg-white dark:bg-gray-600 text-gray-700 dark:text-gray-200 border border-gray-300 dark:border-gray-500 rounded hover:bg-gray-50 dark:hover:bg-gray-500 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              次へ ›
            </button>
            <button
              onclick={() => { currentPage = Math.ceil(totalCount / pageSize) - 1; loadNovels(); }}
              disabled={(currentPage + 1) * pageSize >= totalCount}
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

<!-- 小説追加モーダル -->
<AddNovelModal bind:this={addNovelModal} />

<!-- タグ編集モーダル -->
<TagModal bind:this={tagModal} />

<!-- コンソールパネル -->
<ConsolePanel bind:this={consolePanel} />

<!-- トースト通知 -->
<Toast bind:this={toast} />
