#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_dir/test_helpers.sh"
trap cleanup_test_home EXIT HUP INT TERM

make_pi_source() {
    source=$1
    version=${2:-0.85.1}
    mkdir -p "$source/bin"
    write_healthy_pi "$source/bin/pi" "$version"
    chmod +x "$source/bin/pi"
    printf '%s\n' "{\"piVersion\":\"$version\",\"executable\":\"bin/pi\"}" > "$source/metadata.json"
}
make_pi_metadata() {
    source=$1
    metadata=$2
    printf '%s\n' "$metadata" > "$source/metadata.json"
}
make_core_source() {
    source=$1
    mkdir -p "$source/skills/hiworks-development" "$source/extensions" "$source/prompts" "$source/agents" "$source/mcp"
    cp "$script_dir/../manifest/core.json" "$source/manifest.json"
    printf '%s\n' core > "$source/skills/hiworks-development/SKILL.md"
    for directory in extensions prompts agents mcp; do printf '%s\n' core > "$source/$directory/README.md"; done
}
stub_platform() {
    stub_command uname "case \"\${1:-}\" in -s) printf '%s\\n' '$1' ;; -m) printf '%s\\n' '$2' ;; esac"
}
stub_node() {
    stub_command node "printf '%s\\n' 'v20.11.1'"
    stub_command npm "printf '%s\\n' 'npm-called' >> \"$TEST_HOME/npm.log\""
}
run_install() {
    pi=$1; core=$2; root=$3; bin=$4; version=${5:-0.85.1}; option=${6:-}
    HAC_PI_SOURCE=$pi HAC_CORE_SOURCE=$core HAC_INSTALL_ROOT=$root HAC_BIN_DIR=$bin HAC_PI_VERSION=$version \
        "$script_dir/../install.sh" "$option"
}
stub_failing_publication_mv() {
    stub_command mv 'case "${1:-}" in *.hac-stage.*) exit 73 ;; esac; exec /bin/mv "$@"'
}
stub_failing_launcher_publication_mv() {
    stub_command mv 'case "${1:-}" in *.launcher) exit 74 ;; esac; exec /bin/mv "$@"'
}

test_supported_install_preserves_system_pi() {
    new_test_home; stub_platform Darwin arm64; stub_node
    pi=$TEST_HOME/pi; core=$TEST_HOME/core; make_pi_source "$pi"; make_core_source "$core"
    system_pi=$TEST_HOME/system-pi; printf '%s\n' unchanged > "$system_pi"; before=$(cksum "$system_pi")
    run_install "$pi" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" >/dev/null
    assert_file_exists "$TEST_HOME/bin/hac"; assert_eq "$before" "$(cksum "$system_pi")" system-pi-preserved
    cmp "$script_dir/../LICENSE" "$TEST_HOME/share/hac/LICENSE"
    cmp "$script_dir/../THIRD_PARTY_NOTICES.md" "$TEST_HOME/share/hac/THIRD_PARTY_NOTICES.md"
    cmp "$script_dir/../resources/hac-branding/LICENSE" "$TEST_HOME/share/hac/resources/hac-branding/LICENSE"
    cmp "$script_dir/../resources/licenses/pi.LICENSE" "$TEST_HOME/share/hac/resources/licenses/pi.LICENSE"
    [ ! -e "$TEST_HOME/npm.log" ]
}

test_default_core_source_contains_manifest() {
    assert_file_exists "$script_dir/../resources/hiworks-core/manifest.json"
    jq -e '.coreVersion == "1.0.0"' "$script_dir/../resources/hiworks-core/manifest.json" >/dev/null
}

test_automatic_install_uses_package_local_npm() {
    new_test_home; stub_platform Linux x86_64
    stub_command node "printf '%s\\n' 'v20.11.1'"
    archive_dir="$TEST_HOME/archive"; fixture="$script_dir/fixtures/pi-package-0.85.1"
    mkdir -p "$archive_dir"
    mkdir "$archive_dir/package"; cp -R "$fixture"/. "$archive_dir/package/"
    (cd "$archive_dir" && tar czf package.tgz package)
    stub_command npm 'if [ "${1:-}" = view ]; then printf '\''"0.85.1"\n'\''; exit 0; fi
printf "%s\n" "$*" >> "$NPM_LOG"
        destination=
        previous=
        for argument in "$@"; do
            if [ "$previous" = --pack-destination ]; then destination=$argument; fi
            previous=$argument
        done
        cp "$NPM_ARCHIVE" "$destination/pi.tgz"'
    core=$TEST_HOME/core; make_core_source "$core"
    NPM_LOG="$TEST_HOME/npm.log" NPM_ARCHIVE="$archive_dir/package.tgz" \
        HAC_CORE_SOURCE="$core" HAC_INSTALL_ROOT="$TEST_HOME/share/hac" HAC_BIN_DIR="$TEST_HOME/bin" \
        "$script_dir/../install.sh" >/dev/null
    [ -x "$TEST_HOME/bin/hac" ]
    grep '^pack .*--ignore-scripts .*@earendil-works/pi-coding-agent@0.85.1 .*--pack-destination ' "$TEST_HOME/npm.log" >/dev/null
    ! grep 'install -g\|prefix' "$TEST_HOME/npm.log" >/dev/null
}

