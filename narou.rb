#! /usr/bin/env ruby --yjit
# frozen_string_literal: true

#
# Narou.rb ― 小説家になろうダウンロード＆整形スクリプト
#
# Copyright 2013 whiteleaf. All rights reserved.
#

require 'bootsnap'
Bootsnap.setup(
  cache_dir:            'tmp/cache',          # Path to your cache
  ignore_directories:   [],                   # Directory names to skip.
  development_mode:     false,                # Current working environment, e.g. RACK_ENV, RAILS_ENV, etc
  load_path_cache:      true,                 # Optimize the LOAD_PATH with a cache
  compile_cache_iseq:   true,                 # Compile Ruby code into ISeq cache, breaks coverage reporting.
  compile_cache_yaml:   true,                 # Compile YAML into a cache
  readonly:             true,                 # Use the caches but don't update them on miss or stale entries.
)

require_relative "lib/extension"
require_relative "lib/extensions/monkey_patches"
require_relative "lib/backtracer"

script_dir = File.expand_path(File.dirname(__FILE__))
$debug = File.exist?(File.join(script_dir, "debug"))

Encoding.default_external = Encoding::UTF_8
Narou::Backtracer.argv = ARGV

if ARGV.delete("--time")
  now = Time.now
  at_exit do
    puts "実行時間 #{Time.now - now}秒"
  end
end

require_relative "lib/inventory"

$development = Narou.commit_version.!
if $development
  begin
    require "pry"
    require "awesome_print"
  rescue LoadError
  end
end

global = Inventory.load("global_setting", :global)
$display_backtrace = ARGV.delete("--backtrace")
$display_backtrace ||= $debug
$disable_color = ARGV.delete("--no-color")
$disable_color ||= global["no-color"]
$color_parser ||= global["color-parser"] || "system"

require_relative "lib/narou_logger"
require_relative "lib/version"
require_relative "lib/commandline"

exit Narou::Backtracer.capture {
  CommandLine.run!(ARGV.map(&:dup))
}
