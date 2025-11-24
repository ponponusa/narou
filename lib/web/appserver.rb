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
require_relative "api/v2/tasks"
require_relative "novel_list_processor"
require_relative "server_initializer"
require_relative "static_file_routes"
require_relative "system_management_routes"

class Narou::AppServer < Sinatra::Base
  register Sinatra::Reloader if $development
  helpers Narou::ServerHelpers

  include NovelListProcessor
  include ServerInitializer
  register StaticFileRoutes
  register SystemManagementRoutes

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
  Narou::ApiV2::Tasks.register(self)

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

  include NovelListProcessor

  # キャッシュクリアメソッドをクラスメソッドとして委譲
  def self.clear_api_list_cache
    NovelListProcessor.clear_api_list_cache
  end

  def self.clear_full_ids_cache
    NovelListProcessor.clear_full_ids_cache
  end

  def self.clear_all_cache
    NovelListProcessor.clear_all_cache
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

  # 小説一覧処理の共通メソッド

  # 処理用の完全ソート済IDリストを取得する

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
