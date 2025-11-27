# frozen_string_literal: true

#
# WebSocket Implementation in Ruby
#
# Refoctor of original code by Hiroshi Ichikawa
# - Copyright: Hiroshi Ichikawa <http://gimite.net/en/>
# - Lincense: New BSD Lincense
#
# Recoctord by ponponusa 2025-11-24
# - Refactored WebSocket implementation (RFC 6455 only)
# - Drops support for obsolete Hixie-75/76 drafts.

require "base64"
require "socket"
require "uri"
require "digest/sha1"
require "openssl"
require "stringio"
require "securerandom"

class WebSocket
  class << self
    attr_accessor :debug
  end

  class Error < RuntimeError; end

  WEB_SOCKET_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

  # OpCodes (RFC 6455)
  OPCODE_CONTINUATION = 0x00
  OPCODE_TEXT         = 0x01
  OPCODE_BINARY       = 0x02
  OPCODE_CLOSE        = 0x08
  OPCODE_PING         = 0x09
  OPCODE_PONG         = 0x0a

  attr_reader :server, :header, :path, :socket

  def initialize(arg, params = {})
    @handshaked = false
    @received = []
    @buffer = "".b
    @closing_started = false

    if params[:server]
      init_as_server(arg, params[:server])
    else
      init_as_client(arg, params)
    end
  end

  # ハンドシェイクを実行
  def handshake(status = nil, header = {})
    raise WebSocket::Error, "handshake has already been done" if @handshaked

    status ||= "101 Switching Protocols"

    # RFC 6455 Server Handshake
    key = @header["sec-websocket-key"]
    unless key
      raise WebSocket::Error, "Client did not send Sec-WebSocket-Key"
    end

    accept_token = security_digest(key)

    def_header = {
      "Sec-WebSocket-Accept" => accept_token,
      "Connection" => "Upgrade",
      "Upgrade" => "websocket"
    }

    header = def_header.merge(header)
    header_str = header.map { |k, v| "#{k}: #{v}\r\n" }.join

    write("HTTP/1.1 #{status}\r\n#{header_str}\r\n")
    flush
    @handshaked = true
  end

  # データの送信
  def send(data)
    raise WebSocket::Error, "call WebSocket#handshake first" unless @handshaked

    # クライアントモードならマスクする(true)、サーバーならしない(false)
    should_mask = !@server
    send_frame(OPCODE_TEXT, data, should_mask)
  end

  # データの受信
  def receive
    raise WebSocket::Error, "call WebSocket#handshake first" unless @handshaked

    loop do
      frame = receive_frame
      return nil unless frame # Connection closed

      case frame[:opcode]
      when OPCODE_TEXT
        return frame[:payload].force_encoding("UTF-8")
      when OPCODE_BINARY
        raise WebSocket::Error, "received binary data, which is not supported"
      when OPCODE_CLOSE
        close(1005, "", :peer)
        return nil
      when OPCODE_PING
        send_frame(OPCODE_PONG, frame[:payload], !@server)
      when OPCODE_PONG
        # Pong受信時は特に何もしない
        next
      else
        raise WebSocket::Error, "received unknown opcode: #{frame[:opcode]}"
      end
    end
  end

  def tcp_socket
    @socket
  end

  def host
    @header["host"]
  end

  def origin
    # Origin ヘッダーが存在しない場合はデフォルト値を返す
    # 開発環境やローカルホストからの接続では Origin が送信されないことがある
    @header["origin"] || @header["sec-websocket-origin"] || (host ? "http://#{host}" : "http://localhost")
  end

  def location
    "ws://#{host}#{@path}"
  end

  def close(code = 1005, reason = "", origin = :self)
    unless @closing_started
      if code == 1005
        payload = ""
      else
        payload = [code].pack("n") + reason.dup.force_encoding("ASCII-8BIT")
      end
      send_frame(OPCODE_CLOSE, payload, !@server)
    end
    @socket.close if origin == :peer
    @closing_started = true
  end

  def close_socket
    @socket.close
  end

  private

  # ----------------------------------------------------------------
  # Initialization Logic
  # ----------------------------------------------------------------

  def init_as_server(socket, server_instance)
    @server = server_instance
    @socket = socket

    line = gets
    raise WebSocket::Error, "Client disconnected without sending anything." unless line

    line = line.chomp
    unless line =~ %r{\AGET (\S+) HTTP/1.1\z}n
      raise WebSocket::Error, "Invalid request: #{line}"
    end

    @path = ::Regexp.last_match(1)
    read_header

    unless @server.accepted_origin?(origin)
      raise WebSocket::Error, "Unaccepted origin: #{origin}"
    end
  end

  def init_as_client(arg, params)
    uri = arg.is_a?(String) ? URI.parse(arg) : arg

    default_port = (uri.scheme == "wss" ? 443 : 80)
    unless ["ws", "wss"].include?(uri.scheme)
      raise WebSocket::Error, "unsupported scheme: #{uri.scheme}"
    end

    @path = (uri.path.empty? ? "/" : uri.path) + (uri.query ? "?#{uri.query}" : "")
    host_header = uri.host + ((!uri.port || uri.port == default_port) ? "" : ":#{uri.port}")
    origin = params[:origin] || "http://#{uri.host}"

    # RFC 6455 Client Handshake
    key = Base64.strict_encode64(SecureRandom.random_bytes(16))

    tcp_sock = TCPSocket.new(uri.host, uri.port || default_port)
    @socket = (uri.scheme == "ws") ? tcp_sock : ssl_handshake(tcp_sock)

    write(
      "GET #{@path} HTTP/1.1\r\n" \
      "Host: #{host_header}\r\n" \
      "Connection: Upgrade\r\n" \
      "Upgrade: websocket\r\n" \
      "Origin: #{origin}\r\n" \
      "Sec-WebSocket-Version: 13\r\n" \
      "Sec-WebSocket-Key: #{key}\r\n" \
      "\r\n"
    )
    flush

    line = gets.chomp
    unless line =~ %r{\AHTTP/1.1 101 }n
      raise WebSocket::Error, "bad response: #{line}"
    end

    read_header

    accept = @header["sec-websocket-accept"]
    expected = security_digest(key)

    if accept != expected
      raise WebSocket::Error, "Invalid Sec-WebSocket-Accept: #{accept} != #{expected}"
    end

    @handshaked = true
  end

  # ----------------------------------------------------------------
  # Core Logic
  # ----------------------------------------------------------------

  def read_header
    @header = {}
    while (line = gets)
      line = line.chomp
      break if line.empty?

      if line =~ /\A(\S+): (.*)\z/n
        key = ::Regexp.last_match(1)
        val = ::Regexp.last_match(2)
        @header[key] = val
        @header[key.downcase] = val
      else
        raise WebSocket::Error, "invalid header: #{line}"
      end
    end

    # サーバー側の場合は必須ヘッダーをチェック
    if @server
      unless @header["upgrade"]
        raise WebSocket::Error, "Upgrade header is missing"
      end
      unless @header["upgrade"] =~ /\AWebSocket\z/i
        raise WebSocket::Error, "invalid Upgrade: #{@header['upgrade']}"
      end
      unless @header["connection"]
        raise WebSocket::Error, "Connection header is missing"
      end
      unless @header["connection"].split(/,/).any? { |v| v.strip =~ /\AUpgrade\z/i }
        raise WebSocket::Error, "invalid Connection: #{@header['connection']}"
      end
    end
  end

  def send_frame(opcode, payload, mask)
    $stderr.printf("send_frame> opcode:%d masked:%d payload:%p\n", opcode, mask ? 1 : 0, payload) if WebSocket.debug

    # frozen な文字列でも対応できるように String() で変換してから dup
    payload = payload.to_s.dup.force_encoding("ASCII-8BIT")
    buffer = StringIO.new(String.new("", encoding: "ASCII-8BIT"))

    write_byte(buffer, 0x80 | opcode) # FIN bit set (0x80) + opcode

    masked_byte = mask ? 0x80 : 0x00
    if payload.bytesize <= 125
      write_byte(buffer, masked_byte | payload.bytesize)
    elsif payload.bytesize < 2**16
      write_byte(buffer, masked_byte | 126)
      buffer.write([payload.bytesize].pack("n"))
    else
      write_byte(buffer, masked_byte | 127)
      buffer.write([payload.bytesize >> 32, payload.bytesize & 0xFFFFFFFF].pack("NN"))
    end

    if mask
      mask_key = SecureRandom.random_bytes(4).unpack("C*")
      buffer.write(mask_key.pack("C*"))
      payload = apply_mask(payload, mask_key)
    end

    buffer.write(payload)
    write(buffer.string)
  end

  def receive_frame
    # Read first 2 bytes (FIN+Opcode, Mask+Length)
    head = read(2)
    bytes = head.unpack("C*")

    fin = (bytes[0] & 0x80) != 0
    opcode = bytes[0] & 0x0f
    mask = (bytes[1] & 0x80) != 0
    plength = bytes[1] & 0x7f

    if plength == 126
      plength = read(2).unpack1("n")
    elsif plength == 127
      high, low = read(8).unpack("NN")
      plength = high * (2**32) + low
    end

    # Server must receive masked data, Client must receive unmasked data (RFC 6455)
    # But for flexibility, we strictly check only if we are the server.
    if @server && !mask
      close_socket
      raise WebSocket::Error, "received unmasked data"
    end

    mask_key = mask ? read(4).unpack("C*") : nil
    payload = read(plength)
    payload = apply_mask(payload, mask_key) if mask

    $stderr.printf("recv_frame> opcode:%d fin:%d payload:%p\n", opcode, fin ? 1 : 0, payload) if WebSocket.debug

    { opcode: opcode, payload: payload, fin: fin }
  rescue EOFError
    nil
  end

  def gets(rs = $/)
    line = @socket.gets(rs)
    $stderr.printf("recv> %p\n", line) if WebSocket.debug
    line
  end

  def read(num_bytes)
    return "" if num_bytes == 0
    str = @socket.read(num_bytes)
    $stderr.printf("recv> %p\n", str) if WebSocket.debug

    if str && str.bytesize == num_bytes
      str
    else
      raise EOFError
    end
  end

  def write(data)
    if WebSocket.debug
      # Debug logging
      if data.size < 100
        $stderr.printf("send> %p\n", data)
      else
        $stderr.printf("send> (binary data %d bytes)\n", data.size)
      end
    end
    @socket.write(data)
  end

  def flush
    @socket.flush
  end

  def write_byte(buffer, byte)
    buffer.write([byte].pack("C"))
  end

  def security_digest(key)
    Base64.encode64(Digest::SHA1.digest(key + WEB_SOCKET_GUID)).strip
  end

  def apply_mask(payload, mask_key)
    return payload unless mask_key
    orig_bytes = payload.unpack("C*")
    new_bytes = orig_bytes.map.with_index { |b, i| b ^ mask_key[i % 4] }
    new_bytes.pack("C*")
  end

  def ssl_handshake(socket)
    ssl_context = OpenSSL::SSL::SSLContext.new
    ssl_socket = OpenSSL::SSL::SSLSocket.new(socket, ssl_context)
    ssl_socket.sync_close = true
    ssl_socket.connect
    ssl_socket
  end
