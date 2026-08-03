# Upstream provenance

- Repository: https://github.com/ponponusa/agent-context-maintainer
- Imported commit: `a6d41e7ff6dd8f4595c772bdfb805051de369829`
- Imported on: 2026-08-03
- License: MIT; see `LICENSE` in this directory.

## Imported payload

This project-scoped installation contains the runtime and the documents referenced by `SKILL.md`:

- `SKILL.md` and `SKILL.ja.md`
- `agents/openai.yaml`
- `scripts/agent_context.py`
- `references/*.md`
- `reports/provider-review-2026-07.md`
- `LICENSE`

Upstream examples, tests, workflows, and development-only files are intentionally omitted so they do not appear as `narou-mod` documentation or tests during repository inventory.

## Update procedure

1. Resolve and review a specific upstream commit; do not vendor a moving branch.
2. Compare every imported path with that commit and review upstream `CHANGELOG.md`.
3. Update the payload and this file in the same change.
4. Run `python3 scripts/agent_context.py check <repo-root>` and the SkillOps checks documented in `SKILL.md`.
5. Confirm a second scaffold/sync run is idempotent before committing.

English upstream documentation is authoritative; Japanese companion files follow it.

## Local integration patch

`scripts/agent_context.py` carries two small idempotency fixes:

- Preserve the line boundary when a replaced managed block is followed by hand-written content, and preserve a final newline for a block at EOF. The pinned upstream implementation consumes the end-marker newline, which can concatenate the marker with the following heading or leave generated-only files without a newline.
- Treat an unchanged generated skill-route block as a no-op instead of rewriting `.agents/routing.md` on every `skills routes` run.

Keep these patches until upstream contains equivalent fixes, then remove them during a reviewed pin update.

## Known validation warnings

The pinned upstream payload is valid but currently reports these non-blocking SkillOps warnings:

- `missing-evals`: upstream does not ship `evals/evals.json`.
- `script-without-compatibility`: upstream frontmatter does not declare its Python compatibility field.
- `codex-metadata-unparsed`: SkillOps records the Codex adapter but does not parse its schema.

Keep these as upstream facts rather than patching the vendored `SKILL.md` locally. Re-evaluate them when updating the pinned commit.
