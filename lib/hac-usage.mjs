import { execFile } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { promisify } from 'node:util';
import { load, normalizeAiHubUrl } from './hac-ai-hub.mjs';

const execFileAsync = promisify(execFile);

// Only credentials in hac's own auth.json are checked; other tools' logins may be other accounts.
// hac manages AI Hub as the `gabia` provider; its usage API is keyed by the virtual key.
const AI_HUB_PROVIDER = 'gabia';
// Pi stores the ChatGPT (Codex) login made with /login under this provider.
const CODEX_PROVIDER = 'openai-codex';
const USAGE_PROVIDERS = [AI_HUB_PROVIDER, CODEX_PROVIDER];
const PERIODS = { DAILY: '일간', WEEKLY: '주간', MONTHLY: '월간', PERMANENT: '전체' };
// ChatGPT plan limits as read by Codex itself; this is not a public API.
const CODEX_USAGE_URLS = [
  'https://chatgpt.com/backend-api/wham/usage',
  'https://chatgpt.com/api/codex/usage',
];
const CODEX_REFRESH_SKEW_MS = 60_000;
const CODEX_PI_AUTH_TIMEOUT_MS = 20_000;

const isObject = value => value && typeof value === 'object' && !Array.isArray(value);
const isFiniteNumber = value => typeof value === 'number' && Number.isFinite(value);
const errorText = error => error instanceof Error ? error.message : String(error);
const displayText = value => String(value ?? '').replace(/[\u0000-\u001f\u007f]/gu, ' ');
const validDate = value => Number.isFinite(new Date(value).getTime());

function validateAiHubUsage(data) {
  if (!isObject(data) || !isFiniteNumber(data.spend) || data.spend < 0 ||
      (data.max_budget !== undefined && data.max_budget !== null &&
        (!isFiniteNumber(data.max_budget) || data.max_budget < 0)) ||
      (data.next_budget_reset_at !== undefined && data.next_budget_reset_at !== null &&
        !validDate(data.next_budget_reset_at))) {
    throw Error('AI Hub 사용현황 응답 형식이 올바르지 않습니다.');
  }
  return data;
}

function validateCodexWindow(window) {
  if (!isObject(window) || !isFiniteNumber(window.usedPercent) || window.usedPercent < 0 ||
      !isFiniteNumber(window.windowMinutes) || window.windowMinutes <= 0 ||
      !isFiniteNumber(window.resetsAt) || window.resetsAt < 0) {
    throw Error('Codex 사용현황 응답 형식이 올바르지 않습니다.');
  }
  return window;
}

function validateCodexUsage(usage) {
  const groups = usage?.groups ?? [];
  if (!isObject(usage) || !Array.isArray(usage.windows) || !Array.isArray(groups) ||
      groups.some(group => !isObject(group) || !Array.isArray(group.windows) || !group.windows.length) ||
      (!usage.windows.length && !groups.length))
    throw Error('Codex 사용현황 응답 형식이 올바르지 않습니다.');
  usage.windows.forEach(validateCodexWindow);
  groups.forEach(group => group.windows.forEach(validateCodexWindow));
  if (usage.allowed !== undefined && typeof usage.allowed !== 'boolean')
    throw Error('Codex 사용현황 응답 형식이 올바르지 않습니다.');
  if (usage.resetCredits !== undefined && (!isFiniteNumber(usage.resetCredits) || usage.resetCredits < 0))
    throw Error('Codex 사용현황 응답 형식이 올바르지 않습니다.');
  return usage;
}

