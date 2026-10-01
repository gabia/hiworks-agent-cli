#!/bin/sh

hac_runtime_metadata() {
    path=$1
    jq -e 'type == "object" and (.piVersion | type) == "string" and (.piVersion != "") and (.executable | type) == "string" and (.executable != "")' "$path/metadata.json" >/dev/null 2>&1
}

hac_validate_candidate_version() {
    expected=$1
    path=$2
    actual=$(jq -er '.piVersion' "$path/metadata.json") || return 1
    [ "$actual" = "$expected" ] || {
        printf 'hac: candidate metadata piVersion %s does not match requested %s\n' "$actual" "$expected" >&2
        return 1
    }
}

hac_validate_release_identity() {
    expected=$1
    path=$2
    release_name=$(basename -- "$path")
    case "$release_name" in
        pi-*) release_version=${release_name#pi-}; release_version=${release_version%.tmp}; [ "$release_version" = "$expected" ] || return 1 ;;
        *) return 1 ;;
    esac
    hac_validate_candidate_version "$expected" "$path"
}

# Run probes without user settings, project extensions, or inherited stdin.
# Node is already a Pi prerequisite; spawnSync supplies a portable timeout.
hac_probe_pi() (
    probe_executable=$1
    probe_version=$2
    probe_home=$(mktemp -d "${TMPDIR:-/tmp}/hac-probe.XXXXXX") || return 1
    trap 'rm -rf "$probe_home"' 0
    node --input-type=commonjs - "$probe_executable" "$probe_version" "$probe_home" <<'JS'
const { spawnSync } = require('node:child_process');
const [executable, expected, home] = process.argv.slice(2);
const options = {
    cwd: home,
    env: { ...process.env, HOME: home, PI_CODING_AGENT_DIR: home },
    encoding: 'utf8', timeout: 5000, killSignal: 'SIGKILL',
    maxBuffer: 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'],
};
delete options.env.PI_PACKAGE_DIR;
function probe(flag) {
    const result = spawnSync(executable, [flag], options);
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(flag + ' exited with ' + result.status);
    // Pi 0.85.1 redirects console output to stderr outside interactive mode.
    return result.stdout + result.stderr;
}
try {
    if (probe('--version').trim() !== expected)
        throw new Error('version output does not match ' + expected);
    const help = probe('--help');
    if (!/usage:/i.test(help) || !help.includes('--help') || !help.includes('--version'))
        throw new Error('missing or invalid help output');
} catch (error) {
    console.error('hac: Pi runtime probe failed: ' + error.message);
    process.exitCode = 1;
}
JS
)

