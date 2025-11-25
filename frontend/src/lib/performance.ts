/**
 * パフォーマンス計測ユーティリティ
 * 
 * フィルタリング処理などの実行時間を計測し、開発時にコンソールに出力
 */

// 開発モードかどうか
const isDev = import.meta.env.DEV;

/**
 * 関数の実行時間を計測
 * 
 * @param label 計測ラベル
 * @param fn 計測対象の関数
 * @param logThreshold ログ出力する閾値（ミリ秒）、この値以上の場合のみログ出力
 * @returns 関数の実行結果
 */
export function measurePerformance<T>(
  label: string,
  fn: () => T,
  logThreshold: number = 0
): T {
  if (!isDev) {
    // 本番環境では計測せず、そのまま実行
    return fn();
  }

  const startTime = performance.now();
  const result = fn();
  const endTime = performance.now();
  const duration = endTime - startTime;

  if (duration >= logThreshold) {
    console.log(`[Performance] ${label}: ${duration.toFixed(2)}ms`);
  }

  return result;
}

/**
 * 複数回実行して平均実行時間を計測
 * 
 * @param label 計測ラベル
 * @param fn 計測対象の関数
 * @param iterations 実行回数
 * @returns 平均実行時間（ミリ秒）
 */
export function measureAveragePerformance<T>(
  label: string,
  fn: () => T,
  iterations: number = 10
): number {
  if (!isDev) {
    return 0;
  }

  const times: number[] = [];

  for (let i = 0; i < iterations; i++) {
    const startTime = performance.now();
    fn();
    const endTime = performance.now();
    times.push(endTime - startTime);
  }

  const average = times.reduce((sum, time) => sum + time, 0) / iterations;
  const min = Math.min(...times);
  const max = Math.max(...times);

  console.log(
    `[Performance] ${label}: avg=${average.toFixed(2)}ms, min=${min.toFixed(2)}ms, max=${max.toFixed(2)}ms (${iterations} iterations)`
  );

  return average;
}

/**
 * パフォーマンスマーカー（開始/終了ペアで使用）
 */
export class PerformanceMarker {
  private startTime: number = 0;
  private marks: Map<string, number> = new Map();

  constructor(private enabled: boolean = isDev) {}

  /**
   * 計測開始
   */
  start(): void {
    if (!this.enabled) return;
    this.startTime = performance.now();
    this.marks.clear();
  }

  /**
   * 中間マーク
   * 
   * @param label マークラベル
   */
  mark(label: string): void {
    if (!this.enabled) return;
    const elapsed = performance.now() - this.startTime;
    this.marks.set(label, elapsed);
  }

  /**
   * 計測終了してログ出力
   * 
   * @param label 計測ラベル
   * @param logThreshold ログ出力する閾値（ミリ秒）
   */
  end(label: string, logThreshold: number = 0): number {
    if (!this.enabled) return 0;

    const totalTime = performance.now() - this.startTime;

    if (totalTime >= logThreshold) {
      const marksStr = Array.from(this.marks.entries())
        .map(([name, time]) => `${name}=${time.toFixed(2)}ms`)
        .join(", ");

      if (marksStr) {
        console.log(
          `[Performance] ${label}: ${totalTime.toFixed(2)}ms (${marksStr})`
        );
      } else {
        console.log(`[Performance] ${label}: ${totalTime.toFixed(2)}ms`);
      }
    }

    return totalTime;
  }

  /**
   * 現在の経過時間を取得（ログ出力なし）
   */
  elapsed(): number {
    if (!this.enabled) return 0;
    return performance.now() - this.startTime;
  }
}

/**
 * フィルタリング統計情報
 */
export interface FilterStats {
  label: string;
  inputCount: number;
  outputCount: number;
  duration: number;
  reductionRate: number; // 削減率（%）
}

/**
 * フィルタリングパフォーマンスを計測
 * 
 * @param label フィルタラベル
 * @param inputData 入力データ
 * @param filterFn フィルタ関数
 * @param logThreshold ログ出力する閾値（ミリ秒）
 * @returns フィルタリング結果と統計情報
 */
export function measureFilterPerformance<T>(
  label: string,
  inputData: T[],
  filterFn: (data: T[]) => T[],
  logThreshold: number = 0
): { result: T[]; stats: FilterStats } {
  const startTime = performance.now();
  const result = filterFn(inputData);
  const endTime = performance.now();
  const duration = endTime - startTime;

  const inputCount = inputData.length;
  const outputCount = result.length;
  const reductionRate =
    inputCount > 0 ? ((inputCount - outputCount) / inputCount) * 100 : 0;

  const stats: FilterStats = {
    label,
    inputCount,
    outputCount,
    duration,
    reductionRate,
  };

  if (isDev && duration >= logThreshold) {
    console.log(
      `[Filter Performance] ${label}: ${inputCount} → ${outputCount} items (${reductionRate.toFixed(1)}% reduction) in ${duration.toFixed(2)}ms`
    );
  }

  return { result, stats };
}

/**
 * メモリ使用量を計測（Chrome DevTools API使用）
 * 
 * @param label 計測ラベル
 */
export function measureMemory(label: string): void {
  if (!isDev) return;

  // Chrome限定のperformance.memory APIを使用
  const perf = performance as Performance & {
    memory?: {
      usedJSHeapSize: number;
      totalJSHeapSize: number;
      jsHeapSizeLimit: number;
    };
  };

  if (perf.memory) {
    const { usedJSHeapSize, totalJSHeapSize, jsHeapSizeLimit } = perf.memory;
    const usedMB = (usedJSHeapSize / 1024 / 1024).toFixed(2);
    const totalMB = (totalJSHeapSize / 1024 / 1024).toFixed(2);
    const limitMB = (jsHeapSizeLimit / 1024 / 1024).toFixed(2);

    console.log(
      `[Memory] ${label}: ${usedMB}MB / ${totalMB}MB (limit: ${limitMB}MB)`
    );
  }
}
