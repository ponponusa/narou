<!--
  ログエントリコンポーネント

  コンソールログの1行を表示するための再利用可能なコンポーネント
-->
<script lang="ts">
  import LogBadge from "./LogBadge.svelte";
  import type { BadgeType } from "./BadgeConfig";

  interface LogEntry {
    id: number;
    timestamp: Date;
    console: "stdout" | "stdout2" | "convert";
    message: string;
    isProgress?: boolean;
    progressKey?: string;
    processType?: "download" | "convert" | "other";
    novelId?: string;
  }

  interface Props {
    log: LogEntry;
    formatTime: (date: Date) => string;
    formatConsoleType: (type: "stdout" | "stdout2" | "convert") => string;
    formatMessage: (message: string, progressKey?: string) => string;
    /** 変換ペイン用（黄色表示を無効化） */
    isConvertPane?: boolean;
  }

  let {
    log,
    formatTime,
    formatConsoleType,
    formatMessage,
    isConvertPane = false,
  }: Props = $props();

  // バッジタイプを決定
  const badgeType = $derived.by((): BadgeType | null => {
    if (log.processType) {
      return log.processType as BadgeType;
    }
    if (log.progressKey !== "progress-chapter-download") {
      return "info";
    }
    return null;
  });

  // テキストカラークラス
  const textColorClass = $derived.by(() => {
    if (isConvertPane) {
      return "text-gray-300";
    }
    return log.console === "stdout2" && log.processType !== "convert"
      ? "text-yellow-400"
      : "text-gray-300";
  });
</script>

<div
  class="flex gap-2 hover:bg-gray-800 dark:hover:bg-gray-900 px-2 py-1 rounded"
>
  <span class="text-gray-500 shrink-0">
    {formatTime(log.timestamp)}
  </span>
  <span class="text-gray-400 shrink-0 w-16">
    {formatConsoleType(log.console)}
  </span>

  {#if badgeType}
    <LogBadge type={badgeType} />
  {/if}

  {#if log.novelId}
    <LogBadge type="novelId" novelId={log.novelId} />
  {/if}

  {#if log.progressKey === "progress-chapter-download"}
    <LogBadge type="read" />
  {/if}

  <span
    class="flex-1 whitespace-nowrap overflow-hidden text-ellipsis {textColorClass}"
  >
    {@html formatMessage(log.message, log.progressKey)}
  </span>
</div>
