# frozen_string_literal: true

require "lib/cli/command/freeze"

RSpec.describe Command::Freeze do
  let(:command) { described_class.new }
  let(:frozen_list) { double("frozen_list") }

  before do
    allow(Inventory).to receive(:load).with("freeze").and_return(frozen_list)
    allow(Inventory).to receive(:load).with("local_setting").and_return({})
    allow(Inventory).to receive(:save)
    allow(frozen_list).to receive(:save)
    allow(frozen_list).to receive(:include?).and_return(false)
    allow(frozen_list).to receive(:<<)
    allow(frozen_list).to receive(:delete)
    allow(frozen_list).to receive(:[]=)
  end

  describe "#execute" do
    it "shows help when no arguments provided" do
      expect(command).to receive(:display_help!)
      command.execute([])
    end

    it "freezes a novel when not frozen" do
      data = { "id" => 1, "title" => "テスト小説" }
      allow(Downloader).to receive(:get_data_by_target).with("n9669bk").and_return(data)
      allow(command).to receive(:tagname_to_ids)
      allow(frozen_list).to receive(:include?).with(1).and_return(false)

      expect { command.execute(["n9669bk"]) }.to output(/凍結しました/).to_stdout
      expect(frozen_list).to have_received(:[]=).with(1, true)
    end

    it "unfreezes a novel when already frozen" do
      data = { "id" => 1, "title" => "テスト小説", "tags" => [] }
      database = instance_double(Database)
      allow(Database).to receive(:instance).and_return(database)
      allow(database).to receive(:[]).and_return(data)
      allow(database).to receive(:save_database)
      allow(Downloader).to receive(:get_data_by_target).with("n9669bk").and_return(data)
      allow(command).to receive(:tagname_to_ids)
      allow(frozen_list).to receive(:include?).with(1).and_return(true)

      expect { command.execute(["n9669bk"]) }.to output(/解除しました/).to_stdout
      expect(frozen_list).to have_received(:delete).with(1)
    end

    it "shows error for non-existent novel" do
      allow(Downloader).to receive(:get_data_by_target).with("invalid").and_return(nil)
      allow(command).to receive(:tagname_to_ids)

      expect { command.execute(["invalid"]) }.to output(/は存在しません/).to_stdout
    end
  end

  describe "#output_freeze_list" do
    it "calls List.execute! with frozen filter" do
      expect(Command::List).to receive(:execute!).with("--filter", "frozen")
      command.output_freeze_list
    end
  end
end
