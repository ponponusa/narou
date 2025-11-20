<!--
  小説更新オプション選択モーダル
  
  更新チェック・再取得のオプションを選択して実行
-->
<script lang="ts">
  import { onMount } from "svelte";
  import { getTagList } from "../lib/api";
  import type { TagInfo, Novel } from "../types/api";

  type UpdateMode = "update" | "force-download";

  interface Props {
    selectedCount: number;
    allNovels?: Novel[];
    selectedIds?: Set<number>;
    onConfirm?: (mode: UpdateMode, options: UpdateOptions) => void;
    onCancel?: () => void;
  }

  interface UpdateOptions {
    convertAfterUpdate?: boolean;
    createBackup?: boolean;
    includeFrozen?: boolean;
    filterByTags?: string[];
  }

  let { selectedCount = 0, allNovels = [], selectedIds = new Set(), onConfirm, onCancel }: Props = $props();

  let isOpen = $state(false);
  let mode = $state<UpdateMode>("update");
  let convertAfterUpdate = $state(true);
  let createBackup = $state(false);
  let includeFrozen = $state(false);
  let selectedTags = $state<string[]>([]);
  let allTags = $state<TagInfo[]>([]);
  let dialog: HTMLDialogElement;

  // 実際の対象件数を計算
  let effectiveCount = $derived.by(() => {
    if (selectedTags.length === 0 && includeFrozen === false) {
      return selectedCount;
    }
    
    if (!allNovels || allNovels.length === 0) {
      return selectedCount;
    }

    let count = 0;
    for (const novel of allNovels) {
      // 選択されている小説のみを対象
      if (!selectedIds.has(novel.id)) continue;
      
      // タグフィルター
      if (selectedTags.length > 0) {
        const novelTags = novel.tags || [];
        const hasMatchingTag = selectedTags.some(tag => novelTags.includes(tag));
        if (!hasMatchingTag) continue;
      }
      
      // 凍結フィルター（includeFrozenがfalseの場合は凍結中を除外）
      if (includeFrozen === false && novel.frozen) continue;
      
      count++;
    }
    
    return count;
  });

  export async function open() {
    isOpen = true;
    mode = "update";
    convertAfterUpdate = true;
    createBackup = false;
    includeFrozen = false;
    selectedTags = [];
    
    // タグリストを取得
    try {
      allTags = await getTagList();
    } catch (err) {
      console.error("Failed to load tags:", err);
      allTags = [];
    }
    
    dialog?.showModal();
  }

  export function close() {
    isOpen = false;
    dialog?.close();
  }

  function handleCancel() {
    close();
    onCancel?.();
  }

  function handleConfirm() {
    const options: UpdateOptions = {
      convertAfterUpdate,
      createBackup,
      includeFrozen,
      filterByTags: selectedTags.length > 0 ? selectedTags : undefined,
    };
    close();
    onConfirm?.(mode, options);
  }

  function toggleTag(tagName: string) {
    if (selectedTags.includes(tagName)) {
      selectedTags = selectedTags.filter(t => t !== tagName);
    } else {
      selectedTags = [...selectedTags, tagName];
    }
  }

  function handleBackdropClick(e: MouseEvent) {
    if (e.target === dialog) {
      handleCancel();
    }
  }

  onMount(() => {
    dialog?.addEventListener("click", handleBackdropClick);
    return () => {
      dialog?.removeEventListener("click", handleBackdropClick);
    };
  });
</script>

<dialog
  bind:this={dialog}
  class="rounded-lg shadow-xl backdrop:bg-black backdrop:bg-opacity-50 max-w-2xl w-full p-0 m-auto"
