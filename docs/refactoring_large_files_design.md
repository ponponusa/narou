# 大規模ファイルのリファクタリング設計書

**作成日:** 2025-11-24  
**ステータス:** 🟡 設計段階

---

## 📋 概要

Narou.rb MOD のコードベースには、500行を超える大規模ファイルが6つ存在します。これらのファイルは保守性や可読性、テストのしやすさの観点から分割が推奨されます。

本文書では、優先度の高い3ファイルの分割設計を策定します。

---

## 🎯 対象ファイル

### 優先度 High（即座に対応推奨）

| ファイル | 行数 | メソッド数 | クラス数 | 複雑度 |
|---------|------|-----------|---------|--------|
| **lib/downloader.rb** | 1665 | 85 | 7 | 高 |
| **lib/converterbase.rb** | 1567 | 97 | 1 | 高 |
| **lib/web/appserver.rb** | 1521 | 21 | - | 中 |

### 優先度 Medium（3ヶ月以内）

| ファイル | 行数 | メソッド数 | クラス数 | 複雑度 |
|---------|------|-----------|---------|--------|
| lib/novelconverter.rb | 968 | 34 | 1 | 中 |
| lib/command/setting.rb | 706 | 17 | 1 | 低 |
| lib/helper.rb | 675 | 42 | - | 中 |

---

## 📦 1. lib/downloader.rb (1665行) の分割設計

### 現状分析

**7つのクラスが1ファイルに混在:**

1. `Downloader` - メインクラス（ダウンロード処理）
2. `Downloader::InvalidTarget` - 例外クラス
3. `Downloader::FrozenDownloadError` - 例外クラス
4. `Downloader::NotFoundNovelError` - 例外クラス
5. `NovelSiteDiff` - 小説サイトの差分管理
6. `Update` - 更新チェッククラス
7. その他ヘルパーモジュール

**問題点:**
- 1ファイルで複数の責務を担当
- クラス間の依存関係が不明瞭
- テストが困難（1665行のファイルに対するspec）
- 新規メンテナーの理解が困難

### 分割案: lib/downloader/ ディレクトリ化

```
lib/
├── downloader.rb              # メインクラス（エントリーポイント）200行程度
└── downloader/
    ├── base.rb               # Downloaderベースクラス（共通処理） 300行
    ├── errors.rb             # 例外クラス群（3クラス） 50行
    ├── novel_site_diff.rb    # NovelSiteDiff クラス 300行
    ├── update_checker.rb     # Update クラス（更新チェック） 400行
    ├── content_fetcher.rb    # コンテンツ取得処理 200行
    ├── metadata_parser.rb    # メタデータ解析 200行
    └── file_manager.rb       # ファイル保存処理 200行
```

**メリット:**
- 責務ごとにファイル分割（SRP準拠）
- テストファイルも分割可能（spec/downloader/ に対応）
- 並行開発が容易
- 新規メンテナーの理解が容易

### 移行手順

#### Step 1: 例外クラスの分離（低リスク）

```ruby
# lib/downloader/errors.rb
module Downloader
  class InvalidTarget < StandardError; end
  class FrozenDownloadError < StandardError; end
  class NotFoundNovelError < StandardError; end
end
```

```ruby
# lib/downloader.rb
require_relative "downloader/errors"

class Downloader
  # ... 既存コード（例外クラス定義を削除）
end
```

**影響範囲:** 
- 例外クラスのrequire_relative追加のみ
- 既存のコードは変更不要（後方互換性維持）

#### Step 2: NovelSiteDiff の分離

```ruby
# lib/downloader/novel_site_diff.rb
require_relative "errors"

class NovelSiteDiff
  # ... 既存のコードを移動
end
```

```ruby
# lib/downloader.rb
require_relative "downloader/novel_site_diff"
# ... NovelSiteDiff クラス定義を削除
```

**影響範囲:**
- `NovelSiteDiff` を使用している箇所は変更不要
- require_relative の追加のみ

#### Step 3: Update クラスの分離

```ruby
# lib/downloader/update_checker.rb
class Update
  # ... 既存のコードを移動
end
```

