# Repository Guidelines

## Project Structure & Module Organization

- `lib/` holds Ruby sources: core logic in `lib/narou/`, web helpers in `lib/web/`, and CLI subcommands under `lib/command/`.
- `spec/` contains RSpec examples plus shared helpers in `spec/support/`.
- CLI entry point is `bin/narou-mod` (use this for development).
- Site settings, templates, and assets reside in `webnovel/`, `preset/`, and `template/`.
- CI and release automation are under `.circleci/` and `Rakefile` tasks.

## Build, Test, and Development Commands

- `bundle install`: install gem dependencies locally.
- `bundle exec ruby bin/narou-mod web`: boot the local web interface for manual checks.
- `bundle exec ruby bin/narou-mod download <novel_id>`: fetch source content for conversion experiments.
- `bundle exec rspec`: run the full test suite; scope to a file with `bundle exec rspec spec/downloader_spec.rb`.
- `bundle exec rubocop` (add `-A` to auto-correct): enforce Ruby style and catch regressions.
- `./scripts/process_control.sh --restart` (Unix) or `.\scripts\process_control.ps1 -Restart` (Windows): stop all running servers and restart them in the background.

## Coding Style & Naming Conventions

- Use Ruby two-space indentation, single quotes for simple strings, and snake_case for files and methods.
- Namespaces should follow `Narou::CamelCase` modules; mirror existing CLI subcommand patterns in `lib/command/`.
- Keep new files ASCII with `# frozen_string_literal: true` at the top when applicable.
- Run `bundle exec rubocop` and `bundle exec reek` before submitting changes.

## Testing Guidelines

- Write deterministic RSpec examples in `spec/`; name files `*_spec.rb` and group contexts clearly.
- Stub network or filesystem side effects; rely on fixtures in `spec/support/` when possible.
- Execute `bundle exec rspec` prior to review; add focused specs for new behaviour or bug fixes.

## Commit & Pull Request Guidelines

- Craft imperative commit subjects (e.g., `Add downloader retry logic`) and reference issues like `#123` when relevant.
- Update `ChangeLog.md` for user-facing changes and summarise scope, motivation, and test notes in PR descriptions.
- Attach screenshots or logs for web/UI work and call out migrations or breaking changes explicitly.

## Security & Configuration Tips

- Keep secrets out of the tree; validate new YAML configs in `webnovel/` before shipping.
- Follow UTF-8 defaults in entry scripts and ensure downloaded data is sanitised before conversion.

## Agent-Specific Instructions

- Keep edits minimal and scoped, favour incremental fixes over sweeping refactors.
- Respect existing public APIs and CLI behaviours; coordinate larger changes through issues first.
