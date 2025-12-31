# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "lib/utilities/helper"
require "lib/ebook/kindlestrip"
require "lib/novel/novel_converter/font_manager"
require "lib/novel/novel_converter/output_helper"

begin
  require "zip"
rescue LoadError
  # rubyzipが利用できない場合のフラグ
  ZIP_UNAVAILABLE = true
end

class NovelConverter
  #
  # EPUB/MOBI電子書籍ファイル生成
  #
  module EbookBuilder
    module_function

    #
    # AozoraEpub3でEPUBファイル作成
    #
    # AozoraEpub3は.jarがあるところがカレントディレクトリじゃないとうまく動かない
    # MEMO:
    # 逆にカレントディレクトリにAozoraEpub3の必須ファイルを置いて手を加えることで、
    # テンプレート等の差し替えが容易になる
    #
    # 返り値：正常終了 :success、エラー終了 :error、AozoraEpub3が見つからなかった nil
    #
    def txt_to_epub(filename, dst_dir: nil, device: nil, verbose: false, yokogaki: false, use_dakuten_font: false, stream_io: $stdout2)
      abs_srcpath = File.expand_path(filename)
      src_dir = File.dirname(abs_srcpath)

      cover_option = ""
      # MEMO: 外部実行からだと -c FILENAME, -c 1 オプションはぬるぽが出て動かない
      cover_filename = OutputHelper.get_cover_filename(src_dir)
      if cover_filename
        cover_option = "-c 0" # 先頭の挿絵を表紙として利用
      end

      dst_option = ""
      if dst_dir
        dst_option = %!-dst "#{File.expand_path(dst_dir)}"!
      end

      ext_option = ""
      device_option = ""
      if device
        case device.name
        when "Kobo"
          ext_option = "-ext #{device.ebook_file_ext}"
        when "Kindle"
          device_option = "-device kindle"
        end
      end

      yokogaki_option = yokogaki ? "-hor" : ""

      pwd = Dir.pwd

      aozoraepub3_path = Narou.aozoraepub3_path
      unless aozoraepub3_path
        error "AozoraEpub3が見つからなかったのでEPUBが出力出来ませんでした。" \
              "narou initでAozoraEpub3の設定を行なって下さい"
        return nil
      end
      aozoraepub3_basename = File.basename(aozoraepub3_path)
      aozoraepub3_dir = File.dirname(aozoraepub3_path)

      java_encoding = "-Dfile.encoding=UTF-8" \
                      " -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8" \
                      " -Dsun.stdout.encoding=UTF-8 -Dsun.stderr.encoding=UTF-8"

      if Helper.os_cygwin?
        abs_srcpath = Helper.convert_to_windows_path(abs_srcpath)
      end
      Dir.chdir(aozoraepub3_dir)
      command = %!java #{java_encoding} -cp #{aozoraepub3_basename} AozoraEpub3 -enc UTF-8 -of #{device_option} ! +
                %!#{cover_option} #{dst_option} #{ext_option} #{yokogaki_option} "#{abs_srcpath}"!
      if Helper.os_windows?
        command = "cmd /c #{command}".encode(Encoding::Windows_31J)
      end
      FontManager.activate_dakuten_font_files if use_dakuten_font
      stream_io.print "AozoraEpub3でEPUBに変換しています"
      begin
        res = Helper::AsyncCommand.exec(command) do
          stream_io.print "."
        end
      ensure
        Dir.chdir(pwd)
        FontManager.inactivate_dakuten_font_files if use_dakuten_font
      end

      # AozoraEpub3はエラーだとしてもexitコードは0なので、
      # 失敗した場合はjavaが実行できない場合と確定できる
      unless res[2].success?
        stream_io.puts
        stream_io.puts res
        stream_io.error "JavaがインストールされていないかAozoraEpub3実行時にエラーが発生しました。EPUBを作成出来ませんでした"
        return :error
      end

      stdout_capture = res[0]

      # Javaの実行環境に由来するであろうエラー
      if stdout_capture =~ /Error occurred during initialization of VM/
        stream_io.puts
        stream_io.puts stdout_capture.strip
        stream_io.puts "-" * 70
        stream_io.error "Javaの実行エラーが発生しました。EPUBを作成出来ませんでした\n" \
                       "Hint: 複数のJava環境が混じっていると起きやすいエラーのようです"
        return :error
      end

      error_list = stdout_capture.scan(/^(?:\[ERROR\]|エラーが発生しました :).+$/)
      warn_list = stdout_capture.scan(/^\[WARN\].+$/)
      stdout_capture.scan(/^\[INFO\].+$/)

      if verbose
        stream_io.puts
        stream_io.puts "==== AozoraEpub3 stdout capture #{"=" * 47}"
        stream_io.puts stdout_capture.strip
        stream_io.puts "=" * 79
      end

      if !error_list.empty? || !warn_list.empty?
        unless verbose
          stream_io.puts
          stream_io.puts error_list, warn_list
        end
        # AozoraEpub3 のエラーにはEPUBが出力されないエラーとEPUBが出力されるエラーの2種類ある。
        # EPUBが出力される場合は「変換完了」という文字があるのでそれを検出する
        if !error_list.empty? && (stdout_capture !~ /^変換完了/)
          stream_io.error "AozoraEpub3実行中にエラーが発生したため、EPUBが出力出来ませんでした"
          return :error
        end
      end
      stream_io.puts "変換しました"
      :success
    end

    #
    # EPUBファイルのstandard.opfにdc:subjectを追加する
    #
    def add_dc_subject_to_epub(epub_path, subjects, stream_io: $stdout2)
      return :success if subjects.nil? || subjects.empty?
      if defined?(ZIP_UNAVAILABLE)
        stream_io.error "dc:subject埋め込み機能を使用するにはrubyzip gemが必要です"
        return :error
      end

      entries = {}
      begin
        # EPUBをメモリ上に展開
        Zip::File.open(epub_path) do |zip_file|
          zip_file.each do |entry|
            data = entry.get_input_stream.read
            # XMLファイルはUTF-8として扱う、それ以外はバイナリのまま保持
            data.force_encoding(Encoding::UTF_8) if entry.name.end_with?(".opf", ".html", ".xhtml", ".xml")
            entries[entry.name] = data
          end
        end

        # standard.opf 書き換え
        opf_name, opf_body = entries.find { |name, _| name.end_with?("standard.opf") }
        unless opf_name
          stream_io.error "standard.opfファイルが見つかりませんでした"
          return :error
        end

        content = opf_body.dup
        content.gsub!(%r{<dc:subject>.*?</dc:subject>\s*\n?\s*}m, "")
        dc_subject_lines = subjects.map(&:strip).reject(&:empty?).map { |s|
          esc = s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub("\"", "&quot;").gsub("'", "&apos;")
          "    <dc:subject>#{esc}</dc:subject>"
        }
        if dc_subject_lines.any?
          dc_subjects_xml = "#{dc_subject_lines.join("\n")}\n"
          content.sub!(%r{(\s*)</metadata>}, "\n#{dc_subjects_xml}\\1</metadata>")
        end
        entries[opf_name] = content

        # Windowsでのスレッド内ファイル操作対策: GCを強制実行してファイルハンドルを解放
        GC.start
        sleep 0.1

        # 再Zip化 (mimetypeは無圧縮で先頭)
        File.delete(epub_path)
        Zip::OutputStream.open(epub_path) do |zos|
          # mimetype必須
          unless entries["mimetype"]
            stream_io.error "mimetypeファイルが見つかりません"
            return :error
          end

          # 第1引数に名前、第4引数にZip::Entry::STORED を渡す
          zos.put_next_entry("mimetype", nil, nil, Zip::Entry::STORED)
          zos.write entries["mimetype"]

          entries.each do |name, body|
            next if name == "mimetype"
            zos.put_next_entry(name)
            zos.write body
          end
        end

        stream_io.puts "dc:subjectを追加しました: #{subjects.join(', ')}"
        :success
      rescue StandardError => e
        stream_io.error "dc:subject追加中にエラーが発生しました: #{e.class} - #{e.message}"
        :error
      end
    end

    #
    # EPUBファイルをkindlegenでMOBIへ
    # AozoraEpub3.jar と同じ場所に kindlegen が無ければ何もしない
    #
    # 返り値：正常終了 :success、エラー終了 :error、中断終了 :abort
    #
    def epub_to_mobi(epub_path, verbose = false, stream_io: $stdout2)
      kindlegen_path = Narou.kindlegen_path
      unless File.exist?(kindlegen_path)
        stream_io.error "kindlegenが見つかりませんでした。AozoraEpub3と同じフォルダにインストールして下さい"
        return :error
      end

      if Helper.os_cygwin?
        epub_path = Helper.convert_to_windows_path(epub_path)
      end
      command = +%!"#{kindlegen_path}" -locale ja "#{epub_path}"!
      if Helper.os_windows?
        command.encode!(Encoding::Windows_31J)
      end
      stream_io.print "kindlegen実行中"
      res = Helper::AsyncCommand.exec(command) do
        stream_io.print "."
      end
      stdout_capture, _, proccess_status = res
      stdout_capture.force_encoding(Encoding::UTF_8)

      if verbose
        stream_io.puts
        stream_io.puts "==== kindlegen stdout capture #{"=" * 49}"
        stream_io.puts stdout_capture.gsub("\n\n", "\n").strip
        stream_io.puts "=" * 79
      end

      if proccess_status.exited?
        if proccess_status.exitstatus == 2
          stream_io.puts
          stream_io.error "kindlegen実行中にエラーが発生したため、MOBIが出力出来ませんでした"
          if stdout_capture.scan(/(エラー\(.+?\):\w+?:.+)$/)
            stream_io.error $1
          end
          return :error
        end
      else
        stream_io.puts
        return :abort
      end
      stream_io.puts "変換しました"
      :success
    end

    #
    # 変換された整形済みテキストファイルをデバイスに対応した書籍データに変換する
    #
    def convert_txt_to_ebook_file(txt_path, options)
      options = {
        dst_dir: nil,
        device: nil,
        verbose: false,
        no_epub: false,
        no_mobi: false,
        no_strip: false,
        no_cleanup_txt: false,
        yokogaki: false,
        use_dakuten_font: false,
        stream_io: $stdout2
      }.merge(options)
      stream_io = options[:stream_io]

      device = options[:device]
      clean_up_file_list = []

      return false if options[:no_epub]
      clean_up_file_list << txt_path unless options[:no_cleanup_txt]
      # epub
      status = txt_to_epub(
        txt_path,
        dst_dir: options[:dst_dir], device: device,
        verbose: options[:verbose], yokogaki: options[:yokogaki],
        use_dakuten_font: options[:use_dakuten_font],
        stream_io: stream_io
      )
      return nil if status != :success
      epub_ext = if device&.kobo?
                   device.ebook_file_ext
                 else
                   ".epub"
                 end
      epub_path = txt_path.sub(/\.txt$/, epub_ext)

      # dc:subject埋め込み処理
      if options[:dc_subjects] && !options[:dc_subjects].empty?
        add_dc_subject_status = add_dc_subject_to_epub(
          epub_path, options[:dc_subjects], stream_io: stream_io
        )
        if add_dc_subject_status == :error
          stream_io.error "dc:subject埋め込み処理に失敗しましたが、変換を続行します"
        end
      end

      if !device || !device.kindle? || options[:no_mobi]
        stream_io.puts "#{File.basename(epub_path)} を出力しました"
        stream_io.puts "<bold><green>EPUBファイルを出力しました</green></bold>".termcolor
        return epub_path
      end

      clean_up_file_list << epub_path
      # mobi
      status = epub_to_mobi(epub_path, options[:verbose], stream_io: stream_io)
      return nil if status != :success
      mobi_path = epub_path.sub(/\.epub$/, device.ebook_file_ext)

      # strip
      unless options[:no_strip]
        stream_io.puts "kindlestrip実行中"
        begin
          SectionStripper.strip(mobi_path, nil, false)
        rescue StripException => e
          stream_io.error e.message
        end
      end
      stream_io.puts "#{File.basename(mobi_path).encode(Encoding::UTF_8)} を出力しました"
      stream_io.puts "<bold><green>MOBIファイルを出力しました</green></bold>".termcolor

      mobi_path
    ensure
      if Narou.economy?("cleanup_temp")
        # 作業用ファイルを削除
        OutputHelper.clean_up_temp_files(clean_up_file_list)
      end
    end
  end
end
