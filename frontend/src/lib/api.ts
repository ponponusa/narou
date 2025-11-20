/**
 * API クライアント
 * 
 * バックエンドの REST API とやり取りするためのユーティリティ関数群
 */

import type { 
  Novel,
  ApiV2Response,
  NovelsListData,
  NovelsListResponse, 
  ApiError,
  QueueData,
  QueueSizeResponse,
  TagInfo,
  VersionData,
  VersionInfo,
  LogMessage,
  Task,
  TaskSummary,
  TaskStatus
} from '../types/api';

export type { TagInfo, Task, TaskSummary, TaskStatus };

// 開発時はViteのプロキシを使用するため空文字列
// 本番時は環境変数で指定されたURLを使用
const API_BASE_URL = import.meta.env.PUBLIC_API_BASE_URL || '';

/**
 * API v2 レスポンスの処理
 */
function handleApiV2Response<T>(response: ApiV2Response<T>): T {
  if (!response.success) {
    throw new Error(response.error || response.message || 'Unknown error');
  }
  if (response.data === undefined) {
    throw new Error('No data in response');
  }
  return response.data;
}

/**
 * API v2 リクエストの基本関数
 */
async function fetchApiV2<T>(
  endpoint: string, 
  options: RequestInit = {}
): Promise<T> {
  const url = endpoint.startsWith('http') ? endpoint : `${API_BASE_URL}${endpoint}`;
  
  const response = await fetch(url, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...options.headers,
    },
  });

  if (!response.ok) {
    let errorMessage = `${response.status} ${response.statusText}`;
    
    try {
      const error: ApiError = await response.json();
      // エラーメッセージを抽出（複数のパターンに対応）
      if (typeof error.message === 'string' && error.message) {
        errorMessage = error.message;
      } else if (typeof error.error === 'string' && error.error) {
        errorMessage = error.error;
      } else if (error.error && typeof error.error === 'object') {
        // error.error がオブジェクトの場合（ネストされたエラー）
        const nestedError = error.error as any;
        errorMessage = nestedError.message || nestedError.error || JSON.stringify(error.error);
      }
    } catch (parseError) {
      // JSONパースに失敗した場合はデフォルトメッセージを使用
      console.error('Error response parse failed:', parseError);
    }
    
    const err = new Error(errorMessage);
    // HTTPステータスコードを保持
    (err as any).status = response.status;
    throw err;
  }

  const apiResponse: ApiV2Response<T> = await response.json();
  return handleApiV2Response(apiResponse);
}

/**
 * APIリクエストの基本関数（Legacy API用）
 */
async function fetchApi<T>(
  endpoint: string, 
  options: RequestInit = {}
): Promise<T> {
  const url = endpoint.startsWith('http') ? endpoint : `${API_BASE_URL}${endpoint}`;
  
  const response = await fetch(url, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...options.headers,
    },
  });

  if (!response.ok) {
    let errorMessage = response.statusText || `HTTP ${response.status}`;
    
    try {
      const error: ApiError = await response.json();
      // エラーメッセージを抽出（複数のパターンに対応）
      if (typeof error.message === 'string' && error.message) {
        errorMessage = error.message;
      } else if (typeof error.error === 'string' && error.error) {
        errorMessage = error.error;
      } else if (error.error && typeof error.error === 'object') {
        // error.error がオブジェクトの場合（ネストされたエラー）
        const nestedError = error.error as any;
        errorMessage = nestedError.message || nestedError.error || JSON.stringify(error.error);
      }
    } catch (parseError) {
      // JSONパースに失敗した場合はデフォルトメッセージを使用
      console.error('Error response parse failed:', parseError);
    }
    
    const err = new Error(errorMessage);
    (err as any).status = response.status;
    throw err;
  }

  return response.json();
}

/**
 * フォームデータでAPIリクエストを送信
 */
async function fetchApiForm<T>(
  endpoint: string, 
  params: Record<string, string | string[]>,
  options: RequestInit = {}
): Promise<T | void> {
  const url = endpoint.startsWith('http') ? endpoint : `${API_BASE_URL}${endpoint}`;
  
  const formData = new URLSearchParams();
  Object.entries(params).forEach(([key, value]) => {
    if (Array.isArray(value)) {
      // 配列の場合はキーに[]を付加（Sinatraが配列として認識するため）
      value.forEach(v => formData.append(`${key}[]`, v));
    } else {
      formData.append(key, value);
    }
  });

  const response = await fetch(url, {
    ...options,
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      ...options.headers,
    },
    body: formData,
  });

  if (!response.ok) {
    const error: ApiError = await response.json().catch(() => ({
      error: 'Unknown error',
      message: response.statusText,
    }));
    throw new Error(error.message || error.error);
  }

  // レスポンスが空の場合はvoidを返す
  const text = await response.text();
  return text ? JSON.parse(text) : undefined;
}

