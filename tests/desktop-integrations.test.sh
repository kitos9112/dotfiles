#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck source=tests/lib/contract-test.sh
source "${SCRIPT_DIR}/lib/contract-test.sh"

font_probe="${TMP_ROOT}/font.tmpl"
printf '{{ .terminalFont | toJson }}\n' >"${font_probe}"
font_data="$(render_template "${font_probe}")"
font_family="$(jq -r '.name' <<<"${font_data}")"
font_postscript="$(jq -r '.postScriptName' <<<"${font_data}")"
font_size="$(jq -r '.size' <<<"${font_data}")"

echo "== font source of truth =="
for key in name postScriptName size archive; do
	assert_contains "${font_data}" "\"${key}\"" "terminal font declares ${key}"
done

stray_font_refs="$(grep -rl --fixed-strings "${font_family}" "${SOURCE_DIR}" |
	grep -v '/\.chezmoidata/fonts\.yaml$' || true)"
if [[ -z "${stray_font_refs}" ]]; then
	pass "terminal templates do not hardcode the font family"
else
	fail "terminal templates hardcode the font family: ${stray_font_refs}"
fi

while IFS='|' read -r label path expected; do
	[[ -n "${label}" ]] || continue
	rendered="$(render_for darwin darwin desktop "${SOURCE_DIR}/${path}")"
	assert_contains "${rendered}" "${expected}" "${label} uses managed font data"
done <<EOF
Ghostty|private_dot_config/private_ghostty/config.tmpl|font-family = ${font_family}
Alacritty|private_dot_config/private_alacritty/alacritty.toml.tmpl|family = "${font_family}"
Zellij|private_dot_config/private_zellij/config.kdl.tmpl|font "${font_family}"
WezTerm|dot_wezterm.lua.tmpl|config.font_size = ${font_size}
Hyper|dot_hyper.js.tmpl|fontFamily: '${font_family}'
EOF

echo "== desktop-only sources =="
desktop_externals="$(render_for linux ubuntu desktop "${SOURCE_DIR}/.chezmoiexternal.yaml")"
server_externals="$(render_for linux ubuntu server "${SOURCE_DIR}/.chezmoiexternal.yaml")"
assert_contains "${desktop_externals}" 'nerd-fonts' "desktop fetches the Nerd Font"
assert_not_contains "${server_externals}" 'nerd-fonts' "server skips the Nerd Font"

desktop_ignore="$(render_for linux ubuntu desktop "${SOURCE_DIR}/.chezmoiignore")"
server_ignore="$(render_for linux ubuntu server "${SOURCE_DIR}/.chezmoiignore")"
assert_not_contains "${desktop_ignore}" '.config/ghostty' "desktop keeps Ghostty config"
assert_contains "${server_ignore}" '.config/ghostty' "server ignores Ghostty config"
assert_contains "${server_ignore}" '.config/iterm2' "server ignores iTerm2 profile"

echo "== macOS terminal integration =="
iterm_profile="$(render_for darwin darwin desktop \
	"${SOURCE_DIR}/private_dot_config/private_iterm2/dotfiles-profile.json.tmpl")"
if jq -e . >/dev/null <<<"${iterm_profile}"; then
	pass "iTerm2 dynamic profile renders valid JSON"
else
	fail "iTerm2 dynamic profile renders valid JSON"
fi
assert_contains "$(jq -r '.Profiles[0]["Normal Font"]' <<<"${iterm_profile}")" \
	"${font_postscript} ${font_size}" "iTerm2 uses the managed PostScript font"
assert_not_contains "$(jq -r '.Profiles[0].Guid' <<<"${iterm_profile}")" \
	"null" "iTerm2 profile has a stable Guid"

darwin_fonts="$(render_for darwin darwin desktop \
	"${SCRIPTS_DIR}/run_onchange_after_36-darwin-terminal-fonts.sh.tmpl")"
assert_valid_bash "${darwin_fonts}" "macOS font integration renders valid Bash"
assert_contains "${darwin_fonts}" 'DynamicProfiles' "macOS integration installs the iTerm2 profile"
assert_contains "${darwin_fonts}" 'log_manual_action' "Automation refusal becomes a manual action"

