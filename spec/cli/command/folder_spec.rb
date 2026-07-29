# frozen_string_literal: true

require "lib/cli/command/folder"

RSpec.describe Command::Folder do
  let(:command) { described_class.new }

  before do
    allow(command).to receive(:tagname_to_ids)
  end

  describe "#execute" do
    it "shows help when no arguments provided" do
      expect(command).to receive(:display_help!)
      command.execute([])
    end

    it "opens directory for valid target" do
      target_dir = "/path/to/novel_dir"
      allow(Downloader).to receive(:get_novel_data_dir_by_target).with("0").and_return(target_dir)
      allow(Helper).to receive(:open_directory)

      expect { command.execute(["0"]) }.to output("#{target_dir}\n").to_stdout
      expect(Helper).to have_received(:open_directory).with(target_dir)
    end

    it "does not open directory when --no-open option is set" do
      target_dir = "/path/to/novel_dir"
      allow(Downloader).to receive(:get_novel_data_dir_by_target).with("0").and_return(target_dir)
      allow(Helper).to receive(:open_directory)

      expect { command.execute(["-n", "0"]) }.to output("#{target_dir}\n").to_stdout
      expect(Helper).not_to have_received(:open_directory)
    end

    it "shows error for non-existent target" do
      allow(Downloader).to receive(:get_novel_data_dir_by_target).with("invalid").and_return(nil)
      allow(command).to receive(:error)

      command.execute(["invalid"])
      expect(command).to have_received(:error).with("invalid は存在しません")
    end
  end
end
