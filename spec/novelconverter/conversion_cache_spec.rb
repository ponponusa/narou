# frozen_string_literal: true

require "spec_helper"
require "downloader"
require "yaml"
require "fileutils"
require "tmpdir"
require "stringio"

RSpec.describe NovelConverter do
  describe "section conversion cache" do
    let(:tmp_root) { Dir.mktmpdir("nc-cache") }
    let(:archive_path) { File.join(tmp_root, "novel") }
    let(:section_dir) { File.join(archive_path, Downloader::SECTION_SAVE_DIR_NAME) }
    let(:section_path) { File.join(section_dir, "1 第一話.yaml") }
    let(:toc_path) { File.join(archive_path, "toc.yaml") }
    let(:setting_ini_path) { File.join(archive_path, "setting.ini") }
    let(:converter_path) { File.join(archive_path, "converter.rb") }
    let(:novel_id) { 9_999 }
    let(:stream) { StringIO.new }

    before do
      FileUtils.mkdir_p(section_dir)
      File.write(setting_ini_path, "[global]\n")
      File.write(toc_path, YAML.dump(toc_payload))
      File.write(section_path, YAML.dump(section_payload("本文")))
      File.write(converter_path, test_converter_code)
      allow(SiteSetting).to receive(:find).and_return({ "illust_current_url" => nil, "illust_grep_pattern" => nil })
      allow(Narou).to receive(:get_device).and_return(nil)
      allow(Narou).to receive(:create_novel_filename).and_return("converted.txt")
      allow_any_instance_of(NovelConverter).to receive(:update_latest_convert_novel)
      NovelConverter.clear_section_convert_cache(novel_id)
      $conversion_calls = 0
    end

    after do
      NovelConverter.clear_section_convert_cache(novel_id)
      FileUtils.remove_entry(tmp_root) if File.exist?(tmp_root)
    end

    def toc_payload
      {
        "title" => "テスト小説",
        "author" => "作者",
        "story" => "あらすじ",
        "toc_url" => "http://example.com/test/1",
        "subtitles" => [
          {
            "index" => 1,
            "subtitle" => "第一話",
            "file_subtitle" => "第一話",
            "chapter" => "",
            "subchapter" => "",
            "href" => "1 第一話.html",
            "download_time" => Time.now,
            "subdate" => "2024-01-01 00:00:00",
            "subupdate" => "2024-01-02 00:00:00"
          }
        ]
      }
    end

    def section_payload(body_text)
      {
        "index" => 1,
        "subtitle" => "第一話",
        "file_subtitle" => "第一話",
        "chapter" => "",
        "subchapter" => "",
        "download_time" => Time.now,
        "element" => {
          "data_type" => "text",
          "introduction" => "",
          "body" => body_text,
          "postscript" => ""
        }
      }
    end

    def test_converter_code
      <<~RUBY
        $conversion_calls ||= 0
        converter do
          def convert_multi(pairs)
            $conversion_calls ||= 0
            $conversion_calls += 1
            super
          end
        end
      RUBY
    end

    def build_setting
      setting = NovelSetting.create(archive_path, false, false)
      setting.id = novel_id
      setting
    end

    def run_conversion
      setting = build_setting
      converter = described_class.new(setting, nil, false, nil, stream_io: stream)
      converter.convert_main
    end

    it "skips reprocessing unchanged sections and invalidates on updates" do
      run_conversion
      first_calls = $conversion_calls
      expect(first_calls).to be > 0

      run_conversion
      expect($conversion_calls).to eq(first_calls)

      File.write(section_path, YAML.dump(section_payload("本文を更新しました")))
      run_conversion
      expect($conversion_calls).to be > first_calls
    end
  end
end
