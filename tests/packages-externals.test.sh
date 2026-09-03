#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck source=tests/lib/contract-test.sh
source "${SCRIPT_DIR}/lib/contract-test.sh"

VERSIONS_FILE="${SOURCE_DIR}/.chezmoidata/versions.yaml"
EXTERNALS_FILE="${SOURCE_DIR}/.chezmoiexternal.yaml"

echo "== package profile selection =="
package_probe="${TMP_ROOT}/packages.tmpl"
printf '{{ concat .packages.apt.common (index .packages.apt .machine_class) | uniq | sortAlpha | toJson }}\n' \
	>"${package_probe}"
desktop_packages="$(render_template "${package_probe}" '{"machine_class":"desktop"}')"
server_packages="$(render_template "${package_probe}" '{"machine_class":"server"}')"
assert_contains "${desktop_packages}" '"1password"' "desktop installs the 1Password app"
assert_not_contains "${server_packages}" '"1password"' "server omits the 1Password app"
assert_contains "${server_packages}" '"1password-cli"' "server keeps the 1Password CLI"

echo "== pinned external versions =="
assert_file_exists "${VERSIONS_FILE}" "release versions are checked in"

versions_probe="${TMP_ROOT}/versions.tmpl"
printf '{{ .versions | toJson }}\n' >"${versions_probe}"
versions_json="$(render_template "${versions_probe}")"
for dependency in asdf uv fzf nerd_fonts retry direnv vscode go; do
	if version="$(jq -er --arg dependency "${dependency}" \
		'.[$dependency] | strings | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+([+.~-][0-9A-Za-z.-]+)?$"))' \
		<<<"${versions_json}")"; then
		pass "${dependency} has a checked-in release version (${version})"
	else
		fail "${dependency} has a checked-in semantic version"
	fi
done

asdf_version="$(jq -r '.asdf' <<<"${versions_json}")"
fzf_version="$(jq -r '.fzf' <<<"${versions_json}")"
go_version="$(jq -r '.go' <<<"${versions_json}")"

echo "== offline external rendering =="
external_source="$(<"${EXTERNALS_FILE}")"
for forbidden in \
	'get-github-latest-version' \
	'get-github-head-revision' \
	'versions-and-revisions-cache' \
	'git ls-remote' \
	'releases/latest'; do
	assert_not_contains "${external_source}" "${forbidden}" "externals do not use ${forbidden}"
done

linux_override='{"chezmoi":{"os":"linux","arch":"amd64"},"machine_class":"server","use_homebrew":false}'
mac_override='{"chezmoi":{"os":"darwin","arch":"arm64"},"machine_class":"desktop","use_homebrew":true}'

if linux_render="$(PATH=/usr/bin:/bin DOTFILES_PROFILE=server DOTFILES_HOMEBREW=false render_template "${EXTERNALS_FILE}" "${linux_override}")"; then
	pass "non-Homebrew externals render without network tools"
	assert_contains "${linux_render}" '".local/bin/fzf":' "portable fzf is a managed external"
	assert_not_contains "${linux_render}" '".fzf":' "legacy fzf checkout is not managed"
	assert_contains "${linux_render}" "asdf-v${asdf_version}-linux-amd64.tar.gz" "asdf URL uses its pin"
	assert_contains "${linux_render}" "fzf-${fzf_version}-linux_amd64.tar.gz" "fzf URL uses its pin"
	assert_contains "${linux_render}" "go${go_version}.linux-amd64.tar.gz" "Go URL uses its pin"
	assert_contains "${linux_render}" "direnv.linux-amd64" "portable direnv is rendered"
else
	fail "non-Homebrew externals render without network tools"
fi

if mac_render="$(PATH=/usr/bin:/bin DOTFILES_PROFILE=desktop DOTFILES_HOMEBREW=true render_template "${EXTERNALS_FILE}" "${mac_override}")"; then
	pass "Homebrew externals render without network tools"
	assert_not_contains "${mac_render}" 'apps/vscode' "Homebrew profile skips portable VS Code"
	assert_contains "${mac_render}" 'FiraMono.tar.xz' "desktop profile includes terminal font"
else
	fail "Homebrew externals render without network tools"
fi

finish_tests