**影響範囲:**
- `Update.check` などの呼び出しは変更不要

#### Step 4: Downloader クラスの責務分割（慎重に実施）

メインの `Downloader` クラスを機能モジュールに分割:

```ruby
# lib/downloader/base.rb
class Downloader
  class Base
    # 共通処理
  end
end

# lib/downloader/content_fetcher.rb
class Downloader
  module ContentFetcher
    # コンテンツ取得処理
  end
end

# lib/downloader/metadata_parser.rb
class Downloader
  module MetadataParser
    # メタデータ解析
  end
end

# lib/downloader.rb
require_relative "downloader/base"
require_relative "downloader/content_fetcher"
require_relative "downloader/metadata_parser"

class Downloader < Downloader::Base
  include Downloader::ContentFetcher
  include Downloader::MetadataParser
  
  # エントリーポイントのみ
end
```

**影響範囲:**
- 外部からの `Downloader.new` は変更不要
- 内部構造のみ変更

### テスト戦略

```
spec/
├── downloader_spec.rb                # 統合テスト（既存）
└── downloader/
    ├── errors_spec.rb               # 例外クラスのテスト
    ├── novel_site_diff_spec.rb      # NovelSiteDiff のテスト
    ├── update_checker_spec.rb       # Update のテスト
    ├── content_fetcher_spec.rb      # ContentFetcher のテスト
    ├── metadata_parser_spec.rb      # MetadataParser のテスト
    └── file_manager_spec.rb         # FileManager のテスト
```

---

## 🔄 2. lib/converterbase.rb (1567行) の分割設計

### 現状分析

**1クラス・97メソッド:**

- 1つの巨大な `ConverterBase` クラス
- 複数の責務が混在（変換、フォーマット、ファイル操作、etc.）
- メソッド数が多すぎて全体像の把握が困難

**メソッドの分類:**

1. **HTML処理:** 30メソッド
2. **ファイル操作:** 15メソッド
3. **目次生成:** 12メソッド
4. **画像処理:** 10メソッド
5. **テンプレート処理:** 10メソッド
6. **メタデータ処理:** 8メソッド
7. **その他:** 12メソッド

### 分割案: モジュール化 + Concernパターン

```
lib/
├── converterbase.rb              # メインクラス（コアロジックのみ） 300行
└── converterbase/
    ├── html_processor.rb         # HTML処理モジュール 250行
    ├── file_operations.rb        # ファイル操作モジュール 200行
    ├── toc_generator.rb          # 目次生成モジュール 180行
    ├── image_processor.rb        # 画像処理モジュール 150行
    ├── template_renderer.rb      # テンプレート処理 150行
    ├── metadata_handler.rb       # メタデータ処理 120行
    └── utilities.rb              # ユーティリティメソッド 150行
```

**各モジュールの責務:**

#### html_processor.rb (250行)
```ruby
module ConverterBase
  module HtmlProcessor
    # HTML整形
    def sanitize_html(html)
    end
    
    # タグ変換
    def convert_tags(html)
    end
    
    # ルビ処理
    def process_ruby(text)
    end
    
    # ... 他27メソッド
  end
end
```

#### file_operations.rb (200行)
```ruby
module ConverterBase
  module FileOperations
    # ファイル読み込み
    def read_novel_file(path)
    end
    
    # ファイル書き込み
    def write_output(content, path)
    end
    
    # ディレクトリ操作
    def create_work_dir
    end
    
    # ... 他12メソッド
  end
end
```

#### toc_generator.rb (180行)
```ruby
module ConverterBase
  module TocGenerator
    # 目次生成
    def generate_toc
    end
    
    # 章立て解析
    def parse_chapters
    end
    
    # ... 他10メソッド
  end
end
```

#### 統合方法