/**
 * 小説リストを取得（API v2）
 */
export async function getNovels(params?: {
  page?: number;
  per_page?: number;
  filter?: string;
}): Promise<NovelsListData> {
  const searchParams = new URLSearchParams();
  if (params) {
    if (params.page !== undefined) searchParams.append('page', String(params.page));
    if (params.per_page !== undefined) searchParams.append('per_page', String(params.per_page));
    if (params.filter) searchParams.append('filter', params.filter);
  }

  const query = searchParams.toString();
  const endpoint = query ? `/api/v2/novels?${query}` : '/api/v2/novels';
  
  return fetchApiV2<NovelsListData>(endpoint);
}

/**
 * 小説の詳細を取得（API v2）
 */
export async function getNovel(id: number): Promise<Novel> {
  return fetchApiV2<Novel>(`/api/v2/novels/${id}`);
}

/**
 * 小説の総数を取得（Legacy API）
 */
export async function getNovelsCount(): Promise<number> {
  const result = await fetchApi<{ count: number }>('/api/novels/count');
  return result.count;
}

/**
 * 全小説IDを取得（Legacy API）
 */
export async function getAllNovelIds(): Promise<number[]> {
  return fetchApi<number[]>('/api/novels/all_ids');
}

/**
 * 小説をダウンロード（API v2）
 * @param targets - 小説ID配列または小説情報配列（IDまたはURLを含む）
 * @param force - 強制ダウンロードフラグ
 * @param convertAfterDownload - ダウンロード後に自動変換を実行するフラグ
 */
export async function downloadNovels(
  targets: (number | string | { id?: number; toc_url?: string })[], 
  force = false,
  convertAfterDownload = false
): Promise<void> {
  // targetsを文字列配列に変換
  const targetStrings = targets.map(target => {
    if (typeof target === 'number') {
      return String(target);
    } else if (typeof target === 'string') {
      return target;
    } else if (target.toc_url) {
      return target.toc_url;
    } else if (target.id !== undefined) {
      return String(target.id);
    }
    return String(target);
  });

  await fetchApiV2<null>('/api/v2/novels/download', {
    method: 'POST',
    body: JSON.stringify({ 
      targets: targetStrings, 
      force,
      convert_after_download: convertAfterDownload 
    }),
  });
}

/**
 * URLまたはIDから小説を追加してダウンロード（API v2）
 * @param url - 小説のURL または ncode
 * @param force - 強制ダウンロードフラグ
 */
export async function addNovel(url: string, force = false): Promise<void> {
  await fetchApiV2<null>('/api/v2/novels/download', {
    method: 'POST',
    body: JSON.stringify({ targets: [url], force }),
  });
}

/**
 * 単一小説を再ダウンロード（API v2）
 * @param id - 小説ID
 * @param force - 強制ダウンロードフラグ
 */
export async function downloadNovel(id: number, force = false): Promise<void> {
  await downloadNovels([id], force);
}

/**
 * 小説を変換（API v2）
 */
export async function convertNovels(ids: number[]): Promise<void> {
  await fetchApiV2<null>('/api/v2/novels/convert', {
    method: 'POST',
    body: JSON.stringify({ ids }),
  });
}

/**
 * 単一小説を変換（API v2）
 */
export async function convertNovel(id: number): Promise<void> {
  await convertNovels([id]);
}

/**
 * 小説を更新（Legacy API - API v2 未実装）
 */
export async function updateNovels(ids?: number[]): Promise<void> {
  await fetchApiForm('/api/update', { 
    ids: ids ? ids.map(String) : [] 
  });
}

/**
 * 小説を削除（API v2）
 */
export async function removeNovels(ids: number[], withFile = false): Promise<void> {
  await fetchApiV2<null>('/api/v2/novels/remove', {
    method: 'POST',
    body: JSON.stringify({ ids, with_file: withFile }),
  });
}

