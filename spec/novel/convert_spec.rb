# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#
# auto generated at 2025-11-24 22:54:26 +0900

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

  it "auto_indent/test_auto_indent.txt" do
    check_answer("auto_indent/test_auto_indent.txt")
  end

  it "auto_join_bracket/test_auto_join_bracket.txt" do
    check_answer("auto_join_bracket/test_auto_join_bracket.txt")
  end

  it "auto_join_line/test_auto_join_line.txt" do
    check_answer("auto_join_line/test_auto_join_line.txt")
  end

  it "convert_numbers/test_convert_numbers.txt" do
    check_answer("convert_numbers/test_convert_numbers.txt")
  end

  it "convert_page_break/test_convert_page_break.txt" do
    check_answer("convert_page_break/test_convert_page_break.txt")
  end

  it "convert_prolonged_sound_mark_to_dash/test_convert_prolonged_sound_mark_to_dash.txt" do
    check_answer("convert_prolonged_sound_mark_to_dash/test_convert_prolonged_sound_mark_to_dash.txt")
  end

  it "disable_alphabet_word_to_zenkaku/test_disable_alphabet_word_to_zenkaku.txt" do
    check_answer("disable_alphabet_word_to_zenkaku/test_disable_alphabet_word_to_zenkaku.txt")
  end

  it "english/test_english.txt" do
    check_answer("english/test_english.txt")
  end

  it "force_indent_special_chapter/test_force_indent_special_chapter.txt" do
    check_answer("force_indent_special_chapter/test_force_indent_special_chapter.txt")
  end

  it "horizontal_ellipsis/test_horizontal_ellipsis.txt" do
    check_answer("horizontal_ellipsis/test_horizontal_ellipsis.txt")
  end

  it "insert_separator/test_insert_separator.txt" do
    check_answer("insert_separator/test_insert_separator.txt")
  end

  it "insert_separator_and_replace_txt/test_insert_separator_and_replace_txt.txt" do
    check_answer("insert_separator_and_replace_txt/test_insert_separator_and_replace_txt.txt")
  end

  it "kanji_num/test_kanji_num.txt" do
    check_answer("kanji_num/test_kanji_num.txt")
  end

  it "nonokagi/test_nonokagi.txt" do
    check_answer("nonokagi/test_nonokagi.txt")
  end

  it "replace/test_replace.txt" do
    check_answer("replace/test_replace.txt")
  end

  it "rome_num/test_rome_num.txt" do
    check_answer("rome_num/test_rome_num.txt")
  end

  it "ruby/test_ruby.txt" do
    check_answer("ruby/test_ruby.txt")
  end

  it "ruby_youon/test_ruby_youon.txt" do
    check_answer("ruby_youon/test_ruby_youon.txt")
  end

  it "sesame/test_sesame.txt" do
    check_answer("sesame/test_sesame.txt")
  end

  it "to_odd_leader/test_to_odd_leader.txt" do
    check_answer("to_odd_leader/test_to_odd_leader.txt")
  end
end
