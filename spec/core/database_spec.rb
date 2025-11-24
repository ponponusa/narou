# -*- Encoding: utf-8 -*-
#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "tmpdir"
require "lib/core/database"

describe Database do
  describe "#get_object" do
    it "returns a hash-like object" do
      db = Database.instance
      obj = db.get_object
      expect(obj).to respond_to(:[])
      expect(obj).to respond_to(:each)
    end
  end

  describe "#get_data" do
    it "accepts type and value parameters" do
      db = Database.instance
      result = db.get_data("id", 1)
      expect(result).to be_nil.or be_a(Hash)
    end
  end

  describe "#instance" do
    it "returns a Database instance" do
      db = Database.instance
      expect(db).to be_a(Database)
    end

    it "returns the same instance on multiple calls" do
      db1 = Database.instance
      db2 = Database.instance
      expect(db1).to eq(db2)
    end
  end
end
