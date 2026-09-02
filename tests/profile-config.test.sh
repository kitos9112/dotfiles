#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck source=tests/lib/contract-test.sh
source "${SCRIPT_DIR}/lib/contract-test.sh"

echo "== profile resolution =="
profile_probe="${TMP_ROOT}/profile.tmpl"
printf '{{ includeTemplate "machine-class" . | trim }}\n' >"${profile_probe}"

assert_contains "$(DOTFILES_PROFILE=desktop render_template "${profile_probe}")" \
	"desktop" "desktop override selects the GUI profile"
assert_contains "$(DOTFILES_PROFILE=server render_template "${profile_probe}")" \
	"server" "server override selects the CLI profile"
if DOTFILES_PROFILE=invalid render_template "${profile_probe}" >/dev/null 2>&1; then
	fail "invalid machine profiles are rejected"
else
	pass "invalid machine profiles are rejected"
fi

echo "== privilege and Homebrew axes =="
root_probe="${TMP_ROOT}/root.tmpl"
brew_probe="${TMP_ROOT}/brew.tmpl"
printf '{{ includeTemplate "is-root" . | trim }}\n' >"${root_probe}"
printf '{{ includeTemplate "use-homebrew" . | trim }}\n' >"${brew_probe}"

assert_contains "$(DOTFILES_IS_ROOT=true render_template "${root_probe}")" \
	"true" "sudo can be enabled independently"
assert_contains "$(DOTFILES_IS_ROOT=false render_template "${root_probe}")" \
	"false" "sudo can be disabled independently"
assert_contains "$(DOTFILES_IS_ROOT=true DOTFILES_HOMEBREW=false render_template "${brew_probe}")" \
	"false" "sudo does not enable Homebrew"
assert_contains "$(DOTFILES_IS_ROOT=false DOTFILES_HOMEBREW=true render_template "${root_probe}")" \
	"false" "Homebrew does not grant sudo"

for script in \
	run_once_before_00-linux-prepare.sh.tmpl \
	run_once_before_01-linux-install-prereq.sh.tmpl \
	run_onchange_before_03-linux-apt-packages.sh.tmpl \
	run_onchange_after_25-install-ghostty.sh.tmpl; do
	assert_contains "$(<"${SCRIPTS_DIR}/${script}")" 'includeTemplate "is-root"' \
		"${script} uses shared sudo resolution"
done

echo "== config template =="
config_render="$(${CHEZMOI_BIN} execute-template --init --config "${EMPTY_CONFIG}" \
	--source "${SOURCE_DIR}" \
	--override-data '{"chezmoi":{"os":"darwin","arch":"arm64","osRelease":{"id":"darwin"}}}' \
	--file "${SOURCE_DIR}/.chezmoi.toml.tmpl")"
assert_contains "${config_render}" '[data]' "fresh init renders the data table"
assert_contains "${config_render}" 'machine_class = "desktop"' "macOS init records the desktop profile"
assert_contains "${config_render}" 'use_homebrew = true' "macOS init records Homebrew independently"

echo "== data manifests =="
for data_file in asdf.yaml fonts.yaml gnome.yaml locale.yaml packages.yaml versions.yaml; do
	assert_file_exists "${SOURCE_DIR}/.chezmoidata/${data_file}" ".chezmoidata/${data_file} exists"
done

if compgen -G "${SOURCE_DIR}/.chezmoidata*.tmpl" >/dev/null; then
	fail "templated .chezmoidata files are unsupported"
else
	pass "all chezmoi data files use supported literal names"
fi

finish_tests
