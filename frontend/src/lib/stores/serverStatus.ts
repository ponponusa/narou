/**
 * サーバーステータス管理用ストア
 */
import { writable } from "svelte/store";

export const isServerStopped = writable(false);
