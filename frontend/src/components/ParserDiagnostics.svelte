<script lang="ts">
  /**
   * パーサー診断ツールコンポーネント
   *
   * パーサーのトラブルシューティングと履歴表示を提供
   */
  import { getParserDiagnostics } from "../lib/api";

  interface SelectorHistoryEntry {
    selector: string;
    first_success: string;
    last_success: string;
    success_count: number;
    detected_change?: string;
    replaced_selector?: string;
  }

  interface VersionDetails {
    version: string;
    name: string;
    patterns: {
      body_pattern: string;
      introduction_pattern: string;
      postscript_pattern: string;
    };
  }

  interface Novel {
    id: string;
    title: string;
    last_update: number;
    parser_engine: string;
  }

  interface ChangeLogEntry {
    timestamp: string;
    selector_key?: string;
    pattern_key?: string;
    old_selector?: string;
    new_selector?: string;
    old_version?: string;
    new_version?: string;
    detection_type: string;
    engine: string;
  }

  interface DiagnosticsData {
    domain: string;
    engine: string;
    selector_history?: Record<string, SelectorHistoryEntry[]>;
    selector_coverage?: Record<string, SelectorHistoryEntry[]>;
    version_history?: string[];
    version_details?: Record<string, VersionDetails>;
    novels: Novel[];
    change_log: ChangeLogEntry[];
  }

  let domain = $state("");
  let engine = $state<"nokogiri" | "legacy">("nokogiri");
  let loading = $state(false);
  let error = $state<string | null>(null);
  let diagnosticsData = $state<DiagnosticsData | null>(null);
  let selectedSelectorKey = $state<string>("");

  $effect(() => {
    // エンジン切り替え時にセレクタキーをリセット
    if (diagnosticsData) {
      if (engine === "nokogiri" && diagnosticsData.selector_history) {
        const keys = Object.keys(diagnosticsData.selector_history);
        selectedSelectorKey = keys.length > 0 ? keys[0] : "";
      }
    }
  });

  async function loadDiagnostics() {
    if (!domain.trim()) {
      error = "ドメインを入力してください";
      return;
    }

    loading = true;
    error = null;
    diagnosticsData = null;

    try {
      const data = await getParserDiagnostics(domain.trim(), engine);
      diagnosticsData = data;

      // 初期セレクタキーを設定
      if (
        engine === "nokogiri" &&
        data.selector_history &&
        Object.keys(data.selector_history).length > 0
      ) {
        selectedSelectorKey = Object.keys(data.selector_history)[0];
      }
    } catch (e) {
      error = e instanceof Error ? e.message : "診断情報の取得に失敗しました";
      console.error("Failed to load diagnostics:", e);
    } finally {
      loading = false;
    }
  }

  function formatDate(dateStr: string): string {
    if (!dateStr) return "不明";
    return dateStr;
  }

  function getGenerationNumber(
    entries: SelectorHistoryEntry[],
    entry: SelectorHistoryEntry
  ): number {
    return entries.length - entries.indexOf(entry);
  }
</script>

