# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require_relative "../helper"

module Command
  class Version < CommandBase
    def self.oneline_help
      "バージョンを表示します"
    end

    def initialize
      super("[options...]")
      @opt.separator <<-EOS

  ・バージョンを表示します

  Options:
      EOS
      @opt.on("-m", "--more", "Java と AozoraEpub3 のバージョンも表示する") {
        @options["more"] = true
      }
    end

    def execute(argv)
      super
      puts self.class.create_version_string
      version_more if @options["more"]
    end

    def version_more
      # NovelConverter.txt_to_epubより必要な部分を持ってきた
      pwd = Dir.pwd
      java_encoding = "-Dfile.encoding=UTF-8" +
                      " -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8" +
                      " -Dsun.stdout.encoding=UTF-8 -Dsun.stderr.encoding=UTF-8"

      aozoraepub3_path = Narou.aozoraepub3_path
      if aozoraepub3_path
        aozoraepub3_basename = File.basename(aozoraepub3_path)
        aozoraepub3_dir = File.dirname(aozoraepub3_path)
        # なるべく実行環境を揃える意味でもchdirしてからjava -versionする
        Dir.chdir(aozoraepub3_dir)
      end

      command_java = %!java #{java_encoding} -version!
      command_ae3 = %!java #{java_encoding} -cp #{aozoraepub3_basename} AozoraEpub3 --help!
      if Helper.os_windows?
        command_java = "cmd /c #{command_java}".encode(Encoding::Windows_31J)
        command_ae3 = "cmd /c #{command_ae3}".encode(Encoding::Windows_31J)
      end

      begin
        puts
        res = Helper::AsyncCommand.exec(command_java) do
          true
        end
        print res[0]
        print res[1]
        if ! res[2].success?
          puts res[2]
          puts "Java実行時にエラーが発生しました"
          # javaの実行でエラーが発生したならAozoraEpub3の実行は試みない
        elsif ! aozoraepub3_path
          puts
          puts "AozoraEpub3が見つかりません"
        else
          puts
          res = Helper::AsyncCommand.exec(command_ae3) do
            true
          end
          outs = res[0].lines
          if res[2].success? && outs[2].start_with?(" -c,") && outs[-1].start_with?(" -tf")
            # ヘルプメッセージのみと思われるならバージョン出力のみにする
            print "AozoraEpub3　"
            print outs[1]
          else
            # ヘルプメッセージではなさそうならすべて出力する
            puts res
            unless res[2].success?
              puts "AozoraEpub3実行時にエラーが発生しました"
            end
          end
        end
      ensure
        Dir.chdir(pwd)
      end
    end

    def self.create_version_string
      postfix = (Narou.commit_version ? "" : " (develop)")
      "#{Narou::VERSION}#{postfix}"
    end
  end
end
