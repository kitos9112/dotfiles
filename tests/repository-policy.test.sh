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
lint_workflow="$(<"${REPO_ROOT}/.github/workflows/linters.yaml")"
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
assert_contains "${workflow}" 'name: Acceptance Gate' \
	"CI exposes one stable required-check name"
for required_job in go-tools contracts linux macos; do
	assert_contains "${workflow}" "      - ${required_job}" \
		"the acceptance gate depends on ${required_job}"
done
assert_contains "${workflow}" 'if: always()' \
	"the acceptance gate reports failures and cancellations"
assert_contains "${lint_workflow}" 'name: Security Gate' \
	"CI exposes a stable required security-check name"
assert_contains "${lint_workflow}" 'VALIDATE_TRIVY: true' \
	"the security gate runs the repository-wide Trivy scan"
assert_contains "${lint_workflow}" 'VALIDATE_TRIVY: false' \
	"cosmetic linting does not duplicate the Trivy scan"
assert_contains "${lint_workflow}" 'ENABLE_GITHUB_PULL_REQUEST_SUMMARY_COMMENT: false' \
	"Super-linter does not attempt noisy pull request comments"
assert_not_contains "${lint_workflow}" 'permission-contents: read' \
	"status-only app tokens cannot read repository contents"
assert_not_contains "${lint_workflow}" $'permissions:\n  contents: read\n  statuses: write' \
	"the workflow token cannot write commit statuses"

echo "== dependency update ownership =="
renovate_config="$(<"${REPO_ROOT}/.github/renovate.json5")"
taskfile="$(<"${REPO_ROOT}/Taskfile.yaml")"
renovate_package_rules() {
	awk -v needle="$1" -v skip="${2-}" '
		/^  packageRules: \[$/ { inside = 1; next }
		inside && /^  \],$/ { exit }
		inside && /^    \{$/ { rule = "" }
		inside { rule = rule $0 "\n" }
		inside && /^    \},$/ && index(rule, needle) && (skip == "" || rule !~ skip) { printf "%s", rule }
	' <<<"${renovate_config}"
}
assert_contains "${renovate_config}" ':enableVulnerabilityAlerts' \
	"Renovate owns vulnerability update pull requests"
assert_contains "${renovate_config}" "minimumReleaseAge: '14 days'" \
	"Renovate waits two weeks before proposing routine dependency updates"
assert_contains "${renovate_config}" "internalChecksFilter: 'strict'" \
	"Renovate suppresses updates that have not passed the release-age check"
assert_contains "${renovate_config}" 'ignoreTests: false' \
	"Renovate automerge waits for CI"
assert_contains "${renovate_config}" "rebaseWhen: 'auto'" \
	"Renovate retests automerge candidates against the current base"
assert_contains "${renovate_config}" 'platformAutomerge: true' \
	"GitHub merges Renovate PRs after the required acceptance gate"
assert_not_contains "${renovate_config}" ':disableRateLimiting' \
	"Renovate uses its default PR rate limits"
assert_contains "${renovate_config}" 'Never automerge majors or pin operations' \
	"high-risk update types require manual review"
broad_holds="$(renovate_package_rules 'automerge: false' 'match(UpdateTypes|DepNames|PackageNames):')"
if [[ -z "${broad_holds}" ]]; then
	pass "automerge holds name the update types or dependencies they cover"
else
	fail "automerge holds name the update types or dependencies they cover (found: ${broad_holds})"
fi
homebrew_rules="$(renovate_package_rules "'Homebrew/install'")"
assert_contains "${homebrew_rules}" 'automerge: false' \
	"the curl-piped Homebrew installer always waits for manual review"
assert_contains "${homebrew_rules}" 'minimumReleaseAge: null' \
	"the Homebrew installer skips the release-age hold its git-refs digest cannot pass"
renovate_group="$(renovate_package_rules "'renovatebot/pre-commit-hooks'")"
assert_contains "${renovate_group}" "groupName: 'renovate'" \
	"Renovate's pre-commit hook updates in the renovate group"
assert_contains "${renovate_group}" "'renovate/renovate'" \
	"Renovate's local runner image updates in the same group"
assert_contains "${renovate_group}" 'separateMinorPatch: false' \
	"Renovate self-updates do not split into patch and minor pull requests"
assert_not_contains "${renovate_config}" "minimumReleaseAge: '5 days'" \
	"no dependency class uses the short five-day cooldown"
assert_not_contains "${renovate_config}" 'ignoreTests: true' \
	"Renovate cannot bypass CI globally"
assert_not_contains "${renovate_config}" 'commitMessageSuffix' \
	"Renovate commits cannot request that CI be skipped"
assert_not_contains "${renovate_config}" '"onboarding"' \
	"repository config omits Renovate's global-only onboarding option"
assert_file_absent "${REPO_ROOT}/.github/workflows/renovate.yaml" \
	"Renovate SaaS is the only Renovate runner"
assert_file_absent "${REPO_ROOT}/.github/dependabot.yml" \
	"Dependabot version updates are not configured"
assert_contains "${renovate_config}" 'Track the pinned local Renovate image' \
	"Renovate tracks its own local runner image"
assert_contains "${taskfile}" 'RENOVATE_IMAGE: "renovate/renovate:' \
	"the local Renovate runner uses an explicit version"
assert_contains "${taskfile}" '@sha256:' \
	"the local Renovate runner is pinned to an immutable digest"
assert_not_contains "${taskfile}" 'renovate/renovate:slim' \
	"the local Renovate runner does not use the stale floating slim tag"

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
