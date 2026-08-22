#!/usr/bin/env bash

# Contract tests for the desktop/server bootstrap profiles.
#
# These run on any OS: they exercise template rendering and the source tree's
# invariants rather than installing anything. The Docker smoke tests cover the
# actual apply.

set -euo pipefail

SCRIPT_DIR="$(
	cd -- "$(dirname "$0")" >/dev/null 2>&1
	pwd -P
)"
REPO_ROOT="$(
	cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1
	pwd -P
)"
SOURCE_DIR="${REPO_ROOT}/home"
SCRIPTS_DIR="${SOURCE_DIR}/.chezmoiscripts"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-profiles.XXXXXX")"
trap 'rm -rf "${TMP_ROOT}"' EXIT HUP INT TERM

# Render .chezmoi.toml.tmpl into a throwaway config rather than reading the
# developer's own ~/.config/chezmoi/chezmoi.toml. Relying on the real one made
# these tests pass locally and fail in CI: keys defined in the config template
# resolved on an already-initialised machine and were simply absent on a fresh
# checkout, so apply-time breakage only ever surfaced in CI. Deriving the config
# from the template keeps this fixture from drifting away from it.
#
# `execute-template --init` writes exactly where it is told. `chezmoi init` does
# not: it resolves its own config path through XDG_CONFIG_HOME, which the GitHub
# runners set, so overriding HOME alone put the config outside the sandbox and
# left this suite unable to find it. The empty --config keeps any answers already
# persisted on this machine from leaking into the render.
EMPTY_CHEZMOI_CONFIG="${TMP_ROOT}/empty-chezmoi.toml"
TEST_CHEZMOI_CONFIG="${TMP_ROOT}/chezmoi.toml"
: > "${EMPTY_CHEZMOI_CONFIG}"
chezmoi execute-template --init --config "${EMPTY_CHEZMOI_CONFIG}" \
	--source "${SOURCE_DIR}" \
	< "${SOURCE_DIR}/.chezmoi.toml.tmpl" > "${TEST_CHEZMOI_CONFIG}"

grep -q '^\[data\]' "${TEST_CHEZMOI_CONFIG}" || {
	printf 'rendering .chezmoi.toml.tmpl produced no [data] block; got:\n' >&2
	cat "${TEST_CHEZMOI_CONFIG}" >&2
	exit 1
}

failures=0

function pass() {
	printf '  ok   %s\n' "$*"
}

function fail() {
	printf '  FAIL %s\n' "$*" >&2
	failures=$((failures + 1))
}

function assert_contains() {
	local haystack="$1" needle="$2" label="$3"
	if [[ "${haystack}" == *"${needle}"* ]]; then
		pass "${label}"
	else
		fail "${label} (expected to find: ${needle})"
	fi
}

function assert_not_contains() {
	local haystack="$1" needle="$2" label="$3"
	if [[ "${haystack}" != *"${needle}"* ]]; then
		pass "${label}"
	else
		fail "${label} (unexpectedly found: ${needle})"
	fi
}

function render() {
	# Render a source-tree template with chezmoi's real data.
	local file="$1"
	shift
	chezmoi execute-template --config "${TEST_CHEZMOI_CONFIG}" \
		--source "${SOURCE_DIR}" "$@" < "${file}"
}

echo "== machine-class resolution =="
class_template="${SOURCE_DIR}/.chezmoitemplates/machine-class"
probe="${TMP_ROOT}/probe.tmpl"
printf '{{ includeTemplate "machine-class" . | trim }}\n' > "${probe}"

[[ -f "${class_template}" ]] || fail "missing .chezmoitemplates/machine-class"

resolved="$(DOTFILES_PROFILE=desktop render "${probe}" | tr -d '\n')"
if [[ "${resolved}" == "desktop" ]]; then
	pass "DOTFILES_PROFILE=desktop resolves to desktop"
else
	fail "DOTFILES_PROFILE=desktop resolved to '${resolved}'"
fi

resolved="$(DOTFILES_PROFILE=server render "${probe}" | tr -d '\n')"
if [[ "${resolved}" == "server" ]]; then
	pass "DOTFILES_PROFILE=server resolves to server"
else
	fail "DOTFILES_PROFILE=server resolved to '${resolved}'"
fi

# An invalid profile must fail loudly instead of silently picking a default,
# which would install the wrong package set.
if DOTFILES_PROFILE=nonsense render "${probe}" >/dev/null 2>&1; then
	fail "an invalid DOTFILES_PROFILE was accepted"
else
	pass "an invalid DOTFILES_PROFILE is rejected"
fi

echo "== sudo (is_root) resolution =="
root_probe="${TMP_ROOT}/is-root.tmpl"
printf '{{ includeTemplate "is-root" . | trim }}\n' > "${root_probe}"

resolved="$(DOTFILES_IS_ROOT=true render "${root_probe}" | tr -d '\n')"
if [[ "${resolved}" == "true" ]]; then
	pass "DOTFILES_IS_ROOT=true grants sudo"
else
	fail "DOTFILES_IS_ROOT=true resolved to '${resolved}'"
fi

resolved="$(DOTFILES_IS_ROOT=false render "${root_probe}" | tr -d '\n')"
if [[ "${resolved}" == "false" ]]; then
	pass "DOTFILES_IS_ROOT=false withholds sudo"
