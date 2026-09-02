#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck source=tests/lib/contract-test.sh
source "${SCRIPT_DIR}/lib/contract-test.sh"

echo "== managed helper rendering =="
for helper in dotfiles-doctor dotfiles-reset gnome-settings-export; do
	path="${SOURCE_DIR}/private_dot_local/private_bin/executable_${helper}.tmpl"
	assert_file_exists "${path}" "${helper} source exists"
	if [[ -f "${path}" ]]; then
		rendered="$(render_for linux ubuntu desktop "${path}")"
		assert_valid_bash "${rendered}" "${helper} renders valid Bash"
	fi
done

echo "== non-clobbering seeds =="
for seed in \
	private_dot_config/private_opencode/create_opencode.json \
	private_dot_codex/create_private_config.toml; do
	assert_file_exists "${SOURCE_DIR}/${seed}" "${seed} uses create_ semantics"
done

echo "== Claude settings merge =="
claude_template="${SOURCE_DIR}/dot_claude/modify_settings.json.tmpl"
assert_file_exists "${claude_template}" "Claude settings use a modify_ template"

if [[ -f "${claude_template}" ]]; then
	merge_script="${TMP_ROOT}/modify-settings"
	render_for darwin darwin desktop "${claude_template}" >"${merge_script}"
	chmod 700 "${merge_script}"

	seeded="$(: | "${merge_script}")"
	if jq -e . >/dev/null <<<"${seeded}"; then
		pass "fresh Claude settings are valid JSON"
	else
		fail "fresh Claude settings are valid JSON"
	fi
	assert_contains "${seeded}" 'EnterWorktree' "fresh settings contain the managed deny-list"
	assert_contains "${seeded}" '.claude/hooks/context-mode-cache-heal.mjs' \
		"fresh settings contain the managed hook"

	existing='{"theme":"light","model":"local-model","permissions":{"allow":["Bash(local:*)"],"deny":["StaleEntry"]},"localOnly":true}'
	merged="$("${merge_script}" <<<"${existing}")"
	assert_contains "$(jq -r '.theme' <<<"${merged}")" 'light' "runtime theme survives the merge"
	assert_contains "$(jq -r '.model' <<<"${merged}")" 'local-model' "runtime model survives the merge"
	assert_contains "$(jq -c '.permissions.allow' <<<"${merged}")" 'Bash(local:*)' \
		"machine-local permissions survive the merge"
	assert_contains "$(jq -c '.permissions.deny' <<<"${merged}")" 'EnterWorktree' \
		"managed permissions replace stale values"
	assert_not_contains "$(jq -c '.permissions.deny' <<<"${merged}")" 'StaleEntry' \
		"stale managed values are removed"

	if [[ "$("${merge_script}" <<<"${merged}")" == "${merged}" ]]; then
		pass "Claude settings merge is idempotent"
	else
		fail "Claude settings merge is idempotent"
	fi

	if "${merge_script}" <<<'{ not json' >/dev/null 2>&1; then
		fail "malformed Claude settings are rejected"
	else
		pass "malformed Claude settings are rejected"
	fi
fi

finish_tests
