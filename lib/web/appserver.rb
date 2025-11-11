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
require_relative "../version"
require_relative "../commandline"
require_relative "../inventory"
require_relative "web_worker"
require_relative "pushserver"
require_relative "settingmessages"
require_relative "server_helpers"
require_relative "../narou/promo_tag_extractor"
require_relative "../narou/system_updater"
require_relative "../narou/tag_manager"
require_relative "api/v1/system"
require_relative "api/v1/settings"
require_relative "api/v1/tags"
require_relative "api/v1/utilities"
require_relative "api/v1/novels"
require_relative "api/v2/base"
require_relative "api/v2/novels"
require_relative "api/v2/novel_settings"
require_relative "api/v2/system"
require_relative "api/v2/tags"
require_relative "api/v2/settings"

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
    enable :static
    
    # 静的ファイルの配信設定は動的に決定できないため、
    # デフォルトでlib/web/publicを設定（Legacyモード用）
    # 新しいUIのフロントエンドファイルはルーティングで個別に処理
    set :public_folder, File.join(File.dirname(__FILE__), "public")

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

  # API v1 (Legacy) エンドポイント登録
  Narou::ApiV1::System.register(self)
  Narou::ApiV1::Settings.register(self)
  Narou::ApiV1::Tags.register(self)
  Narou::ApiV1::Utilities.register(self)
  Narou::ApiV1::Novels.register(self)

  # API v2 エンドポイント登録
  include Narou::ApiV2::Base
  Narou::ApiV2::Novels.register(self)
  Narou::ApiV2::NovelSettings.register(self)
  Narou::ApiV2::System.register(self)
  Narou::ApiV2::Tags.register(self)
  Narou::ApiV2::Settings.register(self)

  # Swagger UI と OpenAPI 仕様書のエンドポイント
  get "/api/docs" do
    swagger_ui_path = File.join(settings.public_folder, "swagger-ui", "index.html")
    if File.exist?(swagger_ui_path)
      send_file swagger_ui_path
    else
      halt 404, "Swagger UI not found at #{swagger_ui_path}"
    end
  end

  get "/api/openapi.yaml" do
    content_type "application/x-yaml"
    openapi_path = File.join(File.dirname(__FILE__), "../../docs/openapi.yaml")
    if File.exist?(openapi_path)
      send_file openapi_path
    else
      halt 404, "OpenAPI spec not found at #{openapi_path}"
    end
  end

  # CORS設定（新しいフロントエンドとの連携用）
  before do
    # プリフライトリクエストとAPIエンドポイントにCORSヘッダーを追加
    if request.path.start_with?('/api') || request.request_method == 'OPTIONS'
      headers['Access-Control-Allow-Origin'] = '*'
      headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
      headers['Access-Control-Allow-Headers'] = 'Content-Type, Accept, Authorization'
      headers['Access-Control-Max-Age'] = '86400'
      
      # OPTIONSリクエスト（プリフライト）の場合は200を返して終了
      halt 200 if request.request_method == 'OPTIONS'
    end
  end

  def self.push_server=(server)
    @@push_server = server
  end

  def self.push_server
    @@push_server
  end

  def self.legacy_mode=(enabled)
    @@legacy_mode = enabled
  end

  def self.legacy_mode?
    @@legacy_mode ||= false
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
        if defined?(@@push_server) && @@push_server && @@push_server.connections.count > 0
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
    if self.class.legacy_mode?
      # Legacy Haml UI
      setting = Inventory.load("server_setting", :global)
      @is_first_access = !setting["already-accessed"]
      if @is_first_access
        setting["already-accessed"] = true
        setting.save
      end
      haml :index, layout: true
    else
      # New Astro UI
      # 開発環境のパス
      dev_index_path = File.join(__dir__, "../../frontend/dist/index.html")
      
      # gem環境のパス
      gem_index_path = File.expand_path("../../frontend/dist/index.html", File.dirname(__FILE__))
      
      index_path = if File.exist?(dev_index_path)
                     dev_index_path
                   elsif File.exist?(gem_index_path)
                     gem_index_path
                   else
                     nil
                   end
      
      if index_path && File.exist?(index_path)
        send_file index_path
      else
        halt 500, "Frontend not built. Run 'cd frontend && npm run build' first."
      end
    end
  end

  get "/style.css" do
    if self.class.legacy_mode?
      scss :style
    else
      # Astro UI では使用しない
      halt 404
    end
  end

  # Astro ビルド済みアセット配信
  get "/_astro/*" do
    unless self.class.legacy_mode?
      # 開発環境とgem環境の両方に対応
      asset_filename = params['splat'].first
      
      # 開発環境のパス
      dev_asset_path = File.join(__dir__, "../../frontend/dist/_astro", asset_filename)
      
      # gem環境のパス
      gem_asset_path = File.expand_path("../../frontend/dist/_astro/#{asset_filename}", File.dirname(__FILE__))
      
      asset_path = if File.exist?(dev_asset_path)
                     dev_asset_path
                   elsif File.exist?(gem_asset_path)
                     gem_asset_path
                   else
                     nil
                   end
      
      if asset_path && File.exist?(asset_path)
        send_file asset_path
      else
        halt 404
      end
    else
      halt 404
    end
  end

  get "/favicon.svg" do
    unless self.class.legacy_mode?
      # 開発環境のパス
      dev_favicon_path = File.join(__dir__, "../../frontend/dist/favicon.svg")
      
      # gem環境のパス
      gem_favicon_path = File.expand_path("../../frontend/dist/favicon.svg", File.dirname(__FILE__))
      
      favicon_path = if File.exist?(dev_favicon_path)
                       dev_favicon_path
                     elsif File.exist?(gem_favicon_path)
                       gem_favicon_path
                     else
                       nil
                     end
      
      if favicon_path && File.exist?(favicon_path)
        send_file favicon_path
      else
        halt 404
      end
    else
      halt 404
    end
  end

  before "/settings" do
    if self.class.legacy_mode?
      @title = "環境設定"
      @setting_variables = Command::Setting.get_setting_variables
      @error_list = {}
      @global_replace_pattern = @replace_pattern = Narou.global_replace_pattern
    end
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
    if self.class.legacy_mode?
      haml :settings
    else
      # Astro UI の settings ページ
      # 開発環境のパス
      dev_settings_path = File.join(__dir__, "../../frontend/dist/settings/index.html")
      
      # gem環境のパス
      gem_settings_path = File.expand_path("../../frontend/dist/settings/index.html", File.dirname(__FILE__))
      
      settings_path = if File.exist?(dev_settings_path)
                        dev_settings_path
                      elsif File.exist?(gem_settings_path)
                        gem_settings_path
                      else
                        nil
                      end
      
      if settings_path && File.exist?(settings_path)
        send_file settings_path
      else
        halt 404, "Settings page not found"
      end
    end
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

      cached_data = database_values.map do |data|
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

  # ================================================================================
  # API v2 エンドポイント
  # ================================================================================

  # 小説のあらすじを取得
  get "/api/v2/novels/:id/story" do
    headers "Access-Control-Allow-Origin" => "*"
    
    target_id = params[:id]
    
    begin
      toc = Downloader.get_toc_by_target(target_id)
      unless toc
        status 404
        return json({ 
          success: false, 
          error: "対象の小説が見つかりません",
          data: nil,
          timestamp: Time.now.iso8601
        })
      end
      
      story = toc["story"] || ""
      html = HTML.new
      
      json({
        success: true,
        data: {
          title: toc["title"],
          story: html.ln_to_br(story.strip)
        },
        timestamp: Time.now.iso8601
      })
    rescue StandardError => e
      puts "[ERROR] Get Story API error: #{e.class}: #{e.message}"
      puts e.backtrace.join("\n")
      status 500
      json({ 
        success: false,
        error: "あらすじの取得でエラーが発生しました: #{e.message}",
        data: nil,
        timestamp: Time.now.iso8601
      })
    end
  end

  # 実行中のタスクをキャンセル
  post "/api/v2/cancel" do
    headers "Access-Control-Allow-Origin" => "*"
    begin
      Narou::WebWorker.cancel
      Narou::Worker.cancel if Narou.concurrency_enabled?
      
      json({ 
        success: true, 
        message: "実行中のタスクをキャンセルしました" 
      })
    rescue StandardError => e
      puts "[ERROR] Cancel API error: #{e.class}: #{e.message}"
      status 500
      json({ error: "キャンセル処理でエラーが発生しました: #{e.message}" })
    end
  end

  # すべてのタスクをキャンセル
  post "/api/v2/cancel/all" do
    headers "Access-Control-Allow-Origin" => "*"
    begin
      # WebWorkerとWorkerの両方をキャンセル
      Narou::WebWorker.cancel
      Narou::Worker.cancel if Narou.concurrency_enabled?
      
      json({ 
        success: true, 
        message: "すべてのタスクをキャンセルしました" 
      })
    rescue StandardError => e
      puts "[ERROR] Cancel All API error: #{e.class}: #{e.message}"
      status 500
      json({ error: "キャンセル処理でエラーが発生しました: #{e.message}" })
    end
  end

  # 指定されたIDのタスクをキャンセル
  # NOTE: 現在のWebWorker実装では個別タスクのキャンセルは未対応
  # 将来的にタスクID管理機能を実装する際のプレースホルダー
  post "/api/v2/cancel/:id" do
    headers "Access-Control-Allow-Origin" => "*"
    novel_id = params[:id]
    
    begin
      # 現在は全タスクキャンセルと同じ動作
      # TODO: 個別タスクキャンセル機能の実装
      Narou::WebWorker.cancel
      Narou::Worker.cancel if Narou.concurrency_enabled?
      
      json({ 
        success: true, 
        message: "ID:#{novel_id} のタスクをキャンセルしました（現在は全タスクキャンセル）",
        notice: "個別タスクキャンセル機能は未実装のため、すべてのタスクがキャンセルされます" 
      })
    rescue StandardError => e
      puts "[ERROR] Cancel by ID API error: #{e.class}: #{e.message}"
      status 500
      json({ error: "キャンセル処理でエラーが発生しました: #{e.message}" })
    end
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
