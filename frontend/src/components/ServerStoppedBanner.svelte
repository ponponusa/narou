<!--
  サーバー停止中バナー
  
  サーバー停止後にヘッダー下部に表示される警告バナー
-->
<script lang="ts">
  import { isServerStopped } from '../lib/stores/serverStatus';
</script>

{#if $isServerStopped}
  <div class="bg-red-600 dark:bg-red-700 text-white py-3 px-4 shadow-lg">
    <div class="container mx-auto flex items-center justify-center">
      <svg class="w-6 h-6 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"></path>
      </svg>
      <div>
        <p class="font-bold text-lg">サーバーが停止しています</p>
        <p class="text-sm">再度操作するには、サーバーを起動してください。</p>
      </div>
    </div>
  </div>
{/if}
