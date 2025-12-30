/**
 * API型定義
 *
 * バックエンドのREST APIとの連携に使用する型定義
 */

/**
 * API v2 統一レスポンス型
 */
export interface ApiV2Response<T> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string | null;
  timestamp: string;
}

/**
 * タスクの型定義
 */
export type TaskType = "download" | "convert" | "update" | "remove";
export type TaskStatus =
  | "queued"
  | "running"
  | "paused"
  | "completed"
  | "failed"
  | "canceled";

export interface TaskError {
  message: string;
  class?: string;
  backtrace?: string[];
}

export interface Task {
  id: string;
  type: TaskType;
  novel_id?: number;
  novel_title?: string;
  novel_author?: string;
  status: TaskStatus;
  message?: string;
  created_at: string;
  started_at?: string;
  paused_at?: string;
  completed_at?: string;
  elapsed_time: number;
  error?: TaskError;
  retry_count: number;
  max_retries: number;
  progress: number;
  total_steps?: number;
  current_step: number;
}

export interface TaskSummary {
  current?: Task;
  queued: Task[];
  recent_completed: Task[];
  recent_failed: Task[];
  // 変換専用ワーカーの状態
  convert_current?: Task;
  convert_queued: Task[];
}

/**
 * 小説データの基本型
 */
export interface Novel {
  id: number;
  title: string;
  author: string;
  title_original?: string; // プロモタグ除去前の元タイトル
  author_original?: string; // プロモタグ除去前の元著者
  author_url?: string; // 著者ページURL
  sitename: string;
  site_top_url?: string; // サイトトップURL
  status: string;
  story?: string; // あらすじ
  frozen: boolean;
  tags: string[];
  toc_url: string;
  novel_type?: string;
  general_lastup?: string;
  last_update?: string;
  newest_article_date?: string; // 最新話掲載日
  new_arrivals_date?: string;
  download_date?: string;
  convert_date?: string;
  send_date?: string;
  promo_tags?: string[];
  promo_tags_title?: string[];
  promo_tags_author?: string[];
  general_all_no?: number; // 話数
  length?: number; // 文字数
}

/**
 * 小説リスト取得のレスポンス型（API v2）
 * 全データを一度に取得する設計
 */
export interface NovelsListData {
  novels: Novel[];
  total: number;
}

/**
 * 小説リスト取得のレスポンス型（DataTables形式 - Legacy API用）
 */
export interface NovelsListResponse {
  draw: number;
  recordsTotal: number;
  recordsFiltered: number;
  data: Novel[];
}

/**
 * API エラーレスポンス型
 */
export interface ApiError {
  error: string;
  message?: string;
}

/**
 * キューサイズレスポンス型（API v2）
 */
export interface QueueData {
  total: number;
  web_worker: number;
  worker: number;
  running: boolean;
}

/**
 * キューサイズレスポンス型（Legacy API用）
 */
export interface QueueSizeResponse {
  worker: number;
  web_worker: number;
}

/**
 * タグ情報型
 */
export interface TagInfo {
  name: string;
  count: number;
  color?: string;
}

/**
 * バージョン情報型（API v2）
 */
export interface VersionData {
  narou: string;
  ruby: string;
  latest: string | null;
}

/**
 * バージョン情報型（Legacy API用）
 */
export interface VersionInfo {
  version: string;
  update_available?: boolean;
}

/**
 * ログメッセージ型
 */
export interface LogMessage {
  timestamp: string;
  level: string;
  message: string;
}

/**
 * 小説設定項目の型
 */
export type NovelSettingType =
  | "boolean"
  | "integer"
  | "string"
  | "select"
  | "multiple";

/**
 * 個別小説設定項目
 */
export interface NovelSettingItem {
  name: string;
  type: NovelSettingType;
  value: any;
  original_value: any;
  default_value: any;
  help: string;
  is_forced: boolean;
  select_keys?: string[];
  select_summaries?: string[];
}

/**
 * 置換パターン
 */
export interface ReplacePattern {
  left: string;
  right: string;
}

/**
 * 小説設定取得レスポンス型
 */
export interface NovelSettingsData {
  novel_id: number;
  novel_title: string;
  settings: NovelSettingItem[];
  replace_pattern: [string, string][];
}

/**
 * 小説設定更新リクエスト型
 */
export interface NovelSettingsUpdateRequest {
  settings: Record<string, any>;
  replace_pattern?: ReplacePattern[];
}
