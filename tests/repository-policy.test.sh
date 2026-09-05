#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck source=tests/lib/contract-test.sh
source "${SCRIPT_DIR}/lib/contract-test.sh"

COMPLETION_TEMPLATE="${SOURCE_DIR}/dot_oh-my-zsh-custom/plugins/chezmoi/_chezmoi.tmpl"

echo "== chezmoi compatibility contract =="
assert_file_content "${SOURCE_DIR}/.chezmoiversion" "2.72.0" "chezmoi floor is 2.72.0"
assert_not_contains "$(<"${SOURCE_DIR}/.chezmoi.toml.tmpl")" \
	'missingkey=zero' "templates use strict missing-key behavior"

echo "== native completion =="
assert_file_exists "${COMPLETION_TEMPLATE}" "completion is a chezmoi template"
if [[ -f "${COMPLETION_TEMPLATE}" ]]; then
	assert_file_content "${COMPLETION_TEMPLATE}" '{{ completion "zsh" }}' \
		"completion source uses chezmoi's native function"
	completion="$(render_template "${COMPLETION_TEMPLATE}")"
	assert_contains "${completion}" '#compdef chezmoi' "native completion renders zsh metadata"
fi

echo "== obsolete sources =="
for obsolete in \
	"${SCRIPTS_DIR}/run_after_110-update-completions.zsh.tmpl" \
	"${SCRIPTS_DIR}/run_after_102-reload.zsh.tmpl" \
	"${SOURCE_DIR}/ansible.cfg" \
	"${SOURCE_DIR}/scripts/install_dotfiles.sh"; do
	assert_file_absent "${obsolete}" "$(basename "${obsolete}") is removed"
done

for superseded in \
	"${SCRIPTS_DIR}/run_after_080-install-asdf-plugins.sh.tmpl" \
	"${SCRIPTS_DIR}/run_after_099-update-asdf.sh.tmpl" \
	"${SCRIPTS_DIR}/run_after_103-rust-dev.zsh.tmpl" \
	"${SCRIPTS_DIR}/run_after_900-finalizers.zsh.tmpl" \
	"${SCRIPTS_DIR}/run_once_after_10-linux-install-iac-tools.sh.tmpl" \
	"${SOURCE_DIR}/scripts/.helpers"; do
	assert_file_absent "${superseded}" "$(basename "${superseded}") is superseded"
done

echo "== source attributes and modern functions =="
assert_file_exists "${SOURCE_DIR}/private_dot_config/private_homebrew/brew.env" \
	"Homebrew state is private in the target path"
assert_file_exists "${SOURCE_DIR}/private_dot_config/private_opencode/create_opencode.json" \
	"OpenCode defaults use create_ semantics"
assert_file_exists "${SOURCE_DIR}/private_dot_codex/create_private_config.toml" \
	"Codex defaults use create_ semantics"
assert_contains "$(<"${SCRIPTS_DIR}/run_onchange_after_080-asdf-tools.sh.tmpl")" \
	'shellQuote' "shell arguments use chezmoi 2.72 quoting"
if aliases="$(render_template "${SOURCE_DIR}/dot_oh-my-zsh-custom/aliases.zsh.tmpl")"; then
	pass "optional 1Password aliases render with fresh data"
	assert_not_contains "${aliases}" 'saml2aws-vf' "unset private item aliases are omitted"
else
	fail "optional 1Password aliases render with fresh data"
fi

echo "== unified local and CI tests =="
taskfile="$(<"${REPO_ROOT}/Taskfile.yaml")"
workflow="$(<"${REPO_ROOT}/.github/workflows/acceptance-tests.yaml")"
assert_contains "${taskfile}" '  test:' "Taskfile defines the unified test target"
for command in \
	'bash tests/profile-config.test.sh' \
	'bash tests/packages-externals.test.sh' \
	'bash tests/desktop-integrations.test.sh' \
	'bash tests/script-contracts.test.sh' \
	'bash tests/managed-config.test.sh' \
	'bash tests/repository-policy.test.sh' \
	'bash tests/freeipa-tools.test.sh' \
	'bash tests/go-tools.test.sh' \
	'bash tests/wireshark-profiles.test.sh' \
	'bash tests/backup-shell-history-to-1password.sh'; do
	assert_contains "${taskfile}" "${command}" "task test runs ${command#bash tests/}"
done
assert_contains "${workflow}" 'chezmoi: "2.72.0"' "CI tests the minimum chezmoi version"
assert_contains "${workflow}" 'chezmoi: latest' "CI tests the latest chezmoi version"
assert_contains "${workflow}" 'task test' "CI uses the same test entry point as developers"

echo "== dependency update ownership =="
renovate_config="$(<"${REPO_ROOT}/.github/renovate.json5")"
assert_contains "${renovate_config}" ':enableVulnerabilityAlerts' \
	"Renovate owns vulnerability update pull requests"
assert_file_absent "${REPO_ROOT}/.github/workflows/renovate.yaml" \
	"Renovate SaaS is the only Renovate runner"
assert_file_absent "${REPO_ROOT}/.github/dependabot.yml" \
	"Dependabot version updates are not configured"

echo "== Linux smoke dependencies =="
for family in ubuntu almalinux; do
	dockerfile="${REPO_ROOT}/tests/Dockerfile.${family}"
	assert_contains "$(<"${dockerfile}")" $'\n    jq' \
		"${family} smoke image supplies jq when scripts are excluded"
done

echo "== DNF package ownership =="
prereq_source="$(<"${SCRIPTS_DIR}/run_once_before_01-linux-install-prereq.sh.tmpl")"
assert_not_contains "${prereq_source}" 'dnf update' \
	"one-time prerequisites do not update DNF"
assert_not_contains "${prereq_source}" 'glibc-langpack-en' \
	"one-time prerequisites do not embed the Fedora or AlmaLinux package list"

finish_tests
