#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
. "$script_dir/test_helpers.sh"
trap cleanup_test_home 0
new_test_home
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
old=$TEST_HOME/old
mkdir -p "$old/bin"
write_healthy_pi "$old/bin/pi" 0.85.1
printf '%s\n' '{"piVersion":"0.85.1","executable":"bin/pi"}' > "$old/metadata.json"
HAC_PI_SOURCE="$old" "$repo_root/bin/hac" install
config=$TEST_HOME/.config/hiworks-agent-cli
printf '%s\n' '{"sentinel":true}' > "$config/settings.json"
printf 'session' > "$config/sessions/keep"
core_before=$(cksum "$config/resources/hiworks-core-1.0.0/manifest.json")
archive_dir=$TEST_HOME/archive
mkdir -p "$archive_dir/package/dist/bundle"
printf '%s\n' '{"name":"@earendil-works/pi-coding-agent","version":"0.85.2","bin":{"pi":"dist/bundle/cli.js"}}' > "$archive_dir/package/package.json"
write_healthy_pi "$archive_dir/package/dist/bundle/cli.js" 0.85.2
(cd "$archive_dir" && tar czf pi.tgz package)
export UPDATE_ARCHIVE="$archive_dir/pi.tgz" UPDATE_LOG="$TEST_HOME/npm.log"
stub_command npm 'printf "%s\n" "$*" >> "$UPDATE_LOG"
case "$1" in
 view) printf "\"0.85.2\"\n" ;;
 pack)
  destination=
  previous=
  for arg in "$@"; do
   if [ "$previous" = --pack-destination ]; then destination=$arg; fi
   previous=$arg
  done
  cp "$UPDATE_ARCHIVE" "$destination/pi.tgz" ;;
 *) exit 99 ;;
esac'
# Old offline overrides cannot pin an explicitly requested online update.
HAC_PI_VERSION=0.85.1 HAC_PI_SOURCE="$old" HAC_PI_PACKAGE_DIR="$TEST_HOME/missing" \
 "$repo_root/bin/hac" pi update
assert_eq 0.85.2 "$(jq -r .piVersion "$config/runtime/active.json")" pi-update-selects-online-latest
assert_eq 0.85.1 "$(jq -r .piVersion "$config/runtime/active.json.previous")" previous-release-retained
assert_eq '{"sentinel":true}' "$(cat "$config/settings.json")" settings-preserved
assert_eq session "$(cat "$config/sessions/keep")" sessions-preserved
assert_eq "$core_before" "$(cksum "$config/resources/hiworks-core-1.0.0/manifest.json")" pi-only-keeps-core
[ -d "$config/runtime/releases/pi-0.85.1" ]
grep '@earendil-works/pi-coding-agent@latest' "$UPDATE_LOG" >/dev/null
grep '@earendil-works/pi-coding-agent@0.85.2' "$UPDATE_LOG" >/dev/null
before=$(cksum "$config/runtime/active.json")
"$repo_root/bin/hac" pi update
assert_eq "$before" "$(cksum "$config/runtime/active.json")" latest-noop
# A parent-owned runtime lock is borrowed without failing the child exit trap.
mkdir "$config/runtime/locks/runtime"
printf '%s\n' "$$" > "$config/runtime/locks/runtime/pid"
printf '%s\n' 1 > "$config/runtime/locks/runtime/timestamp"
HAC_RUNTIME_LOCK_HELD=1 "$repo_root/bin/hac" pi update
[ -f "$config/runtime/locks/runtime/pid" ]
rm -rf "$config/runtime/locks/runtime"
# Startup must not invoke npm or replace the current release.
stub_command npm 'exit 97'
"$repo_root/bin/hac" >/dev/null
assert_eq "$before" "$(cksum "$config/runtime/active.json")" startup-preserves-runtime
if "$repo_root/bin/hac" pi update > "$TEST_HOME/fail.log" 2>&1; then exit 1; fi
assert_eq "$before" "$(cksum "$config/runtime/active.json")" offline-failure-keeps-active
# Damaged managed resources on startup require explicit repair, never latest.
mv "$config/resources/hiworks-core-1.0.0/manifest.json" "$TEST_HOME/core-manifest"
if "$repo_root/bin/hac" > "$TEST_HOME/startup.log" 2>&1; then exit 1; fi
grep 'hac install --repair' "$TEST_HOME/startup.log" >/dev/null
assert_eq "$before" "$(cksum "$config/runtime/active.json")" broken-startup-keeps-version
mv "$TEST_HOME/core-manifest" "$config/resources/hiworks-core-1.0.0/manifest.json"
# A no-op candidate must never become active.
stub_command npm 'case "$1" in view) printf "\"0.85.3\"\n" ;; pack)
previous=
for arg in "$@"; do
 if [ "$previous" = --pack-destination ]; then cp "$UPDATE_ARCHIVE" "$arg/pi.tgz"; fi
 previous=$arg
done ;; esac'
printf '%s\n' '{"name":"@earendil-works/pi-coding-agent","version":"0.85.3","bin":{"pi":"dist/bundle/cli.js"}}' > "$archive_dir/package/package.json"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$archive_dir/package/dist/bundle/cli.js"
(cd "$archive_dir" && tar czf pi.tgz package)
if "$repo_root/bin/hac" pi update > "$TEST_HOME/fail.log" 2>&1; then exit 1; fi
assert_eq "$before" "$(cksum "$config/runtime/active.json")" invalid-candidate-keeps-active
printf '%s\n' 'PASS: online Pi-only update contract'
