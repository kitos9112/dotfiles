# Deterministic Chezmoi Modernization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make chezmoi rendering deterministic and offline, simplify bootstrap scripts, and provide one focused test entry point that validates the declared chezmoi compatibility range.

**Architecture:** Checked-in `.chezmoidata` supplies all release and tool-manifest inputs, templates render those values without network or source-tree writes, and small idempotent scripts perform only target-machine actions. Focused shell contracts use chezmoi 2.72 features to render explicit OS/profile fixtures, while container and macOS smoke tests remain responsible for real downloads and applies.

**Tech Stack:** chezmoi templates and externals, Bash/Zsh, Taskfile, Renovate regex managers, GitHub Actions, Docker.

**Spec:** `docs/superpowers/specs/2026-09-02-deterministic-chezmoi-modernization-design.md`

## Global Constraints

- Preserve existing desktop/server, work/personal, sudo, and Homebrew behavior.
- Set the minimum supported chezmoi version to exactly `2.72.0`.
- Template contract tests must not need network access or machine-local chezmoi data.
- Keep the Linux smoke matrix exactly `almalinux-9`, `almalinux-10`, `ubuntu-24.04`, and `ubuntu-26.04`.
- Do not replace asdf, Homebrew, Oh My Zsh, editors, or terminal configurations.
- Git-repository externals retain their current static URLs and refresh periods.
- Optional convenience installation may warn and continue; invalid configuration and invalid rendering must fail.
- Keep the repository public-safe and use conventional commits.

---

## File Structure

- `home/.chezmoidata/versions.yaml`: reviewed versions for release archives and standalone binaries.
- `home/.chezmoidata/asdf.yaml`: ASDF plugin names and optional repository URLs.
- `home/.chezmoidata/packages.yaml`: existing package data plus the pinned Rust cargo-tool manifest.
- `home/.chezmoiexternal.yaml`: pure external URL rendering from checked-in data.
- `home/.chezmoiscripts/run_onchange_after_080-asdf-tools.sh.tmpl`: register missing plugins and run one tolerant `asdf install` when inputs change.
- `home/.chezmoiscripts/run_onchange_after_103-rust-dev.sh.tmpl`: install/update the declared Rust toolchain and pinned cargo tools when their manifest changes.
- `home/.chezmoiscripts/run_once_after_10-linux-install-session-manager.sh.tmpl`: preserve only the Alma/Fedora AWS Session Manager behavior from the legacy IaC script.
- `tests/lib/contract-test.sh`: shared repository paths, isolated chezmoi config, render helpers, assertions, and cleanup.
- `tests/profile-config.test.sh`: profile/root/Homebrew/config-template contracts.
- `tests/packages-externals.test.sh`: package selection, version pins, external rendering, and offline policy.
- `tests/desktop-integrations.test.sh`: fonts, terminals, GNOME, Ghostty, and Homebrew trust behavior.
- `tests/script-contracts.test.sh`: rendered shell syntax, ASDF/Rust/session-manager behavior, and bootstrap resilience.
- `tests/managed-config.test.sh`: Claude merge and managed helper contracts.
- `tests/repository-policy.test.sh`: source attributes, missing-key strictness, completion generation, obsolete-file absence, and CI/Task wiring.
- `Taskfile.yaml`: single `task test` fast-contract entry point plus explicit maintenance commands.
- `.github/workflows/acceptance-tests.yaml`: run `task test` at chezmoi 2.72.0 and latest, while retaining Go compilation and OS smoke tests.

---

### Task 1: Pin external release versions and remove render-time discovery

**Files:**

- Create: `home/.chezmoidata/versions.yaml`
- Create: `tests/lib/contract-test.sh`
- Create: `tests/packages-externals.test.sh`
- Modify: `home/.chezmoiexternal.yaml`
- Modify: `.github/renovate.json5`
- Delete: `home/.chezmoitemplates/get-github-latest-version`
- Delete: `home/.chezmoitemplates/get-github-head-revision`
- Delete: `home/.chezmoitemplates/read-versions-and-revisions-cache`
- Delete: `home/.chezmoitemplates/save-versions-and-revisions-cache`

**Interfaces:**

