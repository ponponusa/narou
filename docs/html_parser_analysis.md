# HTML Parser Analysis

## 現状の問題点

### 1. サイト別設定ファイル依存（YAML設定ファイル）

現在の実装は `webnovel/*.yaml` にサイトごとの正規表現パターンを定義し、`SiteSetting.multi_match()` でHTML文字列から目的のコンテンツを抽出しています。

**問題:**
- サイトのHTML構造が変わると即座にダウンロードが失敗する
- 正規表現パターンの保守が困難（可読性が低い、デバッグが難しい）
- サイト別に個別対応が必要で拡張性に欠ける
- エラー時のフォールバック機構が存在しない

**例: ncode.syosetu.com.yaml**
```yaml
body_pattern: |-
  <div class="js-novel-text p-novel__text">
  (?<body>.+?)
  ?</div>
```

この正規表現はクラス名変更に脆弱で、サイトリニューアル時に即座に破綻します。

### 2. 手動バイトレベル解析（Sanitize module fallback_fragment）

`lib/downloader.rb` の冒頭に定義されている `Sanitize.fragment` のフォールバック実装:

```ruby
def fallback_fragment(html, config = {})
  # 手動でHTMLタグを探してパースする
  result = []
  pos = 0
  while pos < html.bytesize
    # <, >, /などのバイトを探して手動でタグを抽出
    ...
  end
end
```

**問題:**
- DOM解析ライブラリ（Nokogiri等）を使わず手動でバイト列処理
- script/style タグの中身をスキップする特殊処理が複雑
- 壊れたHTMLへの対応が不完全
- 保守性・可読性が極めて低い

### 3. HTML → 青空文庫形式変換の単純置換

`lib/html.rb` の `to_aozora()` メソッド群:

```ruby
def br_to_aozora(text = @string)
  text.gsub(/[\r\n]+/, "").gsub(/<br.*?>/i, "\n")
end

def ruby_to_aozora(text = @string)
  text.tr("《》", "≪≫")
      .gsub(/<ruby>(.+?)<\/ruby>/i) do
    # ...
  end
end
```

**問題:**
- 正規表現による単純な置換処理で、ネストした構造に弱い
- タグの属性値やコメント内の誤検出の可能性
- HTML特殊文字（エンティティ）の処理が分散している

### 4. コンテンツ抽出パターン分散

HTML解析が複数箇所に分散:

1. **目次ページ解析** - `lib/downloader.rb` `get_latest_table_of_contents()`
   - `@setting.multi_match(toc_source, "subtitles")` で章リスト抽出
2. **本文ページ解析** - `lib/downloader.rb` `a_section_download()`
   - `@setting.multi_match(raw, "body_pattern", "introduction_pattern", "postscript_pattern")`
3. **小説情報解析** - `lib/novelinfo.rb` `parse_novel_info()`
   - `@setting.multi_match(info_source, *request_output_parameters)`
4. **HTML→青空変換** - `lib/html.rb` `to_aozora()`
   - 正規表現による置換処理

**問題:**
- 責務が分散していて統一的な改善が困難
- 各箇所で独自の解析ロジックが存在
- エラーハンドリングの一貫性がない

### 5. カクヨムの特殊対応（JSON解析前処理）

`webnovel/kakuyomu.jp.yaml` には以下のような `eval:` コードが含まれています:

```yaml
code: &code
  eval: |-
    # <script id="__NEXT_DATA__" type="application/json">のJSONをパース
    json = JSON.parse($1)
    # データを整形してHTMLコメントとして挿入
    source.insert(m.begin(0), str)
```

**問題:**
- 特定サイトのみ特殊な前処理が必要
- `eval` による動的コード実行（セキュリティリスク）
- 拡張性に欠ける（他のSPA/JSON構造サイトへの対応が困難）

---

## 新パーサーの設計方針

### A. DOM解析ライブラリの採用（Nokogiri）

**方針:** 手動バイト処理を廃止し、Nokogiri による DOM 解析を基本とする。

**理由:**
- XPath/CSS セレクタによる柔軟な要素取得
- 壊れた HTML の自動修正機能
- Ruby標準的なHTML解析手法
- 保守性・可読性の大幅向上

