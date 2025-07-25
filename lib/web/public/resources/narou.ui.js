/* -*- coding: utf-8 -*-
 *
 * Copyright 2013 whiteleaf. All rights reserved.
 */
var t;   // for debugging
$(function() {
  "use strict";

  var touchable_device = "ontouchstart" in window;
  var click_event_name = (touchable_device ? "touchstart" : "click");
  var storage = new Narou.Storage();

  // refreshTooltop関数を早期に定義
  function refreshTooltop(id, title, placement) {
    $(id)
      .tooltip("destroy")
      .tooltip({ title: title, placement: placement })
      .on("shown.bs.tooltip", function(e) {
        setTimeout(function() {
          $(e.target).tooltip("hide");
        }, 3500);
      });
  }

  var datatables_init_completed = false;

  // MEMO: table 全てに対して操作
  // table.$("tr.selected").removeClass("selected");
  // MEMO: .selected が付いている行を全て取得
  // table.rows('.selected').data().length

  // 端末ごとの表示項目初期設定
  var cell_visible = (touchable_device ?
      // スマフォ系端末
      {
        id: false, last_update: false, title: true, author: false, sitename: false,
        toc_url: false, novel_type: false, tags: false, status: false, menu: true,
        download: true, folder: false, update_button: false, general_lastup: false,
        general_all_no: false, last_check_date: false, length: false, average_length: false,
        story: false,
      }
      // PC
    : {
        id: true, last_update: true, title: true, author: true, sitename: true,
        toc_url: true, novel_type: false, tags: true, status: true, menu: true,
        download: false, folder: true, update_button: true, general_lastup: true,
        general_all_no: false, last_check_date: false, length: false, average_length: false,
        story: false,
      });

  $.fn.dataTable.Api.register("fireChangeSelect()", function() {
    $(this.table().node()).trigger("changeselect");
  });

  $.fn.dataTable.Api.register("eachRow()", function(callback) {
    this.table().rows().eq(0).each(function(idx) {
      var row = table.row(idx);
      var data = row.data();
      callback(row, data);
    });
  });

  var ANNOTATION_COLOR_TIME_LIMIT = 6 * 60 * 60;   // 6時間(秒)
  var GENERAL_LASTUP_CLASSES = [
    [60 * 60, "gl-60minutes"],
    [6 * 60 * 60, "gl-6hour"],
    [24 * 60 * 60, "gl-24hour"],
    [3 * 24 * 60 * 60, "gl-3days"],
    [7 * 24 * 60 * 60, "gl-1week"],
    [-1, "gl-other"]
  ];

  function today() {
    return Narou.formatDate(new Date, "YYYYMMDD");
  }

  function isToday(date) {
    var dateobj = (typeof date === "number" ? new Date(date * 1000) : date);
    return Narou.formatDate(dateobj, "YYYYMMDD") === today();
  }

  // initComplete や ajax.reload した時に再設定するために呼ばれる
  function resettingTableState(skipDraw) {
    // refreshTooltop関数が定義されている場合のみ呼び出し
    if (typeof refreshTooltop === 'function') {
      try {
        refreshTooltop(table.$("[data-toggle=tooltip]"), null, "top");
      } catch (e) {
        console.warn("refreshTooltop error:", e);
      }
    } else {
      console.warn("refreshTooltop function not available");
    }
    
    // ページを跨いだ選択状態を復元
    if (typeof action !== 'undefined' && action && action.updateCurrentPageSelection) {
      action.updateCurrentPageSelection();
    }
    
    // バッジを更新しておく(.selectedの復元が終わってから呼ぶ)
    table.fireChangeSelect();

    // Ajax load callback内では追加のdrawを避ける
    if (!skipDraw) {
      table.draw(false);
    }
  }

  function openContextMenuWithTr(tr, event) {
    var $tr = $(tr);
    var target_id = table.row(tr).data().id;
    var $cover = $("<div class=context-menu-target-cover>");
    // MEMO: IEだと要素を追加してから座標を指定しないと反映されない
    $("body").append($cover);
    $cover.offset($tr.offset()).width($tr.width()).height($tr.height());
    $cover.one("contextmenu", function(e) {
      e.preventDefault();
      $cover.remove();
      context_menu.close();
    });
    context_menu.open(target_id, get_event_position(event), function() {
      $cover.remove();
    });
  }

  /*
   * 凍結の表示状態制御
   */
  var visibility_frozen_novel, visibility_nonfrozen_novel;

  $.fn.dataTable.ext.search.push(function(settings, data, dataIndex) {
    var state_frozen = table.row(dataIndex).data().frozen;
    if (state_frozen) {
      return visibility_frozen_novel;
    }
    else {
      return visibility_nonfrozen_novel;
    }
  });

  function restoreVisibilityForViewMenu() {
    visibility_frozen_novel = storage.get("visibility_frozen_novel");
    visibility_nonfrozen_novel = storage.get("visibility_nonfrozen_novel");
    var visibility_open_new_tab = storage.get("open_new_tab_setting_pages");
    var visibility_buttons_hide_page_top = !storage.get("buttons_hide_page_top");
    var visibility_buttons_fix_footer = storage.get("buttons_fix_footer");
    if (typeof visibility_frozen_novel === "undefined")
      visibility_frozen_novel = true;
    if (typeof visibility_nonfrozen_novel === "undefined")
      visibility_nonfrozen_novel = true;
    if (typeof visibility_open_new_tab === "undefined")
      visibility_open_new_tab = false;
    if (typeof visibility_buttons_hide_page_top === "undefined")
      visibility_buttons_hide_page_top = true;
    if (typeof visibility_buttons_fix_footer === "undefined")
      visibility_buttons_fix_footer = false;
    // メニューのチェック状態も復元
    var method = ["removeClass", "addClass"];
    $("#action-view-frozen")[method[visibility_frozen_novel | 0]]("active");
    $("#action-view-nonfrozen")[method[visibility_nonfrozen_novel | 0]]("active");
    $("#action-view-toggle-setting-page-open-new-tab")[method[visibility_open_new_tab | 0]]("active");
    $("#action-view-toggle-buttons-show-page-top")[method[visibility_buttons_hide_page_top | 0]]("active");
    $("#action-view-toggle-buttons-fix-footer")[method[visibility_buttons_fix_footer | 0]]("active");
  }

  restoreVisibilityForViewMenu();

  function saveVisibilityFrozen() {
    storage.set("visibility_frozen_novel", visibility_frozen_novel);
    storage.set("visibility_nonfrozen_novel", visibility_nonfrozen_novel);
    storage.save();
  }

  function toggleVisibilityFrozen() {
    visibility_frozen_novel = !visibility_frozen_novel;
  }

  function toggleVisibilityNonFrozen() {
    visibility_nonfrozen_novel = !visibility_nonfrozen_novel;
  }

  /*
   * 小説リスト設定
   */
  function createAjaxUrl() {
    var url = "/api/list?view_frozen=" + visibility_frozen_novel + "&view_nonfrozen=" + visibility_nonfrozen_novel;
    
    // フィルタ文字列（タグフィルタリング含む）を追加
    var filterString = "";
    if (typeof Narou !== 'undefined' && Narou.Location) {
      filterString = Narou.Location.getFilterString();
    }
    if (filterString) {
      url += "&filter=" + encodeURIComponent(filterString);
    }
    
    return url;
  }

  // データ量に応じて軽量モードを自動判定
  var detectLightweightMode = function() {
    var performanceMode = $("#performance-mode").val() || "auto";
    var totalNovels = parseInt($("#total-novels-count").val()) || 0;
    
    switch (performanceMode) {
      case "on":
        console.log("パフォーマンスモード: 常に有効");
        return true;
      case "off":
        console.log("パフォーマンスモード: 常に無効");
        return false;
      case "auto":
      default:
        // 2000件以上の場合は軽量モードを有効にする
        var autoMode = totalNovels >= 2000;
        console.log("パフォーマンスモード: 自動判定 (" + totalNovels + "件) -> " + (autoMode ? "有効" : "無効"));
        return autoMode;
    }
  };

  // 小説総数を取得してからテーブルを初期化
  var isLightweightMode = false;
  var table, t;
  var action;  // アクション管理インスタンス
  var isInitialLoad = true;  // 初回ロードフラグ

  function initializeDataTable(serverSortState) {
    var initialOrder = serverSortState ? [[serverSortState.column, serverSortState.dir]] : [[ 2, "desc" ]];
    
    table = t = $("#novel-list").DataTable({
    ajax: {
      url: createAjaxUrl(),
      type: "POST",  // POSTメソッドを使用
      data: function(d) {
        d.lightweight = isLightweightMode;
        
        // フィルタ文字列を追加
        if (typeof Narou !== 'undefined' && Narou.Location) {
          var filterString = Narou.Location.getFilterString();
          if (filterString) {
            d.filter = filterString;
          }
        }
        
        return d;
      },
      dataSrc: function(json) {
        // サーバーからの警告メッセージを処理
        if (json.warning) {
          // 既存の警告を更新
          $("#show-all-warning").removeClass("hide");
          $("#show-all-warning").html("<strong>注意:</strong> " + json.warning);
        }
        
        // AJAX完了後に選択状態を復元（少し遅延させて確実に復元）
        setTimeout(function() {
          if (typeof action !== 'undefined' && action && action.updateCurrentPageSelection) {
            console.log("[DEBUG] AJAX completed, refreshing selection display");
            action.updateCurrentPageSelection();
          }
        }, 150);
        
        return json.data;
      },
      error: function(xhr, error, code) {
        console.error("DataTables Ajax Error:", error, code);
        console.error("Response:", xhr.responseText);
        console.error("Status:", xhr.status);
        // エラー時は処理中表示を強制的に非表示
        $("#novel-list_processing").hide();
      }
    },
    serverSide: true,
    processing: false,
    dom: (touchable_device ? 'lprtpi' : 'Rlprtpi'),
    stateSave: true,
    stateDuration: 0,   // tableの状態保存を永続化
    stateLoadCallback: function(settings, callback) {
      try {
        var storageKey = 'DataTables_' + settings.sInstance + '_' + location.pathname;
        var state = JSON.parse(localStorage.getItem(storageKey)) || {};
        
        // サーバーからの初期ソート状態がある場合は、それを優先
        if (serverSortState && serverSortState.column !== undefined && serverSortState.dir) {
          console.log("[DEBUG] Applying server sort state:", serverSortState);
          state.order = [[serverSortState.column, serverSortState.dir]];
        }
        
        return state;
      } catch (e) {
        console.error("[ERROR] stateLoadCallback error:", e);
        return null;
      }
    },
    paginationType: "full_numbers",
    lengthMenu: [[20, 50, 100, 200, 500, -1], [20, 50, 100, 200, 500, "全"]],
    order: initialOrder,   // サーバーから取得したソート状態を使用
    pageLength: isLightweightMode ? 100 : 50, // 軽量モードでは初期ページサイズを大きく
    columns: [
      // ID
      {
        title: "ID",
        data: "id", className: "column-id text-center", visible: cell_visible.id,
        orderSequence: [ "desc", "asc" ],
        width: "20px"
      },
      // UPDATEした日時
      {
        title: "更新日",
        data: "last_update", className: "text-center",
        orderSequence: [ "desc", "asc" ], visible: cell_visible.last_update,
        width: "35px",
        render: function(data, type, row) {
          if (type === "display" || type === "filter") {
            var now = new Date;
            var date = new Date(data * 1000);
            var display = Narou.formatDate(date, "YYYY/MM/DD<br>hh:mm");
            if (type === "display") {
              var klass = null;
              if (row.new_arrivals_date) {
                if (row.new_arrivals_date >= data
                    && (row.new_arrivals_date + ANNOTATION_COLOR_TIME_LIMIT) * 1000 >= now) {
                  klass = "new-arrivals";
                }
              }
              if (!klass && (data + ANNOTATION_COLOR_TIME_LIMIT) * 1000 >= now) {
                klass = "new-update";
              }
              if (klass) {
                display = "<span class=" + klass + ">" + display + "</span>";
              }
            }
            return "<div>" + display + "</div>";
          }
          return data;
        }
      },
      // なろう：最終話掲載日、ハーメルン：最新投稿
      {
        title: "最新話<br>掲載日",
        data: "general_lastup", className: "text-center",
        orderSequence: [ "desc", "asc" ], visible: cell_visible.general_lastup,
        width: "35px",
        render: function(data, type, row) {
          if (type === "display" || type === "filter") {
            if (!data) return "";
            var now = new Date;
            var date = new Date(data * 1000);
            var diff_time = (now - date) / 1000;
            var display = Narou.formatDate(date, "YYYY/MM/DD<br>hh:mm");
            var klass = "";
            var outerClass = "";
            for (var i = 0;; i++) {
              var value = GENERAL_LASTUP_CLASSES[i];
              klass = value[1];
              if (value[0] === -1 || diff_time <= value[0]) break;
            }

            // 更新日より最新話掲載日が新しい場合、新着が来ていると分かる表示をする
            if (data > row.last_update) {
              outerClass = "hint-new-arrival";
            }

            return '<div class="' + outerClass + '"><span class="general-lastup ' + klass + '">' + display + '</span></div>';
          }
          else if (type === "sort") {
            return data * 10000 + (row.id | 0);
          }
          return data;
        }
      },
      // 更新を確認した日時（Update時やgeneral_lastupチェック時に更新）
      {
        title: "更新チェ<br>ック日",
        data: "last_check_date", className: "text-center",
        orderSequence: [ "desc", "asc" ], visible: cell_visible.last_check_date,
        width: "35px",
        render: function(data, type, row) {
          if (type === "display" || type === "filter") {
            if (!data)
              return "";
            var now = new Date;
            var date = new Date(data * 1000);
            var diff_time = (now - date) / 1000;
            var display = Narou.formatDate(date, "YYYY/MM/DD<br>hh:mm");
            return display;
          }
          else if (type === "sort") {
            return data * 10000 + (row.id | 0);
          }
          return data;
        }
      },
      // タイトル
      {
        title: "タイトル",
        data: "title", visible: cell_visible.title
      },
      // 作者名
      {
        title: "作者名",
        data: "author", visible: cell_visible.author,
        width: "100px",
        render: function(author, type, row) {
          if (author && type === "display") {
            return sprintf(
              '<span class="add-filter" data-add-filter="%(author)s">%(author)s</span>',
              { author: author }
            );
          }
          return author;
        }
      },
      // 掲載サイト
      {
        title: "掲載",
        data: "sitename", visible: cell_visible.sitename,
        width: "60px",
        render: function(sitename, type, row) {
          if (sitename && type === "display") {
            return sprintf(
              '<span class="add-filter" data-add-filter="%(sitename)s">%(sitename)s</span>',
              { sitename: sitename }
            );
          }
          return sitename;
        }
      },
      // 小説種別
      {
        title: "種別",
        data: "novel_type", className: "text-center", width: "25px",
        orderSequence: [ "desc", "asc" ], visible: cell_visible.novel_type
      },
      // タグ
      {
        title: "タグ",
        data: "tags", orderSequence: [ "desc", "asc" ], width: "80px",
        visible: cell_visible.tags
      },
      // 話数
      {
        title: "話数",
        data: "general_all_no", visible: cell_visible.general_all_no,
        className: "text-center", searchable: false, orderSequence: [ "desc", "asc" ],
        width: "15px",
        render: function(data, type, row) {
          data = data | 0;
          if (type === "display") {
            return data + "話";
          }
          return data;
        }
      },
      // 文字数
      {
        title: "文字数",
        data: "length", visible: cell_visible.length,
        className: "text-center", searchable: false, orderSequence: [ "desc", "asc" ],
        width: "15px",
        render: function(length, type, row) {
          if (length && type === "display") {
            return Narou.unitizeNumeric(length) + "字";
          }
          return length;
        }
      },
      // １話あたりの平均文字数
      {
        title: "平均<br>文字数",
        data: "average_length", visible: cell_visible.average_length,
        className: "text-center", searchable: false, orderSequence: [ "desc", "asc" ],
        width: "15px",
        render: function(_data, type, row) {
          var averageLength = row.length / row.general_all_no | 0;
          if (averageLength && type === "display") {
            return averageLength.toLocaleString();
          }
          return averageLength || null;
        }
      },
      // 状態
      {
        title: "状態",
        data: "status", visible: cell_visible.status,
        width: "30px"
      },
      // 掲載URL
      {
        title: "リンク",
        data: "toc_url", className: "text-center",
        visible: cell_visible.toc_url,
        width: "25px",
        render: function(data, type, row) {
          if (!data) return "";

          switch (type) {
          case "display":
            return sprintf(
                '<a href="%(url)s" class="btn btn-default btn-xs" target="_blank" rel="noreferrer" ' +
                'data-toggle="tooltip" data-placement="top" title="%(url)s">' +
                '<span class="glyphicon glyphicon-link"></span></a>',
                { url: data }
              );

          case "filter":
          case "sort":
            return data;
          }

          return data;
        }
      },
      // 書籍データDLリンク
      {
        title: "ＤＬ",
        data: "download", className: "text-center", orderable: false,
        searchable: false, visible: cell_visible.download,
        width: "25px"
      },
      {
        title: "保存先",
        data: "folder", className: "text-center", orderable: false,
        searchable: false, visible: cell_visible.folder,
        width: "25px",
        defaultContent: '<button class="btn btn-default btn-xs">' +
                        '<span class="glyphicon glyphicon-folder-open"></span></button>',
        createdCell: function(td, cellData, rowData, rowIndex, colIndex) {
          $(td).children("button")
            .data("targetId", rowData.id)
            .on("click", function(e) {
              e.stopPropagation();
              var $this = $(this);
              var target_id = $this.data("targetId");
              action.folder(target_id);
            });
        },
        render: function() {}
      },
      {
        title: "更新",
        data: "update_button", className: "text-center", orderable: false,
        searchable: false, visible: cell_visible.update_button,
        defaultContent: '<button class="btn btn-default btn-xs">' +
                        '<span class="glyphicon glyphicon-refresh"></span></button>',
        width: "25px",
        createdCell: function(td, cellData, rowData, rowIndex, colIndex) {
          $(td).children("button")
            .data("targetId", rowData.id)
            .on("click", function(e) {
              e.stopPropagation();
              var $this = $(this);
              var target_id = $this.data("targetId");
              action.updateForce(target_id);
            });
        },
        render: function() {}
      },
      // あらすじ
      {
        title: "あらすじ",
        data: "story", visible: cell_visible.story, className: "text-center",
        searchable: false, orderable: false,
        width: "25px",
        render: function () {},
        defaultContent: '<button class="btn btn-default btn-xs n-popover">' +
                        '<span class="glyphicon glyphicon-info-sign"></span></button>',
        createdCell: function(td, cellData, rowData, rowIndex, colIndex) {
          var popoverToggled = false;
          var beforeTargetId = null;
          $(td).children("button")
            .data("targetId", rowData.id)
            .one("click", function(e) {
              var $this = $(this);
              var targetId = $this.data("targetId");
              action.displayStory($this, targetId);
            })
        },
      },
      {
        title: "個別",
        data: "menu", className: "text-center",
        defaultContent: '<button class="btn btn-default btn-xs">' +
                        '<span class="glyphicon glyphicon-option-horizontal"></span></button>',
        visible: cell_visible.menu,
        width: "25px",
        createdCell: function(td, cellData, rowData, rowIndex, colIndex) {
          $(td).children("button")
            .data("targetId", rowData.id)
            .on("click", function(e) {
              e.stopPropagation();
              openContextMenuWithTr($(e.target).closest("tr"), e);
            });
        },
        render: function() {},
        searchable: false, orderable: false,
      },
      // 凍結状態（内部データ用）
      {
        title: "凍結", data: "frozen", visible: false, system_column: true,
        searchable: false,
      },
      // 新着時間（内部データ用）
      {
        title: "新着時間", data: "new_arrivals_date", visible: false, system_column: true,
        searchable: false
      },
    ].map(function(hash) {
      // 検索用に name 要素を追加
      hash.name = hash.data;
      // table-cell 内で position: abosolute を使うために div をかます
      // 参考： http://no1026.com/archives/406
      if (!hash.render) {
        hash.render = function(data, type, row) {
          if (type === "display" || type === "filter") {
            return "<div>" + data + "</div>";
          }
          return data;
        }
      }
      return hash;
    }),
    createdRow: function(row, data, data_index) {
      if (data.frozen) {
        $(row).addClass("frozen");
      }
    },
    initComplete: function(_settings, _json) {
      // 範囲選択モードでもリンクとボタンが使えるように
      table.on("mousedown", "a, button", function(e) {
        e.stopPropagation();
      });
      // リンククリックした時点でツールチップは消す
      table.on("click", "a", function(e) {
        $(this).tooltip("hide");
      });
      
      // ページサイズ変更の監視
      table.on('length.dt', function(e, settings, len) {
        if (len === -1) {
          // "Show All" が選択された場合
          $("#show-all-warning").removeClass("hide");
          console.log("Show All mode activated - may impact performance");
          
          // 大量データの場合は軽量モードを強制的に有効にする
          if (isLightweightMode) {
            // Ajax URLに軽量モードパラメータを追加
            var currentUrl = table.ajax.url();
            if (currentUrl.indexOf('lightweight=true') === -1) {
              var separator = currentUrl.indexOf('?') !== -1 ? '&' : '?';
              table.ajax.url(currentUrl + separator + 'lightweight=true');
            }
          }
        } else {
          $("#show-all-warning").addClass("hide");
        }
      });
      
      resettingTableState();

      // searchオブジェクトが定義されてからsearchSyncを呼び出す
      setTimeout(function() {
        // 正しいフィルタ文字列を取得（URLハッシュまたはローカルストレージ）
        var correct_filter_string = Narou.Location.getFilterString() || '';
        var current_input_value = $("#myFilter").val() || '';
        
        // 入力フィールドの値が正しいフィルタ文字列と異なる場合は修正
        if (current_input_value !== correct_filter_string) {
          $("#myFilter").val(correct_filter_string);
        }
        
        if (typeof search !== 'undefined' && search.searchSync) {
          search.searchSync();
        }
        // 処理完了時にprocessing indicatorを確実に非表示
        $("#novel-list_processing").hide();
      }, 100);

      // テーブル初期化完了後にactionを作成
      action = new Narou.Action(table);

      // ソート変更時に選択状態を復元
      table.on('order.dt', function() {
        console.log("[DEBUG] Sort order changed, refreshing selection display");
        setTimeout(function() {
          if (action && action.updateCurrentPageSelection) {
            action.updateCurrentPageSelection();
          }
        }, 100);
      });

      // 描画完了後に選択状態を復元
      table.on('draw.dt', function() {
        console.log("[DEBUG] Table redrawn, refreshing selection display");
        setTimeout(function() {
          if (action && action.updateCurrentPageSelection) {
            action.updateCurrentPageSelection();
          }
        }, 50);
      });

      datatables_init_completed = true;
      
      // 他のコンポーネントを初期化
      initializeComponents();
    },
    language: {
      //lengthMenu: "_MENU_ 件分表示　<span id='icon-refresh-table' class='glyphicon glyphicon-repeat'></span>",
      lengthMenu: "_MENU_ 件分表示",
      emptyTable: "データが登録されていません",
      zeroRecords: "ひとつも見つかりませんでした",
      infoPostFix: "",
      info: "Page _PAGE_ of _PAGES_",
      infoEmpty: "該当なし",
      infoFiltered: "(全_MAX_件から検索しました)",
      loadingRecords: "ロード中です",
      processing: "処理中...",
      paginate: {
        first: "&laquo;",
        previous: "前へ",
        next: "次へ",
        last: "&raquo;"
      },
    },
    /*
     * Extensions section
     */
    colReorder: {
      realtime: false,

      // colReorder でカラムの順番が入れ替えられた場合、createdCell 内で
      // 設定している内容が全てリセットされてしまいイベント等が消えてしまうので、
      // ここで一旦リロードしてイベントが再設定されるようにする。
      // これは createdCell が初期化時に一度しか呼ばれないためで、dataTables の
      // 今後のバージョンアップで予定されている updatedCell が実装されるまでの
      // 暫定処置として reorderCallback で代用する。
      // https://github.com/DataTables/ColReorder/issues/49
      reorderCallback: function() {
        // stateSave が有効な状態でカラムが入れ替えられていた場合、
        // initComplete イベントが発火する前に一度この reorderCallback が発火されるので、
        // 無駄なリロードをしないように初期化後のみ有効にする
        if (datatables_init_completed) {
          Narou.tableReload();
        }
      },
    },
    });
  }

  // 小説総数を取得してからテーブルを初期化
  $.get("/api/novels/count", function(data) {
    $("#total-novels-count").val(data.count);
    isLightweightMode = detectLightweightMode();
    
    if (isLightweightMode) {
      $("#performance-info").removeClass("hide");
      console.log("Performance mode enabled for", data.count, "novels");
    }
    
    // サーバーからソート状態を取得してDataTablesを初期化
    $.get("/api/sort_state").done(function(sortState) {
      console.log("Loading sort state from server:", sortState);
      initializeDataTable(sortState);
    }).fail(function() {
      console.warn("Failed to get sort state from server, using default");
      initializeDataTable();
    });
  }).fail(function() {
    // エラーの場合は通常モードで初期化
    console.warn("Failed to get novel count, using normal mode");
    isLightweightMode = false;
    
    // サーバーからソート状態を取得してDataTablesを初期化
    $.get("/api/sort_state").done(function(sortState) {
      console.log("Loading sort state from server:", sortState);
      initializeDataTable(sortState);
    }).fail(function() {
      console.warn("Failed to get sort state from server, using default");
      initializeDataTable();
    });
  });

  function initializeComponents() {
    // actionは既にinitCompleteで初期化済み
    var menuAction = new Narou.MenuAction();
    var notification = Narou.Notification.instance();
    
    // テーブルリロード機能を設定
    setupTableReload(notification);
    
    var consoleStdout2 = null;
    if (Narou.concurrencyIsEnabled()) {
      consoleStdout2 = new Narou.Console({
        id: "#console-stdout2",
        restore: false,
        buttons: false,
        buttons_id: "#console-convert-buttons",
        stream_id: "stdout2"
      });
    }
    new Narou.Console({ sync_shape_console: consoleStdout2 });
    var search = Narou.Search.get(table);
    var tag = new Narou.Tag(table);
    var context_menu = new Narou.ContextMenu(action, tag);
    var select_color_menu = new Narou.SelectColorMenu;

    /*
     * フィルターの文字列を復元
     */
    var filter_string = Narou.Location.getFilterString();
    if (filter_string) {
      $("#myFilter").val(filter_string);
    }
    
    // サーバーサイド処理用のハッシュ変更対応（クライアントサイド版は無効化）
    $(window).on('hashchange', function(e) {
      // フィルタフィールドも更新
      var filterString = Narou.Location.getFilterString();
      $("#myFilter").val(filterString || '');
      
      // DataTablesのURLを更新してリロード（処理中表示なし）
      var newUrl = createAjaxUrl();
      
      // テーブルが存在するかチェック
      if (!table) {
        return;
      }
      
      // フィルタリング時は処理中表示を無効化
      table.ajax.url(newUrl).load(null, false);
    });
    
    // フィルタ入力のリアルタイム反映
    $("#myFilter").on('input keyup', function() {
      var filterValue = $(this).val();
      Narou.Location.replaceHash(filterValue);
      // ローカルストレージも更新
      if (filterValue.trim()) {
        storage.set("filter_string", filterValue).save();
      } else {
        storage.remove("filter_string").save();
      }
      // フィルタ入力時は処理中表示を無効化
      table.ajax.url(createAjaxUrl()).load(null, false);
    });
    
    // クリアボタンの動作
    $("#myFilter-clear").on('click', function() {
      $("#myFilter").val('');
      Narou.Location.replaceHash('');
      // ローカルストレージもクリア
      storage.remove("filter_string").save();
      // フィルタクリア時は処理中表示を無効化
      table.ajax.url(createAjaxUrl()).load(null, false);
    });

    // タグクリック処理（キャプチャフェーズで最優先処理）
    // 修飾キーによる検索モード：
    // 何もなし: AND検索, Shift: -AND検索, Ctrl: OR検索, Shift+Ctrl: -OR検索
    
    // キャプチャフェーズでタグクリックを最優先処理
    document.addEventListener('click', function(e) {
      // タグ要素のクリックかチェック
      var tagElement = $(e.target).closest('.tag[data-tag]:not(.tag-reset)')[0];
      if (!tagElement) return; // タグクリックでなければ通常処理続行
      
      // タグクリックの場合は最優先で処理
      e.preventDefault();
      e.stopPropagation();
      e.stopImmediatePropagation();
      
      var $tag = $(tagElement);
      var tagName = $tag.attr('data-tag');
      
      if (tagName && tagName.trim()) {
        var currentFilter = $("#myFilter").val().trim();
        var newTagFilter = '';
        var finalFilter = '';
        
        // 修飾キーを確認して適切な検索構文を構築
        if (e.ctrlKey && e.shiftKey) {
          // Shift + Ctrl: - OR検索
          newTagFilter = '-tag:' + tagName;
          finalFilter = buildTagFilter(currentFilter, newTagFilter, 'or');
        } else if (e.ctrlKey) {
          // Ctrl: OR検索
          newTagFilter = 'tag:' + tagName;
          finalFilter = buildTagFilter(currentFilter, newTagFilter, 'or');
        } else if (e.shiftKey) {
          // Shift: - AND検索 (既存フィルタに追加)
          newTagFilter = '-tag:' + tagName;
          finalFilter = buildTagFilter(currentFilter, newTagFilter, 'and');
        } else {
          // 何もなし: AND検索 (既存フィルタに追加)
          newTagFilter = 'tag:' + tagName;
          finalFilter = buildTagFilter(currentFilter, newTagFilter, 'and');
        }
        
        $("#myFilter").val(finalFilter);
        Narou.Location.setHashWithEvent(finalFilter);
        storage.set("filter_string", finalFilter).save();
      }
      
      return false;
    }, true); // キャプチャフェーズで実行
    
    // タグ検索フィルタ構築ヘルパー関数 (AND/OR対応)
    function buildTagFilter(currentFilter, newTagFilter, mode) {
      if (!currentFilter) {
        return newTagFilter;
      }
      
      if (mode === 'or') {
        // OR検索: パイプ構文でOR検索を構築
        var newExclude = newTagFilter.startsWith('-') ? '-' : '';
        var newTag = newTagFilter.replace(/^-?tag:/, '');
        
        // 同じ除外フラグのタグ検索を後ろから探す
        var parts = currentFilter.split(/\s+/);
        for (var i = parts.length - 1; i >= 0; i--) {
          if (parts[i].match(/^([-^]?)tag:/)) {
            var partExclude = parts[i].match(/^([-^]?)tag:/)[1];
            
            // 同じ除外フラグの場合、パイプで繋げる
            if (partExclude === newExclude) {
              var partContent = parts[i].replace(/^[-^]?tag:/, '');
              parts[i] = (partExclude || '') + 'tag:' + partContent + '|' + newTag;
              return parts.join(' ');
            }
          }
        }
      }
      
      // AND検索 または OR検索で除外フラグが異なる場合: スペース区切りで追加
      return currentFilter + ' ' + newTagFilter;
    }

    // タグリセットボタンクリック時
    $(document).on('click', '.tag-reset', function(e) {
      e.preventDefault();
      e.stopPropagation();
      
      $("#myFilter").val('');
      Narou.Location.setHashWithEvent('');
      storage.remove("filter_string").save();
    });

    // 除外タグクリック時のフィルタリング
    $(document).on('click', '.tag[data-exclusion-tag]', function(e) {
      e.preventDefault();
      e.stopPropagation();
      
      var tagName = $(this).attr('data-exclusion-tag');
      if (tagName && tagName.trim()) {
        var filterString = '-tag:' + tagName;
        $("#myFilter").val(filterString);
        Narou.Location.setHashWithEvent(filterString);
        storage.set("filter_string", filterString).save();
      }
    });

    // 作者名クリック時のフィルタリング（イベントデリゲーション）
    $(document).on('click', 'td:contains("作者名") a, .author-link, [data-author]', function(e) {
      var authorName = $(this).text() || $(this).attr('data-author');
      if (authorName && authorName.trim()) {
        e.preventDefault();
        e.stopPropagation();
        
        $("#myFilter").val(authorName);
        Narou.Location.setHashWithEvent(authorName);
        storage.set("filter_string", authorName).save();
      }
    });

    // サイト名クリック時のフィルタリング（イベントデリゲーション）
    $(document).on('click', 'td:contains("サイト名") a, .sitename-link, [data-sitename]', function(e) {
      var siteName = $(this).text() || $(this).attr('data-sitename');
      if (siteName && siteName.trim()) {
        e.preventDefault();
        e.stopPropagation();
        
        $("#myFilter").val(siteName);
        Narou.Location.setHashWithEvent(siteName);
        storage.set("filter_string", siteName).save();
      }
    });

  // テーブルリロードイベント定義はinitializeComponents内で設定済み
  function setupTableReload(notification) {
    notification.on("table.reload", function() {
      console.log("table.reloadイベントを受信しました");
      if (!table) {
        console.warn("テーブルが初期化されていないため、リロードをスキップします");
        return;
      }
      
      console.log("テーブルの自動リロードを開始します");
      
      // サーバーサイド処理の場合は選択状態の復元方法を変更
      var selected_ids = [];
      if (table.rows && table.rows('.selected').data) {
        table.rows('.selected').data().each(function(data) {
          selected_ids.push(data.id);
        });
        console.log("選択状態を保存しました:", selected_ids);
      }
      
      // URLを更新してからリロード（自動リロード時は処理中表示なし）
      table.ajax.url(createAjaxUrl()).load(function() {
        console.log("テーブルデータの取得が完了しました");
        // サーバーサイド処理では現在のページのデータのみ復元
        setTimeout(function() {
          table.rows().every(function() {
            var data = this.data();
            if (data && $.inArray(data.id, selected_ids) !== -1) {
              $(this.node()).addClass("selected");
            }
          });
          resettingTableState(true); // Ajax load callback内なのでdrawをスキップ
          console.log("テーブルの自動リロードが完了しました");
        }, 100);
      }, false);
    });
    
    // 強制リロードイベント
    notification.on("table.force_reload", function() {
      console.log("table.force_reloadイベントを受信しました");
      if (!table) {
        console.warn("テーブルが初期化されていないため、強制リロードをスキップします");
        return;
      }
      
      console.log("テーブルの強制リロードを開始します（キャッシュクリア付き）");
      
      // DataTablesの状態をクリア
      if (table.state && table.state.clear) {
        table.state.clear();
      }
      
      // サーバーサイド処理の場合は選択状態の復元方法を変更
      var selected_ids = [];
      if (table.rows && table.rows('.selected').data) {
        table.rows('.selected').data().each(function(data) {
          selected_ids.push(data.id);
        });
        console.log("選択状態を保存しました:", selected_ids);
      }
      
      // キャッシュバスターを追加してURLを更新
      var originalUrl = createAjaxUrl();
      var cacheBusterUrl = originalUrl + (originalUrl.indexOf('?') !== -1 ? '&' : '?') + '_cb=' + Date.now();
      console.log("キャッシュバスター付きURL:", cacheBusterUrl);
      
      // URLを更新してからリロード（強制リロード時のみ処理中表示あり）
      table.ajax.url(cacheBusterUrl).load(function() {
        console.log("強制テーブルデータの取得が完了しました");
        // サーバーサイド処理では現在のページのデータのみ復元
        setTimeout(function() {
          table.rows().every(function() {
            var data = this.data();
            if (data && $.inArray(data.id, selected_ids) !== -1) {
              $(this.node()).addClass("selected");
            }
          });
          resettingTableState(true); // Ajax load callback内なのでdrawをスキップ
          console.log("テーブルの強制リロードが完了しました");
        }, 100);
      }, true);
    });
  }

  /*
   * サーバ再起動イベント定義
   */
  notification.on("server.rebooted", function() {
    location.href = "/";
  });

  notification.on("tag.updateCanvas", function() {
    console.log("tag.updateCanvasイベントを受信しました");
    tag.updateCanvas();
    
    // タグキャンバス更新後にテーブルも確実にリロードする
    console.log("タグ更新に伴うテーブルリロードを実行します");
    Narou.tableReload();
    
    // 追加のフォールバック処理：WebSocketイベントが順序通りに来なかった場合
    setTimeout(function() {
      console.log("tag.updateCanvas追加フォールバック: さらにテーブルリロードを実行");
      Narou.tableReload();
    }, 1000);
  });

  /*
   * イジェクトボタンの show / hide イベント
   */
  notification.on("device.ejectable", function(ejectable) {
    if (ejectable)
      $(".eject-group").removeClass("hide");
    else
      $(".eject-group").addClass("hide");
  });

  /*
   * 小説リストの幅を変更
   */
  if (storage.get("novel_list_is_wide")) {
    menuAction.toggleNovelListWide();
  }

  /*************************************************************
   * 小説の選択関係
   *************************************************************/

  // 指定地点に対象要素があるかどうか背面の要素までさかのぼって探す
  $.searchElementFromPoint = function(pos, target) {
    var doc = $(document);
    var html_dom = $("html")[0];
    var display_x = pos.x - doc.scrollLeft();
    var display_y = pos.y - doc.scrollTop();
    var get_element_from_pos = function(x, y, t) {
      var elm = document.elementFromPoint(x, y);
      if (!elm || elm === html_dom) return null;
      var elm_jq = $(elm);
      if (!elm_jq.is(t)) {
        elm_jq.hide();
        elm = get_element_from_pos(x, y, t);
        elm_jq.show();
      }
      return elm;
    };
    var element = get_element_from_pos(display_x, display_y, target);
    return element ? $(element) : null;
  };

  $.elementFromPoint = function(pos) {
    var doc = $(document);
    var rect = $("#rect-select-area");
    var rect_visibility = rect.is(":visible");
    if (rect_visibility) rect.hide();
    var elm = document.elementFromPoint(pos.x - doc.scrollLeft(),
                                        pos.y - doc.scrollTop());
    if (rect_visibility) rect.show();
    return elm ? $(elm) : null;
  };

  function get_event_position(e) {
    return Narou.get_event_position(e);
  }

  var select_mode = storage.get("select_mode") || "hybrid";
  var enable_rect_select_mode = function() {};
  var disable_rect_select_mode = function() {};

  $("#action-select-mode-single").on(click_event_name, function(e) {
    if (select_mode != "single") {
      $(this).addClass("active");
      $("#action-select-mode-" + select_mode).removeClass("active");
      select_mode = "single";
      storage.set("select_mode", select_mode).save();
      disable_rect_select_mode();
      enable_single_select_mode();
    }
    slideNavbar.close();
    e.preventDefault();
  });

  function disable_single_select_mode() {
    table.off("click", "tr")
    table.off("click", "a")
    $("#novel-list tbody").css("cursor", "auto");
  }

  function enable_single_select_mode() {
    var dont_select = false;
    // ここだけはスマフォ系でも touchstart ではなく click で。
    // touchstart だと画面スクロールのためのスワイプでも反応してしまう
    table
      .on("click", "tr", function () {
        $(this).toggleClass("selected");
        table.fireChangeSelect();
      })
      .on("click", "a", function(e) {
        // リンクをクリックした時は選択処理は行わない
        e.stopPropagation();
      })
    $("#novel-list tbody").css("cursor", "pointer");
  }

  if (touchable_device) {
    // スマフォ系は範囲選択モードは封印しておく
    $("#action-select-mode-rect").addClass("disabled");
  }
  else {
    // 小説一覧テーブル内で右クリックしたら個別メニューを表示
    $("#novel-list tbody").on("contextmenu", function(e) {
      var target_tag_name = e.target.tagName.toLowerCase();
      // ボタンとかリンクはブラウザの右クリックメニューをそのまま使いたい
      if (target_tag_name === "button" || target_tag_name === "a" ||
          $(e.target).parent("button, a")[0])
        return;

      e.preventDefault();   // ブラウザの右クリックメニューを抑制
      e.stopPropagation();
      var mousedowned_element = $.elementFromPoint(get_event_position(e));
      var tr = mousedowned_element.parents("tr");
      openContextMenuWithTr(tr, e);
    });

    var initMode = function(mode) {
      if (select_mode != mode) {
        $("#action-select-mode-" + mode).addClass("active");
        $("#action-select-mode-" + select_mode).removeClass("active");
        if (select_mode == "single") {
          disable_single_select_mode();
          enable_rect_select_mode();
        }
        select_mode = mode;
        storage.set("select_mode", mode).save();
        $("#novel-list tbody, #rect-select-area")
          .css("cursor", mode == "rect" ? "crosshair" : "pointer");
      }
    };
    $("#action-select-mode-rect").on(click_event_name, function(e) {
      initMode("rect");
      slideNavbar.close();
      e.preventDefault();
    });
    $("#action-select-mode-hybrid").on(click_event_name, function(e) {
      initMode("hybrid");
      slideNavbar.close();
      e.preventDefault();
    });

    var selected_rect_element = $("<div id=rect-select-area>").hide();
    $("body").append(selected_rect_element);

    disable_rect_select_mode = function() {
      $("body").off("mousedown mousemove mouseup");
      $("#novel-list tbody, #rect-select-area").css("cursor", "auto");
      close_rect_select_menu_handler();
    };

    var close_rect_select_menu_handler = function() {
      $("#rect-select-menu").hide();
      selected_rect_element.hide();
    };

    var unregister_close_handler = function() {
      $(document).off("click", close_rect_select_menu_handler);
    };

    var start_element, end_element;

    var get_rows_rect_selected = function() {
      var target = "td";
      var start = start_element;
      var end = end_element;
      var rows = [];
      if (!start || !end) {
        return rows;
      }
      var from, to;
      if (start.offset().top < end.offset().top) {
        from = start.parents("tr");
        to = end.parents("tr");
      }
      else {
        from = end.parents("tr");
        to = start.parents("tr");
      }
      var current = from;
      while (current.length !== 0) {
        rows.push(current);
        if (current[0] === to[0]) break;
        current = current.next();
      }
      return rows;
    };

    // 範囲選択後に表示される選択肢
    var rect_select_menu_initialize = function() {
      var menu = $("#rect-select-menu");
      // 選択
      $("#rect-select-menu-select").on("click", function(e) {
        e.preventDefault();
        var rows = get_rows_rect_selected();
        $.each(rows, function(_i, row) {
          row.addClass("selected");
        });
        table.fireChangeSelect();
        menu.hide();
        selected_rect_element.hide();
        $(this).children("a").blur();
      });
      // 解除
      $("#rect-select-menu-clear").on("click", function(e) {
        e.preventDefault();
        var rows = get_rows_rect_selected();
        $.each(rows, function(_i, row) {
          row.removeClass("selected");
        });
        table.fireChangeSelect();
        menu.hide();
        selected_rect_element.hide();
        $(this).children("a").blur();
      });
      // 反転
      $("#rect-select-menu-reverse").on("click", function(e) {
        e.preventDefault();
        var rows = get_rows_rect_selected();
        $.each(rows, function(_i, row) {
          row.toggleClass("selected");
        });
        table.fireChangeSelect();
        menu.hide();
        selected_rect_element.hide();
        $(this).children("a").blur();
      });
      // キャンセル
      $("#rect-select-menu-cancel").on("click", function(e) {
        e.preventDefault();
        e.stopPropagation();
        menu.hide();
        selected_rect_element.hide();
        $(this).children("a").blur();
      });
    };
    rect_select_menu_initialize();

    enable_rect_select_mode = function() {
      var not_clicked_yet = true;
      var is_moved = false;
      var start_position = null;
      var end_position = null;
      var resetCursor = function() {
        $("#novel-list tbody, #rect-select-area")
          .css("cursor", select_mode == "rect" ? "crosshair" : "pointer");
      };
      resetCursor();
      $("body").on("mousedown", function(e) {
        var _pos = get_event_position(e);
        var mousedowned_element = $.elementFromPoint(_pos);
        if (!mousedowned_element || mousedowned_element.closest("#novel-list tbody").length === 0)
          return;

        // 右クリックは無視（contextmenu イベント内で個別メニューを表示する）
        if (e.which == 3)
          return;

        e.preventDefault();
        e.stopPropagation();
        var self = this;
        var moving_count = 0;
        var finish_selecting_proc = function() {
          $(self).off("mousemove mouseup");
          not_clicked_yet = true;
          is_moved = false;
          Narou.popupMenu("#rect-select-menu", end_position, close_rect_select_menu_handler);
          resetCursor();
        };
        var mouse_up_when_mode_hybrid_proc = function() {
          mousedowned_element.parents("tr").toggleClass("selected");
          $(self).off("mousemove mouseup");
          not_clicked_yet = true;
          is_moved = false;
          table.fireChangeSelect();
          $("#rect-select-menu").hide();
          selected_rect_element.hide();
          $(".n-popover").blur();
        };
        if (not_clicked_yet) {
          // 範囲選択開始
          $("#rect-select-menu").hide();
          context_menu.close();
          unregister_close_handler();
          not_clicked_yet = false;
          start_position = _pos;
          start_element = mousedowned_element;
          $(self).on("mousemove", function(e) {
            moving_count++;
            if (select_mode == "hybrid" && moving_count < 10) {
              // 範囲選択化への遊び。多少動かした程度はクリックとみなす
              return;
            }
            is_moved = true;
            selected_rect_element.show();
            $("#novel-list tbody, #rect-select-area").css("cursor", "crosshair");
            var pos = get_event_position(e);
            if ($.elementFromPoint(pos).closest("#novel-list tbody").length === 0)
              return;
            end_position = pos;
            end_element = $.searchElementFromPoint(end_position, "td");
            var rect = {};
            rect.x = (pos.x < start_position.x ? pos.x : start_position.x);
            rect.y = (pos.y < start_position.y ? pos.y : start_position.y);
            rect.w = Math.abs(pos.x - start_position.x);
            rect.h = Math.abs(pos.y - start_position.y);
            selected_rect_element.css({
              left: rect.x, top: rect.y,
              width: rect.w, height: rect.h
            });
          });
          // ボタンを離さないでそのまま移動させた場合は、ドラッグによる範囲選択とみなす
          $(self).on("mouseup", function(e) {
            if (is_moved) {
              finish_selecting_proc();
            }
            else if (select_mode == "hybrid") {
              mouse_up_when_mode_hybrid_proc();
            }
          });
          selected_rect_element.css({
            left: start_position.x,
            top: start_position.y,
            width: 1, height: 1
          });
        }
        else {
          finish_selecting_proc();
        }
      });
    }
  }

  function restore_select_mode() {
    if (select_mode === "single")
      enable_single_select_mode();
    else
      enable_rect_select_mode();
    $("#action-select-mode-" + select_mode).addClass("active");
  }
  restore_select_mode();

  /*
   * メニュー
   *   表示＞全ての項目を表示
   */
  $("#action-view-all").on(click_event_name, function(e) {
    e.preventDefault();
    slideNavbar.slide();
    bootbox.confirm("全ての項目を表示します。よろしいですか？", function(result) {
      if (!result) return;
      var aoColumns = table.settings()[0].aoColumns;
      table.columns().eq(0).each(function(index) {
        if (!aoColumns[index].system_column) {
          table.column(index).visible(true);
        }
      });
      table.draw(false);
    });
  });

  /*
   * メニュー
   *   表示＞表示する項目を設定
   */
  var colvis = new $.fn.dataTable.ColVis(table, {
    restore: "元に戻す",
    showAll: "全ての項目を表示",
    showNone: "全て隠す",
    bCssPosition: true,
    overlayFade: 300,
    exclude: [ "title", "frozen", "new_arrivals_date" ],
  });
  $("#action-view-setting").on(click_event_name, function(e) {
    e.preventDefault();
    var pos = {};
    if (touchable_device) {
      var target = $(this);
      pos.x = target.offset().left;
      pos.y = target.offset().top + target.outerHeight();
    }
    else {
      pos = get_event_position(e);
    }
    $(colvis.dom.collection).css({
      position: "absolute",
      left: pos.x, top: pos.y
    });
    slideNavbar.slide();
    colvis._fnCollectionShow();
  });

  /*
   * メニュー
   *   表示＞小説リストの幅を広げる
   */
  $("#action-view-novel-list-wide").on(click_event_name, function(e) {
    e.preventDefault();
    slideNavbar.slide();
    menuAction.novelListToWiden();
  });

  /*
   * メニュー
   *   表示＞凍結中以外を表示
   */
  $("#action-view-nonfrozen").on(click_event_name, function(e) {
    e.preventDefault();
    slideNavbar.slide();
    $(this).toggleClass("active");
    toggleVisibilityNonFrozen();
    saveVisibilityFrozen();
    Narou.tableReload();
  });

  /*
   * メニュー
   *   表示＞凍結中を表示
   */
  $("#action-view-frozen").on(click_event_name, function(e) {
    e.preventDefault();
    slideNavbar.slide();
    $(this).toggleClass("active");
    toggleVisibilityFrozen();
    saveVisibilityFrozen();
    Narou.tableReload();
  });

  /*
   * メニュー
   *   表示＞変換設定ページは新規タブで開く
   */
  $("#action-view-toggle-setting-page-open-new-tab").on(click_event_name, function(e) {
    e.preventDefault();
    slideNavbar.slide();
    $(this).toggleClass("active");
    var open_new_tab = storage.get("open_new_tab_setting_pages");
    storage.set("open_new_tab_setting_pages", !open_new_tab);
    storage.save();
  });

  /*
   * メニュー
   *   表示＞ボタンをページ上部に表示
   */
  $("#action-view-toggle-buttons-show-page-top").on(click_event_name, function(e) {
    e.preventDefault();
    slideNavbar.slide();
    $(this).toggleClass("active");
    var is_hide_buttons_page_top = !storage.get("buttons_hide_page_top");
    storage.set("buttons_hide_page_top", is_hide_buttons_page_top);
    storage.save();
    if (is_hide_buttons_page_top)
      $("#control-panel").addClass("hide");
    else
      $("#control-panel").removeClass("hide");
  });

  /*
   * メニュー
   *   表示＞ボタンを画面下部に表示
   */
  $("#action-view-toggle-buttons-fix-footer").on(click_event_name, function(e) {
    e.preventDefault();
    slideNavbar.slide();
    $(this).toggleClass("active");
    var is_fixed_buttons = !storage.get("buttons_fix_footer");
    storage.set("buttons_fix_footer", is_fixed_buttons);
    storage.save();
    if (is_fixed_buttons)
      $("#footer-navbar").removeClass("hide");
    else
      $("#footer-navbar").addClass("hide");
  });

  /*
   * メニュー
   *   表示＞個別メニューの表示スタイルを選択
   */
  var _menuStyleRenderer = _.template(
    (function () {/*
<div class="radio"><label>
<input type="radio" value="windows" name="select-menu-style" <% if (style == "windows") { %>checked<% } %>>
Windows スタイル：<br>メニューが画面外にはみ出そうとしたら、カーソルの上側に表示する
</label></div>
<div class="radio"><label>
<input type="radio" value="mac" name="select-menu-style" <% if (style == "mac") { %>checked<% } %>>
Mac スタイル：<br>メニューが画面外にはみ出そうとしたら、メニューがはみ出ないよう上にずれる
</label></div>
    */}).toString().replace(/(\n)/g, '').split('*')[1]
  );

  $("#action-view-select-menu-style").on(click_event_name, function(e) {
    e.preventDefault();
    slideNavbar.slide();
    var menuStyle = storage.get("menu_style") || "windows";
    var box = bootbox.alert({
      title: "個別メニューの表示スタイルを選択",
      message: _menuStyleRenderer({ style: menuStyle }),
      callback: function() {
        menuStyle = box.find("input:checked").val();
        storage.set("menu_style", menuStyle);
        storage.save();
        Narou.popupMenuStyle = menuStyle;
      }
    });
  });

  /*
   * メニュー
   *   表示＞表示設定を全てリセット
   */
  $("#action-view-reset").on(click_event_name, function(e) {
    e.preventDefault();
    slideNavbar.slide();
    bootbox.confirm("表示に関わる全ての設定がリセットされます。よろしいですか？", function(result) {
      if (!result) return;
      // localStorageを全て消してリロードする
      localStorage.clear();
      location.href = "/";
    });
  });

  /*
   * メニュー
   *   選択＞全ての小説を選択
   */
  $("#action-select-all").on(click_event_name, function(e) {
    e.preventDefault();
    slideNavbar.slide();
    action.selectAll();
  });

  /*
   * メニュー
   *   選択＞表示されている小説を選択
   */
  $("#action-select-view").on(click_event_name, function(e) {
    e.preventDefault();
    slideNavbar.slide();
    action.selectView();
  });

  /*
   * メニュー
   *   選択＞選択を全て解除
   */
  $("#action-select-clear").on(click_event_name, function(e) {
    e.preventDefault();
    slideNavbar.slide();
    action.selectClear();
  });

  /*
   * メニュー
   *   タグ > 選択した小説のタグを編集
   */
  $("#action-tag-edit").on(click_event_name, function(e) {
    e.preventDefault();
    slideNavbar.slide();
    tag.openEditor();
  });

  /*
   * メニュー
   *   ツール > D&Dウィンドウを開く
   */
  $("#action-tool-open-dnd-window").on(click_event_name, function(e) {
    e.preventDefault();
    slideNavbar.slide();
    window.open("/widget/drag_and_drop", "dnd_window",
                "width=400,height=350,menubar=no,toolbar=no,scrollbars=no,resizable=yes");
  });

  /*
   * メニュー
   *   ツール > CSV形式でリストをダウンロード
   */
  $("#action-tool-csv-download").on(click_event_name, function(e) {
    e.preventDefault();
    slideNavbar.slide();
    location.href = "/api/csv/download"
  });

  /*
   * メニュー
   *   ツール > CSVファイルからインポート
   */
  $("#action-tool-csv-import").on(click_event_name, function(e) {
    e.preventDefault();
    slideNavbar.slide();
    action.csvImport();
  });

  /*
   * メニュー
   *   ツール > メモ帳（ポップアップ）
   */
  $("#action-tool-notepad-window").on(click_event_name, function(e) {
    e.preventDefault();
    slideNavbar.slide();
    window.open("/widget/notepad", "notepad_window",
                "width=400,height=350,menubar=no,toolbar=no,scrollbars=no,resizable=yes");
  });

  /*
   * メニュー
   *   オプション＞環境設定
   */
  $("#action-option-settings").on(click_event_name, function(e) {
    // ページ遷移するだけ
  });

  /*
   * メニュー
   *   オプション＞ヘルプ
   */
  $("#action-option-help").on(click_event_name, function(e) {
    // ページ遷移するだけ
  });

  /*
   * メニュー
   *   オプション＞Narou.rbについて
   */
  $("#action-option-about").on(click_event_name, function(e) {
    e.preventDefault();
    slideNavbar.slide();
    $.get("/about", function(data) {
      bootbox.dialog({
        title: '<span class="glyphicon glyphicon-info-sign"></span> Narou.rb について',
        message: data,
        backdrop: true
      });
    });
  });

  /*
   * メニュー
   *   オプション＞サーバを再起動
   */
  $("#action-option-server-reboot").on(click_event_name, function(e) {
    e.preventDefault();
    slideNavbar.slide();
    action.rebootDialog();
  });

  /*
   * メニュー
   *   オプション＞サーバをシャットダウン
   */
  $("#action-option-server-shutdown").on(click_event_name, function(e) {
    e.preventDefault();
    slideNavbar.slide();
    bootbox.dialog({
      title: '<span class="glyphicon glyphicon-off"></span> シャットダウン',
      message: "<p>Narou.rb WEB UI サーバをシャットダウンします。<br>" +
               "シャットダウンすると再度立ち上げるまではアクセスは出来なくなります。<br>" +
               "再度立ち上げるにはコンソールでもう一度 <kbd>narou web</kbd> を実行して下さい。</p>" +
               "<p class=text-danger>アップデート中や変換中の小説がある場合は中断されます。<br>" +
               "終わったかどうか確認しましょう。</p>",
      backdrop: true,
      buttons: {
        danger: {
          label: "シャットダウン",
          className: "btn-danger",
          callback: function() {
            $.post("/shutdown", function(data) {
              bootbox.alert(data);
            });
          }
        },
        main: {
          label: "キャンセル",
          className: "btn-default",
        }
      }
    });
  });

  // tooltip() にハッシュで設定を渡すと、DOMに設定されているdata-placementなどの
  // 値が無視されてしまうため、デフォルト値を変更しておく
  _.merge($.fn.tooltip.Constructor.DEFAULTS, {
    animation: false,
    container: "body",
    placement: "bottom"
  });

  /*
   * 「選択」メニューの横に現在選択中の小説数をバッジで表示
   */
  var register_badge_number_of_selecting = function(table) {
    table.on("changeselect", function() {
      console.log("[DEBUG] ================================");
      console.log("[DEBUG] changeselect event fired");
      console.log("[DEBUG] action object exists:", !!action);
      console.log("[DEBUG] action.selectedIds exists:", !!(action && action.selectedIds));
      if (action && action.selectedIds) {
        console.log("[DEBUG] action.selectedIds.size:", action.selectedIds.size);
        console.log("[DEBUG] action.selectedIds contents:", Array.from(action.selectedIds));
      }
      
      // ページを跨いだ選択がある場合はそれを使用、そうでなければ現在ページの選択数
      var selected_count;
      if (action && action.selectedIds && action.selectedIds.size > 0) {
        selected_count = action.selectedIds.size;
        console.log("[DEBUG] Using cross-page selection count:", selected_count);
      } else {
        selected_count = table.rows(".selected").data().length;
        console.log("[DEBUG] Using current page selection count:", selected_count);
      }
      console.log("[DEBUG] Final selected_count:", selected_count);
      console.log("[DEBUG] ================================");
      
      $("#badge-number-of-selecting").text(selected_count);
      if (selected_count > 0) {
        refreshTooltop(".button-update", "選択した小説を更新");
        refreshTooltop(".button-send", "選択した小説を送信");
        enable_menu_item(".enable-selected");
      }
      else {
        refreshTooltop(".button-update", "すべての小説を更新");
        refreshTooltop(".button-send", "更新された小説を送信");
        disable_menu_item(".enable-selected");
      }
    });
  };
  register_badge_number_of_selecting(table);

  /*
   * ボタンを一時的に非アクティブ化
   */
  function disableButtonMoment($button) {
    $button.blur();
    $button.tooltip("hide");
    $button.prop("disabled", true);
    // 少したったらアクティブに戻す
    setTimeout(function() {
      $button.prop("disabled", false);
    }, 1000);
  }

  /*
   * ボタン
   *   Download > 新規ダウンロード
   */
  $(".button-download").on("click", function(e) {
    e.preventDefault();
    action.download();
  });

  /*
   * ボタン
   *   Download > 選択した小説を強制再ダウンロード
   */
  $(".button-download-force").on("click", function(e) {
    e.preventDefault();
    action.downloadForce();
  });

  /*
   * ボタン
   *   Update
   */
  $(".button-update").on("click", function(e) {
    e.preventDefault();
    console.log("[DEBUG] Update button clicked");
    console.log("[DEBUG] action object:", action);
    console.log("[DEBUG] action.selectedIds:", action ? action.selectedIds : "action is null");
    console.log("[DEBUG] action.selectedIds.size:", action && action.selectedIds ? action.selectedIds.size : "N/A");
    console.log("[DEBUG] action.selectedIds contents:", action && action.selectedIds ? Array.from(action.selectedIds) : "N/A");
    
    disableButtonMoment($(this));
    action.update();
  });

  /*
   * ボタン
   *   Update > 表示されている小説を更新
   */
  $(".button-update-view").on("click", function(e) {
    e.preventDefault();
    action.updateView();
  });

  /*
   * ボタン
   *   Update > 最新話掲載日を確認
   */
  $(".button-update-general-lastup").on("click", function(e) {
    e.preventDefault();
    action.updateGeneralLastup();
  });


  /*
   * ボタン
   *   な
   * 最新話掲載日をなろうAPIで確認
   */
  $(".button-update-general-lastup-narou").on("click", function(e) {
    e.preventDefault();
    action.updateGeneralLastupNarou();
  });

  /*
   * ボタン
   *   他
   * その他の小説の最新話掲載日を確認
   */
  $(".button-update-general-lastup-other").on("click", function(e) {
    e.preventDefault();
    action.updateGeneralLastupOther();
  });

  /*
   * ボタン
   *   (repeatアイコン)
   * modified タグが付いた小説を更新
   */
  $(".button-update-general-lastup-update-modified").on("click", function(e) {
    e.preventDefault();
    action.updateGeneralLastupUpdateModified();
  });

  /*
   * ボタン
   *   Update > 凍結済みも更新
   */
  $(".button-update-force").on("click", function(e) {
    e.preventDefault();
    action.updateForce();
  });

  /*
   * ボタン
   *   Update > タグを指定して更新
   */
  $(".button-update-by-tag").on("click", function(e) {
    e.preventDefault();
    action.updateByTag();
  });

  /*
   * ボタン
   *   Send
   */
  $(".button-send").on("click", function(e) {
    e.preventDefault();
    disableButtonMoment($(this));
    action.send();
  });

  /*
   * ボタン
   *   Send > hotnentry を送信
   */
  $(".button-send-hotentry").on("click", function(e) {
    e.preventDefault();
    action.send("hotentry");
  });

  /*
   * ボタン
   *   Send > 端末の栞データをバックアップする
   */
  $(".button-send-backup-bookmark").on("click", function(e) {
    e.preventDefault();
    action.backupBookmark();
  });

  /*
   * ボタン
   *   Freeze > 選択した小説を凍結
   */
  $(".button-freeze-on").on("click", function(e) {
    e.preventDefault();
    action.freezeOn();
  });

  /*
   * ボタン
   *   Freeze > 選択した小説の凍結を解除
   */
  $(".button-freeze-off").on("click", function(e) {
    e.preventDefault();
    action.freezeOff();
  });

  /*
   * ボタン
   *   Remove > 選択した小説を削除
   */
  $(".button-remove").on("click", function(e) {
    e.preventDefault();
    action.remove();
  });

  /*
   * ボタン
   *   Convert
   */
  $(".button-convert").on("click", function(e) {
    e.preventDefault();
    disableButtonMoment($(this));
    action.convert();
  });

  /*
   * ボタン
   *   Other > 選択した小説の差分を表示
   */
  $(".button-diff").on("click", function(e) {
    e.preventDefault();
    action.diff();
  });

  /*
   * ボタン
   *   Other > 選択した小説の調査状況ログを表示
   */
  $(".button-inspect").on("click", function(e) {
    e.preventDefault();
    action.inspect();
  });

  /*
   * ボタン
   *   Other > 選択した小説の保存フォルダを開く
   */
  $(".button-folder").on("click", function(e) {
    e.preventDefault();
    action.folder();
  });

  /*
   * ボタン
   *   Other > 選択した小説のバックアップを作成
   */
  $(".button-backup").on("click", function(e) {
    e.preventDefault();
    action.backup();
  });

  /*
   * ボタン
   *   Other > 選択した小説の設定の未設定項目に共通設定を焼付ける
   */
  $(".button-setting-burn").on("click", function(e) {
    e.preventDefault();
    action.settingBurn();
  });

  /*
   * ボタン
   *   Other > 選択した小説をメールで送信
   */
  $(".button-mail").on("click", function(e) {
    e.preventDefault();
    action.mail();
  });

  /*
   * ボタン
   *   Eject
   */
  $(".button-eject").on("click", function(e) {
    e.preventDefault();
    action.eject();
  });

  /*
   * ボタン
   *   Eject > 今すぐ端末を取り出す
   */
  $(".button-eject-now").on("click", function(e) {
    e.preventDefault();
    action.ejectNow();
  });

  /*
   * アイコン
   *   ○件表示の横のリロードアイコン
   */
  $("#icon-refresh-table").on("click", function(e) {
    Narou.tableReload();
  });

  /*
   * ショートカット設定
   * http://www.openjs.com/scripts/events/keyboard_shortcuts/index.php
   */
  var initialize_shortcut = function() {
    var options = {
      disable_in_input: true,
    };
    var add = function() {
      var keys = [];
      var callback = null;
      for (var i = 0; i < arguments.length; i++) {
        var value = arguments[i];
        switch (typeof value) {
        case "string":
          keys.push(value);
          break;
        case "function":
          callback = value;
          break;
        default:
          $.error("invalid arguments: unknow type");
          break;
        }
      }
      if (!callback) $.error("shortcut error: need callback");
      for (var i = 0; i < keys.length; i++) {
        shortcut.add(keys[i], callback, options);
      }
    };

    var click = function(id) {
      return function() {
        $(id).trigger("click");
      };
    };

    add("Ctrl+A", "Meta+A", function() { action.selectView(); });
    add("Shift+A", function() { action.selectAll(); });
    add("Ctrl+Shift+A", "Meta+Shift+A", function() { action.selectClear(); });
    add("ESC", function() {
      if ($("#rect-select-menu").is(":visible")) {
        close_rect_select_menu_handler();
      }
      if (!context_menu.closed) {
        context_menu.close();
      }
      else {
        action.selectClear();
      }
    });
    add("S", click("#action-select-mode-single"));
    add("R", click("#action-select-mode-rect"));
    add("H", click("#action-select-mode-hybrid"));
    add("W", click("#action-view-novel-list-wide"));
    add("F", click("#action-view-frozen"));
    add("Shift+F", click("#action-view-nonfrozen"));
    add("T", click("#action-tag-edit"));
    add("F5", function() { 
      console.log("F5キーによる手動強制テーブルリロード");
      Narou.tableReload(true); 
    });
  };
  if (!touchable_device) {
    initialize_shortcut();
  }

  /*
   * disabled なメニューは何もしないように
   */
  function disable_menu_item(selector) {
    var $element = $(selector);
    $element.each(function(i, dom) {
      if (dom.tagName.toLowerCase() == "button")
        $(dom).prop("disabled", true);
      else
        $(dom).addClass("disabled");
    });
  }

  function enable_menu_item(selector) {
    var $element = $(selector);
    $element.each(function(i, dom) {
      if (dom.tagName.toLowerCase() == "button")
        $(dom).prop("disabled", false);
      else
        $(dom).removeClass("disabled");
    });
  }

  disable_menu_item(".navbar li.disabled");

  /*
   * コントロールパネル（操作ボタン群）をフッターにコピーする
   */
  function copy_buttons_to_footer() {
    refreshTooltop(
        $("#control-panel > div")
          .clone(true)
          .appendTo("#footer-navbar > .container")
          .addClass("in-footer dropup")
          .find("[data-toggle=tooltip]")
            .data("placement", "top")
        );
    table.fireChangeSelect();
  }

  function fix_buttons() {
  }

  function cancel_fix_buttons() {
    $("#footer-navbar").addClass("hide");
  }

    if (storage.get("buttons_hide_page_top"))
      $("#control-panel").addClass("hide");

    copy_buttons_to_footer();
    if (storage.get("buttons_fix_footer"))
      $("#footer-navbar").removeClass("hide");

    /*
     * Tooltip 化
     */
    refreshTooltop("[data-toggle=tooltip]");

    $("button").on("mouseleave", function() {
      $(this).tooltip("hide");
    });
  }

});
