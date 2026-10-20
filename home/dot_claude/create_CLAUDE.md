@RTK.md

# Git Worktrees and Branches

**Declared worktree directory preference: worktrees ALWAYS live outside the repo checkout, as a sibling
of it — `../<repo-name>-worktrees/<branch-name>`. Never inside the repo.**

**Default: work directly in the main checkout on the default branch.** Use a worktree or a separate
branch only when the change is disruptive (including when the main checkout holds another session's
uncommitted work), the risk of downtime is high, or Marcos asks for one.

**Never push, in any repo.** Commit locally, report the SHA and hand Marcos the push command ready to
paste; pushing is always his.

- The one tolerated exception: a session that bootstraps inside `<repo>/.claude/worktrees/` (the
  desktop app's per-session worktree, created before any instruction loads because the app's worktree
  location is set to "Inside the project"; tell Marcos to change it in Settings → Claude Code) can't leave it: the app refuses `change_directory` and blocks Edit/Write to the main
  checkout, and writing there through the shell to dodge that guard is off-limits. With none of the
  conditions above, treat the worktree as master: start from `origin/master`, no feature branch or PR,
  rebase onto `origin/master` and commit. Say so in one line. The push command to hand over is
  `git -C <worktree> fetch -q origin && git -C <worktree> rebase -q origin/master && git -C <worktree> push origin HEAD:master`.
  Leave the worktree alone while the session is live; once Marcos has pushed, ask once to archive the
  session, which removes it.

When a worktree is warranted, create it at that sibling path:

```bash
git worktree add ../<repo>-worktrees/<branch> -b <branch>
```

- Never use `.claude/worktrees/`, `.worktrees/`, or `worktrees/` at the project root, even when a skill's fallback suggests a project-local directory.
- The `EnterWorktree` tool is denied in settings because it hardcodes `.claude/worktrees/` inside the repo and exposes no path setting. If it is blocked, fall through to `git worktree add` with the path above — do not ask to re-enable it.
- Remove with `git worktree remove <path>` once the branch is merged or abandoned.

# Working preferences (all projects)

- Lead every reply with the decision or the most important fact in one sentence, then a few short
  lines. No nested headings or severity lists; offer detail rather than supplying it. Long form only
  when Marcos asks for a report or a document. GitHub issue bodies stay short too.
- Once Marcos signs off a plan, or says "carry on", "don't stop" or "go for it", run every phase to
  completion, validating each with the project's own gate, without per-phase review or further
  questions. Subagents that share one checkout run one at a time. Stop only for a security flag, a
  broken assumption in the agreed plan, or a step needing real infra, credentials or an outward write.
- When scoping fuzzy work, grill him: one question at a time, the recommended option first and marked
  "(Recommended)", reasoning stated as a tradeoff, and challenge his framing when the evidence
  contradicts it. When he says "make this easy", bank the decisions made so far and produce the artifact.
