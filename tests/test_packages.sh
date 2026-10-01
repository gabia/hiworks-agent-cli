#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_dir/test_helpers.sh"
. "$script_dir/../lib/hac-env.sh"
. "$script_dir/../lib/hac-json.sh"
. "$script_dir/../lib/hac-resources.sh"
. "$script_dir/../lib/hac-packages.sh"

hac_script_root() { CDPATH= cd -- "$script_dir/.." && pwd -P; }
hac_manifest_path() { printf '%s/manifest/core.json\n' "$(hac_script_root)"; }

trap cleanup_test_home EXIT HUP INT TERM

manifest="$script_dir/../manifest/core.json"
fixture="$script_dir/fixtures/pi-list-0.85.1.txt"
required_source='npm:@example/required@1.2.3'

make_managed_pi() {
    root=$(hac_config_root)
    mkdir -p "$root/runtime/releases/pi-test/bin"
    printf '%s\n' '#!/bin/sh' \
        'case "${1:-}" in' \
        '  list) cat "$PI_CODING_AGENT_DIR/packages/pi-managed/list.txt" ;;' \
        '  install) printf "install|%s\n" "$2" >> "$PI_CODING_AGENT_DIR/packages/pi-managed/calls"; printf "%s\n" "$2" >> "$PI_CODING_AGENT_DIR/packages/pi-managed/list.txt" ;;' \
        '  *) printf "unexpected|%s\n" "$*" >> "$PI_CODING_AGENT_DIR/packages/pi-managed/calls"; exit 2 ;;' \
        'esac' > "$root/runtime/releases/pi-test/bin/pi"
    chmod +x "$root/runtime/releases/pi-test/bin/pi"
    printf '%s\n' '{"piVersion":"test","executable":"runtime/releases/pi-test/bin/pi","activatedAt":"2026-09-09T00:00:00Z"}' > "$(hac_active_file)"
    mkdir -p "$(hac_config_root)/packages/pi-managed"
    : > "$(hac_config_root)/packages/pi-managed/calls"
}

make_manifest() {
    sources=$1
    temporary=$(mktemp -d "${TMPDIR:-/tmp}/hac-package-manifest.XXXXXX")
    jq --argjson sources "$sources" '.packages = [$sources[] | {source: ., scope: "required"}]' "$manifest" > "$temporary/core.json"
    printf '%s\n' "$temporary/core.json"
}

test_missing_required_package_is_installed_exactly() {
    new_test_home
    hac_init_layout
    make_managed_pi
    manifest_path=$(make_manifest "[\"$required_source\"]")
    temporary=$(dirname "$manifest_path")
    : > "$(hac_config_root)/packages/pi-managed/list.txt"
    hac_reconcile_required_packages "$temporary/core.json"
    assert_eq "install|$required_source" "$(cat "$(hac_config_root)/packages/pi-managed/calls")" missing-required-install
    jq -e --arg source "$required_source" '.packages | index($source)' "$(hac_config_root)/packages/pi-managed/resolved.json" >/dev/null
    rm -rf "$temporary"
}

test_verified_pi_list_fixture_is_source_per_line() {
    new_test_home
    parsed=$(hac_parse_package_list "$fixture")
    assert_eq "$(cat "$fixture")" "$parsed" pi-0.85.1-list-contract
}

test_present_required_and_user_packages_are_untouched() {
    new_test_home
    hac_init_layout
    make_managed_pi
    manifest_path=$(make_manifest "[\"$required_source\"]")
    temporary=$(dirname "$manifest_path")
    printf '%s\n' "$required_source" 'npm:user-package@9.9.9' > "$(hac_config_root)/packages/pi-managed/list.txt"
    hac_reconcile_required_packages "$temporary/core.json"
    assert_eq '' "$(cat "$(hac_config_root)/packages/pi-managed/calls")" present-and-user-packages
    [ ! -e "$(hac_config_root)/packages/pi-managed/list-after" ]
    rm -rf "$temporary"
}

