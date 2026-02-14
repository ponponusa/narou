# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "lib/web/helpers/novel_status_helper"

#
# 小説一覧データの処理を担当するモジュール
#
# 大規模なデータ処理ロジック（フィルタリング、ソート、ページング、キャッシング）を集約
#
module NovelListProcessor
  # キャッシュ管理用のクラス変数
  @@api_list_cache = {}
  @@api_list_cache_time = nil
  @@api_list_cache_duration = 10 # 10秒キャッシュ

  @@full_sorted_ids_cache = {}
  @@full_ids_cache_time = nil
  @@full_ids_cache_duration = 10 # 10秒キャッシュ

  def self.clear_api_list_cache
    @@api_list_cache = {}
    @@api_list_cache_time = nil
  end

  def self.clear_full_ids_cache
    @@full_sorted_ids_cache = {}
    @@full_ids_cache_time = nil
  end

  def self.clear_all_cache
    clear_api_list_cache
    clear_full_ids_cache
  end

  #
  # フィルタされた全小説IDを取得
  #
  def get_all_filtered_novel_ids(params)
    view_frozen = query_to_boolean(params["view_frozen"], default: true)
    view_nonfrozen = query_to_boolean(params["view_nonfrozen"], default: true)

    # 検索パラメータの安全な取得
    search_value = nil
    if params["search"] && params["search"].is_a?(Hash)
      search_value = params["search"]["value"]
    elsif params["search[value]"]
      search_value = params["search[value]"]
    end

    # フィルタ文字列の取得
    url_filter = params["filter"]
    combined_filter = [search_value, url_filter].compact.reject(&:empty?).join(" ")

    # データベースから全データを取得
    database_values = Database.instance.get_object.values
    debug_puts "[DEBUG] Database values count: #{database_values.length}"
    filtered_data = database_values.map do |data|
      id = data["id"]
      debug_puts "[DEBUG] Processing novel ID: #{id} (#{id.class})"
      is_frozen = Narou.novel_frozen?(id)
      tags = data["tags"] || []

      {
        id: id.to_i, # 数値として保持
        title: data["title"],
        author: data["author"],
        sitename: data["sitename"],
        status: data["status"],
        frozen: is_frozen,
        raw_tags: tags
      }
    end

    # 凍結状態でフィルタリング
    unless view_frozen && view_nonfrozen
      filtered_data = filtered_data.select do |item|
        if view_frozen && !view_nonfrozen
          item[:frozen]
        elsif !view_frozen && view_nonfrozen
          !item[:frozen]
        else
          true
        end
      end
    end

    # 検索フィルタリング
    if combined_filter && !combined_filter.strip.empty?
      begin
        filtered_data = apply_filter(filtered_data, combined_filter)
      rescue StandardError => e
        # エラーの場合はフィルターを適用せずに続行
      end
    end

    # IDのみを抽出して返す
    result_ids = filtered_data.map { |item| item[:id] }
    debug_puts "[DEBUG] Final result IDs: #{result_ids.inspect}"
    result_ids
  end

  #
  # DataTables用の小説一覧データを処理
  #
  def process_novel_list_request(params)
    view_frozen = query_to_boolean(params["view_frozen"], default: true)
    view_nonfrozen = query_to_boolean(params["view_nonfrozen"], default: true)

    # DataTablesのサーバーサイド処理パラメータ
    draw = params["draw"].to_i
    start = params["start"].to_i || 0
    length = params["length"].to_i || 50

    # 検索パラメータの安全な取得
    search_value = extract_search_value(params)

    # フィルタパラメータの取得（タグフィルタリング含む）
    filter_value = params["filter"]

    # ソートパラメータの安全な取得
    order_column, order_dir = extract_sort_params(params)

    # ソート状態をサーバー側に保存
    save_sort_state(order_column, order_dir) if order_column && order_dir

    # 軽量なタグ処理モード（大量データ用）
    lightweight_mode = params["lightweight"] == "true"

    # キャッシュされたデータを取得または生成
    cached_data = get_or_create_cached_data(lightweight_mode)

    # フィルタリング
    filtered_data = cached_data.select do |item|
      (view_frozen || !item[:frozen]) && (view_nonfrozen || item[:frozen])
    end

    # フィルタ処理（タグフィルタリング含む）
    combined_filter = [filter_value, search_value].compact.join(" ").strip

    unless combined_filter.empty?
      begin
        filtered_data = apply_filter(filtered_data, combined_filter)
      rescue StandardError => e
        # フィルタエラーの場合はフィルタリングをスキップ
        puts "Filter error: #{e.message}"
      end
    end

    records_total = cached_data.size
    records_filtered = filtered_data.size

    # ソート処理
    if order_column && order_dir
      filtered_data = apply_sort(filtered_data, order_column, order_dir)
    end

    # ページネーション
    paginated_data, warning = apply_pagination(filtered_data, start, length)

    result = {
      draw: draw,
      data: paginated_data,
      recordsTotal: records_total,
      recordsFiltered: records_filtered
    }
    result[:warning] = warning if warning
    result
  end

  #
  # ソート済み全IDリストを取得（ページングなし）
  #
  def get_full_sorted_ids(params = {})
    debug_puts "[DEBUG] get_full_sorted_ids called with params: #{params.inspect}"

    # キャッシュキーの生成（フィルター・ソート条件に基づく）
    server_setting = Inventory.load("server_setting", :global)
    current_sort = server_setting["current_sort"] || { "column" => 0, "dir" => "asc" }

    cache_key = {
      filter: params["filter"],
      search: params["search"],
      view_frozen: params["view_frozen"],
      view_nonfrozen: params["view_nonfrozen"],
      sort: current_sort
    }.to_s.hash

    current_time = Time.now

    # キャッシュチェック
    if @@full_sorted_ids_cache[cache_key] && @@full_ids_cache_time &&
       (current_time - @@full_ids_cache_time) < @@full_ids_cache_duration
      debug_puts "[DEBUG] Using cached full sorted IDs: #{@@full_sorted_ids_cache[cache_key].length} items"
      return @@full_sorted_ids_cache[cache_key]
    end

    debug_puts "[DEBUG] Generating new full sorted IDs"

    # process_novel_list_requestと同じフィルタリング・ソート処理（ページング無し）
    view_frozen = query_to_boolean(params["view_frozen"], default: true)
    view_nonfrozen = query_to_boolean(params["view_nonfrozen"], default: true)

    # 検索パラメータの取得
    search_value = extract_search_value(params)
    filter_value = params["filter"]

    # キャッシュされたデータを使用（軽量モードは使わない）
    cached_data = get_or_create_cached_data(false)

    # フィルタリング
    filtered_data = cached_data.select do |item|
      (view_frozen || !item[:frozen]) && (view_nonfrozen || item[:frozen])
    end

    # フィルタ処理
    combined_filter = [filter_value, search_value].compact.join(" ").strip

    unless combined_filter.empty?
      begin
        filtered_data = apply_filter(filtered_data, combined_filter)
      rescue StandardError => e
        puts "Filter error in get_full_sorted_ids: #{e.message}"
      end
    end

    # ソート処理
    order_column = current_sort["column"]
    order_dir = current_sort["dir"]

    if order_column && order_dir
      filtered_data = apply_sort(filtered_data, order_column, order_dir)
    end

    # IDのみを取得（文字列として）
    sorted_ids = filtered_data.map { |item| item[:id].to_s }

    # キャッシュに保存
    @@full_sorted_ids_cache[cache_key] = sorted_ids
    @@full_ids_cache_time = current_time

    debug_puts "[DEBUG] Generated #{sorted_ids.length} sorted IDs: #{sorted_ids.first(5)}..."
    sorted_ids
  end

  private

  #
  # 検索パラメータを抽出
  #
  def extract_search_value(params)
    if params["search"] && params["search"].is_a?(Hash)
      params["search"]["value"]
    elsif params["search[value]"]
      params["search[value]"]
    end
  end

  #
  # ソートパラメータを抽出
  #
  def extract_sort_params(params)
    order_column = nil
    order_dir = nil
    if params["order"] && params["order"].is_a?(Hash) && params["order"]["0"]
      order_column = params["order"]["0"]["column"].to_i
      order_dir = params["order"]["0"]["dir"]
    elsif params["order[0][column]"] && params["order[0][dir]"]
      order_column = params["order[0][column]"].to_i
      order_dir = params["order[0][dir]"]
    end
    [order_column, order_dir]
  end

  #
  # ソート状態をサーバー設定に保存
  #
  def save_sort_state(order_column, order_dir)
    debug_puts "[DEBUG] Saving sort state: column=#{order_column}, dir=#{order_dir}"
    server_setting = Inventory.load("server_setting", :global)
    server_setting["current_sort"] = {
      "column" => order_column,
      "dir" => order_dir
    }
    begin
      server_setting.save
      debug_puts "[DEBUG] Sort state saved successfully"
    rescue => e
      debug_puts "[DEBUG] Failed to save sort state: #{e.message}"
      # ソート状態の保存に失敗してもリクエスト処理は継続
    end
  end

  #
  # キャッシュされたデータを取得または生成
  #
  def get_or_create_cached_data(lightweight_mode)
    cache_key = lightweight_mode ? :lightweight : :full
    current_time = Time.now

    if @@api_list_cache && @@api_list_cache[cache_key] && @@api_list_cache_time &&
       (current_time - @@api_list_cache_time) < @@api_list_cache_duration
      return @@api_list_cache[cache_key]
    end

    # キャッシュが無い場合は新規作成
    database = Database.instance
    database_values = database.get_object.values

    cached_data = database_values.map do |data|
      build_novel_item(data, lightweight_mode)
    end

    # キャッシュを更新
    @@api_list_cache ||= {}
    @@api_list_cache[cache_key] = cached_data
    @@api_list_cache_time = current_time

    cached_data
  end

  #
  # データベースレコードから小説アイテムを構築
  #
  def build_novel_item(data, lightweight_mode)
    id = data["id"]
    is_frozen = Narou.novel_frozen?(id)
    tags = data["tags"] || []
    promo_tags = data["promo_tags"].is_a?(Array) ? data["promo_tags"] : []
    promo_tags_title = data["promo_tags_title"].is_a?(Array) ? data["promo_tags_title"] : []
    promo_tags_author = data["promo_tags_author"].is_a?(Array) ? data["promo_tags_author"] : []
    author_url = data["author_url"]

    # サイトトップURLを生成（toc_urlから）
    toc_url = data["toc_url"]
    site_top_url = nil
    if toc_url
      begin
        uri = URI.parse(toc_url)
        site_top_url = "#{uri.scheme}://#{uri.host}/"
      rescue URI::InvalidURIError
        # URL解析に失敗した場合はnil
      end
    end

    # タグHTML生成（軽量モードと通常モードで処理を分ける）
    tags_html = build_tags_html(tags, lightweight_mode)

    title_text = data["title"].to_s
    author_text = data["author"].to_s

    {
      id: id,
      last_update: data["last_update"].to_i,
      title: title_text,
      title_plain: title_text,
      author: h(author_text),
      author_plain: author_text,
      sitename: data["sitename"],
      toc_url: data["toc_url"],
      novel_type: data["novel_type"] == 2 ? "短編" : "連載",
      tags: tags_html,
      raw_tags: tags, # 生のタグ配列も追加（JavaScript側での直接アクセス用）
      status: NovelStatusHelper.generate_novel_status(id, data),
      promo_tags: promo_tags,
      promo_tags_title: promo_tags_title,
      promo_tags_author: promo_tags_author,
      promo_tags_text: promo_tags.join(" "),
      author_url: author_url,
      site_top_url: site_top_url,
      actions: "", # アクションボタンはJavaScript側で動的に生成
      frozen: is_frozen,
      new_arrivals_date: data["new_arrivals_date"].tap { |m| break m.to_i if m },
      general_lastup: data["general_lastup"].tap { |m| break m.to_i if m },
      general_all_no: data["general_all_no"],
      last_check_date: data["last_check_date"].tap { |m| break m.to_i if m },
      length: data["length"],
    }
  end

  #
  # タグのHTML表現を構築
  #
  def build_tags_html(tags, lightweight_mode)
    return "" if tags.empty?

    if lightweight_mode
      # 軽量表示だが、data-tag属性は保持
      visible_tags = tags.first(3)
      hidden_count = tags.size > 3 ? tags.size - 3 : 0

      tag_spans = visible_tags.map { |tag| %!<span class="tag-simple" data-tag="#{tag}">#{tag}</span>! }
      result = tag_spans.join(", ")

      if hidden_count > 0
        result += %! <span class="tag-more">... (+#{hidden_count}個)</span>!
      end

      # 隠されたタグもdata-tag属性として保持（検索用）
      if tags.size > 3
        hidden_tags = tags[3..-1]
        hidden_spans = hidden_tags.map { |tag| %!<span class="tag-hidden" data-tag="#{tag}" style="display:none;"></span>! }
        result += hidden_spans.join
      end

      result + %!&nbsp;<span class="tag tag-reset label label-white" data-tag="" data-toggle="tooltip" title="タグ検索を解除">&nbsp;</span>!
    else
      %!#{decorate_tags(tags)}&nbsp;<span class="tag tag-reset label label-white"! +
      %!data-tag="" data-toggle="tooltip" title="タグ検索を解除">&nbsp;</span>!
    end
  end

  #
  # フィルタを適用
  #
  def apply_filter(data, combined_filter)
    # フィルタ文字列を単語に分割
    filter_words = combined_filter.split(/\s+/)

    data.select do |item|
      filter_words.all? do |word|
        if word.match(/^([-^]?)tag:(.+)$/i)
          # タグフィルタリング（OR検索対応）
          apply_tag_filter(item, $1, $2)
        else
          # 通常の検索フィルタリング
          apply_text_filter(item, word)
        end
      end
    end
  end

  #
  # タグフィルタを適用
  #
  def apply_tag_filter(item, exclude_flag, tag_names_part)
    tag_names_part = tag_names_part.downcase

    # パイプ（|）でOR検索をサポート
    tag_names = tag_names_part.split("|").map(&:strip)

    if tag_names.size > 1
      # OR検索: いずれかのタグにマッチすればOK
      has_any_tag = tag_names.any? do |tag_name|
        item[:raw_tags].any? { |tag| tag.downcase.include?(tag_name) }
      end

      case exclude_flag
      when "-", "^"
        !has_any_tag  # いずれのタグも持たない
      else
        has_any_tag   # いずれかのタグを持つ
      end
    else
      # 単一タグの従来処理
      tag_name = tag_names.first
      has_tag = item[:raw_tags].any? { |tag| tag.downcase.include?(tag_name) }

      case exclude_flag
      when "-", "^"
        !has_tag  # 除外
      else
        has_tag   # 包含
      end
    end
  end

  #
  # テキストフィルタを適用
  #
  def apply_text_filter(item, word)
    search_regex = Regexp.new(Regexp.escape(word), Regexp::IGNORECASE)
    item[:title].to_s.match?(search_regex) ||
    item[:author].to_s.match?(search_regex) ||
    item[:sitename].to_s.match?(search_regex) ||
    item[:status].to_s.match?(search_regex) ||
    item[:novel_type].to_s.match?(search_regex) ||
    item[:raw_tags].any? { |tag| tag.match?(search_regex) }
  end

  #
  # ソートを適用
  #
  def apply_sort(data, order_column, order_dir)
    column_names = %w(
      id last_update general_lastup last_check_date
      title author sitename novel_type
      tags general_all_no length average_length
      status actions frozen new_arrivals_date
    )
    sort_column = column_names[order_column]
    return data unless sort_column

    data.sort do |a, b|
      val_a = a[sort_column.to_sym] || 0
      val_b = b[sort_column.to_sym] || 0

      if val_a.is_a?(Numeric) && val_b.is_a?(Numeric)
        comparison = val_a <=> val_b
      else
        comparison = val_a.to_s <=> val_b.to_s
      end

      order_dir == "desc" ? -comparison : comparison
    end
  end

  #
  # ページネーションを適用
  #
  def apply_pagination(data, start, length)
    if length > 0 && length != -1
      return [data[start, length] || [], nil]
    end

    # "Show All" の場合 (length == -1) は全てのデータを返す
    # データ量に応じて段階的な制限を適用
    total_count = data.size
    if total_count <= 1000
      # 1000件以下なら全て表示
      [data, nil]
    elsif total_count <= 100000
      # 100000件以下なら全て表示（警告なし）
      [data, nil]
    else
      # 100000件を超える場合は最大件数を制限
      max_show_all = 100000
      [data.first(max_show_all), "表示件数が多いため、最初の#{max_show_all}件のみ表示しています。"]
    end
  end
end
