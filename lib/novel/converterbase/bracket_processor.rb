# frozen_string_literal: true

#
# ConverterBase bracket processing methods
#

class ConverterBase
  module BracketProcessor
    BRACKETS = [%w(「 」), %w(『 』)]

    # ネストに対応したかぎ括弧の正規表現
    # ReDoS攻撃を防ぐため、ネストの深さを制限
    OPENCLOSE_REGEXPS = BRACKETS.map { |bracket|
      bo, bc = bracket
      # 最大3階層のネストに制限し、各階層の長さも制限
      /(?<oc>#{bo}(?:[^#{bo + bc}]{0,1000}|(?:\g<oc>)){0,50}#{bc})/m
    }

    #
    # 改行を連結した文章を作る
    #
    # 改行がひとつもなかった場合は nil を返す
    #
    def join_inner_bracket(str)
      return nil if str.count("\n") == 0
      joined_str = str.dup
      joined_str.gsub!(/([…―])\n/, "\\1。\n")
      joined_str = joined_str.split("\n").map { |s|
        s.sub(/^　+/, "")
      }.join
      joined_str
    end

    #
    # かぎ括弧のペアを手動で探索してマッチングする（ReDoS回避）
    #
    def find_bracket_pairs(text, open_bracket, close_bracket)
      pairs = []
      stack = []
      i = 0

      while i < text.length
        char = text[i]

        if char == open_bracket
          stack.push(i)
        elsif char == close_bracket && !stack.empty?
          start_pos = stack.pop
          # ネストの深さ制限（最大50階層）
          if stack.length < 50
            pairs.push([start_pos, i + 1])
          end
        end

        i += 1
      end

      # 最も外側のペアのみを抽出（ネストした内側は除外）
      outermost_pairs = []
      pairs.sort_by! { |pair| [pair[0], -pair[1]] } # 開始位置順、終了位置逆順

      last_end = -1
      pairs.each do |start_pos, end_pos|
        if start_pos > last_end
          outermost_pairs.push([start_pos, end_pos])
          last_end = end_pos - 1
        end
      end

      outermost_pairs
    end

    #
    # かぎ括弧内自動連結
    #
    def auto_join_in_brackets(data)
      if !@setting.enable_auto_join_in_brackets && !@setting.enable_inspect
        return
      end

      BRACKETS.each_with_index do |bracket, i|
        open_bracket, close_bracket = bracket

        # 括弧のペアを手動で探索
        pairs = find_bracket_pairs(data, open_bracket, close_bracket)

        next if pairs.empty?

        stack = {}
        replacements = []

        # 後ろから置換していく（位置がずれないように）
        pairs.reverse.each_with_index do |pair, j|
          start_pos, end_pos = pair
          index = pairs.length - 1 - j
          match = data[start_pos...end_pos]

          joined_str = join_inner_bracket(match)
          if @setting.enable_auto_join_in_brackets && joined_str
            error = @inspector.validate_joined_inner_brackets(match, joined_str, bracket)
            stack[index] = error ? match : joined_str
          else
            stack[index] = match
          end

          replacements.push([start_pos, end_pos, index])
        end

        # 後ろから置換
        replacements.each do |start_pos, end_pos, index|
          data[start_pos...end_pos] = "［＃かぎ括弧＝#{index}］"
        end

        if @setting.enable_inspect
          # 正しく閉じてないかぎ括弧だけが data に残ってる
          @inspector.inspect_invalid_openclose_brackets(data, bracket, stack)
        end

        data.replace(ConverterBase.rebuild_brackets(data, stack))
      end
    end

    #
    # 手動折り返しの自動連結
    #
    def auto_join_line(data)
      # 次の行の冒頭が開き記号だったら意図的な改行だと判断して連結しない
      # 行頭の全角スペースが２個以上の場合も連結しない
      data.gsub!(/([^、])、\n　([^「『(（【<＜〈《≪・■…‥―　１-９一-九])/, "\\1、\\2")
    end

    module ClassMethods
      def rebuild_brackets(data, stack)
        data.gsub(/［＃かぎ括弧＝(\d+)］/) do
          stack[$1.to_i]
        end
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end
  end
end
