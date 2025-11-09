<!--
  ヘッダーコンポーネント
  
  ナビゲーションバーとアクションボタンを提供
-->
<script lang="ts">
  import { getCurrentVersion } from '../lib/api';
  import { onMount } from 'svelte';

  let version = $state('...');
  let bootsnap = $state(false);

  onMount(async () => {
    try {
      const versionInfo = await getCurrentVersion();
      version = versionInfo.version;
      // Bootsnap情報は環境変数やAPIから取得
      // 仮実装
      bootsnap = false;
    } catch (error) {
      console.error('バージョン情報の取得に失敗:', error);
    }
  });
</script>

<header class="bg-white dark:bg-gray-800 shadow-md">
  <nav class="container mx-auto px-4 py-3">
    <div class="flex items-center justify-between">
      <div class="flex items-center space-x-4">
        <h1 class="text-2xl font-bold text-blue-600 dark:text-blue-400">
          Narou.rb MOD
          {#if bootsnap}
            <span class="text-yellow-500" title="Bootsnap enabled">⚡︎</span>
          {/if}
          <span class="text-sm text-gray-500 ml-2">WEB UI</span>
        </h1>
        <span class="text-xs text-gray-500 dark:text-gray-400">
          v{version}
        </span>
      </div>
      
      <div class="flex items-center space-x-2">
        <button
          class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors"
          onclick={() => window.location.reload()}
        >
          更新
        </button>
      </div>
    </div>
  </nav>
</header>
