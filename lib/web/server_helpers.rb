# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

# rubocop:disable Style/ClassAndModuleChildren

module Narou::ServerHelpers
  RELOAD_TIMING_DEFAULT = "every"

  #
  # タグをHTMLで装飾する
  #
  def decorate_tags(tags)
    tags.sort.map do |tag|
      %!<span class="tag label label-#{Command::Tag.get_color(tag)}" data-tag="#{escape_html(tag)}">#{escape_html(tag)}</span>!
    end.join(" ")
  end

  #
  # タグをHTMLで装飾する(除外タグ指定用)
  #
  def decorate_exclusion_tags(tags)
    tags.sort.map do |tag|
      %!<span class="tag label label-#{Command::Tag.get_color(tag)}" data-exclusion-tag="#{escape_html(tag)}">^tag:#{escape_html(tag)}</span>!
    end.join(" ")
  end

  #
  # Rubyバージョンを構築
  #
  def build_ruby_version
    begin
      `"#{RbConfig.ruby}" -v`.strip
    rescue
      config = RbConfig::CONFIG
      "ruby #{RUBY_VERSION}p#{config["PATCHLEVEL"]} [#{RUBY_PLATFORM}]"
    end
  end

  #
  # 有効な novel ID だけの配列を生成する
  # ID が指定されなかったか、１件も存在しない場合は nil を返す
  #
  def select_valid_novel_ids(ids)
    return nil unless ids.kind_of?(Array)
    result = ids.select do |id|
      id =~ /^\d+$/
    end
    result.empty? ? nil : result
  end

  #
  # 現在のソート状態に基づいてIDを並び替える
  #
  def sort_ids_by_current_sort(ids)
    puts "[DEBUG] sort_ids_by_current_sort called with #{ids ? ids.length : 0} IDs: #{ids.inspect}"
    return ids unless ids && ids.length > 0
    
    server_setting = Inventory.load("server_setting", :global)
    current_sort = server_setting["current_sort"]
    puts "[DEBUG] Current sort from server: #{current_sort.inspect}"
    return ids unless current_sort
    
    order_column = current_sort["column"]
    order_dir = current_sort["dir"]
    puts "[DEBUG] Sort params: column=#{order_column}, dir=#{order_dir}"
    return ids unless order_column && order_dir
    
    column_names = ["id", "last_update", "general_lastup", "last_check_date", "title", "author", "sitename", "novel_type", "tags", "general_all_no", "length", "status", "toc_url"]
    sort_column = column_names[order_column]
    puts "[DEBUG] Sort column: #{sort_column}"
    return ids unless sort_column
    
    # IDから小説データを取得してソート
    database = Database.instance
    novels_data = ids.map do |id|
      data = database[id.to_i]
      if data
        puts "[DEBUG] ===== ID #{id} COMPLETE DATA ANALYSIS ====="
        puts "[DEBUG] Data class: #{data.class}"
        puts "[DEBUG] Data methods: #{data.methods.sort.select{|m| !Object.new.methods.include?(m)}.inspect}"
        puts "[DEBUG] Data respond_to?('[]'): #{data.respond_to?('[]')}"
        puts "[DEBUG] All keys (raw): #{data.keys.inspect rescue 'NO KEYS METHOD'}"
        puts "[DEBUG] All keys (to_s): #{data.keys.map(&:to_s).inspect rescue 'NO KEYS METHOD'}"
        
        # Try different access methods
        puts "[DEBUG] Access method tests:"
        puts "[DEBUG]   data['#{sort_column}']: #{data[sort_column] rescue 'ERROR'}"
        puts "[DEBUG]   data[:#{sort_column}]: #{data[sort_column.to_sym] rescue 'ERROR'}"
        puts "[DEBUG]   data.#{sort_column}: #{data.send(sort_column) rescue 'ERROR'}"
        puts "[DEBUG]   data.send('#{sort_column}'): #{data.send(sort_column) rescue 'ERROR'}"
        
        # Show a sample of actual data
        puts "[DEBUG] Sample data keys and values:"
        begin
          data.keys.first(5).each do |key|
            puts "[DEBUG]   #{key.inspect} (#{key.class}): #{data[key].inspect}"
          end
        rescue
          puts "[DEBUG]   Could not iterate keys"
        end
        
        puts "[DEBUG] ===== END COMPLETE ANALYSIS FOR ID #{id} ====="
      else
        puts "[DEBUG] ID #{id}: not found"
      end
      data ? [id, data] : nil
    end.compact
    
    puts "[DEBUG] Found #{novels_data.length} novels with data"
    
    # ソート実行
    puts "[DEBUG] Before sort: #{novels_data.map{|n| [n[0], n[1][sort_column.to_s] || n[1][sort_column.to_sym]]}.inspect}"
    
    novels_data.sort! do |a, b|
      # 文字列キーと文字列キーの両方を試す
      val_a = a[1][sort_column.to_s] || a[1][sort_column.to_sym] || 0
      val_b = b[1][sort_column.to_s] || b[1][sort_column.to_sym] || 0
      
      puts "[DEBUG] Comparing ID #{a[0]} (#{val_a}) vs ID #{b[0]} (#{val_b})"
      
      if val_a.is_a?(Numeric) && val_b.is_a?(Numeric)
        comparison = val_a <=> val_b
      else
        comparison = val_a.to_s <=> val_b.to_s
      end
      
      result = order_dir == "desc" ? -comparison : comparison
      puts "[DEBUG] Comparison result: #{result} (#{order_dir})"
      result
    end
    
    puts "[DEBUG] After sort: #{novels_data.map{|n| [n[0], n[1][sort_column.to_s] || n[1][sort_column.to_sym]]}.inspect}"
    
    # ソート済みのIDのみを返す
    sorted_ids = novels_data.map { |novel| novel[0] }
    puts "[DEBUG] Sorted IDs: #{sorted_ids.inspect}"
    sorted_ids
  end

  #
  # フォーム情報の真偽値データを実際のデータに変換
  #
  def convert_on_off_to_boolean(str)
    case str
    when "on"
      true
    when "off"
      false
    else
      nil
    end
  end

  #
  # nil true false を nil on off という文字列に変換
  #
  def convert_boolean_to_on_off(bool)
    case bool
    when TrueClass
      "on"
    when FalseClass
      "off"
    else
      "nil"
    end
  end

  #
  # HTMLエスケープヘルパー
  #
  def h(text)
    Rack::Utils.escape_html(text)
  end

  #
  # 与えられたデータが真偽値だった場合、設定画面用に「はい」「いいえ」に変換する
  # 真偽値ではなかった場合、そのまま返す
  #
  def value_to_msg(value)
    case value
    when TrueClass
      "はい"
    when FalseClass
      "いいえ"
    else
      value
    end
  end

  def notepad_text_path
    File.join(Narou.local_setting_dir, "notepad.txt")
  end

  def query_to_boolean(value, default: false)
    case value
    when "1", 1, "true", true
      true
    when "0", 0, "false", false
      false
    else
      default
    end
  end

  def table_reload_timing
    Inventory.load("local_setting")["webui.table.reload-timing"] || RELOAD_TIMING_DEFAULT
  end

  def partial(template, *args)
    template_file_name = "_#{template}".intern
    options = args.last.is_a?(Hash) ? args.pop : {}
    options[:layout] = false
    collection = options.delete(:collection)
    if collection
      collection.inject([]) do |buffer, member|
        buffer << haml(template_file_name, options.merge(locals: { template => member }))
      end.join("\n")
    else
      haml(template_file_name, options)
    end
  end

  def embed_concurrency_enabled
    <<~HTML
      <input type="hidden" id="concurrency-enabled" value="#{Narou.concurrency_enabled?}">
    HTML
  end

  def embed_performance_mode
    local_setting = Inventory.load("local_setting")
    performance_mode = local_setting["webui.performance-mode"] || "auto"
    <<~HTML
      <input type="hidden" id="performance-mode" value="#{performance_mode}">
    HTML
  end

  def concurrency_push(&block)
    if Narou.concurrency_enabled?
      yield
    else
      Narou::WebWorker.push(&block)
    end
  end
end
