# 拡張ガイド

このドキュメントは `agent-context-maintainer` の意図と拡張契約を説明します。Skill 自体を変更するとき、provider/model profile を追加するとき、生成ルールを調整するとき、または他の agent platform に workflow を移植するときに読んでください。

## 企画意図

この Skill は、AI coding agent がリポジトリ内で安全に作業するために必要なコンテキストを保守できるようにします。その際、`AGENTS.md` を巨大で重複した instruction blob にしないことを重視します。

想定モデルは次の通りです。

- `AGENTS.md` は小さな入口。
- `CLAUDE.md` は Claude Code 互換のため `@AGENTS.md` で `AGENTS.md` を import する。
- `GEMINI.md`、`.gemini/settings.json`、`.github/copilot-instructions.md` は provider-specific な読み込み契約を `AGENTS.md` に bridge する。
- `.agents/core.md` は共有される durable policy。
- `.agents/routing.md` はタスクごとに追加で読むコンテキストを決める。
- `.agents/provider-registry.yaml` は provider bridge files、profile paths、source URLs、review date を記録する。
- `.agents/profiles/*.md` は provider、model family、host tool に合わせて振る舞いを調整する。
- `.agents/skills/*/SKILL.md` は繰り返し発生するタスク固有 workflow を保持する。

この Skill は、将来のエージェントがローカルリポジトリを理解しやすくする一方で、手書きの指示を保護し、機密データを生成コンテキストに入れないためのものです。

## 設計原則

1. 重複より layering を優先する。
2. 生成コンテキストは通常の diff で review できるサイズに保つ。
3. 手書きの指示はデフォルトで維持する。
4. secret と raw log は要約対象ではなく除外対象として扱う。
5. 将来作業の推測ではなく、安定した repository facts を記録する。
6. provider 固有の振る舞いは core policy ではなく profile に置く。
7. validation はエージェントが実際に実行できる程度に安くする。

## 非目標

- universal memory system は作らない。
- chat transcript や hidden model context は取り込まない。
- secret file から private policy を推測しない。
- `README.md`、`DESIGN.md`、`CONTRIBUTING.md` などの project documentation を置き換えない。
- provider profile を各 host product の system instructions と競合させない。

## 生成ファイル契約

script は対象リポジトリ配下に次の path を作成または更新できます。

```text
AGENTS.md
CLAUDE.md
GEMINI.md
.github/copilot-instructions.md
.gemini/settings.json
.agents/core.md
.agents/routing.md
.agents/provider-registry.yaml
.agents/skill-registry.yaml
.agents/skill-reports/skill-health.md
.agents/skill-overrides.json
.agents/skill-workspaces/
.agents/profiles/codex.md
.agents/profiles/claude.md
.agents/profiles/gemini.md
.agents/profiles/cursor.md
.agents/profiles/copilot.md
.agents/profiles/antigravity.md
.agents/profiles/generic.md
.agents/skills/
```

生成コンテンツは次のマーカーで囲まれます。

```md
<!-- agent-context-maintainer:begin -->
...
<!-- agent-context-maintainer:end -->
```

両方のマーカーが存在する場合、updater はマーカー内だけを置き換えます。managed marker は Markdown code fence の外に単独行として存在する必要があります。owned marker がない場合はデフォルトで拒否します。marker のない Markdown を維持して managed block を追記する場合は `--append-generated-block`、明示的な broad rewrite には `--force-recreate` を使います。

マーカー数が一致しない、重複している、または順序が誤っている場合、updater は書き込みを拒否します。これにより、古いまたは壊れた `BEGIN` marker が後続実行で手書き content を巻き込むことを防ぎます。

`AGENTS.md` は provider-neutral に保ちます。Claude Code の import 構文や具体的な `.agents/profiles/claude.md` 参照は `AGENTS.md` ではなく `CLAUDE.md` に置きます。

現在の scaffold behavior は Markdown/YAML target に対して marker-first です。git 上で clean な既存 human file も自動的には置き換えません。git から復元できない generated-block changes を上書きする場合は、`.agents/snapshots/agent-context-maintainer/` に snapshot を保存します。JSON target は安全に comment marker を持てないため、存在しない場合に作成し、既存 JSON object には必要な bridge key だけを merge し、同一内容なら変更せず、unsafe replacement の場合のみ `--force-recreate` を必要とします。

## Script Architecture

`scripts/agent_context.py` には次の public command があります。

- `inventory ROOT`: 安全な repository summary を出力する。
- `inventory ROOT --json --explain-skips`: bounded skip reasons を含む structured inventory を出力する。
- `scaffold ROOT --agent AGENT`: context files を作成または更新する。
- `scaffold ROOT --dry-run`: planned writes を preview する。
- `check ROOT`: 最小 context structure と references を検証する。
- `skills inventory ROOT [--json]`: `.agents/skills` 直下の skill を scan する。
- `skills check ROOT`: skill frontmatter、references、eval manifests を検証する。
- `skills report ROOT`: deterministic な skill health report を出力する。
- `skills sync ROOT`: `.agents/skill-registry.yaml` と `.agents/skill-reports/skill-health.md` を書く。
- `skills routes ROOT`: compact skill routes を `.agents/routing.md` に同期する。
- `skills eval ROOT --plan|--init-workspace`: repository-local eval workspace を計画または作成する。

