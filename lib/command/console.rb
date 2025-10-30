# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

if $development
  module Command
    class Console < CommandBase
      def self.oneline_help
        "開発用コンソール"
      end

      def initialize
        super()
        @opt.separator <<~HELP

          ・開発時のみ有効になるコンソール。pry のインストール必須
        HELP
      end

      def execute(argv)
        # console は素のSTDOUTを使う
        $stdout = STDOUT
        super

        # 実行時にだけ遅延ロード（本体の起動を重くしない）
        begin
          require "pry"
          require "awesome_print" rescue nil
        rescue LoadError
          error "pry が見つかりません。`gem install pry` を実行してください"
          exit Narou::EXIT_ERROR_CODE
        end

        Pry.start(TOPLEVEL_BINDING)
      end
    end
  end
end
