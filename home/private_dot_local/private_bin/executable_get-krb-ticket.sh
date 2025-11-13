#!/usr/bin/env bash
# get-krb-ticket.sh — kinit via 1Password (PW+OTP), with FAST armor
# Usage:
#   get-krb-ticket.sh -p "op://vault/item/password" -o "op://vault/item/one-time password?attribute=otp" [-u principal] [-A]
set -euo pipefail

# if caller had xtrace on, disable to avoid echoing anything
[[ $- == *x* ]] && set +x

usage() {
  cat <<'USAGE'
Usage: get-krb-ticket.sh [options]
  -p  1Password password ref (required), e.g. op://vault/item/password
  -o  1Password OTP ref      (required if -A), e.g. op://vault/item/one-time password?attribute=otp
  -u  Kerberos principal (default: $USER)
  -A  Also obtain FAST ticket (kinit -T …) using PW+OTP after bootstrap
  -h  Show help

Notes:
- Secrets are fetched INSIDE 'expect' via `op read` (never put in argv/env).
- The -T argument is passed unquoted, as-is.
USAGE
}

PW_REF=""
OTP_REF=""
PRINCIPAL="${USER}"
ARMOR_TICKET="0"

while getopts ":p:o:u:hA" opt; do
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

# required inputs
[[ -z "$PW_REF" ]] && { echo "Error: -p <password ref> is required." >&2; exit 2; }
if [[ "$ARMOR_TICKET" == "1" && -z "$OTP_REF" ]]; then
  echo "Error: -o <otp ref> is required when -A is set." >&2
  exit 2
fi

# deps
for c in op expect kinit klist awk; do
  command -v "$c" >/dev/null 2>&1 || { echo "missing dependency: $c" >&2; exit 127; }
done

# 1) Bootstrap: plain kinit with PW only (no OTP)
PW_REF="$PW_REF" PRINCIPAL="$PRINCIPAL" expect -c '
  # read password (suppress stderr to avoid noisy ref leaks on errors)
  if {[catch {set pw [exec sh -c "op read --no-newline \"$env(PW_REF)\" 2>/dev/null"]} err]} {
    puts stderr "Failed to read password from 1Password."
    exit 1
  }
  spawn kinit $env(PRINCIPAL)
  after 250
  send -- "$pw\r"
  expect eof
'

# detect armor cache
ARMOR="$(klist 2>/dev/null | awk "/Ticket cache:/{print \$3}")"
[[ -z "$ARMOR" ]] && { echo "failed to obtain armor cache" >&2; exit 1; }

# 2) Optional FAST ticket: kinit -T <armor> with PW+OTP
if [[ "$ARMOR_TICKET" == "1" ]]; then
  PW_REF="$PW_REF" OTP_REF="$OTP_REF" ARMOR="$ARMOR" PRINCIPAL="$PRINCIPAL" expect -c '
    if {[catch {set pw  [exec sh -c "op read --no-newline \"$env(PW_REF)\" 2>/dev/null"]} err]} {
      puts stderr "Failed to read password from 1Password."
      exit 1
    }
    if {[catch {set otp [exec sh -c "op read --no-newline \"$env(OTP_REF)\" 2>/dev/null"]} err]} {
      puts stderr "Failed to read OTP from 1Password."
      exit 1
    }
    # -T argument intentionally unquoted
    spawn kinit -T $env(ARMOR) $env(PRINCIPAL)
    after 250
    send -- "$pw$otp\r"
    expect eof
  '
  echo "Obtained Kerberos ticket for principal '$PRINCIPAL' using FAST armor."
fi