# My Personal Public DOTfiles managed by `chezmoi`

![Acceptance Tests](https://github.com/kitos9112/dotfiles/actions/workflows/acceptance-tests.yaml/badge.svg)

This public Github repository has been built for my own benefit, however, feel free to sneak in and steal anything that would improve your own productivity.
My plans rely on maintaining a `CI` workflow alongside GitHub Actions to ensure that my changes will not break across different OS flavours.
The current smoke-test matrix covers the following Linux flavours:

- AlmaLinux 9
- AlmaLinux 10
- Ubuntu 24.04
- Ubuntu 26.04

macOS is verified separately on a GitHub-hosted macOS runner by rendering and applying the repo into a temporary home directory.

The minimum supported chezmoi version is **2.72.0**. CI runs the same contract
suite against both that floor and the latest release.

## Installation instructions

I'd not care of using GitHub for backing up my `dotfiles` if my perspectives of using them remained in a single machine.
You can install this repo via a Convenient script or manually in its defect.

### Convenience script

If `chezmoi` is not installed yet, run the standalone `install` script directly.

```bash
# Using Curl
sh -c "$(curl -fsSL https://raw.githubusercontent.com/kitos9112/dotfiles/master/install)"
```

```bash
# OR Using Wget
sh -c "$(wget -qO- https://raw.githubusercontent.com/kitos9112/dotfiles/master/install)"
```

### Manually with `git`

Clone the repo and execute the `install` script from its root directory.

### Manually with `chezmoi`

Leveraging off-the-shelf `Chezmoi` capabilities

```bash
chezmoi init --apply --verbose https://github.com/kitos9112/dotfiles.git
```

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
  default machine inference while rendering chezmoi config. An unrecognised
  `DOTFILES_IS_ROOT` fails the render rather than guessing.

## Sudo on work machines

`is_root` records whether sudo may be used to install system packages (apt,
Homebrew, the 1Password repository). Work machines default to `false` because
they are often locked down, but many do grant sudo, and those need the packages.

Resolution order is `DOTFILES_IS_ROOT`, then the value persisted in
`~/.config/chezmoi/chezmoi.toml`, then `false` on work machines and `true`
elsewhere. On a first interactive `chezmoi init` of a work machine you are asked
once and the answer is stored, so later runs need no environment variable.

To grant sudo on a work machine that was already set up as locked down:

```sh
DOTFILES_IS_ROOT=true chezmoi init --apply
```

The install scripts resolve this through
[`home/.chezmoitemplates/is-root`](./home/.chezmoitemplates/is-root) rather than
reading `is_root` from the config, because chezmoi only re-renders the config
template on `init`. Without that, `DOTFILES_IS_ROOT=true` would be ignored by a
plain `chezmoi apply` and no packages would install.

## Homebrew

Homebrew is a separate decision from sudo. Having root to install apt packages
says nothing about wanting linuxbrew, so `use_homebrew` is its own flag:

| | macOS | Linux |
| --- | --- | --- |
| Default | on | **off** |
| Override | `DOTFILES_HOMEBREW=true\|false` | same |
| Prompt | never | once, on an interactive `init` |

Resolution mirrors `is_root`: environment override, then the persisted value,
then the platform default. It lives in
[`home/.chezmoitemplates/use-homebrew`](./home/.chezmoitemplates/use-homebrew).

So a work machine with sudo installs the apt list and no Homebrew, and a personal
Linux box opts in once:

```sh
DOTFILES_HOMEBREW=true chezmoi init --apply
```

The formulae in `packages.brew` are simply skipped on machines without Homebrew;
they are not reinstalled from another source. Tools that matter everywhere come
from apt, asdf or the Go tool manifest instead.

Portable VS Code, Go and direnv follow **`use_homebrew` being false**, not sudo,
because they stand in for Homebrew-installed tooling. A sudo-capable machine that
opted out of brew still gets them.
- `DOTFILES_PROFILE=desktop|server` overrides GUI auto-detection (see below). An
  unrecognised value fails the render rather than guessing.

## Machine profiles

Every machine resolves to a `machine_class` of `desktop` (a GUI is present) or
`server` (CLI only). Detection order is `DOTFILES_PROFILE`, then the value
persisted in `~/.config/chezmoi/chezmoi.toml`, then GUI auto-detection
(`XDG_CURRENT_DESKTOP`, `DESKTOP_SESSION`, `WAYLAND_DISPLAY` or `gnome-shell` on
`PATH`), then `server`. The logic lives in
[`home/.chezmoitemplates/machine-class`](./home/.chezmoitemplates/machine-class)
and is resolved on every render, so a machine whose config predates the setting
still classifies correctly.

What the profile changes:

| Component | `desktop` | `server` |
| --- | --- | --- |
| 1Password | app plus CLI, QR sign-in walkthrough | CLI only, `op account add` |
| Ghostty | installed and configured | skipped |
| Nerd Font and `fc-cache` | installed | skipped |
| GNOME dconf settings | imported | skipped |
| AI CLIs, apt/brew packages | installed | installed |

Bootstrap a headless box with no prompts:

```sh
DOTFILES_PROFILE=server DOTFILES_NO_TTY=true sh -c "$(curl -fsLS https://raw.githubusercontent.com/kitos9112/dotfiles/master/install)"
```

1Password sign-in is skipped when there is no TTY; finish it later with
`op account add` on a server, or by signing into the app on a desktop. Nothing in
the bootstrap blocks waiting for input.

## Packages

apt and Homebrew manifests live in
[`home/.chezmoidata/packages.yaml`](./home/.chezmoidata/packages.yaml), split into
`common`, `desktop` and `server` lists. The installers are `run_onchange_`
scripts fingerprinted against those lists, so adding a package reaches existing
machines on the next `chezmoi apply` — not just freshly bootstrapped ones.

Data files must be literal `.chezmoidata/*.yaml`. chezmoi does not template data
files, so a `.chezmoidata.yaml.tmpl` is loaded by nothing and its values silently
disappear from the template data.

Archive and standalone-binary versions live in
[`home/.chezmoidata/versions.yaml`](./home/.chezmoidata/versions.yaml). Renovate
proposes updates to that reviewed manifest; chezmoi rendering never calls GitHub
release APIs or writes a cache into the source tree. This keeps `chezmoi diff`,
`apply`, and the template contracts deterministic when offline.

ASDF plugin registration is declared separately in
[`home/.chezmoidata/asdf.yaml`](./home/.chezmoidata/asdf.yaml). A single
`run_onchange_` script adds missing plugins and runs `asdf install` once when the
plugin manifest or `.tool-versions` changes. Rust's toolchain and pinned cargo
tools are declared under `packages.rust`.

`chezmoi apply` installs declared state but does not perform general maintenance
such as `brew upgrade` or `asdf plugin update --all`. Run those commands
explicitly when you intend to upgrade the machine; reviewed version changes
belong in the manifests above.

## GNOME settings

A curated set of dconf paths is version controlled, listed in
[`home/.chezmoidata/gnome.yaml`](./home/.chezmoidata/gnome.yaml). Monitor layout,
window geometry and recently-used files are deliberately excluded so machines do
not fight each other.

```sh
task gnome-export   # dump the current session's settings into this repo
task doctor         # report drift between the repo and the live session
```

Exports land in `home/private_dot_config/dotfiles/gnome/` for review before
committing. On another desktop, `chezmoi apply` replays them via `dconf load`.

## Starting over from scratch

To get back to a pre-init state and bootstrap again:

```sh
dotfiles-reset          # dry run: prints exactly what would be removed
dotfiles-reset --yes    # remove chezmoi config, state, cache and source checkout
```

`task reset -- --yes` does the same. This clears `~/.config/chezmoi` (which holds
`chezmoistate.boltdb`, the `run_once` and `run_onchange` bookkeeping),
`~/.cache/chezmoi` and the source checkout, so every script becomes eligible to
run again. Files already applied into `$HOME` are deliberately left alone —
removing those would take unmanaged dotfiles with them. Add `--keep-source` to
reset state while keeping the checkout you are working in.

A first init is not expected to be all-or-nothing: steps that are conveniences
rather than prerequisites (asdf toolchain builds, package installation, GNOME
imports) warn and continue instead of aborting the apply, so
one missing build dependency cannot leave the rest of the dotfiles unapplied.
Run `task doctor` afterwards to see what actually landed.

## Health check

```sh
task doctor
```

Checks the profile, chezmoi drift, 1Password sign-in, the SSH agent and git
signing helper, the AI CLIs, the terminal font, and GNOME drift. Non-applicable
checks are reported as skipped; only real breakage sets a non-zero exit code.

## Local Chezmoi Data

Machine-specific values should live in local chezmoi config, not in the public repo. This repo already reads data from `~/.config/chezmoi/chezmoi.toml`.

For Git identity, the default profile uses `personal_name` and `personal_email` when present. If `is_work = true` and `work_email` is set, the machine-wide default becomes the work identity. A work-only Git profile is also available via `work_gitdir` for path-based overrides.

Example:

```toml
[data]
  personal_name = "Marcos Soutullo"
  personal_email = "personal@example.com"

  work_name = "Marcos Soutullo"
  work_email = "work@example.com"
  work_gitdir = "~/workspace/company/"
```

With that configuration:

- `~/.gitconfig` uses your personal identity by default, or your work identity when `is_work = true`.
- `~/.gitconfig-work` is rendered automatically.
- Git switches to the work identity only for repositories under `work_gitdir`.

Existing installations should add those keys to `~/.config/chezmoi/chezmoi.toml` and then run `chezmoi apply`.

## Public-safe environment pointers

The tracked `.env` file is allowed to exist in this public repository only for
public-safe pointer values, such as 1Password item references. Do not store raw
tokens, credentials, private keys, recovery codes, or machine-confidential
values in `.env` or any other tracked file.

## Verification

CI currently does four complementary checks:

- Linux container smoke tests build the Dockerfiles under [`tests/`](./tests) and run the standalone installer in `DOTFILES_TEST=true` mode. The Ubuntu image pins `DOTFILES_PROFILE=server`, which is the headless path.
- macOS smoke tests run `chezmoi init --apply` and `chezmoi verify` against a temporary home directory while excluding scripts.
- The Go-tool job verifies the module graph and compiles every declared Go tool
  with the manifest's pinned Go version.
- The contracts job runs `task test` with chezmoi 2.72.0 and with the latest
  release. The focused suites cover profiles, packages/externals, desktop
  integrations, scripts, managed config, repository policy, FreeIPA, Go tools,
  Wireshark profiles, and shell-history backup behavior.

Run the complete fast suite locally with:

```bash
task test
```

`task test-bootstrap` remains as a compatibility alias for the same suite.

To reproduce the macOS-style verification locally:

```bash
tmp_home="$(mktemp -d)"
HOME="${tmp_home}" \
XDG_CONFIG_HOME="${tmp_home}/.config" \
XDG_DATA_HOME="${tmp_home}/.local/share" \
XDG_STATE_HOME="${tmp_home}/.local/state" \
XDG_CACHE_HOME="${tmp_home}/.cache" \
DOTFILES_TEST=true chezmoi init --apply --source "$(pwd)" --exclude scripts --no-tty --error-on-conflict
```

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

## Portable VS Code

If the portable Linux tarball is installed at `~/.apps/vscode`, chezmoi now manages the VS Code launcher directly as code:

- `~/.local/share/applications/code.desktop`
- `~/.local/share/applications/vscode-portable.desktop`
- `~/Desktop/Visual Studio Code.desktop`

The desktop entries prefer a managed local icon named `vscode-portable`, and a hidden `code.desktop` alias helps GNOME/Ubuntu match the running VS Code window to the portable launcher.

If `~/.apps/vscode` was previously added to chezmoi source state by mistake, remove it once with:

```bash
chezmoi forget --force ~/.apps/vscode
```

## Chezmoi scripts

Chezmoi uses general-purpose scripts to execute ordered operations in the system. They can run either:

- Every time you run `chezmoi apply` (`run` scripts)
- When their contents change (`run_once` or `run_onchange` scripts)

[Application order](https://www.chezmoi.io/reference/application-order/)

Bootstrap order on Linux, after the 1Password repository and keys are in place:

| Script | Purpose |
| --- | --- |
| `run_onchange_before_03-linux-apt-packages` | apt packages for the resolved profile, then `locale-gen` |
| `run_onchange_before_04-linux-brew-packages` | Homebrew and its formulae |
| `run_onchange_after_080-asdf-tools` | missing ASDF plugins and the versions in `.tool-versions` |
| `run_onchange_after_103-rust-dev` | the Rust toolchain and pinned cargo tools |
| `run_once_after_10-linux-install-session-manager` | AWS Session Manager on AlmaLinux/Fedora |
| `run_once_after_20-1password-signin` | 1Password sign-in (app QR, or `op account add`) |
| `run_onchange_after_25-install-ghostty` | Ghostty deb, desktop only |
| `run_onchange_after_30-gnome-settings` | `dconf load` of the committed settings |
| `run_onchange_after_35-refresh-font-cache` | `fc-cache` after the Nerd Font external lands |
| `run_onchange_after_40-install-ai-clis` | `claude`, `opencode` and `codex` |

### AI CLI defaults

The AI CLIs are installed with their own installers so they keep self-updating.
Their baseline configs use chezmoi's `create_` attribute, which writes the file
only when it does not already exist — an already-configured machine keeps its
own `~/.claude/settings.json`, `~/.config/opencode/opencode.json` and
`~/.codex/config.toml` untouched.

### Go developer tools

Go-based command-line tools are declared in
[`home/private_dot_config/dotfiles/go-tools/go.mod`](./home/private_dot_config/dotfiles/go-tools/go.mod).
Chezmoi installs that manifest as `~/.config/dotfiles/go-tools/go.mod`, then
`run_onchange_after_104-install-go-tools.zsh.tmpl` runs `go install tool`
through the Go version selected by asdf.

The installer reruns only when `go.mod`, `go.sum`, or the managed Go runtime
changes. It deliberately clears inherited `GOROOT`, `GOPATH`, and `GOBIN`
before entering the asdf environment, preventing an upgraded compiler from
using the previous Go version's standard library.

Renovate's native Go module manager updates tool requirements in this
manifest. Add another Go CLI with Go 1.24 or newer by running:

```bash
~/.local/bin/asdf exec go -C home/private_dot_config/dotfiles/go-tools \
  get -tool example.com/tool/cmd/tool@v1.2.3
```

Scripts are found in its own [directory](./home/.chezmoiscripts) to avoid being copied over to the target system.

## Security considerations

Having a nested `.git` directory in managed dotfiles can expose history or
machine-specific configuration. Third-party public repositories are therefore
declared as chezmoi `git-repo` externals in `home/.chezmoiexternal.yaml` instead
of being copied into this repository.
