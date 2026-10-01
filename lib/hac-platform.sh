#!/bin/sh

hac_platform_id() {
    case "$(uname -s 2>/dev/null):$(uname -m 2>/dev/null)" in
        Darwin:arm64) printf '%s\n' darwin-arm64 ;;
        Darwin:x64|Darwin:x86_64) printf '%s\n' darwin-x64 ;;
        Linux:arm64|Linux:aarch64) printf '%s\n' linux-arm64 ;;
        Linux:x64|Linux:x86_64) printf '%s\n' linux-x64 ;;
        *) return 1 ;;
    esac
}
