import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { prepareDesktop } from './desktop.mjs';

test('desktop config uses a private versioned runtime and a loopback port', async () => {
  const root = await mkdtemp(join(tmpdir(), 'grokbot-desktop-'));
  try {
    const resources = join(root, 'resources');
    const support = join(root, 'support');
    const project = join(support, 'runtime/0.2.0/grokbot-widget');
    await mkdir(join(resources, 'grokbot-widget/bot'), { recursive: true });
    await mkdir(join(project, 'node_modules/@cursor/bdk/dist/bin'), { recursive: true });
    await writeFile(join(resources, 'grokbot-widget/package.json'), JSON.stringify({ version: '0.2.0' }));
    await writeFile(join(resources, 'grokbot-widget/package-lock.json'), '{}');
    await writeFile(join(project, 'node_modules/@cursor/bdk/dist/bin/agent-serve.js'), '');
    await writeFile(join(project, '.installed'), '0.2.0');
    await writeFile(join(support, 'settings.json'), JSON.stringify({ name: '  Release Test Fixture  ', avatarPath: '' }));
    const config = await prepareDesktop(resources, support);
    assert.equal(config.GROKBOT_AGENT_NAME, 'Release Test Fixture');
    assert.equal(config.GROKBOT_PROJECT_DIR, project);
    assert.equal(config.GROKBOT_NODE_PATH, join(resources, 'node'));
    assert.equal(config.GROKBOT_AVATAR_PATH, '');
    assert.equal(config.GROKBOT_AVATAR_CIRCULAR, '0');
    const endpoint = new URL(config.GROKBOT_BDK_URL);
    assert.equal(endpoint.hostname, '127.0.0.1');
    assert.notEqual(endpoint.port, '4317');
    assert.equal(endpoint.pathname, '/grokbot-widget');
    assert.equal(JSON.parse(await readFile(join(project, 'package.json'))).version, '0.2.0');
    await writeFile(join(support, 'settings.json'), JSON.stringify({ name: ' ' }));
    await assert.rejects(prepareDesktop(resources, support), /Choose your existing bot/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
