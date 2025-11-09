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
 * 小説データの基本型
 */
export interface Novel {
  id: number;
  title: string;
  author: string;
  sitename: string;
  status: string;
  frozen: boolean;
  tags: string[];
  toc_url: string;
  novel_type?: string;
  general_lastup?: string;
  last_update?: string;
  new_arrivals_date?: string;
  download_date?: string;
  convert_date?: string;
  send_date?: string;
}

/**
 * 小説リスト取得のレスポンス型（API v2）
 */
export interface NovelsListData {
  novels: Novel[];
  total: number;
  page: number;
  per_page: number;
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
