# Scheduled backups

`dotfiles-scheduled-backups` runs every configured backup at most once every 20 hours. Cron calls it hourly, so a laptop that was asleep at night still gets its backup the next time it is awake. A failed job is retried after 4 hours, logs to its own file, and raises a desktop notification.

| Job | Command | Configured by | Destination |
|---|---|---|---|
| `shell-history` | `backup-shell-history-to-1password.sh` | `~/.config/backup-shell-history-to-1password.env` | 1Password Document item |
| `agent-state` | `backup-agent-state --scheduled` | `${XDG_CONFIG_HOME:-~/.config}/agent-state-backup.env` | age-encrypted archives under `BACKUP_ROOT` on the same machine |

A job whose configuration file is missing is skipped. Stamps and logs live in `${XDG_STATE_HOME:-~/.state}/dotfiles-backups/`. Run `dotfiles-scheduled-backups --force` to run every job now.

## Install the schedule

This repo does not install scheduler persistence; see the scheduling policy in [backup-shell-history-to-1password.md](backup-shell-history-to-1password.md). Add this to your user crontab with `crontab -e`, on macOS and Linux alike:

```cron
SHELL=/bin/bash
PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
7 * * * * "$HOME/.local/bin/dotfiles-scheduled-backups" >/dev/null 2>&1
```

## Agent state archives

`backup-agent-state --scheduled` archives `CLAUDE_SOURCE`, `CODEX_SOURCE` and, when set, `GNUPG_SOURCE`. Each one goes into its own `tar.zst.age` file in a new run directory under `BACKUP_ROOT`, and only the newest `KEEP_RUNS` run directories (default 7) are kept.

- The agents may keep running. Each source is cloned with APFS copy-on-write on macOS (`cp --reflink=auto` on Linux) and the clone is archived. Every file is captured whole, but not all files at the same instant.
- Regenerable bulk is skipped by default: Codex `worktrees`, `plugins`, `packages`, caches, temporary files and logs, and Claude `plugins` and caches. Set `CLAUDE_EXCLUDES`, `CODEX_EXCLUDES` or `GNUPG_EXCLUDES` to a space-separated list of relative paths to replace a default list.
- Encryption uses only the public `BACKUP_RECIPIENT`, so scheduled runs never touch 1Password. They check each archive for an age header and do not decrypt it. Run `backup-agent-state --quiesced` with the agents stopped to verify the archives against the identity in 1Password.

Restore an archive into a new directory for inspection:

```bash
encrypted-directory-backup restore ARCHIVE NEW_DIRECTORY VAULT_ID ITEM_ID
```

The archives sit on the same disk as the data they protect. They cover accidental deletion and corruption, not the loss of the machine.
