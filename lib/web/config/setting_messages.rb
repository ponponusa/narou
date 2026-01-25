# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

module Narou
  # WEB UI > 環境設定画面で表示する各項目の説明
  # ここになければ元々の説明が表示される
  SETTING_VARIABLES_WEBUI_MESSAGES = {
    "convert.multi-device" => "複数の端末用に同時に変換する。deviceよりも優先される。\nただのEPUBを出力したい場合はepubを指定",
    "device" => "変換、送信対象の端末",
    "difftool" => "%%ORIG%%。※WEB UIでは使われません",
    "update.sort-by" => "アップデートを指定した項目順で行う",
    "default.title_date_align" => "enable_add_date_to_title で付与する日付の位置",
    "force.title_date_align" => "enable_add_date_to_title で付与する日付の位置",
    "difftool.arg" => "difftoolで使う引数(指定しなければ単純に新旧ファイルを引数に呼び出す)\n" \
                      "特殊な変数\n" \
                      "<b>%NEW</b> : 最新データの差分用ファイルパス\n" \
                      "<b>%OLD</b> : 古い方の差分用ファイルパス",
    "no-color" => "コンソールのカラー表示を無効にする\n※要サーバ再起動",
    "economy" => "容量節約に関する設定",
    "send.without-freeze" => "一括送信時に凍結された小説は対象外にする。（個別送信時は凍結済みでも送信可能）",
    "server-basic-auth.enable" => "%%ORIG%%\n※basic-auth関連の設定を変更した場合サーバの再起動が必要",
    "concurrency" => "%%ORIG%% ※要サーバ再起動",
    "logging" => "%%ORIG%%\n※要サーバ再起動",
    "logging.format-filename" => "%%ORIG%%\n※要サーバ再起動",
    "logging.format-timestamp" => "%%ORIG%%\n※要サーバ再起動",
    "auto-add-tags" => "小説サイトから取得したタグを自動的に小説データに追加する",
    "convert.add-dc-subject-to-epub" => "EPUB変換時にstandard.opfファイルにdc:subject要素を追加する。\n" \
                                        "小説のタグ情報がdc:subjectとして埋め込まれ、\n" \
                                        "電子書籍リーダーでの検索やカテゴリ分類に活用できます。\n除外するタグは下の設定で指定できます",
    "convert.dc-subject-exclude-tags" => "dc:subjectに埋め込まないタグをカンマ区切りで指定します。\n" \
                                         "<b>初期値:</b> 404,end（初回実行時に自動設定）\n" \
                                         "<b>404:</b> 削除された小説に付くタグ\n<b>end:</b> 完結を示すタグ\n" \
                                         "※すべてのタグを埋め込みたい場合は空欄にしてください",
    "convert.copy-zip-to" => "i文庫用などで生成したZIPを、変換完了時にコピーするフォルダを指定",
  "convert.make-zip" => "ZIPファイルを出力するかどうか（対応端末: i文庫）",
  }

  SETTING_VARIABLES_WEBUI_DEFAULT_HINTS = {
    "webui.theme" => "未設定時：CDN 配信のデフォルト Bootstrap 3 テーマを使用します",
    "webui.performance-mode" => "未設定時：auto が適用されます",
    "webui.table.reload-timing" => "未設定時：１作品ごとに更新します",
  }.freeze
end
