<!--
  タグ管理モーダルコンポーネント
  
  選択された小説に対してタグの追加・削除・編集を行う
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import { getTagInfo, editTags, setTagColors, type TagInfo } from '../lib/api';

  let isOpen = $state(false);
  let selectedIds = $state<number[]>([]);
  let tagStates = $state<Record<string, number>>({});
  let tagColors = $state<Record<string, string>>({});
  let newTagName = $state('');
  let newTagColor = $state('green');
  let isLoading = $state(false);
  let isSaving = $state(false);
  let error = $state<string | null>(null);
  
  // 利用可能な色
  const AVAILABLE_COLORS = ['green', 'yellow', 'blue', 'magenta', 'cyan', 'red', 'white'] as const;

  /**
   * タグ状態の定義
   * 0: 削除（選択された小説から削除）
   * 1: 維持（現状のまま）
   * 2: 追加（選択された小説に追加）
   */
  const TAG_STATE = {
    DELETE: 0,
    KEEP: 1,
    ADD: 2,
  } as const;

  /**
   * モーダルを開く
   */
  export async function open(ids: number[]) {
    selectedIds = ids;
    isOpen = true;
    error = null;
    newTagName = '';
    
    await loadTagInfo();
  }

  /**
   * モーダルを閉じる
   */
  export function close() {
    isOpen = false;
    selectedIds = [];
    tagStates = {};
    newTagName = '';
    error = null;
  }

  /**
   * タグ情報を読み込み
   */
  async function loadTagInfo() {
    if (selectedIds.length === 0) return;
    
    isLoading = true;
    error = null;
    
    try {
      const tagInfo = await getTagInfo(selectedIds);
      
      // タグ状態を初期化 - すべてのタグを表示
      tagStates = {};
      tagColors = {};
      Object.entries(tagInfo).forEach(([tagName, info]) => {
        // count > 0: 選択された小説の一部または全部が持っている = KEEP
        // count === 0: 選択された小説は持っていない（でも他の小説が持っている）= DELETE
        tagStates[tagName] = info.count > 0 ? TAG_STATE.KEEP : TAG_STATE.DELETE;
        tagColors[tagName] = info.color;
      });
      
    } catch (err) {
      error = err instanceof Error ? err.message : 'タグ情報の取得に失敗しました';
      console.error('Failed to load tag info:', err);
    } finally {
      isLoading = false;
    }
  }

  /**
   * タグ状態を切り替え
   */
  function toggleTagState(tagName: string) {
    const currentState = tagStates[tagName] ?? TAG_STATE.DELETE;
    
    // 状態を順番に切り替え: DELETE → KEEP → ADD → DELETE → ...
    if (currentState === TAG_STATE.DELETE) {
      tagStates[tagName] = TAG_STATE.KEEP;
    } else if (currentState === TAG_STATE.KEEP) {
      tagStates[tagName] = TAG_STATE.ADD;
    } else {
      tagStates[tagName] = TAG_STATE.DELETE;
    }
  }

  /**
   * 新しいタグを追加
   */
  function addNewTag() {
    const trimmed = newTagName.trim();
    if (!trimmed) {
      error = 'タグ名を入力してください';
      return;
    }
    
    if (tagStates[trimmed] !== undefined) {
      error = 'このタグは既に存在します';
      return;
    }
    
    tagStates[trimmed] = TAG_STATE.ADD;
    tagColors[trimmed] = newTagColor;
    newTagName = '';
    error = null;
  }

  /**
   * タグを保存
   */
  async function saveTags() {
    if (selectedIds.length === 0) return;
    
    isSaving = true;
    error = null;
    
    try {
      // タグ状態の保存
      const result = await editTags(selectedIds, tagStates);
      
      // タグ色の保存（色が変更されたタグのみ）
      await setTagColors(tagColors);
      
      // 成功メッセージ（後でトースト通知に置き換え）
      const messages = [];
      if (result.added.length > 0) {
        messages.push(`${result.added.length}件のタグを追加`);
      }
      if (result.deleted.length > 0) {
        messages.push(`${result.deleted.length}件のタグを削除`);
      }
      
      if (messages.length > 0) {
        alert(`${result.novel_count}件の小説に対して\n${messages.join('、')}しました`);
      } else {
        alert('変更はありませんでした');
      }
      
      close();
    } catch (err) {
      error = err instanceof Error ? err.message : 'タグの保存に失敗しました';
      console.error('Failed to save tags:', err);
    } finally {
      isSaving = false;
    }
  }

  /**
   * タグ状態のラベルを取得
   */
  function getStateLabel(state: number): string {
    switch (state) {
      case TAG_STATE.DELETE:
        return '削除';
      case TAG_STATE.KEEP:
        return '維持';
      case TAG_STATE.ADD:
        return '追加';
      default:
        return '不明';
    }
  }

  /**
   * タグ状態のクラスを取得
   */
  function getStateClass(state: number): string {
    switch (state) {
      case TAG_STATE.DELETE:
        return 'state-delete';
      case TAG_STATE.KEEP:
        return 'state-keep';
      case TAG_STATE.ADD:
        return 'state-add';
      default:
        return '';
    }
  }

  /**
   * タグ色のCSSクラスを取得
   */
  function getColorClass(color: string): string {
    const colorMap: Record<string, string> = {
      red: 'bg-red-100 dark:bg-red-900 text-red-800 dark:text-red-200',
      blue: 'bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200',
      green: 'bg-green-100 dark:bg-green-900 text-green-800 dark:text-green-200',
      yellow: 'bg-yellow-100 dark:bg-yellow-900 text-yellow-800 dark:text-yellow-200',
      magenta: 'bg-pink-100 dark:bg-pink-900 text-pink-800 dark:text-pink-200',
      cyan: 'bg-cyan-100 dark:bg-cyan-900 text-cyan-800 dark:text-cyan-200',
      white: 'bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200',
    };
    return colorMap[color] || colorMap.white;
  }
  
  /**
   * 背景色から適切なテキスト色を計算（コントラスト考慮）
   */
  function getTextColorForBackground(bgColor: string): string {
    const colorLuminance: Record<string, number> = {
      red: 0.3,
      blue: 0.2,
      green: 0.4,
      yellow: 0.8,
      magenta: 0.4,
      cyan: 0.7,
      white: 0.9,
    };
    
    const luminance = colorLuminance[bgColor] || 0.5;
    return luminance > 0.6 ? '#000000' : '#FFFFFF';
  }
  
  /**
   * タグ色の背景スタイルを取得
   */
  function getColorStyle(color: string): string {
    const colorHex: Record<string, string> = {
      red: '#EF4444',
      blue: '#3B82F6',
      green: '#10B981',
      yellow: '#F59E0B',
      magenta: '#EC4899',
      cyan: '#06B6D4',
      white: '#F3F4F6',
    };
    
    const bg = colorHex[color] || colorHex.white;
    const text = getTextColorForBackground(color);
    return `background-color: ${bg}; color: ${text};`;
  }
  
  /**
   * タグの色を変更
   */
  function changeTagColor(tagName: string, newColor: string) {
    tagColors[tagName] = newColor;
  }

  /**
   * 変更があるかチェック
   */
  function hasChanges(): boolean {
    return Object.values(tagStates).some(state => state !== TAG_STATE.KEEP);
  }

  function handleBackdropClick(e: MouseEvent) {
    if (e.target === e.currentTarget) {
      close();
    }
  }
