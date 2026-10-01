#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_dir/test_helpers.sh"
. "$script_dir/../lib/hac-pi-source.sh"

trap cleanup_test_home EXIT HUP INT TERM

fixture="$script_dir/fixtures/pi-package-0.85.1"

make_pi_source() {
    root=$1
    version=$2
    mkdir -p "$root/bin"
    printf '%s\n' '{"piVersion":"'"$version"'","executable":"bin/pi"}' > "$root/metadata.json"
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$root/bin/pi"
    chmod +x "$root/bin/pi"
}

test_default_source_is_not_required() {
    new_test_home
    unset HAC_PI_SOURCE
    assert_eq '@earendil-works/pi-coding-agent' "$(hac_pi_package_name)" package-name
    stub_command npm 'printf \"0.85.1\"\\n'
    assert_eq '0.85.1' "$(hac_pi_version)" package-version
}

test_local_source_precedes_package_download() {
    new_test_home
    source="$TEST_HOME/local-pi"
    make_pi_source "$source" 0.85.1
    HAC_PI_SOURCE="$source" hac_acquire_source 0.85.1 "$TEST_HOME/out"
    assert_file_exists "$TEST_HOME/out/metadata.json"
}

test_missing_local_source_fails() {
    new_test_home
    if HAC_PI_SOURCE="$TEST_HOME/missing" hac_acquire_source 0.85.1 "$TEST_HOME/out" >/dev/null 2>&1; then
        return 1
    fi
}

test_normalizes_npm_fixture() {
    new_test_home
    HAC_PI_PACKAGE_DIR="$fixture" hac_acquire_source 0.85.1 "$TEST_HOME/out"
    assert_file_exists "$TEST_HOME/out/metadata.json"
    assert_file_exists "$TEST_HOME/out/bin/pi"
    [ -x "$TEST_HOME/out/bin/pi" ]
    assert_eq '0.85.1' "$(jq -r .piVersion "$TEST_HOME/out/metadata.json")" normalized-version
    assert_eq 'bin/pi' "$(jq -r .executable "$TEST_HOME/out/metadata.json")" normalized-entrypoint
}

test_version_mismatch_is_rejected() {
    new_test_home
    if HAC_PI_PACKAGE_DIR="$fixture" hac_acquire_source 0.73.2 "$TEST_HOME/out" >/dev/null 2>&1; then
        return 1
    fi
}

test_missing_cli_entrypoint_is_rejected() {
    new_test_home
    broken="$TEST_HOME/broken"
    cp -R "$fixture" "$broken"
    rm "$broken/dist/cli.js"
    if HAC_PI_PACKAGE_DIR="$broken" hac_acquire_source 0.85.1 "$TEST_HOME/out" >/dev/null 2>&1; then
        return 1
    fi
}

test_symlink_package_is_rejected() {
    new_test_home
    ln -s "$fixture" "$TEST_HOME/package-link"
    if HAC_PI_PACKAGE_DIR="$TEST_HOME/package-link" hac_acquire_source 0.85.1 "$TEST_HOME/out" >/dev/null 2>&1; then
        return 1
    fi
}

test_no_global_npm_invocation() {
    new_test_home
    npm_log="$TEST_HOME/npm.log"
    stub_command npm 'printf "%s\n" "$*" >> "$NPM_LOG"; exit 99'
    NPM_LOG="$npm_log" HAC_PI_PACKAGE_DIR="$fixture" hac_acquire_source 0.85.1 "$TEST_HOME/out"
    [ ! -s "$npm_log" ]
}

test_automatic_npm_acquisition_is_pinned_and_local() {
    new_test_home
    npm_log="$TEST_HOME/npm.log"
    archive_dir="$TEST_HOME/archive"
    mkdir -p "$archive_dir"
    mkdir "$archive_dir/package"; cp -R "$fixture"/. "$archive_dir/package/"
    (cd "$archive_dir" && tar czf package.tgz package)
    stub_command npm 'printf "%s\n" "$*" >> "$NPM_LOG"
        destination=
        previous=
        for argument in "$@"; do
            if [ "$previous" = --pack-destination ]; then destination=$argument; fi
            previous=$argument
        done
        cp "$NPM_ARCHIVE" "$destination/pi.tgz"'
    NPM_LOG="$npm_log" NPM_ARCHIVE="$archive_dir/package.tgz" hac_acquire_source 0.85.1 "$TEST_HOME/out"
    assert_file_exists "$TEST_HOME/out/bin/pi"
    grep '^pack .*--ignore-scripts .*@earendil-works/pi-coding-agent@0.85.1 .*--pack-destination ' "$npm_log" >/dev/null
    ! grep 'install -g\|prefix' "$npm_log" >/dev/null
}

