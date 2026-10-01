# Hiworks TUI fork

Upstream: https://github.com/OldSuns/pi-open-tui
Commit: 04c7a6fd327b3b4a4f5d12ce1cd3ec1dcd8548c9
Package version: 0.3.5
License: MIT, retained in LICENSE.

The upstream LICENSE at the recorded commit was compared byte-for-byte with
the retained file on 2026-09-30. The regression tests copied into
`tests/pi-theme/` are covered by the same upstream notice; Hiworks additions
retain their Gabia copyright under the root MIT license.

The upstream README also acknowledges pi-haiku, pi-claude-code-tui,
pi-zentui, and pi-tps. Their acknowledgements and reviewed license texts
are preserved in the root `THIRD_PARTY_NOTICES.md` and `resources/licenses/`.
The upstream does not identify the exact revisions of those antecedents.

Copied extension modules and upstream regression tests; no nested Git repository.
Hiworks changes: branded header, settings command/config namespace, separate
light/dark semantic palettes, theme selection and ASCII icon default. Thinking
peek is off by default to avoid depending on Pi's internal transcript tree.
The upstream editor/footer and version-guarded scroll compatibility are retained.

Design reference: https://main.hiworks.com/ (2026-09-15).
Public CSS uses .gabia-blue #1d7abd, action blue #167ad8, neutral #f9fafc.
Dark-mode accents are lighter variants for contrast, not official brand tokens.
