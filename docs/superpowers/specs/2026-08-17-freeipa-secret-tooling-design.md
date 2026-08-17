# FreeIPA Secret Tooling Design

## Goal

Add a helper that reads a secret out of a FreeIPA vault, as a sibling of the existing `get-krb-ticket.sh` rather than as a second, differently shaped tool. Both must share their conventions and background assumptions instead of being merged into one CLI.

## Design

Introduce `home/.chezmoitemplates/freeipa-library` for what the two tools genuinely share, and make both of them `.tmpl` scripts that include `scripts-library` followed by `freeipa-library`.

The library is deliberately small, because the shared surface is small: `get-krb-ticket.sh` talks to 1Password through `expect`, while `ipa-get-secret` talks to the FreeIPA vault and needs no 1Password session at all. What it provides is `require_commands` (exit 127, preserving the existing missing-client convention that `scripts-library`'s `error` would otherwise flatten to 1), `usage_error` (exit 2, reserved for caller mistakes), `krb_ticket_cache`, `krb_ticket_valid` and `require_krb_ticket`.

The load-bearing piece is xtrace suppression. `scripts-library` enables `set -x` under `DOTFILES_DEBUG`; in tools that handle passwords, OTPs and decoded secrets, that turns a debug flag into a credential leak. `freeipa-library` re-suppresses xtrace, which is why its include must come second.

`ipa-get-secret` forwards every argument except `-h`/`--help` verbatim to `ipa vault-retrieve`, so `--shared` and `--service` keep working without this script maintaining a shadow copy of an interface that would drift. It preflights the Kerberos ticket so a missing ticket produces an actionable message rather than an opaque `ipa` error, and it treats an absent `Data:` field as a failure rather than emitting an empty string that reads like a valid empty secret. The decoded secret goes to stdout with no trailing newline. The `base64` decode flag differs between GNU (`-d`) and BSD (`-D`), so it is selected from `.chezmoi.os` at render time.

`get-krb-ticket.sh` gains no features here. It is renamed to `.sh.tmpl` and migrated onto the shared idiom with its flags, usage text, `expect` blocks and exit codes unchanged. One latent bug is fixed in passing: `ARMOR="$(klist | awk …)"` under `set -e` with `pipefail` aborted on the pipeline's status before reaching the `[[ -z "$ARMOR" ]]` guard, making that guard's message unreachable; `krb_ticket_cache` tolerates a failing `klist` so the check runs.

## Validation

`tests/freeipa-tools.test.sh` renders each template with `chezmoi execute-template` and runs it against stub `klist`/`ipa` binaries on a restricted PATH, so no KDC, FreeIPA server or 1Password session is involved. It asserts the help and usage exit codes, the missing-client 127, the no-ticket preflight, byte-exact decoding with verbatim option forwarding, non-zero exits for both an empty `Data:` field and a failing `ipa`, and that `DOTFILES_DEBUG` does not trace the secret in either encoded or decoded form. A `freeipa-tools` job in `.github/workflows/acceptance-tests.yaml` runs it on every push and pull request.

## Deferred

Extending `get-krb-ticket.sh` itself (renew, destroy, status, multiple realms, auto-kinit) is out of scope. The library is sized to today's two consumers and is the place those additions would land.
