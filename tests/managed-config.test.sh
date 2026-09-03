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

echo "== native fzf shell integration =="
shell_home="${TMP_ROOT}/shell-home"
asdf_shims="${TMP_ROOT}/asdf-shims"
competing_bin="${TMP_ROOT}/competing-bin"
mkdir -p "${shell_home}/go" "${shell_home}/.oh-my-zsh" \
	"${shell_home}/.oh-my-zsh-custom/plugins/zsh-completions/src" \
	"${shell_home}/.local/bin" "${asdf_shims}" "${competing_bin}"
: >"${shell_home}/.oh-my-zsh/oh-my-zsh.sh"
cat >"${asdf_shims}/fzf" <<'EOF'
#!/usr/bin/env bash
case "${1-}" in
  --bash) printf '%s\n' 'asdf_fzf_bash_marker() { :; }' ;;
  --zsh) printf '%s\n' 'asdf-fzf-zsh-marker() { :; }' ;;
  --version) printf '%s\n' '0.74.1' ;;
  *) exit 64 ;;
esac
EOF
cat >"${competing_bin}/fzf" <<'EOF'
#!/usr/bin/env bash
case "${1-}" in
  --bash) printf '%s\n' 'export FZF_BASH_INTEGRATION=competing' ;;
  --zsh) printf '%s\n' 'export FZF_ZSH_INTEGRATION=competing' ;;
  --version) printf '%s\n' '0.47.0' ;;
  *) exit 64 ;;
esac
EOF
chmod 700 "${asdf_shims}/fzf" "${competing_bin}/fzf"

rendered_bashrc="${TMP_ROOT}/bashrc"
rendered_zshrc="${TMP_ROOT}/zshrc"
PATH="${asdf_shims}:${competing_bin}:/usr/bin:/bin" render_for linux ubuntu desktop "${SOURCE_DIR}/dot_bashrc.tmpl" \
	>"${rendered_bashrc}"
PATH="${asdf_shims}:${competing_bin}:/usr/bin:/bin" render_for linux ubuntu desktop "${SOURCE_DIR}/dot_zshrc.tmpl" \
	>"${rendered_zshrc}"
assert_not_contains "$(<"${rendered_zshrc}")" '$HOME/.local/bin/fzf' \
	"Zsh does not force a private fzf path"

if HOME="${shell_home}" SHELL=/bin/zsh PATH="${asdf_shims}:${competing_bin}:/usr/bin:/bin" \
	bash --noprofile --norc -ic \
	'source "$1"; declare -F asdf_fzf_bash_marker >/dev/null' \
	_ "${rendered_bashrc}" \
	>"${TMP_ROOT}/bashrc.out" 2>&1; then
	pass "Bash loads fzf integration through the asdf shim"
else
	fail "Bash loads fzf integration through the asdf shim"
fi

if HOME="${shell_home}" PATH="${asdf_shims}:${competing_bin}:/usr/bin:/bin" \
	zsh -dfic \
	'source "$1"; [[ "${path[1]}" == "$2" ]] && (( $+functions[asdf-fzf-zsh-marker] ))' \
	_ "${rendered_zshrc}" "${asdf_shims}" \
	>"${TMP_ROOT}/zshrc.out" 2>&1; then
	pass "Zsh keeps asdf shims first and loads fzf integration"
else
	fail "Zsh keeps asdf shims first and loads fzf integration"
fi

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

	no_jq_bin="${TMP_ROOT}/no-jq-bin"
	mkdir -p "${no_jq_bin}"
	ln -s "$(command -v cat)" "${no_jq_bin}/cat"
	if missing_jq_output="$(PATH="${no_jq_bin}" "${BASH}" "${merge_script}" 2>&1)"; then
		fail "Claude settings report a missing jq dependency"
	else
		missing_jq_status=$?
		if [[ "${missing_jq_status}" == 127 ]]; then
			pass "missing jq uses the command-not-found exit status"
		else
			fail "missing jq uses the command-not-found exit status (got ${missing_jq_status})"
		fi
		assert_contains "${missing_jq_output}" 'jq is required' \
			"Claude settings report a missing jq dependency"
		assert_not_contains "${missing_jq_output}" 'not valid JSON' \
			"missing jq is not reported as corrupt settings"
	fi
fi

finish_tests