- Produces: `.versions.{asdf,uv,fzf,nerd_fonts,retry,direnv,vscode,go}` template data.
- Produces: `render_template FILE JSON`, `assert_contains HAYSTACK NEEDLE LABEL`, `assert_not_contains HAYSTACK NEEDLE LABEL`, `assert_file_exists PATH LABEL`, `assert_file_content PATH EXPECTED LABEL`, and `finish_tests` shell helpers.
- Consumes: existing `map-architectures`, `map-platforms`, `machine-class`, and `use-homebrew` templates.

- [ ] **Step 1: Add a failing offline external contract**

Create the shared test helper with an isolated empty config and a render function:

```bash
#!/usr/bin/env bash
set -euo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." && pwd -P)"
SOURCE_DIR="${REPO_ROOT}/home"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-contract.XXXXXX")"
EMPTY_CONFIG="${TMP_ROOT}/empty.toml"
: >"${EMPTY_CONFIG}"
trap 'rm -rf "${TMP_ROOT}"' EXIT HUP INT TERM
failures=0

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }

assert_contains() {
  local haystack=$1 needle=$2 label=$3
  [[ "${haystack}" == *"${needle}"* ]] && pass "${label}" || fail "${label}"
}

assert_not_contains() {
  local haystack=$1 needle=$2 label=$3
  [[ "${haystack}" != *"${needle}"* ]] && pass "${label}" || fail "${label}"
}

assert_file_exists() {
  local path=$1 label=$2
  [[ -e "${path}" ]] && pass "${label}" || fail "${label}"
}

assert_file_content() {
  local path=$1 expected=$2 label=$3
  [[ -f "${path}" && "$(<"${path}")" == "${expected}" ]] && pass "${label}" || fail "${label}"
}

render_template() {
  local file=$1 override=${2:-{}}
  chezmoi execute-template --config "${EMPTY_CONFIG}" --source "${SOURCE_DIR}" \
    --override-data "${override}" --file "${file}"
}

finish_tests() {
  ((failures == 0)) || exit 1
}
```

Add assertions in `tests/packages-externals.test.sh` that require literal version values, reject `get-github-latest-version`, `git ls-remote`, `releases/latest`, and cache-template names, and render both Homebrew and non-Homebrew variants successfully with `PATH=/usr/bin:/bin`.

- [ ] **Step 2: Run the contract and verify the expected failure**

Run: `rtk bash tests/packages-externals.test.sh`

Expected: FAIL because `versions.yaml` does not exist and `.chezmoiexternal.yaml` still contains runtime GitHub lookup/cache templates.

- [ ] **Step 3: Add exact version data and pure external rendering**

Record the latest stable upstream values verified at implementation time using this schema:

```yaml
---
versions:
  # renovate: datasource=github-releases packageName=asdf-vm/asdf
  asdf: "0.20.0"
  # renovate: datasource=github-releases packageName=astral-sh/uv
  uv: "0.12.9"
  # renovate: datasource=github-releases packageName=junegunn/fzf
  fzf: "0.74.1"
  # renovate: datasource=github-releases packageName=ryanoasis/nerd-fonts
  nerd_fonts: "3.5.1"
  # renovate: datasource=github-releases packageName=kadwanev/retry
  retry: "1.0.2"
  # renovate: datasource=github-releases packageName=direnv/direnv
  direnv: "2.37.1"
  # renovate: datasource=github-releases packageName=microsoft/vscode
  vscode: "1.135.0"
  # renovate: datasource=github-tags packageName=golang/go extractVersion=^go(?<version>.*)$
  go: "1.27.1"
```

Before committing, confirm every value and asset name against the upstream release page. Replace every dynamic helper assignment in `.chezmoiexternal.yaml` with `.versions.*`, remove the cache dictionary/read/save calls, and keep the current URL/platform mapping.

- [ ] **Step 4: Simplify Renovate matching**

Delete the dedicated inline VS Code and Go URL managers from `.github/renovate.json5`. Keep the generic `# renovate:` manager and extend its `fileMatch` to cover all `home/**` data files. Validate that the comment format above yields the correct dependency names and extracted versions.

- [ ] **Step 5: Remove the unused lookup/cache templates**

Delete all four files listed in this task. Run:

```bash
rtk rg -n 'get-github|versions-and-revisions|releases/latest|git ls-remote' home
```

Expected: no matches related to dependency discovery.

- [ ] **Step 6: Run focused and existing regression tests**

Run:

```bash
rtk bash tests/packages-externals.test.sh
rtk bash tests/bootstrap-profiles.test.sh
```

Expected: both PASS without DNS or GitHub access.

- [ ] **Step 7: Commit deterministic externals**

```bash
rtk git add home/.chezmoidata/versions.yaml home/.chezmoiexternal.yaml \
  home/.chezmoitemplates .github/renovate.json5 tests/lib/contract-test.sh \
  tests/packages-externals.test.sh
rtk git commit -m "refactor(chezmoi): pin external release versions"
```

---

### Task 2: Adopt the chezmoi 2.72 template contract and remove dead files

**Files:**

- Modify: `home/.chezmoiversion`
- Modify: `home/.chezmoi.toml.tmpl`
- Rename: `home/dot_oh-my-zsh-custom/plugins/chezmoi/_chezmoi` to `home/dot_oh-my-zsh-custom/plugins/chezmoi/_chezmoi.tmpl`
- Modify: shell-producing templates identified by the strict render contract
- Create: `tests/repository-policy.test.sh`
- Delete: `home/.chezmoiscripts/run_after_110-update-completions.zsh.tmpl`
- Delete: `home/.chezmoiscripts/run_after_102-reload.zsh.tmpl`
- Delete: `home/ansible.cfg`
- Delete: `home/scripts/install_dotfiles.sh`

**Interfaces:**

- Consumes: `tests/lib/contract-test.sh` from Task 1.
- Produces: a strict `missingkey=error` repository contract and native `{{ completion "zsh" }}` completion source.

- [ ] **Step 1: Add failing version, completion, strict-key, and obsolete-file checks**

In `tests/repository-policy.test.sh`, assert:

```bash
assert_file_content "${SOURCE_DIR}/.chezmoiversion" "2.72.0" "chezmoi floor"
assert_contains "$(cat "${SOURCE_DIR}/dot_oh-my-zsh-custom/plugins/chezmoi/_chezmoi.tmpl")" \
  '{{ completion "zsh" }}' "native chezmoi completion"
assert_not_contains "$(cat "${SOURCE_DIR}/.chezmoi.toml.tmpl")" \
  'missingkey=zero' "strict missing keys"
```

Also assert the four obsolete files are absent and render `_chezmoi.tmpl`, checking it begins with `#compdef chezmoi`.

- [ ] **Step 2: Run the policy contract and verify it fails**

Run: `rtk bash tests/repository-policy.test.sh`

Expected: FAIL on the old version floor, checked-in completion, permissive template option, and existing obsolete files.

- [ ] **Step 3: Raise the version floor and use native completion generation**

Set `home/.chezmoiversion` to `2.72.0`. Rename the completion file and replace its generated body with exactly:

```gotemplate
{{ completion "zsh" }}
```

Delete `run_after_110-update-completions.zsh.tmpl` so apply no longer writes to source state.

- [ ] **Step 4: Make optional data explicit and enable strict missing keys**

Remove the `[template] options = ["missingkey=zero"]` section. Render all templates under fresh config data and replace optional direct keys with guarded access, for example:

```gotemplate
{{- $extraHomeDir := get . "extra_home_dir" | default "" -}}
{{- $signingProgram := get . "signing_ssh_program" | default "" -}}
```

For shell values in templates touched by the migration, use:

```gotemplate
VALUE={{ shellQuote $value }}
PACKAGES=(
{{ shellQuoteList $packages }}
)
```

- [ ] **Step 5: Delete confirmed obsolete files**

Delete the empty reload script, no-op `ansible.cfg`, and ignored legacy installer. Do not delete unrelated editor, terminal, or archived configuration.

- [ ] **Step 6: Run strict render and regression checks**

Run:

```bash
rtk bash tests/repository-policy.test.sh
rtk bash tests/bootstrap-profiles.test.sh
rtk chezmoi execute-template --config /dev/null --config-format toml \
  --source home --file home/.chezmoiignore
```

Expected: all PASS; missing required keys produce errors while fresh-machine optional keys render normally.

- [ ] **Step 7: Commit the template contract cleanup**

```bash
rtk git add -A home tests/repository-policy.test.sh
rtk git commit -m "refactor(chezmoi): adopt strict native templates"
```

---

### Task 3: Consolidate manifest-driven tool scripts

**Files:**

