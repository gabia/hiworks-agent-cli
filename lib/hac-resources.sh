#!/bin/sh

hac_validate_core_manifest() {
    hac_manifest_path=$1
    [ -f "$hac_manifest_path" ] || return 1
    jq -e '
      type == "object" and
      .schemaVersion == 1 and
      (.coreVersion | type) == "string" and (.coreVersion | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
      (.supportedPlatforms | type) == "array" and (.supportedPlatforms | length > 0) and
      all(.supportedPlatforms[]; type == "string" and test("^(darwin|linux)-(arm64|x64)$")) and
      (.piCompatibility | type) == "object" and
      (.piCompatibility.minVersion | type) == "string" and (.piCompatibility.minVersion | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
      (.piCompatibility.executable | type) == "string" and (.piCompatibility.executable | test("^[A-Za-z0-9][A-Za-z0-9._-]*$")) and
      (.packages | type) == "array" and
      all(.packages[]?; (.scope == "required" or .scope == "optional") and (.source | type) == "string") and
      all(.packages[]?; .scope != "required" or
        (.source | test("^npm:(@[^/[:space:]]+/)?[^@/[:space:]]+@[0-9]+\\.[0-9]+\\.[0-9]+$") or
         test("^git:[^[:space:]@]+@[0-9a-fA-F]{40}$"))) and
      (.mcp.enabledByDefault == false) and (.mcp.servers | type) == "array" and
      (.agents.enabledByDefault == false) and
      .resourcePaths == [
        "skills/hiworks-development", "extensions", "prompts", "agents", "mcp"
      ]
    ' "$hac_manifest_path" >/dev/null 2>&1
}

hac_pi_version_at_least() (
    actual=$1
    minimum=$2
    awk -F. -v actual="$actual" -v minimum="$minimum" '
      BEGIN {
        split(actual, a); split(minimum, b);
        for (i = 1; i <= 3; i++) {
          if ((a[i] + 0) != (b[i] + 0)) exit !((a[i] + 0) > (b[i] + 0));
        }
        exit 0;
      }
    '
)

hac_validate_pi_compatibility() {
    manifest=$1
    pi_release=$2
    hac_validate_core_manifest "$manifest" || return 1
    minimum=$(jq -er '.piCompatibility.minVersion' "$manifest") || return 1
    actual=$(jq -er '.piVersion' "$pi_release/metadata.json") || return 1
    hac_pi_version_at_least "$actual" "$minimum" || {
        printf 'hac: Pi %s is below the core minimum version %s\n' "$actual" "$minimum" >&2
        return 1
    }
    expected_executable=$(jq -er '.piCompatibility.executable' "$manifest") || return 1
    executable=$(jq -er '.executable' "$pi_release/metadata.json") || return 1
    case "$executable" in
        */"$expected_executable") : ;;
        *)
            printf 'hac: Pi executable %s does not match the core executable %s\n' "$executable" "$expected_executable" >&2
            return 1
            ;;
    esac
}

hac_validate_core_release() {
    path=$1
    [ -d "$path" ] || return 1
    [ ! -L "$path" ] || return 1
    hac_release_manifest="$path/manifest.json"
    [ -f "$hac_release_manifest" ] || return 1
    hac_validate_core_manifest "$hac_release_manifest" || return 1
    find "$path" -type l -print -quit | grep . >/dev/null 2>&1 && return 1
    find "$path" -mindepth 1 -print | while IFS= read -r release_path; do
        relative=${release_path#"$path"/}
        case "$relative" in
            manifest.json|skills|skills/hiworks-development|skills/hiworks-development/*|extensions|extensions/*|prompts|prompts/*|agents|agents/*|mcp|mcp/*) : ;;
            *) exit 1 ;;
        esac
    done || return 1
    for resource_path in \
        skills/hiworks-development/SKILL.md \
        extensions/README.md prompts/README.md agents/README.md mcp/README.md
    do
        [ -f "$path/$resource_path" ] || return 1
    done
    for resource_path in \
        skills/hiworks-development extensions prompts agents mcp
    do
        [ -d "$path/$resource_path" ] || return 1
    done
    return 0
}

hac_install_core_release() {
    version=$1
    source=$2
    hac_init_layout || return 1
    case "$version" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
    [ -d "$source" ] || return 1
    [ ! -L "$source" ] || return 1
    destination="$(hac_config_root)/resources/hiworks-core-$version"
    temporary="$destination.tmp.$$"
    if [ -e "$destination" ]; then
        hac_validate_core_release "$destination" || return 1
        jq -e --arg version "$version" '.coreVersion == $version' "$destination/manifest.json" >/dev/null 2>&1 || return 1
        printf '%s\n' "$destination"
        return 0
    fi
    rm -rf "$temporary"
    mkdir -p "$temporary" || return 1
    cp -R "$source"/. "$temporary"/ || { rm -rf "$temporary"; return 1; }
    if [ ! -f "$temporary/manifest.json" ]; then
        manifest_source=$(CDPATH= cd -- "$(dirname -- "$source")/../../manifest" 2>/dev/null && pwd -P)/core.json
        cp "$manifest_source" "$temporary/manifest.json" 2>/dev/null || { rm -rf "$temporary"; return 1; }
    fi
    jq -e --arg version "$version" '.coreVersion == $version' "$temporary/manifest.json" >/dev/null 2>&1 || {
        rm -rf "$temporary"
        return 1
    }
    hac_validate_core_release "$temporary" || { rm -rf "$temporary"; return 1; }
    mv "$temporary" "$destination" || return 1
    printf '%s\n' "$destination"
}
