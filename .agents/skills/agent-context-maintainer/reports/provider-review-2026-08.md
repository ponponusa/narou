# Provider Review — 2026-08

This report records platform facts used by `agent-context-maintainer`, with the
confirmation method and date for each. Only facts recorded here may appear in
README installation instructions, in the `detect_env` lists, or as lint
thresholds in `scripts/agent_context.py`. Update this report whenever
`PROVIDER_REGISTRY_REVIEWED` changes.

All facts below were confirmed on 2026-08-03 during the `.agents/` structure
requirements review (rev2–rev4 adversarial passes) by fetching the cited
first-party sources.

## Custom subagent locations

| Platform | Fact | Confirmed | Method |
|----------|------|-----------|--------|
| Codex | Custom subagents are defined in `~/.codex/agents/*.toml` (personal) and `<repo>/.codex/agents/*.toml` (project). TOML requires `name` / `description` / `developer_instructions`; optional `model` / `model_reasoning_effort` / `sandbox_mode` / `mcp_servers` / `skills.config`. Built-ins (`default` / `worker` / `explorer`) can be overridden by same-name definitions. **Configuration resolution is field-dependent**: when the custom file sets `model` / `model_reasoning_effort`, the file value overrides an explicit spawn value; fields the file does not set resolve independently as spawn value → `config.toml` `[agents]` default → parent session value. Known issue: repo-local custom agents cannot be invoked by name from tool-backed sessions (openai/codex#15250); the feature is still in flux. | 2026-08-03 | Fetched https://learn.chatgpt.com/docs/agent-configuration/subagents ; issue tracked at https://github.com/openai/codex/issues/15250 |
| Claude Code | Custom subagents are defined in `.claude/agents/*.md` (project) and `~/.claude/agents/*.md` (user); Markdown with YAML frontmatter (`name` / `description` / `tools` / `model`, and more). The interactive `/agents` wizard was removed in v2.1.198; direct file editing is the supported path. | 2026-08-03 | Fetched https://code.claude.com/docs/en/sub-agents |
| Gemini CLI | Custom subagents are defined in `.gemini/agents/*.md` (project) and `~/.gemini/agents/*.md` (user); Markdown with YAML frontmatter, required `name` / `description`, optional `kind` / `tools` / `model` / `temperature` / `max_turns` / `timeout_mins` / `mcpServers`. The body becomes the system prompt. | 2026-08-03 | Fetched https://github.com/google-gemini/gemini-cli/blob/main/docs/core/subagents.md |
| Copilot | Custom agents are defined in the repository at `.github/agents/*.agent.md` (org / enterprise scope uses a root-level `agents/` directory); Markdown with YAML frontmatter (`name` defaults to the file name, `description` required, plus `tools` / `mcp-servers` / `model` / `target`). Body is limited to 30,000 characters. | 2026-08-03 | Fetched https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/create-custom-agents |

Note: no platform reads a shared `.agents/agents/` directory; the four native
locations above are provider-specific. Three of the four share the
Markdown + YAML frontmatter shape, but `tools` / `model` vocabularies are
mutually incompatible (see the Copilot tools/model reference:
https://docs.github.com/en/copilot/reference/custom-agents-configuration ).

## Path-scoped instruction rules

| Platform | Fact | Confirmed | Method |
|----------|------|-----------|--------|
| Claude Code | `.claude/rules/*.md` (project) and `~/.claude/rules/` (user) hold instruction rules; recursive discovery with subdirectories. Frontmatter `paths:` (glob, brace expansion) makes a rule conditional on matching files; rules without `paths` load always, like `.claude/CLAUDE.md`. Symlink sharing across projects is officially supported. | 2026-08-03 | Fetched https://code.claude.com/docs/en/memory |
| Copilot | `.github/instructions/NAME.instructions.md` with frontmatter `applyTo:` (glob, `"**/*.ts,**/*.tsx"` form) scopes instructions to paths; `excludeAgent` can exclude code-review or cloud-agent consumers. Repository-wide guidance stays in `.github/copilot-instructions.md`. Nested `AGENTS.md` files are also read (nearest wins; outside the workspace root is off by default in VS Code). | 2026-08-03 | Fetched https://docs.github.com/en/copilot/how-tos/configure-custom-instructions-in-your-ide/add-repository-instructions-in-your-ide |
| Cursor | `.cursor/rules/*.mdc` holds path-scoped rules in Cursor's own `.mdc` format. | 2026-08-03 | https://docs.cursor.com/context/rules (same URL already recorded in `PROVIDERS`) |
| Codex | **`.codex/rules/` is not an instruction-rule mechanism.** `~/.codex/rules/*.rules` and `<repo>/.codex/rules/` (project side only when trusted) contain an exec-policy: an allowlist for running commands outside the sandbox. Experimental. Do not bridge instruction content to it. | 2026-08-03 | Fetched https://developers.openai.com/codex/rules and https://developers.openai.com/codex/exec-policy |

## Skill listing budgets and truncation

| Platform | Fact | Confirmed | Method |
|----------|------|-----------|--------|
| Codex | The **entire skill listing** (names, descriptions, and paths together) is truncated at 2% of the model context window. **8,000 characters is the fallback budget used only when the context window is unknown.** Static lint cannot know the real window, so any repository-side check against 8,000 characters is a fallback-level estimate and must say so. | 2026-08-03 | Fetched https://learn.chatgpt.com/docs/build-skills |
| Claude Code | Truncation at 1,536 characters is **per skill entry**: for each listed skill, the combined `description` + `when_to_use` text is truncated at 1,536 characters (configurable via `skillListingMaxDescChars`). The listing-wide budget is separate and user-configured: `skillListingBudgetFraction` (for example 0.02 = 2%) or `SLASH_COMMAND_TOOL_CHAR_BUDGET` (fixed character count); user-configured budgets are not lint targets. | 2026-08-03 | Fetched https://code.claude.com/docs/en/skills |

Clarification of the 2026-07 report: the sentence "Combined description text is
truncated at 1,536 characters in skill listings" was ambiguous about scope. The
limit is per skill entry (`description` + `when_to_use` combined), not a total
across all skills. The 2026-07 report is a historical record and is not being
rewritten; this report supersedes it on that point.

These two facts are the sources for the `MAX_SKILL_LISTING_ENTRY_CHARS` (1,536)
and `CODEX_LISTING_FALLBACK_BUDGET_CHARS` (8,000) constants in
`scripts/agent_context.py`. Re-confirm them here before changing either
constant.

## Codex skill adapter `agents/openai.yaml` schema

| Fact | Confirmed | Method |
|------|-----------|--------|
| The optional per-skill adapter `agents/openai.yaml` carries `interface.display_name`, `interface.short_description`, `interface.icon_small`, `interface.icon_large`, `interface.brand_color`, `interface.default_prompt`, `policy.allow_implicit_invocation`, and `dependencies.tools` (a list of objects). Other platforms ignore the file. | 2026-08-03 | Fetched https://learn.chatgpt.com/docs/build-skills |

## Documentation migration note

`developers.openai.com/codex/*` skill documentation moved to
`learn.chatgpt.com/docs/*` with a 308 Permanent Redirect (confirmed 2026-08-03
for `/codex/skills` → `/docs/build-skills`). The current `PROVIDERS` registry
and generated output already use `https://agents.md/` for Codex, so **no code or
golden file contains a pre-migration URL**; the only impact is that new source
citations (this report and future `source_urls` additions) use the
`learn.chatgpt.com` addresses. The 2026-07 report's `developers.openai.com`
citations remain valid as historical evidence. The Codex rules / exec-policy
pages had not migrated as of 2026-08-03 and are cited at their
`developers.openai.com` addresses.

## Follow-ups

- **Subagent source URLs in `PROVIDERS`** — done 2026-08-04: the four subagent
  documentation URLs above were added to `PROVIDERS` `source_urls`, the
  codex / claude / gemini / copilot profile bullets now point to the native
  agents directories (with the exec-policy caution for `.codex/rules/`), and
  `.agents/routing.md` gained a subagent-definition route.
  `PROVIDER_REGISTRY_REVIEWED` was re-confirmed at `2026-08-04` together with
  this change. Native directories are mentioned conditionally ("may be
  defined"); the tool does not create or existence-check them.
- **Nested AGENTS.md (monorepo, nearest wins)**: agents.md and Copilot both
  read nested `AGENTS.md` files; this tool assumes a single root `AGENTS.md`.
  Backlog, revisit with a golden-file update.
- **Codex subagent spec stability**: re-check openai/codex#15250 before any
  `.agents/agents` bridge work (AgentOps entry criteria).
