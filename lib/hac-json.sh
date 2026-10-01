#!/bin/sh

hac_init_layout() {
    hac_json_require || return 1
    root=$(hac_config_root) || return 1
    hac_prepare_directory "$root" || return 1
    for directory in resources packages sessions logs; do
        hac_prepare_directory "$root/$directory" || return 1
    done
    hac_prepare_directory "$root/resources/hiworks-core" || return 1
    hac_prepare_directory "$root/packages/pi-managed" || return 1
    hac_prepare_directory "$root/runtime" || return 1
    for directory in releases locks cache; do
        hac_prepare_directory "$root/runtime/$directory" || return 1
    done

    hac_prepare_file "$root/settings.json" || return 1
    if [ -L "$root/auth.json" ] || { [ -e "$root/auth.json" ] && [ ! -f "$root/auth.json" ]; }; then
        printf 'hac: unexpected auth.json symlink or non-file\n' >&2
        return 1
    elif [ ! -e "$root/auth.json" ]; then
        (umask 077 && printf '%s\n' '{}' > "$root/auth.json") || return 1
    fi
    hac_prepare_file "$root/models.json" || return 1
    hac_prepare_file "$(hac_active_file)" || return 1
    chmod 600 "$root/auth.json" || return 1
}

hac_json_require() {
    if ! command -v jq >/dev/null 2>&1; then
        printf 'hac: jq is required for safe JSON state handling\n' >&2
        return 1
    fi
}

hac_prepare_directory() {
    path=$1
    if [ -L "$path" ] || { [ -e "$path" ] && [ ! -d "$path" ]; }; then
        printf 'hac: unexpected managed directory: %s\n' "$path" >&2
        return 1
    fi
    (umask 077 && mkdir -p "$path") || return 1
    chmod 700 "$path"
}

hac_prepare_file() {
    path=$1
    if [ -L "$path" ] || { [ -e "$path" ] && [ ! -f "$path" ]; }; then
        printf 'hac: unexpected managed file: %s\n' "$path" >&2
        return 1
    fi
    [ -e "$path" ] || printf '%s\n' '{}' > "$path"
}

hac_read_active_field() {
    field=$1
    case "$field" in
        piVersion|executable|activatedAt) : ;;
        *) printf 'hac: unsupported active state field: %s\n' "$field" >&2; return 1 ;;
    esac
    hac_json_require || return 1
    jq -er --arg field "$field" 'if type == "object" and (.[$field] | type) == "string" and .[$field] != "" then .[$field] else error("missing active state field") end' "$(hac_active_file)"
}

hac_validate_active_state() {
    active=$(hac_active_file)
    hac_json_require || return 1
    [ -f "$active" ] || { printf 'hac: active state is missing\n' >&2; return 1; }
    jq -e 'type == "object" and (.piVersion | type) == "string" and (.piVersion != "") and (.executable | type) == "string" and (.executable != "") and (.activatedAt | type) == "string" and (.activatedAt != "")' "$active" >/dev/null 2>&1 || {
        printf 'hac: active state is malformed\n' >&2
        return 1
    }
    hac_pi_executable >/dev/null
}
