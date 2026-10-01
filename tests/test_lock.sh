#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_dir/test_helpers.sh"
. "$script_dir/../lib/hac-env.sh"
. "$script_dir/../lib/hac-json.sh"
. "$script_dir/../lib/hac-lock.sh"

trap cleanup_test_home EXIT HUP INT TERM

test_lock_acquisition_and_release() {
    new_test_home
    hac_init_layout
    hac_acquire_lock runtime
    [ -d "$(hac_runtime_root)/locks/runtime" ]
    assert_eq "$$" "$(cat "$(hac_runtime_root)/locks/runtime/pid")" lock-owner
    if hac_acquire_lock runtime >/dev/null 2>&1; then return 1; fi
    hac_release_lock runtime
    [ ! -e "$(hac_runtime_root)/locks/runtime" ]
}

test_live_process_lock_is_not_stale() {
    new_test_home
    hac_init_layout
    lock="$(hac_runtime_root)/locks/live"
    mkdir "$lock"
    printf '%s\n' "$$" > "$lock/pid"
    printf '%s\n' "$(date +%s)" > "$lock/timestamp"
    if hac_lock_is_stale live; then return 1; fi
    if hac_acquire_lock live >/dev/null 2>&1; then return 1; fi
}

test_stale_lock_is_recovered() {
    new_test_home
    hac_init_layout
    lock="$(hac_runtime_root)/locks/stale"
    mkdir "$lock"
    printf '%s\n' 999999 > "$lock/pid"
    printf '%s\n' "$(( $(date +%s) - 7200 ))" > "$lock/timestamp"
    HAC_LOCK_STALE_SECONDS=60
    export HAC_LOCK_STALE_SECONDS
    hac_lock_is_stale stale
    hac_acquire_lock stale
    assert_eq "$$" "$(cat "$lock/pid")" stale-owner
    hac_release_lock stale
}

test_separate_processes_contend_for_lock() {
    new_test_home
    hac_init_layout
    lock_home=$TEST_HOME
    result_dir="$TEST_HOME/results"
    mkdir "$result_dir"
    (
        HOME="$lock_home"; export HOME
        . "$script_dir/../lib/hac-env.sh"
        . "$script_dir/../lib/hac-json.sh"
        . "$script_dir/../lib/hac-lock.sh"
        hac_acquire_lock concurrent && { printf 'held\n' > "$result_dir/one"; sleep 1; hac_release_lock concurrent; } || printf 'rejected\n' > "$result_dir/one"
    ) &
    first_pid=$!
    sleep 0.1
    (
        HOME="$lock_home"; export HOME
        . "$script_dir/../lib/hac-env.sh"
        . "$script_dir/../lib/hac-json.sh"
        . "$script_dir/../lib/hac-lock.sh"
        hac_acquire_lock concurrent && { printf 'held\n' > "$result_dir/two"; hac_release_lock concurrent; } || printf 'rejected\n' > "$result_dir/two"
    ) &
    second_pid=$!
    wait "$first_pid"
    wait "$second_pid"
    held_count=0
    [ "$(cat "$result_dir/one")" = held ] && held_count=$((held_count + 1))
    [ "$(cat "$result_dir/two")" = held ] && held_count=$((held_count + 1))
    assert_eq 1 "$held_count" separate-process-exclusion
}

test_lock_acquisition_and_release
test_live_process_lock_is_not_stale
test_stale_lock_is_recovered
test_separate_processes_contend_for_lock
printf 'PASS: lock contract\n'
