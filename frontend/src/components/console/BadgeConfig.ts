/**
 * コンソールパネル用バッジ設定
 */

export type BadgeType =
  | "download"
  | "convert"
  | "skip"
  | "other"
  | "info"
  | "read"
  | "novelId";

export interface BadgeConfig {
  label: string;
  title: string;
  bgClass: string;
  textClass: string;
  borderClass: string;
}

/**
 * バッジ設定の定義
 */
export const BADGE_CONFIGS: Record<BadgeType, BadgeConfig> = {
  download: {
    label: "DL",
    title: "ダウンロード",
    bgClass: "bg-blue-900/50",
    textClass: "text-blue-300",
    borderClass: "border-blue-700/50",
  },
  convert: {
    label: "変換",
    title: "変換処理",
    bgClass: "bg-green-900/50",
    textClass: "text-green-300",
    borderClass: "border-green-700/50",
  },
  skip: {
    label: "SKIP",
    title: "変換スキップ",
    bgClass: "bg-yellow-900/50",
    textClass: "text-yellow-300",
    borderClass: "border-yellow-700/50",
  },
  other: {
    label: "OTHER",
    title: "その他の処理",
    bgClass: "bg-purple-900/50",
    textClass: "text-purple-300",
    borderClass: "border-purple-700/50",
  },
  info: {
    label: "INFO",
    title: "情報",
    bgClass: "bg-gray-700/50",
    textClass: "text-gray-400",
    borderClass: "border-gray-600/50",
  },
  read: {
    label: "READ",
    title: "章ダウンロード中",
    bgClass: "bg-blue-900/50",
    textClass: "text-blue-300",
    borderClass: "border-blue-700/50",
  },
  novelId: {
    label: "", // 動的に設定
    title: "小説ID",
    bgClass: "bg-gray-700",
    textClass: "text-gray-300",
    borderClass: "border-gray-600",
  },
} as const;

/**
 * processType からバッジタイプを取得
 */
export function getBadgeTypeFromProcessType(
  processType: "download" | "convert" | "skip" | "other" | undefined
): BadgeType | null {
  if (!processType) return null;
  return processType;
}

/**
 * バッジの CSS クラスを生成
 */
export function getBadgeClasses(config: BadgeConfig): string {
  return `shrink-0 px-1.5 py-0.5 rounded text-[10px] leading-none ${config.bgClass} ${config.textClass} border ${config.borderClass}`;
}
