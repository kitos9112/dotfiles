# Tool Ownership, Locale, and Linux Packages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give duplicated developer tools one asdf owner, add Spanish locale support without changing the primary locale, and make Ubuntu/Fedora/AlmaLinux desktop packages declarative and profile-aware.

**Architecture:** Existing chezmoi data remains the source of truth. asdf owns versioned developer commands, `locale.yaml` describes primary and additional locales, and parallel apt/dnf package manifests feed focused `run_onchange_` installers. Contract tests render and execute these artifacts without modifying the host.

**Tech Stack:** chezmoi 2.72 templates, YAML manifests, Bash, Task, GitHub Actions, Docker/Podman

**Spec:** `docs/superpowers/specs/2026-09-03-tool-locale-linux-packages-design.md`

## Global Constraints

- Keep asdf; do not migrate to mise.
- Keep `en_GB.UTF-8` primary and add `es_ES.UTF-8` as an additional locale.
- Install Alacritty and Wireshark only for desktop profiles.
- Use native distribution repositories only; do not add EPEL for AlmaLinux.
- Do not automatically uninstall legacy Homebrew or apt packages.
- Keep the CI matrix at AlmaLinux 9/10 and Ubuntu 24.04/26.04.
- Keep the public repository free of credentials and machine-confidential data.
- Use conventional commits.

---

### Task 1: Close stale GitHub issues

**Files:** None

**Interfaces:**
- Consumes: implemented GNOME workflow, current asdf manifest, active Renovate dashboard issue 9
- Produces: accurate open-issue inventory; issues 1287, 1529, and 968 closed with public-safe explanations

- [ ] **Step 1: Reconfirm each disposition**

Run:

```bash
rg -n 'gnome-settings-export|dconf load' README.md home tests
rg -n 'python|pyenv' home/.chezmoidata home/dot_tool-versions.tmpl
gh issue view 9 --repo kitos9112/dotfiles --json state,updatedAt,url
```

Expected: GNOME export/import is implemented and tested; `.tool-versions` has no Python owner; issue 9 is active.

- [ ] **Step 2: Close the three stale issues**

Run:

```bash
gh issue close 1287 --repo kitos9112/dotfiles --comment 'Implemented on the default branch. GNOME settings now use a curated `.chezmoidata/gnome.yaml` manifest, `gnome-settings-export` for filtered exports, an apply-time `dconf load` script, drift checks in `dotfiles-doctor`, and focused desktop integration contracts. Closing as completed.'
gh issue close 1529 --repo kitos9112/dotfiles --comment 'This is no longer applicable to the current setup: Python is not declared in the asdf plugin manifest or `.tool-versions`; Linux uses distribution Python packages. A future standalone-Python requirement should be opened with a concrete version and consumer.'
gh issue close 968 --repo kitos9112/dotfiles --comment 'Closing this stale Renovate dashboard as a duplicate of the actively maintained dependency dashboard in #9.'
```

Expected: issues 1287, 1529, and 968 are closed; issue 9 remains open.

---

### Task 2: Give duplicated developer tools one asdf owner

**Files:**
- Modify: `tests/packages-externals.test.sh`
- Modify: `tests/managed-config.test.sh`
- Modify: `home/.chezmoidata/asdf.yaml`
- Modify: `home/dot_tool-versions.tmpl`
- Modify: `home/.chezmoidata/packages.yaml`
- Modify: `home/.chezmoidata/versions.yaml`
- Modify: `home/.chezmoiexternal.yaml`
- Modify: `home/dot_zshrc.tmpl`
- Modify: `README.md`

**Interfaces:**
- Consumes: `asdf_plugins`, `.tool-versions`, and the existing asdf convergence script
- Produces: fzf and direnv as asdf plugins; Go, kubectl, fzf, and direnv with one declared owner

- [ ] **Step 1: Write failing ownership contracts**

Extend `tests/packages-externals.test.sh` to render apt, Homebrew, `.tool-versions`, and externals. Require the package lists to omit duplicate Go, kubectl, fzf, and direnv providers; require `.tool-versions` to contain these hand-checked pins:

```text
kubectl 1.37.0
golang 1.27.1
fzf 0.74.3
direnv 2.37.1
```

Require rendered externals to omit `.go`, `.local/bin/fzf`, and `.local/bin/direnv`. Restrict the external-version loop to `asdf`, `uv`, `nerd_fonts`, `retry`, and `vscode`.

In `tests/managed-config.test.sh`, replace the private-fzf fixture with an `asdf-shims/fzf` executable placed first on `PATH`. Have it return distinct Bash/Zsh marker functions and assert the rendered shell files load those markers through ordinary command lookup.

- [ ] **Step 2: Verify RED**

Run:

```bash
bash tests/packages-externals.test.sh
bash tests/managed-config.test.sh
```

Expected: failures identify duplicate package/external providers, missing asdf fzf/direnv pins, and the Zsh private-path preference.

- [ ] **Step 3: Implement the minimum ownership change**