/**
 * 単一小説を削除（API v2）
 */
export async function removeNovel(id: number, withFile = false): Promise<void> {
  await removeNovels([id], withFile);
}

/**
 * 凍結状態をトグル（API v2）
 */
export async function toggleFreeze(ids: number[]): Promise<void> {
  await fetchApiV2<null>('/api/v2/novels/freeze', {
    method: 'POST',
    body: JSON.stringify({ ids }),
  });
}

/**
 * 単一小説を凍結（API v2）
 */
export async function freezeNovel(id: number): Promise<void> {
  await fetchApiV2<null>('/api/v2/novels/freeze', {
    method: 'POST',
    body: JSON.stringify({ ids: [id], freeze: true }),
  });
}

/**
 * 単一小説の凍結を解除（API v2）
 */
export async function unfreezeNovel(id: number): Promise<void> {
  await fetchApiV2<null>('/api/v2/novels/freeze', {
    method: 'POST',
    body: JSON.stringify({ ids: [id], freeze: false }),
  });
}

/**
 * 実行中のタスクをキャンセル（API v2）
 */
export async function cancelCurrentTask(): Promise<void> {
  await fetchApiV2<null>('/api/v2/cancel', {
    method: 'POST',
  });
}

/**
 * すべてのタスクをキャンセル（API v2）
 */
export async function cancelAllTasks(): Promise<void> {
  await fetchApiV2<null>('/api/v2/cancel/all', {
    method: 'POST',
  });
}

/**
 * 指定されたIDのタスクをキャンセル（API v2）
 * 注意: 現在のバックエンド実装では全タスクキャンセルと同じ動作
 */
export async function cancelTask(novelId: number): Promise<void> {
  await fetchApiV2<null>(`/api/v2/cancel/${novelId}`, {
    method: 'POST',
  });
}

/**
 * タグリストを取得（API v2）
 */
export async function getTagList(): Promise<TagInfo[]> {
  interface TagsData {
    tags: TagInfo[];
  }
  const data = await fetchApiV2<TagsData>('/api/v2/tags');
  return data.tags;
}

/**
 * タグ詳細情報を取得（選択された小説のタグ状態）（API v2）
 * @param ids - 対象の小説ID配列
 * @returns タグごとの状態情報 { tagName: { count, total_count, tag, color } }
 */
export async function getTagInfo(ids: number[]): Promise<Record<string, { count: number; total_count: number; tag: string; color: string }>> {
  interface TagInfoData {
    tag_info: Record<string, { count: number; total_count: number; tag: string; color: string }>;
  }
  const data = await fetchApiV2<TagInfoData>('/api/v2/tags/info', {
    method: 'POST',
    body: JSON.stringify({ ids }),
  });
  return data.tag_info;
}

/**
 * タグを一括編集（API v2）
 * @param ids - 対象の小説ID配列
 * @param states - タグごとの状態 { tagName: 0=削除, 1=維持, 2=追加 }
 */
export async function editTags(ids: number[], states: Record<string, number>): Promise<{ added: string[]; deleted: string[]; novel_count: number }> {
  interface EditResult {
    added: string[];
    deleted: string[];
    novel_count: number;
  }
  return fetchApiV2<EditResult>('/api/v2/tags/edit', {
    method: 'POST',
    body: JSON.stringify({ ids, states }),
  });
}

/**
 * タグの色を設定（API v2）
 * @param colors - タグ名と色のマッピング { tagName: color }
 */
export async function setTagColors(colors: Record<string, string>): Promise<{ colors: Record<string, string> }> {
  interface ColorResult {
    colors: Record<string, string>;
  }
  return fetchApiV2<ColorResult>('/api/v2/tags/color', {
    method: 'POST',
    body: JSON.stringify({ colors }),
  });
}

/**
 * タグを追加（API v2）
 * @param ids - 対象の小説ID配列
 * @param tags - 追加するタグ名の配列
 */
export async function addTags(ids: number[], tags: string[]): Promise<void> {
  await fetchApiV2<null>('/api/v2/tags/add', {
    method: 'POST',
    body: JSON.stringify({ ids, tags }),
  });
}

/**
 * タグを削除（API v2）
 * @param ids - 対象の小説ID配列
 * @param tags - 削除するタグ名の配列
 */
