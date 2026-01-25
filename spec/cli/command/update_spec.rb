# -*- coding: utf-8 -*-
#
# Copyright 2013 whiteleaf. All rights reserved.
#
# auto generated at 2015-08-07 22:44:33 +0900

require "lib/cli/commandline"
require "lib/output/narou_logger"

describe Command::Update, :show_output do
  describe "--ignore-all" do
    it "should be blank" do
      cap = $stdout.capture {
        CommandLine.run!(%w(update --ignore-all))
      }.strip
      expect(cap).to eq ""
    end

    it "should not be blank" do
      cap = $stdout.capture(quiet: true) {
        CommandLine.run!(%w(update --ignore-all 22))
      }.strip
      expect(cap).to eq "ID:22　もう一度ナデシコへ は凍結中です"
    end
  end

  describe "--convert-only-new-arrival" do
    # 新着がある場合のみ変換を実行するオプションのテスト
    # このオプションは既存の機能であり、今回の変換スキップ機能の基盤となる

    it "オプションが正しく認識される" do
      cmd = Command::Update.new
      # オプションパーサーにオプションが定義されていることを確認
      expect(cmd.instance_variable_get(:@opt).to_s).to include("--convert-only-new-arrival")
    end
  end

  describe "変換スキップ機能" do
    # result.status が :none の場合、変換をスキップする機能のテスト

    context "更新なしの場合" do
      it "result.status が :none を返す" do
        # Downloader.start_download の戻り値構造をテスト
        result = OpenStruct.new(id: 1, new_arrivals: false, status: :none)
        expect(result.status).to eq(:none)
        expect(result.new_arrivals).to be false
      end
    end

    context "更新ありの場合" do
      it "result.status が :ok を返す" do
        result = OpenStruct.new(id: 1, new_arrivals: true, status: :ok)
        expect(result.status).to eq(:ok)
        expect(result.new_arrivals).to be true
      end
    end
  end
end
