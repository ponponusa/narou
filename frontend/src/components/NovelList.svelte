<!--
  小説リストコンポーネント
  
  小説データをテーブル形式で表示し、各種操作を提供
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import { getNovels, downloadNovels, convertNovels, removeNovels } from '../lib/api';
  import type { Novel } from '../types/api';

  let novels = $state<Novel[]>([]);
  let loading = $state(true);
  let error = $state<string | null>(null);
  let selectedIds = $state<Set<number>>(new Set());
  let totalCount = $state(0);

  // フィルター・ソート設定
  let currentPage = $state(0);
  let pageSize = $state(50);
  let filterText = $state('');

  onMount(async () => {
    await loadNovels();
  });

  async function loadNovels() {
    loading = true;
    error = null;
    try {
      const response = await getNovels({
        page: currentPage + 1, // API v2 は 1-indexed
        per_page: pageSize,
        filter: filterText,
      });
      novels = response.novels;
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

  function handleSearch() {
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
  <!-- アクションバー -->
  <div class="bg-white dark:bg-gray-800 rounded-lg shadow-md p-4 mb-4">
    <div class="flex flex-wrap gap-4 items-center justify-between">
      <div class="flex gap-2">
        <button
          onclick={handleDownload}
          disabled={selectedIds.size === 0}
          class="px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors"
        >
          ダウンロード ({selectedIds.size})
        </button>
        <button
          onclick={handleConvert}
          disabled={selectedIds.size === 0}
          class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors"
        >
          変換 ({selectedIds.size})
        </button>
        <button
          onclick={handleRemove}
          disabled={selectedIds.size === 0}
          class="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors"
        >
          削除 ({selectedIds.size})
        </button>
      </div>
      
      <div class="flex gap-2 items-center">
        <input
          type="text"
          bind:value={filterText}
          onkeydown={(e) => e.key === 'Enter' && handleSearch()}
          placeholder="検索..."
          class="px-3 py-2 border border-gray-300 dark:border-gray-600 rounded dark:bg-gray-700 dark:text-white"
        />
        <button
          onclick={handleSearch}
          class="px-4 py-2 bg-gray-600 text-white rounded hover:bg-gray-700 transition-colors"
        >
          検索
        </button>
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
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">ID</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">タイトル</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">著者</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">サイト</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">状態</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">タグ</th>
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
      <div class="bg-gray-50 dark:bg-gray-700 px-4 py-3 flex items-center justify-between border-t border-gray-200 dark:border-gray-600">
        <div class="text-sm text-gray-700 dark:text-gray-300">
          全 {totalCount} 件中 {currentPage * pageSize + 1} - {Math.min((currentPage + 1) * pageSize, totalCount)} 件を表示
        </div>
        <div class="flex gap-2">
          <button
            onclick={prevPage}
            disabled={currentPage === 0}
            class="px-3 py-1 bg-white dark:bg-gray-600 text-gray-700 dark:text-gray-200 border border-gray-300 dark:border-gray-500 rounded hover:bg-gray-50 dark:hover:bg-gray-500 disabled:bg-gray-100 dark:disabled:bg-gray-800 disabled:cursor-not-allowed transition-colors"
          >
            前へ
          </button>
          <button
            onclick={nextPage}
            disabled={(currentPage + 1) * pageSize >= totalCount}
            class="px-3 py-1 bg-white dark:bg-gray-600 text-gray-700 dark:text-gray-200 border border-gray-300 dark:border-gray-500 rounded hover:bg-gray-50 dark:hover:bg-gray-500 disabled:bg-gray-100 dark:disabled:bg-gray-800 disabled:cursor-not-allowed transition-colors"
          >
            次へ
          </button>
        </div>
      </div>
    </div>
  {/if}
</div>