const formatTime = (date, timeZone, withDate) => {
  const part = Object.fromEntries(new Intl.DateTimeFormat('en-US', { timeZone, month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
    .formatToParts(date).map(({ type, value }) => [type, value]));
  return `${withDate ? `${part.month}-${part.day} ` : ''}${part.hour}:${part.minute}`;
};
const localTimeZone = () => Intl.DateTimeFormat().resolvedOptions().timeZone;
const remaining = (date, now) => {
  const total = Math.max(0, Math.floor((date.getTime() - now) / 60000));
  const days = Math.floor(total / 1440), hours = Math.floor(total % 1440 / 60), minutes = total % 60;
  return `${days ? `${days}일 ` : ''}${hours}시간 ${String(minutes).padStart(2, '0')}분`;
};
// Windows of a day or less reset within hours, so the time alone is unambiguous.
const resetText = (date, timeZone, now, withDate) => `${formatTime(date, timeZone, withDate)} (${remaining(date, now)})`;

/** @param {{ root: string, provider?: string, baseUrl?: string }} options */
export function resolveUsageTarget({ root, provider, baseUrl }) {
  if (!provider) throw Error('선택된 provider가 없습니다. hac setup을 실행하세요.');
  if (provider !== AI_HUB_PROVIDER) throw Error(`${provider} provider는 사용현황 조회를 지원하지 않습니다. 지원: AI Hub(${AI_HUB_PROVIDER}), Codex(${CODEX_PROVIDER})`);
  const key = load(root, 'auth.json')[provider];
  if (key?.type !== 'api_key' || !key.key) throw Error('AI Hub API 키가 없습니다. hac setup을 실행하세요.');
  const url = baseUrl ?? load(root, 'models.json').providers?.[provider]?.baseUrl;
  if (!url) throw Error('AI Hub 주소가 없습니다. hac setup을 실행하세요.');
  return { provider, baseUrl: normalizeAiHubUrl(url), key: key.key };
}

export async function fetchUsage({ baseUrl, key, fetchImpl = fetch }) {
  baseUrl = normalizeAiHubUrl(baseUrl);
  const response = await fetchImpl(`${baseUrl}/usages`, {
    headers: { Authorization: `Bearer ${key}` },
    redirect: 'error', signal: AbortSignal.timeout(20000),
  });
  if (response.status === 401 || response.status === 403) throw Error(`AI Hub가 API 키를 거부했습니다(HTTP ${response.status}). hac setup을 실행하세요.`);
  if (!response.ok) throw Error(`AI Hub 사용현황 요청에 실패했습니다(HTTP ${response.status}).`);
  let body;
  try { body = await response.json(); } catch { throw Error('AI Hub 사용현황 응답 형식이 올바르지 않습니다.'); }
  return validateAiHubUsage(body?.data);
}

// Hangul and other wide characters take two terminal columns.
const displayWidth = text => [...text].reduce((width, char) => width + (/[\u1100-\u115f\u2e80-\ua4cf\uac00-\ud7a3\uf900-\ufaff\uff00-\uff60]/u.test(char) ? 2 : 1), 0);
const BAR_WIDTH = 20;
const LABEL_WIDTH = 5;
const colorFor = percent => percent >= 90 ? 31 : percent >= 70 ? 33 : 32;

function usageRow(label, percent, percentText, detail, color) {
  const filled = Math.min(BAR_WIDTH, Math.max(0, Math.round(percent / 100 * BAR_WIDTH)));
  const paint = text => color && text ? `\x1b[${colorFor(percent)}m${text}\x1b[0m` : text;
  const bar = `[${paint('█'.repeat(filled))}${'░'.repeat(BAR_WIDTH - filled)}]`;
  return `  ${label}${' '.repeat(LABEL_WIDTH - displayWidth(label))} ${bar} ${paint(percentText.padStart(4))} ${detail}`;
}
const detailIndent = ' '.repeat(2 + LABEL_WIDTH + 1);

export function formatUsage(data, { timeZone = localTimeZone(), color = false, now = Date.now() } = {}) {
  validateAiHubUsage(data);
  const number = value => Math.round(value).toLocaleString('en-US');
  const amount = data.budget_basis === 'TOKEN' ? value => `${number(value)}` : value => `₩${number(value)}`;
  const unit = data.budget_basis === 'TOKEN' ? ' 토큰' : '';
  const lines = [`AI Hub 사용현황 — ${displayText(data.key_alias || 'API 키')}`];
  if (typeof data.max_budget === 'number' && data.max_budget > 0) {
    const percent = data.spend / data.max_budget * 100;
    lines.push(usageRow(PERIODS[data.budget_period] ?? '예산', percent, `${percent.toFixed(1)}%`, `${amount(data.spend)} / ${amount(data.max_budget)}${unit}`, color));
  } else {
    lines.push(`  이번 달  ${amount(data.spend)}${unit} (예산 정책 없음)`);
  }
  if (data.next_budget_reset_at) {
    lines.push(`${detailIndent}${resetText(new Date(data.next_budget_reset_at), timeZone, now, data.budget_period !== 'DAILY')}`);
  }
  return lines.join('\n');
}

/** @param {{ root: string }} options */
function readCodexLogin(root) {
  const login = load(root, 'auth.json')[CODEX_PROVIDER];
  if (login?.type !== 'oauth' || !login.access || !login.accountId) throw Error('hac에 연결된 Codex 로그인이 없습니다. hac에서 /login으로 ChatGPT를 연결하세요.');
  return login;
}

export function codexCredentials({ root }) {
  const login = readCodexLogin(root);
  return { access: login.access, accountId: login.accountId };
}

async function refreshCodexCredentials({ root, now, piExecutable = process.env.HAC_PI_EXECUTABLE, runPiAuth = runPiAuthCommand }) {
  if (!piExecutable) throw Error('Codex 로그인을 갱신할 관리 Pi를 찾지 못했습니다. hac에서 /login을 다시 하세요.');
  try {
    await runPiAuth({ root, piExecutable });
  } catch {
    throw Error('Pi가 Codex 로그인을 갱신하지 못했습니다. hac에서 /login을 다시 하세요.');
  }
  const refreshed = readCodexLogin(root);
  if (!isFiniteNumber(refreshed.expires) || refreshed.expires <= now)
    throw Error('Pi가 Codex 로그인 갱신 후에도 유효한 인증 정보를 저장하지 않았습니다. hac에서 /login을 다시 하세요.');
  return { access: refreshed.access, accountId: refreshed.accountId };
}

async function runPiAuthCommand({ root, piExecutable }) {
  const environment = { ...process.env, PI_CODING_AGENT_DIR: root };
  delete environment.PI_PACKAGE_DIR;
  await execFileAsync(piExecutable, ['auth', 'check', '--provider', CODEX_PROVIDER, '--json'], {
    env: environment,
    timeout: CODEX_PI_AUTH_TIMEOUT_MS,
    maxBuffer: 64 * 1024,
    windowsHide: true,
  });
}

async function ensureCodexCredentials({ root, now = Date.now(), piExecutable, runPiAuth }) {
  const login = readCodexLogin(root);
  if (isFiniteNumber(login.expires) && login.expires > now + CODEX_REFRESH_SKEW_MS)
    return { access: login.access, accountId: login.accountId };
  return refreshCodexCredentials({ root, now, piExecutable, runPiAuth });
}

function codexWindowSnapshots(data) {
  const windows = [];
  const visited = new Set();
  const visit = value => {
    if (!value || typeof value !== 'object' || visited.has(value)) return;
    visited.add(value);
    if (Array.isArray(value)) {
      value.forEach(visit);
      return;
    }
    if (isFiniteNumber(value.used_percent) && isFiniteNumber(value.limit_window_seconds) && isFiniteNumber(value.reset_at)) {
      windows.push(validateCodexWindow({
        usedPercent: value.used_percent,
        windowMinutes: Math.round(value.limit_window_seconds / 60),
        resetsAt: value.reset_at,
      }));
    }
    Object.values(value).forEach(visit);
  };
  visit(data);
  return windows.sort((a, b) => a.windowMinutes - b.windowMinutes);
}

// The Codex limits themselves; any other section of the response is a separate quota.
const CODEX_MAIN_LIMITS = ['rate_limit', 'rate_limits'];

function codexLimitGroups(data) {
  const groups = [];
  for (const [key, value] of Object.entries(isObject(data) ? data : {})) {
    if (CODEX_MAIN_LIMITS.includes(key)) continue;
    for (const entry of Array.isArray(value) ? value : [value]) {
      const windows = codexWindowSnapshots(entry);
      if (windows.length) groups.push({ name: typeof entry?.limit_name === 'string' && entry.limit_name ? entry.limit_name : key, windows });
    }
  }
  return groups;
}

function resetCreditCount(value) {
  if (isFiniteNumber(value) && value >= 0) return value;
  if (!isObject(value)) return undefined;
  for (const key of ['available_count', 'available', 'remaining', 'count'])
    if (isFiniteNumber(value[key]) && value[key] >= 0) return value[key];
  if (Array.isArray(value.credits)) return value.credits.length;
  return undefined;
}

export async function fetchCodexUsage({ access, accountId, fetchImpl = fetch }) {
  let response;
  for (const candidate of CODEX_USAGE_URLS) {
    response = await fetchImpl(candidate, {
      headers: { Authorization: `Bearer ${access}`, 'ChatGPT-Account-Id': accountId, Accept: 'application/json' },
      redirect: 'error', signal: AbortSignal.timeout(20000),
    });
    if (![404, 405].includes(response.status) || candidate === CODEX_USAGE_URLS.at(-1)) break;
  }
  if (response.status === 401 || response.status === 403) throw Error(`ChatGPT가 hac의 Codex 로그인을 거부했습니다(HTTP ${response.status}). hac에서 /login을 다시 하세요.`);
  if (!response.ok) throw Error(`Codex 사용현황 요청에 실패했습니다(HTTP ${response.status}).`);
  let data;
  try { data = await response.json(); } catch { throw Error('Codex 사용현황 응답 형식이 올바르지 않습니다.'); }
  const windows = codexWindowSnapshots(CODEX_MAIN_LIMITS.map(key => data?.[key]));
  const groups = codexLimitGroups(data);
  const rateLimit =[data?.rate_limit, data?.rate_limits?.rate_limit].find(value => isObject(value) && typeof value.allowed === 'boolean')
    ?? data?.rate_limit ?? data?.rate_limits?.rate_limit;
  const allowed = typeof rateLimit?.allowed === 'boolean' ? rateLimit.allowed : undefined;
  const resetCredits = resetCreditCount(data?.rate_limit_reset_credits);
  const usage = { plan: data?.plan_type ?? rateLimit?.plan_type, windows, groups, allowed, resetCredits };
  if (!groups.length) delete usage.groups;
  if (usage.allowed === undefined) delete usage.allowed;
  if (usage.resetCredits === undefined) delete usage.resetCredits;
  return validateCodexUsage(usage);
}

const windowLabel = minutes => minutes === 10080 ? '주간' : minutes % 1440 === 0 ? `${minutes / 1440}일` : minutes % 60 === 0 ? `${minutes / 60}시간` : `${minutes}분`;

export function formatCodexUsage(usage, { timeZone = localTimeZone(), color = false, now = Date.now() } = {}) {
  validateCodexUsage(usage);
  const lines = [`Codex 사용현황 — ${displayText(usage.plan || 'ChatGPT')} 플랜`];
  if (usage.allowed === false) lines.push('  현재 Codex 사용이 제한된 상태입니다.');
  if (usage.resetCredits !== undefined) lines.push(`  추가 초기화 크레딧 ${usage.resetCredits}개`);
  const row = w => usageRow(windowLabel(w.windowMinutes), w.usedPercent, `${w.usedPercent}%`, `  ${resetText(new Date(w.resetsAt * 1000), timeZone, now, w.windowMinutes > 1440)}`, color);
  lines.push(...usage.windows.map(row));
  for (const group of usage.groups ?? [])
    lines.push(`  ${displayText(group.name)} 한도`, ...group.windows.map(row));
  return lines.join('\n');
}

/** @param {{ root: string, provider?: string, baseUrl?: string, fetchImpl?: typeof fetch, timeZone?: string, now?: number, color?: boolean, piExecutable?: string, runPiAuth?: (options: { root: string, piExecutable: string }) => Promise<void> }} options */
export async function usageFor({ root, provider, baseUrl, fetchImpl = fetch, timeZone, now, color, piExecutable, runPiAuth }) {
  if (provider === CODEX_PROVIDER)
    return formatCodexUsage(await fetchCodexUsage({ ...await ensureCodexCredentials({ root, now, piExecutable, runPiAuth }), fetchImpl }), { timeZone, color, now });
  const target = resolveUsageTarget({ root, provider, baseUrl });
  return formatUsage(await fetchUsage({ ...target, fetchImpl }), { timeZone, color, now });
}

// Every supported provider connected in hac, default provider first.
/** @param {{ root: string, fetchImpl?: typeof fetch, timeZone?: string, now?: number, color?: boolean, piExecutable?: string, runPiAuth?: (options: { root: string, piExecutable: string }) => Promise<void> }} options */
export async function usageReport({ root, fetchImpl = fetch, timeZone, now, color, piExecutable, runPiAuth }) {
  let auth;
  let preferred;
  try {
    auth = load(root, 'auth.json');
    preferred = load(root, 'settings.json').defaultProvider;
  } catch (error) {
    return { text: `사용현황 설정을 읽지 못했습니다: ${errorText(error)}`, failed: true };
  }
  const providers = USAGE_PROVIDERS.filter(provider => auth[provider])
    .sort((a, b) => Number(b === preferred) - Number(a === preferred));
  if (!providers.length) return { text: 'hac에 연결된 AI Hub 키나 Codex 로그인이 없습니다. hac setup을 실행하거나 hac에서 /login을 사용하세요.', failed: true };
  const sections = [];
  let failed = false;
  for (const provider of providers) {
    try { sections.push(await usageFor({ root, provider, fetchImpl, timeZone, now, color, piExecutable, runPiAuth })); }
    catch (error) { failed = true; sections.push(`${provider === CODEX_PROVIDER ? 'Codex' : 'AI Hub'}: ${errorText(error)}`); }
  }
  return { text: sections.join('\n\n'), failed };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  if (args.length === 1 && ['--help', '-h'].includes(args[0])) {
    console.log('사용법: hac usage\nhac에 연결된 인증 정보의 사용현황을 보여 줍니다.\n- AI Hub: 사용액·예산·초기화 시각\n- Codex: hac에서 /login으로 연결한 ChatGPT 계정의 5시간·주간 한도\n실행 중에는 /usage로 현재 모델 provider의 사용현황을 확인합니다.');
  } else if (args.length) {
    console.error('hac usage: 알 수 없는 옵션입니다. hac usage --help를 확인하세요.');
    process.exitCode = 2;
  } else {
    // Color only on an interactive terminal; /usage notifications and pipes stay plain.
    const color = Boolean(process.stdout.isTTY) && !process.env.NO_COLOR;
    usageReport({ root: join(homedir(), '.config', 'hiworks-agent-cli'), color })
      .then(({ text, failed }) => { console.log(text); if (failed) process.exitCode = 1; });
  }
}
