<!--
  ローディングスクリーンコンポーネント
  
  データ読み込み中の全画面ローディング表示
-->
<script lang="ts">
  interface Props {
    message?: string;
    retryCount?: number;
    maxRetries?: number;
    isInitialLoad?: boolean; // 初回ロードフラグ
  }

  let { 
    message = '読み込み中...', 
    retryCount = 0, 
    maxRetries = 0,
    isInitialLoad = false 
  }: Props = $props();
</script>

<div class="flex items-center justify-center min-h-[400px] py-12">
  <div class="text-center">
    <!-- スピナー -->
    <div class="relative inline-block">
      <div class="w-16 h-16 border-4 border-gray-200 dark:border-gray-700 border-t-blue-600 dark:border-t-blue-400 rounded-full animate-spin"></div>
      <div class="absolute top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-1/2">
        <svg class="w-6 h-6 text-blue-600 dark:text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
        </svg>
      </div>
    </div>
    
    <!-- メッセージ -->
    <p class="mt-6 text-lg font-medium text-gray-700 dark:text-gray-300">
      {message}
    </p>
    
    {#if isInitialLoad}
      <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
        バックエンドサーバーの起動を待機中...
      </p>
    {:else if retryCount > 0 && maxRetries > 0}
      <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
        サーバーに接続中... ({retryCount}/{maxRetries})
      </p>
    {/if}
    
    <!-- アニメーションドット -->
    <div class="mt-2 flex justify-center space-x-1">
      <div class="w-2 h-2 bg-blue-600 dark:bg-blue-400 rounded-full animate-bounce" style="animation-delay: 0ms"></div>
      <div class="w-2 h-2 bg-blue-600 dark:bg-blue-400 rounded-full animate-bounce" style="animation-delay: 150ms"></div>
      <div class="w-2 h-2 bg-blue-600 dark:bg-blue-400 rounded-full animate-bounce" style="animation-delay: 300ms"></div>
    </div>
  </div>
</div>
