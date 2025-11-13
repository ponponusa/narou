# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Command::Stop do
  subject(:command) { described_class.new }

  let(:backend_pid_file) { File.join(Narou.root_dir, "tmp", "pids", "narou-web.pid") }
  let(:frontend_pid_file) { File.join(Narou.root_dir, "tmp", "pids", "narou-frontend.pid") }

  before do
    FileUtils.mkdir_p(File.dirname(backend_pid_file))
    allow(Command::OutputHelper).to receive(:setup_logger)
  end

  after do
    File.delete(backend_pid_file) if File.exist?(backend_pid_file)
    File.delete(frontend_pid_file) if File.exist?(frontend_pid_file)
  end

  describe "#execute" do
    context "when server is not running" do
      it "shows not running message" do
        expect(Command::OutputHelper).to receive(:warning).with("サーバーは起動していません")
        command.execute([])
      end
    end

    context "when backend server is running" do
      before do
        File.write(backend_pid_file, Process.pid.to_s)
      end

      it "stops the backend server with TERM signal" do
        expect(Process).to receive(:kill).with("TERM", Process.pid)
        expect(Command::OutputHelper).to receive(:success).with(/バックエンドサーバーを停止しました/)
        command.execute([])
      end

      context "with --force option" do
        it "stops the backend server with KILL signal" do
          expect(Process).to receive(:kill).with("KILL", Process.pid)
          expect(Command::OutputHelper).to receive(:success).with(/バックエンドサーバーを強制停止しました/)
          command.execute(["--force"])
        end
      end
    end

    context "when frontend server is running" do
      before do
        File.write(frontend_pid_file, Process.pid.to_s)
      end

      it "stops the frontend server with TERM signal" do
        expect(Process).to receive(:kill).with("-TERM", Process.pid)
        expect(Command::OutputHelper).to receive(:success).with(/フロントエンドサーバーを停止しました/)
        command.execute([])
      end

      context "with --force option" do
        it "stops the frontend server with KILL signal" do
          expect(Process).to receive(:kill).with("-KILL", Process.pid)
          expect(Command::OutputHelper).to receive(:success).with(/フロントエンドサーバーを強制停止しました/)
          command.execute(["--force"])
        end
      end
    end

    context "when both servers are running" do
      before do
        File.write(backend_pid_file, Process.pid.to_s)
        File.write(frontend_pid_file, (Process.pid + 1).to_s)
      end

      it "stops both servers" do
        expect(Process).to receive(:kill).with("TERM", Process.pid)
        expect(Process).to receive(:kill).with("-TERM", Process.pid + 1)
        expect(Command::OutputHelper).to receive(:success).with(/バックエンドサーバーを停止しました/)
        expect(Command::OutputHelper).to receive(:success).with(/フロントエンドサーバーを停止しました/)
        command.execute([])
      end
    end
  end
end
