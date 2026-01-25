# frozen_string_literal: true

#
# ConverterBase ruby processing methods
#

class ConverterBase
  module RubyProcessor
    CHARACTER_OF_RUBY = "一-龠Ａ-Ｚａ-ｚA-Za-z"
    AUTO_RUBY_CHARACTERS = "([ぁ-んァ-ヶーゝゞ・ 　]{,20})"

    def object_of_ruby?(char)
      char =~ /[#{CHARACTER_OF_RUBY}]/
    end

    def is_sesame?(str, ten, last_char)
      ten =~ /^[・、]+$/ && (str.include?("｜") || object_of_ruby?(last_char))
    end

    def sesame(str)
      if str.include?("｜")
        str.sub("｜", "［＃傍点］") + "［＃傍点終わり］"
      else
        str.sub(/([#{CHARACTER_OF_RUBY}　]+)$/) {
          match_target = $1
          if match_target =~ /^(　+)/
            "#{$1}［＃傍点］#{match_target[$1.length..-1]}"
          else
            "［＃傍点］#{match_target}"
          end
        } + "［＃傍点終わり］"
      end
    end

    def replace_tatesen(str)
      str.gsub("｜", "※［＃縦線］")
    end

    def to_ruby(match, m1, m2, openclose_symbols)
      last_char = m1[-1]
      case
      when m2[0] == " "
        # 先頭が半角スペースはNG
        match
      when m2 =~ / {2,}$/
        # 末尾の半角スペースが2個以上はNG（1個はOK）
        match
      when last_char == "｜"
        # 直前に｜がある場合ルビ化は抑制される
        "#{m1[0...-1]}#{openclose_symbols[0]}#{m2}#{openclose_symbols[1]}"
      when is_sesame?(m1, m2, last_char)
        sesame(m1)
      when m1 =~ /^(.*)｜([^｜≪≫（）《》]+)$/
        "#{$1}［＃ルビ用縦線］#{$2}《#{ruby_youon_to_big(m2)}》"
      when object_of_ruby?(last_char)
        if openclose_symbols[0] == "≪" && m2 !~ /^#{AUTO_RUBY_CHARACTERS}$/
          # 《 》タイプのルビであっても、｜が存在しない場合の自動ルビ化対象はひらがな等だけである
          match
        elsif m2 =~ /\A([ぁ-んァ-ヶーゝゞ・]+)[ 　]?([ぁ-んァ-ヶーゝゞ・]*)\z/
          build_ruby(m1, m2, $1, $2)
        else
          match
        end
      else
        match
      end
    end

    #
    # なろうのルビ対象文字を辿って｜を挿入する（青空文庫となろうのルビ仕様の差異吸収のため）
    # 空白もルビ対象文字に含むのはなろうの仕様である
    def build_ruby(m1, m2, f1, f2)
      if m1 =~ /([#{CHARACTER_OF_RUBY}]+)([ 　])([#{CHARACTER_OF_RUBY}]+)\z/
        m1.sub(/([#{CHARACTER_OF_RUBY}]+)([ 　])([#{CHARACTER_OF_RUBY}]+)\z/) {
          if f2 == ""
            "#{$1}#{$2}［＃ルビ用縦線］#{$3}《#{ruby_youon_to_big(m2)}》"
          else
            "［＃ルビ用縦線］#{$1}《#{ruby_youon_to_big(f1)}》#{$2}［＃ルビ用縦線］#{$3}《#{ruby_youon_to_big(f2)}》"
          end
        }
      else
        m1.sub(/([#{CHARACTER_OF_RUBY}]+)\z/, "［＃ルビ用縦線］\\1") + "《#{ruby_youon_to_big(m2)}》"
      end
    end

    #
    # ルビの拗音(ぁ、ぃ等)を商業書籍のように大きくする
    #
    def ruby_youon_to_big(ruby)
      result = ruby
      if @setting.enable_ruby_youon_to_big
        result = ruby.tr("ぁぃぅぇぉゃゅょゎっァィゥェォャュョヮッヵヶ",
                         "あいうえおやゆよわつアイウエオヤユヨワツカケ")
      end
      result
    end
  end
end
