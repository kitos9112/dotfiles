#!/usr/bin/env bash
#
# Contract tests for the private work profile: rendering from the local copy
# next to chezmoi.toml, and dotfiles-work-profile-sync filling that copy from a
# stub `op`. No 1Password session is involved.
#
# Run with: bash tests/work-profile.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck source=tests/lib/contract-test.sh
source "${SCRIPT_DIR}/lib/contract-test.sh"

WORK_ZSH_TEMPLATE="${SOURCE_DIR}/dot_oh-my-zsh-custom/private_work.zsh.tmpl"
GHOSTTY_TEMPLATE="${SOURCE_DIR}/private_dot_config/private_ghostty/config.tmpl"
SYNC_TEMPLATE="${SOURCE_DIR}/private_dot_local/private_bin/executable_dotfiles-work-profile-sync.tmpl"
LOCAL_COPY="${TMP_ROOT}/work-profile.yaml"
WITH_DOCUMENT='{"work_profile_op_document":"Doc","work_profile_op_account":"acct.example"}'

VALID_PROFILE='zsh: |
  alias wk="echo work"
ghosttyCommands:
  - key: w
    title: Work thing
    description: d
    command: wk'

echo "== rendering from the local copy =="
rm -f "${LOCAL_COPY}"
warning="$(render_template "${WORK_ZSH_TEMPLATE}" "${WITH_DOCUMENT}" 2>&1 >/dev/null)"
assert_contains "${warning}" 'run dotfiles-work-profile-sync' "a missing copy warns with the fix"
if [[ -z "$(render_template "${WORK_ZSH_TEMPLATE}" "${WITH_DOCUMENT}" 2>/dev/null)" ]]; then
	pass "a missing copy renders no work.zsh"
else
	fail "a missing copy renders no work.zsh"
fi

printf '%s\n' "${VALID_PROFILE}" >"${LOCAL_COPY}"
assert_contains "$(render_template "${WORK_ZSH_TEMPLATE}" "${WITH_DOCUMENT}")" 'alias wk="echo work"' \
	"work.zsh renders from the local copy"
assert_contains "$(render_template "${GHOSTTY_TEMPLATE}" "${WITH_DOCUMENT}")" \
	'keybind = ctrl+alt+shift+super+w=text:wk\r' "Ghostty renders work commands from the local copy"
if [[ -z "$(render_template "${WORK_ZSH_TEMPLATE}")" ]]; then
	pass "the local copy is ignored without work_profile_op_document"
else
	fail "the local copy is ignored without work_profile_op_document"
fi

: >"${LOCAL_COPY}"
if [[ -z "$(render_template "${WORK_ZSH_TEMPLATE}" "${WITH_DOCUMENT}")" ]]; then
	pass "an empty copy renders nothing"
else
	fail "an empty copy renders nothing"
fi

echo "== dotfiles-work-profile-sync =="
SYNC="${TMP_ROOT}/dotfiles-work-profile-sync"
render_template "${SYNC_TEMPLATE}" "${WITH_DOCUMENT}" >"${SYNC}"
chmod 700 "${SYNC}"
assert_valid_bash "$(<"${SYNC}")" "sync renders valid Bash"

STUB_DIR="${TMP_ROOT}/stubs"
mkdir -p "${STUB_DIR}"
cat >"${STUB_DIR}/op" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${OP_ARGS_LOG}"
if [[ "${OP_STUB_FAIL:-}" == 1 ]]; then
	exit 1
fi
cat "${OP_STUB_CONTENT}"
EOF
chmod 700 "${STUB_DIR}/op"

export OP_ARGS_LOG="${TMP_ROOT}/op-args"
export OP_STUB_CONTENT="${TMP_ROOT}/op-content"
COPY="${TMP_ROOT}/sync-copy/work-profile.yaml"

run_sync() {
	set +e
	SYNC_OUTPUT="$(PATH="${STUB_DIR}:${PATH}" "${SYNC}" "$@" 2>&1)"
	SYNC_STATUS=$?
	set -e
}

assert_status() {
	local expected=$1 actual=$2 label=$3
	if [[ "${actual}" == "${expected}" ]]; then
		pass "${label}"
	else
		fail "${label} (expected exit ${expected}, got ${actual})"
	fi
}

assert_failed() {
	local actual=$1 label=$2
	if [[ "${actual}" != 0 ]]; then
		pass "${label}"
	else
		fail "${label} (expected a non-zero exit)"
	fi
}

run_sync -h
assert_status 0 "${SYNC_STATUS}" "sync -h exits 0"
assert_contains "${SYNC_OUTPUT}" 'Usage: dotfiles-work-profile-sync' "sync -h prints usage"

printf '%s\n' "${VALID_PROFILE}" >"${OP_STUB_CONTENT}"
run_sync -f "${COPY}"
assert_status 0 "${SYNC_STATUS}" "sync succeeds on a valid document"
assert_file_content "${COPY}" "${VALID_PROFILE}" "sync writes the document to the local copy"
assert_contains "$(ls -l "${COPY}")" '-rw-------' "the local copy is readable only by its owner"
assert_contains "$(<"${OP_ARGS_LOG}")" 'document get Doc --account acct.example' \
	"sync reads the configured document from the configured account"

run_sync -f "${COPY}"
assert_contains "${SYNC_OUTPUT}" 'already up to date' "an unchanged document is reported as up to date"

printf 'ghostty_commands: []\n' >"${OP_STUB_CONTENT}"
run_sync -f "${COPY}"
assert_failed "${SYNC_STATUS}" "sync rejects a document with unknown keys"
assert_file_content "${COPY}" "${VALID_PROFILE}" "a rejected document leaves the local copy unchanged"

OP_STUB_FAIL=1 run_sync -f "${COPY}"
assert_failed "${SYNC_STATUS}" "sync fails when 1Password fails"
assert_file_content "${COPY}" "${VALID_PROFILE}" "a 1Password failure leaves the local copy unchanged"

leftovers="$(find "$(dirname "${COPY}")" -name 'work-profile.yaml.*')"
if [[ -z "${leftovers}" ]]; then
	pass "sync leaves no temporary files behind"
else
	fail "sync leaves no temporary files behind: ${leftovers}"
fi

NO_DOCUMENT_SYNC="${TMP_ROOT}/sync-without-document"
render_template "${SYNC_TEMPLATE}" >"${NO_DOCUMENT_SYNC}"
chmod 700 "${NO_DOCUMENT_SYNC}"
set +e
PATH="${STUB_DIR}:${PATH}" "${NO_DOCUMENT_SYNC}" -f "${COPY}" >/dev/null 2>&1
status=$?
set -e
assert_status 2 "${status}" "sync without a document is a usage error"

finish_tests
