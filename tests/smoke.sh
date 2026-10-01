#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
export HAC_DEFAULT_PACKAGES_FILE="$script_dir/fixtures/default-packages-empty.json"
skip() { printf 'SKIP: Pi smoke test: %s\n' "$1"; exit 0; }
fail() { printf 'FAIL: Pi smoke test: %s\n' "$1" >&2; exit 1; }
[ "${HAC_SMOKE:-1}" != 0 ] || skip 'disabled with HAC_SMOKE=0'
pi_source=${HAC_PI_SOURCE:-}
command -v jq >/dev/null 2>&1 || skip 'jq is unavailable'
command -v node >/dev/null 2>&1 || skip 'Node.js is unavailable'
real_node=$(command -v node)
real_node_dir=$(dirname -- "$real_node")
pi_version=${HAC_PI_VERSION:-0.85.1}
core_source=${HAC_CORE_SOURCE:-$repo_root/resources/hiworks-core}
# Always own the test HOME; never trust the caller to isolate it.
# Resolve caller-provided relative inputs before changing HOME or cwd.
if [ -n "$pi_source" ]; then
    pi_source=$(CDPATH= cd -- "$pi_source" 2>/dev/null && pwd -P) || skip 'Pi source is unavailable'
fi
core_source=$(CDPATH= cd -- "$core_source" 2>/dev/null && pwd -P) || skip 'core source is unavailable'
if [ -n "${HAC_SMOKE_NPM_FIXTURE:-}" ]; then
    HAC_SMOKE_NPM_FIXTURE=$(CDPATH= cd -- "$HAC_SMOKE_NPM_FIXTURE" 2>/dev/null && pwd -P) || skip 'npm fixture is unavailable'
fi
test_home=$(mktemp -d "${TMPDIR:-/tmp}/hac-smoke-home.XXXXXX") || fail 'cannot create isolated HOME'
smoke_tmp=
cleanup_smoke() {
    [ -z "$smoke_tmp" ] || rm -rf "$smoke_tmp"
    rm -rf "$test_home"
}
trap cleanup_smoke 0
export HOME="$test_home"
unset HAC_PI_SOURCE HAC_PI_PACKAGE_DIR HAC_PI_EXECUTABLE_OVERRIDE HAC_RUNTIME_LOCK_HELD HAC_UPDATE_PROVIDER XDG_CONFIG_HOME
. "$script_dir/test_helpers.sh"
cd "$test_home"
system_pi="$test_home/system-pi-fixture"
printf '%s\n' 'system-pi-unchanged' > "$system_pi"
before=$(cksum "$system_pi")
root="$test_home/.config/hiworks-agent-cli"
install_root="$test_home/.local/share/hac"
bin_dir="$test_home/.local/bin"
if [ "${HAC_SMOKE_NPM_FAILURE:-0}" = 1 ]; then
    smoke_tmp=$(mktemp -d "${TMPDIR:-/tmp}/hac-smoke.XXXXXX")
    core_source="$smoke_tmp/core"
    mkdir -p "$core_source/skills/hiworks-development" "$core_source/extensions" "$core_source/prompts" "$core_source/agents" "$core_source/mcp"
    cp "$repo_root/manifest/core.json" "$core_source/manifest.json"
    printf '%s\n' smoke > "$core_source/skills/hiworks-development/SKILL.md"
    for directory in extensions prompts agents mcp; do printf '%s\n' smoke > "$core_source/$directory/README.md"; done
    pi_source="$smoke_tmp/pi"
    mkdir -p "$pi_source/bin"
    write_healthy_pi "$pi_source/bin/pi"
    chmod +x "$pi_source/bin/pi"
    printf '%s\n' '{"piVersion":"0.85.1","executable":"bin/pi"}' > "$pi_source/metadata.json"
    PATH="$real_node_dir:/opt/homebrew/bin:/usr/bin:/bin" HAC_PI_SOURCE="$pi_source" HAC_CORE_SOURCE="$core_source" HAC_INSTALL_ROOT="$install_root" HAC_BIN_DIR="$bin_dir" HAC_PI_VERSION="$pi_version" \
        "$repo_root/install.sh" --install >/dev/null || fail 'npm failure setup installation failed'
    old_launcher=$(cksum "$bin_dir/hac")
    old_runtime=$(cksum "$root/runtime/active.json")
    stub_dir="$smoke_tmp/bin"; mkdir -p "$stub_dir"
    printf '%s\n' '#!/bin/sh' 'exec "${HAC_SMOKE_REAL_NODE}" "$@"' > "$stub_dir/node"
    printf '%s\n' '#!/bin/sh' 'exit 17' > "$stub_dir/npm"
    chmod +x "$stub_dir/node" "$stub_dir/npm"
    real_node=$(command -v node)
    if PATH="$stub_dir:$(command -p getconf PATH)" HAC_SMOKE_REAL_NODE="$real_node" HAC_CORE_SOURCE="$core_source" HAC_INSTALL_ROOT="$install_root" HAC_BIN_DIR="$bin_dir" HAC_PI_VERSION="$pi_version" \
        "$repo_root/install.sh" --install >/dev/null 2>&1; then
        fail 'npm failure unexpectedly succeeded'
    fi
    [ "$old_launcher" = "$(cksum "$bin_dir/hac")" ] || fail 'launcher changed after npm failure'
    [ "$old_runtime" = "$(cksum "$root/runtime/active.json")" ] || fail 'runtime changed after npm failure'
    outcome='npm-failure'
