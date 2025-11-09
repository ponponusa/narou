<script lang="ts">
  /**
   * 設定画面コンポーネント
   * 
   * ローカル設定とグローバル設定を表示・編集
   */
  import { onMount } from 'svelte';
  import { 
    getSettings, 
    getSettingVariables, 
    updateSettings,
    type SettingsData,
    type SettingVariablesData,
    type SettingVariable
  } from '../lib/api';

  // 状態管理
  let loading = $state(true);
  let saving = $state(false);
  let error = $state<string | null>(null);
  let successMessage = $state<string | null>(null);
  
  let settingsData = $state<SettingsData | null>(null);
  let variablesData = $state<SettingVariablesData | null>(null);
  
  let currentTab = $state<string>('general');
  
  // 編集中の設定値を保持（local/global両方）
  let editedValues = $state<{ local: Record<string, string | boolean | number | null>, global: Record<string, string | boolean | number | null> }>({ local: {}, global: {} });
  let hasChanges = $state(false);

  // 利用可能なタブ一覧（リアクティブ）
  let availableTabs = $derived.by(() => {
    if (!variablesData) return [];
    
    const tabSet = new Set<string>();
    
    // local と global 両方のvariablesからタブを収集
    ['local', 'global'].forEach(scope => {
      const variables = variablesData.variables[scope as 'local' | 'global'];
      if (variables) {
        Object.values(variables).forEach(variable => {
          // invisibleチェックを削除 - すべてのタブを表示
          if (variable.tab) {
            tabSet.add(variable.tab);
          }
        });
      }
    });
    
    console.log('Available tabs:', Array.from(tabSet).sort());
    
    // タブを指定の順番でソート
    const tabOrder = ['general', 'detail', 'webui', 'global', 'default', 'force', 'command'];
    return Array.from(tabSet).sort((a, b) => {
      const indexA = tabOrder.indexOf(a);
      const indexB = tabOrder.indexOf(b);
      if (indexA === -1 && indexB === -1) return a.localeCompare(b);
      if (indexA === -1) return 1;
      if (indexB === -1) return -1;
      return indexA - indexB;
    });
  });

  // 現在のタブで表示する設定項目（リアクティブ）
  let settingsForCurrentTab = $derived.by(() => {
    if (!variablesData || !settingsData) return [];
    
    const result: Array<[string, SettingVariable, 'local' | 'global']> = [];
    
    // localとglobal両方のスコープから、現在のタブに該当する設定を収集
    (['local', 'global'] as const).forEach(scope => {
      const variables = variablesData.variables[scope];
      if (!variables) return;
      
      Object.entries(variables).forEach(([key, variable]) => {
        // invisibleチェックを削除 - タブがあれば表示
        // タブが指定されていない場合は general に表示
        const tab = variable.tab || 'general';
        if (tab === currentTab) {
          result.push([key, variable, scope]);
        }
      });
    });
    
    // アルファベット順にソート
    result.sort((a, b) => a[0].localeCompare(b[0]));
    
    console.log(`Settings for tab "${currentTab}":`, result.length, 'items', 
      `(local: ${result.filter(r => r[2] === 'local').length}, global: ${result.filter(r => r[2] === 'global').length})`);
    
    return result;
  });

  /**
   * 設定データの読み込み
   */
  async function loadSettings() {
    loading = true;
    error = null;
    
    try {
      const [settings, variables] = await Promise.all([
        getSettings(),
        getSettingVariables()
      ]);
      
      settingsData = settings;
      variablesData = variables;
      
      console.log('=== Settings loaded ===');
      console.log('Local settings count:', Object.keys(settings.local).length);
      console.log('Global settings count:', Object.keys(settings.global).length);
      console.log('Local variables count:', Object.keys(variables.variables.local).length);
      console.log('Global variables count:', Object.keys(variables.variables.global).length);
      console.log('Tab names:', variables.tab_names);
      
      // タブの集計をデバッグ（invisibleも含める）
      const tabDebug = { local: {}, global: {} };
      Object.entries(variables.variables.local).forEach(([key, variable]) => {
        if (variable.tab) {
          tabDebug.local[variable.tab] = (tabDebug.local[variable.tab] || 0) + 1;
        }
      });
      Object.entries(variables.variables.global).forEach(([key, variable]) => {
        if (variable.tab) {
          tabDebug.global[variable.tab] = (tabDebug.global[variable.tab] || 0) + 1;
        }
      });
      console.log('Tab distribution (local):', tabDebug.local);
      console.log('Tab distribution (global):', tabDebug.global);
      
      // 初期タブを general に設定
      currentTab = 'general';
      
      console.log('Current tab set to:', currentTab);
      console.log('=== End Settings loaded ===');
      
      // 編集中の値を初期化
      initEditedValues();
      
      console.log('Edited values initialized:', {
        local: Object.keys(editedValues.local).length,
        global: Object.keys(editedValues.global).length
      }, 'items');
      
      // availableTabsを確認するために少し待つ
      setTimeout(() => {
        console.log('Available tabs after mount:', availableTabs);
      }, 100);
      
    } catch (e) {
      error = e instanceof Error ? e.message : '設定の読み込みに失敗しました';
      console.error('Failed to load settings:', e);
    } finally {
      loading = false;
    }
  }

  /**
   * 編集中の値を初期化（local/global両方）
   */
  function initEditedValues() {
    if (!settingsData || !variablesData) return;
    
    editedValues = { local: {}, global: {} };
    
    // local と global 両方の設定を初期化
    ['local', 'global'].forEach(scope => {
      const variables = variablesData.variables[scope as 'local' | 'global'];
      const scopeSettings = settingsData[scope as 'local' | 'global'];
      
      Object.keys(variables).forEach((key) => {
        // 設定値があればそれを使用、なければnull
        editedValues[scope as 'local' | 'global'][key] = scopeSettings[key]?.value ?? null;
      });
    });
    
    hasChanges = false;
  }

  /**
   * 値の変更を追跡
   */
  function handleValueChange(key: string, value: string | boolean | number | null, scope: 'local' | 'global') {
    editedValues[scope][key] = value;
    checkChanges();
  }

  /**
   * 変更があるかチェック
   */
  function checkChanges() {
    if (!settingsData || !variablesData) {
      hasChanges = false;
      return;
    }
    
    // local と global 両方をチェック
    hasChanges = ['local', 'global'].some(scope => {
      const scopeSettings = settingsData[scope as 'local' | 'global'];
      return Object.keys(editedValues[scope as 'local' | 'global']).some(key => {
        const originalValue = scopeSettings[key]?.value ?? null;
        return editedValues[scope as 'local' | 'global'][key] !== originalValue;
      });
    });
  }

  /**
   * 設定を保存
   */
  async function saveSettings() {
    if (!hasChanges || !settingsData || !variablesData) return;
    
    saving = true;
    error = null;
    successMessage = null;
    
    try {
      // 変更された値のみを抽出（local/global両方）
      const changedSettings: Record<string, string | boolean | number | null> = {};
      
      ['local', 'global'].forEach(scope => {
        const scopeSettings = settingsData[scope as 'local' | 'global'];
        
        Object.entries(editedValues[scope as 'local' | 'global']).forEach(([key, value]) => {
          const originalValue = scopeSettings[key]?.value ?? null;
          if (value !== originalValue) {
            changedSettings[key] = value;
          }
        });
      });
      
      const result = await updateSettings(changedSettings);
      
      successMessage = `${result.updated_count}件の設定を更新しました`;
      
      // データを再読み込み
      await loadSettings();
      
      // 3秒後にメッセージを消す
      setTimeout(() => {
        successMessage = null;
      }, 3000);
      
    } catch (e) {
      error = e instanceof Error ? e.message : '設定の保存に失敗しました';
      console.error('Failed to save settings:', e);
    } finally {
      saving = false;
    }
  }

  /**
   * タブを切り替え
   */
  function switchTab(tab: string) {
    currentTab = tab;
  }

  /**
   * 変更を破棄
   */
  function discardChanges() {
    initEditedValues();
  }

  /**
   * タブ名を取得
   */
  function getTabLabel(tab: string): string {
    if (!variablesData?.tab_names) return tab;
    return variablesData.tab_names[tab] || tab;
  }

  /**
   * helpテキストからデフォルト値を抽出
   */
  function extractDefaultFromHelp(help: string | undefined): string | null {
    if (!help) return null;
    
    // "デフォルト○○" または "デフォルトは○○" のパターンを探す
    const patterns = [
      /デフォルト(?:は)?([0-9.]+)/,
      /デフォルト(?:は)?"([^"]+)"/,
      /初期値(?:は)?([0-9.]+)/,
    ];
    
    for (const pattern of patterns) {
      const match = help.match(pattern);
      if (match) {
        return match[1];
      }
    }
    
    return null;
  }

  /**
   * 数値入力のmin値を取得
   */
  function getMinValue(key: string, variable: SettingVariable): number | undefined {
    if (key === 'update.interval') {
      return 2.5; // Update::Interval::MIN
    }
    return undefined;
  }

  /**
   * 数値入力のプレースホルダーを取得
   */
  function getNumberPlaceholder(variable: SettingVariable): string {
    const defaultValue = extractDefaultFromHelp(variable.help);
    return defaultValue || '0';
  }

  /**
   * マルチプル選択のsize属性を取得
   */
  function getMultipleSelectSize(variable: SettingVariable): number {
    const optionCount = variable.select_keys?.length || 5;
    return Math.min(optionCount, 10); // 最大10行
  }

  onMount(() => {
    loadSettings();
  });
