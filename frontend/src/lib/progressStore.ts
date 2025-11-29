/**
 * 小説の一括操作進捗状態管理ストア
 *
 * 各小説の処理状態をリアルタイムで追跡
 */

import { writable } from "svelte/store";

/**
 * 進捗状態の定義
 */
export type ProgressStatus =
  | "idle" // 待機中（表示なし）
  | "waiting" // キュー待ち
  | "downloading" // ダウンロード中
  | "converting" // 変換中
  | "completed" // 完了（永続表示）
  | "error"; // エラー（永続表示）

/**
 * 進捗情報の型
 */
export interface ProgressInfo {
  status: ProgressStatus;
  message?: string;
  updatedAt: number;
}

/**
 * 進捗状態マップ: novelId -> ProgressInfo
 */
type ProgressMap = Record<number, ProgressInfo>;

/**
 * 進捗状態ストア
 */
function createProgressStore() {
  const { subscribe, set, update } = writable<ProgressMap>({});

  return {
    subscribe,

    /**
     * 小説の進捗状態を設定
     */
    setProgress(novelId: number, status: ProgressStatus, message?: string) {
      update((state) => ({
        ...state,
        [novelId]: {
          status,
          message,
          updatedAt: Date.now(),
        },
      }));
    },

    /**
     * 小説の進捗状態を取得
     */
    getProgress(novelId: number): ProgressInfo | undefined {
      let result: ProgressInfo | undefined;
      subscribe((state) => {
        result = state[novelId];
      })();
      return result;
    },

    /**
     * 小説の進捗をクリア
     */
    clearProgress(novelId: number) {
      update((state) => {
        const newState = { ...state };
        delete newState[novelId];
        return newState;
      });
    },

    /**
     * 全ての進捗をクリア
     */
    clearAll() {
      set({});
    },

    /**
     * 複数の小説を一括で状態設定
     */
    setBatch(novelIds: number[], status: ProgressStatus, message?: string) {
      update((state) => {
        const updates: ProgressMap = {};
        novelIds.forEach((id) => {
          updates[id] = {
            status,
            message,
            updatedAt: Date.now(),
          };
        });
        return { ...state, ...updates };
      });
    },
  };
}

export const progressStore = createProgressStore();
