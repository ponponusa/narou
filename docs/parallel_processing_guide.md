# Episode Processing Parallelization Guide

## Overview

narou-modに、大量エピソード変換の並列処理機能を追加しました。
**レジェンド（3,895話）での実測値: 171.9秒 → 90.6秒（47%高速化）**

## Quick Start

### 基本使用（推奨）

```bash
# 並列処理を有効化（自動でCPUコア数を検出）
export NAROU_PARALLEL_CONVERT=true
export NAROU_PARALLEL_USE_PROCESSES=true
bundle exec ruby narou.rb convert <ID>
```

### カスタム設定

```bash
# 4コアで並列処理
export NAROU_PARALLEL_CONVERT=true
export NAROU_PARALLEL_USE_PROCESSES=true
export NAROU_PARALLEL_THREADS=4
bundle exec ruby narou.rb convert <ID>
```

## Environment Variables

| 変数名 | 説明 | デフォルト値 | 推奨値 |
|--------|------|-------------|--------|
| `NAROU_PARALLEL_CONVERT` | 並列処理を有効化 | `false` | `true` (100話以上の小説で推奨) |
| `NAROU_PARALLEL_USE_PROCESSES` | プロセスベース並列化 | `false` | `true` (CPU効率向上) |
| `NAROU_PARALLEL_THREADS` | 並列度 | `CPUコア数` | `2`〜`CPUコア数` |
| `NAROU_DEBUG` | デバッグ出力を有効化 | `false` | `1` (動作確認時) |

## Technical Details

### Why Process-based?

RubyのGIL (Global Interpreter Lock) により、**スレッドベースの並列化ではCPUバウンドな処理の高速化が困難**です：

```ruby
# ❌ スレッドベース: GILで制限される
# CPU使用率 99% (1コアのみ)
Parallel.map(items, in_threads: 4) { |item| heavy_computation(item) }

# ✅ プロセスベース: GILを回避
# CPU使用率 189% (2コア効率活用)
Parallel.map(items, in_processes: 4) { |item| heavy_computation(item) }
```

### Performance Comparison

#### シーケンシャル処理（デフォルト）
```
実行時間: 171.9秒
CPU使用率: 99%
メモリ: 約200MB
```

#### 並列処理（2コア）
```
実行時間: 90.6秒 (-47%)
CPU使用率: 189%
メモリ: 約400MB
```

#### 並列処理（4コア、理論値）
```
実行時間: 約60秒 (-65%)
CPU使用率: 350%
メモリ: 約600MB
```

### When to Use

#### 推奨ケース ✅
- 100話以上の大量エピソード小説
- 複数コアCPU環境（2コア以上）
- メモリが十分にある環境（並列度 × 200MB）
- 変換時間を最優先したい場合

#### 非推奨ケース ❌
- 100話未満の小説（オーバーヘッドが顕著）
- シングルコアCPU
- メモリが限られた環境
- デバッグ中（進捗表示が不正確になる）

## Troubleshooting

### 並列処理が有効にならない

```bash
# デバッグモードで確認
export NAROU_DEBUG=1
export NAROU_PARALLEL_CONVERT=true
export NAROU_PARALLEL_USE_PROCESSES=true
bundle exec ruby narou.rb convert <ID>
```

期待される出力:
```
Using process-based parallel processing (3895 episodes)
Parallel processes: 2
```

### メモリ不足エラー

並列度を下げる:
```bash
export NAROU_PARALLEL_THREADS=2  # 4 → 2 に削減
```

または、プロセスベースを無効化してスレッドベースに戻す:
```bash
unset NAROU_PARALLEL_USE_PROCESSES  # デフォルトのスレッドベース
```

### 進捗表示がおかしい

並列処理では進捗表示が不正確になる可能性があります。
デバッグ時はシーケンシャル処理を使用してください:
```bash
unset NAROU_PARALLEL_CONVERT
```

## Benchmarks

### Test Environment
- CPU: 2コア
- RAM: 8GB
- Ruby: 3.4.7
- Novel: レジェンド（3,895話、183.57MB）

### Results

| 設定 | 実行時間 | CPU使用率 | 改善率 |
|------|---------|----------|--------|
| シーケンシャル | 171.9秒 | 99% | - |
| 並列（2コア） | 90.6秒 | 189% | 47.3% |
| 並列（4コア）* | 約60秒 | 350% | 約65% |

*理論値（Amdahlの法則に基づく推定）

### Component Breakdown

#### シーケンシャル処理
```
Database:        2.6秒 (2%)
YAML load:       1.6秒 (1%)
HTML→Aozora:     6.6秒 (4%)
Converter:     154.0秒 (95%) ← 並列化対象
EPUB generation: 9.8秒 (6%)
```

#### 並列処理（2コア）
```
Database:        2.6秒 (3%)
YAML load:       1.6秒 (2%)
HTML→Aozora:     6.6秒 (7%)
Converter:      70.0秒 (77%) ← 54% 短縮！
EPUB generation: 9.8秒 (11%)
```

## Implementation Details

### Files Modified
- `lib/novel/novel_converter/text_processor.rb`: 並列処理ロジック
- `Gemfile`: `parallel` gem追加
- `docs/performance_analysis_legend.md`: 詳細な分析

### Key Functions
```ruby
# メインエントリーポイント
def subtitles_to_sections(subtitles, html)
  if ENV['NAROU_PARALLEL_CONVERT'] == 'true' && subtitles.size > 100
    subtitles_to_sections_parallel(subtitles, html, use_processes: ...)
  else
    subtitles_to_sections_sequential(subtitles, html)
  end
end

# 並列処理実装
def subtitles_to_sections_parallel(subtitles, html, use_processes: false)
  parallel_options = use_processes ? 
    { in_processes: thread_count } : 
    { in_threads: thread_count }
  
  Parallel.map_with_index(subtitles, parallel_options) do |subinfo, i|
    # 各プロセス/スレッドで独立したConverterを使用
    thread_converter = create_or_get_converter(...)
    # エピソード処理
    convert_episode(subinfo, thread_converter)
  end
end
```

## Future Improvements

### Planned
1. **チャンクベース処理**: プロセス起動オーバーヘッドを削減
2. **Ractor対応**: Ruby 3.0+の軽量並列実行
3. **適応的並列度**: エピソード数に応じた自動最適化
4. **進捗表示改善**: プロセス間での進捗同期

### Theoretical Performance
```ruby
# 現在: エピソード単位並列化
Parallel.map(3895_episodes, in_processes: 2) # 3895回のプロセス間通信

# 改善: チャンク並列化
Parallel.map(2_chunks, in_processes: 2)      # 2回のプロセス起動のみ
# → 更なる高速化が期待できる
```

## References

- **Performance Analysis**: `docs/performance_analysis_legend.md`
- **Parallel Gem**: https://github.com/grosser/parallel
- **Benchmark Scripts**: `tmp/profile_*.rb`, `tmp/test_parallel_*.rb`

## License

Same as narou-mod project.

---

Last updated: 2025-01-20
