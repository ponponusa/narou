# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Command::Stop do
  subject(:command) { described_class.new }

  let(:backend_pid_file) { File.join(Narou.root_dir, "tmp", "pids", "narou-web.pid") }
  let(:frontend_pid_file) { File.join(Narou.root_dir, "tmp", "pids", "narou-frontend.pid") }

  before do
    FileUtils.mkdir_p(File.dirname(backend_pid_file))
  end

  after do
    File.delete(backend_pid_file) if File.exist?(backend_pid_file)
    File.delete(frontend_pid_file) if File.exist?(frontend_pid_file)
  end

  describe "#execute" do
    context "when server is not running" do
      it "shows not running message" do
        expect { command.execute([]) }.to output(/起動していません/).to_stdout
      end
    end

    context "when server is running" do
      before do
        File.write(backend_pid_file, Process.pid.to_s)
      end

      it "stops the server with TERM signal" do
        expect(Process).to receive(:kill).with("TERM", Process.pid)
        expect { command.execute([]) }.to output(/停止しました/).to_stdout
      end

      context "with --force option" do
        it "stops the server with KILL signal" do
          expect(Process).to receive(:kill).with("KILL", Process.pid)
          expect { command.execute(["--force"]) }.to output(/強制停止しました/).to_stdout
        end
      end
    end
  end
end
