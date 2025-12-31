# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "lib/core/inventory"
require "lib/cli/commandbase"
require "lib/utilities/tty_helper"

module Command
  class Init < CommandBase
    OUTPUT_MODES = %w(verbose summary silent).freeze
    OUTPUT_MODE_PRIORITY = {
      verbose: 0,
      summary: 1,
      silent: 2
    }.freeze
    MESSAGE_PRIORITY = {
      verbose: 0,
      summary: 1,
      always: 2
    }.freeze

    def self.oneline_help
      if Narou.already_init?
        "AozoraEpub3 の再設定を行います"
      else
        "現在のフォルダを小説用に初期化します"
      end
    end

    def initialize
      super("[options]")
      @options["output_mode"] = "verbose"
      @summary_data = {}
      if Narou.already_init?
        opt_message(<<-MSG)
  ・AozoraEpub3 の再設定を行います。
        MSG
      else
        opt_message(<<-MSG)
  ・現在のフォルダを小説格納用フォルダとして初期化します。
  ・初期化されるまでは他のコマンドは使えません。
        MSG
      end
      @opt.on("-p", "--path FOLDER", "指定したフォルダの AozoraEpub3 を利用する") { |dirname|
        # no check here since global_setting is not loaded yet
        @options["aozora_dirname"] = dirname
      }
      @opt.on("-l", "--line-height SIZE", "行の高さを変更する(単位em)。オススメは1.8") do |line_height|
        @options["line_height"] = Helper.string_cast_to_type(line_height, :float)
      rescue Helper::InvalidVariableType => e
        error e.message
        exit Narou::EXIT_ERROR_CODE
      end
      @opt.on("--non-interactive", "対話なしで初期化を実行する (環境変数 NAROU_NONINTERACTIVE と同等)") do
        @options["non_interactive"] = true
      end
      @opt.on("--output-mode MODE", "出力レベルを指定する (verbose|summary|silent)") do |mode|
        normalized = mode.to_s.strip.downcase
        unless OUTPUT_MODES.include?(normalized)
          error "--output-mode は #{OUTPUT_MODES.join('/')} のいずれかを指定してください"
          exit Narou::EXIT_ERROR_CODE
        end
        @options["output_mode"] = normalized
      end
    end

    def opt_message(description)
      @opt.separator <<~MSG

        #{description}
          Examples:
            narou-mod init
            narou-mod init -p /opt/narou/aozora    # AozoraEpub3 のフォルダを直接指定
            narou-mod init -p :keep                # 設定済みと同じ場所を指定(既に初期化済の場合)

            # 行の高さの調整
            narou-mod init --line-height 1.8       # 行の高さを1.8emに設定(1.8文字分相当)
            # 行の高さなので、行間を1文字分あけたいという場合は 1+1 で 2 を指定する
            # (未設定のまま小説変換すると 1.6 で計算される)
            # 参考情報：Kindle Voyage で文字サイズ４番目の大きさの場合、
            #   1.6em : 1ページに15行
            #   1.8em : 1ページに13行
            # の表示行数になる

          # 入力を省略したい場合、-p と -l を両方指定してやる必要あり
          narou-mod init -p /path/to/aozora -l 1.8
          narou-mod init --non-interactive --output-mode summary -p /path/to/aozora -l 1.8

          Options:
      MSG
    end

    def execute(argv)
      super
      @summary_data = {}
      @output_mode = parse_output_mode(@options["output_mode"])
      if Narou.already_init?
        init_aozoraepub3(true)
        output_summary_results
      else
        Narou.init(silent: silent_mode?)
        output(:verbose, "-" * 30)
        init_aozoraepub3
        output_summary_results
        output(:summary, "初期化が完了しました！")
        output(:verbose, "現在のフォルダ下で各種コマンドが使用出来るようになりました。")
        output(:verbose, "まずは narou-mod help で簡単な説明を御覧ください。")
      end
    end

    def init_aozoraepub3(force = false)
      @global_setting = Inventory.load("global_setting", :global)
      current_dir = @global_setting["aozoraepub3dir"]
      current_line_height = @global_setting["line-height"]
      if !force && current_dir && @options["aozora_dirname"].nil? && @options["line_height"].nil?
        @summary_data[:used_existing] = true
        @summary_data[:aozora_dir] = current_dir
        @summary_data[:line_height] = current_line_height if current_line_height
        return
      end
      @summary_data[:used_existing] = false
      output(:summary, "<bold><green>AozoraEpub3の設定を行います</green></bold>".termcolor)
      unless current_dir
        output(:summary, "<bold><red>#{"!!!WARNING!!!".center(70)}</red></bold>".termcolor)
        output(:summary, "AozoraEpub3の構成ファイルを書き換えます。narou-mod コマンド用に別途新規インストールしておくことをオススメします")
      end

      path = nil
      if @options["aozora_dirname"]
        path = normalize_aozoraepub3_path(@options["aozora_dirname"])
        unless path
          output(:always, "<bold><green>指定されたフォルダにAozoraEpub3がありません。</green></bold>".termcolor)
          output(:always, "")
        end
      end

      aozora_path =
        if path
          path
        elsif non_interactive?
          @global_setting["aozoraepub3dir"]
        else
          ask_aozoraepub3_path
        end

      unless aozora_path
        @summary_data[:setup_skipped] = true
        output(:summary, "設定をスキップしました。あとで <bold><yellow>narou-mod init</yellow></bold> で再度設定出来ます".termcolor)
        return
      end

      line_height =
        @options["line_height"] || (non_interactive? ? Narou.line_height(default: 1.8) : ask_line_height)

      output(:verbose, "")
      rewrite_aozoraepub3_files(aozora_path, line_height)
      @global_setting["aozoraepub3dir"] = aozora_path
      @global_setting["line-height"] = line_height
      @global_setting.save
      @summary_data[:setup_skipped] = false
      @summary_data[:aozora_dir] = aozora_path
      @summary_data[:line_height] = line_height
      output(:summary, "<bold><green>AozoraEpub3の設定を終了しました</green></bold>".termcolor)
    end

    def rewrite_aozoraepub3_files(aozora_path, line_height)
      # chuki_tag.txt の書き換え
      custom_chuki_tag_path = File.join(Narou.preset_dir, "custom_chuki_tag.txt")
      chuki_tag_path = File.join(aozora_path, "chuki_tag.txt")
      custom_chuki_tag = File.read(custom_chuki_tag_path, mode: "r:BOM|UTF-8")
      chuki_tag = File.read(chuki_tag_path, mode: "r:BOM|UTF-8")
      embedded_mark = "### Narou.rb MOD embedded custom chuki ###"
      if chuki_tag =~ /#{embedded_mark}/
        chuki_tag.gsub!(/#{embedded_mark}.+#{embedded_mark}/m, custom_chuki_tag)
      else
        chuki_tag << "\n" + custom_chuki_tag
      end
      File.write(chuki_tag_path, chuki_tag)
      output(:verbose, "(次のファイルを書き換えました)")
      output(:verbose, chuki_tag_path)
      output(:verbose, "")
      # ファイルコピー
      src = ["AozoraEpub3.ini", "vertical_font.css"]
      dst = ["AozoraEpub3.ini", "template/OPS/css_custom/vertical_font.css"]
      output(:verbose, "(次のファイルをコピーor上書きしました)")
      src.size.times do |i|
        src_full_path = File.join(Narou.preset_dir, src[i])
        dst_full_path = File.join(aozora_path, dst[i])
        Helper.erb_copy(src_full_path, dst_full_path, binding)
        output(:verbose, dst_full_path)
      end
    end

    def ask_aozoraepub3_path
      # 非対話環境では入力を読まない
      return nil if non_interactive?
      $stdout.puts
      print "<bold><green>AozoraEpub3のあるフォルダを入力して下さい:</green></bold>\n(未入力でスキップ".termcolor
      if @global_setting["aozoraepub3dir"]
        $stdout.puts "、:keep で現在と同じ場所を指定)"
        print "(現在の場所:#{@global_setting["aozoraepub3dir"]}"
      end
      print ")\n>"
      while (input = $stdin.gets)
        break if input.strip! == ""
        checked_input = normalize_aozoraepub3_path(input)
        return checked_input if checked_input
        print "\n<bold><green>入力されたフォルダにAozoraEpub3がありません。" \
              "もう一度入力して下さい:</green></bold>\n&gt;".termcolor
      end
      nil
    end

    def ask_line_height
      # 非対話環境ではデフォルトを返す（安全側）
      return Narou.line_height(default: 1.8) if non_interactive?
      # 後方互換のために未設定時の line_height デフォルトは 1.6 だが、
      # オススメは 1.8 なので入力時のデフォルトは 1.8 にする
      line_height = Narou.line_height(default: 1.8)
      $stdout.puts
      $stdout.puts(<<~MSG.termcolor)
        <bold><green>行間の調整を行います。小説の行の高さを設定して下さい(単位 em):</green></bold>
        1em = 1文字分の高さ
        行の高さ＝1文字分の高さ＋行間の高さ
        オススメは 1.8
        1.6 で若干行間狭め。1.8 だと一般的な小説程度。2.0 くらいにするとかなりスカスカ
        (未入力で #{line_height} を採用)
      MSG
      print ">"
      while (input = $stdin.gets)
        break if input.strip! == ""
        begin
          line_height = Helper.string_cast_to_type(input, :float)
          break
        rescue Helper::InvalidVariableType => e
          error e.message
          print "<bold><green>もう一度入力して下さい:</green></bold>\n&gt;".termcolor
        end
      end
      line_height
    end

    def normalize_aozoraepub3_path(input)
      if Helper.os_windows?
        input.force_encoding(Encoding::Windows_31J).encode!(Encoding::UTF_8)
      end
      input.delete!("\"")
      path = File.expand_path(input)
      if input == ":keep"
        aozora_dir = @global_setting["aozoraepub3dir"]
        if aozora_dir && Narou.aozoraepub3_directory?(aozora_dir)
          return aozora_dir
        end
      elsif Narou.aozoraepub3_directory?(path)
        return path
      end
      nil
    end

    def parse_output_mode(value)
      symbol = value.to_s.strip.downcase
      symbol = "verbose" unless OUTPUT_MODES.include?(symbol)
      symbol.to_sym
    end

    def non_interactive?
      !!(@options["non_interactive"] || TTYHelper.non_interactive?)
    end

    def output_mode
      @output_mode ||= :verbose
    end

    def silent_mode?
      output_mode == :silent
    end

    def can_output?(level)
      return true if level == :always
      MESSAGE_PRIORITY[level] >= OUTPUT_MODE_PRIORITY[output_mode]
    end

    def output(level, message = nil)
      return unless can_output?(level)
      message = yield if block_given?
      return if message.nil?
      message.to_s.split(/\n/, -1).each do |line|
        $stdout.puts line
      end
    end

    def output_summary_results
      aozora_dir = @summary_data[:aozora_dir]
      line_height = @summary_data[:line_height]
      if @summary_data[:used_existing]
        output(:summary, "AozoraEpub3 の設定は既存の値 (#{aozora_dir || "未設定"}) を利用しました。")
      elsif @summary_data[:setup_skipped]
        output(:summary, "AozoraEpub3 の設定をスキップしました。")
      elsif aozora_dir
        output(:summary, "AozoraEpub3 フォルダ: #{aozora_dir}")
      end

      if line_height
        output(:summary, format("行の高さ: %.1f", line_height))
      end
    end

    def print_help(argv)
      topics = Array(argv).map(&:to_s).reject { |arg| arg.casecmp("help").zero? }
      buffer = String.new
      buffer << @opt.help
      buffer << <<~DETAIL.termcolor

        <bold><green>詳細ヘルプ:</green></bold>
          --non-interactive / 環境変数 NAROU_NONINTERACTIVE
            対話なしで初期化を完了します。AozoraEpub3 の場所と行の高さを必ず指定してください。

          --output-mode verbose|summary|silent
            verbose : 進行ログをすべて表示します。
            summary : 初期化結果だけを表示します。
            silent  : 標準出力へ一切出力しません。

          AozoraEpub3 の設定
            既存の設定を使いたい場合は --path :keep を指定してください。
            新しい場所を指定する場合は --path /path/to/AozoraEpub3 を使います。

          行の高さの変更
            --line-height で数値(em)を指定するとプリセットを上書きできます。

          組み合わせ例
            narou-mod init --non-interactive --output-mode summary \
              --path /opt/narou/AozoraEpub3 --line-height 1.8

      DETAIL
      unless topics.empty?
        buffer << <<~TOPIC.termcolor

          <bold><yellow>未対応のヘルプトピック:</yellow></bold> #{topics.join(", ")}
        TOPIC
      end
      emit_help_output(buffer)
    end
  end
end
