<script lang="ts">
  /**
   * パーサー設定コンポーネント
   *
   * HTML解析パーサーの設定を管理
   */
  import { onMount } from "svelte";
  import { getParserSettings, updateParserSettings } from "../lib/api";

  interface SuccessfulSelector {
    selector: string;
    date: string;
  }

  interface UserConfig {
    last_successful_selectors?: Record<string, SuccessfulSelector>;
  }

  let loading = $state(true);
  let saving = $state(false);
  let error = $state<string | null>(null);
  let successMessage = $state<string | null>(null);

  let defaultEngine = $state<string>("nokogiri");
  let domains = $state<string[]>([]);
  let selectedDomain = $state<string>("");
  let userConfigs = $state<Record<string, UserConfig>>({});

  // メッセージの自動クリア
  $effect(() => {
    if (successMessage) {
      const timer = setTimeout(() => {
        successMessage = null;
      }, 3000);
      return () => clearTimeout(timer);
    }
  });

  async function loadSettings() {
    loading = true;
    error = null;

    try {
      const settings = await getParserSettings();
      defaultEngine = settings.global_config.default_engine || "nokogiri";
      domains = settings.domains || [];
      userConfigs = settings.user_configs || {};

      // 最初のドメインを選択
      if (domains.length > 0 && !selectedDomain) {
        selectedDomain = domains[0];
      }
    } catch (e) {
      error =
        e instanceof Error ? e.message : "パーサー設定の読み込みに失敗しました";
      console.error("Failed to load parser settings:", e);
    } finally {
      loading = false;
    }
  }

  async function saveDefaultEngine() {
    saving = true;
    error = null;
    successMessage = null;

    try {
      await updateParserSettings({
        default_engine: defaultEngine,
      });
      successMessage = "デフォルトエンジンを更新しました";
    } catch (e) {
      error =
        e instanceof Error
          ? e.message
          : "デフォルトエンジンの更新に失敗しました";
      console.error("Failed to update default engine:", e);
    } finally {
      saving = false;
    }
  }

  onMount(() => {
    loadSettings();
  });
</script>

