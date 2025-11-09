/**
 * API クライアント
 * 
 * バックエンドの REST API とやり取りするためのユーティリティ関数群
 */

import type { 
  Novel, 
  NovelsListResponse, 
  ApiError,
  QueueSizeResponse,
  TagInfo,
  VersionInfo,
  LogMessage
} from '../types/api';

const API_BASE_URL = import.meta.env.PUBLIC_API_BASE_URL || 'http://localhost:33000';

/**
 * APIリクエストの基本関数
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
 * 小説リストを取得
 */
export async function getNovels(params?: {
  draw?: number;
  start?: number;
  length?: number;
  filter?: string;
}): Promise<NovelsListResponse> {
  const searchParams = new URLSearchParams();
  if (params) {
    Object.entries(params).forEach(([key, value]) => {
      if (value !== undefined) {
        searchParams.append(key, String(value));
      }
    });
  }

  return fetchApi<NovelsListResponse>(
    `/api/list?${searchParams.toString()}`
  );
}

/**
 * 小説の総数を取得
 */
export async function getNovelsCount(): Promise<number> {
  const result = await fetchApi<{ count: number }>('/api/novels/count');
  return result.count;
}

/**
 * 全小説IDを取得
 */
export async function getAllNovelIds(): Promise<number[]> {
  return fetchApi<number[]>('/api/novels/all_ids');
}

/**
 * 小説をダウンロード
 */
export async function downloadNovels(ids: number[], force = false): Promise<void> {
  const endpoint = force ? '/api/download_force' : '/api/download';
  await fetchApi(endpoint, {
    method: 'POST',
    body: JSON.stringify({ ids }),
  });
}

/**
 * 小説を変換
 */
export async function convertNovels(ids: number[]): Promise<void> {
  await fetchApi('/api/convert', {
    method: 'POST',
    body: JSON.stringify({ ids }),
  });
}

/**
 * 小説を更新
 */
export async function updateNovels(ids?: number[]): Promise<void> {
  await fetchApi('/api/update', {
    method: 'POST',
    body: JSON.stringify({ ids }),
  });
}

/**
 * 小説を削除
 */
export async function removeNovels(ids: number[], withFile = false): Promise<void> {
  const endpoint = withFile ? '/api/remove_with_file' : '/api/remove';
  await fetchApi(endpoint, {
    method: 'POST',
    body: JSON.stringify({ ids }),
  });
}

/**
 * 凍結状態をトグル
 */
export async function toggleFreeze(ids: number[]): Promise<void> {
  await fetchApi('/api/freeze', {
    method: 'POST',
    body: JSON.stringify({ ids }),
  });
}

/**
 * タグリストを取得
 */
export async function getTagList(): Promise<TagInfo[]> {
  return fetchApi<TagInfo[]>('/api/tag_list');
}

/**
 * タグを編集
 */
export async function editTag(ids: number[], tag: string, action: 'add' | 'remove'): Promise<void> {
  await fetchApi('/api/edit_tag', {
    method: 'POST',
    body: JSON.stringify({ ids, tag, action }),
  });
}

/**
 * キューサイズを取得
 */
export async function getQueueSize(): Promise<QueueSizeResponse> {
  return fetchApi<QueueSizeResponse>('/api/get_queue_size');
}

/**
 * キューをキャンセル
 */
export async function cancelQueue(): Promise<void> {
  await fetchApi('/api/cancel', {
    method: 'POST',
  });
}

/**
 * バージョン情報を取得
 */
export async function getCurrentVersion(): Promise<VersionInfo> {
  return fetchApi<VersionInfo>('/api/version/current.json');
}

/**
 * 最新バージョンを取得
 */
export async function getLatestVersion(): Promise<VersionInfo> {
  return fetchApi<VersionInfo>('/api/version/latest.json');
}

/**
 * ログ履歴を取得
 */
export async function getHistory(): Promise<LogMessage[]> {
  return fetchApi<LogMessage[]>('/api/history');
}

/**
 * ログ履歴をクリア
 */
export async function clearHistory(): Promise<void> {
  await fetchApi('/api/clear_history', {
    method: 'POST',
  });
}

/**
 * CSV形式でダウンロード
 */
export function downloadAsCSV(): string {
  return `${API_BASE_URL}/api/csv/download`;
}
