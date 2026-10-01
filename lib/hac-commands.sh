#!/bin/sh

HAC_VERSION=${HAC_VERSION:-1.0.0}

hac_script_root() {
    CDPATH= cd -- "$(dirname -- "${HAC_COMMANDS_FILE:-$0}")/.." && pwd
}

hac_manifest_path() {
    printf '%s/../manifest/core.json\n' "$(dirname -- "${HAC_COMMANDS_FILE:-$0}")"
}

hac_source_value() {
    variable=$1
    case "$variable" in
        HAC_PI_SOURCE) printf '%s\n' "${HAC_PI_SOURCE:-}" ;;
        HAC_PI_VERSION) printf '%s\n' "${HAC_PI_VERSION:-}" ;;
        HAC_CORE_SOURCE) printf '%s\n' "${HAC_CORE_SOURCE:-}" ;;
        HAC_UPDATE_PROVIDER) printf '%s\n' "${HAC_UPDATE_PROVIDER:-}" ;;
        *) return 1 ;;
    esac
}

hac_active_release_path() {
    executable=$(hac_read_active_field executable) || return 1
    case "$executable" in
        runtime/releases/pi-*/bin/*) : ;;
        *) return 1 ;;
    esac
    release=${executable#runtime/releases/}
    release=${release%%/bin/*}
    printf '%s/runtime/releases/%s\n' "$(hac_config_root)" "$release"
}

hac_required_packages_valid() {
    manifest=$1
    hac_validate_core_manifest "$manifest" || return 1
    resolved=$(hac_config_root)/packages/pi-managed/resolved.json
    [ -f "$resolved" ] || return 1
    jq -e --argjson required "$(jq -c '[.packages[] | select(.scope == "required") | .source] | sort | unique' "$manifest")" \
        'type == "object" and (.packages | type) == "array" and ((.packages | sort | unique) == $required)' "$resolved" >/dev/null 2>&1 || return 1
    if [ "$(jq -r '.packages | length' "$manifest")" -gt 0 ]; then
        hac_list_packages > "$(hac_config_root)/packages/pi-managed/.doctor-list.$$" || return 1
        hac_parse_package_list "$(hac_config_root)/packages/pi-managed/.doctor-list.$$" >/dev/null || return 1
        while IFS= read -r package; do
            [ -z "$package" ] || awk -v expected="$package" '$0 == expected { found=1 } END { exit(found ? 0 : 1) }' "$(hac_config_root)/packages/pi-managed/.doctor-list.$$" || return 1
        done <<EOF
$(jq -r '.packages[] | select(.scope == "required") | .source' "$manifest")
EOF
        rm -f "$(hac_config_root)/packages/pi-managed/.doctor-list.$$"
    fi
}

hac_validate_managed_state() {
    hac_validate_active_state || return 1
    release=$(hac_active_release_path) || return 1
    hac_validate_candidate "$release" || return 1
    active_version=$(hac_read_active_field piVersion) || return 1
    hac_validate_release_identity "$active_version" "$release" || return 1
    core_version=$(jq -er '.coreVersion' "$(hac_manifest_path)") || return 1
    core_release=$(hac_config_root)/resources/hiworks-core-$core_version
    hac_validate_core_release "$core_release" || return 1
    hac_validate_pi_compatibility "$core_release/manifest.json" "$release" || return 1
    hac_required_packages_valid "$core_release/manifest.json" || return 1
}

hac_provider_candidate() {
    provider=$(hac_source_value HAC_UPDATE_PROVIDER)
    [ -n "$provider" ] || return 1
    [ "$provider" = none ] && { printf 'hac: managed updates unavailable; configure HAC_UPDATE_PROVIDER or run hac install with HAC_PI_SOURCE\n' >&2; return 2; }
    [ -x "$provider" ] || { printf 'hac: update provider is not executable: %s\n' "$provider" >&2; return 1; }
    candidate_file=$(mktemp "$(hac_runtime_root)/cache/provider.XXXXXX") || return 1
    if ! "$provider" "$(hac_read_active_field piVersion 2>/dev/null || printf none)" > "$candidate_file"; then
        rm -f "$candidate_file"
        printf 'hac: update provider failed; check provider/network configuration\n' >&2
        return 1
    fi
    jq -e \
        'type == "object" and (.piVersion | type) == "string" and (.piVersion != "") and (.piSource | type) == "string" and (.piSource != "") and (.coreSource | type) == "string" and (.coreSource != "")' \
        "$candidate_file" >/dev/null 2>&1 || { rm -f "$candidate_file"; printf 'hac: update provider returned an invalid candidate\n' >&2; return 1; }
    provider_version=$(jq -er .piVersion "$candidate_file" 2>/dev/null || printf '')
    hac_validate_pi_version "$provider_version" || { rm -f "$candidate_file"; printf 'hac: update provider returned unsupported Pi version: %s\n' "$provider_version" >&2; return 1; }
    cat "$candidate_file"
    rm -f "$candidate_file"
}

hac_prepare_candidate() (
    version=$1
    automatic_source=0
    package_backup=
    core_backup=
    committed=0
    repair_release_path="$(hac_runtime_root)/releases/pi-$version"
    repair_release_backup=
    repair_release_existed=0
    repair_release_touched=0
    cleanup_candidate() {
        if [ "$committed" -eq 0 ] && [ "$repair_release_touched" -eq 1 ]; then
            rm -rf "$repair_release_path"
            if [ "$repair_release_existed" -eq 1 ]; then
                mv "$repair_release_backup/release" "$repair_release_path"
            fi
        fi
        [ -z "$repair_release_backup" ] || rm -rf "$repair_release_backup"
        if [ "$committed" -eq 0 ]; then
            [ -z "$package_backup" ] || { rm -rf "$(hac_config_root)/packages/pi-managed"; mkdir -p "$(hac_config_root)/packages/pi-managed"; cp -R "$package_backup"/. "$(hac_config_root)/packages/pi-managed/"; }
            [ -z "$core_backup" ] || { rm -rf "$(hac_config_root)/resources/hiworks-core-$core_version"; mkdir -p "$(hac_config_root)/resources/hiworks-core-$core_version"; cp -R "$core_backup"/. "$(hac_config_root)/resources/hiworks-core-$core_version/"; }
        fi
        [ -z "$package_backup" ] || rm -rf "$package_backup"
        [ -z "$core_backup" ] || rm -rf "$core_backup"
        [ -z "${pi_source_temp:-}" ] || rm -rf "$pi_source_temp"
    }
    trap cleanup_candidate 0
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    . "$(hac_script_root)/lib/hac-pi-source.sh" || return 1
    hac_validate_pi_version "$version" || return 1
    if [ -n "$(hac_source_value HAC_PI_SOURCE)" ]; then
        hac_validate_normalized_source "$(hac_source_value HAC_PI_SOURCE)" "$version" || return 1
    fi
    pi_source=$(hac_source_value HAC_PI_SOURCE)
    core_source=$(hac_source_value HAC_CORE_SOURCE)
    if [ -z "$pi_source" ]; then
        pi_source=$(mktemp -d "$(hac_runtime_root)/cache/.hac-pi-source.XXXXXX") || return 1
        pi_source_temp=$pi_source
        if ! hac_acquire_source "$version" "$pi_source"; then
            rm -rf "$pi_source"
            return 1
        fi
        automatic_source=1
    else
        automatic_source=0
        hac_validate_normalized_source "$pi_source" "$version" || return 1
    fi
    [ -n "$core_source" ] || core_source=$(CDPATH= cd -- "$(dirname -- "$(hac_manifest_path)")/../resources/hiworks-core" && pwd)
    [ -d "$pi_source" ] || { printf 'hac: Pi release source is unavailable\n' >&2; [ "${automatic_source:-0}" -eq 0 ] || rm -rf "$pi_source"; return 1; }
    [ -d "$core_source" ] || { printf 'hac: Hiworks core source is unavailable\n' >&2; [ "${automatic_source:-0}" -eq 0 ] || rm -rf "$pi_source"; return 1; }
    destination="$(hac_runtime_root)/releases/pi-$version"
    core_version=$(jq -er .coreVersion "$(hac_manifest_path)") || { [ "${automatic_source:-0}" -eq 0 ] || rm -rf "$pi_source"; return 1; }
    core_destination="$(hac_config_root)/resources/hiworks-core-$core_version"
    [ ! -e "$core_destination" ] || hac_validate_core_release "$core_destination" || {
        core_backup=$(mktemp -d "$(hac_runtime_root)/cache/.hac-core-backup.XXXXXX") || return 1
        cp -R "$core_destination"/. "$core_backup"/
        rm -rf "$core_destination"
    }
    package_backup=$(mktemp -d "$(hac_runtime_root)/cache/.hac-package-backup.XXXXXX") || return 1
    cp -R "$(hac_config_root)/packages/pi-managed"/. "$package_backup"/
    if [ -e "$repair_release_path" ]; then
        repair_release_backup=$(mktemp -d "$(hac_runtime_root)/cache/.hac-release-backup.XXXXXX") || return 1
        cp -R "$repair_release_path" "$repair_release_backup/release" || return 1
        repair_release_existed=1
    fi
    repair_release_touched=1
    pi_release=$(hac_install_candidate_locked "$version" "$pi_source") || { [ "${automatic_source:-0}" -eq 0 ] || rm -rf "$pi_source"; return 1; }
    core_release=$(hac_install_core_release "$core_version" "$core_source") || { [ "${automatic_source:-0}" -eq 0 ] || rm -rf "$pi_source"; return 1; }
    core_manifest=$core_release/manifest.json
    hac_validate_pi_compatibility "$core_manifest" "$pi_release" || { [ "${automatic_source:-0}" -eq 0 ] || rm -rf "$pi_source"; return 1; }
    HAC_PI_EXECUTABLE_OVERRIDE=$pi_release/$(jq -r .executable "$pi_release/metadata.json")
    export HAC_PI_EXECUTABLE_OVERRIDE
    hac_reconcile_required_packages "$core_manifest" || { [ "${automatic_source:-0}" -eq 0 ] || rm -rf "$pi_source"; return 1; }
    hac_validate_release_identity "$version" "$pi_release" || { [ "${automatic_source:-0}" -eq 0 ] || rm -rf "$pi_source"; return 1; }
    hac_validate_core_release "$core_release" || { [ "${automatic_source:-0}" -eq 0 ] || rm -rf "$pi_source"; return 1; }
    pi_metadata=$(cat "$pi_release/metadata.json") || { unset HAC_PI_EXECUTABLE_OVERRIDE; [ "${automatic_source:-0}" -eq 0 ] || rm -rf "$pi_source"; return 1; }
    hac_activate_candidate_locked "$pi_release" "$pi_metadata" || { unset HAC_PI_EXECUTABLE_OVERRIDE; [ "${automatic_source:-0}" -eq 0 ] || rm -rf "$pi_source"; return 1; }
    unset HAC_PI_EXECUTABLE_OVERRIDE
    committed=1
)

hac_with_runtime_lock() {
    hac_runtime_lock_enter || return 1
    HAC_COMMAND_LOCK=1
    hac_prepare_candidate "$@"
    status=$?
    unset HAC_PI_EXECUTABLE_OVERRIDE
    hac_runtime_lock_leave
    return "$status"
}

hac_cmd_install() {
    repair=0
    for argument in "$@"; do
        case "$argument" in
            --repair) repair=1 ;;
            *) printf 'hac install: unknown option: %s\n' "$argument" >&2; return 2 ;;
        esac
    done
    hac_init_layout || return 1
    . "$(hac_script_root)/lib/hac-pi-source.sh" || return 1
    if [ "$repair" -eq 0 ] && [ -z "${HAC_PI_VERSION:-}${HAC_PI_SOURCE:-}${HAC_PI_PACKAGE_DIR:-}" ] && hac_validate_managed_state >/dev/null 2>&1; then
        hac_install_default_packages
        return $?
    fi
    version=$(hac_pi_version) || return 1
    hac_validate_pi_version "$version" || return 1
    if [ -n "$(hac_source_value HAC_PI_SOURCE)" ]; then
        hac_validate_normalized_source "$(hac_source_value HAC_PI_SOURCE)" "$version" || return 1
    fi
    if [ "$repair" -eq 0 ] && hac_validate_managed_state >/dev/null 2>&1 && [ "$(hac_read_active_field piVersion)" = "$version" ]; then
        hac_install_default_packages
        return $?
    fi
    hac_with_runtime_lock "$version" || {
        printf 'hac: installation failed; no valid active release is available\n' >&2
        return 1
    }
    hac_install_default_packages
}

hac_cmd_update() {
    update_root=${HAC_INSTALL_ROOT:-$HOME/.local/share/hac}
    actual_root=$(CDPATH= cd -- "$update_root" 2>/dev/null && pwd -P) || {
        printf 'hac: install hac before running hac update; hac pi update works from a checkout\n' >&2
        return 1
    }
    [ ! -e "$actual_root/.git" ] || { printf 'hac: refusing to replace a git checkout\n' >&2; return 1; }
    [ ! -L "$update_root" ] || { printf 'hac: refusing symlink installation root\n' >&2; return 1; }
    case "$actual_root" in /|"$HOME"|"$HOME/.config"|"$(hac_config_root)") printf 'hac: unsafe install root\n' >&2; return 1 ;; esac
    [ -f "$actual_root/bin/hac" ] && [ -d "$actual_root/lib" ] || return 1
    exec node "$(hac_script_root)/lib/hac-update.mjs" "$actual_root"
}

hac_cmd_pi_update() (
    force=0
    for argument in "$@"; do
        case "$argument" in
            --force) force=1 ;;
            --help|-h) printf 'Usage: hac pi update [--force]\nUpdates only managed Pi to npm latest stable.\n'; return 0 ;;
            *) printf 'hac pi update: unsupported option; use --help\n' >&2; return 2 ;;
        esac
    done
    . "$(hac_script_root)/lib/hac-pi-source.sh" || return 1
    # An explicit update always means online latest, never an inherited fixture.
    unset HAC_PI_VERSION HAC_PI_SOURCE HAC_PI_PACKAGE_DIR HAC_CORE_SOURCE HAC_UPDATE_PROVIDER HAC_PI_EXECUTABLE_OVERRIDE
    version=$(hac_latest_pi_version) || return 1
    hac_init_layout || return 1
    inherited_lock=${HAC_RUNTIME_LOCK_HELD:-0}
    hac_runtime_lock_enter || return 1
    if [ "$inherited_lock" != 1 ]; then trap 'hac_runtime_lock_leave' 0; fi
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    current=$(hac_read_active_field piVersion 2>/dev/null || printf '')
    if [ "$force" -eq 0 ] && [ "$current" = "$version" ] && hac_validate_candidate "$(hac_active_release_path)" >/dev/null 2>&1; then
        printf 'hac: Pi already up to date (%s)\n' "$version"
        return 0
    fi
    printf 'hac: updating Pi %s -> %s\n' "${current:-not-installed}" "$version"
    hac_prepare_pi_update "$version" || {
        printf 'hac: Pi update failed; previous release retained\n' >&2
        return 1
    }
    printf 'hac: Pi updated to %s\n' "$version"
)

# This path changes only Pi release files and its active pointer.
hac_prepare_pi_update() (
    update_version=$1
    update_destination="$(hac_runtime_root)/releases/pi-$update_version"
    update_source=$(mktemp -d "$(hac_runtime_root)/cache/.pi-update.XXXXXX") || return 1
    update_backup=
    update_published=0
    update_committed=0
    cleanup_pi_update() {
        if [ "$update_published" -eq 1 ] && [ "$update_committed" -eq 0 ]; then
            rm -rf "$update_destination"
            [ -z "$update_backup" ] || mv "$update_backup/release" "$update_destination"
        fi
        rm -rf "$update_source"
        [ -z "$update_backup" ] || rm -rf "$update_backup"
    }
    trap cleanup_pi_update 0
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    hac_acquire_source "$update_version" "$update_source" || return 1
    hac_validate_candidate "$update_source" || return 1
    if [ -e "$update_destination" ]; then
        update_backup=$(mktemp -d "$(hac_runtime_root)/cache/.pi-update-backup.XXXXXX") || return 1
        cp -R "$update_destination" "$update_backup/release" || return 1
    fi
    update_published=1
    update_release=$(hac_install_candidate_locked "$update_version" "$update_source") || return 1
    hac_activate_candidate_locked "$update_release" "$(cat "$update_release/metadata.json")" || return 1
    update_committed=1
)

hac_cmd_run() {
    hac_init_layout || return 1
    if ! hac_validate_managed_state >/dev/null 2>&1; then
        if [ "$(cat "$(hac_active_file)" 2>/dev/null)" = '{}' ] && [ ! -f "$(hac_active_file).previous" ]; then
            hac_cmd_install || return 1
        else
            printf 'hac: managed installation needs repair; run hac install --repair explicitly\n' >&2
            return 1
        fi
    fi
    hac_install_default_packages || return 1
    hac_forward_pi "$@"
}

hac_cmd_pi() {
    if [ "${1:-}" = update ]; then
        shift
        hac_cmd_pi_update "$@"
    else
        hac_forward_pi "$@"
    fi
}

hac_cmd_uninstall() {
    purge=0
    confirmed=0
    for argument in "$@"; do
        case "$argument" in
            --purge) purge=1 ;;
            --yes) confirmed=1 ;;
            *) printf 'hac uninstall: unknown option: %s\n' "$argument" >&2; return 2 ;;
        esac
    done

    install_root=${HAC_INSTALL_ROOT:-$HOME/.local/share/hac}
    bin_dir=${HAC_BIN_DIR:-$HOME/.local/bin}
    case "$install_root:$bin_dir" in
        /*:/*) : ;;
        *) printf '%s\n' 'hac uninstall: install paths must be absolute' >&2; return 1 ;;
    esac
    case "$install_root" in /|"$HOME"|"$HOME/"*) : ;; *) printf '%s\n' 'hac uninstall: refusing unsafe install root' >&2; return 1 ;; esac
    case "$bin_dir" in /|"$HOME"|"$HOME/"*) : ;; *) printf '%s\n' 'hac uninstall: refusing unsafe bin directory' >&2; return 1 ;; esac
    [ ! -L "$install_root" ] && [ ! -L "$bin_dir/hac" ] || { printf '%s\n' 'hac uninstall: refusing symlink install path' >&2; return 1; }

    if [ "$purge" -eq 1 ] && [ "$confirmed" -ne 1 ]; then
        printf 'Remove %s and all Hiworks settings, credentials, packages, and sessions? [y/N] ' "$(hac_config_root)" >&2
        read answer || answer=
        case "$answer" in y|Y|yes|YES) : ;; *) printf '%s\n' 'hac uninstall: purge cancelled' >&2; return 1 ;; esac
    fi
    rm -rf -- "$install_root" "$bin_dir/hac"
    if [ "$purge" -eq 1 ]; then
        config_root=$(hac_config_root)
        [ ! -L "$config_root" ] || { printf '%s\n' 'hac uninstall: refusing symlink config root' >&2; return 1; }
        rm -rf -- "$config_root"
    fi
    printf '%s\n' 'hac uninstall: removed managed installation'
}

hac_cmd_version() {
    . "$(hac_script_root)/lib/hac-pi-source.sh" || return 1
    wrapper_version=$(jq -er .version "$(hac_script_root)/manifest/hac.json" 2>/dev/null || printf '%s' "$HAC_VERSION")
    printf 'hacVersion=%s\n' "$wrapper_version"
    printf 'piChannel=latest\npiPackage=%s\n' "$(hac_pi_package_name)"
    printf 'configRoot=%s\n' "$(hac_config_root)"
    if hac_validate_active_state >/dev/null 2>&1; then
        printf 'activeRelease=%s\n' "$(hac_active_release_path 2>/dev/null || printf unknown)"
        printf 'piVersion=%s\n' "$(hac_read_active_field piVersion)"
        printf 'piExecutable=%s\n' "$(hac_pi_executable)"
    else
        printf 'piVersion=not-installed\n'
        printf 'activeRelease=not-installed\n'
    fi
    manifest=$(hac_manifest_path)
    if [ -f "$manifest" ]; then
        printf 'coreVersion=%s\n' "$(jq -r .coreVersion "$manifest" 2>/dev/null || printf unknown)"
    else
        printf 'coreVersion=unknown\n'
    fi
}

hac_cmd_doctor() {
    problems=0
    configuration_failed=0
    provider_failed=0
    runtime_failed=0
    core_failed=0
    packages_failed=0
    printf 'configRoot=%s\n' "$(hac_config_root)"
    command -v jq >/dev/null 2>&1 && printf 'json=ok\n' || { printf 'json=missing\n'; problems=1; }
    for file in "$(hac_config_root)/settings.json" "$(hac_config_root)/auth.json" "$(hac_config_root)/models.json" "$(hac_active_file)"; do
        if [ -f "$file" ] && jq -e . "$file" >/dev/null 2>&1; then printf 'jsonFile=%s:ok\n' "$(basename "$file")"; else printf 'jsonFile=%s:invalid\n' "$(basename "$file")"; problems=1; configuration_failed=1; fi
    done
    [ ! -e "$(hac_config_root)/auth.json" ] || [ "$(stat -c '%a' "$(hac_config_root)/auth.json" 2>/dev/null || stat -f '%Lp' "$(hac_config_root)/auth.json" 2>/dev/null)" = 600 ] || { printf 'permissions=auth.json must be 0600\n'; problems=1; configuration_failed=1; }
    [ "$configuration_failed" -eq 0 ] && printf 'configuration=ok\n' || printf 'configuration=failed\n'
    hac_platform_id >/dev/null 2>&1 && printf 'platform=ok\n' || { printf 'platform=unsupported\n'; problems=1; }
    hac_validate_managed_state >/dev/null 2>&1 && printf 'runtime=ok\n' || { printf 'runtime=failed\n'; problems=1; runtime_failed=1; }
    core_version=$(jq -er .coreVersion "$(hac_manifest_path)" 2>/dev/null || printf '')
    core_release=$(hac_config_root)/resources/hiworks-core-$core_version
    hac_validate_core_release "$core_release" >/dev/null 2>&1 && printf 'core=ok\nresources=ok\n' || { printf 'core=failed\nresources=failed\n'; problems=1; core_failed=1; }
    hac_required_packages_valid "$core_release/manifest.json" >/dev/null 2>&1 && printf 'packages=ok\n' || { printf 'packages=failed\n'; problems=1; packages_failed=1; }
    manifest=$(hac_manifest_path)
    provider=$(hac_source_value HAC_UPDATE_PROVIDER)
    if [ "$provider" = none ]; then printf 'provider=unavailable\nnetwork=unavailable\n';
    elif [ -n "$provider" ] && [ -x "$provider" ]; then
        if hac_provider_candidate >/dev/null 2>&1; then printf 'provider=ok\nnetwork=ok\n'; else printf 'provider=failed\nnetwork=failed\n'; problems=1; provider_failed=1; fi
    else printf 'provider=unconfigured\nnetwork=not-checked\n'; fi
    printf 'piUpdateChannel=npm-latest\n'
    feed=${HAC_RELEASE_URL:-$(jq -r '.hacReleaseUrl // empty' "$(hac_config_root)/updates.json" 2>/dev/null || :)}
    if [ -n "$feed" ]; then printf 'hacReleaseFeed=configured\n'; else printf 'hacReleaseFeed=unconfigured (Pi updates available)\n'; fi
    [ "$configuration_failed" -eq 0 ] || printf 'remediation=configuration: fix invalid JSON or auth.json permissions\n'
    [ "$runtime_failed" -eq 0 ] || printf 'remediation=runtime: run hac install to repair the managed Pi release\n'
    [ "$core_failed" -eq 0 ] || printf 'remediation=core/resources: run hac install to rebuild Hiworks resources\n'
    [ "$packages_failed" -eq 0 ] || printf 'remediation=packages: run hac install to reconcile required packages\n'
    [ "$provider_failed" -eq 0 ] || printf 'remediation=provider: fix HAC_UPDATE_PROVIDER or its network/source verification\n'
    return "$problems"
}


hac_cmd_help() {
    cat <<'EOF'
Hiworks Agent CLI

Usage: hac [command]

Commands:
  hac                         Start the interactive Hiworks Agent CLI
  hac --continue, -c          Continue the most recent session
  hac setup                   Configure Gabia AI Hub and choose a default model
  hac install [--repair]      Install or repair the managed runtime and defaults
  hac update                  Update hac (when a feed is configured) and Pi
  hac pi [arguments...]       Run the managed Pi CLI
  hac usage                   Show AI Hub spend and Codex limits connected in hac
  hac doctor                  Check configuration and managed runtime
  hac version                 Show hac and installed Pi versions
  hac uninstall [--purge --yes]
                              Remove hac; --purge also removes user data
  hac ai-hub connect          Configure AI Hub with command-line options
  hac --help, -h, help        Show this help

Pi commands and detailed help:
  hac pi --help               Show Pi's supported commands and options
  hac pi install npm:PACKAGE  Install an additional Pi package
  hac pi list                 List installed Pi packages
  hac pi config               Enable or disable package resources
  hac pi remove npm:PACKAGE   Remove a Pi package
  hac pi update [--force]     Update only managed Pi (--force reinstalls latest)

Note: hac pi update is managed by hac; Pi package-update options are not
      forwarded. Use hac pi update --help for supported options.

More help:
  hac setup --help
  hac ai-hub --help
  hac usage --help
EOF
}
