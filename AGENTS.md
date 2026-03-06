# Repository Guidelines

## Scope

- This repository is public. Never commit secrets, credentials, tokens, private keys, recovery codes, or machine-specific confidential data.
- `private_*` chezmoi paths are still public in source control. Use them for target-path behavior, not secret storage.
- Prefer placeholders, environment variables, or documented setup steps over embedded sensitive values.

## Repo Conventions

- Prefer conventional commits for commit messages and PR titles.
- Preserve chezmoi naming and layout conventions such as `dot_*`, `private_*`, `.tmpl`, and `home/.chezmoiscripts/`.
- Keep changes scoped. Do not rewrite unrelated personal configuration while working on a focused task.

## Acceptance Tests

- Keep `.github/workflows/acceptance-tests.yaml` aligned with the Dockerfiles under `tests/`.
- Acceptance coverage should track current AlmaLinux and Ubuntu releases. Replace stale targets instead of growing the matrix unless asked to do otherwise.
- Current matrix targets are `almalinux-9`, `almalinux-10`, `ubuntu-24.04`, and `ubuntu-25.10`.

## Skills

- Keep repo-local skills concise and public-safe.
- Put only the reusable workflow in `SKILL.md`; move long examples or reference material into supporting files when needed.

## Validation

- Run `pre-commit run --all-files` when practical.
- When changing distro targets or workflows, update `README.md` to match the actual CI matrix.
