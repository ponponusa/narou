# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Command::Init do
  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        begin
          Narou.flush_cache if Narou.respond_to?(:flush_cache)
          Inventory.clear if Inventory.respond_to?(:clear)
          FileUtils.mkdir_p(Narou::GLOBAL_SETTING_DIR_NAME)
          example.run
        ensure
          Narou.flush_cache if Narou.respond_to?(:flush_cache)
          Inventory.clear if Inventory.respond_to?(:clear)
        end
      end
    end
  end

  let(:aozora_dir) { File.join(Dir.pwd, "AozoraEpub3") }

  def prepare_aozora_dir
    FileUtils.mkdir_p(aozora_dir)
    File.write(File.join(aozora_dir, "AozoraEpub3.jar"), "")
  end

  def build_command
    Command::Init.new.tap do |command|
      allow(command).to receive(:rewrite_aozoraepub3_files)
    end
  end

  describe "non-interactive execution" do
    it "suppresses stdout when output mode is silent" do
      prepare_aozora_dir
      command = build_command

      expect do
        command.execute(["--non-interactive", "--output-mode", "silent", "--path", aozora_dir, "--line-height", "1.9"])
      end.to output("").to_stdout
    end

    it "prints summary of selected settings" do
      prepare_aozora_dir
      command = build_command

      expect do
        command.execute(["--non-interactive", "--output-mode", "summary", "--path", aozora_dir, "--line-height", "1.9"])
      end.to output(a_string_including("AozoraEpub3 フォルダ: #{aozora_dir}")
                      .and(include("行の高さ: 1.9"))).to_stdout
    end
  end
end
