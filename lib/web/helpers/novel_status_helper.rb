# frozen_string_literal: true

#
# Copyright 2025 ponponusa. All rights reserved.
#

#
# 小説の状態生成ヘルパー
#
# 小説一覧、詳細、その他の場所で状態表示を統一するための共通ヘルパー
#
module NovelStatusHelper
  module_function

  #
  # 小説の状態を生成
  #
  # @param novel_id [Integer] 小説ID
  # @param data [Hash] 小説データ（データベースレコード）
  # @return [String] 状態文字列（例: "凍結, 完結" または "連載中"）
  #
  # 状態の優先順位:
  # 1. 凍結
  # 2. 完結
  # 3. 削除
  # 4. 中断
  # いずれにも該当しない場合は「連載中」
  #
  def generate_novel_status(novel_id, data)
    tags = data["tags"] || []
    is_frozen = Narou.novel_frozen?(novel_id)

    status_parts = [
      is_frozen ? "凍結" : nil,
      tags.include?("end") ? "完結" : nil,
      tags.include?("404") ? "削除" : nil,
      data["suspend"] ? "中断" : nil
    ].compact

    status_parts.empty? ? "連載中" : status_parts.join(", ")
  end
end