Add to `home/.chezmoidata/asdf.yaml`:

```yaml
  - name: fzf
    url: https://github.com/kompiro/asdf-fzf.git
  - name: direnv
    url: https://github.com/asdf-community/asdf-direnv.git
```

Add `fzf 0.74.3` and `direnv 2.37.1` to `home/dot_tool-versions.tmpl`. Remove `direnv` from apt and `direnv`, `fzf`, `go`, and `kubernetes-cli` from Homebrew. Remove portable Go, fzf, and direnv externals and their release pins. Simplify Zsh to:

```zsh
if (( ${+commands[fzf]} )); then
  eval "$(fzf --zsh)"
fi
```

- [ ] **Step 4: Document safe migration**

Add a README ownership table. Explain that apply does not uninstall existing packages, asdf shims retain precedence, and optional cleanup is:

```bash
brew uninstall go kubernetes-cli fzf direnv
sudo apt-get remove direnv
```

- [ ] **Step 5: Verify GREEN and commit**

Run:

```bash
bash tests/packages-externals.test.sh
bash tests/managed-config.test.sh
bash tests/script-contracts.test.sh
task test
git add README.md home tests/packages-externals.test.sh tests/managed-config.test.sh
git commit -m "refactor(tools): consolidate developer tools under asdf"
```

Expected: all tests pass and the focused ownership commit contains no unrelated files.

---

### Task 3: Add Spanish as an additional locale

**Files:**
- Modify: `tests/profile-config.test.sh`
- Modify: `tests/script-contracts.test.sh`
- Modify: `home/.chezmoidata/locale.yaml`
- Modify: `home/.chezmoiscripts/run_onchange_before_03-linux-apt-packages.sh.tmpl`
- Modify: `home/.chezmoiscripts/run_once_before_01-linux-install-prereq.sh.tmpl`
- Modify: `README.md`

**Interfaces:**
- Consumes: `.locale.primary` and `.locale.additional`
- Produces: English primary locale plus Spanish locale support on Ubuntu, Fedora, and AlmaLinux

- [ ] **Step 1: Write failing locale contracts**

Render `{{ .locale | toJson }}` in `tests/profile-config.test.sh` and require:

```json
{"additional":["es_ES.UTF-8"],"primary":"en_GB.UTF-8"}
```

In `tests/script-contracts.test.sh`, render Ubuntu and AlmaLinux package scripts
with `DOTFILES_IS_ROOT=true`. Require Ubuntu to invoke `locale-gen` for both
values, AlmaLinux to include `glibc-langpack-en` and `glibc-langpack-es`, and
`localectl` to set only `LANG=en_GB.UTF-8`.

- [ ] **Step 2: Verify RED**

Run:

```bash
bash tests/profile-config.test.sh
bash tests/script-contracts.test.sh
```

Expected: failures identify scalar locale data, absent Spanish generation, and missing language packs.

- [ ] **Step 3: Implement structured locale data**

Replace the scalar with:

```yaml
locale:
  primary: en_GB.UTF-8
  additional:
    - es_ES.UTF-8
```

Render all locales as separately quoted `locale-gen` arguments. Add `glibc-langpack-en` and `glibc-langpack-es` to the existing Fedora/AlmaLinux package branch, and change `localectl` to use `.locale.primary` with an actionable warning on failure.

- [ ] **Step 4: Verify GREEN, document, and commit**

Run:

```bash
bash tests/profile-config.test.sh
bash tests/script-contracts.test.sh
task test
git add README.md home/.chezmoidata/locale.yaml home/.chezmoiscripts/run_onchange_before_03-linux-apt-packages.sh.tmpl home/.chezmoiscripts/run_once_before_01-linux-install-prereq.sh.tmpl tests/profile-config.test.sh tests/script-contracts.test.sh
git commit -m "feat(locale): add Spanish language support"
```

Expected: all tests pass; English remains the sole primary locale.

---

### Task 4: Make dnf and desktop packages declarative

**Files:**
- Modify: `tests/packages-externals.test.sh`
- Modify: `tests/script-contracts.test.sh`
- Modify: `tests/repository-policy.test.sh`
- Modify: `home/.chezmoidata/packages.yaml`
- Create: `home/.chezmoiscripts/run_onchange_before_03-linux-dnf-packages.sh.tmpl`
- Modify: `home/.chezmoiscripts/run_once_before_01-linux-install-prereq.sh.tmpl`
- Modify: `README.md`

**Interfaces:**
- Consumes: `packages.dnf.common`, its profile list, and its optional distribution/profile list
- Produces: one manifest-driven dnf convergence script for Fedora and AlmaLinux

- [ ] **Step 1: Write failing selection and policy contracts**

Extend `tests/packages-externals.test.sh` with literal rendered-package assertions:

- Ubuntu desktop includes `alacritty` and `wireshark`; Ubuntu server includes neither.
- Fedora desktop includes `alacritty` and `wireshark`; Fedora server includes neither.
- AlmaLinux desktop includes `wireshark` but not `alacritty`; AlmaLinux server includes neither.

