#!/usr/bin/env ruby

# アプリサーバーファイルの重複部分を削除するスクリプト

input_file = "/mnt/c/Users/rumia/Desktop/APP/Webnovel/narou/lib/web/appserver.rb"
output_file = "/mnt/c/Users/rumia/Desktop/APP/Webnovel/narou/lib/web/appserver_cleaned.rb"

lines = File.readlines(input_file)

# 重複部分の開始と終了を特定
start_index = nil
end_index = nil

lines.each_with_index do |line, index|
  if line.strip.start_with?('post "/api/cancel" do') && start_index.nil?
    # 最初の post "/api/cancel" を見つけた
    if lines[index + 1]&.strip&.start_with?('# DataTables')
      start_index = index
      puts "Found duplicate start at line #{index + 1}"
    end
  end
  
  if start_index && line.strip.start_with?('post "/api/cancel" do') && index > start_index
    # 2つ目の post "/api/cancel" を見つけた
    end_index = index - 1
    puts "Found duplicate end at line #{index}"
    break
  end
end

if start_index && end_index
  puts "Removing lines #{start_index + 1} to #{end_index + 1}"
  clean_lines = lines[0...start_index] + lines[end_index + 1..-1]
  File.write(output_file, clean_lines.join)
  puts "Cleaned file written to #{output_file}"
else
  puts "Could not find duplicate section"
end