**設計:**
```ruby
require 'nokogiri'

module Narou
  class NokogiriParser
    def initialize(html, encoding: 'UTF-8')
      @doc = Nokogiri::HTML(html, nil, encoding)
    end

    def extract_by_selector(selector)
      @doc.css(selector).map(&:text)
    end

    def extract_by_xpath(xpath)
      @doc.xpath(xpath).map(&:text)
    end
  end
end
```

### B. セレクタベース抽出戦略（Fallback Chain）

**方針:** サイト構造変更に強くするため、複数のセレクタパターンを試す Fallback Chain を実装。

**例: 本文抽出の優先順位**
```yaml
# ncode.syosetu.com 用の新設定
body_selectors:
  - selector: "div.js-novel-text.p-novel__text"
    priority: 10
  - selector: "div.p-novel__text"
    priority: 8
  - selector: "div[id*='novel_honbun']"
    priority: 5
  - selector: "div#novel_color"
    priority: 3
```

**実装イメージ:**
```ruby
def extract_body_with_fallback(doc, selectors)
  selectors.sort_by { |s| -s[:priority] }.each do |config|
    result = doc.css(config[:selector])
    return result.first.inner_html if result.any?
  end
  raise ParserError, "本文が見つかりませんでした"
end
```

### C. サイト別アダプタパターン

**方針:** 各サイト固有のロジックを独立したアダプタクラスに分離。アダプタは `.narou/parsers/` 配下のユーザー設定を参照して動作する。

**ディレクトリ構造:**
```
lib/narou/parsers/
  base_parser.rb           # 共通インターフェース
  narou_parser.rb          # 小説家になろう用
  kakuyomu_parser.rb       # カクヨム用（JSON対応含む）
  hameln_parser.rb         # ハーメルン用
  ...
```

**基底クラス:**
```ruby
module Narou
  module Parsers
    class BaseParser
      def initialize(site_setting, user_config)
        @site_setting = site_setting    # webnovel/*.yaml から読み込んだ設定
        @user_config = user_config      # .narou/parsers/*.yaml から読み込んだユーザー設定
        @config = merge_configs(site_setting, user_config)
      end

      # ユーザー設定を優先してマージ
      def merge_configs(site, user)
        site.merge(user) do |key, site_val, user_val|
          # セレクタ設定はユーザー設定を優先
          key.end_with?("_selectors") ? user_val : (user_val || site_val)
        end
      end

      # 各サブクラスで実装
      def parse_toc(html)
        raise NotImplementedError
      end

      def parse_section(html)
        raise NotImplementedError
      end

      def parse_novel_info(html)
        raise NotImplementedError
      end

      # 共通のセレクタチェーン処理
      def extract_with_fallback(doc, selector_key, extract_type: "inner_html")
        selectors = @config[selector_key] || []
        
        selectors.sort_by { |s| -s["priority"] }.each do |config|
          begin
            result = doc.css(config["selector"])
            next if result.empty?
            
            # 成功したセレクタを記録
            update_successful_selector(selector_key, config["selector"])
            
            case extract_type
            when "inner_html"
              return result.first.inner_html
            when "text"
              return result.first.text
            else
              return result.first
            end
          rescue => e
            logger.debug "Selector failed: #{config['selector']} - #{e.message}"
            next
          end
        end
        
        raise ParserError, "全てのセレクタで要素が見つかりませんでした: #{selector_key}"
      end

      # 成功したセレクタをユーザー設定に記録
      def update_successful_selector(selector_key, selector)
        @user_config["last_successful_selectors"] ||= {}
        @user_config["last_successful_selectors"][selector_key] = {
          "selector" => selector,
          "date" => Time.now.strftime("%Y-%m-%d")
        }
        save_user_config
      end

      def save_user_config
        domain = @site_setting["domain"]
        path = ".narou/parsers/#{domain}.yaml"
        File.write(path, YAML.dump(@user_config))
      end
    end
  end
end
```

