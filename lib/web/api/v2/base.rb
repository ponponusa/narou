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

require "lib/web/helpers/novel_status_helper"

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
      def error_response(code, message, details: nil)
        response = {
          success: false,
          error: {
            code: code,
            message: message
          },
          timestamp: Time.now.to_i
        }
        response[:error][:details] = details if details
        response
      end
    end

    # API v2 ベースモジュール
    module Base
      include ResponseHelper

      # CORS ヘッダー設定
      def set_cors_headers
        headers["Access-Control-Allow-Origin"] = "*"
        headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
        headers["Access-Control-Allow-Headers"] = "Content-Type, Accept, Authorization"
        headers["Access-Control-Expose-Headers"] = "Content-Disposition"
        headers["Access-Control-Max-Age"] = "86400"
      end

      # JSON リクエストボディのパース
      def parse_json_body
        request.body.rewind
        raw_body = request.body.read.to_s
        return {} if raw_body.empty?

        begin
          JSON.parse(raw_body)
        rescue JSON::ParserError => e
          halt 400, json(error_response("INVALID_JSON", "Invalid JSON: #{e.message}"))
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

      # データベースの準備状態をチェック
      def database_ready?
        return false unless defined?(Database)

        # Databaseインスタンスが取得できるかチェック
        db = Database.instance
        return false unless db

        # データベースオブジェクトが存在するかチェック
        db_obj = db.get_object
        return false unless db_obj

        true
      rescue StandardError => e
        # エラーが発生した場合は準備未完了とみなす
        logger.warn "Database ready check failed: #{e.message}" if defined?(logger)
        false
      end

      # 小説の状態を生成（共通ヘルパーへの委譲）
      # @param novel_id [Integer] 小説ID
      # @param data [Hash] 小説データ（データベースレコード）
      # @return [String] 状態文字列（例: "凍結, 完結"）
      def generate_novel_status(novel_id, data)
        NovelStatusHelper.generate_novel_status(novel_id, data)
      end
    end
  end
end