<div class="parser-settings">
  {#if loading}
    <div class="loading">
      <div class="spinner"></div>
      <p>設定を読み込み中...</p>
    </div>
  {:else}
    <!-- エラーメッセージ -->
    {#if error}
      <div class="alert alert-error">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="h-6 w-6"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
          />
        </svg>
        <span>{error}</span>
      </div>
    {/if}

    <!-- 成功メッセージ -->
    {#if successMessage}
      <div class="alert alert-success">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="h-6 w-6"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M5 13l4 4L19 7"
          />
        </svg>
        <span>{successMessage}</span>
      </div>
    {/if}

    <!-- デフォルトエンジン設定 -->
    <div class="setting-section">
      <h3 class="section-title">デフォルトパーサーエンジン</h3>
      <p class="section-description">
        新規ダウンロード時に使用するパーサーを選択します。
      </p>

      <div class="engine-selector">
        <label class="radio-label">
          <input
            type="radio"
            bind:group={defaultEngine}
            value="nokogiri"
            onchange={() => saveDefaultEngine()}
            disabled={saving}
          />
          <div class="radio-content">
            <span class="radio-title">Nokogiri (推奨)</span>
            <span class="radio-description">
              CSS
              セレクタベースの新パーサー。サイト構造の変更に強く、保守性が高い。
            </span>
          </div>
        </label>

        <label class="radio-label">
          <input
            type="radio"
            bind:group={defaultEngine}
            value="legacy"
            onchange={() => saveDefaultEngine()}
            disabled={saving}
          />
          <div class="radio-content">
            <span class="radio-title">Legacy</span>
            <span class="radio-description">
              正規表現ベースの従来パーサー。互換性維持のため残されています。
            </span>
          </div>
        </label>
      </div>
    </div>

    <!-- サイト別設定 -->
    <div class="setting-section">
      <h3 class="section-title">サイト別設定</h3>
      <p class="section-description">
        対応サイト: {domains.length} サイト
      </p>

      {#if domains.length > 0}
        <div class="domain-list">
          <select bind:value={selectedDomain} class="domain-select">
            {#each domains as domain}
              <option value={domain}>{domain}</option>
            {/each}
          </select>

          {#if selectedDomain && userConfigs[selectedDomain]}
            <div class="config-info">
              <h4 class="config-title">{selectedDomain}</h4>
              <div class="config-details">
                <p class="text-sm text-gray-600 dark:text-gray-400">
                  カスタム設定が適用されています
                </p>
                {#if userConfigs[selectedDomain].last_successful_selectors}
                  <div class="mt-2">
                    <p class="text-sm font-medium">最後に成功したセレクタ:</p>
                    <ul
                      class="list-disc list-inside text-sm text-gray-600 dark:text-gray-400 mt-1"
                    >
                      {#each Object.entries(userConfigs[selectedDomain].last_successful_selectors || {}) as [key, value]}
                        <li>
                          {key}:
                          <code
                            class="text-xs bg-gray-100 dark:bg-gray-700 px-1 rounded"
                            >{value.selector}</code
                          >
                          <span class="text-xs text-gray-500"
                            >({value.date})</span
                          >
                        </li>
                      {/each}
                    </ul>
                  </div>
                {/if}
              </div>
            </div>
          {:else if selectedDomain}
            <div class="config-info">
              <h4 class="config-title">{selectedDomain}</h4>
              <p class="text-sm text-gray-600 dark:text-gray-400">
                デフォルト設定を使用しています
              </p>
            </div>
          {/if}
        </div>
      {:else}
        <p class="text-gray-600 dark:text-gray-400">対応サイトがありません</p>
      {/if}
    </div>

    <!-- ヒント -->
    <div class="hint-section">
      <h4 class="hint-title">💡 パーサー設定について</h4>
      <ul class="hint-list">
        <li>
          新規ダウンロード時は「デフォルトパーサーエンジン」で指定したエンジンが使用されます
        </li>
        <li>
          サイト構造が変更された場合、自動的に代替セレクタで解析を試みます
        </li>
        <li>成功したセレクタは自動記録され、次回から優先的に使用されます</li>
        <li>
          設定ファイルは <code>.narou/parsers/</code> 配下にあり、手動編集も可能です
        </li>
      </ul>
    </div>
  {/if}
</div>

<style>
  .parser-settings {
    max-width: 800px;
    margin: 0 auto;
    padding: 1rem;
  }

  .loading {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 3rem;
    gap: 1rem;
  }

  .spinner {
    width: 2rem;
    height: 2rem;
    border: 3px solid #e5e7eb;
    border-top-color: #3b82f6;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }

  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }

  .alert {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 1rem;
    margin-bottom: 1rem;
    border-radius: 0.5rem;
  }

  .alert svg {
    width: 1.5rem;
    height: 1.5rem;
    flex-shrink: 0;
  }

  .alert-error {
    background-color: #fee2e2;
    color: #b91c1c;
  }

  :global(.dark) .alert-error {
    background-color: #7f1d1d;
    color: #fecaca;
  }

  .alert-success {
    background-color: #d1fae5;
    color: #065f46;
  }

  :global(.dark) .alert-success {
    background-color: #064e3b;
    color: #a7f3d0;
  }

  .setting-section {
    margin-bottom: 2rem;
    padding: 1.5rem;
    background-color: #ffffff;
    border-radius: 0.5rem;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
  }

  :global(.dark) .setting-section {
    background-color: #1f2937;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.3);
  }

  .section-title {
    font-size: 1.25rem;
    font-weight: 600;
    margin-bottom: 0.5rem;
    color: #111827;
  }

  :global(.dark) .section-title {
    color: #f9fafb;
  }

  .section-description {
    font-size: 0.875rem;
    color: #6b7280;
    margin-bottom: 1rem;
  }

  :global(.dark) .section-description {
    color: #9ca3af;
  }

  .engine-selector {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  .radio-label {
    display: flex;
    align-items: flex-start;
    gap: 0.75rem;
    padding: 1rem;
    border: 2px solid #e5e7eb;
    border-radius: 0.5rem;
    cursor: pointer;
    transition: all 0.2s;
  }

  .radio-label:hover {
    border-color: #3b82f6;
    background-color: #eff6ff;
  }

  :global(.dark) .radio-label {
    border-color: #374151;
  }

  :global(.dark) .radio-label:hover {
    border-color: #3b82f6;
    background-color: #1e3a8a;
  }

  .radio-label input[type="radio"] {
    margin-top: 0.25rem;
    width: 1.25rem;
    height: 1.25rem;
    flex-shrink: 0;
  }

  .radio-content {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
  }

  .radio-title {
    font-weight: 600;
    color: #111827;
  }

  :global(.dark) .radio-title {
    color: #f9fafb;
  }

  .radio-description {
    font-size: 0.875rem;
    color: #6b7280;
  }

  :global(.dark) .radio-description {
    color: #9ca3af;
  }

  .domain-list {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  .domain-select {
    padding: 0.5rem;
    border: 1px solid #d1d5db;
    border-radius: 0.375rem;
    background-color: #ffffff;
    font-size: 0.875rem;
  }

  :global(.dark) .domain-select {
    background-color: #374151;
    border-color: #4b5563;
    color: #f9fafb;
  }

  .config-info {
    padding: 1rem;
    background-color: #f9fafb;
    border-radius: 0.375rem;
  }

  :global(.dark) .config-info {
    background-color: #111827;
  }

  .config-title {
    font-weight: 600;
    margin-bottom: 0.5rem;
    color: #111827;
  }

  :global(.dark) .config-title {
    color: #f9fafb;
  }

  .config-details code {
    font-family: "Courier New", monospace;
  }

  .hint-section {
    padding: 1rem;
    background-color: #eff6ff;
    border-left: 4px solid #3b82f6;
    border-radius: 0.375rem;
  }

  :global(.dark) .hint-section {
    background-color: #1e3a8a;
    border-left-color: #60a5fa;
  }

  .hint-title {
    font-weight: 600;
    margin-bottom: 0.5rem;
    color: #1e40af;
  }

  :global(.dark) .hint-title {
    color: #93c5fd;
  }

  .hint-list {
    margin-left: 1.5rem;
    color: #1e40af;
    font-size: 0.875rem;
  }

  :global(.dark) .hint-list {
    color: #bfdbfe;
  }

  .hint-list li {
    margin-bottom: 0.5rem;
  }

  .hint-list code {
    background-color: #dbeafe;
    padding: 0.125rem 0.375rem;
    border-radius: 0.25rem;
    font-family: "Courier New", monospace;
    font-size: 0.8125rem;
  }

  :global(.dark) .hint-list code {
    background-color: #1e40af;
  }
</style>