end

class WebSocketServer
  attr_reader :tcp_server, :port, :accepted_domains

  def initialize(params_or_uri, params = nil)
    if params
      uri = params_or_uri.is_a?(String) ? URI.parse(params_or_uri) : params_or_uri
      params[:port] ||= uri.port
      params[:accepted_domains] ||= [uri.host]
    else
      params = params_or_uri
    end

    @port = params[:port] || 80
    @accepted_domains = params[:accepted_domains]

    raise ArgumentError, "params[:accepted_domains] is required" unless @accepted_domains

    host = params[:host] || "0.0.0.0" # Default bind to all interfaces
    @tcp_server = TCPServer.open(host, @port)
  end

  def run
    @run_threads = []
    loop do
      client = accept
      @run_threads << Thread.start(client) do |s|
        ws = nil
        begin
          ws = create_web_socket(s)
          yield(ws) if ws
        rescue => ex
          print_backtrace(ex)
        ensure
          begin
            ws&.close_socket
          rescue StandardError
            # ignore
          end
        end
      end
    end
  end

  def quit
    @run_threads.each(&:kill)
  end

  def accept
    @tcp_server.accept
  end

  def accepted_origin?(origin)
    domain = origin_to_domain(origin)
    @accepted_domains.any? { |d| File.fnmatch(d, domain) }
  end

  def origin_to_domain(origin)
    if origin == "null" || origin == "file://"
      "null"
    else
      URI.parse(origin).host
    end
  end

  def create_web_socket(socket)
    # Hixie-76 の Flash Policy File 対応は削除 (現代のブラウザでは不要)
    WebSocket.new(socket, server: self)
  end

  private

  def print_backtrace(ex)
    $stderr.printf("%s: %s (%p)\n", ex.backtrace[0], ex.message, ex.class)
    ex.backtrace[1..-1].each do |s|
      $stderr.printf("        %s\n", s)
    end
  end
