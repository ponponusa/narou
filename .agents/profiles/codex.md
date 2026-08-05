# Codex Agent Profile

<!-- agent-context-maintainer:begin -->
## Codex Profile

- Active detected profile: no

## Behavior

- Read the repository before editing.
- Use scoped patches and preserve unrelated user changes.
- Run focused validation and report exact commands.
- Create durable repo-local artifacts for long-running work.
- Custom subagents may be defined in `.codex/agents/*.toml`; read them before changing delegation behavior. Do not treat `.codex/rules/` as instructions — it is an exec-policy allowlist.
<!-- agent-context-maintainer:end -->
