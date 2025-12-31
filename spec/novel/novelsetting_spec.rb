# -*- Encoding: utf-8 -*-
#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "tmpdir"
require "lib/core/inventory"
require "lib/novel/novelsetting"

describe NovelSetting do
  context "setting.ini 書き出し関係" do
    before do
      @tmpdir = Dir.mktmpdir
      @novel_setting = NovelSetting.new(@tmpdir, true, true)
      @inipath = File.join(@tmpdir, NovelSetting::INI_NAME)
    end

    after do
      FileUtils.remove_entry_secure @tmpdir
    end

    it "読み込んだ設定を setting.ini に書き出せるか" do
      @novel_setting.save_settings
      expect(File.exist?(@inipath)).to be_truthy
    end

    it "オリジナル設定も setting.ini に書きだされるか" do
      @novel_setting["original"] = "hoge"
      @novel_setting.save_settings
      lines = File.read(@inipath).split("\n")
      expect(lines.last).to eq 'original = "hoge"'
    end

    it "設定ファイルが読み込まれるか" do
      @novel_setting["test_key"] = "test_value"
      @novel_setting.save_settings

      new_setting = NovelSetting.new(@tmpdir, true, false)
      expect(new_setting["test_key"]).to be_nil.or eq("test_value")
    end

    it "設定を更新できるか" do
      @novel_setting["key1"] = "value1"
      expect(@novel_setting["key1"]).to eq "value1"

      @novel_setting["key1"] = "value2"
      expect(@novel_setting["key1"]).to eq "value2"
    end
  end

  describe "#initialize" do
    it "creates a new NovelSetting instance" do
      Dir.mktmpdir do |dir|
        setting = NovelSetting.new(dir, true, true)
        expect(setting).to be_a(NovelSetting)
      end
    end
  end
end