else
	fail "DOTFILES_IS_ROOT=false resolved to '${resolved}'"
fi

if DOTFILES_IS_ROOT=yes render "${root_probe}" >/dev/null 2>&1; then
	fail "an invalid DOTFILES_IS_ROOT was accepted"
else
	pass "an invalid DOTFILES_IS_ROOT is rejected"
fi

# The regression this guards: a work machine has is_root=false persisted, and
# chezmoi only re-renders the config template on `init`. Scripts must therefore
# resolve sudo through the shared template, or DOTFILES_IS_ROOT=true is ignored
# by a plain `chezmoi apply` and no apt packages ever install.
# The Homebrew script is deliberately absent: it is gated on use-homebrew, not on
# sudo, and is covered by the Homebrew independence checks above.
for sudo_script in \
	run_once_before_00-linux-prepare.sh.tmpl \
	run_once_before_01-linux-install-prereq.sh.tmpl \
	run_onchange_before_03-linux-apt-packages.sh.tmpl \
	run_onchange_after_25-install-ghostty.sh.tmpl; do

	if grep -q 'includeTemplate "is-root"' "${SCRIPTS_DIR}/${sudo_script}"; then
		pass "${sudo_script} resolves sudo through the shared template"
	else
		fail "${sudo_script} reads .is_root directly, so DOTFILES_IS_ROOT is ignored on apply"
	fi
done

# A work machine with sudo must actually get the apt batch. The OS guard is
# stripped so this is deterministic on any host.
work_apt_body="${TMP_ROOT}/apt-sudo.tmpl"
sed '1d;$d' "${SCRIPTS_DIR}/run_onchange_before_03-linux-apt-packages.sh.tmpl" > "${work_apt_body}"
assert_contains "$(DOTFILES_IS_ROOT=true DOTFILES_IS_WORK=true render "${work_apt_body}")" \
	"apt-get install" "a work machine with sudo still installs apt packages"

echo "== Homebrew is independent of sudo =="
brew_probe="${TMP_ROOT}/use-homebrew.tmpl"
printf '{{ includeTemplate "use-homebrew" . | trim }}\n' > "${brew_probe}"

resolved="$(DOTFILES_HOMEBREW=true render "${brew_probe}" | tr -d '\n')"
if [[ "${resolved}" == "true" ]]; then
	pass "DOTFILES_HOMEBREW=true enables Homebrew"
else
	fail "DOTFILES_HOMEBREW=true resolved to '${resolved}'"
fi

if DOTFILES_HOMEBREW=maybe render "${brew_probe}" >/dev/null 2>&1; then
	fail "an invalid DOTFILES_HOMEBREW was accepted"
else
	pass "an invalid DOTFILES_HOMEBREW is rejected"
fi

# The point of the split: sudo must not drag Homebrew in with it.
resolved="$(DOTFILES_IS_ROOT=true DOTFILES_HOMEBREW=false render "${brew_probe}" | tr -d '\n')"
if [[ "${resolved}" == "false" ]]; then
	pass "granting sudo does not enable Homebrew"
else
	fail "sudo forced Homebrew on (resolved '${resolved}')"
fi

resolved="$(DOTFILES_IS_ROOT=false DOTFILES_HOMEBREW=true render "${root_probe}" | tr -d '\n')"
if [[ "${resolved}" == "false" ]]; then
	pass "enabling Homebrew does not grant sudo"
else
	fail "Homebrew forced sudo on (resolved '${resolved}')"
fi

# Every Homebrew consumer must key off the new flag, or the axes silently recouple.
for brew_consumer in \
	".chezmoiscripts/run_onchange_before_04-linux-brew-packages.zsh.tmpl" \
	".chezmoiscripts/run_after_099-update-asdf.sh.tmpl" \
	".chezmoiscripts/run_after_900-finalizers.zsh.tmpl" \
	"dot_oh-my-zsh-custom/env.zsh.tmpl" \
	".chezmoiexternal.yaml"; do

	if grep -q 'includeTemplate "use-homebrew"' "${SOURCE_DIR}/${brew_consumer}"; then
		pass "$(basename "${brew_consumer}") gates Homebrew on use-homebrew"
	else
		fail "$(basename "${brew_consumer}") still ties Homebrew to sudo"
	fi
done

# A sudo-capable machine that opted out of brew still needs the portable tooling.
assert_contains "$(DOTFILES_IS_ROOT=true DOTFILES_HOMEBREW=false render "${SOURCE_DIR}/.chezmoiexternal.yaml")" \
	"apps/vscode" "sudo without Homebrew still fetches portable tooling"
assert_not_contains "$(DOTFILES_HOMEBREW=true render "${SOURCE_DIR}/.chezmoiexternal.yaml")" \
	"apps/vscode" "Homebrew machines skip the portable tooling"

echo "== data manifests =="
for data_file in packages.yaml fonts.yaml gnome.yaml; do
	if [[ -f "${SOURCE_DIR}/.chezmoidata/${data_file}" ]]; then
		pass ".chezmoidata/${data_file} exists"
	else
		fail ".chezmoidata/${data_file} is missing"
	fi
done

