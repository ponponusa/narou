# frozen_string_literal: true

require_relative "../../lib/command/remove"

RSpec.describe Command::Remove do
  let(:command) { described_class.new }
  let(:database) { instance_double(Database) }
  let(:db_object) { {} }

  before do
    allow(Database).to receive(:instance).and_return(database)
    allow(database).to receive(:get_object).and_return(db_object)
    allow(database).to receive(:delete)
    allow(database).to receive(:save_database)
    allow(database).to receive(:tag_indexies).and_return({})
    allow(database).to receive(:ids).and_return([])
    allow(Inventory).to receive(:load).with("local_setting").and_return({})
  end

  describe "#get_all_short_story" do
    it "returns only short stories (novel_type == 2)" do
      db_object[1] = { "id" => 1, "title" => "短編1", "novel_type" => 2 }
      db_object[2] = { "id" => 2, "title" => "連載1", "novel_type" => 1 }
      db_object[3] = { "id" => 3, "title" => "短編2", "novel_type" => 2 }

      result = command.get_all_short_story
      expect(result.size).to eq(2)
      expect(result.map { |n| n["id"] }).to contain_exactly(1, 3)
    end

    it "returns empty array when no short stories exist" do
      db_object[1] = { "id" => 1, "title" => "連載1", "novel_type" => 1 }
      
      result = command.get_all_short_story
      expect(result).to be_empty
    end
  end

  describe "#execute" do
    it "shows help when no arguments provided and --all-ss not set" do
      # display_help!とexitをstubして出力を完全に抑制
      allow(command).to receive(:exit).and_return(nil)
      expect(command).to receive(:display_help!)
      command.execute([])
    end

    it "removes all short stories with --all-ss option" do
      db_object[1] = { "id" => 1, "title" => "短編1", "novel_type" => 2 }
      db_object[2] = { "id" => 2, "title" => "短編2", "novel_type" => 2 }
      
      command.instance_variable_set(:@options, { "all-ss" => true, "yes" => true })
      allow(command).to receive(:tagname_to_ids)
      allow(Downloader).to receive(:get_data_by_target).and_return(db_object[1], db_object[2])
      
      expect { command.execute([]) }.to output.to_stdout
    end

    it "shows message when no short stories exist with --all-ss" do
      command.instance_variable_set(:@options, { "all-ss" => true })
      
      expect { command.execute([]) }.to output(/短編小説がひとつもありません/).to_stdout
    end

    it "shows error for non-existent novel" do
      allow(command).to receive(:tagname_to_ids)
      allow(Downloader).to receive(:get_data_by_target).with("invalid").and_return(nil)
      
      expect { command.execute(["invalid"]) }.to output(/は存在しません/).to_stdout
    end
  end
end
