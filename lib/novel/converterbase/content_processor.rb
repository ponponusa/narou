# frozen_string_literal: true

#
# ConverterBase content processing methods (URL, illustration, special characters)
#

class ConverterBase
  module ContentProcessor
    #
    # URL っぽい文字列を一旦別のIDに置き換えてあとで復元することで、変換処理の影響を受けさせない
    #
    def replace_url(data)
      data.gsub!(URI::DEFAULT_PARSER.make_regexp(%w(http https))) do |match|
        @url_list << match
        "［＃ＵＲＬ＝#{@url_list.size - 1}］"
      end
    end

    def rebuild_url(data)
      @url_list.each_with_index do |url, id|
        data.sub!("［＃ＵＲＬ＝#{convert_numbers(id.to_s)}］",
                  "<a href=\"#{url}\">#{url}</a>")
      end
    end

    #
    # 挿絵タグやimgタグ等を挿絵注釈に変換
    # 挿絵画像が存在しなければダウンロードして保存する
    #
    def replace_illust_tag(data)
      @illustration.scanner(data) do |chuki|
        next "" unless @setting.enable_illust
        @illust_chuki_list << chuki
        "［＃挿絵＝#{@illust_chuki_list.size - 1}］\n"
      end
    end

    def rebuild_illust(data)
      @illust_chuki_list.each_with_index do |chuki, id|
        data.sub!("［＃挿絵＝#{convert_numbers(id.to_s)}］", chuki)
      end
    end

    #
    # 中黒(・)や句読点を並べて三点リーダーもどきにしているのを三点リーダーに変換
    #
    def convert_horizontal_ellipsis(data)
      return if !@setting.enable_convert_horizontal_ellipsis || \
                @text_type == "subtitle" || @text_type == "chapter"
      %w(・ 。 、 ．).each do |char|
        data.gsub!(/#{char}{3,}/) do |match|
          pre_char = $`[-1]
          post_char = $'[0]
          if pre_char == "―" || post_char == "―"
            match
          else
            "…" * ((match.length / 3.0 / 2).ceil * 2)
          end
        end
      end
      data.gsub!("。。", "。")
      data.gsub!("、、", "、")
    end

    KANA = "ァ-ヶー"

    #
    # 漢字の二じゃなくて間違えてカタカナのニを使ってるのを校正する
    #
    def modify_kana_ni_to_kanji_ni(data)
      if @setting.enable_kana_ni_to_kanji_ni
        data.gsub!(/([^#{KANA}]{2})ニ([^#{KANA}]{2})/) do
          prefix = $`.tap { |it|
            break it[-10, 10] if it.length > 10
          }
          @inspector.info(<<~EOS % (prefix + $1 + "ニ" + $2 + $'[0, 10]))
            カタカナのニを漢字の二に修正しました
            ≫≫≫ 該当箇所
            ...%s...
          EOS
          "#{$1}二#{$2}"
        end
      end
      data
    end
  end
end
