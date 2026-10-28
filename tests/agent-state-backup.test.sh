#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck source=tests/lib/contract-test.sh
source "${SCRIPT_DIR}/lib/contract-test.sh"

for dependency in age age-keygen zstd python3; do
	command -v "${dependency}" >/dev/null 2>&1 || {
		printf 'missing dependency for tests: %s\n' "${dependency}" >&2
		exit 127
	}
done

BIN_SOURCE="${SOURCE_DIR}/private_dot_local/private_bin"
TAR="$(command -v gtar || command -v tar)"
BIN="${TMP_ROOT}/bin"
IDENTITY="${TMP_ROOT}/identity"
OP_LOG="${TMP_ROOT}/op.log"
mkdir -p "${BIN}"
install -m 700 "${BIN_SOURCE}/private_executable_encrypted-directory-backup" "${BIN}/encrypted-directory-backup"
install -m 700 "${BIN_SOURCE}/private_executable_backup-agent-state" "${BIN}/backup-agent-state"
age-keygen -o "${IDENTITY}" 2>/dev/null
RECIPIENT="$(age-keygen -y "${IDENTITY}")"
cat >"${BIN}/op" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"${OP_LOG}"
[[ "\$1 \$2" == "document get" ]] && cat "${IDENTITY}"
EOF
chmod 700 "${BIN}/op"
export PATH="${BIN}:${PATH}"

listing() {
	age --decrypt --identity "${IDENTITY}" "$1" | zstd --decompress --stdout --quiet | "${TAR}" --list --file - | LC_ALL=C sort
}

make_source() {
	local root=$1
	mkdir -p "${root}/sub" "${root}/drop/deep"
	printf 'keep\n' >"${root}/keep.txt"
	printf 'nested\n' >"${root}/sub/keep"
	printf 'gone\n' >"${root}/sub/drop-nested"
	printf 'big\n' >"${root}/drop/deep/big"
	printf 'dot\n' >"${root}/.hidden"
	python3 -Ic "import os,socket,sys; os.chdir(sys.argv[1]); socket.socket(socket.AF_UNIX).bind('agent.sock')" "${root}/sub"
}

expected_listing=$'src/\nsrc/.hidden\nsrc/keep.txt\nsrc/sub/\nsrc/sub/keep'

for mode in --snapshot --quiesced; do
	case_dir="${TMP_ROOT}/create${mode}"
	mkdir -p "${case_dir}"
	make_source "${case_dir}/src"
	encrypted-directory-backup create "${case_dir}/src" "${case_dir}/out.age" "${RECIPIENT}" "${mode}" \
		--exclude drop --exclude sub/drop-nested >/dev/null
	actual="$(listing "${case_dir}/out.age")"
	if [[ "${actual}" == "${expected_listing}" ]]; then
		pass "create ${mode} honours exact excludes and omits sockets"
	else
		fail "create ${mode} honours exact excludes and omits sockets (got: ${actual//$'\n'/, })"
	fi
	assert_file_exists "${case_dir}/src/drop/deep/big" "create ${mode} leaves the source untouched"
done

case_dir="${TMP_ROOT}/restore"
mkdir -p "${case_dir}"
make_source "${case_dir}/src"
encrypted-directory-backup create "${case_dir}/src" "${case_dir}/out.age" "${RECIPIENT}" --snapshot >/dev/null
encrypted-directory-backup restore "${case_dir}/out.age" "${case_dir}/restored" vault item >/dev/null
assert_file_content "${case_dir}/restored/src/sub/keep" "nested" "a snapshot archive restores its files"

for bad in ../escape /absolute 'sub/../../escape' ''; do
	if encrypted-directory-backup create "${case_dir}/src" "${case_dir}/bad.age" "${RECIPIENT}" --snapshot \
		--exclude "${bad}" >/dev/null 2>&1; then
		fail "exclude '${bad}' is rejected"
	else
		pass "exclude '${bad}' is rejected"
	fi
done
assert_file_absent "${case_dir}/bad.age" "a rejected exclude publishes no archive"

