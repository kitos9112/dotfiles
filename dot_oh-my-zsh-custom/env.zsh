# Full list of logical env.variables to me!
export ZSH_CUSTOM=$ZSH_CUSTOM
export EDITOR="/usr/bin/vim"
export TERM=xterm-256color

# Go-related envs
export GOPATH=$HOME/Go
export GOBIN=$GOPATH/bin
export PATH=$GOBIN:$PATH

# User configuration
export MANPATH="/usr/local/man:$MANPATH"
export PYENV_ROOT="$HOME/.pyenv"

# IaC-related
export TFENV_AUTO_INSTALL=true
export TGENV_AUTO_INSTALL=true

# You may need to manually set your language environment
export LANG=en_GB.UTF-8

# Fix gpg: signing failed: Inappropiate ioctl for device
export GPG_TTY=$TTY

#aws --version | grep -q "aws-cli/2" && source /usr/local/bin/aws_zsh_completer.sh
# Kubectl autocomplete
if [ $commands[kubectl] ]; then source <(kubectl completion zsh); fi

# Other alterations to PATH
export PATH=${PYENV_ROOT}:${HOME}/.local/bin:${HOME}/bin:${HOME}/.asdf/shims:${HOME}/.tfenv/bin:${HOME}/.tgenv/bin:$HOME/.poetry/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}

# Pyenv-related envs
eval "$(pyenv init -)"
# export PYENV_SHELL=zsh
# export PYENV_ROOT="$HOME/.pyenv"
# export PATH="$PYENV_ROOT/bin:$PATH"

# direnv
eval "$(direnv hook zsh)"
if $(uname -a | grep -qPe "(M|m)icrosoft"); then
  # Hitting a WSL system :)
  export DISPLAY="$(/sbin/ip route | awk '/default/ { print $3 }'):0"
  export PATH=$PATH:/mnt/c/Windows/System32
  DockerResourcesBin="/mnt/c/Program Files/Docker/Docker/resources/bin"
  export PATH=${PATH}:${DockerResourcesBin}
fi

# ASDF - Add a command-line fuzzy finder tool https://github.com/junegunn/fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Remove duplicated PATH entries
deduplicate_env_path
