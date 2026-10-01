#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
. "$script_dir/test_helpers.sh"
trap cleanup_test_home EXIT HUP INT TERM
new_test_home
mkdir -p "$TEST_HOME/.local/bin" "$TEST_HOME/.local/share/hac"
printf sentinel > "$TEST_HOME/.local/bin/hac"
printf sentinel > "$TEST_HOME/.local/share/hac/marker"
HOME="$TEST_HOME" HAC_SMOKE_NPM_FIXTURE="$script_dir/fixtures/pi-package-0.85.1" sh "$script_dir/smoke.sh" > "$TEST_HOME/output" 2>&1 || :
assert_eq sentinel "$(cat "$TEST_HOME/.local/bin/hac")" smoke-must-preserve-caller-launcher
assert_eq sentinel "$(cat "$TEST_HOME/.local/share/hac/marker")" smoke-must-preserve-caller-install
[ ! -e "$TEST_HOME/.config/hiworks-agent-cli" ]
grep '^PASS: automatic Pi smoke test$' "$TEST_HOME/output" >/dev/null
printf '%s\n' 'PASS: smoke HOME isolation'