**サイト別アダプタの実装例:**
```ruby
module Narou
  module Parsers
    class NarouParser < BaseParser
      def parse_section(html)
        doc = Nokogiri::HTML(html)
        
        {
          "body" => extract_with_fallback(doc, "body_selectors"),
          "introduction" => extract_with_fallback(doc, "introduction_selectors"),
          "postscript" => extract_with_fallback(doc, "postscript_selectors")
        }
      rescue ParserError => e
        # ユーザー設定のセレクタが全て失敗した場合
        raise ParserError, "小説家になろうの本文解析に失敗: #{e.message}"
      end
    end
  end
end
```

### D. 段階的移行戦略とパーサー設定管理

**方針:** 既存のYAML設定ベースのパーサーを残しつつ、新パーサーを並行稼働。ユーザーがパーサー設定を確認・編集できる仕組みを提供。

#### D.1. パーサー設定ファイルの配置

**ディレクトリ構造:**
```
preset/parsers/               # 新パーサー用デフォルト設定（システム提供、リードオンリー）
  ncode.syosetu.com.yaml
  kakuyomu.jp.yaml
  www.akatsuki-novels.com.yaml
  ...

webnovel/                     # Legacy パーサー専用（既存、正規表現パターン）
  ncode.syosetu.com.yaml      # 既存ファイル、変更なし
  kakuyomu.jp.yaml
  ...

.narou/
  parsers/                    # 新パーサー用設定（ユーザー編集可能）
    ncode.syosetu.com.yaml    # 初回は preset/parsers/ からコピー
    kakuyomu.jp.yaml
    custom-site.yaml          # ユーザーが独自に追加した設定
    ...
  legacy_parsers/             # Legacy パーサー用設定（ユーザー編集可能）
    ncode.syosetu.com.yaml    # 初回は webnovel/ からコピー
    kakuyomu.jp.yaml
    ...
  parser_config.yaml          # グローバル設定
```

**設定の役割分担:**

| パス | 対象パーサー | 役割 | 編集可否 |
|------|------------|------|---------|
| `preset/parsers/` | Nokogiri | デフォルト設定（セレクタベース） | ❌ システム管理 |
| `webnovel/` | Legacy | 正規表現パターン（既存） | ❌ システム管理 |
| `.narou/parsers/` | Nokogiri | ユーザー設定（セレクタカスタマイズ） | ✅ ユーザー編集 |
| `.narou/legacy_parsers/` | Legacy | ユーザー設定（正規表現カスタマイズ） | ✅ ユーザー編集 |

**設定読み込み優先順位:**

**新パーサー (Nokogiri):**
1. `.narou/parsers/{domain}.yaml` - ユーザー設定
2. `preset/parsers/{domain}.yaml` - デフォルト設定（初回コピー元）

**Legacy パーサー:**
1. `.narou/legacy_parsers/{domain}.yaml` - ユーザー設定
2. `webnovel/{domain}.yaml` - デフォルト設定（既存、初回コピー元）

#### D.2. グローバル設定

**`.narou/parser_config.yaml`:**
```yaml
# パーサーエンジンのデフォルト設定
default_engine: nokogiri  # "nokogiri" or "legacy"

# 各小説ごとの上書き設定
novels:
  n1234ab:
    engine: legacy  # この小説だけ Legacy パーサーを使用
  n5678cd:
    engine: nokogiri
```

#### D.3. サイト別パーサー設定

**新パーサー用デフォルト設定: `preset/parsers/ncode.syosetu.com.yaml`**
```yaml
# サイト基本情報
name: 小説家になろう
domain: ncode.syosetu.com
encoding: UTF-8
top_url: https://ncode.syosetu.com

# セレクタチェーン（優先度順）
body_selectors:
  - selector: "div.js-novel-text.p-novel__text"
    priority: 10
    extract: "inner_html"
    description: "公式クラス名（2024年以降）"
  - selector: "div.p-novel__text"
    priority: 8
    extract: "inner_html"
    description: "BEMクラスのみ"
  - selector: "div#novel_honbun"
    priority: 5
    extract: "inner_html"
    description: "旧ID（2020年以前）"

introduction_selectors:
  - selector: "div.js-novel-text.p-novel__text--preface"
    priority: 10
  - selector: "div.p-novel__text--preface"
    priority: 8

postscript_selectors:
  - selector: "div.js-novel-text.p-novel__text--afterword"
    priority: 10
  - selector: "div.p-novel__text--afterword"
    priority: 8

# 最後に成功したセレクタを記録（自動更新）
last_successful_selector: "div.js-novel-text.p-novel__text"
last_success_date: "2024-11-23"
```