hac_validate_candidate() {
    path=$1
    [ -d "$path" ] || return 1
    candidate_root=$(CDPATH= cd -- "$path" 2>/dev/null && pwd -P) || return 1
    hac_runtime_metadata "$path" || return 1
    executable=$(jq -er '.executable' "$path/metadata.json") || return 1
    case "$executable" in /*|../*|*/../*|*/..|..) return 1 ;; esac
    [ -x "$path/$executable" ] || return 1
    target=$(hac_realpath_file "$candidate_root/$executable") || return 1
    case "$target" in "$candidate_root"/*) : ;; *) return 1 ;; esac
    [ -x "$target" ] || return 1
    probe_expected=$(jq -er .piVersion "$candidate_root/metadata.json") || return 1
    hac_probe_pi "$target" "$probe_expected" || return 1
    return 0
}

hac_runtime_lock_enter() {
    if [ "${HAC_RUNTIME_LOCK_HELD:-0}" = 1 ]; then
        return 0
    fi
    hac_acquire_lock runtime || return 1
    HAC_RUNTIME_LOCK_HELD=1
    export HAC_RUNTIME_LOCK_HELD
}

hac_runtime_lock_leave() {
    if [ "${HAC_RUNTIME_LOCK_HELD:-0}" = 1 ]; then
        hac_release_lock runtime
        HAC_RUNTIME_LOCK_HELD=0
        export HAC_RUNTIME_LOCK_HELD
    fi
}

hac_install_candidate() {
    hac_runtime_lock_enter || return 1
    result=$(hac_install_candidate_locked "$@")
    status=$?
    hac_runtime_lock_leave
    [ "$status" -eq 0 ] && printf '%s\n' "$result"
    return "$status"
}

hac_install_candidate_locked() {
    version=$1
    source=$2
    hac_init_layout || return 1
    case "$version" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
    [ -d "$source" ] || return 1
    [ ! -L "$source" ] || return 1
    find "$source" -type l -print -quit | grep . >/dev/null 2>&1 && {
        printf '%s\n' 'hac: Pi candidate contains symlinks; release copies require dereferenced files' >&2
        return 1
    }
    destination="$(hac_runtime_root)/releases/pi-$version"
    temporary="$destination.tmp"
    backup="$destination.previous.$$"
    if [ -e "$destination" ]; then
        rm -rf "$backup"
        mv "$destination" "$backup" || return 1
    fi
    rm -rf "$temporary"
    if ! mkdir "$temporary" || ! cp -R "$source"/. "$temporary"/ || ! hac_validate_candidate "$temporary" || ! hac_validate_release_identity "$version" "$temporary"; then
        rm -rf "$temporary" "$destination"
        [ ! -e "$backup" ] || mv "$backup" "$destination"
        return 1
    fi
    if ! mv "$temporary" "$destination"; then
        rm -rf "$temporary" "$destination"
        [ ! -e "$backup" ] || mv "$backup" "$destination"
        return 1
    fi
    rm -rf "$backup"
    printf '%s\n' "$destination"
}

hac_activate_candidate() {
    hac_runtime_lock_enter || return 1
    hac_activate_candidate_locked "$@"
    status=$?
    hac_runtime_lock_leave
    return "$status"
}

hac_activate_candidate_locked() {
    path=$1
    metadata=$2
    releases_root=$(CDPATH= cd -- "$(hac_runtime_root)/releases" 2>/dev/null && pwd -P) || return 1
    candidate_root=$(CDPATH= cd -- "$path" 2>/dev/null && pwd -P) || return 1
    case "$candidate_root" in "$releases_root"/*) : ;; *) return 1 ;; esac
    candidate_name=$(basename -- "$candidate_root")
    case "$candidate_name" in pi-*|pi-*.tmp) : ;; *) return 1 ;; esac
    [ "$candidate_name" != *.tmp ] || return 1
    [ "$candidate_root" = "$releases_root/$candidate_name" ] || return 1
    hac_validate_candidate "$path" || return 1
    jq -e . >/dev/null 2>&1 <<EOF
$metadata
EOF
    executable=$(printf '%s\n' "$metadata" | jq -er '.executable') || return 1
    metadata_version=$(printf '%s\n' "$metadata" | jq -er '.piVersion') || return 1
    case "$executable" in /*|../*|*/../*|*/..|..) return 1 ;; esac
    candidate_executable=$(jq -er '.executable' "$path/metadata.json") || return 1
    candidate_version=$(jq -er '.piVersion' "$path/metadata.json") || return 1
    [ "$candidate_version" = "$metadata_version" ] || return 1
    expected_version=${candidate_name#pi-}
    [ "$candidate_version" = "$expected_version" ] || return 1
    [ "$executable" = "$candidate_executable" ] || return 1
    target=$(hac_realpath_file "$candidate_root/$executable") || return 1
    case "$target" in "$candidate_root"/*) : ;; *) return 1 ;; esac
    active=$(hac_active_file)
    temporary="$active.tmp.$$"
    previous="$active.previous"
    active_executable="runtime/releases/$candidate_name/$executable"
    printf '%s\n' "$metadata" | jq --arg executable "$active_executable" --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '. + {executable: $executable, activatedAt: $timestamp}' > "$temporary" || { rm -f "$temporary"; return 1; }
    [ ! -e "$active" ] || cp "$active" "$previous" || { rm -f "$temporary"; return 1; }
    mv "$temporary" "$active"
}

hac_rollback_active() {
    hac_runtime_lock_enter || return 1
    hac_rollback_active_locked
    status=$?
    hac_runtime_lock_leave
    return "$status"
}

hac_rollback_active_locked() {
    active=$(hac_active_file)
    previous="$active.previous"
    [ -f "$previous" ] || return 1
    temporary="$active.tmp.$$"
    cp "$previous" "$temporary" && mv "$temporary" "$active"
}
