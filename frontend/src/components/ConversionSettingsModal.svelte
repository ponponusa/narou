<script lang="ts">
  import { onMount } from 'svelte';
  import type { 
    NovelSettingsData, 
    NovelSettingItem, 
    NovelSettingsUpdateRequest,
    ReplacePattern 
  } from '../types/api';

	// ===========================================================================================
	// Constants and Bindings
	// ===========================================================================================
	const API_BASE_URL = 'http://localhost:5678/api/v2';  // Props
  let toast: { show: (message: string, type: 'success' | 'error' | 'info' | 'warning', duration?: number) => void } | null = null;

  // モーダル表示状態
  let showModal = $state(false);
  let novelId = $state<number | null>(null);
  let novelTitle = $state<string>('');
  let settings = $state<NovelSettingItem[]>([]);
  let replacePatterns = $state<ReplacePattern[]>([]);
  let loading = $state(false);
  let saving = $state(false);

  // モーダル要素の参照
  let modalElement: HTMLElement | null = null;

  // 設定値の作業用コピー
  let workingSettings = $state<Record<string, any>>({});

  /**
   * Toast参照を設定
   */
  export function setToast(toastInstance: any) {
    toast = toastInstance;
  }

  /**
   * モーダルを開く
   */
  export async function open(id: number, title: string, onSave?: () => void) {
    novelId = id;
    novelTitle = title;
    showModal = true;
    loading = true;

    try {
      // 設定データを取得
      const response = await fetch(`${API_BASE_URL}/novels/${id}/settings`);
      if (!response.ok) {
        throw new Error('設定の取得に失敗しました');
      }

      const result = await response.json();
      if (result.success && result.data) {
        const data: NovelSettingsData = result.data;
        settings = data.settings;
        
        // 置換パターンを変換
        replacePatterns = (data.replace_pattern || []).map(([left, right]) => ({
          left,
          right
        }));

        // 作業用設定オブジェクトを初期化
        workingSettings = {};
        settings.forEach(item => {
          workingSettings[item.name] = item.value;
        });
      } else {
        throw new Error(result.error || '設定の取得に失敗しました');
      }
    } catch (error) {
      console.error('Error loading settings:', error);
      toast?.show('設定の読み込みに失敗しました', 'error');
      closeModal();
    } finally {
      loading = false;
    }
  }

  /**
   * モーダルを閉じる
   */
  function closeModal() {
    showModal = false;
    novelId = null;
    novelTitle = '';
    settings = [];
    replacePatterns = [];
    workingSettings = {};
  }

  /**
   * 設定を保存
   */
  async function saveSettings() {
    if (!novelId) return;

    saving = true;

    try {
      const updateData: NovelSettingsUpdateRequest = {
        settings: workingSettings,
        replace_pattern: replacePatterns
      };

      const response = await fetch(`${API_BASE_URL}/novels/${novelId}/settings`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(updateData)
      });

      const result = await response.json();

      if (result.success) {
        toast?.show('設定を保存しました', 'success');
        closeModal();
      } else {
        throw new Error(result.error || '設定の保存に失敗しました');
      }
    } catch (error) {
      console.error('Error saving settings:', error);
      toast?.show('設定の保存に失敗しました', 'error');
    } finally {
      saving = false;
    }
  }

  /**
   * 置換パターンを追加
   */
  function addReplacePattern() {
    replacePatterns = [...replacePatterns, { left: '', right: '' }];
  }

  /**
   * 置換パターンを削除
   */
  function removeReplacePattern(index: number) {
    replacePatterns = replacePatterns.filter((_, i) => i !== index);
  }

  /**
   * 設定値の型に応じたHTMLを生成
   */
  function getSettingControl(item: NovelSettingItem): 'boolean' | 'select' | 'multiple' | 'text' {
    if (item.type === 'boolean') return 'boolean';
    if (item.type === 'select') return 'select';
    if (item.type === 'multiple') return 'multiple';
    return 'text';
  }

  /**
   * Boolean設定の値を文字列表現に変換
   */
  function getBooleanValueString(value: any): 'nil' | 'off' | 'on' {
    if (value === null || value === undefined) return 'nil';
    if (value === false) return 'off';
    return 'on';
  }

  /**
   * Boolean設定の値を設定
   */
  function setBooleanValue(name: string, strValue: 'nil' | 'off' | 'on') {
    if (strValue === 'nil') {
      workingSettings[name] = null;
    } else if (strValue === 'off') {
      workingSettings[name] = false;
    } else {
      workingSettings[name] = true;
    }
  }

  /**
   * デフォルト値の表示用文字列
   */
  function formatDefaultValue(value: any): string {
    if (value === null || value === undefined) return '未設定';
    if (typeof value === 'boolean') return value ? 'はい' : 'いいえ';
    return String(value);
  }

  onMount(() => {
    // ESCキーでモーダルを閉じる
    const handleKeydown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && showModal) {
        closeModal();
      }
    };
    window.addEventListener('keydown', handleKeydown);
    return () => window.removeEventListener('keydown', handleKeydown);
  });
