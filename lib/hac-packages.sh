#!/bin/sh

hac_list_packages() {
    executable=$(hac_pi_executable) || return 1
    config_root=$(hac_config_root) || return 1
    env -u PI_PACKAGE_DIR "PI_CODING_AGENT_DIR=$config_root" \
        "$executable" list
}

hac_parse_package_list() {
    package_list_path=$1
    awk '
        /^[[:space:]]*$/ { next }
        /^[[:space:]]*(npm:|git:|https?:|ssh:|\/)([^[:space:]]*)[[:space:]]*$/ {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            sub(/[[:space:]]*$/, "", line)
            print line
            next
        }
        { invalid = 1 }
        END { exit(invalid ? 1 : 0) }
    ' "$package_list_path"
}

hac_forward_pi() {
    executable=$(hac_pi_executable) || return 1
    config_root=$(hac_config_root) || return 1
    # Managed skills live outside Pi's automatic discovery directories.
    case "${1:-}" in
        --version|--help|-h|list|install|remove|update|config) : ;;
        *)
            branding="$(hac_script_root)/resources/hac-branding/hiworks-theme.mjs"
            if [ -f "$branding" ]; then set -- "$@" --extension "$branding"; fi
            core_version=$(jq -er .coreVersion "$(hac_manifest_path)" 2>/dev/null || :)
            skill_path="$config_root/resources/hiworks-core-$core_version/skills/hiworks-development"
            if [ -n "$core_version" ] && [ -f "$skill_path/SKILL.md" ]; then
                set -- "$@" --skill "$skill_path"
            fi
            ;;
    esac
    exec env -u PI_PACKAGE_DIR "PI_CODING_AGENT_DIR=$config_root" "HAC_PI_EXECUTABLE=$executable" \
        "$executable" "$@"
}

hac_reconcile_required_packages() {
    (
        manifest_path=$1
        hac_json_require || exit 1
        hac_validate_core_manifest "$manifest_path" || exit 1
        hac_init_layout || exit 1

        package_root=$(hac_config_root)/packages/pi-managed
        if [ ! -f "$package_root/package.json" ]; then
            printf '%s\n' '{"private":true,"dependencies":{}}' > "$package_root/package.json" || exit 1
        fi
        package_list=$package_root/.packages.$$
        parsed_list=$package_root/.parsed.$$
        resolved=$package_root/resolved.json
        resolved_temp=$resolved.tmp.$$
        trap 'rm -f "$package_list" "$parsed_list" "$resolved_temp"' 0 HUP INT TERM
        required=$(jq -r '.packages[] | select(.scope == "required") | .source' "$manifest_path" | sort -u) || exit 1
        hac_list_packages > "$package_list" || exit 1
        if [ -z "$required" ]; then
            printf '%s\n' '{"packages":[],"resolvedAt":0}' > "$resolved_temp" || exit 1
            mv "$resolved_temp" "$resolved" || exit 1
            exit 0
        fi
        hac_parse_package_list "$package_list" > "$parsed_list" || {
            printf 'hac: unexpected Pi package list output\n' >&2
            exit 1
        }

        while IFS= read -r source; do
            [ -n "$source" ] || continue
            if ! awk -v expected="$source" '$0 == expected { found = 1 } END { exit(found ? 0 : 1) }' "$parsed_list"; then
                executable=$(hac_pi_executable) || exit 1
                config_root=$(hac_config_root) || exit 1
                env -u PI_PACKAGE_DIR "PI_CODING_AGENT_DIR=$config_root" \
                    "$executable" install "$source" || exit 1
                hac_list_packages > "$package_list" || exit 1
                hac_parse_package_list "$package_list" > "$parsed_list" || {
                    printf 'hac: unexpected Pi package list output after install\n' >&2
                    exit 1
                }
                awk -v expected="$source" '$0 == expected { found = 1 } END { exit(found ? 0 : 1) }' "$parsed_list" || {
                    printf 'hac: Pi did not report required package after install: %s\n' "$source" >&2
                    exit 1
                }
            fi
        done <<EOF
$required
EOF

        {
            printf '{"packages":['
            first=1
            while IFS= read -r source; do
                [ -n "$source" ] || continue
                [ "$first" -eq 1 ] || printf ','
                jq -Rn --arg source "$source" '$source' || exit 1
                first=0
            done <<EOF
$required
EOF
            printf '],"resolvedAt":%s}\n' "$(date +%s)"
        } > "$resolved_temp" || exit 1
        mv "$resolved_temp" "$resolved" || exit 1
    )
}

# Install defaults through Pi's own package manager; keep user choices intact.
hac_install_default_packages() (
    defaults=${HAC_DEFAULT_PACKAGES_FILE:-$(hac_script_root)/manifest/default-packages.json}
    [ -f "$defaults" ] || return 0
    jq -e '.packages | type == "array" and all(.[]; type == "string" and startswith("npm:"))' "$defaults" >/dev/null || return 1
    hac_init_layout || return 1
    inherited=${HAC_RUNTIME_LOCK_HELD:-0}
    hac_runtime_lock_enter || return 1
    if [ "$inherited" != 1 ]; then trap 'hac_runtime_lock_leave' 0; fi
    config_root=$(hac_config_root)
    executable=$(hac_pi_executable) || return 1
    jq -r '.packages[]' "$defaults" > "$config_root/runtime/default-packages.$$"
    trap 'rm -f "$config_root/runtime/default-packages.$$"; if [ "$inherited" != 1 ]; then hac_runtime_lock_leave; fi' 0
    while IFS= read -r source; do
        if jq -e --arg source "$source" '
          def identity: sub("@[^@/]+$"; "");
          any(.packages[]?; (if type == "object" then .source else . end | identity) == ($source | identity))
        ' "$config_root/settings.json" >/dev/null; then continue; fi
        printf 'hac: installing default package %s\n' "$source"
        env -u PI_PACKAGE_DIR "PI_CODING_AGENT_DIR=$config_root" "$executable" install "$source" || return 1
    done < "$config_root/runtime/default-packages.$$"
)
