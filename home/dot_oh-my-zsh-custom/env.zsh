# Full list of logical env.variables to me!
export ZSH_CUSTOM=$ZSH_CUSTOM
export EDITOR="/usr/bin/vim"
export TERM="xterm-256color"
export GPG_TTY=$TTY # Fix gpg: signing failed: Inappropiate ioctl for device

export MANPATH="/usr/local/man:$MANPATH"
export PYENV_ROOT="$HOME/.pyenv"

export XDG_CONFIG_HOME="${HOME}/.config"
export XDG_DATA_HOME="${HOME}/.data"
# XDG_STATE_HOME
#
# Lang-related settings
export LANG=en_GB.UTF-8

## Go-related envs
export GOPATH=$HOME/Go
export GOBIN=$GOPATH/bin
export PATH=$GOBIN:$PATH

## cargoup - RUST
export PATH=$HOME/.cargo/bin:$PATH

## IaC-related
export TFENV_AUTO_INSTALL=true
export TGENV_AUTO_INSTALL=true

# Other alterations to PATH
export PATH=${PYENV_ROOT}/bin:${HOME}/.local/bin:${HOME}/bin:${HOME}/.asdf/shims:${HOME}/.tfenv/bin:${HOME}/.tgenv/bin:$HOME/.poetry/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${KREW_ROOT:-$HOME/.krew}/bin:${PATH}

#aws --version | grep -q "aws-cli/2" && source /usr/local/bin/aws_zsh_completer.sh
# Kubectl autocomplete
if [ $commands[kubectl] ]; then source <(kubectl completion zsh); fi

# Pyenv-related envs
eval "$(pyenv init --path)"

# direnv
eval "$(direnv hook zsh)"
if $(uname -a | grep -qPe "(M|m)icrosoft"); then
  # Hitting a WSL system :)
  export DISPLAY="$(/sbin/ip route | awk '/default/ { print $3 }'):0"
  export PATH=$PATH:/mnt/c/Windows/System32
  DockerResourcesBin="/mnt/c/Program Files/Docker/Docker/resources/bin"
  export PATH=${PATH}:${DockerResourcesBin}
fi

# ssh-agent

# Sample script that will always reuse the same ssh-agent, or start ssh-agent if it is not running in the background
# set SSH_AUTH_SOCK env var to a fixed value
export SSH_AUTH_SOCK=~/.ssh/ssh-agent.sock

# test whether $SSH_AUTH_SOCK is valid
ssh-add -l 2>/dev/null >/dev/null

# if not valid, then start ssh-agent using $SSH_AUTH_SOCK. Ignore errors that may happen in WSL2
[ $? -ge 2 ] && ssh-agent -a "$SSH_AUTH_SOCK" 2>/dev/null

# ASDF - Add a command-line fuzzy finder tool https://github.com/junegunn/fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# GOROOT
export GOROOT=$(go env GOROOT)
