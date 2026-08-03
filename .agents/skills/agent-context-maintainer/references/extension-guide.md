# Extension Guide

This document explains the intent and extension contract for `agent-context-maintainer`. Read it when changing the skill itself, adding a provider/model profile, adjusting generation rules, or porting the workflow to another agent platform.

## Product Intent

The skill helps AI coding agents maintain the context they need to work safely inside a repository without turning `AGENTS.md` into a large, duplicated instruction blob.

The intended model is:

- `AGENTS.md` is a small entry point.
- `CLAUDE.md` imports `AGENTS.md` with `@AGENTS.md` for Claude Code compatibility.
- `GEMINI.md`, `.gemini/settings.json`, and `.github/copilot-instructions.md` bridge provider-specific loading contracts back to `AGENTS.md`.
- `.agents/core.md` holds shared, durable policy.
- `.agents/routing.md` decides what additional context to read for a task.
- `.agents/provider-registry.yaml` records provider bridge files, profile paths, source URLs, and review date.
- `.agents/profiles/*.md` adapts behavior to a provider, model family, or host tool.
- `.agents/skills/*/SKILL.md` captures repeated task-specific workflows.

The skill should make the local repository easier for future agents to understand, while preserving human-authored instructions and keeping sensitive data out of generated context.

## Design Principles

1. Prefer layering over duplication.
2. Keep generated context reviewable in a normal diff.
3. Preserve hand-written instructions by default.
4. Treat secrets and raw logs as excluded inputs, not as data to summarize.
5. Encode stable repository facts, not guesses about future work.
6. Put provider-specific behavior in profiles, not in core policy.
7. Make validation cheap enough that agents will actually run it.

## Non-Goals

- Do not create a universal memory system.
- Do not import chat transcripts or hidden model context.
- Do not infer private policy from secret files.
- Do not replace project documentation such as `README.md`, `DESIGN.md`, or `CONTRIBUTING.md`.
- Do not make provider profiles compete with the system instructions of each host product.

## Generated File Contract

The script may create or update these paths under the target repository:

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

Generated content is bounded by:

```md
<!-- agent-context-maintainer:begin -->
...
<!-- agent-context-maintainer:end -->
```

The updater should replace only the marked block when both markers exist. Managed markers must be standalone lines outside Markdown code fences. If no owned markers exist, it must refuse by default. Use `--append-generated-block` to preserve unmarked Markdown and append a managed block. Use `--force-recreate` for an explicit broad rewrite.

If marker counts are mismatched, duplicated, or ordered incorrectly, the updater must refuse to write. This prevents a stale or malformed `BEGIN` marker from consuming hand-written content on a later run.

`AGENTS.md` must stay provider-neutral. Put Claude Code import syntax and the concrete `.agents/profiles/claude.md` pointer in `CLAUDE.md`, not in `AGENTS.md`.

Current scaffold behavior is marker-first for Markdown/YAML targets. Existing clean human files are not automatically replaced. If generated-block changes are not recoverable from git, save a snapshot under `.agents/snapshots/agent-context-maintainer/` before overwriting the block. JSON targets cannot carry comments safely, so create them when missing, merge required bridge keys into existing JSON objects, leave identical files unchanged, and require `--force-recreate` only for unsafe replacement.

## Script Architecture

`scripts/agent_context.py` has three public commands:

- `inventory ROOT`: print a safe repository summary.
- `inventory ROOT --json --explain-skips`: print structured inventory with bounded skip reasons.
- `scaffold ROOT --agent AGENT`: create or refresh context files.
- `scaffold ROOT --dry-run`: preview planned writes.
- `check ROOT`: verify the minimum context structure and references.
- `skills inventory ROOT [--json]`: scan direct child skills under `.agents/skills`.
- `skills check ROOT`: validate skill frontmatter, references, and eval manifests.
- `skills report ROOT`: print the deterministic skill health report.
- `skills sync ROOT`: write `.agents/skill-registry.yaml` and `.agents/skill-reports/skill-health.md`.
- `skills routes ROOT`: sync compact skill routes into `.agents/routing.md`.
- `skills eval ROOT --plan|--init-workspace`: plan or create repository-local eval workspaces.

