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

finish_tests