</script>

<div class="settings-container">
  {#if loading}
    <div class="text-center py-12">
      <div class="inline-block animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
      <p class="mt-4 text-gray-600">設定を読み込み中...</p>
    </div>
  {:else if error}
    <div class="bg-red-50 border border-red-200 rounded-lg p-4 mb-4">
      <p class="text-red-800">{error}</p>
      <button 
        onclick={() => loadSettings()} 
        class="mt-2 px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700"
      >
        再試行
      </button>
    </div>
  {:else if settingsData && variablesData}
    <!-- ヘッダー -->
    <div class="mb-6">
      <h1 class="text-3xl font-bold text-gray-900 dark:text-gray-100 mb-2">設定</h1>
      <p class="text-gray-600 dark:text-gray-400">Narouの動作設定を変更できます</p>
    </div>

    <!-- タブ切り替え -->
    {#if availableTabs.length > 1}
      <div class="mb-6">
        <div class="flex flex-wrap gap-2">
          {#each availableTabs as tab}
            <button
              onclick={() => switchTab(tab)}
              class="px-4 py-2 rounded-lg text-sm font-medium transition-colors {currentTab === tab ? 'bg-blue-600 text-white' : 'bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-600'}"
            >
              {getTabLabel(tab)}
            </button>
          {/each}
        </div>
      </div>
    {/if}

    <!-- 成功メッセージ -->
    {#if successMessage}
      <div class="bg-green-50 dark:bg-green-900/30 border border-green-200 dark:border-green-800 rounded-lg p-4 mb-4">
        <p class="text-green-800 dark:text-green-200">{successMessage}</p>
      </div>
    {/if}

    <!-- 設定フォーム -->
    <div class="bg-white dark:bg-gray-800 rounded-lg shadow-sm border border-gray-200 dark:border-gray-700 p-6">
      <div class="space-y-6">
        {#each settingsForCurrentTab as [key, variable, scope]}
          {@const currentValue = editedValues[scope][key]}
          
          <div class="setting-item">
            <div class="setting-row">
              <div class="setting-label">
                <span class="text-sm font-medium text-gray-900 dark:text-gray-100">{key}</span>
                {#if scope === 'global'}
                  <span class="ml-2 px-2 py-0.5 text-xs bg-purple-100 dark:bg-purple-900 text-purple-800 dark:text-purple-200 rounded">Global</span>
                {/if}
                {#if variable.help}
                  <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">{variable.help}</p>
                {/if}
              </div>
              <div class="setting-value">

              {#if variable.type === 'boolean'}
                <!-- boolean型: force.*/default.*は3択トグル、それ以外は2択トグル -->
                {#if key.startsWith('force.') || key.startsWith('default.')}
                  <!-- 3択トグルスイッチ（未設定/いいえ/はい） -->
                  <div class="toggle-3way">
                    <input
                      type="radio"
                      id="{key}-null"
                      name={key}
                      checked={currentValue === null}
                      onchange={() => handleValueChange(key, null, scope)}
                    />
                    <label for="{key}-null">未設定</label>
                    
                    <input
                      type="radio"
                      id="{key}-false"
                      name={key}
                      checked={currentValue === false}
                      onchange={() => handleValueChange(key, false, scope)}
                    />
                    <label for="{key}-false">いいえ</label>
                    
                    <input
                      type="radio"
                      id="{key}-true"
                      name={key}
                      checked={currentValue === true}
                      onchange={() => handleValueChange(key, true, scope)}
                    />
                    <label for="{key}-true">はい</label>
                  </div>
                {:else}
                  <!-- 2択トグルスイッチ（セグメント型） -->
                  <div class="toggle-2way">
                    <input
                      type="radio"
                      id="{key}-false"
                      name={key}
                      checked={currentValue === false || currentValue === null}
                      onchange={() => handleValueChange(key, false, scope)}
                    />
                    <label for="{key}-false">いいえ</label>
                    
                    <input
                      type="radio"
                      id="{key}-true"
                      name={key}
                      checked={currentValue === true}
                      onchange={() => handleValueChange(key, true, scope)}
                    />
                    <label for="{key}-true">はい</label>
                  </div>
                {/if}
              {:else if variable.type === 'select'}
                <!-- セレクトボックス -->
                <select
                  value={currentValue?.toString() || ''}
                  onchange={(e) => handleValueChange(key, e.currentTarget.value, scope)}
                  class="select-field"
                >
                  <option value="">未設定</option>
                  {#if variable.select_keys && variable.select_summaries}
                    {#each variable.select_keys as selectKey, i}
                      <option value={selectKey}>
                        {variable.select_summaries[i] || selectKey}
                      </option>
                    {/each}
                  {/if}
                </select>
              {:else if variable.type === 'multiple'}
                <!-- 複数選択セレクトボックス -->
                <select
                  multiple
                  value={currentValue ? currentValue.toString().split(',') : []}
                  onchange={(e) => {
                    const selected = Array.from(e.currentTarget.selectedOptions).map(o => o.value);
                    handleValueChange(key, selected.length > 0 ? selected.join(',') : null, scope);
                  }}
                  class="select-field-multiple"
                  size={getMultipleSelectSize(variable)}
                >
                  {#if variable.select_keys && variable.select_summaries}
                    {#each variable.select_keys as selectKey, i}
                      <option value={selectKey}>
                        {variable.select_summaries[i] || selectKey}
                      </option>
                    {/each}
                  {/if}
                </select>
                <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">Ctrl/Cmdキーを押しながらクリックで複数選択</p>
              {:else if variable.type === 'float' || variable.type === 'integer'}
                <!-- 数値入力 -->
                <input
                  type="number"
                  value={currentValue?.toString() || ''}
                  placeholder={getNumberPlaceholder(variable)}
                  min={getMinValue(key, variable)}
                  step={variable.type === 'float' ? '0.1' : '1'}
                  oninput={(e) => {
                    const val = e.currentTarget.value;
                    const numVal = val === '' ? null : (variable.type === 'float' ? parseFloat(val) : parseInt(val));
                    
                    // update.intervalの最小値チェック
                    if (key === 'update.interval' && numVal !== null && numVal < 2.5) {
                      e.currentTarget.value = '2.5';
                      handleValueChange(key, 2.5, scope);
                      return;
                    }
                    
                    handleValueChange(key, numVal, scope);
                  }}
                  class="input-field"
                />
              {:else}
                <!-- テキスト入力 -->
                <input
                  type="text"
                  value={currentValue?.toString() || ''}
                  placeholder={currentValue === null ? 'null' : currentValue === '' ? '未入力' : ''}
                  oninput={(e) => handleValueChange(key, e.currentTarget.value || null, scope)}
                  class="input-field"
                />
              {/if}
              </div>
            </div>
          </div>
        {/each}

        {#if settingsForCurrentTab.length === 0}
          <p class="text-center text-gray-500 py-8">このタブに設定項目はありません</p>
        {/if}
      </div>
    </div>

    <!-- 保存ボタン -->
    {#if hasChanges}
      <div class="mt-6 flex gap-4 justify-end">
        <button
          onclick={discardChanges}
          disabled={saving}
          class="px-4 py-2 border border-gray-300 rounded-lg text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          変更を破棄
        </button>
        <button
          onclick={saveSettings}
          disabled={saving}
          class="px-4 py-2 bg-blue-600 text-white rounded-lg text-sm font-medium hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
        >
          {#if saving}
            <div class="inline-block animate-spin rounded-full h-4 w-4 border-b-2 border-white"></div>
            保存中...
          {:else}
            変更を保存
          {/if}
        </button>
      </div>
    {/if}
  {/if}
</div>

<style>
  .settings-container {
    max-width: 1200px;
    margin: 0 auto;
  }

  .setting-item {
    padding-bottom: 1.5rem;
    border-bottom: 1px solid #e5e7eb;
  }

  :global(.dark) .setting-item {
    border-bottom-color: #374151;
  }

  .setting-item:last-child {
    border-bottom: none;
    padding-bottom: 0;
  }

  /* レスポンシブレイアウト: 項目名と設定値を横並びに */
  .setting-row {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  @media (min-width: 768px) {
    .setting-row {
      flex-direction: row;
      align-items: flex-start;
      gap: 2rem;
    }

    .setting-label {
      flex: 1;
      min-width: 0;
    }

    .setting-value {
      flex: 0 0 auto;
      width: 220px;
    }
  }

  /* テキストフィールドのスタイル */
  .input-field {
    display: block;
    width: 100%;
    padding: 0.5rem 0.75rem;
    line-height: 1.75;
    border: 1px solid #d1d5db;
    border-radius: 0.375rem;
    font-size: 0.875rem;
    background-color: white;
    color: #111827;
    transition: border-color 0.15s, box-shadow 0.15s;
  }

  .input-field::placeholder {
    color: #9ca3af;
    font-style: italic;
  }

  :global(.dark) .input-field {
    background-color: #1f2937;
    border-color: #4b5563;
    color: #f9fafb;
  }

  :global(.dark) .input-field::placeholder {
    color: #6b7280;
  }

  .input-field:focus {
    outline: none;
    border-color: #3b82f6;
    box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
  }

  /* セレクトボックスのスタイル（3択トグルと同様） */
  .select-field {
    display: block;
    width: 100%;
    padding: 0.5rem 0.75rem;
    line-height: 1.75;
    border: 1px solid #d1d5db;
    border-radius: 0.375rem;
    font-size: 0.875rem;
    font-weight: 500;
    background-color: #f1f5f9;
    color: #1f2937;
    transition: all 0.2s;
    cursor: pointer;
  }

  :global(.dark) .select-field {
    background-color: #374151;
    border-color: #4b5563;
    color: #f9fafb;
  }

  .select-field:hover {
    background-color: #e2e8f0;
  }

  :global(.dark) .select-field:hover {
    background-color: #4b5563;
  }

  .select-field:focus {
    outline: none;
    border-color: #3b82f6;
    box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
  }

  .select-field option {
    background-color: white;
    color: #1f2937;
    padding: 0.5rem;
  }

  :global(.dark) .select-field option {
    background-color: #1f2937;
    color: #f9fafb;
  }

  /* 複数選択セレクトボックス */
  .select-field-multiple {
    display: block;
    width: 100%;
    padding: 0.5rem 0.75rem;
    line-height: 1.75;
    border: 1px solid #d1d5db;
    border-radius: 0.375rem;
    font-size: 0.875rem;
    background-color: #f1f5f9;
    color: #1f2937;
    transition: all 0.2s;
  }

  :global(.dark) .select-field-multiple {
    background-color: #374151;
    border-color: #4b5563;
    color: #f9fafb;
  }

  .select-field-multiple:focus {
    outline: none;
    border-color: #3b82f6;
    box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
  }

  .select-field-multiple option {
    padding: 0.5rem;
  }

  .select-field-multiple option:checked {
    background-color: #3b82f6;
    color: white;
  }

  /* 2択トグルスイッチ - 3択と同じセグメント型に変更 */
  .toggle-2way {
    display: inline-flex;
    background-color: #f1f5f9;
    border-radius: 0.5rem;
    padding: 0.25rem;
  }

  :global(.dark) .toggle-2way {
    background-color: #374151;
  }

  .toggle-2way label {
    padding: 0.5rem 1rem;
    cursor: pointer;
    border-radius: 0.375rem;
    transition: all 0.2s;
    font-size: 0.875rem;
    font-weight: 500;
    color: #1f2937;
  }

  :global(.dark) .toggle-2way label {
    color: #f9fafb;
  }

  .toggle-2way input[type="radio"] {
    display: none;
  }

  .toggle-2way input[type="radio"]:checked + label {
    background-color: white;
    color: #2563eb;
    box-shadow: 0 1px 3px 0 rgb(0 0 0 / 0.1);
  }

  :global(.dark) .toggle-2way input[type="radio"]:checked + label {
    background-color: #4b5563;
    color: #60a5fa;
  }

  .toggle-2way label:hover {
    background-color: #e2e8f0;
  }

  :global(.dark) .toggle-2way label:hover {
    background-color: #4b5563;
  }

  .toggle-2way input[type="radio"]:checked + label:hover {
    background-color: white;
  }

  :global(.dark) .toggle-2way input[type="radio"]:checked + label:hover {
    background-color: #4b5563;
  }

  /* 3択トグルスイッチ - 文字色を修正 */
  .toggle-3way {
    display: inline-flex;
    background-color: #f1f5f9;
    border-radius: 0.5rem;
    padding: 0.25rem;
  }

  :global(.dark) .toggle-3way {
    background-color: #374151;
  }

  .toggle-3way label {
    padding: 0.5rem 1rem;
    cursor: pointer;
    border-radius: 0.375rem;
    transition: all 0.2s;
    font-size: 0.875rem;
    font-weight: 500;
    color: #1f2937; /* グレー背景でも見えるように濃い色に */
  }

  :global(.dark) .toggle-3way label {
    color: #f9fafb;
  }

  .toggle-3way input[type="radio"] {
    display: none;
  }

  .toggle-3way input[type="radio"]:checked + label {
    background-color: white;
    color: #2563eb;
    box-shadow: 0 1px 3px 0 rgb(0 0 0 / 0.1);
  }

  :global(.dark) .toggle-3way input[type="radio"]:checked + label {
    background-color: #4b5563;
    color: #60a5fa;
  }

  .toggle-3way label:hover {
    background-color: #e2e8f0;
  }

  :global(.dark) .toggle-3way label:hover {
    background-color: #4b5563;
  }

  .toggle-3way input[type="radio"]:checked + label:hover {
    background-color: white;
  }

  :global(.dark) .toggle-3way input[type="radio"]:checked + label:hover {
    background-color: #4b5563;
  }
</style>
