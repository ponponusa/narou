# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "lib/core/inventory"
require "novel/downloader"

module Command
  class Browser < CommandBase
    def self.oneline_help
      "小説の掲載ページをブラウザで開きます"
    end

    def initialize
      super("<target> [<target2> ...] [options]")
      @opt.separator <<-EOS

  ・指定した小説の掲載ページをブラウザで開きます。

  Examples:
    narou-mod browser n9669bk
    narou-mod browser musyoku -v
    narou-mod b 0

  Options:
      EOS

      @opt.on("-v", "--vote", "小説の投票・感想を投稿するページを表示する(なろうのみ)") {
        @options["vote"] = true
      }
    end

    def execute(argv)
      super
      display_help! if argv.empty?
      tagname_to_ids(argv)
      argv.each do |target|
        data = Downloader.get_data_by_target(target)
        unless data
          error "#{target} は存在しません"
          next
        end
        toc_url = data["toc_url"]
        if @options["vote"]
          # TODO: 最新話の場所をAPIで取得する
          data_dir = Downloader.get_novel_data_dir_by_target(data["id"])
          toc_path = File.join(data_dir, Downloader::TOC_FILE_NAME)
          begin
            latest_index = YAML.unsafe_load_file(toc_path)["subtitles"].last["index"]
          rescue SystemCallError
            # bootsnap on Windows can raise Errno::E01 errors, fallback to standard YAML
            latest_index = YAML.unsafe_load(File.read(toc_path))["subtitles"].last["index"]
          end
          open_url = "#{toc_url + latest_index}/#my_novelpoint"
        else
          open_url = toc_url
        end
        Helper.open_browser(open_url)
        puts open_url
      end
    end
  end
end
