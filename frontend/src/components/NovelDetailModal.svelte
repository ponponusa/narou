<script lang="ts">
  import { onMount } from "svelte";
  import type { Novel } from "../types/api";
  import {
    downloadNovel,
    convertNovel,
    removeNovel,
    freezeNovel,
    unfreezeNovel,
    getNovelStory,
  } from "../lib/api";

  // Props
  let toast: {
    show: (
      message: string,
      type: "success" | "error" | "info" | "warning",
      duration?: number,
    ) => void;
  } | null = null;

  // モーダル表示状態
  let showModal = $state(false);
  let novel = $state<Novel | null>(null);
  let storyContent = $state<string>("");
  let loadingStory = $state(false);

  // 処理中フラグ
  let downloading = $state(false);
  let converting = $state(false);
  let freezing = $state(false);
  let deleting = $state(false);

  // コールバック
  let onUpdateCallback: (() => void) | null = null;
  let onDeleteCallback: (() => void) | null = null;
  let onTagEditCallback: ((novelId: number) => void) | null = null;
  let onConversionSettingsCallback:
    | ((novelId: number, title: string) => void)
    | null = null;

  /**
   * Toast参照を設定
   */
  export function setToast(toastInstance: any) {
    toast = toastInstance;
  }

  /**
   * モーダルを開く
   */
  export async function open(
    novelData: Novel,
    callbacks?: {
      onUpdate?: () => void;
      onDelete?: () => void;
      onTagEdit?: (novelId: number) => void;
      onConversionSettings?: (novelId: number, title: string) => void;
    },
  ) {
    novel = novelData;
    showModal = true;
    storyContent = "";

    if (callbacks) {
      onUpdateCallback = callbacks.onUpdate || null;
      onDeleteCallback = callbacks.onDelete || null;
      onTagEditCallback = callbacks.onTagEdit || null;
      onConversionSettingsCallback = callbacks.onConversionSettings || null;
    }

    // あらすじを取得
    loadingStory = true;
    try {
      const result = await getNovelStory(novelData.id);
      storyContent = result.story;
    } catch (err) {
      console.error("あらすじの取得に失敗しました:", err);
      storyContent = "";
    } finally {
      loadingStory = false;
    }
  }

  /**
   * モーダルを閉じる
   */
  function closeModal() {
    showModal = false;
    novel = null;
    downloading = false;
    converting = false;
    freezing = false;
    deleting = false;
  }

  /**
   * EPUBダウンロード
   */
  function handleDownloadEpub() {
    if (!novel) return;

    const filename = `${novel.title}.epub`;
    const downloadUrl = `http://localhost:5678/novels/${novel.id}/download`;

    // ダウンロード用のリンクを生成してクリック
    const link = document.createElement("a");
    link.href = downloadUrl;
    link.download = filename;
    link.click();

    toast?.show(`${novel.title} のEPUBダウンロードを開始しました`, "info");
  }

  /**
   * 再取得
   */
  async function handleRedownload() {
    if (!novel || downloading) return;

    if (!confirm(`「${novel.title}」を再取得しますか？`)) return;

    downloading = true;
    try {
      await downloadNovel(novel.id);
      toast?.show(`${novel.title} の再取得を開始しました`, "success");
      onUpdateCallback?.();
    } catch (err) {
      const message =
        err instanceof Error ? err.message : "再取得に失敗しました";
      toast?.show(message, "error");
    } finally {
      downloading = false;
    }
  }

  /**
   * 変換再実行
   */
  async function handleReconvert() {
    if (!novel || converting) return;

    if (!confirm(`「${novel.title}」を変換しますか？`)) return;

    converting = true;
    try {
      await convertNovel(novel.id);
      toast?.show(`${novel.title} の変換を開始しました`, "success");
      onUpdateCallback?.();
    } catch (err) {
      const message = err instanceof Error ? err.message : "変換に失敗しました";
      toast?.show(message, "error");
    } finally {
      converting = false;
    }
  }

  /**
   * タグ編集
   */
  function handleEditTags() {
    if (!novel) return;
    onTagEditCallback?.(novel.id);
    closeModal();
  }

  /**
   * 個別設定
   */
  function handleConversionSettings() {
    if (!novel) return;
    onConversionSettingsCallback?.(novel.id, novel.title);
    closeModal();
  }

  /**
   * 凍結/凍結解除
   */
  async function handleFreeze() {
    if (!novel || freezing) return;

    const action = novel.frozen ? "凍結解除" : "凍結";
    if (!confirm(`「${novel.title}」を${action}しますか？`)) return;

    freezing = true;
    try {
      if (novel.frozen) {
        await unfreezeNovel(novel.id);
        toast?.show(`${novel.title} の凍結を解除しました`, "success");
      } else {
        await freezeNovel(novel.id);
        toast?.show(`${novel.title} を凍結しました`, "success");
      }
      onUpdateCallback?.();
      closeModal();
    } catch (err) {
      const message =
        err instanceof Error ? err.message : `${action}に失敗しました`;
      toast?.show(message, "error");
    } finally {
      freezing = false;
    }
  }

  /**
   * 削除
   */
  async function handleDelete() {
    if (!novel || deleting) return;

    if (
      !confirm(
        `「${novel.title}」を削除しますか？\n\nこの操作は取り消せません。`,
      )
    )
      return;

    deleting = true;
    try {
      await removeNovel(novel.id);
      toast?.show(`${novel.title} を削除しました`, "success");
      onDeleteCallback?.();
      closeModal();
    } catch (err) {
      const message = err instanceof Error ? err.message : "削除に失敗しました";
      toast?.show(message, "error");
    } finally {
      deleting = false;
    }
  }

  /**
   * 日時フォーマット
   */
  function formatDate(dateString: string | number | undefined): string {
    if (!dateString) return "---";
    try {
      // 数値の場合はUNIXタイムスタンプ(秒)なので1000倍してミリ秒に変換
      const timestamp =
        typeof dateString === "number" ? dateString * 1000 : dateString;
      const date = new Date(timestamp);
      return date.toLocaleString("ja-JP", {
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
      });
    } catch {
      return "---";
    }
  }

  /**
   * 数値フォーマット（カンマ区切り）
   */
  function formatNumber(num: number | undefined): string {
    if (num === undefined) return "---";
    return num.toLocaleString("ja-JP");
  }

  onMount(() => {
    // ESCキーでモーダルを閉じる
    const handleKeydown = (e: KeyboardEvent) => {
      if (e.key === "Escape" && showModal) {
        closeModal();
      }
    };
    window.addEventListener("keydown", handleKeydown);
    return () => window.removeEventListener("keydown", handleKeydown);
  });