setup_agent_case() {
	CASE="${TMP_ROOT}/agent-$1"
	ROOT="${CASE}/backups"
	CONFIG="${CASE}/agent-state-backup.env"
	mkdir -p "${CASE}/claude/projects" "${CASE}/claude/plugins" "${CASE}/codex/sessions" \
		"${CASE}/codex/worktrees/w" "${CASE}/gnupg/private-keys-v1.d" "${ROOT}"
	printf 'transcript\n' >"${CASE}/claude/projects/a.jsonl"
	printf 'plugin\n' >"${CASE}/claude/plugins/p"
	printf 'session\n' >"${CASE}/codex/sessions/s"
	printf 'checkout\n' >"${CASE}/codex/worktrees/w/f"
	printf 'key\n' >"${CASE}/gnupg/private-keys-v1.d/k.key"
	cat >"${CONFIG}" <<EOF
BACKUP_RECIPIENT='${RECIPIENT}'
OP_VAULT='vault'
OP_ITEM_ID='item'
BACKUP_ROOT='${ROOT}'
CLAUDE_SOURCE='${CASE}/claude'
CODEX_SOURCE='${CASE}/codex'
GNUPG_SOURCE='${CASE}/gnupg'
EOF
	chmod 600 "${CONFIG}"
	: >"${OP_LOG}"
}

run_dirs() {
	find "${ROOT}" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | LC_ALL=C sort
}

setup_agent_case scheduled
AGENT_BACKUP_CONFIG="${CONFIG}" backup-agent-state --scheduled >/dev/null
run="$(find "${ROOT}" -mindepth 1 -maxdepth 1 -type d | head -1)"
assert_contains "$(listing "${run}/claude.tar.zst.age")" "claude/projects/a.jsonl" "scheduled run keeps Claude transcripts"
assert_not_contains "$(listing "${run}/claude.tar.zst.age")" "claude/plugins" "scheduled run drops regenerable Claude plugins"
assert_contains "$(listing "${run}/codex.tar.zst.age")" "codex/sessions/s" "scheduled run keeps Codex sessions"
assert_not_contains "$(listing "${run}/codex.tar.zst.age")" "codex/worktrees" "scheduled run drops Codex worktrees"
assert_contains "$(listing "${run}/gnupg.tar.zst.age")" "gnupg/private-keys-v1.d/k.key" "scheduled run includes the optional GnuPG source"
if [[ ! -s "${OP_LOG}" ]]; then pass "scheduled run never calls 1Password"; else fail "scheduled run never calls 1Password ($(<"${OP_LOG}"))"; fi

setup_agent_case override
printf "CLAUDE_EXCLUDES='projects'\n" >>"${CONFIG}"
AGENT_BACKUP_CONFIG="${CONFIG}" backup-agent-state --scheduled >/dev/null
run="$(find "${ROOT}" -mindepth 1 -maxdepth 1 -type d | head -1)"
assert_not_contains "$(listing "${run}/claude.tar.zst.age")" "claude/projects" "CLAUDE_EXCLUDES replaces the default list"
assert_contains "$(listing "${run}/claude.tar.zst.age")" "claude/plugins/p" "an override does not keep the default excludes"

setup_agent_case retention
for day in 1 2 3 4 5; do mkdir "${ROOT}/2026010${day}T000000Z.abcdef"; done
mkdir "${ROOT}/unrelated"
printf 'KEEP_RUNS=3\n' >>"${CONFIG}"
AGENT_BACKUP_CONFIG="${CONFIG}" backup-agent-state --scheduled >/dev/null
remaining="$(run_dirs)"
assert_not_contains "${remaining}" "20260103T000000Z.abcdef" "retention prunes runs beyond KEEP_RUNS"
assert_contains "${remaining}" "20260105T000000Z.abcdef" "retention keeps the newest older runs"
assert_contains "${remaining}" "20260104T000000Z.abcdef" "retention keeps KEEP_RUNS runs including the new one"
assert_contains "${remaining}" "unrelated" "retention ignores directories it did not create"
if [[ "$(grep -c '^2' <<<"${remaining}")" == 3 ]]; then pass "exactly KEEP_RUNS runs remain"; else fail "exactly KEEP_RUNS runs remain (${remaining//$'\n'/, })"; fi

setup_agent_case failure
mkdir "${ROOT}/20260101T000000Z.abcdef" "${ROOT}/20260102T000000Z.abcdef"
printf 'KEEP_RUNS=1\n' >>"${CONFIG}"
mkfifo "${CASE}/codex/sessions/pipe"
if AGENT_BACKUP_CONFIG="${CONFIG}" backup-agent-state --scheduled >/dev/null 2>&1; then
	fail "a failing scheduled run exits non-zero"
else
	pass "a failing scheduled run exits non-zero"
fi
if [[ "$(run_dirs)" == $'20260101T000000Z.abcdef\n20260102T000000Z.abcdef' ]]; then
	pass "a failing scheduled run removes its own run directory and prunes nothing"
else
	fail "a failing scheduled run removes its own run directory and prunes nothing ($(run_dirs | tr '\n' ' '))"
fi

finish_tests
