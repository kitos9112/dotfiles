# Go-Native Developer Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the ad hoc gmailctl installer with a Renovate-compatible Go tool manifest and make installs survive asdf Go upgrades.

**Architecture:** Chezmoi deploys a `go.mod`/`go.sum` tool manifest under `~/.config/dotfiles/go-tools`. A change-triggered installer calls asdf directly, clears stale Go variables, installs every declared tool into the active asdf Go version, and refreshes shims.

**Tech Stack:** chezmoi templates, Bash/Zsh, asdf, Go 1.26, Go module tool directives, Renovate gomod manager.

## Global Constraints

- Keep the change limited to Go-native developer-tool management and its asdf handoff.
- Preserve the existing asdf runtime manager and current PATH precedence.
- Do not publish the associated GitHub issue without explicit user approval.
- Keep every tracked file suitable for a public repository.

---

### Task 1: Add a failing Go-tool installer regression test

**Files:**
- Create: `tests/go-tools.test.sh`
- Test: `tests/go-tools.test.sh`

**Interfaces:**
- Consumes: the existing chezmoi templates and repository root layout.
- Produces: a hermetic contract for the Go-tool installer and asdf failure propagation.

- [ ] **Step 1: Write the failing test**

Create a shell test that builds a temporary home, renders the Go-tool and asdf
update templates, and installs a recording executable at
`~/.local/bin/asdf`. Start the Go-tool installer with stale `GOROOT`, `GOPATH`,
and `GOBIN`, plus a `PATH` that excludes asdf. Assert that the recording
executable receives:

```text
exec go -C <temporary-home>/.config/dotfiles/go-tools install tool
reshim golang
```

Record the Go variables seen by the fake asdf executable and assert all three
are unset. Assert that the rendered installer contains three SHA-256
fingerprints. Make fake `asdf install` fail while testing script `099` and
assert that its exit status is non-zero.

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bash tests/go-tools.test.sh
```

Expected: FAIL because the manifest and change-triggered installer do not yet
exist, and the current asdf update script suppresses installation errors.

- [ ] **Step 3: Commit the red test**

```bash
git add tests/go-tools.test.sh
git commit -m "test: cover Go tool installation across asdf upgrades"
```

### Task 2: Add the Go-native manifest and reliable installer

**Files:**
- Create: `home/private_dot_config/dotfiles/go-tools/go.mod`
- Create: `home/private_dot_config/dotfiles/go-tools/go.sum`
- Create: `home/.chezmoiscripts/run_onchange_after_104-install-go-tools.zsh.tmpl`
- Delete: `home/.chezmoiscripts/run_after_104-go-dev.zsh.tmpl`
- Modify: `home/.chezmoiscripts/run_after_099-update-asdf.sh.tmpl`
- Test: `tests/go-tools.test.sh`

**Interfaces:**
- Consumes: `~/.local/bin/asdf`, `~/.asdf`, and the Go version selected by `~/.tool-versions`.
- Produces: `gmailctl` in the selected asdf Go installation and a refreshed asdf shim.

- [ ] **Step 1: Add the Go manifest**

Add a Go 1.26.5 module named `dotfiles.tools` with:

```go
tool github.com/mbrt/gmailctl/cmd/gmailctl
```

Require `github.com/mbrt/gmailctl v0.12.0` and commit the complete module graph
and checksums produced by `go get -tool`.

- [ ] **Step 2: Implement the change-triggered installer**

The rendered script must use strict Zsh options, fingerprint `go.mod`,
`go.sum`, and `dot_tool-versions.tmpl`, verify the managed asdf binary exists,
and execute:

```zsh
env -u GOROOT -u GOPATH -u GOBIN \
  ASDF_DATA_DIR="${HOME}/.asdf" \
  "${HOME}/.local/bin/asdf" exec go \
  -C "${HOME}/.config/dotfiles/go-tools" install tool

"${HOME}/.local/bin/asdf" reshim golang
```

- [ ] **Step 3: Propagate asdf installation failures**

Remove `|| echo ""` from the non-WSL `asdf install` invocation in script `099`
so a missing runtime cannot be reported as successfully installed.

- [ ] **Step 4: Run the focused test**

Run:

```bash
bash tests/go-tools.test.sh
```

Expected: PASS.

- [ ] **Step 5: Validate the real manifest**

Run:

```bash
go -C home/private_dot_config/dotfiles/go-tools mod verify
go -C home/private_dot_config/dotfiles/go-tools list -m all
```

Expected: module checksums verify and the dependency graph resolves.

- [ ] **Step 6: Commit the implementation**

```bash
git add home/private_dot_config/dotfiles/go-tools \
  home/.chezmoiscripts/run_onchange_after_104-install-go-tools.zsh.tmpl \
  home/.chezmoiscripts/run_after_104-go-dev.zsh.tmpl \
  home/.chezmoiscripts/run_after_099-update-asdf.sh.tmpl
git commit -m "feat: manage Go developer tools declaratively"
```

### Task 3: Document, validate, and prepare the unpublished issue

**Files:**
- Modify: `README.md`
- Create outside the repository: `/private/tmp/chezmoi-dev-tools-consolidation-issue.md`
- Test: all repository checks.

**Interfaces:**
- Consumes: the final Go-tool manifest and installer behavior.
- Produces: operator documentation and a public-safe issue draft that has not been submitted.

- [ ] **Step 1: Document Go tool ownership**

Add a concise README section identifying
`~/.config/dotfiles/go-tools/go.mod` as the source of Go CLI versions,
explaining that Renovate updates it and that `run_onchange` installs tools
after manifest or Go runtime changes.

- [ ] **Step 2: Draft the GitHub issue locally**

Write a public-safe issue describing duplicated installers, dynamic
latest-version resolution, unpinned Cargo tools, PATH/environment ownership,
and CI's exclusion of scripts. Include a staged consolidation roadmap, without
private machine details or credentials.

- [ ] **Step 3: Run focused and existing shell tests**

Run:

```bash
bash tests/go-tools.test.sh
bash tests/wireshark-profiles.test.sh
bash tests/backup-shell-history-to-1password.sh
```

Expected: all tests pass.

- [ ] **Step 4: Run repository validation**

Run:

```bash
uvx pre-commit run --all-files
```

Expected: all hooks pass.

- [ ] **Step 5: Review the issue command without executing it**

Prepare, but do not execute:

```bash
gh issue create \
  --title "Consolidate developer tool installation and version ownership" \
  --body-file /private/tmp/chezmoi-dev-tools-consolidation-issue.md
```

- [ ] **Step 6: Commit documentation**

```bash
git add README.md docs/superpowers/specs/2026-07-30-go-native-dev-tools-design.md \
  docs/superpowers/plans/2026-07-30-go-native-dev-tools.md
git commit -m "docs: explain Go developer tool management"
```
