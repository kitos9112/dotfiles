#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck source=tests/lib/contract-test.sh
source "${SCRIPT_DIR}/lib/contract-test.sh"

VERSIONS_FILE="${SOURCE_DIR}/.chezmoidata/versions.yaml"
EXTERNALS_FILE="${SOURCE_DIR}/.chezmoiexternal.yaml"
ASDF_PLUGINS_FILE="${SOURCE_DIR}/.chezmoidata/asdf.yaml"
DARWIN_BREW_TEMPLATE="${SCRIPTS_DIR}/run_once_before_00-darwin-install-brew-packages.sh.tmpl"

echo "== package profile selection =="
apt_probe="${TMP_ROOT}/apt-packages.tmpl"
brew_probe="${TMP_ROOT}/brew-packages.tmpl"
dnf_probe="${TMP_ROOT}/dnf-packages.tmpl"
printf '{{ concat .packages.apt.common (index .packages.apt .machine_class) | uniq | sortAlpha | toJson }}\n' \
	>"${apt_probe}"
printf '{{ .packages.brew.common | uniq | sortAlpha | toJson }}\n' >"${brew_probe}"
printf '{{- if hasKey .packages "dnf" -}}{{- $packages := .packages.dnf.common -}}{{- $packages = concat $packages (index .packages.dnf .machine_class) -}}{{- $distribution := index .packages.dnf.distributions .chezmoi.osRelease.id -}}{{- $packages = concat $packages (index $distribution .machine_class) -}}{{ $packages | uniq | sortAlpha | toJson }}{{- else -}}[]{{- end -}}\n' \
	>"${dnf_probe}"
desktop_packages="$(render_template "${apt_probe}" '{"machine_class":"desktop"}')"
server_packages="$(render_template "${apt_probe}" '{"machine_class":"server"}')"
brew_packages="$(render_template "${brew_probe}")"
darwin_brew_script="$(render_for darwin darwin desktop "${DARWIN_BREW_TEMPLATE}")"
embedded_brew_packages="$(sed -nE 's/^[[:space:]]*brew "([^"]+)".*/\1/p' \
	<<<"${darwin_brew_script}")"
render_dnf_packages() {
	local distribution=$1 profile=$2 override
	override="$(jq -cn --arg distribution "${distribution}" --arg profile "${profile}" \
		'{chezmoi:{os:"linux",osRelease:{id:$distribution}},machine_class:$profile}')"
	render_template "${dnf_probe}" "${override}"
}

ubuntu_desktop_packages="${desktop_packages}"
ubuntu_server_packages="${server_packages}"
fedora_desktop_packages="$(render_dnf_packages fedora desktop)"
fedora_server_packages="$(render_dnf_packages fedora server)"
almalinux_desktop_packages="$(render_dnf_packages almalinux desktop)"
almalinux_server_packages="$(render_dnf_packages almalinux server)"
assert_contains "${desktop_packages}" '"1password"' "desktop installs the 1Password app"
assert_not_contains "${server_packages}" '"1password"' "server omits the 1Password app"
assert_contains "${server_packages}" '"1password-cli"' "server keeps the 1Password CLI"
assert_not_contains "${desktop_packages}" '"direnv"' "apt does not own direnv"
assert_contains "${ubuntu_desktop_packages}" '"alacritty"' "Ubuntu desktop installs Alacritty"
assert_contains "${ubuntu_desktop_packages}" '"wireshark"' "Ubuntu desktop installs Wireshark"
assert_not_contains "${ubuntu_server_packages}" '"alacritty"' "Ubuntu server omits Alacritty"
assert_not_contains "${ubuntu_server_packages}" '"wireshark"' "Ubuntu server omits Wireshark"
assert_contains "${fedora_desktop_packages}" '"alacritty"' "Fedora desktop installs Alacritty"
assert_contains "${fedora_desktop_packages}" '"wireshark"' "Fedora desktop installs Wireshark"
assert_not_contains "${fedora_server_packages}" '"alacritty"' "Fedora server omits Alacritty"
assert_not_contains "${fedora_server_packages}" '"wireshark"' "Fedora server omits Wireshark"
assert_not_contains "${almalinux_desktop_packages}" '"alacritty"' "AlmaLinux desktop omits Alacritty"
assert_contains "${almalinux_desktop_packages}" '"wireshark"' "AlmaLinux desktop installs Wireshark"
assert_not_contains "${almalinux_server_packages}" '"alacritty"' "AlmaLinux server omits Alacritty"
assert_not_contains "${almalinux_server_packages}" '"wireshark"' "AlmaLinux server omits Wireshark"
active_package_sources="$({
	jq -r '.[]' <<<"${desktop_packages}"
	jq -r '.[]' <<<"${server_packages}"
	jq -r '.[]' <<<"${brew_packages}"
	jq -r '.[]' <<<"${fedora_desktop_packages}"
	jq -r '.[]' <<<"${fedora_server_packages}"
	jq -r '.[]' <<<"${almalinux_desktop_packages}"
	jq -r '.[]' <<<"${almalinux_server_packages}"
	printf '%s\n' "${embedded_brew_packages}"
} | sort -u)"
for ownership in \
	'Go|go golang golang-go' \
	'kubectl|kubectl kubernetes-cli' \
	'fzf|fzf' \
	'direnv|direnv'; do
	tool="${ownership%%|*}"
	provider_names="${ownership#*|}"
	duplicate=false
	for package in ${provider_names}; do
		if grep -Fxq -- "${package}" <<<"${active_package_sources}"; then
			duplicate=true
		fi
	done
	if [[ "${duplicate}" == false ]]; then
		pass "active package sources do not own ${tool}"
	else
		fail "active package sources do not own ${tool}"
	fi