# chezmoi only loads literal .chezmoidata.$FORMAT files, so a templated data file
# would be silently ignored and its values would vanish from the template data.
if compgen -G "${SOURCE_DIR}/.chezmoidata*.tmpl" >/dev/null; then
	fail "a templated .chezmoidata file exists; chezmoi will not load it"
else
	pass "no templated .chezmoidata files"
fi

data_keys="$(chezmoi data --config "${TEST_CHEZMOI_CONFIG}" --source "${SOURCE_DIR}" --format json)"
for key in packages terminalFont gnome fontsDir locale; do
	assert_contains "${data_keys}" "\"${key}\"" "template data exposes ${key}"
done

echo "== apt package selection =="
apt_script="${SCRIPTS_DIR}/run_onchange_before_03-linux-apt-packages.sh.tmpl"
# The OS guard is stripped so the body can be inspected from any host.
body="${TMP_ROOT}/apt.tmpl"
sed '1d;$d' "${apt_script}" > "${body}"

desktop_apt="$(DOTFILES_PROFILE=desktop render "${body}")"
server_apt="$(DOTFILES_PROFILE=server render "${body}")"

assert_contains "${desktop_apt}" '"1password"' "desktop installs the 1Password app"
assert_not_contains "${server_apt}" '"1password"' "server omits the 1Password app"
assert_contains "${server_apt}" '"1password-cli"' "server installs the 1Password CLI"
assert_contains "${desktop_apt}" "machine_class: desktop" "apt script records the desktop profile"
assert_contains "${server_apt}" "machine_class: server" "apt script records the server profile"

echo "== fonts are desktop-only =="
externals="${SOURCE_DIR}/.chezmoiexternal.yaml"
assert_contains "$(DOTFILES_PROFILE=desktop render "${externals}")" "nerd-fonts" \
	"desktop fetches the Nerd Font"
assert_not_contains "$(DOTFILES_PROFILE=server render "${externals}")" "nerd-fonts" \
	"server skips the Nerd Font download"

echo "== the terminal font has a single source of truth =="
# Switching Nerd Font has to be a one-line edit to .chezmoidata/fonts.yaml. A
# terminal that hardcodes the family instead keeps rendering the old font --
# or tofu, once the old font is no longer installed -- and nobody finds out
# until they happen to open that particular terminal.
font_data="$(chezmoi data --config "${TEST_CHEZMOI_CONFIG}" --source "${SOURCE_DIR}" --format json |
	jq -c '.terminalFont')"

for font_key in name postScriptName size archive; do
	assert_contains "${font_data}" "\"${font_key}\"" "terminalFont declares ${font_key}"
done

font_family="$(printf '%s' "${font_data}" | jq -r '.name')"
font_postscript="$(printf '%s' "${font_data}" | jq -r '.postScriptName')"
font_size="$(printf '%s' "${font_data}" | jq -r '.size')"

# The family and the PostScript name are independent facts about the font file:
# "FiraMono Nerd Font" has the PostScript name "FiraMonoNF-Regular", which no
# amount of string munging derives from the family. File-configured terminals
# want the family, the macOS plist terminals want the PostScript name, so both
# have to be declared rather than computed.
if [[ -n "${font_postscript}" && "${font_postscript}" != "null" &&
	"${font_postscript}" != "${font_family}" ]]; then
	pass "the PostScript name is declared separately from the family"
else
	fail "postScriptName is missing or just a copy of the family ('${font_postscript}')"
fi

# The manifest is the only place allowed to name the font.
stray_font_refs="$(grep -rl --fixed-strings "${font_family}" "${SOURCE_DIR}" |
	grep -v '/\.chezmoidata/fonts\.yaml$' || true)"
if [[ -z "${stray_font_refs}" ]]; then
	pass "no source file hardcodes the font family"
else
	fail "these hardcode the font family instead of reading fonts.yaml: $(printf '%s' "${stray_font_refs}" | tr '\n' ' ')"
fi

# Every terminal that renders glyphs must resolve both the family and the size
# from the manifest. The expectations are exact strings rather than a bare
# search for "12", which would pass by accident against any unrelated number.
# Zellij is family-only: its font key configures the browser-based web client,
# which takes no size.
while IFS='|' read -r label config_path expect_font expect_size; do
	[[ -n "${label}" ]] || continue
	path="${SOURCE_DIR}/${config_path}"
	if [[ ! -f "${path}" ]]; then
		fail "${label}: expected a template at ${config_path}"
		continue
	fi
	if ! rendered="$(DOTFILES_PROFILE=desktop render "${path}" 2>&1)"; then
		fail "${label} failed to render: ${rendered}"
		continue
	fi
	assert_contains "${rendered}" "${expect_font}" "${label} renders the managed font family"
	[[ -n "${expect_size}" ]] &&
		assert_contains "${rendered}" "${expect_size}" "${label} renders the managed font size"
done <<-EOF
	Ghostty|private_dot_config/private_ghostty/config.tmpl|font-family = ${font_family}|font-size = ${font_size}
	Alacritty|private_dot_config/private_alacritty/alacritty.toml.tmpl|family = "${font_family}"|size = ${font_size}
	Zellij|private_dot_config/private_zellij/config.kdl.tmpl|font "${font_family}"|
	WezTerm|dot_wezterm.lua.tmpl|wezterm.font '${font_family}'|config.font_size = ${font_size}
	Hyper|dot_hyper.js.tmpl|fontFamily: '${font_family}'|fontSize: ${font_size}
