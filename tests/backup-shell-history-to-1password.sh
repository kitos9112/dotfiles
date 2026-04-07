#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(
  cd -- "$(dirname "$0")" >/dev/null 2>&1
  pwd -P
)"
REPO_ROOT="$(
  cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1
  pwd -P
)"
TEMPLATE_PATH="${REPO_ROOT}/home/private_dot_local/private_bin/executable_backup-shell-history-to-1password.sh.tmpl"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/backup-shell-history-tests.XXXXXX")"
trap 'rm -rf "${TMP_ROOT}"' EXIT HUP INT TERM
TEST_CHEZMOI_CONFIG="${TMP_ROOT}/empty-chezmoi.toml"
: >"${TEST_CHEZMOI_CONFIG}"

for dependency in bash chezmoi zip unzip; do
  command -v "${dependency}" >/dev/null 2>&1 || {
    printf 'missing dependency for tests: %s\n' "${dependency}" >&2
    exit 127
  }
done

fail() {
  printf 'not ok: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected=$1
  local actual=$2
  local message=$3

  if [ "${expected}" != "${actual}" ]; then
    printf 'expected: %s\n' "${expected}" >&2
    printf 'actual:   %s\n' "${actual}" >&2
    fail "${message}"
  fi
}

assert_file_exists() {
  local path=$1
  local message=$2

  [ -f "${path}" ] || fail "${message}"
}

assert_not_exists() {
  local path=$1
  local message=$2

  [ ! -e "${path}" ] || fail "${message}"
}

assert_permissions_600() {
  local path=$1
  local message=$2
  local mode

  mode="$(LC_ALL=C ls -ld "${path}" | awk '{print $1}')"
  [ "${mode}" = "-rw-------" ] || fail "${message}"
}

assert_contains() {
  local needle=$1
  local haystack=$2
  local message=$3

  case "${haystack}" in
    *"${needle}"*) ;;
    *) fail "${message}" ;;
  esac
}

archive_entries() {
  unzip -Z1 "$1" | LC_ALL=C sort
}

render_script() {
  local destination=$1
  local data_json=${2:-'{"shell_history_backup_document":"","shell_history_backup_vault":"","shell_history_backup_archive_name":""}'}

  chezmoi execute-template \
    --config "${TEST_CHEZMOI_CONFIG}" \
    --source "${REPO_ROOT}" \
    --file "${TEMPLATE_PATH}" \
    --override-data "${data_json}" >"${destination}"
  chmod 700 "${destination}"
}

make_mock_op() {
  local destination=$1

  cat >"${destination}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

{
  printf 'cmd'
  for arg in "$@"; do
    printf '\t%s' "${arg}"
  done
  printf '\n'
} >> "${OP_MOCK_LOG:?}"

if [ "${1:-}" = "whoami" ]; then
  [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] || exit 1
  [ "${OP_MOCK_FAIL_WHOAMI:-0}" = "1" ] && exit 1
  exit 0
fi

if [ "${1:-}" = "document" ] && [ "${2:-}" = "edit" ]; then
  [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] || exit 1
  if [ -n "${OP_MOCK_ARCHIVE:-}" ]; then
    cp "${4:?}" "${OP_MOCK_ARCHIVE}"
  fi

  [ "${OP_MOCK_FAIL_EDIT:-0}" = "1" ] && exit 1
  exit 0
fi

exit 64
EOF

  chmod 700 "${destination}"
}

