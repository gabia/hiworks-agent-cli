#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_dir/test_helpers.sh"
. "$script_dir/../lib/hac-env.sh"
. "$script_dir/../lib/hac-json.sh"

trap cleanup_test_home EXIT HUP INT TERM

make_pi_source() {
    source=$1
    version=$2
    mkdir -p "$source/bin"
    printf '%s\n' '#!/bin/sh' \
        'case "${1:-}" in' \
        "  --version) printf '%s\\n' '$version' ;;" \
        '  --help) printf "Usage: pi [options]\n  --help --version\n" ;;' \
        '  list) cat "$PI_CODING_AGENT_DIR/packages/pi-managed/list.txt" 2>/dev/null || : ;;' \
        '  install) printf "%s\n" "$2" >> "$PI_CODING_AGENT_DIR/packages/pi-managed/list.txt" ;;' \
        '  *) printf "pi:%s\n" "$*" ;;' \
        'esac' > "$source/bin/pi"
    chmod +x "$source/bin/pi"
    printf '%s\n' "{\"piVersion\":\"$version\",\"executable\":\"bin/pi\"}" > "$source/metadata.json"
}

make_core_source() {
    source=$1
    mkdir -p "$source/skills/hiworks-development" "$source/extensions" \
        "$source/prompts" "$source/agents" "$source/mcp"
    cp "$script_dir/../manifest/core.json" "$source/manifest.json"
    printf '%s\n' core > "$source/skills/hiworks-development/SKILL.md"
    for directory in extensions prompts agents mcp; do
        printf '%s\n' core > "$source/$directory/README.md"
    done
}

stub_automatic_npm() {
    archive=$1
    stub_command npm 'if [ "${1:-}" = view ]; then printf '\''"0.85.1"\n'\''; exit 0; fi
destination=
previous=
for argument in "$@"; do
    if [ "$previous" = --pack-destination ]; then destination=$argument; fi
    previous=$argument
done
printf "%s|%s\n" "$*" "$destination" >> "$NPM_LOG"
cp "$NPM_ARCHIVE" "$destination/pi.tgz"'
    NPM_ARCHIVE=$archive
    NPM_LOG=$TEST_HOME/npm.log
    export NPM_ARCHIVE NPM_LOG
}

configure_sources() {
    HAC_PI_SOURCE=$1
    HAC_PI_VERSION=$2
    HAC_CORE_SOURCE=$3
    export HAC_PI_SOURCE HAC_PI_VERSION HAC_CORE_SOURCE
}

test_dispatch_and_stable_failure() {
    new_test_home
    if "$script_dir/../bin/hac" unknown >/dev/null 2>&1; then return 1; else status=$?; fi
    assert_eq 2 "$status" dispatch-status
}

test_first_install_failure_is_actionable() {
    new_test_home
    stub_command npm 'exit 127'
    if "$script_dir/../bin/hac" >/dev/null 2>"$TEST_HOME/error"; then return 1; else status=$?; fi
    assert_eq 1 "$status" first-install-status
    grep 'unable to query latest Pi' "$TEST_HOME/error" >/dev/null
}

test_install_preserves_user_state_and_activates() {
    new_test_home
    pi_source=$TEST_HOME/pi
    core_source=$TEST_HOME/core
    make_pi_source "$pi_source" 0.85.1
    make_core_source "$core_source"
    configure_sources "$pi_source" 0.85.1 "$core_source"
    hac_root="$TEST_HOME/.config/hiworks-agent-cli"
    mkdir -p "$hac_root/sessions"
    printf '%s\n' settings > "$hac_root/settings.json"
    printf '%s\n' auth > "$hac_root/auth.json"
    printf '%s\n' models > "$hac_root/models.json"
    printf '%s\n' session > "$hac_root/sessions/session"
    "$script_dir/../bin/hac" install >/dev/null
    assert_eq settings "$(cat "$hac_root/settings.json")" settings-preserved
    assert_eq auth "$(cat "$hac_root/auth.json")" auth-preserved
    assert_eq models "$(cat "$hac_root/models.json")" models-preserved
    assert_eq session "$(cat "$hac_root/sessions/session")" sessions-preserved
    assert_eq 0.85.1 "$(jq -r .piVersion "$hac_root/runtime/active.json")" installed-version
}

test_update_failure_preserves_active_and_startup_falls_back() {
    new_test_home
    pi_source=$TEST_HOME/pi
    core_source=$TEST_HOME/core
    make_pi_source "$pi_source" 0.85.1
    make_core_source "$core_source"
    configure_sources "$pi_source" 0.85.1 "$core_source"
    "$script_dir/../bin/hac" install >/dev/null
    before=$(cat "$(hac_config_root)/runtime/active.json")
    bad_source=$TEST_HOME/bad
    mkdir -p "$bad_source"
    HAC_PI_SOURCE=$bad_source HAC_PI_VERSION=0.73.2 export HAC_PI_SOURCE HAC_PI_VERSION
    if "$script_dir/../bin/hac" update >/dev/null 2>&1; then return 1; fi
    assert_eq "$before" "$(cat "$(hac_config_root)/runtime/active.json")" update-preserved
    "$script_dir/../bin/hac" >/dev/null
}