主な extension point:

- `PROVIDERS`: provider 知識の単一の正本 — profile 文言、bridge files、registry の source URL、runtime 検出用環境変数。`PROFILES`、生成される provider registry、profile 本文、`detect_agent()` はすべてここから導出されます。
- `DETECT_PRIORITY`: 複数 provider の変数が同時に存在する場合の検出優先順位。`PROVIDERS` の key 順とは独立です。
- `EXCLUDED_DIRS`: inventory で skip する directory。
- `SECRET_NAMES`、`EXCLUDED_SUFFIXES`、`is_secret()`: file-level safety exclusion。
- `SENSITIVE_DIR_COMPONENTS`、`ARCHIVE_SUFFIXES`、`BINARY_SUFFIXES`、skip reason helpers: inventory hardening。
- `MANIFESTS`: project manifest detection。
- `LANG_EXTS`: language signal detection。
- `*_body()` functions: 生成 Markdown template。
- `check()`: validation rules。bridge ごとの検証内容(各 bridge file が含むべき文字列)は明示的なロジックとして残し、`PROVIDERS` から導出するのは「どのファイル・profile が存在すべきか」だけです。
- SkillOps helpers: `skill_inventory()`、`parse_skill_frontmatter()`、`validate_eval_manifest()`、`skills_sync()`、`sync_skill_routes()`、`init_skill_workspace()` は skill audit を dependency-free に保ち、symlink target を追跡しません。
- `claude_body()`: `AGENTS.md` を import する Claude Code wrapper。
- `classify_recreate()` と `apply_planned_writes()`: marker-first update planning と書き込み。
- `detect_agent()`: `(agent, matched_variable)` を返します。完全一致検出のみで、部分文字列マッチは使いません。

明確な reliability benefit がない限り、script は dependency-free に保ちます。現在の script は、多くの agent sandbox で利用できる system Python で動くことを意図しています。

## Provider または Model Profile の追加

`aider`、`qwen`、`deepseek` など、新しい provider、host product、model family を追加するときはこの手順を使います。

1. 正規化した key、title、profile bullets、bridge files、source URLs を持つ entry を `PROVIDERS` に追加する。他のすべて(`PROFILES` タプル、生成される registry、profile ファイル)はここから導出される。
2. `detect_env` の変数は一次情報で確認できたものだけを列挙し、確認記録(変数、方法、日付)を `reports/provider-review-*.md` に残す。検出変数を持つ provider は `DETECT_PRIORITY` にも追加する。未確認の provider は `detect_env: []` のままとし、`--agent <name>` で選択する。
3. provider に安定した loading contract がある場合のみ、bridge file を追加または更新する。
4. `PROVIDER_REGISTRY_REVIEWED` は provider-review レポートとセットで更新する — 片方だけの更新は禁止。
5. `references/provider-profiles.md` と `references/provider-profiles.ja.md` に profile の意図と anti-patterns を追加する。
6. provider が新しい種類の振る舞いを必要とする場合、この guide も更新する。
7. `tests/golden/` と `examples/sample-output/` を再生成し、生成物の変更を `CHANGELOG.md` に記録する。
8. fixture repository に対して `scaffold` を 2 回実行する。1 回目は file creation、2 回目は marker-based update の確認。
9. fixture repository に対して `check` を実行する。

Profile guidance は operational であるべきです。良い profile は、その agent がこの repository でどう違って動くべきかを示します。弱い profile は generic policy を繰り返したり、model を褒めるだけになったりします。

## 生成 core context のカスタマイズ

全エージェントに適用する repository-wide rule を変えたい場合は `core_body()` を変更します。

適した候補:

- source-of-truth documentation rules。
- secret handling と logging boundaries。
- validation expectations。
- public/private documentation synchronization。
- handoff または resume checkpoint expectations。

避ける候補:

- provider-specific tone。
- task-specific implementation checklist。
- 既存 docs からの大きな copied excerpt。
- script が安全に推定できない事実。

新しい inventory-derived field を追加する場合は、`inventory()` も更新し、出力を bounded に保ちます。デフォルトでは file contents の scan を避け、ユーザーが deeper analysis を求めない限り、filenames、manifests、明示的な docs を優先します。

## Routing のカスタマイズ

エージェントにとって「次に何を読むか」の decision tree を明確にしたい場合は `routing_body()` を変更します。

有用な route:

- Code review
- Feature implementation
- Documentation updates
- Security/privacy-sensitive changes
- Frontend UI work
- Release or CI triage
- Repository-specific repeated workflows

すべてのタスクをすべてのファイルへ route してはいけません。目的は context efficiency です。

## Task Skill の作成

