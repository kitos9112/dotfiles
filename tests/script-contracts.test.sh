#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck source=tests/lib/contract-test.sh
source "${SCRIPT_DIR}/lib/contract-test.sh"

ASDF_TEMPLATE="${SCRIPTS_DIR}/run_onchange_after_080-asdf-tools.sh.tmpl"
RUST_TEMPLATE="${SCRIPTS_DIR}/run_onchange_after_103-rust-dev.sh.tmpl"
SESSION_MANAGER_TEMPLATE="${SCRIPTS_DIR}/run_once_after_10-linux-install-session-manager.sh.tmpl"

assert_count() {
	local haystack=$1 needle=$2 expected=$3 label=$4 count
	count="$(grep -F -c -- "${needle}" <<<"${haystack}" || true)"
	if [[ "${count}" == "${expected}" ]]; then
		pass "${label}"
	else
		fail "${label} (expected ${expected}, got ${count})"
	fi
}

echo "== manifest-driven ASDF convergence =="
assert_file_exists "${SOURCE_DIR}/.chezmoidata/asdf.yaml" "ASDF plugin manifest exists"
assert_file_exists "${ASDF_TEMPLATE}" "single ASDF convergence template exists"

if [[ -f "${ASDF_TEMPLATE}" ]]; then
	asdf_source="$(<"${ASDF_TEMPLATE}")"
	assert_contains "${asdf_source}" 'asdf manifest sha256:' "ASDF script fingerprints its manifest"
	assert_contains "${asdf_source}" 'dot_tool-versions.tmpl sha256:' "ASDF script fingerprints tool versions"
	assert_not_contains "${asdf_source}" 'plugin update --all' "ASDF script does not update plugins"

	case_home="${TMP_ROOT}/asdf-home"
	mkdir -p "${case_home}/.local/bin"
	asdf_log="${TMP_ROOT}/asdf.log"
	rendered_asdf="${TMP_ROOT}/asdf-tools.sh"
	cat >"${case_home}/.local/bin/asdf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${ASDF_MOCK_LOG:?}"
if [[ "${1-} ${2-}" == "plugin list" ]]; then
  printf '%s\n' kubectl
  exit 0
fi
if [[ "${1-}" == install ]]; then
  [[ "${ASDF_MOCK_FAIL_INSTALL:-0}" == 1 ]] && exit 42
  exit 0
fi
if [[ "${1-} ${2-}" == "plugin add" ]]; then
  exit 0
fi
exit 64
EOF
	chmod 700 "${case_home}/.local/bin/asdf"
	render_template "${ASDF_TEMPLATE}" \
		'{"chezmoi":{"os":"linux","arch":"amd64"},"is_wsl":false}' >"${rendered_asdf}"
	chmod 700 "${rendered_asdf}"

	: >"${asdf_log}"
	HOME="${case_home}" ASDF_MOCK_LOG="${asdf_log}" PATH=/usr/bin:/bin \
		bash "${rendered_asdf}"
	asdf_calls="$(<"${asdf_log}")"
	assert_count "${asdf_calls}" 'install' 1 "ASDF install runs exactly once"
	assert_not_contains "${asdf_calls}" 'plugin add kubectl' "existing ASDF plugins are skipped"
	assert_contains "${asdf_calls}" 'plugin add terraform https://github.com/asdf-community/asdf-hashicorp.git' \
		"ASDF plugin URL is passed as one argument"

	: >"${asdf_log}"
	if HOME="${case_home}" ASDF_MOCK_LOG="${asdf_log}" ASDF_MOCK_FAIL_INSTALL=1 \
		PATH=/usr/bin:/bin bash "${rendered_asdf}" >"${TMP_ROOT}/asdf-failure.out" 2>&1; then
		pass "ASDF install failure does not abort chezmoi apply"
	else
		fail "ASDF install failure does not abort chezmoi apply"
	fi
	assert_contains "$(<"${TMP_ROOT}/asdf-failure.out")" 'failed to install' \
		"ASDF install failure emits an actionable warning"
fi

echo "== Rust and Session Manager scope =="
assert_file_exists "${RUST_TEMPLATE}" "Rust setup is an onchange template"
assert_file_exists "${SESSION_MANAGER_TEMPLATE}" "Session Manager has a focused run-once template"
assert_contains "$(<"${SOURCE_DIR}/.chezmoidata/packages.yaml")" 'version: "1.3.0"' \
	"license-generator is pinned"

