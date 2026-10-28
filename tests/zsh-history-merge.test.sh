#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck source=tests/lib/contract-test.sh
source "${SCRIPT_DIR}/lib/contract-test.sh"

MERGE="${SOURCE_DIR}/private_dot_local/private_bin/executable_zsh-history-merge"

case_dir() {
	local dir="${TMP_ROOT}/$1"
	mkdir -p "${dir}"
	printf '%s\n' "${dir}"
}

dir="$(case_dir union)"
printf ': 30:0;three\n: 10:0;one\n' >"${dir}/a"
printf ': 20:0;two\n: 10:0;one\n' >"${dir}/b"
python3 -I "${MERGE}" --output "${dir}/out" "${dir}/a" "${dir}/b"
assert_file_content "${dir}/out" $': 10:0;one\n: 20:0;two\n: 30:0;three' \
	"merge is a time-ordered union without duplicate records"

dir="$(case_dir same-time)"
printf ': 10:0;first\n: 10:0;second\n' >"${dir}/a"
python3 -I "${MERGE}" --output "${dir}/out" "${dir}/a"
assert_file_content "${dir}/out" $': 10:0;first\n: 10:0;second' \
	"records sharing a timestamp keep their input order"

dir="$(case_dir multiline)"
printf ': 20:0;echo a \\\n: 5:0;still the same command\n: 10:0;other\n' >"${dir}/a"
python3 -I "${MERGE}" --output "${dir}/out" "${dir}/a"
assert_file_content "${dir}/out" $': 10:0;other\n: 20:0;echo a \\\n: 5:0;still the same command' \
	"a backslash-continued line stays part of its record"

dir="$(case_dir in-place)"
printf ': 10:0;kept\n' >"${dir}/archive"
printf ': 20:0;new\n' >"${dir}/live"
python3 -I "${MERGE}" --output "${dir}/archive" "${dir}/archive" "${dir}/live"
assert_file_content "${dir}/archive" $': 10:0;kept\n: 20:0;new' \
	"the output may also be an input, so an archive can absorb new history"

dir="$(case_dir missing-input)"
printf ': 10:0;kept\n' >"${dir}/live"
python3 -I "${MERGE}" --output "${dir}/archive" "${dir}/archive" "${dir}/live"
assert_file_content "${dir}/archive" ': 10:0;kept' \
	"a missing input is treated as empty, so the first archive run works"

mode="$(LC_ALL=C ls -l "${dir}/archive" | cut -c1-10)"
if [[ "${mode}" == "-rw-------" ]]; then pass "output is private (0600)"; else fail "output is private (0600), got ${mode}"; fi

dir="$(case_dir bytes)"
printf ': 10:0;echo \x83\xa2meta\n' >"${dir}/a"
python3 -I "${MERGE}" --output "${dir}/out" "${dir}/a"
if cmp -s "${dir}/a" "${dir}/out"; then pass "zsh metafied bytes survive unchanged"; else fail "zsh metafied bytes survive unchanged"; fi

dir="$(case_dir no-trailing-newline)"
printf ': 10:0;one\n: 20:0;two' >"${dir}/a"
python3 -I "${MERGE}" --output "${dir}/out" "${dir}/a"
if [[ "$(tail -c1 "${dir}/out" | od -An -c | tr -d ' ')" == '\n' ]]; then
	pass "output always ends with a newline"
else
	fail "output always ends with a newline"
fi

dir="$(case_dir count)"
printf ': 10:0;one\n: 20:0;two \\\nmore\n: 20:0;two \\\nmore\n' >"${dir}/a"
count="$(python3 -I "${MERGE}" --count "${dir}/a")"
if [[ "${count}" == 2 ]]; then pass "--count reports distinct records"; else fail "--count reports distinct records, got ${count}"; fi

dir="$(case_dir repair-swallowed)"
printf ': 10:0;ssh host\\\n: 20:0;ipa vault-retrieve x\n: 30:0;ls\n' >"${dir}/a"
python3 -I "${MERGE}" --repair --output "${dir}/out" "${dir}/a"
assert_file_content "${dir}/out" $': 10:0;ssh host\n: 20:0;ipa vault-retrieve x\n: 30:0;ls' \
	"--repair splits an entry swallowed by a trailing backslash and drops the backslash"

dir="$(case_dir repair-chain)"
printf ': 10:0;a\\\\\n: 20:0;b\\\n: 30:0;c\\\n' >"${dir}/a"
python3 -I "${MERGE}" --repair --output "${dir}/out" "${dir}/a"
assert_file_content "${dir}/out" $': 10:0;a\n: 20:0;b\n: 30:0;c' \
	"--repair splits chains and strips every trailing backslash, including on the last entry"

dir="$(case_dir repair-backslash-space)"
printf ': 10:0;echo one\\ \n: 20:0;echo two\n' >"${dir}/a"
python3 -I "${MERGE}" --repair --output "${dir}/out" "${dir}/a"
assert_file_content "${dir}/out" $': 10:0;echo one\n: 20:0;echo two' \
	"--repair strips a trailing backslash followed by spaces, which a whitespace trim would turn harmful"

dir="$(case_dir repair-rerun)"
printf ': 10:0;ssh host\\\n: 20:0;ipa x\n: 99:0;ssh host\\\n: 20:0;ipa x\n' >"${dir}/a"
python3 -I "${MERGE}" --repair --output "${dir}/out" "${dir}/a"
assert_file_content "${dir}/out" $': 10:0;ssh host\n: 20:0;ipa x\n: 99:0;ssh host' \
	"--repair collapses an entry re-saved after being recalled from a merged line"

dir="$(case_dir repair-keeps-multiline)"
printf ': 10:0;for f in *; do\\\n  echo $f\\\ndone\n' >"${dir}/a"
python3 -I "${MERGE}" --repair --output "${dir}/out" "${dir}/a"
if cmp -s "${dir}/a" "${dir}/out"; then pass "--repair leaves genuine multi-line commands alone"; else fail "--repair leaves genuine multi-line commands alone"; fi

dir="$(case_dir no-repair-by-default)"
printf ': 10:0;ssh host\\\n: 20:0;ipa x\n' >"${dir}/a"
python3 -I "${MERGE}" --output "${dir}/out" "${dir}/a"
if cmp -s "${dir}/a" "${dir}/out"; then pass "without --repair records are kept as zsh reads them"; else fail "without --repair records are kept as zsh reads them"; fi

if python3 -I "${MERGE}" --output "${dir}/out" >/dev/null 2>&1; then
	fail "merge without inputs is rejected"
else
	pass "merge without inputs is rejected"
fi

finish_tests