EOF

# iTerm2 reads a dynamic profile: a plain JSON file it hot-reloads, which keeps
# this out of plist-editing territory entirely.
iterm_profile="${SOURCE_DIR}/private_dot_config/private_iterm2/dotfiles-profile.json.tmpl"
if [[ ! -f "${iterm_profile}" ]]; then
	fail "the iTerm2 dynamic profile template is missing"
elif ! iterm_rendered="$(render "${iterm_profile}" 2>&1)"; then
	fail "the iTerm2 dynamic profile failed to render: ${iterm_rendered}"
elif ! printf '%s' "${iterm_rendered}" | jq -e . > /dev/null 2>&1; then
	fail "the iTerm2 dynamic profile does not render valid JSON"
else
	pass "the iTerm2 dynamic profile renders valid JSON"
	assert_contains "$(printf '%s' "${iterm_rendered}" | jq -r '.Profiles[0]["Normal Font"]')" \
		"${font_postscript} ${font_size}" \
		"the iTerm2 profile sets the managed PostScript name and size"
	# iTerm2 keys a dynamic profile on its Guid. Without a stable one it adds a
	# fresh duplicate profile on every apply.
	if [[ "$(printf '%s' "${iterm_rendered}" | jq -r '.Profiles[0].Guid')" != "null" ]]; then
		pass "the iTerm2 profile pins a stable Guid"
	else
		fail "the iTerm2 profile has no Guid, so every apply would duplicate it"
	fi
fi

echo "== the macOS terminal font script =="
darwin_fonts="${SCRIPTS_DIR}/run_onchange_after_36-darwin-terminal-fonts.sh.tmpl"
if [[ ! -f "${darwin_fonts}" ]]; then
	fail "run_onchange_after_36-darwin-terminal-fonts.sh.tmpl is missing"
else
	# Gated on darwin, so it renders to nothing on the Linux CI runners. Keeping
	# the guard to exactly one first and one last line leaves the body
	# inspectable from any host -- the same trick the apt-package test uses.
	assert_contains "$(head -1 "${darwin_fonts}")" 'eq .chezmoi.os "darwin"' \
		"the macOS font script is gated on darwin"

	darwin_body="${TMP_ROOT}/darwin-fonts.tmpl"
	sed '1d;$d' "${darwin_fonts}" > "${darwin_body}"
	if ! darwin_rendered="$(DOTFILES_PROFILE=desktop render "${darwin_body}" 2>&1)"; then
		fail "the macOS font script body failed to render: ${darwin_rendered}"
	else
		printf '%s\n' "${darwin_rendered}" > "${TMP_ROOT}/darwin-fonts.sh"
		if bash -n "${TMP_ROOT}/darwin-fonts.sh" 2>/dev/null; then
			pass "the macOS font script renders valid bash"
		else
			fail "the macOS font script renders invalid bash"
		fi

		assert_contains "${darwin_rendered}" "${font_postscript}" \
			"the macOS script applies the managed PostScript name"
		assert_contains "${darwin_rendered}" "DynamicProfiles" \
			"the macOS script installs the iTerm2 dynamic profile"

		# These dotfiles do not install either app on macOS, so a Mac missing one
		# must skip it rather than abort the whole apply.
		assert_contains "${darwin_rendered}" "/Applications/iTerm.app" \
			"the macOS script skips iTerm2 when it is not installed"
		# Driving Terminal.app over AppleScript needs one-time Automation
		# consent, which cannot be granted on an unattended apply. A refusal has
		# to become a logged manual step, not a failed bootstrap.
		assert_contains "${darwin_rendered}" "log_manual_action" \
			"the macOS script degrades to a manual step instead of failing"
	fi
fi

echo "== dotfiles-doctor verifies fonts on macOS =="
# fc-list ships with fontconfig, which stock macOS does not have. The darwin
# branch therefore hit the "fontconfig not installed" skip on every single Mac
# and never once verified the font it exists to guard.
doctor_source="$(cat "${SOURCE_DIR}/private_dot_local/private_bin/executable_dotfiles-doctor.tmpl")"
assert_contains "${doctor_source}" "fontWithNameSize" \
	"the doctor asks CoreText for the font on macOS instead of fontconfig"
assert_contains "${doctor_source}" "TERMINAL_FONT_POSTSCRIPT" \
	"the doctor checks the PostScript name the plist terminals resolve"
# Drift detection is the whole point: the check has to compare what the apps are
# actually configured with, not merely that the font is installed.
assert_contains "${doctor_source}" "Default Window Settings" \
	"the doctor inspects Terminal.app's configured font"
assert_contains "${doctor_source}" "DynamicProfiles" \
	"the doctor inspects the iTerm2 dynamic profile"

echo "== the GNOME Terminal font comes from fonts.yaml =="
# GNOME Terminal keeps its font in dconf rather than in a file this repo renders,
# which makes it the Linux counterpart of Terminal.app. Left alone, the next
# `gnome-settings-export` would bake the font into terminal-legacy.ini as a
# literal and it would drift from .chezmoidata/fonts.yaml for good -- inside a
# file that looks like inert exported state.
gnome_data="$(chezmoi data --config "${TEST_CHEZMOI_CONFIG}" --source "${SOURCE_DIR}" --format json |
	jq -c '.gnome.fontKeys')"
