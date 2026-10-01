#!/bin/sh

# Pi 0.85.1 was verified from npm on 2026-09-09:
# - Node.js engine: >=20.6.0
# - executable: package dist/cli.js, exposed as bin "pi"
# - config override: PI_CODING_AGENT_DIR
# - PI_PACKAGE_DIR selects Pi installation assets, not user packages; unset it

hac_config_root() {
    printf '%s/.config/hiworks-agent-cli\n' "$HOME"
}

hac_runtime_root() {
    printf '%s/runtime\n' "$(hac_config_root)"
}

hac_active_file() {
    printf '%s/active.json\n' "$(hac_runtime_root)"
}

hac_isolated_env() {
    printf 'PI_CODING_AGENT_DIR=%s\n' "$(hac_config_root)"
}

hac_realpath_file() {
    path=$1
    seen=
    hops=0
    while :; do
        hops=$((hops + 1))
        if [ "$hops" -gt 40 ]; then
            printf 'hac: active Pi executable symlink chain is too deep or cyclic\n' >&2
            return 1
        fi
        parent=$(CDPATH= cd -- "$(dirname -- "$path")" 2>/dev/null && pwd -P) || return 1
        path=$parent/$(basename -- "$path")
        case "$seen" in
            *"|$path|"*)
                printf 'hac: active Pi executable symlink chain is cyclic\n' >&2
                return 1
                ;;
        esac
        seen=$seen'|'$path'|'
        if [ ! -L "$path" ]; then
            printf '%s\n' "$path"
            return 0
        fi
        target=$(readlink "$path") || return 1
        case "$target" in
            /*) path=$target ;;
            *) path=$(dirname -- "$path")/$target ;;
        esac
    done
}

hac_pi_executable() {
    if [ -n "${HAC_PI_EXECUTABLE_OVERRIDE:-}" ]; then
        override_root=$(CDPATH= cd -- "$(hac_config_root)" 2>/dev/null && pwd -P) || return 1
        override_target=$(hac_realpath_file "$HAC_PI_EXECUTABLE_OVERRIDE") || return 1
        case "$override_target" in "$override_root/runtime/releases/"*/*) printf '%s\n' "$override_target"; return 0 ;; esac
        printf 'hac: candidate Pi executable escapes the managed root\n' >&2
        return 1
    fi
    active_file=$(hac_active_file)
    root=$(hac_config_root)
    if [ ! -f "$active_file" ]; then
        printf 'hac: active Pi release is not installed\n' >&2
        return 1
    fi

    if command -v jq >/dev/null 2>&1; then
        executable=$(jq -er 'if type == "object" and (.executable | type) == "string" and .executable != "" then .executable else error("invalid executable") end' "$active_file" 2>/dev/null) || executable=
    else
        printf 'hac: jq is required for safe active state handling\n' >&2
        return 1
    fi
    if [ -z "$executable" ]; then
        printf 'hac: active Pi executable must be a relative path\n' >&2
        return 1
    fi
    case "$executable" in
        /*)
            printf 'hac: active Pi executable must be a relative path\n' >&2
            return 1
            ;;
    esac

    case "$executable" in
        ../*|*/../*|*/..|..)
            printf 'hac: active Pi executable escapes the managed root\n' >&2
            return 1
            ;;
    esac

    resolved=$root/$executable
    resolved_root=$(CDPATH= cd -- "$root" 2>/dev/null && pwd -P) || {
        printf 'hac: managed configuration root is unavailable\n' >&2
        return 1
    }
    resolved_dir=$(CDPATH= cd -- "$(dirname -- "$resolved")" 2>/dev/null && pwd -P) || {
        printf 'hac: active Pi executable parent is unavailable\n' >&2
        return 1
    }
    resolved=$resolved_dir/$(basename -- "$resolved")
    case "$resolved" in
        "$resolved_root"/*) : ;;
        *)
            printf 'hac: active Pi executable escapes the managed root\n' >&2
            return 1
            ;;
    esac
    if [ ! -x "$resolved" ]; then
        printf 'hac: active Pi executable is missing or not executable\n' >&2
        return 1
    fi
    resolved_target=$(hac_realpath_file "$resolved") || {
        printf 'hac: active Pi executable target is unavailable\n' >&2
        return 1
    }
    case "$resolved_target" in
        "$resolved_root"/*) printf '%s\n' "$resolved_target" ;;
        *)
            printf 'hac: active Pi executable escapes the managed root\n' >&2
            return 1
            ;;
    esac
}