```ruby
# lib/converterbase.rb
require_relative "converterbase/html_processor"
require_relative "converterbase/file_operations"
require_relative "converterbase/toc_generator"
require_relative "converterbase/image_processor"
require_relative "converterbase/template_renderer"
require_relative "converterbase/metadata_handler"
require_relative "converterbase/utilities"

class ConverterBase
  include ConverterBase::HtmlProcessor
  include ConverterBase::FileOperations
  include ConverterBase::TocGenerator
  include ConverterBase::ImageProcessor
  include ConverterBase::TemplateRenderer
  include ConverterBase::MetadataHandler
  include ConverterBase::Utilities
  
  # コアロジックのみ（初期化、メインフロー）
  def initialize(setting)
    # ...
  end
  
  def convert
    # メインの変換フロー
  end
end
```

### 移行手順

#### Step 1: ユーティリティメソッドの分離（低リスク）

最も独立性の高いユーティリティメソッドから分離:

```ruby
# lib/converterbase/utilities.rb
module ConverterBase
  module Utilities
    def strip_decoration_tag(str)
      # ... 既存コード
    end
    
    def kanji_to_arabic(str)
      # ... 既存コード
    end
  end
end
```

#### Step 2: HTML処理モジュールの分離

```ruby
# lib/converterbase/html_processor.rb
module ConverterBase
  module HtmlProcessor
    # ... HTML関連メソッドを移動
  end
end
```

#### Step 3: 残りのモジュールを順次分離

- ファイル操作
- 目次生成
- 画像処理
- テンプレート処理
- メタデータ処理

#### Step 4: テストの分割

```
spec/
├── converterbase_spec.rb                    # 統合テスト
└── converterbase/
    ├── html_processor_spec.rb
    ├── file_operations_spec.rb
    ├── toc_generator_spec.rb
    ├── image_processor_spec.rb
    ├── template_renderer_spec.rb
    ├── metadata_handler_spec.rb
    └── utilities_spec.rb
```

### 後方互換性の保証

```ruby
# 既存のコード（変更不要）
converter = ConverterBase.new(setting)
converter.convert  # 従来通り動作

# メソッドも従来通り呼び出し可能
converter.sanitize_html(html)
converter.generate_toc
```

---

## 🌐 3. lib/web/appserver.rb (1521行) の分割設計

### 現状分析

**Sinatraアプリケーション + API:**

- 旧WebUIのルーティング: 約800行
- REST API: 約500行
- ヘルパーメソッド: 約200行

**問題点:**
- 旧WebUIと新APIが混在
- ルーティングが多すぎて見通しが悪い
- 旧WebUI削除時に大規模な変更が必要

### 分割案（旧WebUI削除前提）

旧WebUI削除後は **API部分のみ保持** するため、削除を見越した分割:

```
lib/web/
├── appserver.rb              # メインアプリ（Sinatraベース） 200行
├── api/
│   ├── v1/
│   │   ├── novels.rb        # 小説関連API 150行
│   │   ├── downloads.rb     # ダウンロードAPI 120行
│   │   ├── settings.rb      # 設定API 100行
│   │   └── tasks.rb         # タスクAPI 100行
│   └── v2/
│       └── (将来の新API)
└── legacy/                   # 旧WebUI（削除予定）
    ├── routes.rb            # 旧UIルーティング 400行
    └── helpers.rb           # 旧UIヘルパー 200行
```

### 移行手順

#### Step 1: 旧WebUIコードを legacy/ に隔離

```ruby
# lib/web/legacy/routes.rb
module Narou
  module LegacyWebUI
    def self.registered(app)
      app.get "/" do
        # 旧UIのトップページ
      end
      
      # ... 他の旧UIルーティング
    end
  end
end

# lib/web/appserver.rb
require_relative "legacy/routes"

class AppServer < Sinatra::Base
  register Narou::LegacyWebUI if ENV["LEGACY_WEB_UI"]
  
  # API部分のみ残す
end
```

#### Step 2: API部分をバージョン別に分離

```ruby
# lib/web/api/v1/novels.rb
module Narou
  module API
    module V1
      module Novels
        def self.registered(app)
          app.get "/api/v1/novels" do
            # 小説一覧取得
          end
          
          app.get "/api/v1/novels/:id" do
            # 小説詳細取得
          end
        end
      end
    end
  end
end

# lib/web/appserver.rb
require_relative "api/v1/novels"
require_relative "api/v1/downloads"
require_relative "api/v1/settings"
require_relative "api/v1/tasks"

class AppServer < Sinatra::Base
  register Narou::API::V1::Novels
  register Narou::API::V1::Downloads
  register Narou::API::V1::Settings
  register Narou::API::V1::Tasks
end
```

