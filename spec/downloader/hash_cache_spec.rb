# frozen_string_literal: true

require "spec_helper"
require "downloader"
require "stringio"
require "fileutils"
require "yaml"

RSpec.describe Downloader do
  describe "section hash cache" do
    let(:io) { StringIO.new }
    let(:downloader) { described_class.new(1, stream: io, from_download: true) }
    let(:relative_path) { File.join(Downloader::SECTION_SAVE_DIR_NAME, "999 hash_spec.yaml") }
    let(:base_dir) { downloader.send(:get_novel_data_dir) }
    let(:full_path) { base_dir.join(relative_path) }
    let(:subtitle_data) { { "element" => "body" } }

    before do
      described_class.clear_section_hash_cache(downloader.id)
      FileUtils.mkdir_p(full_path.dirname)
      File.write(full_path, YAML.dump(subtitle_data))
    end

    after do
      FileUtils.rm_f(full_path)
      described_class.clear_section_hash_cache(downloader.id)
    end

    it "memoizes digest after first comparison" do
      subtitle = YAML.unsafe_load_file(full_path.to_s)
      expect(downloader.send(:cached_section_digest, relative_path)).to be_nil

      expect(downloader.send(:different_section?, relative_path, subtitle)).to eq(false)
      cached_digest = downloader.send(:cached_section_digest, relative_path)
      expect(cached_digest).to be_a(String)

      expect(downloader.send(:different_section?, relative_path, subtitle)).to eq(false)

      modified = subtitle.merge("element" => subtitle["element"].to_s + " updated")
      expect(downloader.send(:different_section?, relative_path, modified)).to eq(true)
    end
  end
end
