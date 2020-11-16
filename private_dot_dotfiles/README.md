# My Personal Public DOTfiles managed by `chezmoi`

This repo has been built for my own benefit, however feel free to sneak in and steal anything that would benefit your own productivity. My plans are focused on start doing `CI` for ensuring that my changes won't break across different OS flavours.

## Installation instructions

I'd not care of using GitHub for backing up my `dotfiles` if my perspectives of using them remained in a single machine.
You can install this repo via a Convenient script or manually in its defect.

### Convenience script

In case of not having `chezmoi` installed - Just firing the `install.sh` after a simple download of it.

```bash
# Using Curl
 sh -c "$(curl -fsSL https://git.io/Jkf5l)"
# Using Wget
 sh -c "$(wget -qO- https://git.io/Jkf5l)"
```

### Manually with `git`

You will have to clone the repo and execute the `install.sh` script

### Manually with `chezmoi`

Leveraging Chezmoi capabilities

```bash
> chezmoi init https://github.com/kitos9112/dotfiles.git "$HOME/.dotfiles" && "$HOME/.dotfiles/install.sh"
```

## Security considerations

Having a local `.git` (A.K.A. submodule) folder inside your dotfiles could become dangerous as you're naturally exposing (or unconsciously prompted to) your git history and specific configuration.
As I just feed myself from the great works other peers performed in the wild Internet (e.g. Oh-my-zsh), I'm a mere user who clones their source code thereby use it. My `run_once_100-extras.zsh.tmpl` takes care of cloning/pulling(`--rebase`) their public GitHub repos.
