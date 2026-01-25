# frozen_string_literal: true

require "fileutils"
require "securerandom"
require "benchmark"
require "nokogiri"

#
# 小説データ（raw, txt）のパフォーマンステスト用データ生成スクリプト
#
# Usage:
#   ruby spec/performance/novel_data_generator.rb generate [count]
#   ruby spec/performance/novel_data_generator.rb cleanup
#
class NovelDataGenerator
  TEST_DATA_DIR = "小説データ_perf_test"

  # 小説の規模パターン
  NOVEL_PATTERNS = [
    { name: "短編", episodes: 1, chars_per_episode: 5000 },
    { name: "短編集", episodes: rand(3..10), chars_per_episode: 3000 },
    { name: "短編連載", episodes: rand(10..30), chars_per_episode: 4000 },
    { name: "中編", episodes: rand(30..100), chars_per_episode: 5000 },
    { name: "長編", episodes: rand(100..300), chars_per_episode: 6000 },
    { name: "大長編", episodes: rand(300..1000), chars_per_episode: 7000 },
    { name: "超長編", episodes: rand(1000..3000), chars_per_episode: 8000 },
    { name: "極長編", episodes: rand(3000..10000), chars_per_episode: 5000 }
  ]

  SAMPLE_CONTENT = [
    "　これは物語の始まりである。主人公は平凡な高校生だった。",
    "　ある日、不思議な出来事が起こった。それは世界を変える出来事だった。",
    "　彼は決意した。この世界を守るために、戦うことを。",
    "　仲間たちとの出会いが、彼を成長させていく。",
    "　試練は続く。しかし、希望を捨てることはなかった。",
    "　激しい戦いの末、ついに敵の正体が明らかになる。",
    "　感動の再会。涙が止まらなかった。",
    "　新たな冒険の始まりである。",
    "　予期せぬ展開に、誰もが驚いた。",
    "　これが、真実だったのだ。"
  ]

  def initialize
    @test_dir = File.join(Dir.pwd, TEST_DATA_DIR)
  end

  #
  # テストデータを生成
  #
  # @param [Integer] count 生成する小説データ数
  #
  def generate(count = 50000)
    puts "小説データ生成開始: #{count}件"
    puts "注意: 大量のファイルを生成します。ディスク容量に注意してください。\n\n"

    FileUtils.mkdir_p(@test_dir)

    total_files = 0
    total_size = 0

    # パターン別の分布を決定（現実的な比率）
    pattern_distribution = [
      { pattern: 0, weight: 30 },  # 短編: 30%
      { pattern: 1, weight: 20 },  # 短編集: 20%
      { pattern: 2, weight: 15 },  # 短編連載: 15%
      { pattern: 3, weight: 15 },  # 中編: 15%
      { pattern: 4, weight: 10 },  # 長編: 10%
      { pattern: 5, weight: 7 },   # 大長編: 7%
      { pattern: 6, weight: 2 },   # 超長編: 2%
      { pattern: 7, weight: 1 }    # 極長編: 1%
    ]

    benchmark_result = Benchmark.measure do
      count.times do |i|
        # パターンを重み付きで選択
        pattern = select_pattern(pattern_distribution)
        novel_info = NOVEL_PATTERNS[pattern].dup

        # エピソード数が範囲の場合は確定値に
        if novel_info[:episodes].is_a?(Range)
          novel_info[:episodes] = rand(novel_info[:episodes])
        end

        # 小説ディレクトリを作成
        novel_id = i
        novel_dir = File.join(@test_dir, novel_id.to_s)
        FileUtils.mkdir_p(novel_dir)

        # rawディレクトリとtxtディレクトリを作成
        raw_dir = File.join(novel_dir, "raw")
        txt_dir = File.join(novel_dir, "txt")
        FileUtils.mkdir_p(raw_dir)
        FileUtils.mkdir_p(txt_dir)

        # エピソードファイルを生成
        novel_info[:episodes].times do |ep|
          episode_num = ep + 1

          # rawファイル（HTML形式）
          raw_file = File.join(raw_dir, "#{episode_num}.html")
          raw_content = generate_raw_episode(episode_num, novel_info[:chars_per_episode])
          File.write(raw_file, raw_content)
          total_files += 1
          total_size += raw_content.bytesize

          # txtファイル（プレーンテキスト）
          txt_file = File.join(txt_dir, "#{episode_num}.txt")
          txt_content = generate_txt_episode(episode_num, novel_info[:chars_per_episode])
          File.write(txt_file, txt_content)
          total_files += 1
          total_size += txt_content.bytesize
        end

        # 進捗表示
        if (i + 1) % 1000 == 0
          puts "#{i + 1}/#{count} 件生成完了... (ファイル数: #{total_files}, サイズ: #{(total_size / 1024.0 / 1024.0).round(2)} MB)"
        end
      end
    end

    puts "\n=== 生成完了 ==="
    puts "生成時間: #{benchmark_result.real.round(2)}秒"
    puts "小説数: #{count}件"
    puts "総ファイル数: #{total_files}件"
    puts "総サイズ: #{(total_size / 1024.0 / 1024.0).round(2)} MB"
    puts "生成先: #{@test_dir}"
  end

  #
  # 重み付きでパターンを選択
  #
  def select_pattern(distribution)
    total_weight = distribution.sum { |d| d[:weight] }
    random = rand(0...total_weight)

    cumulative = 0
    distribution.each do |d|
      cumulative += d[:weight]
      return d[:pattern] if random < cumulative
    end

    distribution.last[:pattern]
  end

  #
  # RAWエピソードファイルを生成（HTML形式）
  #
  def generate_raw_episode(episode_num, chars)
    paragraphs = (chars / 50).times.map do
      SAMPLE_CONTENT.sample
    end

    html = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <title>第#{episode_num}話</title>
      </head>
      <body>
        <div id="novel_contents">
          <div class="novel_subtitle">第#{episode_num}話 テストエピソード</div>
          <div class="novel_view">
            <p>#{paragraphs.join("</p>\n          <p>")}</p>
          </div>
        </div>
      </body>
      </html>
    HTML

    html
  end

  #
  # TXTエピソードファイルを生成（プレーンテキスト）
  #
  def generate_txt_episode(episode_num, chars)
    paragraphs = (chars / 50).times.map do
      SAMPLE_CONTENT.sample
    end

    txt = <<~TXT
      第#{episode_num}話 テストエピソード

      #{paragraphs.join("\n\n")}
    TXT

    txt
  end

  #
  # テストデータをクリーンアップ
  #
  def cleanup
    if Dir.exist?(@test_dir)
      puts "小説データ削除中: #{@test_dir}"
      puts "注意: 大量のファイルを削除します。時間がかかる場合があります。"

      benchmark = Benchmark.measure do
        FileUtils.rm_rf(@test_dir)
      end

      puts "削除完了！（#{benchmark.real.round(2)}秒）"
    else
      puts "テストデータが見つかりません: #{@test_dir}"
    end
  end

  #
  # HTML→TXT変換ベンチマーク
  #
  def benchmark_html_to_txt
    unless Dir.exist?(@test_dir)
      puts "エラー: テストデータが見つかりません"
      puts "先に 'ruby #{__FILE__} generate' を実行してください"
      return
    end

    puts "=== HTML→TXT変換ベンチマーク ==="

    # サンプルとして最初の10小説を変換
    sample_count = 10
    total_files = 0

    benchmark_result = Benchmark.measure do
      Dir.glob(File.join(@test_dir, "*")).first(sample_count).each do |novel_dir|
        next unless File.directory?(novel_dir)

        raw_dir = File.join(novel_dir, "raw")
        next unless File.directory?(raw_dir)

        Dir.glob(File.join(raw_dir, "*.html")).each do |html_file|
          # 簡易的なHTML→TXT変換（実際の変換処理に置き換え可能）
          content = File.read(html_file)
          # Nokogiriを使用して安全にHTMLからテキストを抽出
          doc = Nokogiri::HTML(content)
          # script/styleタグを削除
          doc.css("script, style").remove
          # テキストコンテンツを抽出
          txt_content = doc.text.gsub(/\s+/, " ").strip

          # 結果を一時ファイルに保存
          txt_file = html_file.sub("/raw/", "/txt_converted/").sub(".html", ".txt")
          FileUtils.mkdir_p(File.dirname(txt_file))
          File.write(txt_file, txt_content)

          total_files += 1
        end
      end
    end

    puts "変換ファイル数: #{total_files}件"
    puts "変換時間: #{benchmark_result.real.round(4)}秒"
    puts "1ファイルあたり: #{(benchmark_result.real / total_files * 1000).round(4)}ms"

    # 一時ファイル削除
    Dir.glob(File.join(@test_dir, "*", "txt_converted")).each do |dir|
      FileUtils.rm_rf(dir)
    end
  end

  #
  # TXTファイル結合ベンチマーク（EPUB変換向け）
  #
  def benchmark_txt_concat
    unless Dir.exist?(@test_dir)
      puts "エラー: テストデータが見つかりません"
      return
    end

    puts "\n=== TXTファイル結合ベンチマーク ==="

    # サンプルとして最初の10小説を結合
    sample_count = 10

    benchmark_result = Benchmark.measure do
      Dir.glob(File.join(@test_dir, "*")).first(sample_count).each do |novel_dir|
        next unless File.directory?(novel_dir)

        txt_dir = File.join(novel_dir, "txt")
        next unless File.directory?(txt_dir)

        # 全エピソードを結合
        combined_content = +"" # frozen_string_literal対策で+を付ける
        Dir.glob(File.join(txt_dir, "*.txt")).sort_by { |f| File.basename(f, ".txt").to_i }.each do |txt_file|
          combined_content << File.read(txt_file)
          combined_content << "\n\n#{'-' * 50}\n\n"
        end

        # 結合ファイルを保存
        combined_file = File.join(novel_dir, "combined.txt")
        File.write(combined_file, combined_content)
      end
    end

    puts "結合小説数: #{sample_count}件"
    puts "結合時間: #{benchmark_result.real.round(4)}秒"
    puts "1小説あたり: #{(benchmark_result.real / sample_count * 1000).round(4)}ms"

    # 一時ファイル削除
    Dir.glob(File.join(@test_dir, "*", "combined.txt")).each do |file|
      FileUtils.rm(file)
    end
  end

  #
  # ファイル読み込みベンチマーク
  #
  def benchmark_file_read
    unless Dir.exist?(@test_dir)
      puts "エラー: テストデータが見つかりません"
      return
    end

    puts "\n=== ファイル読み込みベンチマーク ==="

    # サンプルファイルを収集
    sample_files = []
    Dir.glob(File.join(@test_dir, "*", "txt", "*.txt")).first(1000).each do |file|
      sample_files << file
    end

    puts "対象ファイル数: #{sample_files.size}件"

    # 読み込みベンチマーク
    benchmark_result = Benchmark.measure do
      sample_files.each do |file|
        File.read(file)
      end
    end

    puts "読み込み時間: #{benchmark_result.real.round(4)}秒"
    puts "1ファイルあたり: #{(benchmark_result.real / sample_files.size * 1000).round(4)}ms"
  end
