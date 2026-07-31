# Ubuntu Bootstrap v2 — Desktop/Server Profiles, 1Password, AI CLIs, GNOME Settings

**Date:** 2026-07-31
**Status:** Approved (design), pending implementation plan
**Scope:** Ubuntu 24.04/26.04 (Debian-family paths); existing Darwin/Fedora/RHEL behaviour unchanged unless noted.

## Goal

Bring fresh-box bootstrap to a "clone, run `install`, sign in to 1Password, done" experience for
both GUI desktops and CLI-only servers, with declarative package management, seeded AI-CLI
defaults, reproducible GNOME settings, and a post-bootstrap health check.

## Approach

Evolve the existing chezmoi idioms (numbered `.chezmoiscripts`, templates, `scripts/.helpers`)
rather than introducing a new installer framework or Ansible. All new behaviour keys off a new
`machine_class` data variable plus the existing `is_work` / `is_root` flags.

## 1. Machine profile (`machine_class`)

- New variable in `home/.chezmoi.toml.tmpl`: `machine_class = "desktop" | "server"`.
- Auto-detection (in order): `DOTFILES_PROFILE` env override → persisted value from a previous
  apply → GUI heuristics (`XDG_CURRENT_DESKTOP` non-empty, `gnome-shell` on PATH, or systemd
  default target `graphical.target`) → fallback `server`.
- Persisted via the same `promptStringOnce`-style pattern used for `is_work` so re-applies never
  re-detect differently. macOS is always `desktop`.
- Exported under `[data]` so scripts and file templates can guard on
  `eq .machine_class "desktop"`.

## 2. Declarative package lists

- New `home/.chezmoidata/packages.yaml`:
  ```yaml
  packages:
    apt:
      common: [ ... current prereq list ... ]
      desktop: [ 1password, 1password-cli ]
      server: [ 1password-cli ]
    brew:
      common: [ ... current linuxbrew list ... ]
      taps: [ common-fate/granted, ... ]
  ```
- `run_once_before_01-linux-install-prereq.sh.tmpl` shrinks to true one-time prep (apt update,
  locale). Package installation moves to a new
  `run_onchange_before_03-linux-apt-packages.sh.tmpl` that embeds a hash of the relevant
  package lists in a template comment so YAML edits re-trigger installs on existing boxes.
- Same treatment for the linuxbrew script → `run_onchange_` keyed on `.packages.brew`.
- Repo/key setup (1Password apt repo, debsig policy) stays in
  `run_once_before_00-linux-prepare.sh.tmpl`, gated on `is_root`.

## 3. 1Password bootstrap

**Desktop:**
- apt installs `1password` + `1password-cli` (via the desktop package list).
- New `run_once_after_20-1password-signin.sh.tmpl` (desktop + TTY only):
  1. Skip if `op account list` already returns an account.
  2. Launch the 1Password app (`1password --silent &` then bring to front) and print
     instructions: open 1Password on your phone → Settings → "Set up another device" → scan the
     QR from the desktop app's "Scan your Setup Code" screen.
  3. Poll `op account list` (with the CLI–app integration enabled) up to a timeout (~5 min),
     then confirm sign-in and enable: CLI integration, SSH agent
     (`~/.config/1Password/ssh/agent.toml`), and system-autostart.
  4. On timeout: print a resume command and exit 0 (never fail the apply).

**Server:**
- Only `1password-cli` installed.
- Same script's server branch: if TTY and no account configured, run `op account add`
  interactively (address/email/secret key/password); if no TTY, print a clear
  "run `op signin` when ready" notice and exit 0.

Existing `executable_dot_op-ssh-agent.sh` and git signing config remain the consumers.

## 4. Ghostty terminal (desktop only)

- Install from the `ghostty-ubuntu` project's deb release (arch- and series-aware URL), falling
  back to snap if the deb fetch fails. Managed by a `run_onchange_` script pinned to a version
  in `packages.yaml` (`packages.ghostty.version`) so Renovate can bump it.
- New managed config `home/private_dot_config/ghostty/config` seeded from the WezTerm config's
  look & feel: MesloLGS Nerd Font, same color theme, comparable keybinds.

## 5. AI CLIs: claude, opencode, codex (all boxes)