test_automatic_acquisition_failure_preserves_existing_install() {
    new_test_home; stub_platform Linux x86_64; stub_node
    pi=$TEST_HOME/pi; core=$TEST_HOME/core; make_pi_source "$pi"; make_core_source "$core"
    run_install "$pi" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" >/dev/null
    launcher=$(cksum "$TEST_HOME/bin/hac"); runtime=$(cksum "$TEST_HOME/share/hac/bin/hac")
    unset HAC_PI_SOURCE
    stub_command npm 'if [ "${1:-}" = view ]; then printf '\''"0.85.1"\n'\''; exit 0; fi
exit 17'
    if HAC_CORE_SOURCE="$core" HAC_INSTALL_ROOT="$TEST_HOME/share/hac" HAC_BIN_DIR="$TEST_HOME/bin" \
        "$script_dir/../install.sh" >/dev/null 2>"$TEST_HOME/error"; then return 1; fi
    assert_eq "$launcher" "$(cksum "$TEST_HOME/bin/hac")" launcher-preserved
    assert_eq "$runtime" "$(cksum "$TEST_HOME/share/hac/bin/hac")" runtime-preserved
}

test_automatic_normalization_failure_preserves_existing_install() {
    new_test_home; stub_platform Linux x86_64; stub_node
    pi=$TEST_HOME/pi; core=$TEST_HOME/core; make_pi_source "$pi"; make_core_source "$core"
    run_install "$pi" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" >/dev/null
    launcher=$(cksum "$TEST_HOME/bin/hac"); runtime=$(cksum "$TEST_HOME/share/hac/bin/hac")
    unset HAC_PI_SOURCE
    archive_dir=$TEST_HOME/archive; mkdir -p "$archive_dir/package"
    printf '%s\n' '{"name":"@mariozechner/pi-coding-agent","version":"0.85.1","bin":{"pi":"dist/cli.js"}}' > "$archive_dir/package/package.json"
    (cd "$archive_dir" && tar czf package.tgz package)
    stub_command npm 'if [ "${1:-}" = view ]; then printf '\''"0.85.1"\n'\''; exit 0; fi
destination=
previous=
for argument in "$@"; do
    if [ "$previous" = --pack-destination ]; then destination=$argument; fi
    previous=$argument
done
cp "$NPM_ARCHIVE" "$destination/pi.tgz"'
    if NPM_ARCHIVE="$archive_dir/package.tgz" HAC_CORE_SOURCE="$core" HAC_INSTALL_ROOT="$TEST_HOME/share/hac" HAC_BIN_DIR="$TEST_HOME/bin" \
        "$script_dir/../install.sh" >/dev/null 2>"$TEST_HOME/error"; then return 1; fi
    assert_eq "$launcher" "$(cksum "$TEST_HOME/bin/hac")" launcher-preserved-after-normalization
    assert_eq "$runtime" "$(cksum "$TEST_HOME/share/hac/bin/hac")" runtime-preserved-after-normalization
}

