# Parallel Processing Feature

大量エピソード小説の変換を高速化する並列処理機能です。

## Quick Start

```bash
# 並列処理はデフォルトで有効（100話以上の小説で自動的に高速化）
bundle exec ruby narou.rb convert <小説 ID>

# 無効化する場合
export NAROU_PARALLEL_CONVERT=false
bundle exec ruby narou.rb convert <小説 ID>
```

**注意**: Windows環境では自動的にスレッドベース並列化に切り替わります。

## Performance

**レジェンド（3,895話、183.57MB）での実測値:**

| 処理方式 | 実行時間 | CPU使用率 | 改善率 |
|---------|---------|----------|--------|
| シーケンシャル | 171.9秒 | 99% | - |
| **並列処理（2コア）** | **90.5秒** | 187% | **47.3%高速化** |

## Features

- ✅ **プロセスベース並列化**: Ruby GILを回避して複数コアを活用
- ✅ **チャンク最適化**: プロセス起動オーバーヘッドを最小化
- ✅ **自動有効化**: 100話以上の小説で自動的に並列処理
- ✅ **簡単設定**: 環境変数で制御

## Documentation

- **[使用ガイド](parallel_processing_guide.md)**: 詳細な使い方
- **[改善サマリー](performance_improvements_summary.md)**: 実装成果と技術詳細
- **[分析レポート](performance_analysis_legend.md)**: ボトルネック特定と改善提案

## Configuration

```bash
# 並列処理の制御（デフォルト: 有効）
export NAROU_PARALLEL_CONVERT=false  # 無効化する場合のみ設定

# プロセスベースの制御（デフォルト: Windows以外で有効）
export NAROU_PARALLEL_USE_PROCESSES=false  # 明示的にスレッドベースにする
export NAROU_PARALLEL_USE_PROCESSES=true   # Windowsでも強制的にプロセスベースにする（非推奨）

# オプション: 並列度（デフォルト: CPUコア数）
export NAROU_PARALLEL_THREADS=4

# オプション: チャンクサイズ（デフォルト: 1000）
export NAROU_CHUNK_SIZE=1000

# オプション: 並列処理の閾値（デフォルト: 10エピソード）
export NAROU_PARALLEL_THRESHOLD=10

# オプション: デバッグ出力
export NAROU_DEBUG=1
```

### プラットフォーム別の振る舞い

| 環境 | デフォルト動作 | 備考 |
|------|------------|------|
| Linux/macOS | プロセスベース並列 | GIL回避で高速 |
| Windows | スレッドベース並列 | Parallel gemの制約 |
| WSL | プロセスベース並列 | Linuxと同様 |

## Requirements

- Ruby 3.x
- 2+ CPU cores (推奨)
- 2GB+ RAM (並列度 × 200MB)
- `parallel` gem (Gemfileに含まれています)

## When to Use

### 推奨 ✅
- 100話以上の大量エピソード小説
- 2コア以上のCPU環境
- 変換時間を最優先したい場合

### 非推奨 ❌
- 100話未満の小説（オーバーヘッドが顕著）
- シングルコアCPU
- メモリが限られた環境

## Future Improvements

- [ ] YAML キャッシュ最適化（10秒短縮）
- [ ] 正規表現プリコンパイル（15秒短縮）
- [ ] Ractor対応（Ruby 3.0+の軽量並列実行）

**目標**: 171秒 → 65秒（62%改善）

---

**実装ブランチ**: `feature/performance-investigation`  
**最終更新**: 2025-11-25
