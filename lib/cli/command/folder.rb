# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "lib/utilities/helper"

module Command
  class Folder < CommandBase
    def self.oneline_help
      "小説の保存フォルダを開きます"
    end

    def initialize
      super("<target> [<target2> ...]")
      @opt.separator <<-EOS

  ・指定した小説の保存フォルダを開きます。

  Examples:
    narou-mod folder n9669bk
    narou-mod folder musyoku
    narou-mod folder 0
    narou-mod f 0

  Options:
      EOS
      @opt.on("-n", "--no-open", "フォルダを開かずにパスだけ表示する") {
        @options["no-open"] = true
      }
    end

    def execute(argv)
      super
      display_help! if argv.empty?
      tagname_to_ids(argv)
      argv.each do |target|
        dir = Downloader.get_novel_data_dir_by_target(target)
        if dir
          Helper.open_directory(dir) unless @options["no-open"]
          puts dir
        else
          error "#{target} は存在しません"
        end
      end
    end
  end
end