end

# ----------------------------------------------------------------------
# Sample Run Logic
# ----------------------------------------------------------------------
if __FILE__ == $0
  Thread.abort_on_exception = true

  if ARGV[0] == "server" && ARGV.size == 3
    server = WebSocketServer.new(accepted_domains: [ARGV[1]], port: ARGV[2].to_i)
    puts "Server is running at port #{server.port}"

    server.run do |ws|
      puts "Connection accepted"
      puts "Path: #{ws.path}, Origin: #{ws.origin}"

      if ws.path == "/"
        ws.handshake
        while data = ws.receive
          printf("Received: %p\n", data)
          ws.send(data)
          printf("Sent: %p\n", data)
        end
      else
        ws.handshake("404 Not Found")
      end
      puts "Connection closed"
    end

  elsif ARGV[0] == "client" && ARGV.size == 2
    client = WebSocket.new(ARGV[1])
    puts "Connected"

    Thread.new do
      while data = client.receive
        printf("Received: %p\n", data)
      end
    end

    $stdin.each_line do |line|
      data = line.chomp
      client.send(data)
      printf("Sent: %p\n", data)
    end

  else
    $stderr.puts "Usage:"
    $stderr.puts "  ruby web_socket.rb server ACCEPTED_DOMAIN PORT"
    $stderr.puts "  ruby web_socket.rb client ws://HOST:PORT/"
    exit(1)
  end
end