test_version_and_doctor_report_contract() {
    new_test_home
    pi_source=$TEST_HOME/pi
    core_source=$TEST_HOME/core
    make_pi_source "$pi_source" 0.85.1
    make_core_source "$core_source"
    configure_sources "$pi_source" 0.85.1 "$core_source"
    "$script_dir/../bin/hac" install >/dev/null
    output=$("$script_dir/../bin/hac" version)
    printf '%s\n' "$output" | grep '^hacVersion=' >/dev/null
    printf '%s\n' "$output" | grep '^piVersion=0.85.1$' >/dev/null
    "$script_dir/../bin/hac" doctor >/dev/null
}

test_pi_forwarding_preserves_arguments() {
    new_test_home
    pi_source=$TEST_HOME/pi
    core_source=$TEST_HOME/core
    make_pi_source "$pi_source" 0.85.1
    make_core_source "$core_source"
    configure_sources "$pi_source" 0.85.1 "$core_source"
    "$script_dir/../bin/hac" install >/dev/null
    assert_eq "pi:arg with spaces --flag=value --extension $(CDPATH= cd -- "$script_dir/.." && pwd -P)/resources/hac-branding/hiworks-theme.mjs --skill $(hac_config_root)/resources/hiworks-core-1.0.0/skills/hiworks-development" "$($script_dir/../bin/hac pi 'arg with spaces' '--flag=value')" pi-forwarding
}

test_continue_resumes_latest_session() {
    new_test_home
    pi_source=$TEST_HOME/pi
    core_source=$TEST_HOME/core
    make_pi_source "$pi_source" 0.85.1
    make_core_source "$core_source"
    configure_sources "$pi_source" 0.85.1 "$core_source"
    "$script_dir/../bin/hac" install >/dev/null
    suffix="--extension $(CDPATH= cd -- "$script_dir/.." && pwd -P)/resources/hac-branding/hiworks-theme.mjs --skill $(hac_config_root)/resources/hiworks-core-1.0.0/skills/hiworks-development"
    assert_eq "pi:--continue $suffix" "$($script_dir/../bin/hac --continue)" continue-long
    assert_eq "pi:--continue $suffix" "$($script_dir/../bin/hac -c)" continue-short
}

test_install_repairs_corrupt_active_state() {
    new_test_home
    pi_source=$TEST_HOME/pi; core_source=$TEST_HOME/core
    make_pi_source "$pi_source" 0.85.1; make_core_source "$core_source"
    configure_sources "$pi_source" 0.85.1 "$core_source"
    "$script_dir/../bin/hac" install >/dev/null
    rm "$(hac_config_root)/resources/hiworks-core-1.0.0/skills/hiworks-development/SKILL.md"
    "$script_dir/../bin/hac" install >/dev/null
    [ -f "$(hac_config_root)/resources/hiworks-core-1.0.0/skills/hiworks-development/SKILL.md" ]
}


test_startup_preserves_user_package() {
    new_test_home
    pi_source=$TEST_HOME/pi; core_source=$TEST_HOME/core
    make_pi_source "$pi_source" 0.85.1; make_core_source "$core_source"
    configure_sources "$pi_source" 0.85.1 "$core_source"
    "$script_dir/../bin/hac" install >/dev/null
    printf '%s\n' npm:user@9.9.9 > "$(hac_config_root)/packages/pi-managed/list.txt"
    "$script_dir/../bin/hac" >/dev/null
    grep '^npm:user@9.9.9$' "$(hac_config_root)/packages/pi-managed/list.txt" >/dev/null
}



test_doctor_reports_failing_components() {
    new_test_home
    hac_root=$(hac_config_root)
    hac_init_layout
    printf '%s\n' '{' > "$hac_root/settings.json"
    output=$({ "$script_dir/../bin/hac" doctor || :; } 2>/dev/null)
    printf '%s\n' "$output" | grep '^configuration=failed' >/dev/null
    printf '%s\n' "$output" | grep '^runtime=failed' >/dev/null
    printf '%s\n' "$output" | grep '^core=failed' >/dev/null
    printf '%s\n' "$output" | grep '^packages=failed' >/dev/null
    printf '%s\n' "$output" | grep '^remediation=configuration:' >/dev/null
    if printf '%s\n' "$output" | grep '^remediation=provider:' >/dev/null; then return 1; fi
}

