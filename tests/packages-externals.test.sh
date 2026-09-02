#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck source=tests/lib/contract-test.sh
source "${SCRIPT_DIR}/lib/contract-test.sh"

VERSIONS_FILE="${SOURCE_DIR}/.chezmoidata/versions.yaml"
EXTERNALS_FILE="${SOURCE_DIR}/.chezmoiexternal.yaml"

echo "== pinned external versions =="
assert_file_exists "${VERSIONS_FILE}" "release versions are checked in"

if [[ -f "${VERSIONS_FILE}" ]]; then
	versions="$(<"${VERSIONS_FILE}")"
	for pin in \
		'asdf: "0.20.0"' \
		'uv: "0.12.9"' \
		'fzf: "0.74.1"' \
		'nerd_fonts: "3.5.1"' \
		'retry: "1.0.2"' \
		'direnv: "2.37.1"' \
		'vscode: "1.135.0"' \
		'go: "1.27.1"'; do
		assert_contains "${versions}" "${pin}" "versions manifest contains ${pin}"
	done
fi

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
	assert_contains "${linux_render}" "asdf-v0.20.0-linux-amd64.tar.gz" "asdf URL uses its pin"
	assert_contains "${linux_render}" "go1.27.1.linux-amd64.tar.gz" "Go URL uses its pin"
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
