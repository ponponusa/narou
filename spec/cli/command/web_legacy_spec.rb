# frozen_string_literal: true

require_relative "../../spec_helper"
require "stringio"

# rubocop:disable Metrics/BlockLength
RSpec.describe Command::WebLegacy do
  subject(:command) { described_class.new }

  let(:push_server) do
    double("push_server",
           run: nil,
           quit: nil,
           send_all: nil,
           connections: [])
  end

  around do |example|
    worker_defined = Narou.const_defined?(:Worker, false)
    original_worker = Narou.const_get(:Worker) if worker_defined
    Narou.send(:remove_const, :Worker) if worker_defined

    original_stdout = $stdout
    stdout2_defined = global_variables.include?(:$stdout2)
    original_stdout2 = $stdout2 if stdout2_defined
    original_web = Narou.web?

    example.run
  ensure
    $stdout = original_stdout
    $stdout2 = stdout2_defined ? original_stdout2 : $stdout
    Narou.web = original_web

    if worker_defined
      Narou.const_set(:Worker, original_worker)
    elsif Narou.const_defined?(:Worker, false)
      Narou.send(:remove_const, :Worker)
    end
  end

  before do
    stub_const("Narou::PushServer", double("PushServerClass", instance: push_server))

    streaming_logger_class = Class.new(StringIO) do
      attr_accessor :log_postfix
      attr_writer :silent
      attr_reader :target_console, :push_server

      def initialize(push_server, _original_stream = $stdout, target_console: "stdout")
        super()
        @push_server = push_server
        @target_console = target_console
        self.log_postfix = nil
      end

      def copy_instance
        self.class.new(@push_server, $stdout, target_console: @target_console)
      end

      def silent?
        !!@silent
      end

      def append_log(_str); end

      def push_streaming(*); end
    end
    stub_const("Narou::StreamingLogger", streaming_logger_class)

    progress_bar_class = Class.new do
      class << self
        attr_accessor :assigned_server

        def push_server=(server)
          self.assigned_server = server
        end
      end
    end
    stub_const("ProgressBar", progress_bar_class)

    web_worker_class = Class.new do
      class << self
        attr_accessor :push_server

        def run; end

        def stop; end
      end
    end
    stub_const("Narou::WebWorker", web_worker_class)

    app_server_class = Class.new do
      class << self
        attr_accessor :push_server, :request_reboot_flag, :running_flag, :next_address, :legacy_mode

        def create_address(_port)
          next_address
        end

        def run!; end

        def request_reboot?
          !!request_reboot_flag
        end

        def running?
          !!running_flag
        end

        def legacy_mode=(enabled)
          @legacy_mode = enabled
        end

        def legacy_mode?
          !!@legacy_mode
        end
      end
    end
    stub_const("Narou::AppServer", app_server_class)

    stub_const("Command::Update", Module.new) unless defined?(Command::Update)
    stub_const("Command::Update::Scheduler", double("Scheduler", start: nil, stop: nil))

    allow(command).to receive(:load_web_dependencies)
    allow(Narou::PushServer).to receive(:instance).and_return(push_server)
    allow(push_server).to receive(:accepted_domains=)
    allow(push_server).to receive(:port=)
    allow(push_server).to receive(:host=)

    Narou::AppServer.next_address = { host: "127.0.0.1", port: 30_000 }
    Narou::AppServer.request_reboot_flag = false
    Narou::AppServer.running_flag = true

    allow(Helper).to receive(:open_browser)
    allow(command).to receive(:confirm_of_first)
    allow(command).to receive(:open_browser_when_server_boot)
    allow(command).to receive(:send_rebooted_event_when_connection_recover)
    allow(command).to receive(:create_push_server).and_return(push_server)
    allow(Inventory).to receive(:load).and_return({})
  end

  it "boots the web UI even when the worker is unavailable" do
    expect(Narou::AppServer).to receive(:run!)

    expect do
      command.execute(%w(--boot --no-browser --no-daemon))
    end.not_to raise_error
  end

  it "ignores kill_threads when worker is undefined" do
    expect { command.send(:kill_threads) }.not_to raise_error
  end
end
# rubocop:enable Metrics/BlockLength