- Create: `home/.chezmoidata/asdf.yaml`
- Modify: `home/.chezmoidata/packages.yaml`
- Create: `home/.chezmoiscripts/run_onchange_after_080-asdf-tools.sh.tmpl`
- Create: `home/.chezmoiscripts/run_onchange_after_103-rust-dev.sh.tmpl`
- Create: `home/.chezmoiscripts/run_once_after_10-linux-install-session-manager.sh.tmpl`
- Modify: `home/.chezmoiscripts/run_once_before_00-linux-prepare.sh.tmpl`
- Modify: `tests/go-tools.test.sh`
- Modify: `tests/script-contracts.test.sh`
- Delete: `home/.chezmoiscripts/run_after_080-install-asdf-plugins.sh.tmpl`
- Delete: `home/.chezmoiscripts/run_after_099-update-asdf.sh.tmpl`
- Delete: `home/.chezmoiscripts/run_after_103-rust-dev.zsh.tmpl`
- Delete: `home/.chezmoiscripts/run_after_900-finalizers.zsh.tmpl`
- Delete: `home/.chezmoiscripts/run_once_after_10-linux-install-iac-tools.sh.tmpl`
- Delete: `home/scripts/.helpers` after its final consumer is migrated

**Interfaces:**

- Produces: `.asdf_plugins` list entries with `name` and optional `url`.
- Produces: `.packages.rust.toolchain` and `.packages.rust.cargo_tools[]` entries with `name` and `version`.
- Consumes: `scripts-library`, `.tool-versions`, and the asdf binary external.

- [ ] **Step 1: Add failing ASDF manifest and single-install contracts**

Add a recording fake asdf to `tests/script-contracts.test.sh`. Assert the rendered script:

- fingerprints `asdf.yaml` and `dot_tool-versions.tmpl`;
- adds each missing plugin with its optional URL;
- calls `asdf install` exactly once;
- never calls `plugin update --all`; and
- exits successfully with a warning when `asdf install` returns 42.

Update `tests/go-tools.test.sh` so `ASDF_UPDATE_TEMPLATE` points to `run_onchange_after_080-asdf-tools.sh.tmpl` and retains the tolerant install assertion.

- [ ] **Step 2: Run the script contracts and verify they fail**

Run:

```bash
rtk bash tests/script-contracts.test.sh
rtk bash tests/go-tools.test.sh
```

Expected: FAIL because the manifest-driven script does not exist.

- [ ] **Step 3: Add ASDF manifest data**

Create:

```yaml
---
asdf_plugins:
  - name: terragrunt
  - name: kubectl
  - name: packer
  - name: terraform
    url: https://github.com/asdf-community/asdf-hashicorp.git
  - name: helm
    url: https://github.com/Antiarchitect/asdf-helm.git
  - name: nodejs
    url: https://github.com/asdf-vm/asdf-nodejs.git
  - name: golang
    url: https://github.com/asdf-community/asdf-golang.git
```

- [ ] **Step 4: Implement one onchange ASDF convergence script**

Render plugin names/URLs into shell-safe arguments. Use `asdf plugin list` to skip existing plugins, tolerate plugin-add failures with a warning, then run one `asdf install`. Do not update plugins or Homebrew. Include SHA256 comments for the manifest and `.tool-versions` so chezmoi re-runs when either input changes.

- [ ] **Step 5: Preserve Rust behavior as a pinned onchange manifest**

Add a `rust` block to `packages.yaml` with `toolchain: stable` and Renovate-tracked `license-generator` version `1.3.0`. Render a Bash onchange script that installs rustup only when absent, ensures the declared toolchain, and runs `cargo install license-generator --version 1.3.0 --locked`. A failed optional cargo install warns and returns success.

- [ ] **Step 6: Narrow the legacy IaC script to Session Manager**

Delete the `.terraform-version` write because `dot_tool-versions.tmpl` already pins Terraform and Terragrunt. Rename the script to describe AWS Session Manager, keep its Fedora/AlmaLinux guard, use a temporary directory with cleanup, and retain the current one-time behavior.

- [ ] **Step 7: Migrate the Linux preparation script to scripts-library**

Replace `.helpers` logging calls with `log_task`, `log_green`, or `log_manual_action` from `scripts-library`. Delete `.helpers` after confirming:

```bash
rtk rg -n 'scripts/\.helpers|is_installed|log_echo|started|successfully' home/.chezmoiscripts
```

