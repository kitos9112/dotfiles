# Dotfiles Maintenance Normalization Design

## Context

This public chezmoi dotfiles repository uses `master` as its active branch. The
repo manages a root installer, chezmoi templates under `home/`, Renovate
automation, GitHub Actions smoke tests, and local helper tasks.

The first maintenance pass should be broader than a minimal cleanup, but it
should stay focused on repository reliability rather than rewriting personal
configuration. The tracked `.env` file is intentionally public-safe because it
contains pointers to 1Password items, not secret values. It must remain tracked.

The current acceptance matrix remains:

- AlmaLinux 9
- AlmaLinux 10
- Ubuntu 24.04
- Ubuntu 25.10

macOS remains covered by the temp-home GitHub Actions smoke test.

## Goals

- Make the chezmoi init/bootstrap path predictable and easier to test.
- Normalize machine-specific chezmoi data boundaries where scripts and templates
  already depend on computed values.
- Keep frequent Renovate checks while making the workflow and local dry-run path
  safer and clearer.
- Align workflow triggers and documentation around `master`.
- Preserve public-safety rules: do not print tokens, do not expose `.env`
  contents, and do not add secrets or confidential machine data.

## Non-Goals

- Migrate the repository from `master` to `main`.
- Remove or ignore the tracked `.env` file.
- Redesign shell, editor, terminal, or package preferences unrelated to init,
  Renovate, CI, or public-safety behavior.
- Expand the distro acceptance matrix beyond the current targets.
- Run mutating package-manager scripts during local smoke tests.

## Architecture

The root `install` script remains the public entry point and stays POSIX shell
compatible. It continues to support direct `curl | sh`, local clone execution,
and CI/test execution. Its contract should become explicit: environment
variables configure behavior, the script builds one `chezmoi init` command,
logs the resolved mode without exposing secrets, and retries only the final
init/apply command.

The chezmoi template layer keeps `home/.chezmoi.toml.tmpl` as the default data
source. Computed values used outside that template should be exported into
`[data]`. Machine-specific choices should keep current defaults, while allowing
local config overrides where this is clean and backwards-compatible.

Renovate remains split between GitHub Actions for scheduled execution and
`Taskfile.yaml` for local Docker dry-runs. Both should point at the same repo
configuration and avoid logging token material. Custom managers should be
readable, local to the repo, and matched to the files they update.

CI keeps the existing acceptance matrix and treats `master` as canonical.
Documentation should describe the same install and validation paths that CI
uses.

## Components

### Installer

`install` should:

- Keep `chezmoi` discovery and bootstrap behavior.
- Validate retry settings before use.
- Preserve support for `DOTFILES_SOURCE`, `DOTFILES_REPO`,
  `DOTFILES_ONE_SHOT`, `DOTFILES_CHEZMOI_INCLUDE`,
  `DOTFILES_CHEZMOI_EXCLUDE`, `DOTFILES_NO_TTY`, `DOTFILES_VERBOSE`, and
  `DOTFILES_DEBUG`.
- Make command assembly and logging easier to reason about.
- Avoid printing unrelated environment values or token-like data.
- Distinguish retry attempts from final failure.

### Chezmoi Data And Templates

`home/.chezmoi.toml.tmpl` should:

- Export computed values that other templates or scripts use, including
  `is_wsl`.
- Preserve existing default behavior for work/root machine inference.
- Add optional local override points only where they reduce brittle hostname or
  environment assumptions.
- Keep existing installs working without requiring new local config keys.

`home/.chezmoiexternal.yaml` and template helpers should:

- Keep `DOTFILES_TEST=true` fast and offline by skipping externals.
- Keep pinned or live dependency sources clear enough for Renovate to update.
- Avoid changing external download behavior unless needed for correctness.

### Renovate

Renovate changes should cover:

- `.github/renovate.json5`
- `.github/renovate/regexManagers.json5`
- `.github/workflows/renovate.yaml`
- `Taskfile.yaml`
- `tests/renovate-bot/local-config.js`

The design keeps frequent scheduled Renovate runs. The cleanup should make
dispatch variables map cleanly to Renovate environment values, keep local runs
dry-run by default, and remove any command that prints `GITHUB_TOKEN`.