#### D.4. パーサー選択ロジック

**実装:**
```ruby
def select_parser(novel_id, site_setting)
  # グローバル設定を読み込み
  global_config = load_parser_config(".narou/parser_config.yaml")
  
  # 小説ごとの設定を確認
  engine = global_config.dig("novels", novel_id, "engine") ||
           global_config["default_engine"] ||
           "nokogiri"
  
  # ユーザー設定を読み込み（なければデフォルト設定）
  user_config = load_user_parser_config(site_setting["domain"], engine)
  
  case engine
  when "nokogiri"
    Narou::Parsers::NokogiriParser.new(site_setting, user_config)
  when "legacy"
    Narou::Parsers::LegacyParser.new(site_setting, user_config)
  else
    raise "Unknown parser engine: #{engine}"
  end
end

def load_user_parser_config(domain, engine)
  # エンジンごとに異なるパスを設定
  if engine == 'nokogiri'
    user_path = ".narou/parsers/#{domain}.yaml"
    default_path = "preset/parsers/#{domain}.yaml"
  else
    user_path = ".narou/legacy_parsers/#{domain}.yaml"
    default_path = "webnovel/#{domain}.yaml"
  end
  
  # ユーザー設定が存在すればそれを使用
  if File.exist?(user_path)
    return YAML.load_file(user_path)
  end
  
  # 初回: デフォルト設定をユーザー領域にコピー
  unless File.exist?(default_path)
    raise "Default parser config not found: #{default_path}"
  end
  
  default_config = YAML.load_file(default_path)
  FileUtils.mkdir_p(File.dirname(user_path))
  File.write(user_path, YAML.dump(default_config))
  
  default_config
end
```

#### D.5. Web UI でのパーサー設定編集

**新 Web UI (Astro + Svelte) に Settings タブ追加:**

```svelte
<!-- frontend/src/components/ParserSettings.svelte -->
<script>
  import { onMount } from 'svelte';
  
  let parserConfig = $state({});
  let selectedSite = $state('');
  let parserEngine = $state('nokogiri');
  
  async function loadParserConfig() {
    const response = await fetch('/api/settings/parser');
    parserConfig = await response.json();
  }
  
  async function saveParserConfig() {
    await fetch('/api/settings/parser', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(parserConfig)
    });
  }
  
  onMount(loadParserConfig);
</script>

<div class="parser-settings">
  <h2>パーサー設定</h2>
  
  <div class="global-settings">
    <label>
      デフォルトエンジン:
      <select bind:value={parserConfig.default_engine}>
        <option value="nokogiri">Nokogiri (推奨)</option>
        <option value="legacy">Legacy (正規表現)</option>
      </select>
    </label>
  </div>
  
  <div class="site-settings">
    <h3>サイト別設定</h3>
    <select bind:value={selectedSite}>
      <option value="">サイトを選択...</option>
      <option value="ncode.syosetu.com">小説家になろう</option>
      <option value="kakuyomu.jp">カクヨム</option>
    </select>
    
    {#if selectedSite}
      <div class="selector-editor">
        <h4>セレクタ設定</h4>
        <!-- YAML エディタ or フォーム -->
        <textarea bind:value={parserConfig.sites[selectedSite]} rows="20" />
      </div>
    {/if}
  </div>
  
  <button onclick={saveParserConfig}>保存</button>
</div>
```

**バックエンド API エンドポイント追加:**

```ruby
# lib/web/appserver.rb

get "/api/settings/parser" do
  content_type :json
  {
    default_engine: load_global_parser_config["default_engine"],
    sites: load_all_parser_configs
  }.to_json
end

post "/api/settings/parser" do
  content_type :json
  data = JSON.parse(request.body.read)
  
  # グローバル設定を保存
  save_global_parser_config(data["default_engine"])
  
  # サイト別設定を保存
  data["sites"]&.each do |domain, config|
    save_site_parser_config(domain, config, data["default_engine"])
  end
  
  { status: "ok" }.to_json
end
```