</script>

{#if isOpen}
  <!-- モーダルバックドロップ -->
  <div
    class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50"
    onclick={handleBackdropClick}
    role="dialog"
    aria-modal="true"
    aria-labelledby="tag-modal-title"
  >
    <!-- モーダルコンテンツ -->
    <div class="bg-white dark:bg-gray-800 rounded-lg shadow-xl w-full max-w-2xl mx-4 max-h-[90vh] flex flex-col">
      <!-- ヘッダー -->
      <div class="flex items-center justify-between px-6 py-4 border-b border-gray-200 dark:border-gray-700">
        <h2 id="tag-modal-title" class="text-xl font-semibold text-gray-900 dark:text-gray-100">
          タグ編集 ({selectedIds.length}件選択中)
        </h2>
        <button
          onclick={close}
          class="text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200 text-2xl leading-none"
          aria-label="閉じる"
        >
          ×
        </button>
      </div>

      <!-- コンテンツ -->
      <div class="flex-1 overflow-y-auto p-6">
        {#if isLoading}
          <div class="text-center py-8">
            <div class="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
            <p class="mt-2 text-gray-600 dark:text-gray-400">タグ情報を読み込み中...</p>
          </div>
        {:else}
          <!-- 新しいタグを追加 -->
          <div class="mb-6">
            <label for="new-tag" class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
              新しいタグを追加
            </label>
            <div class="flex gap-2 flex-wrap">
              <input
                id="new-tag"
                type="text"
                bind:value={newTagName}
                onkeydown={(e) => e.key === 'Enter' && addNewTag()}
                placeholder="タグ名を入力..."
                class="flex-1 min-w-[200px] px-3 py-2 border border-gray-300 dark:border-gray-600 rounded dark:bg-gray-700 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                disabled={isSaving}
              />
              <select
                bind:value={newTagColor}
                class="px-3 py-2 border border-gray-300 dark:border-gray-600 rounded dark:bg-gray-700 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                disabled={isSaving}
              >
                {#each AVAILABLE_COLORS as color}
                  <option value={color}>
                    {color === 'green' ? '緑' : 
                     color === 'yellow' ? '黄' : 
                     color === 'blue' ? '青' : 
                     color === 'magenta' ? 'マゼンタ' : 
                     color === 'cyan' ? 'シアン' : 
                     color === 'red' ? '赤' : 
                     '白'}
                  </option>
                {/each}
              </select>
              <button
                onclick={addNewTag}
                class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors whitespace-nowrap"
                disabled={isSaving || !newTagName.trim()}
              >
                追加
              </button>
            </div>
          </div>

          <!-- タグリスト -->
          <div>
            <h3 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-3">
              タグをクリックして状態を変更
            </h3>
            
            {#if Object.keys(tagStates).length === 0}
              <p class="text-center text-gray-500 dark:text-gray-400 py-8">
                タグがありません。上のフォームから新しいタグを追加してください。
              </p>
            {:else}
              <div class="space-y-2">
                {#each Object.entries(tagStates) as [tagName, state]}
                  <div class="flex items-center gap-2">
                    <button
                      onclick={() => toggleTagState(tagName)}
                      class="flex-1 flex items-center justify-between px-4 py-3 border-2 rounded-lg transition-all hover:shadow-md {getStateClass(state)}"
                      disabled={isSaving}
                    >
                      <div class="flex items-center gap-2">
                        <span
                          class="px-2 py-1 rounded text-xs font-semibold"
                          style={getColorStyle(tagColors[tagName] || 'white')}
                        >
                          {tagName}
                        </span>
                      </div>
                      <div class="flex items-center gap-3">
                        <span class="state-badge">
                          {getStateLabel(state)}
                        </span>
                        <span class="text-xs text-gray-500 dark:text-gray-400">
                          クリックで切り替え
                        </span>
                      </div>
                    </button>
                    <select
                      value={tagColors[tagName] || 'white'}
                      onchange={(e) => changeTagColor(tagName, e.currentTarget.value)}
                      class="px-2 py-2 border border-gray-300 dark:border-gray-600 rounded dark:bg-gray-700 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500 text-sm"
                      disabled={isSaving}
                      title="タグの色を変更"
                    >
                      {#each AVAILABLE_COLORS as color}
                        <option value={color}>
                          {color === 'green' ? '緑' : 
                           color === 'yellow' ? '黄' : 
                           color === 'blue' ? '青' : 
                           color === 'magenta' ? 'マゼンタ' : 
                           color === 'cyan' ? 'シアン' : 
                           color === 'red' ? '赤' : 
                           '白'}
                        </option>
                      {/each}
                    </select>
                  </div>
                {/each}
              </div>
            {/if}
          </div>

          {#if error}
            <div class="mt-4 p-3 bg-red-100 dark:bg-red-900 border border-red-400 dark:border-red-700 text-red-700 dark:text-red-200 rounded text-sm">
              {error}
            </div>
          {/if}
        {/if}
      </div>

      <!-- フッター -->
      <div class="flex gap-3 justify-end px-6 py-4 border-t border-gray-200 dark:border-gray-700">
        <button
          type="button"
          onclick={close}
          class="px-4 py-2 text-gray-700 dark:text-gray-300 bg-gray-200 dark:bg-gray-700 rounded hover:bg-gray-300 dark:hover:bg-gray-600 transition-colors"
          disabled={isSaving}
        >
          キャンセル
        </button>
        <button
          type="button"
          onclick={saveTags}
          class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors flex items-center gap-2"
          disabled={isSaving || !hasChanges()}
        >
          {#if isSaving}
            <div class="inline-block animate-spin rounded-full h-4 w-4 border-b-2 border-white"></div>
            保存中...
          {:else}
            保存
          {/if}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  /* タグ状態別のスタイル */
  .state-delete {
    border-color: #ef4444;
    background-color: #fee2e2;
  }

  :global(.dark) .state-delete {
    border-color: #991b1b;
    background-color: #7f1d1d;
  }

  .state-keep {
    border-color: #9ca3af;
    background-color: #f9fafb;
  }

  :global(.dark) .state-keep {
    border-color: #4b5563;
    background-color: #1f2937;
  }

  .state-add {
    border-color: #10b981;
    background-color: #d1fae5;
  }

  :global(.dark) .state-add {
    border-color: #065f46;
    background-color: #064e3b;
  }

  .state-badge {
    display: inline-block;
    padding: 0.25rem 0.75rem;
    font-size: 0.75rem;
    font-weight: 600;
    border-radius: 9999px;
  }

  .state-delete .state-badge {
    background-color: #ef4444;
    color: white;
  }

  .state-keep .state-badge {
    background-color: #6b7280;
    color: white;
  }

  .state-add .state-badge {
    background-color: #10b981;
    color: white;
  }

  :global(.dark) .state-delete .state-badge {
    background-color: #dc2626;
  }

  :global(.dark) .state-keep .state-badge {
    background-color: #4b5563;
  }

  :global(.dark) .state-add .state-badge {
    background-color: #059669;
  }
</style>
