<!--
  小説リストコンポーネント
  
  小説データをテーブル形式で表示し、各種操作を提供
-->
<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { getNovels, downloadNovels, convertNovels, removeNovels, getTagList } from '../lib/api';
  import type { Novel, TagInfo } from '../types/api';
  import { getPushServer } from '../lib/pushserver';
  import AddNovelModal from './AddNovelModal.svelte';
  import TagModal from './TagModal.svelte';
  import ConsolePanel from './ConsolePanel.svelte';

  let novels = $state<Novel[]>([]);
  let loading = $state(true);
  let error = $state<string | null>(null);
  let selectedIds = $state<Set<number>>(new Set());
  let totalCount = $state(0);
  let allTags = $state<TagInfo[]>([]);
  let pushServer = getPushServer();
  let addNovelModal: AddNovelModal;
  let tagModal: TagModal;
  let consolePanel: ConsolePanel;

  // フィルター・ソート設定
  let currentPage = $state(0);
  let pageSize = $state(50);
  let filterText = $state('');
  let selectedTag = $state<string>('');
  let selectedStatus = $state<string>('');
  let sortBy = $state<'title' | 'author' | 'updated_at' | ''>('');
  let sortOrder = $state<'asc' | 'desc'>('asc');

  onMount(async () => {
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
      
      // クライアント側でのフィルタリング（タグ、ステータス）
      let filteredNovels = response.novels;
      
      if (selectedTag) {
        filteredNovels = filteredNovels.filter(novel => 
          novel.tags && novel.tags.includes(selectedTag)
        );
      }
      
      if (selectedStatus) {
        filteredNovels = filteredNovels.filter(novel => 
          novel.status === selectedStatus
        );
      }
      
      // クライアント側でのソート
      if (sortBy) {
        filteredNovels.sort((a, b) => {
          let aVal: string | number = '';
          let bVal: string | number = '';
          
          switch (sortBy) {
            case 'title':
              aVal = a.title || '';
              bVal = b.title || '';
              break;
            case 'author':
              aVal = a.author || '';
              bVal = b.author || '';
              break;
            case 'updated_at':
              aVal = a.last_update || '';
              bVal = b.last_update || '';
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
      error = err instanceof Error ? err.message : '小説リストの取得に失敗しました';
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
      alert('小説を選択してください');
      return;
    }
    try {
      await downloadNovels(Array.from(selectedIds));
      alert('ダウンロードを開始しました');
      selectedIds = new Set();
      await loadNovels();
    } catch (err) {
      alert('ダウンロードに失敗しました: ' + (err instanceof Error ? err.message : '不明なエラー'));
    }
  }

  async function handleConvert() {
    if (selectedIds.size === 0) {
      alert('小説を選択してください');
      return;
    }
    try {
      await convertNovels(Array.from(selectedIds));
      alert('変換を開始しました');
      selectedIds = new Set();
      await loadNovels();
    } catch (err) {
      alert('変換に失敗しました: ' + (err instanceof Error ? err.message : '不明なエラー'));
    }
  }

  async function handleRemove() {
    if (selectedIds.size === 0) {
      alert('小説を選択してください');
      return;
    }
    if (!confirm(`選択した ${selectedIds.size} 件の小説を削除しますか？`)) {
      return;
    }
    try {
      await removeNovels(Array.from(selectedIds));
      alert('削除しました');
      selectedIds = new Set();
      await loadNovels();
    } catch (err) {
      alert('削除に失敗しました: ' + (err instanceof Error ? err.message : '不明なエラー'));
    }
  }

  function handleTagEdit() {
    if (selectedIds.size === 0) {
      alert('小説を選択してください');
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
    loadNovels();
  }
  
  function handleSort(column: 'title' | 'author' | 'updated_at') {
    if (sortBy === column) {
      sortOrder = sortOrder === 'asc' ? 'desc' : 'asc';
    } else {
      sortBy = column;
      sortOrder = 'asc';
    }
    loadNovels();
  }
  
  function clearFilters() {
    filterText = '';
    selectedTag = '';
    selectedStatus = '';
    sortBy = '';
    sortOrder = 'asc';
    currentPage = 0;
    loadNovels();
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
  <div class="bg-white dark:bg-gray-800 rounded-lg shadow-md p-4 mb-4">
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
      <!-- テキスト検索 -->
      <div>
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
      
      <!-- ステータスフィルター -->
      <div>
        <label for="statusFilter" class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
          ステータス
        </label>
        <select
          id="statusFilter"
          bind:value={selectedStatus}
          onchange={handleFilterChange}
          class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded dark:bg-gray-700 dark:text-white"
        >
          <option value="">すべて</option>
          <option value="連載中">連載中</option>
          <option value="完結済">完結済</option>
          <option value="短編">短編</option>
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
    {#if filterText || selectedTag || selectedStatus || sortBy}
      <div class="mt-3 flex flex-wrap gap-2 items-center">
        <span class="text-sm text-gray-600 dark:text-gray-400">フィルター:</span>
        {#if filterText}
          <span class="px-2 py-1 text-xs bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200 rounded">
            検索: {filterText}
          </span>
        {/if}
        {#if selectedTag}
          <span class="px-2 py-1 text-xs bg-purple-100 dark:bg-purple-900 text-purple-800 dark:text-purple-200 rounded">
            タグ: {selectedTag}
          </span>
        {/if}
        {#if selectedStatus}
          <span class="px-2 py-1 text-xs bg-green-100 dark:bg-green-900 text-green-800 dark:text-green-200 rounded">
            ステータス: {selectedStatus}
          </span>
        {/if}
        {#if sortBy}
          <span class="px-2 py-1 text-xs bg-orange-100 dark:bg-orange-900 text-orange-800 dark:text-orange-200 rounded">
            ソート: {sortBy === 'title' ? 'タイトル' : sortBy === 'author' ? '著者' : '更新日'} ({sortOrder === 'asc' ? '昇順' : '降順'})
          </span>
        {/if}
      </div>
    {/if}
  </div>

  <!-- アクションバー -->
  <div class="bg-white dark:bg-gray-800 rounded-lg shadow-md p-4 mb-4">
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
          📥 ダウンロード ({selectedIds.size})
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

  <!-- 小説リストテーブル -->
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
              <th class="px-4 py-3 text-left">
                <input
                  type="checkbox"
                  onchange={selectAll}
                  checked={selectedIds.size === novels.length && novels.length > 0}
                  class="rounded"
                />
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">
                ID
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">
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
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">
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
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">
                サイト
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">
                状態
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">
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
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">
                タグ
              </th>
            </tr>
          </thead>
          <tbody class="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700">
            {#each novels as novel (novel.id)}
              <tr class="hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors">
                <td class="px-4 py-3">
                  <input
                    type="checkbox"
                    checked={selectedIds.has(novel.id)}
                    onchange={() => toggleSelection(novel.id)}
                    class="rounded"
                  />
                </td>
                <td class="px-4 py-3 text-sm">{novel.id}</td>
                <td class="px-4 py-3 text-sm font-medium">
                  <a href={novel.toc_url} target="_blank" rel="noopener noreferrer" class="text-blue-600 dark:text-blue-400 hover:underline">
                    {novel.title}
                  </a>
                  {#if novel.frozen}
                    <span class="ml-2 text-xs bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200 px-2 py-1 rounded">凍結</span>
                  {/if}
                </td>
                <td class="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">{novel.author}</td>
                <td class="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">{novel.sitename}</td>
                <td class="px-4 py-3 text-sm">
                  <span class="px-2 py-1 text-xs rounded bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200">
                    {novel.status}
                  </span>
                </td>
                <td class="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">
                  {#if novel.last_update}
                    {new Date(novel.last_update).toLocaleDateString('ja-JP')}
                  {:else}
                    -
                  {/if}
                </td>
                <td class="px-4 py-3 text-sm">
                  <div class="flex flex-wrap gap-1">
                    {#each novel.tags || [] as tag}
                      <span class="px-2 py-1 text-xs rounded bg-purple-100 dark:bg-purple-900 text-purple-800 dark:text-purple-200">
                        {tag}
                      </span>
                    {/each}
                  </div>
                </td>
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
                onchange={() => { currentPage = 0; loadNovels(); }}
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
          <div class="flex gap-2">
            <button
              onclick={() => { currentPage = 0; loadNovels(); }}
              disabled={currentPage === 0}
              class="px-3 py-1 bg-white dark:bg-gray-600 text-gray-700 dark:text-gray-200 border border-gray-300 dark:border-gray-500 rounded hover:bg-gray-50 dark:hover:bg-gray-500 disabled:bg-gray-100 dark:disabled:bg-gray-800 disabled:cursor-not-allowed transition-colors"
              title="最初のページ"
            >
              «
            </button>
            <button
              onclick={prevPage}
              disabled={currentPage === 0}
              class="px-3 py-1 bg-white dark:bg-gray-600 text-gray-700 dark:text-gray-200 border border-gray-300 dark:border-gray-500 rounded hover:bg-gray-50 dark:hover:bg-gray-500 disabled:bg-gray-100 dark:disabled:bg-gray-800 disabled:cursor-not-allowed transition-colors"
            >
              ‹ 前へ
            </button>
            
            <!-- ページ番号表示 -->
            {#if totalCount > 0}
              {@const totalPages = Math.ceil(totalCount / pageSize)}
              {@const startPage = Math.max(0, currentPage - 2)}
              {@const endPage = Math.min(totalPages - 1, currentPage + 2)}
              
              {#if startPage > 0}
                <button
                  onclick={() => { currentPage = 0; loadNovels(); }}
                  class="px-3 py-1 bg-white dark:bg-gray-600 text-gray-700 dark:text-gray-200 border border-gray-300 dark:border-gray-500 rounded hover:bg-gray-50 dark:hover:bg-gray-500 transition-colors"
                >
                  1
                </button>
                {#if startPage > 1}
                  <span class="px-2 py-1 text-gray-500">...</span>
                {/if}
              {/if}
              
              {#each Array.from({ length: endPage - startPage + 1 }, (_, i) => startPage + i) as page}
                <button
                  onclick={() => { currentPage = page; loadNovels(); }}
                  class="px-3 py-1 {page === currentPage ? 'bg-blue-600 text-white' : 'bg-white dark:bg-gray-600 text-gray-700 dark:text-gray-200'} border border-gray-300 dark:border-gray-500 rounded hover:bg-blue-500 hover:text-white transition-colors"
                >
                  {page + 1}
                </button>
              {/each}
              
              {#if endPage < totalPages - 1}
                {#if endPage < totalPages - 2}
                  <span class="px-2 py-1 text-gray-500">...</span>
                {/if}
                <button
                  onclick={() => { currentPage = totalPages - 1; loadNovels(); }}
                  class="px-3 py-1 bg-white dark:bg-gray-600 text-gray-700 dark:text-gray-200 border border-gray-300 dark:border-gray-500 rounded hover:bg-gray-50 dark:hover:bg-gray-500 transition-colors"
                >
                  {totalPages}
                </button>
              {/if}
            {/if}
            
            <button
              onclick={nextPage}
              disabled={(currentPage + 1) * pageSize >= totalCount}
              class="px-3 py-1 bg-white dark:bg-gray-600 text-gray-700 dark:text-gray-200 border border-gray-300 dark:border-gray-500 rounded hover:bg-gray-50 dark:hover:bg-gray-500 disabled:bg-gray-100 dark:disabled:bg-gray-800 disabled:cursor-not-allowed transition-colors"
            >
              次へ ›
            </button>
            <button
              onclick={() => { currentPage = Math.ceil(totalCount / pageSize) - 1; loadNovels(); }}
              disabled={(currentPage + 1) * pageSize >= totalCount}
              class="px-3 py-1 bg-white dark:bg-gray-600 text-gray-700 dark:text-gray-200 border border-gray-300 dark:border-gray-500 rounded hover:bg-gray-50 dark:hover:bg-gray-500 disabled:bg-gray-100 dark:disabled:bg-gray-800 disabled:cursor-not-allowed transition-colors"
              title="最後のページ"
            >
              »
            </button>
          </div>
        </div>
      </div>
    </div>
  {/if}
</div>

<!-- 小説追加モーダル -->
<AddNovelModal bind:this={addNovelModal} />

<!-- タグ編集モーダル -->
<TagModal bind:this={tagModal} />

<!-- コンソールパネル -->
<ConsolePanel bind:this={consolePanel} />
