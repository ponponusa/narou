# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "fileutils"
require "stringio"

begin
  require "rexml/document"
rescue LoadError
  # rexmlが利用できない場合のフラグ
  REXML_UNAVAILABLE = true
end
require "lib/novel/novelsetting"
require "lib/output/inspector"
require "lib/conversion/illustration"
require "lib/loading/loadconverter"
require "lib/novel/downloader"
require "lib/conversion/template"
require "lib/output/progressbar"
require "lib/utilities/helper"
require "lib/core/inventory"
require "lib/conversion/html"
require "lib/utilities/eventable"
require "lib/core/database"
require "lib/novel/novel_converter/font_manager"
require "lib/novel/novel_converter/ebook_builder"
require "lib/novel/novel_converter/output_helper"
require "lib/novel/novel_converter/title_decorator"
require "lib/novel/novel_converter/text_processor"

class NovelConverter
  include Narou::Eventable
  include TitleDecorator
  include TextProcessor

  NOVEL_TEXT_TEMPLATE_NAME = "novel.txt"
  NOVEL_TEXT_TEMPLATE_NAME_FOR_IBUNKO = "ibunko_novel.txt"

  attr_reader :use_dakuten_font, :stream_io

  def self.extensions_of_converted_files(device)
    exts = [".txt"]
    if device&.kobo?
      exts.push(device.ebook_file_ext)
    else
      exts.push(".epub", device&.ebook_file_ext)
    end
    exts.compact
  end

  #
  # 指定の小説を整形・変換する
  #
  def self.convert(target, options = {})
    options = {
      # default paraeters
      output_filename: nil, display_inspector: false,
      ignore_force: false, ignore_default: false
    }.merge(options)
    setting = NovelSetting.load(target, options[:ignore_force], options[:ignore_default])
    if setting
      novel_converter = new(setting, options[:output_filename], options[:display_inspector])
      return {
        converted_txt_paths: novel_converter.convert_main,
        use_dakuten_font: novel_converter.use_dakuten_font
      }
    end
    nil
  end

  #
  # テキストファイルを整形・変換する
  #
  def self.convert_file(filename, options = {})
    options = {
      # default parameters
      encoding: nil, output_filename: nil, display_inspector: false,
      ignore_force: false, ignore_default: false
    }.merge(options)
    output_filename = options[:output_filename]
    archive_path = if output_filename
                     "#{File.dirname(output_filename)}/"
                   else
                     "#{File.dirname(filename)}/"
                   end
    setting = NovelSetting.create(archive_path, options[:ignore_force], options[:ignore_default])
    setting.author = ""
    setting.title = File.basename(filename)
    novel_converter = new(setting, output_filename, options[:display_inspector])
    text = File.open(filename, "r:BOM|UTF-8", &:read).gsub("\r", "")
    if options[:encoding]
      text.force_encoding(options[:encoding]).encode!(Encoding::UTF_8)
    end
    {
      converted_txt_paths: novel_converter.convert_main(text),
      use_dakuten_font: novel_converter.use_dakuten_font
    }
  end

  # FontManagerへの委譲
  def self.activate_dakuten_font_files
    FontManager.activate_dakuten_font_files
  end

  def self.inactivate_dakuten_font_files
    FontManager.inactivate_dakuten_font_files
  end

  # EbookBuilderへの委譲
  def self.txt_to_epub(*, **)
    EbookBuilder.txt_to_epub(*, **)
  end

  def self.add_dc_subject_to_epub(*, **)
    EbookBuilder.add_dc_subject_to_epub(*, **)
  end

  def self.epub_to_mobi(*, **)
    EbookBuilder.epub_to_mobi(*, **)
  end

  def self.convert_txt_to_ebook_file(*, **)
    EbookBuilder.convert_txt_to_ebook_file(*, **)
  end

  # OutputHelperへの委譲
  def self.clean_up_temp_files(path_list)
    OutputHelper.clean_up_temp_files(path_list)
  end

  def self.get_cover_filename(archive_path)
    OutputHelper.get_cover_filename(archive_path)
  end

  def initialize(setting, output_filename = nil, display_inspector = false, output_text_dir = nil, stream_io: $stdout2)
    @setting = setting
    @novel_id = setting.id
    @novel_author = setting.novel_author.empty? ? setting.author : setting.novel_author
    @novel_title = setting.novel_title.empty? ? setting.title : setting.novel_title
    @output_filename = output_filename || setting.output_filename
    @output_filename = nil if @output_filename.empty?
    @inspector = Inspector.new(@setting)
    @illustration = Illustration.new(@setting, @inspector)
    @display_inspector = display_inspector
    @use_dakuten_font = false
    @converter = create_converter
    @converter.output_text_dir = output_text_dir
    @data = @novel_id ? Database.instance.get_data("id", @novel_id) : {}
    @stream_io = stream_io
  end

  #
  # メモリリーク回避のための明示的なクリーンアップ
  #
  def cleanup
    # 循環参照を切断（settingは最後まで必要）
    @inspector&.cleanup if @inspector.respond_to?(:cleanup)
    @illustration&.cleanup if @illustration.respond_to?(:cleanup)
    @converter&.cleanup if @converter.respond_to?(:cleanup)

    # 重いオブジェクトのみ解放
    @inspector = nil
    @illustration = nil
    @converter = nil
    @data = nil
    # @settingは最後まで必要なので解放しない
  end

  #
  # 小説のタグ情報をdc:subject用の配列として取得
  #
  def get_dc_subjects_from_tags(exclude_tags_setting = "404,end")
    return [] unless @data && @data["tags"]
    tags = @data["tags"]
    return [] unless tags.is_a?(Array)

    # 除外タグの設定を解析
    excluded_tags = exclude_tags_setting.split(",").map(&:strip).reject(&:empty?)
    tags.reject { |tag| excluded_tags.include?(tag) }.map(&:strip).reject(&:empty?)
  end

  #
  # 変換処理メインループ
  #
  def convert_main(text = nil)
    display_header
    initialize_event

    if text
      array_of_converted_text = convert_main_for_text(text)
    else
      array_of_converted_text = convert_main_for_novel
      update_latest_convert_novel
    end
    inspect_novel(array_of_converted_text)

    array_of_output_path = []
    array_of_converted_text.each_with_index do |converted_text, i|
      output_path = create_output_path(text, converted_text, i + 1)
      File.write(output_path, converted_text)
      array_of_output_path.push(output_path)
    end

    display_footer

    array_of_output_path
  ensure
    # 変換完了後にリソースを解放（ensureで確実に実行）
    cleanup
  end

  def initialize_event
    progressbar = nil

    on(:"convert_main.init") do |subtitles|
      progressbar = ProgressBar.new(subtitles.size, io: stream_io)
    end

    on(:"convert_main.loop") do |i|
      # 毎回ではな10件ごとに絞る
      progressbar.output(i) if progressbar && (i % 10).zero?
    end

    on(:"convert_main.finish") do
      progressbar&.clear
    end
  end

  def display_header
    stream_io.print "ID:#{@novel_id}　" if @novel_id
    stream_io.puts "#{@novel_title} の変換を開始"
  end

  def display_footer
    stream_io.puts "縦書用の変換が終了しました"
  end

  #
  # 表紙用挿絵注記作成
  #
  def create_cover_chuki
    cover_filename = self.class.get_cover_filename(@setting.archive_path)
    if cover_filename
      "［＃挿絵（#{cover_filename}）入る］"
    else
      ""
    end
  end

  #
  # 各小説用の converter.rb 変換オブジェクトを生成
  #
  def create_converter
    load_converter(@setting.archive_path).new(@setting, @inspector, @illustration)
  end

  #
  # 最終的に出力するパスを生成
  #
  def create_output_path(is_text_file_mode, converted_text, index)
    output_path = +""
    if @output_filename
      output_path = File.join(@setting.archive_path, File.basename(@output_filename))
    else
      if is_text_file_mode
        info = get_title_and_author_by_text(converted_text)
        info["ncode"] = info["title"]
        info["domain"] = "text"
      else
        info = {
          "id" => @novel_id,
          "author" => @novel_author, "title" => @novel_title
        }
      end
      filename = Narou.create_novel_filename(info)
      output_path = File.join(@setting.archive_path, filename)
    end
    if output_path !~ /\.\w+$/
      output_path += ".txt"
    end
    # change output_path to "basename_#{index}.ext" if index is greater than 1
    if index > 1
      ext = File.extname(output_path)
      output_path = File.join(File.dirname(output_path), File.basename(output_path, ext))
      output_path += "_#{index}#{ext}"
    end
    output_path
  end

  def inspect_novel(array_of_text)
    if @setting.enable_inspect
      array_of_text.each do |text|
        @inspector.inspect_end_touten_conditions(text)   # 行末読点の現在状況を調査する
        @inspector.countup_return_in_brackets(text)      # カギ括弧内の改行状況を調査する
      end
    end

    if !@display_inspector
      unless @inspector.empty?
        @inspector.display_summary(stream_io)
      end
    else
      # 小説の監視・検査状況を表示する
      if @inspector.error? || @inspector.warning?
        stream_io.puts "<bold><yellow>―――― 小説にエラーもしくは警告が存在します ――――</yellow></bold>".termcolor
        stream_io.puts
        @inspector.display(Inspector::ERROR | Inspector::WARNING)
        stream_io.puts
      end
      if @inspector.info?
        stream_io.puts "<bold><yellow>―――― 小説の検査状況を表示します ――――</yellow></bold>".termcolor
        stream_io.puts
        @inspector.display(Inspector::INFO)
        stream_io.puts
      end
    end

    @inspector.save
  end

  #
  # 最近変換した小説IDを記録更新
  #
  def update_latest_convert_novel
    id = Downloader.get_id_by_target(@novel_title)
    Inventory.load("latest_convert").tap { |inv|
      inv["id"] = id
      inv.save
    }
  end
end
