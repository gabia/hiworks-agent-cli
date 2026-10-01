#!/bin/sh

hac_pi_package_name() {
    printf '%s\n' '@earendil-works/pi-coding-agent'
}

hac_validate_pi_version() {
    printf '%s\n' "$1" | LC_ALL=C grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' || {
        printf 'hac: expected a stable Pi version (X.Y.Z), got %s\n' "$1" >&2
        return 1
    }
}

hac_latest_pi_version() (
    printf 'hac: checking the latest Pi version from npm...\n' >&2
    latest=$(npm view "$(hac_pi_package_name)@latest" version --json --fetch-retries=0 --fetch-timeout=20000 2>/dev/null) || {
        printf 'hac: unable to query latest Pi from npm; existing release is unchanged\n' >&2
        return 1
    }
    latest=$(printf '%s\n' "$latest" | jq -er 'select(type == "string")') || return 1
    hac_validate_pi_version "$latest" || return 1
    printf '%s\n' "$latest"
)

# Offline installation overrides are explicit. Online updates bypass these.
hac_pi_version() (
    if [ -n "${HAC_PI_VERSION:-}" ]; then
        selected=$HAC_PI_VERSION
    elif [ -n "${HAC_PI_SOURCE:-}" ]; then
        selected=$(jq -er .piVersion "$HAC_PI_SOURCE/metadata.json") || return 1
    elif [ -n "${HAC_PI_PACKAGE_DIR:-}" ]; then
        selected=$(jq -er .version "$HAC_PI_PACKAGE_DIR/package.json") || return 1
    else
        selected=$(hac_latest_pi_version) || return 1
    fi
    hac_validate_pi_version "$selected" || return 1
    printf '%s\n' "$selected"
)

hac_source_has_symlink() {
    [ ! -L "$1" ] || return 0
    find "$1" -type l -print -quit | grep . >/dev/null 2>&1
}

hac_validate_normalized_source() {
    source=$1
    version=$2
    [ -d "$source" ] || { printf 'hac: Pi source is unavailable: %s\n' "$source" >&2; return 1; }
    hac_source_has_symlink "$source" && { printf 'hac: Pi source contains a symlink: %s\n' "$source" >&2; return 1; }
    [ -f "$source/metadata.json" ] || { printf 'hac: Pi source metadata.json is missing\n' >&2; return 1; }
    hac_validate_pi_version "$version" || return 1
    [ "$(jq -er '.piVersion | strings' "$source/metadata.json" 2>/dev/null)" = "$version" ] || {
        printf 'hac: Pi source version mismatch: expected %s\n' "$version" >&2
        return 1
    }
    executable=$(jq -r '.executable // empty' "$source/metadata.json") || return 1
    [ "$executable" = "bin/pi" ] || { printf 'hac: Pi source executable must be bin/pi\n' >&2; return 1; }
    [ -f "$source/$executable" ] && [ -x "$source/$executable" ] || {
        printf 'hac: Pi source executable is missing or not executable\n' >&2
        return 1
    }
}

hac_copy_tree_without_symlinks() {
    copy_source=$1
    copy_destination=$2
    hac_source_has_symlink "$copy_source" && return 1
    mkdir -p "$copy_destination" || return 1
    cp -R "$copy_source"/. "$copy_destination"/ || return 1
}

