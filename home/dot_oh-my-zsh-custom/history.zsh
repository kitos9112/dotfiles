# zsh reloads a history entry ending in a backslash as a continuation and swallows the next entry.
_history_strip_trailing_backslash() {
  emulate -L zsh -o extendedglob
  local line=${1%$'\n'}
  [[ $line == *\\[[:space:]]# ]] || return 0
  [[ -o histignorespace && $line == ' '* ]] && return 1
  line=${line%%[\\[:space:]]##}
  [[ -n ${line//[[:space:]]/} ]] && print -sr -- "$line"
  return 1
}
autoload -Uz add-zsh-hook
add-zsh-hook zshaddhistory _history_strip_trailing_backslash
