#!/usr/bin/env zsh

architecture() {
  if uname -a | grep -q x86; then echo 'amd'
  elif uname -a | grep -q armv; then echo 'arm'
  else
    echo 'Unknown architecture'
    exit 1
  fi
}

is_installed() {
  [[ -x "$(command -v $1)" ]]
}

is_cask_installed() {
  [[ -n "$(brew cask ls | grep $1)" ]]
}

is_brew_installed() {
  [[ -n "$(brew ls | grep $1)" ]]
}

# usage: `if was_successful; then`
was_successful() {
  [[ $? == 0 ]]
}

# usage: `if was_not_successful; then`
was_not_successful() {
  [[ $? != 0 ]]
}

successfully() {
  $*
  if [[ $? != 0 ]]; then
    echo ⛔️
    exit 1
  fi
}

started() {
  log_echo "▶️  $*"
}

success() {
  log_echo "✅ $*"
}

warn() {
  log_echo "⚠️  $*"
}

heading() {
  real_clear
  log_echo "- $*"
}

log_echo() {
  if [[ $CLEAR_SCREEN_BETWEEN_LOGS == "true" ]]; then
    log="$log
  $*"
    real_clear
  else
    echo
    echo "$*"
  fi
}

real_clear() {
  printf "\033c"
  clear
  echo "$log"
}

ensure_var() {
  if [[ $2 == "" ]]; then
    echo "Environment variable required $1"
    exit 1
  fi
}

capitalize() {
  cap_first="$(echo ${1:0:1} | tr '[a-z]' '[A-Z]')"
  cap_rest="${1:1}"
  echo $cap_first$cap_rest
}

check_sudo() {
  echo "Testing sudo, you may need to enter your password:"
  sudo echo "✅  sudo is good"
    if [[ $? != 0 ]]; then
    echo "💥  sudo auth failed"
    exit 1
  fi
}
