# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Command::Process do
  subject(:command) { described_class.new }

  let(:pid_file) { File.join(Narou.root_dir, "tmp", "pids", "narou-web.pid") }

  before do
    FileUtils.mkdir_p(File.dirname(pid_file))
  end

  after do
    File.delete(pid_file) if File.exist?(pid_file)
  end

  describe "#execute with --status" do
    context "when server is not running" do
      it "shows stopped status" do
        expect { command.execute(["--status"]) }.to output(/停止中/).to_stdout
      end
    end

    context "when server is running" do
      before do
        File.write(pid_file, Process.pid.to_s)
        allow(Inventory).to receive(:load).with("local_setting").and_return({})
        allow(Inventory).to receive(:load).with("server_setting", :global).and_return(
          { "server-port" => 5678 }
        )
      end

      it "shows running status with PID and port" do
        expect { command.execute(["--status"]) }.to output(/実行中.*#{Process.pid}.*5678/m).to_stdout
      end
    end
  end

  describe "#execute with --pid" do
    context "when server is not running" do
      it "shows not running message and exits with error" do
        expect { command.execute(["--pid"]) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end

    context "when server is running" do
      before do
        File.write(pid_file, "12345")
      end

      it "shows PID" do
        expect { command.execute(["--pid"]) }.to output("12345\n").to_stdout
      end
    end
  end

  describe "#execute with --stop" do
    context "when server is not running" do
      it "shows not running message" do
        expect { command.execute(["--stop"]) }.to output(/起動していません/).to_stdout
      end
    end

    context "when server is running" do
      before do
        File.write(pid_file, Process.pid.to_s)
      end

      it "stops the server" do
        expect(Process).to receive(:kill).with("TERM", Process.pid)
        expect { command.execute(["--stop"]) }.to output(/停止しました/).to_stdout
      end
    end
  end
end
