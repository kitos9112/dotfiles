# Homebrew Trust Store Permissions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent Homebrew tap trust from failing when chezmoi or an earlier Homebrew setup leaves either trust-store directory group-writable.

**Architecture:** Encode `0700` for the managed XDG trust-store directory with chezmoi's `private_` directory attribute. The trust script also normalizes both trust-store directories before invoking Homebrew, covering the unmanaged legacy store.

**Tech Stack:** chezmoi source-state attributes, Bash, repository contract tests.

## Global Constraints

- Preserve the managed target path `~/.config/homebrew/brew.env`.
- Do not store secrets or machine-specific data in the repository.
- Keep the Homebrew trust script's existing nine-tap list and two-store behavior.

---

### Task 1: Add a failing trust-store regression test

**Files:**
- Modify: `tests/bootstrap-profiles.test.sh`

**Interfaces:**
- Consumes: `home/.chezmoiscripts/run_onchange_after_01-brew-trust-taps.sh.tmpl`
- Produces: a contract that both Homebrew stores are mode `0700` after the rendered script runs.

- [ ] **Step 1: Write the failing test**

Add a temporary `brew` executable that returns success, create `${HOME}/.config/homebrew` and `${HOME}/.homebrew` at `0775`, execute the rendered trust script, and assert both modes are `700`. Assert the source directory is named `private_homebrew`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/bootstrap-profiles.test.sh`

Expected: failure because the current source directory is `homebrew` and the script does not change trust-store modes.

### Task 2: Declare and normalize private stores

**Files:**
- Move: `home/private_dot_config/homebrew/brew.env` to `home/private_dot_config/private_homebrew/brew.env`
- Modify: `home/.chezmoiscripts/run_onchange_after_01-brew-trust-taps.sh.tmpl`

**Interfaces:**
- Consumes: `$HOME`, `XDG_CONFIG_HOME`, and the available `brew` command.
- Produces: private Homebrew trust-store directories before `brew trust --tap` runs.

- [ ] **Step 1: Implement the minimal change**

Rename the managed directory with the `private_` attribute. In the script, loop over `${HOME}/.config/homebrew` and `${HOME}/.homebrew`, create each directory, and run `chmod 700` before the two `brew trust` calls.

- [ ] **Step 2: Run test to verify it passes**

Run: `bash tests/bootstrap-profiles.test.sh`

Expected: success, including the new Homebrew trust-store checks.

### Task 3: Verify live source and machine state

**Files:**
- No repository files beyond Tasks 1–2.

- [ ] **Step 1: Check formatting and the focused test**

Run: `uvx pre-commit run --all-files` and `bash tests/bootstrap-profiles.test.sh`.

- [ ] **Step 2: Apply the repaired state**

Run: `chezmoi apply --force ~/.config/homebrew` followed by the rendered trust script or `chezmoi update` in an interactive terminal. Verify both stores are mode `700` and Homebrew accepts a trusted tap.
