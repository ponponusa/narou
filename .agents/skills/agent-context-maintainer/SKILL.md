---
name: agent-context-maintainer
description: Create, update, and validate repository-local AI agent context files such as AGENTS.md, .agents/core.md, .agents/routing.md, provider-specific profiles, and task SKILL.md routing. Use when an AI coding agent (Codex, Claude Code, Gemini, Copilot, Cursor, or others) is asked to make AGENTS.md or SKILL instructions self-maintaining, inspect the current path and generate optimal agent context for it, or keep agent instructions synchronized with the repository's actual structure.
---

# Agent Context Maintainer

## Overview

Maintain a small, layered agent-context system for the current repository: a universal entry point, shared rules, provider-specific profiles, and task-specific skill routing. Prefer safe incremental updates over replacing human-authored instructions.

## Workflow

1. Treat the current working directory, or the user-specified path, as the context root. Do not scan above it unless the user explicitly asks.
2. Identify the active agent runtime when possible: Codex, Claude Code, Gemini, Copilot, Cursor, Antigravity, or unknown. If unknown, create generic profiles and make the user-facing routing explicit.
3. Inventory the path with file names, manifests, existing docs, tests, and build files. Do not read secrets, credentials, private keys, `.env*`, local databases, dependency caches, or generated build output.
4. Read existing `AGENTS.md`, `.agents/**`, and relevant `SKILL.md` files before editing. Preserve human-written rules and update only the smallest needed sections.
5. Create or refresh this structure:

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

6. Keep `AGENTS.md` as a thin entry point. Generate `CLAUDE.md` as a Claude Code entry file that imports `AGENTS.md` with `@AGENTS.md`.
7. Put durable cross-agent rules in `.agents/core.md`, provider/model differences in `.agents/profiles/*.md`, and task selection rules in `.agents/routing.md`.
8. Validate references and report what changed, what was preserved, and what still needs human confirmation.

## Scripted Scaffold

Use `scripts/agent_context.py` for repeatable setup and validation:

```bash
python3 scripts/agent_context.py providers
python3 scripts/agent_context.py inventory /path/to/repo
python3 scripts/agent_context.py scaffold /path/to/repo --agent auto
python3 scripts/agent_context.py check /path/to/repo
```

Run `providers` to list supported providers, their bridge files, and whether they can be auto-detected. Run `inventory` before manual edits when the repository shape is unclear. Use `inventory --json --explain-skips` when skip reasons matter. Run `scaffold` to create missing files or refresh generated blocks; `--agent auto` detects the runtime from confirmed environment variables and reports what it found, and `--agent <name>` always overrides detection. Run `check` before finishing.

## Update Rules

- Update marker-first by default: replace only generated blocks and preserve hand-written content outside markers.
- Treat markers as owned only when they are standalone lines outside Markdown code fences.
- Refuse existing unmarked Markdown targets by default.
- Use `--append-generated-block` to preserve an unmarked Markdown target and append a managed block.
- Use `--force-recreate` only when the user explicitly accepts replacing an unmarked scaffold target.
- Use `--dry-run` to preview planned writes.
- If a generated-block update is not recoverable from git, snapshot the previous content before overwriting that block.
- Merge existing `.gemini/settings.json` objects by adding required bridge keys and preserving other settings.
- Prefer generated-block updates delimited by `<!-- agent-context-maintainer:begin -->` and `<!-- agent-context-maintainer:end -->`.
- Do not copy raw secrets, credentials, tokens, private URLs, personal data, chat transcripts, or raw logs into context files.
- Mention sensitive boundaries as policy, not as examples containing real data.
- Keep provider profiles short. Put only differences that help that agent behave better.
- Keep task skills focused on triggering and procedure. Avoid duplicating core repository policy in every skill.
- If a private planning document changes a public-facing rule, call out the sync need rather than silently making broad edits.

## Reference Files

Read these only when needed:

- `references/context-file-contract.md`: required files, section ownership, and update boundaries.
- `references/provider-profiles.md`: what belongs in Codex, Claude, Gemini, Cursor, and generic profiles.
- `references/inventory-heuristics.md`: what to inspect, what to ignore, and how to summarize a repository safely.
- `references/extension-guide.md`: product intent, generation rules, and how to extend the skill for new agents or models.
- Japanese companion docs use the same names with `.ja.md`.
