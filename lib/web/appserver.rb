# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

# rubocop:disable Metrics/ClassLength
# rubocop:disable Style/ClassAndModuleChildren

require "socket"
require "sinatra/base"
require "sinatra/json"
require "sinatra/reloader" if $development
require "securerandom"
require "rack/session"
require "rack/protection"
# require "better_errors" if $debug
require "tilt/erubi"
require "tilt/haml"
require "tilt/sass"
require_relative "../commandline"
require_relative "../inventory"
require_relative "web_worker"
require_relative "pushserver"
require_relative "settingmessages"
require_relative "server_helpers"
require_relative "../narou/promo_tag_extractor"
require_relative "../narou/system_updater"

class Narou::AppServer < Sinatra::Base
  register Sinatra::Reloader if $development
  helpers Narou::ServerHelpers

  @@request_reboot = false
  @@already_update_system = false
  @@gem_update_last_log = ""

  configure do
    set :app_file, __FILE__
    set :erb, trim: "-"
    set :quiet, true
    enable :protection
    enable :sessions

    set(:version) do
      Command::Version.create_version_string
    end

    set :environment, :production unless $development
    set :server, :puma
    set :server_settings, { Silent: true }

    if $debug
      use BetterErrors::Middleware
      BetterErrors.application_root = Narou.script_dir
    end
  end

  def self.push_server=(server)
    @@push_server = server
  end

  def self.push_server
    @@push_server
  end

  def self.request_reboot
    @@request_reboot = true
  end

  def self.request_reboot?
    @@request_reboot
  end

  #
  # サーバのアドレスを生成
  #
  # portは初回起動時にランダムで設定する。次回からは同じ設定を引き継ぐ。
  # bindは自分で設定する場合は narou s server-bind=address で行う。
  # bindは設定しなかった場合は起動したPCのプライベートIPアドレスが設定される。
  # この場合はLAN内からアクセス出来る。
  # bindがlocalhostの場合は実際には127.0.0.1で処理される。(起動したPCでしかアクセス出来ない)
  # 0.0.0.0 はDocker利用時しか許容しない。 
  #
  def self.create_address(user_port = nil)
    global_setting = Inventory.load("global_setting", :global)
    port, bind = global_setting["server-port"], global_setting["server-bind"]
    port = user_port if user_port
    ipaddress = my_ipaddress

    # portが未設定なら乱数で決定
    unless port
      port = rand(4000..65000)
      global_setting["server-port"] = port
      global_setting.save
    end

    # Docker以外では 0.0.0.0 を禁止
    if bind == "0.0.0.0" && !Helper.in_docker?
      warn "[WARN] server-bind=0.0.0.0 is not allowed outside Docker. Forcing 127.0.0.1"
      bind = "127.0.0.1"
    end

    # localhost は内部的に 127.0.0.1 扱いにしておく（任意）
    # bind = "127.0.0.1" if bind == "localhost"
    host = bind ? bind : ipaddress
    set :port, port
    set :bind, host
    {
      host: host,
      port: port
    }
  end

  #
  # 自分のIPアドレス取得
  #
  # 参考：http://qiita.com/saltheads/items/cc49fcf2af37cb277c4f
  #
  def self.my_ipaddress
    @@__ipaddress ||= -> {
      udp = UDPSocket.new
      begin
        # 128.0.0.0 への送信に使用されるNICのアドレスを取得
        udp.connect("128.0.0.0", 7)
        Socket.unpack_sockaddr_in(udp.getsockname)[1]
      rescue Errno::ENETUNREACH
        # 128.0.0.0 へのルーティングがないとき
        "127.0.0.1"
      ensure
        udp.close
      end
    }.call
  end

  def initialize
    super
    puts_hello_messages
    start_device_ejectable_event
    fill_general_all_no_in_database
    setup_server_authentication
  end

  def puts_hello_messages
    puts "<white>Narou.rb MOD version #{Narou::VERSION}</white>".termcolor
  end

  def start_device_ejectable_event
    return unless Device.support_eject?
    Thread.new do
      loop do
        if @@push_server.connections.count > 0
          device = Narou.get_device
          @@push_server.send_all(:"device.ejectable" => device && device.ejectable?)
        end

        sleep 2
      end
    end
  end

  def general_all_no_by_toc(id)
    toc = Downloader.new(id).load_toc_file
    return nil unless toc
    toc["subtitles"].size
  rescue Downloader::InvalidTarget
    nil
  end

  # 話数の設定されていない小説の話数を取得して埋める
  def fill_general_all_no_in_database
    modified = false
    Database.instance.each do |id, data|
      next if data["general_all_no"]
      data["general_all_no"] = general_all_no_by_toc(id)
      modified = true
    end
    Database.instance.save_database if modified
  end

  # サーバーの認証の設定
  # - Digest認証がRackの機能からオミットされたので、Basic認証に変更
  def setup_server_authentication
    auth = Inventory.load("global_setting", :global).group("server-basic-auth")
    user = auth.user
    passwd = auth.password  # ハッシュは使わない

    return unless auth.enable && user && passwd

    self.class.class_exec do
      use Rack::Auth::Basic, "narou.rb MOD" do |username, password|
        username == user && password == passwd
      end
    end
  end

  # ===================================================================
  # ルーティング
  # ===================================================================

  before do
    headers "Cache-Control" => "no-cache" if $development
    @bootstrap_theme = case params["webui.theme"]
                       when nil
                         Narou.theme
                       when ""   # 環境設定画面で未設定が選択された時
                         nil
                       else
                         params["webui.theme"]
                       end
    Narou::WebWorker.push_as_system_worker do
      Inventory.clear
      Database.instance.refresh
      Narou.load_global_replace_pattern
    end
  end

  get "/" do
    setting = Inventory.load("server_setting", :global)
    @is_first_access = !setting["already-accessed"]
    if @is_first_access
      setting["already-accessed"] = true
      setting.save
    end
    haml :index, layout: true
  end

  get "/style.css" do
    scss :style
  end

  before "/settings" do
    @title = "環境設定"
    @setting_variables = Command::Setting.get_setting_variables
    @error_list = {}
    @global_replace_pattern = @replace_pattern = Narou.global_replace_pattern
  end

  post "/settings" do
    built_arguments = []
    device = params.delete("device")
    [:local, :global].each do |scope|
      @setting_variables[scope].each do |name, info|
        param_data = params[name]
        argument = ""
        if info[:type] == :boolean
          # :boolean 用のフォームデータは on, off, nil で渡される。
          # ただしチェックボックスはチェックした時だけ on が渡されるので、
          # 何もデータが無い＝off を選択したと判断する。
          # 隠しデータの場合は hidden として on, off, nil が必ず送信されるので、
          # それで判断できる。
          if param_data
            argument = convert_on_off_to_boolean(param_data).to_s
          else
            argument = "false"
          end
        elsif param_data.kind_of?(Array)
          argument = param_data.join(",")
        else
          argument = param_data
        end
        built_arguments << "#{name}=#{argument}"
      end
    end
    # device の項目だけ関連項目を変更するという挙動をするため、変更を上書き
    # されないように最後にまわす
    built_arguments << "device=#{device}" if device
    unless built_arguments.empty?
      setting = Command::Setting.new
      setting.on(:error) do |msg, name|
        if name
          @error_list[name] = msg
        end
      end
      setting.execute!(built_arguments, io: Narou::NullIO.new)
      Inventory.clear
      
      # 自動アップデート設定が変更された場合、スケジューラーを再起動
      if built_arguments.any? { |arg| arg.start_with?("update.auto-schedule") }
        require_relative "../command/update/scheduler"
        Command::Update::Scheduler.stop
        Command::Update::Scheduler.start
      end
    end

    # 置換設定保存
    params_replace_pattern = params["replace_pattern"]
    @global_replace_pattern.clear
    if params_replace_pattern.kind_of?(Array)
      params_replace_pattern.each do |pattern|
        left, right = pattern["left"].strip, pattern["right"].strip
        next if left == ""
        @global_replace_pattern << [left, right]
      end
    end
    Narou.save_global_replace_pattern

    if @error_list.empty?
      session[:alert] = [ "保存が完了しました", "success" ]
    else
      session[:alert] = [ "#{@error_list.size}個の設定にエラーがありました", "danger" ]
    end
    redirect to "/settings"
  end

  get "/settings" do
    haml :settings
  end

  get "/help" do
    @title = "ヘルプ"
    haml :help
  end

  get "/about" do
    @narourb_version = settings.version
    @ruby_version = build_ruby_version
    haml :_about, layout: false
  end

  post "/shutdown" do
    self.class.quit!
    "シャットダウンしました。再起動するまで操作は出来ません"
  end

  post "/reboot" do
    self.class.request_reboot
    self.class.quit!
    haml :_rebooting, layout: false
  end

  post "/update_system" do
    Thread.new do
      begin
        result = Narou::SystemUpdater.update_from_github
        @@gem_update_last_log = result.log

        case result.status
        when :success
          @@already_update_system = true
          @@push_server.send_all("server.update.success" => result.log)
        when :nothing
          @@push_server.send_all("server.update.nothing" => result.log)
        else
          @@push_server.send_all("server.update.failure" => result.log)
        end
      rescue Narou::SystemUpdater::Error => e
        log = "更新に失敗しました: #{e.message}"
        @@gem_update_last_log = log
        @@push_server.send_all("server.update.failure" => log)
      rescue StandardError => e
        log = <<~LOG.strip
          予期しないエラーが発生しました: #{e.class} #{e.message}
          #{Array(e.backtrace).join("\n")}
        LOG
        @@gem_update_last_log = log
        @@push_server.send_all("server.update.failure" => log)
      end
    end
  end

  post "/gem_update_last_log" do
    content_type "text/plain"
    @@gem_update_last_log
  end

  post "/check_already_update_system" do
    json({ result: @@already_update_system })
  end

  before "/novels/:id/*" do
    @id = params[:id]
    not_found unless @id =~ /^\d+$/
    @data = Downloader.get_data_by_target(@id)
    not_found unless @data
  end

  before "/novels/:id/setting" do
    @novel_title = @data["title"]
    @title = "小説の変換設定 - #{h @novel_title}"
    @setting_variables = []
    @error_list = {}
    @novel_setting = NovelSetting.new(@id, true, true)    # 空っぽの設定を作成
    @novel_setting.settings = @novel_setting.load_setting_ini["global"]
    @original_settings = NovelSetting.get_original_settings
    @force_settings = NovelSetting.load_force_settings
    @default_settings = NovelSetting.load_default_settings
    @replace_pattern = @novel_setting.load_replace_pattern
  end

  post "/novels/:id/setting" do
    # 変換設定保存
    @original_settings.each do |info|
      name, type = info[:name], info[:type]
      param_data = params[name]
      value = nil
      begin
        if type == :boolean
          if param_data
            value = convert_on_off_to_boolean(param_data)
          else
            value = false
          end
        elsif param_data.kind_of?(Array)
          value = param_data.join(",")
        else
          if param_data.strip != ""
            value = Helper.string_cast_to_type(param_data, type)
          end
        end
        @novel_setting[name] = value
      rescue Helper::InvalidVariableType => e
        @error_list[name] = e.message
      end
    end
    @novel_setting.save_settings

    # 置換設定保存
    params_replace_pattern = params["replace_pattern"]
    @novel_setting.replace_pattern.clear
    if params_replace_pattern.kind_of?(Array)
      params_replace_pattern.each do |pattern|
        left, right = pattern["left"].strip, pattern["right"].strip
        next if left == ""
        @novel_setting.replace_pattern << [left, right]
      end
    end
    @novel_setting.save_replace_pattern

    if @error_list.empty?
      session[:alert] = [ "保存が完了しました", "success" ]
    else
      session[:alert] = [ "#{@error_list.size}個の設定にエラーがありました", "danger" ]
    end

    haml :"novels/setting"
  end

  get "/novels/:id/setting" do
    haml :"novels/setting"
  end

  get "/novels/:id/download" do
    device = Narou.get_device
    ext = device ? device.ebook_file_ext : ".epub"
    paths = Narou.get_ebook_file_paths(@id, ext)
    if !paths.empty? && File.exist?(paths[0])
      send_file(paths[0], filename: File.basename(paths[0]), type: "application/octet-stream")
    else
      not_found
    end
  end

  get "/novels/:id/author_comments" do
    downloader = Downloader.new(@id)
    toc = downloader.load_toc_file
    @comments = []
    introductions_count = 0
    postscripts_count = 0
    toc["subtitles"].each do |sub|
      begin
        section_path = downloader.section_file_path(sub)
        begin
          element = YAML.unsafe_load_file(section_path)["element"]
        rescue SystemCallError
          # bootsnap on Windows can raise Errno::E01 errors, fallback to standard YAML
          element = YAML.unsafe_load(File.read(section_path))["element"]
        end
        data_type = element["data_type"] || "text"
        introduction = element["introduction"] || ""
        postscript = element["postscript"] || ""
        if data_type == "html"
          html = HTML.new
          html.strip_decoration_tag = true
          html.string = introduction
          introduction = html.to_aozora
          html.string = postscript
          postscript = html.to_aozora
        end
        @comments.push(
          sub: sub,
          introduction: introduction,
          postscript: postscript
        )
        introductions_count += 1 unless introduction.empty?
        postscripts_count += 1 unless postscript.empty?
      rescue Errno::ENOENT
      end
    end
    total = toc["subtitles"].count.to_f
    @introductions_ratio = (introductions_count / total * 100).round(2)
    @postscripts_ratio = (postscripts_count / total * 100).round(2)
    haml :"novels/author_comments"
  end

  get "/notepad" do
    @title = "メモ帳"
    haml :notepad
  end

  get "/edit_menu" do
    @title = "個別メニューの編集"
    haml :edit_menu
  end

  not_found do
    existing_body = Array(response.body).join
    if response.content_type == "application/json" && existing_body && !existing_body.empty?
      existing_body
    else
      "not found"
    end
  end

  # -------------------------------------------------------------------------------
  # API's
  # -------------------------------------------------------------------------------

  # 小説一覧APIのキャッシュ機能
  @@api_list_cache = {}
  @@api_list_cache_time = nil
  @@api_list_cache_duration = 10 # 10秒キャッシュ

  # 処理用完全IDキャッシュシステム
  @@full_sorted_ids_cache = {}
  @@full_ids_cache_time = nil
  @@full_ids_cache_duration = 10 # 10秒キャッシュ

  # API一覧のキャッシュを無効化する
  def self.clear_api_list_cache
    @@api_list_cache = {}
    @@api_list_cache_time = nil
  end

  # 処理用完全IDキャッシュを無効化する
  def self.clear_full_ids_cache
    @@full_sorted_ids_cache = {}
    @@full_ids_cache_time = nil
  end

  # 全キャッシュを無効化する
  def self.clear_all_cache
    clear_api_list_cache
    clear_full_ids_cache
  end

  # 小説総数を取得するAPI
  get "/api/novels/count" do
    json({ count: Database.instance.get_object.size })
  end

  # フィルター条件に一致する全小説IDを取得
  get "/api/novels/all_ids" do
    begin
      debug_puts "[DEBUG] /api/novels/all_ids called with params: #{params.inspect}"
      all_ids = get_all_filtered_novel_ids(params)
      debug_puts "[DEBUG] Retrieved #{all_ids.length} IDs: #{all_ids.inspect}"
      json({ ids: all_ids })
    rescue StandardError => e
      puts "[ERROR] /api/novels/all_ids error: #{e.message}"
      puts e.backtrace.join("\n")
      status 500
      json({ error: e.message })
    end
  end

  # フィルター条件に一致する全小説IDを取得する共通メソッド
  def get_all_filtered_novel_ids(params)
    view_frozen = query_to_boolean(params["view_frozen"], default: true)
    view_nonfrozen = query_to_boolean(params["view_nonfrozen"], default: true)
    
    # 検索パラメータの安全な取得
    search_value = nil
    if params["search"] && params["search"].is_a?(Hash)
      search_value = params["search"]["value"]
    elsif params["search[value]"]
      search_value = params["search[value]"]
    end
    
    # フィルタ文字列の取得
    url_filter = params["filter"]
    combined_filter = [search_value, url_filter].compact.reject(&:empty?).join(" ")
    
    # データベースから全データを取得
    database_values = Database.instance.get_object.values
    debug_puts "[DEBUG] Database values count: #{database_values.length}"
    filtered_data = database_values.map do |data|
      id = data["id"]
      debug_puts "[DEBUG] Processing novel ID: #{id} (#{id.class})"
      is_frozen = Narou.novel_frozen?(id)
      tags = data["tags"] || []
      
      {
        id: id.to_i,  # 数値として保持
        title: data["title"],
        author: data["author"],
        sitename: data["sitename"],
        status: data["status"],
        frozen: is_frozen,
        raw_tags: tags
      }
    end
    
    # 凍結状態でフィルタリング
    unless view_frozen && view_nonfrozen
      filtered_data = filtered_data.select do |item|
        if view_frozen && !view_nonfrozen
          item[:frozen]
        elsif !view_frozen && view_nonfrozen
          !item[:frozen]
        else
          true
        end
      end
    end
    
    # 検索フィルタリング
    if combined_filter && !combined_filter.strip.empty?
      begin
        # フィルタ文字列を単語に分割
        filter_words = combined_filter.split(/\s+/)
        
        filtered_data = filtered_data.select do |item|
          filter_words.all? do |word|
            if word.match(/^([-^]?)tag:(.+)$/i)
              # タグフィルタリング（OR検索対応）
              exclude_flag = $1
              tag_names_part = $2.downcase
              
              # パイプ（|）でOR検索をサポート
              tag_names = tag_names_part.split('|').map(&:strip)
              
              if tag_names.size > 1
                # OR検索: いずれかのタグにマッチすればOK
                has_any_tag = tag_names.any? do |tag_name|
                  item[:raw_tags].any? { |tag| tag.downcase.include?(tag_name) }
                end
                
                case exclude_flag
                when "-", "^"
                  !has_any_tag  # いずれのタグも持たない
                else
                  has_any_tag   # いずれかのタグを持つ
                end
              else
                # 単一タグの従来処理
                tag_name = tag_names.first
                has_tag = item[:raw_tags].any? { |tag| tag.downcase.include?(tag_name) }
                
                case exclude_flag
                when "-", "^"
                  !has_tag  # 除外
                else
                  has_tag   # 包含
                end
              end
            else
              # 通常の検索フィルタリング
              search_regex = Regexp.new(Regexp.escape(word), Regexp::IGNORECASE)
              item[:title_plain].to_s.match?(search_regex) || 
              item[:author_plain].to_s.match?(search_regex) ||
              item[:sitename].to_s.match?(search_regex) ||
              item[:status].to_s.match?(search_regex) ||
              item[:promo_tags].any? { |tag| tag.match?(search_regex) } ||
              item[:raw_tags].any? { |tag| tag.match?(search_regex) }
            end
          end
        end
      rescue StandardError => e
        # エラーの場合はフィルターを適用せずに続行
      end
    end
    
    # IDのみを抽出して返す
    result_ids = filtered_data.map { |item| item[:id] }
    debug_puts "[DEBUG] Final result IDs: #{result_ids.inspect}"
    result_ids
  end

  # 小説一覧処理の共通メソッド
  def process_novel_list_request(params)
    view_frozen = query_to_boolean(params["view_frozen"], default: true)
    view_nonfrozen = query_to_boolean(params["view_nonfrozen"], default: true)
  
    # DataTablesのサーバーサイド処理パラメータ
    draw = params["draw"].to_i
    start = params["start"].to_i || 0
    length = params["length"].to_i || 50
    
    # 検索パラメータの安全な取得
    search_value = nil
    if params["search"] && params["search"].is_a?(Hash)
      search_value = params["search"]["value"]
    elsif params["search[value]"]
      search_value = params["search[value]"]
    end
    
    # フィルタパラメータの取得（タグフィルタリング含む）
    filter_value = params["filter"]
    
    # ソートパラメータの安全な取得
    order_column = nil
    order_dir = nil
    if params["order"] && params["order"].is_a?(Hash) && params["order"]["0"]
      order_column = params["order"]["0"]["column"].to_i
      order_dir = params["order"]["0"]["dir"]
    elsif params["order[0][column]"] && params["order[0][dir]"]
      order_column = params["order[0][column]"].to_i
      order_dir = params["order[0][dir]"]
    end
    
    # ソート状態をサーバー側に保存
    if order_column && order_dir
      debug_puts "[DEBUG] Saving sort state: column=#{order_column}, dir=#{order_dir}"
      server_setting = Inventory.load("server_setting", :global)
      server_setting["current_sort"] = {
        "column" => order_column,
        "dir" => order_dir
      }
      begin
        server_setting.save
        debug_puts "[DEBUG] Sort state saved successfully"
      rescue => e
        debug_puts "[DEBUG] Failed to save sort state: #{e.message}"
        # ソート状態の保存に失敗してもリクエスト処理は継続
      end
    else
      debug_puts "[DEBUG] No sort parameters to save: column=#{order_column}, dir=#{order_dir}"
    end
    
    # 軽量なタグ処理モード（大量データ用）
    lightweight_mode = params["lightweight"] == "true"
    
    # キャッシュチェック（軽量データも分けてキャッシュ）
    cache_key = lightweight_mode ? :lightweight : :full
    current_time = Time.now
    if @@api_list_cache && @@api_list_cache[cache_key] && @@api_list_cache_time && 
       (current_time - @@api_list_cache_time) < @@api_list_cache_duration
      cached_data = @@api_list_cache[cache_key]
    else
      # キャッシュが無い場合は新規作成
      database = Database.instance
      database_values = database.get_object.values
      database_modified = false

      cached_data = database_values.map do |data|
        entry_modified = Narou::PromoTagExtractor.normalize_entry!(data)
        database_modified ||= entry_modified

        id = data["id"]
        is_frozen = Narou.novel_frozen?(id)
        tags = data["tags"] || []
        promo_tags = data["promo_tags"].is_a?(Array) ? data["promo_tags"] : []
        promo_tags_title = data["promo_tags_title"].is_a?(Array) ? data["promo_tags_title"] : []
        promo_tags_author = data["promo_tags_author"].is_a?(Array) ? data["promo_tags_author"] : []
        author_url = data["author_url"]

        # 軽量モードではタグ処理を簡素化（表示のみ）
        tags_html = if lightweight_mode
                      if tags.empty?
                        ""
                      else
                        # 軽量表示だが、data-tag属性は保持
                        visible_tags = tags.first(3)
                        hidden_count = tags.size > 3 ? tags.size - 3 : 0

                        tag_spans = visible_tags.map { |tag| %!<span class="tag-simple" data-tag="#{tag}">#{tag}</span>! }
                        result = tag_spans.join(", ")

                        if hidden_count > 0
                          result += %! <span class="tag-more">... (+#{hidden_count}個)</span>!
                        end

                        # 隠されたタグもdata-tag属性として保持（検索用）
                        if tags.size > 3
                          hidden_tags = tags[3..-1]
                          hidden_spans = hidden_tags.map { |tag| %!<span class="tag-hidden" data-tag="#{tag}" style="display:none;"></span>! }
                          result += hidden_spans.join
                        end

                        result + %!&nbsp;<span class="tag tag-reset label label-white" data-tag="" data-toggle="tooltip" title="タグ検索を解除">&nbsp;</span>!
                      end
                    else
                      if tags.empty?
                        ""
                      else
                        %!#{decorate_tags(tags)}&nbsp;<span class="tag tag-reset label label-white"! +
                        %!data-tag="" data-toggle="tooltip" title="タグ検索を解除">&nbsp;</span>!
                      end
                    end

        title_text = data["title"].to_s
        author_text = data["author"].to_s

        {
          id: id,
          last_update: data["last_update"].to_i,
          title: title_text,
          title_plain: title_text,
          author: h(author_text),
          author_plain: author_text,
          sitename: data["sitename"],
          toc_url: data["toc_url"],
          novel_type: data["novel_type"] == 2 ? "短編" : "連載",
          tags: tags_html,
          raw_tags: tags,  # 生のタグ配列も追加（JavaScript側での直接アクセス用）
          status: [
            is_frozen ? "凍結" : nil,
            tags.include?("end") ? "完結" : nil,
            tags.include?("404") ? "削除" : nil,
            data["suspend"] ? "中断" : nil
          ].compact.join(", "),
          promo_tags: promo_tags,
          promo_tags_title: promo_tags_title,
          promo_tags_author: promo_tags_author,
          promo_tags_text: promo_tags.join(" "),
          author_url: author_url,
          actions: nil,
          frozen: is_frozen,
          new_arrivals_date: data["new_arrivals_date"].tap { |m| break m.to_i if m },
          general_lastup: data["general_lastup"].tap { |m| break m.to_i if m },
          general_all_no: data["general_all_no"],
          last_check_date: data["last_check_date"].tap { |m| break m.to_i if m },
          length: data["length"],
        }
      end

      database.save_database if database_modified

      # キャッシュを更新
      @@api_list_cache ||= {}
      @@api_list_cache[cache_key] = cached_data
      @@api_list_cache_time = current_time
    end

    # フィルタリング
    filtered_data = cached_data.select do |item|
      (view_frozen || !item[:frozen]) && (view_nonfrozen || item[:frozen])
    end
    
    # フィルタ処理（タグフィルタリング含む）
    combined_filter = [filter_value, search_value].compact.join(" ").strip
    
    if !combined_filter.empty?
      begin
        # フィルタ文字列を単語に分割
        filter_words = combined_filter.split(/\s+/)
        
        filtered_data = filtered_data.select do |item|
          filter_words.all? do |word|
            if word.match(/^([-^]?)tag:(.+)$/i)
              # タグフィルタリング（OR検索対応）
              exclude_flag = $1
              tag_names_part = $2.downcase
              
              # パイプ（|）でOR検索をサポート
              tag_names = tag_names_part.split('|').map(&:strip)
              
              if tag_names.size > 1
                # OR検索: いずれかのタグにマッチすればOK
                has_any_tag = tag_names.any? do |tag_name|
                  item[:raw_tags].any? { |tag| tag.downcase.include?(tag_name) }
                end
                
                case exclude_flag
                when "-", "^"
                  !has_any_tag  # いずれのタグも持たない
                else
                  has_any_tag   # いずれかのタグを持つ
                end
              else
                # 単一タグの従来処理
                tag_name = tag_names.first
                has_tag = item[:raw_tags].any? { |tag| tag.downcase.include?(tag_name) }
                
                case exclude_flag
                when "-", "^"
                  !has_tag  # 除外
                else
                  has_tag   # 包含
                end
              end
            else
              # 通常の検索フィルタリング
              search_regex = Regexp.new(Regexp.escape(word), Regexp::IGNORECASE)
              item[:title].to_s.match?(search_regex) || 
              item[:author].to_s.match?(search_regex) ||
              item[:sitename].to_s.match?(search_regex) ||
              item[:status].to_s.match?(search_regex) ||
              item[:raw_tags].any? { |tag| tag.match?(search_regex) }
            end
          end
        end
      rescue StandardError => e
        # フィルタエラーの場合はフィルタリングをスキップ
        puts "Filter error: #{e.message}"
      end
    end
    
    records_total = cached_data.size
    records_filtered = filtered_data.size
    
    # ソート処理
    if order_column && order_dir
      column_names = [
        "id", "last_update", "general_lastup", "last_check_date",
        "title", "author", "sitename", "novel_type",
        "tags", "general_all_no", "length", "average_length",
        "status", "actions", "frozen", "new_arrivals_date"
      ]
      sort_column = column_names[order_column]
      if sort_column
        filtered_data.sort! do |a, b|
          val_a = a[sort_column.to_sym] || 0
          val_b = b[sort_column.to_sym] || 0
          
          if val_a.is_a?(Numeric) && val_b.is_a?(Numeric)
            comparison = val_a <=> val_b
          else
            comparison = val_a.to_s <=> val_b.to_s
          end
          
          order_dir == "desc" ? -comparison : comparison
        end
      end
    end
    
    # ページネーション
    if length > 0 && length != -1
      paginated_data = filtered_data[start, length] || []
    else
      # "Show All" の場合 (length == -1) は全てのデータを返す
      # データ量に応じて段階的な制限を適用
      total_count = filtered_data.size
      if total_count <= 1000
        # 1000件以下なら全て表示
        paginated_data = filtered_data
      elsif total_count <= 5000
        # 5000件以下なら軽量モードを強制
        lightweight_mode = true
        paginated_data = filtered_data
      else
        # 5000件を超える場合は最大件数を制限
        max_show_all = 5000
        paginated_data = filtered_data.first(max_show_all)
        # レスポンスに制限情報を追加
        return {
          draw: draw,
          data: paginated_data,
          recordsTotal: records_total,
          recordsFiltered: records_filtered,
          warning: "表示件数が多いため、最初の#{max_show_all}件のみ表示しています。"
        }
      end
    end
    
    {
      draw: draw,
      data: paginated_data,
      recordsTotal: records_total,
      recordsFiltered: records_filtered
    }
  end

  # 処理用の完全ソート済IDリストを取得する
  def get_full_sorted_ids(params = {})
    debug_puts "[DEBUG] get_full_sorted_ids called with params: #{params.inspect}"
    
    # キャッシュキーの生成（フィルター・ソート条件に基づく）
    server_setting = Inventory.load("server_setting", :global)
    current_sort = server_setting["current_sort"] || { "column" => 0, "dir" => "asc" }
    
    cache_key = {
      filter: params["filter"],
      search: params["search"],
      view_frozen: params["view_frozen"],
      view_nonfrozen: params["view_nonfrozen"],
      sort: current_sort
    }.to_s.hash
    
    current_time = Time.now
    
    # キャッシュチェック
    if @@full_sorted_ids_cache[cache_key] && @@full_ids_cache_time && 
       (current_time - @@full_ids_cache_time) < @@full_ids_cache_duration
      debug_puts "[DEBUG] Using cached full sorted IDs: #{@@full_sorted_ids_cache[cache_key].length} items"
      return @@full_sorted_ids_cache[cache_key]
    end
    
    debug_puts "[DEBUG] Generating new full sorted IDs"
    
    # process_novel_list_requestと同じフィルタリング・ソート処理（ページング無し）
    view_frozen = query_to_boolean(params["view_frozen"], default: true)
    view_nonfrozen = query_to_boolean(params["view_nonfrozen"], default: true)
    
    # 検索パラメータの取得
    search_value = nil
    if params["search"] && params["search"].is_a?(Hash)
      search_value = params["search"]["value"]
    elsif params["search[value]"]
      search_value = params["search[value]"]
    end
    
    filter_value = params["filter"]
    
    # キャッシュされたデータを使用（軽量モードは使わない）
    cache_key_api = :full
    if @@api_list_cache && @@api_list_cache[cache_key_api] && @@api_list_cache_time && 
       (current_time - @@api_list_cache_time) < @@api_list_cache_duration
      cached_data = @@api_list_cache[cache_key_api]
    else
      # APIキャッシュが無い場合は新規作成
      database_values = Database.instance.get_object.values
      cached_data = database_values.map do |data|
        id = data["id"]
        is_frozen = Narou.novel_frozen?(id)
        tags = data["tags"] || []
        tags_html = if tags.empty?
                      ""
                    else
                      %!#{decorate_tags(tags)}&nbsp;<span class="tag tag-reset label label-white"! +
                      %!data-tag="" data-toggle="tooltip" title="タグ検索を解除">&nbsp;</span>!
                    end
        
        {
          id: id,
          last_update: data["last_update"].to_i,
          title: h(data["title"]),
          author: h(data["author"]),
          sitename: data["sitename"],
          toc_url: data["toc_url"],
          novel_type: data["novel_type"] == 2 ? "短編" : "連載",
          tags: tags_html,
          raw_tags: tags,
          status: [
            is_frozen ? "凍結" : nil,
            tags.include?("end") ? "完結" : nil,
            tags.include?("404") ? "削除" : nil,
            data["suspend"] ? "中断" : nil
          ].compact.join(", "),
          download: %!<a href="/novels/#{id}/download" class="btn btn-default btn-xs"><span class="glyphicon glyphicon-download-alt"></span></a>!,
          frozen: is_frozen,
          new_arrivals_date: data["new_arrivals_date"].tap { |m| break m.to_i if m },
          general_lastup: data["general_lastup"].tap { |m| break m.to_i if m },
          general_all_no: data["general_all_no"],
          last_check_date: data["last_check_date"].tap { |m| break m.to_i if m },
          length: data["length"],
        }
      end
      
      # APIキャッシュも更新
      @@api_list_cache ||= {}
      @@api_list_cache[cache_key_api] = cached_data
      @@api_list_cache_time = current_time
    end
    
    # フィルタリング（process_novel_list_requestと同じ）
    filtered_data = cached_data.select do |item|
      (view_frozen || !item[:frozen]) && (view_nonfrozen || item[:frozen])
    end
    
    # フィルタ処理
    combined_filter = [filter_value, search_value].compact.join(" ").strip
    
    if !combined_filter.empty?
      begin
        filter_words = combined_filter.split(/\s+/)
        
        filtered_data = filtered_data.select do |item|
          filter_words.all? do |word|
            if word.match(/^([-^]?)tag:(.+)$/i)
              exclude_flag = $1
              tag_names_part = $2.downcase
              tag_names = tag_names_part.split('|').map(&:strip)
              
              if tag_names.size > 1
                has_any_tag = tag_names.any? do |tag_name|
                  item[:raw_tags].any? { |tag| tag.downcase.include?(tag_name) }
                end
                
                case exclude_flag
                when "-", "^"
                  !has_any_tag
                else
                  has_any_tag
                end
              else
                tag_name = tag_names.first
                has_tag = item[:raw_tags].any? { |tag| tag.downcase.include?(tag_name) }
                
                case exclude_flag
                when "-", "^"
                  !has_tag
                else
                  has_tag
                end
              end
            else
              search_regex = Regexp.new(Regexp.escape(word), Regexp::IGNORECASE)
              item[:title].to_s.match?(search_regex) || 
              item[:author].to_s.match?(search_regex) ||
              item[:sitename].to_s.match?(search_regex) ||
              item[:status].to_s.match?(search_regex) ||
              item[:raw_tags].any? { |tag| tag.match?(search_regex) }
            end
          end
        end
      rescue StandardError => e
        puts "Filter error in get_full_sorted_ids: #{e.message}"
      end
    end
    
    # ソート処理（process_novel_list_requestと同じ）
    order_column = current_sort["column"]
    order_dir = current_sort["dir"]
    
    if order_column && order_dir
      column_names = ["id", "last_update", "general_lastup", "last_check_date", "title", "author", "sitename", "novel_type", "tags", "general_all_no", "length", "status", "toc_url"]
      sort_column = column_names[order_column]
      if sort_column
        filtered_data.sort! do |a, b|
          val_a = a[sort_column.to_sym] || 0
          val_b = b[sort_column.to_sym] || 0
          
          if val_a.is_a?(Numeric) && val_b.is_a?(Numeric)
            comparison = val_a <=> val_b
          else
            comparison = val_a.to_s <=> val_b.to_s
          end
          
          order_dir == "desc" ? -comparison : comparison
        end
      end
    end
    
    # IDのみを取得（文字列として）
    sorted_ids = filtered_data.map { |item| item[:id].to_s }
    
    # キャッシュに保存
    @@full_sorted_ids_cache[cache_key] = sorted_ids
    @@full_ids_cache_time = current_time
    
    debug_puts "[DEBUG] Generated #{sorted_ids.length} sorted IDs: #{sorted_ids.first(5)}..."
    return sorted_ids
  end

  get "/api/list" do
    begin
      result = process_novel_list_request(params)
      json result
    rescue StandardError => e
      # エラーが発生した場合のレスポンス
      puts "API List Error: #{e.message}"
      puts e.backtrace.join("\n")
      
      json({
        draw: params["draw"].to_i || 1,
        data: [],
        recordsTotal: 0,
        recordsFiltered: 0,
        error: "サーバーエラーが発生しました: #{e.message}"
      })
    end
  end

  # POSTメソッドでも同じ処理を実行（URIが長くなる問題を回避）
  post "/api/list" do
    begin
      result = process_novel_list_request(params)
      json result
    rescue StandardError => e
      # エラーが発生した場合のレスポンス
      puts "API List Error: #{e.message}"
      puts e.backtrace.join("\n")
      
      json({
        draw: params["draw"].to_i || 1,
        data: [],
        recordsTotal: 0,
        recordsFiltered: 0,
        error: "サーバーエラーが発生しました: #{e.message}"
      })
    end
  end

  post "/api/cancel" do
    Narou::WebWorker.cancel
    Narou::Worker.cancel if Narou.concurrency_enabled?
  end

  get "/api/sort_state" do
    server_setting = Inventory.load("server_setting", :global)
    current_sort = server_setting["current_sort"]
    
    if current_sort
      json({
        column: current_sort["column"],
        dir: current_sort["dir"]
      })
    else
      # デフォルトソート: 最新話掲載日 降順
      json({
        column: 2,
        dir: "desc"
      })
    end
  end

  post "/api/convert" do
    begin
      ids = select_valid_novel_ids(params["ids"]) or halt(400, json({ error: "小説が選択されていません" }))
      
      # convert実行時点でのソート状態が渡された場合はそれを使用
      if params["sort_state"] && params["timestamp"]
        debug_puts "[DEBUG] Convert with fixed sort state (timestamp: #{params["timestamp"]})"
        sorted_ids = sort_ids_with_fixed_state(ids, params["sort_state"])
      else
        # 従来通りの現在のソート状態に基づく並び替え
        debug_puts "[DEBUG] Convert with current sort state"
        sorted_ids = sort_ids_by_current_sort(ids)
      end
      
      debug_puts "[DEBUG] Convert processing #{sorted_ids.length} novels: #{sorted_ids.inspect}"
      concurrency_push do
        CommandLine.run!("convert", "--no-open", sorted_ids)
      end
      
      json({ 
        success: true, 
        message: "変換処理を開始しました", 
        count: sorted_ids.length,
        ids: sorted_ids 
      })
    rescue StandardError => e
      puts "[ERROR] Convert API error: #{e.class}: #{e.message}"
      puts e.backtrace.first(5).join("\n") if $DEBUG
      status 500
      json({ error: "変換処理でエラーが発生しました: #{e.message}" })
    end
  end

  post "/api/download" do
    headers "Access-Control-Allow-Origin" => "*"
    targets_param = params["targets"]
    bad_request!("ダウンロード対象が指定されていません") if targets_param.nil?

    targets = targets_param.is_a?(Array) ? targets_param : targets_param.to_s.split
    targets = targets.map(&:to_s).reject(&:empty?)
    bad_request!("ダウンロード対象が指定されていません") if targets.empty?

    opt_mail = "--mail" if query_to_boolean(params["mail"])
    Narou::WebWorker.push do
      CommandLine.run!("download", targets, opt_mail)
      Narou::AppServer.clear_all_cache # 全キャッシュ無効化
      @@push_server.send_all(:"table.reload")
    end
  end

  post "/api/download_force" do
    ids = select_valid_novel_ids(params["ids"])
    bad_request!("小説が選択されていません") unless ids
    Narou::WebWorker.push do
      CommandLine.run!("download", "--force", ids)
      Narou::AppServer.clear_all_cache # 全キャッシュ無効化
      @@push_server.send_all(:"table.reload")
    end
  end

  post "/api/mail" do
    ids = select_valid_novel_ids(params["ids"]) || []
    Narou::WebWorker.push do
      Narou.concurrency_call do
        CommandLine.run!("mail", ids, io: $stdout2)
      end
    end
  end

  post "/api/update" do
    if params["update_all"] == "true"
      # 全件更新の場合 - 処理用完全IDリストを使用
      puts "[DEBUG] All novels update requested" if ENV["NAROU_DEBUG"] == "1"
      
      # 新しいキャッシュシステムで全IDを取得（現在のフィルター・ソート条件適用済み）
      sorted_ids = get_full_sorted_ids(params)
      puts "[DEBUG] Full sorted IDs for update: #{sorted_ids.length} items" if ENV["NAROU_DEBUG"] == "1"
      puts "[DEBUG] First 10 IDs: #{sorted_ids.first(10).inspect}" if ENV["NAROU_DEBUG"] == "1"
      
      opt_arguments = []
      if params["force"] == "true"
        opt_arguments << "--force"
      end
      Narou::WebWorker.push do
        puts "<white>全ての小説の更新を開始します（#{sorted_ids.length}件を#{current_sort_display_string}で処理）</white>".termcolor
        cmd = Command::Update.new
        if table_reload_timing == "every"
          cmd.on(:success) do
            @@push_server.send_all(:"table.reload")
          end
        end
        cmd.execute!(sorted_ids, opt_arguments)
        Narou::AppServer.clear_all_cache # 全キャッシュ無効化
        @@push_server.send_all(:"table.reload")
      end
    else
      # 選択された小説のみ更新 - 処理用完全IDリストと照合
      selected_ids = select_valid_novel_ids(params["ids"]) || []
      puts "[DEBUG] Selected IDs from WebUI: #{selected_ids.inspect}" if ENV["NAROU_DEBUG"] == "1"
      
      if selected_ids.empty?
        puts "[DEBUG] No valid IDs selected, skipping update" if ENV["NAROU_DEBUG"] == "1"
        return
      end
      
      # 処理用完全IDリストを取得（現在のフィルター・ソート条件適用済み）
      full_sorted_ids = get_full_sorted_ids(params)
      puts "[DEBUG] Full sorted IDs: #{full_sorted_ids.length} items" if ENV["NAROU_DEBUG"] == "1"
      
      # 選択されたIDを完全リストの順序で並び替え
      sorted_ids = full_sorted_ids.select { |id| selected_ids.include?(id) }
      puts "[DEBUG] Final sorted IDs for update: #{sorted_ids.inspect}" if ENV["NAROU_DEBUG"] == "1"
      
      if sorted_ids.empty?
        puts "[DEBUG] No selected IDs found in current filter/sort, skipping update" if ENV["NAROU_DEBUG"] == "1"
        return
      end
      
      opt_arguments = []
      if params["force"] == "true"
        opt_arguments << "--force"
      end
      Narou::WebWorker.push do
        puts "<white>更新を開始します（#{sorted_ids.length}件を#{current_sort_display_string}で処理）</white>".termcolor
        cmd = Command::Update.new
        if table_reload_timing == "every"
          cmd.on(:success) do
            @@push_server.send_all(:"table.reload")
          end
        end
        cmd.execute!(sorted_ids, opt_arguments)
        Narou::AppServer.clear_all_cache # 全キャッシュ無効化
        @@push_server.send_all(:"table.reload")
      end
    end
  end

  post "/api/update_by_tag" do
    tags = params["tags"] || []
    exclusion_tags = params["exclusion_tags"] || []
    tag_params = tags.map do |tag|
      "tag:#{tag}"
    end
    tag_params += exclusion_tags.map do |tag|
      "^tag:#{tag}"
    end
    bad_request!("タグが指定されていません") if tag_params.empty?
    Narou::WebWorker.push do
      cmd = Command::Update.new
      if table_reload_timing == "every"
        cmd.on(:success) do
          @@push_server.send_all(:"table.reload")
        end
      end
      cmd.execute!(tag_params)
      Narou::AppServer.clear_all_cache # 全キャッシュ無効化
      @@push_server.send_all(:"table.reload")
    end
  end

  post "/api/send" do
    ids = select_valid_novel_ids(params["ids"]) || []
    Narou::WebWorker.push do
      Narou.concurrency_call do
        CommandLine.run!("send", ids, io: $stdout2)
      end
    end
  end

  post "/api/backup_bookmark" do
    Narou::WebWorker.push do
      CommandLine.run!("send", "--backup-bookmark")
    end
  end

  post "/api/freeze" do
    begin
      ids = select_valid_novel_ids(params["ids"]) or halt(400, json({ error: "小説が選択されていません" }))
      Narou::WebWorker.push do
        CommandLine.run!("freeze", ids)
        Narou::AppServer.clear_all_cache
        @@push_server.send_all(:"table.reload")
      end
      json({ success: true, message: "凍結状態を切り替えました", count: ids.length })
    rescue StandardError => e
      puts "[ERROR] Freeze API error: #{e.class}: #{e.message}"
      status 500
      json({ error: "凍結処理でエラーが発生しました: #{e.message}" })
    end
  end

  post "/api/freeze_on" do
    begin
      ids = select_valid_novel_ids(params["ids"]) or halt(400, json({ error: "小説が選択されていません" }))
      Narou::WebWorker.push do
        CommandLine.run!("freeze", "--on", ids)
        Narou::AppServer.clear_all_cache
        @@push_server.send_all(:"table.reload")
      end
      json({ success: true, message: "凍結しました", count: ids.length })
    rescue StandardError => e
      puts "[ERROR] Freeze On API error: #{e.class}: #{e.message}"
      status 500
      json({ error: "凍結処理でエラーが発生しました: #{e.message}" })
    end
  end

  post "/api/freeze_off" do
    begin
      ids = select_valid_novel_ids(params["ids"]) or halt(400, json({ error: "小説が選択されていません" }))
      Narou::WebWorker.push do
        CommandLine.run!("freeze", "--off", ids)
        Narou::AppServer.clear_all_cache
        @@push_server.send_all(:"table.reload")
      end
      json({ success: true, message: "凍結を解除しました", count: ids.length })
    rescue StandardError => e
      puts "[ERROR] Freeze Off API error: #{e.class}: #{e.message}"
      status 500
      json({ error: "凍結解除処理でエラーが発生しました: #{e.message}" })
    end
  end

  post "/api/remove" do
    ids = select_valid_novel_ids(params["ids"])
    bad_request!("小説が選択されていません") unless ids
    
    # remove実行時点でのソート状態が渡された場合はそれを使用
    if params["sort_state"] && params["timestamp"]
      debug_puts "[DEBUG] Remove with fixed sort state (timestamp: #{params["timestamp"]})"
      sorted_ids = sort_ids_with_fixed_state(ids, params["sort_state"])
    else
      # 従来通りの現在のソート状態に基づく並び替え
      debug_puts "[DEBUG] Remove with current sort state"
      sorted_ids = sort_ids_by_current_sort(ids)
    end
    
    opt_arguments = []
    if params["with_file"] == "true"
      opt_arguments << "--with-file"
    end
    
    debug_puts "[DEBUG] Remove processing #{sorted_ids.length} novels: #{sorted_ids.inspect}"
    begin
      Narou::WebWorker.push do
        begin
          CommandLine.run!("remove", "--yes", sorted_ids, opt_arguments)
          @@push_server.send_all(:"table.reload")
        rescue => e
          @@push_server.send_all(:"error", { message: "削除に失敗しました: #{e.message}" })
        end
      end
      { success: true }.to_json
    rescue => e
      status 500
      { error: "削除処理でエラーが発生しました: #{e.message}" }.to_json
    end
  end

  post "/api/remove_with_file" do
    ids = select_valid_novel_ids(params["ids"])
    bad_request!("小説が選択されていません") unless ids
    
    # remove実行時点でのソート状態が渡された場合はそれを使用
    if params["sort_state"] && params["timestamp"]
      debug_puts "[DEBUG] Remove with file with fixed sort state (timestamp: #{params["timestamp"]})"
      sorted_ids = sort_ids_with_fixed_state(ids, params["sort_state"])
    else
      # 従来通りの現在のソート状態に基づく並び替え
      debug_puts "[DEBUG] Remove with file with current sort state"
      sorted_ids = sort_ids_by_current_sort(ids)
    end
    
    debug_puts "[DEBUG] Remove with file processing #{sorted_ids.length} novels: #{sorted_ids.inspect}"
    begin
      Narou::WebWorker.push do
        begin
          CommandLine.run!("remove", "--yes", "--with-file", sorted_ids)
          @@push_server.send_all(:"table.reload")
        rescue => e
          @@push_server.send_all(:"error", { message: "削除に失敗しました: #{e.message}" })
        end
      end
      { success: true }.to_json
    rescue => e
      status 500
      { error: "削除処理でエラーが発生しました: #{e.message}" }.to_json
    end
  end

  post "/api/diff" do
    ids = select_valid_novel_ids(params["ids"])
    bad_request!("小説が選択されていません") unless ids
    number = params["number"] || "1"
    disabled_log_io = $stdout.dup_with_disabled_logging
    Narou::WebWorker.push do
      # diff コマンドは１度に一つのIDしか受け取らないので一つずつ表示する
      ids.each do |id|
        # セキュリティ的にWEB UIでは独自の差分表示のみ使う
        CommandLine.run!("diff", "--no-tool", id, "--number", number)
        Helper.print_horizontal_rule(disabled_log_io)
      end
    end
  end

  get "/api/diff_list" do
    target = params["target"] or return ""
    id = Downloader.get_id_by_target(target) or return ""
    @list = Command::Diff.new.get_diff_list(id)
    haml :_diff_list, layout: false
  end

  post "/api/diff_clean" do
    target = params["target"] or bad_request!("target が指定されていません")
    id = Downloader.get_id_by_target(target) or bad_request!("対象の小説が見つかりません")
    Narou::WebWorker.push do
      CommandLine.run!("diff", "--clean", id)
    end
  end

  post "/api/inspect" do
    ids = select_valid_novel_ids(params["ids"])
    bad_request!("小説が選択されていません") unless ids
    Narou::WebWorker.push do
      CommandLine.run!("inspect", ids)
    end
  end

  post "/api/folder" do
    ids = select_valid_novel_ids(params["ids"])
    bad_request!("小説が選択されていません") unless ids
    CommandLine.run!("folder", ids)
  end

  post "/api/backup" do
    ids = select_valid_novel_ids(params["ids"])
    bad_request!("小説が選択されていません") unless ids
    Narou::WebWorker.push do
      CommandLine.run!("backup", ids)
    end
  end

  get "/api/history" do
    case params["stream"]
    when "stdout2"
      $stdout2.string
    else
      $stdout.string
    end
  end

  post "/api/clear_history" do
    Narou::PushServer.instance.clear_history
    $stdout.string.clear
    $stdout2.string.clear if Narou.concurrency_enabled?
  end

  get "/api/tag_list" do
    result =
      +'<div><span class="tag tag-reset label label-default" data-tag="">タグ検索を解除</span></div>' \
      '<div class="text-muted" style="font-size:10px">Altキーを押しながらで除外検索</div>'
    tagname_list = Command::Tag.get_tag_list.keys
    tagname_list.sort.each do |tagname|
      result << "<div>#{decorate_tags([tagname])} " \
                "<span class='select-color-button' data-target-tag='#{h tagname}'>" \
                "<span class='#{Command::Tag.get_color(tagname)}'>a</span></span></div>"
    end
    result
  end

  post "/api/taginfo.json" do
    ids = select_valid_novel_ids(params["ids"])
    bad_request!("小説が選択されていません") unless ids
    ids.map!(&:to_i)
    
    # tag情報取得時点でのソート状態が渡された場合はそれを使用
    if params["sort_state"] && params["timestamp"]
      debug_puts "[DEBUG] TagInfo with fixed sort state (timestamp: #{params["timestamp"]})"
      # 固定化された状態でデータを取得
      sorted_ids = sort_ids_with_fixed_state(ids.map(&:to_s), params["sort_state"]).map(&:to_i)
    else
      debug_puts "[DEBUG] TagInfo with current state"
      sorted_ids = ids
    end
    
    database = Database.instance
    tag_info = {}
    
    # まず全体のタグ一覧を取得（すべてのタグを選択肢として表示するため）
    all_tags = Command::Tag.get_tag_list
    all_tags.each do |tag, total_count|
      tag_info[tag] = {
        count: 0,
        total_count: total_count,
        tag: tag,
        html: decorate_tags([tag]),
        exclusion_html: params["with_exclusion"] ? decorate_exclusion_tags([tag]) : ""
      }
    end
    
    # 選択されたIDの小説での各タグの出現回数を計算
    sorted_ids.each do |id|
      data = database[id]
      next unless data
      
      tags = data["tags"] || []
      tags.each do |tag|
        if tag_info[tag]
          tag_info[tag][:count] += 1
        end
      end
    end
    
    debug_puts "[DEBUG] TagInfo processing #{sorted_ids.length} novels for #{tag_info.keys.length} tags (#{all_tags.keys.length} total tags available)"
    json Hash[tag_info.sort_by { |k, v| k }].values
  end

  post "/api/edit_tag" do
    request.body.rewind
    raw_body = request.body.read.to_s

    unless request.media_type == "application/json"
      debug_puts "[ERROR] Unsupported Content-Type for tag edit: #{request.media_type.inspect}"
      halt 415, json({
        success: false,
        error: "Unsupported Media Type",
        message: "このエンドポイントは application/json のみ受け付けます"
      })
    end

    if raw_body.empty?
      debug_puts "[ERROR] Empty request body for tag edit"
      halt 400, json({ success: false, error: "Empty request body" })
    end

    begin
      request_payload = JSON.parse(raw_body)
    rescue JSON::ParserError => e
      debug_puts "[ERROR] Failed to parse JSON payload: #{e.message}"
      halt 400, json({ success: false, error: "Invalid JSON payload" })
    end

    unless request_payload.is_a?(Hash)
      debug_puts "[ERROR] Tag edit payload must be a JSON object: #{request_payload.class.name}"
      halt 400, json({ success: false, error: "JSON object required" })
    end

  ids = select_valid_novel_ids(request_payload["ids"])
  bad_request!("小説が選択されていません") unless ids
    
    # tag編集実行時点でのソート状態が渡された場合はそれを使用
    if request_payload["sort_state"] && request_payload["timestamp"]
      debug_puts "[DEBUG] Tag edit with fixed sort state (timestamp: #{request_payload["timestamp"]})"
      sorted_ids = sort_ids_with_fixed_state(ids, request_payload["sort_state"])
    else
      debug_puts "[DEBUG] Tag edit with current sort state"
      sorted_ids = ids
    end
    
  debug_puts "[DEBUG] Tag edit processing #{sorted_ids.length} novels: #{sorted_ids.inspect}"
    debug_puts "[DEBUG] Received payload: #{request_payload.inspect}"
    debug_puts "[DEBUG] Received states param: #{request_payload["states"].inspect}"
    debug_puts "[DEBUG] Received states class: #{request_payload["states"]&.class&.name || 'nil'}"
    
    # states パラメータの存在チェック
    if request_payload["states"].nil? || request_payload["states"].empty?
      debug_puts "[ERROR] States parameter is nil or empty"
      return { success: false, error: "No tag states provided" }.to_json
    end
    
    # key と value を重複を維持したまま反転
    begin
      invert_states = request_payload["states"].inject({}) { |h,(k,v)| (h[v] ||= []) << k; h }
      debug_puts "[DEBUG] Inverted states: #{invert_states.inspect}"
    rescue => e
      debug_puts "[ERROR] Failed to invert states: #{e.message}"
      debug_puts "[ERROR] States param details: #{request_payload["states"].inspect}"
      return { success: false, error: e.message }.to_json
    end
    
    has_additions = false
    has_deletions = false
    
    invert_states.each do |state, tags|
      case state.to_i
      when 0
        # タグを削除
        debug_puts "タグ削除実行: #{tags.join(', ')} (対象ID: #{sorted_ids.join(', ')})"
        Command::Tag.execute!("--delete", tags.join(" "), sorted_ids, io: Narou::NullIO.new)
        has_deletions = true
      when 1
        # 現状を維持(何もしない)
      when 2
        # タグを追加
        debug_puts "タグ追加実行: #{tags.join(', ')} (対象ID: #{sorted_ids.join(', ')})"
        Command::Tag.execute!("--add", tags.join(" "), sorted_ids, io: Narou::NullIO.new)
        has_additions = true
      end
    end
    
    # タグ追加がある場合は、データベース書き込み完了を待つ
    if has_additions
      debug_puts "タグ追加処理のためデータベース同期を待機中..."
      sleep(0.5)  # データベース書き込み完了を待つ
    end
    
    # キャッシュを確実にクリアしてからイベント送信
    Narou::AppServer.clear_all_cache 
    debug_puts "タグ編集完了 (追加: #{has_additions}, 削除: #{has_deletions}): 全キャッシュクリア後にリロードイベントを送信"
    
    # テーブルリロードとタグキャンバス更新を順次実行
    @@push_server.send_all(:"table.reload")
    @@push_server.send_all(:"tag.updateCanvas")
  end

  get "/api/get_queue_size" do
    res = [
      Narou::WebWorker.instance.size, Narou::Worker.size
    ]
    json res
  end

  post "/api/update_general_lastup" do
    option = params["option"]
    option = nil if option == "all"
    is_update_modified = params["is_update_modified"] == "true"
    Narou::WebWorker.push do
      CommandLine.run!(["update", "--gl", option].compact)
      Narou::AppServer.clear_all_cache # 全キャッシュ無効化
      @@push_server.send_all(:"table.reload")
      @@push_server.send_all(:"tag.updateCanvas")
      if is_update_modified
        puts "<yellow>#{Narou::MODIFIED_TAG} タグの付いた小説を更新します</yellow>".termcolor
        CommandLine.run!("update", "tag:#{Narou::MODIFIED_TAG}")
        Narou::AppServer.clear_all_cache # 全キャッシュ無効化
        @@push_server.send_all(:"table.reload")
        @@push_server.send_all(:"tag.updateCanvas")
      end
    end
  end

  post "/api/setting_burn" do
    ids = select_valid_novel_ids(params["ids"])
    bad_request!("小説が選択されていません") unless ids
    Narou::WebWorker.push do
      CommandLine.run!("setting", "--burn", ids)
    end
  end

  post "/api/change_tag_color" do
    tag = params["tag"] or bad_request!("タグが指定されていません")
    color = params["color"] or bad_request!("カラーが指定されていません")
    tag_colors = Inventory.load("tag_colors")
    tag_colors[tag] = color
    tag_colors.save
    
    # キャッシュを確実にクリアしてからイベント送信
    Narou::AppServer.clear_all_cache 
    puts "タグ色変更完了: 全キャッシュクリア後にリロードイベントを送信"
    
    # テーブルリロードとタグキャンバス更新を順次実行
    @@push_server.send_all(:"table.reload")
    @@push_server.send_all(:"tag.updateCanvas")
  end

  get "/api/csv/download" do
    begin
      content_type "application/csv"
      attachment "novels.csv"

      csv_command = Command::Csv.new
      result = csv_command.generate
      puts "CSVファイルをエクスポートしました (#{result.bytesize} bytes)"
      result
    rescue StandardError => e
      puts "[ERROR] CSVエクスポートに失敗しました: #{e.message}"
      status 500
      content_type "text/plain"
      "CSVエクスポートエラー: #{e.message}"
    end
  end

  post "/api/csv/import" do
    begin
  raw_files = params["files"]
  bad_request!("CSVファイルが指定されていません") if raw_files.nil?
  files = raw_files.is_a?(Array) ? raw_files.compact : [raw_files].compact
  bad_request!("CSVファイルが指定されていません") if files.empty?
      csv = Command::Csv.new
      imported_count = 0
      files.each do |file|
        csv.import(file[:tempfile])
        imported_count += 1
      end
      bad_request!("CSVファイルが指定されていません") if imported_count.zero?
      puts "CSVファイルをインポートしました (#{imported_count}件)"
      ""
    rescue StandardError => e
      puts "[ERROR] CSVインポートに失敗しました: #{e.message}"
      status 500
      "CSVインポートエラー: #{e.message}"
    end
  end

  # ダウンロード登録すると同時にグレーのボタン画像を返す
  get "/api/download4ssl" do
    target = params["target"] or error("need a parameter: `target'")
    opt_mail = "--mail" if query_to_boolean(params["mail"])
    Narou::WebWorker.push do
      CommandLine.run!("download", target, opt_mail)
      @@push_server.send_all(:"table.reload")
    end
    redirect "/resources/images/dl_button1.gif"
  end

  # ダウンロード済みかどうかで表示が変わる画像
  get "/api/downloadable.gif" do
    target = params["target"]
    # 0: 未ダウンロード, 1: ダウンロード済み, 2: ダウンロード出来ない
    number =
      if target
        Downloader.get_id_by_target(target) ? 1 : 0
      else
        2
      end
    redirect "/resources/images/dl_button#{number}.gif"
  end

  get "/api/validate_url_regexp_list" do
    json SiteSetting.settings.values.map { |setting|
      Array(setting["url"]).map do |url|
        "(#{url.gsub(/\?<.+?>/, "?:").gsub("\\", "\\\\")})"
      end
    }.flatten
  end

  get "/api/version/current.json" do
    json({ version: Narou::VERSION })
  end

  get "/api/version/latest.json" do
    json({ version: Narou.latest_version })
  end

  get "/api/notepad/read" do
    content_type "text/plain"
    if File.exist?(notepad_text_path)
      File.read(notepad_text_path)
    else
      ""
    end
  end

  post "/api/notepad/save" do
    File.write(notepad_text_path, params["text"])
    @@push_server.send_all("notepad.change" => {
      text: params["text"], object_id: params["object_id"]
    })
    ""
  end

  post "/api/eject" do
    do_eject = proc do
      device = Narou.get_device
      device&.eject do
        puts "<bold><green>端末を取り外しました</green></bold>".termcolor
      end
    end
    if params["enqueue"] == "true"
      Narou::WebWorker.push do
        Narou.concurrency_call(&do_eject)
      end
    else
      do_eject.call
    end
    ""
  end

  get "/api/story" do
    target_id = params["id"]
    bad_request!("小説IDが指定されていません") if target_id.nil? || target_id.to_s.empty?
    toc = Downloader.get_toc_by_target(target_id)
    unless toc
      status 404
      return json({ success: false, error: "対象の小説が見つかりません" })
    end
    story = toc["story"] || ""
    html = HTML.new
    json title: toc["title"], story: html.ln_to_br(story.strip)
  end

  # -------------------------------------------------------------------------------
  # 一部分に表示するためのHTMLを取得する(パーシャル)
  # -------------------------------------------------------------------------------

  get "/partial/csv_import" do
    haml :"partial/csv_import", layout: false
  end

  get "/partial/download_form" do
    haml :"partial/download_form", layout: false
  end

  # -------------------------------------------------------------------------------
  # ウィジット関係
  # -------------------------------------------------------------------------------

  BOOKMARKLET_MODE = %w(download insert_button)

  get "/js/widget.js" do
    @params = params
    if BOOKMARKLET_MODE.include?(params["mode"])
      content_type :js
      erb :"bookmarklet/#{params['mode']}.js"
    else
      error("invaid mode")
    end
  end

  ALLOW_HOSTS = [].tap do |hosts|
    SiteSetting.settings.each_value do |s|
      hosts << s["domain"]
    end
    hosts.freeze
  end

  before "/widget/*" do
    from = params["from"]
    if ALLOW_HOSTS.include?(from)
      headers "X-Frame-Options" => "ALLOW-FROM http://#{from}/"
    end
  end

  get "/widget/download" do
    target = params["target"] or error("targetを指定して下さい")
    mail = query_to_boolean(params["mail"]) ? "--mail" : nil
    Narou::WebWorker.push do
      CommandLine.run!("download", target, mail)
      @@push_server.send_all(:"table.reload")
    end
    haml :"widget/download", layout: nil
  end

  get "/widget/drag_and_drop" do
    haml :"widget/drag_and_drop", layout: nil
  end

  get "/widget/notepad" do
    haml :"widget/notepad", layout: nil
  end

  private

  def debug_puts(message)
    puts message if ENV["NAROU_DEBUG"] == "1"
  end
end
