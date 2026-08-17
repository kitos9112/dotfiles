#!/usr/bin/env bash
#
# Contract tests for the Kerberos and FreeIPA tools in ~/.local/bin and the
# `freeipa-library` chezmoi template they share.
#
# Hermetic: each case renders the chezmoi template into a throwaway directory and
# runs it against stub `klist`/`ipa` binaries on a restricted PATH. No KDC, no
# FreeIPA server and no 1Password session are involved, so this is safe to run
# anywhere, including on a machine that has never joined the realm.
#
# Run with: bash tests/freeipa-tools.test.sh

set -euo pipefail

SCRIPT_DIR="$(
	cd -- "$(dirname "$0")" >/dev/null 2>&1
	pwd -P
)"
REPO_ROOT="$(
	cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1
	pwd -P
)"
GET_SECRET_TEMPLATE="${REPO_ROOT}/home/private_dot_local/private_bin/executable_get-ipa-secret.tmpl"
GET_TICKET_TEMPLATE="${REPO_ROOT}/home/private_dot_local/private_bin/executable_get-krb-ticket.sh.tmpl"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/freeipa-tools-tests.XXXXXX")"
trap 'rm -rf "${TMP_ROOT}"' EXIT HUP INT TERM
TEST_CHEZMOI_CONFIG="${TMP_ROOT}/empty-chezmoi.toml"
: >"${TEST_CHEZMOI_CONFIG}"

STUB_DIR="${TMP_ROOT}/stubs"
mkdir -p "${STUB_DIR}"
IPA_ARGS_LOG="${TMP_ROOT}/ipa-args"
STDOUT_FILE="${TMP_ROOT}/stdout"
STDERR_FILE="${TMP_ROOT}/stderr"

GET_SECRET_SCRIPT="${TMP_ROOT}/get-ipa-secret"
GET_TICKET_SCRIPT="${TMP_ROOT}/get-krb-ticket.sh"

# Synthetic secret handed back by the `ipa` stub. Nothing real, by design.
SECRET_PLAINTEXT='s3cr3t-value'
SECRET_BASE64="$(printf '%s' "${SECRET_PLAINTEXT}" | base64)"

STATUS=0

fail() {
	printf 'not ok: %s\n' "$*" >&2
	exit 1
}

pass() {
	printf 'ok: %s\n' "$*"
}

assert_status() {
	local expected=$1
	local message=$2

	[ "${STATUS}" = "${expected}" ] ||
		fail "${message} (expected exit ${expected}, got ${STATUS})"
}

assert_contains() {
	local needle=$1
	local path=$2
	local message=$3

	grep -F -- "${needle}" "${path}" >/dev/null || fail "${message}"
}

assert_not_contains() {
	local needle=$1
	local path=$2
	local message=$3

	if grep -F -- "${needle}" "${path}" >/dev/null; then
		fail "${message}"
	fi
}

render_template() {
	local template=$1
	local destination=$2

	chezmoi execute-template \
		--config "${TEST_CHEZMOI_CONFIG}" \
		--source "${REPO_ROOT}" \
		--file "${template}" >"${destination}"
	chmod 700 "${destination}"
}

# $1: exit code `klist -s` should return; 0 means "a valid ticket exists".
write_klist_stub() {
	local ticket_status=$1

	cat >"${STUB_DIR}/klist" <<-EOF
		#!/usr/bin/env bash
		if [ "\${1:-}" = "-s" ]; then
		  exit ${ticket_status}
		fi
		printf 'Ticket cache: FILE:/tmp/krb5cc_test\n'
		printf 'Default principal: tester@EXAMPLE.TEST\n'
	EOF
	chmod 700 "${STUB_DIR}/klist"
}

# $1: data | nodata | fail
write_ipa_stub() {
	local mode=$1

	cat >"${STUB_DIR}/ipa" <<-EOF
		#!/usr/bin/env bash
		printf '%s\n' "\$*" >'${IPA_ARGS_LOG}'
	EOF

	case "${mode}" in
		data)
			cat >>"${STUB_DIR}/ipa" <<-EOF
				printf '  Vault: test\n'
				printf '  Data: %s\n' '${SECRET_BASE64}'
			EOF
			;;
		nodata)
			cat >>"${STUB_DIR}/ipa" <<-'EOF'
				printf '  Vault: test\n'
			EOF
			;;
		fail)
			cat >>"${STUB_DIR}/ipa" <<-'EOF'
				printf 'ipa: ERROR: no such vault\n' >&2
				exit 1
			EOF
			;;
		*)
			fail "unknown ipa stub mode: ${mode}"
			;;
	esac
	chmod 700 "${STUB_DIR}/ipa"
}

# Only the stubs plus the system utilities the scripts genuinely need are on
# PATH, so "missing dependency" cases are real rather than incidental. ${BASH} is
# invoked explicitly because the restricted PATH would otherwise decide which
# bash runs (notably the 3.2 build stock macOS ships in /bin).
run_capture() {
	local script=$1
	shift

	STATUS=0
	PATH="${STUB_DIR}:/usr/bin:/bin" "${BASH}" "${script}" "$@" \
		>"${STDOUT_FILE}" 2>"${STDERR_FILE}" || STATUS=$?
}

run_capture_with_debug() {
	local script=$1
	shift

	STATUS=0
	DOTFILES_DEBUG=1 PATH="${STUB_DIR}:/usr/bin:/bin" "${BASH}" "${script}" "$@" \
		>"${STDOUT_FILE}" 2>"${STDERR_FILE}" || STATUS=$?
}

