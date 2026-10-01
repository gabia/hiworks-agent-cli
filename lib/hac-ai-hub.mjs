import { existsSync, lstatSync, mkdirSync, readFileSync, writeFileSync, renameSync, unlinkSync, rmdirSync, statSync, chmodSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

export const DEFAULT_URL = 'https://ai-hub.gabia.com/v1';
const FILES = ['auth.json', 'models.json', 'settings.json'];
const isObject = value => value && typeof value === 'object' && !Array.isArray(value);

export function normalizeAiHubUrl(url) {
  const endpoint = new URL(url);
  if (endpoint.protocol !== 'https:' || endpoint.username || endpoint.password || endpoint.search || endpoint.hash)
    throw Error('Use an HTTPS base URL without credentials, query, or fragment');
  return endpoint.href.replace(/\/+$/, '');
}

export function load(root, name) {
  const path = join(root, name);
  if (!existsSync(path)) return {};
  if (!lstatSync(path).isFile()) throw Error(`${name} must be a regular file`);
  try {
    const value = JSON.parse(readFileSync(path, 'utf8'));
    if (!isObject(value)) throw Error();
    return value;
  } catch { throw Error(`${name} contains invalid JSON; fix it before connecting`); }
}

export async function connectAiHub({ root, key, model = 'glm', url = DEFAULT_URL, fetchImpl = fetch, selectModel, syncModels = false }) {
  url = normalizeAiHubUrl(url);
  if (!key?.trim() || /[\r\n]/.test(key)) throw Error('An API key is required');
  if (!model || /[\x00-\x1f\x7f]/.test(model)) throw Error('Invalid model ID');
  if (existsSync(root) && !lstatSync(root).isDirectory()) throw Error('Configuration root must be a directory');
  // Reject malformed user configuration before making any network request.
  for (const name of FILES) load(root, name);
  let response;
  try {
    response = await fetchImpl(`${url}/models`, {
      headers: { Authorization: `Bearer ${key.trim()}` },
      redirect: 'error', signal: AbortSignal.timeout(20000),
    });
  } catch (error) {
    const code = error.cause?.code;
    if (['SELF_SIGNED_CERT_IN_CHAIN', 'UNABLE_TO_VERIFY_LEAF_SIGNATURE', 'DEPTH_ZERO_SELF_SIGNED_CERT'].includes(code))
      throw Error('TLS certificate verification failed; use a Node.js version supporting NODE_USE_SYSTEM_CA=1 or configure NODE_EXTRA_CA_CERTS');
    throw Error('Could not reach AI Hub; check the endpoint, network, and trusted certificates');
  }
  if (!response.ok) throw Error(`AI Hub authentication/model lookup failed (HTTP ${response.status}); settings unchanged`);
  let data;
  try { data = await response.json(); } catch { throw Error('AI Hub returned invalid model JSON'); }
  if (!Array.isArray(data?.data)) throw Error('AI Hub returned invalid model list');
  const catalog = [...new Map(data.data.filter(item => item && typeof item.id === 'string' && item.id.trim() && !/[\x00-\x1f\x7f]/.test(item.id)).map(item => [item.id, item])).values()]
    .sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
  if (!catalog.length) throw Error('AI Hub returned no available models; settings unchanged');
  if (selectModel) model = await selectModel(catalog.map(item => item.id));
  const found = catalog.find(item => item.id === model);
  if (!found) throw Error(`AI Hub does not list model ${model}; settings unchanged`);
  const definitions = (syncModels ? catalog : [found]).map(item => {
    const definition = { id: item.id };
    if (Number.isSafeInteger(item.max_input_tokens) && item.max_input_tokens > 0) definition.contextWindow = item.max_input_tokens;
    if (Number.isSafeInteger(item.max_tokens) && item.max_tokens > 0) definition.maxTokens = item.max_tokens;
    return definition;
  });

  mkdirSync(root, { recursive: true, mode: 0o700 });
  chmodSync(root, 0o700);
  const lock = join(root, '.ai-hub-connect.lock');
  try { mkdirSync(lock, { mode: 0o700 }); }
  catch { throw Error('Another AI Hub configuration update is in progress'); }
  const snapshots = new Map();
  const written = [];
  const pending = [];
  try {
    const values = Object.fromEntries(FILES.map(name => [name, load(root, name)]));
    if (values['models.json'].providers !== undefined && !isObject(values['models.json'].providers))
      throw Error('models.json providers must be an object');
    values['auth.json'].gabia = { type: 'api_key', key: key.trim() };
    const providers = values['models.json'].providers ??= {};
    const previous = isObject(providers.gabia) ? providers.gabia : {};
    const previousModels = Array.isArray(previous.models) ? previous.models : [];
    const oldModels = syncModels ? [] : previousModels.filter(item => item.id !== model);
    const mergedModels = definitions.map(definition => ({...previousModels.find(item => item.id === definition.id), ...definition}));
    providers.gabia = {
      ...previous, baseUrl: url, api: 'openai-completions',
      apiKey: '!jq -er \'.gabia.key\' "$PI_CODING_AGENT_DIR/auth.json"',
      models: [...oldModels, ...mergedModels],
    };
    Object.assign(values['settings.json'], { defaultProvider: 'gabia', defaultModel: model });
    // Synchronous publication cannot interleave with signal handlers. Roll back
    // already-renamed files if any filesystem operation fails.
    for (const name of FILES) {
      const path = join(root, name);
      snapshots.set(name, existsSync(path) ? { data: readFileSync(path), mode: statSync(path).mode & 0o777 } : null);
      const temp = join(root, `.${name}.ai-hub-${process.pid}`);
      writeFileSync(temp, JSON.stringify(values[name], null, 2) + '\n', { mode: 0o600, flag: 'wx' });
      pending.push(temp);
    }
    for (let index = 0; index < FILES.length; index++) {
      renameSync(pending[index], join(root, FILES[index]));
      written.push(FILES[index]);
    }
  } catch (error) {
    for (const name of written.reverse()) {
      const path = join(root, name);
      const snapshot = snapshots.get(name);
      if (snapshot) {
        const temp = `${path}.restore-${process.pid}`;
        writeFileSync(temp, snapshot.data, { mode: snapshot.mode, flag: 'wx' });
        renameSync(temp, path);
      } else unlinkSync(path);
    }
    throw error;
  } finally {
    for (const temp of pending) if (existsSync(temp)) unlinkSync(temp);
    rmdirSync(lock);
  }
  return { provider: 'gabia', model, url, modelCount: definitions.length };
}

export async function readKey(hidden, label = 'AI Hub API key (hidden): ') {
  if (!hidden) {
    let value = '';
    for await (const chunk of process.stdin) {
      value += chunk;
      if (value.length > 4096) throw Error('API key input is too long');
    }
    return value.trim();
  }
  if (!process.stdin.isTTY) throw Error('No saved API key; use --api-key-stdin or run in a terminal');
  const wasRaw = process.stdin.isRaw;
  process.stdin.setRawMode(true);
  process.stderr.write(label);
  process.stdin.resume();
  return new Promise((resolve, reject) => {
    let value = '';
    const finish = (error) => {
      process.stdin.off('data', onData);
      process.stdin.setRawMode(wasRaw);
      process.stdin.pause();
      process.stderr.write('\n');
      error ? reject(error) : resolve(value.trim());
    };
    const onData = chunk => {
      for (const character of chunk.toString('utf8')) {
        if (character === '\r' || character === '\n') return finish();
        if (character === '\u0003' || character === '\u0004') return finish(Error('Cancelled'));
        if (character === '\u007f' || character === '\b') value = value.slice(0, -1);
        else value += character;
        if (value.length > 4096) return finish(Error('API key input is too long'));
      }
    };
    process.stdin.on('data', onData);
  });
}

async function main(args) {
  if (args[0] === 'connect') args = args.slice(1);
  if (args.includes('--help') || args.includes('-h')) {
    console.log('Usage: hac ai-hub connect [--model glm] [--url HTTPS_URL] [--api-key-stdin]\n\nDefaults: Gabia AI Hub, glm. Reuses a saved key or prompts with hidden input.\n--api-key-stdin replaces the key from standard input. Existing settings are preserved.');
    return;
  }
  let model = 'glm', url = DEFAULT_URL, stdin = false;
  while (args.length) {
    const option = args.shift();
    if (option === '--api-key-stdin') stdin = true;
    else if (option === '--model' || option === '--url') {
      const value = args.shift();
      if (!value || value.startsWith('--')) throw Error(`${option} requires a value`);
      if (option === '--model') model = value; else url = value;
    } else throw Error('Unknown option; run hac ai-hub --help');
  }
  const root = join(homedir(), '.config', 'hiworks-agent-cli');
  const auth = load(root, 'auth.json');
  // Never reuse a saved credential with a different endpoint implicitly.
  const prior = load(root, 'models.json').providers?.gabia;
  const sameEndpoint = (prior?.baseUrl ?? DEFAULT_URL).replace(/\/+$/, '') === url.replace(/\/+$/, '');
  const stored = sameEndpoint && auth.gabia?.type === 'api_key' ? auth.gabia.key : undefined;
  const key = stdin ? await readKey(false) : stored || await readKey(true);
  const result = await connectAiHub({ root, key, model, url });
  console.log(`AI Hub connected: ${result.provider}/${result.model}\nEndpoint: ${result.url}\nDefault saved. Run hac to start.`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).catch(error => {
    console.error(`hac ai-hub: ${error.message}`);
    process.exitCode = 1;
  });
}
