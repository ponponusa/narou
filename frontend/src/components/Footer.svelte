<!--
  フッターコンポーネント
  
  バージョン情報を表示
-->
<script lang="ts">
  import { getVersion } from '../lib/api';
  import { onMount } from 'svelte';

  let version = $state('...');

  onMount(async () => {
    try {
      const versionData = await getVersion();
      version = versionData.narou;
    } catch (error) {
      console.error('バージョン情報の取得に失敗:', error);
    }
  });
</script>

<footer class="bg-gray-100 dark:bg-gray-800 py-4 mt-8">
  <div class="container mx-auto px-2.5 text-center text-sm text-gray-600 dark:text-gray-400">
    <p>Narou.rb MOD v{version}</p>
  </div>
</footer>
