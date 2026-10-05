#!/usr/bin/env bash
# Claude Code SessionStart hook: flag sessions that bootstrapped inside <repo>/.claude/worktrees/.
set -euo pipefail

cwd="$(jq -r '.cwd // empty')"
[[ "${cwd}" == */.claude/worktrees/* ]] || exit 0

repo="${cwd%%/.claude/worktrees/*}"
name="${cwd#"${repo}"/.claude/worktrees/}"
name="${name%%/*}"
repo_name="$(basename -- "${repo}")"
target="$(dirname -- "${repo}")/${repo_name}-worktrees/${name}"

context="This session started inside ${repo}/.claude/worktrees/${name}, which the session bootstrap created against the worktree convention (worktrees live at ../${repo_name}-worktrees/<branch>). Say so in your first reply, before any other work, and offer to continue in the main checkout instead. Once this session has ended the worktree can be moved with: git -C ${repo} worktree move ${repo}/.claude/worktrees/${name} ${target}"

jq -n --arg context "${context}" '{
	systemMessage: "Session is running in a stray .claude/worktrees checkout",
	hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $context}
}'
