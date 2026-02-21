# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "lib/cli/command/tag"

module Command
  class List < CommandBase
    class NovelDecorator
      attr_accessor(*%i(id frozen novel_type novel options parent))

      def initialize(novel, parent)
        self.id = novel["id"]
        self.frozen = Narou.novel_frozen?(id)
        self.novel_type = novel["novel_type"].to_i
        self.novel = novel
        self.options = parent.options
        self.parent = parent
      end

      def decorate_id
        disp_id = ((frozen ? "*" : "") + id.to_s).rjust(4)
        if frozen
          disp_id.gsub("*", "<bold><cyan>*</cyan></bold>")
        else
          disp_id
        end
      end

      def decorate_date
        key = parent.view_date_type
        base_time =
          novel[key] || novel[key.to_s] || novel[key.to_sym]

        new_arrivals_date = novel["new_arrivals_date"] || novel[:new_arrivals_date]
        last_update       = novel["last_update"]       || novel[:last_update]

        # 表示に使う日付（デフォは view_date_type）
        shown_time = base_time

        # 新着（magenta）: new_arrivals_date を表示する
        if new_arrivals_date && last_update &&
          new_arrivals_date >= last_update &&
          (new_arrivals_date + ANNOTATION_COLOR_TIME_LIMIT) >= now
          shown_time = new_arrivals_date
          return "<bold><magenta>#{shown_time.strftime('%y/%m/%d')}</magenta></bold>"
        end

        # 更新のみ（green）: last_update を表示（表示キーが general_lastup でも緑は last_update 基準）
        if last_update && (last_update + ANNOTATION_COLOR_TIME_LIMIT) >= now
          shown_time ||= last_update
          return "<bold><green>#{shown_time.strftime('%y/%m/%d')}</green></bold>"
        end

        # 通常表示
        return "" unless shown_time.respond_to?(:strftime)
        shown_time.strftime("%y/%m/%d")
      end

      def decorate_kind
        options["kind"] ? NOVEL_TYPE_LABEL[novel_type] : nil
      end

      def decorate_author
        options["author"] ? novel["author"].escape : nil
      end

      def decorate_site
        options["site"] ? novel["sitename"].escape : nil
      end

      def decorate_title
        if !options["kind"] && novel_type == 2
          type = " <bold><black>(#{NOVEL_TYPE_LABEL[novel_type]})</black></bold>"
        end
        the_end = "<bold><black>(完結)</black></bold>" if tags.include?("end")
        delete = "<bold><black>(削除)</black></bold>" if tags.include?("404")
        [
          novel["title"].escape,
          type,
          the_end,
          delete
        ].compact.join(" ")
      end

      def decorate_url
        return nil unless options["url"]
        (novel["toc_url"] || novel[:toc_url] || novel["url"] || novel[:url])&.to_s&.escape
      end

      def decorate_tags
        return nil unless options["tags"] || options["all-tags"]
        tags.empty? ? nil : tags.map { |tag|
          color = Tag.get_color(tag)
          "<bold><#{color}>#{tag.escape}</#{color}></bold>"
        }.join(",")
      end

      def decorate_line
        [
          decorate_id,
          decorate_date,
          decorate_kind,
          decorate_author,
          decorate_site,
          decorate_title,
          decorate_url,
          decorate_tags
        ].compact.join(" | ")
      end

      private

      def tags
        @__tags ||= novel["tags"] || []
      end

      def now
        parent.now
      end
    end
  end
end
