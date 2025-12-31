# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

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
require "lib/core/narou"
require "lib/core/version"
require "lib/cli/commandline"
require "lib/core/inventory"
require "lib/web/workers/web_worker"
require "lib/web/server/push_server"
require "lib/web/config/setting_messages"
require "lib/web/server/helpers"
require "lib/narou/promo_tag_extractor"
require "lib/narou/system_updater"
require "lib/narou/tag_manager"
require "lib/web/api/v1/system"
require "lib/web/api/v1/settings"
require "lib/web/api/v1/tags"
require "lib/web/api/v1/utilities"
require "lib/web/api/v1/novels"
require "lib/web/api/v2/base"
require "lib/web/api/v2/novels"
require "lib/web/api/v2/novel_settings"
require "lib/web/api/v2/system"
require "lib/web/api/v2/tags"
require "lib/web/api/v2/settings"
require "lib/web/api/v2/tasks"
require "lib/web/processors/novel_list"
require "lib/web/server/initializer"
require "lib/web/api/documentation"

# ルートモジュールを遅延ロード（密結合回避）
module Narou
  autoload :WidgetRoutes, "lib/web/routes/widget"
end

class Narou::AppServer < Sinatra::Base
  # ルートモジュール（Narou::以外）を遅延ロード
  autoload :StaticFileRoutes, "lib/web/routes/static_file"
  autoload :SystemManagementRoutes, "lib/web/routes/system_management"
  autoload :SettingsRoutes, "lib/web/routes/settings"
  autoload :NovelsRoutes, "lib/web/routes/novels"

  register Sinatra::Reloader if $development
  helpers Narou::ServerHelpers

  include NovelListProcessor
  include ServerInitializer

  register StaticFileRoutes
  register SystemManagementRoutes
  register SettingsRoutes
  register NovelsRoutes
  register Narou::WidgetRoutes
  register Narou::ApiV1::Documentation

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

    # gzip圧縮を有効化（API v2レスポンスの最適化）
    use Rack::Deflater

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

  # CORS設定（新しいフロントエンドとの連携用）
  before do
    # プリフライトリクエストとAPIエンドポイントにCORSヘッダーを追加
    if request.path.start_with?("/api") || request.request_method == "OPTIONS"
      headers["Access-Control-Allow-Origin"] = "*"
      headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
      headers["Access-Control-Allow-Headers"] = "Content-Type, Accept, Authorization"
      headers["Access-Control-Max-Age"] = "86400"

      # OPTIONSリクエスト（プリフライト）の場合は200を返して終了
      halt 200 if request.request_method == "OPTIONS"
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
    port = global_setting["server-port"]
    bind = global_setting["server-bind"]
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
    host = bind || ipaddress
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
                       when "" # 環境設定画面で未設定が選択された時
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

  private

  def debug_puts(message)
    puts message if ENV["NAROU_DEBUG"] == "1"
  end
end
