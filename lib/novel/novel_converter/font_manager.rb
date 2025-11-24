# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "fileutils"
require "lib/utilities/helper"

class NovelConverter
  #
  # 濁点フォント管理
  #
  module FontManager
    DAKUTEN_FROM = ["vertical_font_with_dakuten.css", "DMincho.ttf"]
    DAKUTEN_TO = ["template/OPS/css_custom/vertical_font.css", "template/OPS/fonts/DMincho.ttf"]
    DAKUTEN_ERB = [true, false]

    module_function

    def activate_dakuten_font_files
      preset_dir = Narou.preset_dir
      aozora_dir = File.dirname(Narou.aozoraepub3_path)
      line_height = Narou.line_height

      DAKUTEN_FROM.each_with_index do |name, i|
        src = File.join(preset_dir, name)
        dst = File.join(aozora_dir, DAKUTEN_TO[i])
        if DAKUTEN_ERB[i]
          Helper.erb_copy(src, dst, binding)
        else
          FileUtils.mkdir_p(File.dirname(dst))
          FileUtils.copy(src, dst)
        end
      end
    end

    def inactivate_dakuten_font_files
      preset_dir = Narou.preset_dir
      aozora_dir = File.dirname(Narou.aozoraepub3_path)
      path_normal_vertical_css = File.join(preset_dir, "vertical_font.css")
      line_height = Narou.line_height

      Helper.erb_copy(path_normal_vertical_css, File.join(aozora_dir, DAKUTEN_TO[0]), binding)
      FileUtils.remove(File.join(aozora_dir, DAKUTEN_TO[1]))
    end
  end
end
