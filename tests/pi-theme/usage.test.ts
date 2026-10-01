import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import usage from "../../resources/hac-branding/usage.ts";

type Handler = (args: string, ctx: ExtensionContext) => Promise<void>;

async function runUsage(model: { provider: string; baseUrl: string } | undefined): Promise<{ text: string; level: string; urls: string[] }> {
	const root = mkdtempSync(join(tmpdir(), "hac-usage-ext-"));
	const previousDir = process.env.PI_CODING_AGENT_DIR;
	const previousFetch = globalThis.fetch;
	const urls: string[] = [];
	try {
		writeFileSync(join(root, "auth.json"), JSON.stringify({ gabia: { type: "api_key", key: "test-secret" } }));
		writeFileSync(join(root, "models.json"), JSON.stringify({ providers: { gabia: { baseUrl: "https://default.example.com/v1" } } }));
		process.env.PI_CODING_AGENT_DIR = root;
		globalThis.fetch = (async (url: string) => {
			urls.push(url);
			return new Response(JSON.stringify({ data: { key_alias: "tim", spend: 99, max_budget: 25000, budget_period: "WEEKLY", budget_basis: "COST" } }));
		}) as typeof fetch;
		let handler: Handler | undefined;
		usage({ registerCommand: (name: string, command: { handler: Handler }) => { if (name === "usage") handler = command.handler; } } as unknown as ExtensionAPI);
		assert.ok(handler);
		let text = "", level = "";
		await handler("", { model, ui: { notify: (message: string, type: string) => { text = message; level = type; } } } as unknown as ExtensionContext);
		return { text, level, urls };
	} finally {
		globalThis.fetch = previousFetch;
		if (previousDir === undefined) delete process.env.PI_CODING_AGENT_DIR; else process.env.PI_CODING_AGENT_DIR = previousDir;
		rmSync(root, { recursive: true, force: true });
	}
}

test("/usage checks the current model's provider endpoint", async () => {
	const result = await runUsage({ provider: "gabia", baseUrl: "https://session.example.com/v1" });
	assert.deepEqual(result.urls, ["https://session.example.com/v1/usages"]);
	assert.equal(result.level, "info");
	assert.match(result.text, /주간 {2}\[░+\] 0\.4% ₩99 \/ ₩25,000/);
	assert.ok(!result.text.includes("\x1b["));
});

test("/usage explains unsupported providers without a request", async () => {
	const result = await runUsage({ provider: "anthropic", baseUrl: "https://api.anthropic.com" });
	assert.deepEqual(result.urls, []);
	assert.equal(result.level, "warning");
	assert.match(result.text, /anthropic provider는 사용현황 조회를 지원하지 않습니다/);
});

test("/usage for a Codex model uses only the hac login", async () => {
	const result = await runUsage({ provider: "openai-codex", baseUrl: "https://chatgpt.com/backend-api" });
	assert.deepEqual(result.urls, []);
	assert.equal(result.level, "warning");
	assert.match(result.text, /hac에 연결된 Codex 로그인이 없습니다/);
});
