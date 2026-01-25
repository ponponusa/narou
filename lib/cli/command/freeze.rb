# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "lib/core/database"
require "lib/novel/downloader"
require "lib/core/inventory"

module Command
  class Freeze < CommandBase
    def self.oneline_help
      "小説の凍結設定を行います"
    end

    def initialize
      super("<target> [<target2> ...] [options]")
      @opt.separator <<-EOS

  ・指定した小説を凍結し、変更不可属性を付与します。
  ・凍結することでダウンロード、アップデート及び削除が出来なくなります。
  ・凍結済みの小説を指定した場合、凍結が解除されます。

  Examples:
    narou-mod freeze --list
    narou-mod freeze n9669bk
    narou-mod freeze 0 1 musyoku

  Options:
      EOS
      @opt.on("-l", "--list", "凍結中小説の一覧を表示") {
        output_freeze_list
        exit 0
      }
      @opt.on("--on", "現在の状態にかかわらず凍結する") {
        @options["on"] = true
      }
      @opt.on("--off", "現在の状態にかかわらず解除する") {
        @options["off"] = true
      }
    end

    def output_freeze_list
      require "lib/cli/command/list" unless defined?(Command::List)
      List.execute!("--filter", "frozen")
    end

    def execute(argv)
      super
      display_help! if argv.empty?
      tagname_to_ids(argv)
      frozen_list = Inventory.load("freeze")
      argv.each do |target|
        data = Downloader.get_data_by_target(target)
        unless data
          puts "#{target} は存在しません"
          next
        end
        id = data["id"]
        title = data["title"]
        flag = !frozen_list.include?(id)
        flag = true if @options["on"]
        flag = false if @options["off"]
        if flag
          frozen_list[id] = true
          puts "#{title} を凍結しました"
        else
          frozen_list.delete(id)
          # 凍結解除時に404タグも削除
          tags = data["tags"] || []
          if tags.include?("404")
            tags.delete("404")
            database = Database.instance
            database[id]["tags"] = tags
            database.save_database
          end
          puts "#{title} の凍結を解除しました"
          next
        end
      end
      frozen_list.save
    end
  end
end