>
  {#if isOpen}
    <div class="bg-white dark:bg-gray-800 rounded-lg">
      <!-- ヘッダー -->
      <div class="flex items-center justify-between p-6 border-b border-gray-200 dark:border-gray-700">
        <h3 class="text-xl font-semibold text-gray-900 dark:text-white">
          小説の更新オプション
        </h3>
        <button
          onclick={handleCancel}
          class="text-gray-400 hover:text-gray-500 dark:hover:text-gray-300 transition-colors"
          title="閉じる"
          aria-label="モーダルを閉じる"
        >
          <i class="fas fa-times"></i>
        </button>
      </div>

      <!-- ボディ -->
      <div class="p-6 space-y-6">
        <!-- 更新モード選択 -->
        <div class="space-y-3">
          <div class="block text-sm font-medium text-gray-700 dark:text-gray-300">
            更新モード
          </div>
          <div class="flex flex-col sm:flex-row gap-2">
            <label
              class={`flex flex-1 items-start space-x-3 p-3 border rounded-lg cursor-pointer transition-colors ${
                mode === "update"
                  ? "border-green-500 bg-green-50 dark:bg-green-900/20"
                  : "border-gray-300 dark:border-gray-600"
              }`}
            >
              <input
                type="radio"
                bind:group={mode}
                value="update"
                class="mt-1"
              />
              <div class="flex-1">
                <div class="font-medium text-gray-900 dark:text-white">
                  <i class="fas fa-sync text-green-600"></i> 更新チェック
                </div>
                <div class="text-sm text-gray-600 dark:text-gray-400 mt-1">
                  新着話数のみ取得します（推奨）
                </div>
              </div>
            </label>

            <label
              class={`flex flex-1 items-start space-x-3 p-3 border rounded-lg cursor-pointer transition-colors ${
                mode === "force-download"
                  ? "border-green-500 bg-green-50 dark:bg-green-900/20"
                  : "border-gray-300 dark:border-gray-600"
              }`}
            >
              <input
                type="radio"
                bind:group={mode}
                value="force-download"
                class="mt-1"
              />
              <div class="flex-1">
                <div class="font-medium text-gray-900 dark:text-white">
                  <i class="fas fa-cloud-download-alt text-green-700"></i> 再取得
                </div>
                <div class="text-sm text-gray-600 dark:text-gray-400 mt-1">
                  全話を再ダウンロードします
                </div>
              </div>
            </label>
          </div>
        </div>

        <!-- 更新オプション -->
        <div class="space-y-4 pt-4 border-t border-gray-200 dark:border-gray-700">
          <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300">
            更新オプション
          </h4>

          <div class="space-y-3">
            <!-- 変換も同時実行 -->
            <label class="flex items-start space-x-3 cursor-pointer">
              <input
                type="checkbox"
                bind:checked={convertAfterUpdate}
                class="mt-1"
              />
              <div class="flex-1">
                <div class="text-sm font-medium text-gray-900 dark:text-white">
                  <i class="fas fa-file-export text-blue-600"></i> 更新後に変換も実行
                </div>
                <div class="text-xs text-gray-600 dark:text-gray-400 mt-1">
                  更新完了後、自動的に EPUB 変換を実行します
                </div>
              </div>
            </label>

            <!-- バックアップ作成 -->
            <label class="flex items-start space-x-3 cursor-pointer">
              <input
                type="checkbox"
                bind:checked={createBackup}
                class="mt-1"
              />
              <div class="flex-1">
                <div class="text-sm font-medium text-gray-900 dark:text-white">
                  <i class="fas fa-save text-yellow-600"></i> 更新前にバックアップを作成
                </div>
                <div class="text-xs text-gray-600 dark:text-gray-400 mt-1">
                  更新前に現在のデータをバックアップします
                </div>
              </div>
            </label>

            <!-- 凍結中も含める -->
            <label class="flex items-start space-x-3 cursor-pointer">
              <input
                type="checkbox"
                bind:checked={includeFrozen}
                class="mt-1"
              />
              <div class="flex-1">
                <div class="text-sm font-medium text-gray-900 dark:text-white">
                  <i class="fas fa-snowflake text-blue-400"></i> 凍結中の小説も更新対象に含める
                </div>
                <div class="text-xs text-gray-600 dark:text-gray-400 mt-1">
                  通常はスキップされる凍結中の小説も更新します
                </div>
              </div>
            </label>
          </div>
        </div>

        <!-- タグフィルター -->
        {#if allTags.length > 0}
          <div class="space-y-4 pt-4 border-t border-gray-200 dark:border-gray-700">
            <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300">
              タグで絞り込み（任意）
            </h4>
            <p class="text-xs text-gray-600 dark:text-gray-400">
              特定のタグを持つ小説のみを更新対象にできます
            </p>

            <div class="flex flex-wrap gap-2 max-h-40 overflow-y-auto p-2 bg-gray-50 dark:bg-gray-900 rounded-lg">
              {#each allTags as tag}
                <button
                  type="button"
                  onclick={() => toggleTag(tag.name)}
                  class="px-3 py-1 text-sm rounded-full transition-colors"
                  class:bg-purple-600={selectedTags.includes(tag.name)}
                  class:text-white={selectedTags.includes(tag.name)}
                  class:bg-gray-200={!selectedTags.includes(tag.name)}
                  class:dark:bg-gray-700={!selectedTags.includes(tag.name)}
                  class:text-gray-700={!selectedTags.includes(tag.name)}
                  class:dark:text-gray-300={!selectedTags.includes(tag.name)}
                  class:hover:bg-purple-500={selectedTags.includes(tag.name)}
                  class:hover:bg-gray-300={!selectedTags.includes(tag.name)}
                  class:dark:hover:bg-gray-600={!selectedTags.includes(tag.name)}
                >
                  {#if selectedTags.includes(tag.name)}
                    <i class="fas fa-check-circle mr-1"></i>
                  {/if}
                  {tag.name} ({tag.count})
                </button>
              {/each}
            </div>

            {#if selectedTags.length > 0}
              <div class="text-xs text-purple-600 dark:text-purple-400">
                <i class="fas fa-filter"></i> 選択中のタグ: {selectedTags.join(", ")}
                <button
                  type="button"
                  onclick={() => selectedTags = []}
                  class="ml-2 underline hover:no-underline"
                >
                  クリア
                </button>
              </div>
            {/if}
          </div>
        {/if}
      </div>

      <!-- フッター -->
      <div class="flex items-center justify-between gap-3 p-6 border-t border-gray-200 dark:border-gray-700">
        <!-- 対象件数表示 -->
        <div class="text-sm text-gray-700 dark:text-gray-300">
          <i class="fas fa-info-circle text-blue-600 dark:text-blue-400"></i>
          {#if selectedTags.length > 0 || includeFrozen}
            対象: <span class="font-semibold text-blue-600 dark:text-blue-400">{effectiveCount}件</span>
            {#if effectiveCount !== selectedCount}
              <span class="text-xs ml-1">（選択: {selectedCount}件）</span>
            {/if}
          {:else}
            対象: <span class="font-semibold text-blue-600 dark:text-blue-400">{selectedCount}件</span>
          {/if}
        </div>
        
        <!-- アクションボタン -->
        <div class="flex gap-3">
          <button
            onclick={handleCancel}
            class="px-4 py-2 text-gray-700 dark:text-gray-300 bg-white dark:bg-gray-700 border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-600 transition-colors"
          >
            キャンセル
          </button>
          <button
            onclick={handleConfirm}
            class="px-6 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors"
          >
            <i class="fas fa-check"></i> 実行
          </button>
        </div>
      </div>
    </div>
  {/if}
</dialog>

<style>
  dialog::backdrop {
    background-color: rgba(0, 0, 0, 0.5);
  }
</style>
