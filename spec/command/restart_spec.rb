# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Command::Restart do
  subject(:command) { described_class.new }

  let(:pid_file) { File.join(Narou.root_dir, "tmp", "pids", "narou-web.pid") }
  let(:stop_command) { instance_double(Command::Stop) }
  let(:web_command) { instance_double(Command::Web) }

  before do
    FileUtils.mkdir_p(File.dirname(pid_file))
    allow(Command::Stop).to receive(:new).and_return(stop_command)
    allow(Command::Web).to receive(:new).and_return(web_command)
  end

  after do
    File.delete(pid_file) if File.exist?(pid_file)
  end

  describe "#execute" do
    context "when server is running" do
      before do
        File.write(pid_file, Process.pid.to_s)
        allow(stop_command).to receive(:execute)
        allow(web_command).to receive(:execute)
      end

      it "stops and starts the server" do
        expect(stop_command).to receive(:execute).with([])
        expect(web_command).to receive(:execute).with(["--boot", "--daemon", "--no-browser"])

        command.execute([])
      end

      context "with --force option" do
        it "force stops and starts the server" do
          expect(stop_command).to receive(:execute).with(["--force"])
          expect(web_command).to receive(:execute).with(["--boot", "--daemon", "--no-browser"])

          command.execute(["--force"])
        end
      end
    end

    context "when server is not running" do
      before do
        allow(web_command).to receive(:execute)
      end

      it "just starts the server" do
        expect(web_command).to receive(:execute).with(["--boot", "--daemon", "--no-browser"])
        
        expect { command.execute([]) }.to output(/起動していません.*起動しています.*完了しました/m).to_stdout
      end
    end
  end
end
