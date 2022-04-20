#!/usr/bin/env sh
SCRIPT_PATH="$(
  cd -- "$(dirname "$0")" >/dev/null 2>&1
  pwd -P
)"

script -qec "zsh -is </dev/null" /dev/null

chezmoi update -a -v
exec "$@"