for gnome_font_key in font monospace-font-name use-system-font; do
	assert_contains "${gnome_data}" "\"${gnome_font_key}\"" \
		"gnome.fontKeys claims ${gnome_font_key}"
done

# The export helper has to strip them, or they are committed on the next export.
export_helper="${SOURCE_DIR}/private_dot_local/private_bin/executable_gnome-settings-export.tmpl"
assert_contains "$(cat "${export_helper}")" ".gnome.fontKeys" \
	"the export helper strips the font keys from dconf dumps"
rendered_export="$(render "${export_helper}")"
for gnome_font_key in font monospace-font-name; do
	assert_contains "${rendered_export}" "\"${gnome_font_key}\"" \
		"the rendered export helper filters ${gnome_font_key}"
done

# ...and the import script has to put the font back, from fonts.yaml.
gnome_script="${SCRIPTS_DIR}/run_onchange_after_30-gnome-settings.sh.tmpl"
assert_contains "$(head -1 "${gnome_script}")" 'eq .chezmoi.os "linux"' \
	"the GNOME script keeps its guard on one line so the body stays testable"

gnome_body="${TMP_ROOT}/gnome-settings.tmpl"
sed '1d;$d' "${gnome_script}" > "${gnome_body}"
if ! gnome_rendered="$(DOTFILES_PROFILE=desktop render "${gnome_body}" 2>&1)"; then
	fail "the GNOME script body failed to render: ${gnome_rendered}"
else
	printf '%s\n' "${gnome_rendered}" > "${TMP_ROOT}/gnome-settings.sh"
	if bash -n "${TMP_ROOT}/gnome-settings.sh" 2>/dev/null; then
		pass "the GNOME script renders valid bash"
	else
		fail "the GNOME script renders invalid bash"
	fi

	assert_contains "${gnome_rendered}" "${font_family} ${font_size}" \
		"the GNOME script writes the managed font family and size"
	assert_contains "${gnome_rendered}" "/org/gnome/terminal/legacy/profiles:" \
		"the GNOME script targets the terminal profile subtree"
	# The path is assembled from PROFILE_ROOT, so match the shell source rather
	# than a fully expanded dconf path.
	assert_contains "${gnome_rendered}" 'PROFILE_ROOT}/list' \
		"the GNOME script applies the font to every profile in the list"
	# A profile with use-system-font left true ignores its own font key, so
	# stripping the font from the dump would silently fall back to the system font.
	assert_contains "${gnome_rendered}" "use-system-font" \
		"the GNOME script stops profiles falling back to the system font"

	# Execute the profile handling against a fake dconf. dconf reports a GVariant
	# list and bash cannot parse GVariant, so the reduction to bare UUIDs is the
	# part most likely to break -- and without a stub it would only ever run on a
	# GNOME desktop, never in CI or on a Mac. Same approach as the fake brew below.
	gnome_stub_bin="${TMP_ROOT}/gnome-stub-bin"
	mkdir -p "${gnome_stub_bin}"
	cat > "${gnome_stub_bin}/dconf" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "read /org/gnome/terminal/legacy/profiles:/list")
    echo "['aaaa1111-0000-0000-0000-000000000001', 'bbbb2222-0000-0000-0000-000000000002']" ;;
  "write "*) echo "WROTE $2 = $3" ;;
  *) exit 0 ;;
esac
STUB
	chmod 755 "${gnome_stub_bin}/dconf"

	gnome_writes="$(PATH="${gnome_stub_bin}:${PATH}" DBUS_SESSION_BUS_ADDRESS=unix:path=/fake \
		bash "${TMP_ROOT}/gnome-settings.sh" 2>&1 || true)"

	for gnome_profile in aaaa1111-0000-0000-0000-000000000001 bbbb2222-0000-0000-0000-000000000002; do
		assert_contains "${gnome_writes}" \
			"WROTE /org/gnome/terminal/legacy/profiles:/:${gnome_profile}/font = '${font_family} ${font_size}'" \
			"the managed font reaches profile ${gnome_profile%%-*}"
		assert_contains "${gnome_writes}" \
			"WROTE /org/gnome/terminal/legacy/profiles:/:${gnome_profile}/use-system-font = false" \
			"use-system-font is disabled on profile ${gnome_profile%%-*}"
	done

	# A machine that has never opened GNOME Terminal must skip cleanly rather than
	# write the font to a malformed profile path built from an empty UUID.
	cat > "${gnome_stub_bin}/dconf" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  read) echo "" ;;
  write) echo "WROTE $2 = $3" ;;
  *) exit 0 ;;
esac
STUB
	chmod 755 "${gnome_stub_bin}/dconf"
	gnome_writes="$(PATH="${gnome_stub_bin}:${PATH}" DBUS_SESSION_BUS_ADDRESS=unix:path=/fake \
		bash "${TMP_ROOT}/gnome-settings.sh" 2>&1 || true)"
	assert_not_contains "${gnome_writes}" "WROTE" \
		"a machine with no GNOME Terminal profiles writes nothing"
fi

# Same drift question as macOS, asked of dconf: is GNOME Terminal actually
# configured with the managed font, not merely able to render it?
assert_contains "${doctor_source}" "profiles:/list" \
	"the doctor checks the GNOME Terminal font on Linux"