test_doctor_reports_provider_failure() {
    new_test_home
    hac_init_layout
    printf '%s\n' '#!/bin/sh' 'exit 7' > "$TEST_HOME/provider"
    chmod +x "$TEST_HOME/provider"
    output=$({ HAC_UPDATE_PROVIDER="$TEST_HOME/provider" "$script_dir/../bin/hac" doctor || :; } 2>/dev/null)
    printf '%s\n' "$output" | grep '^provider=failed$' >/dev/null
    printf '%s\n' "$output" | grep '^network=failed$' >/dev/null
    printf '%s\n' "$output" | grep '^remediation=provider:' >/dev/null
}

test_none_provider_startup_falls_back() {
    new_test_home
    pi_source=$TEST_HOME/pi; core_source=$TEST_HOME/core
    make_pi_source "$pi_source" 0.85.1; make_core_source "$core_source"
    configure_sources "$pi_source" 0.85.1 "$core_source"
    "$script_dir/../bin/hac" install >/dev/null
    write_healthy_pi "$(hac_config_root)/runtime/releases/pi-0.85.1/bin/pi"
    printf "printf launched > '%s/launched'\n" "$TEST_HOME" >> "$(hac_config_root)/runtime/releases/pi-0.85.1/bin/pi"
    chmod +x "$(hac_config_root)/runtime/releases/pi-0.85.1/bin/pi"
    HAC_UPDATE_PROVIDER=none "$script_dir/../bin/hac" >/dev/null
    assert_eq launched "$(cat "$TEST_HOME/launched")" none-provider-startup
}

test_requested_version_is_checked_during_normal_install() {
    new_test_home
    pi_source=$TEST_HOME/pi
    core_source=$TEST_HOME/core
    make_pi_source "$pi_source" 0.85.1
    make_core_source "$core_source"
    configure_sources "$pi_source" 0.73.2 "$core_source"
    if "$script_dir/../bin/hac" install >/dev/null 2>"$TEST_HOME/error"; then return 1; fi
    grep 'version mismatch' "$TEST_HOME/error" >/dev/null
}

test_install_automatically_acquires_without_source() {
    new_test_home
    unset HAC_PI_SOURCE HAC_PI_VERSION HAC_UPDATE_PROVIDER
    stub_command uname 'case "${1:-}" in -s) printf "%s\n" Linux ;; -m) printf "%s\n" x86_64 ;; esac'
    stub_command node 'printf "%s\n" v20.11.1'
    archive_dir=$TEST_HOME/archive
    mkdir -p "$archive_dir/package"
    printf '%s\n' '{"name":"@mariozechner/pi-coding-agent","version":"0.85.1","bin":{"pi":"dist/cli.js"}}' > "$archive_dir/package/package.json"
    mkdir -p "$archive_dir/package/dist"
    write_healthy_pi "$archive_dir/package/dist/cli.js"
    chmod +x "$archive_dir/package/dist/cli.js"
    (cd "$archive_dir" && tar czf package.tgz package)
    stub_automatic_npm "$archive_dir/package.tgz"
    core_source=$TEST_HOME/core
    make_core_source "$core_source"
    HAC_CORE_SOURCE=$core_source HAC_INSTALL_ROOT=$TEST_HOME/share/hac HAC_BIN_DIR=$TEST_HOME/bin \
        "$script_dir/../install.sh" >/dev/null
    unset HAC_PI_SOURCE
    HAC_CORE_SOURCE=$core_source HAC_PI_VERSION=0.85.1 \
        "$TEST_HOME/bin/hac" install >/dev/null
    assert_eq 0.85.1 "$(jq -r .piVersion "$(hac_config_root)/runtime/active.json")" automatic-command-version
}

test_active_release_version_identity_is_required() {
    new_test_home
    pi_source=$TEST_HOME/pi; core_source=$TEST_HOME/core
    make_pi_source "$pi_source" 0.85.1; make_core_source "$core_source"
    configure_sources "$pi_source" 0.85.1 "$core_source"
    "$script_dir/../bin/hac" install >/dev/null
    active=$(hac_config_root)/runtime/active.json
    jq '.piVersion = "0.73.2"' "$active" > "$active.tmp"
    mv "$active.tmp" "$active"
    if "$script_dir/../bin/hac" doctor >/dev/null 2>&1; then return 1; fi
}

test_install_rejects_non_pinned_command_version_without_state_change() {
    new_test_home
    pi_source=$TEST_HOME/pi; core_source=$TEST_HOME/core
    make_pi_source "$pi_source" 0.85.1; make_core_source "$core_source"
    configure_sources "$pi_source" 0.85.1 "$core_source"
    "$script_dir/../bin/hac" install >/dev/null
    before=$(cksum "$(hac_active_file)")
    if HAC_PI_VERSION=0.73.2 "$script_dir/../bin/hac" install >/dev/null 2>&1; then return 1; fi
    assert_eq "$before" "$(cksum "$(hac_active_file)")" pinned-command-state
}

