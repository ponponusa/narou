# frozen_string_literal: true

#
# Copyright 2025 ponponusa
#
# プロセス管理とポート競合検出を行うモジュール
#

require "fileutils"
require "json"
require "socket"
require "lib/utilities/helper"

module Narou
  class ProcessManager
    class ProcessConflictError < StandardError; end
    class PortConflictError < StandardError; end

    attr_reader :pid_file_path, :port_file_path

    def initialize(service_name)
      @service_name = service_name
      @pid_dir = File.join(Narou.tmp_dir, "pids")
      @pid_file_path = File.join(@pid_dir, "#{@service_name}.pid")
      @port_file_path = File.join(@pid_dir, "#{@service_name}.port")

      ensure_directories
    end

    # 現在のプロセスのPIDを記録
    # pid: 登録するプロセスのPID（未指定時は現在のプロセス）
    def register_process(pid: nil, port: nil, metadata: {})
      ensure_directories

      target_pid = pid || Process.pid

      pid_data = {
        pid: target_pid,
        ppid: pid ? nil : Process.ppid, # 外部プロセスの場合はppidを記録しない
        started_at: Time.now.iso8601,
        platform: RUBY_PLATFORM,
        ruby_version: RUBY_VERSION,
        service: @service_name,
        port: port,
        metadata: metadata
      }

      File.write(@pid_file_path, JSON.pretty_generate(pid_data))
      File.write(@port_file_path, port.to_s) if port

      pid_data
    end

    # プロセス情報を読み込み
    def read_process_info
      return nil unless File.exist?(@pid_file_path)

      begin
        content = File.read(@pid_file_path)
        parsed = JSON.parse(content, symbolize_names: true)

        # 古い形式（整数のみ）の場合はHashに変換
        if parsed.is_a?(Integer)
          { pid: parsed }
        else
          parsed
        end
      rescue JSON::ParserError, Errno::ENOENT
        # JSON以外（生の整数など）の場合も対応
        begin
          pid = content.strip.to_i
          pid > 0 ? { pid: pid } : nil
        rescue
          nil
        end
      end
    end

    # プロセスが実行中かチェック
    def process_running?(pid = nil)
      if pid.nil?
        info = read_process_info
        return false unless info
        pid = info[:pid]
      end

      return false unless pid

      begin
        # kill 0 はシグナルを送らず、プロセスの存在確認のみ行う
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH, Errno::EPERM, RangeError
        # ESRCH: プロセスが存在しない
        # EPERM: 権限がない（他のユーザーのプロセス）
        # RangeError: 無効なPID
        false
      end
    end

    # ポートが使用中かチェック
    def port_in_use?(port, host = "127.0.0.1")

      server = TCPServer.new(host, port)
      server.close
      false
    rescue Errno::EADDRINUSE
      true
    rescue Errno::EACCES
      # 権限エラー（1024未満のポート等）
      true

    end

    # 既存プロセスが存在する場合にクリーンアップを試みる
    def cleanup_stale_process!
      info = read_process_info
      return unless info

      pid = info[:pid]

      # プロセスが実行中でない場合はPIDファイルを削除
      unless process_running?(pid)
        cleanup_files
        return
      end

      # プロセスが実行中の場合
      raise ProcessConflictError, <<~MSG
        サービス '#{@service_name}' は既に起動しています (PID: #{pid})

        プロセス情報:
        - 起動時刻: #{info[:started_at]}
        - ポート: #{info[:port]}
        - プラットフォーム: #{info[:platform]}

        停止するには以下のコマンドを実行してください:
          kill #{pid}
        または
          ./scripts/process_control.sh --kill --force
      MSG
    end

    # ポート競合をチェックして、必要に応じてエラーを発生
    def check_port_conflict!(port, host = "127.0.0.1")
      return unless port_in_use?(port, host)

      # ポートを使用しているプロセスを特定
      process_info = find_process_using_port(port)

      error_msg = <<~MSG
        ポート #{port} は既に使用されています。

      MSG

      if process_info
        error_msg += <<~MSG
          使用しているプロセス:
          #{process_info}

        MSG
      end

      error_msg += <<~MSG
        以下のいずれかの対処を行ってください:
        1. ポートを使用しているプロセスを停止する
        2. 別のポートを指定する（--port オプション）
        3. ./scripts/process_control.sh を実行して関連プロセスをクリーンアップする
      MSG

      raise PortConflictError, error_msg
    end

    # プロセスを停止
    def stop_process(signal: "TERM", timeout: 10)
      info = read_process_info
      return false unless info

      pid = info[:pid]
      pgid = info.dig(:metadata, :pgid) # プロセスグループID（Unix系のみ）

      # プロセスが既に終了している場合はクリーンアップのみ
      unless process_running?(pid)
        cleanup_files
        return false
      end

      begin
        if Helper.os_windows?
          # Windows: taskkill で子プロセスも含めて終了
          # /T: 子プロセスも終了, /F: 強制終了
          system("taskkill /PID #{pid} /T /F >NUL 2>&1")
          sleep 0.5
          cleanup_files
          return true
        end

        # Unix系: プロセスグループIDがある場合はグループごと停止
        target_pid = pgid || pid

        # シグナルを送信
        Process.kill(signal, target_pid)

        # タイムアウトまで待機
        deadline = Time.now + timeout
        while Time.now < deadline
          unless process_running?(pid)
            cleanup_files
            return true
          end
          sleep 0.1
        end

        # タイムアウトした場合は強制終了
        if process_running?(pid)
          Process.kill("KILL", target_pid)
          sleep 0.5
          cleanup_files
        end

        true
      rescue Errno::ESRCH, Errno::EPERM
        cleanup_files
        false
      end
    end

    # PIDファイルとポートファイルをクリーンアップ
    def cleanup_files
      File.delete(@pid_file_path) if File.exist?(@pid_file_path)
      File.delete(@port_file_path) if File.exist?(@port_file_path)
    end

    # ポートを使用しているプロセスを検索（プラットフォーム依存）
    def find_process_using_port(port)
      if RUBY_PLATFORM =~ /linux/
        find_process_linux(port)
      elsif RUBY_PLATFORM =~ /darwin/
        find_process_macos(port)
      elsif RUBY_PLATFORM =~ /mswin|mingw|cygwin/
        find_process_windows(port)
      end
    end

    private

    def ensure_directories
      FileUtils.mkdir_p(@pid_dir) unless File.exist?(@pid_dir)
    end

    def find_process_linux(port)
      # lsof または ss コマンドでポートを使用しているプロセスを検索
      output = `lsof -i :#{port} -t 2>/dev/null`.strip
      return nil if output.empty?

      pid = output.lines.first&.strip&.to_i
      return nil unless pid

      # プロセス情報を取得
      cmd = `ps -p #{pid} -o pid,ppid,user,command --no-headers 2>/dev/null`.strip
      cmd.empty? ? "PID: #{pid}" : cmd
    rescue Errno::ENOENT, StandardError
      # lsof コマンドがない場合や、その他のエラー
      nil
    end

    def find_process_macos(port)
      # lsof コマンドでポートを使用しているプロセスを検索
      output = `lsof -i :#{port} -t 2>/dev/null`.strip
      return nil if output.empty?

      pid = output.lines.first&.strip&.to_i
      return nil unless pid

      # プロセス情報を取得
      cmd = `ps -p #{pid} -o pid,ppid,user,command 2>/dev/null`.lines[1]&.strip
      cmd || "PID: #{pid}"
    rescue Errno::ENOENT, StandardError
      nil
    end

    def find_process_windows(port)
      # netstat コマンドでポートを使用しているプロセスを検索
      output = `netstat -ano | findstr :#{port}`.strip
      return nil if output.empty?

      # PIDを抽出（最後のカラム）
      pid = output.lines.first&.split&.last&.to_i
      return nil unless pid || pid == 0

      # tasklist でプロセス情報を取得
      task_output = `tasklist /FI "PID eq #{pid}" /FO CSV /NH`.strip
      task_output.empty? ? "PID: #{pid}" : task_output
    rescue Errno::ENOENT, StandardError
      nil
    end
  end
end
