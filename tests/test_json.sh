#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_dir/test_helpers.sh"
. "$script_dir/../lib/hac-env.sh"
. "$script_dir/../lib/hac-json.sh"

trap cleanup_test_home EXIT HUP INT TERM

test_layout_creates_defaults_and_directories() {
    new_test_home
    hac_init_layout
    assert_file_exists "$(hac_config_root)/settings.json"
    assert_file_exists "$(hac_config_root)/auth.json"
    assert_file_exists "$(hac_config_root)/models.json"
    assert_file_exists "$(hac_active_file)"
    [ -d "$(hac_config_root)/resources/hiworks-core" ]
    [ -d "$(hac_config_root)/packages/pi-managed" ]
    [ -d "$(hac_runtime_root)/releases" ]
    [ -d "$(hac_runtime_root)/locks" ]
    [ -d "$(hac_runtime_root)/cache" ]
    [ -d "$(hac_config_root)/sessions" ]
    [ -d "$(hac_config_root)/logs" ]
    mode=$(stat -c '%a' "$(hac_config_root)/auth.json" 2>/dev/null || stat -f '%Lp' "$(hac_config_root)/auth.json")
    assert_eq 600 "$mode" auth-permissions
}

test_layout_preserves_existing_json() {
    new_test_home
    root=$(hac_config_root)
    mkdir -p "$root"
    printf '%s\n' '{"custom":true}' > "$root/settings.json"
    printf '%s\n' '{"token":"keep"}' > "$root/auth.json"
    printf '%s\n' '{"model":"keep"}' > "$root/models.json"
    hac_init_layout
    assert_eq '{"custom":true}' "$(cat "$root/settings.json")" settings-preserved
    assert_eq '{"token":"keep"}' "$(cat "$root/auth.json")" auth-preserved
    assert_eq '{"model":"keep"}' "$(cat "$root/models.json")" models-preserved
}

test_layout_protects_new_and_existing_directories() (
    new_test_home
    umask 022
    root=$(hac_config_root)
    mkdir -p "$root/sessions"
    chmod 755 "$root" "$root/sessions"
    hac_init_layout
    for path in "$root" "$root/sessions" "$root/logs" "$root/runtime" "$root/runtime/locks"; do
        mode=$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path")
        assert_eq 700 "$mode" private-managed-directory
    done
)

test_layout_ignores_xdg_config_home() {
    new_test_home
    XDG_CONFIG_HOME="$TEST_HOME/other-config"
    export XDG_CONFIG_HOME
    assert_eq "$TEST_HOME/.config/hiworks-agent-cli" "$(hac_config_root)" fixed-config-root
}

test_layout_rejects_file_symlinks() {
    new_test_home
    root=$(hac_config_root)
    mkdir -p "$root" "$TEST_HOME/targets"
    for name in settings.json auth.json models.json; do
        ln -s "$TEST_HOME/targets/$name" "$root/$name"
        if hac_init_layout >/dev/null 2>&1; then return 1; fi
        rm "$root/$name"
    done
    ln -s "$TEST_HOME/targets/active.json" "$root/runtime-active-placeholder"
    mkdir -p "$root/runtime"
    mv "$root/runtime-active-placeholder" "$(hac_active_file)"
    if hac_init_layout >/dev/null 2>&1; then return 1; fi
}

test_layout_rejects_external_directory_symlink() {
    new_test_home
    root=$(hac_config_root)
    mkdir -p "$root" "$TEST_HOME/external"
    for name in resources packages sessions logs; do
        ln -s "$TEST_HOME/external" "$root/$name"
        if hac_init_layout >/dev/null 2>&1; then return 1; fi
        rm "$root/$name"
    done
    mkdir -p "$root/runtime"
    for name in releases locks cache; do
        ln -s "$TEST_HOME/external" "$root/runtime/$name"
        if hac_init_layout >/dev/null 2>&1; then return 1; fi
        rm "$root/runtime/$name"
    done
}

test_layout_rejects_dangling_directory_symlink() {
    new_test_home
    root=$(hac_config_root)
    mkdir -p "$root" "$root/runtime"
    ln -s "$TEST_HOME/missing" "$root/resources"
    if hac_init_layout >/dev/null 2>&1; then return 1; fi
}

test_active_state_validation_and_field_read() {
    new_test_home
    hac_init_layout
    root=$(hac_config_root)
    mkdir -p "$root/runtime/releases/pi-test/bin"
    printf '#!/bin/sh\nexit 0\n' > "$root/runtime/releases/pi-test/bin/pi"
    chmod +x "$root/runtime/releases/pi-test/bin/pi"
    printf '%s\n' '{"piVersion":"test","executable":"runtime/releases/pi-test/bin/pi","activatedAt":"2026-09-09T00:00:00Z"}' > "$(hac_active_file)"
    hac_validate_active_state
    assert_eq runtime/releases/pi-test/bin/pi "$(hac_read_active_field executable)" active-field
}

test_malformed_active_state_is_rejected() {
    new_test_home
    hac_init_layout
    printf '%s\n' '{"piVersion":"test"' > "$(hac_active_file)"
    if hac_validate_active_state >/dev/null 2>&1; then return 1; fi
}

test_active_executable_outside_root_is_rejected() {
    new_test_home
    hac_init_layout
    printf '%s\n' '{"piVersion":"test","executable":"../../outside/pi","activatedAt":"2026-09-09T00:00:00Z"}' > "$(hac_active_file)"
    if hac_validate_active_state >/dev/null 2>&1; then return 1; fi
}

test_layout_creates_defaults_and_directories
test_layout_preserves_existing_json
test_layout_protects_new_and_existing_directories
test_layout_ignores_xdg_config_home
test_layout_rejects_file_symlinks
test_layout_rejects_external_directory_symlink
test_layout_rejects_dangling_directory_symlink
test_active_state_validation_and_field_read
test_malformed_active_state_is_rejected
test_active_executable_outside_root_is_rejected
printf 'PASS: JSON state contract\n'
