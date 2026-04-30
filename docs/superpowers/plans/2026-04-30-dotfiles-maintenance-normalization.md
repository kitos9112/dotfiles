# Dotfiles Maintenance Normalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the dotfiles bootstrap, chezmoi data, Renovate automation, CI branch defaults, and public-safety documentation predictable and validated.

**Architecture:** Keep the root `install` script as the single bootstrap entry point, normalize computed chezmoi data in `home/.chezmoi.toml.tmpl`, and keep Renovate split between GitHub Actions and a local Taskfile dry-run. Treat `master` as canonical, leave `.env` tracked, and make validation pass through `uvx pre-commit` plus temp-home chezmoi smoke tests.

**Tech Stack:** POSIX shell, chezmoi templates, JSON5 Renovate config, GitHub Actions YAML, Taskfile v3, pre-commit via `uvx`.

---

## File Structure

- Modify `.pre-commit-config.yaml`: fix the `Lucas-C/pre-commit-hooks` tag so validation can run.
- Modify `install`: validate retry settings, improve command assembly logging, and avoid printing raw init arguments that may contain token-like repository URLs.
- Modify `home/.chezmoi.toml.tmpl`: export `is_wsl` and add explicit environment override points for root/work inference.
- Modify `Taskfile.yaml`: remove `GITHUB_TOKEN` echoing and keep local Renovate dry-runs explicit.
- Modify `tests/renovate-bot/local-config.js`: align the local self-hosted Renovate config with repo bot identity and safe dry-run use.
- Modify `.github/workflows/renovate.yaml`: keep frequent scheduling, use `master`, and map dispatch inputs to Renovate environment variables.
- Modify `.github/renovate.json5`: embed custom managers directly in the repo config and remove the self-referential preset extension.
- Delete `.github/renovate/regexManagers.json5`: remove the now-duplicated custom manager preset file after embedding its content.
- Modify `.github/workflows/linters.yaml`: treat `master` as the default branch.
- Modify `README.md`: document tracked `.env` safety, installer environment flags, `master`, and validation commands.

## Task 1: Restore Pre-Commit Baseline

**Files:**

- Modify: `.pre-commit-config.yaml`

- [ ] **Step 1: Fix the `Lucas-C/pre-commit-hooks` tag**

In `.pre-commit-config.yaml`, replace:

```yaml
  - repo: https://github.com/Lucas-C/pre-commit-hooks
    rev: 1.5.6
```

with:

```yaml
  - repo: https://github.com/Lucas-C/pre-commit-hooks
    rev: v1.5.6
```

- [ ] **Step 2: Verify the upstream tag exists**

Run:

```bash
git ls-remote --tags https://github.com/Lucas-C/pre-commit-hooks.git 'refs/tags/v1.5.6'
```

Expected output includes:

```text
refs/tags/v1.5.6
```

- [ ] **Step 3: Run the previously blocked hook**

Run:

```bash
uvx pre-commit run forbid-crlf --files README.md
```

Expected: the hook initializes successfully and reports `Passed`.

- [ ] **Step 4: Commit**

Run:

```bash
git add .pre-commit-config.yaml
git commit -m "chore: fix pre-commit hook ref"
```

## Task 2: Harden The Root Installer

**Files:**

- Modify: `install`

- [ ] **Step 1: Replace the installer with the hardened POSIX shell version**

Replace the full contents of `install` with:

