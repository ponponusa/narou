# Repository Guidelines

## Project Structure & Module Organization
- `lib/` – Ruby sources (core under `lib/narou/*.rb`, web under `lib/web/*`, CLI subcommands in `lib/command/*`).
- `spec/` – RSpec tests (`*_spec.rb`), helpers in `spec/support/`.
- `bin/narou` / `narou.rb` – CLI entry points for local development.
- `webnovel/` – site configuration YAMLs.
- `preset/`, `template/` – conversion templates and assets.
- `.circleci/` – CI configuration.

## Build, Test, and Development Commands
- Setup: `bundle install` – install Ruby gem dependencies.
- Run CLI (local): `bundle exec ruby narou.rb <command>` (e.g., `web`, `download`, `convert`).
- Tests: `bundle exec rspec` or `bundle exec rake spec` – run the test suite.
- Lint (Ruby): `bundle exec rubocop` (auto-fix: `-A`). Smells: `bundle exec reek`.
- Lint (templates/styles when edited): `bundle exec haml-lint`, `bundle exec scss-lint`.
- Build gem: `bundle exec rake build` (release: `bundle exec rake release`).

## Coding Style & Naming Conventions
- Ruby 2-space indentation; keep `# frozen_string_literal: true` in new files.
- Prefer single quotes for simple strings; snake_case for files/methods; CamelCase for classes/modules under the `Narou` namespace.
- Follow cops defined in `.rubocop.yml`; do not reformat unrelated code.
- Place new CLI subcommands in `lib/command/<name>.rb` mirroring existing patterns.

## Testing Guidelines
- Framework: RSpec. Add tests under `spec/` with filenames `*_spec.rb` and descriptive `describe`/`context` blocks.
- Keep tests deterministic; avoid network I/O—stub external calls.
- Run full suite with `bundle exec rspec`; target a file during TDD, e.g., `bundle exec rspec spec/downloader_spec.rb`.

## Commit & Pull Request Guidelines
- Commits: concise imperative subject, optional body for rationale; reference issues (e.g., `#123`). Update `ChangeLog.md` for user-facing changes.
- PRs: include summary, motivation, scope of change, test notes, and screenshots for web/UI impacts. Link related issues and note migration steps if any.

## Security & Configuration Tips
- Use UTF-8 consistently (as enforced in entry script). Do not commit secrets or tokens.
- Validate site YAMLs in `webnovel/` and include minimal tests for new formats.

## Agent-Specific Instructions
- Keep changes minimal and scoped; follow linters before proposing large refactors. Respect existing public APIs and command behaviors.