hac_normalize_package() (
    package=$1
    version=$2
    destination=$3
    [ -d "$package" ] && [ ! -L "$package" ] || return 1
    hac_source_has_symlink "$package" && return 1
    package_name=$(jq -r '.name // empty' "$package/package.json") || return 1
    case "$package_name" in
        @earendil-works/pi-coding-agent|@mariozechner/pi-coding-agent) : ;;
        *) return 1 ;;
    esac
    package_version=$(jq -r '.version // empty' "$package/package.json") || return 1
    [ "$package_version" = "$version" ] || return 1
    entrypoint=$(jq -r '.bin.pi // empty' "$package/package.json") || return 1
    case "$entrypoint" in
        dist/*) : ;;
        *) return 1 ;;
    esac
    case "$entrypoint" in *[!A-Za-z0-9._/-]*|*/../*|*/..|*/./*) return 1 ;; esac
    [ -f "$package/$entrypoint" ] || return 1
    mkdir -p "$destination/bin" "$destination/package" || return 1
    hac_copy_tree_without_symlinks "$package" "$destination/package" || return 1
    if [ "$(jq -r '((.dependencies // {}) + (.optionalDependencies // {})) | length' "$package/package.json")" -gt 0 ]; then
        # Published shrinkwraps may omit dev/workspace entries; npm install can
        # reconcile them while retaining locked production dependencies.
        printf 'hac: installing Pi runtime dependencies...\n' >&2
        npm install --engine-strict --ignore-scripts --no-bin-links --no-package-lock --omit=dev --fetch-retries=0 --fetch-timeout=20000 --prefix "$destination/package" >/dev/null 2>&1 || {
            printf 'hac: Pi dependency installation failed; check Node compatibility and npm logs\n' >&2
            return 1
        }
    fi
    chmod +x "$destination/package/$entrypoint" || return 1
    printf '#!/bin/sh\nexec "$(dirname "$0")/../package/%s" "$@"\n' "$entrypoint" > "$destination/bin/pi"
    chmod +x "$destination/bin/pi"
    printf '{"piVersion":"%s","executable":"bin/pi"}\n' "$version" > "$destination/metadata.json"
)

hac_acquire_source() (
    version=$1
    destination=$2
    hac_validate_pi_version "$version" || return 1
    rm -rf "$destination"
    if [ -n "${HAC_PI_SOURCE:-}" ]; then
        [ -d "$HAC_PI_SOURCE" ] && [ ! -L "$HAC_PI_SOURCE" ] || {
            printf 'hac: HAC_PI_SOURCE is not a local directory: %s\n' "$HAC_PI_SOURCE" >&2
            return 1
        }
        hac_copy_tree_without_symlinks "$HAC_PI_SOURCE" "$destination" || return 1
        hac_validate_normalized_source "$destination" "$version"
        return
    fi
    if [ -n "${HAC_PI_PACKAGE_DIR:-}" ]; then
        hac_normalize_package "$HAC_PI_PACKAGE_DIR" "$version" "$destination" || {
            printf 'hac: invalid Pi npm package %s@%s\n' "$(hac_pi_package_name)" "$version" >&2
            return 1
        }
        hac_validate_normalized_source "$destination" "$version"
        return
    fi
    package=$(hac_pi_package_name)
    acquisition_parent=$(dirname -- "$destination")
    mkdir -p "$acquisition_parent" || return 1
    pack_dir=$(mktemp -d "$acquisition_parent/.hac-pi-pack.XXXXXX") || {
        printf 'hac: unable to create npm staging directory for %s@%s; set HAC_PI_SOURCE=/path/to/verified/pi-release\n' "$package" "$version" >&2
        return 1
    }
    cleanup_pack() { rm -rf "$pack_dir"; }
    printf 'hac: downloading Pi %s@%s from npm...\n' "$package" "$version" >&2
    if ! npm pack --ignore-scripts --fetch-retries=0 --fetch-timeout=20000 "$package@$version" --pack-destination "$pack_dir" >/dev/null 2>&1; then
        printf 'hac: could not download %s@%s; check npm registry/proxy access or set HAC_PI_SOURCE=/path/to/verified/pi-release\n' "$package" "$version" >&2
        cleanup_pack
        return 1
    fi
    archive=
    archive_count=0
    for candidate in "$pack_dir"/*.tgz; do
        [ -f "$candidate" ] || continue
        archive=$candidate
        archive_count=$((archive_count + 1))
    done
    [ "$archive_count" -eq 1 ] || {
        printf 'hac: npm did not produce a package archive for %s@%s; set HAC_PI_SOURCE=/path/to/verified/pi-release\n' "$package" "$version" >&2
        cleanup_pack; return 1
    }
    archive_listing="$pack_dir/archive.list"
    if ! tar tf "$archive" >"$archive_listing"; then
        printf 'hac: invalid npm archive for %s@%s; set HAC_PI_SOURCE=/path/to/verified/pi-release\n' "$package" "$version" >&2
        cleanup_pack; return 1
    fi
    invalid_path=0
    while IFS= read -r path; do
        case "$path" in /*|../*|*/../*|*/..|..) invalid_path=1 ;; esac
    done <"$archive_listing"
    [ "$invalid_path" -eq 0 ] || {
        printf 'hac: invalid npm archive for %s@%s; set HAC_PI_SOURCE=/path/to/verified/pi-release\n' "$package" "$version" >&2
        cleanup_pack; return 1
    }
    if ! tar tvf "$archive" | awk 'substr($0,1,1) != "-" && substr($0,1,1) != "d" { bad=1 } END { exit bad }'; then
        printf 'hac: npm archive contains unsupported links or file types\n' >&2
        cleanup_pack; return 1
    fi
    extract_dir="$pack_dir/extracted"
    mkdir -p "$extract_dir" || { cleanup_pack; return 1; }
    tar xzf "$archive" -C "$extract_dir" || {
        printf 'hac: could not extract %s@%s; set HAC_PI_SOURCE=/path/to/verified/pi-release\n' "$package" "$version" >&2
        cleanup_pack; return 1
    }
    package_dir="$extract_dir/package"
    [ -d "$package_dir" ] || {
        printf 'hac: npm archive is missing package files for %s@%s; set HAC_PI_SOURCE=/path/to/verified/pi-release\n' "$package" "$version" >&2
        cleanup_pack; return 1
    }
    hac_normalize_package "$package_dir" "$version" "$destination" || {
        printf 'hac: invalid npm package %s@%s; set HAC_PI_SOURCE=/path/to/verified/pi-release\n' "$package" "$version" >&2
        cleanup_pack; return 1
    }
    hac_validate_normalized_source "$destination" "$version" || {
        cleanup_pack; return 1
    }
    cleanup_pack
)
