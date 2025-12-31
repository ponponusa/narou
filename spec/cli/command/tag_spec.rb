# frozen_string_literal: true

require "lib/cli/command/tag"

RSpec.describe Command::Tag do
  let(:command) { described_class.new }

  describe "constants" do
    it "has valid color list" do
      expect(Command::Tag::COLORS).to include("red", "green", "blue")
      expect(Command::Tag::COLORS.size).to eq(7)
    end

    it "has ban character pattern" do
      expect("test:tag").to match(Command::Tag::BAN_CHAR)
      expect("test;tag").to match(Command::Tag::BAN_CHAR)
      expect("valid_tag").not_to match(Command::Tag::BAN_CHAR)
    end

    it "has ban word list" do
      expect(Command::Tag::BAN_WORD).to include("hotentry")
    end
  end

  describe "#validate_tags" do
    before do
      command.instance_variable_set(:@options, { "tags" => [] })
    end

    it "accepts valid tag names" do
      valid_tags = %w(fav later end 404 test_tag)
      valid_tags.each do |tag|
        expect(tag).not_to match(Command::Tag::BAN_CHAR)
        expect(Command::Tag::BAN_WORD).not_to include(tag)
      end
    end

    it "rejects tags with ban characters" do
      ban_char_tags = ["test:tag", "tag;name", "tag<>name"]
      ban_char_tags.each do |tag|
        expect(tag).to match(Command::Tag::BAN_CHAR)
      end
    end

    it "rejects ban words" do
      Command::Tag::BAN_WORD.each do |word|
        expect(Command::Tag::BAN_WORD).to include(word)
      end
    end
  end

  describe "color validation" do
    it "accepts valid colors" do
      Command::Tag::COLORS.each do |color|
        expect(Command::Tag::COLORS).to include(color)
      end
    end

    it "has correct number of colors" do
      expect(Command::Tag::COLORS.size).to eq(7)
    end
  end

  describe "special tags" do
    it "recognizes 'end' as completion tag" do
      # endタグは完結を示す特殊タグ
      expect("end").not_to match(Command::Tag::BAN_CHAR)
      expect(Command::Tag::BAN_WORD).not_to include("end")
    end

    it "recognizes '404' as deleted tag" do
      # 404タグは削除を示す特殊タグ
      expect("404").not_to match(Command::Tag::BAN_CHAR)
      expect(Command::Tag::BAN_WORD).not_to include("404")
    end
  end
end
