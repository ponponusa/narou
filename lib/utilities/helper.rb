# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "erb"
require "open3"
require "time"
require "systemu"
require "shellwords"

#
# 雑多なお助けメソッド群
#
module Helper
  module_function

  HOST_OS = RbConfig::CONFIG["host_os"].freeze
  FILENAME_LENGTH_LIMIT = 50
  FOLDER_LENGTH_LIMIT = 50

  # OS判定結果をメモ化（一度だけ計算）
  def current_os
    @current_os ||= detect_os
  end

  def detect_os
    return :docker  if in_docker?
    return :windows if Gem.win_platform?
    return :cygwin  if HOST_OS =~ /cygwin/i
    return :mac     if HOST_OS =~ /darwin/i
    return :wsl     if wsl_environment?
    :linux
  end
  private_class_method :detect_os

  def in_docker?
    return false unless File.exist?("/proc/1/cgroup")
    File.read("/proc/1/cgroup").include?("/docker/") ||
      File.read("/proc/1/cgroup").include?("/lxc/")
  rescue Errno::ENOENT, Errno::EACCES
    false
  end

  def wsl_environment?
    return true if ENV.key?("WSL_DISTRO_NAME")
    File.read("/proc/version").include?("Microsoft")
  rescue Errno::ENOENT, Errno::EACCES
    false
  end

  # 便利メソッド（後方互換性）
  def os_windows?
    current_os == :windows
  end

  def os_mac?
    current_os == :mac
  end

  def os_cygwin?
    current_os == :cygwin
  end

  def os_wsl?
    current_os == :wsl
  end

  def os_linux?
    current_os == :linux
  end

  # 後方互換性のためのエイリアス
  def determine_os
    current_os
  end

  def engine_jruby?
    @@engine_is_jruby ||= RUBY_ENGINE == "jruby"
  end

  if engine_jruby? && os_windows?
    require "lib/extensions/windows"
    def $stdin.getch
      WinAPI._getch.chr
    end
  else
    require "io/console"
  end

  def open_browser_linux(address, error_message)
    %w(xdg-open firefox w3m).each do |browser|
      next unless command_available?(browser)
      # 配列形式でsystemを呼び出すことでシェルインジェクションを防止
      system(browser, address)
      return if $?.success?
    end
    warn error_message
  end

  def open_directory(path, confirm_message = nil)
    if confirm_message && !Narou::Input.confirm(confirm_message, false, false)
      return
    end
    case determine_os
    when :windows
      # 配列形式でコマンドインジェクションを防止
      system("explorer", "file:///#{path}".encode(Encoding::Windows_31J))
    when :cygwin
      system("cygstart", path)
    when :mac
      system("open", path)
    when :wsl
      open_directory_wsl(path, "フォルダが開けませんでした")
    else
      open_browser_linux(path, "フォルダが開けませんでした")
    end
  end

  def open_browser(url)
    case determine_os
    when :windows
      escaped_url = url.gsub("%", "%^").gsub("&", "^&")
      # MEMO: start の引数を "" で囲むと動かない
      system(%!start #{escaped_url}!)
    when :cygwin
      system(%!cygstart #{url}!)
    when :mac
      system(%!open "#{url}"!)
    when :wsl
      open_browser_wsl(url, "ブラウザが見つかりませんでした")
    else
      open_browser_linux(url, "ブラウザが見つかりませんでした")
    end
  end

  def open_browser_wsl(url, error_message)
    if command_available?("wslview")
      system("wslview", url)
      return if $?.success?
    end
    escaped = url.gsub("'", "''")
    begin
      system("powershell.exe", "-NoProfile", "-Command", "Start-Process '#{escaped}'")
      return if $?.success?
    rescue Errno::ENOENT
      # powershell.exe が見つからない場合は警告にフォールバック
    end
    warn error_message
  end

  def open_directory_wsl(path, error_message)
    if command_available?("wslview")
      system("wslview", path)
      return if $?.success?
    end
    begin
      # Open3.capture2を使用してシェルインジェクションを防止
      windows_path, status = Open3.capture2("wslpath", "-w", path)
      windows_path = windows_path.strip
      windows_path = path if windows_path.empty?
    rescue Errno::ENOENT
      windows_path = path
    end
    begin
      # PowerShellコマンドを配列形式で実行してインジェクションを防止
      system("powershell.exe", "-NoProfile", "-Command", "Start-Process", "-FilePath", windows_path)
      return if $?.success?
    rescue Errno::ENOENT
      # powershell.exe が見つからない場合は警告にフォールバック
    end
    warn error_message
  end

  def command_available?(command)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |path|
      executable = File.join(path, command)
      File.executable?(executable) && !File.directory?(executable)
    end
  end

  HR_TEXT = "―" * 35

  def print_horizontal_rule(io = $stdout)
    io.puts HR_TEXT
  end

  def replace_filename_special_chars(str, invalid_replace = false)
    result = str.tr("/:*?\"<>[]{}|.`", "／：＊？”〈〉［］｛｝｜．｀").gsub("\\", "￥").gsub("\t", "").gsub("\n", "")
    if Inventory.load("local_setting")["normalize-filename"]
      begin
        result.unicode_normalize!
      rescue Encoding::CompatibilityError
      end
    end
    if invalid_replace
      org_encoding = result.encoding
      result = result.encode(Encoding::Windows_31J, invalid: :replace, undef: :replace, replace: "_")
                     .encode(org_encoding)
    end
    result
  end

  #
  # ダウンロードした文字列をエンコード及び不正な文字列除去、改行コード統一
  #
  def pretreatment_source(src, encoding = Encoding::UTF_8)
    encoding_class = Encoding.find(encoding)
    src.force_encoding(encoding)
       .tap do |this|
         if encoding_class != Encoding::UTF_8
           this.encode!(Encoding::UTF_8, invalid: :replace, undef: :replace)
         end
       end
       .scrub("?")
       .gsub("\r", "")
       .gsub(/&#x([0-9a-f]+);/i) { [$1.hex].pack("U") }
       .gsub(/&#(\d+);/) { [$1.to_i].pack("U") }
  end

  ENTITIES = { quot: '"', amp: "&", nbsp: " ", lt: "<", gt: ">", copy: "(c)", "#39" => "'" }
  #
  # エンティティ復号
  #
  def restore_entity(str)
    result = str.dup
    ENTITIES.each do |key, value|
      result.gsub!("&#{key};", value)
    end
    result
  end

  #
  # CYGWINのパスからwindowsのパスへと変換(cygpathを呼び出すだけ)
  #
  def convert_to_windows_path(path)
    `cygpath -aw \"#{path}\"`.strip
  end

  #
  # アンパサンドをエンティティに変換
  #
  def ampersand_to_entity(str)
    str.gsub(/&(?!amp;)/mi, "&amp;")
  end

  #
  # 文章の中から挿絵注記を分離する
  #
  def extract_illust_chuki(str)
    illust_chuki_array = []
    extracted_str = str.gsub(/[ 　\t]*?(［＃挿絵（.+?）入る］)\n?/) do
      illust_chuki_array << $1
      ""
    end
    [extracted_str, illust_chuki_array]
  end

  class InvalidVariableType < StandardError
    def initialize(type)
      super("値が #{Helper.variable_type_to_description(type).rstrip} ではありません")
    end
  end

  class UnknownVariableType < StandardError
    def initialize(type)
      super("unknwon variable type (:#{type})")
    end
  end

  class InvalidVariableName < StandardError; end

  #
  # 与えられた型情報の意味文字列を取得
  #
  def variable_type_to_description(type)
    case type
    when :boolean
      "true/false  "
    when :integer
      "整数        "
    when :float
      "小数点数    "
    when :string, :select
      "文字列      "
    when :multiple
      "文字列(複数)"
    when :directory
      "フォルダパス"
    when :file
      "ファイルパス"
    else
      raise UnknownVariableType, type
    end
  end

  #
  # 文字列データを指定された型にキャストする
  #
  def string_cast_to_type(value, type)
    result = nil
    case type
    when :boolean
      case value.strip.downcase
      when "true"
        result = true
      when "false"
        result = false
      else
        raise InvalidVariableType, type
      end
    when :integer
      begin
        result = Integer(value)
      rescue StandardError
        raise InvalidVariableType, type
      end
    when :float
      begin
        result = Float(value)
      rescue StandardError
        raise InvalidVariableType, type
      end
    when :directory, :file
      raise InvalidVariableType, type unless File.method("#{type}?").call(value)
      result = File.expand_path(value)

    when :string, :select, :multiple
      result = value
    else
      raise UnknownVariableType, type
    end
    result
  end

  INTEGER_CLASS = RUBY_VERSION >= "2.4.0" ? Integer : Integer
  TYPE_OF_VALUE = {
    TrueClass => :boolean, FalseClass => :boolean, INTEGER_CLASS => :integer,
    Float => :float, String => :string
  }

  #
  # Rubyの変数がなんの型かシンボルで取得
  #
  def type_of_value(value)
    TYPE_OF_VALUE[value.class]
  end

  #
  # ファイルを指定したディレクトリにまとめてコピーする
  # 指定したディレクトリが存在しなければ作成する
  #
  # from: ファイルパスをまとめた Array
  # dest_dir: コピー先のディレクトリ
  # check_timestamp: タイムスタンプを比較して新しければコピーする
  #
  def copy_files(from, dest_dir, check_timestamp: true, exception: true)
    from.each do |path|
      basename = File.basename(path)
      dirname = File.basename(File.dirname(path))
      save_dir = File.join(dest_dir, dirname)
      unless File.directory?(save_dir)
        FileUtils.mkdir_p(save_dir)
      end
      dest = File.join(save_dir, basename)
      if check_timestamp && File.exist?(dest)
        src_mtime = File.mtime(path)
        dest_mtime = File.mtime(dest)
        next if dest_mtime >= src_mtime
      end
      begin
        FileUtils.copy(path, dest)
      rescue StandardError => e
        raise if exception
        error "#{path} はコピー出来ませんでした"
      end
    end
  end

  #
  # 日付形式の文字列をTime型に変換する
  #
  def date_string_to_time(date)
    case date
    when Time
      date
    when String
      Time.parse(date.sub(/[(（].+?[)）]/, "").tr("年月日時分秒@;", "///::: :")).getlocal
    end
  rescue ArgumentError
    nil
  end

  #
  # 指定のファイルが前回のチェック時より新しいかどうか
  #
  # 初回チェック時は無条件で新しいと判定
  #
  def file_latest?(path)
    @@file_mtime_list ||= {}
    fullpath = File.expand_path(path)
    last_mtime = @@file_mtime_list[fullpath]
    mtime = File.mtime(fullpath)
    if mtime == last_mtime
      result = false
    else
      result = true
      @@file_mtime_list[fullpath] = mtime
    end
    result
  end

  #
  # 伏せ字にする
  #
  # 数字やスペース、句読点、感嘆符はそのままにする
  #
  def to_unprintable_words(string, mask = "●")
    result = +""
    string.each_char do |char|
      result += case char
                when /[0-9０-９ 　、。!?！？]/
                  char
                else
                  mask
                end
    end
    result
  end

  #
  # 長過ぎるファイルパスを詰める
  # ファイル名部分のみを詰める。拡張子は維持する
  #
  def truncate_path(path, limit = Inventory.load["filename-length-limit"], extname: nil)
    limit ||= FILENAME_LENGTH_LIMIT
    dirname = File.dirname(path)
    extname ||= File.extname(path)
    basename = File.basename(path, extname)
    if basename.length > limit
      basename = basename[0...limit]
      dirname = nil if dirname == "."
      [dirname, "#{basename}#{extname}"].compact.join("/")
    else
      path
    end
  end

  def truncate_folder_title(title, limit = Inventory.load["folder-length-limit"])
    limit ||= FOLDER_LENGTH_LIMIT
    return title if title.length <= limit
    title[0...limit].strip
  end

  #
  # src をERBとして読み込んでから dst に書き出す
  #
  def erb_copy(src, dst, _binding)
    data = File.read(src, mode: "r:BOM|UTF-8")
    result = ERB.new(data, trim_mode: "-").result(_binding)
    File.write(dst, result)
  end

  #
  # カンマ付き数字列を数値に変換
  #
  def numeric_length(len)
    return len unless len.is_a?(String)
    len.delete(",").to_i
  end

  #
  # 外部コマンド実行中の待機ループの処理を書けるクラス
  #
  # 返り値：[標準出力のキャプチャ, 標準エラーのキャプチャ, Process::Status]
  #
  # response = Helper::AsyncCommand.exec("処理に時間がかかる外部コマンド") do
  #   print "*"
  # end
  # if response[2].success?
  #   puts "成功しました"
  # end
  #
  class AsyncCommand
    def self.exec(command, sleep_time = 0.5, &block)
      looper = nil
      _pid = nil
      status, stdout, stderr = systemu(command) do |pid|
        _pid = pid
        looper = Thread.new(pid) do |pid|
          loop do
            block.call if block
            sleep(sleep_time)
            next unless Narou::Worker.canceled?
            next unless Narou::WebWorker.canceled?
            Process.kill("KILL", pid)
            Process.detach(pid)
            break
          end
        end
        looper.join
        looper = nil
      end
      stdout.force_encoding(Encoding::UTF_8)
      stderr.force_encoding(Encoding::UTF_8)
      [stdout, stderr, status]
    rescue RuntimeError => e
      raise unless e.message.include?("interrupted")
      process_kill(_pid)
      raise Interrupt
    rescue Interrupt
      process_kill(_pid)
      raise
    ensure
      looper&.kill
    end

    def self.process_kill(pid)
      return unless pid
      Process.kill("KILL", pid)
      Process.detach(pid) # 死亡確認しないとゾンビ化する
    rescue StandardError
    end
  end

  #
  # 更新時刻を考慮したファイルのローダー
  #
  module CacheLoader
    module_function

    @@mutex = Mutex.new
    @@caches = {}
    @@result_caches = {}
    @@cache_access_order = []
    @@result_cache_access_order = []

    # キャッシュサイズ制限（メモリ使用量制限）
    MAX_CACHE_SIZE = 100 # ファイル数制限
    MAX_RESULT_CACHE_SIZE = 50 # 結果キャッシュ数制限

    DEFAULT_OPTIONS = { mode: "r:BOM|UTF-8" }

    #
    # ファイルの更新時刻を考慮してファイルのデータを取得する。
    # 前回取得した時からファイルが変更されていない場合は、キャッシュを返す
    #
    # options にはファイルを読み込む時に File.read に渡すオプションを指定できる
    #
    def load(path, options = DEFAULT_OPTIONS)
      @@mutex.synchronize do
        fullpath = File.expand_path(path)
        cache_data = @@caches[fullpath]
        if Helper.file_latest?(fullpath) || !cache_data
          body = File.read(fullpath, **options)
          # LRU キャッシュの実装
          @@caches[fullpath] = body
          @@cache_access_order.delete(fullpath)
          @@cache_access_order.push(fullpath)

          # キャッシュサイズ制限
          if @@caches.size > MAX_CACHE_SIZE
            oldest = @@cache_access_order.shift
            @@caches.delete(oldest)
          end

          return body
        else
          # アクセス順を更新
          @@cache_access_order.delete(fullpath)
          @@cache_access_order.push(fullpath)
          return cache_data
        end
      end
    end

    #
    # ファイルを処理するブロックの結果をキャッシュ化する
    #
    # CacheLoader.load がファイルの中身だけをキャッシュ化するのに対して
    # これはブロックの結果をキャッシュする。ファイルが更新されない限り、
    # ブロックの結果は変わらない
    #
    # ex.)
    # Helper::CacheLoader.memo("filepath") do |data|
    #   # data に関する処理
    #   result  # ここで nil を返すと次回も再度読み込まれる
    # end
    #
    def memo(path, options = DEFAULT_OPTIONS, &block)
      @@mutex.synchronize do
        raise ArgumentError, "need a block" unless block
        fullpath = File.expand_path(path)
        key = generate_key(fullpath, block)
        cache = @@result_caches[key]
        if Helper.file_latest?(fullpath) || !cache
          data = File.read(fullpath, **options)
          result = block.call(data)

          # 結果キャッシュのLRU実装
          @@result_caches[key] = result
          @@result_cache_access_order.delete(key)
          @@result_cache_access_order.push(key)

          # 結果キャッシュサイズ制限
          if @@result_caches.size > MAX_RESULT_CACHE_SIZE
            oldest = @@result_cache_access_order.shift
            @@result_caches.delete(oldest)
          end

          return result
        else
          # アクセス順を更新
          @@result_cache_access_order.delete(key)
          @@result_cache_access_order.push(key)
          return cache
        end
      end
    end

    #
    # キャッシュを格納する際に必要なキーを生成する
    #
    # ブロックはその場所が実行されるたびに違うprocオブジェクトが生成されるため、
    # 同一性判定のために「どのソース」の「何行目」かで判定を行う
    #
    def generate_key(fullpath, block)
      src, line = block.source_location
      "#{fullpath}:#{src}:#{line}"
    end

    #
    # 指定したファイルのキャッシュを削除する
    #
    # path を指定しなかった場合、全てのキャッシュを削除する
    #
    def clear(path = nil)
      @@mutex.synchronize do
        if path
          fullpath = File.expand_path(path)
          @@caches.delete(fullpath)
          @@cache_access_order.delete(fullpath)
          # 結果キャッシュも該当ファイルのものを削除
          @@result_caches.delete_if { |key, _| key.start_with?("#{fullpath}:") }
          @@result_cache_access_order.delete_if { |key| key.start_with?("#{fullpath}:") }
        else
          @@caches.clear
          @@result_caches.clear
          @@cache_access_order.clear
          @@result_cache_access_order.clear
        end
      end
    end

    #
    # キャッシュサイズ情報を取得する（デバッグ用）
    #
    def cache_stats
      @@mutex.synchronize do
        {
          file_cache_size: @@caches.size,
          result_cache_size: @@result_caches.size,
          file_cache_limit: MAX_CACHE_SIZE,
          result_cache_limit: MAX_RESULT_CACHE_SIZE
        }
      end
    end

    #
    # メモリ使用量が多い場合に強制的にキャッシュを削減する
    #
    def force_cleanup(target_size_ratio = 0.5)
      @@mutex.synchronize do
        # ファイルキャッシュを半分に削減
        target_file_size = (@@caches.size * target_size_ratio).to_i
        while @@caches.size > target_file_size && !@@cache_access_order.empty?
          oldest = @@cache_access_order.shift
          @@caches.delete(oldest)
        end

        # 結果キャッシュを半分に削減
        target_result_size = (@@result_caches.size * target_size_ratio).to_i
        while @@result_caches.size > target_result_size && !@@result_cache_access_order.empty?
          oldest = @@result_cache_access_order.shift
          @@result_caches.delete(oldest)
        end
      end
    end
  end
end
