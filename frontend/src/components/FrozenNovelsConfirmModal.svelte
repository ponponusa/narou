<!--
  凍結小説確認モーダル
  
  include_frozen オプションが有効な場合に、
  凍結中の小説が対象に含まれていることを確認するモーダル
-->
<script lang="ts">
  import { onMount } from "svelte";
  import type { Novel } from "../types/api";

  interface Props {
    onConfirm?: (selectedIds: number[]) => void;
    onCancel?: () => void;
  }

  let { onConfirm, onCancel }: Props = $props();

  let isOpen = $state(false);
  let frozenNovels = $state<Novel[]>([]);
  let selectedIds = $state<Set<number>>(new Set());
  let dialog: HTMLDialogElement;

  // 全選択状態
  let isAllSelected = $derived(
    frozenNovels.length > 0 && selectedIds.size === frozenNovels.length
  );

  // 部分選択状態
  let isPartiallySelected = $derived(
    selectedIds.size > 0 && selectedIds.size < frozenNovels.length
  );

  /**
   * モーダルを開く
   * @param novels 確認対象の凍結小説リスト
   */
  export function open(novels: Novel[]) {
    frozenNovels = novels;
    // 初期状態は全て選択
    selectedIds = new Set(novels.map(n => n.id));
    isOpen = true;
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
    const ids = Array.from(selectedIds);
    close();
    onConfirm?.(ids);
  }

  function toggleSelection(id: number) {
    const newSet = new Set(selectedIds);
    if (newSet.has(id)) {
      newSet.delete(id);
    } else {
      newSet.add(id);
    }
    selectedIds = newSet;
  }

  function toggleAll() {
    if (isAllSelected) {
      selectedIds = new Set();
    } else {
      selectedIds = new Set(frozenNovels.map(n => n.id));
    }
  }

  function formatDate(dateString: string | undefined): string {
    if (!dateString) return "不明";
    try {
      const date = new Date(dateString);
      if (isNaN(date.getTime())) return dateString;
      return date.toLocaleDateString("ja-JP", {
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
      });
    } catch {
      return dateString;
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
        <h3 class="text-xl font-semibold text-gray-900 dark:text-white flex items-center gap-2">
          <i class="fas fa-snowflake text-blue-400"></i>
          凍結中の小説の確認
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
      <div class="p-6 space-y-4">
        <!-- 注意メッセージ -->
        <div class="bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-700 rounded-lg p-4">
          <div class="flex items-start gap-3">
            <i class="fas fa-exclamation-triangle text-yellow-600 dark:text-yellow-400 mt-0.5"></i>
            <div class="text-sm text-yellow-800 dark:text-yellow-200">
              <p class="font-medium mb-1">凍結中の小説が更新対象に含まれています</p>
              <p class="text-yellow-700 dark:text-yellow-300">
                凍結中の小説は通常の更新チェックではスキップされます。<br>
                今回だけ更新する小説を選択してください。更新後も凍結状態は維持されます。
              </p>
            </div>
          </div>
        </div>

        <!-- 小説リスト -->
        <div class="space-y-2">
          <!-- 全選択ヘッダー -->
          <div class="flex items-center justify-between px-2 py-1">
            <label class="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={isAllSelected}
                indeterminate={isPartiallySelected}
                onchange={toggleAll}
                class="w-4 h-4 rounded border-gray-300 text-blue-600 focus:ring-blue-500"
              />
              <span class="text-sm font-medium text-gray-700 dark:text-gray-300">
                {#if isAllSelected}
                  すべて選択解除
                {:else}
                  すべて選択
                {/if}
              </span>
            </label>
            <span class="text-sm text-gray-500 dark:text-gray-400">
              {selectedIds.size} / {frozenNovels.length} 件選択中
            </span>
          </div>

          <!-- スクロール可能なリスト -->
          <div class="max-h-64 overflow-y-auto border border-gray-200 dark:border-gray-700 rounded-lg divide-y divide-gray-200 dark:divide-gray-700">
            {#each frozenNovels as novel (novel.id)}
              <label
                class="flex items-center gap-3 p-3 hover:bg-gray-50 dark:hover:bg-gray-700/50 cursor-pointer transition-colors {selectedIds.has(novel.id) ? 'bg-blue-50 dark:bg-blue-900/20' : ''}"
              >
                <input
                  type="checkbox"
                  checked={selectedIds.has(novel.id)}
                  onchange={() => toggleSelection(novel.id)}
                  class="w-4 h-4 rounded border-gray-300 text-blue-600 focus:ring-blue-500 flex-shrink-0"
                />
                <div class="flex-1 min-w-0">
                  <div class="flex items-center gap-2">
                    <span class="font-medium text-gray-900 dark:text-white truncate">
                      {novel.title}
                    </span>
                    <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200 flex-shrink-0">
                      <i class="fas fa-snowflake mr-1"></i>凍結中
                    </span>
                  </div>
                  <div class="flex items-center gap-4 mt-1 text-xs text-gray-500 dark:text-gray-400">
                    <span class="truncate">
                      <i class="fas fa-user mr-1"></i>{novel.author}
                    </span>
                    <span class="flex-shrink-0">
                      <i class="fas fa-calendar-alt mr-1"></i>
                      最終更新: {formatDate(novel.general_lastup || novel.last_update)}
                    </span>
                  </div>
                </div>
              </label>
            {/each}
          </div>
        </div>
      </div>

      <!-- フッター -->
      <div class="flex items-center justify-between gap-3 p-6 border-t border-gray-200 dark:border-gray-700">
        <!-- 説明テキスト -->
        <div class="text-sm text-gray-600 dark:text-gray-400">
          {#if selectedIds.size === 0}
            <i class="fas fa-info-circle text-gray-400"></i>
            凍結小説は更新されません
          {:else}
            <i class="fas fa-check-circle text-blue-500"></i>
            {selectedIds.size}件の凍結小説を更新対象に含めます
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
            class="px-6 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
          >
            <i class="fas fa-check"></i>
            {#if selectedIds.size === 0}
              凍結小説なしで続行
            {:else}
              選択を確定
            {/if}
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
