<!--
  モバイルメニューコンポーネント
  
  モバイル表示時のハンバーガーメニュー
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import ThemeToggle from './ThemeToggle.svelte';
  import PowerMenu from './PowerMenu.svelte';
  import { isServerStopped } from '../lib/stores/serverStatus';

  let isOpen = $state(false);
  let currentPath = $state('/');

  onMount(() => {
    currentPath = window.location.pathname;
  });

  function toggleMenu() {
    isOpen = !isOpen;
  }

  function closeMenu() {
    isOpen = false;
  }

  function handleNavigation() {
    closeMenu();
  }
</script>

<!-- ハンバーガーボタン（モバイルのみ表示） -->
<button
  class="md:hidden p-2 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors cursor-pointer"
  onclick={toggleMenu}
  title="メニュー"
>
  <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    {#if isOpen}
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
    {:else}
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16" />
    {/if}
  </svg>
</button>

<!-- モバイルメニュー（ドロップダウン） -->
{#if isOpen}
  <!-- 背景オーバーレイ -->
  <button
    class="fixed inset-0 bg-black bg-opacity-50 z-40 md:hidden"
    onclick={closeMenu}
    aria-label="メニューを閉じる"
  ></button>

  <!-- メニューパネル -->
  <div class="fixed top-16 right-0 w-64 bg-white dark:bg-gray-800 shadow-lg border-l border-gray-200 dark:border-gray-700 z-50 md:hidden">
    <nav class="p-4 space-y-2">
      <!-- ナビゲーションリンク -->
      <a
        href="/"
        class="block px-4 py-3 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors {currentPath === '/' || currentPath === '/index.html' ? 'bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300' : ''} {$isServerStopped ? 'opacity-50 pointer-events-none' : ''}"
        onclick={handleNavigation}
      >
        <div class="flex items-center gap-3">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6" />
          </svg>
          <span>小説リスト</span>
        </div>
      </a>

      <a
        href="/tasks"
        class="block px-4 py-3 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors {currentPath === '/tasks' || currentPath === '/tasks/' || currentPath === '/tasks/index.html' ? 'bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300' : ''} {$isServerStopped ? 'opacity-50 pointer-events-none' : ''}"
        onclick={handleNavigation}
      >
        <div class="flex items-center gap-3">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01" />
          </svg>
          <span>タスク</span>
        </div>
      </a>

      <a
        href="/settings"
        class="block px-4 py-3 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors {currentPath === '/settings' || currentPath === '/settings/' || currentPath === '/settings/index.html' ? 'bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300' : ''} {$isServerStopped ? 'opacity-50 pointer-events-none' : ''}"
        onclick={handleNavigation}
      >
        <div class="flex items-center gap-3">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
          </svg>
          <span>設定</span>
        </div>
      </a>

      <a
        href="/help"
        class="block px-4 py-3 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors {currentPath === '/help' || currentPath === '/help/' || currentPath === '/help/index.html' ? 'bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300' : ''} {$isServerStopped ? 'opacity-50 pointer-events-none' : ''}"
        onclick={handleNavigation}
      >
        <div class="flex items-center gap-3">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <circle cx="12" cy="12" r="10" stroke-width="2" />
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3" />
            <circle cx="12" cy="17" r="0.5" fill="currentColor" stroke="none" />
          </svg>
          <span>ヘルプ</span>
        </div>
      </a>

      <button
        class="w-full px-4 py-3 text-left text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors {$isServerStopped ? 'opacity-50 pointer-events-none' : 'cursor-pointer'}"
        onclick={() => {
          closeMenu();
          // TODO: 「Narou.rb MODについて」モーダルを表示
        }}
        disabled={$isServerStopped}
      >
        <div class="flex items-center gap-3">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <span>Narou.rb MODについて</span>
        </div>
      </button>

      <!-- 更新ボタン -->
      <button
        class="w-full px-4 py-3 text-left text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors {$isServerStopped ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}"
        onclick={() => { closeMenu(); window.location.reload(); }}
        disabled={$isServerStopped}
      >
        <div class="flex items-center gap-3">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
          <span>ページを更新</span>
        </div>
      </button>

      <!-- 区切り線 -->
      <div class="border-t border-gray-200 dark:border-gray-700 my-2"></div>

      <!-- 電源メニュー（インライン展開） -->
      <div class="px-4 py-2">
        <div class="text-xs font-semibold text-gray-500 dark:text-gray-400 mb-2">サーバー管理</div>
        <PowerMenu />
      </div>

      <!-- 区切り線 -->
      <div class="border-t border-gray-200 dark:border-gray-700 my-2"></div>

      <!-- テーマトグル -->
      <div class="px-4 py-2">
        <div class="text-xs font-semibold text-gray-500 dark:text-gray-400 mb-2">表示設定</div>
        <ThemeToggle />
      </div>
    </nav>
  </div>
{/if}
