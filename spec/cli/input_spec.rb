# -*- Encoding: utf-8 -*-
# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "lib/cli/input"
require "lib/output/narou_logger"

describe Narou::Input, :show_output do
  before :all do
    $stdout.silent = true
    @original_stdin = $stdin
    @original_noninteractive = ENV["NAROU_NONINTERACTIVE"]
  end

  after :all do
    $stdout.silent = false
    $stdin = @original_stdin
    ENV["NAROU_NONINTERACTIVE"] = @original_noninteractive
  end

  after :each do
    # 各テスト後に$stdinを復元（他テストへのリークを防ぐ）
    $stdin = @original_stdin
  end

  describe ".confirm" do
    before :each do
      # 対話型テストのため一時的に非対話モードを解除
      ENV.delete("NAROU_NONINTERACTIVE")
    end

    after :each do
      ENV["NAROU_NONINTERACTIVE"] = @original_noninteractive
    end

    it "y の時 true を返すべき" do
      $stdin = double("$stdin yes", getch: "y", tty?: true)
      expect(Narou::Input.confirm("")).to eq true
    end

    it "Y の時 true を返すべき" do
      $stdin = double("$stdin yes", getch: "Y", tty?: true)
      expect(Narou::Input.confirm("")).to eq true
    end

    it "n の時 false を返すべき" do
      $stdin = double("$stdin no", getch: "n", tty?: true)
      expect(Narou::Input.confirm("")).to eq false
    end

    it "N の時 fale を返すべき" do
      $stdin = double("$stdin no", getch: "N", tty?: true)
      expect(Narou::Input.confirm("")).to eq false
    end

    it "enter をおした時 false を返すべき" do
      $stdin = double("$stdin enter", getch: "\n", tty?: true)
      expect(Narou::Input.confirm("")).to eq false
    end

    it "pipe で接続された時 true を返すべき" do
      $stdin = double("$stdin nontty", tty?: false)
      expect(Narou::Input.confirm("")).to eq true
    end

    it "Web UI 実行時は nontty_default を返すべき" do
      $stdin = double("$stdin tty", tty?: true)
      allow(Narou).to receive(:web?).and_return(true)
      expect(Narou::Input.confirm("", false, true)).to eq true
    end
  end

  describe ".choose" do
    before :each do
      @choices = { "japanese" => "日本語", "english" => "English", default: "japanese" }
      # 対話型テストのため一時的に非対話モードを解除
      ENV.delete("NAROU_NONINTERACTIVE")
    end

    after :each do
      ENV["NAROU_NONINTERACTIVE"] = @original_noninteractive
    end

    it "japanese を入力された時 japanese を返すべき" do
      $stdin = double("$stdin japanese", gets: "japanese\n", tty?: true)
      expect(Narou::Input.choose("", "", @choices)).to eq "japanese"
    end

    it "JAPANESE を入力された時 japanese を返すべき" do
      $stdin = double("$stdin JAPANESE", gets: "JAPANESE\n", tty?: true)
      expect(Narou::Input.choose("", "", @choices)).to eq "japanese"
    end

    it "English を入力された時 english を返すべき" do
      $stdin = double("$stdin English", gets: "English\n", tty?: true)
      expect(Narou::Input.choose("", "", @choices)).to eq "english"
    end

    it "pipe で接続された時 japanese を返すべき" do
      $stdin = double("$stdin nontty", tty?: false)
      expect(Narou::Input.choose("", "", @choices)).to eq "japanese"
    end
  end
end

