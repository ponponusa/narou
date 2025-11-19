<!--
  About モーダルコンポーネント
  
  Narou.rb MODのバージョン情報や開発者情報を表示
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import { getVersion } from '../lib/api';
  import type { VersionData } from '../types/api';

  interface Props {
    isOpen?: boolean;
    onClose?: () => void;
  }

  let { isOpen = $bindable(false), onClose }: Props = $props();
  
  let version = $state<VersionData | null>(null);
  let loading = $state(true);
  let error = $state<string | null>(null);

  onMount(async () => {
    try {
      version = await getVersion();
    } catch (e) {
      console.error('バージョン情報の取得に失敗:', e);
      error = 'バージョン情報を取得できませんでした';
    } finally {
      loading = false;
    }
  });

  function handleClose() {
    isOpen = false;
    if (onClose) {
      onClose();
    }
  }

  function handleBackdropClick(e: MouseEvent) {
    if (e.target === e.currentTarget) {
      handleClose();
    }
  }
</script>

{#if isOpen}
  <!-- モーダルバックドロップ -->
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
  <div
    class="fixed inset-0 bg-black bg-opacity-50 z-50 flex items-center justify-center p-4"
    onclick={handleBackdropClick}
    role="dialog"
    aria-modal="true"
    aria-labelledby="about-modal-title"
    tabindex="-1"
  >
    <!-- モーダルコンテンツ -->
    <!-- svelte-ignore a11y_click_events_have_key_events -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div
      class="bg-white dark:bg-gray-800 rounded-lg shadow-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto"
      onclick={(e) => e.stopPropagation()}
    >
      <!-- ヘッダー -->
      <div class="flex items-center justify-between p-6 border-b border-gray-200 dark:border-gray-700">
        <h2 id="about-modal-title" class="text-2xl font-bold text-gray-900 dark:text-white" style="font-family: 'Stack Sans Headline', sans-serif; font-optical-sizing: auto; font-weight: 700;">
          Narou.rb MODについて
        </h2>
        <button
          class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 transition-colors"
          onclick={handleClose}
          aria-label="閉じる"
        >
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>

      <!-- コンテンツ -->
      <div class="p-6 space-y-6">
        <!-- ロゴとタイトル -->
        <div class="text-center">
          <h3 class="text-3xl font-bold text-blue-600 dark:text-blue-400 mb-2" style="font-family: 'Stack Sans Headline', sans-serif; font-optical-sizing: auto; font-weight: 700;">
            Narou.rb MOD
          </h3>
          <p class="text-gray-600 dark:text-gray-400">
            小説家になろう ダウンロード＆変換ツール
          </p>
        </div>

        <!-- バージョン情報 -->
        <div class="bg-gray-50 dark:bg-gray-900 rounded-lg p-4">
          <h4 class="text-lg font-semibold text-gray-900 dark:text-white mb-3">
            バージョン情報
          </h4>
          {#if loading}
            <div class="text-gray-600 dark:text-gray-400">読み込み中...</div>
          {:else if error}
            <div class="text-red-600 dark:text-red-400">{error}</div>
          {:else if version}
            <dl class="space-y-2">
              <div class="flex justify-between">
                <dt class="text-gray-600 dark:text-gray-400">Narou.rb MOD:</dt>
                <dd class="font-mono text-gray-900 dark:text-white">{version.narou}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-gray-600 dark:text-gray-400">Ruby:</dt>
                <dd class="font-mono text-gray-900 dark:text-white">{version.ruby}</dd>
              </div>
              {#if version.latest}
                <div class="flex justify-between">
                  <dt class="text-gray-600 dark:text-gray-400">最新バージョン:</dt>
                  <dd class="font-mono text-gray-900 dark:text-white">{version.latest}</dd>
                </div>
              {/if}
            </dl>
          {/if}
        </div>

        <!-- プロジェクト情報 -->
        <div class="space-y-4">
          <h4 class="text-lg font-semibold text-gray-900 dark:text-white">
            プロジェクト情報
          </h4>
          <div class="space-y-3">
            <div>
              <h5 class="font-semibold text-gray-900 dark:text-white mb-1">開発者</h5>
              <p class="text-gray-600 dark:text-gray-400">
                Original: <a href="https://github.com/whiteleaf7" class="text-blue-600 dark:text-blue-400 hover:underline" target="_blank" rel="noopener noreferrer">whiteleaf7</a>
              </p>
              <p class="text-gray-600 dark:text-gray-400">
                MOD: <a href="https://github.com/ponponusa" class="text-blue-600 dark:text-blue-400 hover:underline" target="_blank" rel="noopener noreferrer">ponponusa</a>
              </p>
            </div>
            <div>
              <h5 class="font-semibold text-gray-900 dark:text-white mb-1">リポジトリ</h5>
              <p>
                <a 
                  href="https://github.com/ponponusa/narou-mod" 
                  class="text-blue-600 dark:text-blue-400 hover:underline inline-flex items-center gap-1"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                    <path fill-rule="evenodd" d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z" clip-rule="evenodd" />
                  </svg>
                  GitHub
                </a>
              </p>
            </div>
            <div>
              <h5 class="font-semibold text-gray-900 dark:text-white mb-1">ライセンス</h5>
              <p class="text-gray-600 dark:text-gray-400">MIT License</p>
            </div>
          </div>
        </div>

        <!-- 説明 -->
        <div class="text-sm text-gray-600 dark:text-gray-400 pt-4 border-t border-gray-200 dark:border-gray-700">
          <p>
            Narou.rb MODは、「小説家になろう」などの小説投稿サイトから作品をダウンロードし、
            EPUB/MOBIなどの電子書籍形式に変換するツールです。
          </p>
        </div>
      </div>

      <!-- フッター -->
      <div class="flex justify-end p-6 border-t border-gray-200 dark:border-gray-700">
        <button
          class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded transition-colors"
          onclick={handleClose}
        >
          閉じる
        </button>
      </div>
    </div>
  </div>
{/if}
