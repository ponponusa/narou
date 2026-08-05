# Context File Contract

## File Roles

`AGENTS.md` is the entry point. Keep it brief and point agents to `.agents/core.md`, `.agents/routing.md`, and the matching provider profile.

`CLAUDE.md` is the Claude Code entry point. Create it as a thin wrapper that imports the shared entry point with `@AGENTS.md`, then add only Claude-specific notes below that import.

`GEMINI.md` is the Gemini CLI bridge. Keep it brief and point back to `AGENTS.md` plus `.agents/profiles/gemini.md`. Use `.gemini/settings.json` for Gemini CLI settings such as accepted context file names.

`.github/copilot-instructions.md` is the GitHub Copilot repository-wide bridge. Keep it concise and point back to `AGENTS.md` plus `.agents/profiles/copilot.md`; do not duplicate shared policy there.

Do not put Claude import syntax or Claude-specific profile paths in `AGENTS.md`; keep those in `CLAUDE.md`.

`.agents/core.md` contains cross-agent rules: repo summary, safety boundaries, verification policy, documentation sync, editing norms, and handoff expectations.

`.agents/routing.md` maps tasks to additional files or skills. It should answer "what should I read next for this task?"

`.agents/profiles/*.md` contains provider-specific behavior. It should not repeat the entire core policy.

`.agents/provider-registry.yaml` records supported providers, bridge files, profile paths, source URLs, and the last review date. Use YAML comment markers for generated registry content.

`.agents/skills/*/SKILL.md` contains task-specific procedures. Use it when a repeated workflow deserves a focused trigger and checklist.

### Role separation: core, rules, skills

Choose the layer by scope and trigger:

- Policy that applies to **every agent, loaded at all times** belongs in `.agents/core.md`.
- Policy that should apply **only when specific paths are touched** belongs in a path-scoped rules layer. This tool does not generate one yet: a shared `.agents/rules/` source is **future/planned** (see the Review Rule below — never reference it as an existing path). Until it exists, keep path-conditional policy in `.agents/core.md` or route it per task via `.agents/routing.md`. Providers with native path-scoped rule mechanisms load those independently of this tool.
- **Procedures for repeated tasks** belong in `.agents/skills/*/SKILL.md`, not in core policy.

Codex's `.codex/rules/` directory is an exec-policy allowlist for running commands outside the sandbox, not instruction context; it is outside this tool's management scope and is not a rules layer in the sense above.

## Generated Blocks

Generated content should live between:

```md
<!-- agent-context-maintainer:begin -->
...
<!-- agent-context-maintainer:end -->
```

Agents may replace only the text inside the markers unless the user explicitly requests a broader rewrite. A managed marker must appear as its own line outside Markdown code fences; marker examples inside fenced code blocks are documentation, not owned content.

If marker counts are mismatched, duplicated, or ordered incorrectly, agents must stop and ask for repair instead of appending or replacing content.

For scaffolded Markdown targets, the implementation is marker-first. If a generated block exists, replace only that block and preserve all content outside it, even when the file is clean in git. If no generated marker exists, refuse by default. Use `--append-generated-block` to add a managed block to an unmarked Markdown file, or `--force-recreate` to replace an unmarked scaffold target. Before overwriting generated-block changes that are not recoverable from git, save a snapshot under `.agents/snapshots/agent-context-maintainer/`.

JSON targets such as `.gemini/settings.json` cannot carry comments safely. Create them when missing, merge required bridge keys into an existing JSON object while preserving other settings, leave identical files unchanged, and require `--force-recreate` only when the existing JSON cannot be safely parsed or merged.

## Minimum AGENTS.md

```md
# Agent Instructions

Always read:

1. `.agents/core.md`
2. `.agents/routing.md`
3. The matching provider profile in `.agents/profiles/`; if unsure, read `.agents/profiles/generic.md`

If a task matches a routed skill, read that `SKILL.md` before editing.
```

## Minimum CLAUDE.md

```md
@AGENTS.md

## Claude Code

Use `AGENTS.md` as the shared source of truth for repository instructions. For Claude-specific behavior, also follow `.agents/profiles/claude.md` when present.
```

## Minimum GEMINI.md

```md
# Gemini CLI Instructions

Use `AGENTS.md` as the shared source of truth for repository instructions. Also follow `.agents/profiles/gemini.md` when present.
```

## Minimum GitHub Copilot Instructions

```md
# GitHub Copilot Instructions

Use `AGENTS.md` as the shared source of truth for repository instructions. Also follow `.agents/profiles/copilot.md` when present.
```

## Minimum Core Sections

- Repository Snapshot
- Context Boundaries
- Safety and Secrets
- Editing Rules
- Validation
- Handoff Notes

## Minimum Routing Sections

- Universal First Reads
- Task Routes
- Provider Profile Selection
- Missing Context Rule

## Review Rule

Before finishing, check that every referenced file exists or is explicitly marked as future/planned. Do not leave broken local paths in `AGENTS.md`.
