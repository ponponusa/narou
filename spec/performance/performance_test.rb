# frozen_string_literal: true

require_relative "yaml_database_generator"
require_relative "novel_data_generator"
require "benchmark"
require "fileutils"

#
# Narou.rb MOD パフォーマンステスト統合スクリプト
#
# Usage:
#   ruby spec/performance/performance_test.rb setup [novel_count]
#   ruby spec/performance/performance_test.rb run
#   ruby spec/performance/performance_test.rb cleanup
#   ruby spec/performance/performance_test.rb full [novel_count]
#
class PerformanceTest
  REPORT_FILE = "performance_report.txt"

  def initialize
    @yaml_gen = YamlDatabaseGenerator.new
    @novel_gen = NovelDataGenerator.new
    @report = []
  end

  #
  # セットアップ: テストデータを生成
  #
  def setup(novel_count = 10000)
    log_section "=== パフォーマンステスト環境セットアップ ==="

    puts "生成する小説データ数: #{novel_count}件"
    puts "注意: 大量のデータを生成します。ディスク容量を確認してください。"
    puts ""

    # YAMLデータベース生成
    log_section "1. YAMLデータベース生成"
    @yaml_gen.generate(novel_count)

    # 小説データ生成（YAMLの1/5程度に抑える）
    novel_data_count = [novel_count / 5, 1000].max
    log_section "\n2. 小説データ（raw/txt）生成"
    puts "注意: 小説データは#{novel_data_count}件生成します（YAML件数の1/5）"
    @novel_gen.generate(novel_data_count)

    log_section "\nセットアップ完了！"
  end

  #
  # パフォーマンステスト実行
  #
  def run
    log_section "=== パフォーマンステスト実行 ==="

    start_time = Time.now

    # 1. YAMLデータベース読み込みテスト
    log_section "\n【1】 YAMLデータベース読み込みテスト"
    @yaml_gen.benchmark_read

    # 2. YAMLデータベース操作テスト
    log_section "\n【2】 YAMLデータベース操作テスト"
    @yaml_gen.benchmark_operations

    # 3. 小説データファイル読み込みテスト
    log_section "\n【3】 小説データファイル読み込みテスト"
    @novel_gen.benchmark_file_read

    # 4. HTML→TXT変換テスト
    log_section "\n【4】 HTML→TXT変換テスト"
    @novel_gen.benchmark_html_to_txt

    # 5. TXTファイル結合テスト
    log_section "\n【5】 TXTファイル結合テスト（EPUB変換向け）"
    @novel_gen.benchmark_txt_concat

    end_time = Time.now
    total_time = end_time - start_time

    log_section "\n=== テスト完了 ==="
    log "総実行時間: #{total_time.round(2)}秒"

    # レポート保存
    save_report
  end

  #
  # クリーンアップ: テストデータを削除
  #
  def cleanup
    log_section "=== テストデータクリーンアップ ==="

    @yaml_gen.cleanup
    @novel_gen.cleanup

    # レポートファイルも削除
    if File.exist?(REPORT_FILE)
      FileUtils.rm(REPORT_FILE)
      puts "レポートファイル削除: #{REPORT_FILE}"
    end

    log_section "クリーンアップ完了！"
  end

  #
  # フルテスト: セットアップ→実行→クリーンアップ
  #
  def full(novel_count = 10000)
    setup(novel_count)
    run

    puts "\n" + "=" * 60
    puts "フルテスト完了！"
    puts "レポートを確認してください: #{REPORT_FILE}"
    puts "=" * 60
    puts "\nテストデータを削除する場合は以下を実行:"
    puts "  ruby #{__FILE__} cleanup"
  end

  #
  # クイックテスト: 小規模データで簡易テスト
  #
  def quick
    log_section "=== クイックパフォーマンステスト ==="
    puts "注意: 少量データ（1000件）で簡易テストを実行します\n\n"

    full(1000)
  end

  #
  # 最適化推奨事項の分析
  #
  def analyze_and_recommend
    log_section "=== 最適化推奨事項の分析 ==="

    recommendations = []

    # YAMLデータベースサイズチェック
    yaml_db_path = File.join(YamlDatabaseGenerator::TEST_DATA_DIR, YamlDatabaseGenerator::DATABASE_FILE)
    if File.exist?(yaml_db_path)
      size_mb = File.size(yaml_db_path) / 1024.0 / 1024.0

      if size_mb > 100
        recommendations << {
          category: "YAMLデータベース",
          issue: "データベースファイルサイズが大きい（#{size_mb.round(2)} MB）",
          recommendation: "SQLiteやPostgreSQLなどのRDBMS導入を検討してください",
          priority: "高"
        }
      elsif size_mb > 50
        recommendations << {
          category: "YAMLデータベース",
          issue: "データベースファイルサイズが増加中（#{size_mb.round(2)} MB）",
          recommendation: "インデックス機能を持つデータベースへの移行を検討してください",
          priority: "中"
        }
      end
    end

    # キャッシュ機能の推奨
    recommendations << {
      category: "キャッシュ",
      issue: "頻繁なYAML読み込みでパフォーマンス低下の可能性",
      recommendation: "Inventory.load のキャッシュ機構を強化してください",
      priority: "中"
    }

    # 並列処理の推奨
    recommendations << {
      category: "並列処理",
      issue: "大量データの一括処理時間",
      recommendation: "変換処理などにマルチスレッド/プロセス処理を導入してください",
      priority: "中"
    }

    # zstd圧縮の推奨
    recommendations << {
      category: "圧縮",
      issue: "大量の小説データによるディスク使用量",
      recommendation: "zstd圧縮形式のサポートを実装してください",
      priority: "低"
    }

    # 推奨事項を表示
    puts "\n最適化推奨事項:\n\n"
    recommendations.each_with_index do |rec, i|
      puts "#{i + 1}. [#{rec[:priority]}] #{rec[:category]}"
      puts "   問題: #{rec[:issue]}"
      puts "   推奨: #{rec[:recommendation]}"
      puts ""
    end

    # レポートに追加
    @report << "\n=== 最適化推奨事項 ==="
    recommendations.each_with_index do |rec, i|
      @report << "\n#{i + 1}. [#{rec[:priority]}] #{rec[:category]}"
      @report << "   問題: #{rec[:issue]}"
      @report << "   推奨: #{rec[:recommendation]}"
    end

    save_report
  end

  private

  #
  # セクションログ
  #
  def log_section(message)
    puts message
    @report << message
  end

  #
  # ログ
  #
  def log(message)
    puts message
    @report << message
  end

  #
  # レポート保存
  #
  def save_report
    File.write(REPORT_FILE, @report.join("\n"))
    puts "\nレポート保存: #{REPORT_FILE}"
  end
