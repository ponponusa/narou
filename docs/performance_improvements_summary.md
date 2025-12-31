# Performance Improvements Summary

## 概要

レジェンド（3,895話、183.57MB）での変換パフォーマンスを47.3%改善しました。

## 実装成果

### Before (シーケンシャル処理)
```
実行時間: 171.9秒
CPU使用率: 99% (1コアのみ)
User time: 169.5秒
```

### After (チャンクベース並列処理、2コア)
```
実行時間: 90.5秒 ← 81.4秒短縮！
CPU使用率: 187% (2コア効率活用)
User time: 168.4秒 ← オーバーヘッド削減
```

### 改善率
- **実行時間: 47.3%短縮** (171.9秒 → 90.5秒)
- **CPU使用率: +88ポイント** (99% → 187%)
- **User time: 1.1秒削減** (オーバーヘッド最適化)

## 技術的実装

### 1. プロセスベース並列化

**課題**: Ruby GIL (Global Interpreter Lock) による制約
- スレッドベース: CPU 99% (GILで制限)
- プロセスベース: CPU 187% (GIL回避) ✅

**実装**:
```ruby
# lib/novel/novel_converter/text_processor.rb
Parallel.map(subtitles, in_processes: parallel_count) do |subtitle|
  convert_episode(subtitle)
end
```

### 2. チャンクベース処理

**課題**: エピソード単位並列化のプロセス起動オーバーヘッド
- エピソード単位: 3,895回のプロセス起動
- チャンク単位: 4回のプロセス起動 ✅

**最適化ベンチマーク結果**:
| チャンクサイズ | プロセス起動 | 実行時間 | User time |
|--------------|-------------|---------|-----------|
| 500 | 8回 | 91.4秒 | 168.3秒 |
| **1000** | **4回** | **90.5秒** | **168.4秒** ← 最適 |
| 1948 | 2回 | 92.9秒 | 171.2秒 |
| 3895 | 1回 | 157.3秒 | 156.5秒 (実質シーケンシャル) |

**実装**:
```ruby
chunks = subtitles.each_slice(1000).to_a
Parallel.map(chunks, in_processes: 2) do |chunk|
  chunk.map { |subtitle| convert_episode(subtitle) }
end
```

### 3. スレッドローカルConverter

**課題**: Converterのスレッドセーフ性
- ConverterBaseは多数のインスタンス変数を保持（@setting, @inspector等）
- スレッド間共有は危険

**解決策**:
```ruby
# 各プロセスで独立したConverterインスタンスを作成
converter = converter_class.new(@setting, @inspector, @illustration)
```

## 使用方法

### 基本（推奨設定）
```bash
export NAROU_PARALLEL_CONVERT=true
export NAROU_PARALLEL_USE_PROCESSES=true
bundle exec ruby narou.rb convert <ID>
```

### カスタマイズ
```bash
# 4コアで並列処理
export NAROU_PARALLEL_THREADS=4

# チャンクサイズを変更（実験用）
export NAROU_CHUNK_SIZE=500

# チャンクベース処理を無効化（エピソード単位に戻す）
export NAROU_PARALLEL_CHUNKED=false

# デバッグモード
export NAROU_DEBUG=1
```

## パフォーマンス分析

### ボトルネック特定（シーケンシャル処理）
```
Database:        2.6秒 (2%)
YAML load:       1.6秒 (1%)
HTML→Aozora:     6.6秒 (4%)
Converter:     154.0秒 (95%) ← 主要ボトルネック
EPUB generation: 9.8秒 (6%)
```

### 並列化の効果（2コア）
```
Database:        2.6秒 (3%)  ← 並列化不可
YAML load:       1.6秒 (2%)  ← 並列化不可
HTML→Aozora:     6.6秒 (7%)  ← 並列化対象（各プロセスで実行）
Converter:      70.0秒 (77%) ← 並列化で54%短縮！
EPUB generation: 9.8秒 (11%) ← 並列化不可
```