Add the new dnf script to the syntax table in `tests/script-contracts.test.sh`
for AlmaLinux desktop/server and Fedora desktop, rendering with
`DOTFILES_IS_ROOT=true`. In `tests/repository-policy.test.sh`, require the old
prerequisite script to contain neither `dnf update` nor an embedded
Fedora/AlmaLinux package list.

- [ ] **Step 2: Verify RED**

Run:

```bash
bash tests/packages-externals.test.sh
bash tests/script-contracts.test.sh
bash tests/repository-policy.test.sh
```

Expected: failures identify absent application packages, missing dnf data/template, and the embedded one-time branch.

- [ ] **Step 3: Add package data**

Add `alacritty` and `wireshark` to `packages.apt.desktop`. Add the complete
`packages.dnf` manifest below. It preserves the existing Fedora/AlmaLinux
package set, moves the 1Password GUI to the desktop profile, retains Task 3's
language packs, and applies the native-only Alacritty overlay:

```yaml
  dnf:
    common:
      - 1password-cli
      - bison
      - bzip2
      - bzip2-devel
      - cronie
      - cronie-anacron
      - curl
      - dnf-automatic
      - file
      - gcc
      - g++
      - glibc-langpack-en
      - glibc-langpack-es
      - git
      - jq
      - libffi-devel
      - libxcrypt-compat
      - make
      - openssl-devel
      - patch
      - python
      - readline-devel
      - sqlite
      - sqlite-devel
      - tk-devel
      - tmux
      - unzip
      - util-linux-user
      - vim
      - xz
      - zlib-devel
      - zsh
    desktop:
      - 1password
      - wireshark
    server: []
    distributions:
      fedora:
        desktop:
          - alacritty
        server: []
      almalinux:
        desktop: []
        server: []
```

- [ ] **Step 4: Implement dnf convergence**

Create `run_onchange_before_03-linux-dnf-packages.sh.tmpl`. Guard it for root-enabled Fedora/AlmaLinux, resolve common + profile + distribution/profile lists, then `uniq | sortAlpha`. Fingerprint `.packages.dnf`, record machine class and OS release in comments, and execute:

```bash
sudo dnf install --yes "${packages[@]}"
sudo localectl set-locale LANG={{ .locale.primary | shellQuote }} || \
  log_manual_action "Could not set primary locale {{ .locale.primary }}"
```

Remove the Fedora/AlmaLinux update, package, and locale branch from `run_once_before_01-linux-install-prereq.sh.tmpl`. Preserve its Ubuntu/Debian and RHEL behavior.

- [ ] **Step 5: Verify GREEN, document, and commit**

Run:

```bash
bash tests/packages-externals.test.sh
bash tests/script-contracts.test.sh
bash tests/repository-policy.test.sh
task test
git add README.md home/.chezmoidata/packages.yaml home/.chezmoiscripts/run_onchange_before_03-linux-dnf-packages.sh.tmpl home/.chezmoiscripts/run_once_before_01-linux-install-prereq.sh.tmpl tests/packages-externals.test.sh tests/script-contracts.test.sh tests/repository-policy.test.sh
git commit -m "feat(linux): manage desktop packages by distribution"
```

Expected: all profile combinations and rendered shell syntax pass in one focused commit.

---

### Task 5: Verify, review, and update active issues

**Files:** Only files already named above if verification exposes a defect

**Interfaces:**
- Consumes: Tasks 2-4 commits
- Produces: reviewed branch, passing checks, and accurate issue progress

- [ ] **Step 1: Run full verification**

Run:

```bash
task test
uvx pre-commit run --all-files
git diff --check 747ba69..HEAD
git status --short --branch
```

Expected: zero failures and a clean working tree.

- [ ] **Step 2: Build representative smoke images when available**

Run:

```bash
podman build --build-arg BASE_IMAGE=ubuntu:24.04 -f tests/Dockerfile.ubuntu -t dotfiles-smoke:ubuntu-24.04 .
podman build --build-arg BASE_IMAGE=almalinux:9 -f tests/Dockerfile.almalinux -t dotfiles-smoke:almalinux-9 .
```

Expected: both complete their real `chezmoi init --apply` layer. If local Podman or corporate TLS prevents this, report the environmental limitation without weakening repository TLS; GitHub Actions remains authoritative.

- [ ] **Step 3: Request read-only code review**

Use the requesting-code-review skill against base `747ba69` and current HEAD. Fix Critical and Important findings test-first, then repeat Step 1.

- [ ] **Step 4: Comment on active issues without closing prematurely**

Post implementation summaries to issues 3004, 1286, and 1288. State that they close only after the commits are pushed and the full acceptance matrix passes.

- [ ] **Step 5: Record final state**

Run:

```bash
git log --oneline --decorate -6
git status --short --branch
```

Expected: design, plan, ownership, locale, and Linux-package commits exist; the worktree is clean; no push occurred without explicit authorization.
