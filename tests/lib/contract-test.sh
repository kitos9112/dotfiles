#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." && pwd -P)"
SOURCE_DIR="${REPO_ROOT}/home"
SCRIPTS_DIR="${SOURCE_DIR}/.chezmoiscripts"
CHEZMOI_BIN="$(command -v chezmoi)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-contract.XXXXXX")"
EMPTY_CONFIG="${TMP_ROOT}/empty.toml"
: >"${EMPTY_CONFIG}"
trap 'rm -rf "${TMP_ROOT}"' EXIT HUP INT TERM

failures=0

pass() {
	printf '  ok   %s\n' "$1"
}

fail() {
	printf '  FAIL %s\n' "$1" >&2
	failures=$((failures + 1))
}

assert_contains() {
	local haystack=$1 needle=$2 label=$3
	if [[ "${haystack}" == *"${needle}"* ]]; then
		pass "${label}"
	else
		fail "${label} (expected to find: ${needle})"
	fi
}

assert_not_contains() {
	local haystack=$1 needle=$2 label=$3
	if [[ "${haystack}" != *"${needle}"* ]]; then
		pass "${label}"
	else
		fail "${label} (unexpectedly found: ${needle})"
	fi
}

assert_file_exists() {
	local path=$1 label=$2
	if [[ -e "${path}" ]]; then
		pass "${label}"
	else
		fail "${label} (missing: ${path})"
	fi
}

assert_file_absent() {
	local path=$1 label=$2
	if [[ ! -e "${path}" ]]; then
		pass "${label}"
	else
		fail "${label} (still present: ${path})"
	fi
}

assert_file_content() {
	local path=$1 expected=$2 label=$3
	if [[ -f "${path}" && "$(<"${path}")" == "${expected}" ]]; then
		pass "${label}"
	else
		fail "${label}"
	fi
}

render_template() {
	local file=$1 override
	override=${2-}
	[[ -n "${override}" ]] || override='{}'
	"${CHEZMOI_BIN}" execute-template --config "${EMPTY_CONFIG}" \
		--source "${SOURCE_DIR}" --override-data "${override}" \
		--file "${file}"
}

render_for() {
	local os=$1 os_id=$2 profile=$3 file=$4 override
	override="$(jq -cn \
		--arg os "${os}" \
		--arg id "${os_id}" \
		--arg profile "${profile}" \
		'{chezmoi:{os:$os,osRelease:{id:$id}},osid:(if $os == "linux" then "linux-" + $id else $id end),machine_class:$profile,is_root:false,is_work:false,is_wsl:false,use_homebrew:false,github_username:"kitos9112"}')"
	DOTFILES_PROFILE="${profile}" DOTFILES_HOMEBREW=false \
		render_template "${file}" "${override}"
}

assert_valid_bash() {
	local content=$1 label=$2 script="${TMP_ROOT}/syntax-$RANDOM.sh"
	printf '%s\n' "${content}" >"${script}"
	if bash -n "${script}" 2>/dev/null; then
		pass "${label}"
	else
		fail "${label}"
	fi
}

finish_tests() {
	if ((failures > 0)); then
		printf '\n%d contract test(s) failed\n' "${failures}" >&2
		exit 1
	fi
	printf '\nAll contract tests passed\n'
}
