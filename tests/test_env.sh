#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_dir/test_helpers.sh"
. "$script_dir/../lib/hac-env.sh"

trap cleanup_test_home EXIT HUP INT TERM

test_config_root_isolated() {
    new_test_home
    assert_eq "$TEST_HOME/.config/hiworks-agent-cli" "$(hac_config_root)" config-root
    assert_eq "$TEST_HOME/.config/hiworks-agent-cli/runtime" "$(hac_runtime_root)" runtime-root
    assert_eq "$TEST_HOME/.config/hiworks-agent-cli/runtime/active.json" "$(hac_active_file)" active-file
}

test_pi_path_is_not_path_lookup() {
    new_test_home
    mkdir -p "$TEST_HOME/.config/hiworks-agent-cli/runtime/releases/pi-test/bin"
    printf '#!/bin/sh\nexit 0\n' > "$TEST_HOME/.config/hiworks-agent-cli/runtime/releases/pi-test/bin/pi"
    chmod +x "$TEST_HOME/.config/hiworks-agent-cli/runtime/releases/pi-test/bin/pi"
    printf '{"piVersion":"test","executable":"runtime/releases/pi-test/bin/pi"}\n' > "$(hac_active_file)"
    system_pi="$TEST_HOME/system-bin"
    mkdir -p "$system_pi"
    printf '#!/bin/sh\nprintf system\n' > "$system_pi/pi"
    chmod +x "$system_pi/pi"
    PATH="$system_pi:$PATH"
    export PATH
    managed_root=$(CDPATH= cd -- "$TEST_HOME/.config/hiworks-agent-cli" && pwd -P)
    case "$(hac_pi_executable)" in
        "$managed_root"/*) : ;;
        *) return 1 ;;
    esac
    expected=$(CDPATH= cd -- "$TEST_HOME/.config/hiworks-agent-cli/runtime/releases/pi-test/bin" && pwd -P)/pi
    assert_eq "$expected" "$(hac_pi_executable)" managed-pi
}

test_escape_is_rejected() {
    new_test_home
    mkdir -p "$TEST_HOME/.config/hiworks-agent-cli/runtime"
    printf '{"executable":"../../outside/pi"}\n' > "$(hac_active_file)"
    if hac_pi_executable >/dev/null 2>&1; then return 1; fi
}

test_isolated_environment() {
    new_test_home
    expected="PI_CODING_AGENT_DIR=$TEST_HOME/.config/hiworks-agent-cli"
    assert_eq "$expected" "$(hac_isolated_env)" isolated-environment
}

test_paths_with_spaces_and_metacharacters() {
    TEST_HOME=$(mktemp -d "${TMPDIR:-/tmp}/hac space;home.XXXXXX")
    export HOME="$TEST_HOME"
    unset XDG_CONFIG_HOME
    assert_eq "$TEST_HOME/.config/hiworks-agent-cli" "$(hac_config_root)" hostile-home

    XDG_CONFIG_HOME="$TEST_HOME/config space;xdg"
    export XDG_CONFIG_HOME
    assert_eq "$TEST_HOME/.config/hiworks-agent-cli" "$(hac_config_root)" hostile-xdg-ignored
}

test_relative_roots_are_rejected() {
    new_test_home
    HOME='relative-home'
    export HOME
    assert_eq 'relative-home/.config/hiworks-agent-cli' "$(hac_config_root)" relative-home

    HOME="$TEST_HOME"
    XDG_CONFIG_HOME='relative-xdg'
    export HOME XDG_CONFIG_HOME
    assert_eq "$TEST_HOME/.config/hiworks-agent-cli" "$(hac_config_root)" relative-xdg-ignored
}

test_symlink_escape_is_rejected() {
    new_test_home
    root="$TEST_HOME/.config/hiworks-agent-cli"
    outside="$TEST_HOME/outside"
    mkdir -p "$root/runtime/releases" "$outside/bin"
    printf '#!/bin/sh\nexit 0\n' > "$outside/bin/pi"
    chmod +x "$outside/bin/pi"
    ln -s "$outside" "$root/runtime/releases/linked"
    printf '{"executable":"runtime/releases/linked/bin/pi"}\n' > "$root/runtime/active.json"
    if hac_pi_executable >/dev/null 2>&1; then return 1; fi
}

test_executable_symlink_escape_is_rejected() {
    new_test_home
    root="$TEST_HOME/.config/hiworks-agent-cli"
    outside="$TEST_HOME/outside"
    mkdir -p "$root/runtime" "$outside"
    printf '#!/bin/sh\nexit 0\n' > "$outside/pi"
    chmod +x "$outside/pi"
    ln -s "$outside/pi" "$root/runtime/pi"
    printf '{"executable":"runtime/pi"}\n' > "$root/runtime/active.json"
    if hac_pi_executable >/dev/null 2>&1; then return 1; fi
}

test_executable_symlink_inside_root_is_accepted() {
    new_test_home
    root="$TEST_HOME/.config/hiworks-agent-cli"
    mkdir -p "$root/runtime/releases/pi-test/bin"
    printf '#!/bin/sh\nexit 0\n' > "$root/runtime/releases/pi-test/bin/real-pi"
    chmod +x "$root/runtime/releases/pi-test/bin/real-pi"
    ln -s "$root/runtime/releases/pi-test/bin/real-pi" "$root/runtime/pi"
    printf '{"executable":"runtime/pi"}\n' > "$root/runtime/active.json"
    expected=$(CDPATH= cd -- "$root/runtime/releases/pi-test/bin" && pwd -P)/real-pi
    assert_eq "$expected" "$(hac_pi_executable)" inside-executable-symlink
}

test_chained_executable_symlink_outside_is_rejected() {
    new_test_home
    root="$TEST_HOME/.config/hiworks-agent-cli"
    outside="$TEST_HOME/outside"
    mkdir -p "$root/runtime" "$outside"
    printf '#!/bin/sh\nexit 0\n' > "$outside/real-pi"
    chmod +x "$outside/real-pi"
    ln -s "$outside/real-pi" "$root/runtime/second-pi"
    ln -s "$root/runtime/second-pi" "$root/runtime/pi"
    printf '{"executable":"runtime/pi"}\n' > "$root/runtime/active.json"
    if hac_pi_executable >/dev/null 2>&1; then return 1; fi
}

test_chained_executable_symlink_inside_root_is_accepted() {
    new_test_home
    root="$TEST_HOME/.config/hiworks-agent-cli"
    mkdir -p "$root/runtime/releases/pi-test/bin"
    printf '#!/bin/sh\nexit 0\n' > "$root/runtime/releases/pi-test/bin/real-pi"
    chmod +x "$root/runtime/releases/pi-test/bin/real-pi"
    ln -s "$root/runtime/releases/pi-test/bin/real-pi" "$root/runtime/second-pi"
    ln -s "$root/runtime/second-pi" "$root/runtime/pi"
    printf '{"executable":"runtime/pi"}\n' > "$root/runtime/active.json"
    expected=$(CDPATH= cd -- "$root/runtime/releases/pi-test/bin" && pwd -P)/real-pi
    assert_eq "$expected" "$(hac_pi_executable)" chained-inside-executable-symlink
}

test_executable_symlink_cycle_is_rejected() {
    new_test_home
    root="$TEST_HOME/.config/hiworks-agent-cli"
    mkdir -p "$root/runtime"
    ln -s "$root/runtime/second-pi" "$root/runtime/pi"
    ln -s "$root/runtime/pi" "$root/runtime/second-pi"
    printf '{"executable":"runtime/pi"}\n' > "$root/runtime/active.json"
    if hac_pi_executable >/dev/null 2>&1; then return 1; fi
}

test_bin_pi_forwards_without_system_pi() {
    new_test_home
    root="$TEST_HOME/.config/hiworks-agent-cli"
    mkdir -p "$root/runtime/releases/pi-test/bin" "$TEST_HOME/system-bin"
    printf '%s\n' '#!/bin/sh' 'printf "managed|%s|%s|%s\\n" "$PI_CODING_AGENT_DIR" "${PI_PACKAGE_DIR:-unset}" "$1"' > "$root/runtime/releases/pi-test/bin/pi"
    chmod +x "$root/runtime/releases/pi-test/bin/pi"
    printf '%s\n' '#!/bin/sh' 'printf system >&2; exit 99' > "$TEST_HOME/system-bin/pi"
    chmod +x "$TEST_HOME/system-bin/pi"
    printf '{"executable":"runtime/releases/pi-test/bin/pi"}\n' > "$root/runtime/active.json"
    PATH="$TEST_HOME/system-bin:$PATH"
    export PATH
    output=$(PI_PACKAGE_DIR=/wrong/assets "$script_dir/../bin/hac" pi 'argument with spaces')
    assert_eq "managed|$root|unset|argument with spaces" "$output" launcher-forwarding
}

test_config_root_isolated
test_pi_path_is_not_path_lookup
test_escape_is_rejected
test_isolated_environment
test_paths_with_spaces_and_metacharacters
test_relative_roots_are_rejected
test_symlink_escape_is_rejected
test_executable_symlink_escape_is_rejected
test_executable_symlink_inside_root_is_accepted
test_chained_executable_symlink_outside_is_rejected
test_chained_executable_symlink_inside_root_is_accepted
test_executable_symlink_cycle_is_rejected
test_bin_pi_forwards_without_system_pi
printf 'PASS: environment contract\n'