</script>

{#if showModal && novel}
  <!-- モーダルオーバーレイ -->
  <div
    class="fixed inset-0 bg-black bg-opacity-50 flex items-start justify-center z-50 p-4 overflow-y-auto"
    onclick={(e) => e.target === e.currentTarget && closeModal()}
    onkeydown={(e) => e.key === 'Escape' && closeModal()}
    role="button"
    tabindex="-1"
    aria-label="モーダルを閉じる"
  >
    <!-- モーダルコンテンツ -->
    <div
      class="bg-white dark:bg-gray-800 rounded-lg shadow-xl max-w-4xl w-full my-8"
      onclick={(e) => e.stopPropagation()}
      onkeydown={(e) => e.stopPropagation()}
      role="dialog"
      aria-modal="true"
      tabindex="0"
    >
      <!-- ヘッダー -->
      <div
        class="flex items-center justify-between p-4 border-b border-gray-200 dark:border-gray-700"
      >
        <h2 class="text-xl font-semibold text-gray-900 dark:text-white">
          小説詳細
        </h2>
        <div class="flex items-center gap-3">
          <a
            href={novel.toc_url}
            target="_blank"
            rel="noopener noreferrer"
            class="text-blue-600 dark:text-blue-400 hover:underline flex items-center gap-1.5"
            title="小説サイトを開く"
          >
            <i class="fas fa-external-link-alt"></i>
            <span>小説サイト</span>
          </a>
          <button
            onclick={closeModal}
            class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 transition-colors"
            aria-label="閉じる"
          >
            <i class="fas fa-times text-xl"></i>
          </button>
        </div>
      </div>

      <!-- 本文 -->
      <div class="p-6 max-h-[70vh] overflow-y-auto">
        <!-- プロモタグ -->
        {#if novel.promo_tags && novel.promo_tags.length > 0}
          <div class="mb-4">
            <dd class="flex flex-wrap gap-2">
              {#each novel.promo_tags as tag}
                <span
                  class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200"
                >
                  {tag}
                </span>
              {/each}
            </dd>
          </div>
        {/if}

        <!-- タイトル -->
        <div class="mb-6">
          <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-2">
            {novel.title}
          </h3>
          {#if novel.promo_tags_title}
            <p class="text-sm text-gray-600 dark:text-gray-400">
              元タイトル: {novel.promo_tags_title}
            </p>
          {/if}

          <!-- あらすじ -->
          {#if loadingStory}
            <div class="mt-4 p-4 bg-gray-50 dark:bg-gray-700 rounded-lg">
              <h4
                class="text-sm font-medium text-gray-600 dark:text-gray-400 mb-2"
              >
                あらすじ
              </h4>
              <div
                class="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400"
              >
                <i class="fas fa-spinner fa-spin"></i>
                <span>読み込み中...</span>
              </div>
            </div>
          {:else if storyContent}
            <div class="mt-4 p-4 bg-gray-50 dark:bg-gray-700 rounded-lg">
              <h4
                class="text-sm font-medium text-gray-600 dark:text-gray-400 mb-2"
              >
                あらすじ
              </h4>
              <div
                class="text-sm text-gray-700 dark:text-gray-300 whitespace-pre-wrap leading-relaxed"
              >
                {@html storyContent}
              </div>
            </div>
          {/if}
        </div>

        <!-- 基本情報 -->
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
          <div class="p-3 bg-gray-50 dark:bg-gray-700 rounded-lg">
            <dt class="text-sm font-medium text-gray-600 dark:text-gray-400">
              著者
            </dt>
            <dd class="mt-1 text-base text-gray-900 dark:text-white">
              {novel.author}
              {#if novel.promo_tags_author}
                <span class="text-sm text-gray-600 dark:text-gray-400">
                  (元: {novel.promo_tags_author})
                </span>
              {/if}
            </dd>
          </div>

          <div class="p-3 bg-gray-50 dark:bg-gray-700 rounded-lg">
            <dt class="text-sm font-medium text-gray-600 dark:text-gray-400">
              掲載サイト
            </dt>
            <dd class="mt-1 text-base text-gray-900 dark:text-white">
              {novel.sitename}
            </dd>
          </div>

          <div class="p-3 bg-gray-50 dark:bg-gray-700 rounded-lg">
            <dt class="text-sm font-medium text-gray-600 dark:text-gray-400">
              状態
            </dt>
            <dd class="mt-1">
              <span
                class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200"
              >
                {novel.status || "---"}
              </span>
              {#if novel.frozen}
                <span
                  class="ml-2 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200"
                >
                  凍結中
                </span>
              {/if}
            </dd>
          </div>

          <div class="p-3 bg-gray-50 dark:bg-gray-700 rounded-lg">
            <dt class="text-sm font-medium text-gray-600 dark:text-gray-400">
              小説ID
            </dt>
            <dd class="mt-1 text-base text-gray-900 dark:text-white">
              #{novel.id}
            </dd>
          </div>

          <div class="p-3 bg-gray-50 dark:bg-gray-700 rounded-lg">
            <dt class="text-sm font-medium text-gray-600 dark:text-gray-400">
              話数
            </dt>
            <dd class="mt-1 text-base text-gray-900 dark:text-white">
              {formatNumber(novel.general_all_no)} 話
            </dd>
          </div>

          <div class="p-3 bg-gray-50 dark:bg-gray-700 rounded-lg">
            <dt class="text-sm font-medium text-gray-600 dark:text-gray-400">
              文字数
            </dt>
            <dd class="mt-1 text-base text-gray-900 dark:text-white">
              {formatNumber(novel.length)} 文字
            </dd>
          </div>

          <div class="p-3 bg-gray-50 dark:bg-gray-700 rounded-lg">
            <dt class="text-sm font-medium text-gray-600 dark:text-gray-400">
              最新話掲載日
            </dt>
            <dd class="mt-1 text-base text-gray-900 dark:text-white">
              {formatDate(novel.general_lastup)}
            </dd>
          </div>

          <div class="p-3 bg-gray-50 dark:bg-gray-700 rounded-lg">
            <dt class="text-sm font-medium text-gray-600 dark:text-gray-400">
              更新チェック日
            </dt>
            <dd class="mt-1 text-base text-gray-900 dark:text-white">
              {formatDate(novel.last_update)}
            </dd>
          </div>

          <div class="p-3 bg-gray-50 dark:bg-gray-700 rounded-lg">
            <dt class="text-sm font-medium text-gray-600 dark:text-gray-400">
              ダウンロード日
            </dt>
            <dd class="mt-1 text-base text-gray-900 dark:text-white">
              {formatDate(novel.download_date)}
            </dd>
          </div>

          <div class="p-3 bg-gray-50 dark:bg-gray-700 rounded-lg">
            <dt class="text-sm font-medium text-gray-600 dark:text-gray-400">
              変換日
            </dt>
            <dd class="mt-1 text-base text-gray-900 dark:text-white">
              {formatDate(novel.convert_date)}
            </dd>
          </div>
        </div>

        <!-- タグ -->
        {#if novel.tags && novel.tags.length > 0}
          <div class="mb-6">
            <dt
              class="text-sm font-medium text-gray-600 dark:text-gray-400 mb-2"
            >
              タグ
            </dt>
            <dd class="flex flex-wrap gap-2">
              {#each novel.tags as tag}
                <span
                  class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200"
                >
                  {tag}
                </span>
              {/each}
            </dd>
          </div>
        {/if}
      </div>

      <!-- フッター（アクションボタン） -->
      <div
        class="flex flex-wrap gap-2 p-4 bg-gray-50 dark:bg-gray-700 border-t border-gray-200 dark:border-gray-600"
      >
        <button
          onclick={handleDownloadEpub}
          class="px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700 transition-colors flex items-center gap-2"
          title="EPUBをダウンロード"
        >
          <i class="fas fa-download"></i>
          EPUB
        </button>

        <button
          onclick={handleRedownload}
          disabled={downloading}
          class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
          title="再取得"
        >
          {#if downloading}
            <i class="fas fa-spinner fa-spin"></i>
          {:else}
            <i class="fas fa-sync-alt"></i>
          {/if}
          再取得
        </button>

        <button
          onclick={handleReconvert}
          disabled={converting}
          class="px-4 py-2 bg-purple-600 text-white rounded-md hover:bg-purple-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
          title="変換再実行"
        >
          {#if converting}
            <i class="fas fa-spinner fa-spin"></i>
          {:else}
            <i class="fas fa-sync"></i>
          {/if}
          変換
        </button>

        <button
          onclick={handleEditTags}
          class="px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 transition-colors flex items-center gap-2"
          title="タグ編集"
        >
          <i class="fas fa-tags"></i>
          タグ編集
        </button>

        <button
          onclick={handleConversionSettings}
          class="px-4 py-2 bg-gray-600 text-white rounded-md hover:bg-gray-700 transition-colors flex items-center gap-2"
          title="個別設定"
        >
          <i class="fas fa-cog"></i>
          個別設定
        </button>

        <button
          onclick={handleFreeze}
          disabled={freezing}
          class="px-4 py-2 bg-yellow-600 text-white rounded-md hover:bg-yellow-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
          title={novel.frozen ? "凍結解除" : "凍結"}
        >
          {#if freezing}
            <i class="fas fa-spinner fa-spin"></i>
          {:else if novel.frozen}
            <i class="fas fa-unlock"></i>
          {:else}
            <i class="fas fa-lock"></i>
          {/if}
          {novel.frozen ? "凍結解除" : "凍結"}
        </button>

        <button
          onclick={handleDelete}
          disabled={deleting}
          class="px-4 py-2 bg-red-600 text-white rounded-md hover:bg-red-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
          title="削除"
        >
          {#if deleting}
            <i class="fas fa-spinner fa-spin"></i>
          {:else}
            <i class="fas fa-trash"></i>
          {/if}
          削除
        </button>

        <button
          onclick={closeModal}
          class="ml-auto px-4 py-2 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-600 rounded-md transition-colors"
        >
          閉じる
        </button>
      </div>
    </div>
  </div>
{/if}