export async function removeTags(ids: number[], tags: string[]): Promise<void> {
  await fetchApiV2<null>('/api/v2/tags/delete', {
    method: 'POST',
    body: JSON.stringify({ ids, tags }),
  });
}

/**
 * 単一タグを編集（addTags/removeTags のラッパー）
 * @deprecated editTags() の使用を推奨
 */
export async function editTag(ids: number[], tag: string, action: 'add' | 'remove'): Promise<void> {
  if (action === 'add') {
    await addTags(ids, [tag]);
  } else {
    await removeTags(ids, [tag]);
  }
}

/**
 * キューサイズを取得（API v2）
 */
export async function getQueueSize(): Promise<QueueData> {
  return fetchApiV2<QueueData>('/api/v2/system/queue');
}

/**
 * システムステータスを取得（API v2）
 */
export async function getSystemStatus(): Promise<{
  queue: QueueData;
  push_server: { running: boolean; port: number };
  version: VersionData;
}> {
  return fetchApiV2('/api/v2/system/status');
}

/**
 * バージョン情報を取得（API v2）
 */
export async function getVersion(): Promise<VersionData> {
  return fetchApiV2<VersionData>('/api/v2/system/version');
}

/**
 * キューをキャンセル（Legacy API - API v2 未実装）
 */
export async function cancelQueue(): Promise<void> {
  await fetchApiForm('/api/cancel', {});
}

/**
 * 現在のバージョンを取得（Legacy API用）
 */
export async function getCurrentVersion(): Promise<VersionInfo> {
  return fetchApi<VersionInfo>('/api/version/current.json');
}

/**
 * 最新バージョンを取得（Legacy API用）
 */
export async function getLatestVersion(): Promise<VersionInfo> {
  return fetchApi<VersionInfo>('/api/version/latest.json');
}

/**
 * ログ履歴を取得（Legacy API - API v2 未実装）
 */
export async function getHistory(): Promise<LogMessage[]> {
  return fetchApi<LogMessage[]>('/api/history');
}

/**
 * ログ履歴をクリア（Legacy API - API v2 未実装）
 */
export async function clearHistory(): Promise<void> {
  await fetchApiForm('/api/clear_history', {});
}

/**
 * CSV形式でダウンロード（Legacy API - API v2 未実装）
 */
export function downloadAsCSV(): string {
  return `${API_BASE_URL}/api/csv/download`;
}

/**
 * 設定データの型定義
 */
export interface SettingValue {
  value: string | boolean | number | null;
  type?: string;
  help?: string;
}

export interface SettingVariable {
  type: string;
  help: string;
  select_keys?: string[];
  select_summaries?: string[];
  tab?: string;
  invisible?: boolean;
}

export interface SettingsData {
  local: Record<string, SettingValue>;
  global: Record<string, SettingValue>;
  variables?: {
    local: Record<string, SettingVariable>;
    global: Record<string, SettingVariable>;
  };
}

export interface SettingVariablesData {
  variables: {
    local: Record<string, SettingVariable>;
    global: Record<string, SettingVariable>;
  };
  tab_names: Record<string, string>; // タブキー → タブ表示名のマッピング
  tab_info: Record<string, string>; // タブキー → タブ説明のマッピング
}

export interface SettingsUpdateResult {
  updated_count: number;
  validation_errors?: string[];
}

/**
 * 設定一覧を取得（API v2）
 */
export async function getSettings(): Promise<SettingsData> {
  return fetchApiV2<SettingsData>('/api/v2/settings');
}

/**
 * 設定変数の定義を取得（API v2）
 */
export async function getSettingVariables(): Promise<SettingVariablesData> {
  return fetchApiV2<SettingVariablesData>('/api/v2/settings/variables');
}

/**
 * 設定を更新（API v2）
 * @param settings - 更新する設定のキーと値
 */
export async function updateSettings(settings: Record<string, string | boolean | number | null>): Promise<SettingsUpdateResult> {
  return fetchApiV2<SettingsUpdateResult>('/api/v2/settings', {
    method: 'PUT',
    body: JSON.stringify({ settings }),
  });
}

/**
 * 設定を部分更新（API v2）
 * @param settings - 更新する設定のキーと値（差分のみ）
 */
export async function patchSettings(settings: Record<string, string | boolean | number | null>): Promise<SettingsUpdateResult> {
  return fetchApiV2<SettingsUpdateResult>('/api/v2/settings', {
    method: 'PATCH',
    body: JSON.stringify({ settings }),
  });
}

