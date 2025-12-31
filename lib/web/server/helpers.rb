# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

# rubocop:disable Style/ClassAndModuleChildren

require "json"
require "lib/novel/novelsetting"

module Narou::ServerHelpers
  RELOAD_TIMING_DEFAULT = "every"
  FORCE_SETTING_DEFAULT_HINT = "未設定時：個別設定や default.* の値がそのまま利用されます".freeze

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

    `"#{RbConfig.ruby}" -v`.strip
  rescue
    config = RbConfig::CONFIG
    "ruby #{RUBY_VERSION}p#{config["PATCHLEVEL"]} [#{RUBY_PLATFORM}]"

  end

  #
  # 有効な novel ID だけの配列を生成する
  # ID が指定されなかったか、１件も存在しない場合は nil を返す
  #
  def select_valid_novel_ids(ids)
    return nil unless ids.is_a?(Array)
    result = ids.select do |id|
      # 数値または数値文字列をチェック
      case id
      when Integer
        true
      when String
        id =~ /^\d+$/
      else
        false
      end
    end.map(&:to_s) # 最終的に文字列に統一
    result.empty? ? nil : result
  end

  #
  # 現在のソート状態に基づいてIDを並び替える
  #
  def sort_ids_by_current_sort(ids)
    debug_puts "[DEBUG] sort_ids_by_current_sort called with #{ids ? ids.length : 0} IDs: #{ids.inspect}"
    return ids unless ids && ids.length > 0

    server_setting = Inventory.load("server_setting", :global)
    current_sort = server_setting["current_sort"]
    debug_puts "[DEBUG] Current sort from server: #{current_sort.inspect}"
    return ids unless current_sort

    order_column = current_sort["column"]
    order_dir = current_sort["dir"]
    debug_puts "[DEBUG] Sort params: column=#{order_column}, dir=#{order_dir}"
    return ids unless order_column && order_dir

    column_names = %w(id last_update general_lastup last_check_date title author sitename novel_type tags general_all_no length status
toc_url)
    sort_column = column_names[order_column]
    debug_puts "[DEBUG] Sort column: #{sort_column}"
    return ids unless sort_column

    # IDから小説データを取得してソート
    database = Database.instance
    novels_data = ids.map do |id|
      data = database[id.to_i]
      if data
        debug_puts "[DEBUG] Found data for ID #{id}"
      else
        debug_puts "[DEBUG] ID #{id}: not found"
      end
      data ? [id, data] : nil
    end.compact

    debug_puts "[DEBUG] Found #{novels_data.length} novels with data"

    # ソート実行
    debug_puts "[DEBUG] Before sort: #{novels_data.map {|n| [n[0], n[1][sort_column]]}.inspect}"

    novels_data.sort! do |a, b|
      # データベースのHashは文字列キーを使用
      val_a = a[1][sort_column] || 0
      val_b = b[1][sort_column] || 0

      debug_puts "[DEBUG] Comparing ID #{a[0]} (#{val_a}) vs ID #{b[0]} (#{val_b})"

      if val_a.is_a?(Numeric) && val_b.is_a?(Numeric)
        comparison = val_a <=> val_b
      else
        comparison = val_a.to_s <=> val_b.to_s
      end

      result = order_dir == "desc" ? -comparison : comparison
      debug_puts "[DEBUG] Comparison result: #{result} (#{order_dir})"
      result
    end

    debug_puts "[DEBUG] After sort: #{novels_data.map {|n| [n[0], n[1][sort_column]]}.inspect}"

    # ソート済みのIDのみを返す
    sorted_ids = novels_data.map { |novel| novel[0] }
    debug_puts "[DEBUG] Sorted IDs: #{sorted_ids.inspect}"
    sorted_ids
  end

  #
  # 固定されたソート状態に基づいてIDを並び替える（convert実行時点のソート状態を保持）
  #
  def sort_ids_with_fixed_state(ids, sort_state)
    debug_puts "[DEBUG] sort_ids_with_fixed_state called with #{ids ? ids.length : 0} IDs"
    debug_puts "[DEBUG] Fixed sort state: #{sort_state.inspect}"
    return ids unless ids && ids.length > 0
    return ids unless sort_state

    order_column = sort_state["column"]
    order_dir = sort_state["dir"]
    debug_puts "[DEBUG] Fixed sort params: column=#{order_column}, dir=#{order_dir}"
    return ids unless order_column && order_dir

    column_names = %w(id last_update general_lastup last_check_date title author sitename novel_type tags general_all_no length status
toc_url)
    sort_column = column_names[order_column.to_i]
    debug_puts "[DEBUG] Fixed sort column: #{sort_column}"
    return ids unless sort_column

    # IDから小説データを取得してソート（convert実行時点のデータを取得）
    database = Database.instance
    novels_data = ids.map do |id|
      data = database[id.to_i]
      data ? [id, data.dup] : nil # データをコピーして固定化
    end.compact

    debug_puts "[DEBUG] Found #{novels_data.length} novels with data for fixed sort"

    # ソート実行（固定されたソート条件で）
    novels_data.sort! do |a, b|
      val_a = a[1][sort_column] || 0
      val_b = b[1][sort_column] || 0

      if val_a.is_a?(Numeric) && val_b.is_a?(Numeric)
        comparison = val_a <=> val_b
      else
        comparison = val_a.to_s <=> val_b.to_s
      end

      order_dir == "desc" ? -comparison : comparison
    end

    # ソート済みのIDのみを返す
    sorted_ids = novels_data.map { |novel| novel[0] }
    debug_puts "[DEBUG] Fixed sorted IDs: #{sorted_ids.inspect}"
    sorted_ids
  end

  #
  # 現在のソート状態を日本語で表示する文字列を生成
  #
  def current_sort_display_string
    server_setting = Inventory.load("server_setting", :global)
    current_sort = server_setting["current_sort"]
    return "ID順" unless current_sort

    order_column = current_sort["column"]
    order_dir = current_sort["dir"]
    return "ID順" unless order_column && order_dir

    column_names = %w(ID 最終更新日 最新話掲載日 最終確認日 タイトル 作者 サイト名 小説種別 タグ 話数 文字数 状態 URL)
    column_display = column_names[order_column] || "不明"
    dir_display = order_dir == "desc" ? "降順" : "昇順"

    "#{column_display}#{dir_display}"
  end

  private

  def debug_puts(message)
    puts message if ENV["NAROU_DEBUG"] == "1"
  end

  def json_error!(status_code, message, extra = {})
    payload = { success: false, error: message }.merge(extra)
    halt status_code, { "Content-Type" => "application/json" }, JSON.generate(payload)
  end

  def bad_request!(message = "不正なリクエストです")
    json_error!(400, message)
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

  def default_hint_for_setting(name, definition)
    hint_map = if Narou.const_defined?(:SETTING_VARIABLES_WEBUI_DEFAULT_HINTS)
                 Narou::SETTING_VARIABLES_WEBUI_DEFAULT_HINTS
               else
                 {}
               end
    hint = hint_map[name]
    return hint if hint

    if name.start_with?("default_args.")
      command_name = name.split(".", 2).last
      return "未設定時：#{command_name} コマンドに追加の既定オプションは付与されません"
    end

    case definition[:tab]
    when :default
      if name == "default.enable_promo_tag_filter"
        return "未設定時：いいえ"
      end
      original_key = name.sub(/^default\./, "")
      original = original_setting_definition(original_key)
      return nil unless original
      formatted = format_setting_value(original[:value], original)
      "未設定時：#{formatted}"
    when :force
      FORCE_SETTING_DEFAULT_HINT
    end
  end

  def format_setting_value(value, definition = nil)
    case definition && definition[:type]
    when :select
      summary = select_summary(definition, value)
      return summary if summary
    when :multiple
      values = Array(value)
      return "未設定" if values.empty?
      formatted_values = values.map do |entry|
        select_summary(definition, entry) || format_setting_value(entry)
      end
      return formatted_values.join(", ")
    when :boolean
      return value_to_msg(value)
    end

    case value
    when TrueClass, FalseClass
      value_to_msg(value)
    when Array
      return "未設定" if value.empty?
      value.map { |entry| format_setting_value(entry) }.join(", ")
    when NilClass
      "未設定"
    else
      str = value.to_s
      str.empty? ? "（空文字）" : str
    end
  end

  def select_summary(definition, value)
    keys = definition[:select_keys]
    summaries = definition[:select_summaries]
    return nil unless keys && summaries
    index = keys.index(value)
    index ? summaries[index] : nil
  end

  def original_setting_definition(setting_name)
    index = NovelSetting::ORIGINAL_SETTINGS_KEY_INDEXES[setting_name]
    return nil unless index
    NovelSetting::ORIGINAL_SETTINGS[index]
  end

  def partial(template, *args)
    template_file_name = :"_#{template}"
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

  def concurrency_push(&)
    if Narou.concurrency_enabled?
      yield
    else
      Narou::WebWorker.push(&)
    end
  end
end
