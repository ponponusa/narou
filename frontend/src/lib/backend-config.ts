/**
 * バックエンド設定の動的取得
 *
 * バックエンドが起動時に生成する backend-port.json から
 * ポート情報を取得する
 */

interface BackendConfig {
  backend_port: number;
  push_server_port: number;
  updated_at: string;
}

let cachedConfig: BackendConfig | null = null;

/**
 * バックエンドのポート情報を取得
 */
export async function getBackendConfig(): Promise<BackendConfig> {
  if (cachedConfig) {
    return cachedConfig;
  }

  // サーバーサイドレンダリング時はデフォルト値を返す
  if (typeof window === "undefined") {
    return {
      backend_port: 5678,
      push_server_port: 5679,
      updated_at: new Date().toISOString(),
    };
  }

  try {
    const response = await fetch("/backend-port.json");
    if (!response.ok) {
      throw new Error(`Failed to fetch backend config: ${response.statusText}`);
    }
    cachedConfig = await response.json();
    return cachedConfig!;
  } catch (error) {
    console.error(
      "[BackendConfig] Failed to load backend-port.json, using defaults:",
      error
    );
    // デフォルト値を返す
    return {
      backend_port: 5678,
      push_server_port: 5679,
      updated_at: new Date().toISOString(),
    };
  }
}

/**
 * バックエンドAPIのベースURLを取得
 */
export async function getBackendBaseUrl(): Promise<string> {
  const config = await getBackendConfig();
  return `http://localhost:${config.backend_port}`;
}

/**
 * PushServerのポート番号を取得
 */
export async function getPushServerPort(): Promise<number> {
  const config = await getBackendConfig();
  return config.push_server_port;
}

/**
 * キャッシュをクリア（テスト用）
 */
export function clearBackendConfigCache(): void {
  cachedConfig = null;
}
