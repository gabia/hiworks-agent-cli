#!/bin/sh

set -eu

HAC_TEST_REAL_NODE=${HAC_TEST_REAL_NODE:-$(command -v node)}
export HAC_TEST_REAL_NODE

HAC_DEFAULT_PACKAGES_FILE=${HAC_DEFAULT_PACKAGES_FILE:-$script_dir/fixtures/default-packages-empty.json}
export HAC_DEFAULT_PACKAGES_FILE

TEST_HOME=

new_test_home() {
    TEST_HOME=$(mktemp -d "${TMPDIR:-/tmp}/hac-test.XXXXXX")
    export TEST_HOME
    export HOME="$TEST_HOME"
    unset XDG_CONFIG_HOME
}

stub_command() {
    command_name=$1
    command_body=$2
    # Version stubs emulate the installer prerequisite only. Runtime probes
    # must execute actual Node, otherwise tests can bypass health validation.
    if [ "$command_name" = node ]; then
        command_body='if [ "${1:-}" != --version ]; then exec "$HAC_TEST_REAL_NODE" "$@"; fi
'"$command_body"
    fi
    stub_dir=${TEST_HOME}/bin
    mkdir -p "$stub_dir"
    printf '%s\n' '#!/bin/sh' "$command_body" > "$stub_dir/$command_name"
    chmod +x "$stub_dir/$command_name"
    PATH="$stub_dir:$PATH"
    export PATH
}

assert_eq() {
    expected=$1
    actual=$2
    message=${3:-values differ}
    if [ "$expected" != "$actual" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual: %s\n' "$message" "$expected" "$actual" >&2
        return 1
    fi
}

assert_file_exists() {
    if [ ! -f "$1" ]; then
        printf 'FAIL: expected file does not exist: %s\n' "$1" >&2
        return 1
    fi
}

cleanup_test_home() {
    if [ -n "${TEST_HOME:-}" ] && [ -d "$TEST_HOME" ]; then
        rm -rf "$TEST_HOME"
    fi
}

write_healthy_pi() {
    fixture_target=$1
    fixture_version=${2:-0.85.1}
    printf '%s\n' '#!/bin/sh' 'case "${1:-}" in' \
        "  --version) printf '%s\\n' '$fixture_version' ;;" \
        '  --help) printf "Usage: pi [options]\n  --help --version\n" ;;' \
        '  list) : ;;' \
        '  *) : ;;' 'esac' > "$fixture_target"
    chmod +x "$fixture_target"
}
