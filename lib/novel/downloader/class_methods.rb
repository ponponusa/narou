# frozen_string_literal: true

class Downloader
  #
  # Class methods for Downloader - database access and path utilities
  #
  module ClassMethods
    #
    # 小説サイト設定を取得する
    #
    def get_sitesetting_by_target(target)
      toc_url = get_toc_url(target)
      setting = nil
      if toc_url
        setting = SiteSetting.find(toc_url)
      end
      setting
    end

    #
    # 本文格納用ディレクトリを取得
    #
    def get_novel_section_save_dir(archive_path)
      Pathname(File.join(archive_path, SECTION_SAVE_DIR_NAME))
    end

    #
    # target の種別を判別する
    #
    # ncodeの場合、targetを破壊的に変更する
    #
    def get_target_type(target)
      case target
      when URI::DEFAULT_PARSER.make_regexp
        :url
      when /^n\d+[a-z]+$/i
        target.downcase!
        :ncode
      when /^\d+$/, Integer
        :id
      else
        :other
      end
    end

    #
    # 指定されたIDとかから小説の保存ディレクトリを取得
    #
    def get_novel_data_dir_by_target(target)
      data = get_data_by_target(target) or return nil
      id = data["id"]
      file_title = data["file_title"] || data["title"] # 互換性維持のための処理
      use_subdirectory = data["use_subdirectory"] || false
      subdirectory = use_subdirectory ? create_subdirecotry_name(file_title) : ""
      path = Database.archive_root_path.join(data["sitename"], subdirectory, file_title)
      return path if path.exist?
      database.delete(id)
      database.save_database
      error "#{path} が見つかりません。\n" \
            "保存フォルダが消去されていたため、データベースのインデックスを削除しました。"
      nil
    end

    #
    # target のIDを取得
    #
    def get_id_by_target(target)
      data = get_data_by_target(target)
      data && data["id"]
    end

    #
    # target からデータベースのデータを取得
    #
    def get_data_by_target(target)
      target = Narou.alias_to_id(target)
      case get_target_type(target)
      when :url
        setting = SiteSetting.find(target)
        if setting
          toc_url = setting["toc_url"]
          return database.get_data_by_toc_url(toc_url, setting)
        end
      when :ncode
        database.each_value do |data|
          return data if data["toc_url"] =~ %r{#{Regexp.escape(target)}/$}
        end
      when :id
        data = database[target.to_i]
        return data if data
      when :other
        data = database.get_data("title", target)
        return data if data
      end
      nil
    end

    #
    # toc 読込
    #
    def get_toc_data(archive_path)
      path = File.join(archive_path, TOC_FILE_NAME)
      Narou::YAMLLoader.load_file(path)
    rescue SystemCallError
      # bootsnap on Windows can raise Errno::E01 errors, fallback to standard IO read
      Narou::YAMLLoader.load(File.read(path), filename: path)
    end

    def get_toc_by_target(target)
      dir = Downloader.get_novel_data_dir_by_target(target)
      get_toc_data(dir)
    end

    #
    # 指定の小説の目次ページのURLを取得する
    #
    # targetがURLかNコードの場合、実際には小説が存在しないURLが返ってくることがあるのを留意する
    #
    def get_toc_url(target)
      target = Narou.alias_to_id(target)
      case get_target_type(target)
      when :url
        setting = SiteSetting.find(target)
        return setting["toc_url"] if setting
      when :ncode
        database.each_value do |data|
          if data["toc_url"] =~ %r{#{target}/$}
            return data["toc_url"]
          end
        end
        return "#{SiteSetting.narou["top_url"]}/#{target}/"
      when :id
        data = database[target.to_i]
        return data["toc_url"] if data
      when :other
        data = database.get_data("title", target)
        return data["toc_url"] if data
      end
      nil
    end

    def novel_exists?(target)
      id = get_id_by_target(target) or return nil
      database.novel_exists?(id)
    end

    def remove_novel(target, with_file = false)
      data = get_data_by_target(target) or return nil
      data_dir = get_novel_data_dir_by_target(target)
      if with_file
        FileUtils.remove_entry_secure(data_dir, true)
        puts "#{data_dir} を完全に削除しました"
      else
        # TOCは消しておかないと再DL時に古いデータがあると誤認する
        data_dir.join(TOC_FILE_NAME).delete
      end
      database.delete(data["id"])
      database.save_database
      data["title"]
    end

    #
    # 差分用キャッシュの保存ディレクトリ取得
    #
    def get_cache_root_dir(target)
      dir = get_novel_data_dir_by_target(target)
      if dir
        return dir.join(SECTION_SAVE_DIR_NAME, CACHE_SAVE_DIR_NAME)
      end
      nil
    end

    #
    # 差分用キャッシュのディレクトリ一覧取得
    #
    def get_cache_list(target)
      dir = get_cache_root_dir(target)
      if dir
        return Dir.glob("#{dir}/*")
      end
      nil
    end

    #
    # サブディレクトリ名を生成
    #
    def create_subdirecotry_name(title)
      name = title.start_with?("n") ? title[1..2] : title[0..1]
      name.strip
    end

    def database
      Database.instance
    end

    #
    # エラーメッセージ検出
    #
    def detect_error_message(setting, source)
      message = setting["error_message"]
      return false unless message
      source.match(message)
    end

    #
    # 選択肢を文字列に変換
    #
    def choices_to_string(width: 0)
      Downloader::CHOICES.dup.tap { |h| h.delete(:default) }.map { |key, summary|
        "#{key.rjust(width)}: #{summary}"
      }.join("\n")
    end
  end
end
