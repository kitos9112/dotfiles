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
	chezmoi execute-template --source "${SOURCE_DIR}" "$@" < "${file}"
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

data_keys="$(chezmoi data --source "${SOURCE_DIR}" --format json)"
for key in packages terminalFont gnome fontsDir; do
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

echo "== rendered scripts are valid shell =="
for script in \
	run_onchange_before_03-linux-apt-packages.sh.tmpl \
	run_onchange_before_04-linux-brew-packages.zsh.tmpl \
	run_once_after_20-1password-signin.sh.tmpl \
	run_onchange_after_25-install-ghostty.sh.tmpl \
	run_onchange_after_30-gnome-settings.sh.tmpl \
	run_onchange_after_35-refresh-font-cache.sh.tmpl \
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

echo "== managed helpers =="
for helper in dotfiles-doctor gnome-settings-export; do
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
	dot_claude/create_settings.json \
	private_dot_config/private_opencode/create_opencode.json \
	private_dot_codex/create_config.toml; do

	if [[ -f "${SOURCE_DIR}/${seed}" ]]; then
		pass "${seed} is seeded with create_"
	else
		fail "${seed} is missing or not using the create_ attribute"
	fi
done

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
