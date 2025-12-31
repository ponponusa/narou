# frozen_string_literal: true

#
# パーサー関連のエラークラス
#

module Narou
  module Parsers
    # パーサーの基底エラークラス
    class ParserError < StandardError; end

    # セレクタでの要素取得失敗
    class SelectorNotFoundError < ParserError
      attr_reader :selector, :context

      def initialize(selector, context = nil)
        @selector = selector
        @context = context
        msg = "要素が見つかりませんでした: #{selector}"
        msg += " (#{context})" if context
        super(msg)
      end
    end

    # 全てのフォールバックセレクタで失敗
    class AllSelectorsFailedError < ParserError
      attr_reader :selector_key, :tried_selectors

      def initialize(selector_key, tried_selectors = [])
        @selector_key = selector_key
        @tried_selectors = tried_selectors
        msg = "全てのセレクタで要素が見つかりませんでした: #{selector_key}"
        if tried_selectors.any?
          msg += "\n試行したセレクタ:\n"
          tried_selectors.each do |s|
            msg += "  - #{s['selector']} (priority: #{s['priority']})\n"
          end
        end
        super(msg)
      end
    end

    # パーサー設定ファイルの読み込みエラー
    class ConfigLoadError < ParserError; end

    # サイト構造変更の可能性
    class StructureChangedError < ParserError
      attr_reader :url, :last_successful_selector

      def initialize(url, last_successful_selector)
        @url = url
        @last_successful_selector = last_successful_selector
        msg = "サイト構造が変更された可能性があります: #{url}\n"
        msg += "以前成功したセレクタ: #{last_successful_selector}"
        super(msg)
      end
    end

    # JSON 解析エラー
    class JsonParseError < ParserError; end
  end
end
