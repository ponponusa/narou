# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

#
# API/Widget/Partialルーティングを担当するモジュール
#
# REST API、ウィジェット、パーシャルビューなどの補助的なルーティングを集約
#
module ApiAndWidgetRoutes
  # ブックマークレット対応モード
  BOOKMARKLET_MODE = %w(download insert_button)
  
  # ウィジェット許可ホスト
  ALLOW_HOSTS = [].tap do |hosts|
    SiteSetting.settings.each_value do |s|
      hosts << s["domain"]
    end
    hosts.freeze
  end
  
  def self.registered(app)
    #
    # API Documentation (Swagger UI)
    #
    app.get "/api/docs" do
      swagger_ui_path = File.join(settings.public_folder, "swagger-ui", "index.html")
      if File.exist?(swagger_ui_path)
        send_file swagger_ui_path
      else
        halt 404, "Swagger UI not found at #{swagger_ui_path}"
      end
    end

    #
    # OpenAPI Specification
    #
    app.get "/api/openapi.yaml" do
      content_type "application/x-yaml"
      openapi_path = File.join(File.dirname(__FILE__), "../../docs/openapi.yaml")
      if File.exist?(openapi_path)
        send_file openapi_path
      else
        halt 404, "OpenAPI spec not found at #{openapi_path}"
      end
    end

    #
    # 小説総数取得API
    #
    app.get "/api/novels/count" do
      json({ count: Database.instance.get_object.size })
    end

    #
    # フィルター済み小説ID取得API
    #
    app.get "/api/novels/all_ids" do
      begin
        debug_puts "[DEBUG] /api/novels/all_ids called with params: #{params.inspect}"
        all_ids = get_all_filtered_novel_ids(params)
        debug_puts "[DEBUG] Returning #{all_ids.length} novel IDs"
        
        json({
          success: true,
          data: all_ids,
          count: all_ids.length
        })
      rescue StandardError => e
        puts "[ERROR] all_ids API error: #{e.class}: #{e.message}"
        puts e.backtrace.join("\n")
        status 500
        json({ 
          success: false, 
          error: "IDの取得でエラーが発生しました: #{e.message}",
          data: [],
          count: 0
        })
      end
    end

    #
    # Partial: CSVインポートフォーム
    #
    app.get "/partial/csv_import" do
      haml :"partial/csv_import", layout: false
    end

    #
    # Partial: ダウンロードフォーム
    #
    app.get "/partial/download_form" do
      haml :"partial/download_form", layout: false
    end

    # -------------------------------------------------------------------------------
    # ウィジット関係
    # -------------------------------------------------------------------------------

    #
    # ウィジェットJavaScript配信
    #
    app.get "/js/widget.js" do
      @params = params
      if ApiAndWidgetRoutes::BOOKMARKLET_MODE.include?(params["mode"])
        content_type :js
        erb :"bookmarklet/#{params['mode']}.js"
      else
        error("invaid mode")
      end
    end

    #
    # ウィジェットフィルター
    #
    app.before "/widget/*" do
      from = params["from"]
      if ApiAndWidgetRoutes::ALLOW_HOSTS.include?(from)
        headers "X-Frame-Options" => "ALLOW-FROM http://#{from}/"
      end
    end

    #
    # ウィジェット: ダウンロード
    #
    app.get "/widget/download" do
      target = params["target"] or error("targetを指定して下さい")
      mail = query_to_boolean(params["mail"]) ? "--mail" : nil
      Narou::WebWorker.push do
        CommandLine.run!("download", target, mail)
        @@push_server.send_all(:"table.reload")
      end
      haml :"widget/download", layout: nil
    end

    #
    # ウィジェット: ドラッグ&ドロップ
    #
    app.get "/widget/drag_and_drop" do
      haml :"widget/drag_and_drop", layout: nil
    end

    #
    # ウィジェット: メモ帳
    #
    app.get "/widget/notepad" do
      haml :"widget/notepad", layout: nil
    end

    # ================================================================================
    # API v2 エンドポイント
    # ================================================================================

    #
    # 小説のあらすじ取得API
    #
    app.get "/api/v2/novels/:id/story" do
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

    #
    # タスクキャンセルAPI
    #
    app.post "/api/v2/cancel" do
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

    #
    # 全タスクキャンセルAPI
    #
    app.post "/api/v2/cancel/all" do
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

    #
    # 個別タスクキャンセルAPI
    #
    # NOTE: 現在のWebWorker実装では個別タスクのキャンセルは未対応
    # 将来的にタスクID管理機能を実装する際のプレースホルダー
    #
    app.post "/api/v2/cancel/:id" do
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
  end
end