if [[ -f "${RUST_TEMPLATE}" ]]; then
	rust_source="$(<"${RUST_TEMPLATE}")"
	assert_contains "${rust_source}" 'rust manifest sha256:' "Rust script fingerprints its manifest"
	assert_contains "${rust_source}" 'cargo install' "Rust script installs declared cargo tools"
	assert_contains "${rust_source}" '--locked' "cargo installs use the lockfile"
fi

if [[ -f "${SESSION_MANAGER_TEMPLATE}" ]]; then
	session_source="$(<"${SESSION_MANAGER_TEMPLATE}")"
	assert_not_contains "${session_source}" '.terraform-version' "Session Manager script does not mutate Terraform versions"
	assert_contains "${session_source}" 'mktemp -d' "Session Manager download uses a temporary directory"
fi

echo "== apply is free of implicit upgrades =="
upgrade_matches="$(grep -R -E '(^|[[:space:]])(brew|\$brew|"\$\{BREW\}") update|plugin update --all' \
	"${SCRIPTS_DIR}" || true)"
if [[ -z "${upgrade_matches}" ]]; then
	pass "chezmoi apply does not perform package-manager upgrades"
else
	fail "chezmoi apply still performs package-manager upgrades: ${upgrade_matches}"
fi

echo "== rendered script syntax =="
while IFS='|' read -r os os_id profile script; do
	[[ -n "${script}" ]] || continue
	path="${SCRIPTS_DIR}/${script}"
	assert_file_exists "${path}" "${script} exists"
	if [[ -f "${path}" ]]; then
		rendered="$(render_for "${os}" "${os_id}" "${profile}" "${path}")"
		assert_valid_bash "${rendered}" "${script} renders valid Bash"
	fi
done <<'EOF'
linux|ubuntu|desktop|run_onchange_before_03-linux-apt-packages.sh.tmpl
linux|ubuntu|desktop|run_once_after_20-1password-signin.sh.tmpl
linux|ubuntu|desktop|run_onchange_after_25-install-ghostty.sh.tmpl
linux|ubuntu|desktop|run_onchange_after_30-gnome-settings.sh.tmpl
linux|ubuntu|desktop|run_onchange_after_35-refresh-font-cache.sh.tmpl
darwin|darwin|desktop|run_onchange_after_36-darwin-terminal-fonts.sh.tmpl
darwin|darwin|desktop|run_onchange_after_40-install-ai-clis.sh.tmpl
linux|ubuntu|server|run_after_800-create-symblinks.sh.tmpl
EOF

echo "== bootstrap resilience =="
assert_file_exists "${SCRIPTS_DIR}/run_after_015-fzf-shell-integration.sh.tmpl" \
	"fzf integration runs after externals"
assert_contains "$(<"${SCRIPTS_DIR}/run_after_800-create-symblinks.sh.tmpl")" \
	'if [[ ! -e "$HOME/$path" ]]' "symlink replication skips missing sources"

omz_source="$(<"${SCRIPTS_DIR}/run_once_before_02-install-omz.sh.tmpl")"
assert_contains "${omz_source}" 'grep -q "^${username}:" /etc/passwd' \
	"login-shell changes are limited to local accounts"
assert_contains "${omz_source}" 'if sudo chsh' "a failed chsh does not abort bootstrap"
assert_contains "$(<"${SOURCE_DIR}/dot_bashrc.tmpl")" \
	'"$(basename -- "${SHELL:-}")" != "zsh"' "interactive Bash hands over to Zsh"

trust_source="$(<"${SCRIPTS_DIR}/run_onchange_after_01-brew-trust-taps.sh.tmpl")"
assert_contains "${trust_source}" 'chmod 700' "Homebrew trust stores are private"
assert_file_exists "${SOURCE_DIR}/private_dot_config/private_homebrew/brew.env" \
	"managed Homebrew config uses the private_ attribute"

echo "== pipeline safety =="
sigpipe_hits=0
while IFS= read -r candidate; do
	grep -qE 'pipefail|scripts-library' "${candidate}" || continue
	while IFS= read -r hit; do
		fail "grep --quiet in a pipefail pipeline: ${hit}"
		sigpipe_hits=$((sigpipe_hits + 1))
	done < <(grep -n -- '| *grep [^|]*--quiet\|| *grep -[a-zA-Z]*q' "${candidate}" || true)
done < <(find "${SCRIPTS_DIR}" "${SOURCE_DIR}/private_dot_local/private_bin" -type f)
((sigpipe_hits > 0)) || pass "no SIGPIPE-prone grep pipelines remain"

finish_tests