### E. エラーハンドリングとフォールバック

**方針:** パース失敗時の多段階フォールバック機構を実装。生HTMLは保存するが再取得時以外はリードオンリーとする。

**戦略:**
1. **生HTMLを保存** - ダウンロード時に必ず保存（既存の `raw/` ディレクトリ活用）
2. **新パーサーで試行** - Nokogiri + セレクタチェーンで解析
3. **失敗時の構造変更検出** - サイト構造変更の可能性をチェック
   - 変更検出時はユーザーに通知（Web UI: タスク失敗、CLI: ログ出力）
   - 自動修正可能な場合は次のフォールバックセレクタで再試行
4. **完全失敗時の処理** - エラー通知とログを残して終了（Legacy パーサーへのフォールバックは削除）

**実装例:**
```ruby
def robust_parse(url, setting)
  html = download_html(url)
  save_raw_html(html, url)  # 必ず生HTMLを保存
  
  parser = NokogiriParser.new(setting)
  
  begin
    result = parser.parse_section(html)
    return result if result.valid?
  rescue ParserError => e
    # セレクタチェーンで自動フォールバック試行済み
    logger.error "Parser failed after all fallback attempts: #{e.message}"
    
    # サイト構造変更の可能性を検出
    if detect_structure_change?(html, setting)
      notify_structure_change(url, setting)  # Web UI: タスク失敗、CLI: ログ
    end
    
    # エラー詳細をログに記録
    save_error_log(url, e, html)
    raise DownloadError, "パース失敗: #{url} - 詳細はログを参照してください"
  end
end

def detect_structure_change?(html, setting)
  # 以前成功したセレクタが今回全く要素を見つけられなかった場合
  # サイト構造が変更された可能性が高い
  previous_successful_selector = setting.parser_config["last_successful_selector"]
  return false unless previous_successful_selector
  
  doc = Nokogiri::HTML(html)
  doc.css(previous_successful_selector).empty?
end
```

**Legacy パーサーへのフォールバック削除の理由:**
- 新パーサー自体がセレクタチェーンでフォールバック機構を持つ
- Legacy パーサー（正規表現）は保守モードとし、明示的に選択した場合のみ使用
- 自動フォールバックすると問題の早期発見が遅れる（サイト変更に気づきにくい）


### F. 構造化ログとデバッグ支援

**方針:** パース過程を可視化し、サイト構造変更の早期発見を支援。

**ログ出力例:**
```
[INFO] Parsing https://ncode.syosetu.com/n1234ab/1/
[DEBUG] Trying selector: div.js-novel-text.p-novel__text
[DEBUG] Found 1 element(s)
[DEBUG] Extracted body: 1234 chars
[INFO] Parse success (nokogiri engine)
```

**失敗時:**
```
[WARN] Trying selector: div.js-novel-text.p-novel__text
[WARN] No elements found, trying fallback
[WARN] Trying selector: div.p-novel__text
[ERROR] All selectors failed, falling back to legacy parser
[INFO] Legacy parser success
[NOTICE] サイト構造が変更された可能性があります: https://ncode.syosetu.com/n1234ab/1/
```

---

## 実装計画

### Phase 1: Nokogiri基盤実装（Week 1-2）

1. `lib/narou/parsers/` ディレクトリ作成
2. `base_parser.rb` - 共通インターフェース定義
3. `nokogiri_parser.rb` - Nokogiri基盤の汎用パーサー
4. セレクタベース抽出の基本実装

### Phase 2: サイト別アダプタ実装（Week 3-4）

1. `narou_parser.rb` - 小説家になろう対応
2. `kakuyomu_parser.rb` - カクヨム対応（JSON解析含む）
3. `preset/parsers/*.yaml` - 新パーサー用デフォルト設定作成
4. フォールバックチェーン機構実装

### Phase 3: Legacy互換レイヤー（Week 5）

1. 既存の `Downloader` クラスをラップする `LegacyParser` 作成
2. パーサー選択ロジック実装（`select_parser`）
3. グローバル設定・小説別設定の読み込み機構