end

# CLI実行
if __FILE__ == $PROGRAM_NAME
  generator = NovelDataGenerator.new

  command = ARGV[0]
  case command
  when "generate"
    count = (ARGV[1] || 1000).to_i
    puts "警告: デフォルトは1000件です。50000件生成する場合は明示的に指定してください。"
    puts "例: ruby #{__FILE__} generate 50000"
    puts ""
    generator.generate(count)
  when "cleanup"
    generator.cleanup
  when "benchmark-html"
    generator.benchmark_html_to_txt
  when "benchmark-concat"
    generator.benchmark_txt_concat
  when "benchmark-read"
    generator.benchmark_file_read
  when "benchmark-all"
    generator.benchmark_html_to_txt
    generator.benchmark_txt_concat
    generator.benchmark_file_read
  else
    puts "Usage:"
    puts "  ruby #{__FILE__} generate [count]       # 小説データ生成 (デフォルト: 1000件)"
    puts "  ruby #{__FILE__} cleanup                # テストデータ削除"
    puts "  ruby #{__FILE__} benchmark-html         # HTML→TXT変換ベンチマーク"
    puts "  ruby #{__FILE__} benchmark-concat       # TXTファイル結合ベンチマーク"
    puts "  ruby #{__FILE__} benchmark-read         # ファイル読み込みベンチマーク"
    puts "  ruby #{__FILE__} benchmark-all          # 全ベンチマーク実行"
    puts ""
    puts "注意:"
    puts "  - 50000件生成すると数GB〜数十GBのディスク容量を使用します"
    puts "  - 生成・削除には時間がかかる場合があります"
  end
end
