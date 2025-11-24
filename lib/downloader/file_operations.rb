# frozen_string_literal: true

class Downloader
  #
  # File operation methods for Downloader
  #
  module FileOperations
    #
    # 差分用キャッシュ保存ディレクトリ作成
    #
    def create_cache_dir
      return nil if @nosave_diff
      now = Time.now
      name = now.strftime("%Y.%m.%d@%H.%M.%S")
      cache_dir = get_novel_data_dir.join(SECTION_SAVE_DIR_NAME, CACHE_SAVE_DIR_NAME, name)
      FileUtils.mkdir_p(cache_dir)
      cache_dir
    end

    #
    # 差分用キャッシュ保存ディレクトリを削除
    #
    def remove_cache_dir
      FileUtils.remove_entry_secure(@cache_dir, true) if @cache_dir
    end

    def raw_dir
      @raw_dir ||= get_novel_data_dir.join(RAW_DATA_DIR_NAME)
    end

    def init_raw_dir
      return if @nosave_raw
      path = raw_dir
      FileUtils.mkdir_p(path) unless path.exist?
    end

    #
    # テキストデータの生データを保存
    #
    def save_raw_data(raw_data, subtitle_info, ext = ".txt")
      return if @nosave_raw
      index = subtitle_info["index"]
      file_subtitle = subtitle_info["file_subtitle"]
      path = raw_dir.join("#{index} #{file_subtitle}#{ext}")
      File.write(path, raw_data)
    end

    #
    # 小説データの格納ディレクトリパス
    #
    def get_novel_data_dir
      raise "小説名がまだ設定されていません" unless get_file_title
      subdirectory = @download_use_subdirectory ? Downloader.create_subdirecotry_name(get_file_title) : ""
      Database.archive_root_path.join(sitename, subdirectory, get_file_title)
    end
    # Note: memoize is applied in the main Downloader class via extend Memoist

    #
    # 小説本文の保存パスを生成
    #
    def section_file_path(subtitle_info)
      filename = "#{subtitle_info["index"]} #{subtitle_info["file_subtitle"]}.yaml"
      get_novel_data_dir.join(SECTION_SAVE_DIR_NAME, filename)
    end

    def save_toc_once(toc)
      return if @save_toc_once
      save_novel_data(TOC_FILE_NAME, toc)
      @save_toc_once = true
    end

    #
    # 小説データの格納ディレクトリに保存
    #
    def save_novel_data(filename, object)
      path = get_novel_data_dir.join(filename)
      dir_path = path.dirname
      unless dir_path.exist?
        FileUtils.mkdir_p(dir_path)
      end
      File.write(path, YAML.dump(object))
    end

    #
    # 小説データの格納ディレクトリから読み込む
    def load_novel_data(filename)
      path = get_novel_data_dir.join(filename)
      Narou::YAMLLoader.load_file(path)
    rescue Errno::ENOENT
      nil
    rescue SystemCallError => e
      # bootsnap on Windows can raise Errno::E01 errors, fallback to standard YAML
      return nil unless File.exist?(path)
      Narou::YAMLLoader.load(File.read(path), filename: path)
    rescue Narou::YAMLLoader::Error => e
      warn "[warn] YAML load failed for #{filename}: #{e.message}"
      nil
    end

    #
    # 小説データの格納ディレクトリを初期設定する
    #
    def init_novel_dir
      novel_dir_path = get_novel_data_dir
      file_title = novel_dir_path.basename.to_s
      FileUtils.mkdir_p(novel_dir_path) unless novel_dir_path.exist?
      original_settings = NovelSetting.get_original_settings
      default_settings = NovelSetting.load_default_settings
      novel_setting = NovelSetting.new(@id, true, true)
      special_preset_dir = Narou.preset_dir.join(@setting["domain"], @setting["ncode"])
      exists_special_preset_dir = special_preset_dir.exist?
      templates = [
        [NovelSetting::INI_NAME, NovelSetting::INI_ERB_BINARY_VERSION],
        ["converter.rb", 1.0],
        [NovelSetting::REPLACE_NAME, 1.0]
      ]
      templates.each do |(filename, binary_version)|
        if exists_special_preset_dir
          preset_file_path = special_preset_dir.join(filename)
          if preset_file_path.exist?
            unless novel_dir_path.join(filename).exist?
              FileUtils.cp(preset_file_path, novel_dir_path)
            end
            next
          end
        end
        Template.write(filename, novel_dir_path, binding, binary_version)
      end
    end
  end
end
