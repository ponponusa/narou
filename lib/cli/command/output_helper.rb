# frozen_string_literal: true

#
# Copyright 2025 ponponusa
#
# This is part of narou-mod and is distributed under the MIT License
#

require "erb"
require "logger"
require "tty-markdown"
require "tty-spinner"
require "tty-box"
require "pastel"

module Command
  #
  # CLI出力を一元管理するヘルパーモジュール
  # TUIライブラリ（tty-*）を使用した見やすい出力を提供
  #
  module OutputHelper
    extend self

    # 出力モード
    MODE_STDOUT = :stdout  # 標準出力（TUI使用）
    MODE_FILE = :file      # ファイル出力（プレーンテキスト）

    # Pastelインスタンス（色付き出力用）
    @pastel = Pastel.new

    # Logger インスタンス
    @logger = nil

    # 出力モード
    @output_mode = MODE_STDOUT

    # 元のSTDOUTを保存（Narou::Loggerに置き換わる前の実際のターミナル）
    ORIGINAL_STDOUT = STDOUT.dup
    ORIGINAL_STDERR = STDERR.dup

    # TTY検出（パイプやリダイレクト時はTUIを無効化）
    @tty_enabled = ORIGINAL_STDOUT.tty?

    #
    # ログファイルを設定
    #
    # @param [String, nil] log_file ログファイルパス（nilの場合は標準出力）
    #
    def setup_logger(log_file = nil)
      if log_file
        # ファイル出力モード
        log_dir = File.dirname(log_file)
        FileUtils.mkdir_p(log_dir) unless File.exist?(log_dir)

        @logger = Logger.new(log_file)
        @output_mode = MODE_FILE
        @tty_enabled = false

        # 標準出力・エラー出力をログファイルにリダイレクト
        # テスト環境ではSTDOUT/STDERRがStringIOの場合があるのでスキップ
        unless ORIGINAL_STDOUT.is_a?(StringIO) || ORIGINAL_STDERR.is_a?(StringIO)
          ORIGINAL_STDOUT.reopen(log_file, "a")
          ORIGINAL_STDERR.reopen(ORIGINAL_STDOUT)
          ORIGINAL_STDOUT.sync = true
          ORIGINAL_STDERR.sync = true
        end
      else
        # 標準出力モード（デフォルト）
        # 元のSTDOUTを使ってLoggerを作成
        @logger = Logger.new(ORIGINAL_STDOUT)
        @output_mode = MODE_STDOUT
        @tty_enabled = ORIGINAL_STDOUT.tty?
      end

      @logger.level = Logger::INFO
      @logger.formatter = proc do |severity, datetime, _progname, msg|
        if @output_mode == MODE_FILE
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
        else
          # 標準出力モードではタイムスタンプなし
          "#{msg}\n"
        end
      end
    end

    #
    # Markdownテンプレートをレンダリングして出力
    #
    # @param [String] template_name テンプレート名（拡張子なし）
    # @param [Hash] vars テンプレート変数
    #
    def render(template_name, vars = {})
      setup_logger if @logger.nil?

      template_path = File.join(__dir__, "markdown", "#{template_name}.md.erb")

      unless File.exist?(template_path)
        error("テンプレートが見つかりません: #{template_path}")
        return
      end

      erb = ERB.new(File.read(template_path), trim_mode: "-")
      markdown = erb.result_with_hash(vars)

      if @output_mode == MODE_FILE || !@tty_enabled
        # ファイル出力またはTTY無効時: プレーンテキスト
        plain = strip_markdown(markdown)
        @logger.info(plain)
      else
        # 標準出力モード: tty-markdownでレンダリング
        # 元のSTDOUTを使用（Narou::Loggerではなく実際のターミナル）
        # TTY::Screen.widthがNarou::Loggerにアクセスしないよう、明示的に幅を指定
        begin
          require "io/console"
          width = ORIGINAL_STDOUT.winsize[1]
        rescue StandardError
          width = 80 # デフォルト幅
        end

        ORIGINAL_STDOUT.puts TTY::Markdown.parse(markdown, width: width)
      end
    end

    #
    # スピナー付きで処理を実行
    #
    # @param [String] message スピナーメッセージ
    # @yield 実行する処理
    # @return 処理の戻り値
    #
    def with_spinner(message)
      setup_logger if @logger.nil?

      if @output_mode == MODE_FILE || !@tty_enabled
        # ファイル出力またはTTY無効時: ログ出力のみ
        @logger.info("#{message}...")
        result = yield
        @logger.info("#{message}...完了")
        result
      else
        # 標準出力モード: tty-spinnerを使用
        # 元のSTDOUTを使用（Narou::Loggerではなく実際のターミナル）
        spinner = TTY::Spinner.new("[:spinner] #{message}...", format: :dots, output: ORIGINAL_STDOUT)
        spinner.auto_spin
        begin
          result = yield
          spinner.success("(完了)")
          result
        rescue StandardError => e
          spinner.error("(エラー)")
          raise e
        end
      end
    end

    #
    # ボックス表示
    #
    # @param [String] title タイトル
    # @param [String] content 内容
    # @param [Symbol] style スタイル（:success, :error, :warning, :info）
    #
    def box(title, content, style: :info)
      setup_logger if @logger.nil?

      if @output_mode == MODE_FILE || !@tty_enabled
        # ファイル出力またはTTY無効時: プレーンテキスト
        @logger.info("=== #{title} ===")
        @logger.info(content)
        @logger.info("=" * (title.length + 8))
      else
        # 標準出力モード: tty-boxを使用
        # 元のSTDOUTを使用（Narou::Loggerではなく実際のターミナル）
        box_style = case style
                    when :success then { border: :thick, padding: 1, style: { fg: :green, border: { fg: :green } } }
                    when :error then { border: :thick, padding: 1, style: { fg: :red, border: { fg: :red } } }
                    when :warning then { border: :thick, padding: 1, style: { fg: :yellow, border: { fg: :yellow } } }
                    else { border: :thick, padding: 1, style: { fg: :cyan, border: { fg: :cyan } } }
                    end

        ORIGINAL_STDOUT.puts TTY::Box.frame(title: { top_left: " #{title} " }, **box_style) do
          content
        end
      end
    end

    #
    # 情報メッセージを出力
    #
    # @param [String] message メッセージ
    #
    def info(message)
      setup_logger if @logger.nil?

      if @output_mode == MODE_FILE || !@tty_enabled
        @logger.info(message)
      else
        ORIGINAL_STDOUT.puts @pastel.cyan(message)
      end
    end

    #
    # 成功メッセージを出力
    #
    # @param [String] message メッセージ
    #
    def success(message)
      setup_logger if @logger.nil?

      if @output_mode == MODE_FILE || !@tty_enabled
        @logger.info("✓ #{message}")
      else
        ORIGINAL_STDOUT.puts @pastel.green("✓ #{message}")
      end
    end

    #
    # 警告メッセージを出力
    #
    # @param [String] message メッセージ
    #
    def warning(message)
      setup_logger if @logger.nil?

      if @output_mode == MODE_FILE || !@tty_enabled
        @logger.warn(message)
      else
        ORIGINAL_STDOUT.puts @pastel.yellow("⚠ #{message}")
      end
    end

    #
    # エラーメッセージを出力
    #
    # @param [String] message メッセージ
    #
    def error(message)
      setup_logger if @logger.nil?

      if @output_mode == MODE_FILE || !@tty_enabled
        @logger.error(message)
        # ファイル出力時も重要なエラーは標準エラー出力に出す
        ORIGINAL_STDERR.puts "ERROR: #{message}" if @output_mode == MODE_FILE
      else
        ORIGINAL_STDOUT.puts @pastel.red("✗ #{message}")
      end
    end

    #
    # デバッグメッセージを出力
    #
    # @param [String] message メッセージ
    #
    def debug(message)
      setup_logger if @logger.nil?
      @logger.debug(message)
    end

    private

    #
    # Markdownマークアップを除去してプレーンテキストに変換
    #
    # @param [String] markdown Markdown文字列
    # @return [String] プレーンテキスト
    #
    def strip_markdown(markdown)
      markdown
        .gsub(/^#+\s*/, "") # 見出し
        .gsub(/\*\*([^*]+)\*\*/, '\1') # 太字
        .gsub(/\*([^*]+)\*/, '\1')     # 斜体
        .gsub(/`([^`]+)`/, '\1')       # インラインコード
        .gsub(/^>\s*/, "")             # 引用
        .gsub(/^-\s*/, "  • ")         # リスト
        .gsub(/^\d+\.\s*/, "  ")       # 番号付きリスト
        .gsub(/\[([^\]]+)\]\([^)]+\)/, '\1') # リンク
    end
  end
end
