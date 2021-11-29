# My Personal Public DOTfiles managed by `chezmoi`

This repo has been built for my own benefit, however feel free to sneak in and steal anything that would improve your own productivity. My plans are focused on start doing `CI` for ensuring that my changes won't break across different OS flavours. At the moment, I got Docker containers for the following Linux flavours:

- Fedora 35
- Ubuntu 20.04

## Installation instructions

I'd not care of using GitHub for backing up my `dotfiles` if my perspectives of using them remained in a single machine.
You can install this repo via a Convenient script or manually in its defect.

### Convenience script

In case of not having `chezmoi` installed - Just firing the `install.sh` after a simple download of it.

```bash
# Using Curl
sh -c "$(curl -fsSL https://git.io/JIoZb)"
# OR Using Wget
sh -c "$(wget -qO- https://git.io/JIoZb)"
```

### Manually with `git`

You will have to clone the repo and from its root directory, execute the `install` SH script

### Manually with `chezmoi`

Leveraging off-the-shelf `Chezmoi` capabilities

```bash
chezmoi init --apply --verbose https://github.com/kitos9112/dotfiles.git
```

## Security considerations

Having a local `.git` (A.K.A. submodule) folder inside your dotfiles could become dangerous as you're naturally exposing (or unconsciously prompted to) your git history and very specific local configuration. Not even to mention the burden it sometimes signifies.

As I just feed myself from the great works other `peers` conduct in the wild Internet (e.g. Oh-my-zsh), I'm a mere consumer of their work who clones their source code and thereby uses it.

My `scsripts/00_run_once/run_once_100-extras.zsh.tmpl` takes care of cloning/pulling(`--rebase`) their public GitHub repos.
