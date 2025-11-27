# frozen_string_literal: true

#
# ConverterBase indent and formatting methods
#

class ConverterBase
  module IndentProcessor
    HALF_INDENT_TARGET = /^[ 　\t]*((?:[〔「『(（【〈《≪〝])|(?:※［＃始め二重山括弧］))/
    FULL_INDENT_TARGET = /^[ 　\t]*(――)/
    AUTO_INDENT_IGNORE_INDENT_CHAR = Inspector::IGNORE_INDENT_CHAR.sub("・", "")

    #
    # 行頭かぎ括弧(等)に二分アキを追加する
    #
    # 「や（などの前にカスタム注記（［＃二分アキ］）を追加し、半文字分字下げする(二分アキ)。
    # kindle paperwhite で鍵括弧のインデントがおかしいことへの対応
    #
    def half_indent_bracket(data)
      data.gsub!(HALF_INDENT_TARGET) do
        if @setting.enable_half_indent_bracket
          "［＃二分アキ］#{$1}"
        else
          $1
        end
      end
    end

    #
    # 行頭字下げ
    #
    # 必ず下げなければいけないところは強制的に字下げ
    # 他の部分は全体的に判断して字下げ
    # enable_force_indent が有効なら強制字下げ
    #
    def auto_indent(data)
      data.gsub!(FULL_INDENT_TARGET, "　\\1")
      if @setting.enable_force_indent || (@setting.enable_auto_indent && @inspector.inspect_indent(data))
        data.gsub!(/^([^#{AUTO_INDENT_IGNORE_INDENT_CHAR}])/) do
          # 行頭に三点リーダーの代わりに連続中黒（・・・）が来た場合の対策
          # https://github.com/whiteleaf7/narou/issues/35
          # 行頭に中黒１個だけの場合はよくある表現なので字下げしない
          if $1 == "・" && $'[0] != "・"
            "・"
          else
            $1 == " " || $1 == "　" ? "　" : "　#{$1}"
          end
        end
      end
    end

    #
    # 章見出しっぽい文字列を字下げする
    #
    def force_indent_special_chapter(data)
      return unless @text_type == "body" || @text_type == "textfile"
      @@count_of_rebuild_container ||= 0
      data.gsub!(/^[ 　\t]*([－―<＜〈-]*)([0-9０-９#{KANJI_NUM}]{1,3})([－―>＞〉-]*)$/) do
        top = $1
        chapter = $2
        bottom = $3
        if top != "" && "―－-".include?(top) # include?は空文字("")だとtrueなのでチェック必須
          top = "― "
          bottom = " ―"
        end
        str = +"　　　#{top}"
        str += hankaku_num_to_zenkaku_num(chapter.tr("０-９", "0-9"))
        str += "#{bottom}"
        # 前後に空行を入れたいが、それは行処理ループ中に行う
        symbols_to_zenkaku(str)
        index = @@count_of_rebuild_container += 1
        @force_indent_special_chapter_list[convert_numbers(index.to_s.rjust(10, "0"))] = str
        "［＃章見出しっぽい文＝#{index.to_s.rjust(10, "0")}］"
      end
    end

    def rebuild_force_indent_special_chapter(data)
      data.gsub!(/［＃章見出しっぽい文＝(.+?)］/) do
        @force_indent_special_chapter_list[$1]
      end
    end

    def insert_blank_before_line_and_behind_to_special_chapter(line)
      result = +""
      if line =~ /［＃章見出しっぽい文＝/
        unless blank_line?(@before_line)
          result << "\n"
        end
        @request_insert_blank_next_line = true
      end
      line.sub!(/\A/, result)
    end

    #
    # 行頭空白を考慮した字下げ
    #
    def jisage(line, num)
      line.sub!(/^[ 　\t]*/, "　" * num)
    end
  end
end
