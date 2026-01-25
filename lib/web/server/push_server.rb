# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "json"
require "singleton"
require "lib/web/workers/web_socket"
require "lib/utilities/eventable"

module Narou
  class PushServer
    include Singleton
    include Eventable

    HISTORY_SAVED_COUNT = 60 # 保存する履歴の数

    attr_accessor :port, :host
    attr_reader :accepted_domains, :connections

    def accepted_domains=(domains)
      @accepted_domains = Array(domains)
    end

    def initialize
      @accepted_domains = ["*"]
      @port = 31000
      @connections = []
      @server_thread = nil
      clear_history
    end

    def running?
      !@server_thread.nil? && @server_thread.alive?
    end

    def run
      @server = WebSocketServer.new({
        accepted_domains: @accepted_domains,
        port: @port,
        host: @host
      })
      @server_thread = Thread.new do
        @server.run do |ws|
          que = nil
          thread = nil
          begin
            ws.handshake
            que = Queue.new
            @connections.push(que)

            # 接続時に履歴を送信（タイムスタンプ付き）
            history_count = @history.compact.size
            $stderr.puts "[PushServer] Sending #{history_count} history messages to new connection" if $DEBUG
            begin
              @history.compact.each do |message|
                ws.send(JSON.generate(echo: message))
              end
            rescue Errno::ECONNRESET, Errno::EPIPE, IOError
              # 履歴送信中に接続が切れた場合は無視して続行
            end

            thread = Thread.new do
              while true
                data = que.pop
                ws.send(data)
              end
            rescue Errno::ECONNRESET, Errno::EPIPE, IOError => e
              # 接続が切れた場合、スレッドを終了
            rescue => e
              # その他のエラーもログに出力してスレッド終了
              puts "[ERROR] WebSocket send thread error: #{e.class}: #{e.message}" if $DEBUG
            end

            while data = ws.receive
              begin
                JSON.parse(data).each do |name, value|
                  trigger(name, value, ws)
                end
              rescue JSON::ParserError => e
                ws.send(JSON.generate(echo: {
                  target_console: "#console",
                  body: e.message
                }))
              end
            end
          rescue WebSocket::Error => e
            # WebSocketハンドシェイクエラー（通常はクライアントの切断）
            $stderr.puts "[PushServer] WebSocket error: #{e.message}" if $DEBUG
            $stderr.puts e.backtrace.first(5).join("\n") if $DEBUG
          rescue Errno::ECONNRESET, Errno::ECONNABORTED, Errno::EPIPE, IOError => e
            # 接続リセット/中断エラー（デバッグ時のみ出力）
            $stderr.puts "[PushServer] Connection closed: #{e.message}" if $DEBUG
          rescue StandardError => e
            # その他の予期しないエラー（常に出力）
            $stderr.puts "[PushServer] Unexpected error: #{e.class}: #{e.message}"
            $stderr.puts e.backtrace.first(5).join("\n")
          ensure
            @connections.delete(que) if que
            thread.terminate if thread
          end
        end
      end
    end

    #
    # PushServer を停止させる
    #
    def quit
      @server.quit if @server
      if @server_thread && @server_thread.alive?
        @server_thread.kill
        @server_thread.join(1) # 最大1秒待つ
      end
    end

    def clear_history
      history_count = @history ? @history.compact.size : 0
      $stderr.puts "[PushServer] Clearing history (#{history_count} messages)" if $DEBUG
      @history = [nil] * HISTORY_SAVED_COUNT
      # 接続中のクライアントにクリアイベントを送信
      if @connections && @connections.size > 0
        $stderr.puts "[PushServer] Sending console.clear to #{@connections.size} connections" if $DEBUG
        send_all(:"console.clear")
      end
      # Sinatra で get "/" { clear_history } とかやった場合に [nil,nil...] な配列データが
      # 渡されないようにするため（配列は Sinatra にとって特別なデータ）
      true
    end

    #
    # 接続している全てのクライアントに対してメッセージを送信
    #
    def send_all(data)
      if data.is_a?(Symbol)
        # send_all(:"events.name") としてイベント名だけで送りたい場合の対応
        data = { data => true }
      end
      json = JSON.generate(data)
      $stderr.puts "[PushServer] send_all: #{data.keys.first} to #{@connections.size} connections" if $DEBUG && !data[:echo]
      @connections.each do |queue_of_connection|
        queue_of_connection.push(json)
      end
      # echo 以外のイベントは履歴に保存しない
      message = data[:echo]
      if message
        stack_to_history(message)
      end
    rescue JSON::GeneratorError => e
      STDERR.puts $@.shift + ": #{e.message} (#{e.class})"
    end

    def stack_to_history(message)
      return if message[:no_history]
      # タイムスタンプを追加（ISO8601形式）
      message_with_timestamp = message.merge(timestamp: Time.now.iso8601(3))
      if message[:body] == "." && (last = @history[-1]) && last[:body] =~ /\A\.+\z/
        # 進行中を表す .... の出力でヒストリーが消費されるのを防ぐため、
        # 連続した . は一つにまとめる
        last[:body] = "#{last[:body]}."
        last[:timestamp] = Time.now.iso8601(3) # タイムスタンプも更新
      else
        @history.push(message_with_timestamp)
        @history.shift
      end
    end
  end
end