Expected: no legacy-helper consumers.

- [ ] **Step 8: Delete duplicated maintenance scripts and run tests**

Remove the five superseded scripts listed above. Run:

```bash
rtk bash tests/script-contracts.test.sh
rtk bash tests/go-tools.test.sh
rtk bash tests/bootstrap-profiles.test.sh
```

Expected: PASS and no normal apply script contains `brew upgrade`, `plugin update --all`, or more than one general `asdf install`.

- [ ] **Step 9: Commit manifest-driven scripts**

```bash
rtk git add -A home tests/go-tools.test.sh tests/script-contracts.test.sh
rtk git commit -m "refactor(bootstrap): converge tools from manifests"
```

---

### Task 4: Refactor the monolithic bootstrap contract into focused tests

**Files:**

- Modify: `tests/lib/contract-test.sh`
- Create: `tests/profile-config.test.sh`
- Modify: `tests/packages-externals.test.sh`
- Create: `tests/desktop-integrations.test.sh`
- Modify: `tests/script-contracts.test.sh`
- Create: `tests/managed-config.test.sh`
- Modify: `tests/repository-policy.test.sh`
- Delete: `tests/bootstrap-profiles.test.sh`

**Interfaces:**

- Produces: all test files source `tests/lib/contract-test.sh` and call `finish_tests` once.
- Produces: `render_for OS OS_RELEASE_ID PROFILE FILE` that uses `--override-data` and never strips guards.
- Consumes: focused contracts introduced by Tasks 1–3.

- [ ] **Step 1: Expand the shared rendering fixture**

Implement:

```bash
render_for() {
  local os=$1 os_id=$2 profile=$3 file=$4
  local override
  override="$(jq -cn --arg os "${os}" --arg id "${os_id}" --arg profile "${profile}" \
    '{chezmoi:{os:$os,osRelease:{id:$id}},machine_class:$profile,is_root:false,is_wsl:false,use_homebrew:false}')"
  DOTFILES_PROFILE="${profile}" render_template "${file}" "${override}"
}
```

Keep assertions free of global ordering dependencies so every test file runs independently.

- [ ] **Step 2: Move profile and config tests**

Move machine-class, sudo, Homebrew, data-file, and config-template assertions into `profile-config.test.sh`. Run it alone and verify it passes.

- [ ] **Step 3: Move desktop integration tests**

Move font single-source-of-truth, macOS terminal, GNOME terminal, Ghostty, iTerm2, and Homebrew trust-store assertions into `desktop-integrations.test.sh`. Use full Linux/macOS rendering through `render_for`; remove every first-line/last-line `sed` workaround.

- [ ] **Step 4: Move script and managed-config tests**

Move rendered shell syntax, first-bootstrap resilience, login shell, ASDF, Rust, Session Manager, and no-SIGPIPE checks into `script-contracts.test.sh`. Move dotfiles-doctor/reset/export and Claude `modify_` merge/idempotency checks into `managed-config.test.sh`.

- [ ] **Step 5: Move repository wiring tests and delete the monolith**

Move source-attribute, AI seed, Taskfile, and CI wiring checks into `repository-policy.test.sh`. Confirm every old assertion has exactly one new home, then delete `bootstrap-profiles.test.sh`.

- [ ] **Step 6: Run every focused contract independently**

Run:

```bash
for test_file in tests/profile-config.test.sh tests/packages-externals.test.sh \
  tests/desktop-integrations.test.sh tests/script-contracts.test.sh \
  tests/managed-config.test.sh tests/repository-policy.test.sh; do
  rtk bash "${test_file}"
done
```

Expected: all PASS; no test requires GitHub or developer config state.

- [ ] **Step 7: Commit focused contract tests**

```bash
rtk git add tests
rtk git commit -m "test: split chezmoi bootstrap contracts"
```

---

### Task 5: Unify local tests and CI compatibility coverage

**Files:**

- Modify: `Taskfile.yaml`
- Modify: `.github/workflows/acceptance-tests.yaml`
- Modify: `tests/repository-policy.test.sh`

**Interfaces:**

- Produces: `task test` as the single fast local and CI contract command.
- Produces: `contracts` CI matrix entries `2.72.0` and `latest`.
- Consumes: all focused and existing test scripts.

- [ ] **Step 1: Add failing Taskfile and CI wiring assertions**

