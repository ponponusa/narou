# frozen_string_literal: true

class Downloader
  #
  # Database update methods for Downloader
  #
  module DatabaseUpdater
    def __search_latest_update_time(key, subtitles, subkey: nil)
      latest = Time.new(0)
      subtitles.each do |subtitle|
        value = subtitle[key]
        if value.to_s.empty? && subkey
          value = subtitle[subkey]
        end
        time = Helper.date_string_to_time(value)
        latest = time if time && latest < time
      end
      latest
    end

    #
    # 小説が更新された日をTime型で取得
    #
    def get_novelupdated_at
      info = @setting["info"] || {}
      if info["novelupdated_at"]
        info["novelupdated_at"]
      else
        __search_latest_update_time("subupdate", @setting["subtitles"], subkey: "subdate")
      end
    end

    #
    # 小説の最新掲載日をTime型で取得
    #
    # 小説家になろう、ハーメルンは小説情報ページの最終話掲載日などから取得した日付
    # その他サイトは一番新しい話の投稿日（更新日ではない）
    #
    def get_general_lastup
      info = @setting["info"] || {}
      if info["general_lastup"]
        info["general_lastup"]
      else
        __search_latest_update_time("subdate", @setting["subtitles"])
      end
    end

    #
    # 小説の文字数
    #
    # 小説情報から取得するため、実際に計算するわけではない。
    # 情報から取得出来ない（記載がない）場合は無視する
    #
    def novel_length
      info = @setting["info"] || {}
      info["length"]
    end

    #
    # データベース更新
    #
    def update_database(suspend: false)
      info = @setting["info"] || {}
      data = {
        "id" => @id,
        "author" => @setting["author"],
        "title" => get_title,
        "file_title" => get_file_title,
        "toc_url" => @setting["toc_url"],
        "sitename" => sitename,
        "novel_type" => get_novel_type,
        "end" => novel_end?,
        "last_update" => Time.now,
        "new_arrivals_date" => (@new_arrivals ? Time.now : record["new_arrivals_date"]),
        "use_subdirectory" => @download_use_subdirectory,
        "general_firstup" => info["general_firstup"],
        "novelupdated_at" => get_novelupdated_at,
        "general_lastup" => get_general_lastup,
        "length" => novel_length,
        "suspend" => suspend
      }

      data["title_raw_latest"] = data["title"]&.dup
      data["title_original"] = data["title_raw_latest"] || data["title"]
      data["author_original"] = data["author"]

      promo_config = Narou::PromoTagExtractor.resolve_config(novel_id: @id)
      Narou::PromoTagExtractor.normalize_entry!(data, config: promo_config)
      @setting["title"] = data["title"]
      @setting["author"] = data["author"]
      @title = data["title"]

      auto_add_tags = Inventory.load("local_setting")["auto-add-tags"]
      if @setting["tag"] && auto_add_tags
        tag_value = @setting["tag"]
        tags = if tag_value.is_a?(Array)
                 tag_value.map { |t| Sanitize.fragment(t).strip }.select { |t| t.length > 0 }
               else
                 clean_tag = Sanitize.fragment(tag_value).gsub(/キーワード/, "").gsub(/\"?\(\?\.\+\?\)\"?/, "").gsub(/\(\?\<?[^)]*\)/, "").strip
                 clean_tag.length > 0 ? clean_tag.split(/[ 　]+/) : []
               end
        if tags.length > 0
          if record && record["tags"]
            old_tags = record["tags"]
            tags.concat(old_tags)
          end
          data["tags"] = tags.uniq
        end
      end
      if record
        database[@id].merge!(data)
      else
        database[@id] = data
      end
      database.save_database
    end

    def apply_promo_tag_preferences!
      data = record
      return false unless data

      promo_config = Narou::PromoTagExtractor.resolve_config(novel_id: @id)
      changed = Narou::PromoTagExtractor.normalize_entry!(data, config: promo_config)

      if @setting
        @setting["title"] = data["title"]
        @setting["author"] = data["author"]
      end
      @title = data["title"]

      changed
    end

    def get_novel_status
      novel_status = NovelInfo.load(@setting, of: "nt-e-sitename")
      novel_status ||= {
        "novel_type" => NOVEL_TYPE_SERIES,
        "end" => nil, # nil で完結状態が定義されていなかったことを示す（扱いとしては未完結と同じ）
        "sitename" => @setting["sitename"]
      }
      novel_status
    end

    #
    # 小説の種別を取得（連載か短編）
    #
    def get_novel_type
      get_novel_status["novel_type"]
    end

    #
    # 小説が完結しているか調べる
    #
    def novel_end?
      get_novel_status["end"]
    end

    #
    # 掲載サイト名
    #
    # すでにレコードに登録されている場合はそちらを優先する
    #
    def sitename
      record&.dig("sitename") || get_novel_status["sitename"]
    end

    #
    # 連載小説かどうか調べる
    #
    def series_novel?
      get_novel_type == NOVEL_TYPE_SERIES
    end
  end
end
