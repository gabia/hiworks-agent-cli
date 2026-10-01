import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { resolveUsageTarget, fetchUsage, formatUsage, codexCredentials, fetchCodexUsage, formatCodexUsage, usageFor, usageReport } from '../lib/hac-usage.mjs';

function fixture(t, { auth, models, settings } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'hac-usage-test-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  writeFileSync(join(root, 'auth.json'), JSON.stringify(auth ?? { gabia: { type: 'api_key', key: 'test-secret' } }));
  writeFileSync(join(root, 'models.json'), JSON.stringify(models ?? { providers: { gabia: { baseUrl: 'https://hub.example.com/v1/', models: [] } } }));
  writeFileSync(join(root, 'settings.json'), JSON.stringify(settings ?? { defaultProvider: 'gabia', defaultModel: 'glm' }));
  return root;
}
const usage = (data = {}) => ({ data: {
  key_alias: 'tim', masked_key: 'sk-...ERUw', spend: 99, max_budget: 25000,
  budget_period: 'WEEKLY', budget_basis: 'COST', next_budget_reset_at: '2026-09-27T15:00:00.000Z', ...data,
} });

test('target uses the provider key and configured base URL', t => {
  const root = fixture(t);
  assert.deepEqual(resolveUsageTarget({ root, provider: 'gabia' }),
    { provider: 'gabia', baseUrl: 'https://hub.example.com/v1', key: 'test-secret' });
});

test('base URL override wins over models.json', t => {
  const root = fixture(t);
  assert.equal(resolveUsageTarget({ root, provider: 'gabia', baseUrl: 'https://other.example.com/v1' }).baseUrl, 'https://other.example.com/v1');
});

test('usage rejects HTTP configuration and model overrides before a request', async t => {
  const root = fixture(t, { models: { providers: { gabia: { baseUrl: 'http://hub.example.com/v1' } } } });
  for (const baseUrl of [undefined, 'http://other.example.com/v1']) {
    let requests = 0;
    await assert.rejects(usageFor({ root, provider: 'gabia', baseUrl, fetchImpl: async () => {
      requests++;
      return new Response(JSON.stringify(usage()));
    } }), /HTTPS/);
    assert.equal(requests, 0);
  }
});

test('direct usage requests reject credentials and ambiguous URLs before sending the key', async () => {
  for (const baseUrl of ['http://hub.example.com/v1', 'https://user:password@hub.example.com/v1', 'https://hub.example.com/v1?route=other', 'https://hub.example.com/v1#route']) {
    let requests = 0;
    await assert.rejects(fetchUsage({ baseUrl, key: 'test-secret', fetchImpl: async () => {
      requests++;
      return new Response(JSON.stringify(usage()));
    } }), /HTTPS/);
    assert.equal(requests, 0);
  }
});

test('providers other than AI Hub are reported as unsupported', t => {
  const root = fixture(t);
  assert.throws(() => resolveUsageTarget({ root, provider: 'anthropic' }), /anthropic provider는 사용현황 조회를 지원하지 않습니다/);
  assert.throws(() => resolveUsageTarget({ root, provider: undefined }), /선택된 provider가 없습니다/);
});

test('missing AI Hub key asks for setup', t => {
  const root = fixture(t, { auth: {} });
  assert.throws(() => resolveUsageTarget({ root, provider: 'gabia' }), /hac setup/);
});

test('fetch calls /usages with the bearer key and returns data', async () => {
  const data = await fetchUsage({ baseUrl: 'https://hub.example.com/v1', key: 'test-secret', fetchImpl: async (url, options) => {
    assert.equal(url, 'https://hub.example.com/v1/usages');
    assert.equal(options.headers.Authorization, 'Bearer test-secret');
    assert.equal(options.redirect, 'error');
    return new Response(JSON.stringify(usage()));
  } });
  assert.equal(data.spend, 99);
});

test('fetch errors never include the key', async () => {
  for (const status of [401, 500]) {
    await assert.rejects(fetchUsage({ baseUrl: 'https://hub.example.com/v1', key: 'test-secret',
      fetchImpl: async () => new Response('test-secret', { status }) }), error => {
      assert.match(error.message, new RegExp(String(status)));
      assert.ok(!error.message.includes('test-secret'));
      return true;
    });
  }
  await assert.rejects(fetchUsage({ baseUrl: 'https://hub.example.com/v1', key: 'k', fetchImpl: async () => new Response('{}') }), /응답 형식이 올바르지 않습니다/);
});

test('format shows cost budget, percentage and reset time', () => {
  assert.equal(formatUsage(usage().data, { timeZone: 'Asia/Seoul', now: 1790150000 * 1000 }), [
    'AI Hub 사용현황 — tim',
    '  주간  [░░░░░░░░░░░░░░░░░░░░] 0.4% ₩99 / ₩25,000',
    '        09-28 00:00 (4일 7시간 06분)',
  ].join('\n'));
});

