<script lang="ts">
  /**
   * テーマ切り替えトグルコンポーネント
   * 
   * ダークモード/ライトモードの切り替え機能を提供
   * LocalStorageでテーマ設定を永続化
   */
  import { onMount } from 'svelte';

  let isDark = $state(false);

  onMount(() => {
    // LocalStorageからテーマ設定を復元（デフォルトはライトモード）
    const savedTheme = localStorage.getItem('theme');
    
    if (savedTheme === 'dark') {
      isDark = true;
      document.documentElement.classList.add('dark');
    } else {
      // 明示的にライトモードまたは未設定の場合
      isDark = false;
      document.documentElement.classList.remove('dark');
    }
  });

  function toggleTheme() {
    isDark = !isDark;
    
    if (isDark) {
      document.documentElement.classList.add('dark');
      localStorage.setItem('theme', 'dark');
    } else {
      document.documentElement.classList.remove('dark');
      localStorage.setItem('theme', 'light');
    }
  }
</script>

<button
  type="button"
  onclick={toggleTheme}
  class="theme-toggle"
  aria-label={isDark ? 'ライトモードに切り替え' : 'ダークモードに切り替え'}
  title={isDark ? 'ライトモードに切り替え' : 'ダークモードに切り替え'}
>
  {#if isDark}
    <i class="fas fa-sun"></i>
  {:else}
    <i class="fas fa-moon"></i>
  {/if}
</button>

<style>
  .theme-toggle {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 2.5rem;
    height: 2.5rem;
    padding: 0.5rem;
    border: 1px solid #d1d5db;
    border-radius: 0.5rem;
    background-color: white;
    color: #374151;
    font-size: 1.125rem;
    cursor: pointer;
    transition: all 0.2s;
  }

  .theme-toggle:hover {
    background-color: #f3f4f6;
    border-color: #9ca3af;
  }

  :global(.dark) .theme-toggle {
    background-color: #374151;
    border-color: #4b5563;
    color: #f9fafb;
  }

  :global(.dark) .theme-toggle:hover {
    background-color: #4b5563;
    border-color: #6b7280;
  }

  .theme-toggle:active {
    transform: scale(0.95);
  }
</style>
