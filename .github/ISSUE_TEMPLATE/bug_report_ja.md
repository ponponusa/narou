---
name: "🐞 バグ報告"
about: "WebUI / ダウンロード処理などの不具合を報告する"
title: "[bug] ～するとエラーが発生する"
labels: ["bug"]
assignees: []
---

## 🐛 バグの概要
発生している問題について、簡潔で明確に説明してください。

例：  
`narou download 12345` を実行すると  
`Template.write: Invalid or unsafe file path` という例外で処理が停止します。

---

## 🔁 再現手順
問題を再現する手順をできるだけ具体的に書いてください。

1. 実行したコマンドまたは操作手順（例：`narou download 12345`）  
2. 使用したオプションや設定内容（例：保存先をカスタムしている）  
3. Web UI 上での操作が原因の場合、どの画面で何をクリックしたか  
4. どのタイミングでエラーが発生したか  

---

## 📖 期待していた動作
本来どのように動作することを期待していたか、簡潔に書いてください。

例：  
対象小説が正常にダウンロード・整形され、ライブラリに追加されることを期待していました。

---

## 📝 実際のログ / エラーメッセージ
例：
terminated with exception (report_on_exception is true):
Template.write: Invalid or unsafe file path ...***.yaml

---

## 🖥 実行環境（CLI利用時）
- OS：例）Ubuntu 24.04 / macOS 15 / Windows 11 (WSL2)
- Ruby バージョン：`ruby -v` の結果
- narou.rb バージョン：`narou-mod --version` の結果
- 実行方法：`gem install` / `bundle exec` / Docker 等
- 設定変更・カスタマイズがある場合は概要を記載

---

## 🌐 実行環境（WebUI利用時）
- ブラウザ：例）Chrome 131 / Firefox 132 / Safari 18  
- アクセス方法：ローカルで `narou-mod web` 起動 / リモートサーバ経由 など  
- Web UI のポート番号や HTTPS の有無（例：`https://localhost:9200`）

---

## 📚 対象の小説・サイト
- どの小説サイトで発生しましたか？（例：小説家になろう / カクヨム / ノクターン など）  
- 特定作品のみで発生しますか？（作品IDなど分かる範囲で）  

※公開しづらい場合は「特定作品のみで再現」などの記載でもOKです。

---

## 🧩 補足情報
再現に関係しそうな情報があれば記載してください。  
例）3.9.1.mod.R1.1への更新後から発生、2025.1.1以降でのみ再現、など。
