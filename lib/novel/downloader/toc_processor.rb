# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

class Downloader
  #
  # TOC (Table of Contents) 処理を担当するモジュール
  #
  # 目次の取得、パース、サブタイトル抽出、更新チェックなど
  # 目次関連の全処理を集約
  #
  module TocProcessor
    #
    # 目次ソースを取得
    #
    # リダイレクト処理、エラーハンドリング、リトライロジックを含む
    #
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
        URI(toc_url).open(open_uri_options) do |toc_fp|
          if toc_fp.base_uri.to_s != toc_url
            # リダイレクトされた場合。
            # ノクターン・ムーンライトのNコードを ncode.syosetu.com に渡すと、年齢認証のクッションページに飛ばされる
            # 転送先を取得し再度ページを取得し直す
            uri = URI.parse(toc_fp.base_uri.to_s)
            if uri.host == "nl.syosetu.com"
              decode = Hash[URI.decode_www_form(uri.query)]
              toc_url = decode["url"] # 年齢認証確認ページからの転送先
              raise DownloaderForceRedirect
            end
            s = Downloader.get_sitesetting_by_target(toc_fp.base_uri.to_s)
            raise DownloaderNotFoundError unless s # 非公開や削除等でトップページへリダイレクトされる場合がある
            @setting.clear # 今まで使っていたのは一旦クリア
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
      rescue OpenURI::HTTPError, Errno::ECONNRESET, Errno::ECONNABORTED, Errno::ETIMEDOUT, Net::OpenTimeout, IO::TimeoutError,
SocketError => e
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
    rescue OpenURI::HTTPError, Errno::ECONNRESET, Errno::ECONNABORTED, Errno::ETIMEDOUT, Net::OpenTimeout, IO::TimeoutError,
SocketError => e
      raise if through_error # エラー処理はしなくていいからそのまま例外を受け取りたい時用
      if e.message.include?("404")
        @stream.error "小説が削除されているか非公開な可能性があります"
        sleep_for_download
        if database.novel_exists?(@id)
          require "cli/command/tag" unless defined?(Command::Tag)
          require "cli/command/freeze" unless defined?(Command::Freeze)
          Command::Tag.execute!(%W(#{@id} --add 404 --color white --no-overwrite-color), io: Narou::NullIO.new)
          Command::Freeze.execute!(@id, "--on")
        end
      else
        @stream.error "何らかの理由により目次が取得できませんでした(#{e.message})"
      end
      false
    end

    #
    # 複数ページにわたる目次からサブタイトルを取得
    #
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

    #
    # サブタイトル配列からインデックスを検索
    #
    def __search_index_in_subtitles(subtitles, index)
      subtitles.index { |item|
        item["index"] == index
      }
    end

    #
    # 日付文字列をYYYYMMDD形式に変換
    #
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

    #
    # タイトルをファイル名として使える形式に変換
    #
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

    #
    # サブタイトルから余分な文字を削除
    #
    def slim_subtitle(string)
      HTML.new(string).delete_ruby_tag.delete("\n")
    end
  end
end
