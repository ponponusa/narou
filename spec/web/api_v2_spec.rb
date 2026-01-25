# frozen_string_literal: true

#
# Copyright 2024 ponponusa. All rights reserved.
#

require "rack/test"
require "json"

require "spec/spec_helper"
require "lib/web/appserver"

RSpec.describe "Narou::AppServer API v2" do
  include Rack::Test::Methods

  def app
    Narou::AppServer
  end

  def json_response
    JSON.parse(last_response.body)
  end

  let(:push_server) { instance_double(Narou::PushServer, send_all: nil, connections: []) }

  before do
    Narou::AppServer.push_server = push_server
    allow(Narou::PushServer).to receive(:instance).and_return(push_server)
    allow(NovelListProcessor).to receive(:clear_all_cache)
    allow_any_instance_of(Narou::AppServer).to receive(:puts_hello_messages)
    allow_any_instance_of(Narou::AppServer).to receive(:start_device_ejectable_event)
    allow_any_instance_of(Narou::AppServer).to receive(:fill_general_all_no_in_database)
    allow_any_instance_of(Narou::AppServer).to receive(:setup_server_authentication)
    allow_any_instance_of(Narou::AppServer).to receive(:table_reload_timing).and_return("never")
    allow(Narou).to receive(:concurrency_enabled?).and_return(false)
    allow(Narou::WebWorker).to receive(:push) do |&block|
      block.call if block
    end
    allow(Narou::WebWorker).to receive(:push_task) do |task, &block|
      block.call if block
    end
    # ConvertWorkerのモック（変換タスク並列化対応）
    allow(Narou::ConvertWorker).to receive(:push_task) do |task, &block|
      block.call if block
    end
  end

  describe "GET /api/v2/system/version" do
    it "returns version information with unified format" do
      get "/api/v2/system/version"

      expect(last_response).to be_ok
      expect(json_response).to have_key("success")
      expect(json_response).to have_key("data")
      expect(json_response).to have_key("timestamp")

      expect(json_response["success"]).to be true
      expect(json_response["data"]).to have_key("narou")
      expect(json_response["data"]).to have_key("ruby")
    end

    it "includes valid version strings" do
      get "/api/v2/system/version"

      expect(last_response).to be_ok
      expect(json_response["data"]["narou"]).to match(/\d+\.\d+\.\d+/)
      expect(json_response["data"]["ruby"]).to match(/\d+\.\d+\.\d+/)
    end
  end

  describe "GET /api/v2/system/queue" do
    it "returns queue status" do
      allow(Narou::WebWorker.instance).to receive(:size).and_return(2)
      allow(Narou::Worker).to receive(:size).and_return(1)

      get "/api/v2/system/queue"

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]["total"]).to eq(3)
      expect(json_response["data"]["web_worker"]).to eq(2)
      expect(json_response["data"]["worker"]).to eq(1)
    end
  end

  describe "GET /api/v2/system/status" do
    it "returns system status" do
      allow(Narou::Worker).to receive(:size).and_return(0)
      allow(Narou::WebWorker.instance).to receive(:size).and_return(0)
      allow(push_server).to receive(:running?).and_return(true)
      allow(push_server).to receive(:port).and_return(33333)
      allow(push_server).to receive(:connections).and_return([])

      get "/api/v2/system/status"

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]).to have_key("queue")
      expect(json_response["data"]).to have_key("push_server")
    end
  end

  describe "GET /api/v2/novels" do
    it "returns novel list with total count" do
      get "/api/v2/novels"

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]).to have_key("novels")
      expect(json_response["data"]).to have_key("total")
    end

    it "accepts filter parameter" do
      get "/api/v2/novels?filter=test"

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
    end

    it "returns all novels (no server-side pagination)" do
      # YAMLベースのため、サーバー側ではページネーションせず全データを返す
      # クライアント側でSvelte 5 Runesを使って処理する設計
      get "/api/v2/novels"

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]["novels"]).to be_an(Array)
      expect(json_response["data"]["total"]).to be_an(Integer)
    end
  end

  describe "GET /api/v2/novels/:id" do
    it "returns novel details when novel exists" do
      database = instance_double(Database)
      allow(Database).to receive(:instance).and_return(database)
      allow(database).to receive(:[]).with(1).and_return({
        "id" => 1,
        "title" => "Test Novel",
        "author" => "Test Author",
        "tags" => []
      })
      allow(Narou).to receive(:novel_frozen?).with(1).and_return(false)
      allow(Downloader).to receive(:get_novel_data_dir_by_target).and_return(nil)

      get "/api/v2/novels/1"

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]["id"]).to eq(1)
      expect(json_response["data"]["title"]).to eq("Test Novel")
    end

    it "returns 404 when novel does not exist" do
      database = instance_double(Database)
      allow(Database).to receive(:instance).and_return(database)
      allow(database).to receive(:[]).with(9999).and_return(nil)

      get "/api/v2/novels/9999"

      expect(last_response.status).to eq(404)
      expect(json_response["success"]).to be false
    end

    it "generates status field dynamically" do
      database = instance_double(Database)
      allow(Database).to receive(:instance).and_return(database)
      allow(database).to receive(:[]).with(1).and_return({
        "id" => 1,
        "title" => "Test Novel",
        "author" => "Test Author",
        "tags" => ["end"],
        "suspend" => false
      })
      allow(Narou).to receive(:novel_frozen?).with(1).and_return(false)
      allow(Downloader).to receive(:get_novel_data_dir_by_target).and_return(nil)

      get "/api/v2/novels/1"

      expect(last_response).to be_ok
      expect(json_response["data"]["status"]).to eq("完結")
    end

    it "includes title_original and author_original when present" do
      database = instance_double(Database)
      allow(Database).to receive(:instance).and_return(database)
      allow(database).to receive(:[]).with(1).and_return({
        "id" => 1,
        "title" => "Test Novel",
        "author" => "Test Author",
        "title_original" => "【書籍化】Test Novel",
        "author_original" => "Test Author【受賞】",
        "tags" => []
      })
      allow(Narou).to receive(:novel_frozen?).with(1).and_return(false)
      allow(Downloader).to receive(:get_novel_data_dir_by_target).and_return(nil)

      get "/api/v2/novels/1"

      expect(last_response).to be_ok
      expect(json_response["data"]["title_original"]).to eq("【書籍化】Test Novel")
      expect(json_response["data"]["author_original"]).to eq("Test Author【受賞】")
    end

    it "includes download_date and convert_date from filesystem" do
      database = instance_double(Database)
      allow(Database).to receive(:instance).and_return(database)
      allow(database).to receive(:[]).with(1).and_return({
        "id" => 1,
        "title" => "Test Novel",
        "author" => "Test Author",
        "tags" => []
      })
      allow(Narou).to receive(:novel_frozen?).with(1).and_return(false)

      # ファイルシステムのモック
      novel_dir = "/test/novel/dir"
      allow(Downloader).to receive(:get_novel_data_dir_by_target).with(1).and_return(novel_dir)
      allow(Dir).to receive(:exist?).with(novel_dir).and_return(true)

      toc_file = File.join(novel_dir, "toc.yaml")
      allow(File).to receive(:exist?).with(toc_file).and_return(true)
      download_time = Time.new(2025, 1, 1, 12, 0, 0)
      allow(File).to receive(:mtime).with(toc_file).and_return(download_time)

      allow(Narou).to receive(:get_device).and_return(nil)
      epub_path = "/test/novel.epub"
      allow(Narou).to receive(:get_ebook_file_paths).with(1, ".epub").and_return([epub_path])
      allow(File).to receive(:exist?).with(epub_path).and_return(true)
      convert_time = Time.new(2025, 1, 2, 12, 0, 0)
      allow(File).to receive(:mtime).with(epub_path).and_return(convert_time)

      get "/api/v2/novels/1"

      expect(last_response).to be_ok
      expect(json_response["data"]["download_date"]).not_to be_nil
      expect(json_response["data"]["convert_date"]).not_to be_nil
    end
  end

  describe "GET /api/v2/novels/:id/story" do
    it "returns story sections when novel exists" do
      test_toc = {
        "title" => "Test Novel",
        "story" => "This is a test story\nWith multiple lines"
      }
      allow(Downloader).to receive(:get_toc_by_target).with("1").and_return(test_toc)

      get "/api/v2/novels/1/story"

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]["title"]).to eq("Test Novel")
      expect(json_response["data"]["story"]).to be_a(String)
    end

    it "returns 404 when novel does not exist" do
      allow(Downloader).to receive(:get_toc_by_target).with("9999").and_return(nil)

      get "/api/v2/novels/9999/story"

      expect(last_response.status).to eq(404)
      expect(json_response["success"]).to be false
    end
  end

  describe "POST /api/v2/novels/download" do
    it "queues download when targets are provided" do
      allow(Narou::WebWorker).to receive(:push).and_yield
      allow(CommandLine).to receive(:run!)
      allow(NovelListProcessor).to receive(:clear_all_cache)

      payload = { targets: ["n9669bk"] }.to_json
      post "/api/v2/novels/download", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]["targets"]).to eq(["n9669bk"])
    end

    it "calls NovelListProcessor.clear_all_cache after download" do
      allow(Narou::WebWorker).to receive(:push).and_yield
      allow(CommandLine).to receive(:run!)
      expect(NovelListProcessor).to receive(:clear_all_cache)

      payload = { targets: ["n9669bk"] }.to_json
      post "/api/v2/novels/download", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
    end

    it "returns 400 when targets are missing" do
      post "/api/v2/novels/download", {}.to_json, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
      expect(json_response["success"]).to be false
      expect(json_response["error"]).to have_key("code")
    end

    it "returns 400 for empty targets array" do
      post "/api/v2/novels/download", { targets: [] }.to_json, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
      expect(json_response["success"]).to be false
    end

    it "handles multiple targets" do
      allow(Narou::WebWorker).to receive(:push).and_yield
      allow(CommandLine).to receive(:run!)
      allow(NovelListProcessor).to receive(:clear_all_cache)

      payload = { targets: ["n9669bk", "n0000xx"] }.to_json
      post "/api/v2/novels/download", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]["targets"].length).to eq(2)
    end
  end

  describe "POST /api/v2/novels/convert" do
    before do
      # データベースに2つの小説が存在することをモック
      allow(Database.instance).to receive(:[]).with(1).and_return({
        "id" => 1,
        "title" => "Test Novel 1",
        "author" => "Test Author 1"
      })
      allow(Database.instance).to receive(:[]).with(2).and_return({
        "id" => 2,
        "title" => "Test Novel 2",
        "author" => "Test Author 2"
      })
    end

    it "queues convert to ConvertWorker when IDs are provided" do
      allow(Narou::ConvertWorker).to receive(:push_task).and_yield
      allow(CommandLine).to receive(:run!)
      allow(NovelListProcessor).to receive(:clear_all_cache)

      payload = { ids: [1, 2] }.to_json
      post "/api/v2/novels/convert", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      actual = json_response["data"]["ids"]
      # JSONは文字列として返される可能性があるため、文字列に変換して比較
      expect(actual.map(&:to_s)).to match_array(["1", "2"])
    end

    it "calls NovelListProcessor.clear_all_cache after convert" do
      allow(Narou::ConvertWorker).to receive(:push_task).and_yield
      allow(CommandLine).to receive(:run!)
      expect(NovelListProcessor).to receive(:clear_all_cache).at_least(:once)

      payload = { ids: [1] }.to_json
      post "/api/v2/novels/convert", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
    end

    it "returns 400 when IDs are missing" do
      post "/api/v2/novels/convert", {}.to_json, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
      expect(json_response["success"]).to be false
    end
  end

  describe "POST /api/v2/novels/update" do
    before do
      # データベースに小説が存在することをモック
      allow(Database.instance).to receive(:[]).with(1).and_return({
        "id" => 1,
        "title" => "Test Novel 1",
        "author" => "Test Author 1"
      })
      allow(Database.instance).to receive(:[]).with(2).and_return({
        "id" => 2,
        "title" => "Test Novel 2",
        "author" => "Test Author 2"
      })
      allow(Database.instance).to receive(:[]).with(999).and_return(nil)
    end

    it "queues update when IDs are provided" do
      allow(Narou::WebWorker).to receive(:push_task).and_yield
      allow(CommandLine).to receive(:run!)
      allow(NovelListProcessor).to receive(:clear_all_cache)

      payload = { ids: [1, 2] }.to_json
      post "/api/v2/novels/update", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      actual = json_response["data"]["ids"]
      expect(actual.map(&:to_s)).to match_array(["1", "2"])
    end

    it "calls CommandLine.run! with update command (always with --no-convert)" do
      allow(Narou::WebWorker).to receive(:push_task).and_yield
      allow(NovelListProcessor).to receive(:clear_all_cache)
      # 新実装では常に--no-convertで実行し、変換はConvertWorkerに委譲
      expect(CommandLine).to receive(:run!).with("update", "--no-convert", "1")
      # convert_after_update=true（デフォルト）なのでConvertWorkerにも追加される
      allow(Narou::ConvertWorker).to receive(:push_task)

      payload = { ids: [1] }.to_json
      post "/api/v2/novels/update", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
    end

    it "calls update with --no-convert and does not queue convert when convert_after_update is false" do
      allow(Narou::WebWorker).to receive(:push_task).and_yield
      allow(NovelListProcessor).to receive(:clear_all_cache)
      expect(CommandLine).to receive(:run!).with("update", "--no-convert", "1")
      # convert_after_update=false なのでConvertWorkerには追加されない
      expect(Narou::ConvertWorker).not_to receive(:push_task)

      payload = { ids: [1], convert_after_update: false }.to_json
      post "/api/v2/novels/update", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
    end

    it "calls update with --no-convert and --force when include_frozen is true" do
      allow(Narou::WebWorker).to receive(:push_task).and_yield
      allow(NovelListProcessor).to receive(:clear_all_cache)
      expect(CommandLine).to receive(:run!).with("update", "--no-convert", "--force", "1")
      allow(Narou::ConvertWorker).to receive(:push_task)

      payload = { ids: [1], include_frozen: true }.to_json
      post "/api/v2/novels/update", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
    end

    it "calls update with --no-convert and --force when both specified, no convert task" do
      allow(Narou::WebWorker).to receive(:push_task).and_yield
      allow(NovelListProcessor).to receive(:clear_all_cache)
      expect(CommandLine).to receive(:run!).with("update", "--no-convert", "--force", "1")
      expect(Narou::ConvertWorker).not_to receive(:push_task)

      payload = { ids: [1], include_frozen: true, convert_after_update: false }.to_json
      post "/api/v2/novels/update", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
    end

    it "calls download --force --no-convert when force_redownload is true (always --no-convert)" do
      allow(Narou::WebWorker).to receive(:push_task).and_yield
      allow(NovelListProcessor).to receive(:clear_all_cache)
      # 新実装では常に--no-convertで実行
      expect(CommandLine).to receive(:run!).with("download", "--force", "--no-convert", "1")
      # convert_after_update=true（デフォルト）なのでConvertWorkerに追加
      allow(Narou::ConvertWorker).to receive(:push_task)

      payload = { ids: [1], force_redownload: true }.to_json
      post "/api/v2/novels/update", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
    end

    it "calls download --force --no-convert and queues convert when force_redownload and convert_after_update are true" do
      allow(Narou::WebWorker).to receive(:push_task).and_yield
      allow(NovelListProcessor).to receive(:clear_all_cache)
      # force_redownload の場合、download コマンドを使用（常に--no-convert）
      expect(CommandLine).to receive(:run!).with("download", "--force", "--no-convert", "1")
      # convert_after_update=true なのでConvertWorkerに追加
      allow(Narou::ConvertWorker).to receive(:push_task)

      payload = { ids: [1], force_redownload: true, convert_after_update: true }.to_json
      post "/api/v2/novels/update", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
    end

    it "calls download --force --no-convert without convert task when convert_after_update is false" do
      allow(Narou::WebWorker).to receive(:push_task).and_yield
      allow(NovelListProcessor).to receive(:clear_all_cache)
      expect(CommandLine).to receive(:run!).with("download", "--force", "--no-convert", "1")
      # convert_after_update=false なのでConvertWorkerには追加されない
      expect(Narou::ConvertWorker).not_to receive(:push_task)

      payload = { ids: [1], force_redownload: true, convert_after_update: false }.to_json
      post "/api/v2/novels/update", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
    end

    it "temporarily unfreezes frozen novel for force_redownload with include_frozen" do
      # spec_helper では id=22 が凍結されている
      # データベースモック設定
      allow(Database.instance).to receive(:[]).with(22).and_return({
        "id" => 22, "title" => "Frozen Novel", "author" => "Author"
      })

      # 凍結リストのモック（実際のHashで代用、saveはスタブ化）
      frozen_list = { 22 => true }
      frozen_list.define_singleton_method(:save) { }
      allow(Inventory).to receive(:load).and_call_original
      allow(Inventory).to receive(:load).with("freeze").and_return(frozen_list)

      # グローバルモックが既にあるので、ここでは追加のモックのみ
      allow(NovelListProcessor).to receive(:clear_all_cache)
      allow(CommandLine).to receive(:run!).with("download", "--force", "--no-convert", "22")
      allow(Narou::ConvertWorker).to receive(:push_task)

      payload = { ids: [22], force_redownload: true, include_frozen: true }.to_json
      post "/api/v2/novels/update", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
    end

    it "does not unfreeze non-frozen novel for force_redownload with include_frozen" do
      # id=1 は凍結されていない（spec_helper の設定）
      allow(Narou::WebWorker).to receive(:push_task).and_yield
      allow(NovelListProcessor).to receive(:clear_all_cache)
      expect(CommandLine).to receive(:run!).with("download", "--force", "--no-convert", "1")
      allow(Narou::ConvertWorker).to receive(:push_task)

      payload = { ids: [1], force_redownload: true, include_frozen: true }.to_json
      post "/api/v2/novels/update", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
    end

    it "calls NovelListProcessor.clear_all_cache after update" do
      allow(Narou::WebWorker).to receive(:push_task).and_yield
      allow(CommandLine).to receive(:run!)
      allow(Narou::ConvertWorker).to receive(:push_task)
      expect(NovelListProcessor).to receive(:clear_all_cache).at_least(:once)

      payload = { ids: [1] }.to_json
      post "/api/v2/novels/update", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
    end

    it "returns 400 when IDs are missing" do
      post "/api/v2/novels/update", {}.to_json, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
      expect(json_response["success"]).to be false
      expect(json_response["error"]["code"]).to eq("INVALID_PARAMS")
    end

    it "returns 400 for empty IDs array" do
      post "/api/v2/novels/update", { ids: [] }.to_json, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
      expect(json_response["success"]).to be false
    end

    it "handles multiple IDs" do
      allow(Narou::WebWorker).to receive(:push_task).and_yield
      allow(CommandLine).to receive(:run!)
      allow(NovelListProcessor).to receive(:clear_all_cache)

      payload = { ids: [1, 2] }.to_json
      post "/api/v2/novels/update", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]["ids"].length).to eq(2)
    end

    it "returns task_ids in response" do
      allow(Narou::WebWorker).to receive(:push_task).and_yield
      allow(CommandLine).to receive(:run!)
      allow(NovelListProcessor).to receive(:clear_all_cache)

      payload = { ids: [1] }.to_json
      post "/api/v2/novels/update", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
      expect(json_response["data"]).to have_key("task_ids")
    end

    it "skips non-existent novel IDs gracefully" do
      allow(Narou::WebWorker).to receive(:push_task).and_yield
      allow(CommandLine).to receive(:run!)
      allow(NovelListProcessor).to receive(:clear_all_cache)

      # ID 999 は存在しない
      payload = { ids: [1, 999] }.to_json
      post "/api/v2/novels/update", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
      # 存在する小説のみがタスクに追加される
      expect(json_response["success"]).to be true
    end

    it "includes novel_id, novel_title, novel_author in task metadata" do
      task_instance = nil
      allow(Narou::WebWorker).to receive(:push_task) do |task, &block|
        task_instance = task
        block.call if block
      end
      allow(CommandLine).to receive(:run!)
      allow(NovelListProcessor).to receive(:clear_all_cache)

      payload = { ids: [1] }.to_json
      post "/api/v2/novels/update", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
      expect(task_instance).not_to be_nil
      expect(task_instance.novel_id).to eq(1)
      expect(task_instance.novel_title).to eq("Test Novel 1")
      expect(task_instance.novel_author).to eq("Test Author 1")
    end

    # 更新なしの小説に対する変換スキップ機能のテスト
    describe "変換スキップ機能（更新なしの小説）" do
      before do
        allow(Narou::WebWorker).to receive(:push_task).and_yield
        allow(CommandLine).to receive(:run!)
        allow(NovelListProcessor).to receive(:clear_all_cache)
      end

      context "skip_unchanged: true（デフォルト）の場合" do
        it "更新ありの小説のみ変換タスクを登録する" do
          old_time = Time.now - 7200
          new_time = Time.now

          # 更新あり（ID: 1）- 2回目の呼び出しで new_arrivals_date が変化
          call_count_1 = 0
          allow(Database.instance).to receive(:[]).with(1) do
            call_count_1 += 1
            if call_count_1 == 1
              # 更新前
              { "id" => 1, "title" => "Updated Novel", "author" => "Author",
                "new_arrivals_date" => old_time }
            else
              # 更新後（new_arrivals_date が更新された）
              { "id" => 1, "title" => "Updated Novel", "author" => "Author",
                "new_arrivals_date" => new_time }
            end
          end

          # 更新なし（ID: 2）- new_arrivals_date が変化しない
          allow(Database.instance).to receive(:[]).with(2).and_return({
            "id" => 2,
            "title" => "No Update Novel",
            "author" => "Author",
            "new_arrivals_date" => old_time
          })

          convert_task_ids = []
          allow(Narou::ConvertWorker).to receive(:push_task) do |task, &block|
            convert_task_ids << task.novel_id
            block.call if block
          end

          payload = { ids: [1, 2], convert_after_update: true }.to_json
          post "/api/v2/novels/update", payload, { "CONTENT_TYPE" => "application/json" }

          expect(last_response).to be_ok
          # 更新ありの小説（ID: 1）のみ変換タスクが登録される
          expect(convert_task_ids).to eq([1])
          # 更新なしの小説（ID: 2）は変換タスクが登録されない
          expect(convert_task_ids).not_to include(2)
        end
      end

      context "skip_unchanged: false の場合" do
        it "更新なしの小説も変換タスクを登録する" do
          old_time = Time.now - 7200

          # 更新なし（new_arrivals_date が変化しない）
          allow(Database.instance).to receive(:[]).with(1).and_return({
            "id" => 1,
            "title" => "No Update Novel",
            "author" => "Author",
            "new_arrivals_date" => old_time
          })

          convert_task_count = 0
          allow(Narou::ConvertWorker).to receive(:push_task) do |task, &block|
            convert_task_count += 1
            block.call if block
          end

          payload = { ids: [1], convert_after_update: true, skip_unchanged: false }.to_json
          post "/api/v2/novels/update", payload, { "CONTENT_TYPE" => "application/json" }

          expect(last_response).to be_ok
          # skip_unchanged: false なので変換タスクが登録される
          expect(convert_task_count).to eq(1)
        end
      end
    end
  end

  describe "POST /api/v2/novels/remove" do
    it "queues remove when IDs are provided" do
      allow(Narou::WebWorker).to receive(:push).and_yield
      allow(CommandLine).to receive(:run!)
      allow(NovelListProcessor).to receive(:clear_all_cache)

      payload = { ids: [1, 2] }.to_json
      post "/api/v2/novels/remove", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]["ids"]).to eq(["1", "2"])
    end

    it "calls NovelListProcessor.clear_all_cache after remove" do
      allow(Narou::WebWorker).to receive(:push).and_yield
      allow(CommandLine).to receive(:run!)
      expect(NovelListProcessor).to receive(:clear_all_cache)

      payload = { ids: [1] }.to_json
      post "/api/v2/novels/remove", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
    end

    it "returns 400 when IDs are missing" do
      post "/api/v2/novels/remove", {}.to_json, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
      expect(json_response["success"]).to be false
    end
  end

  describe "POST /api/v2/novels/freeze" do
    it "queues freeze when IDs are provided" do
      allow(Narou::WebWorker).to receive(:push).and_yield
      allow(CommandLine).to receive(:run!)
      allow(NovelListProcessor).to receive(:clear_all_cache)

      payload = { ids: [1, 2] }.to_json
      post "/api/v2/novels/freeze", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]["ids"]).to eq(["1", "2"])
    end

    it "calls NovelListProcessor.clear_all_cache after freeze" do
      allow(Narou::WebWorker).to receive(:push).and_yield
      allow(CommandLine).to receive(:run!)
      expect(NovelListProcessor).to receive(:clear_all_cache)

      payload = { ids: [1] }.to_json
      post "/api/v2/novels/freeze", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
    end

    it "returns 400 when IDs are missing" do
      post "/api/v2/novels/freeze", {}.to_json, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
      expect(json_response["success"]).to be false
    end
  end

  describe "GET /api/v2/tags" do
    it "returns tag list" do
      allow(Narou::TagManager).to receive(:get_tag_list).and_return([["tag1", 5], ["tag2", 3]])
      allow(Narou::TagManager).to receive(:get_color).and_return("white")

      get "/api/v2/tags"

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]["tags"]).to be_an(Array)
    end
  end

  describe "POST /api/v2/tags/info" do
    it "returns tag info for specified novels" do
      allow(Narou::TagManager).to receive(:get_tag_info).and_return({ "tag1" => 2, "tag2" => 1 })

      payload = { ids: [1, 2] }.to_json
      post "/api/v2/tags/info", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]).to have_key("tag_info")
    end

    it "returns 400 when ids are missing" do
      post "/api/v2/tags/info", {}.to_json, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
      expect(json_response["success"]).to be false
    end

    it "handles empty ids array" do
      allow(Narou::TagManager).to receive(:get_tag_info).and_return({})

      payload = { ids: [] }.to_json
      post "/api/v2/tags/info", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
      expect(json_response["success"]).to be false
    end
  end

  describe "POST /api/v2/tags/edit" do
    it "edits tags for specified novels" do
      allow(Narou::TagManager).to receive(:edit_tags).and_return({
        success: true,
        added: 2,
        deleted: 1,
        novel_count: 3
      })
      allow(NovelListProcessor).to receive(:clear_all_cache)

      payload = { ids: [1, 2], states: { "tag1" => 2, "tag2" => 0 } }.to_json
      post "/api/v2/tags/edit", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
    end

    it "returns 400 when ids are missing" do
      payload = { states: { "tag1" => 2 } }.to_json
      post "/api/v2/tags/edit", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
    end

    it "returns 400 when states are missing" do
      payload = { ids: [1, 2] }.to_json
      post "/api/v2/tags/edit", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
    end

    it "handles invalid state values" do
      allow(Narou::TagManager).to receive(:edit_tags).and_raise(ArgumentError, "invalid state value")

      payload = { ids: [1, 2], states: { "tag1" => 99 } }.to_json
      post "/api/v2/tags/edit", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(500)
      expect(json_response["success"]).to be false
    end
  end

  describe "POST /api/v2/tags/add" do
    it "adds tags to specified novels" do
      allow(Narou::TagManager).to receive(:add_tags).and_return({
        success: true,
        added: 2,
        novel_count: 3
      })
      allow(NovelListProcessor).to receive(:clear_all_cache)

      payload = { ids: [1, 2], tags: ["tag1", "tag2"] }.to_json
      post "/api/v2/tags/add", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
    end

    it "returns 400 when ids are missing" do
      payload = { tags: ["tag1"] }.to_json
      post "/api/v2/tags/add", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
      expect(json_response["success"]).to be false
    end

    it "returns 400 when tags are missing" do
      payload = { ids: [1, 2] }.to_json
      post "/api/v2/tags/add", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
      expect(json_response["success"]).to be false
    end
  end

  describe "POST /api/v2/tags/delete" do
    it "deletes tags from specified novels" do
      allow(Narou::TagManager).to receive(:remove_tags).and_return({
        success: true,
        deleted: 2,
        novel_count: 3
      })
      allow(NovelListProcessor).to receive(:clear_all_cache)

      payload = { ids: [1, 2], tags: ["tag1", "tag2"] }.to_json
      post "/api/v2/tags/delete", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
    end

    it "returns 400 when ids are missing" do
      payload = { tags: ["tag1"] }.to_json
      post "/api/v2/tags/delete", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
      expect(json_response["success"]).to be false
    end

    it "returns 400 when tags are missing" do
      payload = { ids: [1, 2] }.to_json
      post "/api/v2/tags/delete", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
      expect(json_response["success"]).to be false
    end
  end

  describe "POST /api/v2/tags/color" do
    it "sets colors for tags" do
      allow(Narou::TagManager).to receive(:set_colors).and_return(true)
      allow(NovelListProcessor).to receive(:clear_all_cache)

      payload = { colors: { "tag1" => "red", "tag2" => "blue" } }.to_json
      post "/api/v2/tags/color", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
    end

    it "returns 400 when colors are missing" do
      payload = {}.to_json
      post "/api/v2/tags/color", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
      expect(json_response["success"]).to be false
    end
  end

  describe "GET /api/v2/settings" do
    it "returns settings with metadata" do
      allow(Inventory).to receive(:load).and_return({})
      allow(Command::Setting).to receive(:get_setting_variables).and_return({
        local: {},
        global: {}
      })

      get "/api/v2/settings"

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]).to have_key("local")
      expect(json_response["data"]).to have_key("global")
    end

    it "includes all setting scopes" do
      test_settings = {
        local: { "key1" => "value1" },
        global: { "key2" => "value2" }
      }

      allow(Inventory).to receive(:load).and_return({})
      allow(Command::Setting).to receive(:get_setting_variables).and_return(test_settings)

      get "/api/v2/settings"

      expect(last_response).to be_ok
      data = json_response["data"]
      expect(data).to have_key("local")
      expect(data).to have_key("global")
    end
  end

  describe "GET /api/v2/settings/variables" do
    it "returns setting variables with metadata" do
      allow(Command::Setting).to receive(:get_setting_variables).and_return({
        local: { "key1" => { "value" => "value1", "type" => "string" } },
        global: { "key2" => { "value" => "value2", "type" => "string" } }
      })
      allow(Command::Setting).to receive(:get_setting_tab_names).and_return(["tab1"])
      allow(Command::Setting).to receive(:get_setting_tab_info).and_return({})

      get "/api/v2/settings/variables"

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]).to have_key("variables")
      expect(json_response["data"]).to have_key("tab_names")
      expect(json_response["data"]).to have_key("tab_info")
    end
  end

  describe "PUT /api/v2/settings" do
    it "updates settings" do
      setting_cmd = instance_double(Command::Setting)
      allow(Command::Setting).to receive(:new).and_return(setting_cmd)
      allow(setting_cmd).to receive(:on)
      allow(setting_cmd).to receive(:execute!)
      allow(Inventory).to receive(:clear)
      allow(NovelListProcessor).to receive(:clear_all_cache)

      payload = { settings: { "key1" => "value1" } }.to_json
      put "/api/v2/settings", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
    end

    it "returns 400 when settings are missing" do
      put "/api/v2/settings", {}.to_json, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
      expect(json_response["success"]).to be false
    end
  end

  describe "GET /api/v2/novels/:id/settings" do
    it "returns novel settings" do
      database = instance_double(Database)
      allow(Database).to receive(:instance).and_return(database)
      allow(database).to receive(:[]).with(1).and_return({ "id" => 1, "title" => "Test" })

      novel_setting = instance_double(NovelSetting)
      allow(NovelSetting).to receive(:new).and_return(novel_setting)
      allow(novel_setting).to receive(:settings=)
      allow(novel_setting).to receive(:load_setting_ini).and_return({ "global" => {} })
      allow(novel_setting).to receive(:[]).and_return("test")
      allow(novel_setting).to receive(:load_replace_pattern).and_return("")
      allow(NovelSetting).to receive(:get_original_settings).and_return([
        { name: "author", type: "string", value: "", help: "Author" }
      ])
      allow(NovelSetting).to receive(:load_force_settings).and_return({})
      allow(NovelSetting).to receive(:load_default_settings).and_return({})

      get "/api/v2/novels/1/settings"

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]).to have_key("settings")
    end

    it "returns 404 when novel does not exist" do
      database = instance_double(Database)
      allow(Database).to receive(:instance).and_return(database)
      allow(database).to receive(:[]).with(9999).and_return(nil)

      get "/api/v2/novels/9999/settings"

      expect(last_response.status).to eq(404)
      expect(json_response["success"]).to be false
    end
  end

  describe "PUT /api/v2/novels/:id/settings" do
    it "updates novel settings" do
      database = instance_double(Database)
      allow(Database).to receive(:instance).and_return(database)
      allow(database).to receive(:[]).with(1).and_return({ "id" => 1 })

      novel_setting = instance_double(NovelSetting)
      allow(NovelSetting).to receive(:new).and_return(novel_setting)
      allow(novel_setting).to receive(:settings=)
      allow(novel_setting).to receive(:load_setting_ini).and_return({ "global" => {} })
      allow(novel_setting).to receive(:[]=)
      allow(novel_setting).to receive(:save_settings)
      allow(NovelListProcessor).to receive(:clear_all_cache)

      payload = { settings: { "author" => "New Author" } }.to_json
      put "/api/v2/novels/1/settings", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
    end

    it "returns 404 when novel does not exist" do
      database = instance_double(Database)
      allow(Database).to receive(:instance).and_return(database)
      allow(database).to receive(:[]).with(9999).and_return(nil)

      payload = { settings: { "author" => "New Author" } }.to_json
      put "/api/v2/novels/9999/settings", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(404)
      expect(json_response["success"]).to be false
    end
  end

  describe "POST /api/v2/cancel" do
    it "cancels current task" do
      allow(Narou::WebWorker).to receive(:cancel)
      allow(Narou::Worker).to receive(:cancel)

      post "/api/v2/cancel"

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
    end
  end

  describe "POST /api/v2/console/clear" do
    it "clears console history when PushServer is available" do
      allow(push_server).to receive(:clear_history)

      post "/api/v2/console/clear"

      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]["cleared"]).to be true
      expect(json_response["message"]).to eq("Console history cleared")
      expect(push_server).to have_received(:clear_history)
    end

    it "returns 503 when PushServer is not available" do
      Narou::AppServer.push_server = nil

      post "/api/v2/console/clear"

      expect(last_response.status).to eq(503)
      expect(json_response["success"]).to be false
      expect(json_response["error"]["code"]).to eq("PUSH_SERVER_NOT_AVAILABLE")
    end
  end

  describe "CORS Headers" do
    it "sets CORS headers for API v2 endpoints" do
      get "/api/v2/system/version"

      expect(last_response.headers["access-control-allow-origin"]).to eq("*")
    end

    it "sets CORS headers for POST requests" do
      payload = { targets: ["n9669bk"] }.to_json
      allow(Narou::WebWorker).to receive(:push).and_yield
      allow(CommandLine).to receive(:run!)
      allow(NovelListProcessor).to receive(:clear_all_cache)

      post "/api/v2/novels/download", payload, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.headers["access-control-allow-origin"]).to eq("*")
    end
  end

  describe "GET /api/v2/novels/:id/epub" do
    let(:novel_id) { 1 }
    let(:epub_path) { "/tmp/test_novel.epub" }

    before do
      # データベースのモック
      database = instance_double(Database)
      allow(Database).to receive(:instance).and_return(database)
      allow(database).to receive(:[]).with(novel_id).and_return({
        "id" => novel_id,
        "title" => "Test Novel",
        "author" => "Test Author"
      })
      allow(database).to receive(:[]).with(9999).and_return(nil)
    end

    context "when EPUB file exists" do
      before do
        # デバイスとEPUBパスのモック
        allow(Narou).to receive(:get_device).and_return(nil)
        allow(Narou).to receive(:get_ebook_file_paths).with(novel_id, ".epub").and_return([epub_path])
        allow(File).to receive(:exist?).with(epub_path).and_return(true)
      end

      it "returns EPUB file with formatted filename" do
        # send_file の呼び出しをモック
        allow_any_instance_of(Sinatra::Base).to receive(:send_file) do |_instance, path|
          # Rackレスポンスを返さないとエラーになるので、空のボディを返す
          ""
        end

        get "/api/v2/novels/#{novel_id}/epub"

        expect(last_response).to be_ok, "Expected 200 but got #{last_response.status}"
        # send_file が呼ばれたことを確認
        expect(Narou).to have_received(:get_ebook_file_paths).with(novel_id, ".epub")

        # Content-Dispositionヘッダーが RFC 5987 形式で設定されていることを確認
        content_disposition = last_response.headers["Content-Disposition"]
        expect(content_disposition).to include("attachment")
        expect(content_disposition).to include("filename*=UTF-8''")
        # URLエンコードされたファイル名を確認
        expect(content_disposition).to include("%5BTest%20Author%5D%20Test%20Novel.epub")
      end
    end

    context "when EPUB file does not exist" do
      before do
        allow(Narou).to receive(:get_device).and_return(nil)
        allow(Narou).to receive(:get_ebook_file_paths).with(novel_id, ".epub").and_return([epub_path])
        allow(File).to receive(:exist?).with(epub_path).and_return(false)
      end

      it "returns 404 error" do
        get "/api/v2/novels/#{novel_id}/epub"

        expect(last_response.status).to eq(404)
        expect(json_response["success"]).to be false
        expect(json_response["error"]["code"]).to eq("EPUB_NOT_FOUND")
      end
    end

    context "when novel does not exist" do
      it "returns 404 error" do
        get "/api/v2/novels/9999/epub"

        expect(last_response.status).to eq(404)
        expect(json_response["success"]).to be false
        expect(json_response["error"]["code"]).to eq("NOT_FOUND")
      end
    end

    context "with Kobo device (.kepub.epub)" do
      let(:kepub_path) { "/tmp/test_novel.kepub.epub" }

      before do
        # Device インスタンスをモック
        kobo_device = instance_double(Device, ebook_file_ext: ".kepub.epub")
        allow(Narou).to receive(:get_device).and_return(kobo_device)
        allow(Narou).to receive(:get_ebook_file_paths).with(novel_id, ".kepub.epub").and_return([kepub_path])
        allow(File).to receive(:exist?).with(kepub_path).and_return(true)
      end

      it "returns Kobo EPUB file with formatted filename" do
        # send_file の呼び出しをモック
        allow_any_instance_of(Sinatra::Base).to receive(:send_file) do |_instance, path|
        end

        get "/api/v2/novels/#{novel_id}/epub"

        expect(last_response).to be_ok
        # Kobo用の拡張子でファイルパスが取得されたことを確認
        expect(Narou).to have_received(:get_ebook_file_paths).with(novel_id, ".kepub.epub")

        # Content-Dispositionヘッダーが RFC 5987 形式で設定されていることを確認
        content_disposition = last_response.headers["Content-Disposition"]
        expect(content_disposition).to include("attachment")
        expect(content_disposition).to include("filename*=UTF-8''")
        # URLエンコードされたファイル名を確認（.kepub.epub拡張子）
        expect(content_disposition).to include("%5BTest%20Author%5D%20Test%20Novel.kepub.epub")
      end
    end
  end

  describe "GET /api/v2/settings/export" do
    let(:local_dir) { Pathname.new("/tmp/test_narou/.narou") }
    let(:global_dir) { Pathname.new("/tmp/test_narou/.narousetting") }

    before do
      allow(Narou).to receive(:local_setting_dir).and_return(local_dir)
      allow(Narou).to receive(:global_setting_dir).and_return(global_dir)
    end

    context "when narou is not initialized" do
      before do
        allow(local_dir).to receive(:exist?).and_return(false)
      end

      it "returns 400 error" do
        get "/api/v2/settings/export"

        expect(last_response.status).to eq(400)
        expect(json_response["success"]).to be false
        expect(json_response["error"]["code"]).to eq("NOT_INITIALIZED")
      end
    end

    context "when narou is initialized" do
      let(:test_local_dir) { Dir.mktmpdir("narou_test_local") }
      let(:test_global_dir) { Dir.mktmpdir("narou_test_global") }

      before do
        # 実際のテンポラリディレクトリを使用
        local_pathname = Pathname.new(test_local_dir)
        global_pathname = Pathname.new(test_global_dir)

        allow(Narou).to receive(:local_setting_dir).and_return(local_pathname)
        allow(Narou).to receive(:global_setting_dir).and_return(global_pathname)

        # テスト用ファイルを作成
        File.write(File.join(test_local_dir, "local_setting.yaml"), "key: value")
        File.write(File.join(test_global_dir, "global_setting.yaml"), "global_key: global_value")
      end

      after do
        FileUtils.remove_entry(test_local_dir) if File.exist?(test_local_dir)
        FileUtils.remove_entry(test_global_dir) if File.exist?(test_global_dir)
      end

      it "returns a ZIP file" do
        get "/api/v2/settings/export"

        expect(last_response).to be_ok
        expect(last_response.content_type).to eq("application/zip")
      end

      it "sets correct Content-Disposition header" do
        get "/api/v2/settings/export"

        expect(last_response).to be_ok
        content_disposition = last_response.headers["Content-Disposition"]
        expect(content_disposition).to include("attachment")
        expect(content_disposition).to include("narou-settings-")
        expect(content_disposition).to include(".zip")
      end

      it "includes settings files in the ZIP" do
        get "/api/v2/settings/export"

        expect(last_response).to be_ok

        # ZIPファイルの内容を検証
        require "zip"
        zip_content = StringIO.new(last_response.body)
        entry_names = []

        Zip::InputStream.open(zip_content) do |zis|
          while (entry = zis.get_next_entry)
            entry_names << entry.name
          end
        end

        expect(entry_names).to include(".narou/local_setting.yaml")
        expect(entry_names).to include(".narousetting/global_setting.yaml")
      end
    end
  end

  describe "POST /api/v2/settings/import" do
    context "when no file is uploaded" do
      let(:local_dir) { Pathname.new("/tmp/test_narou/.narou") }
      let(:global_dir) { Pathname.new("/tmp/test_narou/.narousetting") }

      before do
        allow(Narou).to receive(:local_setting_dir).and_return(local_dir)
        allow(Narou).to receive(:global_setting_dir).and_return(global_dir)
      end

      it "returns 400 error" do
        post "/api/v2/settings/import"

        expect(last_response.status).to eq(400)
        expect(json_response["success"]).to be false
        expect(json_response["error"]["code"]).to eq("NO_FILE")
      end
    end

    context "when narou is not initialized" do
      let(:local_dir) { Pathname.new("/tmp/nonexistent_dir") }
      let(:global_dir) { Pathname.new("/tmp/nonexistent_dir2") }

      before do
        allow(Narou).to receive(:local_setting_dir).and_return(local_dir)
        allow(Narou).to receive(:global_setting_dir).and_return(global_dir)
      end

      it "returns 400 error" do
        # 空のZIPファイルを作成
        require "zip"
        zip_buffer = StringIO.new
        Zip::OutputStream.write_buffer(zip_buffer) { |_| }
        zip_buffer.rewind

        # Tempfileを作成
        tempfile = Tempfile.new(["test", ".zip"])
        tempfile.write(zip_buffer.read)
        tempfile.rewind

        uploaded_file = Rack::Test::UploadedFile.new(tempfile.path, "application/zip")

        post "/api/v2/settings/import", file: uploaded_file

        expect(last_response.status).to eq(400)
        expect(json_response["success"]).to be false
        expect(json_response["error"]["code"]).to eq("NOT_INITIALIZED")

        tempfile.close
        tempfile.unlink
      end
    end

    context "when valid ZIP file is uploaded" do
      let(:test_local_dir) { Dir.mktmpdir("narou_test_local") }
      let(:test_global_dir) { Dir.mktmpdir("narou_test_global") }

      before do
        local_pathname = Pathname.new(test_local_dir)
        global_pathname = Pathname.new(test_global_dir)

        allow(Narou).to receive(:local_setting_dir).and_return(local_pathname)
        allow(Narou).to receive(:global_setting_dir).and_return(global_pathname)
        allow(Inventory).to receive(:clear_cache)
      end

      after do
        FileUtils.remove_entry(test_local_dir) if File.exist?(test_local_dir)
        FileUtils.remove_entry(test_global_dir) if File.exist?(test_global_dir)
      end

      it "imports settings from ZIP file" do
        # テスト用ZIPファイルを作成
        require "zip"
        zip_buffer = StringIO.new
        Zip::OutputStream.write_buffer(zip_buffer) do |zos|
          zos.put_next_entry(".narou/local_setting.yaml")
          zos.write("key: value")
          zos.put_next_entry(".narousetting/global_setting.yaml")
          zos.write("global_key: global_value")
        end
        zip_buffer.rewind

        # Tempfileを作成
        tempfile = Tempfile.new(["test", ".zip"])
        tempfile.binmode
        tempfile.write(zip_buffer.read)
        tempfile.rewind

        # Rack::Test::UploadedFileを使用
        uploaded_file = Rack::Test::UploadedFile.new(tempfile.path, "application/zip")

        post "/api/v2/settings/import", file: uploaded_file

        expect(last_response).to be_ok
        expect(json_response["success"]).to be true
        expect(json_response["data"]["imported_count"]).to eq(2)
        expect(json_response["data"]["imported_files"]).to include(".narou/local_setting.yaml")
        expect(json_response["data"]["imported_files"]).to include(".narousetting/global_setting.yaml")

        # 実際にファイルが作成されたことを確認
        expect(File.exist?(File.join(test_local_dir, "local_setting.yaml"))).to be true
        expect(File.exist?(File.join(test_global_dir, "global_setting.yaml"))).to be true

        tempfile.close
        tempfile.unlink
      end

      it "skips files with disallowed extensions" do
        require "zip"
        zip_buffer = StringIO.new
        Zip::OutputStream.write_buffer(zip_buffer) do |zos|
          zos.put_next_entry(".narou/local_setting.yaml")
          zos.write("key: value")
          zos.put_next_entry(".narou/malicious.rb")
          zos.write("# malicious code")
        end
        zip_buffer.rewind

        tempfile = Tempfile.new(["test", ".zip"])
        tempfile.binmode
        tempfile.write(zip_buffer.read)
        tempfile.rewind

        uploaded_file = Rack::Test::UploadedFile.new(tempfile.path, "application/zip")

        post "/api/v2/settings/import", file: uploaded_file

        expect(last_response).to be_ok
        expect(json_response["success"]).to be true
        expect(json_response["data"]["imported_count"]).to eq(1)
        expect(json_response["data"]["skipped_count"]).to eq(1)
        expect(json_response["data"]["skipped_files"]).to include(".narou/malicious.rb")

        # 悪意のあるファイルが作成されていないことを確認
        expect(File.exist?(File.join(test_local_dir, "malicious.rb"))).to be false

        tempfile.close
        tempfile.unlink
      end

      it "prevents path traversal attacks" do
        require "zip"
        zip_buffer = StringIO.new
        Zip::OutputStream.write_buffer(zip_buffer) do |zos|
          zos.put_next_entry("../../../etc/passwd")
          zos.write("malicious content")
          zos.put_next_entry(".narou/local_setting.yaml")
          zos.write("key: value")
        end
        zip_buffer.rewind

        tempfile = Tempfile.new(["test", ".zip"])
        tempfile.binmode
        tempfile.write(zip_buffer.read)
        tempfile.rewind

        uploaded_file = Rack::Test::UploadedFile.new(tempfile.path, "application/zip")

        post "/api/v2/settings/import", file: uploaded_file

        expect(last_response).to be_ok
        expect(json_response["success"]).to be true
        # パストラバーサルを含むエントリは無視される
        expect(json_response["data"]["imported_count"]).to eq(1)

        tempfile.close
        tempfile.unlink
      end

      it "imports replace.txt files" do
        require "zip"
        zip_buffer = StringIO.new
        Zip::OutputStream.write_buffer(zip_buffer) do |zos|
          zos.put_next_entry(".narou/replace.txt")
          zos.write("pattern=replacement")
        end
        zip_buffer.rewind

        tempfile = Tempfile.new(["test", ".zip"])
        tempfile.binmode
        tempfile.write(zip_buffer.read)
        tempfile.rewind

        uploaded_file = Rack::Test::UploadedFile.new(tempfile.path, "application/zip")

        post "/api/v2/settings/import", file: uploaded_file

        expect(last_response).to be_ok
        expect(json_response["success"]).to be true
        expect(json_response["data"]["imported_files"]).to include(".narou/replace.txt")

        # ファイルが作成されたことを確認
        expect(File.exist?(File.join(test_local_dir, "replace.txt"))).to be true

        tempfile.close
        tempfile.unlink
      end

      it "imports parser config files" do
        require "zip"
        zip_buffer = StringIO.new
        Zip::OutputStream.write_buffer(zip_buffer) do |zos|
          zos.put_next_entry(".narou/parsers/ncode.syosetu.com.yaml")
          zos.write("engine: nokogiri")
        end
        zip_buffer.rewind

        tempfile = Tempfile.new(["test", ".zip"])
        tempfile.binmode
        tempfile.write(zip_buffer.read)
        tempfile.rewind

        uploaded_file = Rack::Test::UploadedFile.new(tempfile.path, "application/zip")

        post "/api/v2/settings/import", file: uploaded_file

        expect(last_response).to be_ok
        expect(json_response["success"]).to be true
        expect(json_response["data"]["imported_files"]).to include(".narou/parsers/ncode.syosetu.com.yaml")

        # サブディレクトリが作成されたことを確認
        expect(File.exist?(File.join(test_local_dir, "parsers", "ncode.syosetu.com.yaml"))).to be true

        tempfile.close
        tempfile.unlink
      end
    end

    context "when invalid ZIP file is uploaded" do
      let(:test_local_dir) { Dir.mktmpdir("narou_test_local") }

      before do
        allow(Narou).to receive(:local_setting_dir).and_return(Pathname.new(test_local_dir))
      end

      after do
        FileUtils.remove_entry(test_local_dir) if File.exist?(test_local_dir)
      end

      it "returns 400 error for invalid ZIP" do
        tempfile = Tempfile.new(["test", ".zip"])
        tempfile.write("not a zip file")
        tempfile.rewind

        uploaded_file = Rack::Test::UploadedFile.new(tempfile.path, "application/zip")

        post "/api/v2/settings/import", file: uploaded_file

        expect(last_response.status).to eq(400)
        expect(json_response["success"]).to be false
        expect(json_response["error"]["code"]).to eq("INVALID_ZIP")

        tempfile.close
        tempfile.unlink
      end
    end
  end
end
