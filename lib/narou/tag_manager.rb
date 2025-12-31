# frozen_string_literal: true

#
# Copyright 2025 ponponusa. All rights reserved.
#

require "lib/core/database"
require "lib/core/inventory"
require "lib/cli/command/tag"

module Narou
  #
  # タグ管理を担当するクラス
  # Legacy API と API v2 の両方で使用される共通ロジックを提供
  #
  class TagManager
    # タグ色の定義
    COLORS = %w(green yellow blue magenta cyan red white).freeze

    class << self
      #
      # タグ一覧を取得
      #
      # @param ids [Array<Integer>, nil] 特定の小説IDのタグだけ取得する場合に指定
      # @return [Hash<String, Integer>] { "タグ名" => タグが付けられた小説の数, ... }
      #
      def get_tag_list(ids = nil)
        database = Database.instance
        tag_list = Hash.new(0)

        database.each_value do |data|
          next if ids.is_a?(Array) && !ids.include?(data["id"])

          tags = data["tags"] || []
          tags.each do |tag|
            tag_list[tag] += 1
          end
        end

        tag_list.default = nil
        tag_list
      end

      #
      # 指定されたタグの色を取得
      #
      # @param tagname [String] タグ名
      # @return [String] タグの色（CSSクラス名）
      #
      def get_color(tagname)
        require "lib/cli/command/tag"
        Command::Tag.get_color(tagname)
      end

      #
      # タグの色を一括設定
      #
      # @param colors [Hash<String, String>] { "タグ名" => "色", ... }
      # @return [void]
      #
      def set_colors(colors)
        require "lib/cli/command/tag"
        tag_colors = Inventory.load("tag_colors")
        colors.each do |tagname, color|
          tag_colors[tagname] = color if Command::Tag::COLORS.include?(color)
        end
        tag_colors.save
      end

      #
      # タグ情報を詳細形式で取得
      #
      # @param ids [Array<Integer>] 対象の小説ID配列
      # @param with_exclusion [Boolean] 除外タグHTMLを含めるか
      # @return [Hash] タグ情報のハッシュ
      #
      def get_tag_info(ids, with_exclusion: false)
        database = Database.instance
        tag_info = {}

        # まず全体のタグ一覧を取得
        all_tags = get_tag_list
        all_tags.each do |tag, total_count|
          tag_info[tag] = {
            count: 0,
            total_count: total_count,
            tag: tag,
            color: get_color(tag)
          }
        end

        # 選択されたIDの小説での各タグの出現回数を計算
        ids.each do |id|
          # データベースのキーは文字列または整数の可能性があるため、両方を試す
          # 文字列が渡された場合は整数にも変換して試す
          id_int = id.is_a?(String) ? id.to_i : id
          id_str = id.to_s
          data = database[id] || database[id_int] || database[id_str]

          next unless data

          tags = data["tags"] || []
          tags.each do |tag|
            tag_info[tag] ||= {
              count: 0,
              total_count: 1,
              tag: tag,
              color: get_color(tag)
            }
            tag_info[tag][:count] += 1
          end
        end

        tag_info
      end

      #
      # タグを追加
      #
      # @param tag_names [Array<String>] 追加するタグ名の配列
      # @param novel_ids [Array<Integer>] 対象の小説ID配列
      # @return [Hash] { success: Boolean, added_count: Integer }
      #
      def add_tags(tag_names, novel_ids)
        require "lib/cli/command/tag"
        require "lib/output/narou_logger"

        begin
          Command::Tag.execute!("--add", tag_names.join(" "), novel_ids, io: Narou::NullIO.new)
          { success: true, added_count: novel_ids.length }
        rescue StandardError => e
          { success: false, error: e.message }
        end
      end

      #
      # タグを削除
      #
      # @param tag_names [Array<String>] 削除するタグ名の配列
      # @param novel_ids [Array<Integer>] 対象の小説ID配列
      # @return [Hash] { success: Boolean, deleted_count: Integer }
      #
      def delete_tags(tag_names, novel_ids)
        require "lib/cli/command/tag"
        require "lib/output/narou_logger"

        begin
          Command::Tag.execute!("--delete", tag_names.join(" "), novel_ids, io: Narou::NullIO.new)
          { success: true, deleted_count: novel_ids.length }
        rescue StandardError => e
          { success: false, error: e.message }
        end
      end

      #
      # タグを一括編集
      #
      # @param states [Hash<String, Integer>] { "タグ名" => 状態(0:削除, 1:維持, 2:追加) }
      # @param novel_ids [Array<Integer>] 対象の小説ID配列
      # @return [Hash] { success: Boolean, added: Array, deleted: Array }
      #
      def edit_tags(states, novel_ids)
        require "lib/cli/command/tag"
        require "lib/output/narou_logger"

        # key と value を重複を維持したまま反転
        invert_states = states.inject({}) { |h, (k, v)| (h[v] ||= []) << k; h }

        added_tags = []
        deleted_tags = []

        invert_states.each do |state, tags|
          case state.to_i
          when 0
            # タグを削除
            Command::Tag.execute!("--delete", tags.join(" "), novel_ids, io: Narou::NullIO.new)
            deleted_tags.concat(tags)
          when 1
            # 現状を維持(何もしない)
          when 2
            # タグを追加
            Command::Tag.execute!("--add", tags.join(" "), novel_ids, io: Narou::NullIO.new)
            added_tags.concat(tags)
          end
        end

        # タグ追加がある場合は、データベース書き込み完了を待つ
        sleep(0.5) if added_tags.any?

        {
          success: true,
          added: added_tags,
          deleted: deleted_tags,
          novel_count: novel_ids.length
        }
      rescue StandardError => e
        { success: false, error: e.message }
      end
    end
  end
end