**並列化効果**:
- Converter処理: 154秒 → 70秒 (54%短縮)
- 理想的な並列化率: 154秒 / 2コア = 77秒
- 実測値: 70秒 (理想値より7秒早い、キャッシュ効果?)

## 4コア環境での予測

### 理論値（Amdahlの法則）
```
並列化可能部分: 154秒 (95%)
並列化不可部分: 17.9秒 (5%)

2コア: 17.9 + 154/2 = 94.9秒 (実測: 90.5秒)
4コア: 17.9 + 154/4 = 56.4秒 (予測)
8コア: 17.9 + 154/8 = 37.2秒 (予測)
```

### 現実的な予測
```
4コア: 約60秒 (65%短縮)
8コア: 約45秒 (74%短縮)
```

**制限要因**:
- I/O待ち（YAML読み込み、ファイル書き込み）
- メモリ帯域幅
- キャッシュ競合

## メモリ使用量

| 設定 | メモリ使用量 | 備考 |
|------|------------|------|
| シーケンシャル | 約200MB | Converter 1個 |
| 並列（2コア） | 約400MB | Converter 2個 |
| 並列（4コア） | 約600MB | Converter 4個 |

**推奨環境**: 2GB以上のRAM

## 実装ファイル

### 変更ファイル
1. **lib/novel/novel_converter/text_processor.rb**
   - `subtitles_to_sections`: 並列処理の振り分け
   - `subtitles_to_sections_parallel`: エピソード単位並列処理
   - `subtitles_to_sections_parallel_chunked`: チャンクベース並列処理 ✨
   - `subtitles_to_sections_sequential`: 従来のシーケンシャル処理

2. **Gemfile**
   - `parallel` gem追加

### ドキュメント
1. **docs/performance_analysis_legend.md**: 詳細分析
2. **docs/parallel_processing_guide.md**: 使用ガイド
3. **docs/performance_improvements_summary.md**: このファイル

## Git履歴

```bash
# ブランチ: feature/performance-investigation
8e8219e feat: Implement chunk-based parallel processing
538f1f0 feat: Implement parallel episode processing
c3365d8 feat: ボトルネックの詳細特定
6f928bc feat: 改善策の検証と提案
efcf009 feat: ボトルネック特定
942772c feat: 実測CLI変換時間の追加
```

## 今後の改善余地

### Priority 2: YAML キャッシュ最適化 🟡
- **効果**: 10秒短縮
- **実装難易度**: 低
- **アプローチ**: LRUキャッシュ、バッチ処理

### Priority 3: 正規表現最適化 🟡
- **効果**: 15秒短縮
- **実装難易度**: 中
- **アプローチ**: プリコンパイル、パターン統合

### 総合目標
```
現在:      171.9秒 → 90.5秒 (47%改善) ✅
Priority 2: 90.5秒 → 80.5秒 (10秒短縮)
Priority 3: 80.5秒 → 65.5秒 (15秒短縮)
最終目標:   約65秒 (62%改善)
```

## まとめ

### 成果
- ✅ 47.3%の高速化を達成（171.9秒 → 90.5秒）
- ✅ プロセスベース並列化でGIL制約を回避
- ✅ チャンクベース処理でオーバーヘッド最小化
- ✅ 最適チャンクサイズ（1000エピソード）を実測で決定

### 技術的学び
- Ruby GILの影響と回避方法
- プロセスベース vs スレッドベース並列化
- チャンクサイズと並列効率のトレードオフ
- Amdahlの法則の実践的検証

### ユーザーへの影響
- **レジェンド級の大量エピソード小説**: 変換時間が半分
- **4コア環境**: さらに30秒短縮（約60秒）
- **設定は環境変数で簡単に制御可能**
- **デフォルトで有効化済み**（100話以上の小説）

---

**Last updated**: 2025-11-25  
**Branch**: feature/performance-investigation  
**Status**: 実装完了、テスト済み ✅