Assert `Taskfile.yaml` defines `test:` and invokes these exact commands:

```text
bash tests/profile-config.test.sh
bash tests/packages-externals.test.sh
bash tests/desktop-integrations.test.sh
bash tests/script-contracts.test.sh
bash tests/managed-config.test.sh
bash tests/repository-policy.test.sh
bash tests/freeipa-tools.test.sh
bash tests/go-tools.test.sh
bash tests/wireshark-profiles.test.sh
bash tests/backup-shell-history-to-1password.sh
```

Assert CI contains both `chezmoi: "2.72.0"` and `chezmoi: latest`, and invokes `task test`.

- [ ] **Step 2: Run the policy contract and verify it fails**

Run: `rtk bash tests/repository-policy.test.sh`

Expected: FAIL because `task test` and the compatibility matrix are absent.

- [ ] **Step 3: Add the unified Task target**

Add `test` with the ten commands above in deterministic order. Keep `test-bootstrap` only as a compatibility alias whose sole command is `task: test`, or remove it after README and CI no longer reference it.

Do not add package-upgrade maintenance targets in this change; removing implicit upgrades is sufficient, and new convenience commands can be added later only when there is a demonstrated workflow for them.

- [ ] **Step 4: Replace duplicate contract jobs with a version matrix**

Create a `contracts` job on Ubuntu 24.04 with matrix values `2.72.0` and `latest`. Install Zsh, jq, and Task. For `2.72.0`, pass the exact version to the official chezmoi installer; for `latest`, omit the version. Run `task test` for both.

Keep Go module verification/compilation in its existing Go-enabled job. Keep the Linux Docker matrix unchanged. Add `--error-on-conflict` to the noninteractive macOS apply/verify flow where the command supports it.

- [ ] **Step 5: Run local tests and validate workflow syntax**

Run:

```bash
rtk task test
rtk uvx pre-commit run yamllint --files Taskfile.yaml .github/workflows/acceptance-tests.yaml
```

Expected: PASS.

- [ ] **Step 6: Commit unified test wiring**

```bash
rtk git add Taskfile.yaml .github/workflows/acceptance-tests.yaml tests/repository-policy.test.sh
rtk git commit -m "ci: test minimum and latest chezmoi"
```

---

### Task 6: Document behavior and complete verification

**Files:**

- Modify: `README.md`
- Modify: any source/test file required by verification fixes

**Interfaces:**

- Consumes: final version-data, script, Taskfile, and CI behavior from Tasks 1–5.
- Produces: user-facing maintenance and testing instructions that match the implementation.

- [ ] **Step 1: Update README dependency and test documentation**

Document that archive/binary versions live in `home/.chezmoidata/versions.yaml`, Renovate proposes updates, rendering stays offline, and package-manager upgrades are explicit maintenance. Replace the bootstrap-only test description with `task test` and list the chezmoi minimum/latest compatibility coverage. Preserve the exact distro matrix.

- [ ] **Step 2: Run offline render checks with network tools unavailable**

Create a temporary `bin` directory containing executable `curl` and `git` stubs that append their arguments to `${TMP_ROOT}/network-calls` and exit 97. Prepend that directory to the normal test `PATH`, run `tests/packages-externals.test.sh`, and assert the log remains absent or empty. Expected: the rendering contract passes and neither stub records a call.

- [ ] **Step 3: Verify no test apply mutates source state**

Capture `git status --porcelain`, run a temporary-home `chezmoi init --apply --exclude scripts --no-tty --error-on-conflict`, capture status again, and compare the two outputs. Expected: identical output.

- [ ] **Step 4: Run the full repository verification suite**

Run:

```bash
rtk task test
rtk uvx pre-commit run --all-files
rtk git diff --check
rtk git status --short
```

Expected: tests and hooks PASS; diff check is empty; only intentional README or verification-fix changes remain before the final commit.

- [ ] **Step 5: Commit documentation and verification fixes**

```bash
rtk git add README.md
rtk git commit -m "docs: describe deterministic dotfile maintenance"
```

- [ ] **Step 6: Confirm the completed commit series**

Run:

```bash
rtk git status --short --branch
rtk git log -7 --oneline
```

Expected: clean worktree and a conventional commit series containing the design, deterministic externals, strict templates, manifest-driven scripts, focused tests, CI compatibility, and documentation.