/**
 * 小説のあらすじを取得（API v2）
 * @param id - 小説ID
 */
export async function getNovelStory(id: number): Promise<{ title: string; story: string }> {
  // API v2を使用
  const result = await fetchApiV2<{ title: string; story: string }>(`/api/v2/novels/${id}/story`);
  return result;
}

/**
 * EPUBファイルをダウンロード
 * @param id - 小説ID
 * @returns EPUBファイルのBlob
 */
export async function downloadEpub(id: number): Promise<Blob> {
  const response = await fetch(`${API_BASE_URL}/api/v2/novels/${id}/epub`);
  if (!response.ok) {
    throw new Error(`EPUBダウンロードに失敗しました: ${response.statusText}`);
  }
  return response.blob();
}

/**
 * 小説を削除
 * @param id - 小説ID
 */
export async function deleteNovel(id: number): Promise<void> {
  const response = await fetch(`${API_BASE_URL}/api/v2/novels/${id}`, {
    method: 'DELETE',
  });
  if (!response.ok) {
    throw new Error(`削除に失敗しました: ${response.statusText}`);
  }
}

/**
 * サーバーステータス情報の型定義
 */
export interface ServerStatus {
  queue: {
    total: number;
    web_worker: number;
    worker: number;
    running: boolean;
  };
  push_server: {
    running: boolean;
    port: number | null;
  };
  version: {
    narou: string;
    ruby: string;
  };
}

/**
 * サーバーステータスを取得
 */
export async function getServerStatus(): Promise<ServerStatus> {
  const result = await fetchApiV2<ServerStatus>('/api/v2/system/status');
  return result;
}

/**
 * サーバーを再起動
 */
export async function restartServer(): Promise<{ success: boolean; message: string }> {
  const response = await fetch(`${API_BASE_URL}/api/v2/server/restart`, {
    method: 'POST',
  });
  if (!response.ok) {
    throw new Error(`サーバーの再起動に失敗しました: ${response.statusText}`);
  }
  return response.json();
}

/**
 * サーバーを停止
 */
export async function stopServer(): Promise<{ success: boolean; message: string }> {
  const response = await fetch(`${API_BASE_URL}/api/v2/server/stop`, {
    method: 'POST',
  });
  if (!response.ok) {
    throw new Error(`サーバーの停止に失敗しました: ${response.statusText}`);
  }
  return response.json();
}

/**
 * タスク一覧を取得
 * @param status - フィルタするタスク状態（オプション）
 * @param limit - 取得する最大件数（オプション）
 */
export async function getTasks(status?: TaskStatus, limit?: number): Promise<Task[]> {
  const params = new URLSearchParams();
  if (status) params.append('status', status);
  if (limit) params.append('limit', limit.toString());
  
  const queryString = params.toString();
  const endpoint = queryString ? `/api/v2/tasks?${queryString}` : '/api/v2/tasks';
  
  const result = await fetchApiV2<{ tasks: Task[]; count: number }>(endpoint);
  return result.tasks;
}

/**
 * タスクサマリーを取得
 */
export async function getTaskSummary(): Promise<TaskSummary> {
  return await fetchApiV2<TaskSummary>('/api/v2/tasks/summary');
}

/**
 * 特定のタスクを取得
 * @param taskId - タスクID
 */
export async function getTask(taskId: string): Promise<Task> {
  return await fetchApiV2<Task>(`/api/v2/tasks/${taskId}`);
}

/**
 * タスクをキャンセル
 * @param taskId - タスクID
 */
export async function cancelTaskById(taskId: string): Promise<{ message: string }> {
  return await fetchApiV2<{ message: string }>(`/api/v2/tasks/${taskId}/cancel`, {
    method: 'POST',
  });
}

/**
 * タスクを一時停止
 * @param taskId - タスクID
 */
export async function pauseTask(taskId: string): Promise<{ message: string }> {
  return await fetchApiV2<{ message: string }>(`/api/v2/tasks/${taskId}/pause`, {
    method: 'POST',
  });
}

/**
 * タスクを再開
 * @param taskId - タスクID
 */
export async function resumeTask(taskId: string): Promise<{ message: string }> {
  return await fetchApiV2<{ message: string }>(`/api/v2/tasks/${taskId}/resume`, {
    method: 'POST',
  });
}
