#!/usr/bin/env bash
# Claude Code PostToolUse/PostToolUseFailure hook: after a Bash `git commit`, show what HEAD contains.
set -euo pipefail

input="$(cat)"
command="$(jq -r '.tool_input.command // empty' <<<"${input}")"
cwd="$(jq -r '.cwd // empty' <<<"${input}")"
event="$(jq -r '.hook_event_name // "PostToolUse"' <<<"${input}")"

commit_re='(^|[;&|(]|[[:space:]])(rtk[[:space:]]+)?git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)'
[[ "${command}" =~ ${commit_re} ]] || exit 0
[[ "${command}" =~ [[:space:]]--dry-run([[:space:]]|=|$) ]] && exit 0

repo_dir="${cwd:-${PWD}}"
if [[ "${command}" =~ git[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]]; then
	repo_dir="${BASH_REMATCH[1]}"
elif [[ "${command}" =~ (^|[;&|][[:space:]]*)cd[[:space:]]+([^[:space:]\;\&\|]+) ]]; then
	repo_dir="${BASH_REMATCH[2]}"
fi
repo_dir="${repo_dir//\"/}"
repo_dir="${repo_dir//\'/}"
if [[ "${repo_dir}" == "~"* ]]; then
	repo_dir="${HOME}${repo_dir#\~}"
fi
if [[ "${repo_dir}" != /* ]]; then
	repo_dir="${cwd%/}/${repo_dir}"
fi

head_epoch="$(git -C "${repo_dir}" log -1 --format=%ct 2>/dev/null)" || exit 0
[[ -n "${head_epoch}" ]] || exit 0

if (($(date +%s) - head_epoch > 300)); then
	context="No new commit: HEAD in ${repo_dir} is still $(git -C "${repo_dir}" log -1 --format='%h %s (%cr)'). The commit did not land; read the command output (pre-commit hook, signing) before reporting anything as committed."
else
	count="$(git -C "${repo_dir}" show --name-only --format= HEAD | grep -c . || true)"
	summary="$(git -C "${repo_dir}" show --name-status --format='%h %s' HEAD | head -n 41)"
	context="Commit landed in ${repo_dir}. HEAD contains ${count} file(s):
${summary}
Check this list against the files you meant to commit before reporting. Other sessions can change this checkout between commands."
fi

jq -n --arg event "${event}" --arg context "${context}" \
	'{hookSpecificOutput: {hookEventName: $event, additionalContext: $context}}'