done

echo "== asdf tool ownership =="
assert_file_exists "${ASDF_PLUGINS_FILE}" "asdf plugin manifest is checked in"
asdf_plugins_probe="${TMP_ROOT}/asdf-plugins.tmpl"
printf '{{ .asdf_plugins | toJson }}\n' >"${asdf_plugins_probe}"
asdf_plugins="$(render_template "${asdf_plugins_probe}")"
for plugin in \
	'fzf|https://github.com/kompiro/asdf-fzf.git' \
	'direnv|https://github.com/asdf-community/asdf-direnv.git'; do
	plugin_name="${plugin%%|*}"
	plugin_url="${plugin#*|}"
	if jq -e --arg name "${plugin_name}" --arg url "${plugin_url}" \
		'.[] | select(.name == $name and .url == $url)' >/dev/null <<<"${asdf_plugins}"; then
		pass "asdf registers ${plugin_name} with its required plugin URL"
	else
		fail "asdf registers ${plugin_name} with its required plugin URL"
	fi
done

tool_versions="$(render_template "${SOURCE_DIR}/dot_tool-versions.tmpl")"
for pin in \
	'kubectl 1.37.0' \
	'golang 1.27.1' \
	'fzf 0.74.3' \
	'direnv 2.37.1'; do
	assert_contains "${tool_versions}" "${pin}" ".tool-versions pins ${pin} through asdf"
done

echo "== pinned external versions =="
assert_file_exists "${VERSIONS_FILE}" "release versions are checked in"

versions_probe="${TMP_ROOT}/versions.tmpl"
printf '{{ .versions | toJson }}\n' >"${versions_probe}"
versions_json="$(render_template "${versions_probe}")"
for dependency in asdf uv nerd_fonts retry vscode; do
	if version="$(jq -er --arg dependency "${dependency}" \
		'.[$dependency] | strings | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+([+.~-][0-9A-Za-z.-]+)?$"))' \
		<<<"${versions_json}")"; then
		pass "${dependency} has a checked-in release version (${version})"
	else
		fail "${dependency} has a checked-in semantic version"
	fi
done

asdf_version="$(jq -r '.asdf' <<<"${versions_json}")"

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
	assert_not_contains "${linux_render}" '".fzf":' "legacy fzf checkout is not managed"
	assert_contains "${linux_render}" "asdf-v${asdf_version}-linux-amd64.tar.gz" "asdf URL uses its pin"
	for external in '.go' '.local/bin/fzf' '.local/bin/direnv'; do
		assert_not_contains "${linux_render}" "\"${external}\":" "externals do not own ${external}"
	done
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