workflow が繰り返し発生し、task-specific procedure が必要な場合は `.agents/skills/<task>/SKILL.md` を作成します。

推奨形:

```md
---
name: repo-task-name
description: What this task skill does and when to use it.
---

# Repo Task Name

## Workflow

1. Read the minimum required files.
2. Make the scoped change.
3. Run focused validation.
4. Report changed files and residual risk.
```

Task skill は core policy を複製せず、参照する形にします。

## Safety Model

Inventory は次を skip します。

- `.env*`
- private keys and certificates
- 名前に `secret` または `token` を含む files
- dependency caches
- build outputs
- 明示的に要求されない local databases and raw logs

生成コンテキストでは、これらのカテゴリが除外対象であることを記述できます。ただし内容そのものを含めてはいけません。

extension が sensitive files を調査する必要がある場合は、明示的に user-approved mode とし、目的を narrow に保ち、raw values を context files に書き込まないでください。

## Validation Expectations

Skill を変更したら、次を行います。

1. script syntax validation を実行する。

```bash
python3 -c "from pathlib import Path; p=Path('scripts/agent_context.py'); compile(p.read_text(), str(p), 'exec')"
```

2. `README.md`、manifest、test file、既存 `AGENTS.md` を少なくとも含む小さな fixture repository を作成または再利用する。
3. 次を実行する。

```bash
python3 scripts/agent_context.py inventory /path/to/fixture
python3 scripts/agent_context.py scaffold /path/to/fixture --agent codex
python3 scripts/agent_context.py check /path/to/fixture
python3 scripts/agent_context.py scaffold /path/to/fixture --agent claude
python3 scripts/agent_context.py check /path/to/fixture
```

4. 2 回目の scaffold が generated block を重複追記せず、既存 block を更新することを確認する。
5. markers 外の手書き text が維持されていることを確認する。
6. 壊れた marker pair がある場合、`scaffold` が書き込まずに失敗すること、code fence 内の marker example が無視されることを確認する。
7. generated marker のない git-tracked clean target files がデフォルトで拒否されることを確認する。
8. `--append-generated-block` が marker のない Markdown を維持し、managed block を 1 つだけ追記し、non-Markdown target を拒否することを確認する。
9. git から復元できない generated-block updates は、その block の上書き前に snapshot されることを確認する。

利用プラットフォームに skill validator がある場合(例: skill-creator の `quick_validate.py`)は、任意の追加手順として実行しても構いません。特定プラットフォームの validator は必須ではありません。

ローカルで全検証を再現可能に実行する方法は次の通りです。

```bash
scripts/run_checks.sh
```

## 他 Agent Platform への移植

core pattern は platform-neutral です。他の agent では次の方針を使います。

- platform が `AGENTS.md` を読むなら universal entry point として維持する。
- 必須の場合のみ、`CLAUDE.md`、`.cursorrules`、IDE-specific rule file など platform-native entry file を追加する。Claude Code では、指示を複製するより `@AGENTS.md` を含む `CLAUDE.md` を優先する。
- platform-native file は `.agents/core.md` と `.agents/routing.md` を指すようにする。
- source-of-truth policy は複数の platform files ではなく `.agents/` に置く。

platform が references を安定して追えない場合は、first-read list と最重要 safety boundary だけを含む compact な platform entry file を生成します。

## この Skill 自体の配布

この skill は、すべてのプラットフォームに対して 1 つのフォルダとして配布します。

- `SKILL.md` は Codex と Claude Code が共有する Agent Skills 規約(`name` と `description` を持つ YAML frontmatter)に従うため、1 つのファイルで両方に対応します。frontmatter の description はプラットフォーム中立に保ちます: provider 名は例として列挙し、トリガー条件の主語にはしません。
- `agents/openai.yaml` が唯一のプラットフォーム固有アダプタです。追加のアダプタは、他プラットフォームが無視できる追加ファイルでなければなりません。プラットフォームごとに `SKILL.md` をフォークしてはいけません。
- `scripts/agent_context.py` は、skill 機構を持たないエージェント(および人間)が直接実行できるよう、依存ゼロの単一ファイルを維持します。明確な reliability 上の利点なしに分割や依存追加をしないでください。
- リポジトリのルートには生成コンテキストファイル(`AGENTS.md`、`.agents/` など)を置きません。生成例は `examples/sample-output/` に置き、skill インストールを清潔に保ちます。

## 二言語ドキュメントルール

正は英語版ドキュメントです。日本語版(`*.ja.md`)は英語版と同一コミットで更新します。両者が食い違う場合は英語版を信頼し、日本語版を修正します。

## Versioning Guidance

generation behavior を変更するときは、この guide を更新します。

- 新しい file または section contract。
- 既存 repository に対する migration behavior。
- 古い `.agents/` directory との compatibility risk。

marker 名、path 名、profile key に silent breaking change を入れないでください。breaking change が必要な場合は、`scaffold` semantics を暗黙に変えるのではなく migration command を追加します。
