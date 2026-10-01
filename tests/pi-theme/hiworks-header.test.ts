import assert from "node:assert/strict";
import test from "node:test";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { TUI } from "@earendil-works/pi-tui";
import { OpenTuiHeader } from "../../resources/hac-branding/extensions/open-tui/header.ts";
import { visibleWidth } from "../../resources/hac-branding/extensions/open-tui/utils.ts";

test("Hiworks header fits narrow and wide terminals", () => {
 const pi = {getCommands: () => [], getThinkingLevel: () => "off"} as unknown as ExtensionAPI;
 const ctx = {cwd: "/projects/매우-긴-프로젝트-이름/example", ui: {theme: {
  fg: (_color: string, text: string) => text, bold: (text: string) => text,
 }}} as unknown as ExtensionContext;
 const header = new OpenTuiHeader(pi, ctx, {} as TUI);
 for (const width of [0, 1, 20, 24, 40, 60, 80, 110, 160]) {
  for (const line of header.render(width)) assert.ok(visibleWidth(line) <= width, `${width}: ${line}`);
 }
 assert.match(header.render(110).join("\n"), /Hiworks Agent CLI/);
});
