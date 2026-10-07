#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
STUB_DIR="$ROOT_DIR/docker/fixtures/reload-stub"
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/what-changed-reload-test.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

run_case() {
  mode=$1
  expected_status=$2
  expected_attempts=$3
  state="$WORK_DIR/$mode.state"
  stdout="$WORK_DIR/$mode.stdout"
  stderr="$WORK_DIR/$mode.stderr"

  set +e
  PATH="$STUB_DIR:$PATH" \
    STUB_MODE="$mode" \
    STUB_STATE="$state" \
    "$ROOT_DIR/docker/reload-freepbx-lab.sh" >"$stdout" 2>"$stderr"
  status=$?
  set -e

  if [ "$status" -ne "$expected_status" ]; then
    echo "$mode returned $status; expected $expected_status" >&2
    cat "$stdout" >&2
    cat "$stderr" >&2
    return 1
  fi
  attempts=$(cat "$state")
  if [ "$attempts" -ne "$expected_attempts" ]; then
    echo "$mode made $attempts reload attempts; expected $expected_attempts" >&2
    return 1
  fi
}

run_case success 0 1
run_case failure 7 1
run_case lock 9 3
run_case lock-then-success 0 2

root_state="$WORK_DIR/root-success.state"
PATH="$STUB_DIR:$PATH" \
  STUB_MODE=success \
  STUB_STATE="$root_state" \
  FWCONSOLE_RUN_AS=root \
  "$ROOT_DIR/docker/reload-freepbx-lab.sh" >/dev/null
[ "$(cat "$root_state")" -eq 1 ]

echo 'Bounded FreePBX reload helper regression checks passed'
