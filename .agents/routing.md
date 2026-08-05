# Agent Routing

Use this file to choose only the additional context needed for the current task.

<!-- agent-context-maintainer:begin -->
## Universal First Reads

- `AGENTS.md`
- `.agents/core.md`
- Matching provider profile in `.agents/profiles/`

## Task Routes

- Code review: inspect changed files first, then relevant tests and docs.
- Implementation: inspect manifests, existing patterns, and nearest tests before editing.
- Documentation: reconcile private planning docs with public docs when both exist.
- Security or privacy: read security guidance before changing storage, logging, sync, or agent-context behavior.
- Changing or adding custom subagent definitions: read the provider's native agents directory listed in your profile.
- New repeated workflow: create or update `.agents/skills/<task>/SKILL.md`.

## Detected Tests

- `lib/web/public/test/jquery.outerclick.html`
- `spec/data/convert_test/auto_indent/test_auto_indent.txt`
- `spec/data/convert_test/auto_join_bracket/test_auto_join_bracket.txt`
- `spec/data/convert_test/auto_join_line/test_auto_join_line.txt`
- `spec/data/convert_test/convert_numbers/test_convert_numbers.txt`
- `spec/data/convert_test/convert_page_break/test_convert_page_break.txt`
- `spec/data/convert_test/convert_prolonged_sound_mark_to_dash/test_convert_prolonged_sound_mark_to_dash.txt`
- `spec/data/convert_test/disable_alphabet_word_to_zenkaku/test_disable_alphabet_word_to_zenkaku.txt`
- `spec/data/convert_test/english/test_english.txt`
- `spec/data/convert_test/force_indent_special_chapter/test_force_indent_special_chapter.txt`
- `spec/data/convert_test/horizontal_ellipsis/test_horizontal_ellipsis.txt`
- `spec/data/convert_test/insert_separator/test_insert_separator.txt`
- `spec/data/convert_test/insert_separator_and_replace_txt/test_insert_separator_and_replace_txt.txt`
- `spec/data/convert_test/kanji_num/test_kanji_num.txt`
- `spec/data/convert_test/nonokagi/test_nonokagi.txt`
- `spec/data/convert_test/replace/test_replace.txt`
- `spec/data/convert_test/rome_num/test_rome_num.txt`
- `spec/data/convert_test/ruby/test_ruby.txt`
- `spec/data/convert_test/ruby_youon/test_ruby_youon.txt`
- `spec/data/convert_test/sesame/test_sesame.txt`
- `spec/data/convert_test/to_odd_leader/test_to_odd_leader.txt`

## Missing Context Rule

If required context is absent, state the gap clearly, make the safest local assumption, and avoid broad rewrites.
<!-- agent-context-maintainer:end -->
## Repository Task Routes

### Ruby core, CLI, download, and conversion

- Read the nearest implementation under `lib/` and its matching specs under `spec/`.
- CLI commands follow the patterns in `lib/cli/command/`; bootstrap work must also inspect `narou.rb`, `bin/narou-mod`, and `lib/loading/`.
- Novel download/conversion work usually spans `lib/narou/`, `lib/novel/`, `lib/conversion/`, `lib/ebook/`, and the matching fixture-backed specs.

### Supported sites and parsers

- Inspect `webnovel/`, `preset/parsers/`, `preset/parsers/legacy_archive/`, and `lib/narou/parsers/` before choosing the active definition path.
- When changing parser architecture, consult `docs/_tmp/html_parser_analysis.md` if the local documentation repository contains it; do not require that private plan for a narrow selector or fixture fix.
- Validate network-dependent behavior with fixtures first and keep adult/non-adult or legacy variants aligned when they share behavior.

### Sinatra Web UI and REST API

- Read `lib/web/appserver.rb` and the relevant modules under `lib/web/api/`, `lib/web/routes/`, `lib/web/helpers/`, `lib/web/workers/`, or `lib/web/server/`.
- API contract changes require `docs/openapi.yaml` and relevant `spec/web/` coverage. If present, `docs/_tmp/web_api_endpoints.md` is an unverified historical aid, not a contract source.
- Legacy Haml/static UI changes use `lib/web/views/` and `lib/web/public/`; do not apply frontend conventions there.

### Astro/Svelte frontend

- Read `frontend/AGENTS.md` before any file under `frontend/`.
- Backend integration changes usually require `frontend/src/lib/api.ts`, `frontend/src/lib/backend-config.ts`, `frontend/src/types/api.ts`, and the matching API endpoint/docs.
- UI behavior changes should inspect the nearest component/page and `frontend/e2e/` before adding a new pattern.

### Process management and local development

- Read `scripts/process_control.sh` and `scripts/process_control.ps1` as applicable to the host platform. Local documents such as `docs/_tmp/process_management.md` and `docs/_tmp/development_environment_setup.md` are unverified aids only.
- Treat port files, PID files, and logs as runtime output, not source.

### CI, dependency, and release work

- Read `.github/workflows/ci.yml`, both lockfiles, `narou-mod.gemspec`, `lib/core/version.rb`, and `CHANGELOG.md` as applicable.
- Separate local sandbox/tooling failures from regressions, and confirm remote CI before release promotion.
- For publishing, verify branch, worktree, remote, computed version/tag, and uploaded platform artifacts.

### Documentation

- Verify documentation claims against current code and manifests.
- Keep `docs/openapi.yaml` synchronized with the implemented API. Treat Markdown files in the independent local `docs/_tmp/` repository as unreviewed working material, not current documentation.
- Put new investigations, plans, design drafts, decision notes, and time-bound reports in `docs/_tmp/` and record them in its review index.
- Promote a Markdown document to tracked `docs/` only after checking it against current code, manifests, tests, and runtime behavior and updating public references.
- If private findings change public behavior or an accepted contract, promote only the verified conclusions into the relevant tracked documentation and leave the working notes private.

### Agent context

- Read `.agents/skills/agent-context-maintainer/SKILL.md` before changing `AGENTS.md`, provider bridges, `.agents/core.md`, `.agents/routing.md`, profiles, or project skills.
- Keep hand-written repository policy outside managed markers and let the project-scoped script own generated blocks.
- Update `.agents/skills/agent-context-maintainer/UPSTREAM.md` whenever the vendored upstream commit or payload changes.

## Provider Profile Selection

- Codex/OpenAI: `.agents/profiles/codex.md`
- Claude Code: `.agents/profiles/claude.md`
- Gemini CLI: `.agents/profiles/gemini.md`
- Cursor/IDE agents: `.agents/profiles/cursor.md`
- GitHub Copilot: `.agents/profiles/copilot.md`
- Antigravity: `.agents/profiles/antigravity.md`
- Unknown runtime: `.agents/profiles/generic.md`

## Missing Context Rule

If a referenced path is absent or code contradicts context, verify the nearest source and manifest, state the discrepancy, and avoid inventing policy. Update stale context when that reconciliation is part of the task.


## Skill Routes

<!-- agent-context-maintainer:skills-begin -->
- Agent context maintenance: read `.agents/skills/agent-context-maintainer/SKILL.md`.
<!-- agent-context-maintainer:skills-end -->
