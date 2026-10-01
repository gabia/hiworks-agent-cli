#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
[ -n "${HAC_PI_SOURCE:-}" ] || { printf '%s\n' 'SKIP: interactive smoke requires a real HAC_PI_SOURCE'; exit 0; }
command -v python3 >/dev/null 2>&1 || { printf '%s\n' 'SKIP: interactive smoke requires Python 3'; exit 0; }
source_path=$(CDPATH= cd -- "$HAC_PI_SOURCE" && pwd -P)
smoke_home=$(mktemp -d "${TMPDIR:-/tmp}/hac-interactive.XXXXXX")
trap 'rm -rf "$smoke_home"' 0
export HOME="$smoke_home"
unset HAC_PI_PACKAGE_DIR HAC_PI_EXECUTABLE_OVERRIDE HAC_RUNTIME_LOCK_HELD XDG_CONFIG_HOME
export HAC_UPDATE_PROVIDER=none
HAC_PI_SOURCE="$source_path" "$repo_root/bin/hac" install
python3 "$script_dir/interactive_smoke.py" "$repo_root/bin/hac" "$smoke_home"
