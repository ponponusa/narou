# -*- Encoding: utf-8 -*-
#
# Copyright 2013 whiteleaf. All rights reserved.
#

# convert コマンドのテストを自動生成する
#
# spec/data/convert_test/ 以下に各種テストケースごとにフォルダ分けして、
# その中に test_HOGE.txt を用意すると認識する。
# そのテストケースごとにreplace.txtやsetting.iniも置ける。
# テキストのタイトルは(拡張子を除いた)ファイル名と同じでなければならない。
# 想定する出力例は correct_test_HOGE.txt に書く。

require "erb"

spec_dir = "spec"
recipe_dir = File.join(spec_dir, "data/convert_test")
pwd = Dir.pwd
Dir.chdir(recipe_dir)
# テストファイルのリストを作成
convert_test_text_list = Dir.glob(File.join("*", "test_*.txt")).keep_if { |path|
  dir = File.dirname(path)
  basename = File.basename(path)
  unless File.exist?(File.join(dir, "correct_#{basename}"))
    puts <<~EOS
      [Warning]
      テストケース(#{path})は見つかりましたが、出力例のテキストデータが見つかりません。
      correct_#{basename} を用意して下さい。

    EOS
  end
  true
}
Dir.chdir(pwd)
result = ERB.new(DATA.read, trim_mode: "-").result(binding)
output_path = File.join(spec_dir, "novel", "convert_spec.rb")
File.write(output_path, result)
puts "#{output_path} を出力しました"

__END__
# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#
# auto generated at <%= Time.now %>

Encoding.default_external = Encoding::UTF_8

require_relative "../spec_helper"
require "lib/cli/commandline"
require "lib/output/narou_logger"

AUTHOR = "whiteleaf"
$debug = File.exist?(File.join("spec", "debug"))

describe "convert" do
  before :all do
    spec_dir = File.expand_path("..", __dir__)
    test_text_dir = File.join(spec_dir, "data", "convert_test")
    @pwd = Dir.pwd
    Dir.chdir(test_text_dir)

    Inventory.load("local_setting")["convert.filename-to-ncode"] = false
  end

  after :all do
    # 変換した際に出力される各ファイルを削除
    unless $debug
      patterns = ["*/\\[#{AUTHOR}\\]*.txt", "*/{見出しリスト,調査ログ}.txt"]
      patterns.each do |pattern|
        pattern = pattern.encode("Windows-31J") if RbConfig::CONFIG["host_os"] =~ /mswin(?!ce)|mingw|bccwin/i
        Dir.glob(pattern) do |path|
          File.delete(path)
        end
      end
    end
    Dir.chdir(@pwd)
  end

  def load_file(path)
    # 行末の空白と改行の違いは無視する
    File.read(path).gsub("\r", "").rstrip
  end

  def check_answer(path)
    dir = File.dirname(path)
    filename = File.basename(path)
    # テスト実行中の出力を抑制するため、$stdoutと$stdout2を一時的にStringIOに置き換える
    original_stdout = $stdout
    original_stdout2 = $stdout2
    $stdout = StringIO.new
    $stdout2 = StringIO.new
    begin
      CommandLine.run(["convert", path, "--no-epub", "--no-open", "--ignore-force", "--ignore-default"])
    ensure
      $stdout = original_stdout
      $stdout2 = original_stdout2
    end
    output_file = File.join(dir, "[#{AUTHOR}] #{filename}")
    correct_file = File.join(dir, "correct_#{filename}")
    expect(load_file(output_file)).to eq load_file(correct_file)
  end
<% convert_test_text_list.each do |path| %>
  it "<%= path %>" do
    check_answer("<%= path %>")
  end
<% end -%>
end