test_failed_install_preserves_full_managed_state() {
    new_test_home; stub_platform Linux x86_64; stub_node
    pi=$TEST_HOME/pi; core=$TEST_HOME/core; make_pi_source "$pi"; make_core_source "$core"
    run_install "$pi" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" >/dev/null
    HAC_PI_SOURCE="$pi" HAC_PI_VERSION=0.85.1 HAC_CORE_SOURCE="$core" HAC_INSTALL_ROOT="$TEST_HOME/share/hac" HAC_BIN_DIR="$TEST_HOME/bin" \
        "$TEST_HOME/bin/hac" install >/dev/null
    config="$TEST_HOME/.config/hiworks-agent-cli"
    mkdir -p "$config/sessions" "$config/packages/pi-managed"
    printf user > "$config/credentials"; printf session > "$config/sessions/saved"; printf package > "$config/packages/pi-managed/user"
    active=$(cksum "$config/runtime/active.json"); release=$(cksum "$config/runtime/releases/pi-0.85.1/metadata.json")
    core_file=$(cksum "$config/resources/hiworks-core-1.0.0/manifest.json"); launcher=$(cksum "$TEST_HOME/bin/hac")
    bad=$TEST_HOME/bad; mkdir -p "$bad"; printf '%s\n' '{"piVersion":"0.85.1","executable":"bin/missing"}' > "$bad/metadata.json"
    if HAC_PI_SOURCE="$bad" HAC_PI_VERSION=0.85.1 HAC_CORE_SOURCE="$core" HAC_INSTALL_ROOT="$TEST_HOME/share/hac" HAC_BIN_DIR="$TEST_HOME/bin" \
        "$script_dir/../install.sh" >/dev/null 2>&1; then return 1; fi
    assert_eq "$active" "$(cksum "$config/runtime/active.json")" active-preserved
    assert_eq "$release" "$(cksum "$config/runtime/releases/pi-0.85.1/metadata.json")" release-preserved
    assert_eq "$core_file" "$(cksum "$config/resources/hiworks-core-1.0.0/manifest.json")" core-preserved
    assert_eq "$launcher" "$(cksum "$TEST_HOME/bin/hac")" launcher-preserved
    assert_eq user "$(cat "$config/credentials")" credentials-preserved
    assert_eq session "$(cat "$config/sessions/saved")" sessions-preserved
    assert_eq package "$(cat "$config/packages/pi-managed/user")" packages-preserved
}

