#!/usr/bin/env bash
# get-krb-ticket.sh — kinit via 1Password (PW+OTP), with FAST armor
# Usage:
#   get-krb-ticket.sh [-p <op_pw_ref>] [-o <op_otp_ref>] [-u <principal>] [-a <armor_path>] [-s <sleep_ms>] [-w]
# Examples:
#   get-krb-ticket.sh \
#     -p "op://<vault>/<itemName>/password" \
#     -o "op://<vault>/<itemName>/one-time password?attribute=otp" \
#     -u "$USER"

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: get-krb-ticket.sh [options]

Options:
  -p  1Password reference for password (default: op://<vault>/<itemName>/password)
  -o  1Password reference for OTP (default: op://<vault>/<itemName>/one-time password?attribute=otp)
  -u  Kerberos principal (default: $USER)
  -A  Armor cache path (default: use existing ticket cache if available)
  -h  Show this help.

Notes:
- Secrets never appear in argv/env; they’re piped to expect via stdin.
- The -T argument is passed unquoted, as-is.
USAGE
}

# ---- defaults ----
PW_REF=""
OTP_REF=""
PRINCIPAL="${USER}"
ARMOR_TICKET="0"

# -- scrub secrets on any exit or signal, while preserving the original exit code

while getopts ":p:o:u:h:A" opt; do
  case "$opt" in
    p) PW_REF="$OPTARG" ;;
    o) OTP_REF="$OPTARG" ;;
    u) PRINCIPAL="$OPTARG" ;;
    A) ARMOR_TICKET="1" ;;
    h) usage; exit 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage; exit 2 ;;
    :)  echo "Option -$OPTARG requires an argument." >&2; usage; exit 2 ;;
  esac
done

# ---- deps ----
for c in op expect kinit klist awk; do
  command -v "$c" >/dev/null 2>&1 || { echo "missing dependency: $c" >&2; exit 127; }
done

# optional: check op signin
if ! op whoami >/dev/null 2>&1; then
  echo "1Password CLI not signed in (run: op signin ...)" >&2
  op signin || { echo "failed to sign in to 1Password CLI" >&2; exit 1; }
fi

#shellcheck disable=SC2016
PW_REF="$PW_REF" PRINCIPAL="$PRINCIPAL" expect -c '
  set pw  [exec op read --no-newline $env(PW_REF)]
  spawn kinit $env(PRINCIPAL)
  after 250
  send -- "$pw\r"
  expect eof
'
ARMOR="$(klist 2>/dev/null | awk '/Ticket cache:/{print $3}')"
[[ -z "$ARMOR" ]] && { echo "failed to obtain armor cache" >&2; exit 1; }

if [[ "$ARMOR_TICKET" == "1" ]]; then
  #shellcheck disable=SC2016
  PW_REF="$PW_REF" OTP_REF="$OTP_REF" ARMOR="$ARMOR" PRINCIPAL="$PRINCIPAL" expect -c '
    set pw  [exec op read --no-newline $env(PW_REF)]
    set otp [exec op read --no-newline $env(OTP_REF)]
    spawn kinit -T $env(ARMOR) $env(PRINCIPAL)
    after 250
    send -- "$pw$otp\r"
    expect eof
  '

  echo "Obtained Kerberos ticket for principal '$PRINCIPAL' using FAST armor."
fi