test_empty_pi_package_list_is_accepted() {
    new_test_home
    hac_init_layout
    make_managed_pi
    manifest_path=$(make_manifest '[]')
    printf '%s\n' 'No packages installed.' > "$(hac_config_root)/packages/pi-managed/list.txt"
    hac_reconcile_required_packages "$manifest_path"
    jq -e '.packages == []' "$(hac_config_root)/packages/pi-managed/resolved.json" >/dev/null
    rm -rf "$(dirname "$manifest_path")"
}

test_duplicate_required_sources_install_once_and_requery() {
    new_test_home
    hac_init_layout
    make_managed_pi
    manifest_path=$(make_manifest "[\"$required_source\",\"$required_source\"]")
    : > "$(hac_config_root)/packages/pi-managed/list.txt"
    hac_reconcile_required_packages "$manifest_path"
    assert_eq "install|$required_source" "$(cat "$(hac_config_root)/packages/pi-managed/calls")" duplicate-install
    rm -rf "$(dirname "$manifest_path")"
}

test_malformed_package_list_fails_and_cleans_temporary_state() {
    new_test_home
    hac_init_layout
    make_managed_pi
    manifest_path=$(make_manifest "[\"$required_source\"]")
    printf '%s\n' 'Installed packages:' > "$(hac_config_root)/packages/pi-managed/list.txt"
    if hac_reconcile_required_packages "$manifest_path" >/dev/null 2>&1; then return 1; fi
    [ ! -e "$(hac_config_root)/packages/pi-managed/resolved.json" ]
    [ -z "$(find "$(hac_config_root)/packages/pi-managed" -name '.packages.*' -print)" ]
    rm -rf "$(dirname "$manifest_path")"
}

test_install_verification_failure_does_not_record_resolution() {
    new_test_home
    hac_init_layout
    make_managed_pi
    manifest_path=$(make_manifest "[\"$required_source\"]")
    printf '%s\n' 'other-package' > "$(hac_config_root)/packages/pi-managed/list.txt"
    if hac_reconcile_required_packages "$manifest_path" >/dev/null 2>&1; then return 1; fi
    [ ! -e "$(hac_config_root)/packages/pi-managed/resolved.json" ]
    rm -rf "$(dirname "$manifest_path")"
}

test_forwarding_uses_managed_pi_and_preserves_arguments() {
    new_test_home
    hac_init_layout
    make_managed_pi
    : > "$(hac_config_root)/packages/pi-managed/list.txt"
    printf '%s\n' '#!/bin/sh' 'printf system >&2; exit 99' > "$TEST_HOME/system-pi"
    chmod +x "$TEST_HOME/system-pi"
    PATH="$TEST_HOME:$PATH"
    export PATH
    if output=$(hac_forward_pi 'arg with spaces' '--flag=value'); then
        return 1
    else
        status=$?
    fi
    assert_eq "unexpected|arg with spaces --flag=value --extension $(hac_script_root)/resources/hac-branding/hiworks-theme.mjs" "$(cat "$(hac_config_root)/packages/pi-managed/calls")" forwarded-to-managed
    assert_eq 2 "$status" forwarding-status
}

test_bin_hac_pi_forwards_to_managed_executable() {
    new_test_home
    hac_init_layout
    make_managed_pi
    PATH="$TEST_HOME/bin:$PATH"
    export PATH
    if "$script_dir/../bin/hac" pi 'actual launcher argument' >/dev/null 2>&1; then
        return 1
    else
        status=$?
    fi
    assert_eq 2 "$status" bin-forward-status
    assert_eq "unexpected|actual launcher argument --extension $(CDPATH= cd -- "$script_dir/.." && pwd -P)/resources/hac-branding/hiworks-theme.mjs" "$(cat "$(hac_config_root)/packages/pi-managed/calls")" bin-forward-target
}

test_missing_required_package_is_installed_exactly
test_verified_pi_list_fixture_is_source_per_line
test_present_required_and_user_packages_are_untouched
test_empty_pi_package_list_is_accepted
test_duplicate_required_sources_install_once_and_requery
test_malformed_package_list_fails_and_cleans_temporary_state
test_install_verification_failure_does_not_record_resolution
test_bin_hac_pi_forwards_to_managed_executable
test_forwarding_uses_managed_pi_and_preserves_arguments
printf 'PASS: packages contract\n'
