# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "fileutils"

class NovelConverter
  #
  # 出力ファイル関連のヘルパーメソッド
  #
  module OutputHelper
    module_function

    #
    # 表紙用の画像名取得
    #
    def get_cover_filename(archive_path)
      [".jpg", ".png", ".jpeg"].each do |ext|
        filename = "cover#{ext}"
        cover_path = File.join(archive_path, filename)
        if File.exist?(cover_path)
          return filename
        end
      end
      nil
    end

    #
    # 一時ファイルを削除
    #
    def clean_up_temp_files(path_list)
      return unless path_list
      path_list.each do |path|
        FileUtils.rm_f(path)
      end
    end
  end
end