```sh
#!/bin/sh

set -eu

echo_task() {
  printf "\033[0;34m--> %s\033[0m\n" "$*"
}

error() {
  printf "\033[0;31m%s\033[0m\n" "$*" >&2
  exit 1
}

is_unsigned_integer() {
  case "$1" in
    ""|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

validate_unsigned_integer() {
  name="$1"
  value="$2"

  if ! is_unsigned_integer "${value}"; then
    error "${name} must be a non-negative integer."
  fi
}

retry_count="${DOTFILES_RETRY_COUNT:-3}"
retry_delay="${DOTFILES_RETRY_DELAY:-5}"

validate_unsigned_integer "DOTFILES_RETRY_COUNT" "${retry_count}"
validate_unsigned_integer "DOTFILES_RETRY_DELAY" "${retry_delay}"

if [ "${retry_count}" -eq 0 ]; then
  error "DOTFILES_RETRY_COUNT must be greater than 0."
fi

if chezmoi="$(command -v chezmoi 2>/dev/null)"; then
  echo_task "Using chezmoi from ${chezmoi}"
else
  bin_dir="${HOME}/.local/bin"
  chezmoi="${bin_dir}/chezmoi"
  mkdir -p "${bin_dir}"
  echo_task "Installing chezmoi to ${chezmoi}"
  if command -v curl >/dev/null 2>&1; then
    sh -c "$(curl -fsLS https://get.chezmoi.io/lb)" -- -b "${bin_dir}"
  elif command -v wget >/dev/null 2>&1; then
    sh -c "$(wget -qO- https://get.chezmoi.io/lb)" -- -b "${bin_dir}"
  else
    error "To install chezmoi, you must have curl or wget."
  fi
fi

# POSIX way to get script's dir: https://stackoverflow.com/a/29834779/12156188
script_dir="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
source_dir=""
source_label=""

if [ -n "${DOTFILES_SOURCE-}" ]; then
  source_dir="${DOTFILES_SOURCE}"
  source_label="DOTFILES_SOURCE"
elif [ -f "${script_dir}/.chezmoiversion" ]; then
  source_dir="${script_dir}"
  source_label="local source"
elif [ -f "${script_dir}/home/.chezmoiversion" ] || [ -f "${script_dir}/.chezmoiroot" ]; then
  source_dir="${script_dir}"
  source_label="local source"
fi

set -- init

if [ -n "${DOTFILES_ONE_SHOT-}" ]; then
  echo_task "Mode: one-shot init"
  set -- "$@" --one-shot
else
  echo_task "Mode: init and apply"
  set -- "$@" --apply
fi

if [ -n "${DOTFILES_DEBUG-}" ]; then
  echo_task "Debug output enabled"
  set -- "$@" --debug
fi

if [ -n "${DOTFILES_VERBOSE-}" ]; then
  echo_task "Verbose output enabled"
  set -- "$@" --verbose
fi

if [ -n "${DOTFILES_CHEZMOI_INCLUDE-}" ]; then
  echo_task "Using chezmoi include filter"
  set -- "$@" --include "${DOTFILES_CHEZMOI_INCLUDE}"
fi

if [ -n "${DOTFILES_CHEZMOI_EXCLUDE-}" ]; then
  echo_task "Using chezmoi exclude filter"
  set -- "$@" --exclude "${DOTFILES_CHEZMOI_EXCLUDE}"
fi

if [ -n "${DOTFILES_NO_TTY-}" ]; then
  echo_task "TTY prompts disabled"
  set -- "$@" --no-tty
fi

if [ -n "${source_dir}" ]; then
  echo_task "Using ${source_label}: ${source_dir}"
  set -- "$@" --source "${source_dir}"
else
  repo="${DOTFILES_REPO:-github.com/${DOTFILES_USER:-kitos9112}/dotfiles}"
  if [ -n "${DOTFILES_REPO-}" ]; then
    echo_task "Using remote chezmoi repository from DOTFILES_REPO"
  else
    echo_task "Using default remote chezmoi repository"
  fi
  set -- "$@" "${repo}"
fi

attempt=1

while [ "${attempt}" -le "${retry_count}" ]; do
  echo_task "Attempt ${attempt}/${retry_count}: running chezmoi init"

  if "${chezmoi}" "$@"; then
    exit 0
  fi

  if [ "${attempt}" -lt "${retry_count}" ]; then
    echo_task "chezmoi init failed on attempt ${attempt}. Retrying in ${retry_delay} seconds."
    sleep "${retry_delay}"
  fi

  attempt=$((attempt + 1))
done

error "chezmoi init failed after ${retry_count} attempts."
```

- [ ] **Step 2: Check POSIX shell syntax**

Run:

```bash
sh -n install
```

Expected: no output and exit code `0`.

- [ ] **Step 3: Smoke test invalid retry input**

Run:

```bash
DOTFILES_RETRY_COUNT=abc ./install
```

Expected: the command exits non-zero and prints:

```text
DOTFILES_RETRY_COUNT must be a non-negative integer.
```

- [ ] **Step 4: Smoke test the root installer in a temp home**

Run:

```bash
tmp_home="$(mktemp -d)"
HOME="${tmp_home}" \
XDG_CONFIG_HOME="${tmp_home}/.config" \
XDG_DATA_HOME="${tmp_home}/.local/share" \
XDG_STATE_HOME="${tmp_home}/.local/state" \
XDG_CACHE_HOME="${tmp_home}/.cache" \
DOTFILES_SOURCE="$(pwd)" \
DOTFILES_TEST=true \
DOTFILES_VERBOSE=true \
DOTFILES_NO_TTY=true \
DOTFILES_CHEZMOI_EXCLUDE=scripts \
./install
```