test_npm_failure_includes_remediation() {
    new_test_home
    stub_command npm 'exit 42'
    if hac_acquire_source 0.85.1 "$TEST_HOME/out" 2>"$TEST_HOME/error"; then return 1; fi
    grep '@earendil-works/pi-coding-agent@0.85.1' "$TEST_HOME/error" >/dev/null
    grep 'HAC_PI_SOURCE=' "$TEST_HOME/error" >/dev/null
}

make_npm_stub() {
    archive=$1
    stub_command npm 'printf "%s\n" "$*" >> "$NPM_LOG"
        destination=
        previous=
        for argument in "$@"; do
            if [ "$previous" = --pack-destination ]; then destination=$argument; fi
            previous=$argument
        done
        cp "$NPM_ARCHIVE" "$destination/pi.tgz"'
    NPM_LOG="$TEST_HOME/npm.log" NPM_ARCHIVE="$archive"
}

test_invalid_tarball_is_rejected() {
    new_test_home
    archive="$TEST_HOME/invalid.tgz"; printf '%s\n' invalid > "$archive"
    make_npm_stub "$archive"
    if NPM_LOG="$NPM_LOG" NPM_ARCHIVE="$NPM_ARCHIVE" hac_acquire_source 0.85.1 "$TEST_HOME/out" >/dev/null 2>"$TEST_HOME/error"; then return 1; fi
    grep -E 'invalid npm archive|could not extract.*@mariozechner/pi-coding-agent@0.85.1' "$TEST_HOME/error" >/dev/null
}

test_automatic_package_metadata_mismatch_is_rejected() {
    new_test_home
    archive_dir="$TEST_HOME/archive"; mkdir -p "$archive_dir/package"
    cp -R "$fixture"/. "$archive_dir/package/"
    printf '%s\n' '{"name":"@mariozechner/pi-coding-agent","version":"0.73.2","bin":{"pi":"dist/cli.js"}}' > "$archive_dir/package/package.json"
    (cd "$archive_dir" && tar czf package.tgz package)
    make_npm_stub "$archive_dir/package.tgz"
    if NPM_LOG="$NPM_LOG" NPM_ARCHIVE="$NPM_ARCHIVE" hac_acquire_source 0.85.1 "$TEST_HOME/out" >/dev/null 2>&1; then return 1; fi
}

test_automatic_package_missing_entrypoint_is_rejected() {
    new_test_home
    archive_dir="$TEST_HOME/archive"; mkdir -p "$archive_dir/package"
    cp -R "$fixture"/. "$archive_dir/package/"
    rm "$archive_dir/package/dist/cli.js"
    (cd "$archive_dir" && tar czf package.tgz package)
    make_npm_stub "$archive_dir/package.tgz"
    if NPM_LOG="$NPM_LOG" NPM_ARCHIVE="$NPM_ARCHIVE" hac_acquire_source 0.85.1 "$TEST_HOME/out" >/dev/null 2>&1; then return 1; fi
}

test_normalized_package_preserves_runtime_dependencies() {
    HAC_PI_PACKAGE_DIR="$fixture" hac_acquire_source 0.85.1 "$TEST_HOME/out"
    assert_file_exists "$TEST_HOME/out/package/package.json"
}

test_default_source_is_not_required
test_local_source_precedes_package_download
test_missing_local_source_fails
test_normalizes_npm_fixture
test_version_mismatch_is_rejected
test_missing_cli_entrypoint_is_rejected
test_symlink_package_is_rejected
test_no_global_npm_invocation
test_automatic_npm_acquisition_is_pinned_and_local
test_npm_failure_includes_remediation
test_invalid_tarball_is_rejected
test_automatic_package_metadata_mismatch_is_rejected
test_automatic_package_missing_entrypoint_is_rejected
test_normalized_package_preserves_runtime_dependencies
printf 'PASS: source contract\n'
