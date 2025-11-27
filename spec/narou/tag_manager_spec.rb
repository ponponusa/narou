# frozen_string_literal: true

#
# Copyright 2024 ponponusa. All rights reserved.
#

require "spec/spec_helper"
require "lib/narou/tag_manager"

RSpec.describe Narou::TagManager do
  let(:database) { Database.instance }

  before do
    allow(Database).to receive(:instance).and_return(database)
  end

  describe ".get_tag_list" do
    it "returns list of all tags with counts" do
      allow(database).to receive(:each_value).and_yield(
        { "id" => 1, "tags" => ["tag1"] }
      ).and_yield(
        { "id" => 2, "tags" => ["tag1", "tag2"] }
      )

      tags = Narou::TagManager.get_tag_list

      expect(tags).to be_a(Hash)
      expect(tags["tag1"]).to eq(2)
      expect(tags["tag2"]).to eq(1)
    end
  end

  describe ".get_color" do
    it "returns color for existing tag" do
      allow(Command::Tag).to receive(:get_color).with("tag1").and_return("red")

      color = Narou::TagManager.get_color("tag1")
      expect(color).to eq("red")
    end
  end

  describe ".get_tag_info" do
    it "returns tag states for specified novels" do
      allow(Narou::TagManager).to receive(:get_tag_list).and_return({ "tag1" => 1, "tag2" => 2 })
      allow(Narou::TagManager).to receive(:get_color).and_return("white")
      allow(database).to receive(:[])
        .with(1).and_return({ "tags" => ["tag1", "tag2"] })
      allow(database).to receive(:[])
        .with(2).and_return({ "tags" => ["tag2"] })

      info = Narou::TagManager.get_tag_info([1, 2])

      expect(info).to be_a(Hash)
      expect(info["tag1"]).to have_key(:count)
      expect(info["tag1"]).to have_key(:total_count)
      expect(info["tag2"][:count]).to eq(2) # 両方の小説にある
    end
  end

  describe ".add_tags" do
    it "adds tags to specified novels and returns result" do
      novel1 = { "id" => 1, "tags" => [] }
      novel2 = { "id" => 2, "tags" => ["existing"] }

      allow(database).to receive(:[])
        .with(1).and_return(novel1)
      allow(database).to receive(:[])
        .with(2).and_return(novel2)
      allow(database).to receive(:save_database)

      result = Narou::TagManager.add_tags(["new_tag"], [1, 2])

      expect(result[:success]).to be true
      expect(novel1["tags"]).to include("new_tag")
      expect(novel2["tags"]).to include("new_tag", "existing")
    end
  end

  describe ".delete_tags" do
    it "removes tags from specified novels" do
      novel = { "id" => 1, "tags" => ["tag1", "tag2"] }
      allow(database).to receive(:[]).with(1).and_return(novel)
      allow(database).to receive(:save_database)

      result = Narou::TagManager.delete_tags(["tag1"], [1])

      expect(result[:success]).to be true
      expect(novel["tags"]).to eq(["tag2"])
    end
  end

  describe ".edit_tags" do
    it "edits tags based on states" do
      novel = { "id" => 1, "tags" => ["keep", "remove"] }
      allow(database).to receive(:[]).with(1).and_return(novel)
      allow(database).to receive(:save_database)
      allow(Command::Tag).to receive(:execute!)

      states = {
        "add" => 2,
        "keep" => 1,
        "remove" => 0
      }
      result = Narou::TagManager.edit_tags(states, [1])

      expect(result[:success]).to be true
      expect(result).to have_key(:added)
      expect(result).to have_key(:deleted)
    end
  end
end
