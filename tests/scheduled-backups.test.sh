#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck source=tests/lib/contract-test.sh
source "${SCRIPT_DIR}/lib/contract-test.sh"

RUNNER="${SOURCE_DIR}/private_dot_local/private_bin/executable_dotfiles-scheduled-backups"

setup_case() {
	CASE="${TMP_ROOT}/$1"
	BIN="${CASE}/bin"
	STATE="${CASE}/state"
	CALLS="${CASE}/calls"
	NOTES="${CASE}/notifications"
	mkdir -p "${BIN}" "${CASE}/home/.config"
	install -m 700 "${RUNNER}" "${BIN}/dotfiles-scheduled-backups"
	for job in backup-shell-history-to-1password.sh backup-agent-state; do
		cat >"${BIN}/${job}" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "${job}" "\$*" >>"${CALLS}"
[[ "\${FAIL_JOB:-}" != "${job}" ]]
EOF
		chmod 700 "${BIN}/${job}"
	done
	cat >"${BIN}/notify" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"${NOTES}"
EOF
	chmod 700 "${BIN}/notify"
	: >"${CASE}/home/.config/agent-state-backup.env"
	: >"${CASE}/home/.config/backup-shell-history-to-1password.env"
	: >"${CALLS}"
}

runner() {
	HOME="${CASE}/home" XDG_STATE_HOME="${STATE}" XDG_CONFIG_HOME="${CASE}/home/.config" \
		DOTFILES_BACKUP_NOTIFY="${BIN}/notify" "${BIN}/dotfiles-scheduled-backups" "$@"
}

stamp() {
	printf '%s\n' "$(($(date +%s) - $2 * 3600))" >"${STATE}/dotfiles-backups/$1.$3"
}

setup_case first-run
runner >/dev/null
assert_contains "$(<"${CALLS}")" "backup-shell-history-to-1password.sh " "first run backs up shell history"
assert_contains "$(<"${CALLS}")" "backup-agent-state --scheduled" "first run backs up agent state in scheduled mode"
assert_file_exists "${STATE}/dotfiles-backups/shell-history.last-success" "success is stamped per job"
assert_file_exists "${STATE}/dotfiles-backups/shell-history.log" "each job logs to its own file"

: >"${CALLS}"
runner >/dev/null
assert_file_content "${CALLS}" "" "a second run within the interval does nothing"

stamp shell-history 21 last-attempt
stamp shell-history 21 last-success
runner >/dev/null
assert_file_content "${CALLS}" "backup-shell-history-to-1password.sh " "a job runs again once its last success is 20 hours old"

setup_case failure
if FAIL_JOB=backup-agent-state runner >/dev/null 2>&1; then
	fail "a failed job makes the runner exit non-zero"
else
	pass "a failed job makes the runner exit non-zero"
fi
assert_file_absent "${STATE}/dotfiles-backups/agent-state.last-success" "a failed job is not stamped as a success"
assert_file_exists "${STATE}/dotfiles-backups/shell-history.last-success" "one failed job does not stop the others"
assert_contains "$(cat "${NOTES}" 2>/dev/null)" "agent-state" "a failed job raises a notification naming it"

: >"${CALLS}"
FAIL_JOB=backup-agent-state runner >/dev/null 2>&1 || true
assert_file_content "${CALLS}" "" "a failed job is not retried within four hours"

stamp agent-state 5 last-attempt
FAIL_JOB=backup-agent-state runner >/dev/null 2>&1 || true
assert_file_content "${CALLS}" "backup-agent-state --scheduled" "a failed job is retried after four hours"

setup_case force
runner >/dev/null
: >"${CALLS}"
runner --force >/dev/null
assert_contains "$(<"${CALLS}")" "backup-agent-state --scheduled" "--force ignores the stamps"

setup_case unconfigured
rm "${CASE}/home/.config/agent-state-backup.env"
runner >/dev/null
assert_not_contains "$(<"${CALLS}")" "backup-agent-state" "agent state is skipped where it is not configured"
assert_contains "$(<"${STATE}/dotfiles-backups/agent-state.log")" "not configured" "the skip is logged"

setup_case locked
mkdir -p "${STATE}/dotfiles-backups/lock"
printf '%s\n' "$$" >"${STATE}/dotfiles-backups/lock/pid"
runner >/dev/null
assert_file_content "${CALLS}" "" "a run is skipped while another one holds the lock"

printf '999999\n' >"${STATE}/dotfiles-backups/lock/pid"
runner >/dev/null
assert_contains "$(<"${CALLS}")" "backup-agent-state" "a lock left by a dead process is taken over"

finish_tests