test_hac_pi_version_override_is_rejected() {
    new_test_home; stub_platform Linux x86_64; stub_node
    core=$TEST_HOME/core; make_core_source "$core"
    if HAC_PI_VERSION=invalid HAC_CORE_SOURCE="$core" HAC_INSTALL_ROOT="$TEST_HOME/share/hac" HAC_BIN_DIR="$TEST_HOME/bin" \
        "$script_dir/../install.sh" >/dev/null 2>"$TEST_HOME/error"; then return 1; fi
    grep 'unable to query latest\|stable Pi version' "$TEST_HOME/error" >/dev/null
}
test_reinstall_is_repeatable() {
    new_test_home; stub_platform Linux x86_64; stub_node
    pi=$TEST_HOME/pi; core=$TEST_HOME/core; make_pi_source "$pi"; make_core_source "$core"
    run_install "$pi" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" >/dev/null
    first=$(cksum "$TEST_HOME/bin/hac"); run_install "$pi" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" >/dev/null
    assert_eq "$first" "$(cksum "$TEST_HOME/bin/hac")" repeat-install
}
test_rejects_unsupported_platform() {
    new_test_home; stub_platform FreeBSD x86_64; stub_node
    if "$script_dir/../install.sh" >/dev/null 2>"$TEST_HOME/error"; then return 1; fi
    grep 'unsupported platform' "$TEST_HOME/error" >/dev/null
}
test_missing_node_fails_closed() {
    new_test_home; stub_platform Linux aarch64; stub_command node 'exit 127'; stub_command npm 'if [ "${1:-}" = view ]; then printf '\''"0.85.1"\n'\''; exit 0; fi
exit 127'
    if "$script_dir/../install.sh" >/dev/null 2>"$TEST_HOME/error"; then return 1; fi
    grep 'Node.js 20.6.0 or newer' "$TEST_HOME/error" >/dev/null
}
test_metadata_version_must_match_requested_version() {
    new_test_home; stub_platform Linux arm64; stub_node
    pi=$TEST_HOME/pi; core=$TEST_HOME/core; make_pi_source "$pi" 0.85.1; make_core_source "$core"
    if run_install "$pi" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" 0.73.2 >/dev/null 2>"$TEST_HOME/error"; then return 1; fi
    grep 'version mismatch' "$TEST_HOME/error" >/dev/null; [ ! -e "$TEST_HOME/share/hac" ]
}
test_failed_install_preserves_existing_runtime_and_launcher() {
    new_test_home; stub_platform Linux x86_64; stub_node
    pi=$TEST_HOME/pi; core=$TEST_HOME/core; make_pi_source "$pi"; make_core_source "$core"
    run_install "$pi" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" >/dev/null
    launcher=$(cksum "$TEST_HOME/bin/hac"); runtime=$(cksum "$TEST_HOME/share/hac/bin/hac")
    bad=$TEST_HOME/bad; mkdir -p "$bad/bin"; printf '%s\n' '{"piVersion":"0.85.1","executable":"bin/missing"}' > "$bad/metadata.json"
    if run_install "$bad" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" >/dev/null 2>"$TEST_HOME/error"; then return 1; fi
    assert_eq "$launcher" "$(cksum "$TEST_HOME/bin/hac")" launcher-preserved; assert_eq "$runtime" "$(cksum "$TEST_HOME/share/hac/bin/hac")" runtime-preserved
    grep 'executable must be bin/pi' "$TEST_HOME/error" >/dev/null
}
test_optional_install_control() {
    new_test_home; stub_platform Darwin x86_64; stub_node
    pi=$TEST_HOME/pi; core=$TEST_HOME/core; make_pi_source "$pi"; make_core_source "$core"
    run_install "$pi" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" >/dev/null; [ ! -e "$TEST_HOME/share/hac/runtime/active.json" ]; [ ! -e "$TEST_HOME/npm.log" ]
    run_install "$pi" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" 0.85.1 --install >/dev/null; [ -f "$TEST_HOME/.config/hiworks-agent-cli/runtime/active.json" ]; [ ! -e "$TEST_HOME/npm.log" ]
}
test_architecture_aliases() {
    for os in Darwin Linux; do for arch in arm64 aarch64 x64 x86_64; do
        new_test_home; stub_platform "$os" "$arch"; stub_node; pi=$TEST_HOME/pi; core=$TEST_HOME/core; make_pi_source "$pi"; make_core_source "$core"
        if [ "$os:$arch" = Darwin:aarch64 ]; then
            if run_install "$pi" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" >/dev/null; then return 1; fi
        else
            run_install "$pi" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" >/dev/null
        fi
    done; done
}
test_doctor_platform_aliases_match_installer() {
    for os in Darwin Linux; do for arch in arm64 aarch64 x64 x86_64; do
        new_test_home; stub_platform "$os" "$arch"; stub_node
        output=$({ "$script_dir/../bin/hac" doctor || :; } 2>/dev/null)
        if [ "$os:$arch" = Darwin:aarch64 ]; then
            printf '%s\n' "$output" | grep '^platform=unsupported$' >/dev/null
        else
            printf '%s\n' "$output" | grep '^platform=ok$' >/dev/null
        fi
    done; done
}
test_paths_with_metacharacters() {
    new_test_home; stub_platform Linux x86_64; stub_node; pi=$TEST_HOME/pi; core=$TEST_HOME/core; make_pi_source "$pi"; make_core_source "$core"
    root="$TEST_HOME/share;touch HACK"; bin="$TEST_HOME/bin with space"; run_install "$pi" "$core" "$root" "$bin" >/dev/null
    [ -x "$bin/hac" ]; [ ! -e "$TEST_HOME/HACK" ]
}
test_source_metadata_executable_is_validated_before_publish() {
    for metadata in '{"piVersion":"0.85.1"}' '{"piVersion":"0.85.1","executable":"../bin/pi"}' '{"piVersion":"0.85.1","executable":"bin/outside"}'; do
        new_test_home; stub_platform Linux x86_64; stub_node
        pi=$TEST_HOME/pi; core=$TEST_HOME/core; make_pi_source "$pi"; make_core_source "$core"; make_pi_metadata "$pi" "$metadata"
        if run_install "$pi" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" >/dev/null 2>"$TEST_HOME/error"; then return 1; fi
        [ ! -e "$TEST_HOME/share/hac" ]
    done
}
test_source_metadata_symlink_escape_is_rejected() {
    new_test_home; stub_platform Linux x86_64; stub_node
    pi=$TEST_HOME/pi; core=$TEST_HOME/core; make_pi_source "$pi"; make_core_source "$core"
    outside=$TEST_HOME/outside; printf '%s\n' '#!/bin/sh' 'exit 0' > "$outside"; chmod +x "$outside"
    rm "$pi/bin/pi"; ln -s "$outside" "$pi/bin/pi"
    if run_install "$pi" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" >/dev/null 2>"$TEST_HOME/error"; then return 1; fi
    grep 'symlink' "$TEST_HOME/error" >/dev/null; [ ! -e "$TEST_HOME/share/hac" ]
}
test_launcher_quotes_all_path_characters() {
    new_test_home; stub_platform Linux x86_64; stub_node
    pi=$TEST_HOME/pi; core=$TEST_HOME/core; make_pi_source "$pi"; make_core_source "$core"
    root="$TEST_HOME/root ' \; \$(touch BAD)"; bin="$TEST_HOME/bin ' \; \$(touch BAD)"
    run_install "$pi" "$core" "$root" "$bin" >/dev/null
    [ ! -e "$TEST_HOME/BAD" ]; [ -x "$bin/hac" ]; "$bin/hac" version >/dev/null
}
test_publication_failure_restores_old_runtime_and_launcher() {
    new_test_home; stub_platform Linux x86_64; stub_node
    pi=$TEST_HOME/pi; core=$TEST_HOME/core; make_pi_source "$pi"; make_core_source "$core"
    run_install "$pi" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" >/dev/null
    old_root=$(cksum "$TEST_HOME/share/hac/bin/hac"); old_launcher=$(cksum "$TEST_HOME/bin/hac")
    stub_failing_publication_mv
    run_install "$pi" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" >/dev/null 2>"$TEST_HOME/error" || :
    assert_eq "$old_root" "$(cksum "$TEST_HOME/share/hac/bin/hac")" publication-root-restored
    assert_eq "$old_launcher" "$(cksum "$TEST_HOME/bin/hac")" publication-launcher-restored
    for artifact in "$TEST_HOME"/share/hac.previous.* "$TEST_HOME"/bin/hac.previous.*; do [ ! -e "$artifact" ]; done
}
test_install_publication_failure_preserves_full_managed_state() {
    new_test_home; stub_platform Linux x86_64; stub_node
    pi=$TEST_HOME/pi; core=$TEST_HOME/core; make_pi_source "$pi"; make_core_source "$core"
    stub_command mv 'exec /bin/mv "$@"'
    run_install "$pi" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" >/dev/null
    HAC_PI_SOURCE="$pi" HAC_CORE_SOURCE="$core" HAC_INSTALL_ROOT="$TEST_HOME/share/hac" HAC_BIN_DIR="$TEST_HOME/bin" "$TEST_HOME/bin/hac" install >/dev/null
    config="$TEST_HOME/.config/hiworks-agent-cli"
    mkdir -p "$config/sessions" "$config/packages/pi-managed"
    printf user > "$config/credentials"; printf session > "$config/sessions/saved"; printf package > "$config/packages/pi-managed/user"
    managed_before=$(cksum "$config/runtime/active.json")
    credentials_before=$(cksum "$config/credentials")
    launcher_before=$(cksum "$TEST_HOME/bin/hac")
    runtime_before=$(cksum "$TEST_HOME/share/hac/bin/hac")
    stub_failing_launcher_publication_mv
    if run_install "$pi" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" 0.85.1 --install >/dev/null 2>"$TEST_HOME/error"; then return 1; fi
    assert_eq "$managed_before" "$(cksum "$config/runtime/active.json")" managed-state-preserved
    assert_eq "$credentials_before" "$(cksum "$config/credentials")" credentials-state-preserved
    assert_eq "$launcher_before" "$(cksum "$TEST_HOME/bin/hac")" launcher-state-preserved
    assert_eq "$runtime_before" "$(cksum "$TEST_HOME/share/hac/bin/hac")" runtime-state-preserved
    for artifact in "$TEST_HOME"/share/hac.previous.* "$TEST_HOME"/.config/hiworks-agent-cli.previous.* "$TEST_HOME"/bin/hac.previous.*; do [ ! -e "$artifact" ]; done
}
test_explicit_source_does_not_require_npm() {
    new_test_home; stub_platform Linux x86_64; stub_command node "printf '%s\\n' 'v20.11.1'"
    pi=$TEST_HOME/pi; core=$TEST_HOME/core; make_pi_source "$pi"; make_core_source "$core"
    stub_command mv 'exec /bin/mv "$@"'
    stub_command npm 'if [ "${1:-}" = view ]; then printf '\''"0.85.1"\n'\''; exit 0; fi
exit 99'
    run_install "$pi" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" >/dev/null
    [ ! -e "$TEST_HOME/share/hac/.npm" ]
}
test_source_copy_failure_does_not_publish() {
    new_test_home; stub_platform Linux x86_64; stub_node
    pi=$TEST_HOME/pi; core=$TEST_HOME/core; make_pi_source "$pi"; make_core_source "$core"
    touch "$TEST_HOME/fail-copy"
    stub_command cp 'if [ -e "$TEST_HOME/fail-copy" ]; then exit 75; fi; exec /bin/cp "$@"'
    if run_install "$pi" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" >/dev/null 2>"$TEST_HOME/error"; then return 1; fi
    [ ! -e "$TEST_HOME/share/hac" ]; [ ! -e "$TEST_HOME/bin/hac" ]
}
test_no_install_rejects_invalid_entrypoint() {
    new_test_home; stub_platform Linux x86_64; stub_node
    pi=$TEST_HOME/pi; core=$TEST_HOME/core; make_pi_source "$pi"; make_core_source "$core"
    make_pi_metadata "$pi" '{"piVersion":"0.85.1","executable":"bin/not-pi"}'
    if run_install "$pi" "$core" "$TEST_HOME/share/hac" "$TEST_HOME/bin" >/dev/null 2>"$TEST_HOME/error"; then return 1; fi
    grep 'executable must be bin/pi' "$TEST_HOME/error" >/dev/null
    [ ! -e "$TEST_HOME/share/hac" ]
}
test_smoke_uses_deterministic_automatic_fixture() {
    smoke_home=$(mktemp -d "${TMPDIR:-/tmp}/hac-smoke-test.XXXXXX")
    output=$(HOME="$smoke_home" HAC_SMOKE_NPM_FIXTURE="$script_dir/fixtures/pi-package-0.85.1" sh "$script_dir/smoke.sh")
    rm -rf "$smoke_home"
    printf '%s\n' "$output" | grep '^PASS: automatic Pi smoke test$' >/dev/null
}
test_smoke_reports_prerequisite_skip() {
    smoke_home=$(mktemp -d "${TMPDIR:-/tmp}/hac-smoke-skip.XXXXXX")
    output=$(HOME="$smoke_home" HAC_SMOKE_NPM_FIXTURE="$smoke_home/missing-fixture" sh "$script_dir/smoke.sh")
    rm -rf "$smoke_home"
    printf '%s\n' "$output" | grep '^SKIP: Pi smoke test: npm fixture is unavailable' >/dev/null
}
test_smoke_runs_explicit_source_mode() {
    new_test_home
    pi=$TEST_HOME/pi; core=$TEST_HOME/core
    make_pi_source "$pi"; make_core_source "$core"
    node_bin_dir=$(dirname -- "$HAC_TEST_REAL_NODE")
    output=$(PATH="$node_bin_dir:/opt/homebrew/bin:/usr/bin:/bin" HOME="$TEST_HOME" HAC_PI_SOURCE="$pi" HAC_CORE_SOURCE="$core" sh "$script_dir/smoke.sh")
    printf '%s\n' "$output" | grep '^PASS: explicit-source Pi smoke test$' >/dev/null
}
test_smoke_preserves_install_on_npm_failure() {
    new_test_home
    output=$(HOME="$TEST_HOME" HAC_SMOKE_NPM_FAILURE=1 sh "$script_dir/smoke.sh")
    printf '%s\n' "$output" | grep '^PASS: npm-failure Pi smoke test$' >/dev/null
}
test_default_core_source_contains_manifest
test_supported_install_preserves_system_pi
test_automatic_install_uses_package_local_npm
test_automatic_acquisition_failure_preserves_existing_install
test_automatic_normalization_failure_preserves_existing_install
test_failed_install_preserves_full_managed_state
test_hac_pi_version_override_is_rejected
test_reinstall_is_repeatable
test_rejects_unsupported_platform
test_missing_node_fails_closed
test_metadata_version_must_match_requested_version
test_failed_install_preserves_existing_runtime_and_launcher
test_optional_install_control
test_architecture_aliases
test_doctor_platform_aliases_match_installer
test_paths_with_metacharacters
test_source_metadata_executable_is_validated_before_publish
test_source_metadata_symlink_escape_is_rejected
test_launcher_quotes_all_path_characters
test_publication_failure_restores_old_runtime_and_launcher
test_install_publication_failure_preserves_full_managed_state
test_explicit_source_does_not_require_npm
test_source_copy_failure_does_not_publish
test_no_install_rejects_invalid_entrypoint
test_smoke_uses_deterministic_automatic_fixture
test_smoke_reports_prerequisite_skip
test_smoke_runs_explicit_source_mode
test_smoke_preserves_install_on_npm_failure
printf '%s\n' 'PASS: installer contract'
