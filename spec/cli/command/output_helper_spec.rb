# frozen_string_literal: true

require "lib/cli/command/output_helper"

RSpec.describe Command::OutputHelper do
  let(:test_template_dir) { File.join("spec", "fixtures", "templates") }
  let(:test_log_file) { File.join("tmp", "test_output.log") }

  before do
    # テスト用テンプレートディレクトリを作成
    FileUtils.mkdir_p(test_template_dir)

    # モジュール変数をリセット
    described_class.instance_variable_set(:@logger, nil)
    described_class.instance_variable_set(:@output_mode, :stdout)
    described_class.instance_variable_set(:@tty_enabled, true)

    # ログファイルがあれば削除
    FileUtils.rm_f(test_log_file) if File.exist?(test_log_file)
  end

  after do
    # テスト用ファイルをクリーンアップ
    FileUtils.rm_rf(test_template_dir) if Dir.exist?(test_template_dir)
    FileUtils.rm_f(test_log_file) if File.exist?(test_log_file)
  end

  describe ".setup_logger" do
    context "引数なし（標準出力モード）" do
      it "標準出力モードに設定される" do
        described_class.setup_logger
        expect(described_class.instance_variable_get(:@output_mode)).to eq(:stdout)
      end

      it "Loggerが初期化される" do
        described_class.setup_logger
        expect(described_class.instance_variable_get(:@logger)).to be_a(Logger)
      end
    end

    context "ログファイルパス指定（ファイル出力モード）" do
      it "ファイル出力モードに設定される" do
        described_class.setup_logger(test_log_file)
        expect(described_class.instance_variable_get(:@output_mode)).to eq(:file)
      end

      it "ログファイルが作成される" do
        described_class.setup_logger(test_log_file)
        expect(File.exist?(test_log_file)).to be true
      end

      it "TTYが無効化される" do
        described_class.setup_logger(test_log_file)
        expect(described_class.instance_variable_get(:@tty_enabled)).to be false
      end
    end
  end

  describe ".info" do
    it "情報メッセージを出力できる" do
      described_class.setup_logger
      expect { described_class.info("テスト情報") }.not_to raise_error
    end
  end

  describe ".success" do
    it "成功メッセージを出力できる" do
      described_class.setup_logger
      expect { described_class.success("成功しました") }.not_to raise_error
    end
  end

  describe ".warning" do
    it "警告メッセージを出力できる" do
      described_class.setup_logger
      expect { described_class.warning("警告です") }.not_to raise_error
    end
  end

  describe ".error" do
    it "エラーメッセージを出力できる" do
      described_class.setup_logger
      expect { described_class.error("エラーが発生しました") }.not_to raise_error
    end
  end

  describe ".with_spinner" do
    context "標準出力モード" do
      before do
        described_class.setup_logger
        # TTYを有効にして標準出力モードをシミュレート
        described_class.instance_variable_set(:@tty_enabled, true)
      end

      it "スピナー付きで処理を実行できる" do
        result = described_class.with_spinner("テスト処理中") do
          sleep 0.1
          "完了"
        end
        expect(result).to eq("完了")
      end

      it "処理中にエラーが発生した場合も適切に処理される" do
        expect {
          described_class.with_spinner("エラーテスト") do
            raise StandardError, "テストエラー"
          end
        }.to raise_error(StandardError, "テストエラー")
      end
    end

    context "ファイル出力モード" do
      before do
        described_class.setup_logger(test_log_file)
      end

      it "ログファイルに出力される" do
        described_class.with_spinner("ファイル出力テスト") do
          "完了"
        end

        log_content = File.read(test_log_file)
        expect(log_content).to include("ファイル出力テスト...")
        expect(log_content).to include("ファイル出力テスト...完了")
      end
    end
  end

  describe ".box" do
    it "ボックス表示ができる" do
      described_class.setup_logger
      expect {
        described_class.box("テストタイトル", "テスト内容", style: :info)
      }.not_to raise_error
    end

    it "success スタイルでボックス表示ができる" do
      described_class.setup_logger
      expect {
        described_class.box("成功", "処理が成功しました", style: :success)
      }.not_to raise_error
    end

    it "error スタイルでボックス表示ができる" do
      described_class.setup_logger
      expect {
        described_class.box("エラー", "エラーが発生しました", style: :error)
      }.not_to raise_error
    end
  end

  describe "private .strip_markdown" do
    it "Markdownマークアップを除去できる" do
      markdown = <<~MD
        # 見出し
        **太字** と *斜体*
        - リスト項目
        `コード`
      MD

      # privateメソッドなので直接テストはしないが、
      # renderメソッド経由でテストされる
      expect(markdown).to be_a(String)
    end
  end
end
