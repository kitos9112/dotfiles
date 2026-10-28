#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck source=tests/lib/contract-test.sh
source "${SCRIPT_DIR}/lib/contract-test.sh"

for dependency in zsh python3; do
	command -v "${dependency}" >/dev/null 2>&1 || {
		printf 'missing dependency for tests: %s\n' "${dependency}" >&2
		exit 127
	}
done

HOOK="${SOURCE_DIR}/dot_oh-my-zsh-custom/history.zsh"
DRIVER="${TMP_ROOT}/drive.py"
cat >"${DRIVER}" <<'EOF'
import os, pty, select, sys, time

histfile, hook, keys = sys.argv[1], sys.argv[2], sys.argv[3:]
pid, fd = pty.fork()
if pid == 0:
    os.environ.update(HISTFILE=histfile, PS1="$ ", PS2="> ")
    os.execvp("zsh", ["zsh", "-f", "-i"])


def drain(seconds=0.4):
    end = time.time() + seconds
    while time.time() < end:
        if select.select([fd], [], [], 0.05)[0]:
            try:
                os.read(fd, 4096)
            except OSError:
                return


setup = "HISTSIZE=100 SAVEHIST=100; setopt extendedhistory sharehistory histignorespace histreduceblanks"
if hook != "-":
    setup += f"; source {hook}"
for key in [setup + "\r", *keys, "exit\r"]:
    os.write(fd, key.encode())
    drain()
os.waitpid(pid, 0)
EOF

history_after() {
	local hook=$1 histfile="${TMP_ROOT}/hist-$RANDOM"
	shift
	python3 -I "${DRIVER}" "${histfile}" "${hook}" "$@"
	grep -vE 'HISTSIZE=|source ' "${histfile}" | sed -E 's/^: [0-9]+:0;//'
}

cancelled=(
	$'echo one\\\r' $'\x03'
	$'echo two\r'
)

without_hook="$(history_after - "${cancelled[@]}")"
assert_contains "${without_hook}" 'echo one\' \
	"without the hook a cancelled continuation is saved with its trailing backslash"

with_hook="$(history_after "${HOOK}" "${cancelled[@]}")"
assert_contains "${with_hook}" $'echo one\necho two\nexit' \
	"the hook saves a cancelled continuation without its trailing backslash"

secret="$(history_after "${HOOK}" $' echo hidden\\\r' $'\x03' $'echo shown\r')"
assert_not_contains "${secret}" "hidden" "the hook keeps honouring HIST_IGNORE_SPACE"

multiline="$(history_after "${HOOK}" $'echo three\\\r' $'echo four\r')"
assert_contains "${multiline}" $'echo three\\\\\necho four' "a completed multi-line command is saved unchanged"

finish_tests
