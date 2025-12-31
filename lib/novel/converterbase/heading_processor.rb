# frozen_string_literal: true

#
# ConverterBase heading and author comment processing methods
#

class ConverterBase
  module HeadingProcessor
    #
    # ［＃改ページ］直後の行を見出しに設定する
    #
    def enchant_midashi(data)
      def midashi(str)
        midashi_title = str.gsub("［＃半字下げ］", "").gsub(/^[　\s]+/, "").gsub(/[　\s]+$/, "")
        @inspector.subtitle = midashi_title
        "［＃３字下げ］［＃中見出し］#{midashi_title}［＃中見出し終わり］"
      end

      def calc_cr_count(str)
        head_cr_count = str.index(/[^\n]/) || 0
        head_cr_count > 2 ? 2 : head_cr_count
      end

      # 実際に見出しを付与する
      data.gsub!(/［＃改ページ］\n(.+?)\n/) do |match|
        m1 = $1
        rest = $'
        # 前書きがある場合は今回は保留して、次の処理で見出しを付与する
        if $1 =~ /#{AUTHOR_COMMENT_CHUKI[:introduction][:open]}/
          match
        else
          # 見出しの次の行が空行ではない場合空行を追加する
          add_tail = "\n" * (2 - calc_cr_count(rest))
          # 見出しと本文の間には空行を２行挟む
          "［＃改ページ］\n\n#{midashi(m1)}\n#{add_tail}"
        end
      end
      # 前書きがある場合は、前書き→見出しの順番を見出し→前書きに入れ替えて置換
      data.gsub!(/(［＃改ページ］\n)(#{AUTHOR_COMMENT_CHUKI[:introduction][:open]}.+?#{AUTHOR_COMMENT_CHUKI[:introduction][:close]}\n)(.+?\n)/m) do
        m1 = $1
        m2 = $2
        m3 = $3
        add_tail = $' =~ /\A$/ ? "" : "\n"
        "#{m1 + midashi(m3) + m2}#{add_tail}"
      end
    end

    #
    # 前書きを削除する
    #
    def erase_introduction(data)
      del_count = 0
      data.gsub!(/(［＃改ページ］)\n#{AUTHOR_COMMENT_CHUKI[:introduction][:open]}.+?#{AUTHOR_COMMENT_CHUKI[:introduction][:close]}/m) do
        del_count += 1
        $1
      end
      if del_count > 0
        @inspector.info("前書きをすべて削除しました。削除した数は#{del_count}個です。")
      end
    end

    #
    # 後書きを削除する
    #
    def erase_postscript(data)
      del_count = 0
      data.gsub!(/#{AUTHOR_COMMENT_CHUKI[:postscript][:open]}.+?#{AUTHOR_COMMENT_CHUKI[:postscript][:close]}\n(［＃改ページ］|\z)/m) do
        del_count += 1
        $1
      end
      if del_count > 0
        @inspector.info("後書きをすべて削除しました。削除した数は#{del_count}個です。")
      end
    end
  end
end
