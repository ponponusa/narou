# Inventory Heuristics

## 調査するもの

- ルート docs: `README*`, `DESIGN*`, `CONTRIBUTING*`, `SECURITY*`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`
- Agent context: `.agents/**`, `.codex/**`, `.github/**`, `.gemini/**`
- Manifests: `package.json`, `Cargo.toml`, `pyproject.toml`, `go.mod`, `pom.xml`, `build.gradle`, `Package.swift`, `*.xcodeproj`, `*.xcworkspace`
- Tests and CI: `scripts/`, `Makefile`, `.github/workflows/`, test directories, CI wrappers
- public/private doc split: `docs/`, `.docs/`, internal planning folders

## 明示的に必要でない限り無視するもの

- Secrets and credentials: `.env*`, `*.pem`, `*.key`, token files, local keychains
- Sensitive directory components: `.ssh/`, `.aws/`, `.kube/`, `.docker/`, `.gnupg/`, `.terraform/`, `secrets/`, `credentials/`
- Dependency caches: `node_modules/`, `.venv/`, `vendor/`, `.cargo/`, `.gradle/`
- Build outputs: `dist/`, `build/`, `target/`, `.next/`, `DerivedData/`
- Binary databases and logs: `*.db`, `*.sqlite`, `*.log`
- symlink、archive、binary file、bounded inventory threshold を超える巨大ファイル
- 本ツール自身の snapshot: `.agents/snapshots/`(実行時の副産物。数えてしまうと scaffold のたびに inventory が変わり続ける)

git repository では `.gitignore` を尊重します。bounded な skip 理由を監査するときは `inventory --explain-skips`、downstream tooling に渡すときは `inventory --json` を使います。

## 要約するもの

安定した事実を優先します。

- manifest から推定できる主要言語と framework。
- 既存 scripts や docs に書かれている主要コマンド。
- すでに存在する validation command。
- repository-specific な privacy / security boundary。
- 既存の handoff docs と resume checkpoints。

不確かな観察は policy として埋め込まず、`needs confirmation` として明示します。
