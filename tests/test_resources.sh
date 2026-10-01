#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_dir/test_helpers.sh"
. "$script_dir/../lib/hac-env.sh"
. "$script_dir/../lib/hac-json.sh"
. "$script_dir/../lib/hac-lock.sh"
. "$script_dir/../lib/hac-runtime.sh"
. "$script_dir/../lib/hac-resources.sh"

repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
manifest="$repo_root/manifest/core.json"

trap cleanup_test_home EXIT HUP INT TERM

test_manifest_has_required_fields() {
    hac_validate_core_manifest "$manifest"
    jq -e '.schemaVersion == 1 and .coreVersion == "1.0.0" and (.supportedPlatforms | type) == "array" and (.piCompatibility | type) == "object" and (.packages | type) == "array"' "$manifest" >/dev/null
    assert_eq "$(jq -r '.piCompatibility.minVersion' "$manifest")" "$(jq -r '.piCompatibility.minVersion' "$repo_root/resources/hiworks-core/manifest.json")" pi-min-version-consistent
}

test_required_packages_are_exactly_pinned() {
    temporary=$(mktemp -d "${TMPDIR:-/tmp}/hac-manifest.XXXXXX")
    cp "$manifest" "$temporary/core.json"
    jq '.packages = [{"source":"npm:example@latest","scope":"required"}]' "$manifest" > "$temporary/floating.json"
    if hac_validate_core_manifest "$temporary/floating.json"; then return 1; fi
    jq '.packages = [{"source":"npm:example@1.2.3","scope":"required"}]' "$manifest" > "$temporary/exact.json"
    hac_validate_core_manifest "$temporary/exact.json"
    jq '.packages = [{"source":"npm:@scope/example@1.2.3","scope":"required"}]' "$manifest" > "$temporary/scoped.json"
    hac_validate_core_manifest "$temporary/scoped.json"
    jq '.packages = [{"source":"git:https://github.com/example/pkg.git@main","scope":"required"}]' "$manifest" > "$temporary/git-main.json"
    if hac_validate_core_manifest "$temporary/git-main.json"; then return 1; fi
    jq '.packages = [{"source":"git:https://github.com/example/pkg.git@0123456789abcdef0123456789abcdef01234567","scope":"required"}]' "$manifest" > "$temporary/git-sha.json"
    hac_validate_core_manifest "$temporary/git-sha.json"
    jq '.packages = [{"source":"git:https://github.com/example/pkg.git@0123456789abcdef0123456789abcdef0123456g","scope":"required"}]' "$manifest" > "$temporary/git-invalid-sha.json"
    if hac_validate_core_manifest "$temporary/git-invalid-sha.json"; then return 1; fi
    rm -rf "$temporary"
}

test_manifest_rejects_malformed_resources_and_platforms() {
    temporary=$(mktemp -d "${TMPDIR:-/tmp}/hac-manifest.XXXXXX")
    jq '.resourcePaths = ["skills/hiworks-development", "extensions", "prompts", "agents", "../mcp"]' "$manifest" > "$temporary/unsafe.json"
    if hac_validate_core_manifest "$temporary/unsafe.json"; then return 1; fi
    jq '.resourcePaths = ["skills/hiworks-development", "extensions", "prompts", "agents", "missing"]' "$manifest" > "$temporary/missing.json"
    if hac_validate_core_manifest "$temporary/missing.json"; then return 1; fi
    jq '.supportedPlatforms = ["darwin-arm64", 7]' "$manifest" > "$temporary/platform.json"
    if hac_validate_core_manifest "$temporary/platform.json"; then return 1; fi
    jq '.piCompatibility.minVersion = ""' "$manifest" > "$temporary/min-version.json"
    if hac_validate_core_manifest "$temporary/min-version.json"; then return 1; fi
    jq '.piCompatibility.executable = "../pi"' "$manifest" > "$temporary/executable.json"
    if hac_validate_core_manifest "$temporary/executable.json"; then return 1; fi
    rm -rf "$temporary"
}

test_release_rejects_missing_declared_resource() {
    temporary=$(mktemp -d "${TMPDIR:-/tmp}/hac-release.XXXXXX")
    cp -R "$repo_root/resources/hiworks-core"/. "$temporary"/
    cp "$manifest" "$temporary/manifest.json"
    rm -rf "$temporary/mcp"
    if hac_validate_core_release "$temporary"; then return 1; fi
    rm -rf "$temporary"
}

test_required_resource_paths_and_mcp_defaults() {
    assert_file_exists "$repo_root/resources/hiworks-core/skills/hiworks-development/SKILL.md"
    assert_file_exists "$repo_root/resources/hiworks-core/extensions/README.md"
    assert_file_exists "$repo_root/resources/hiworks-core/prompts/README.md"
    assert_file_exists "$repo_root/resources/hiworks-core/agents/README.md"
    assert_file_exists "$repo_root/resources/hiworks-core/mcp/README.md"
    jq -e '.mcp.enabledByDefault == false and .agents.enabledByDefault == false' "$manifest" >/dev/null
}

