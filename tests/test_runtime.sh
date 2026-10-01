#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_dir/test_helpers.sh"
. "$script_dir/../lib/hac-env.sh"
. "$script_dir/../lib/hac-json.sh"
. "$script_dir/../lib/hac-lock.sh"
. "$script_dir/../lib/hac-runtime.sh"

trap cleanup_test_home EXIT HUP INT TERM

make_release_source() {
    source=$1
    version=$2
    mkdir -p "$source/bin"
    write_healthy_pi "$source/bin/pi" "$version"
    chmod +x "$source/bin/pi"
    printf '%s\n' "{\"piVersion\":\"$version\",\"executable\":\"bin/pi\"}" > "$source/metadata.json"
}

test_install_and_activate_candidate() {
    new_test_home
    hac_init_layout
    source="$TEST_HOME/source"
    make_release_source "$source" 1.0.0
    release=$(hac_install_candidate 1.0.0 "$source")
    assert_eq "$(hac_runtime_root)/releases/pi-1.0.0" "$release" installed-release
    [ -x "$release/bin/pi" ]
    hac_activate_candidate "$release" '{"piVersion":"1.0.0","executable":"bin/pi"}'
    expected=$(CDPATH= cd -- "$release/bin" && pwd -P)/pi
    assert_eq "$expected" "$(hac_pi_executable)" absolute-executable
    hac_validate_active_state
}

test_failed_activation_preserves_previous_active() {
    new_test_home
    hac_init_layout
    first="$TEST_HOME/first"
    second="$TEST_HOME/second"
    make_release_source "$first" 1.0.0
    make_release_source "$second" 2.0.0
    first_release=$(hac_install_candidate 1.0.0 "$first")
    second_release=$(hac_install_candidate 2.0.0 "$second")
    hac_activate_candidate "$first_release" '{"piVersion":"1.0.0","executable":"bin/pi"}'
    before=$(cat "$(hac_active_file)")
    if hac_activate_candidate "$second_release" '{"piVersion":"2.0.0","executable":"missing/pi"}' >/dev/null 2>&1; then return 1; fi
    assert_eq "$before" "$(cat "$(hac_active_file)")" active-preserved
}

test_rollback_to_previous_known_good_release() {
    new_test_home
    hac_init_layout
    first="$TEST_HOME/first"
    second="$TEST_HOME/second"
    make_release_source "$first" 1.0.0
    make_release_source "$second" 2.0.0
    first_release=$(hac_install_candidate 1.0.0 "$first")
    second_release=$(hac_install_candidate 2.0.0 "$second")
    hac_activate_candidate "$first_release" '{"piVersion":"1.0.0","executable":"bin/pi"}'
    hac_activate_candidate "$second_release" '{"piVersion":"2.0.0","executable":"bin/pi"}'
    hac_rollback_active
    expected=$(CDPATH= cd -- "$first_release/bin" && pwd -P)/pi
    assert_eq "$expected" "$(hac_pi_executable)" rollback-release
    assert_eq 1.0.0 "$(hac_read_active_field piVersion)" rollback-version
}

test_external_candidate_cannot_activate() {
    new_test_home
    hac_init_layout
    source="$TEST_HOME/external-release"
    make_release_source "$source" 3.0.0
    if hac_activate_candidate "$source" '{"piVersion":"3.0.0","executable":"bin/pi"}' >/dev/null 2>&1; then return 1; fi
}

test_executable_symlink_escape_is_rejected() {
    new_test_home
    hac_init_layout
    source="$TEST_HOME/source"
    outside="$TEST_HOME/outside"
    make_release_source "$source" 4.0.0
    mkdir "$outside"
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$outside/pi"
    chmod +x "$outside/pi"
    rm "$source/bin/pi"
    ln -s "$outside/pi" "$source/bin/pi"
    if hac_install_candidate 4.0.0 "$source" >/dev/null 2>&1; then return 1; fi
}

test_invalid_existing_release_is_replaced() {
    new_test_home
    hac_init_layout
    destination="$(hac_runtime_root)/releases/pi-5.0.0"
    mkdir -p "$destination"
    printf '%s\n' '{"piVersion":"5.0.0","executable":"bin/pi"}' > "$destination/metadata.json"
    source="$TEST_HOME/source"
    make_release_source "$source" 5.0.0
    release=$(hac_install_candidate 5.0.0 "$source")
    assert_file_exists "$release/bin/pi"
}

