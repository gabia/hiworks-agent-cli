import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, statSync, rmSync, chmodSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { connectAiHub } from '../lib/hac-ai-hub.mjs';

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'hac-ai-hub-test-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  writeFileSync(join(root, 'auth.json'), JSON.stringify({ other: { type: 'api_key', key: 'keep' } }));
  writeFileSync(join(root, 'models.json'), JSON.stringify({ providers: { other: { models: [] } } }));
  writeFileSync(join(root, 'settings.json'), JSON.stringify({ theme: 'dark' }));
  return root;
}
const read = (root, name) => JSON.parse(readFileSync(join(root, name), 'utf8'));
const response = () => new Response(JSON.stringify({ data: [{ id: 'glm', max_input_tokens: 1048576, max_tokens: 0 }] }), { status: 200 });

test('connecting makes an existing shared configuration directory private', async t => {
  const root = fixture(t);
  chmodSync(root, 0o755);
  await connectAiHub({ root, key: 'test-secret', fetchImpl: response });
  assert.equal(statSync(root).mode & 0o777, 0o700);
});

test('connect verifies credentials and merges default glm without losing existing settings', async t => {
  const root = fixture(t);
  const result = await connectAiHub({ root, key: 'test-secret', fetchImpl: async (url, options) => {
    assert.equal(url, 'https://ai-hub.gabia.com/v1/models');
    assert.equal(options.headers.Authorization, 'Bearer test-secret');
    assert.equal(options.redirect, 'error');
    return response();
  }});
  assert.equal(result.model, 'glm');
  assert.equal(read(root, 'settings.json').theme, 'dark');
  assert.equal(read(root, 'settings.json').defaultModel, 'glm');
  assert.equal(read(root, 'auth.json').other.key, 'keep');
  assert.equal(read(root, 'auth.json').gabia.key, 'test-secret');
  assert.equal(statSync(join(root, 'auth.json')).mode & 0o777, 0o600);
  assert.ok(read(root, 'models.json').providers.other);
  assert.equal(read(root, 'models.json').providers.gabia.models[0].contextWindow, 1048576);
  assert.ok(!readFileSync(join(root, 'models.json'), 'utf8').includes('test-secret'));
});

test('bad credentials and unknown models leave files unchanged', async t => {
  for (const fetchImpl of [async () => new Response('', { status: 401 }), async () => new Response('{"data":[]}')]) {
    const root = fixture(t);
    const before = ['auth.json', 'models.json', 'settings.json'].map(n => readFileSync(join(root, n), 'utf8'));
    await assert.rejects(connectAiHub({ root, key: 'test-secret', fetchImpl }));
    assert.deepEqual(['auth.json', 'models.json', 'settings.json'].map(n => readFileSync(join(root, n), 'utf8')), before);
  }
});

test('invalid existing JSON is not overwritten', async t => {
  const root = fixture(t);
  writeFileSync(join(root, 'settings.json'), '{broken');
  await assert.rejects(connectAiHub({ root, key: 'test-secret', fetchImpl: response }), /settings.json/);
  assert.equal(readFileSync(join(root, 'settings.json'), 'utf8'), '{broken');
});

test('refuses insecure endpoints before sending credentials', async t => {
  const root = fixture(t);
  await assert.rejects(connectAiHub({ root, key: 'test-secret', url: 'http://example.com/v1', fetchImpl: () => { throw Error('must not fetch'); } }), /HTTPS/);
});

test('second connection updates model without duplicating entries', async t => {
  const root = fixture(t);
  const opts = { root, key: 'test-secret', fetchImpl: response };
  await connectAiHub(opts);
  await connectAiHub(opts);
  assert.equal(read(root, 'models.json').providers.gabia.models.length, 1);
});

test('an existing connection lock leaves settings untouched', async t => {
  const root = fixture(t);
  mkdirSync(join(root, '.ai-hub-connect.lock'));
  await assert.rejects(connectAiHub({ root, key: 'test-secret', fetchImpl: response }), /in progress/);
  assert.equal(read(root, 'settings.json').theme, 'dark');
  assert.equal(read(root, 'auth.json').gabia, undefined);
});

test('staging failure cleans temporary files and preserves credentials', async t => {
  const root = fixture(t);
  writeFileSync(join(root, `.models.json.ai-hub-${process.pid}`), 'occupied');
  await assert.rejects(connectAiHub({ root, key: 'test-secret', fetchImpl: response }));
  assert.equal(read(root, 'auth.json').gabia, undefined);
  assert.equal(read(root, 'settings.json').defaultModel, undefined);
});

test('reconnect preserves custom properties of the selected model', async t => {
  const root = fixture(t);
  writeFileSync(join(root, 'models.json'), JSON.stringify({ providers: { gabia: { models: [{ id: 'glm', reasoning: true, maxTokens: 4096, compat: { supportsDeveloperRole: false } }] } } }));
  await connectAiHub({ root, key: 'test-secret', fetchImpl: response });
  const model = read(root, 'models.json').providers.gabia.models[0];
  assert.equal(model.reasoning, true);
  assert.equal(model.maxTokens, 4096);
  assert.equal(model.compat.supportsDeveloperRole, false);
});
