![Acceptance Tests](https://github.com/kitos9112/dotfiles/actions/workflows/acceptance-tests.yaml/badge.svg)

# My Personal Public DOTfiles managed by `chezmoi`

This public Github repository has been built for my own benefit, however, feel free to sneak in and steal anything that would improve your own productivity.
My plans rely on maintaining a `CI` workflow alongside GitHub Actions to ensure that my changes will not break across different OS flavours.
The current smoke-test matrix covers the following Linux flavours:

- AlmaLinux 9
- AlmaLinux 10
- Ubuntu 24.04
- Ubuntu 25.10

macOS is verified separately on a GitHub-hosted macOS runner by rendering and applying the repo into a temporary home directory.

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

## Verification

CI currently does two different checks:

- Linux container smoke tests build the Dockerfiles under [`tests/`](./tests) and run the standalone installer in `DOTFILES_TEST=true` mode.
- macOS smoke tests run `chezmoi init --apply` and `chezmoi verify` against a temporary home directory while excluding scripts.

To reproduce the macOS-style verification locally:

```bash
tmp_home="$(mktemp -d)"
HOME="${tmp_home}" \
XDG_CONFIG_HOME="${tmp_home}/.config" \
XDG_DATA_HOME="${tmp_home}/.local/share" \
XDG_STATE_HOME="${tmp_home}/.local/state" \
XDG_CACHE_HOME="${tmp_home}/.cache" \
DOTFILES_TEST=true chezmoi init --apply --source "$(pwd)" --exclude scripts --no-tty
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

Scripts are found in its own [directory](./home/.chezmoiscripts) to avoid being copied over to the target system.

## Security considerations

Having a local `.git` (A.K.A. submodule) folder inside your dotfiles could become dangerous as you're naturally exposing (or unconsciously prompted to) your git history and very specific local configuration. Not even to mention the burden it sometimes signifies.

As I just feed myself from the great works other `peers` conduct in the wild Internet (e.g. Oh-my-zsh), I'm a mere consumer of their work who clones their source code and thereby uses it.

My `scsripts/00_run_once/run_once_100-extras.zsh.tmpl` takes care of cloning/pulling(`--rebase`) their public GitHub repos.
