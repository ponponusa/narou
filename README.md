# Narou.rb_MOD - 小説家になろうのダウンローダ＆縦書き整形＆管理アプリ。

> [!NOTE]
> このプロジェクトは下記プロジェクトの派生です。
>
> - **Original Project : [whiteleaf7/narou](https://github.com/whiteleaf7/narou) --** <sub>![GitHub last commit](https://img.shields.io/github/last-commit/whiteleaf7/narou?style=flat&labelColor=blue&color=white)</sub>
>
> - **Forked from : [Rumia-Channel/narou](https://github.com/Rumia-Channel/narou) --** <sub>![GitHub last commit](https://img.shields.io/github/last-commit/Rumia-Channel/narou?style=flat&labelColor=gold&color=pink&link=https%3A%2F%2Fgithub.com%2FRumia-Channel%2Fnarou)</sub>
>

素晴らしいプロジェクトを作成していただいた、[whiteleaf7](https://github.com/whiteleaf7) さん、[Rumia-Channel](https://github.com/Rumia-Channel) さんに多大なる感謝を。

## 概要 - Summary

![GitHub Release](https://img.shields.io/github/v/release/ponponusa/narou)

このアプリは[小説家になろう](http://syosetu.com/)などで公開されている小説の管理、
及び電子書籍データへの変換を支援します。縦書き用に特化されており、
横書きに最適化されたWEB小説を違和感なく縦書きで読むことが出来るようになります。
また、校正機能もありますので、小説としての一般的な整形ルールに矯正します。（例：感嘆符のあとにはスペースが必ずくる）

小説家になろうを含めて、下記のサイトに対応しています。

| サイト名 | URL | 備考 |
|----------|----------|----------|
| 小説家になろう | http://syosetu.com/ | |
| ノクターンノベルズ | http://noc.syosetu.com/ | |
| ムーンライトノベルズ | http://mnlt.syosetu.com/ | |
| ミッドナイトノベルズ | http://mid.syosetu.com/ | |
| ハーメルン | https://syosetu.org/ | |
| Arcadia | http://www.mai-net.net/ | |
| 暁 | http://www.akatsuki-novels.com/ | （※300話以上ある作品は未対応） |
| カクヨム | https://kakuyomu.jp/ | |

主な機能は小説家になろうの小説のダウンロード、更新管理、テキスト整形、AozoraEpub3・kindlegen連携によるEPUB/MOBI出力です。  
その他にも変換したデータを直接電子書籍端末へ送信する機能は、メールで送信する機能などもあります。

~~詳細な説明やインストール方法は **[Narou.rb_MOD説明書](https://github.com/ponponusa/narou/wiki)** を御覧ください。~~（準備中）

## 動作要件 - Requirements

- Ruby 3.4以上（※元プロジェクトから変更されています）

## 更新履歴 - ChangeLog

### 3.9.1.mod.R1 : 2025-10-28

#### <更新内容> ※[Rumia-Channel/narou](https://github.com/Rumia-Channel/narou)からの更新点を記載しています

```md
- テキスト/EPUB変換処理の高速化
  - 主に話数の多い（1000話オーバーなど）小説で顕著に効果があります
  - ※小説掲載サイトからの取得ロジックに変更はないため、取得速度は変化はありません（変更予定もなし）
- JavaScriptライブラリの更新、変更
  - update jQuery 1.11.1 -> 3.7.1
  - update datatables.js 1.10.10 -> 2.3.4
  - update bootstrap 3.3.5 -> 3.4.1
  - and more...
- Rubyパッケージの更新、変更
  - supported Ruby version 2.3.0~ -> 3.4.0~
  - add puma/bootsnap/and more...
  - update sinatra/ActiveSuport/tilt/and more...
- Digest認証からBasic認証に変更
  - Rack3.1から[Digest認証が非対応](https://github.com/ruby-grape/grape/issues/2294)となったため
- その他、細かな修正
```

## TODO

- 外部Webサーバを利用しない形でのHTTPS対応
- bootstrap5への移行
    - bootstrap3系では、jQuery3系に対応していないため
    - jQuery migrateを削除したい
- 小説タイトルの自動整形
- セキュリティリスクのある実装の修正
- 変換処理の並列化による高速化
    - 今後の最適化のためにもスレッドセーフにする

----

:classical_building:「小説家になろう」は株式会社ヒナプロジェクトの登録商標です。