elif [ -n "${HAC_SMOKE_NPM_FIXTURE:-}" ]; then
    fixture=$HAC_SMOKE_NPM_FIXTURE
    [ -d "$fixture" ] || skip "npm fixture is unavailable: $fixture"
    smoke_tmp=$(mktemp -d "${TMPDIR:-/tmp}/hac-smoke.XXXXXX")
    core_source="$smoke_tmp/core"
    mkdir -p "$core_source/skills/hiworks-development" "$core_source/extensions" "$core_source/prompts" "$core_source/agents" "$core_source/mcp"
    cp "$repo_root/manifest/core.json" "$core_source/manifest.json"
    printf '%s\n' smoke > "$core_source/skills/hiworks-development/SKILL.md"
    for directory in extensions prompts agents mcp; do printf '%s\n' smoke > "$core_source/$directory/README.md"; done
    archive_dir="$smoke_tmp/archive"; mkdir -p "$archive_dir/package"
    cp -R "$fixture"/. "$archive_dir/package/"
    write_healthy_pi "$archive_dir/package/dist/cli.js"
    chmod +x "$archive_dir/package/dist/cli.js"
    (cd "$archive_dir" && tar czf package.tgz package)
    stub_dir="$smoke_tmp/bin"; mkdir -p "$stub_dir"
    printf '%s\n' '#!/bin/sh' 'exec "$HAC_SMOKE_REAL_NODE" "$@"' > "$stub_dir/node"
    printf '%s\n' '#!/bin/sh' 'destination=' 'previous=' 'for argument in "$@"; do' '    if [ "$previous" = --pack-destination ]; then destination=$argument; fi' '    previous=$argument' 'done' 'cp "$HAC_SMOKE_NPM_ARCHIVE" "$destination/pi.tgz"' > "$stub_dir/npm"
    chmod +x "$stub_dir/node" "$stub_dir/npm"
    PATH="$stub_dir:$(command -p getconf PATH)" HAC_SMOKE_REAL_NODE="$real_node" HAC_SMOKE_NPM_ARCHIVE="$archive_dir/package.tgz" \
        HAC_CORE_SOURCE=$core_source HAC_INSTALL_ROOT=$install_root HAC_BIN_DIR=$bin_dir HAC_PI_VERSION=$pi_version \
        "$repo_root/install.sh" --install >/dev/null || fail 'automatic fixture installation failed'
    outcome='automatic'
else
    [ -n "$pi_source" ] || skip 'HAC_PI_SOURCE is not set and no deterministic npm fixture was supplied'
    [ -d "$pi_source" ] || skip "Pi source is unavailable: $pi_source"
    [ -f "$pi_source/metadata.json" ] || skip 'Pi source is missing metadata.json'
    HAC_PI_SOURCE=$pi_source HAC_CORE_SOURCE=$core_source HAC_INSTALL_ROOT=$install_root HAC_BIN_DIR=$bin_dir HAC_PI_VERSION=$pi_version \
        "$repo_root/install.sh" --install >/dev/null || fail 'explicit source installation failed'
    outcome='explicit-source'
fi
version_output=$(HOME="$test_home" "$bin_dir/hac" version)
printf '%s\n' "$version_output" | grep '^hacVersion=' >/dev/null || fail 'version output is missing hacVersion'
printf '%s\n' "$version_output" | grep "^configRoot=$root$" >/dev/null || fail 'version output has wrong config root'
printf '%s\n' "$version_output" | grep "^piVersion=$pi_version$" >/dev/null || fail 'version output has wrong Pi version'
managed_executable=$(printf '%s\n' "$version_output" | awk -F= '/^piExecutable=/{print substr($0, index($0, "=") + 1)}')
case "$managed_executable" in */.config/hiworks-agent-cli/runtime/releases/*) : ;; *) fail "smoke executable is outside managed root: $managed_executable" ;; esac
help_output=$(HOME="$test_home" "$bin_dir/hac" pi --help 2>&1) || fail 'managed Pi help failed'
printf '%s\n' "$help_output" | grep -i 'usage:' >/dev/null || fail 'managed Pi help is empty or invalid'
[ "$(HOME="$test_home" "$bin_dir/hac" pi --version 2>&1)" = "$pi_version" ] || fail 'managed Pi version mismatch'
after=$(cksum "$system_pi")
[ "$before" = "$after" ] || fail 'system Pi fixture changed'
printf 'PASS: %s Pi smoke test\n' "$outcome"