setup_case() {
  local case_name=$1
  local data_json=${2:-'{"shell_history_backup_document":"","shell_history_backup_vault":"","shell_history_backup_archive_name":""}'}

  CASE_DIR="${TMP_ROOT}/${case_name}"
  HOME_DIR="${CASE_DIR}/home"
  BIN_DIR="${CASE_DIR}/bin"
  TMP_CASE_DIR="${CASE_DIR}/tmp"
  LOG_FILE="${CASE_DIR}/op.log"
  CAPTURED_ARCHIVE="${CASE_DIR}/captured.zip"
  SCRIPT_PATH="${CASE_DIR}/backup-shell-history-to-1password.sh"
  CONFIG_DIR="${HOME_DIR}/.config"
  ENV_FILE="${CONFIG_DIR}/backup-shell-history-to-1password.env"

  mkdir -p "${HOME_DIR}" "${BIN_DIR}" "${TMP_CASE_DIR}" "${CONFIG_DIR}"
  : >"${LOG_FILE}"
  cat >"${ENV_FILE}" <<'EOF'
OP_SERVICE_ACCOUNT_TOKEN=test-service-account-token
OP_VAULT=vault-from-env
EOF
  render_script "${SCRIPT_PATH}" "${data_json}"
  make_mock_op "${BIN_DIR}/op"
}

run_script() {
  local stdout_file=$1
  local stderr_file=$2
  shift 2
  local env_args=()

  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
    env_args+=("$1")
    shift
  done

  if [ "$#" -gt 0 ] && [ "$1" = "--" ]; then
    shift
  fi

  (
    export HOME="${HOME_DIR}"
    export XDG_CONFIG_HOME="${CONFIG_DIR}"
    export TMPDIR="${TMP_CASE_DIR}"
    export PATH="${BIN_DIR}:/usr/bin:/bin"
    export OP_MOCK_LOG="${LOG_FILE}"
    export OP_MOCK_ARCHIVE="${CAPTURED_ARCHIVE}"
    env "${env_args[@]}" "${SCRIPT_PATH}" "$@"
  ) >"${stdout_file}" 2>"${stderr_file}"
}

test_happy_path_both_histories() {
  setup_case "happy-both"
  printf 'echo hello\n' >"${HOME_DIR}/.bash_history"
  printf ': 1:0;pwd\n' >"${HOME_DIR}/.zsh_history"

  run_script "${CASE_DIR}/stdout" "${CASE_DIR}/stderr" OP_ITEM="Shell History Backup"

  assert_file_exists "${CAPTURED_ARCHIVE}" "captured archive missing"
  assert_eq $'.bash_history\n.zsh_history' "$(archive_entries "${CAPTURED_ARCHIVE}")" "archive should contain both histories"
  assert_contains $'cmd\twhoami' "$(cat "${LOG_FILE}")" "expected whoami call"
  assert_contains $'cmd\tdocument\tedit\tShell History Backup\t' "$(cat "${LOG_FILE}")" "expected document edit call"
  assert_contains $'\t--vault\tvault-from-env' "$(cat "${LOG_FILE}")" "expected vault from env file"
}

test_happy_path_only_bash() {
  setup_case "happy-bash"
  printf 'ls\n' >"${HOME_DIR}/.bash_history"

  run_script "${CASE_DIR}/stdout" "${CASE_DIR}/stderr" OP_ITEM="Shell History Backup"

  assert_eq '.bash_history' "$(archive_entries "${CAPTURED_ARCHIVE}")" "archive should contain only bash history"
}

test_happy_path_only_zsh() {
  setup_case "happy-zsh"
  printf ': 1:0;git status\n' >"${HOME_DIR}/.zsh_history"

  run_script "${CASE_DIR}/stdout" "${CASE_DIR}/stderr" OP_ITEM="Shell History Backup"

  assert_eq '.zsh_history' "$(archive_entries "${CAPTURED_ARCHIVE}")" "archive should contain only zsh history"
}

test_failure_when_no_histories_exist() {
  setup_case "missing-histories"

  if run_script "${CASE_DIR}/stdout" "${CASE_DIR}/stderr" OP_ITEM="Shell History Backup"; then
    fail "script should fail when no history files exist"
  fi

  assert_contains "no shell history files found" "$(cat "${CASE_DIR}/stderr")" "expected missing history error"
  assert_not_exists "${CAPTURED_ARCHIVE}" "archive should not be captured on failure"
}

