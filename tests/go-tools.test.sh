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
GO_TOOLS_TEMPLATE="${REPO_ROOT}/home/.chezmoiscripts/run_onchange_after_104-install-go-tools.zsh.tmpl"
ASDF_UPDATE_TEMPLATE="${REPO_ROOT}/home/.chezmoiscripts/run_after_099-update-asdf.sh.tmpl"
GO_TOOLS_SOURCE="${REPO_ROOT}/home/private_dot_config/dotfiles/go-tools"
ACCEPTANCE_WORKFLOW="${REPO_ROOT}/.github/workflows/acceptance-tests.yaml"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/go-tools-tests.XXXXXX")"
trap 'rm -rf "${TMP_ROOT}"' EXIT HUP INT TERM
TEST_CHEZMOI_CONFIG="${TMP_ROOT}/empty-chezmoi.toml"
: >"${TEST_CHEZMOI_CONFIG}"

fail() {
  printf 'not ok: %s\n' "$*" >&2
  exit 1
}

assert_file_exists() {
  local path=$1
  local message=$2

  [ -f "${path}" ] || fail "${message}"
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
    --file "${template}" \
    --override-data '{"is_root":false,"is_wsl":false}' >"${destination}"
  chmod 700 "${destination}"
}

make_recording_asdf() {
  local destination=$1

  cat >"${destination}" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

{
  printf 'cmd'
  for arg in "$@"; do
    printf '\t%s' "${arg}"
  done
  printf '\tGOROOT=%s\tGOPATH=%s\tGOBIN=%s\n' \
    "${GOROOT-unset}" "${GOPATH-unset}" "${GOBIN-unset}"
} >>"${ASDF_MOCK_LOG:?}"

if [ "${1:-}" = "plugin" ] && [ "${2:-}" = "update" ]; then
  exit 0
fi

if [ "${1:-}" = "install" ]; then
  [ "${ASDF_MOCK_FAIL_INSTALL:-0}" = "1" ] && exit 42
  exit 0
fi

if [ "${1:-}" = "exec" ] && [ "${2:-}" = "go" ]; then
  [ "${GOROOT+x}" != "x" ] || exit 51
  [ "${GOPATH+x}" != "x" ] || exit 52
  [ "${GOBIN+x}" != "x" ] || exit 53
  [ "${3:-}" = "-C" ] || exit 54
  [ "${4:-}" = "${HOME}/.config/dotfiles/go-tools" ] || exit 55
  [ "${5:-}" = "install" ] || exit 56
  [ "${6:-}" = "tool" ] || exit 57
  exit 0
fi

if [ "${1:-}" = "reshim" ] && [ "${2:-}" = "golang" ]; then
  exit 0
fi

exit 64
EOF

  chmod 700 "${destination}"
}

setup_case() {
  CASE_DIR="${TMP_ROOT}/case"
  HOME_DIR="${CASE_DIR}/home"
  LOG_FILE="${CASE_DIR}/asdf.log"
  GO_TOOLS_SCRIPT="${CASE_DIR}/install-go-tools.zsh"
  ASDF_UPDATE_SCRIPT="${CASE_DIR}/update-asdf.sh"

  mkdir -p \
    "${HOME_DIR}/.local/bin" \
    "${HOME_DIR}/.config/dotfiles/go-tools"
  : >"${LOG_FILE}"

  assert_file_exists "${GO_TOOLS_TEMPLATE}" "Go tools installer template is missing"
  assert_file_exists "${GO_TOOLS_SOURCE}/go.mod" "Go tools go.mod is missing"
  assert_file_exists "${GO_TOOLS_SOURCE}/go.sum" "Go tools go.sum is missing"

  cp "${GO_TOOLS_SOURCE}/go.mod" "${HOME_DIR}/.config/dotfiles/go-tools/go.mod"
  cp "${GO_TOOLS_SOURCE}/go.sum" "${HOME_DIR}/.config/dotfiles/go-tools/go.sum"
  make_recording_asdf "${HOME_DIR}/.local/bin/asdf"
  render_template "${GO_TOOLS_TEMPLATE}" "${GO_TOOLS_SCRIPT}"
  render_template "${ASDF_UPDATE_TEMPLATE}" "${ASDF_UPDATE_SCRIPT}"
}

