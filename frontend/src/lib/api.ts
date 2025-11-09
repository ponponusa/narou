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
  LogMessage
} from '../types/api';

const API_BASE_URL = import.meta.env.PUBLIC_API_BASE_URL || 'http://localhost:33000';

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
    const error: ApiError = await response.json().catch(() => ({
      error: 'HTTP Error',
      message: `${response.status} ${response.statusText}`,
    }));
    throw new Error(error.message || error.error);
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
    const error: ApiError = await response.json().catch(() => ({
      error: 'Unknown error',
      message: response.statusText,
    }));
    throw new Error(error.message || error.error);
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
 */
export async function downloadNovels(ids: number[], force = false): Promise<void> {
  await fetchApiV2<null>('/api/v2/novels/download', {
    method: 'POST',
    body: JSON.stringify({ ids, force }),
  });
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
 * 凍結状態をトグル（API v2）
 */
export async function toggleFreeze(ids: number[]): Promise<void> {
  await fetchApiV2<null>('/api/v2/novels/freeze', {
    method: 'POST',
    body: JSON.stringify({ ids }),
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
 * タグを追加（API v2）
 */
export async function addTags(ids: number[], tag: string): Promise<void> {
  await fetchApiV2<null>('/api/v2/tags/add', {
    method: 'POST',
    body: JSON.stringify({ ids, tag }),
  });
}

/**
 * タグを削除（API v2）
 */
export async function removeTags(ids: number[], tag: string): Promise<void> {
  await fetchApiV2<null>('/api/v2/tags/delete', {
    method: 'POST',
    body: JSON.stringify({ ids, tag }),
  });
}

/**
 * タグを編集（addTags/removeTags のラッパー）
 */
export async function editTag(ids: number[], tag: string, action: 'add' | 'remove'): Promise<void> {
  if (action === 'add') {
    await addTags(ids, tag);
  } else {
    await removeTags(ids, tag);
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