test_candidate_version_must_match_requested_version() {
    new_test_home
    hac_init_layout
    source="$TEST_HOME/source"
    make_release_source "$source" 1.0.0
    if hac_install_candidate 2.0.0 "$source" >/dev/null 2>&1; then return 1; fi
}

test_candidate_copy_rejects_any_symlink() {
    new_test_home
    hac_init_layout
    source="$TEST_HOME/source"
    outside="$TEST_HOME/outside"
    make_release_source "$source" 3.0.0
    printf '%s\n' external > "$outside"
    ln -s "$outside" "$source/extra"
    if hac_install_candidate 3.0.0 "$source" >/dev/null 2>&1; then return 1; fi
}

test_failed_candidate_does_not_replace_existing_release() {
    new_test_home
    hac_init_layout
    source="$TEST_HOME/source"
    make_release_source "$source" 8.0.0
    release=$(hac_install_candidate 8.0.0 "$source")
    before=$(cksum "$release/metadata.json")
    rm "$source/bin/pi"
    ln -s "$TEST_HOME/missing" "$source/bin/pi"
    if hac_install_candidate 8.0.0 "$source" >/dev/null 2>&1; then return 1; fi
    assert_eq "$before" "$(cksum "$release/metadata.json")" release-preserved
}

test_existing_release_is_replaced_by_new_candidate() {
    new_test_home
    hac_init_layout
    first="$TEST_HOME/first"
    second="$TEST_HOME/second"
    make_release_source "$first" 9.0.0
    make_release_source "$second" 9.0.0
    printf '%s\n' old > "$first/marker"
    printf '%s\n' new > "$second/marker"
    release=$(hac_install_candidate 9.0.0 "$first")
    assert_eq old "$(cat "$release/marker")" initial-release
    replaced=$(hac_install_candidate 9.0.0 "$second")
    assert_eq "$release" "$replaced" replaced-release-path
    assert_eq new "$(cat "$replaced/marker")" release-refreshed
}

test_rollback_and_activation_are_serialized() {
    new_test_home
    hac_init_layout
    first="$TEST_HOME/first"
    second="$TEST_HOME/second"
    make_release_source "$first" 6.0.0
    make_release_source "$second" 7.0.0
    first_release=$(hac_install_candidate 6.0.0 "$first")
    second_release=$(hac_install_candidate 7.0.0 "$second")
    hac_activate_candidate "$first_release" '{"piVersion":"6.0.0","executable":"bin/pi"}'
    hac_activate_candidate "$second_release" '{"piVersion":"7.0.0","executable":"bin/pi"}'

    hac_acquire_lock runtime
    (
        HOME="$TEST_HOME"; export HOME
        . "$script_dir/../lib/hac-env.sh"
        . "$script_dir/../lib/hac-json.sh"
        . "$script_dir/../lib/hac-lock.sh"
        . "$script_dir/../lib/hac-runtime.sh"
        if hac_rollback_active; then printf 'unexpected-success\n'; else printf 'rejected\n'; fi
    ) > "$TEST_HOME/rollback-result" 2>&1 &
    rollback_pid=$!
    sleep 0.1
    [ -f "$(hac_active_file)" ]
    assert_eq 7.0.0 "$(hac_read_active_field piVersion)" activation-state-unchanged-while-locked
    wait "$rollback_pid"
    assert_eq rejected "$(awk 'END {print}' "$TEST_HOME/rollback-result")" rollback-rejected-while-locked
    hac_release_lock runtime
    hac_rollback_active
    assert_eq 6.0.0 "$(hac_read_active_field piVersion)" serialized-rollback
}

test_install_and_activate_candidate
test_failed_activation_preserves_previous_active
test_rollback_to_previous_known_good_release
test_external_candidate_cannot_activate
test_executable_symlink_escape_is_rejected
test_invalid_existing_release_is_replaced
test_candidate_version_must_match_requested_version
test_candidate_copy_rejects_any_symlink
test_failed_candidate_does_not_replace_existing_release
test_existing_release_is_replaced_by_new_candidate
test_rollback_and_activation_are_serialized
printf 'PASS: runtime contract\n'
