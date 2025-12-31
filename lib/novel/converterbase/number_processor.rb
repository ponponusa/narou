# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

class ConverterBase
  module NumberProcessor
    KANJI_NUM_UNITS = %w(万 億 兆 京).unshift("")
    KANJI_KURAI = %w(十 百 千).unshift("")
    KANJI_NUM_UNITS_DIGIT = {
      "十" => 1, "百" => 2, "千" => 3, "万" => 4, "億" => 8, "兆" => 12, "京" => 16
    }
    RECONVERT_KANJI_TO_NUM_PATTERN_UNIT = "％㎜㎝㎞㎎㎏㏄㎡㎥"

    #
    # 数字の変換
    #
    def convert_numbers(data)
      # 小数点を・に
      data.gsub!(/([\d０-９#{KANJI_NUM}]+?)[\.．]([\d０-９#{KANJI_NUM}]+?)/) do |match|
        integer = $1
        decimal = $2
        if [/\d/, /[０-９]/, /[#{KANJI_NUM}]/].any? { |r| integer[-1] =~ r && decimal[0] =~ r }
          "#{integer}・#{decimal}"
        else
          match
        end
      end
      if @setting.enable_convert_num_to_kanji &&
         @text_type != "subtitle" && @text_type != "chapter" && @text_type != "story"
        num_to_kanji(data)
      else
        hankaku_num_to_zenkaku_num(data)
      end
      data
    end

    #
    # アラビア数字を漢数字に
    #
    # カンマ区切りの数字はアラビア数字のままにしておく
    # もともと漢数字なのは他の変換を受けないように退避させておく
    #
    def num_to_kanji(data)
      stash_kanji_num(data)
      data.gsub!(/[\d０-９,，]+/) do |match|
        if match =~ /[,，]/
          if match =~ /\d/
            stash_hankaku_num_and_comma(match.tr("，", ","))
          else
            match
          end
        else
          zenkaku_num_to_kanji(match.tr("0-9", KANJI_NUM))
        end
      end
      data
    end

    def stash_hankaku_num_and_comma(num)
      @@num_and_comma_list_counter ||= 0
      @@num_and_comma_list_counter += 1
      @num_and_comma_list[@@num_and_comma_list_counter] = num
      "［＃半角数字＝#{@@num_and_comma_list_counter}］"
    end

    def rebuild_hankaku_num_and_comma(data)
      data.gsub!(/［＃半角数字＝(.+?)］/) do
        @num_and_comma_list[$1.to_i]
      end
    end

    def stash_kanji_num(data)
      data.gsub!(/[#{KANJI_NUM}十百千万億兆京]+/).with_index do |match, i|
        if "#{$`[-1]}#{$'[0]}" =~ /[\d０-９]/
          next match
        end
        @kanji_num_list[convert_numbers(i.to_s)] = match
        "［＃漢数字＝#{i}］"
      end
    end

    def rebuild_kanji_num(data)
      data.gsub!(/［＃漢数字＝(.+?)］/) do
        @kanji_num_list[$1]
      end
    end

    #
    # 全角アラビア数字を漢数字に
    #
    def zenkaku_num_to_kanji(str)
      str.tr("０-９", KANJI_NUM)
    end

    def __calc_sum_unit(units)
      units.each_char.inject(0) do |sum, c|
        sum + ("1" + "0" * KANJI_NUM_UNITS_DIGIT[c]).to_i
      end
    end

    def __calc_kanji_num_with_unit(string)
      total = 0
      string.scan(/([#{KANJI_NUM}]*)([十百千]*)/) do |num, units|
        break if num + units == ""
        num = "1" if num.empty?
        num_tr = num.tr(KANJI_NUM, "0-9")
        if units.empty?
          total += num_tr.to_i
        else
          total += (num_tr + __calc_sum_unit(units).to_s[1, 99]).to_i
        end
      end
      total
    end

    def kanji_num_to_integer(string)
      total = 0
      string.scan(/([#{KANJI_NUM}十百千]+)([万億兆京]*)/) do |num, units|
        total += (__calc_kanji_num_with_unit(num).to_s + units.each_char.map { |c| "0" * KANJI_NUM_UNITS_DIGIT[c] }.join).to_i
      end
      total
    end

    #
    # 漢数字を単位を使った表現に変換
    #
    # ８００万１０００ といったような表現は、内部一度で 8001000 に変換する。
    # lower_digit_zero はこの最後の 000 に適用される
    #
    def convert_kanji_num_with_unit(data, lower_digit_zero = 0)
      data.gsub!(/([#{KANJI_NUM}十百千万億兆京]+)/) do |match|
        total = kanji_num_to_integer($1)
        next match if total.to_s.length > KANJI_NUM_UNITS_DIGIT["京"] + 4
        m1 = total.to_s.tr("0-9", KANJI_NUM)
        if m1 =~ /〇{#{lower_digit_zero},}$/
          digits = m1.reverse.scan(/.{1,4}/).map(&:reverse).reverse # 下の桁から4桁ずつ区切った配列を作成
          keta = digits.size - 1
          digits.map.with_index { |nums, keta_i|
            four_digit_num = nums.scan(/./).map.with_index { |d, di|
              next "" if d == "〇"
              kurai = KANJI_KURAI[nums.length - di - 1]
              if d == "一"
                # 4桁の千の前は一は必須ではなく、5桁以上の場合の千の前には一をつける
                # 1100 → 千百、11100 → 一万一千百
                if kurai != "" && !(keta > 0 && kurai == "千")
                  d = ""
                end
              end
              d + kurai
            }.join
            if four_digit_num.length > 0
              four_digit_num + KANJI_NUM_UNITS[keta - keta_i]
            else
              ""
            end
          }.join
        else
          match
        end
      end
    end

    #
    # アラビア数字を使うべきところはアラビア数字に戻す
    #
    def exception_reconvert_kanji_to_num(data)
      return unless @setting.enable_convert_num_to_kanji
      data.gsub!(/([Ａ-Ｚａ-ｚ])([#{KANJI_NUM}・～]+)/) do # ｖｅｒ１・０１ のようなパターンも許容する
        $1 + $2.tr(KANJI_NUM, "０-９")
      end
      data.gsub!(/([#{KANJI_NUM}・～]+)([Ａ-Ｚａ-ｚ#{RECONVERT_KANJI_TO_NUM_PATTERN_UNIT}])/) do
        $1.tr(KANJI_NUM, "０-９") + $2
      end
    end

    #
    # 分数表記を○分の○表記に変更、及び日付表記を検出
    #
    # スラッシュで区切られた数字が２個なら分数、３個なら日付と定義
    #
    def convert_fraction_and_date(data)
      if !@setting.enable_transform_fraction && !@setting.enable_transform_date
        return
      end
      target_num = "\d０-９#{KANJI_NUM}十百千万億兆京垓"
      data.gsub!(%r{[#{target_num}/／]+}) do |match|
        numerics = match.split(%r{[/／]})
        case numerics.size
        when 2
          # 分数
          if @setting.enable_transform_fraction
            "#{zenkaku_num_to_kanji(numerics[1])}分の#{zenkaku_num_to_kanji(numerics[0])}"
          else
            match
          end
        when 3
          # 日付
          if @setting.enable_transform_date
            begin
              date = Date.new(*numerics.map { |s|
                s.tr!("0-9０-９#{KANJI_NUM}", "0-90-90-9")
                s.to_i
              })
            rescue ArgumentError
              match
            else
              convert_numbers(date.strftime(@setting.date_format))
            end
          end
        else
          match
        end
      end
    end
  end
end
