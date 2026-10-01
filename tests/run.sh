#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
test_home=$(mktemp -d "${TMPDIR:-/tmp}/hac-suite.XXXXXX")
cleanup() { rm -rf "$test_home"; }
trap cleanup EXIT HUP INT TERM
export HOME="$test_home"
export HAC_DEFAULT_PACKAGES_FILE="$script_dir/fixtures/default-packages-empty.json"
unset XDG_CONFIG_HOME HAC_PI_SOURCE HAC_PI_VERSION HAC_CORE_SOURCE HAC_UPDATE_PROVIDER
printf '%s\n' 'hac: running shell syntax checks'
sh -n "$repo_root/install.sh" "$repo_root/bin/hac" "$repo_root"/lib/*.sh "$repo_root"/tests/*.sh
printf '%s\n' 'PASS: shell syntax checks'
for test_file in \
    "$script_dir/test_help.sh" \
    "$script_dir/test_env.sh" \
    "$script_dir/test_skill_loading.sh" \
    "$script_dir/test_default_superpowers.sh" \
    "$script_dir/test_json.sh" \
    "$script_dir/test_lock.sh" \
    "$script_dir/test_resources.sh" \
    "$script_dir/test_packages.sh" \
    "$script_dir/test_runtime.sh" \
    "$script_dir/test_source.sh" \
    "$script_dir/test_update.sh" \
    "$script_dir/test_repair.sh" \
    "$script_dir/test_smoke_isolation.sh" \
    "$script_dir/test_commands.sh" \
    "$script_dir/test_install.sh"; do
    printf 'hac: running %s\n' "$(basename "$test_file")"
    HOME="$test_home" sh "$test_file"
done
if command -v python3 >/dev/null 2>&1; then
    python3 "$script_dir/test_repair_signal.py"
    python3 "$script_dir/test_ai_hub_prompt.py"
else
    printf '%s\n' 'SKIP: signal repair regression requires Python 3'
fi
node --test "$script_dir/test_setup.mjs" "$script_dir/test_branding.mjs" "$script_dir/test_ai_hub.mjs" "$script_dir/test_self_update.mjs" "$script_dir/test_usage.mjs" "$script_dir/test_release_notices.mjs" "$script_dir/test_private_runtime.mjs"
printf '%s\n' 'hac: running Pi smoke test'
HAC_SMOKE_NPM_FIXTURE="$script_dir/fixtures/pi-package-0.85.1" HOME="$test_home" sh "$script_dir/smoke.sh"
printf '%s\n' 'PASS: aggregate test suite'
