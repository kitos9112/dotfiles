# My Personal Public DOTfiles

This repo has been built for my own benefit, however feel free to sneak in and steal anything that would benefit your own productivity.

## Installation instructions

I'd not care of using GitHub for backing up my dotfiles if my perspectives of using them remained in a single machine.
You can install this repo via a Convenient script or manually in its defect.

### Convenience script

Just firing the `install.sh` after a simple download of it.

```bash
 sh -c "$(curl -fsSL https://git.io/Jkf5l)"
 # OR
 sh -c "$(wget -qO- https://git.io/Jkf5l)"
```

### Manually

You will have to clone the repo and execute the `install.sh` script

```bash
> git clone https://github.com/kitos9112/dotfiles.git "$HOME/.dotfiles" && "$HOME/.dotfiles/install.sh"
```

## Security considerations

Having a local `.git` (A.K.A. submodule) folder inside your dotfiles could become dangerous as you're naturally exposing (or unconsciously prompted to) your git history and specific configuration.
As I just feed myself from the great works other peers performed in the wild Internet (e.g. Oh-my-zsh), I'm a mere user who clones their source code thereby use it. My `run_once_100-extras.zsh.tmpl` takes care of cloning/pulling(`--rebase`) their public GitHub repos. 
