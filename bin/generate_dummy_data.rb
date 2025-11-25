#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "fileutils"
require "securerandom"
require "benchmark"

#
# ダミーデータ生成スクリプト
#
# Usage:
#   ruby bin/generate_dummy_data.rb [count]
#   ruby bin/generate_dummy_data.rb cleanup
#
class DummyDataGenerator
  NAROU_DIR = ".narou"
  NOVEL_DIR = "小説データ"
  DATABASE_FILE = "database.yaml"
  
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
    "幼女戦記",
    "ありふれた職業で世界最強",
    "盾の勇者の成り上がり",
    "魔王学院の不適合者",
    "転スラ日記",
    "悪役令嬢に転生したようですが",
    "最果てのパラディン",
    "ゴブリンスレイヤー",
    "ダンジョン飯",
    "薬屋のひとりごと",
    "本好きの下剋上"
  ]
  
  SAMPLE_AUTHORS = [
    "山田太郎", "佐藤花子", "鈴木一郎", "田中美咲", "高橋健太",
    "伊藤さくら", "渡辺翔太", "中村麻美", "小林大輔", "加藤由美",
    "佐々木健", "吉田愛", "松本真", "井上優", "木村香織",
    "林直樹", "斎藤美穂", "清水翔", "山本彩", "森田拓也"
  ]
  
  SAMPLE_SITES = [
    { host: "ncode.syosetu.com", code_prefix: "N", name: "小説家になろう" },
    { host: "novel18.syosetu.com", code_prefix: "N", name: "小説家になろう（18禁）" },
    { host: "kakuyomu.jp", code_prefix: "", name: "カクヨム" }
  ]
  
  SAMPLE_TAGS = [
    "異世界転生", "冒険", "魔法", "ファンタジー", "バトル",
    "恋愛", "ハーレム", "スキル", "チート", "成り上がり",
    "現代", "学園", "コメディ", "シリアス", "ダーク"
  ]
  
  def initialize
    @narou_dir = File.join(Dir.pwd, NAROU_DIR)
    @novel_dir = File.join(Dir.pwd, NOVEL_DIR)
    @database_path = File.join(@narou_dir, DATABASE_FILE)
  end
  
  #
  # ダミーデータを生成
  #
  # @param [Integer] count 生成する小説データ数
  #
  def generate(count = 10000)
    puts "ダミーデータ生成開始: #{count}件"
    puts "対象ディレクトリ:"
    puts "  - #{@narou_dir}"
    puts "  - #{@novel_dir}"
    
    # ディレクトリ作成
    FileUtils.mkdir_p(@narou_dir)
    FileUtils.mkdir_p(@novel_dir)
    
    # 既存のデータベースを読み込む
    database = load_database
    
    # 既存の最大IDを取得
    max_id = database.keys.map(&:to_i).max || -1
    start_id = max_id + 1
    
    puts "\n既存データ: #{database.size}件"
    puts "新規ID開始: #{start_id}"
    
    benchmark_result = Benchmark.measure do
      count.times do |i|
        id = start_id + i
        novel_data = generate_novel_data(id)
        database[id.to_s] = novel_data
        
        # 小説ディレクトリとファイルを生成
        create_novel_files(id, novel_data)
        
        # 進捗表示
        if (i + 1) % 1000 == 0
          puts "#{i + 1}/#{count} 件生成完了..."
        end
      end
    end
    
    puts "\nデータ生成完了！"
    puts "生成時間: #{benchmark_result.real.round(2)}秒"
    
    # データベースファイルに書き出し
    puts "\nデータベースファイル書き出し中..."
    write_benchmark = Benchmark.measure do
      File.write(@database_path, YAML.dump(database))
    end
    
    puts "書き出し完了！"
    puts "書き出し時間: #{write_benchmark.real.round(2)}秒"
    
    # ファイルサイズを表示
    display_file_sizes
    
    puts "\n生成完了!"
    puts "総小説数: #{database.size}件（新規: #{count}件）"
  end
  
  #
  # 既存のデータベースを読み込む
  #
  def load_database
    if File.exist?(@database_path)
      YAML.load_file(@database_path) || {}
    else
      {}
    end
  rescue => e
    puts "警告: データベース読み込みエラー: #{e.message}"
    {}
  end
  
  #
  # 小説データを生成
  #
  def generate_novel_data(id)
    site = SAMPLE_SITES.sample
    code = generate_ncode(site)
    title = "#{SAMPLE_TITLES.sample} ##{id}"
    author = SAMPLE_AUTHORS.sample
    novel_type = rand < 0.7 ? 1 : 2 # 1: 連載, 2: 短編
    episode_count = novel_type == 2 ? 1 : rand(10..500)
    
    first_up = Time.now - rand(86400 * 365 * 3) # 過去3年以内
    last_up = Time.now - rand(86400 * 30) # 過去30日以内
    
    # タグに必ず "dummy" を追加
    tags = (["dummy"] + Array.new(rand(1..4)) { SAMPLE_TAGS.sample }).uniq
    
    {
      "id" => id,
      "title" => title,
      "author" => author,
      "sitename" => site[:host],
      "toc_url" => generate_toc_url(site, code),
      "novel_type" => novel_type,
      "end" => rand < 0.2,
      "general_firstup" => first_up,
      "general_lastup" => last_up,
      "last_update" => Time.now - rand(86400 * 7),
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
      "novelupdated_at" => last_up,
      "updated_at" => Time.now - rand(86400 * 7),
      "tags" => tags,
      "story" => "これは#{title}のあらすじです。ダミーデータとして生成されました。\n#{SAMPLE_TITLES.sample(3).join('、')}のような要素を含んだ物語です。",
      "genre" => rand(1..99),
      "gensaku" => "",
      "keyword" => tags.join(" "),
      "general_all_no" => episode_count,
      "freeze" => rand < 0.05 # 5%の確率で凍結
    }
  end
  
  #
  # Nコード生成
  #
  def generate_ncode(site)
    if site[:code_prefix] == "N"
      # なろう系: N1234AB形式
      "N#{rand(1000..9999)}#{('A'..'Z').to_a.sample}#{('A'..'Z').to_a.sample}"
    else
      # カクヨム: 数字のみ
      rand(1000000000000..9999999999999).to_s
    end
  end
  
  #
  # TOC URLを生成
  #
  def generate_toc_url(site, code)
    case site[:host]
    when "ncode.syosetu.com", "novel18.syosetu.com"
      "https://#{site[:host]}/#{code.downcase}/"
    when "kakuyomu.jp"
      "https://#{site[:host]}/works/#{code}"
    else
      "https://#{site[:host]}/#{code}"
    end
  end
  
  #
  # 小説ファイルを作成
  #
  def create_novel_files(id, novel_data)
    novel_dir = File.join(@novel_dir, id.to_s)
    FileUtils.mkdir_p(novel_dir)
    
    # setting.ini
    create_setting_ini(novel_dir, novel_data)
    
    # toc.yaml
    create_toc_yaml(novel_dir, novel_data)
    
    # エピソードファイル（短編 or 連載の数話分）
    episode_count = novel_data["novel_type"] == 2 ? 1 : [novel_data["general_all_no"], 5].min
    episode_count.times do |i|
      create_episode_file(novel_dir, i + 1, novel_data)
    end
  end
  
  #
  # setting.iniを作成
  #
  def create_setting_ini(novel_dir, novel_data)
    content = <<~INI
      [version]
      0.0.0 = 2024-01-01 00:00:00
      
      [title]
      name = #{novel_data['title']}
      
      [author]
      name = #{novel_data['author']}
    INI
    
    File.write(File.join(novel_dir, "setting.ini"), content)
  end
  
  #
  # toc.yamlを作成
  #
  def create_toc_yaml(novel_dir, novel_data)
    episode_count = novel_data["novel_type"] == 2 ? 1 : novel_data["general_all_no"]
    
    episodes = episode_count.times.map do |i|
      {
        "subtitle" => "第#{i + 1}話 #{SAMPLE_TITLES.sample}",
        "subdate" => (novel_data["general_firstup"] + (i * 86400)).strftime("%Y/%m/%d %H:%M"),
        "href" => "#{i + 1}/"
      }
    end
    
    toc_data = {
      "title" => novel_data["title"],
      "author" => novel_data["author"],
      "toc_url" => novel_data["toc_url"],
      "toc" => episodes
    }
    
    File.write(File.join(novel_dir, "toc.yaml"), YAML.dump(toc_data))
  end
  
  #
  # エピソードファイルを作成
  #
  def create_episode_file(novel_dir, episode_num, novel_data)
    content = <<~HTML
      <div class="novel_subtitle">第#{episode_num}話 #{SAMPLE_TITLES.sample}</div>
      <div class="novel_text">
        <p>これはダミーデータとして生成された#{episode_num}話目の本文です。</p>
        <p>#{novel_data['title']}の物語が展開されます。</p>
        <p>#{SAMPLE_TITLES.sample(3).join('、')}などの要素が含まれています。</p>
      </div>
    HTML
    
    File.write(File.join(novel_dir, "#{episode_num}.html"), content)
  end
  
  #
  # ファイルサイズを表示
  #
  def display_file_sizes
    puts "\n=== ファイルサイズ ==="
    if File.exist?(@database_path)
      size_mb = File.size(@database_path) / 1024.0 / 1024.0
      puts "#{DATABASE_FILE}: #{size_mb.round(2)} MB"
    end
  end
  
  #
  # ダミーデータをクリーンアップ
  #
  def cleanup
    puts "ダミーデータをクリーンアップ中..."
    
    # データベース読み込み
    database = load_database
    
    if database.empty?
      puts "データベースが空です"
      return
    end
    
    # dummy タグを持つデータを削除
    dummy_ids = database.select { |id, data| data["tags"]&.include?("dummy") }.keys
    
    puts "削除対象: #{dummy_ids.size}件"
    
    if dummy_ids.empty?
      puts "削除対象のダミーデータが見つかりません"
      return
    end
    
    # 確認
    print "本当に削除しますか？ (y/N): "
    answer = gets.chomp
    
    unless answer.downcase == "y"
      puts "キャンセルしました"
      return
    end
    
    # 削除実行
    benchmark_result = Benchmark.measure do
      dummy_ids.each do |id|
        database.delete(id)
        
        # 小説ディレクトリを削除
        novel_dir = File.join(@novel_dir, id)
        FileUtils.rm_rf(novel_dir) if File.exist?(novel_dir)
        
        if dummy_ids.index(id) % 1000 == 0
          puts "#{dummy_ids.index(id) + 1}/#{dummy_ids.size} 件削除..."
        end
      end
      
      # データベース保存
      File.write(@database_path, YAML.dump(database))
    end
    
    puts "\n削除完了！"
    puts "削除時間: #{benchmark_result.real.round(2)}秒"
    puts "残り小説数: #{database.size}件"
  end
end

# メイン処理
if __FILE__ == $PROGRAM_NAME
  generator = DummyDataGenerator.new
  
  if ARGV[0] == "cleanup"
    generator.cleanup
  elsif ARGV[0] =~ /^\d+$/
    count = ARGV[0].to_i
    generator.generate(count)
  elsif ARGV[0].nil?
    generator.generate(10000)
  else
    puts "Usage:"
    puts "  ruby bin/generate_dummy_data.rb [count]     # ダミーデータ生成（デフォルト: 10000件）"
    puts "  ruby bin/generate_dummy_data.rb cleanup     # ダミーデータ削除"
    exit 1
  end
end
