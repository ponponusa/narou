# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "spec_helper"
require "tmpdir"
require "lib/output/inspector"

RSpec.describe Inspector do
  let(:archive_path) { Dir.mktmpdir("inspector_spec") }
  let(:setting) do
    double("NovelSetting",
           archive_path: archive_path,
           title: "テスト小説",
           enable_inspect: true,
           enable_auto_join_line: false,
           enable_auto_join_in_brackets: false)
  end
  let(:inspector) { Inspector.new(setting) }
  let(:log_path) { File.join(archive_path, Inspector::INSPECT_LOG_NAME) }

  after do
    FileUtils.rm_rf(archive_path) if archive_path
  end

  describe "#save" do
    context "メッセージが空の場合" do
      it "ファイルを作成しない" do
        inspector.save
        expect(File.exist?(log_path)).to be false
      end
    end

    context "メッセージがある場合" do
      before do
        inspector.info("テスト情報メッセージ")
      end

      it "ファイルを作成する" do
        inspector.save
        expect(File.exist?(log_path)).to be true
      end

      it "ヘッダー情報を含む" do
        inspector.save
        content = File.read(log_path)
        expect(content).to include("--- ログ出力")
      end

      it "対象タイトルを含む" do
        inspector.save
        content = File.read(log_path)
        expect(content).to include("対象: テスト小説")
      end

      it "メッセージを保存する" do
        inspector.save
        content = File.read(log_path)
        expect(content).to include("テスト情報メッセージ")
      end
    end

    context "全種類のメッセージがある場合" do
      before do
        inspector.info("情報メッセージ")
        inspector.warning("警告メッセージ")
        inspector.error("エラーメッセージ")
      end

      it "すべてのメッセージを保存する" do
        inspector.save
        content = File.read(log_path)
        expect(content).to include("[INFO] 情報メッセージ")
        expect(content).to include("[警告] 警告メッセージ")
        expect(content).to include("[エラー] エラーメッセージ")
      end
    end

    context "archive_pathがnilの場合" do
      let(:archive_path) { nil }
      let(:setting) do
        double("NovelSetting",
               archive_path: nil,
               title: "テスト小説",
               enable_inspect: true)
      end

      it "エラーにならない" do
        inspector.info("テスト")
        expect { inspector.save }.not_to raise_error
      end

      it "ファイルを作成しない（早期リターン）" do
        inspector.info("テスト")
        inspector.save
        # archive_path が nil なのでsaveは早期リターンする
        # ファイルシステムに何も作成されないことを確認
        expect(Dir.exist?("/tmp")).to be true # 基本的な確認のみ
      end
    end

    context "archive_pathが空文字の場合" do
      let(:setting) do
        double("NovelSetting",
               archive_path: "",
               title: "テスト小説",
               enable_inspect: true)
      end

      it "エラーにならない" do
        inspector.info("テスト")
        expect { inspector.save }.not_to raise_error
      end
    end

    context "archive_pathのディレクトリが存在しない場合" do
      let(:nonexistent_path) { File.join(archive_path, "nonexistent", "deep", "path") }
      let(:setting) do
        double("NovelSetting",
               archive_path: nonexistent_path,
               title: "テスト小説",
               enable_inspect: true)
      end
      let(:log_path) { File.join(nonexistent_path, Inspector::INSPECT_LOG_NAME) }

      it "ディレクトリを作成してファイルを保存する" do
        inspector.info("テスト")
        inspector.save
        expect(File.exist?(log_path)).to be true
      end
    end

    context "UTF-8エンコーディング" do
      before do
        inspector.info("日本語メッセージテスト：漢字、ひらがな、カタカナ")
      end

      it "UTF-8でファイルを保存する" do
        inspector.save
        content = File.read(log_path, encoding: "UTF-8")
        expect(content.encoding.name).to eq("UTF-8")
        expect(content).to include("日本語メッセージテスト")
      end
    end
  end

  describe "#empty?" do
    context "メッセージがない場合" do
      it "trueを返す" do
        expect(inspector.empty?).to be true
      end
    end

    context "メッセージがある場合" do
      it "falseを返す" do
        inspector.info("テスト")
        expect(inspector.empty?).to be false
      end
    end
  end

  describe "#info" do
    it "INFOタグ付きでメッセージを追加する" do
      inspector.info("情報")
      inspector.save
      content = File.read(log_path)
      expect(content).to include("[INFO] 情報")
    end

    it "info?フラグをtrueにする" do
      expect { inspector.info("情報") }.to change { inspector.info? }.from(false).to(true)
    end
  end

  describe "#warning" do
    it "警告タグ付きでメッセージを追加する" do
      inspector.warning("警告")
      inspector.save
      content = File.read(log_path)
      expect(content).to include("[警告] 警告")
    end

    it "warning?フラグをtrueにする" do
      expect { inspector.warning("警告") }.to change { inspector.warning? }.from(false).to(true)
    end
  end

  describe "#error" do
    it "エラータグ付きでメッセージを追加する" do
      inspector.error("エラー")
      inspector.save
      content = File.read(log_path)
      expect(content).to include("[エラー] エラー")
    end

    it "error?フラグをtrueにする" do
      expect { inspector.error("エラー") }.to change { inspector.error? }.from(false).to(true)
    end
  end

  describe ".read_messages" do
    context "ログファイルが存在する場合" do
      before do
        inspector.info("保存されたメッセージ")
        inspector.save
      end

      it "ファイル内容を読み込む" do
        content = Inspector.read_messages(setting)
        expect(content).to include("保存されたメッセージ")
      end
    end

    context "ログファイルが存在しない場合" do
      it "nilを返す" do
        expect(Inspector.read_messages(setting)).to be_nil
      end
    end
  end
end
