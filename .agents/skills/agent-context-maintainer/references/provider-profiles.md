# Provider Profiles

Use provider profiles to adapt style and tool behavior, not to fork policy.

The canonical profile wording lives in the `PROVIDERS` dict in `scripts/agent_context.py`; the generated `.agents/profiles/*.md` files are rendered from it. This document explains the intent behind each profile and the anti-patterns to avoid — it deliberately paraphrases rather than repeats the generated bullets, so the two never need to be kept word-for-word in sync.

## Codex / OpenAI

Emphasize:

- Inspecting the repository before editing.
- Small, scoped patches that leave unrelated user changes untouched.
- Focused validation, reporting the exact commands that were run.
- Durable repo-local artifacts for long-running work.
- Awareness of native custom subagents (`.codex/agents/*.toml`) before changing delegation behavior.

Avoid:

- Repeating the full `core.md`.
- Long speculative design essays when the task is implementable.
- Treating `.codex/rules/` as instruction context; it is an exec-policy allowlist.

## Claude

Emphasize:

- Strong long-form reasoning for design reviews and cross-document reconciliation.
- Explicit assumptions and open questions.
- Careful handling of architectural tradeoffs.
- Awareness of native custom subagents (`.claude/agents/*.md`) before changing delegation behavior.

Avoid:

- Letting analysis replace concrete file updates when the user asked for implementation.

## Gemini

Emphasize:

- Broad context synthesis across many files.
- Fast inventory of docs, manifests, and generated artifacts.
- Clear source attribution for repository facts.
- Awareness of native custom subagents (`.gemini/agents/*.md`) before changing delegation behavior.

Avoid:

- Treating broad recall as verified current state without checking local files.

## Cursor / IDE Agents

Emphasize:

- Local edit locality.
- File and symbol navigation.
- Keeping changes small enough for IDE review.
- Avoiding unrelated formatting churn.

Avoid:

- Hidden bulk rewrites across many files without a task route.

## GitHub Copilot

Emphasize:

- Concise repository-wide guidance that reduces cloud-agent exploration.
- Keeping `.github/copilot-instructions.md` as a bridge back to `AGENTS.md`.
- Using `.agents/profiles/copilot.md` and routed skills for provider-specific workflow details.
- Awareness of native custom agents (`.github/agents/*.agent.md`) before changing delegation behavior.

Avoid:

- Copying all shared policy into `.github/copilot-instructions.md`.
- Adding task-specific or path-specific rules to the repository-wide bridge when a routed skill or `.github/instructions/*.instructions.md` file would be narrower.

## Antigravity

Emphasize:

- Verifiable artifacts such as plans, command results, screenshots, browser recordings, or review notes when they help user trust.
- Clear user-visible intent before broad autonomous edits or risky commands.
- Shared `AGENTS.md` policy plus Gemini-compatible bridge files where available.

Avoid:

- Treating autonomous execution as permission to skip repository safety rules.
- Duplicating all Gemini guidance in the Antigravity profile before the provider contract is confirmed.

## Unknown Agent

Use the generic profile:

- Read `AGENTS.md`, `.agents/core.md`, and `.agents/routing.md`.
- Identify your runtime and tools.
- If provider-specific behavior is unavailable, follow core rules and ask only when a missing decision would be risky.