# Checking only the font string would report a false green: a profile inheriting
# the system font ignores its own font key, so the right value there still
# renders the wrong font.
assert_contains "${doctor_source}" 'gnome_system_font' \
	"the doctor also checks use-system-font, not just the font string"

echo "== ghostty config is desktop-only =="
# The install script is profile-gated, so the config must be too: a server has no
# terminal emulator to read it.
ignore_file="${SOURCE_DIR}/.chezmoiignore"
assert_contains "$(DOTFILES_PROFILE=server render "${ignore_file}")" ".config/ghostty" \
	"server ignores the Ghostty config"
assert_not_contains "$(DOTFILES_PROFILE=desktop render "${ignore_file}")" ".config/ghostty" \
	"desktop keeps the Ghostty config"

# The iTerm2 dynamic profile is staged in ~/.config for the macOS script to copy,
# so it is dead weight on a server and on every Linux desktop.
assert_contains "$(DOTFILES_PROFILE=server render "${ignore_file}")" ".config/iterm2" \
	"server ignores the iTerm2 profile"

echo "== rendered scripts are valid shell =="
for script in \
	run_onchange_before_03-linux-apt-packages.sh.tmpl \
	run_onchange_before_04-linux-brew-packages.zsh.tmpl \
	run_once_after_20-1password-signin.sh.tmpl \
	run_onchange_after_25-install-ghostty.sh.tmpl \
	run_onchange_after_30-gnome-settings.sh.tmpl \
	run_onchange_after_35-refresh-font-cache.sh.tmpl \
	run_onchange_after_36-darwin-terminal-fonts.sh.tmpl \
	run_onchange_after_40-install-ai-clis.sh.tmpl; do

	path="${SCRIPTS_DIR}/${script}"
	if [[ ! -f "${path}" ]]; then
		fail "${script} is missing"
		continue
	fi

	# Under the profile/OS the script targets it emits a script; otherwise it is
	# intentionally empty. Either way rendering must not error.
	if ! rendered="$(DOTFILES_PROFILE=desktop render "${path}" 2>&1)"; then
		fail "${script} failed to render: ${rendered}"
		continue
	fi

	if [[ -z "${rendered//[[:space:]]/}" ]]; then
		pass "${script} renders empty on this host"
		continue
	fi

	printf '%s\n' "${rendered}" > "${TMP_ROOT}/rendered.sh"
	if [[ "$(head -1 "${TMP_ROOT}/rendered.sh")" != '#!'* ]]; then
		fail "${script} does not start with a shebang"
		continue
	fi

	case "${script}" in
		*.zsh.tmpl)
			# zsh syntax differs enough that bash -n gives false positives.
			pass "${script} renders with a shebang"
			;;
		*)
			if bash -n "${TMP_ROOT}/rendered.sh" 2>/dev/null; then
				pass "${script} renders valid bash"
			else
				fail "${script} renders invalid bash"
			fi
			;;
	esac
done

echo "== first-bootstrap resilience =="
# fzf shell integration must run in the `after` stage, because ~/.fzf is an
# external and does not exist while `before` scripts run. Living in the Homebrew
# script also skipped it entirely on machines without sudo.
fzf_script="${SCRIPTS_DIR}/run_after_015-fzf-shell-integration.sh.tmpl"
if [[ -f "${fzf_script}" ]]; then
	pass "fzf shell integration runs in the after stage"
else
	fail "run_after_015-fzf-shell-integration.sh.tmpl is missing"
fi

assert_not_contains "$(cat "${SCRIPTS_DIR}/run_onchange_before_04-linux-brew-packages.zsh.tmpl")" \
	"opt/fzf/install --all" "the before-stage brew script no longer sets up fzf"

# realpath on an absent path exits non-zero, which aborted the apply under set -e.
# shellcheck disable=SC2016 # matching literal shell source, not expanding it
assert_contains "$(cat "${SCRIPTS_DIR}/run_after_800-create-symblinks.sh.tmpl")" \
	'if [[ ! -e "$HOME/$path" ]]' "the symlink script skips absent paths"

# A toolchain build failure must not abort the whole apply.
for guarded in run_after_099-update-asdf.sh.tmpl run_after_900-finalizers.zsh.tmpl; do
	if grep -qE 'plugin update --all(\)|;| \|\|)' "${SCRIPTS_DIR}/${guarded}" &&
		grep -qE '\|\| echo|^if \$\{ASDF\}|if \$\{ASDF\}' "${SCRIPTS_DIR}/${guarded}"; then
		pass "${guarded} tolerates asdf failures"
	else
		fail "${guarded} still aborts the apply when asdf fails"
	fi
done

assert_contains "$(cat "${SCRIPTS_DIR}/run_after_900-finalizers.zsh.tmpl")" \
	"command -v brew" "the finalizer guards brew being absent from PATH"

