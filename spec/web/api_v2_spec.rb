# frozen_string_literal: true

#
# Copyright 2024 ponponusa. All rights reserved.
#

require "rack/test"
require "json"

require_relative "../spec_helper"
require "web/appserver"

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
    allow(Narou::AppServer).to receive(:clear_all_cache)
    allow_any_instance_of(Narou::AppServer).to receive(:puts_hello_messages)
    allow_any_instance_of(Narou::AppServer).to receive(:start_device_ejectable_event)
    allow_any_instance_of(Narou::AppServer).to receive(:fill_general_all_no_in_database)
    allow_any_instance_of(Narou::AppServer).to receive(:setup_server_authentication)
    allow_any_instance_of(Narou::AppServer).to receive(:table_reload_timing).and_return("never")
    allow(Narou).to receive(:concurrency_enabled?).and_return(false)
    allow(Narou::WebWorker).to receive(:push) do |&block|
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
    it "returns novel list with pagination" do
      get "/api/v2/novels"
      
      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]).to have_key("novels")
      expect(json_response["data"]).to have_key("pagination")
      expect(json_response["data"]["pagination"]).to have_key("total")
      expect(json_response["data"]["pagination"]).to have_key("page")
    end

    it "accepts filter parameter" do
      get "/api/v2/novels?filter=test"
      
      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
    end

    it "accepts pagination parameters" do
      get "/api/v2/novels?page=1&per_page=10"
      
      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]["pagination"]["page"]).to eq(1)
      expect(json_response["data"]["pagination"]["per_page"]).to eq(10)
    end
  end

  describe "GET /api/v2/novels/:id" do
    it "returns novel details when novel exists" do
      database = instance_double(Database)
      allow(Database).to receive(:instance).and_return(database)
      allow(database).to receive(:[]).with(1).and_return({
        "id" => 1,
        "title" => "Test Novel",
        "author" => "Test Author"
      })
      
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
      allow(Narou::AppServer).to receive(:clear_all_cache)
      
      payload = { targets: ["n9669bk"] }.to_json
      post "/api/v2/novels/download", payload, { "CONTENT_TYPE" => "application/json" }
      
      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]["targets"]).to eq(["n9669bk"])
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
      allow(Narou::AppServer).to receive(:clear_all_cache)
      
      payload = { targets: ["n9669bk", "n0000xx"] }.to_json
      post "/api/v2/novels/download", payload, { "CONTENT_TYPE" => "application/json" }
      
      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]["targets"].length).to eq(2)
    end
  end

  describe "POST /api/v2/novels/convert" do
    it "queues convert when IDs are provided" do
      allow(Narou::WebWorker).to receive(:push).and_yield
      allow(CommandLine).to receive(:run!)
      allow(Narou::AppServer).to receive(:clear_all_cache)
      
      payload = { ids: [1, 2] }.to_json
      post "/api/v2/novels/convert", payload, { "CONTENT_TYPE" => "application/json" }
      
      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]["ids"]).to eq(["1", "2"])
    end

    it "returns 400 when IDs are missing" do
      post "/api/v2/novels/convert", {}.to_json, { "CONTENT_TYPE" => "application/json" }
      
      expect(last_response.status).to eq(400)
      expect(json_response["success"]).to be false
    end
  end

  describe "POST /api/v2/novels/remove" do
    it "queues remove when IDs are provided" do
      allow(Narou::WebWorker).to receive(:push).and_yield
      allow(CommandLine).to receive(:run!)
      allow(Narou::AppServer).to receive(:clear_all_cache)
      
      payload = { ids: [1, 2] }.to_json
      post "/api/v2/novels/remove", payload, { "CONTENT_TYPE" => "application/json" }
      
      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]["ids"]).to eq(["1", "2"])
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
      allow(Narou::AppServer).to receive(:clear_all_cache)
      
      payload = { ids: [1, 2] }.to_json
      post "/api/v2/novels/freeze", payload, { "CONTENT_TYPE" => "application/json" }
      
      expect(last_response).to be_ok
      expect(json_response["success"]).to be true
      expect(json_response["data"]["ids"]).to eq(["1", "2"])
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
      allow(Narou::AppServer).to receive(:clear_all_cache)
      
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
      allow(Narou::AppServer).to receive(:clear_all_cache)
      
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
      allow(Narou::AppServer).to receive(:clear_all_cache)
      
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
      allow(Narou::AppServer).to receive(:clear_all_cache)
      
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
      allow(Narou::AppServer).to receive(:clear_all_cache)
      
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
      allow(Narou::AppServer).to receive(:clear_all_cache)
      
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

  describe "POST /api/v2/cancel/:id" do
    it "cancels specific task" do
      allow(Narou::WebWorker).to receive(:cancel)
      allow(Narou::Worker).to receive(:cancel)
      
      post "/api/v2/cancel/1"
      
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
      allow(Narou::AppServer).to receive(:clear_all_cache)

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
        # send_file の呼び出しを検証するために、モックを設定
        received_filename = nil
        allow_any_instance_of(Sinatra::Base).to receive(:send_file) do |_instance, path, options|
          received_filename = options[:filename]
        end

        get "/api/v2/novels/#{novel_id}/epub"

        expect(last_response).to be_ok
        # send_file が呼ばれたことを確認
        expect(Narou).to have_received(:get_ebook_file_paths).with(novel_id, ".epub")
        
        # ファイル名が "[著者名] タイトル.拡張子" の形式になっていることを確認
        expect(received_filename).to eq("[Test Author] Test Novel.epub")
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
        # send_file の呼び出しを検証するために、モックを設定
        received_filename = nil
        allow_any_instance_of(Sinatra::Base).to receive(:send_file) do |_instance, path, options|
          received_filename = options[:filename]
        end

        get "/api/v2/novels/#{novel_id}/epub"

        expect(last_response).to be_ok
        # Kobo用の拡張子でファイルパスが取得されたことを確認
        expect(Narou).to have_received(:get_ebook_file_paths).with(novel_id, ".kepub.epub")
        
        # ファイル名が "[著者名] タイトル.kepub.epub" の形式になっていることを確認
        expect(received_filename).to eq("[Test Author] Test Novel.kepub.epub")
      end
    end
  end
end
