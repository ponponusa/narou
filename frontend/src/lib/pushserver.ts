/**
 * PushServer WebSocket クライアント
 *
 * バックエンドのPushServerと接続し、リアルタイム通知を受け取る
 */

import { getPushServerPort } from "./backend-config";

export type PushServerEvent =
  | "table.reload"
  | "tag.updateCanvas"
  | "device.ejectable"
  | "server.update.success"
  | "server.update.nothing"
  | "server.update.failure"
  | "notification.queue"
  | "echo"
  | "show.modal"
  | "hide.modal"
  | "ping.modal"
  | "progressbar.init"
  | "progressbar.step"
  | "progressbar.clear"
  | "console.clear";

export interface EchoMessage {
  target_console: "stdout" | "stdout2" | "convert";
  body: string;
  no_history?: boolean;
}

export interface ProgressBarMessage {
  target_console?: "stdout" | "stdout2" | "convert";
  percent?: number;
}

export interface ModalMessage {
  id: number;
  title: string;
  message: string;
  choices: string[];
}

export interface QueueNotification {
  webWorkerSize: number;
  workerSize: number;
}

type EventHandler = (data: any) => void;

export class PushServerClient {
  private ws: WebSocket | null = null;
  private url: string;
  private eventHandlers: Map<PushServerEvent | string, Set<EventHandler>> =
    new Map();
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 10;
  private reconnectDelay = 1000;
  private isManualClose = false;

  constructor(host: string, port: number) {
    this.url = `ws://${host}:${port}/`;
  }

  /**
   * WebSocket接続を開始
   */
  connect(): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      console.log("[PushServer] Already connected");
      return;
    }

    this.isManualClose = false;
    console.log(`[PushServer] Connecting to ${this.url}`);

    try {
      this.ws = new WebSocket(this.url);

      this.ws.onopen = () => {
        console.log("[PushServer] Connected");
        this.reconnectAttempts = 0;
        this.trigger("connected", true);
      };

      this.ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);
          this.handleMessage(data);
        } catch (err) {
          console.error("[PushServer] Failed to parse message:", err);
        }
      };

      this.ws.onerror = (error) => {
        console.error("[PushServer] WebSocket error:", error);
        this.trigger("error", error);
      };

      this.ws.onclose = (event) => {
        console.log("[PushServer] Disconnected", event.code, event.reason);
        this.trigger("disconnected", {
          code: event.code,
          reason: event.reason,
        });

        if (!this.isManualClose) {
          this.attemptReconnect();
        }
      };
    } catch (err) {
      console.error("[PushServer] Failed to create WebSocket:", err);
      this.attemptReconnect();
    }
  }

  /**
   * WebSocket接続を切断
   */
  disconnect(): void {
    this.isManualClose = true;
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
  }

  /**
   * 再接続を試みる
   */
  private attemptReconnect(): void {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error("[PushServer] Max reconnection attempts reached");
      this.trigger("max-reconnect-reached", this.reconnectAttempts);
      return;
    }

    this.reconnectAttempts++;
    const delay = this.reconnectDelay * this.reconnectAttempts;
    console.log(
      `[PushServer] Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts})`
    );

    setTimeout(() => {
      this.connect();
    }, delay);
  }

  /**
   * メッセージを処理
   */
  private handleMessage(data: Record<string, any>): void {
    for (const [event, value] of Object.entries(data)) {
      console.log(`[PushServer] Event: ${event}`, value);
      this.trigger(event, value);
    }
  }

  /**
   * イベントハンドラを登録
   */
  on(event: PushServerEvent | string, handler: EventHandler): void {
    if (!this.eventHandlers.has(event)) {
      this.eventHandlers.set(event, new Set());
    }
    this.eventHandlers.get(event)!.add(handler);
  }

  /**
   * イベントハンドラを解除
   */
  off(event: PushServerEvent | string, handler: EventHandler): void {
    const handlers = this.eventHandlers.get(event);
    if (handlers) {
      handlers.delete(handler);
    }
  }

  /**
   * イベントを発火
   */
  private trigger(event: string, data: any): void {
    const handlers = this.eventHandlers.get(event);
    if (handlers) {
      handlers.forEach((handler) => {
        try {
          handler(data);
        } catch (err) {
          console.error(
            `[PushServer] Error in event handler for ${event}:`,
            err
          );
        }
      });
    }
  }

  /**
   * サーバーにメッセージを送信
   */
  send(event: string, data: any): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      const message = { [event]: data };
      this.ws.send(JSON.stringify(message));
    } else {
      console.warn("[PushServer] Cannot send message: not connected");
    }
  }

  /**
   * 接続状態を取得
   */
  isConnected(): boolean {
    return this.ws?.readyState === WebSocket.OPEN;
  }
}

// グローバルインスタンス
let globalPushServer: PushServerClient | null = null;
let portInitialized = false;
let cachedPort: number | null = null;

/**
 * APIからPushServerのポート番号を取得
 */
async function fetchPushServerPort(): Promise<number> {
  if (cachedPort !== null) {
    return cachedPort as number;
  }

  try {
    // backend-config.tsからポート番号を取得
    cachedPort = await getPushServerPort();
    console.log(`[PushServer] Using port from backend config: ${cachedPort}`);
    return cachedPort as number;
  } catch (error) {
    console.warn(
      "[PushServer] Failed to fetch port from backend config, using default: 5679"
    );
    cachedPort = 5679;
    return cachedPort as number;
  }
}

/**
 * PushServerクライアントのグローバルインスタンスを取得または作成
 * 注意: SSR/ビルド時は null を返す（ブラウザ環境でのみ動作）
 */
export function getPushServer(): PushServerClient | null {
  // SSR/ビルド時は何もしない
  if (typeof window === "undefined") {
    return null;
  }

  if (!globalPushServer) {
    const host = window.location.hostname;

    // 初期はデフォルトポートで作成
    const port =
      cachedPort || parseInt(import.meta.env.PUBLIC_PUSH_SERVER_PORT || "5679");

    globalPushServer = new PushServerClient(host, port);

    // 初回作成時に自動接続
    globalPushServer.connect();

    // 非同期でポート番号を取得して、ポートが異なる場合のみ再接続
    if (!portInitialized) {
      portInitialized = true;
      fetchPushServerPort().then((actualPort) => {
        if (actualPort !== port && globalPushServer) {
          console.log(
            `[PushServer] Port changed from ${port} to ${actualPort}, reconnecting`
          );
          // 既存の接続を切断
          globalPushServer.disconnect();
          // 新しいポートで再作成して接続
          globalPushServer = new PushServerClient(host, actualPort);
          globalPushServer.connect();
        } else {
          console.log(
            `[PushServer] Port ${actualPort} confirmed, using existing connection`
          );
        }
      });
    }
  }
  return globalPushServer;
}

/**
 * PushServerの初期化（ページロード時に呼び出し推奨）
 * 注意: SSR/ビルド時は何もしない
 */
export async function initializePushServer(): Promise<void> {
  // SSR/ビルド時は何もしない
  if (typeof window === "undefined") {
    return;
  }

  await fetchPushServerPort();
  getPushServer();
}