Custom managers should update the intended chezmoi external and tool-version
sources. If a custom manager is only needed by this repo, local extension should
be preferred over a self-reference through GitHub when practical.

### CI And Documentation

Workflow and documentation changes should:

- Treat `master` as the active branch in triggers and defaults.
- Keep the current acceptance-test matrix.
- Keep README install snippets and validation commands consistent with actual
  workflow behavior.
- Document that `.env` is safe tracked pointer data, not a secret container.

## Behavior

### Install Flow

1. The installer finds an existing `chezmoi` binary or installs it into
   `~/.local/bin`.
2. `DOTFILES_SOURCE` wins when set.
3. Local repo execution uses `--source`.
4. Remote initialization uses `DOTFILES_REPO` when set, otherwise the default
   GitHub repository.
5. Documented `DOTFILES_*` flags are translated into `chezmoi init` arguments.
6. The script logs source and mode decisions without printing secrets.
7. The resolved `chezmoi init` command is retried according to validated retry
   settings.

### Template Flow

1. `home/.chezmoi.toml.tmpl` computes defaults from OS, hostname, and
   environment.
2. Values consumed by other templates/scripts are exported into `[data]`.
3. Optional local config can override brittle machine-specific decisions.
4. `DOTFILES_TEST=true` continues to avoid external downloads and package
   manager side effects.

### Renovate Flow

1. GitHub Actions runs Renovate frequently using the repo config file.
2. Local `task run-renovate` runs a dry-run against the same config.
3. Local Renovate execution requires a token but never echoes it.
4. Regex managers update intended chezmoi external/tool-version sources.
5. Automerge remains limited to safe update types unless changed explicitly in a
   later design.

### CI And Docs Flow

1. Workflows trigger for `master`.
2. README and workflow matrix names stay aligned.
3. Temp-home chezmoi smoke checks remain the canonical local reproduction path.
4. `.env` remains tracked and unprinted.

## Error Handling And Safety

The installer should fail early for invalid retry settings and for missing
`curl`/`wget` when `chezmoi` must be installed. Retry messages should identify
the failed attempt and final failure without hiding useful context.

Template changes should preserve current defaults. New local overrides must be
optional. Test mode should keep avoiding external downloads and mutating
package-manager scripts.

Renovate local execution should require `GITHUB_TOKEN` but never print it. Dry
run remains the local default. Workflow dispatch inputs should avoid ambiguous
behavior.

Public-safety rules for this pass:

- Do not remove `.env`.
- Do not print `.env`, `GITHUB_TOKEN`, or other token-like values.
- Do not add secrets or confidential machine data.
- Keep changes scoped to bootstrap, data normalization, Renovate, CI, docs, and
  validation.

## Testing

Primary validation should include:

- `uvx pre-commit run --all-files` when practical.
- Renovate config validation through the existing pre-commit hook or a local
  Renovate dry-run.
- Temp-home `chezmoi init --apply --source "$(pwd)" --exclude scripts --no-tty`
  with `DOTFILES_TEST=true`.
- Temp-home `chezmoi verify --source "$(pwd)" --exclude scripts --no-tty` with
  the same environment.
- A root installer smoke test in a temp home using `DOTFILES_SOURCE="$(pwd)"`,
  `DOTFILES_TEST=true`, `DOTFILES_NO_TTY=true`, and
  `DOTFILES_CHEZMOI_EXCLUDE=scripts`.

If full pre-commit or Docker validation is too slow locally, the implementation
must still run the temp-home chezmoi smoke checks and report any skipped checks.

## Acceptance Criteria

- The root installer behavior is documented by implementation and README, with
  clearer validation and failure paths.
- `is_wsl` and any other cross-template computed values used by scripts are
  available through chezmoi data.
- Local Renovate dry-run no longer prints `GITHUB_TOKEN`.
- Renovate GitHub Action keeps frequent scheduling and uses clear dispatch/env
  behavior.
- Workflow triggers and docs consistently treat `master` as active.
- `.env` remains tracked, unprinted, and documented as public-safe pointer data.
- Current acceptance-test matrix remains unchanged.
- Temp-home chezmoi init and verify checks pass.
