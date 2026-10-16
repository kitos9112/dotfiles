#!/usr/bin/env bash
# Claude Code SessionStart hook: flag sessions that bootstrapped inside <repo>/.claude/worktrees/.
set -euo pipefail

cwd="$(jq -r '.cwd // empty')"
[[ "${cwd}" == */.claude/worktrees/* ]] || exit 0

repo="${cwd%%/.claude/worktrees/*}"
name="${cwd#"${repo}"/.claude/worktrees/}"
name="${name%%/*}"
repo_name="$(basename -- "${repo}")"
worktree="${repo}/.claude/worktrees/${name}"
branch="$(git -C "${worktree}" branch --show-current 2>/dev/null || true)"
target="$(dirname -- "${repo}")/${repo_name}-worktrees/${name}"

context="This session bootstrapped inside the desktop app's worktree ${worktree} (branch ${branch:-unknown}). Marcos's default is to work on the default branch, not a feature branch; isolation is only for disruptive changes (including another session's uncommitted work in the main checkout), high downtime risk, or when he asks. The app refuses change_directory out of this worktree and blocks Edit/Write to ${repo}; never bypass that through the shell. Unless isolation is warranted, say so in one line and treat this worktree as master: start from origin/master, no PR, rebase onto origin/master and commit. Never push; hand Marcos the push command ready to paste: git -C ${worktree} fetch -q origin && git -C ${worktree} rebase -q origin/master && git -C ${worktree} push origin HEAD:master. Leave the worktree alone while the session is live; once he has pushed, ask once to archive the session, which removes it. If isolation is warranted, keep the branch and move the worktree afterwards: git -C ${repo} worktree move ${worktree} ${target}"

jq -n --arg context "${context}" '{
	systemMessage: "Session bootstrapped in a .claude/worktrees checkout; default is the main checkout",
	hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $context}
}'
