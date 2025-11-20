<!--
  小説更新オプション選択モーダル
  
  更新チェック・再取得のオプションを選択して実行
-->
<script lang="ts">
  import { onMount } from "svelte";

  type UpdateMode = "update" | "force-download";

  interface Props {
    selectedCount: number;
    onConfirm?: (mode: UpdateMode, options: UpdateOptions) => void;
    onCancel?: () => void;
  }

  interface UpdateOptions {
    fromEpisode?: number;
    limit?: number;
  }

  let { selectedCount = 0, onConfirm, onCancel }: Props = $props();

  let isOpen = $state(false);
  let mode = $state<UpdateMode>("update");
  let fromEpisode = $state<number | undefined>(undefined);
  let limit = $state<number | undefined>(undefined);
  let dialog: HTMLDialogElement;

  export function open() {
    isOpen = true;
    mode = "update";
    fromEpisode = undefined;
    limit = undefined;
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
    const options: UpdateOptions = {};
    if (fromEpisode !== undefined && fromEpisode > 0) {
      options.fromEpisode = fromEpisode;
    }
    if (limit !== undefined && limit > 0) {
      options.limit = limit;
    }
    close();
    onConfirm?.(mode, options);
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
  class="rounded-lg shadow-xl backdrop:bg-black backdrop:bg-opacity-50 max-w-2xl w-full p-0"
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
        <!-- 選択数表示 -->
        <div class="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-4">
          <p class="text-sm text-blue-800 dark:text-blue-200">
            <i class="fas fa-info-circle"></i> {selectedCount}件の小説を更新します
          </p>
        </div>

        <!-- 更新モード選択 -->
        <div class="space-y-3">
          <div class="block text-sm font-medium text-gray-700 dark:text-gray-300">
            更新モード
          </div>
          <div class="space-y-2">
            <label
              class="flex items-start space-x-3 p-3 border rounded-lg cursor-pointer transition-colors"
              class:border-green-500={mode === "update"}
              class:bg-green-50={mode === "update"}
              class:border-gray-300={mode !== "update"}
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
              class="flex items-start space-x-3 p-3 border rounded-lg cursor-pointer transition-colors"
              class:border-green-500={mode === "force-download"}
              class:bg-green-50={mode === "force-download"}
              class:border-gray-300={mode !== "force-download"}
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

        <!-- 詳細オプション -->
        <div class="space-y-4 pt-4 border-t border-gray-200 dark:border-gray-700">
          <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300">
            詳細オプション（任意）
          </h4>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <!-- 開始話数 -->
            <div>
              <label for="fromEpisode" class="block text-sm text-gray-600 dark:text-gray-400 mb-2">
                開始話数
              </label>
              <input
                id="fromEpisode"
                type="number"
                bind:value={fromEpisode}
                min="1"
                placeholder="指定しない"
                class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent bg-white dark:bg-gray-700 text-gray-900 dark:text-white"
              />
              <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">
                この話数から取得開始
              </p>
            </div>

            <!-- 取得数制限 -->
            <div>
              <label for="limit" class="block text-sm text-gray-600 dark:text-gray-400 mb-2">
                取得数制限
              </label>
              <input
                id="limit"
                type="number"
                bind:value={limit}
                min="1"
                placeholder="制限なし"
                class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent bg-white dark:bg-gray-700 text-gray-900 dark:text-white"
              />
              <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">
                最大取得話数
              </p>
            </div>
          </div>
        </div>
      </div>

      <!-- フッター -->
      <div class="flex items-center justify-end gap-3 p-6 border-t border-gray-200 dark:border-gray-700">
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
  {/if}
</dialog>

<style>
  dialog::backdrop {
    background-color: rgba(0, 0, 0, 0.5);
  }
</style>
