#!/bin/sh

set -eu
umask 077
export NODE_USE_SYSTEM_CA=${NODE_USE_SYSTEM_CA:-1}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
. "$script_dir/lib/hac-platform.sh"
. "$script_dir/lib/hac-pi-source.sh"
. "$script_dir/lib/hac-env.sh"
install_root=${HAC_INSTALL_ROOT:-"$HOME/.local/share/hac"}
bin_dir=${HAC_BIN_DIR:-"$HOME/.local/bin"}
run_install=0
for argument in "$@"; do
    case "$argument" in
        --install) run_install=1 ;;
        --) : ;;
        '') : ;;
        *) printf 'hac installer: unknown option: %s\n' "$argument" >&2; exit 1 ;;
    esac
done

platform=$(hac_platform_id 2>/dev/null) || { printf 'hac installer: unsupported platform: %s/%s\n' "$(uname -s 2>/dev/null || :)" "$(uname -m 2>/dev/null || :)" >&2; exit 1; }

node_version=$(node --version 2>/dev/null || :)
node_numeric=${node_version#v}
node_major=${node_numeric%%.*}
node_minor=${node_numeric#*.}
node_minor=${node_minor%%.*}
case "$node_major:$node_minor" in
    20:6|20:7|20:8|20:9|20:[1-9][0-9]*|2[1-9]:*|[3-9][0-9]:*) : ;;
    *) printf 'hac installer: Node.js 20.6.0 or newer is required; found %s\n' "${node_version:-none}" >&2; exit 1 ;;
esac
if [ -z "${HAC_PI_SOURCE:-}" ] && [ -z "${HAC_PI_PACKAGE_DIR:-}" ]; then
    command -v npm >/dev/null 2>&1 || { printf 'hac installer: npm is required for automatic Pi acquisition\n' >&2; exit 1; }
fi

pi_version=$(hac_pi_version) || exit 1

if [ -n "${HAC_PI_SOURCE:-}" ]; then
    [ ! -L "$HAC_PI_SOURCE" ] || { printf '%s\n' 'hac installer: HAC_PI_SOURCE must not be a symlink' >&2; exit 1; }
    pi_source=$(CDPATH= cd -- "$HAC_PI_SOURCE" 2>/dev/null && pwd -P) || { printf 'hac installer: HAC_PI_SOURCE is not a readable directory\n' >&2; exit 1; }
fi
[ -n "${HAC_PI_SOURCE:-}" ] || pi_source=''
metadata_version=
if [ -n "$pi_source" ]; then
    hac_validate_normalized_source "$pi_source" "$pi_version" || exit 1
fi
core_source=${HAC_CORE_SOURCE:-"$script_dir/resources/hiworks-core"}
[ ! -L "$core_source" ] || { printf '%s\n' 'hac installer: HAC_CORE_SOURCE must not be a symlink' >&2; exit 1; }
[ -d "$core_source" ] || { printf 'hac installer: Hiworks core source is not a directory: %s\n' "$core_source" >&2; exit 1; }
[ -f "$core_source/manifest.json" ] || { printf 'hac installer: Hiworks core source is missing manifest.json\n' >&2; exit 1; }
jq -e . "$core_source/manifest.json" >/dev/null 2>&1 || { printf 'hac installer: Hiworks core manifest.json is invalid JSON\n' >&2; exit 1; }

install_parent=$(dirname -- "$install_root")
bin_parent=$(dirname -- "$bin_dir")
mkdir -p "$install_parent" "$bin_parent"
mkdir -p "$bin_dir"
install_root=$(CDPATH= cd -- "$install_parent" && pwd -P)/$(basename -- "$install_root")
bin_dir=$(CDPATH= cd -- "$bin_parent" && pwd -P)/$(basename -- "$bin_dir")
quoted_install_root=$(printf '%s' "$install_root" | sed "s/'/'\\\\''/g; 1s/^/'/; \$s/\$/'/")
stage=$(mktemp -d "$install_parent/.hac-stage.XXXXXX")
cleanup() { rm -rf "$stage" "$stage.launcher"; }
trap cleanup EXIT HUP INT TERM
mkdir -p "$stage/bin"
if [ -z "${HAC_PI_SOURCE:-}" ]; then
    hac_acquire_source "$pi_version" "$stage/pi-source" || exit 1
    pi_source="$stage/pi-source"
