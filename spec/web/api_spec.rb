# frozen_string_literal: true

require "rack/test"
require "json"

require_relative "../spec_helper"
require_relative "../../lib/web/appserver"

RSpec.describe "Narou::AppServer REST API" do
  include Rack::Test::Methods

  def app
    Narou::AppServer
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
end
