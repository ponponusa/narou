# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "erb"
require "lib/core/narou"

class Template
  TEMPLATE_DIR = "template/"
  OVERWRITE = true

  class LoadError < StandardError; end

  # コンパイル済みテンプレートをキャッシュする
  # { "novel.txt" => { erb: <ERB>, binary_version: 1.1, src_filename: "novel.txt" } }
  # キャッシュする関係でスレッドセーフにはなっていないので、並列での変換処理を行う場合は対応が必要
  @__compiled_cache = {}

  #
  # テンプレートを元にデータを作成
  #
  # テンプレートファイルの検索順位
  # 1. root_dir/template
  # 2. script_dir/template
  #
  def self.compile(src_filename, binary_version)
    # すでにキャッシュ済みならそのまま返す
    cached = @__compiled_cache[src_filename]
    return cached if cached

    # ファイル探索（getと同じロジック）
    [Narou.root_dir, Narou.script_dir].each do |dir|
      path = dir.join(TEMPLATE_DIR, src_filename + ".erb")
      next unless path.exist?

      src = Helper::CacheLoader.load(path)
      erb = ERB.new(src, trim_mode: "-")

      compiled = {
        erb: erb,
        binary_version: binary_version,
        src_filename: src_filename
      }

      @__compiled_cache[src_filename] = compiled
      return compiled
    end

    raise LoadError, "テンプレートファイルが見つかりません。(#{src_filename}.erb)"
  end

  def self.render(compiled, _binding)
    # compiled は compile が返した Hash
    @@binary_version = compiled[:binary_version]
    @@src_filename   = compiled[:src_filename]

    # target_binary_version から参照される @@src_version は
    # テンプレート内で <%= Template.target_binary_version 1.1 %> みたいに呼ばれる想定
    # なので、ここでは設定しない。テンプレの中から呼ばれた時点で
    # @@src_version が更新され、invalid_templace_version? が機能する

    compiled[:erb].result(_binding)
  end

  #
  # テンプレートを元にファイルを作成
  #
  # src_filename  読み込みたいテンプレートファイル名(.erb は省略する)
  # dest_filepath 保存先ファイルパス。ディレクトリならファイル名はsrcと同じ名前で保存する
  # _binding      変数とか設定したいスコープの binding 変数を渡す
  # overwrite     上書きするか
  #
  def self.write(src_filename, dest_filepath, _binding, binary_version, overwrite = false)
    if File.directory?(dest_filepath)
      dest_filepath = File.join(dest_filepath, src_filename)
    end
    unless overwrite
      return if File.exist?(dest_filepath)
    end
    result = get(src_filename, _binding, binary_version) or return nil
    if Helper.os_windows?
      File.write(dest_filepath, result)
    else
      File.binwrite(dest_filepath, result.lstrip)
    end
  end

  # 既存コード向けのwrap関数
  def self.get(src_filename, _binding, binary_version)
    compiled = compile(src_filename, binary_version)
    render(compiled, _binding)
  end

  def self.invalid_templace_version?
    @@src_version != @@binary_version
  end

  #
  # 書かれているテンプレートがどのバージョンのテンプレートかを設定
  #
  # テンプレート内部で使われる変数の変更があった場合に binary_version が上がる
  # （変数の追加ではバージョンは上がらない。現在使われている変数の中身が変わった場合は上る）
  #
  def self.target_binary_version(version)
    @@src_version = version
    if invalid_templace_version?
      error "テンプレートのバージョンが異なるので意図しない動作をする可能性があります\n" +
            "(#{@@src_filename}.erb ver #{version.to_f} != #{@@binary_version.to_f})"
    end
  end
end