<div class="diagnostics-container">
  <h2 class="page-title">パーサー診断ツール</h2>
  <p class="page-description">
    パーサーの動作履歴とトラブルシューティング情報を表示します
  </p>

  <!-- 入力フォーム -->
  <div class="input-section">
    <div class="input-group">
      <label for="domain-input">ドメイン</label>
      <div class="input-row">
        <input
          id="domain-input"
          type="text"
          bind:value={domain}
          placeholder="ncode.syosetu.com"
          class="domain-input"
          disabled={loading}
        />
        <button
          onclick={loadDiagnostics}
          disabled={loading || !domain.trim()}
          class="btn-primary"
        >
          {#if loading}
            <div class="spinner-small"></div>
            診断中...
          {:else}
            🔍 診断実行
          {/if}
        </button>
      </div>
    </div>

    <!-- エンジン選択 -->
    <div class="engine-selector">
      <button
        class="engine-btn"
        class:active={engine === "nokogiri"}
        onclick={() => (engine = "nokogiri")}
        disabled={loading}
      >
        Nokogiri (新パーサー)
      </button>
      <button
        class="engine-btn"
        class:active={engine === "legacy"}
        onclick={() => (engine = "legacy")}
        disabled={loading}
      >
        Legacy (レガシー)
      </button>
    </div>
  </div>

  <!-- エラー表示 -->
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

  <!-- 診断結果表示 -->
  {#if diagnosticsData}
    <div class="results-container">
      <!-- 対象小説リスト -->
      {#if diagnosticsData.novels.length > 0}
        <section class="result-section">
          <h3 class="section-title">
            対象小説 ({diagnosticsData.novels.length})
          </h3>
          <div class="novels-grid">
            {#each diagnosticsData.novels as novel}
              <div class="novel-card">
                <div class="novel-title">{novel.title}</div>
                <div class="novel-meta">
                  <span class="novel-id">ID: {novel.id}</span>
                  <span class="novel-engine"
                    >エンジン: {novel.parser_engine}</span
                  >
                </div>
              </div>
            {/each}
          </div>
        </section>
      {:else}
        <div class="alert alert-info">
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
              d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
          <span>このドメインの小説は登録されていません</span>
        </div>
      {/if}

      {#if engine === "nokogiri"}
        <!-- Nokogiri: セレクタ履歴タイムライン -->
        {#if diagnosticsData.selector_history && Object.keys(diagnosticsData.selector_history).length > 0}
          <section class="result-section">
            <h3 class="section-title">セレクタ履歴タイムライン</h3>

            <!-- セレクタタブ -->
            <div class="selector-tabs">
              {#each Object.keys(diagnosticsData.selector_history) as key}
                <button
                  class="selector-tab"
                  class:active={selectedSelectorKey === key}
                  onclick={() => (selectedSelectorKey = key)}
                >
                  {key}
                </button>
              {/each}
            </div>

            <!-- タイムライン -->
            {#if selectedSelectorKey && diagnosticsData.selector_history[selectedSelectorKey]}
              <div class="timeline">
                {#each diagnosticsData.selector_history[selectedSelectorKey] as entry, index}
                  {@const generation = getGenerationNumber(
                    diagnosticsData.selector_history[selectedSelectorKey],
                    entry
                  )}
                  <div class="timeline-entry">
                    <div class="timeline-marker">第{generation}世代</div>
                    <div class="timeline-content">
                      <code class="selector-code">{entry.selector}</code>
                      <div class="timeline-meta">
                        <p>
                          📅 適用期間: {formatDate(entry.first_success)} 〜 {formatDate(
                            entry.last_success
                          )}
                        </p>
                        <p>✅ 成功回数: {entry.success_count}回</p>
                        {#if entry.detected_change && entry.replaced_selector}
                          <p class="change-detected">
                            🔄 変更検出: {formatDate(entry.detected_change)}
                          </p>
                          <p class="replaced-selector">
                            旧セレクタ:
                            <code>{entry.replaced_selector}</code>
                          </p>
                        {/if}
                      </div>
                    </div>
                  </div>
                {/each}
              </div>
            {/if}
          </section>
        {:else}
          <div class="alert alert-info">
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
                d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            <span>セレクタ履歴がまだ記録されていません</span>
          </div>
        {/if}
      {:else}
        <!-- Legacy: バージョン履歴タイムライン -->
        {#if diagnosticsData.version_history && diagnosticsData.version_history.length > 0}
          <section class="result-section">
            <h3 class="section-title">
              バージョン履歴 ({diagnosticsData.version_history.length} バージョン)
            </h3>

            <div class="timeline">
              {#each diagnosticsData.version_history as version}
                {@const details = diagnosticsData.version_details?.[version]}
                <div class="timeline-entry">
                  <div class="timeline-marker">v{version}</div>
                  <div class="timeline-content">
                    {#if details}
                      <h4 class="version-name">{details.name}</h4>
                      <details class="pattern-details">
                        <summary>正規表現パターンを表示</summary>
                        <div class="patterns-container">
                          {#if details.patterns.body_pattern}
                            <div class="pattern-item">
                              <strong>本文パターン:</strong>
                              <pre><code>{details.patterns.body_pattern}</code
                                ></pre>
                            </div>
                          {/if}
                          {#if details.patterns.introduction_pattern}
                            <div class="pattern-item">
                              <strong>前書きパターン:</strong>
                              <pre><code
                                  >{details.patterns.introduction_pattern}</code
                                ></pre>
                            </div>
                          {/if}
                          {#if details.patterns.postscript_pattern}
                            <div class="pattern-item">
                              <strong>後書きパターン:</strong>
                              <pre><code
                                  >{details.patterns.postscript_pattern}</code
                                ></pre>
                            </div>
                          {/if}
                        </div>
                      </details>
                    {:else}
                      <p class="text-gray-600 dark:text-gray-400">
                        詳細情報を取得できません
                      </p>
                    {/if}
                  </div>
                </div>
              {/each}
            </div>
          </section>
        {:else}
          <div class="alert alert-info">
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
                d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            <span>アーカイブされたバージョンがありません</span>
          </div>
        {/if}
      {/if}

      <!-- 変更ログ -->
      {#if diagnosticsData.change_log && diagnosticsData.change_log.length > 0}
        <section class="result-section">
          <h3 class="section-title">
            変更ログ ({diagnosticsData.change_log.length})
          </h3>
          <div class="changelog-table-wrapper">
            <table class="changelog-table">
              <thead>
                <tr>
                  <th>日時</th>
                  <th>エンジン</th>
                  <th>種別</th>
                  <th>変更内容</th>
                </tr>
              </thead>
              <tbody>
                {#each diagnosticsData.change_log as log}
                  <tr>
                    <td class="timestamp">{formatDate(log.timestamp)}</td>
                    <td class="engine-badge">
                      <span class="badge badge-{log.engine}">{log.engine}</span>
                    </td>
                    <td class="change-type">
                      {log.selector_key || log.pattern_key || "不明"}
                    </td>
                    <td class="change-content">
                      {#if log.engine === "nokogiri"}
                        <code class="old-value">{log.old_selector}</code>
                        <span class="arrow">→</span>
                        <code class="new-value">{log.new_selector}</code>
                      {:else}
                        v{log.old_version}
                        <span class="arrow">→</span>
                        v{log.new_version}
                      {/if}
                    </td>
                  </tr>
                {/each}
              </tbody>
            </table>
          </div>
        </section>
      {:else}
        <div class="alert alert-info">
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
              d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
          <span>変更ログはまだ記録されていません</span>
        </div>
      {/if}
    </div>
  {/if}
</div>

<style>
  .diagnostics-container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 1rem;
  }

  .page-title {
    font-size: 1.875rem;
    font-weight: 700;
    margin-bottom: 0.5rem;
    color: #111827;
  }

  :global(.dark) .page-title {
    color: #f9fafb;
  }

  .page-description {
    font-size: 0.875rem;
    color: #6b7280;
    margin-bottom: 1.5rem;
  }

  :global(.dark) .page-description {
    color: #9ca3af;
  }

  .input-section {
    background-color: #ffffff;
    padding: 1.5rem;
    border-radius: 0.5rem;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
    margin-bottom: 1.5rem;
  }

  :global(.dark) .input-section {
    background-color: #1f2937;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.3);
  }

  .input-group {
    margin-bottom: 1rem;
  }

  .input-group label {
    display: block;
    font-weight: 500;
    margin-bottom: 0.5rem;
    color: #374151;
  }

  :global(.dark) .input-group label {
    color: #d1d5db;
  }

  .input-row {
    display: flex;
    gap: 0.75rem;
  }

  .domain-input {
    flex: 1;
    padding: 0.5rem 0.75rem;
    border: 1px solid #d1d5db;
    border-radius: 0.375rem;
    font-size: 0.875rem;
    background-color: #ffffff;
  }

  :global(.dark) .domain-input {
    background-color: #374151;
    border-color: #4b5563;
    color: #f9fafb;
  }

  .domain-input:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .btn-primary {
    padding: 0.5rem 1rem;
    background-color: #3b82f6;
    color: white;
    border: none;
    border-radius: 0.375rem;
    font-weight: 500;
    cursor: pointer;
    display: flex;
    align-items: center;
    gap: 0.5rem;
    transition: background-color 0.2s;
  }

  .btn-primary:hover:not(:disabled) {
    background-color: #2563eb;
  }

  .btn-primary:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .spinner-small {
    width: 1rem;
    height: 1rem;
    border: 2px solid rgba(255, 255, 255, 0.3);
    border-top-color: white;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }

  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }

  .engine-selector {
    display: flex;
    gap: 0.5rem;
  }

  .engine-btn {
    flex: 1;
    padding: 0.75rem;
    border: 2px solid #e5e7eb;
    border-radius: 0.375rem;
    background-color: #ffffff;
    color: #6b7280;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.2s;
  }

  :global(.dark) .engine-btn {
    background-color: #374151;
    border-color: #4b5563;
    color: #9ca3af;
  }

  .engine-btn:hover:not(:disabled) {
    border-color: #3b82f6;
  }

  .engine-btn.active {
    background-color: #3b82f6;
    border-color: #3b82f6;
    color: white;
  }

  .engine-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
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

  .alert-info {
    background-color: #dbeafe;
    color: #1e40af;
  }

  :global(.dark) .alert-info {
    background-color: #1e3a8a;
    color: #bfdbfe;
  }

  .results-container {
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
  }

  .result-section {
    background-color: #ffffff;
    padding: 1.5rem;
    border-radius: 0.5rem;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
  }

  :global(.dark) .result-section {
    background-color: #1f2937;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.3);
  }

  .section-title {
    font-size: 1.25rem;
    font-weight: 600;
    margin-bottom: 1rem;
    color: #111827;
  }

  :global(.dark) .section-title {
    color: #f9fafb;
  }

  .novels-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
    gap: 1rem;
  }

  .novel-card {
    padding: 1rem;
    background-color: #f9fafb;
    border-radius: 0.375rem;
    border: 1px solid #e5e7eb;
  }

  :global(.dark) .novel-card {
    background-color: #111827;
    border-color: #374151;
  }

  .novel-title {
    font-weight: 600;
    margin-bottom: 0.5rem;
    color: #111827;
  }

  :global(.dark) .novel-title {
    color: #f9fafb;
  }

  .novel-meta {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    font-size: 0.75rem;
    color: #6b7280;
  }

  :global(.dark) .novel-meta {
    color: #9ca3af;
  }

  .selector-tabs {
    display: flex;
    gap: 0.5rem;
    margin-bottom: 1rem;
    flex-wrap: wrap;
  }

  .selector-tab {
    padding: 0.5rem 1rem;
    border: 1px solid #d1d5db;
    border-radius: 0.375rem;
    background-color: #ffffff;
    color: #6b7280;
    font-size: 0.875rem;
    cursor: pointer;
    transition: all 0.2s;
  }

  :global(.dark) .selector-tab {
    background-color: #374151;
    border-color: #4b5563;
    color: #9ca3af;
  }

  .selector-tab:hover {
    border-color: #3b82f6;
  }

  .selector-tab.active {
    background-color: #3b82f6;
    border-color: #3b82f6;
    color: white;
  }

  .timeline {
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
  }

  .timeline-entry {
    display: flex;
    gap: 1rem;
  }

  .timeline-marker {
    flex-shrink: 0;
    width: 80px;
    padding: 0.5rem;
    background-color: #3b82f6;
    color: white;
    border-radius: 0.375rem;
    text-align: center;
    font-weight: 600;
    font-size: 0.875rem;
    height: fit-content;
  }

  .timeline-content {
    flex: 1;
    padding: 1rem;
    background-color: #f9fafb;
    border-radius: 0.375rem;
    border-left: 3px solid #3b82f6;
  }

  :global(.dark) .timeline-content {
    background-color: #111827;
  }

  .selector-code {
    display: block;
    padding: 0.75rem;
    background-color: #1f2937;
    color: #22d3ee;
    border-radius: 0.375rem;
    font-family: "Courier New", monospace;
    font-size: 0.875rem;
    margin-bottom: 0.75rem;
    word-break: break-all;
  }

  :global(.dark) .selector-code {
    background-color: #0f172a;
  }

  .timeline-meta {
    font-size: 0.875rem;
    color: #6b7280;
  }

  :global(.dark) .timeline-meta {
    color: #9ca3af;
  }

  .timeline-meta p {
    margin-bottom: 0.25rem;
  }

  .change-detected {
    color: #ea580c;
    font-weight: 500;
  }

  :global(.dark) .change-detected {
    color: #fb923c;
  }

  .replaced-selector {
    font-size: 0.8125rem;
  }

  .replaced-selector code {
    background-color: #fee2e2;
    color: #991b1b;
    padding: 0.125rem 0.375rem;
    border-radius: 0.25rem;
  }

  :global(.dark) .replaced-selector code {
    background-color: #7f1d1d;
    color: #fca5a5;
  }

  .version-name {
    font-size: 1rem;
    font-weight: 600;
    margin-bottom: 0.5rem;
    color: #111827;
  }

  :global(.dark) .version-name {
    color: #f9fafb;
  }

  .pattern-details {
    margin-top: 0.5rem;
  }

  .pattern-details summary {
    cursor: pointer;
    font-weight: 500;
    color: #3b82f6;
    user-select: none;
  }

  .pattern-details summary:hover {
    text-decoration: underline;
  }

  .patterns-container {
    margin-top: 0.75rem;
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .pattern-item strong {
    display: block;
    margin-bottom: 0.25rem;
    color: #374151;
  }

  :global(.dark) .pattern-item strong {
    color: #d1d5db;
  }

  .pattern-item pre {
    margin: 0;
    padding: 0.75rem;
    background-color: #1f2937;
    border-radius: 0.375rem;
    overflow-x: auto;
  }

  :global(.dark) .pattern-item pre {
    background-color: #0f172a;
  }

  .pattern-item code {
    color: #22d3ee;
    font-family: "Courier New", monospace;
    font-size: 0.8125rem;
    white-space: pre-wrap;
    word-break: break-all;
  }

  .changelog-table-wrapper {
    overflow-x: auto;
  }

  .changelog-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.875rem;
  }

  .changelog-table thead {
    background-color: #f9fafb;
  }

  :global(.dark) .changelog-table thead {
    background-color: #111827;
  }

  .changelog-table th {
    padding: 0.75rem;
    text-align: left;
    font-weight: 600;
    color: #374151;
    border-bottom: 2px solid #e5e7eb;
  }

  :global(.dark) .changelog-table th {
    color: #d1d5db;
    border-bottom-color: #374151;
  }

  .changelog-table td {
    padding: 0.75rem;
    border-bottom: 1px solid #e5e7eb;
  }

  :global(.dark) .changelog-table td {
    border-bottom-color: #374151;
  }

  .changelog-table tr:hover {
    background-color: #f9fafb;
  }

  :global(.dark) .changelog-table tr:hover {
    background-color: #111827;
  }

  .timestamp {
    color: #6b7280;
    font-size: 0.8125rem;
  }

  :global(.dark) .timestamp {
    color: #9ca3af;
  }

  .badge {
    display: inline-block;
    padding: 0.25rem 0.5rem;
    border-radius: 0.25rem;
    font-size: 0.75rem;
    font-weight: 600;
  }

  .badge-nokogiri {
    background-color: #dbeafe;
    color: #1e40af;
  }

  :global(.dark) .badge-nokogiri {
    background-color: #1e3a8a;
    color: #bfdbfe;
  }

  .badge-legacy {
    background-color: #fef3c7;
    color: #92400e;
  }

  :global(.dark) .badge-legacy {
    background-color: #78350f;
    color: #fde68a;
  }

  .change-type {
    font-family: "Courier New", monospace;
    font-size: 0.8125rem;
    color: #6b7280;
  }

  :global(.dark) .change-type {
    color: #9ca3af;
  }

  .change-content {
    font-family: "Courier New", monospace;
    font-size: 0.8125rem;
  }

  .old-value {
    background-color: #fee2e2;
    color: #991b1b;
    padding: 0.125rem 0.375rem;
    border-radius: 0.25rem;
  }

  :global(.dark) .old-value {
    background-color: #7f1d1d;
    color: #fca5a5;
  }

  .new-value {
    background-color: #d1fae5;
    color: #065f46;
    padding: 0.125rem 0.375rem;
    border-radius: 0.25rem;
  }

  :global(.dark) .new-value {
    background-color: #064e3b;
    color: #a7f3d0;
  }

  .arrow {
    margin: 0 0.5rem;
    color: #6b7280;
  }

  :global(.dark) .arrow {
    color: #9ca3af;
  }
</style>
