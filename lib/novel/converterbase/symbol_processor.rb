# frozen_string_literal: true

#
# Copyright 2025 whiteleaf. All rights reserved.
#

class ConverterBase
  module SymbolProcessor
    # ミニュート（ノノカギ）化する記号定義
    SINGLE_MINUTE_FAMILY = %!‘’'!
    DOUBLE_MINUTE_FAMILY = %!“”〝〟"!

    #
    # 特定の表現・記号を変換していく
    #
    def convert_special_characters(data)
      stash_kome(data)
      convert_double_angle_quotation_to_gaiji(data) # 最初からギュメなのはルビ対象外なので外字注記に
      symbols_to_zenkaku(data)
      convert_tatechuyoko(data)
      convert_novel_rule(data)
      convert_arrow(data)
      convert_head_half_spaces(data)
    end

    #
    # 半角カナと ｢｣｡､･ 等を全角に変換
    #
    def hankakukana_to_zenkakukana(data)
      data.replace(NKF.nkf("-wWX", data).tr("\u2014", "―"))
    end

    #
    # 半角記号を全角に変換
    #
    def symbols_to_zenkaku(data)
      # MEMO: シングルミニュートを表示出来るフォントはほとんど無いためダブルにする
      data.gsub!(/[#{SINGLE_MINUTE_FAMILY}]([^"\n]+?)[#{SINGLE_MINUTE_FAMILY}]/, "〝\\1〟")
      data.gsub!(/[#{DOUBLE_MINUTE_FAMILY}]([^"\n]+?)[#{DOUBLE_MINUTE_FAMILY}]/, "〝\\1〟")
      data.tr!("-=+/*《》'\"%$#&!?<>＜＞()|‐,._;:\[\]{}",
               "－＝＋／＊≪≫'〝％＄＃＆！？〈〉〈〉（）｜－，．＿；：［］｛｝")
      data.gsub!("\\", "￥")
      data
    end

    #
    # 縦中横注記取得
    #
    def tcy(str)
      "［＃縦中横］#{str}［＃縦中横終わり］"
    end

    #
    # 縦中横にすべき表現を変換
    #
    def convert_tatechuyoko(data)
      # 感嘆符及び疑問符の縦中横化
      # AozoraEPUB3の縦中横設定を使えば明示的に注記を使う必要はないが、
      # 見出しの中では自動で縦中横にはならないため、明示的指定をしておく
      # 事前に !? は全角にしておく
      data.gsub!(/！+/) do |match|
        if "#{$`[-1]}#{$'[0]}".include?("？")
          next match
        end
        len = match.length
        if len == 3
          tcy("!!!")
        elsif len >= 4
          # 4個以上なら偶数になるように調整（奇数だった場合増やす方向（+1））して2個ずつ縦中横
          len += 1 if len.odd?
          tcy("!!") * (len / 2)
        else
          match
        end
      end
      data.gsub!(/[！？]+/) do |match|
        case match.length
        when 2
          tcy(match.tr("！？", "!?"))
        when 3
          # 見た目的にこのパターンだけ縦中横化を許容する
          if %w(！！？ ？！！).find { |v| v == match }
            tcy(match.tr("！？", "!?"))
          else
            match
          end
        else
          match
        end
      end
    end

    #
    # おかしくなりやすい矢印文字の変換
    #
    def convert_arrow(data)
      # Kindle PW でしか確認してないのでとりあえず device=kindle の場合のみ変換
      if @device && @device.kindle?
        data.tr!("⇒⇐", "→←")
      end
    end

    #
    # 先に外字注記にしてしまうと border_symbol? 等で困るので、あとで外字注記化出来るようにする
    #
    def stash_kome(data)
      data.gsub!("※", "※※")
    end

    #
    # ギュメを二重山括弧（の外字）に変換
    #
    def convert_double_angle_quotation_to_gaiji(data)
      data.gsub!("≪", "※［＃始め二重山括弧］")
      data.gsub!("≫", "※［＃終わり二重山括弧］")
    end

    #
    # ※の外字注記化
    #
    # stash_kome で2つにしておいた※を外字注記化する
    #
    def rebuild_kome_to_gaiji(data)
      data.gsub!("※※", "※［＃米印、1-2-8］")
    end

    #
    # 間違えて行頭字下げに半角スペースを使ってるっぽいのを全角スペースにする
    #
    def convert_head_half_spaces(data)
      data.gsub!(/^ +/) do |match|
        # 半角スペースの数に応じて全角スペースの数も調整してみる
        "　" * (match.count(" ") / 2.0).ceil
      end
    end
  end
end
