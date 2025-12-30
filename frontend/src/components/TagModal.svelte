<!--
  タグ管理モーダルコンポーネント
  
  選択された小説に対してタグの追加・削除・編集を行う
-->
<script lang="ts">
  import { onMount } from "svelte";
  import { getTagInfo, editTags, setTagColors, type TagInfo } from "../lib/api";

  let isOpen = $state(false);
  let selectedIds = $state<number[]>([]);
  let novelTitle = $state<string | null>(null);
  let onSaveCallback = $state<(() => void) | null>(null);
  let tagStates = $state<Record<string, number>>({});
  let tagColors = $state<Record<string, string>>({});
  let tagCounts = $state<Record<string, number>>({});
  let newTagName = $state("");
  let newTagColor = $state("green");
  let isLoading = $state(false);
  let isSaving = $state(false);
  let error = $state<string | null>(null);
  let colorPickerOpenTag = $state<string | null>(null);
  let newTagColorPickerOpen = $state(false);
  let editingTagName = $state<string | null>(null);
  let editingTagNewName = $state<string>("");

  // 利用可能な色
  const AVAILABLE_COLORS = [
    "green",
    "yellow",
    "blue",
    "magenta",
    "cyan",
    "red",
    "white",
  ] as const;

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
  export async function open(
    ids: number[],
    title: string | null = null,
    onSave: (() => void) | null = null
  ) {
    selectedIds = ids;
    novelTitle = title;
    onSaveCallback = onSave;
    isOpen = true;
    error = null;
    newTagName = "";

    await loadTagInfo();
  }

  /**
   * モーダルを閉じる
   */
  export function close() {
    isOpen = false;
    selectedIds = [];
    novelTitle = null;
    onSaveCallback = null;
    tagStates = {};
    newTagName = "";
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

      // タグ状態を初期化
      tagStates = {};
      tagColors = {};
      tagCounts = {};
      Object.entries(tagInfo).forEach(([tagName, info]) => {
        // 既存の紐付け状態をそのまま維持
        // すべてのタグの初期状態は KEEP（維持）
        tagStates[tagName] = TAG_STATE.KEEP;
        tagColors[tagName] = info.color;
        tagCounts[tagName] = info.count;
      });
    } catch (err) {
      error =
        err instanceof Error ? err.message : "タグ情報の取得に失敗しました";
      console.error("Failed to load tag info:", err);
    } finally {
      isLoading = false;
    }
  }

  /**
   * タグ状態を切り替え（トリステート）
   * KEEP → ADD → DELETE → KEEP ...
   */
  function toggleTagState(tagName: string) {
    const currentState = tagStates[tagName] ?? TAG_STATE.KEEP;

    // トリステートトグル: KEEP → ADD → DELETE → KEEP ...
    if (currentState === TAG_STATE.KEEP) {
      tagStates[tagName] = TAG_STATE.ADD;
    } else if (currentState === TAG_STATE.ADD) {
      tagStates[tagName] = TAG_STATE.DELETE;
    } else {
      tagStates[tagName] = TAG_STATE.KEEP;
    }
  }

  /**
   * 新しいタグを追加
   */
  function addNewTag() {
    const trimmed = newTagName.trim();
    if (!trimmed) {
      error = "タグ名を入力してください";
      return;
    }

    if (tagStates[trimmed] !== undefined) {
      error = "このタグは既に存在します";
      return;
    }

    tagStates[trimmed] = TAG_STATE.ADD;
    tagColors[trimmed] = newTagColor;
    tagCounts[trimmed] = 0;
    newTagName = "";
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
        alert(
          `${result.novel_count}件の小説に対して\n${messages.join("、")}しました`
        );
      } else {
        alert("変更はありませんでした");
      }

      // 保存成功時のコールバックを実行
      if (onSaveCallback) {
        onSaveCallback();
      }

      close();
    } catch (err) {
      error = err instanceof Error ? err.message : "タグの保存に失敗しました";
      console.error("Failed to save tags:", err);
    } finally {
      isSaving = false;
    }
  }

  /**
   * タグ状態のクラスを取得
   */
  function getStateClass(state: number): string {
    switch (state) {
      case TAG_STATE.DELETE:
        return "state-delete";
      case TAG_STATE.KEEP:
        return "state-keep";
      case TAG_STATE.ADD:
        return "state-add";
      default:
        return "";
    }
  }

  /**
   * タグ色のCSSクラスを取得
   */
  function getColorClass(color: string): string {
    const colorMap: Record<string, string> = {
      red: "bg-red-100 dark:bg-red-900 text-red-800 dark:text-red-200",
      blue: "bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200",
      green:
        "bg-green-100 dark:bg-green-900 text-green-800 dark:text-green-200",
      yellow:
        "bg-yellow-100 dark:bg-yellow-900 text-yellow-800 dark:text-yellow-200",
      magenta: "bg-pink-100 dark:bg-pink-900 text-pink-800 dark:text-pink-200",
      cyan: "bg-cyan-100 dark:bg-cyan-900 text-cyan-800 dark:text-cyan-200",
      white: "bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200",
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
    return luminance > 0.6 ? "#000000" : "#FFFFFF";
  }

  /**
   * タグ色の背景スタイルを取得
   */
  function getColorStyle(color: string): string {
    const colorHex: Record<string, string> = {
      red: "#EF4444",
      blue: "#3B82F6",
      green: "#10B981",
      yellow: "#F59E0B",
      magenta: "#EC4899",
      cyan: "#06B6D4",
      white: "#F3F4F6",
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
    colorPickerOpenTag = null;
  }

  /**
   * 色ピッカーのトグル
   */
  function toggleColorPicker(tagName: string) {
    colorPickerOpenTag = colorPickerOpenTag === tagName ? null : tagName;
  }

  /**
   * 色の●記号を取得
   */
  function getColorDot(color: string): string {
    const colorHex: Record<string, string> = {
      red: "#EF4444",
      blue: "#3B82F6",
      green: "#10B981",
      yellow: "#F59E0B",
      magenta: "#EC4899",
      cyan: "#06B6D4",
      white: "#9CA3AF",
    };
    return colorHex[color] || colorHex.white;
  }

  /**
   * 既存の紐付け状態を判定
   * @returns 'all' - 全ての選択小説に紐付いている, 'partial' - 一部に紐付いている, 'none' - 紐付いていない
   */
  function getExistingLinkState(tagName: string): "all" | "partial" | "none" {
    const count = tagCounts[tagName] || 0;
    if (count === 0) return "none";
    if (count === selectedIds.length) return "all";
    return "partial";
  }

  /**
   * タグ名の編集を開始
   */
  function startEditingTag(tagName: string) {
    editingTagName = tagName;
    editingTagNewName = tagName;
  }

  /**
   * タグ名の編集を完了
   */
  function finishEditingTag() {
    if (!editingTagName) return;

    const trimmed = editingTagNewName.trim();
    if (!trimmed) {
      error = "タグ名は空にできません";
      return;
    }

    if (trimmed !== editingTagName && tagStates[trimmed] !== undefined) {
      error = "このタグ名は既に存在します";
      return;
    }

    if (trimmed !== editingTagName) {
      // タグ名を変更
      tagStates[trimmed] = tagStates[editingTagName];
      tagColors[trimmed] = tagColors[editingTagName];
      tagCounts[trimmed] = tagCounts[editingTagName];

      delete tagStates[editingTagName];
      delete tagColors[editingTagName];
      delete tagCounts[editingTagName];
    }

    editingTagName = null;
    editingTagNewName = "";
    error = null;
  }

  /**
   * タグ名の編集をキャンセル
   */
  function cancelEditingTag() {
    editingTagName = null;
    editingTagNewName = "";
    error = null;
  }

  /**
   * 変更があるかチェック
   */
  function hasChanges(): boolean {
    return Object.values(tagStates).some((state) => state !== TAG_STATE.KEEP);
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
    <div
      class="bg-white dark:bg-gray-800 rounded-lg shadow-xl w-full max-w-2xl mx-4 max-h-[90vh] flex flex-col"
    >
      <!-- ヘッダー -->
      <div
        class="flex items-center justify-between px-6 py-4 border-b border-gray-200 dark:border-gray-700"
      >
        <h2
          id="tag-modal-title"
          class="text-xl font-semibold text-gray-900 dark:text-gray-100"
        >
          {#if novelTitle}
            タグ編集 - {novelTitle}
          {:else}
            タグ編集 ({selectedIds.length}件選択中)
          {/if}
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
            <div
              class="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"
            ></div>
            <p class="mt-2 text-gray-600 dark:text-gray-400">
              タグ情報を読み込み中...
            </p>
          </div>
        {:else}
          <!-- 新しいタグを追加 -->
          <div class="mb-6">
            <label
              for="new-tag"
              class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2"
            >
              新しいタグを追加
            </label>
            <div class="flex gap-2 flex-wrap items-center">
              <!-- 色選択ドット -->
              <div class="relative">
                <button
                  type="button"
                  onclick={(e) => {
                    e.stopPropagation();
                    newTagColorPickerOpen = !newTagColorPickerOpen;
                  }}
                  class="color-dot-button-large"
                  style="color: {getColorDot(newTagColor)}"
                  disabled={isSaving}
                  title="色を選択"
                >
                  ●
                </button>

                <!-- 色選択ポップアップ -->
                {#if newTagColorPickerOpen}
                  <div class="color-picker-popup">
                    {#each AVAILABLE_COLORS as color}
                      <button
                        type="button"
                        onclick={(e) => {
                          e.stopPropagation();
                          newTagColor = color;
                          newTagColorPickerOpen = false;
                        }}
                        class="color-option"
                        style="color: {getColorDot(color)}"
                        title={color === "green"
                          ? "緑"
                          : color === "yellow"
                            ? "黄"
                            : color === "blue"
                              ? "青"
                              : color === "magenta"
                                ? "マゼンタ"
                                : color === "cyan"
                                  ? "シアン"
                                  : color === "red"
                                    ? "赤"
                                    : "白"}
                      >
                        ●
                      </button>
                    {/each}
                  </div>
                {/if}
              </div>
              <input
                id="new-tag"
                type="text"
                bind:value={newTagName}
                onkeydown={(e) => e.key === "Enter" && addNewTag()}
                placeholder="タグ名を入力..."
                class="flex-1 min-w-[200px] px-3 py-2 border border-gray-300 dark:border-gray-600 rounded dark:bg-gray-700 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                disabled={isSaving}
              />
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
            {#if Object.keys(tagStates).length === 0}
              <p class="text-center text-gray-500 dark:text-gray-400 py-8">
                タグがありません。上のフォームから新しいタグを追加してください。
              </p>
            {:else}
              <!-- 紐付け済みタグ -->
              {@const linkedTags = Object.entries(tagStates).filter(
                ([name]) => getExistingLinkState(name) !== "none"
              )}
              {#if linkedTags.length > 0}
                <div class="mb-6">
                  <h3
                    class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-3"
                  >
                    紐付け済みタグ
                  </h3>
                  <div class="grid grid-cols-2 gap-2">
                    {#each linkedTags as [tagName, state]}
                      <div
                        class="tag-item-new {getStateClass(
                          state
                        )} {getExistingLinkState(tagName) === 'all'
                          ? 'linked-all'
                          : 'linked-partial'}"
                      >
                        <!-- 色選択ボタン -->
                        <div class="relative color-picker-container">
                          <button
                            type="button"
                            onclick={(e) => {
                              e.stopPropagation();
                              toggleColorPicker(tagName);
                            }}
                            class="color-dot-button"
                            style="color: {getColorDot(
                              tagColors[tagName] || 'white'
                            )}"
                            disabled={isSaving}
                            title="色を変更"
                          >
                            ●
                          </button>

                          <!-- 色選択ポップアップ -->
                          {#if colorPickerOpenTag === tagName}
                            <div class="color-picker-popup">
                              {#each AVAILABLE_COLORS as color}
                                <button
                                  type="button"
                                  onclick={(e) => {
                                    e.stopPropagation();
                                    changeTagColor(tagName, color);
                                  }}
                                  class="color-option"
                                  style="color: {getColorDot(color)}"
                                  title={color === "green"
                                    ? "緑"
                                    : color === "yellow"
                                      ? "黄"
                                      : color === "blue"
                                        ? "青"
                                        : color === "magenta"
                                          ? "マゼンタ"
                                          : color === "cyan"
                                            ? "シアン"
                                            : color === "red"
                                              ? "赤"
                                              : "白"}
                                >
                                  ●
                                </button>
                              {/each}
                            </div>
                          {/if}
                        </div>

                        <!-- タグ名（編集可能） -->
                        {#if editingTagName === tagName}
                          <input
                            type="text"
                            bind:value={editingTagNewName}
                            onkeydown={(e) => {
                              if (e.key === "Enter") finishEditingTag();
                              if (e.key === "Escape") cancelEditingTag();
                            }}
                            onblur={finishEditingTag}
                            class="tag-name-input"
                            disabled={isSaving}
                            autofocus
                          />
                        {:else}
                          <div
                            onclick={() => startEditingTag(tagName)}
                            class="tag-name-display"
                            role="button"
                            tabindex="0"
                          >
                            {tagName}
                          </div>
                        {/if}

                        <!-- 小説数カウント（複数選択時のみ） -->
                        {#if selectedIds.length > 1}
                          <span class="tag-count-new">
                            {tagCounts[tagName] || 0}/{selectedIds.length}
                          </span>
                        {/if}

                        <!-- 操作状態トグル -->
                        <button
                          type="button"
                          onclick={() => toggleTagState(tagName)}
                          class="tag-state-toggle {state === TAG_STATE.DELETE
                            ? 'toggle-off'
                            : state === TAG_STATE.ADD
                              ? 'toggle-on'
                              : 'toggle-partial'}"
                          disabled={isSaving}
                        >
                          <div class="toggle-track">
                            <div class="toggle-thumb"></div>
                          </div>
                          <span class="toggle-label">
                            {state === TAG_STATE.DELETE
                              ? "紐付けない"
                              : state === TAG_STATE.ADD
                                ? "すべて連携"
                                : getExistingLinkState(tagName) === "all"
                                  ? "すべて連携"
                                  : "一部連携"}
                          </span>
                        </button>
                      </div>
                    {/each}
                  </div>
                </div>
              {/if}

              <!-- 未紐付けタグ -->
              {@const unlinkedTags = Object.entries(tagStates).filter(
                ([name]) => getExistingLinkState(name) === "none"
              )}
              {#if unlinkedTags.length > 0}
                <div>
                  <h3
                    class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-3"
                  >
                    未紐付けタグ
                  </h3>
                  <div class="grid grid-cols-2 gap-2">
                    {#each unlinkedTags as [tagName, state]}
                      <div
                        class="tag-item-new {getStateClass(state)} linked-none"
                      >
                        <!-- 色選択ボタン -->
                        <div class="relative color-picker-container">
                          <button
                            type="button"
                            onclick={(e) => {
                              e.stopPropagation();
                              toggleColorPicker(tagName);
                            }}
                            class="color-dot-button"
                            style="color: {getColorDot(
                              tagColors[tagName] || 'white'
                            )}"
                            disabled={isSaving}
                            title="色を変更"
                          >
                            ●
                          </button>

                          <!-- 色選択ポップアップ -->
                          {#if colorPickerOpenTag === tagName}
                            <div class="color-picker-popup">
                              {#each AVAILABLE_COLORS as color}
                                <button
                                  type="button"
                                  onclick={(e) => {
                                    e.stopPropagation();
                                    changeTagColor(tagName, color);
                                  }}
                                  class="color-option"
                                  style="color: {getColorDot(color)}"
                                  title={color === "green"
                                    ? "緑"
                                    : color === "yellow"
                                      ? "黄"
                                      : color === "blue"
                                        ? "青"
                                        : color === "magenta"
                                          ? "マゼンタ"
                                          : color === "cyan"
                                            ? "シアン"
                                            : color === "red"
                                              ? "赤"
                                              : "白"}
                                >
                                  ●
                                </button>
                              {/each}
                            </div>
                          {/if}
                        </div>

                        <!-- タグ名（編集可能） -->
                        {#if editingTagName === tagName}
                          <input
                            type="text"
                            bind:value={editingTagNewName}
                            onkeydown={(e) => {
                              if (e.key === "Enter") finishEditingTag();
                              if (e.key === "Escape") cancelEditingTag();
                            }}
                            onblur={finishEditingTag}
                            class="tag-name-input"
                            disabled={isSaving}
                            autofocus
                          />
                        {:else}
                          <div
                            onclick={() => startEditingTag(tagName)}
                            class="tag-name-display"
                            role="button"
                            tabindex="0"
                          >
                            {tagName}
                          </div>
                        {/if}

                        <!-- 操作状態トグル -->
                        <button
                          type="button"
                          onclick={() => toggleTagState(tagName)}
                          class="tag-state-toggle {state === TAG_STATE.DELETE
                            ? 'toggle-off'
                            : state === TAG_STATE.ADD
                              ? 'toggle-on'
                              : 'toggle-partial'}"
                          disabled={isSaving}
                        >
                          <div class="toggle-track">
                            <div class="toggle-thumb"></div>
                          </div>
                          <span class="toggle-label">
                            {state === TAG_STATE.DELETE
                              ? "紐付けない"
                              : state === TAG_STATE.ADD
                                ? "リンクする"
                                : "未連携"}
                          </span>
                        </button>
                      </div>
                    {/each}
                  </div>
                </div>
              {/if}
            {/if}
          </div>

          {#if error}
            <div
              class="mt-4 p-3 bg-red-100 dark:bg-red-900 border border-red-400 dark:border-red-700 text-red-700 dark:text-red-200 rounded text-sm"
            >
              {error}
            </div>
          {/if}
        {/if}
      </div>

      <!-- フッター -->
      <div
        class="flex gap-3 justify-end px-6 py-4 border-t border-gray-200 dark:border-gray-700"
      >
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
            <div
              class="inline-block animate-spin rounded-full h-4 w-4 border-b-2 border-white"
            ></div>
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
  /* 新しいタグアイテム */
  .tag-item-new {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.5rem 0.75rem;
    border-radius: 0.5rem;
    transition: all 0.15s;
    background-color: #f9fafb;
  }

  :global(.dark) .tag-item-new {
    background-color: #1f2937;
  }

  /* 既存の紐付け状態に応じた枠線 */
  .linked-all {
    border: 3px solid #3b82f6;
  }

  :global(.dark) .linked-all {
    border-color: #60a5fa;
  }

  .linked-partial {
    border: 2px solid #f59e0b;
  }

  :global(.dark) .linked-partial {
    border-color: #fbbf24;
  }

  .linked-none {
    border: 1px solid #d1d5db;
  }

  :global(.dark) .linked-none {
    border-color: #4b5563;
  }

  /* 操作状態別の背景色 */
  .state-delete {
    background-color: #fee2e2;
  }

  :global(.dark) .state-delete {
    background-color: #7f1d1d;
  }

  .state-keep {
    /* デフォルトの背景色を使用 */
  }

  .state-add {
    background-color: #d1fae5;
  }

  :global(.dark) .state-add {
    background-color: #064e3b;
  }

  /* 色選択コンテナ */
  .color-picker-container {
    flex-shrink: 0;
  }

  /* 色選択ボタン */
  .color-dot-button {
    font-size: 1.25rem;
    line-height: 1;
    padding: 0;
    background: none;
    border: none;
    cursor: pointer;
    transition: transform 0.15s;
  }

  .color-dot-button:hover:not(:disabled) {
    transform: scale(1.2);
  }

  .color-dot-button:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  /* 新規タグ追加用の大きめ色選択ボタン */
  .color-dot-button-large {
    font-size: 2rem;
    line-height: 1;
    padding: 0.25rem;
    background: none;
    border: none;
    cursor: pointer;
    transition: transform 0.15s;
  }

  .color-dot-button-large:hover:not(:disabled) {
    transform: scale(1.2);
  }

  .color-dot-button-large:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  /* 色選択ポップアップ */
  .color-picker-popup {
    position: absolute;
    top: 100%;
    left: 0;
    margin-top: 0.25rem;
    background-color: white;
    border: 1px solid #d1d5db;
    border-radius: 0.5rem;
    padding: 0.5rem;
    display: flex;
    gap: 0.25rem;
    box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1);
    z-index: 10;
  }

  :global(.dark) .color-picker-popup {
    background-color: #374151;
    border-color: #4b5563;
  }

  /* 色選択オプション */
  .color-option {
    font-size: 1.5rem;
    line-height: 1;
    padding: 0;
    background: none;
    border: none;
    cursor: pointer;
    transition: transform 0.15s;
  }

  .color-option:hover {
    transform: scale(1.3);
  }

  /* タグ名表示 */
  .tag-name-display {
    flex: 1;
    font-size: 0.875rem;
    font-weight: 500;
    color: #1f2937;
    min-width: 0;
    cursor: text;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    padding: 0.25rem 0.5rem;
    border-radius: 0.25rem;
    transition: background-color 0.15s;
  }

  :global(.dark) .tag-name-display {
    color: #f3f4f6;
  }

  .tag-name-display:hover {
    background-color: rgba(0, 0, 0, 0.05);
  }

  :global(.dark) .tag-name-display:hover {
    background-color: rgba(255, 255, 255, 0.05);
  }

  /* タグ名入力 */
  .tag-name-input {
    flex: 1;
    font-size: 0.875rem;
    font-weight: 500;
    color: #1f2937;
    min-width: 0;
    padding: 0.25rem 0.5rem;
    border: 2px solid #3b82f6;
    border-radius: 0.25rem;
    background-color: white;
    outline: none;
  }

  :global(.dark) .tag-name-input {
    color: #f3f4f6;
    background-color: #374151;
    border-color: #60a5fa;
  }

  /* 小説数カウント */
  .tag-count-new {
    flex-shrink: 0;
    font-size: 0.75rem;
    font-weight: 600;
    color: #6b7280;
  }

  :global(.dark) .tag-count-new {
    color: #d1d5db;
  }

  /* トリステートトグル */
  .tag-state-toggle {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0;
    background: none;
    border: none;
    cursor: pointer;
  }

  .tag-state-toggle:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  /* トグルトラック */
  .toggle-track {
    position: relative;
    width: 2.5rem;
    height: 1.25rem;
    border-radius: 9999px;
    transition: background-color 0.2s;
  }

  .toggle-off .toggle-track {
    background-color: #d1d5db;
  }

  :global(.dark) .toggle-off .toggle-track {
    background-color: #4b5563;
  }

  .toggle-partial .toggle-track {
    background-color: #f59e0b;
  }

  :global(.dark) .toggle-partial .toggle-track {
    background-color: #d97706;
  }

  .toggle-on .toggle-track {
    background-color: #10b981;
  }

  :global(.dark) .toggle-on .toggle-track {
    background-color: #059669;
  }

  /* トグルサム（丸いボタン） */
  .toggle-thumb {
    position: absolute;
    top: 0.125rem;
    width: 1rem;
    height: 1rem;
    background-color: white;
    border-radius: 9999px;
    transition: transform 0.2s;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
  }

  .toggle-off .toggle-thumb {
    left: 0.125rem;
  }

  .toggle-partial .toggle-thumb {
    left: 0.75rem;
  }

  .toggle-on .toggle-thumb {
    left: 1.375rem;
  }

  /* トグルラベル */
  .toggle-label {
    font-size: 0.75rem;
    font-weight: 600;
    color: #374151;
    white-space: nowrap;
  }

  :global(.dark) .toggle-label {
    color: #e5e7eb;
  }
</style>
