# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "fileutils"
require "lib/novel/downloader"
require "lib/novel/novelconverter"
require "lib/core/inventory"
require "lib/ebook/kindlestrip"
require "lib/utilities/worker"
require_relative "send"

module Command
  class Convert < CommandBase
    def self.oneline_help
      "小説を変換します。管理小説以外にテキストファイルも変換可能"
    end

    attr_accessor :device, :converted_txt_path

    @@sending_error_list = []

    def self.display_sending_error_list
      return unless exists_sending_error_list?
      $stdout2.puts <<~MSG
        #{"=" * 79}
        ・送信失敗リスト
        #{@@sending_error_list.join("\n")}

      MSG
      $stdout2.puts "<red><bold>上記のファイルの送信に失敗しました。</bold></red>".termcolor
      $stdout2.puts <<~MSG
        送信出来なかった原因を解消し、send コマンドを実行して下さい。
        #{"=" * 79}
      MSG
      @@sending_error_list.clear
    end

    def self.exists_sending_error_list?
      @@sending_error_list.present?
    end

    def initialize
      @argument_target_type = :file

      super("<target> [<target2> ...] [options]")
      @opt.separator <<-EOS

  ・指定した小説を縦書き用に整形及びEPUB、MOBIに変換します。
  ・変換したい小説のNコード、URL、タイトルもしくはIDを指定して下さい。
    IDは #{@opt.program_name} list を参照して下さい。
  ・一度に複数の小説を指定する場合は空白で区切って下さい。
  ※-oオプションがない場合、[著者名] 小説名.txtが小説の保存フォルダに出力されます
  ・管理小説以外にもテキストファイルを変換出来ます。
    テキストファイルのファイルパスを指定します。
  ※複数指定した場合に-oオプションがあった場合、ファイル名に連番がつきます。
  ・MOBI化する場合は narou-mod setting device=kindle をして下さい。
  ・device=kobo の場合、.kepub.epub を出力します。

  Examples:
    narou-mod convert n9669bk
    narou-mod convert http://ncode.syosetu.com/n9669bk/
    narou-mod convert 異世界迷宮で奴隷ハーレムを
    narou-mod convert 1 -o "ハーレム -変換済み-.txt"
    narou-mod convert mynovel.txt --enc sjis

  Options:
      EOS
      @opt.on("-o FILE", "--output FILE", "出力ファイル名を指定する。フォルダパス部分は無視される") { |filename|
        @options["output"] = filename
      }
      @opt.on("--make-zip", "i文庫用のzipファイルを作る") {
        @options["make-zip"] = true
      }
      @opt.on("-e ENCODING", "--enc ENCODING",
              "テキストファイル指定時の文字コードを指定する。デフォルトはUTF-8") { |encoding|
        encoding = "utf-8" if encoding =~ /UTF8/i
        @options["encoding"] = encoding
      }
      @opt.on("--no-epub", "AozoraEpub3でEPUB化しない") {
        @options["no-epub"] = true
      }
      @opt.on("--no-mobi", "kindlegenでMOBI化しない") {
        @options["no-mobi"] = true
      }
      @opt.on("--no-strip", "MOBIをstripしない") {
        @options["no-strip"] = true
      }
      @opt.on("--no-zip", "i文庫用のzipファイルを作らない") {
        @options["no-zip"] = true
      }
      @opt.on("--no-open", "出力時に保存フォルダを開かない") {
        @options["no-open"] = true
      }
      @opt.on("-i", "--inspect", "小説状態の調査結果を表示する") {
        @options["inspect"] = true
      }
      @opt.on("-v", "--verbose", "AozoraEpub3, kindlegen の標準出力を全て表示する") {
        @options["verbose"] = true
      }
      @opt.on("--ignore-default", "settingコマンドのdefault系設定を無視する") {
        @options["ignore-default"] = true
      }
      @opt.on("--ignore-force", "settingコマンドのforce系設定を無視する") {
        @options["ignore-force"] = true
      }
      @opt.separator <<-EOS

  Configuration:
  --make-zip, --no-epub, --no-mobi, --no-strip, --no-zip, --no-open , --inspect は narou-mod setting コマンドで恒常的な設定にすることが可能です。
    convert.copy-to を設定すれば変換したEPUB/MOBIを指定のフォルダに自動でコピー出来ます。
    device で設定した端末が接続されていた場合、対応するデータを自動送信します。
  詳しくは narou-mod setting --help を参照して下さい。
      EOS
    end

    def self.execute!(*argv, io: $stdout2, sync: false)
      if sync
        # cocurrency が有効だろうが必ず同期実行する
        status = super(*argv, io: io)
        yield if block_given?
        status
      else
        Narou.concurrency_call do
          status = super(*argv, io: io)
          yield if block_given?
          status
        end
      end
    end

    def execute(argv)
      super
      init(argv)
      main(argv)
    end

    def init(argv)
      display_help! if argv.empty?
      @output_filename = @options["output"]
      if @output_filename
        @ext = File.extname(@output_filename)
        @basename = File.basename(@output_filename, @ext)
      else
        @basename = nil
      end
      return unless @options["encoding"]
      @enc = Encoding.find(@options["encoding"]) rescue nil
      return if @enc
      $stdout2.error "--enc で指定された文字コードは存在しません。sjis, eucjp, utf-8 等を指定して下さい"
    end

    def main(argv)
      build_device_names.each do |name|
        @device = Narou.get_device(name)
        if name
          $stdout2.puts "<bold><magenta>&gt;&gt; #{@device.display_name}用に変換します</magenta></bold>".termcolor
        end
        self.extend(@device.get_hook_module) if @device
        hook_call(:change_settings)
        convert_novels(argv)
      end
      return unless @options["multi-device"]
      # device の設定に戻す
      device = Narou.get_device
      force_change_settings_function(device.get_relative_variables) if device
    end

    def build_device_names
      multi_device = @options["multi-device"]
      device_names = if multi_device
                       multi_device.split(",").map(&:strip).map(&:downcase).select do |name|
                         Device.exists?(name).tap do |this|
                           unless this
                             $stdout2.error "[convert.multi-device] #{name} は有効な端末名ではありません"
                           end
                         end
                       end
                     else
                       [nil] # nil で device 設定が読まれる
                     end
      # kindle用のmobiを作る過程でepubが作成され、上書きされてしまうので、最初に作るようにする
      kindle = device_names.delete("kindle")
      device_names.unshift(kindle) if kindle
      if multi_device && device_names.empty?
        $stdout2.error "有効な端末名がひとつもありませんでした"
        exit Narou::EXIT_ERROR_CODE
      end
      device_names
    end

    def change_settings
      return unless @device
      if @options["multi-device"]
        force_change_settings_function(@device.get_relative_variables)
      end
    end

    def convert_novels(argv)
      tagname_to_ids(argv)
      total_count = argv.length
      completed_count = 0

      $stdout2.puts "変換処理開始: #{total_count}件の小説を処理します"

      argv.each.with_index(1) do |target, index|
        $stdout2.puts "[#{index}/#{total_count}] 処理中: #{target}"
        Narou.lock(target) do
          convert_novel_main(target, index)
        end
        completed_count += 1
        $stdout2.puts "[#{index}/#{total_count}] 完了: #{target}"
      rescue => e
        if ENV["NAROU_ENV"] == "test"
          # テスト時は握りつぶさずに原因を見える化
          raise
        else
          $stdout2.error "[#{index}/#{total_count}] エラー: #{target} - #{e.message}"
          # 個別のエラーでは処理を継続
        end
      end

      $stdout2.puts "変換処理完了: #{completed_count}/#{total_count}件が正常に変換されました"
    rescue Interrupt
      $stdout2.puts "変換を中断しました (#{completed_count}/#{total_count}件完了)"
      exit Narou::EXIT_INTERRUPT
    end

    def convert_novel_main(target, index)
      @target = target
      @novel_data = nil

      Helper.print_horizontal_rule($stdout2) if index > 1
      if @basename
        @basename << " (#{index})" if argv.length > 1
        @output_filename = @basename + @ext
      end

      if File.file?(target.to_s)
        using_send_command = false
        # not remove output files for text file conversion
        res = convert_txt(target)
      else
        using_send_command = true
        unless Downloader.novel_exists?(target)
          $stdout2.error "#{target} は存在しません"
          return
        end
        # remove output files for novel conversion
        NovelConverter.extensions_of_converted_files(@device).each do |ext|
          ebook_paths = Narou.get_ebook_file_paths(target, ext)
          NovelConverter.clean_up_temp_files(ebook_paths)
        end
        # start novel conversion
        @argument_target_type = :novel
        res = NovelConverter.convert(target, {
                output_filename: @output_filename,
                display_inspector: @options["inspect"],
                ignore_force: @options["ignore-force"],
                ignore_default: @options["ignore-default"],
              })
        @novel_data = Downloader.get_data_by_target(target)
        @options["yokogaki"] = NovelSetting.load(target)["enable_yokogaki"]
      end
      return unless res
      array_of_converted_txt_path = res[:converted_txt_paths]
      ebook_file = nil
      array_of_converted_txt_path.each do |converted_txt_path|
        @converted_txt_path = converted_txt_path
        @use_dakuten_font = res[:use_dakuten_font]

        ebook_file = hook_call(:convert_txt_to_ebook_file)
        next if ebook_file.nil?
        if ebook_file
          copy_to_converted_file(ebook_file, io: stream_io)
          # ZIP専用のコピー先が設定されている場合、ZIPを追加コピー
          copy_to_converted_zip_file(ebook_file, io: stream_io)
          send_file_to_device(ebook_file) unless using_send_command
        end
      end
      send_file_to_device(ebook_file) if
        using_send_command && ebook_file

      if @options["no-open"].! && Narou.web?.!
        Helper.open_directory(File.dirname(@converted_txt_path), "小説の保存フォルダを開きますか")
      end
    end

    #
    # 直接指定されたテキストファイルを変換する
    #
    def convert_txt(target)
      NovelConverter.convert_file(target, {
               encoding: @enc,
               output_filename: @output_filename,
               display_inspector: @options["inspect"],
               ignore_force: @options["ignore-force"],
               ignore_default: @options["ignore-default"],
             })
    rescue ArgumentError => e
      if e.message =~ /invalid byte sequence in UTF-8/
        $stdout2.error "テキストファイルの文字コードがUTF-8ではありません。" \
                       "--enc オプションでテキストの文字コードを指定して下さい"
        warn "(#{e.message})"
        nil
      else
        raise
      end
    rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
      $stdout2.error <<~ERR
        #{target}:
        テキストファイルの文字コードは#{@options["encoding"]}ではありませんでした。
        正しい文字コードを指定して下さい
      ERR
      nil
    end

    #
    # 変換された整形済みテキストファイルをデバイスに対応した書籍データに変換する
    #
    def convert_txt_to_ebook_file
      # dc:subject埋め込み設定の確認とタグ情報の取得
      dc_subjects = nil
      if @options["add-dc-subject-to-epub"] && @novel_data && @novel_data["tags"]
        tags = @novel_data["tags"]
        if tags.is_a?(Array)
          # 除外タグの設定を取得
          exclude_tags_setting = @options["dc-subject-exclude-tags"]

          # 初回実行時にデフォルト値を設定
          if exclude_tags_setting.nil?
            exclude_tags_setting = "404,end"
            # 設定を保存
            local_settings = Inventory.load("local_setting")
            local_settings["convert.dc-subject-exclude-tags"] = exclude_tags_setting
            local_settings.save
          end

          excluded_tags = exclude_tags_setting.split(",").map(&:strip).reject(&:empty?)
          dc_subjects = tags.reject { |tag| excluded_tags.include?(tag) }.map(&:strip).reject(&:empty?)
        end
      end

      # EPUB生成（dc:subject 挿入を含む）
      # ZIPも生成する場合(cleanup_tempの影響を避けるため)は一旦txtのクリーンアップを抑止
      no_cleanup_txt = (@argument_target_type == :file) || @options["make-zip"]
      ebook_path = NovelConverter.convert_txt_to_ebook_file(@converted_txt_path, {
        use_dakuten_font: @use_dakuten_font,
        device: @device,
        verbose: @options["verbose"],
        no_epub: @options["no-epub"],
        no_mobi: @options["no-mobi"],
        no_strip: @options["no-strip"],
        no_cleanup_txt: no_cleanup_txt,
        yokogaki: @options["yokogaki"],
        dc_subjects: dc_subjects
      })
      # その他の処理 -> EPUBタグ挿入処理(有効時) -> ZIP作成処理(有効時)
      # ZIP作成はEPUB生成の成否に依存させない（TXTから生成するため）
      if @options["make-zip"] && !@options["no-zip"]
        begin
          zip_path = generate_ibunko_zip
          copy_to_converted_zip_file(zip_path, io: stream_io) if zip_path
        rescue => e
          $stdout2.error "ZIP生成に失敗しました: #{e.message}"
        end
      end
      ebook_path
    end

    #
    # i文庫用ZIP生成を明示的に実行する
    #
    def generate_ibunko_zip
      prev_device = @device
      ibunko_device = Narou.get_device("ibunko")
      # デバイス情報を一時的に差し替えてフック処理を使う
      @device = ibunko_device
      # 純青空テキストからのZIP生成（EPUB最適化要素を除去）
      if Device::Ibunko.method_defined?(:create_pure_aozora_zip, false)
        Device::Ibunko.instance_method(:create_pure_aozora_zip).bind(self).call
      else
        # フォールバック（互換性維持）
        Device::Ibunko.instance_method(:hook_convert_txt_to_ebook_file).bind(self).call { -> {} }
      end
    ensure
      @device = prev_device
    end

    class NoSuchDirectory < StandardError; end

    #
    # convert.copy-to で指定されたディレクトリに書籍データをコピーする
    #
    def copy_to_converted_file(src_path, io: nil)
      io ||= (respond_to?(:stream_io) ? stream_io : nil) || $stdout2
      copy_to_dir = get_copy_to_directory
      return nil unless copy_to_dir
      FileUtils.copy(src_path, copy_to_dir)
      copied_file_path = File.join(copy_to_dir, File.basename(src_path))
      $stdout2.puts copied_file_path.to_s.encode(Encoding::UTF_8) + " へコピーしました"
      copied_file_path
    rescue NoSuchDirectory => e
      io.error "#{e.message} はフォルダではないかすでに削除されています。コピー出来ませんでした"
      nil
    end

    #
    # 書籍ファイルのコピー先を取得
    #
    # copy-to が設定されていなければ nil を返す。
    # copy-to が存在しないディレクトリだった場合は例外を投げる
    #
    def get_copy_to_directory
      # 2.1.0 から convert.copy_to から convert.copy-to へ名称が変更された
      # (互換性維持のため、copy_to も使えるようにはしておく)
      copy_to_dir = @options["copy-to"] || @options["copy_to"]
      return nil unless copy_to_dir
      unless File.directory?(copy_to_dir)
        raise NoSuchDirectory, copy_to_dir
      end

      dirs = [copy_to_dir]
      gvalues = grouping_values
      if gvalues.device && @device
        dirs << @device.display_name
      end
      if gvalues.site && @novel_data
        dirs << @novel_data["sitename"]
      end
      copy_to_dir_with_groups = File.join(dirs)
      unless File.directory?(copy_to_dir_with_groups)
        FileUtils.mkdir_p(copy_to_dir_with_groups)
      end
      copy_to_dir_with_groups
    end
    private :get_copy_to_directory

    #
    # ZIPファイルを convert.copy-zip-to にコピーする
    #
    def copy_to_converted_zip_file(src_path, io: nil)
      io ||= (respond_to?(:stream_io) ? stream_io : nil) || $stdout2
      return nil unless File.extname(src_path).downcase == ".zip"
      copy_to_dir = @options["copy-zip-to"]
      return nil if copy_to_dir.nil? || copy_to_dir.to_s.empty?
      unless File.directory?(copy_to_dir)
        raise NoSuchDirectory, copy_to_dir
      end
      FileUtils.copy(src_path, copy_to_dir)
      copied_file_path = File.join(copy_to_dir, File.basename(src_path))
      $stdout2.puts copied_file_path.to_s.encode(Encoding::UTF_8) + " へZIPをコピーしました"
      copied_file_path
    rescue NoSuchDirectory => e
      io.error "#{e.message} はフォルダではないかすでに削除されています。ZIPをコピー出来ませんでした"
      nil
    end

    def grouping_values
      result = OpenStruct.new
      grouping = @options["copy-to-grouping"]
      if grouping.is_a?(TrueClass)
        # 後方互換維持用
        result.device = true
        return result
      end
      grouping.to_s.split(",").map(&:strip).each do |key|
        result[key] = true
      end
      result
    end

    def send_file_to_device(ebook_file, io: $stdout2)
      if @device && @device.physical_support? &&
        @device.connecting? && File.extname(ebook_file) == @device.ebook_file_ext
        if @argument_target_type == :novel
          if Send.execute!(@device.name, @target, io: io) > 0
            @@sending_error_list << ebook_file
          end
        else
          io.puts @device.name + "へ送信しています"
          copy_to_path = nil
          begin
            copy_to_path = @device.copy_to_documents(ebook_file)
          rescue Device::SendFailure
          end
          if copy_to_path
            $stdout2.puts copy_to_path.to_s.encode(Encoding::UTF_8) + " へコピーしました"
          else
            io.error "送信に失敗しました"
            @@sending_error_list << ebook_file
          end
        end
      end
    end
  end
end