echo "== Ghostty command keybinds =="
ghostty_template="${SOURCE_DIR}/private_dot_config/private_ghostty/config.tmpl"
work_zsh_template="${SOURCE_DIR}/dot_oh-my-zsh-custom/private_work.zsh.tmpl"
work_command='{"key":"w","title":"Work thing","description":"d","command":"wk"}'
work_profile="{\"work_profile\":{\"zsh\":\"alias wk=\\\"echo work\\\"\\n\",\"ghosttyCommands\":[${work_command}]}}"

assert_not_contains "$(render_template "${ghostty_template}")" 'ctrl+alt+shift+super+w=' \
	"Ghostty has no work commands without a work profile"
ghostty_work="$(render_template "${ghostty_template}" "${work_profile}")"
assert_contains "${ghostty_work}" 'keybind = ctrl+alt+shift+super+w=text:wk\r' \
	"Ghostty binds work profile commands"
assert_contains "${ghostty_work}" 'command-palette-entry = title:"Work thing"' \
	"Ghostty lists work profile commands in the palette"
if render_template "${ghostty_template}" \
	"{\"ghosttyCommands\":[${work_command}],\"work_profile\":{\"ghosttyCommands\":[${work_command}]}}" \
	>/dev/null 2>&1; then
	fail "Ghostty rejects a key used by both the public and work lists"
else
	pass "Ghostty rejects a key used by both the public and work lists"
fi
ghostty_escaped="$(render_template "${ghostty_template}" \
	'{"ghosttyCommands":[{"key":"e","title":"Quote \"x\"","description":"a, b","command":"echo \"a\\\\b\""}]}')"
assert_contains "${ghostty_escaped}" 'text:echo \"a\\\\b\"\r' "Ghostty escapes commands as Zig string literals"
assert_contains "${ghostty_escaped}" 'action:"text:echo \\\"a\\\\\\\\b\\\"\\r"' \
	"Ghostty escapes palette actions for both parse passes"
for bad_key in q . ab; do
	if render_template "${ghostty_template}" \
		"{\"ghosttyCommands\":[{\"key\":\"${bad_key}\",\"title\":\"Bad\",\"description\":\"d\",\"command\":\"x\"}]}" \
		>/dev/null 2>&1; then
		fail "Ghostty rejects command key '${bad_key}'"
	else
		pass "Ghostty rejects command key '${bad_key}'"
	fi
done

echo "== private work profile =="
work_zsh_public="$(render_template "${work_zsh_template}")"
if [[ -z "${work_zsh_public}" ]]; then
	pass "work.zsh renders empty, so is not created, without a work profile"
else
	fail "work.zsh renders empty, so is not created, without a work profile"
fi
assert_contains "$(render_template "${work_zsh_template}" "${work_profile}")" 'alias wk="echo work"' \
	"work.zsh carries the work profile's zsh text"
if render_template "${work_zsh_template}" '{"work_profile":{"ghostty_commands":[]}}' >/dev/null 2>&1; then
	fail "work profile rejects unknown keys"
else
	pass "work profile rejects unknown keys"
fi

echo "== GNOME terminal integration =="
gnome_settings="$(render_for linux ubuntu desktop \
	"${SCRIPTS_DIR}/run_onchange_after_30-gnome-settings.sh.tmpl")"
assert_valid_bash "${gnome_settings}" "GNOME settings render valid Bash"
assert_contains "${gnome_settings}" "${font_family} ${font_size}" "GNOME uses the managed font"
assert_contains "${gnome_settings}" 'use-system-font' "GNOME disables system-font fallback"

export_source="$(<"${SOURCE_DIR}/private_dot_local/private_bin/executable_gnome-settings-export.tmpl")"
assert_contains "${export_source}" '.gnome.fontKeys' "GNOME export filters managed font keys"

doctor_source="$(<"${SOURCE_DIR}/private_dot_local/private_bin/executable_dotfiles-doctor.tmpl")"
assert_contains "${doctor_source}" 'fontWithNameSize' "doctor uses CoreText on macOS"
assert_contains "${doctor_source}" 'profiles:/list' "doctor checks GNOME terminal profiles"

finish_tests
