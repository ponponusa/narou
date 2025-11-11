<!--
  小説追加モーダル
  
  URLまたはncodeを入力して小説を追加
-->
<script lang="ts">
  import { addNovel } from '../lib/api';

  let isOpen = $state(false);
  let url = $state('');
  let isLoading = $state(false);
  let error = $state<string | null>(null);

  export function open() {
    isOpen = true;
    url = '';
    error = null;
  }

  export function close() {
    isOpen = false;
    url = '';
    error = null;
  }

  async function handleSubmit(e: Event) {
    e.preventDefault();
    
    if (!url.trim()) {
      error = 'URLまたはncodeを入力してください';
      return;
    }

    isLoading = true;
    error = null;

    try {
      await addNovel(url.trim(), false);
      close();
      // 成功通知（後でトースト通知に置き換え）
      alert('小説をダウンロードキューに追加しました');
    } catch (err) {
      error = err instanceof Error ? err.message : 'ダウンロードに失敗しました';
      console.error('小説追加エラー:', err);
    } finally {
      isLoading = false;
    }
  }

  function handleBackdropClick(e: MouseEvent) {
    if (e.target === e.currentTarget) {
      close();
    }
  }
</script>

{#if isOpen}
  <!-- モーダルバックドロップ -->
  <div
    class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50"
    onclick={handleBackdropClick}
    role="dialog"
    aria-modal="true"
    aria-labelledby="add-novel-title"
  >
    <!-- モーダルコンテンツ -->
    <div class="bg-white dark:bg-gray-800 rounded-lg shadow-xl w-full max-w-md mx-4">
      <!-- ヘッダー -->
      <div class="flex items-center justify-between px-6 py-4 border-b border-gray-200 dark:border-gray-700">
        <h2 id="add-novel-title" class="text-xl font-semibold text-gray-900 dark:text-gray-100">
          小説を追加
        </h2>
        <button
          onclick={close}
          class="text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200 text-2xl leading-none"
          aria-label="閉じる"
        >
          ×
        </button>
      </div>

      <!-- フォーム -->
      <form onsubmit={handleSubmit} class="p-6">
        <div class="mb-4">
          <label for="novel-url" class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            小説のURL または ncode
          </label>
          <input
            id="novel-url"
            type="text"
            bind:value={url}
            placeholder="https://ncode.syosetu.com/n9669bk/ または n9669bk"
            class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded dark:bg-gray-700 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
            disabled={isLoading}
            autofocus
          />
          <p class="mt-2 text-xs text-gray-500 dark:text-gray-400">
            小説家になろう、カクヨムなどのURLまたはncodeを入力してください
          </p>
        </div>

        {#if error}
          <div class="mb-4 p-3 bg-red-100 dark:bg-red-900 border border-red-400 dark:border-red-700 text-red-700 dark:text-red-200 rounded text-sm">
            {error}
          </div>
        {/if}

        <!-- ボタン -->
        <div class="flex gap-3 justify-end">
          <button
            type="button"
            onclick={close}
            class="px-4 py-2 text-gray-700 dark:text-gray-300 bg-gray-200 dark:bg-gray-700 rounded hover:bg-gray-300 dark:hover:bg-gray-600 transition-colors"
            disabled={isLoading}
          >
            キャンセル
          </button>
          <button
            type="submit"
            class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors"
            disabled={isLoading}
          >
            {isLoading ? 'ダウンロード中...' : 'ダウンロード'}
          </button>
        </div>
      </form>
    </div>
  </div>
{/if}