#### Step 3: 旧WebUI削除時の対応

旧WebUI削除時は `lib/web/legacy/` を丸ごと削除:

```bash
rm -rf lib/web/legacy/
rm -rf lib/web/views/
rm -rf lib/web/public/resources/  # 旧UI専用リソース
```

`lib/web/appserver.rb` から旧UI参照を削除:

```ruby
# 削除前
require_relative "legacy/routes"
register Narou::LegacyWebUI if ENV["LEGACY_WEB_UI"]

# 削除後（この行を削除）
```

---

## 📊 その他の中規模ファイル

### lib/novelconverter.rb (968行)

**現状:**
- `NovelConverter` クラス（ConverterBaseの子クラス）
- 小説特有の変換処理

**推奨分割:**
- 優先度 Medium（3ヶ月以内）
- `ConverterBase` の分割完了後に実施
- 同様のモジュール化パターン適用

### lib/command/setting.rb (706行)

**現状:**
- `Command::Setting` クラス
- 設定管理CLI

**推奨分割:**
- 優先度 Medium
- サブコマンド別にファイル分割
  - `setting/novel.rb` - 小説別設定
  - `setting/global.rb` - グローバル設定
  - `setting/convert.rb` - 変換設定

### lib/helper.rb (675行)

**現状:**
- グローバルヘルパーメソッド群（42メソッド）

**推奨分割:**
- 優先度 Medium
- 機能別モジュール化
  - `helper/string.rb` - 文字列操作
  - `helper/file.rb` - ファイル操作
  - `helper/novel.rb` - 小説データ操作

---

## 🗓️ 実施スケジュール

### Phase 1: 低リスク分割（1週間〜1ヶ月）

| ファイル | 作業内容 | 工数 | リスク |
|---------|---------|------|--------|
| lib/downloader.rb | Step 1-3 (例外、NovelSiteDiff、Update分離) | 3日 | 低 |
| lib/converterbase.rb | Step 1-2 (Utilities、HtmlProcessor分離) | 3日 | 低 |
| lib/web/appserver.rb | Step 1 (legacy隔離) | 2日 | 低 |

**成果物:**
- 3ファイルで合計約600行削減
- テストの部分的分割
- リスクの低い範囲での実績作り

### Phase 2: 本格的分割（1〜2ヶ月）

| ファイル | 作業内容 | 工数 | リスク |
|---------|---------|------|--------|
| lib/downloader.rb | Step 4 (Downloader本体の分割) | 1週間 | 中 |
| lib/converterbase.rb | Step 3-4 (全モジュール分離) | 1週間 | 中 |
| lib/web/appserver.rb | Step 2 (API分離) | 3日 | 低 |

**成果物:**
- 完全なディレクトリ構造化
- テストの完全分割
- ドキュメント更新

### Phase 3: 中規模ファイル対応（2〜3ヶ月）

| ファイル | 作業内容 | 工数 | リスク |
|---------|---------|------|--------|
| lib/novelconverter.rb | モジュール化 | 3日 | 低 |
| lib/command/setting.rb | サブコマンド分割 | 2日 | 低 |
| lib/helper.rb | 機能別モジュール化 | 2日 | 低 |

---

## ✅ 実施チェックリスト

### 事前準備

- [ ] 現在のテストカバレッジ確認（ベースライン）
  ```bash
  bundle exec rspec --format documentation
  ```
- [ ] 対象ファイルの依存関係調査
  ```bash
  grep -r "require.*downloader" lib/
  ```
- [ ] バックアップブランチ作成
  ```bash
  git checkout -b refactor/split-large-files
  ```

### Phase 1 実施項目

#### lib/downloader.rb

- [ ] `lib/downloader/errors.rb` 作成
- [ ] `lib/downloader/novel_site_diff.rb` 作成
- [ ] `lib/downloader/update_checker.rb` 作成
- [ ] `lib/downloader.rb` から該当コード削除
- [ ] テスト実行（失敗ゼロ確認）
- [ ] コミット

