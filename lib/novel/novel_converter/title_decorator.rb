# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

class NovelConverter
  #
  # タイトル装飾（日付付与、完結表示等）
  #
  module TitleDecorator
    #
    # 2035年くらいまでの残り時間を10分単位の36進数で取得する
    # hyff のような文字列が取得可能
    # 小説家になろうで、もっとも古い作品が2004年5月1日11時49分なので、
    # その小説がちょうど4桁の zzzz となるように調整してある
    #
    def calc_reverse_short_time(time)
      ((2_091_149_000 - time.to_i) / (10 * 60)).to_s(36).rjust(4, "0")
    end

    #
    # タイトルに日付を付与する。
    # 日付の種類は title_date_target で指定する
    #
    # strftime の書式の他に拡張書式として $s, $t をサポートする
    # $s 2035年くらいまでの残り時間を10分単位の36進数（4桁）
    # $t タイトル自身。書式の中で自由な位置にタイトルを埋め込める
    # $ns 小説が掲載されているサイト名
    # $nt 小説種別（短編 or 連載）
    # $ntag 小説のタグをカンマ区切りにしたもの
    #
    # ※ $t を使用した場合、title_date_align を無視する
    #
    def add_date_to_title(title)
      result = title

      if @setting.enable_add_date_to_title
        new_arrivals_date = @data[@setting.title_date_target] || Time.now
        special_format_chars = [
          ["$s", calc_reverse_short_time(new_arrivals_date)],
          ["$ns", @data["sitename"]],
          ["$ntag", tags_join_comma(@data)],
          ["$nt", Narou.novel_type_text(@data["novel_type"])],
          ["$t", title]
        ]

        date_str = new_arrivals_date.strftime(@setting.title_date_format)
        doller_t_included = date_str.include?("$t")

        special_format_chars.each do |(symbol, replace_text)|
          date_str.gsub!(symbol, replace_text)
        end

        result = if doller_t_included
                   # $t で任意の位置にタイトルを埋め込むために title_date_align は無視する
                   date_str
                 elsif @setting.title_date_align == "left"
                   date_str + result
                 else # right
                   title + date_str
                 end
      end
      result
    end

    def tags_join_comma(data)
      tags = data["tags"] || []
      tags.sort.join(",")
    end

    def decorate_title(title)
      processed_title = add_date_to_title(title)
      # タイトルに完結したかどうかを付加する
      if @setting.enable_add_end_to_title
        tags = @data["tags"] || []
        if tags.include?("end")
          processed_title += " (完結)"
        end
      end
      # タイトルがルビ化されてしまうのを抑制
      processed_title.gsub("《", "※［＃始め二重山括弧］")
                     .gsub("》", "※［＃終わり二重山括弧］")
    end
  end
end
