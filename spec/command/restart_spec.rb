# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Command::Restart do
  subject(:command) { described_class.new }

  describe "#execute" do
    it "shows warning message about foreground mode" do
      expect(Command::OutputHelper).to receive(:warning).with(/フォアグラウンド実行モードでは restart コマンドは使用できません/)
      expect(Command::OutputHelper).to receive(:info).at_least(:once)
      
      expect { command.execute([]) }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end
    end

    context "with --force option" do
      it "still shows warning message" do
        expect(Command::OutputHelper).to receive(:warning).with(/フォアグラウンド実行モードでは restart コマンドは使用できません/)
        expect(Command::OutputHelper).to receive(:info).at_least(:once)
        
        expect { command.execute(["--force"]) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end
  end
end
