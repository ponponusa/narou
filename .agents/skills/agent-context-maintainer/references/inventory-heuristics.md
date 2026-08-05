# Inventory Heuristics

## Inspect

- Root docs: `README*`, `DESIGN*`, `CONTRIBUTING*`, `SECURITY*`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`.
- Agent context: `.agents/**`, `.codex/**`, `.github/**`, `.gemini/**`.
- Manifests: `package.json`, `Cargo.toml`, `pyproject.toml`, `go.mod`, `pom.xml`, `build.gradle`, `Package.swift`, `*.xcodeproj`, `*.xcworkspace`.
- Tests and CI: `scripts/`, `Makefile`, `.github/workflows/`, test directories, CI wrappers.
- Public/private doc split: `docs/`, `.docs/`, internal planning folders.

## Ignore Unless Explicitly Needed

- Secrets and credentials: `.env*`, `*.pem`, `*.key`, token files, local keychains.
- Sensitive directory components: `.ssh/`, `.aws/`, `.kube/`, `.docker/`, `.gnupg/`, `.terraform/`, `secrets/`, `credentials/`.
- Dependency caches: `node_modules/`, `.venv/`, `vendor/`, `.cargo/`, `.gradle/`.
- Build outputs: `dist/`, `build/`, `target/`, `.next/`, `DerivedData/`.
- Binary databases and logs: `*.db`, `*.sqlite`, `*.log`.
- Symlinks, archives, binary files, and files larger than the bounded inventory threshold.
- This tool's own snapshots: `.agents/snapshots/` (runtime byproducts; counting them would keep changing the inventory on every scaffold run).

Respect `.gitignore` when a git repository is available. Use `inventory --explain-skips` to audit bounded skip reasons and `inventory --json` when downstream tooling needs structured output.

## Summarize

Prefer stable facts:

- Primary languages and frameworks inferred from manifests.
- Main commands from existing scripts or docs.
- Validation commands that are already present.
- Repository-specific privacy or security boundaries.
- Existing handoff docs and resume checkpoints.

Mark uncertain observations as "needs confirmation" instead of embedding guesses as policy.