- New `run_onchange_after_40-install-ai-clis.sh.tmpl`:
  - `claude`: official native installer (`curl -fsSL https://claude.ai/install.sh | bash`);
    binary self-updates thereafter.
  - `opencode`: official install script (`curl -fsSL https://opencode.ai/install | bash`).
  - `codex`: `npm install -g @openai/codex` (node guaranteed by asdf/brew layer).
  - Script content embeds the desired channel/version pins from `packages.yaml` so bumps
    re-run it.
- Seeded default configs (templates, chezmoi-managed):
  - `home/dot_claude/settings.json.tmpl` + `home/dot_claude/CLAUDE.md` (global defaults:
    model, permissions posture, statusline, RTK reference).
  - `home/private_dot_config/opencode/opencode.json.tmpl`.
  - `home/dot_codex/config.toml.tmpl`.
- Authentication stays per-box first-run; `doctor` reports auth status. Configs must tolerate
  the tools appending their own state (chezmoi will show drift; acceptable — documented).

## 6. GNOME settings export/import (desktop only)

- Curated dconf paths, one `.ini` per path under `home/dot_data/gnome/`:
  - `/org/gnome/desktop/wm/keybindings/`
  - `/org/gnome/settings-daemon/plugins/media-keys/`
  - `/org/gnome/desktop/interface/` (theme, fonts, clock)
  - `/org/gnome/desktop/input-sources/`
  - `/org/gnome/desktop/peripherals/`
  - `/org/gnome/settings-daemon/plugins/power/`
  - `/org/gnome/desktop/session/`
  - `/org/gnome/shell/` **excluding** transient keys (`command-history`, `app-picker-layout`)
  - `/org/gnome/terminal/legacy/` (profiles)
- `run_onchange_after_30-gnome-settings.sh.tmpl`: for each file, `dconf load <path> < file`;
  guarded on `machine_class == desktop` and a running dbus session.
- `task gnome-export`: re-dumps each curated path into the repo (`dconf dump`), applying the
  exclusion filters, ready to diff/commit.
- Explicitly out of scope: monitor layout, window geometry, recent files, extension
  *installation* (settings for installed extensions are captured under `/org/gnome/shell/`).

## 7. Nerd Font (desktop only)

- MesloLGS Nerd Font (4 styles) via `.chezmoiexternal.yaml` →
  `~/.local/share/fonts/MesloLGS/`, with a `run_onchange_` `fc-cache -f` refresh.
- Referenced by Ghostty config and p10k.

## 8. Doctor

- `scripts/doctor.sh` + `task doctor`: green/red checklist, exit non-zero on failures:
  - chezmoi version & pending drift
  - op CLI present; account configured; `op whoami` succeeds
  - SSH agent socket present; `ssh-add -l` via 1P agent; git signing config resolves
  - apt/brew health (`brew doctor` abridged)
  - claude / opencode / codex on PATH; version prints; auth state
  - desktop-only: Ghostty installed, fonts present (`fc-list | grep MesloLGS`), dconf values
    match repo files
  - zsh is the default shell

## Error handling conventions

- All scripts: `set -e -o pipefail`, source `scripts/.helpers`.
- Anything interactive is TTY-guarded (`stdinIsATTY` at template level, `[ -t 0 ]` at runtime);
  unattended applies never hang or fail on missing interaction — they print a resume hint and
  exit 0.
- Network installs retried via existing helper conventions; failures in optional components
  (fonts, Ghostty fallback) warn but don't abort the apply.

## Testing

- Extend `tests/` container setup: Ubuntu 24.04 image runs a full server-profile apply with
  `DOTFILES_PROFILE=server DOTFILES_IS_WORK=false` non-interactively; asserts packages, AI CLI
  binaries, seeded configs, and that no script blocked on input.
- Desktop-only scripts get dry-run/lint coverage (shellcheck via pre-commit) since containers
  lack a GUI; GNOME load script tested with a mocked `dconf` shim.
- GitHub workflow updated to run the server-profile test.

## Out of scope

- 1Password service accounts / Connect.
- GNOME extension installation.
- WSL-specific behaviour changes (existing detection kept).
- Fedora/RHEL parity for the new desktop features (guards make them Ubuntu-first, harmless
  elsewhere).
