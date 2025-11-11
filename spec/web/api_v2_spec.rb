# frozen_string_literal: true

#
# Copyright 2024 ponponusa. All rights reserved.
#

require "rack/test"
require "json"

require_relative "../spec_helper"
require_relative "../../lib/web/appserver"

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

  describe "CORS Headers" do
    it "sets CORS headers for API v2 endpoints" do
      get "/api/v2/system/version"
      
      expect(last_response.headers["access-control-allow-origin"]).to eq("*")
    end
  end
end
