![Nightly Build](https://github.com/kitos9112/dotfiles/actions/workflows/schedule-nightly-build.yaml/badge.svg)

# My Personal Public DOTfiles managed by `chezmoi`

This public Github repository has been built for my own benefit, however, feel free to sneak in and steal anything that would improve your own productivity.
My plans rely on maintaining a `CI` workflow alongside GitHub actions to ensure that my changes will not break across different OS flavours.
At the moment, I got Docker containers for the following Linux flavours:

- Fedora 40
- Ubuntu 22.04
- Ubuntu 24.04

## Installation instructions

I'd not care of using GitHub for backing up my `dotfiles` if my perspectives of using them remained in a single machine.
You can install this repo via a Convenient script or manually in its defect.

### Convenience script

In case of not having `chezmoi` installed - Just firing the `install.sh` after a simple download of it.

```bash

# Using Curl
sh -c "$(curl -fsSL https://raw.githubusercontent.com/kitos9112/dotfiles/master/install)"
# OR Using Wget
sh -c "$(wget -qO- https://raw.githubusercontent.com/kitos9112/dotfiles/master/install)"
```

### Manually with `git`

You will have to clone the repo and from its root directory, execute the `install` SH script

### Manually with `chezmoi`

Leveraging off-the-shelf `Chezmoi` capabilities

```bash
chezmoi init --apply --verbose https://github.com/kitos9112/dotfiles.git
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
