# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

module Device::Ibunko
  PHYSICAL_SUPPORT = false
  VOLUME_NAME = nil
  DOCUMENTS_PATH_LIST = nil
  EBOOK_FILE_EXT = ".zip"
  NAME = "iBunko"
  DISPLAY_NAME = "i文庫"

  RELATED_VARIABLES = {
    "default.enable_half_indent_bracket" => false
  }

  #
  # make-zip 用：純粋な青空文庫テキストからZIP生成（EPUB最適化要素を除去）
  #
  def create_pure_aozora_zip
    require "zip"
    Zip.unicode_names = true
    setting = {}
    if @novel_data
      setting = NovelSetting.load(@novel_data["id"], @options["ignore-force"], @options["ignore-default"])
    end
    dirpath = File.dirname(@converted_txt_path)

    # 元テキストを汚さないように一時ファイルを生成して整形
    sanitized_txt_path = @converted_txt_path.sub(/\.txt$/, ".ibunko.txt")
    data = File.read(@converted_txt_path, encoding: Encoding::UTF_8)
    # EPUB最適化のために混入しうるHTML/タグ類を汎用的に除去
    # 先に汎用HTMLを除去してから、青空注記→i文庫カスタムタグへの変換を行う
    previous = nil
    while data != previous
      previous = data
      data = data.gsub(%r{</?[^>]+>}, "")
    end
    # HTMLエンティティは実体に復号
    data = Helper.restore_entity(data)
    # 青空注記 → i文庫HDカスタムタグへ変換
    # 挿絵注記
    data.gsub!(/［＃挿絵（(.+?)）入る］/, '<IMG SRC="\1">')
    # 改ページ
    data.gsub!(/［＃改ページ］/, "<PBR>")
    # 改行コードをCR+LFに正規化（i文庫HDの仕様に準拠）
    data.gsub!("\r\n", "\n")
    data.gsub!("\r", "\n")
    data.gsub!("\n", "\r\n")
    File.write(sanitized_txt_path, data)

    zipfile_path = @converted_txt_path.sub(/.txt$/, @device.ebook_file_ext)
    File.delete(zipfile_path) if File.exist?(zipfile_path)

    # Windowsでのスレッド内ファイル操作対策: GCを強制実行してファイルハンドルを解放
    GC.start
    sleep 0.1

    Zip::File.open(zipfile_path, create: true) do |zip|
      # テキスト本体（整形済み）
      zip.add(File.basename(@converted_txt_path), sanitized_txt_path) { true }
      # 挿絵（Aozora注記のまま。画像ファイルは同梱）
      if setting["enable_illust"]
        illust_dirpath = File.join(dirpath, Illustration::ILLUST_DIR)
        if File.exist?(illust_dirpath)
          Dir.glob(File.join(illust_dirpath, "*")) do |img_path|
            zip.add(File.join(Illustration::ILLUST_DIR, File.basename(img_path)), img_path) { true }
          end
        end
      end
      # 表紙画像
      cover_name = NovelConverter.get_cover_filename(dirpath)
      if cover_name
        zip.add(cover_name, File.join(dirpath, cover_name)) { true }
      end
    end
    FileUtils.rm_f(sanitized_txt_path)
    output_io = $stdout2
    output_io.puts File.basename(zipfile_path) + " を出力しました"
    output_io.puts "<bold><green>#{@device.display_name}用ファイルを出力しました</green></bold>".termcolor
    if Narou.economy?("cleanup_temp") && @argument_target_type == :novel
      FileUtils.rm_f(@converted_txt_path)
    end
    zipfile_path
  end

  #
  # i文庫用にテキストと挿絵ファイルをzipアーカイブ化する
  #
  def hook_convert_txt_to_ebook_file(&)
    # 既存の no-zip 設定、または make-zip=false の場合はZIPを作らない
    return false if @options["no-zip"] || (@options.key?("make-zip") && !@options["make-zip"])
    require "zip"
    Zip.unicode_names = true # 日本語ファイル名対応
    # TODO: テキストファイル変換時もsettingを取れるようにする
    setting = {}
    if @novel_data
      setting = NovelSetting.load(@novel_data["id"], @options["ignore-force"], @options["ignore-default"])
    end
    dirpath = File.dirname(@converted_txt_path)
    translate_illust_chuki_to_img_tag
    zipfile_path = @converted_txt_path.sub(/.txt$/, @device.ebook_file_ext)
    File.delete(zipfile_path) if File.exist?(zipfile_path)

    # Windowsでのスレッド内ファイル操作対策: GCを強制実行してファイルハンドルを解放
    GC.start
    sleep 0.1

    Zip::File.open(zipfile_path, create: true) do |zip|
      # テキスト本体
      zip.add(File.basename(@converted_txt_path), @converted_txt_path) { true }
      # 挿絵
      if setting["enable_illust"]
        illust_dirpath = File.join(dirpath, Illustration::ILLUST_DIR)
        if File.exist?(illust_dirpath)
          Dir.glob(File.join(illust_dirpath, "*")) do |img_path|
            zip.add(File.join(Illustration::ILLUST_DIR, File.basename(img_path)), img_path) { true }
          end
        end
      end
      # 表紙画像
      cover_name = NovelConverter.get_cover_filename(dirpath)
      if cover_name
        zip.add(cover_name, File.join(dirpath, cover_name)) { true }
      end
    end
    output_io = $stdout2
    output_io.puts File.basename(zipfile_path) + " を出力しました"
    output_io.puts "<bold><green>#{@device.display_name}用ファイルを出力しました</green></bold>".termcolor
    if Narou.economy?("cleanup_temp") && @argument_target_type == :novel
      # 作業用ファイルを削除
      FileUtils.rm_f(@converted_txt_path)
    end
    zipfile_path
  end

  #
  # 挿絵注記をimgタグに変換する
  #
  def translate_illust_chuki_to_img_tag
    data = File.read(@converted_txt_path, encoding: Encoding::UTF_8)
    data.gsub!(/［＃挿絵（(.+?)）入る］/, '<img src="\1">')
    File.write(@converted_txt_path, data)
  end
end
