# コンテキストファイル契約

## ファイルの役割

`AGENTS.md` は入口です。短く保ち、エージェントを `.agents/core.md`、`.agents/routing.md`、該当する provider profile に誘導します。

`CLAUDE.md` は Claude Code 向けの入口です。共有入口を `@AGENTS.md` で import する薄い wrapper として作成し、Claude 固有の補足だけをその下に追加します。

`GEMINI.md` は Gemini CLI 向けの bridge です。短く保ち、`AGENTS.md` と `.agents/profiles/gemini.md` に誘導します。`.gemini/settings.json` は、受け入れる context file name など Gemini CLI の設定に使います。

`.github/copilot-instructions.md` は GitHub Copilot の repository-wide bridge です。簡潔に保ち、`AGENTS.md` と `.agents/profiles/copilot.md` に誘導します。共有ポリシーをここに重複させてはいけません。

`AGENTS.md` には Claude の import 構文や Claude 固有 profile path を置かず、それらは `CLAUDE.md` 側に閉じ込めます。

`.agents/core.md` には、全エージェント共通のルールを書きます。リポジトリ概要、安全境界、検証方針、ドキュメント同期、編集規範、handoff の期待値などが対象です。

`.agents/routing.md` は、タスクに応じて追加で読むべきファイルや Skill を対応付けます。「このタスクでは次に何を読むべきか」に答えるファイルです。

`.agents/profiles/*.md` には、provider 固有の振る舞いを書きます。`core.md` 全体を繰り返してはいけません。

`.agents/provider-registry.yaml` には、対応 provider、bridge file、profile path、source URL、最終 review date を記録します。生成された registry content には YAML comment marker を使います。

`.agents/skills/*/SKILL.md` には、タスク固有の手順を書きます。繰り返し発生する workflow に専用の trigger と checklist が必要な場合に使います。

## 生成ブロック

生成コンテンツは次の範囲に置きます。

```md
<!-- agent-context-maintainer:begin -->
...
<!-- agent-context-maintainer:end -->
```

ユーザーが明示的に広範な rewrite を依頼しない限り、エージェントはマーカー内のテキストだけを置き換えます。managed marker は Markdown code fence の外に単独行として現れる必要があります。fenced code block 内の marker example は documentation であり、owned content ではありません。

マーカー数が一致しない、重複している、または順序が誤っている場合、エージェントは追記や置換をせず、修復を求めて停止します。

scaffold 対象の Markdown は marker-first に更新します。generated block が存在する場合は、その block だけを置き換え、git 上で clean なファイルでも marker 外の content はすべて維持します。generated marker がない場合はデフォルトで拒否します。marker のない Markdown に managed block を足す場合は `--append-generated-block`、marker のない scaffold 対象を置き換える場合は `--force-recreate` を使います。git から復元できない generated-block changes を上書きする前に、`.agents/snapshots/agent-context-maintainer/` に snapshot を保存します。

`.gemini/settings.json` のような JSON target は安全に comment marker を持てません。存在しない場合は作成し、既存 JSON object には必要な bridge key だけを merge し、他の設定は維持します。同一内容なら変更せず、既存 JSON を安全に parse / merge できない場合のみ `--force-recreate` を必要とします。

## 最小 AGENTS.md

```md
# Agent Instructions

Always read:

1. `.agents/core.md`
2. `.agents/routing.md`
3. The matching provider profile in `.agents/profiles/`; if unsure, read `.agents/profiles/generic.md`

If a task matches a routed skill, read that `SKILL.md` before editing.
```

## 最小 CLAUDE.md

```md
@AGENTS.md

## Claude Code

Use `AGENTS.md` as the shared source of truth for repository instructions. For Claude-specific behavior, also follow `.agents/profiles/claude.md` when present.
```

## 最小 GEMINI.md

```md
# Gemini CLI Instructions

Use `AGENTS.md` as the shared source of truth for repository instructions. Also follow `.agents/profiles/gemini.md` when present.
```

## 最小 GitHub Copilot Instructions

```md
# GitHub Copilot Instructions

Use `AGENTS.md` as the shared source of truth for repository instructions. Also follow `.agents/profiles/copilot.md` when present.
```

## core.md の最小セクション

- Repository Snapshot
- Context Boundaries
- Safety and Secrets
- Editing Rules
- Validation
- Handoff Notes

## routing.md の最小セクション

- Universal First Reads
- Task Routes
- Provider Profile Selection
- Missing Context Rule

## レビュー規則

完了前に、参照されているすべてのファイルが存在するか、future/planned と明示されていることを確認します。`AGENTS.md` に壊れたローカルパスを残してはいけません。
