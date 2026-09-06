@RTK.md

# Git Worktrees

**Declared worktree directory preference: worktrees ALWAYS live outside the repo checkout, as a sibling of it. Never inside the repo.**

Path convention — `../<repo-name>-worktrees/<branch-name>`:

```bash
git worktree add ../<repo>-worktrees/<branch> -b <branch>
```

- Never use `.claude/worktrees/`, `.worktrees/`, or `worktrees/` at the project root, even when a skill's fallback suggests a project-local directory.
- The `EnterWorktree` tool is denied in settings because it hardcodes `.claude/worktrees/` inside the repo and exposes no path setting. If it is blocked, fall through to `git worktree add` with the path above — do not ask to re-enable it.
- Remove with `git worktree remove <path>` once the branch is merged or abandoned.
