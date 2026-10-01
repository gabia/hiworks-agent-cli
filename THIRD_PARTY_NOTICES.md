# Third-party software notices

Hiworks Agent CLI's Gabia-authored code and documentation are licensed under
the root [MIT License](LICENSE). Third-party material retains its original
copyright and license. This file identifies that material; it does not
replace or modify any upstream license.

## Included TUI code and tests

The files in `resources/hac-branding/extensions/open-tui/` and the upstream
regression tests adapted into `tests/pi-theme/` derive from
[pi-open-tui](https://github.com/OldSuns/pi-open-tui), commit
`04c7a6fd327b3b4a4f5d12ce1cd3ec1dcd8548c9` (recorded package version 0.3.5).

Copyright (c) 2026 pi-open-tui contributors. The complete MIT license is
retained in [resources/hac-branding/LICENSE](resources/hac-branding/LICENSE).
Hiworks changes and provenance are recorded in
[PROVENANCE.md](resources/hac-branding/PROVENANCE.md).

The upstream README acknowledges the following antecedents. These credits
are retained here along with their license texts reviewed on 2026-09-30.
The exact antecedent revisions used by pi-open-tui are not specified upstream;
these references do not imply that every feature or file of each project is
included in Hiworks Agent CLI.

| Project | Upstream acknowledgement | Reviewed copyright and license |
|---|---|---|
| [pi-haiku](https://github.com/nnocte/pi-haiku) | Two-line footer structure and working timer | Copyright (c) 2026 nocte; [MIT](resources/licenses/pi-haiku.LICENSE) |
| [pi-claude-code-tui](https://github.com/Phoobobo/pi-claude-code-tui) | Pi logo frames and rounded editor border technique | Copyright (c) 2026 Phoobobo; [MIT](resources/licenses/pi-claude-code-tui.LICENSE) |
| [pi-zentui](https://github.com/lmilojevicc/pi-zentui) | Footer segments, runtime detection, session lifecycle, settings UI and Git porcelain parsing | Copyright (c) 2025-2026 Luka; [MIT](resources/licenses/pi-zentui.LICENSE) |
| [pi-tps](https://github.com/monotykamary/pi-tps) | Turn timing, stall detection and TPS measurement | Copyright (c) 2026, as stated upstream; [MIT](resources/licenses/pi-tps.LICENSE) |

The upstream also credits Pi's official install script (`pi.dev/install.sh`)
for its original logo frames and thanks the LINUX DO community. Hiworks uses
its own branded header. Pi's reviewed MIT text is preserved below.

## Separately acquired runtime and default packages

The hac source release does not bundle the npm packages below. hac downloads
Pi and installs default packages into the user's managed environment.
These versions were reviewed on 2026-09-30; online installation can select
newer versions. Their license files are retained here as attribution and to
provide the Pi license text absent from the reviewed npm tarballs.

| Package | Reviewed version | Copyright and full license |
|---|---|---|
| [@earendil-works/pi-coding-agent](https://github.com/earendil-works/pi), pi-ai and pi-tui | Development packages 0.87.1; runtime coding-agent 0.99.1; historical 0.85.1 also reviewed | Copyright (c) 2025 Mario Zechner; [MIT](resources/licenses/pi.LICENSE) |
| [pi-superpowers-plus](https://github.com/coctostan/pi-superpowers-plus) | 0.4.1 | Copyright (c) 2026 coctostan and (c) 2025 Jesse Vincent, original skill content from obra/superpowers; [MIT](resources/licenses/pi-superpowers-plus.LICENSE) |
| [pi-anthropic-oauth](https://github.com/leohenon/pi-anthropic-oauth) | 0.3.0 | Copyright (c) 2026 Leo Henon; [MIT](resources/licenses/pi-anthropic-oauth.LICENSE) |

Pi 0.85.1, 0.87.1 and 0.99.1 have identical root MIT texts in their respective source
commits. The preserved text was retrieved from commit
`d981de1229ef899957bbe968bc8dcda02a21f477`; the reviewed 0.99.1 commit is
`d86654abb8862e201933517d6f1fce9f88dd117f`.

The MIT license of pi-anthropic-oauth covers its code. It does not grant
permission to access Claude subscription services through a third-party
application.

## Development tools and transitive dependencies

`typescript@5.9.3` is Apache-2.0 licensed and `@types/node@22.15.30` is MIT
licensed. The root development `node_modules/` directory is not distributed
by the hac packaging script. TypeScript's own `LICENSE.txt` and
`ThirdPartyNoticeText.txt`, and each dependency's original license and
notices, must accompany those packages if they are redistributed.

Each dependency retains its original license. Dependencies may
include bundled code or native components under additional terms.

Preserve all original LICENSE, COPYING, NOTICE, copyright and attribution
files in downloaded packages and their dependencies. For Apache-2.0 material
that is redistributed, include the license, preserve relevant notices and
any upstream NOTICE, and identify modifications where required. Review
actual artifacts when packaging dependencies,
changing versions or creating an offline distribution.

## Names, branding and external services

Hiworks and Gabia names and logos are not offered for unrestricted trademark
use by the software license. Other product names belong to their respective
owners. Nerd Font code points are referenced by the TUI; no font files are
bundled in the tracked source. Redistributing a font requires reviewing that
font's own license.

External AI services, subscription authentication and API access remain
subject to each provider's terms and the user's account permissions.
