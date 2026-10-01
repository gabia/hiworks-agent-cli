import { type Theme, getAgentDir, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { getCapabilities } from "@earendil-works/pi-tui";
import { readFileSync, existsSync, writeFileSync, mkdirSync, renameSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import openTui from "./extensions/open-tui/index.ts";
import usage from "./usage.ts";
import { resolveAppearance } from "./palette.mjs";

type Appearance = "auto" | "light" | "dark";
const valid = (value: unknown): value is Appearance => ["auto", "light", "dark"].includes(String(value));
const bgKeys = new Set(["selectedBg", "searchMatchBg", "userMessageBg", "customMessageBg", "toolPendingBg", "toolSuccessBg", "toolErrorBg"]);
export default function hiworks(pi: ExtensionAPI) {
 let preference: Appearance = "auto";
 let originalThemeName = "dark";
 const configPath = join(getAgentDir(), "hiworks-theme.json");
 const apply = (ctx: ExtensionContext) => {
  const mode = resolveAppearance(preference, originalThemeName, process.env.COLORFGBG);
  const path = join(dirname(fileURLToPath(import.meta.url)), "themes", `hiworks-${mode}.json`);
  const data = JSON.parse(readFileSync(path, "utf8"));
  const fg: Record<string, string> = {}, bg: Record<string, string> = {};
  for(const [key,value] of Object.entries(data.colors)) (bgKeys.has(key) ? bg : fg)[key] = String(value);
  // Use the host constructor: extension loaders can create a separate module identity.
  const HostTheme = ctx.ui.theme.constructor as typeof Theme;
  const theme = new HostTheme(fg as ConstructorParameters<typeof Theme>[0], bg as ConstructorParameters<typeof Theme>[1], getCapabilities().trueColor ? "truecolor" : "256color", {name:data.name});
  const result = ctx.ui.setTheme(theme);
  if(!result.success) throw new Error(result.error || "Unable to apply Hiworks theme");
  ctx.ui.setTitle("Hiworks Agent CLI");
 };
 pi.on("session_start", (_event, ctx) => {
  if(ctx.mode !== "tui") return;
  if(!ctx.ui.theme.name?.startsWith("hiworks-")) originalThemeName = ctx.ui.theme.name ?? "dark";
  try {
   const saved=existsSync(configPath) ? JSON.parse(readFileSync(configPath,"utf8")).appearance : "auto";
   preference=valid(process.env.HAC_THEME) ? process.env.HAC_THEME : valid(saved) ? saved : "auto";
   apply(ctx);
  } catch(error) {ctx.ui.notify(`Hiworks theme: ${error instanceof Error ? error.message : String(error)}`,"warning");}
 });
 pi.registerCommand("hiworks-theme", {
  description: "Choose Hiworks terminal appearance: auto, light, dark",
  handler: async (args,ctx) => {
   if(ctx.mode !== "tui") return;
   const choice=args.trim() || await ctx.ui.select("Hiworks appearance",["auto","light","dark"]);
   if(!choice)return;
   if(!valid(choice)){ctx.ui.notify("Use /hiworks-theme auto, light, or dark", "warning");return;}
   preference=choice;apply(ctx);
   mkdirSync(dirname(configPath),{recursive:true});
   const tmp=`${configPath}.${process.pid}.tmp`;
   writeFileSync(tmp,JSON.stringify({appearance:choice},null,2)+"\n",{mode:0o600});renameSync(tmp,configPath);
   ctx.ui.notify(`Hiworks appearance: ${choice}`,"info");
  },
 });
 usage(pi);
 openTui(pi);
}