test_explicit_source_is_normalized_and_validated_by_command() {
    new_test_home
    pi_source=$TEST_HOME/pi; core_source=$TEST_HOME/core
    make_pi_source "$pi_source" 0.85.1; make_core_source "$core_source"
    printf '%s\n' '{"piVersion":"0.85.1","executable":"bin/missing"}' > "$pi_source/metadata.json"
    configure_sources "$pi_source" 0.85.1 "$core_source"
    if "$script_dir/../bin/hac" install >/dev/null 2>&1; then return 1; fi
    if hac_validate_active_state >/dev/null 2>&1; then return 1; else :; fi
}

test_healthy_install_rejects_invalid_source_override() {
    new_test_home
    pi_source=$TEST_HOME/pi; core_source=$TEST_HOME/core
    make_pi_source "$pi_source" 0.85.1; make_core_source "$core_source"
    configure_sources "$pi_source" 0.85.1 "$core_source"
    "$script_dir/../bin/hac" install >/dev/null
    invalid=$TEST_HOME/invalid
    mkdir -p "$invalid"
    printf '%s\n' '{"piVersion":"0.85.1","executable":"bin/missing"}' > "$invalid/metadata.json"
    if HAC_PI_SOURCE="$invalid" "$script_dir/../bin/hac" install >/dev/null 2>&1; then return 1; else :; fi
}


test_version_reports_latest_channel() {
    new_test_home
    output=$($script_dir/../bin/hac version)
    printf '%s\n' "$output" | grep '^piChannel=latest$' >/dev/null
    printf '%s\n' "$output" | grep '^piVersion=not-installed$' >/dev/null
}

test_uninstall_removes_installation_preserves_config() {
    new_test_home
    . "$script_dir/../lib/hac-commands.sh"
    install_root="$TEST_HOME/.local/share/hac"
    bin_dir="$TEST_HOME/.local/bin"
    config_root="$TEST_HOME/.config/hiworks-agent-cli"
    mkdir -p "$install_root" "$bin_dir" "$config_root"
    printf runtime > "$install_root/marker"
    printf launcher > "$bin_dir/hac"
    printf settings > "$config_root/settings.json"
    HAC_INSTALL_ROOT="$install_root" HAC_BIN_DIR="$bin_dir" hac_cmd_uninstall
    [ ! -e "$install_root" ]
    [ ! -e "$bin_dir/hac" ]
    [ -f "$config_root/settings.json" ]
}

test_uninstall_purge_requires_confirmation() {
    new_test_home
    . "$script_dir/../lib/hac-commands.sh"
    config_root="$TEST_HOME/.config/hiworks-agent-cli"
    mkdir -p "$config_root"
    printf settings > "$config_root/settings.json"
    if HAC_INSTALL_ROOT="$TEST_HOME/.local/share/hac" HAC_BIN_DIR="$TEST_HOME/.local/bin" hac_cmd_uninstall --purge </dev/null; then
        return 1
    fi
    [ -f "$config_root/settings.json" ]
}

test_uninstall_purge_removes_config_with_yes() {
    new_test_home
    . "$script_dir/../lib/hac-commands.sh"
    config_root="$TEST_HOME/.config/hiworks-agent-cli"
    mkdir -p "$config_root"
    printf settings > "$config_root/settings.json"
    HAC_INSTALL_ROOT="$TEST_HOME/.local/share/hac" HAC_BIN_DIR="$TEST_HOME/.local/bin" hac_cmd_uninstall --purge --yes
    [ ! -e "$config_root" ]
}

test_dispatch_and_stable_failure
test_first_install_failure_is_actionable
test_install_preserves_user_state_and_activates
test_update_failure_preserves_active_and_startup_falls_back
test_version_and_doctor_report_contract
test_pi_forwarding_preserves_arguments
test_continue_resumes_latest_session
test_install_repairs_corrupt_active_state
test_startup_preserves_user_package
test_doctor_reports_failing_components
test_doctor_reports_provider_failure
test_none_provider_startup_falls_back
test_requested_version_is_checked_during_normal_install
test_install_automatically_acquires_without_source
test_active_release_version_identity_is_required
test_install_rejects_non_pinned_command_version_without_state_change
test_explicit_source_is_normalized_and_validated_by_command
test_healthy_install_rejects_invalid_source_override
test_version_reports_latest_channel
test_uninstall_removes_installation_preserves_config
test_uninstall_purge_requires_confirmation
test_uninstall_purge_removes_config_with_yes
printf 'PASS: command contract\n'
