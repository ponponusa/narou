# Provider Review — 2026-07

This report records platform facts used by `agent-context-maintainer`, with the
confirmation method and date for each. Per the redesign plan, only facts recorded
here may appear in README installation instructions or in the `detect_env` lists
in `scripts/agent_context.py`. Update this report whenever
`PROVIDER_REGISTRY_REVIEWED` changes.

## Skill installation paths

| Platform | Fact | Confirmed | Method |
|----------|------|-----------|--------|
| Codex | Skills are discovered from `.agents/skills` at repo scope (`$REPO_ROOT/.agents/skills`, `$CWD/../.agents/skills`), user scope (`~/.agents/skills`), admin (`/etc/codex/skills`), and system scopes. `~/.codex/` holds configuration (`config.toml`), not skills. | 2026-07-02 | Fetched https://developers.openai.com/codex/skills during adversarial review R1; consistent with the 2026-06-17 review report. |
| Claude Code | Personal skills live in `~/.claude/skills/<name>/SKILL.md`; project skills in `.claude/skills/<name>/SKILL.md`. Frontmatter `name` is optional and defaults to the directory name. Combined description text is truncated at 1,536 characters in skill listings. | 2026-07-02 | Fetched https://code.claude.com/docs/en/skills during adversarial review R2. |

## Runtime detection environment variables

Only variables listed as **confirmed** are used in `detect_env`. Candidates stay
out of the code until confirmed here.

| Provider | Variable | Status | Evidence |
|----------|----------|--------|----------|
| claude | `CLAUDECODE` | Confirmed 2026-07-02 | Present in a live Claude Code session environment (macOS, checked with `env`). |
| claude | `CLAUDE_CODE_ENTRYPOINT` | Confirmed 2026-07-02 | Same live-session check. |
| codex | `CODEX_SANDBOX` | Confirmed 2026-07-02 | openai/codex source, `codex-rs/core/src/spawn.rs`: "Should be set when the process is spawned under a sandbox. Currently, the value is 'seatbelt' for macOS". **Conditional**: only set when a sandbox is active. |
| codex | `CODEX_SANDBOX_NETWORK_DISABLED` | Confirmed 2026-07-02 | openai/codex source, `codex-rs/core/src/spawn.rs`: set to `"1"` when the process was spawned by Codex as part of a shell tool call and network access is restricted. **Conditional**: only set when the network sandbox is restricted. |
| gemini | `GEMINI_CLI` | Confirmed 2026-07-02 | google-gemini/gemini-cli `docs/tools/shell.md`: "When `run_shell_command` executes a command, it sets the `GEMINI_CLI=1` environment variable in the subprocess's environment. This allows scripts or tools to detect if they are being run from within Gemini CLI." |
| cursor | `CURSOR_AGENT` | Candidate (unconfirmed) | Not adopted. `CURSOR_TRACE_ID` is believed to be set by Cursor terminals generally (unconfirmed), so it must not be used as an agent signal either way. |
| copilot | (none) | Rejected | `COPILOT_OTEL_FILE_EXPORTER_PATH` was observed in a live **non-Copilot** (Claude Code) session on 2026-07-02, so `COPILOT`-prefixed variables are not a reliable signal. No exact-match candidate is known. |
| antigravity | (none) | No candidate | No stable environment signal identified yet. |

Notes:

- The Codex variables are conditional on sandboxing, so Codex sessions running
  without a sandbox fall back to `generic`. README documents `--agent codex` as
  the explicit override.
- Detection is best-effort by design. `--agent <name>` always wins, and the
  fallback is `generic` with a hint, never a guess.

## Follow-ups

- **Inventory scope of `.agents/skills`**: when this skill is installed at repo
  scope (`.agents/skills/agent-context-maintainer/`), its bundled files
  (`examples/`, `tests/`) show up in the target repository's inventory as
  docs/tests. Excluding `.agents/skills` from docs/tests detection would change
  generated output for existing repositories, so it was deliberately left out of
  the generic redesign (see plan §1 non-goals). Revisit in a future release
  together with a golden-file update.
- **Cursor / Antigravity detection**: adopt exact-match variables once a
  first-party source documents them, then update `detect_env`, this report, and
  `PROVIDER_REGISTRY_REVIEWED` together.