render_template "${GET_SECRET_TEMPLATE}" "${GET_SECRET_SCRIPT}"
render_template "${GET_TICKET_TEMPLATE}" "${GET_TICKET_SCRIPT}"

# --- get-ipa-secret -------------------------------------------------------

# Help is a successful request, and must not depend on having a ticket.
write_klist_stub 1
write_ipa_stub data
run_capture "${GET_SECRET_SCRIPT}" --help
assert_status 0 "get-ipa-secret --help must succeed"
assert_contains 'Usage: get-ipa-secret' "${STDOUT_FILE}" \
	"--help must print usage on stdout"
pass "get-ipa-secret --help exits 0 and prints usage"

run_capture "${GET_SECRET_SCRIPT}"
assert_status 2 "a missing vault key must be a usage error"
pass "get-ipa-secret without a vault key exits 2"

# A missing FreeIPA client is reported as such, before any Kerberos work.
rm -f "${STUB_DIR}/ipa"
write_klist_stub 0
run_capture "${GET_SECRET_SCRIPT}" my_key
assert_status 127 "a missing 'ipa' client must exit 127"
assert_contains 'missing dependency: ipa' "${STDERR_FILE}" \
	"the missing dependency must be named"
pass "get-ipa-secret reports a missing 'ipa' client as exit 127"

# No ticket: fail with something actionable instead of an opaque ipa error.
write_ipa_stub data
write_klist_stub 1
run_capture "${GET_SECRET_SCRIPT}" my_key
assert_status 1 "an expired or absent ticket must fail"
assert_contains 'get-krb-ticket.sh' "${STDERR_FILE}" \
	"the no-ticket error must say how to get a ticket"
pass "get-ipa-secret preflights the Kerberos ticket with an actionable error"

# Happy path: exact bytes out, options forwarded verbatim.
write_klist_stub 0
write_ipa_stub data
run_capture "${GET_SECRET_SCRIPT}" --shared my_key
assert_status 0 "retrieving a secret must succeed"
decoded="$(cat "${STDOUT_FILE}")"
[ "${decoded}" = "${SECRET_PLAINTEXT}" ] ||
	fail "decoded secret mismatch (got '${decoded}')"
decoded_bytes="$(wc -c <"${STDOUT_FILE}" | tr -d '[:space:]')"
[ "${decoded_bytes}" = "${#SECRET_PLAINTEXT}" ] ||
	fail "decoded secret must not gain a trailing newline (${decoded_bytes} bytes)"
assert_contains 'vault-retrieve --shared my_key' "${IPA_ARGS_LOG}" \
	"options must be forwarded verbatim to 'ipa vault-retrieve'"
pass "get-ipa-secret decodes the secret byte for byte and forwards options"

# An empty Data: field must not look like a successfully retrieved empty secret.
write_ipa_stub nodata
run_capture "${GET_SECRET_SCRIPT}" my_key
[ "${STATUS}" != "0" ] || fail "a retrieval with no Data: line must not exit 0"
[ ! -s "${STDOUT_FILE}" ] || fail "a failed retrieval must print nothing on stdout"
pass "get-ipa-secret fails when no secret data is returned"

write_ipa_stub fail
run_capture "${GET_SECRET_SCRIPT}" my_key
[ "${STATUS}" != "0" ] || fail "an 'ipa' failure must not exit 0"
[ ! -s "${STDOUT_FILE}" ] || fail "an 'ipa' failure must print nothing on stdout"
pass "get-ipa-secret propagates an 'ipa' failure"

# The reason freeipa-library re-suppresses xtrace: scripts-library enables it
# under DOTFILES_DEBUG, which would otherwise trace the secret to the terminal.
write_ipa_stub data
run_capture_with_debug "${GET_SECRET_SCRIPT}" my_key
assert_status 0 "DOTFILES_DEBUG must not break retrieval"
assert_not_contains "${SECRET_PLAINTEXT}" "${STDERR_FILE}" \
	"DOTFILES_DEBUG must not trace the decoded secret"
assert_not_contains "${SECRET_BASE64}" "${STDERR_FILE}" \
	"DOTFILES_DEBUG must not trace the encoded secret"
pass "DOTFILES_DEBUG does not leak secrets through xtrace"

# --- get-krb-ticket.sh ------------------------------------------------------

# Usage handling must come before the op/expect/kinit dependency gate, so these
# cases pass without any of those clients installed.
run_capture "${GET_TICKET_SCRIPT}" -h
assert_status 0 "get-krb-ticket.sh -h must succeed"
assert_contains 'Usage: get-krb-ticket.sh' "${STDOUT_FILE}" \
	"-h must print usage on stdout"
pass "get-krb-ticket.sh -h exits 0 and prints usage"

run_capture "${GET_TICKET_SCRIPT}"
assert_status 2 "get-krb-ticket.sh without -p must be a usage error"
pass "get-krb-ticket.sh without a password ref exits 2"

run_capture "${GET_TICKET_SCRIPT}" -p 'op://vault/item/password' -A
assert_status 2 "get-krb-ticket.sh -A without -o must be a usage error"
assert_contains '-o <otp ref> is required' "${STDERR_FILE}" \
	"the -A/-o dependency must be explained"
pass "get-krb-ticket.sh rejects -A without an OTP ref"

printf '\nall freeipa tool contracts hold\n'
