# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

class ConverterBase
  module TextProcessor
    ROME_NUM_ALPHABET = %w(II III IV VI VII VIII IX ii iii iv vi vii viii ix)
    ROME_NUM = %w(Ⅱ Ⅲ Ⅳ Ⅵ Ⅶ Ⅷ Ⅸ ⅱ ⅲ ⅳ ⅵ ⅶ ⅷ ⅸ)

    #
    # ローマ数字っぽいアルファベットをローマ数字に変換
    #
    # ※alphabet_to_zenkaku の前に実行する必要あり
    #
    def convert_rome_numeric(data)
      ROME_NUM_ALPHABET.each_with_index do |rome, i|
        data.gsub!(/([^a-zA-Z])#{rome}([^a-zA-Z])/, "\\1#{ROME_NUM[i]}\\2")
      end
    end

    #
    # 濁点のついてない文字に濁点をつける表現を対応
    #
    # 濁点つきフォントに部分的に切り替える
    #
    def convert_dakuten_char_to_font(data)
      return unless @setting.enable_dakuten_font
      data.gsub!(/([ぁ-んァ-ヶι])[゛ﾞ]/) do
        @use_dakuten_font = true
        "［＃濁点］#{$1}［＃濁点終わり］"
      end
    end

    def convert_prolonged_sound_mark_to_dash(data)
      return unless @setting.enable_prolonged_sound_mark_to_dash
      data.gsub!(/(ー{2,})/) do |match|
        "―" * match.length
      end
    end

    #
    # 小説のルールに沿うように変換
    #
    def convert_novel_rule(data)
      # 括弧の閉じの直前の句点を消す
      data.gsub!(/。([」』）])/, "\\1")
      # 原則偶数個を１セットで使うべき文字を偶数個に補正
      # MEMO:（―も偶数個セットにするべきだが、記号的な意味で使われる場合もあるので無視）
      %w(… ‥).each do |target|
        data.gsub!(/#{target}+/) do |match|
          len = match.length
          len += 1 if len.odd?
          target * len
        end
      end
      # たまに見かける誤字対策
      data.gsub!(/。　/, "。")
    end

    def should_word_be_hankaku?(word)
      (word.length >= ENGLISH_SENTENCES_MIN_LENGTH || @setting.disable_alphabet_word_to_zenkaku) &&
        word.match(/[a-z]/i)
    end

    def sentence?(match)
      match.split(" ").size >= 2
    end

    #
    # 半角アルファベットを全角に変換する
    #
    # force : 強制的に全アルファベットを全角にするか？
    #         false の場合、英文章（半角スペースで区切られた2単語以上）を半角のままにする
    #         英文の定義： 1. 半角スペースで区切られた２単語以上の文章、
    #                      2. 一定以上の長さの一文字以上アルファベットを含む文章
    #
    def alphabet_to_zenkaku(data, force = false)
      if force
        data.gsub!(/[a-zA-Z]+/) do |match|
          match.tr("a-zA-Z", "ａ-ｚＡ-Ｚ")
        end
      else
        data.gsub!(ENGLISH_SENTENCES_CHARACTERS) do |match|
          if sentence?(match) || should_word_be_hankaku?(match)
            @english_sentences << match
            "［＃英文＝#{@english_sentences.size - 1}］"
          else
            match.tr("a-zA-Z", "ａ-ｚＡ-Ｚ")
          end
        end
      end
    end

    #
    # 英文を再構成する
    #
    def rebuild_english_sentences(data)
      @english_sentences.each_with_index do |sentence, id|
        data.sub!("［＃英文＝#{convert_numbers(id.to_s)}］", sentence)
      end
    end

    #
    # コメントブロックを検出する
    #
    # コメントブロックの定義は - のみが50回以上連続された行に囲まれている間
    #
    def comments_block?(line)
      if line =~ /^-{50,}$/
        @in_comment_block ^= 1
        return true
      end
      @in_comment_block
    end

    #
    # コメントブロックを削除する
    #
    def erase_comments_block(data)
      if @text_type == "textfile"
        data.gsub!(/^-{50,}\n.*?^-{50,}\n/m, "")
      end
      data
    end

    #
    # 全角数字(漢数字含む)を半角アラビア数字に
    #
    def zenkaku_num_to_hankaku_num(num)
      num.tr("０-９#{KANJI_NUM}", "0-90-9")
    end

    #
    # 半角アラビア数字の全角化
    #
    # 1桁、3桁以上：全角化
    # 2桁：縦中横化
    #
    def hankaku_num_to_zenkaku_num(data)
      data.gsub!(/\d+/) do |num|
        if num.length == 2
          tcy(num)
        elsif num.length == 3 && @text_type == "subtitle" && $`.empty?
          tcy(num)
        else
          num.tr("0-9", "０-９")
        end
      end
      data
    end
  end
end
