#!/usr/bin/env sh
SCRIPT_PATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

sh -c "${SCRIPT_PATH}/../install"

exec "$@"