</script>

{#if showModal}
  <!-- モーダルオーバーレイ -->
  <div 
    class="fixed inset-0 bg-black bg-opacity-50 flex items-start justify-center z-50 p-4 overflow-y-auto"
    onclick={(e) => e.target === e.currentTarget && closeModal()}
    bind:this={modalElement}
  >
    <!-- モーダルコンテンツ -->
    <div 
      class="bg-white dark:bg-gray-800 rounded-lg shadow-xl max-w-4xl w-full my-8"
      onclick={(e) => e.stopPropagation()}
    >
      <!-- ヘッダー -->
      <div class="flex items-center justify-between p-4 border-b border-gray-200 dark:border-gray-700">
        <h2 class="text-xl font-semibold text-gray-900 dark:text-white">
          {novelTitle} の変換設定
        </h2>
        <button
          onclick={closeModal}
          class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 transition-colors"
          aria-label="閉じる"
        >
          <i class="fas fa-times text-xl"></i>
        </button>
      </div>

      <!-- 本文 -->
      <div class="p-6 max-h-[70vh] overflow-y-auto">
        {#if loading}
          <div class="flex items-center justify-center py-12">
            <i class="fas fa-spinner fa-spin text-3xl text-gray-400"></i>
          </div>
        {:else}
          <!-- 説明 -->
          <div class="mb-6 p-4 bg-blue-50 dark:bg-blue-900/20 rounded-lg">
            <ul class="text-sm text-gray-700 dark:text-gray-300 space-y-1">
              <li>• この小説専用の変換時の設定を変更できます（setting.ini を書き換えます）</li>
              <li>• 変更を反映させるには再度変換を実行する必要があります</li>
              <li>• 未設定の項目は、変換時に共通設定が適用されます</li>
              <li>• 環境設定で force.* 系設定が有効な場合、ここでの該当項目は無視されます</li>
            </ul>
          </div>

          <!-- 設定項目 -->
          <div class="space-y-6">
            {#each settings as item (item.name)}
              <div class="setting-item {item.is_forced ? 'forced-item' : ''}">
                <div class="setting-row">
                  <div class="setting-label">
                    <span class="text-sm font-medium text-gray-900 dark:text-gray-100">{item.name}</span>
                    {#if item.is_forced}
                      <span class="ml-2 px-2 py-0.5 text-xs bg-yellow-100 dark:bg-yellow-900 text-yellow-800 dark:text-yellow-200 rounded">Force</span>
                    {/if}
                    {#if item.help}
                      <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">{item.help}</p>
                    {/if}
                    <p class="text-xs text-gray-500 dark:text-gray-500 mt-1">
                      未設定時：{formatDefaultValue(item.default_value)}
                    </p>
                  </div>
                  <div class="setting-value">
                    {#if getSettingControl(item) === 'boolean'}
                      <!-- Boolean型（3択セグメント型トグル） -->
                      <div class="toggle-3way">
                        <input
                          type="radio"
                          id="{item.name}-nil"
                          name={item.name}
                          checked={getBooleanValueString(workingSettings[item.name]) === 'nil'}
                          onchange={() => setBooleanValue(item.name, 'nil')}
                          disabled={item.is_forced}
                        />
                        <label for="{item.name}-nil">未設定</label>
                        
                        <input
                          type="radio"
                          id="{item.name}-off"
                          name={item.name}
                          checked={getBooleanValueString(workingSettings[item.name]) === 'off'}
                          onchange={() => setBooleanValue(item.name, 'off')}
                          disabled={item.is_forced}
                        />
                        <label for="{item.name}-off">いいえ</label>
                        
                        <input
                          type="radio"
                          id="{item.name}-on"
                          name={item.name}
                          checked={getBooleanValueString(workingSettings[item.name]) === 'on'}
                          onchange={() => setBooleanValue(item.name, 'on')}
                          disabled={item.is_forced}
                        />
                        <label for="{item.name}-on">はい</label>
                      </div>

                    {:else if getSettingControl(item) === 'select'}
                      <!-- Select型 -->
                      <select
                        bind:value={workingSettings[item.name]}
                        disabled={item.is_forced}
                        class="select-field"
                      >
                        <option value="">未設定</option>
                        {#if item.select_keys && item.select_summaries}
                          {#each item.select_keys as key, i}
                            <option value={key}>{item.select_summaries[i]}</option>
                          {/each}
                        {/if}
                      </select>

                    {:else if getSettingControl(item) === 'multiple'}
                      <!-- Multiple型 -->
                      <select
                        bind:value={workingSettings[item.name]}
                        disabled={item.is_forced}
                        multiple
                        class="select-field-multiple"
                        size="4"
                      >
                        {#if item.select_keys && item.select_summaries}
                          {#each item.select_keys as key, i}
                            <option value={key}>{item.select_summaries[i]}</option>
                          {/each}
                        {/if}
                      </select>
                      <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">Ctrl/Cmdキーを押しながらクリックで複数選択</p>

                    {:else}
                      <!-- Text/Integer型 -->
                      <input
                        type={item.type === 'integer' ? 'number' : 'text'}
                        bind:value={workingSettings[item.name]}
                        disabled={item.is_forced}
                        placeholder={item.type === 'integer' ? '整数値' : 'テキスト'}
                        class="input-field"
                      />
                    {/if}
                  </div>
                </div>
              </div>
            {/each}
          </div>

          <!-- 置換設定 -->
          <div class="mt-8">
            <h3 class="text-lg font-semibold text-gray-900 dark:text-white mb-4">
              置換設定
            </h3>
            
            <div class="mb-4 p-4 bg-blue-50 dark:bg-blue-900/20 rounded-lg">
              <ul class="text-sm text-gray-700 dark:text-gray-300 space-y-1">
                <li>• この小説の文章を置換する設定を行うことができます（replace.txt を書き換えます）</li>
                <li>• 変更を反映させるには再度変換を実行する必要があります</li>
              </ul>
            </div>

            <div class="space-y-2">
              {#each replacePatterns as pattern, i (i)}
                <div class="flex gap-2">
                  <input
                    type="text"
                    bind:value={pattern.left}
                    placeholder="置換前"
                    class="flex-1 px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-800 text-gray-900 dark:text-white focus:ring-2 focus:ring-blue-500"
                  />
                  <span class="flex items-center text-gray-400">→</span>
                  <input
                    type="text"
                    bind:value={pattern.right}
                    placeholder="置換後"
                    class="flex-1 px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-800 text-gray-900 dark:text-white focus:ring-2 focus:ring-blue-500"
                  />
                  <button
                    onclick={() => removeReplacePattern(i)}
                    class="px-3 py-2 text-red-600 hover:bg-red-50 dark:hover:bg-red-900/20 rounded-md transition-colors"
                    aria-label="削除"
                  >
                    <i class="fas fa-trash-alt"></i>
                  </button>
                </div>
              {/each}
            </div>

            <button
              onclick={addReplacePattern}
              class="mt-3 px-4 py-2 text-sm text-blue-600 dark:text-blue-400 hover:bg-blue-50 dark:hover:bg-blue-900/20 rounded-md transition-colors"
            >
              <i class="fas fa-plus mr-2"></i>
              置換パターンを追加
            </button>
          </div>
        {/if}
      </div>

      <!-- フッター -->
      <div class="flex items-center justify-end gap-3 p-4 border-t border-gray-200 dark:border-gray-700">
        <button
          onclick={closeModal}
          disabled={saving}
          class="px-4 py-2 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-md transition-colors disabled:opacity-50"
        >
          キャンセル
        </button>
        <button
          onclick={saveSettings}
          disabled={saving || loading}
          class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
        >
          {#if saving}
            <i class="fas fa-spinner fa-spin"></i>
          {/if}
          {saving ? '保存中...' : '設定を保存'}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  /* Settings.svelteと同じスタイルを適用 */
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

  /* Force設定の背景色 */
  .forced-item {
    background-color: #fef3c7;
    padding: 1rem;
    border-radius: 0.5rem;
    border: 1px solid #fbbf24;
  }

  :global(.dark) .forced-item {
    background-color: rgba(217, 119, 6, 0.1);
    border-color: #92400e;
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
    background-color: #374151;
    border-color: #4b5563;
    color: #f9fafb;
  }

  :global(.dark) .input-field::placeholder {
    color: #9ca3af;
  }

  .input-field:focus {
    outline: none;
    border-color: #3b82f6;
    box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
  }

  .input-field:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  /* セレクトボックスのスタイル */
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

  .select-field:disabled {
    opacity: 0.5;
    cursor: not-allowed;
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

  .select-field-multiple:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .select-field-multiple option {
    padding: 0.5rem;
  }

  .select-field-multiple option:checked {
    background-color: #3b82f6;
    color: white;
  }

  /* 3択トグルスイッチ（セグメント型） */
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
    color: #1f2937;
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

  /* disabled状態 */
  .toggle-3way input[type="radio"]:disabled + label {
    opacity: 0.5;
    cursor: not-allowed;
  }
</style>
