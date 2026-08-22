# Portable terminal font across macOS terminals

**Date:** 2026-08-22

## Problem

`.chezmoidata/fonts.yaml` already declared the terminal font, but only Ghostty,
the Linux font-cache script and `dotfiles-doctor` read it. WezTerm, Hyper,
Alacritty and Zellij each hardcoded `FiraMono Nerd Font`, so changing the font
was a five-file edit with no way to notice a file that had been missed. iTerm2
and Terminal.app were not covered at all.

The goal: changing the font is a one-line edit to `fonts.yaml`, and every
terminal follows.

## Design

`fonts.yaml` is the single source of truth. It gained two fields:

- `postScriptName` — required because the family name and the PostScript name
  are independent facts about the font file. `FiraMono Nerd Font` has the
  PostScript name `FiraMonoNF-Regular`; no string transformation connects them.
  File-configured terminals want the family, the macOS plist terminals want the
  PostScript name. Read it with
  `mdls -name com_apple_ats_name_postscript <face>.otf`.
- `size` — was copy-pasted into three configs.

| Terminal | Mechanism |
|---|---|
| Ghostty, Alacritty, Zellij | already templates; now read both values |
| WezTerm, Hyper | renamed to `.tmpl` so they can read them |
| iTerm2 | chezmoi-templated dynamic profile JSON |
| Terminal.app | `run_onchange` script editing exported preferences |

The guard test is `grep -r 'FiraMono' home/`, which must match only
`fonts.yaml`. It is asserted in `tests/bootstrap-profiles.test.sh`.

## Two findings that changed the design

**Terminal.app cannot be scripted into creating a profile.** The original plan
was to drive it over AppleScript, whose `settings set` class exposes `font name`
and `font size` as plain text. But `Terminal.sdef` declares the settings-set
collection `access="r"`: AppleScript can edit a profile that exists and cannot
create one. Since the chosen design is a dotfiles-owned profile, AppleScript
could not deliver it.

So Terminal.app is configured by generating the `NSKeyedArchiver`-encoded
`NSFont` with JXA — `osascript -l JavaScript`, built into macOS, no dependencies
— and editing an exported copy of the preferences with `plutil`, then
`defaults import`ing it back. The managed profile is seeded from whatever is
currently default, so colours and geometry carry over.

This turned out better than the original plan: no Automation consent prompt, and
Terminal.app is never launched.

**iTerm2 must not be configured with `defaults write`.** It holds preferences in
memory and rewrites the plist on quit, so a write to a running iTerm2 is
discarded. A dynamic profile is a plain JSON file in a directory iTerm2 watches
and hot-reloads, which sidesteps the problem entirely. Only the "make it the
default profile" step touches the plist, and it is skipped while iTerm2 runs.

## Constraints worth remembering

- Preferences must be edited via `defaults export`/`import`, not by writing
  `~/Library/Preferences` directly, which races cfprefsd's cache.
- The Terminal.app step is skipped while Terminal.app is running, since it would
  overwrite the change on quit.
- `mktemp -t` is not portable: a Mac with GNU coreutils ahead of `/usr/bin` gets
  GNU `mktemp`, which rejects a template with no `X`s.
- `base64`'s decode flag differs between the BSD and GNU builds, and `strings`
  ships with the Xcode command line tools. The doctor uses `openssl base64 -d`
  and `tr -cd '[:print:]'` instead.
- chezmoi does not manage anything under `~/Library`: it would take ownership of
  that directory's permissions, and `~/Library` is `0700`. The dynamic profile is
  staged in `~/.config/iterm2` and copied into place by the script.

## Linux

The file-based terminals need nothing extra: Ghostty, WezTerm, Alacritty, Hyper
and Zellij are the same templates on both platforms, and the font download and
`fc-cache` refresh were already keyed on `fonts.yaml`. `postScriptName` is unused
on Linux, since fontconfig addresses fonts by family.

GNOME Terminal is Linux's counterpart to Terminal.app: its font lives in dconf
rather than in a file this repo renders, so it can drift. `gnome.yaml` already
tracked `/org/gnome/terminal/legacy/`, which meant the next
`gnome-settings-export` would have committed the font as a literal into
`terminal-legacy.ini` and forked it from `fonts.yaml` permanently — inside a file
that reads as inert exported state.

The fix reuses the exclusion mechanism that was already there. A new
`gnome.fontKeys` list (`font`, `monospace-font-name`, `use-system-font`) is
stripped from every dump on export, and `run_onchange_after_30-gnome-settings`
writes the font back from `fonts.yaml` afterwards — after the `dconf load`, which
would otherwise overwrite it. `use-system-font` has to be turned off per profile,
or the profile ignores its own font key and silently keeps the system font.

`dconf` reports profiles as a GVariant list, which bash cannot parse, so the
script reduces it to bare comma-separated UUIDs. That reduction is covered by a
fake-`dconf` test with three cases — several profiles, an empty list falling back
to the recorded default, and no profiles at all — so it executes on macOS and in
CI instead of only on a GNOME desktop.

## Verification

`dotfiles-doctor`'s macOS font check previously gated on `fc-list`, a fontconfig
tool absent from stock macOS, so it reported "fontconfig not installed" on every
Mac and verified nothing. It now asks CoreText via JXA, and additionally compares
the font each plist terminal is *actually configured with* against `fonts.yaml`,
reported as a warning with the remedy. Installed and configured are different
questions, and only the second one catches drift.

On Linux the doctor keeps the fontconfig check and gains the GNOME Terminal
equivalent, comparing each profile's configured font against `fonts.yaml`.

## What is not verified end to end

macOS is applied and observed working: all four font checks pass, with the
`dotfiles` profile active in both Terminal.app and iTerm2.

Linux is verified at the template and contract level, plus the fake-`dconf`
test. Docker was not installed on the machine this was built on, so
`tests/Dockerfile.ubuntu` and the AlmaLinux image only run in CI, and no real
GNOME desktop has applied it yet. The first GNOME apply is the remaining unknown
— specifically whether `dconf write` reaches profiles that GNOME Terminal has
open at the time, which it caches much as Terminal.app does.