test_pi_compatibility_enforces_minimum_and_entrypoint() {
    temporary=$(mktemp -d "${TMPDIR:-/tmp}/hac-pi-compatibility.XXXXXX")
    mkdir -p "$temporary/bin"
    printf '%s\n' '{"piVersion":"0.85.0","executable":"bin/pi"}' > "$temporary/metadata.json"
    if hac_validate_pi_compatibility "$manifest" "$temporary"; then return 1; fi
    printf '%s\n' '{"piVersion":"0.85.1","executable":"bin/not-pi"}' > "$temporary/metadata.json"
    if hac_validate_pi_compatibility "$manifest" "$temporary"; then return 1; fi
    printf '%s\n' '{"piVersion":"0.85.1","executable":"bin/pi"}' > "$temporary/metadata.json"
    hac_validate_pi_compatibility "$manifest" "$temporary"
    rm -rf "$temporary"
}

test_install_core_release_isolated_and_validated() {
    new_test_home
    hac_init_layout
    source="$TEST_HOME/core-source"
    mkdir -p "$source"
    cp -R "$repo_root/resources/hiworks-core"/. "$source"/
    cp "$manifest" "$source/manifest.json"
    touch "$source/auth.json" "$source/settings.json" "$source/models.json"
    mkdir -p "$source/sessions"
    mkdir -p "$source/nested/credentials"
    touch "$source/nested/credentials/token.json"
    if hac_install_core_release 1.0.0 "$source"; then return 1; fi
    rm -f "$source/auth.json" "$source/settings.json" "$source/models.json"
    rm -rf "$source/sessions"
    rm -rf "$source/nested"
    release=$(hac_install_core_release 1.0.0 "$source")
    assert_eq "$(hac_config_root)/resources/hiworks-core-1.0.0" "$release" core-release-path
    hac_validate_core_release "$release"
    [ ! -e "$release/auth.json" ]
    [ ! -e "$release/settings.json" ]
}

test_existing_release_version_must_match() {
    new_test_home
    hac_init_layout
    source="$TEST_HOME/core-source"
    mkdir -p "$source"
    cp -R "$repo_root/resources/hiworks-core"/. "$source"/
    cp "$manifest" "$source/manifest.json"
    release=$(hac_install_core_release 1.0.0 "$source")
    jq '.coreVersion = "2.0.0"' "$release/manifest.json" > "$release/manifest.tmp"
    mv "$release/manifest.tmp" "$release/manifest.json"
    if hac_install_core_release 1.0.0 "$source"; then return 1; fi
}

test_release_allowlist_rejects_arbitrary_files_and_symlinks() {
    new_test_home
    hac_init_layout
    source="$TEST_HOME/core-source"
    mkdir -p "$source"
    cp -R "$repo_root/resources/hiworks-core"/. "$source"/
    cp "$manifest" "$source/manifest.json"
    touch "$source/user-state.json"
    if hac_install_core_release 1.0.0 "$source"; then return 1; fi
    rm "$source/user-state.json"
    ln -s "$TEST_HOME" "$source/mcp/external"
    if hac_install_core_release 1.0.0 "$source"; then return 1; fi
}

test_existing_release_allowlist_rejects_contamination() {
    new_test_home
    hac_init_layout
    source="$TEST_HOME/core-source"
    mkdir -p "$source"
    cp -R "$repo_root/resources/hiworks-core"/. "$source"/
    cp "$manifest" "$source/manifest.json"
    release=$(hac_install_core_release 1.0.0 "$source")

    touch "$release/arbitrary.txt"
    if hac_install_core_release 1.0.0 "$source"; then return 1; fi
    rm "$release/arbitrary.txt"

    touch "$release/auth.json"
    if hac_validate_core_release "$release"; then return 1; fi
    rm "$release/auth.json"

    ln -s "$TEST_HOME" "$release/mcp/external"
    if hac_validate_core_release "$release"; then return 1; fi
}

test_manifest_has_required_fields
test_required_packages_are_exactly_pinned
test_manifest_rejects_malformed_resources_and_platforms
test_release_rejects_missing_declared_resource
test_required_resource_paths_and_mcp_defaults
test_pi_compatibility_enforces_minimum_and_entrypoint
test_install_core_release_isolated_and_validated
test_existing_release_version_must_match
test_release_allowlist_rejects_arbitrary_files_and_symlinks
test_existing_release_allowlist_rejects_contamination
printf 'PASS: resources contract\n'
