---
name: agent-context-maintainer
description: AGENTS.md、.agents/core.md、.agents/routing.md、provider 固有の profile、タスク用 SKILL.md routing といった repo-local な AI agent コンテキストファイルを作成・更新・検証する。AI coding agent（Codex、Claude Code、Gemini、Copilot、Cursor など）に AGENTS.md や SKILL 指示を自己保守可能にしてほしいとき、現在のパスを調査して最適な agent コンテキストを生成してほしいとき、agent 指示をリポジトリの実態と同期させ続けたいときに使う。
---

# Agent Context Maintainer

## 概要

現在のリポジトリ向けに、小さく階層化された agent コンテキストシステムを保守します。構成は、共通の入口、共有ルール、provider 固有の profile、タスク単位の skill routing です。人が書いた指示を置き換えるのではなく、安全な incremental update を優先します。

## ワークフロー

1. 現在の作業ディレクトリ、またはユーザーが指定したパスを context root として扱います。ユーザーが明示的に求めない限り、その上位はスキャンしません。
2. 可能な限り、稼働中の agent runtime を特定します（Codex、Claude Code、Gemini、Copilot、Cursor、Antigravity、または不明）。不明な場合は generic profile を作成し、ユーザー向けの routing を明示します。
3. ファイル名、manifest、既存ドキュメント、テスト、ビルドファイルを使ってパスを inventory します。secret、credential、private key、`.env*`、ローカル DB、依存キャッシュ、生成されたビルド成果物は読みません。
4. 編集前に、既存の `AGENTS.md`、`.agents/**`、関連する `SKILL.md` を読みます。人が書いたルールは維持し、必要最小限のセクションだけを更新します。
5. 次の構造を作成、またはリフレッシュします。

```text
AGENTS.md
CLAUDE.md
GEMINI.md
.github/
  copilot-instructions.md
.gemini/
  settings.json
.agents/
  core.md
  routing.md
  provider-registry.yaml
  profiles/
    codex.md
    claude.md
    gemini.md
    cursor.md
    copilot.md
    antigravity.md
    generic.md
  skills/
```

6. `AGENTS.md` は薄い入口に留めます。`CLAUDE.md` は、`@AGENTS.md` で `AGENTS.md` を import する Claude Code 用の入口ファイルとして生成します。
7. エージェント横断で長く使えるルールは `.agents/core.md`、provider/model ごとの差分は `.agents/profiles/*.md`、タスク選択ルールは `.agents/routing.md` に置きます。
8. 参照を検証し、何を変更し、何を維持し、何が人による確認を要するかを報告します。

## スクリプトによる Scaffold

再現性のあるセットアップと検証には `scripts/agent_context.py` を使います。

```bash
python3 scripts/agent_context.py providers
python3 scripts/agent_context.py inventory /path/to/repo
python3 scripts/agent_context.py scaffold /path/to/repo --agent auto
python3 scripts/agent_context.py check /path/to/repo
```

`providers` は、対応 provider・bridge ファイル・自動検出の可否を一覧表示します。リポジトリの構成がはっきりしない場合は、手動編集の前に `inventory` を実行します。skip 理由が重要なときは `inventory --json --explain-skips` を使います。欠けているファイルの作成や生成ブロックのリフレッシュには `scaffold` を使います。`--agent auto` は確認済みの環境変数から runtime を検出して検出結果を表示し、`--agent <name>` の明示指定は常に検出より優先されます。仕上げ前には `check` を実行します。

## 更新ルール

- デフォルトは marker-first 更新：生成ブロックだけを置き換え、marker 外の手書き内容は維持します。
- marker は、Markdown code fence の外にある単独行のときだけ「管理対象」とみなします。
- marker のない既存 Markdown 対象は、デフォルトで拒否します。
- marker のない Markdown 対象を維持して managed block を追記するには `--append-generated-block` を使います。
- marker のない scaffold 対象の置き換えをユーザーが明示的に承認した場合のみ `--force-recreate` を使います。
- 予定される書き込みをプレビューするには `--dry-run` を使います。
- git から復元できない generated-block 更新は、そのブロックを上書きする前に以前の内容を snapshot します。
- 既存の `.gemini/settings.json` オブジェクトは、必要な bridge key を追加し、他の設定を維持してマージします。
- 生成ブロックの更新は `<!-- agent-context-maintainer:begin -->` と `<!-- agent-context-maintainer:end -->` で区切って行うことを優先します。
- secret、credential、token、private URL、個人データ、チャット履歴、生ログそのものをコンテキストファイルにコピーしません。
- 機密の境界は、実データを含む例ではなく、ポリシーとして言及します。
- provider profile は短く保ちます。そのエージェントがより良く振る舞うのに役立つ差分だけを書きます。
- task skill は triggering と手順に集中させます。core のリポジトリポリシーをすべての skill に重複させないようにします。
- private な計画ドキュメントが公開向けのルールを変える場合は、黙って広範な編集をするのではなく、同期の必要性を指摘します。

## リファレンスファイル

必要なときだけ読みます。

- `references/context-file-contract.md`: 必要なファイル、セクションの所有権、更新境界。
- `references/provider-profiles.md`: Codex、Claude、Gemini、Cursor、generic profile にそれぞれ何を書くか。
- `references/inventory-heuristics.md`: 何を調べ、何を無視し、リポジトリを安全に要約する方法。
- `references/extension-guide.md`: プロダクトの意図、生成ルール、新しいエージェントやモデルへ skill を拡張する方法。
- 日本語版ドキュメントは、同じ名前に `.ja.md` を付けたものです。
