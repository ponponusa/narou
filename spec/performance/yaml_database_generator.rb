# frozen_string_literal: true

require "yaml"
require "fileutils"
require "securerandom"
require "benchmark"

#
# YAMLデータベースのパフォーマンステスト用データ生成スクリプト
#
# Usage:
#   ruby spec/performance/yaml_database_generator.rb generate [count]
#   ruby spec/performance/yaml_database_generator.rb cleanup
#
class YamlDatabaseGenerator
  TEST_DATA_DIR = ".narou_perf_test"
  DATABASE_FILE = "database.yaml"
  FREEZE_FILE = "freeze.yaml"
  TOC_FILE = "toc.yaml"

  SAMPLE_TITLES = [
    "異世界転生したけど何もしないで平穏に暮らしたい",
    "最強魔法使いの冒険譚",
    "勇者パーティーを追放されたので自由に生きることにした",
    "転生したらスライムだった件について",
    "無職転生 - 異世界行ったら本気だす -",
    "この素晴らしい世界に祝福を！",
    "Re:ゼロから始める異世界生活",
    "ソードアート・オンライン",
    "オーバーロード",
    "幼女戦記"
  ]

  SAMPLE_AUTHORS = %w(
    山田太郎 佐藤花子 鈴木一郎 田中美咲 高橋健太
    伊藤さくら 渡辺翔太 中村麻美 小林大輔 加藤由美
  )

  SAMPLE_SITES = [
    { host: "ncode.syosetu.com", code_prefix: "N" },
    { host: "novel18.syosetu.com", code_prefix: "N" },
    { host: "kakuyomu.jp", code_prefix: "K" }
  ]

  SAMPLE_TAGS = %w(
    異世界転生 冒険 魔法 ファンタジー バトル
    恋愛 ハーレム スキル チート 成り上がり
  )

  def initialize
    @test_dir = File.join(Dir.pwd, TEST_DATA_DIR)
  end

  #
  # テストデータを生成
  #
  # @param [Integer] count 生成する小説データ数
  #
  def generate(count = 50000)
    puts "テストデータ生成開始: #{count}件"

    FileUtils.mkdir_p(@test_dir)

    database = {}
    freeze_db = {}
    toc_db = {}

    benchmark_result = Benchmark.measure do
      count.times do |i|
        id = i
        novel_data = generate_novel_data(id)
        database[id] = novel_data

        # 10%の確率で凍結状態にする
        if rand < 0.1
          freeze_db[id] = {
            "freeze" => true,
            "freeze_date" => Time.now - rand(86400 * 30)
          }
        end

        # TOCデータを生成
        toc_db[id] = generate_toc_data(novel_data)

        # 進捗表示
        if (i + 1) % 5000 == 0
          puts "#{i + 1}/#{count} 件生成完了..."
        end
      end
    end

    puts "\nデータ生成完了！"
    puts "生成時間: #{benchmark_result.real.round(2)}秒"

    # YAMLファイルに書き出し
    puts "\nYAMLファイル書き出し中..."
    write_benchmark = Benchmark.measure do
      File.write(File.join(@test_dir, DATABASE_FILE), YAML.dump(database))
      File.write(File.join(@test_dir, FREEZE_FILE), YAML.dump(freeze_db))
      File.write(File.join(@test_dir, TOC_FILE), YAML.dump(toc_db))
    end

    puts "書き出し完了！"
    puts "書き出し時間: #{write_benchmark.real.round(2)}秒"

    # ファイルサイズを表示
    display_file_sizes

    puts "\n生成完了: #{@test_dir}"
  end

  #
  # 小説データを生成
  #
  def generate_novel_data(id)
    site = SAMPLE_SITES.sample
    code = "#{site[:code_prefix]}#{rand(1000..9999)}#{('A'..'Z').to_a.sample}#{('A'..'Z').to_a.sample}"
    title = "#{SAMPLE_TITLES.sample} #{id}"
    author = SAMPLE_AUTHORS.sample

    {
      "id" => id,
      "title" => title,
      "author" => author,
      "sitename" => site[:host],
      "toc_url" => "https://#{site[:host]}/#{code.downcase}/",
      "novel_type" => rand < 0.7 ? 1 : 2, # 1: 連載, 2: 短編
      "end" => rand < 0.2,
      "general_firstup" => Time.now - rand(86400 * 365 * 3), # 過去3年以内
      "general_lastup" => Time.now - rand(86400 * 30), # 過去30日以内
      "last_update" => Time.now - rand(86400 * 7), # 過去7日以内
      "new_arrivals_date" => Time.now - rand(86400 * 30),
      "length" => rand(1000..500000),
      "time" => rand(10..1000),
      "ncode" => code,
      "global_point" => rand(1..100000),
      "daily_point" => rand(0..1000),
      "weekly_point" => rand(0..5000),
      "monthly_point" => rand(0..20000),
      "quarter_point" => rand(0..50000),
      "yearly_point" => rand(0..100000),
      "fav_novel_cnt" => rand(0..10000),
      "impression_cnt" => rand(0..5000),
      "review_cnt" => rand(0..500),
      "all_point" => rand(0..1000000),
      "all_hyoka_cnt" => rand(0..50000),
      "sasie_cnt" => rand(0..100),
      "kaiwaritu" => rand(0..100),
      "novelupdated_at" => Time.now - rand(86400 * 30),
      "updated_at" => Time.now - rand(86400 * 7),
      "tags" => Array.new(rand(1..5)) { SAMPLE_TAGS.sample }.uniq,
      "story" => "これは#{title}のあらすじです。" * rand(1..10),
      "genre" => rand(1..99),
      "gensaku" => "",
      "keyword" => Array.new(rand(3..10)) { SAMPLE_TAGS.sample }.uniq.join(" "),
      "general_all_no" => rand(1..1000)
    }
  end

  #
  # TOCデータを生成
  #
  def generate_toc_data(novel_data)
    episode_count = novel_data["novel_type"] == 2 ? 1 : rand(10..500)

    episodes = episode_count.times.map do |i|
      {
        "subtitle" => "第#{i + 1}話 #{SAMPLE_TITLES.sample}",
        "subdate" => (novel_data["general_firstup"] + (i * 86400)).strftime("%Y/%m/%d %H:%M"),
        "subupdate" => rand < 0.3 ? (novel_data["general_lastup"] - rand(86400 * 7)).strftime("%Y/%m/%d %H:%M") : nil,
        "chapter" => i % 10 == 0 ? "第#{(i / 10) + 1}章" : nil,
        "href" => "#{i + 1}/"
      }.compact
    end

    {
      "title" => novel_data["title"],
      "author" => novel_data["author"],
      "toc_url" => novel_data["toc_url"],
      "toc" => episodes
    }
  end

  #
  # ファイルサイズを表示
  #
  def display_file_sizes
    puts "\n=== ファイルサイズ ==="
    [DATABASE_FILE, FREEZE_FILE, TOC_FILE].each do |filename|
      path = File.join(@test_dir, filename)
      if File.exist?(path)
        size_mb = File.size(path) / 1024.0 / 1024.0
        puts "#{filename}: #{size_mb.round(2)} MB"
      end
    end
  end

  #
  # テストデータをクリーンアップ
  #
  def cleanup
    if Dir.exist?(@test_dir)
      puts "テストデータ削除中: #{@test_dir}"
      FileUtils.rm_rf(@test_dir)
      puts "削除完了！"
    else
      puts "テストデータが見つかりません: #{@test_dir}"
    end
  end

  #
  # テストデータの読み込みベンチマーク
  #
  def benchmark_read
    unless Dir.exist?(@test_dir)
      puts "エラー: テストデータが見つかりません"
      puts "先に 'ruby #{__FILE__} generate' を実行してください"
      return
    end

    puts "=== 読み込みベンチマーク ==="

    database_path = File.join(@test_dir, DATABASE_FILE)
    freeze_path = File.join(@test_dir, FREEZE_FILE)
    toc_path = File.join(@test_dir, TOC_FILE)

    # database.yaml 読み込み
    puts "\n1. database.yaml 読み込み..."
    db_result = Benchmark.measure do
      @database = YAML.unsafe_load_file(database_path)
    end
    puts "  読み込み時間: #{db_result.real.round(2)}秒"
    puts "  データ件数: #{@database.size}件"

    # freeze.yaml 読み込み
    puts "\n2. freeze.yaml 読み込み..."
    freeze_result = Benchmark.measure do
      @freeze_db = YAML.unsafe_load_file(freeze_path)
    end
    puts "  読み込み時間: #{freeze_result.real.round(2)}秒"
    puts "  データ件数: #{@freeze_db.size}件"

    # toc.yaml 読み込み
    puts "\n3. toc.yaml 読み込み..."
    toc_result = Benchmark.measure do
      @toc_db = YAML.unsafe_load_file(toc_path)
    end
    puts "  読み込み時間: #{toc_result.real.round(2)}秒"
    puts "  データ件数: #{@toc_db.size}件"

    puts "\n=== 合計読み込み時間: #{(db_result.real + freeze_result.real + toc_result.real).round(2)}秒 ==="
  end

  #
  # データ操作ベンチマーク
  #
  def benchmark_operations
    unless Dir.exist?(@test_dir)
      puts "エラー: テストデータが見つかりません"
      return
    end

    # データ読み込み
    database_path = File.join(@test_dir, DATABASE_FILE)
    @database = YAML.unsafe_load_file(database_path)

    puts "\n=== データ操作ベンチマーク ==="
    puts "データ件数: #{@database.size}件\n"

    # 1. ID検索
    puts "\n1. ID検索 (1000回)"
    search_result = Benchmark.measure do
      1000.times do
        id = rand(0...@database.size)
        @database[id]
      end
    end
    puts "  実行時間: #{search_result.real.round(4)}秒"
    puts "  1回あたり: #{(search_result.real / 1000 * 1000).round(4)}ms"

    # 2. タイトル検索
    puts "\n2. タイトル検索 (1000回)"
    title_search_result = Benchmark.measure do
      1000.times do
        target_title = SAMPLE_TITLES.sample
        @database.select { |_, data| data["title"].include?(target_title) }
      end
    end
    puts "  実行時間: #{title_search_result.real.round(4)}秒"
    puts "  1回あたり: #{(title_search_result.real / 1000 * 1000).round(4)}ms"

    # 3. タグフィルタリング
    puts "\n3. タグフィルタリング (1000回)"
    tag_filter_result = Benchmark.measure do
      1000.times do
        target_tag = SAMPLE_TAGS.sample
        @database.select { |_, data| data["tags"]&.include?(target_tag) }
      end
    end
    puts "  実行時間: #{tag_filter_result.real.round(4)}秒"
    puts "  1回あたり: #{(tag_filter_result.real / 1000 * 1000).round(4)}ms"

    # 4. ソート処理
    puts "\n4. 更新日時ソート (100回)"
    sort_result = Benchmark.measure do
      100.times do
        @database.values.sort_by { |data| data["general_lastup"] }
      end
    end
    puts "  実行時間: #{sort_result.real.round(4)}秒"
    puts "  1回あたり: #{(sort_result.real / 100 * 1000).round(4)}ms"

    # 5. データ更新 + 保存
    puts "\n5. データ更新 + YAML書き込み (10回)"
    update_result = Benchmark.measure do
      10.times do
        id = rand(0...@database.size)
        @database[id]["last_update"] = Time.now
        File.write(File.join(@test_dir, "database_temp.yaml"), YAML.dump(@database))
      end
    end
    puts "  実行時間: #{update_result.real.round(4)}秒"
    puts "  1回あたり: #{(update_result.real / 10 * 1000).round(4)}ms"

    # 一時ファイル削除
    FileUtils.rm_f(File.join(@test_dir, "database_temp.yaml"))
  end
end

# CLI実行
if __FILE__ == $PROGRAM_NAME
  generator = YamlDatabaseGenerator.new

  command = ARGV[0]
  case command
  when "generate"
    count = (ARGV[1] || 50000).to_i
    generator.generate(count)
  when "cleanup"
    generator.cleanup
  when "benchmark-read"
    generator.benchmark_read
  when "benchmark-ops"
    generator.benchmark_operations
  when "benchmark-all"
    generator.benchmark_read
    generator.benchmark_operations
  else
    puts "Usage:"
    puts "  ruby #{__FILE__} generate [count]       # テストデータ生成 (デフォルト: 50000件)"
    puts "  ruby #{__FILE__} cleanup                # テストデータ削除"
    puts "  ruby #{__FILE__} benchmark-read         # 読み込みベンチマーク"
    puts "  ruby #{__FILE__} benchmark-ops          # 操作ベンチマーク"
    puts "  ruby #{__FILE__} benchmark-all          # 全ベンチマーク実行"
  end
end