test('format handles token budgets and missing budget policy', () => {
  assert.match(formatUsage(usage({ budget_basis: 'TOKEN', spend: 1200, max_budget: 5000 }).data, { timeZone: 'UTC' }),
    /주간  \[█████░░░░░░░░░░░░░░░\] 24\.0% 1,200 \/ 5,000 토큰/);
  const none = formatUsage(usage({ max_budget: null, budget_period: null, budget_basis: null, next_budget_reset_at: null }).data, { timeZone: 'UTC' });
  assert.match(none, / {2}이번 달 {2}₩99 \(예산 정책 없음\)/);
  assert.doesNotMatch(none, /\d\d:\d\d/);
  assert.match(formatUsage(usage({ budget_period: 'DAILY' }).data, { timeZone: 'Asia/Seoul', now: 1790150000 * 1000 }), /\n {8}00:00 \(/);
});

test('usage formatting rejects non-finite and invalid values', () => {
  for (const spend of [Number.NaN, Number.POSITIVE_INFINITY, -1])
    assert.throws(() => formatUsage(usage({ spend }).data), /응답 형식이 올바르지 않습니다/);
  assert.throws(() => formatUsage(usage({ max_budget: Number.NaN }).data), /응답 형식이 올바르지 않습니다/);
  assert.throws(() => formatUsage(usage({ next_budget_reset_at: 'not-a-date' }).data), /응답 형식이 올바르지 않습니다/);
  assert.throws(() => formatCodexUsage({ plan: 'team', windows: [{ usedPercent: Number.NaN, windowMinutes: 300, resetsAt: 1 }] }), /응답 형식이 올바르지 않습니다/);
});

const codexLogin = (extra = {}) => ({ type: 'oauth', access: 'codex-secret', refresh: 'r', expires: 2000000000000, accountId: 'acct', ...extra });
const live = { plan_type: 'team', rate_limit: {
  primary_window: { used_percent: 4, limit_window_seconds: 18000, reset_at: 1790160069 },
  secondary_window: { used_percent: 16, limit_window_seconds: 604800, reset_at: 1790728854 },
} };
const route = responses => async url => {
  const body = url.endsWith('/usages') ? responses.hub : responses.codex;
  return body instanceof Response ? body : new Response(JSON.stringify(body));
};

test('codex credentials come only from the openai-codex login in hac auth.json', t => {
  assert.deepEqual(codexCredentials({ root: fixture(t, { auth: { 'openai-codex': codexLogin() } }) }), { access: 'codex-secret', accountId: 'acct' });
  assert.throws(() => codexCredentials({ root: fixture(t) }), /hac에 연결된 Codex 로그인이 없습니다/);
  assert.deepEqual(codexCredentials({ root: fixture(t, { auth: { 'openai-codex': codexLogin({ expires: 1000 }) } }) }), { access: 'codex-secret', accountId: 'acct' });
});

test('codex usage is fetched with the hac login and parsed', async () => {
  const usage = await fetchCodexUsage({ access: 'codex-secret', accountId: 'acct', fetchImpl: async (url, options) => {
    assert.equal(url, 'https://chatgpt.com/backend-api/wham/usage');
    assert.equal(options.headers.Authorization, 'Bearer codex-secret');
    assert.equal(options.headers['ChatGPT-Account-Id'], 'acct');
    assert.equal(options.redirect, 'error');
    return new Response(JSON.stringify(live));
  } });
  assert.deepEqual(usage, { plan: 'team', windows: [
    { usedPercent: 4, windowMinutes: 300, resetsAt: 1790160069 },
    { usedPercent: 16, windowMinutes: 10080, resetsAt: 1790728854 },
  ] });
  await assert.rejects(fetchCodexUsage({ access: 'codex-secret', accountId: 'a', fetchImpl: async () => new Response('codex-secret', { status: 401 }) }),
    error => /401/.test(error.message) && !error.message.includes('codex-secret'));
});

test('codex usage falls back to the Codex API path and includes additional limits', async () => {
  let requests = 0;
  const result = await fetchCodexUsage({ access: 'codex-secret', accountId: 'acct', fetchImpl: async url => {
    requests++;
    if (requests === 1) return new Response('', { status: 404 });
    return new Response(JSON.stringify({
      plan_type: 'team',
      rate_limits: { rate_limit: { allowed: false } },
      rate_limit: { primary_window: live.rate_limit.primary_window },
      additional_rate_limits: [{ details: { primary_window: { used_percent: 2, limit_window_seconds: 3600, reset_at: 1790160069 } } }],
      rate_limit_reset_credits: { available: 2 },
    }));
  } });
  assert.equal(requests, 2);
  assert.equal(result.allowed, false);
  assert.equal(result.resetCredits, 2);
  assert.equal(result.windows.length, 1);
  assert.deepEqual(result.groups, [{ name: 'additional_rate_limits', windows: [{ usedPercent: 2, windowMinutes: 60, resetsAt: 1790160069 }] }]);
  assert.match(formatCodexUsage(result), /제한된 상태입니다/);
  assert.match(formatCodexUsage(result), /초기화 크레딧 2개/);
});

test('codex limits outside the main rate limit are shown as separate named groups', async () => {
  const result = await fetchCodexUsage({ access: 'codex-secret', accountId: 'acct', fetchImpl: async () => new Response(JSON.stringify({
    ...live,
    code_review_rate_limit: null,
    additional_rate_limits: [{ limit_name: 'spark', rate_limit: { primary_window: { used_percent: 2, limit_window_seconds: 3600, reset_at: 1790160069 } } }],
    chatpass: { windows: [
      { used_percent: 0, limit_window_seconds: 604800, reset_at: 1790728854 },
      { used_percent: 0, limit_window_seconds: 18000, reset_at: 1790160069 },
    ] },
  })) });
  assert.equal(result.windows.length, 2);
  assert.deepEqual(result.groups.map(group => [group.name, group.windows.length]), [['spark', 1], ['chatpass', 2]]);
  assert.equal(formatCodexUsage(result, { timeZone: 'Asia/Seoul', now: 1790150000 * 1000 }), [
    'Codex 사용현황 — team 플랜',
    '  5시간 [█░░░░░░░░░░░░░░░░░░░]   4%   19:41 (2시간 47분)',
    '  주간  [███░░░░░░░░░░░░░░░░░]  16%   09-30 09:40 (6일 16시간 47분)',
    '  spark 한도',
    '  1시간 [░░░░░░░░░░░░░░░░░░░░]   2%   19:41 (2시간 47분)',
    '  chatpass 한도',
    '  5시간 [░░░░░░░░░░░░░░░░░░░░]   0%   19:41 (2시간 47분)',
    '  주간  [░░░░░░░░░░░░░░░░░░░░]   0%   09-30 09:40 (6일 16시간 47분)',
  ].join('\n'));
});

test('codex reset credits are read from available_count', async () => {
  const result = await fetchCodexUsage({ access: 'codex-secret', accountId: 'acct', fetchImpl: async () => new Response(JSON.stringify({
    ...live, rate_limit_reset_credits: { available_count: 1, applicable_available_count: 0 },
  })) });
  assert.equal(result.resetCredits, 1);
  assert.match(formatCodexUsage(result), /초기화 크레딧 1개/);
});

test('usage delegates expired Codex login refresh to Pi and uses its persisted credentials', async t => {
  const root = fixture(t, { auth: { 'openai-codex': codexLogin({ access: 'old-access', refresh: 'old-refresh', expires: 1000 }) } });
  let usageRequest = false;
  let piExecutable;
  const result = await usageFor({ root, provider: 'openai-codex', now: 2000, piExecutable: '/managed/pi', timeZone: 'UTC', runPiAuth: async options => {
    piExecutable = options.piExecutable;
    const auth = JSON.parse(readFileSync(join(root, 'auth.json'), 'utf8'));
    auth['openai-codex'] = codexLogin({ access: 'new-access', refresh: 'new-refresh', expires: 3000000000 });
    writeFileSync(join(root, 'auth.json'), JSON.stringify(auth));
  }, fetchImpl: async (url, options) => {
    usageRequest = true;
    assert.equal(options.headers.Authorization, 'Bearer new-access');
    return new Response(JSON.stringify(live));
  } });
  assert.equal(piExecutable, '/managed/pi');
  assert.equal(usageRequest, true);
  assert.match(result, /Codex 사용현황/);
  const saved = JSON.parse(readFileSync(join(root, 'auth.json'), 'utf8'))['openai-codex'];
  assert.equal(saved.access, 'new-access');
  assert.equal(saved.refresh, 'new-refresh');
});

test('expired Codex usage reports a refresh failure without a managed Pi', async t => {
  const root = fixture(t, { auth: { 'openai-codex': codexLogin({ expires: 1000 }) } });
  await assert.rejects(usageFor({ root, provider: 'openai-codex', now: 2000, fetchImpl: async () => assert.fail('usage must not be requested') }), /관리 Pi/);
});

test('codex format labels 5-hour and weekly windows', () => {
  assert.equal(formatCodexUsage({ plan: 'team', windows: [
    { usedPercent: 4, windowMinutes: 300, resetsAt: 1790160069 },
    { usedPercent: 16, windowMinutes: 10080, resetsAt: 1790728854 },
  ] }, { timeZone: 'Asia/Seoul', now: 1790150000 * 1000 }), [
    'Codex 사용현황 — team 플랜',
    '  5시간 [█░░░░░░░░░░░░░░░░░░░]   4%   19:41 (2시간 47분)',
    '  주간  [███░░░░░░░░░░░░░░░░░]  16%   09-30 09:40 (6일 16시간 47분)',
  ].join('\n'));
});

test('usageFor routes the current provider to AI Hub or Codex', async t => {
  const root = fixture(t, { auth: { gabia: { type: 'api_key', key: 'k' }, 'openai-codex': codexLogin() } });
  const fetchImpl = route({ hub: usage(), codex: live });
  assert.match(await usageFor({ root, provider: 'gabia', fetchImpl, timeZone: 'UTC' }), /AI Hub 사용현황/);
  assert.match(await usageFor({ root, provider: 'openai-codex', fetchImpl, timeZone: 'UTC' }), /Codex 사용현황 — team 플랜/);
});

test('usage report forwards the managed Pi refresh hook', async t => {
  const root = fixture(t, { auth: { 'openai-codex': codexLogin({ expires: 1000 }) } });
  let piExecutable;
  const report = await usageReport({ root, now: 2000, piExecutable: '/managed/pi', runPiAuth: async options => {
    piExecutable = options.piExecutable;
    const auth = JSON.parse(readFileSync(join(root, 'auth.json'), 'utf8'));
    auth['openai-codex'] = codexLogin({ expires: 3000000000 });
    writeFileSync(join(root, 'auth.json'), JSON.stringify(auth));
  }, timeZone: 'UTC', fetchImpl: route({ hub: usage(), codex: live }) });
  assert.equal(piExecutable, '/managed/pi');
  assert.equal(report.failed, false);
  assert.match(report.text, /Codex 사용현황/);
});

test('report covers only providers connected in hac, default first', async t => {
  const hubOnly = await usageReport({ root: fixture(t), timeZone: 'UTC', fetchImpl: route({ hub: usage(), codex: live }) });
  assert.equal(hubOnly.failed, false);
  assert.ok(!hubOnly.text.includes('Codex'));
  const root = fixture(t, { auth: { gabia: { type: 'api_key', key: 'k' }, 'openai-codex': codexLogin() }, settings: { defaultProvider: 'openai-codex' } });
  const both = await usageReport({ root, timeZone: 'UTC', fetchImpl: route({ hub: new Response('', { status: 500 }), codex: live }) });
  assert.equal(both.failed, true);
  assert.ok(both.text.indexOf('Codex 사용현황') < both.text.indexOf('AI Hub: AI Hub 사용현황 요청에 실패했습니다(HTTP 500).'));
  const none = await usageReport({ root: fixture(t, { auth: {} }), fetchImpl: async () => assert.fail('no request') });
  assert.equal(none.failed, true);
  assert.match(none.text, /hac에 연결된 AI Hub 키나 Codex 로그인이 없습니다/);
});

test('usage report returns a friendly configuration error', async t => {
  const root = fixture(t);
  writeFileSync(join(root, 'auth.json'), '{broken');
  const report = await usageReport({ root });
  assert.equal(report.failed, true);
  assert.match(report.text, /설정을 읽지 못했습니다/);
  assert.match(report.text, /auth.json/);
});

test('bars clamp overuse and color by level only when requested', () => {
  const codex = percent => formatCodexUsage({ plan: 'team', windows: [{ usedPercent: percent, windowMinutes: 300, resetsAt: 1790160069 }] }, { timeZone: 'UTC', color: true });
  assert.match(formatCodexUsage({ plan: 'team', windows: [{ usedPercent: 130, windowMinutes: 300, resetsAt: 1790160069 }] }, { timeZone: 'UTC' }), /\[████████████████████\] 130%/);
  assert.match(codex(50), /\x1b\[32m/);
  assert.match(codex(80), /\x1b\[33m/);
  assert.match(codex(95), /\x1b\[31m/);
  assert.ok(!formatUsage(usage().data, { timeZone: 'UTC' }).includes('\x1b['));
});

test('remaining time pads minutes, adds days and never goes negative', () => {
  const row = resetsAt => formatCodexUsage({ plan: 'team', windows: [{ usedPercent: 1, windowMinutes: 300, resetsAt }] }, { timeZone: 'UTC', now: 1_000_000 * 1000 });
  assert.match(row(1_000_000 + 5 * 60 + 59), /\(0시간 05분\)$/);
  assert.match(row(1_000_000 + 86400 + 3600), /\(1일 1시간 00분\)$/);
  assert.match(row(1_000_000 - 60), /\(0시간 00분\)$/);
});
