# Shell History Backup to 1Password

## What it does

`backup-shell-history-to-1password.sh` collects these files when they exist:

- `~/.bash_history`
- `~/.zsh_history`

It copies only those files into a secure temporary directory, creates a single ZIP archive named `shell-history.zip` by default, and uploads that ZIP to an existing 1Password **Document** item with `op document edit`.

The ZIP filename stays stable on every run. Backup history comes from the 1Password item's version history, not from local retention logic.

## Append-only archive and shrink guard

zsh can rewrite `~/.zsh_history` with only part of its history when many shells exit at once, for example during a forced logout for an OS update. Two safeguards cover that:

- Every run merges `~/.zsh_history` into `${XDG_STATE_HOME:-~/.local/state}/shell-history/zsh_history.archive` with `zsh-history-merge`. The archive is a time-ordered union of every command seen, so it never loses entries. The ZIP carries it as `.zsh_history.archive`.
- After a successful upload the script records the number of entries in `zsh_history.count`. If a later `~/.zsh_history` holds fewer than 90% of that number, the script exits with status 3 without uploading. The archive is still updated.

To recover after the guard fires, close every shell and restore from the archive:

```bash
zsh-history-merge --output ~/.zsh_history ~/.zsh_history "${XDG_STATE_HOME:-$HOME/.local/state}/shell-history/zsh_history.archive"
```

If the history shrank on purpose, run once with `--accept-shrink` to upload and reset the baseline.

## Dependencies

- Bash
- `zip`
- `python3`, for `zsh-history-merge`
- [1Password CLI (`op`)](https://developer.1password.com/docs/cli/)

## Authentication

The unattended path uses a **1Password service account token** from the local env file, then checks `op whoami` before uploading.

Relevant docs:

- [Use service accounts with 1Password CLI](https://developer.1password.com/docs/service-accounts/use-with-1password-cli/)
- [Get started with 1Password Service Accounts](https://developer.1password.com/docs/service-accounts/get-started/)
- [1Password CLI reference: document](https://developer.1password.com/docs/cli/reference/management-commands/document/)

## Required env file

The script expects a readable env file at:

```bash
~/.config/backup-shell-history-to-1password.env
```

If the file is missing, the script creates it automatically with mode `0600`, writes a commented template, prints a short configuration menu, and exits non-zero so you can fill the values in safely.

Recommended contents:

```bash
OP_SERVICE_ACCOUNT_TOKEN='ops_...'
OP_VAULT='d3say5tyceayp6wovlpulvl6qu'
OP_ITEM_ID='lh4bebumvjoayjmp3dye3b3xea'
ARCHIVE_NAME='shell-history.zip'
```

Protect it with:

```bash
chmod 600 ~/.config/backup-shell-history-to-1password.env
```

If the file permissions are broader than `600`, fix them before you schedule unattended runs:

```bash
chmod 600 ~/.config/backup-shell-history-to-1password.env
```

`OP_ITEM` can be used instead of `OP_ITEM_ID`, but IDs are safer.

## Runtime configuration

The script sources the env file before doing any work. It expects:

- `OP_SERVICE_ACCOUNT_TOKEN`
- `OP_VAULT`
- `OP_ITEM_ID` or `OP_ITEM`

Optional:

- `ARCHIVE_NAME`

The script still accepts runtime overrides, but the unattended path is the env file.

If the file exists but is incomplete or invalid, the script prints a short checklist showing:

- which values are missing
- the exact file path to edit
- the expected file format
- the next steps after editing it

Examples:

```bash
~/.local/bin/backup-shell-history-to-1password.sh
```

```bash
~/.local/bin/backup-shell-history-to-1password.sh --verbose
```

```bash
~/.local/bin/backup-shell-history-to-1password.sh --dry-run
```

## Scheduling policy

This repo no longer installs scheduler persistence automatically. That keeps `chezmoi apply` from creating LaunchAgents or user services that can trigger EDR noise on managed machines.

Use:

- Linux: `anacron`, invoked from your user `crontab`
- macOS: user `cron`

## Manual scheduling

Schedule `dotfiles-scheduled-backups` rather than this script. It runs this backup and the agent state backup at most once every 20 hours, retries a failure after 4 hours, and raises a desktop notification when one fails. See [scheduled-backups.md](scheduled-backups.md).

## Restore notes

The script overwrites the same 1Password Document item each run. To restore an older backup, open the item in 1Password and use the item's previous versions:

- [View and restore previous versions of items](https://support.1password.com/item-history/)

## Design choices and limitations

- The script targets an existing **Document** item because `op document edit` is the documented file-content replacement flow.
- The unattended path is a 1Password service account token loaded from a local env file.
- It backs up only `~/.bash_history` and `~/.zsh_history`.
- It does not create dated archives. The only local state is the zsh archive and the entry-count baseline.
- It requires `zip`; it does not fall back to tar or other archive formats.
- This repo does not auto-install scheduler persistence; cron/anacron setup is manual by design.

## Warning

Shell history often contains sensitive commands, tokens, hostnames, or copied secrets. Treat the 1Password item and its version history as sensitive data.
