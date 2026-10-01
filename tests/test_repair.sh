#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
. "$script_dir/test_helpers.sh"
. "$script_dir/../lib/hac-env.sh"
. "$script_dir/../lib/hac-json.sh"
. "$script_dir/../lib/hac-runtime.sh"
trap cleanup_test_home EXIT HUP INT TERM
new_test_home
hac_init_layout
candidate=$TEST_HOME/candidate
mkdir -p "$candidate/bin"
printf '%s\n' '{"piVersion":"0.85.1","executable":"bin/pi"}' > "$candidate/metadata.json"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$candidate/bin/pi"
chmod +x "$candidate/bin/pi"
if hac_validate_candidate "$candidate"; then
    printf '%s\n' 'FAIL: no-op Pi passed candidate validation' >&2
    exit 1
fi
cat > "$candidate/bin/pi" <<'PI'
#!/bin/sh
case "${1:-}" in
    --version) printf '0.85.1\n' ;;
    --help) printf 'Usage: pi [options]\n  --version --help\n' ;;
    list) : ;;
    *) printf 'interactive-fixture\n' ;;
esac
PI
hac_validate_candidate "$candidate"
# Real Pi emits CLI information on stderr when stdin is not a terminal.
cp "$candidate/bin/pi" "$TEST_HOME/stdout-pi"
printf '%s\n' '#!/bin/sh' "exec '$TEST_HOME/stdout-pi' \"\$@\" >&2" > "$candidate/bin/pi"
hac_validate_candidate "$candidate"
cp "$TEST_HOME/stdout-pi" "$candidate/bin/pi"
cp "$candidate/bin/pi" "$TEST_HOME/good-pi"
# Correct metadata/version alone is insufficient if help is empty.
printf '%s\n' '#!/bin/sh' 'if [ "${1:-}" = --version ]; then printf "0.85.1\n"; fi' > "$candidate/bin/pi"
if hac_validate_candidate "$candidate"; then exit 1; fi
printf '%s\n' '#!/bin/sh' 'exec sleep 30' > "$candidate/bin/pi"
if hac_validate_candidate "$candidate"; then exit 1; fi
cp "$TEST_HOME/good-pi" "$candidate/bin/pi"
HAC_PI_SOURCE="$candidate" "$script_dir/../bin/hac" install
root=$(hac_config_root)
printf '%s\n' '{"sentinel":"preserved"}' > "$root/auth.json"
printf '%s\n' session > "$root/sessions/sentinel"
printf old > "$root/runtime/releases/pi-0.85.1/marker"
printf new > "$candidate/marker"
HAC_PI_SOURCE="$candidate" "$script_dir/../bin/hac" install --repair
assert_eq new "$(cat "$root/runtime/releases/pi-0.85.1/marker")" repair-replaces-same-version
assert_eq '{"sentinel":"preserved"}' "$(cat "$root/auth.json")" auth-preserved
assert_eq session "$(cat "$root/sessions/sentinel")" session-preserved
printf '%s\n' '#!/bin/sh' 'exit 0' > "$candidate/bin/pi"
if HAC_PI_SOURCE="$candidate" "$script_dir/../bin/hac" install --repair; then
    printf '%s\n' 'FAIL: repair accepted no-op candidate' >&2; exit 1
fi
assert_eq new "$(cat "$root/runtime/releases/pi-0.85.1/marker")" failed-repair-preserves-release
assert_eq 0.85.1 "$("$script_dir/../bin/hac" pi --version)" previous-pi-still-works
# A later reconciliation failure must restore the same-version binary too.
cp "$TEST_HOME/good-pi" "$candidate/bin/pi"
printf '%s\n' 'if [ "${1:-}" = list ]; then exit 9; fi' >> "$candidate/bin/pi"
printf broken > "$candidate/marker"
active_before=$(cksum "$root/runtime/active.json")
if HAC_PI_SOURCE="$candidate" "$script_dir/../bin/hac" install --repair; then exit 1; fi
assert_eq new "$(cat "$root/runtime/releases/pi-0.85.1/marker")" reconciliation-failure-restores-release
assert_eq "$active_before" "$(cksum "$root/runtime/active.json")" reconciliation-failure-preserves-active
printf '%s\n' '#!/bin/sh' 'exit 0' > "$root/runtime/releases/pi-0.85.1/bin/pi"
if "$script_dir/../bin/hac" doctor > "$TEST_HOME/doctor"; then
    printf '%s\n' 'FAIL: doctor accepted no-op Pi' >&2; exit 1
fi
grep 'runtime=failed' "$TEST_HOME/doctor" >/dev/null
printf '%s\n' 'PASS: runtime repair contract'
