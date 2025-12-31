# frozen_string_literal: true

require "spec_helper"
require "lib/web/server/push_server"

RSpec.describe Narou::PushServer do
  let(:push_server) { Narou::PushServer.instance }

  before do
    # スレッドの例外をテストプロセスに伝播させない
    Thread.report_on_exception = false

    # シングルトンの状態を完全にリセット
    if push_server.running?
      # @serverを先に取得してからquitを呼ぶ
      server = push_server.instance_variable_get(:@server)
      server&.quit rescue nil
      thread = push_server.instance_variable_get(:@server_thread)
      thread&.kill rescue nil
      thread&.join(0.1) rescue nil
    end
    sleep 0.02

    push_server.instance_variable_set(:@connections, [])
    push_server.instance_variable_set(:@server_thread, nil)
    push_server.instance_variable_set(:@server, nil)
    push_server.clear_history

    # デフォルト値に戻す
    push_server.accepted_domains = ["*"]
    push_server.port = 31000
    push_server.host = nil

    # イベントリスナーをリセット
    push_server.instance_variable_set(:@__events_container, {})
  end

  after do
    # テスト後にPushServerを停止
    if push_server.running?
      server = push_server.instance_variable_get(:@server)
      server&.quit rescue nil
      thread = push_server.instance_variable_get(:@server_thread)
      thread&.kill rescue nil
      thread&.join(0.1) rescue nil
    end
    push_server.instance_variable_set(:@server_thread, nil)
    push_server.instance_variable_set(:@server, nil)
    sleep 0.02
    Thread.report_on_exception = true
  end

  describe ".instance" do
    it "returns singleton instance" do
      expect(Narou::PushServer.instance).to be push_server
    end
  end

  describe "#initialize state" do
    it "has expected default values" do
      expect(push_server.port).to eq(31000)
      expect(push_server.accepted_domains).to eq(["*"])
      expect(push_server.connections).to eq([])
    end
  end

  describe "#accepted_domains=" do
    it "accepts single domain as string" do
      push_server.accepted_domains = "example.com"
      expect(push_server.accepted_domains).to eq(["example.com"])
    end

    it "accepts multiple domains as array" do
      push_server.accepted_domains = ["example.com", "test.com"]
      expect(push_server.accepted_domains).to eq(["example.com", "test.com"])
    end
  end

  describe "#port=" do
    it "sets custom port" do
      push_server.port = 31234
      expect(push_server.port).to eq(31234)
    end
  end

  describe "#host=" do
    it "sets custom host" do
      push_server.host = "127.0.0.1"
      expect(push_server.host).to eq("127.0.0.1")
    end

    it "can be set to nil" do
      push_server.host = nil
      expect(push_server.host).to be_nil
    end
  end

  describe "#running?" do
    it "returns false when not started" do
      expect(push_server.running?).to be false
    end

    it "returns false when server_thread is nil" do
      push_server.instance_variable_set(:@server_thread, nil)
      expect(push_server.running?).to be false
    end

    it "returns true when server_thread is alive" do
      thread = Thread.new { sleep 10 }
      push_server.instance_variable_set(:@server_thread, thread)

      expect(push_server.running?).to be true

      thread.kill
      thread.join(0.1)
    end

    it "returns false when server_thread is dead" do
      thread = Thread.new { }
      thread.join # スレッドが終了するのを待つ
      push_server.instance_variable_set(:@server_thread, thread)

      expect(push_server.running?).to be false
    end
  end

  describe "#quit" do
    it "does nothing when not running" do
      push_server.instance_variable_set(:@server, nil)
      push_server.instance_variable_set(:@server_thread, nil)

      expect { push_server.quit }.not_to raise_error
    end

    it "kills the server thread" do
      thread = Thread.new { sleep 10 }
      mock_server = Object.new
      def mock_server.quit; end

      push_server.instance_variable_set(:@server_thread, thread)
      push_server.instance_variable_set(:@server, mock_server)

      push_server.quit

      expect(push_server.running?).to be false
    end
  end

  describe "#send_all" do
    it "sends message to all connections" do
      queue1 = Queue.new
      queue2 = Queue.new
      push_server.instance_variable_set(:@connections, [queue1, queue2])

      push_server.send_all(test_message: { data: "test" })

      expect(queue1.pop).to eq('{"test_message":{"data":"test"}}')
      expect(queue2.pop).to eq('{"test_message":{"data":"test"}}')
    end

    it "handles symbol argument" do
      queue = Queue.new
      push_server.instance_variable_set(:@connections, [queue])

      push_server.send_all(:"test.event")

      expect(queue.pop).to eq('{"test.event":true}')
    end

    it "handles empty connections gracefully" do
      push_server.instance_variable_set(:@connections, [])

      expect { push_server.send_all(test: "message") }.not_to raise_error
    end

    it "stores echo messages in history" do
      push_server.instance_variable_set(:@connections, [])

      push_server.send_all(echo: { body: "test message", target_console: "#console" })

      history = push_server.instance_variable_get(:@history)
      last_message = history.compact.last
      expect(last_message[:body]).to eq("test message")
      expect(last_message[:target_console]).to eq("#console")
      expect(last_message[:timestamp]).to be_a(String)
      expect(last_message[:timestamp]).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}/)
    end

    it "does not store non-echo messages in history" do
      push_server.instance_variable_set(:@connections, [])
      push_server.clear_history

      push_server.send_all(notification: { type: "update" })

      history = push_server.instance_variable_get(:@history)
      expect(history.compact).to be_empty
    end
  end

  describe "#clear_history" do
    it "clears message history" do
      # 履歴にいくつかメッセージを追加
      push_server.instance_variable_set(:@connections, [])
      push_server.send_all(echo: { body: "message1" })
      push_server.send_all(echo: { body: "message2" })

      result = push_server.clear_history

      history = push_server.instance_variable_get(:@history)
      expect(history.compact).to be_empty
      expect(result).to be true # Sinatraの配列返却問題回避のため
    end

    it "returns true for Sinatra compatibility" do
      expect(push_server.clear_history).to be true
    end
  end

  describe "#stack_to_history" do
    before do
      push_server.clear_history
    end

    it "adds message to history" do
      push_server.stack_to_history({ body: "test", target_console: "#console" })

      history = push_server.instance_variable_get(:@history)
      last_message = history.compact.last
      expect(last_message[:body]).to eq("test")
      expect(last_message[:target_console]).to eq("#console")
      expect(last_message[:timestamp]).to be_a(String)
      expect(last_message[:timestamp]).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}/)
    end

    it "does not store messages with no_history flag" do
      push_server.stack_to_history({ body: "test", no_history: true })

      history = push_server.instance_variable_get(:@history)
      expect(history.compact).to be_empty
    end

    it "combines consecutive dot messages" do
      # 最初にダミーのメッセージを追加して履歴に内容があることを確保
      push_server.stack_to_history({ body: "start" })
      push_server.stack_to_history({ body: "." })
      push_server.stack_to_history({ body: "." })
      push_server.stack_to_history({ body: "." })

      history = push_server.instance_variable_get(:@history)
      # 最後のメッセージは "..." になっているはず（連続したドットは結合される）
      expect(history.compact.last[:body]).to eq("...")
    end

    it "limits history to HISTORY_SAVED_COUNT" do
      (Narou::PushServer::HISTORY_SAVED_COUNT + 10).times do |i|
        push_server.stack_to_history({ body: "message #{i}" })
      end

      history = push_server.instance_variable_get(:@history)
      expect(history.size).to eq(Narou::PushServer::HISTORY_SAVED_COUNT)
    end
  end

  describe "Eventable integration" do
    it "includes Eventable module" do
      expect(push_server.class.included_modules).to include(Narou::Eventable)
    end

    it "can register event listeners with #on" do
      received_data = nil
      push_server.on(:test_event) do |data|
        received_data = data
      end

      push_server.trigger(:test_event, { test: "data" })

      expect(received_data).to eq({ test: "data" })
    end

    it "can trigger events with #trigger" do
      call_count = 0
      push_server.on(:count_event) { call_count += 1 }

      push_server.trigger(:count_event)
      push_server.trigger(:count_event)

      expect(call_count).to eq(2)
    end

    it "can remove event listeners with #off" do
      call_count = 0
      handler = proc { call_count += 1 }
      push_server.on(:removable_event, &handler)

      push_server.trigger(:removable_event)
      push_server.off(:removable_event, &handler)
      push_server.trigger(:removable_event)

      expect(call_count).to eq(1)
    end

    it "can register one-time event with #one" do
      call_count = 0
      push_server.one(:once_event) { call_count += 1 }

      push_server.trigger(:once_event)
      push_server.trigger(:once_event)

      expect(call_count).to eq(1)
    end
  end

  describe "HISTORY_SAVED_COUNT constant" do
    it "is defined" do
      expect(Narou::PushServer::HISTORY_SAVED_COUNT).to eq(60)
    end
  end

  describe "#connections" do
    it "returns connections array" do
      expect(push_server.connections).to be_an(Array)
    end

    it "can have multiple connections" do
      queue1 = Queue.new
      queue2 = Queue.new
      push_server.instance_variable_set(:@connections, [queue1, queue2])

      expect(push_server.connections.size).to eq(2)
    end
  end
end