test_failure_when_op_is_missing() {
  setup_case "missing-op"
  printf 'echo test\n' >"${HOME_DIR}/.bash_history"

  if (
    export HOME="${HOME_DIR}"
    export XDG_CONFIG_HOME="${CONFIG_DIR}"
    export TMPDIR="${TMP_CASE_DIR}"
    export PATH="/usr/bin:/bin"
    "${SCRIPT_PATH}"
  ) >"${CASE_DIR}/stdout" 2>"${CASE_DIR}/stderr"; then
    fail "script should fail when op is missing"
  fi

  assert_contains "missing dependency: op" "$(cat "${CASE_DIR}/stderr")" "expected missing op error"
}

test_failure_when_destination_is_not_configured() {
  setup_case "missing-destination"
  printf 'history\n' >"${HOME_DIR}/.bash_history"

  if run_script "${CASE_DIR}/stdout" "${CASE_DIR}/stderr"; then
    fail "script should fail when destination is not configured"
  fi

  assert_contains "Configuration help" "$(cat "${CASE_DIR}/stderr")" "expected config menu"
  assert_contains "config file is missing required values" "$(cat "${CASE_DIR}/stderr")" "expected destination error"
  assert_contains "OP_ITEM_ID or OP_ITEM" "$(cat "${CASE_DIR}/stderr")" "expected destination guidance"
}

test_failure_when_env_file_is_missing() {
  setup_case "missing-env-file"
  printf 'history\n' >"${HOME_DIR}/.bash_history"
  rm -f "${ENV_FILE}"

  if run_script "${CASE_DIR}/stdout" "${CASE_DIR}/stderr" OP_ITEM="Shell History Backup"; then
    fail "script should fail when env file is missing"
  fi

  assert_file_exists "${ENV_FILE}" "expected env file to be created"
  assert_permissions_600 "${ENV_FILE}" "expected env file mode 600"
  assert_contains "created template config file" "$(cat "${CASE_DIR}/stderr")" "expected env file creation message"
  assert_contains "OP_SERVICE_ACCOUNT_TOKEN=''" "$(cat "${ENV_FILE}")" "expected service account placeholder"
  assert_contains "OP_ITEM_ID=''" "$(cat "${ENV_FILE}")" "expected item id placeholder"
}

test_failure_when_env_file_is_incomplete() {
  setup_case "incomplete-env-file"
  printf 'history\n' >"${HOME_DIR}/.bash_history"
  cat >"${ENV_FILE}" <<'EOF'
OP_SERVICE_ACCOUNT_TOKEN=''
OP_VAULT=''
OP_ITEM_ID=''
EOF

  if run_script "${CASE_DIR}/stdout" "${CASE_DIR}/stderr"; then
    fail "script should fail when env file is incomplete"
  fi

  assert_contains "Configuration help" "$(cat "${CASE_DIR}/stderr")" "expected config menu"
  assert_contains "Missing required values:" "$(cat "${CASE_DIR}/stderr")" "expected missing values list"
  assert_contains "OP_SERVICE_ACCOUNT_TOKEN" "$(cat "${CASE_DIR}/stderr")" "expected token guidance"
  assert_contains "OP_VAULT" "$(cat "${CASE_DIR}/stderr")" "expected vault guidance"
  assert_contains "OP_ITEM_ID or OP_ITEM" "$(cat "${CASE_DIR}/stderr")" "expected item guidance"
}

test_dry_run_behavior() {
  setup_case "dry-run"
  printf 'echo dry-run\n' >"${HOME_DIR}/.bash_history"

  run_script "${CASE_DIR}/stdout" "${CASE_DIR}/stderr" OP_ITEM="Shell History Backup" -- --dry-run

  assert_eq '' "$(cat "${LOG_FILE}")" "dry run should not call op"
  assert_not_exists "${CAPTURED_ARCHIVE}" "dry run should not upload an archive"
  assert_contains "Dry run: would upload" "$(cat "${CASE_DIR}/stdout")" "expected dry-run message"
}

