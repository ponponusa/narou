# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "stringio"
require "date"
require "uri"
require "nkf"
require "pathname"
require "lib/core/narou"
require "lib/output/progressbar"
require "lib/output/inspector"
require "lib/novel/converterbase/utilities"
require "lib/novel/converterbase/ruby_processor"
require "lib/novel/converterbase/content_processor"
require "lib/novel/converterbase/heading_processor"
require "lib/novel/converterbase/indent_processor"
require "lib/novel/converterbase/bracket_processor"
require "lib/novel/converterbase/symbol_processor"
require "lib/novel/converterbase/number_processor"
require "lib/novel/converterbase/text_processor"

class ConverterBase
  include ConverterBase::Utilities
  include ConverterBase::RubyProcessor
  include ConverterBase::ContentProcessor
  include ConverterBase::HeadingProcessor
  include ConverterBase::IndentProcessor
  include ConverterBase::BracketProcessor
  include ConverterBase::SymbolProcessor
  include ConverterBase::NumberProcessor
  include ConverterBase::TextProcessor

  KANJI_NUM = "〇一二三四五六七八九"
  ENGLISH_SENTENCES_CHARACTERS = /[\w.,!?'" &:;-]+/
  ENGLISH_SENTENCES_MIN_LENGTH = 8 # この文字数以上アルファベットが続くと半角のまま

  attr_accessor :use_dakuten_font
  attr_accessor :output_text_dir, :subtitles, :data_type
  attr_accessor :current_index # 現在処理してる subtitles 内でのインデックス

  def before(io, text_type)
    data = io.string
    convert_page_break(data) if @text_type == "body" || @text_type == "textfile"
    if @text_type != "story" && @setting.enable_pack_blank_line
      data.gsub!("\n\n", "\n")
      data.gsub!(/(^\n){3}/m, "\n\n") # 改行のみの行３つを２つに削減
    end
    io
  end

  def after(io, text_type)
    io
  end

  def initialize(setting, inspector, illustration)
    @setting = setting
    @inspector = inspector
    @illustration = illustration
    @use_dakuten_font = false
    @output_text_dir = nil
    @subtitles = nil
    @data_type = "text"
    @current_index = 0
    @device = Narou.get_device
    reset_member_values
  end

  #
  # .convert が実行されるたびに呼ばれるメンバ変数リセット用メソッド
  # インスタンス作成時に一度だけ初期化したい場合は initialize で初期化する
  #
  def reset_member_values
    @request_insert_blank_next_line = false
    @request_skip_output_line = false
    @before_line = ""
    @delay_outputs_buffer = +""
    @in_comment_block = false
    @english_sentences = []
    @url_list = []
    @illust_chuki_list = []
    @kanji_num_list = {}
    @num_and_comma_list = {}
    @force_indent_special_chapter_list = {}
    @in_author_comment_block = nil
  end

  def outputs(data = "", force = false)
    if !@request_skip_output_line || force
      @write_fp.puts(data)
    end
  end

  def delay_outputs(data = "")
    unless @request_skip_output_line
      @delay_outputs_buffer << data + "\n"
    end
  end

  #
  # 特定の記号の直後は全角アキを挿入する
  #
  def insert_separate_space(data)
    data.gsub!(/([!?！？]+)([^!?！？])/) do
      m1 = $1
      m2 = $2
      m2 = "　" if m2 =~ /[ 、。]/
      if m2 =~ /[^」］｝\]\}』】〉》〕＞>≫)）"”’〟　☆★♪［―]/
        "#{m1}　#{m2}"
      else
        "#{m1}#{m2}"
      end
    end
  end

  #
  # 小説家になろう専用タグを置換
  #
  def replace_narou_tag(data)
    data.gsub!("【改ページ】", "")
    data.gsub!(/<KBR>/i, "\n")
    data.gsub!(/<PBR>/i, "\n")
  end

  def border_symbol?(line)
    @@symbols ||= File.read(Narou.preset_dir.join("bordersymbols.txt"), encoding: "BOM|UTF-8")
    line =~ /^[ 　\t]*[#{@@symbols}]+$/
  end

  def blank_line?(line)
    line =~ /\A[ 　\t]*$/
  end

  #
  # ■などの区切りの前後には空行が必ず存在するようにする
  #
  def insert_blank_line_to_border_symbol(line)
    result = +""
    if border_symbol?(line)
      unless blank_line?(@before_line)
        result << "\n"
      end
      @request_insert_blank_next_line = true
      jisage(line, 4)
    end
    line.sub!(/\A/, result)
  end

  #
  # 改ページある？
  #
  def page_break?(line)
    line =~ /［＃改ページ］/
  end

  #
  # 前書き・後書きの検出及び処理 ==============================
  #

  AUTHOR_INTRODUCTION_SPLITTER = /^　*[\*＊]{44}$/
  AUTHOR_POSTSCRIPT_SPLITTER = /^　*[\*＊]{48}$/
  AUTHOR_COMMENT_CHUKI = {
    introduction: {
      open: "［＃ここから前書き］", close: "［＃ここで前書き終わり］"
    },
    postscript: {
      open: "［＃ここから後書き］", close: "［＃ここで後書き終わり］"
    }
  }

  def process_author_comment(line)
    if @setting.enable_author_comments
      if @in_author_comment_block
        if leave_author_comment_block?(line)
          outputs(AUTHOR_COMMENT_CHUKI[@in_author_comment_block][:close])
          if @in_author_comment_block == :introduction
            @request_skip_output_line = true
            line.clear
            @in_author_comment_block = nil
          elsif @in_author_comment_block == :postscript
            @in_author_comment_block = nil
            # ［＃改ページ］（前書きの開始位置）を検出したため、
            # 改めて前書きの検出をする
            process_author_comment(line)
          end
        end
      else
        if inclusion_author_comment_block?(line)
          # outputs を使うと改ページより前に注記が入ってしまうため、
          # delay_outputs を使って出力を line 出力の後に遅らせる
          delay_outputs(AUTHOR_COMMENT_CHUKI[@in_author_comment_block][:open])
          if @in_author_comment_block == :postscript
            @request_skip_output_line = true
            line.clear
          end
        end
      end
    end
  end

  # 前書きの検出
  def find_introduction?
    pos = @read_fp.pos
    result = false
    @read_fp.each do |line|
      break if page_break?(line)
      if line =~ AUTHOR_INTRODUCTION_SPLITTER
        result = true
        break
      end
    end
    @read_fp.pos = pos
    result
  end

  def inclusion_author_comment_block?(line)
    result = false
    if page_break?(line)
      if find_introduction?
        @in_author_comment_block = :introduction
        result = true
      end
    elsif line =~ AUTHOR_POSTSCRIPT_SPLITTER
      @in_author_comment_block = :postscript
      result = true
    end
    result
  end

  def leave_author_comment_block?(line)
    result = false
    case @in_author_comment_block
    when :introduction
      if line =~ AUTHOR_INTRODUCTION_SPLITTER
        result = true
      end
    when :postscript
      if page_break?(line)
        result = true
      end
    end
    result
  end

  def author_comment_force_close
    if @in_author_comment_block
      outputs(AUTHOR_COMMENT_CHUKI[@in_author_comment_block][:close])
    end
  end

  # ==================================================

  #
  # 小説家になろうのルビ対策
  #
  def narou_ruby(data)
    if @text_type != "subtitle" && @text_type != "chapter"
      # 《》なルビの対処
      data.gsub!(/(.+?)≪([^≪]+?)≫/) do |match|
        to_ruby(match, $1, $2, ["≪", "≫"])
      end
      if @data_type == "text"
        # （）なルビの対処
        data.gsub!(/(.+?)（#{AUTO_RUBY_CHARACTERS}）/) do |match|
          to_ruby(match, $1, $2, ["（", "）"])
        end
      end
    end
    data.replace(replace_tatesen(data))
    data.gsub!("［＃ルビ用縦線］", "｜")
  end

  #
  # 一定以上の連続する空行を改ページに変換
  #
  def convert_page_break(data)
    if @setting.enable_convert_page_break
      threshold = @setting.to_page_break_threshold
      # `改ページ' を使うと見出し付与等で混乱するので自動生成したものは区別する
      data.gsub!(/(^\n){#{threshold},}/, "［＃改頁］\n")
    end
  end

  #
  # 表示上化けてしまうゴミ削除
  #
  def delete_dust_char(data)
    data.gsub!("︎", "")
  end

  #
  # 小説データ全体に対して施す変換
  #
  def convert_for_all_data(data)
    hankakukana_to_zenkakukana(data)
    auto_join_in_brackets(data)
    auto_join_line(data) if @setting.enable_auto_join_line
    erase_comments_block(data)
    replace_illust_tag(data)
    replace_url(data)
    replace_narou_tag(data)
    convert_rome_numeric(data)
    alphabet_to_zenkaku(data, @setting.enable_alphabet_force_zenkaku)
    force_indent_special_chapter(data)
    convert_numbers(data)
    exception_reconvert_kanji_to_num(data)
    if @setting.enable_convert_num_to_kanji && @text_type != "subtitle" && @text_type != "chapter" \
       && @setting.enable_kanji_num_with_units
      convert_kanji_num_with_unit(data, @setting.kanji_num_with_units_lower_digit_zero)
    end
    rebuild_kanji_num(data)
    insert_separate_space(data)
    convert_special_characters(data)
    convert_fraction_and_date(data)
    modify_kana_ni_to_kanji_ni(data)
    convert_dakuten_char_to_font(data)
    convert_prolonged_sound_mark_to_dash(data)
  end

  def before_convert(io)
    before(io, @text_type)
  end

  def after_convert(io)
    after(io, @text_type)
  end

  WORD_SEPARATOR = "［＃zws］" # zws = zero width space

  # 端末名を小文字で返す（@device を最優先。無ければ Narou.get_device）
  def current_device_name_for_gate
    dev =
      if instance_variable_defined?(:@device) && (d = instance_variable_get(:@device))
        d
      else
        begin
          Narou.get_device
        rescue
          nil
        end
      end
    name = dev.respond_to?(:name) ? dev.name : nil
    name.to_s.downcase.presence
  end

  #
  # Kindle端末で単語選択がしやすいように０幅スペースを挿入する
  #
  def insert_separator_for_selection(str = nil)
    # body / textfile / 以外は素通し
    return str unless @text_type == "body" || @text_type == "textfile"
    # nilガード
    return "" if str.nil?

    # Device gating: Kindle 以外では ZWS を入れない
    # 端末が明示されている場合のみゲートする
    dev_name = current_device_name_for_gate
    if dev_name
      # Kindle 以外なら挿入せず素通し
      return str unless dev_name == "kindle"
      # Kindle ならこの先の本体ロジックへ（ZWS 挿入）
    end
    # 端末が不明（nil）の場合は従来どおり ZWS を挿入

    # 設定値を確認（true/false を区別できるようにそのまま保持）
    word_on = @setting && @setting.respond_to?(:enable_insert_word_separator) ?
                @setting.enable_insert_word_separator : nil
    char_on = @setting && @setting.respond_to?(:enable_insert_char_separator) ?
                @setting.enable_insert_char_separator : nil

    # 優先順位:
    #  1) 小説設定で明示 ON → 端末に関係なく従う
    #  2) 未設定（nil/false の両方を未指定扱いにしたい場合は nil 判定に変えてもOK）
    #  3) それ以外 → 何もしない
    mode =
      if word_on
        :word
      elsif char_on
        :char
      else
        :none
      end

    case mode
    when :word then insert_word_separator(str)
    when :char then insert_char_separator(str)
    else str
    end
  end

  #
  # 単語単位でzwsを挿入する
  #
  def insert_word_separator(str)
    buffer = +""
    ss = StringScanner.new(str)
    before_symbol = false

    if @text_type == "textfile"
      buffer << ss.scan(/(.+\n){2}/)
    end

    while char = ss.getch
      symbol = false
      case char
      when "｜"
        ss.scan(/.+?》/)
      when "［"
        buffer << char
        if ss.scan(/^＃.+?］/)
          buffer << "#{ss.matched}"
        else
          before_symbol = false
        end
        next
      when "<"
        if ss.scan(/.+?>/)
          buffer << "<#{ss.matched}"
          next
        end
        symbol = true
      when /[\d０-９]/
        ss.scan(/[\d０-９]+/)
      when /[ぁ-んゝゞ]/
        ss.scan(/[ぁ-んゝゞー]+/)
      when /[ァ-ヶ]/
        ss.scan(/[ァ-ヶー・]+/)
      when /[Ａ-Ｚａ-ｚA-Za-z]/
        ss.scan(/[Ａ-Ｚａ-ｚA-Za-z ]+/)
      when /[一-龥朗-鶴]/
        ss.scan(/[一-龥朗-鶴]+/)
      when /[〔「『\(（【〈《≪〝]/
        buffer << char
        before_symbol = false
        next
      else
        symbol = true
      end
      if before_symbol && !symbol
        buffer << WORD_SEPARATOR
      end
      buffer << char
      unless symbol
        buffer << ss.matched if ss.matched?
        buffer << WORD_SEPARATOR
      end
      before_symbol = symbol
    end
    buffer
  end

  #
  # 文字単位でzwsを挿入する
  #
  def insert_char_separator(str)
    buffer = +""
    ss = StringScanner.new(str)
    before_symbol = false
    while char = ss.getch
      symbol = false
      case char
      when "｜"
        buffer << char
        if ss.scan(/.+?》/)
          buffer << "#{ss.matched}"
        else
          before_symbol = false
        end
        next
      when "［"
        buffer << char
        if ss.scan(/^＃.+?］/)
          buffer << "#{ss.matched}"
        else
          before_symbol = false
        end
        next
      when "<"
        if ss.scan(/.+?>/)
          buffer << "<#{ss.matched}"
          next
        end
        symbol = true
      when /[〔「『\(（【〈《≪〝]/
        buffer << char
        before_symbol = false
        next
      when /[―…!?！？※]/
        symbol = true
      end
      if before_symbol && !symbol
        buffer << WORD_SEPARATOR
      end
      buffer << char
      unless symbol
        buffer << WORD_SEPARATOR
      end
      before_symbol = symbol
    end
    buffer
  end

  def convert(text, text_type)
    return "" if text == ""
    output_text_dir = @output_text_dir || @setting.archive_path
    @text_type = text_type
    text.force_encoding(Encoding::UTF_8)
    io = StringIO.new(rstrip_all_lines(text))
    (io = before_convert(io)).rewind
    (io = convert_main(io)).rewind
    (io = after_convert(io)).rewind
    data = replace_by_replace_txt(io.read)
    data = insert_separator_for_selection(data)
    data
  end

  # 複数のテキストをまとめて変換する
  # pairs: { key1 => [text, text_type], key2 => [text, text_type], ... }
  # 戻り値: { key1 => converted_text1, key2 => converted_text2, ... }
  def convert_multi(pairs)
    results = {}
    pairs.each do |key, (text, text_type)|
      results[key] = convert(text, text_type)
    end
    results
  end

  #
  # 変換処理本体
  #
  # @text_type: 渡されるテキストの種類。
  #             subtitle, introduction, body, postscript, textfile, chapter, story
  #
  def convert_main(io)
    @write_fp = StringIO.new
    case @text_type
    when "introduction"
      return @write_fp if @setting.enable_erase_introduction
    when "postscript"
      return @write_fp if @setting.enable_erase_postscript
    end
    title_and_author = nil
    if @text_type == "textfile"
      # タイトル・著者名スキップ
      title_and_author = io.gets + io.gets
      data = io.read
    else
      data = io.read
    end
    reset_member_values
    convert_for_all_data(data)
    progressbar = nil
    if @text_type == "textfile"
      # convert_for_all_data -> replace_narou_tag
      # で改行化を行わないと正確な改行数は分からない
      progressbar = ProgressBar.new(data.count("\n") + 1)
      progressbar.output(0)
    end
    @read_fp = StringIO.new(data)
    if @text_type == "subtitle"
      @write_fp.write(data)
    else
      @read_fp.each_with_index do |line, i|
        progressbar.output(i) if progressbar && (i % 50).zero? # 50行ごとに制限
        @request_skip_output_line = false
        zenkaku_rstrip(line)
        if @request_insert_blank_next_line
          outputs unless blank_line?(line)
          @request_insert_blank_next_line = false
          @before_line = ""
        end
        process_author_comment(line) if @text_type == "textfile"
        insert_blank_before_line_and_behind_to_special_chapter(line)
        insert_blank_line_to_border_symbol(line)

        outputs(line)
        unless @delay_outputs_buffer.empty?
          @write_fp.write(@delay_outputs_buffer)
          @before_line = @delay_outputs_buffer
          @delay_outputs_buffer.clear
        else
          @before_line = line
        end
      end
      author_comment_force_close if @text_type == "textfile"
    end

    @write_fp.rewind
    data = @write_fp.string
    if @text_type == "textfile"
      if @setting.enable_author_comments
        erase_introduction(data) if @setting.enable_erase_introduction
        erase_postscript(data) if @setting.enable_erase_postscript
      end
      if @setting.enable_enchant_midashi
        enchant_midashi(data)
      end
    end
    rebuild_illust(data)
    rebuild_url(data)
    rebuild_english_sentences(data)
    rebuild_hankaku_num_and_comma(data)
    rebuild_kome_to_gaiji(data)
    if @text_type == "body" || @text_type == "textfile"
      half_indent_bracket(data)
      auto_indent(data)
    end
    rebuild_force_indent_special_chapter(data)
    # 再構築された文章にルビがふられる可能性を考慮して、
    # この位置でルビの処理を行う
    narou_ruby(data) if @setting.enable_ruby
    # 三点リーダーの変換は、ルビで圏点として・・・を使っている場合を考慮して、ルビ処理後にする
    convert_horizontal_ellipsis(data)
    # ルビ化されなくて残ったギュメを二重山括弧（の外字）に変換
    convert_double_angle_quotation_to_gaiji(data)
    delete_dust_char(data)
    if title_and_author
      data.replace(title_and_author + data)
    end
    data.rstrip!
    @write_fp
  ensure
    if @text_type == "textfile" && progressbar
      progressbar.clear
    end
  end

  #
  # replace.txt により単純置換
  #
  def replace_by_replace_txt(text)
    result = text.dup
    (@setting.replace_pattern + Narou.global_replace_pattern).each do |pattern|
      src, dst = pattern
      result.gsub!(src, dst)
    end
    result
  end
end
