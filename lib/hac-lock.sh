#!/bin/sh

hac_lock_path() {
    printf '%s/locks/%s\n' "$(hac_runtime_root)" "$1"
}

hac_lock_is_stale() {
    name=$1
    lock=$(hac_lock_path "$name")
    [ -d "$lock" ] || return 1
    pid=$(cat "$lock/pid" 2>/dev/null) || return 0
    timestamp=$(cat "$lock/timestamp" 2>/dev/null) || return 0
    case "$pid:$timestamp" in *[!0-9:]*|:*) return 0 ;; esac
    if kill -0 "$pid" 2>/dev/null; then
        return 1
    fi
    now=$(date +%s)
    age=$((now - timestamp))
    [ "$age" -ge "${HAC_LOCK_STALE_SECONDS:-3600}" ]
}

hac_acquire_lock() {
    name=$1
    hac_init_layout || return 1
    lock=$(hac_lock_path "$name")
    if mkdir "$lock" 2>/dev/null; then
        (umask 077 && printf '%s\n' "$$" > "$lock/pid" && printf '%s\n' "$(date +%s)" > "$lock/timestamp") || {
            rmdir "$lock" 2>/dev/null || :
            return 1
        }
        return 0
    fi
    if hac_lock_is_stale "$name"; then
        pid=$(cat "$lock/pid" 2>/dev/null || printf '?')
        timestamp=$(cat "$lock/timestamp" 2>/dev/null || printf '?')
        current=$(date +%s)
        case "$pid:$timestamp" in *[!0-9:]*|:*) return 1 ;; esac
        age=$((current - timestamp))
        if [ "$age" -ge "${HAC_LOCK_STALE_SECONDS:-3600}" ] && ! kill -0 "$pid" 2>/dev/null; then
            quarantine="$lock.stale.$$"
            mv "$lock" "$quarantine" 2>/dev/null || return 1
            rm -f "$quarantine/pid" "$quarantine/timestamp"
            rmdir "$quarantine" 2>/dev/null || return 1
            mkdir "$lock" 2>/dev/null || return 1
            (umask 077 && printf '%s\n' "$$" > "$lock/pid" && printf '%s\n' "$(date +%s)" > "$lock/timestamp") || return 1
            return 0
        fi
    fi
    printf 'hac: lock is held: %s\n' "$name" >&2
    return 1
}

hac_release_lock() {
    name=$1
    lock=$(hac_lock_path "$name")
    [ -d "$lock" ] || return 0
    owner=$(cat "$lock/pid" 2>/dev/null) || return 1
    [ "$owner" = "$$" ] || return 1
    rm -f "$lock/pid" "$lock/timestamp" && rmdir "$lock"
}