test_cleanup_of_temp_files_on_failure() {
  setup_case "cleanup-failure"
  printf 'echo cleanup\n' >"${HOME_DIR}/.bash_history"

  if (
    export HOME="${HOME_DIR}"
    export XDG_CONFIG_HOME="${CONFIG_DIR}"
    export TMPDIR="${TMP_CASE_DIR}"
    export PATH="${BIN_DIR}:/usr/bin:/bin"
    export OP_MOCK_LOG="${LOG_FILE}"
    export OP_MOCK_ARCHIVE="${CAPTURED_ARCHIVE}"
    export OP_MOCK_FAIL_EDIT=1
    "${SCRIPT_PATH}"
  ) >"${CASE_DIR}/stdout" 2>"${CASE_DIR}/stderr"; then
    fail "script should fail when upload fails"
  fi

  assert_eq '' "$(find "${TMP_CASE_DIR}" -mindepth 1 -maxdepth 1 -name 'backup-shell-history-to-1password.*' -print)" "temporary working directory should be removed"
}

test_rerun_uses_same_archive_target() {
  setup_case "rerun"
  printf 'first\n' >"${HOME_DIR}/.bash_history"

  run_script "${CASE_DIR}/stdout-1" "${CASE_DIR}/stderr-1" OP_ITEM="Shell History Backup"

  printf 'second\n' >"${HOME_DIR}/.bash_history"
  : >"${LOG_FILE}"
  run_script "${CASE_DIR}/stdout-2" "${CASE_DIR}/stderr-2" OP_ITEM="Shell History Backup"

  assert_contains $'cmd\tdocument\tedit\tShell History Backup\t' "$(cat "${LOG_FILE}")" "expected document edit on rerun"
  assert_contains $'\t--file-name\tshell-history.zip' "$(cat "${LOG_FILE}")" "expected stable archive name on rerun"
}

test_baked_default_document_name() {
  setup_case "baked-default" '{"shell_history_backup_document":"Baked Backup Document","shell_history_backup_vault":"","shell_history_backup_archive_name":""}'
  printf 'echo baked\n' >"${HOME_DIR}/.bash_history"

  run_script "${CASE_DIR}/stdout" "${CASE_DIR}/stderr"

  assert_contains $'cmd\tdocument\tedit\tBaked Backup Document\t' "$(cat "${LOG_FILE}")" "expected baked-in default document"
}

test_env_overrides_baked_default() {
  setup_case "env-overrides" '{"shell_history_backup_document":"Baked Backup Document","shell_history_backup_vault":"","shell_history_backup_archive_name":""}'
  printf 'echo override\n' >"${HOME_DIR}/.bash_history"

  run_script "${CASE_DIR}/stdout" "${CASE_DIR}/stderr" OP_ITEM_ID="doc-123" OP_ITEM="Runtime Name"

  assert_contains $'cmd\tdocument\tedit\tdoc-123\t' "$(cat "${LOG_FILE}")" "expected OP_ITEM_ID to override baked default"
}

tests=(
  test_happy_path_both_histories
  test_happy_path_only_bash
  test_happy_path_only_zsh
  test_failure_when_no_histories_exist
  test_failure_when_op_is_missing
  test_failure_when_destination_is_not_configured
  test_failure_when_env_file_is_missing
  test_failure_when_env_file_is_incomplete
  test_dry_run_behavior
  test_cleanup_of_temp_files_on_failure
  test_rerun_uses_same_archive_target
  test_baked_default_document_name
  test_env_overrides_baked_default
)

for test_name in "${tests[@]}"; do
  printf '==> %s\n' "${test_name}"
  "${test_name}"
done

printf 'ok: %s tests passed\n' "${#tests[@]}"
