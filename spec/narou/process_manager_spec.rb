# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require "lib/narou/process_manager"

describe Narou::ProcessManager do
  let(:test_tmp_dir) { Dir.mktmpdir }
  let(:service_name) { "test-service" }
  let(:manager) do
    allow(Narou).to receive(:tmp_dir).and_return(test_tmp_dir)
    described_class.new(service_name)
  end

  after do
    FileUtils.rm_rf(test_tmp_dir)
  end

  describe "#initialize" do
    it "sets correct file paths" do
      expect(manager.pid_file_path).to eq(File.join(test_tmp_dir, "pids", "#{service_name}.pid"))
      expect(manager.port_file_path).to eq(File.join(test_tmp_dir, "pids", "#{service_name}.port"))
    end
  end

  describe "#register_process" do
    it "creates PID directory and file" do
      manager.register_process
      expect(File.directory?(File.join(test_tmp_dir, "pids"))).to be true
      expect(File.exist?(manager.pid_file_path)).to be true
    end

    it "creates PID file with process information" do
      info = manager.register_process(port: 5000, metadata: { test: "data" })

      expect(File.exist?(manager.pid_file_path)).to be true
      expect(info[:pid]).to eq(Process.pid)
      expect(info[:port]).to eq(5000)
      expect(info[:metadata][:test]).to eq("data")
    end

    it "creates port file" do
      manager.register_process(port: 5000)
      expect(File.read(manager.port_file_path)).to eq("5000")
    end

    it "stores platform and Ruby version" do
      info = manager.register_process
      expect(info[:platform]).to eq(RUBY_PLATFORM)
      expect(info[:ruby_version]).to eq(RUBY_VERSION)
    end
  end

  describe "#read_process_info" do
    context "when PID file exists" do
      before do
        manager.register_process(port: 5000)
      end

      it "returns process information" do
        info = manager.read_process_info
        expect(info).to be_a(Hash)
        expect(info[:pid]).to eq(Process.pid)
        expect(info[:port]).to eq(5000)
      end
    end

    context "when PID file does not exist" do
      it "returns nil" do
        expect(manager.read_process_info).to be_nil
      end
    end

    context "when PID file is corrupted" do
      before do
        FileUtils.mkdir_p(File.dirname(manager.pid_file_path))
        File.write(manager.pid_file_path, "invalid json")
      end

      it "returns nil" do
        expect(manager.read_process_info).to be_nil
      end
    end
  end

  describe "#process_running?" do
    it "returns true for current process" do
      expect(manager.process_running?(Process.pid)).to be true
    end

    it "returns false for non-existent process" do
      expect(manager.process_running?(999999)).to be false
    end

    context "when PID is from registered process" do
      before do
        manager.register_process
      end

      it "returns true" do
        expect(manager.process_running?).to be true
      end
    end
  end

  describe "#port_in_use?" do
    let(:test_port) { 15000 + rand(1000) } # ランダムなポート

    it "returns false for unused port" do
      expect(manager.port_in_use?(test_port)).to be false
    end

    it "returns true for port in use" do
      server = TCPServer.new("127.0.0.1", test_port)
      begin
        expect(manager.port_in_use?(test_port)).to be true
      ensure
        server.close
      end
    end
  end

  describe "#cleanup_stale_process!" do
    context "when process is not running" do
      before do
        manager.register_process
        # PID を存在しないプロセスに書き換え
        info = manager.read_process_info
        info[:pid] = 999999
        File.write(manager.pid_file_path, JSON.pretty_generate(info))
      end

      it "cleans up PID files" do
        manager.cleanup_stale_process!
        expect(File.exist?(manager.pid_file_path)).to be false
      end
    end

    context "when process is running" do
      before do
        manager.register_process
      end

      it "raises ProcessConflictError" do
        expect {
          manager.cleanup_stale_process!
        }.to raise_error(Narou::ProcessManager::ProcessConflictError)
      end
    end
  end

  describe "#check_port_conflict!" do
    let(:test_port) { 15000 + rand(1000) }

    it "does not raise error for available port" do
      expect {
        manager.check_port_conflict!(test_port)
      }.not_to raise_error
    end

    it "raises PortConflictError for port in use" do
      server = TCPServer.new("127.0.0.1", test_port)
      begin
        expect {
          manager.check_port_conflict!(test_port)
        }.to raise_error(Narou::ProcessManager::PortConflictError)
      ensure
        server.close
      end
    end
  end

  describe "#stop_process" do
    context "when process is running" do
      before do
        manager.register_process
      end

      it "cannot stop itself (would terminate test)" do
        # 自分自身を停止することはできないため、PIDファイルを削除できることのみ確認
        manager.cleanup_files
        expect(File.exist?(manager.pid_file_path)).to be false
      end
    end

    context "when process is not running" do
      before do
        manager.register_process
        info = manager.read_process_info
        info[:pid] = 999999
        File.write(manager.pid_file_path, JSON.pretty_generate(info))
      end

      it "cleans up files" do
        manager.stop_process
        # stop_processは存在しないプロセスの場合、cleanup_filesを呼ぶ
        expect(File.exist?(manager.pid_file_path)).to be false
      end
    end
  end

  describe "#cleanup_files" do
    before do
      manager.register_process(port: 5000)
    end

    it "removes PID and port files" do
      manager.cleanup_files
      expect(File.exist?(manager.pid_file_path)).to be false
      expect(File.exist?(manager.port_file_path)).to be false
    end
  end
end
