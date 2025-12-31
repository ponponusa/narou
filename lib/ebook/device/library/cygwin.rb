# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "open3"

module Device::Library
  module Cygwin
    def get_device_root_dir(volume_name)
      return nil if volume_name.nil? || volume_name.empty?
      # cygwinのドライブマウント先のpath prefixを取得する。
      # 1.7.28では二行目の行頭
      mount_output, _status = Open3.capture2("mount", "-p")
      mount_root = mount_output.split("\n").last.split(/\s+/).first

      Dir.glob("#{mount_root}/*") do |drive_path|
        drive   = drive_path.sub(%r{.*/}, "")
        # windowsのvolコマンドを利用してがんばってvolume_nameを探す。
        # 一行目にボリュームラベルが含まれる。
        # volume_nameが "volume" とか "hoge(*)" などだとはまる。
        cmd     = "cmd /c vol #{drive}:".encode(Encoding::Windows_31J)
        capture, _status = Open3.capture2(cmd)
        capture = capture.force_encoding(Encoding::Windows_31J).encode(Encoding::UTF_8)
        if capture.split("\n").first.match(/#{Regexp.escape(volume_name)}/i)
          return drive_path
        end
      end
      nil
    end
  end
end
