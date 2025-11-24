# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "yaml"
require "fileutils"
require "ostruct"
require "cgi"
require_relative "narou"
require_relative "narou/promo_tag_extractor"
require_relative "narou/parsers/parser_selector"
require_relative "helper"
require_relative "sitesetting"
require_relative "novelsetting"
require_relative "template"
require_relative "progressbar"
require_relative "database"
require_relative "inventory"
require_relative "eventable"
require_relative "html"
require_relative "input"
require_relative "narou/yaml_loader"
require_relative "downloader/errors"
require_relative "downloader/sanitize"
require_relative "downloader/class_methods"
require_relative "downloader/file_operations"
require_relative "downloader/database_updater"
require_relative "downloader/section_downloader"

#
# 小説サイトからのダウンロード
#
class Downloader
  extend Downloader::ClassMethods
  include Downloader::FileOperations
  include Downloader::DatabaseUpdater
  include Downloader::SectionDownloader
  include Narou::Eventable
  extend Memoist

  SECTION_SAVE_DIR_NAME = "本文"    # 本文を保存するディレクトリ名
  CACHE_SAVE_DIR_NAME = "cache"   # 差分用キャッシュ保存用ディレクトリ名
  RAW_DATA_DIR_NAME = "raw"    # 本文の生データを保存するディレクトリ名
  TOC_FILE_NAME = "toc.yaml"
  STEPS_WAIT_TIME = 5   # 数話ごとにかかるwaitの秒数
  WAIT_TIME_TO_RETRY_NETWORK = 10 # タイムアウト等でリトライするまでの待機時間
  LIMIT_TO_RETRY_NETWORK = 5 # タイムアウト等でリトライする回数上限
  NOVEL_TYPE_SERIES = 1   # 連載
  NOVEL_TYPE_SS = 2       # 短編
  DISPLAY_LIMIT_DIGITS = 4   # indexの表示桁数限界
  DEFAULT_INTERVAL_WAIT = 0.7   # download.interval のデフォルト値(秒)

  attr_reader :id, :setting

  def initialize(target, options = {})
    id = Downloader.get_id_by_target(target)
    options = {
      force: false, from_download: false,
      stream: $stdout
    }.merge(options)
    setting = Downloader.get_sitesetting_by_target(target)

    unless setting
      case type = Downloader.get_target_type(target)
      when :url, :ncode
        raise InvalidTarget, "対応外の#{type}です(#{target})"
      when :id
        raise InvalidTarget, "指定のID(#{target})は存在しません"
      when :other
        raise InvalidTarget, "指定の小説(#{target})は存在しません"
      end
    end

    initialize_variables(id, setting, options)
  end

  #
  # 変数初期化
  #
  def initialize_variables(id, setting, options)
    @id = id || database.create_new_id
    @title = nil
    @setting = setting
    @force = options[:force]
    @stream = options[:stream]
    @cache_dir = nil
    @new_arrivals = false
    @new_novel = record.!
    @from_download = options[:from_download]
    @section_download_cache = {}
    @max_cache_size = 20  # セクションキャッシュの上限
    @download_wait_steps = Inventory.load("local_setting")["download.wait-steps"] || 0
    @download_use_subdirectory = use_subdirectory?
    if @setting["is_narou"] && (@download_wait_steps > 10 || @download_wait_steps == 0)
      @download_wait_steps = 10
    end
    @nosave_diff = Narou.economy?("nosave_diff")
    @nosave_raw = Narou.economy?("nosave_raw")
    @gurad_spoiler = Inventory.load("local_setting")["guard-spoiler"]
    
    # 新パーサーの初期化
    @parser = Narou::Parsers::ParserSelector.select(@setting, novel_id: @id) rescue nil
    
    initialize_wait_counter
  end

  def database
    self.class.database
  end

  def record
    database[@id]
  end

  #
  # ウェイト関係初期化
  #
  def initialize_wait_counter
    @@__run_once ||= false
    unless @@__run_once
      @@__run_once = true
      @@__wait_counter = 0
      @@__last_download_time = Time.now - 20
    end
    @@interval_sleep_time = Inventory.load("local_setting")["download.interval"] || DEFAULT_INTERVAL_WAIT
    @@interval_sleep_time = 0 if @@interval_sleep_time < 0
    @@max_steps_wait_time = [STEPS_WAIT_TIME, @@interval_sleep_time].max
  end

  #
  # サブディレクトリに保存してあるかどうか
  #
  def use_subdirectory?
    if @new_novel
      # 新規DLする小説
      Inventory.load("local_setting")["download.use-subdirectory"] || false
    else
      # すでにDL済みの小説
      record["use_subdirectory"] || false
    end
  end

  #
  # 18歳以上か確認する
  #
  def confirm_over18?
    global_setting = Inventory.load("global_setting", :global)
    if global_setting.include?("over18")
      return global_setting["over18"]
    end
    if Narou::Input.confirm("年齢認証：あなたは18歳以上ですか")
      global_setting["over18"] = true
      global_setting.save
      return true
    else
      return false
    end
  end

  #
  # ダウンロードを処理本体を起動
  #
  def start_download
    @status = run_download
    OpenStruct.new(
      :id => @id,
      :new_arrivals => @new_arrivals,
      :status => @status
      ).freeze
  end

  def load_toc_file
    load_novel_data(TOC_FILE_NAME)
  end

  #
  # ダウンロード処理本体
  #
  def run_download
    old_toc = @new_novel ? nil : load_toc_file
    latest_toc = get_latest_table_of_contents(old_toc)
    unless latest_toc
      @stream.error @setting["toc_url"] + " の目次データが取得出来ませんでした"
      return :failed
    end
    latest_toc_subtitles = latest_toc["subtitles"]
    if @setting["confirm_over18"]
      unless confirm_over18?
        @stream.puts "18歳以上のみ閲覧出来る小説です。ダウンロードを中止しました"
        return :canceled
      end
    end
    unless old_toc
      init_novel_dir
      old_toc = {}
      @new_arrivals = true
    end
    init_raw_dir
    if old_toc.empty? || @force
      update_subtitles = latest_toc_subtitles
    else
      update_subtitles = update_body_check(old_toc["subtitles"], latest_toc_subtitles)
    end

    if old_toc.empty? && update_subtitles.size.zero?
      @stream.error "#{@setting['title']} の目次がありません"
      return :failed
    end

    unless @force
      if process_digest(old_toc, latest_toc)
        return :canceled
      end
    end

    id_and_title = "ID:#{@id}　#{@title}"

    return_status =
      case
      when update_subtitles.size > 0
        @cache_dir = create_cache_dir if old_toc.length > 0
        sections_download_and_save(update_subtitles)
        if @cache_dir && @cache_dir.glob("*").count == 0
          remove_cache_dir
        end
        update_database
        :ok
      when old_toc["subtitles"].size > latest_toc_subtitles.size
        # 削除された節がある（かつ更新がない）場合
        @stream.puts "#{id_and_title} は一部の話が削除されています"
        :ok
      when old_toc["title"] != latest_toc["title"]
        # タイトルが更新されている場合
        @stream.puts "#{id_and_title} のタイトルが更新されています"
        update_database
        :ok
      when old_toc["story"] != latest_toc["story"]
        # あらすじが更新されている場合
        @stream.puts "#{id_and_title} のあらすじが更新されています"
        :ok
      when old_toc["author"] != latest_toc["author"]
        # 著者名が更新されている場合
        @stream.puts "#{id_and_title} の著者名が更新されています"
        update_database
      else
        :none
      end

    auto_add_tags = Inventory.load("local_setting")["auto-add-tags"]
    if @setting["tag"] && auto_add_tags
      clean_tag = Sanitize.fragment(@setting["tag"]).gsub(/キーワードが設定されていません/, '').gsub(/キーワード/, '').gsub(/\"?\(\?\.\+\?\)\"?/, '').gsub(/\(\?\<?[^)]*\)/, '').strip
      if clean_tag.length > 0
        new_tags = clean_tag.split(/[ 　]+/).uniq
        old_tags = (record && record["tags"]) ? record["tags"] : []
        if (new_tags - old_tags).any?
          @stream.puts "#{id_and_title} のタグが更新されています"
          update_database
          return_status = :ok if return_status == :none
        end
      end
    end

    record["general_all_no"] = latest_toc_subtitles.size

    save_toc_once(latest_toc)
    tags = @new_novel ? [] : record["tags"] || []
    case novel_end?
    when true
      unless tags.include?("end")
        update_database if update_subtitles.count == 0
        require_relative "command/tag" unless defined?(Command::Tag)
        Command::Tag.execute!(%W(#{id} --add end --color white --no-overwrite-color), io: Narou::NullIO.new)
        msg = old_toc.empty? ? "完結しているようです" : "完結したようです"
        @stream.puts "<cyan>#{id_and_title.escape} は#{msg}</cyan>".termcolor
        return_status = :ok
      end
    when false
      if tags.include?("end")
        update_database if update_subtitles.size == 0
        require_relative "command/tag" unless defined?(Command::Tag)
        Command::Tag.execute!(@id, "--delete", "end", io: Narou::NullIO.new)
        @stream.puts "<cyan>#{id_and_title.escape} は連載を再開したようです</cyan>".termcolor
        return_status = :ok
      end
    end
    return_status
  rescue Interrupt, SuspendDownload
    if latest_toc.present?
      save_toc_once(latest_toc)
      update_database(suspend: true)
    end
    raise Interrupt
  ensure
    @setting.clear
  end

  CHOICES = {
    "1" => "このまま更新する",
    "2" => "更新をキャンセル",
    "3" => "更新をキャンセルして小説を凍結する",
    "4" => "バックアップを作成する",
    "5" => "最新のあらすじを表示する",
    "6" => "小説ページをブラウザで開く",
    "7" => "保存フォルダを開く",
    "8" => "変換する",
    default: "2"
  }.freeze

  #
  # ダイジェスト化に関する処理
  #
  # @return true = 更新をキャンセル、false = 更新する
  #
  def process_digest(old_toc, latest_toc)
    return false unless old_toc["subtitles"]
    latest_subtitles_count = latest_toc["subtitles"].size
    old_subtitles_count = old_toc["subtitles"].size
    if latest_subtitles_count < old_subtitles_count
      title = latest_toc["title"]
      message = <<-EOS
更新後の話数が保存されている話数より減少していることを検知しました。
ダイジェスト化されている可能性があるので、更新に関しての処理を選択して下さい。

保存済み話数: #{old_subtitles_count}
更新後の話数: #{latest_subtitles_count}

      EOS

      auto_choices = Inventory.load("local_setting")["download.choices-of-digest-options"]
      auto_choices &&= auto_choices.split(",")

      loop do
        if auto_choices
          # 自動入力
          choice = auto_choices.shift || CHOICES[:default]
          puts title
          puts message
          puts self.class.choices_to_string
          puts "> #{choice}"
        else
          choice = Narou::Input.choose(title, message, CHOICES)
        end

        case choice
        when "1"
          return false
        when "2"
          return true
        when "3"
          require_relative "command/freeze" unless defined?(Command::Freeze)
          Command::Freeze.execute!(latest_toc["toc_url"])
          return true
        when "4"
          require_relative "command/backup" unless defined?(Command::Backup)
          Command::Backup.execute!(latest_toc["toc_url"])
        when "5"
          if Narou.web?
            message = "あらすじ\n#{latest_toc["story"]}\n"
          else
            puts "あらすじ"
            puts latest_toc["story"]
          end
        when "6"
          Helper.open_browser(latest_toc["toc_url"])
        when "7"
          Helper.open_directory(Downloader.get_novel_data_dir_by_target(latest_toc["toc_url"]))
        when "8"
          require_relative "command/convert" unless defined?(Command::Convert)
          Command::Convert.execute!(latest_toc["toc_url"], sync: true)
        end
        unless Narou.web?
          message = ""   # 長いので二度は表示しない
        end
      end
    else
      return false
    end
  end
  #
  # 小説を格納するためのディレクトリ名を取得する
  #
  def get_file_title
    # すでにデータベースに登録されているならそれを引き続き使うようにする
    file_title = record&.dig("file_title")
    return file_title if file_title
    ncode = @setting["ncode"]
    return ncode unless @setting["append_title_to_folder_name"]
    scrubbed_title = Helper.replace_filename_special_chars(get_title, true).strip
    Helper.truncate_folder_title("#{ncode} #{scrubbed_title}")
  end
  memoize :get_file_title
  memoize :get_novel_data_dir
  memoize :get_novel_status

  #
  # 小説のタイトルを取得する
  #
  def get_title
    return @title if @title
    @title = @setting["title"] || record["title"]
    if @setting["title_strip_pattern"]
      @title = @title.gsub(/#{@setting["title_strip_pattern"]}/, "").gsub(/^[　\s]*(.+?)[　\s]*?$/, "\\1")
    end
    @title
  end

  def get_toc_source
    toc_url = @setting["toc_url"]
    return nil unless toc_url
    max_retry = 5
    retry_count = LIMIT_TO_RETRY_NETWORK
    toc_source = ""
    cookie = @setting["cookie"] || ""
    open_uri_options = make_open_uri_options("Cookie" => cookie, allow_redirections: :safe)
    sleep_for_download
    begin
      URI.open(toc_url, open_uri_options) do |toc_fp|
        if toc_fp.base_uri.to_s != toc_url
          # リダイレクトされた場合。
          # ノクターン・ムーンライトのNコードを ncode.syosetu.com に渡すと、年齢認証のクッションページに飛ばされる
          # 転送先を取得し再度ページを取得し直す
          uri = URI.parse(toc_fp.base_uri.to_s)
          if uri.host == "nl.syosetu.com"
            decode = Hash[URI.decode_www_form(uri.query)]
            toc_url = decode["url"]   # 年齢認証確認ページからの転送先
            raise DownloaderForceRedirect
          end
          s = Downloader.get_sitesetting_by_target(toc_fp.base_uri.to_s)
          raise DownloaderNotFoundError unless s   # 非公開や削除等でトップページへリダイレクトされる場合がある
          @setting.clear   # 今まで使っていたのは一旦クリア
          @setting = s
          toc_url = @setting["toc_url"]
        end
        toc_source = Helper.restore_entity(Helper.pretreatment_source(toc_fp.read, @setting["encoding"]))
        raise DownloaderNotFoundError if Downloader.detect_error_message(@setting, toc_source)
      end
    rescue DownloaderForceRedirect
      max_retry -= 1
      if max_retry >= 0
        retry
      else
        raise
      end
    rescue OpenURI::HTTPError, Errno::ECONNRESET, Errno::ECONNABORTED, Errno::ETIMEDOUT, Net::OpenTimeout, IO::TimeoutError, SocketError => e
      case e.message
      when /^503/
        @stream&.error "server message: #{e.message}"
        display_hint if @stream
        raise SuspendDownload
      when /^404/
        # 404は上位のget_latest_table_of_contentsで処理させるため、そのまま再raise
        raise e
      else
        if retry_count == 0
          @stream&.error "上限までリトライしましたが目次がダウンロード出来ませんでした"
          raise SuspendDownload
        end
        retry_count -= 1
        @stream&.puts <<~MSG
          server message: #{e.message}
          リトライ待機中...
        MSG
        sleep(WAIT_TIME_TO_RETRY_NETWORK)
        retry
      end
    end
    toc_source
  end

  #
  # 目次データを取得する
  #
  def get_latest_table_of_contents(old_toc, through_error: false)
    toc_source = get_toc_source
    return nil unless toc_source
    @setting.multi_match(toc_source, "tcode")
    info = NovelInfo.load(@setting, toc_source: toc_source)
    if info
      raise DownloaderNotFoundError unless info["title"]
      @setting["title"] = info["title"]
      @setting["author"] = info["writer"]
      @setting["story"] = info["story"]
    else
      # 小説情報ページがないサイトの場合は目次ページから取得する
      @setting.multi_match(toc_source, "title", "author", "story")
      raise DownloaderNotFoundError unless @setting.matched?("title")
      story_html = HTML.new(@setting["story"])
      story_html.strip_decoration_tag = true
      @setting["story"] = story_html.to_aozora
    end
    @setting.multi_match(toc_source, "tags")
    @setting["info"] = info
    replace_external_properties_of_setting

    @setting["title"] = get_title
    if series_novel?
      # 連載小説
      subtitles = get_subtitles_multipage(toc_source, old_toc)
    else
      # 短編小説
      subtitles = create_short_story_subtitles(info)
    end
    @setting["subtitles"] = subtitles

    toc_objects = {
      "title" => get_title,
      "author" => @setting["author"],
      "toc_url" => @setting["toc_url"],
      "story" => @setting["story"],
      "subtitles" => subtitles
    }
    toc_objects
  rescue OpenURI::HTTPError, Errno::ECONNRESET, Errno::ECONNABORTED, Errno::ETIMEDOUT, Net::OpenTimeout, IO::TimeoutError, SocketError => e
    raise if through_error   # エラー処理はしなくていいからそのまま例外を受け取りたい時用
    if e.message.include?("404")
      @stream.error "小説が削除されているか非公開な可能性があります"
      sleep_for_download
      if database.novel_exists?(@id)
        require_relative "command/tag" unless defined?(Command::Tag)
        require_relative "command/freeze" unless defined?(Command::Freeze)
        Command::Tag.execute!(%W(#{@id} --add 404 --color white --no-overwrite-color), io: Narou::NullIO.new)
        Command::Freeze.execute!(@id, "--on")
      end
    else
      @stream.error "何らかの理由により目次が取得できませんでした(#{e.message})"
    end
    false
  end

  def get_subtitles_multipage(toc_source, old_toc)
    subtitles = []
    # 元々のURLを保存する
    toc_url_orig = @setting["toc_url"]
    # 全ページ数を得る
    @setting.multi_match(toc_source, "toc_page_max")
    toc_page_max = @setting["toc_page_max"].to_i
    # toc_page_maxが設定されていない、正規表現にマッチしない場合などでも最低限は1にする
    toc_page_max = 1 unless toc_page_max > 0
    # 5ページ以上でプログレスバーを表示する
    progressbar =  nil
    if toc_page_max >= 5
      @stream.puts "#{@setting["title"]} の目次ページを取得中..."
      progressbar = ProgressBar.new(toc_page_max, io: @stream)
    end
    ret = toc_page_max.times do |i|
      progressbar&.output(i + 1)
      subtitles.concat(get_subtitles(toc_source, old_toc))
      break unless @setting.multi_match(toc_source, "next_toc")
      # 得られたURLをセットしてページ内容を取得する
      @setting["toc_url"] = @setting["next_url"]
      toc_source = get_toc_source
    end
    progressbar&.clear
    if ret
      # 通常ならbreakでループを抜けるはず
      # breakでループを抜けなかったら例外を出す
      raise "目次ページが多すぎます"
    end
    subtitles
  ensure
    @setting["toc_url"] = toc_url_orig
  end

  def __search_index_in_subtitles(subtitles, index)
    subtitles.index { |item|
      item["index"] == index
    }
  end

  def __strdate_to_ymd(date)
    Date.parse(date.to_s.tr("年月日時分秒", "///:::")).strftime("%Y%m%d")
  end

  #
  # 本文更新チェック
  #
  # 更新された subtitle だけまとまった配列を返す
  #
  def update_body_check(old_subtitles, latest_subtitles)
    strong_update = Inventory.load("local_setting")["update.strong"]
    latest_subtitles.select do |latest|
      index = latest["index"]
      index_in_old_toc = __search_index_in_subtitles(old_subtitles, index)
      next true unless index_in_old_toc
      old = old_subtitles[index_in_old_toc]
      # タイトルチェック
      if old["subtitle"] != latest["subtitle"]
        next true
      end
      # 章チェック
      if old["chapter"] != latest["chapter"]
        next true
      end
      # 前回ダウンロードしたはずの本文ファイルが存在するか
      section_file_name = "#{index} #{old["file_subtitle"]}.yaml"
      section_file_relative_path = File.join(SECTION_SAVE_DIR_NAME, section_file_name)
      unless get_novel_data_dir.join(section_file_relative_path).exist?
        # あるはずのファイルが存在しなかったので、再ダウンロードが必要
        next true
      end
      # 更新日チェック
      # subdate : 初稿投稿日
      # subupdate : 改稿日
      old_subdate = old["subdate"]
      latest_subdate = latest["subdate"]
      old_subupdate = old["subupdate"]
      latest_subupdate = latest["subupdate"]
      # oldにsubupdateがなくても、latestのほうにsubupdateがある場合もある
      old_subupdate = old_subdate if latest_subupdate && !old_subupdate
      different_check = nil
      latest["download_time"] = old["download_time"]
      if strong_update
        latest_section_timestamp_ymd = __strdate_to_ymd(get_section_file_timestamp(old, latest))
        different_check = lambda do
          latest_info_dummy = latest.dup
          latest_info_dummy["element"] = a_section_download(latest)
          deffer = different_section?(section_file_relative_path, latest_info_dummy)
          unless deffer
            # 差分がある場合はこのあと保存されて更新されるので、差分がない場合のみ
            # タイムスタンプを更新しておく
            FileUtils.touch(get_novel_data_dir.join(section_file_relative_path))
          end
          deffer
        end
      end
      if old_subupdate && latest_subupdate
        if old_subupdate == ""
          next latest_subupdate != ""
        end
        if strong_update
          if __strdate_to_ymd(old_subupdate) == latest_section_timestamp_ymd
            next different_check.call
          end
        end
        latest_subupdate > old_subupdate
      else
        # 古いバージョンだと old_subdate が nil なので判定出来ないため
        next true unless old_subdate

        if strong_update
          if __strdate_to_ymd(old_subdate) == latest_section_timestamp_ymd
            next different_check.call
          end
        end
        latest_subdate > old_subdate
      end
    end
  end

  #
  # 対象話数のタイムスタンプを取得
  #
  def get_section_file_timestamp(old_subtitles_info, latest_subtitles_info)
    download_time = old_subtitles_info["download_time"]
    unless download_time
      download_time = File.mtime(section_file_path(old_subtitles_info))
    end
    latest_subtitles_info["download_time"] = download_time
    download_time
  end

  def title_to_filename(title)
    Helper.truncate_path(
      Helper.replace_filename_special_chars(
        HTML.new(title).delete_ruby_tag
      )
    )
  end

  #
  # 各話の情報を取得
  #
  def get_subtitles(toc_source, old_toc)
    subtitles = []
    toc_post = toc_source.dup
    old_subtitles = old_toc ? old_toc["subtitles"] : nil
    loop do
      match_data = @setting.multi_match(toc_post, "subtitles")
      break unless match_data
      toc_post = match_data.post_match
      @setting["subtitle"] = @setting["subtitle"].gsub("\t", "")
      subdate = @setting["subdate"].tap { |sd|
        # subdate(初回掲載日)がない場合、最初に取得した時のsubupdateで代用する
        # subdateが取得出来ないのは暁とArcadia
        unless sd
          old_index = old_subtitles ? __search_index_in_subtitles(old_subtitles, @setting["index"]) : nil
          if !old_index || !old_subtitles[old_index]["subdate"]
            break @setting["subupdate"]
          end
          # || 以降は subupdate を取得していない古い(2.4.0以前)toc.yamlがあるためsubdateを使う
          break old_subtitles[old_index]["subupdate"] || old_subtitles[old_index]["subdate"]
        end
      }
      subtitles << {
        "index" => @setting["index"],
        "href" => @setting["href"],
        "chapter" => @setting["chapter"].to_s,
        "subchapter" => @setting["subchapter"].to_s,
        "subtitle" => slim_subtitle(@setting["subtitle"]),
        "file_subtitle" => title_to_filename(@setting["subtitle"]),
        "subdate" => subdate,
        "subupdate" => @setting["subupdate"]
      }
    end
    subtitles
  end

  #
  # 短編用の情報を生成
  #
  def create_short_story_subtitles(info)
    subtitle = {
      "index" => "1",
      "href" => @setting.replace_group_values("href", "index" => "1"),
      "chapter" => "",
      "subtitle" => slim_subtitle(@setting["title"]),
      "file_subtitle" => title_to_filename(@setting["title"]),
      "subdate" => info["general_firstup"],
      "subupdate" => info["novelupdated_at"] || info["general_lastup"] || info["general_firstup"]
    }
    [subtitle]
  end

  def slim_subtitle(string)
    HTML.new(string).delete_ruby_tag.delete("\n")
  end

  def replace_external_properties_of_setting
    @setting["title"] = @setting["title"].delete("\r\n")
    @setting["author"] = @setting["author"].delete("\r\n")
  end
end

# ==== UTF-8 Hotfix: avoid "UTF-8 and ASCII-8BIT" clashes ====
# このブロックは downloader.rb の最下部にそのまま追記してください。
# 既存コードには手を入れず、戻り値の文字列だけを UTF-8 に正規化します。

module Narou
  module Utf8Hotfix
    module_function
    def utf8(v)
      case v
      when String
        # BINARY(ASCII-8BIT) を含む可能性があるので強制的に UTF-8 + scrub
        v.encoding == Encoding::UTF_8 ? v : v.dup.force_encoding(Encoding::UTF_8).scrub
      when Array
        v.map { |e| utf8(e) }
      when Hash
        # 値側を再帰的に正規化。キーはそのまま（シンボルや固定文字列想定）
        v.transform_values { |e| utf8(e) }
      else
        v
      end
    end
  end
end

if defined?(Narou::Downloader)
  class Narou::Downloader
    # get_latest_table_of_contents の戻り値を UTF-8 に正規化
    if method_defined?(:get_latest_table_of_contents)
      alias __orig_get_latest_table_of_contents get_latest_table_of_contents
      def get_latest_table_of_contents(*args, **kwargs, &blk)
        res = __orig_get_latest_table_of_contents(*args, **kwargs, &blk)
        Narou::Utf8Hotfix.utf8(res)
      end
    end

    # 念のため run_download の戻り値も正規化（TOC 以外の経路対策）
    if method_defined?(:run_download)
      alias __orig_run_download run_download
      def run_download(*args, **kwargs, &blk)
        res = __orig_run_download(*args, **kwargs, &blk)
        Narou::Utf8Hotfix.utf8(res)
      end
    end
  end

  private

  # 互換: 旧来の make_open_uri_options を Downloader 側で吸収
  # 呼び出し側: make_open_uri_options("Cookie" => cookie, allow_redirections: :safe)
  def make_open_uri_options(headers = {}, allow_redirections: :safe)
    if defined?(Helper) && Helper.respond_to?(:make_open_uri_options)
      return Helper.make_open_uri_options(headers, allow_redirections: allow_redirections)
    end
    # 最低限のフォールバック
    opts = { allow_redirections: allow_redirections }
    headers.each { |k, v| opts[k] = v }
    opts
  end

end
# ==== /UTF-8 Hotfix ====