fi
cp "$script_dir/bin/hac" "$stage/bin/hac"
cp -R "$script_dir/lib" "$stage/lib"
cp -R "$script_dir/manifest" "$stage/manifest"
cp -R "$script_dir/resources" "$stage/resources"
cp "$script_dir/LICENSE" "$stage/LICENSE"
cp "$script_dir/THIRD_PARTY_NOTICES.md" "$stage/THIRD_PARTY_NOTICES.md"
chmod 755 "$stage/bin/hac"
launcher_stage=$stage.launcher
printf '%s\n' '#!/bin/sh' "exec $quoted_install_root/bin/hac \"\$@\"" > "$launcher_stage"
chmod 755 "$launcher_stage"
[ -x "$stage/bin/hac" ] || { printf '%s\n' 'hac installer: staged launcher validation failed' >&2; exit 1; }

old_root=$install_root.previous.$$; old_launcher="$bin_dir/hac.previous.$$"
config_root=$(CDPATH= cd -- "$(dirname -- "$(hac_config_root 2>/dev/null || printf '%s/.config/hiworks-agent-cli' "$HOME")")" 2>/dev/null && pwd -P)/$(basename -- "$(hac_config_root 2>/dev/null || printf '%s/.config/hiworks-agent-cli' "$HOME")")
config_backup=
config_existed=0
published_root=0
published_launcher=0
rollback() {
    status=$1
    if [ "$published_launcher" -eq 1 ]; then rm -f "$bin_dir/hac"; fi
    if [ "$published_root" -eq 1 ]; then rm -rf "$install_root"; fi
    if [ -e "$old_root" ]; then mv "$old_root" "$install_root" 2>/dev/null || :; fi
    if [ -e "$old_launcher" ]; then mv "$old_launcher" "$bin_dir/hac" 2>/dev/null || :; fi
    if [ -n "$config_backup" ]; then rm -rf "$config_root"; mv "$config_backup" "$config_root" 2>/dev/null || :;
    elif [ "$config_existed" -eq 0 ]; then rm -rf "$config_root"; fi
    exit "$status"
}
if [ "$run_install" -eq 1 ]; then
    if [ -e "$config_root" ]; then
        config_existed=1
        config_backup=$stage.config
        printf 'hac installer: preserving existing configuration...\n' >&2
        cp -R "$config_root" "$config_backup" || { printf '%s\n' 'hac installer: could not snapshot managed configuration' >&2; exit 1; }
    fi
    printf 'hac installer: validating and installing the managed Pi runtime...\n' >&2
    HAC_COMMANDS_FILE="$stage/bin/hac" HAC_PI_VERSION=$pi_version HAC_CORE_SOURCE="$core_source" \
        HAC_PI_SOURCE="$pi_source" "$stage/bin/hac" install || { status=$?; rollback "$status"; }
fi
[ ! -e "$install_root" ] || {
    if mv "$install_root" "$old_root"; then :; else
        status=$?
        printf '%s\n' 'hac installer: could not quarantine existing runtime' >&2
        exit "$status"
    fi
}
if mv "$stage" "$install_root"; then :; else
    status=$?
    printf '%s\n' 'hac installer: could not publish runtime' >&2
    rollback "$status"
fi
published_root=1
if [ -e "$bin_dir/hac" ]; then
    if mv "$bin_dir/hac" "$old_launcher"; then :; else
        status=$?
        printf '%s\n' 'hac installer: could not quarantine existing launcher' >&2
        rollback "$status"
    fi
fi
if mv "$launcher_stage" "$bin_dir/hac"; then :; else
    status=$?
    printf '%s\n' 'hac installer: could not publish launcher' >&2
    rollback "$status"
fi
published_launcher=1
rm -rf "$old_root" "$old_launcher" "$config_backup"
printf 'hac installed for %s at %s\n' "$platform" "$bin_dir/hac"