### Phase 4: テストとデバッグ（Week 6-7）

1. 各サイトの実データでテスト
2. エッジケース処理（壊れたHTML、特殊文字等）
3. パフォーマンス測定・最適化
4. エラーログ収集と改善

### Phase 5: ドキュメント整備（Week 8）

1. 新パーサーの設計書
2. YAML設定ファイル移行ガイド
3. トラブルシューティングガイド
4. 開発者向けアダプタ作成ガイド

### Phase 6: ロールアウト（Week 9-10）

1. デフォルトを `legacy` のまま新パーサーをオプトイン公開
2. ユーザーフィードバック収集
3. 問題修正と安定化
4. デフォルトを `nokogiri` に変更

---

## ファイル構成（新規作成予定）

```
lib/narou/parsers/
  base_parser.rb              # BaseParser クラス（抽象基底）
  nokogiri_parser.rb          # 汎用 Nokogiri パーサー
  legacy_parser.rb            # 既存実装のラッパー
  narou_parser.rb             # 小説家になろう専用
  kakuyomu_parser.rb          # カクヨム専用（JSON対応）
  hameln_parser.rb            # ハーメルン専用
  parser_selector.rb          # パーサー選択ロジック
  parser_error.rb             # カスタムエラークラス
  config_manager.rb           # パーサー設定の読み込み・保存

spec/parsers/
  base_parser_spec.rb
  nokogiri_parser_spec.rb
  narou_parser_spec.rb
  kakuyomu_parser_spec.rb
  config_manager_spec.rb
  ...

preset/parsers/                # 新パーサー用デフォルト設定（新規作成）
  ncode.syosetu.com.yaml      # セレクタベース設定
  kakuyomu.jp.yaml            # JSON + セレクタ設定
  www.akatsuki-novels.com.yaml
  novel18.syosetu.com.yaml
  ...

webnovel/                      # Legacy パーサー専用（既存、変更なし）
  ncode.syosetu.com.yaml      # 正規表現パターン
  kakuyomu.jp.yaml
  ...

.narou/                        # ユーザー設定領域
  parser_config.yaml          # グローバル設定
  parsers/                    # 新パーサー用ユーザー設定
    ncode.syosetu.com.yaml    # preset/parsers/ から初回コピー
    kakuyomu.jp.yaml
    custom-site.yaml          # ユーザー独自サイト
    ...
  legacy_parsers/             # Legacy パーサー用ユーザー設定
    ncode.syosetu.com.yaml    # webnovel/ から初回コピー
    kakuyomu.jp.yaml
    ...

frontend/src/components/       # Web UI コンポーネント
  ParserSettings.svelte       # パーサー設定画面（新規）

lib/web/appserver.rb           # API エンドポイント追加
  # GET  /api/settings/parser
  # POST /api/settings/parser
```

---

## YAML設定ファイル例

### 新パーサー用: `preset/parsers/ncode.syosetu.com.yaml`

```yaml
# サイト基本情報
name: 小説家になろう
domain: ncode.syosetu.com
encoding: UTF-8
top_url: https://ncode.syosetu.com
sitename: 小説家になろう

# 目次ページ設定
toc_url_pattern: "https://ncode.syosetu.com/{ncode}/"
toc_selectors:
  - selector: "div.p-eplist__sublist"
    priority: 10
    extract: "list"
    item_selectors:
      chapter: "div.p-eplist__chapter-title"
      subtitle: "a.p-eplist__subtitle"
      href: "a.p-eplist__subtitle::attr(href)"
      index: "a.p-eplist__subtitle::attr(href)"  # /n1234ab/123/ から 123 を抽出
      subdate: "div.p-eplist__update"

# 本文ページ設定
body_selectors:
  - selector: "div.js-novel-text.p-novel__text"
    priority: 10
    extract: "inner_html"
    description: "公式クラス名（2024年以降）"
  - selector: "div.p-novel__text"
    priority: 8
    extract: "inner_html"
    description: "BEMクラスのみ"
  - selector: "div#novel_honbun"
    priority: 5
    extract: "inner_html"
    description: "旧ID（2020年以前）"

introduction_selectors:
  - selector: "div.js-novel-text.p-novel__text--preface"
    priority: 10
    extract: "inner_html"
  - selector: "div.p-novel__text--preface"
    priority: 8
    extract: "inner_html"

postscript_selectors:
  - selector: "div.js-novel-text.p-novel__text--afterword"
    priority: 10
    extract: "inner_html"
  - selector: "div.p-novel__text--afterword"
    priority: 8
    extract: "inner_html"

# 小説情報ページ設定
novel_info_selectors:
  title: "h1.p-infotop-title a"
  author: "dd.p-infotop-data__value a"
  story: "dd.p-infotop-data__value"  # あらすじのセレクタ

# 成功履歴（自動更新、ユーザーは編集不要）
last_successful_selectors: {}
```

