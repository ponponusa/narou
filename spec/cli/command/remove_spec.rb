# frozen_string_literal: true

require "lib/cli/command/remove"

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

  after do
    # テスト間でcommandインスタンスが共有される場合に備えて@optionsをクリア
    command.instance_variable_set(:@options, {}) if command
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
      # display_help!の実装内でexitが呼ばれるため、display_help!自体をstub
      expect(command).to receive(:display_help!) do
        # 何もしない（exitを呼ばない）
      end
      command.execute([])
    end

    it "removes all short stories with --all-ss option" do
      db_object[1] = { "id" => 1, "title" => "短編1", "novel_type" => 2 }
      db_object[2] = { "id" => 2, "title" => "短編2", "novel_type" => 2 }

      command.instance_variable_set(:@options, { "all-ss" => true, "yes" => true })
      allow(command).to receive(:tagname_to_ids)
      allow(Downloader).to receive(:get_data_by_target).and_return(db_object[1], db_object[2])
      allow(Narou).to receive(:locked?).and_return(false)
      allow(Narou).to receive(:novel_frozen?).and_return(false)
      allow(Downloader).to receive(:remove_novel)
      allow(Helper).to receive(:print_horizontal_rule)

      # Kernel.exitを明示的にstub
      allow(command).to receive(:exit)
      allow(Kernel).to receive(:exit)

      expect { command.execute([]) }.to output.to_stdout
    end

    it "shows message when no short stories exist with --all-ss" do
      # display_help!とKernel.exitをstub
      allow(command).to receive(:display_help!)
      allow(command).to receive(:exit)
      allow(Kernel).to receive(:exit)

      # --all-ssオプションを引数として渡す
      expect { command.execute(["--all-ss"]) }.to output(/短編小説がひとつもありません/).to_stdout
    end

    it "shows error for non-existent novel" do
      allow(command).to receive(:tagname_to_ids)
      allow(Downloader).to receive(:get_data_by_target).with("invalid").and_return(nil)

      # Kernel.exitをstub
      allow(command).to receive(:exit)
      allow(Kernel).to receive(:exit)

      # errorメソッドをstub（$stdout.errorが呼ばれるため）
      allow(command).to receive(:error)

      command.execute(["invalid"])

      # errorメソッドが呼ばれたことを検証
      expect(command).to have_received(:error).with(/は存在しません/)
    end

    it "can call tagname_to_ids without Database require error" do
      # Database が正しく require されていることを確認
      # 修正前: NameError (uninitialized constant Command::CommandBase::Database)
      command.instance_variable_set(:@options, { "yes" => true })
      allow(command).to receive(:display_help!)
      allow(Downloader).to receive(:get_data_by_target).and_return(nil)
      allow(command).to receive(:error)

      # tagname_to_ids が NameError を起こさずに実行される
      expect { command.execute(["test_target"]) }.not_to raise_error
    end
  end
end
