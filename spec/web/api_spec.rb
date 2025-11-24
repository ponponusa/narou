# frozen_string_literal: true

require "rack/test"
require "json"

require "spec/spec_helper"
require "lib/web/appserver"

RSpec.describe "Narou::AppServer REST API" do
  include Rack::Test::Methods

  def app
    Narou::AppServer
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
  end

  describe "GET /api/novels/count" do
    it "returns JSON with the total novel count" do
      get "/api/novels/count"
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body).to include("count")
      expect(body["count"]).to be_an(Integer)
    end
  end

  describe "GET /api/tag_list" do
    it "returns rendered tag list HTML" do
      get "/api/tag_list"
      expect(last_response).to be_ok
      expect(last_response.body).to include("タグ検索を解除")
    end
  end

  describe "POST /api/taginfo.json" do
    it "returns 400 when ids are missing" do
      post "/api/taginfo.json"
      expect(last_response.status).to eq(400)
      body = JSON.parse(last_response.body)
      expect(body).to include("success" => false, "error" => "小説が選択されていません")
    end
  end

  describe "POST /api/edit_tag" do
    let(:json_headers) { { "CONTENT_TYPE" => "application/json" } }

    it "returns 400 when ids are invalid" do
      payload = {
        ids: ["invalid"],
        states: { "tag" => 2 }
      }.to_json

      post "/api/edit_tag", payload, json_headers

      expect(last_response.status).to eq(400)
      body = JSON.parse(last_response.body)
      expect(body).to include("success" => false, "error" => "小説が選択されていません")
    end
  end

  describe "GET /api/story" do
    it "returns 400 when id is missing" do
      get "/api/story"
      expect(last_response.status).to eq(400)
      body = JSON.parse(last_response.body)
      expect(body).to include("success" => false, "error" => "小説IDが指定されていません")
    end

    it "returns 404 when the specified novel does not exist" do
      allow(Downloader).to receive(:get_toc_by_target).and_return(nil)

      get "/api/story", id: "999"

      expect(last_response.status).to eq(404)
      body = JSON.parse(last_response.body)
      expect(body).to include("success" => false, "error" => "対象の小説が見つかりません")
    end
  end

  describe "POST /api/download" do
    it "queues download command with the provided targets" do
      expect(CommandLine).to receive(:run!).with("download", %w(22), nil)
      post "/api/download", targets: "22"
      expect(last_response.status).to eq(200)
    end
  end

  describe "POST /api/update" do
    it "invokes Command::Update for selected ids" do
      command = instance_double(Command::Update, execute!: nil)
      allow(Command::Update).to receive(:new).and_return(command)
      allow(command).to receive(:on)
      allow_any_instance_of(Narou::AppServer).to receive(:get_full_sorted_ids).and_return(%w(22))
      expect(command).to receive(:execute!).with(%w(22), [])

      post "/api/update", "ids[]" => "22"
      expect(last_response.status).to eq(200)
    end
  end

  describe "POST /update_system" do
    let(:result) do
      Narou::SystemUpdater::Result.new(
        status: :success,
        log: "update succeeded",
        remote_version: Gem::Version.new("9.9.9"),
        asset_name: "narou-mod-9.9.9.gem"
      )
    end

    before do
      allow(Thread).to receive(:new).and_yield
      allow(Narou::SystemUpdater).to receive(:update_from_github).and_return(result)
    end

    it "triggers the system updater and broadcasts success" do
      expect(push_server).to receive(:send_all).with("server.update.success" => "update succeeded")

      post "/update_system"

      expect(last_response.status).to eq(200)
      post "/gem_update_last_log"
      expect(last_response.body).to eq("update succeeded")
    end

    it "broadcasts failure when updater raises error" do
      allow(Narou::SystemUpdater).to receive(:update_from_github).and_raise(Narou::SystemUpdater::Error, "boom")
      expect(push_server).to receive(:send_all).with("server.update.failure" => include("boom"))

      post "/update_system"

      post "/gem_update_last_log"
      expect(last_response.body).to include("boom")
    end
  end

  describe "POST /api/convert" do
    it "queues convert command for selected ids" do
      allow(Narou::WebWorker).to receive(:push).and_yield
      allow(CommandLine).to receive(:run!)
      allow(NovelListProcessor).to receive(:clear_all_cache)

      post "/api/convert", "ids[]" => "22"
      expect(last_response.status).to eq(200)
    end
  end

  describe "POST /api/freeze" do
    it "queues freeze command for selected ids" do
      allow(Narou::WebWorker).to receive(:push).and_yield
      allow(CommandLine).to receive(:run!)
      allow(NovelListProcessor).to receive(:clear_all_cache)

      post "/api/freeze", "ids[]" => "22"
      expect(last_response.status).to eq(200)
    end
  end

  describe "POST /api/remove" do
    it "returns 400 when no ids provided" do
      post "/api/remove"
      expect(last_response.status).to eq(400)
      body = JSON.parse(last_response.body)
      expect(body).to include("success" => false)
    end

    it "queues remove command for selected ids" do
      allow(Narou::WebWorker).to receive(:push).and_yield
      allow(CommandLine).to receive(:run!)
      allow(NovelListProcessor).to receive(:clear_all_cache)

      post "/api/remove", "ids[]" => "22"
      expect(last_response.status).to eq(200)
    end
  end

  describe "GET /api/list" do
    it "returns novel list data" do
      get "/api/list"
      expect(last_response).to be_ok
      expect(last_response.body).to be_a(String)
    end
  end
end