end

# CLI実行
if __FILE__ == $PROGRAM_NAME
  test = PerformanceTest.new

  command = ARGV[0]
  case command
  when "setup"
    count = (ARGV[1] || 10000).to_i
    test.setup(count)
  when "run"
    test.run
  when "cleanup"
    test.cleanup
  when "full"
    count = (ARGV[1] || 10000).to_i
    test.full(count)
  when "quick"
    test.quick
  when "analyze"
    test.analyze_and_recommend
  else
    puts "Narou.rb MOD パフォーマンステストツール"
    puts ""
    puts "Usage:"
    puts "  ruby #{__FILE__} setup [count]     # テストデータ生成 (デフォルト: 10000件)"
    puts "  ruby #{__FILE__} run               # パフォーマンステスト実行"
    puts "  ruby #{__FILE__} cleanup           # テストデータ削除"
    puts "  ruby #{__FILE__} full [count]      # フルテスト（生成→実行→レポート）"
    puts "  ruby #{__FILE__} quick             # クイックテスト（1000件で簡易実行）"
    puts "  ruby #{__FILE__} analyze           # 最適化推奨事項の分析"
    puts ""
    puts "推奨ワークフロー:"
    puts "  1. クイックテストで動作確認"
    puts "     $ ruby #{__FILE__} quick"
    puts ""
    puts "  2. フルテストで詳細計測"
    puts "     $ ruby #{__FILE__} full 50000"
    puts ""
    puts "  3. 最適化推奨事項を確認"
    puts "     $ ruby #{__FILE__} analyze"
    puts ""
    puts "  4. テストデータを削除"
    puts "     $ ruby #{__FILE__} cleanup"
  end
end