### 新パーサー用: `preset/parsers/kakuyomu.jp.yaml`

```yaml
# サイト基本情報
name: カクヨム
domain: kakuyomu.jp
encoding: UTF-8
top_url: https://kakuyomu.jp
sitename: カクヨム

# JSON データ抽出設定（Next.js のデータ）
json_data_source:
  selector: "script#__NEXT_DATA__"
  type: "application/json"
  paths:
    work_id: "query.workId"
    toc: "props.pageProps.__APOLLO_STATE__.Work:{workId}.tableOfContents"
    title: "props.pageProps.__APOLLO_STATE__.Work:{workId}.title"
    author: "props.pageProps.__APOLLO_STATE__.Work:{workId}.author.__ref"

# 本文ページ設定（フォールバック用）
body_selectors:
  - selector: "div.widget-episodeBody.js-episode-body"
    priority: 10
    extract: "inner_html"
    description: "メインコンテンツ"

# 成功履歴
last_successful_selectors: {}
```

### Legacy パーサー用: `webnovel/ncode.syosetu.com.yaml` (既存、変更なし)

```yaml
# 既存の正規表現パターン（変更なし）
name: &name 小説家になろう
domain: ncode.syosetu.com
top_url: https://\\k<domain>
url: https?://\\k<domain>/(?<ncode>n\d+[a-z]+)
encoding: UTF-8

# 正規表現による抽出
body_pattern: |-
  <div class="js-novel-text p-novel__text">
  (?<body>.+?)
  ?</div>

introduction_pattern: |-
  <div class="js-novel-text p-novel__text p-novel__text--preface">
  (?<introduction>.+?)
  ?</div>

# ... 以下既存のまま
```

---

## 移行チェックリスト

### 開発者向け
- [ ] Nokogiri gem の依存関係追加（Gemfile）
- [ ] `lib/narou/parsers/` ディレクトリとファイル作成
- [ ] `.narou/parsers/` および `.narou/legacy_parsers/` 自動生成機構
- [ ] `ParserConfigManager` クラス実装（設定の読み込み・保存・マージ）
- [ ] 既存テストの互換性確認
- [ ] 新テストスイート作成（RSpec）
- [ ] エラーログ収集機構実装
- [ ] Web UI パーサー設定タブ実装
- [ ] API エンドポイント追加（GET/POST `/api/settings/parser`）
- [ ] ドキュメント作成

### ユーザー向け
- [ ] 新パーサー使用のオプトイン手順公開
- [ ] `.narou/parsers/` 配下の設定ファイル編集ガイド
- [ ] Web UI でのパーサー設定編集方法
- [ ] トラブル時の legacy 切り替え手順
- [ ] サイト構造変更検出の通知機能
- [ ] カスタムセレクタ追加方法のチュートリアル
- [ ] フィードバック収集フォーム

---

## 期待される効果

1. **保守性向上:** 正規表現地獄からの脱却、可読性の高いセレクタベース実装
2. **耐障害性向上:** フォールバックチェーンによるサイト変更への対応力
3. **拡張性向上:** アダプタパターンで新サイト対応が容易
4. **デバッグ性向上:** 構造化ログで問題箇所の特定が迅速化
5. **安全性向上:** `eval` 使用の削減、セキュリティリスク低減
6. **設定の明確化:** 新パーサー（`preset/parsers/`）と Legacy（`webnovel/`）で完全分離、役割が明確