test_go_tools_install_normalizes_asdf_environment() {
  printf '==> %s\n' "${FUNCNAME[0]}"
  : >"${LOG_FILE}"

  HOME="${HOME_DIR}" \
    PATH="/usr/bin:/bin" \
    ASDF_MOCK_LOG="${LOG_FILE}" \
    GOROOT="${HOME_DIR}/.asdf/installs/golang/old/go" \
    GOPATH="${HOME_DIR}/.asdf/installs/golang/old/packages" \
    GOBIN="${HOME_DIR}/.asdf/installs/golang/old/bin" \
    zsh "${GO_TOOLS_SCRIPT}"

  assert_contains \
    $'cmd\texec\tgo\t-C\t'"${HOME_DIR}"$'/.config/dotfiles/go-tools\tinstall\ttool\tGOROOT=unset\tGOPATH=unset\tGOBIN=unset' \
    "${LOG_FILE}" \
    "installer did not invoke Go with a normalized asdf environment"
  assert_contains \
    $'cmd\treshim\tgolang' \
    "${LOG_FILE}" \
    "installer did not refresh golang shims"
}

test_go_tools_script_fingerprints_inputs() {
  printf '==> %s\n' "${FUNCNAME[0]}"
  local fingerprint_count

  fingerprint_count="$(
    grep -Ec '^# (go\.mod|go\.sum|dot_tool-versions\.tmpl) sha256: [0-9a-f]{64}$' \
      "${GO_TOOLS_SCRIPT}"
  )"
  [ "${fingerprint_count}" = "3" ] ||
    fail "installer does not fingerprint all three change inputs"
}

test_asdf_install_failure_propagates() {
  printf '==> %s\n' "${FUNCNAME[0]}"
  : >"${LOG_FILE}"

  if HOME="${HOME_DIR}" \
    PATH="/usr/bin:/bin" \
    ASDF_MOCK_LOG="${LOG_FILE}" \
    ASDF_MOCK_FAIL_INSTALL=1 \
    bash "${ASDF_UPDATE_SCRIPT}"; then
    fail "asdf update script suppressed an asdf install failure"
  fi
}

test_go_tools_checks_are_wired_into_ci() {
  printf '==> %s\n' "${FUNCNAME[0]}"

  assert_contains \
    "bash tests/go-tools.test.sh" \
    "${ACCEPTANCE_WORKFLOW}" \
    "acceptance workflow does not run the Go tools regression suite"
  assert_contains \
    "go -C home/private_dot_config/dotfiles/go-tools mod verify" \
    "${ACCEPTANCE_WORKFLOW}" \
    "acceptance workflow does not verify the Go tools module"
  assert_contains \
    "go -C home/private_dot_config/dotfiles/go-tools install tool" \
    "${ACCEPTANCE_WORKFLOW}" \
    "acceptance workflow does not compile the declared Go tools"
  assert_contains \
    "list -m -f '{{.Version}}' github.com/mbrt/gmailctl" \
    "${ACCEPTANCE_WORKFLOW}" \
    "acceptance workflow does not derive gmailctl's expected version from go.mod"
  assert_not_contains \
    "github.com/mbrt/gmailctl\\tv0.12.0" \
    "${ACCEPTANCE_WORKFLOW}" \
    "acceptance workflow hardcodes gmailctl's current version"
}

setup_case
test_go_tools_install_normalizes_asdf_environment
test_go_tools_script_fingerprints_inputs
test_asdf_install_failure_propagates
test_go_tools_checks_are_wired_into_ci

printf 'ok: 4 tests passed\n'
