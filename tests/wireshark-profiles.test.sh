#! /usr/bin/env bash
#
# Regression test for the wireshark profile installer.
#
# The `run_onchange_after_*-wireshark-profiles` chezmoi script must extract
# every *.zip fetched into ~/.config/wireshark_profiles (by the external in
# .chezmoiexternal.yaml) into ~/.config/wireshark/profiles, which is the
# directory Wireshark actually reads on both Linux and macOS.
#
# This test is hermetic: it builds a fixture archive inside a throwaway HOME,
# renders the chezmoi template for the current OS, runs it, and asserts the
# profile was installed. It never touches the real ~/.config/wireshark.
#
# Run with: bash tests/wireshark-profiles.test.sh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
template="${repo_root}/home/.chezmoiscripts/run_onchange_after_00-wireshark-profiles.sh.tmpl"

test_home="$(mktemp -d)"
trap 'rm -rf "${test_home}"' EXIT

# Arrange: simulate the fetched external. Upstream packages each profile as a
# directory inside its own zip (e.g. SampleProfile/preferences).
src_dir="${test_home}/.config/wireshark_profiles"
mkdir -p "${src_dir}/staging/SampleProfile"
printf 'fixture preference\n' >"${src_dir}/staging/SampleProfile/preferences"
(cd "${src_dir}/staging" && zip -q -r "../SampleProfile.zip" "SampleProfile")
rm -rf "${src_dir}/staging"

# Act: render the chezmoi template for this OS and run it against the temp HOME.
if [[ -f "${template}" ]]; then
  rendered="${test_home}/rendered.sh"
  chezmoi execute-template <"${template}" >"${rendered}"
  HOME="${test_home}" bash "${rendered}"
else
  echo "(no template at ${template#"${repo_root}/"} yet)"
fi

# Assert: the profile landed where Wireshark reads it.
expected="${test_home}/.config/wireshark/profiles/SampleProfile/preferences"
if [[ -f "${expected}" ]]; then
  echo "PASS: wireshark profile installed at ~${expected#"${test_home}"}"
else
  echo "FAIL: profile not installed at ~${expected#"${test_home}"}"
  echo "Contents of profiles dir:"
  ls -R "${test_home}/.config/wireshark/profiles" 2>&1 | sed 's/^/  /' || echo "  (profiles dir does not exist)"
  exit 1
fi