Important internal extension points:

- `PROVIDERS`: the single source of truth for provider knowledge — profile wording, bridge files, registry source URLs, and runtime-detection environment variables. `PROFILES`, the generated provider registry, profile bodies, and `detect_agent()` all derive from it.
- `DETECT_PRIORITY`: detection precedence when multiple providers' variables are present; independent of the `PROVIDERS` key order.
- `EXCLUDED_DIRS`: directories skipped during inventory.
- `SECRET_NAMES`, `EXCLUDED_SUFFIXES`, and `is_secret()`: file-level safety exclusions.
- `SENSITIVE_DIR_COMPONENTS`, `ARCHIVE_SUFFIXES`, `BINARY_SUFFIXES`, and skip reason helpers: inventory hardening.
- `MANIFESTS`: project manifest detection.
- `LANG_EXTS`: language signal detection.
- `*_body()` functions: generated Markdown templates.
- `check()`: validation rules. Bridge-specific verification (which strings each bridge file must contain) stays as explicit logic; only "which files and profiles must exist" derives from `PROVIDERS`.
- SkillOps helpers: `skill_inventory()`, `parse_skill_frontmatter()`, `validate_eval_manifest()`, `skills_sync()`, `sync_skill_routes()`, and `init_skill_workspace()` keep skill auditing dependency-free and do not follow symlink targets.
- `claude_body()`: Claude Code wrapper that imports `AGENTS.md`.
- `classify_recreate()` and `apply_planned_writes()`: marker-first update planning and writes.
- `detect_agent()`: returns `(agent, matched_variable)`; exact-match detection only, never substring matching.

Keep the script dependency-free unless a new dependency provides a clear reliability benefit. The current script is intended to run with the system Python available in most agent sandboxes.

## Adding a Provider or Model Profile

Use this process for a new provider, host product, or model family such as `aider`, `qwen`, or `deepseek`.

1. Add a `PROVIDERS` entry with the normalized key, title, profile bullets, bridge files, and source URLs. Everything else (the `PROFILES` tuple, the generated registry, the profile file) derives from it.
2. List `detect_env` variables only after confirming them against a first-party source, and record the confirmation (variable, method, date) in `reports/provider-review-*.md`. Add the key to `DETECT_PRIORITY` when it has detection variables. Unconfirmed providers stay `detect_env: []` and are selected with `--agent <name>`.
3. Add or update bridge files only when the provider has a stable loading contract.
4. Update `PROVIDER_REGISTRY_REVIEWED` together with the provider-review report — never one without the other.
5. Update `references/provider-profiles.md` with profile intent and anti-patterns.
6. Update this guide if the provider needs a new category of behavior.
7. Regenerate `tests/golden/` and `examples/sample-output/`, and record the output change in `CHANGELOG.md`.
8. Run `scaffold` on a fixture repository twice: once to create files, once to confirm marker-based update.
9. Run `check` on the fixture repository.

Profile guidance should be operational. Good profile content says how the agent should work differently in this repository. Weak profile content repeats generic policy or praises a model.

## Customizing Generated Core Context

Change `core_body()` when a repository-wide rule should apply to all agents.

Good candidates:

- Source-of-truth documentation rules.
- Secret handling and logging boundaries.
- Validation expectations.
- Public/private documentation synchronization.
- Handoff or resume checkpoint expectations.

Poor candidates:

- Provider-specific tone.
- Task-specific implementation checklists.
- Large copied excerpts from existing docs.
- Facts that the script cannot infer safely.

When adding new inventory-derived fields, also update `inventory()` and keep the output bounded. Avoid scanning file contents by default; prefer filenames, manifests, and explicit docs unless the user asks for deeper analysis.

## Customizing Routing

Change `routing_body()` when agents need a clearer decision tree for what to read next.

Useful routes include:

- Code review.
- Feature implementation.
- Documentation updates.
- Security/privacy-sensitive changes.
- Frontend UI work.
- Release or CI triage.
- Repository-specific repeated workflows.

