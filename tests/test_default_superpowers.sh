#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
. "$script_dir/test_helpers.sh"
. "$script_dir/../lib/hac-env.sh"
. "$script_dir/../lib/hac-json.sh"
. "$script_dir/../lib/hac-lock.sh"
. "$script_dir/../lib/hac-runtime.sh"
. "$script_dir/../lib/hac-packages.sh"
trap cleanup_test_home 0
new_test_home
hac_init_layout
export HAC_DEFAULT_PACKAGES_FILE="$script_dir/../manifest/default-packages.json"
hac_script_root() { CDPATH= cd "$script_dir/.." && pwd -P; }
root=$(hac_config_root)
mkdir -p "$root/runtime/releases/pi-test/bin"
cat > "$root/runtime/releases/pi-test/bin/pi" <<'PI'
#!/bin/sh
[ "$1" = install ] || exit 1
printf '%s\n' "$2" >> "$PI_CODING_AGENT_DIR/install.log"
jq --arg source "$2" '.packages += [$source]' "$PI_CODING_AGENT_DIR/settings.json" > "$PI_CODING_AGENT_DIR/settings.tmp"
mv "$PI_CODING_AGENT_DIR/settings.tmp" "$PI_CODING_AGENT_DIR/settings.json"
PI
chmod +x "$root/runtime/releases/pi-test/bin/pi"
printf '%s\n' '{"executable":"runtime/releases/pi-test/bin/pi"}' > "$root/runtime/active.json"
printf '%s\n' '{"defaultModel":"glm","packages":["npm:user-package"]}' > "$root/settings.json"
hac_install_default_packages
hac_install_default_packages
assert_eq "$(jq -r ' .packages[]' "$HAC_DEFAULT_PACKAGES_FILE")" "$(cat "$root/install.log")" installed-once
jq -e --argjson defaults "$(jq -c .packages "$HAC_DEFAULT_PACKAGES_FILE")" '.defaultModel=="glm" and .packages==(["npm:user-package"] + $defaults)' "$root/settings.json" >/dev/null
printf 'PASS: default package installation is additive and idempotent\n'
