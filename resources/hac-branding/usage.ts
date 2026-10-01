import { getAgentDir, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { usageFor } from "../../lib/hac-usage.mjs";

// Checks the key of the model in use, which can differ from the default after /model.
export default function usage(pi: ExtensionAPI) {
 pi.registerCommand("usage", {
  description: "현재 모델 provider의 AI Hub 사용액 또는 Codex 한도 보기",
  handler: async (_args, ctx) => {
   const model = ctx.model;
   try {
    const text = await usageFor({ root: getAgentDir(), provider: model?.provider, baseUrl: model?.baseUrl });
    ctx.ui.notify(text, "info");
   } catch(error) {ctx.ui.notify(`사용현황: ${error instanceof Error ? error.message : String(error)}`, "warning");}
  },
 });
}