Do not route every task to every file. The goal is context efficiency.

## Creating Task Skills

Create `.agents/skills/<task>/SKILL.md` when a workflow is repeated and has task-specific procedure.

Recommended shape:

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

Task skills should reference core policy rather than duplicate it.

## Safety Model

Inventory must skip:

- `.env*`
- private keys and certificates
- files with `secret` or `token` in the name
- dependency caches
- build outputs
- local databases and raw logs unless explicitly requested

Generated context may mention that these categories are excluded. It must not include their contents.

If an extension needs to inspect sensitive files, make it an explicit user-approved mode with a narrow purpose and avoid writing raw values into context files.

## Validation Expectations

For changes to the skill:

1. Run script syntax validation:

```bash
python3 -c "from pathlib import Path; p=Path('scripts/agent_context.py'); compile(p.read_text(), str(p), 'exec')"
```

2. Create or reuse a small fixture repository with at least `README.md`, one manifest, one test file, and an existing `AGENTS.md`.
3. Run:

```bash
python3 scripts/agent_context.py inventory /path/to/fixture
python3 scripts/agent_context.py scaffold /path/to/fixture --agent codex
python3 scripts/agent_context.py check /path/to/fixture
python3 scripts/agent_context.py scaffold /path/to/fixture --agent claude
python3 scripts/agent_context.py check /path/to/fixture
```

4. Confirm the second scaffold updates existing generated blocks instead of appending duplicates.
5. Confirm hand-written text outside markers remains intact.
6. Confirm malformed marker pairs make `scaffold` fail without writing, and marker examples inside code fences are ignored.
7. Confirm clean git-tracked target files without generated markers are refused by default.
8. Confirm `--append-generated-block` preserves unmarked Markdown, appends exactly one managed block, and refuses non-Markdown targets.
9. Confirm generated-block updates that are not recoverable from git are snapshotted before that block is overwritten.

If your platform ships a skill validator (for example skill-creator's `quick_validate.py`), running it is a useful optional extra; no specific platform's validator is required.

The repeatable way to run the full validation locally is:

```bash
scripts/run_checks.sh
```

## Porting to Other Agent Platforms

The core pattern is platform-neutral. For other agents:

- Keep `AGENTS.md` as the universal entry point if the platform reads it.
- Add a platform-native entry file only when required, such as `CLAUDE.md`, `.cursorrules`, or an IDE-specific rule file. For Claude Code, prefer `CLAUDE.md` containing `@AGENTS.md` over duplicating instructions.
- Make that platform-native file point back to `.agents/core.md` and `.agents/routing.md`.
- Keep source-of-truth policy in `.agents/`, not in multiple platform files.

If a platform cannot follow references reliably, generate a compact platform entry file containing only the first-read list and the most important safety boundary.

## Distributing This Skill Itself

The skill is distributed as one folder that serves every platform:

- `SKILL.md` follows the Agent Skills convention (YAML frontmatter with `name` and `description`) shared by Codex and Claude Code, so a single file serves both. Keep the frontmatter description platform-neutral: name providers as examples, never as the subject of the trigger condition.
- `agents/openai.yaml` is the only platform-specific adapter file. Additional adapters must be additive files that other platforms ignore; never fork `SKILL.md` per platform.
- `scripts/agent_context.py` stays a single dependency-free file so that agents without a skill mechanism (and humans) can run it directly. Do not split it or add dependencies without a clear reliability win.
- The repository root carries no generated context files (`AGENTS.md`, `.agents/`, ...). Generated examples live under `examples/sample-output/` so skill installs stay clean.

## Bilingual Documentation Rule

English documentation is authoritative. Japanese companion files (`*.ja.md`) must be updated in the same commit as their English counterparts; when they disagree, trust the English version and fix the Japanese file.

## Versioning Guidance

When changing generation behavior, update this guide with:

- The new file or section contract.
- The migration behavior for existing repositories.
- Any compatibility risk for older generated `.agents/` directories.

Avoid silent breaking changes to marker names, path names, or profile keys. If a breaking change is necessary, add a migration command rather than changing `scaffold` semantics implicitly.
