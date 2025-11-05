# frozen_string_literal: true
#
# Lazy loader for stdlib / common gems used in Narou.rb
#
# 使い方:
#  1) このファイルを `lib/lazy.rb` として配置
#  2) 各ファイルの先頭で、以下のように宣言
#       require_relative "lazy"
#       Lazy.use :yaml, :fileutils, :open3, :tempfile
#     ※ 明示しておくことで、可読性を維持したままオートロードされます。
#  3) よく使うセットは `Lazy.use_default!` で一括登録可能
#
# 仕組み:
#   SPECの定義に基づき、対象モジュール/クラス名に autoload を設定します。
#   実際に参照された瞬間に require されます（スレッド非依存のCLI前提）。
#
module Lazy
  module_function

  # ===== 対象定義 =====
  # into: autoload を設定する親モジュール/クラス（Object か、Symbol/Module）
  # const: 対象の定数名（Symbol）
  # file:  require するパス（String）
  SPEC = {
    # 軽いが依存の多いものは遅延対象に含める
    yaml:       { into: Object, const: :YAML,      file: "yaml" },
    erb:        { into: Object, const: :ERB,       file: "erb" },
    fileutils:  { into: Object, const: :FileUtils, file: "fileutils" },
    stringio:   { into: Object, const: :StringIO,  file: "stringio" },
    date:       { into: Object, const: :Date,      file: "date" },
    pathname:   { into: Object, const: :Pathname,  file: "pathname" },
    weakref:    { into: Object, const: :WeakRef,   file: "weakref" }, 

    # コスト中〜高: 遅延の効果が大きい
    tmpdir:     { into: Dir,     const: :Tmpname,  file: "tmpdir" },
    tempfile:   { into: Object, const: :Tempfile,  file: "tempfile" },
    diff_lcs:   { into: Object, const: :Diff,      file: "diff/lcs" },
    open3:      { into: Object, const: :Open3,     file: "open3" },
    termcolorlight: { into: Object, const: :TermColorLight, file: "termcolorlight" },

    # よく使う周辺
    json:       { into: Object, const: :JSON,      file: "json" },
    rexml:      { into: Object, const: :REXML,     file: "rexml/document" },
    nkf:        { into: Object, const: :NKF,       file: "nkf" },
    zip:        { into: Object, const: :Zip,       file: "zip" },
    csv:        { into: Object, const: :CSV,       file: "csv" },
    openssl:    { into: Object, const: :OpenSSL,   file: "openssl" },
    uri:        { into: Object, const: :URI,       file: "uri" },
    zlib:       { into: Object, const: :Zlib,      file: "zlib" },

    # ネットワーク系
    net_http:   { into: :Net,   const: :HTTP,      file: "net/http" },
    socket:     { into: Object, const: :Socket,    file: "socket" },
    base64:     { into: Object, const: :Base64,    file: "base64" },
    digest:     { into: Object, const: :Digest,    file: "digest" },
    digest_md5: { into: Digest, const: :MD5,       file: "digest/md5" },
    digest_sha1:{ into: Digest, const: :SHA1,      file: "digest/sha1" },

    # 開発系（デバッグ）
    pry:        { into: Object, const: :Pry,       file: "pry", dev_only: true },
    awesome_print: { into: Object, const: :AwesomePrint, file: "awesome_print", dev_only: true },

    # OS異存系
    etc: {
      into: Object,
      const: :Etc,
      file: "etc",
      if: -> { !Gem.win_platform? || RUBY_PLATFORM =~ /mingw|mswin|cygwin/ }
    },
    win32ole: {
      into: Object,
      const: :WIN32OLE,
      file: "win32ole",
      if: -> { Gem.win_platform? }
    },
  }.freeze

  # Narou.rb での "全部入り" デフォルトセット
  DEFAULT_SET = %i[
    yaml fileutils stringio date pathname tempfile open3
    json rexml nkf zip csv openssl uri net_http
  ].freeze

  # ===== 公開API =====
  # 使用宣言。各ファイル先頭で "このファイルで使うもの" を列挙。
  def use(*keys)
    keys.flatten.each { |k| register(k) }
  end

  # よく使うものをまとめて設定
  def use_default!
    use(DEFAULT_SET)
  end

  # 明示的に今すぐ require したい場合（ホットパスでの前倒し）
  def require_now(*keys)
    keys.flatten.each do |k|
      spec = SPEC.fetch(k.to_sym) { raise ArgumentError, "Lazy: unknown key: #{k.inspect}" }
      require spec[:file]
    end
  end

  # ===== 実装詳細 =====
  def register(key)
    spec = SPEC.fetch(key.to_sym) { raise ArgumentError, "Lazy: unknown key: #{key.inspect}" }
    into_mod = resolve_into(spec[:into])
    const    = spec[:const]
    file     = spec[:file]

    # すでに定義済みなら二重登録しない
    return if defined?(into_mod.const_get(const))

    # autoload を仕掛ける
    into_mod.autoload(const, file)
  end

  # into が Symbol のとき、適切な親モジュールを確保する
  def resolve_into(into)
    case into
    when Module
      into
    when Class
      into
    when Object
      Object
    when Symbol
      name = into
      if Object.const_defined?(name, false)
        Object.const_get(name)
      else
        # 親が未定義でも autoload したい場合は空モジュールを立てる
        Object.const_set(name, Module.new)
      end
    else
      raise ArgumentError, "Lazy: unsupported :into => #{into.inspect}"
    end
  end
end
