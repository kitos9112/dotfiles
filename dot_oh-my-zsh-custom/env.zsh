# Full list of logical env.variables to me!
export ZSH_CUSTOM=$ZSH_CUSTOM
export EDITOR="/usr/bin/vim"

# Go-related envs
export GOPATH=$HOME/Go
export GOBIN=$GOPATH/bin
export PATH=$GOBIN:$PATH

# User configuration
export MANPATH="/usr/local/man:$MANPATH"
export PYENV_ROOT="$HOME/.pyenv"

# IaC-related
export TFENV_AUTO_INSTAL=true
export TGENV_AUTO_INSTALL=true

# You may need to manually set your language environment
export LANG=en_GB.UTF-8

# Fix gpg: signing failed: Inappropiate ioctl for device
export GPG_TTY=$TTY

# Other alterations to PATH
export PATH=${HOME}/.local/bin:${HOME}/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}
export PATH=${HOME}/.tfenv/bin:${HOME}/.tgenv/bin:${PATH}

# Pyenv-related envs
eval "$(pyenv init -)"

if $(uname -a | grep -qPe "(M|m)icrosoft"); then
  # Hitting a WSL system :)
  export DISPLAY="$(/sbin/ip route | awk '/default/ { print $3 }'):0"
  export PATH=$PATH:/mnt/c/Windows/System32
fi
