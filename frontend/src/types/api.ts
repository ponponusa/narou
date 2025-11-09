/**
 * API型定義
 * 
 * バックエンドのREST APIとの連携に使用する型定義
 */

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
 * 小説リスト取得のレスポンス型（DataTables形式）
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
 * キューサイズレスポンス型
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
 * バージョン情報型
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