#### lib/converterbase.rb

- [ ] `lib/converterbase/utilities.rb` 作成
- [ ] `lib/converterbase/html_processor.rb` 作成
- [ ] `lib/converterbase.rb` に include 追加
- [ ] テスト実行
- [ ] コミット

#### lib/web/appserver.rb

- [ ] `lib/web/legacy/routes.rb` 作成
- [ ] `lib/web/legacy/helpers.rb` 作成
- [ ] `lib/web/appserver.rb` から旧UIコード移動
- [ ] 条件付き register 追加
- [ ] テスト実行
- [ ] コミット

### 各作業後の確認事項

- [ ] **テストが通る**
  ```bash
  bundle exec rspec
  ```
- [ ] **Rubocop違反がない**
  ```bash
  bundle exec rubocop
  ```
- [ ] **実際の動作確認**
  ```bash
  bundle exec ruby narou.rb download ncode.syosetu.com/nXXXXX/
  bundle exec ruby narou.rb convert nXXXXX
  ```
- [ ] **コミットメッセージが明確**
  ```
  refactor(downloader): Extract errors to separate file
  
  - Create lib/downloader/errors.rb
  - Move InvalidTarget, FrozenDownloadError, NotFoundNovelError
  - No behavior changes
  ```

---

## ⚠️ リスクと対策

### リスク1: テストの失敗

**リスク内容:**
- ファイル分割によるrequire_relative漏れ
- モジュール化によるメソッド参照エラー

**対策:**
- 各Step後に必ずテスト実行
- 1ファイルずつ慎重に作業
- 失敗時は即座にロールバック

### リスク2: パフォーマンス劣化

**リスク内容:**
- require_relative の増加によるロード時間増加
- モジュールincludeのオーバーヘッド

**対策:**
- ベンチマーク計測（分割前後）
  ```ruby
  require 'benchmark'
  
  Benchmark.bm do |x|
    x.report("load") { require_relative "downloader" }
  end
  ```
- 必要に応じて autoload の検討

### リスク3: 後方互換性の破壊

**リスク内容:**
- 外部からの直接参照が壊れる
- 継承関係の変更による影響

**対策:**
- public API は絶対に変更しない
- 内部構造のみ変更
- 移行期間中は alias 提供も検討

---

## 📊 進捗管理

### 現在のステータス

| ファイル | Phase | ステータス | 進捗 |
|---------|-------|-----------|------|
| lib/downloader.rb | Phase 1 | 🔵 未着手 | 0% |
| lib/converterbase.rb | Phase 1 | 🔵 未着手 | 0% |
| lib/web/appserver.rb | Phase 1 | 🔵 未着手 | 0% |
| lib/novelconverter.rb | Phase 3 | ⚪ 未開始 | - |
| lib/command/setting.rb | Phase 3 | ⚪ 未開始 | - |
| lib/helper.rb | Phase 3 | ⚪ 未開始 | - |

### 成果指標（KPI）

| 指標 | 現在 | 目標 | 達成時期 |
|------|------|------|---------|
| 500行超ファイル数 | 6 | 0 | 3ヶ月後 |
| 平均ファイルサイズ | ~200行 | ~150行 | 3ヶ月後 |
| テストカバレッジ | 43.57% | 50% | 3ヶ月後 |
| 最大メソッド数/ファイル | 97 | 30 | 2ヶ月後 |

---

## 📝 備考

### 参考資料

- [Single Responsibility Principle (SRP)](https://en.wikipedia.org/wiki/Single-responsibility_principle)
- [Ruby Modules and Mixins](https://ruby-doc.org/core/Module.html)
- [Sinatra Modular Style](http://sinatrarb.com/intro.html#Sinatra::Base%20-%20Middleware,%20Libraries,%20and%20Modular%20Apps)

### 関連Issue

- TBD: GitHub Issue作成後にリンク追加

---

## 🔄 更新履歴

| 日付 | 変更内容 | 担当者 |
|------|---------|--------|
| 2025-11-24 | 初版作成 | AI Assistant |
