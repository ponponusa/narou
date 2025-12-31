# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

#
# テスト用にデータベース等を設定する
#

require "time"
require "lib/core/narou"
require "lib/core/database"

class Module
  def const_replace(name, value)
    remove_const(name)
    const_set(name, value)
  end
end

Narou.const_replace :LOCAL_SETTING_DIR_NAME, ".test_dot_narou"
Narou.const_replace :GLOBAL_SETTING_DIR_NAME, ".test_dot_narousetting"
Database.const_replace :ARCHIVE_ROOT_DIR_PATH, ".test_novel_data/"

Narou.flush_cache

def install_fixtures
  local_dir = ".test_dot_narou"
  _global_dir = ".test_dot_narousetting"
  fixture_narou = File.join("spec", "fixtures", ".test_dot_narou")
  fixture_novel_data = File.join("spec", "fixtures", ".test_novel_data")
  novel_data_dir = ".test_novel_data"

  if File.directory?(local_dir)
    version = Time.parse(File.read(File.join(local_dir, "fixture_version.txt")))
    fixture_version = Time.parse(File.read(File.join(fixture_narou, "fixture_version.txt")))
    return if version == fixture_version
    FileUtils.rm_r(local_dir, force: true)
    FileUtils.rm_r(novel_data_dir, force: true)
  end
  FileUtils.cp_r(fixture_narou, local_dir)
  FileUtils.cp_r(fixture_novel_data, novel_data_dir)
  puts "== Copied fixtures version #{fixture_version}"
end

install_fixtures
