#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
. "$script_dir/test_helpers.sh"
trap cleanup_test_home 0
new_test_home
root=$HOME/.config/hiworks-agent-cli
mkdir -p "$root/runtime/releases/pi-test/bin" "$root/resources/hiworks-core-1.0.0/skills/hiworks-development"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$@"' > "$root/runtime/releases/pi-test/bin/pi"
chmod +x "$root/runtime/releases/pi-test/bin/pi"
printf '%s\n' '{"executable":"runtime/releases/pi-test/bin/pi"}' > "$root/runtime/active.json"
cp "$script_dir/../resources/hiworks-core/skills/hiworks-development/SKILL.md" "$root/resources/hiworks-core-1.0.0/skills/hiworks-development/"
output=$("$script_dir/../bin/hac" pi -p 'test prompt')
printf '%s\n' "$output" | grep '^--skill$' >/dev/null
printf '%s\n' "$output" | grep -Fx "$root/resources/hiworks-core-1.0.0/skills/hiworks-development" >/dev/null
printf '%s\n' "$output" | grep -Fx 'test prompt' >/dev/null
assert_eq --version "$("$script_dir/../bin/hac" pi --version)" version-args-preserved
printf 'PASS: managed skill forwarding\n'