echo "== Homebrew trust-store permissions =="
# Homebrew 6 refuses to write trust.json if either of the stores the script
# updates is group- or world-writable. Use a fake brew so this is a pure
# source-contract test and does not require a Homebrew installation.
trust_script="${SCRIPTS_DIR}/run_onchange_after_01-brew-trust-taps.sh.tmpl"
trust_home="${TMP_ROOT}/homebrew-trust-home"
trust_bin="${TMP_ROOT}/homebrew-trust-bin"
mkdir -p "${trust_home}/.config/homebrew" "${trust_home}/.homebrew" "${trust_bin}"
chmod 775 "${trust_home}/.config/homebrew" "${trust_home}/.homebrew"
printf '#!/usr/bin/env bash\nexit 0\n' > "${trust_bin}/brew"
chmod 755 "${trust_bin}/brew"

rendered_trust_script="${TMP_ROOT}/brew-trust-taps.sh"
DOTFILES_HOMEBREW=true render "${trust_script}" > "${rendered_trust_script}"
PATH="${trust_bin}:${PATH}" HOME="${trust_home}" bash "${rendered_trust_script}"

for trust_store in "${trust_home}/.config/homebrew" "${trust_home}/.homebrew"; do
	if [[ "$(stat -c '%a' "${trust_store}")" == "700" ]]; then
		pass "$(basename "${trust_store}") trust store is private"
	else
		fail "${trust_store} trust store is not mode 700"
	fi
done

if [[ -f "${SOURCE_DIR}/private_dot_config/private_homebrew/brew.env" ]]; then
	pass "the managed Homebrew directory has the private_ attribute"
else
	fail "the managed Homebrew directory is not private_"
fi

echo "== login shell on directory accounts =="
# chsh only edits /etc/passwd, so it cannot change the shell of a FreeIPA/LDAP/AD
# account. The old code compared against /etc/passwd, never matched for those
# users, and aborted the bootstrap when the resulting sudo chsh failed.
omz_script="${SCRIPTS_DIR}/run_once_before_02-install-omz.sh.tmpl"
omz_source="$(cat "${omz_script}")"

# shellcheck disable=SC2016 # these are literal shell snippets to match, not expansions
assert_not_contains "${omz_source}" 'awk -F ":${HOME}:" ' \
	"the login-shell check no longer parses /etc/passwd by home directory"
# shellcheck disable=SC2016
assert_contains "${omz_source}" 'grep -q "^${username}:" /etc/passwd' \
	"chsh only runs for accounts with a local passwd entry"
assert_contains "${omz_source}" "if sudo chsh" \
	"a failing chsh cannot abort the bootstrap"

# The bashrc handover is the only thing that gives a directory account zsh, so it
# must trigger for any non-zsh login shell, not just for bash.
# shellcheck disable=SC2016
assert_contains "$(cat "${SOURCE_DIR}/dot_bashrc.tmpl")" \
	'"$(basename -- "${SHELL:-}")" != "zsh"' \
	"dot_bashrc hands over to zsh from any non-zsh login shell"

echo "== managed helpers =="
for helper in dotfiles-doctor dotfiles-reset gnome-settings-export; do
	path="${SOURCE_DIR}/private_dot_local/private_bin/executable_${helper}.tmpl"
	if [[ ! -f "${path}" ]]; then
		fail "${helper} is missing"
		continue
	fi
	rendered="${TMP_ROOT}/${helper}.sh"
	if render "${path}" > "${rendered}" 2>/dev/null && bash -n "${rendered}"; then
		pass "${helper} renders valid bash"
	else
		fail "${helper} failed to render or is invalid bash"
	fi
done

echo "== AI CLI defaults never clobber =="
# chezmoi's create_ attribute seeds a file only when the target is absent, which
# is what keeps an already-configured machine's settings intact.
for seed in \
	private_dot_config/private_opencode/create_opencode.json \
	private_dot_codex/create_private_config.toml; do

	if [[ -f "${SOURCE_DIR}/${seed}" ]]; then
		pass "${seed} is seeded with create_"
	else
		fail "${seed} is missing or not using the create_ attribute"
	fi
done

echo "== Claude settings merge =="
# ~/.claude/settings.json cannot use create_ like the seeds above, because
# Claude Code rewrites it at runtime (theme, model, effortLevel, plugin
# toggles). A write-once seed could therefore never ship a later hook or
# permission change to a machine that already has the file -- which is exactly
# what create_ did here for as long as it was used. It uses modify_ instead:
# chezmoi pipes the current file in on stdin and takes the script's stdout as
# the new contents, so the script merges rather than replaces.
#
# That trades create_'s blunt guarantee for a conditional one, so assert the
# behaviour rather than the filename: keys the application owns must still win,
# and only the explicitly managed keys may be forced.
claude_modify="${SOURCE_DIR}/dot_claude/modify_settings.json.tmpl"
if [[ ! -f "${claude_modify}" ]]; then
	fail "dot_claude/modify_settings.json.tmpl is missing"
elif ! command -v jq >/dev/null 2>&1; then
	# The script itself needs jq, so a missing jq breaks apply, not just this
	# test. Fail loudly instead of skipping.
	fail "jq is required to exercise the Claude settings merge"
