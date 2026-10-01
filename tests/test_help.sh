#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
help=$("$script_dir/../bin/hac" --help)
for command in 'hac setup' 'hac install' 'hac update' 'hac pi' 'hac doctor' 'hac version' 'hac uninstall' 'hac ai-hub' 'hac pi --help' 'hac --continue, -c' 'hac usage'; do
    printf '%s\n' "$help" | grep -F "$command" >/dev/null
done
[ "$help" = "$("$script_dir/../bin/hac" -h)" ]
[ "$help" = "$("$script_dir/../bin/hac" help)" ]
printf 'PASS: hac help commands\n'