Expected: output includes `Mode: init and apply`, `TTY prompts disabled`, and `Attempt 1/3: running chezmoi init`; command exits `0`.

- [ ] **Step 5: Commit**

Run:

```bash
git add install
git commit -m "fix: harden chezmoi installer"
```

## Task 3: Normalize Chezmoi Data Exports

**Files:**

- Modify: `home/.chezmoi.toml.tmpl`

- [ ] **Step 1: Add explicit root/work environment overrides**

In `home/.chezmoi.toml.tmpl`, after:

```gotemplate
{{- $isRoot := contains $workLaptop .chezmoi.hostname | not -}}
{{- $isWork := contains $workLaptop .chezmoi.hostname -}}
```

add:

```gotemplate
{{- $isRootOverride := env "DOTFILES_IS_ROOT" -}}
{{- if eq $isRootOverride "true" -}}
{{-   $isRoot = true -}}
{{- else if eq $isRootOverride "false" -}}
{{-   $isRoot = false -}}
{{- end -}}

{{- $isWorkOverride := env "DOTFILES_IS_WORK" -}}
{{- if eq $isWorkOverride "true" -}}
{{-   $isWork = true -}}
{{- else if eq $isWorkOverride "false" -}}
{{-   $isWork = false -}}
{{- end -}}
```

- [ ] **Step 2: Export `is_wsl` into chezmoi data**

In the `[data]` section, replace:

```toml
  osid = {{ $osid | quote }}
```

with:

```toml
  osid = {{ $osid | quote }}
  is_wsl = {{ $isWsl }}
```

- [ ] **Step 3: Render the config template with override inputs**

Run:

```bash
rendered="$(
  HOME="$(mktemp -d)" \
  DOTFILES_TEST=true \
  WSL_DISTRO_NAME=Ubuntu \
  DOTFILES_IS_ROOT=false \
  DOTFILES_IS_WORK=true \
  chezmoi execute-template --source "$(pwd)" < home/.chezmoi.toml.tmpl
)"
printf '%s\n' "${rendered}" | rg 'is_wsl = true|is_root = false|is_work = true'
```

Expected output contains all three lines:

```text
  is_wsl = true
  is_root = false
  is_work = true
```

- [ ] **Step 4: Verify exported data through a temp chezmoi init**

Run:

```bash
tmp_home="$(mktemp -d)"
HOME="${tmp_home}" \
XDG_CONFIG_HOME="${tmp_home}/.config" \
XDG_DATA_HOME="${tmp_home}/.local/share" \
XDG_STATE_HOME="${tmp_home}/.local/state" \
XDG_CACHE_HOME="${tmp_home}/.cache" \
DOTFILES_TEST=true \
WSL_DISTRO_NAME=Ubuntu \
DOTFILES_IS_ROOT=false \
DOTFILES_IS_WORK=true \
chezmoi init --apply --source "$(pwd)" --exclude scripts --no-tty

HOME="${tmp_home}" \
XDG_CONFIG_HOME="${tmp_home}/.config" \
XDG_DATA_HOME="${tmp_home}/.local/share" \
XDG_STATE_HOME="${tmp_home}/.local/state" \
XDG_CACHE_HOME="${tmp_home}/.cache" \
chezmoi execute-template '{{ .is_wsl }} {{ .is_root }} {{ .is_work }}'
```

Expected output is:

```text
true false true
```

- [ ] **Step 5: Commit**

Run:

```bash
git add home/.chezmoi.toml.tmpl
git commit -m "fix: export chezmoi machine data"
```

## Task 4: Make Local Renovate Execution Safe

**Files:**

- Modify: `Taskfile.yaml`
- Modify: `tests/renovate-bot/local-config.js`
- Modify: `.github/workflows/renovate.yaml`

- [ ] **Step 1: Replace the local Renovate task**

Replace the full contents of `Taskfile.yaml` with:

```yaml
---
# https://taskfile.dev

version: "3"

vars:
  RENOVATE_LOCAL_CONFIG: "tests/renovate-bot/local-config.js"

dotenv: ["~/.env"]

tasks:
  run-renovate:
    desc: Run Renovate in dry-run mode against this repository.
    env:
      GITHUB_TOKEN: "{{.GITHUB_TOKEN}}"
    preconditions:
      - sh: test -n "$GITHUB_TOKEN"
        msg: GITHUB_TOKEN must be set to run Renovate locally.
    cmds:
      - >
        docker run --rm
        --volume "$(pwd)/{{.RENOVATE_LOCAL_CONFIG}}:/usr/src/app/config.js:ro"
        renovate/renovate:slim
        --platform=github
        --token="$GITHUB_TOKEN"
        --print-config=true
        --force-cli=true
        --dry-run=full
        --use-base-branch-config=merge
```

- [ ] **Step 2: Align the local Renovate bot config**

Replace the full contents of `tests/renovate-bot/local-config.js` with:

```javascript
module.exports = {
  platform: 'github',
  repositories: ['kitos9112/dotfiles'],
  includeForks: true,
  onboarding: false,
  requireConfig: 'optional',
  gitAuthor: 'henry-pa-bot <166536+henry-bot[bot]@users.noreply.github.com>',
};
```

- [ ] **Step 3: Normalize Renovate workflow branch and env handling**

In `.github/workflows/renovate.yaml`, replace:

```yaml
  push:
    branches:
      - main
      - master

env:
  LOG_LEVEL: debug
  DRY_RUN: false
  RENOVATE_CONFIG_FILE: .github/renovate.json5
```

with:

```yaml
  push:
    branches:
      - master

env:
  LOG_LEVEL: info
  RENOVATE_DRY_RUN: "false"
  RENOVATE_CONFIG_FILE: .github/renovate.json5
```

Then replace:

```yaml
      - name: Override default config from dispatch variables
        run: |
          echo "DRY_RUN=${{ github.event.inputs.dryRun || env.DRY_RUN }}" >> "$GITHUB_ENV"
          echo "LOG_LEVEL=${{ github.event.inputs.logLevel || env.LOG_LEVEL }}" >> "$GITHUB_ENV"
```

with:

```yaml
      - name: Override Renovate env from dispatch inputs
        run: |
          echo "RENOVATE_DRY_RUN=${{ github.event.inputs.dryRun || env.RENOVATE_DRY_RUN }}" >> "$GITHUB_ENV"
          echo "LOG_LEVEL=${{ github.event.inputs.logLevel || env.LOG_LEVEL }}" >> "$GITHUB_ENV"
```

- [ ] **Step 4: Verify token echoing is gone**

Run:

```bash
rg -n 'echo \\$GITHUB_TOKEN|echo ".*GITHUB_TOKEN|echo .*GITHUB_TOKEN' Taskfile.yaml .github/workflows tests/renovate-bot
```

Expected: no output and exit code `1`.

- [ ] **Step 5: Validate YAML syntax for changed YAML files**

Run:

```bash
uvx pre-commit run yamllint --files Taskfile.yaml .github/workflows/renovate.yaml
```

Expected: `yamllint` reports `Passed`.

- [ ] **Step 6: Commit**

Run:

```bash
git add Taskfile.yaml tests/renovate-bot/local-config.js .github/workflows/renovate.yaml
git commit -m "fix: make renovate dry-run safer"
```

## Task 5: Inline Renovate Custom Managers

**Files:**

- Modify: `.github/renovate.json5`
- Delete: `.github/renovate/regexManagers.json5`

- [ ] **Step 1: Replace the Renovate repo config**

Replace the full contents of `.github/renovate.json5` with:

```json5
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    ":enableRenovate",
    "config:recommended",
    ":disableRateLimiting",
    ":dependencyDashboard",
    ":semanticCommits",
    ":separatePatchReleases",
    "docker:enableMajor",
    ":enablePreCommit",
  ],
  "timezone": "Europe/London",
  "dependencyDashboard": true,
  "dependencyDashboardTitle": "Renovate Dashboard",
  "labels": [
    "renovatebot",
  ],
  "commitMessageSuffix": "[ci-skip]",
  "onboarding": false,
  "gitAuthor": "henry-pa-bot <166536+henry-bot[bot]@users.noreply.github.com>",
  "suppressNotifications": [
    "prIgnoreNotification",
  ],
  "ignoreTests": true,
  "rebaseWhen": "conflicted",
  "assignees": [
    "@kitos9112",
  ],
  "customManagers": [
    {
      "customType": "regex",
      "datasourceTemplate": "github-releases",
      "depNameTemplate": "microsoft/vscode",
      "description": "Process Microsoft VS Code template versions",
      "fileMatch": [
        "^home/\\.chezmoiexternal\\.ya?ml$",
      ],
      "matchStrings": [
        "\\{\\{-?\\s*\\$vscodeVersion := \"(?<currentValue>\\d+\\.\\d+\\.\\d+)\"\\s*-?\\}\\}",
      ],
      "autoReplaceStringTemplate": "{{- $vscodeVersion := \"{{newValue}}\" -}}",
      "versioningTemplate": "semver-coerced",
    },
    {
      "customType": "regex",
      "datasourceTemplate": "github-tags",
      "depNameTemplate": "golang/go",
      "description": "Process Golang version URLs",
      "extractVersionTemplate": "^go(?<version>.*)$",
      "fileMatch": [
        "^home/\\.chezmoiexternal\\.ya?ml$",
      ],
      "matchStrings": [
        "https:\\/\\/go\\.dev\\/dl\\/go(?<currentValue>\\d+\\.\\d+\\.\\d+)\\..*",
      ],
      "versioningTemplate": "semver",
    },
    {
      "customType": "regex",
      "description": "Process renovate comments in home templates",
      "fileMatch": [
        "^home\\/.*",
      ],
      "matchStrings": [
        "# renovate: datasource=(?<datasource>.+?) packageName=(?<packageName>.+?)( extractVersion=(?<extractVersion>.+?))?( registryUrl=(?<registryUrl>.+?))?\\s+(?<depName>.+?) (?<currentValue>.+)",
      ],
      "extractVersionTemplate": "{{#if extractVersion}}{{extractVersion}}{{else}}^v?(?<version>.+)${{/if}}",
    },
  ],
  "packageRules": [
    {
      "matchPackageNames": [
        "node",
        "python",
      ],
      "minimumReleaseAge": "20 days",
    },
    {
      "matchUpdateTypes": [
        "minor",
        "patch",
        "pin",
        "digest",
      ],
      "automerge": true,
    },
  ],
  "asdf": {
    "fileMatch": [
      "(^|/)\\.tool-versions$",
      "(^|/)dot_tool-versions.tmpl$",
    ],
  },
}
```

- [ ] **Step 2: Delete the separate regex manager preset**

Run:

```bash
git rm .github/renovate/regexManagers.json5
```

- [ ] **Step 3: Confirm no self-reference remains**

Run:

```bash
rg -n 'github>kitos9112/dotfiles|regexManagers\\.json5' .github/renovate.json5 .github tests Taskfile.yaml
```

Expected: no output and exit code `1`.

- [ ] **Step 4: Validate Renovate config**

Run:

```bash
uvx pre-commit run renovate-config-validator --files .github/renovate.json5
```

Expected: `renovate-config-validator` reports `Passed`.

- [ ] **Step 5: Commit**

Run:

```bash
git add .github/renovate.json5 .github/renovate/regexManagers.json5
git commit -m "fix: inline renovate custom managers"
```

## Task 6: Align CI And README With `master`

**Files:**

- Modify: `.github/workflows/linters.yaml`
- Modify: `README.md`

- [ ] **Step 1: Update linter workflow branch defaults**

In `.github/workflows/linters.yaml`, replace:

```yaml
  pull_request:
    branches:
      - main

env:
  # Currently no way to detect automatically
  DEFAULT_BRANCH: main
```

with:

```yaml
  pull_request:
    branches:
      - master

env:
  DEFAULT_BRANCH: master
```

- [ ] **Step 2: Add tracked `.env` safety documentation**

In `README.md`, after the paragraph ending with:

```markdown
Existing installations should add those keys to `~/.config/chezmoi/chezmoi.toml` and then run `chezmoi apply`.
```

add:

```markdown

## Public-safe environment pointers

The tracked `.env` file is allowed to exist in this public repository only for
public-safe pointer values, such as 1Password item references. Do not store raw
tokens, credentials, private keys, recovery codes, or machine-confidential
values in `.env` or any other tracked file.
```

- [ ] **Step 3: Document installer controls**

In `README.md`, after the manual chezmoi install snippet:

```markdown
chezmoi init --apply --verbose https://github.com/kitos9112/dotfiles.git
```

add:

```markdown

### Installer controls

The root `install` script accepts environment variables for test and recovery
flows:

- `DOTFILES_SOURCE` uses a local source checkout instead of the remote repo.
- `DOTFILES_REPO` overrides the remote chezmoi repository.
- `DOTFILES_ONE_SHOT=true` passes `--one-shot` instead of `--apply`.
- `DOTFILES_CHEZMOI_INCLUDE` and `DOTFILES_CHEZMOI_EXCLUDE` pass include and
  exclude filters to chezmoi.
- `DOTFILES_NO_TTY=true` passes `--no-tty`.
- `DOTFILES_VERBOSE=true` passes `--verbose`.
- `DOTFILES_DEBUG=true` passes `--debug`.
- `DOTFILES_RETRY_COUNT` and `DOTFILES_RETRY_DELAY` control retry behavior.
- `DOTFILES_IS_ROOT=true|false` and `DOTFILES_IS_WORK=true|false` override the
  default machine inference while rendering chezmoi config.
```

- [ ] **Step 4: Update local validation documentation**

In `README.md`, in the `Verification` section after the existing temp-home command block, add:

````markdown

To validate hooks locally through `uv`, run:

```bash
uvx pre-commit run --all-files
```

To validate the root installer path locally without running mutating scripts:

```bash
tmp_home="$(mktemp -d)"
HOME="${tmp_home}" \
XDG_CONFIG_HOME="${tmp_home}/.config" \
XDG_DATA_HOME="${tmp_home}/.local/share" \
XDG_STATE_HOME="${tmp_home}/.local/state" \
XDG_CACHE_HOME="${tmp_home}/.cache" \
DOTFILES_SOURCE="$(pwd)" \
DOTFILES_TEST=true \
DOTFILES_NO_TTY=true \
DOTFILES_CHEZMOI_EXCLUDE=scripts \
./install
```
````

- [ ] **Step 5: Validate Markdown and YAML formatting**

Run:

```bash
uvx pre-commit run yamllint --files .github/workflows/linters.yaml
uvx pre-commit run trailing-whitespace --files README.md .github/workflows/linters.yaml
```

Expected: both commands report `Passed`.

- [ ] **Step 6: Commit**

Run:

```bash
git add .github/workflows/linters.yaml README.md
git commit -m "docs: align maintenance docs with master"
```

## Task 7: Run End-To-End Validation

**Files:**

- Verify: all changed files

- [ ] **Step 1: Run all pre-commit hooks**

Run:

```bash
uvx pre-commit run --all-files
```

Expected: all hooks report `Passed`.

- [ ] **Step 2: Run temp-home chezmoi init and verify**

Run:

```bash
tmp_home="$(mktemp -d)"
HOME="${tmp_home}" \
XDG_CONFIG_HOME="${tmp_home}/.config" \
XDG_DATA_HOME="${tmp_home}/.local/share" \
XDG_STATE_HOME="${tmp_home}/.local/state" \
XDG_CACHE_HOME="${tmp_home}/.cache" \
DOTFILES_TEST=true \
chezmoi init --apply --source "$(pwd)" --exclude scripts --no-tty

HOME="${tmp_home}" \
XDG_CONFIG_HOME="${tmp_home}/.config" \
XDG_DATA_HOME="${tmp_home}/.local/share" \
XDG_STATE_HOME="${tmp_home}/.local/state" \
XDG_CACHE_HOME="${tmp_home}/.cache" \
DOTFILES_TEST=true \
chezmoi verify --source "$(pwd)" --exclude scripts --no-tty
```

Expected: both commands exit `0`.

- [ ] **Step 3: Run the root installer smoke test**

Run:

```bash
tmp_home="$(mktemp -d)"
HOME="${tmp_home}" \
XDG_CONFIG_HOME="${tmp_home}/.config" \
XDG_DATA_HOME="${tmp_home}/.local/share" \
XDG_STATE_HOME="${tmp_home}/.local/state" \
XDG_CACHE_HOME="${tmp_home}/.cache" \
DOTFILES_SOURCE="$(pwd)" \
DOTFILES_TEST=true \
DOTFILES_NO_TTY=true \
DOTFILES_CHEZMOI_EXCLUDE=scripts \
./install
```

Expected: command exits `0`.

- [ ] **Step 4: Confirm no token-printing command remains**

Run:

```bash
rg -n 'echo \\$GITHUB_TOKEN|echo ".*GITHUB_TOKEN|echo .*GITHUB_TOKEN' .
```

Expected: no output and exit code `1`.

- [ ] **Step 5: Confirm `.env` remains tracked**

Run:

```bash
git ls-files --stage .env
```

Expected output starts with:

```text
100644
```

- [ ] **Step 6: Review final git state**

Run:

```bash
git status --short --branch
git log --oneline -8
```

Expected: the branch contains the implementation commits from this plan. Working tree is clean.