else
	merge="${TMP_ROOT}/modify_settings"
	render "${claude_modify}" > "${merge}"
	chmod +x "${merge}"

	assert_contains "$(cat "${claude_modify}")" '{{ .chezmoi.homeDir }}' \
		"the SessionStart hook path is templated, not hardcoded to one home"

	# A fresh machine has no target file, so chezmoi hands the script empty
	# stdin and the entire output becomes the new settings.json.
	seeded="$(: | "${merge}")"
	if printf '%s' "${seeded}" | jq -e . > /dev/null; then
		pass "the fresh-machine seed is valid JSON"
	else
		fail "the fresh-machine seed is not valid JSON"
	fi
	assert_contains "${seeded}" '"EnterWorktree"' \
		"the seed denies EnterWorktree"
	assert_contains "${seeded}" '.claude/hooks/context-mode-cache-heal.mjs' \
		"the seed wires up the SessionStart hook"

	# An already-configured machine. Everything Claude Code owns has to survive,
	# including keys this repo has never heard of.
	existing="${TMP_ROOT}/claude-existing-settings.json"
	cat > "${existing}" <<'JSON'
{
  "theme": "light",
  "model": "stub-model",
  "permissions": {
    "allow": ["Bash(only-mine:*)"],
    "deny": ["StaleEntry"]
  },
  "env": {"STALE_KEY": "1"},
  "localOnlyKey": true
}
JSON

	merged="$("${merge}" < "${existing}")"
	assert_contains "$(printf '%s' "${merged}" | jq -r '.theme')" "light" \
		"a theme written at runtime survives the merge"
	assert_contains "$(printf '%s' "${merged}" | jq -r '.model')" "stub-model" \
		"a model written at runtime survives the merge"
	assert_contains "$(printf '%s' "${merged}" | jq -c '.permissions.allow')" "only-mine" \
		"a machine-local allow-list survives the merge"
	assert_contains "$(printf '%s' "${merged}" | jq -r '.localOnlyKey')" "true" \
		"keys this repo does not manage survive the merge"

	# The managed tier is forced instead. jq's recursive merge replaces arrays
	# rather than concatenating them, so a stale deny entry is dropped rather
	# than accumulating forever.
	assert_contains "$(printf '%s' "${merged}" | jq -c '.permissions.deny')" "EnterWorktree" \
		"the managed deny-list is forced onto an existing file"
	assert_not_contains "$(printf '%s' "${merged}" | jq -c '.permissions.deny')" "StaleEntry" \
		"the managed deny-list replaces rather than appends"
	assert_contains "$(printf '%s' "${merged}" | jq -r '.env.HOMEBREW_NO_ASK')" "1" \
		"the managed env is forced onto an existing file"
	assert_contains \
		"$(printf '%s' "${merged}" | jq -r '[.hooks[][].hooks[].command] | join(" ")')" \
		"rtk hook claude" \
		"the managed hooks are forced onto an existing file"

	# chezmoi verify re-runs the script against the file it just wrote, so drift
	# here fails the macOS smoke job rather than this one.
	if [[ "$(printf '%s' "${merged}" | "${merge}")" == "${merged}" ]]; then
		pass "re-merging an already-merged file changes nothing"
	else
		fail "the merge is not idempotent on an existing file"
	fi
	if [[ "$(printf '%s' "${seeded}" | "${merge}")" == "${seeded}" ]]; then
		pass "re-merging the fresh-machine seed changes nothing"
	else
		fail "the merge is not idempotent on the seed"
	fi

	# A malformed settings.json silently disables every setting in it. Replacing
	# it with the seed would throw away whatever was being edited at the time,
	# so the script has to refuse and let a human look at it.
	if printf '{ not json' | "${merge}" > /dev/null 2>&1; then
		fail "a malformed settings.json was overwritten instead of rejected"
	else
		pass "a malformed settings.json is rejected rather than clobbered"
	fi
fi

echo "== no SIGPIPE-prone pipelines =="
# `grep --quiet` closes the pipe on its first match. Under pipefail the upstream
# command then dies of SIGPIPE and the whole pipeline reports failure, so a
# passing check fails intermittently. Only scripts that enable pipefail — on
# their own or via the scripts-library template — are affected.
sigpipe_hits=0
while IFS= read -r candidate; do
	grep -qE 'pipefail|scripts-library' "${candidate}" || continue

	while IFS= read -r hit; do
		fail "grep --quiet in a pipeline under pipefail: ${hit}"
		sigpipe_hits=$((sigpipe_hits + 1))
	done < <(grep -n -- '| *grep [^|]*--quiet\|| *grep -[a-zA-Z]*q' "${candidate}" || true)
done < <(find "${SCRIPTS_DIR}" "${SOURCE_DIR}/private_dot_local/private_bin" -type f 2>/dev/null)

if ((sigpipe_hits == 0)); then
	pass "no grep --quiet inside pipefail pipelines"
fi

echo "== task and CI wiring =="
taskfile="$(cat "${REPO_ROOT}/Taskfile.yaml")"
for task_name in doctor gnome-export test-bootstrap; do
	assert_contains "${taskfile}" "  ${task_name}:" "Taskfile defines ${task_name}"
done

assert_contains "$(cat "${REPO_ROOT}/.github/workflows/acceptance-tests.yaml")" \
	"bootstrap-profiles.test.sh" "CI runs these contract tests"

assert_contains "$(cat "${REPO_ROOT}/tests/Dockerfile.ubuntu")" \
	"DOTFILES_PROFILE=server" "the Ubuntu smoke image exercises the server profile"

echo
if ((failures > 0)); then
	printf '%d check(s) failed\n' "${failures}" >&2
	exit 1
fi

echo "all bootstrap profile checks passed"
