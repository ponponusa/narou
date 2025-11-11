# frozen_string_literal: true

#
# Copyright 2025 ponponusa. All rights reserved.
#

#
# API v2 エンドポイント
# 
# SPA (Single Page Application) 向けの最新API実装
# JSON レスポンスを基本とし、REST原則に従う
#

module Narou
  module ApiV2
    # API v2 共通レスポンスフォーマット
    module ResponseHelper
      # 成功レスポンス
      def success_response(data, message: nil)
        {
          success: true,
          data: data,
          message: message,
          timestamp: Time.now.to_i
        }
      end

      # エラーレスポンス
      def error_response(code, message)
        {
          success: false,
          error: {
            code: code,
            message: message
          },
          timestamp: Time.now.to_i
        }
      end
    end

    # API v2 ベースモジュール
    module Base
      include ResponseHelper

      # CORS ヘッダー設定
      def set_cors_headers
        headers['Access-Control-Allow-Origin'] = '*'
        headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
        headers['Access-Control-Allow-Headers'] = 'Content-Type, Accept, Authorization'
        headers['Access-Control-Max-Age'] = '86400'
      end

      # JSON リクエストボディのパース
      def parse_json_body
        request.body.rewind
        raw_body = request.body.read.to_s
        return {} if raw_body.empty?

        begin
          JSON.parse(raw_body)
        rescue JSON::ParserError => e
          halt 400, json(error_response('INVALID_JSON', "Invalid JSON: #{e.message}"))
        end
      end

      # ID パラメータのバリデーション
      def validate_ids(ids)
        return nil unless ids.is_a?(Array)
        
        result = ids.select do |id|
          case id
          when Integer
            true
          when String
            id =~ /^\d+$/
          else
            false
          end
        end.map(&:to_s)
        
        result.empty? ? nil : result
      end
    end
  end
end
