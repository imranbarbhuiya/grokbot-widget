import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { resolveAvatar } from './avatar.mjs';

test('custom avatar priority and safe local-cache fallbacks', async () => {
  const root = await mkdtemp(join(tmpdir(), 'grokbot-avatar-'));
  try {
    const persistence = join(root, 'sand-client-persistence');
    const avatars = join(root, 'roster-avatars');
    await mkdir(persistence);
    await mkdir(avatars);
    const key = 'a'.repeat(32);
    const image = join(avatars, key);
    await writeFile(image, Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jGZkAAAAASUVORK5CYII=', 'base64'));
    let bits = 0, value = 0, encoded = '';
    for (const byte of Buffer.from('sand.client.slice.account.test.roster.last-roster')) {
      value = (value << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        encoded += 'abcdefghijklmnopqrstuvwxyz234567'[(value >>> bits) & 31];
        value &= (1 << bits) - 1;
      }
    }
    if (bits) encoded += 'abcdefghijklmnopqrstuvwxyz234567'[(value << (5 - bits)) & 31];
    const roster = join(persistence, `${encoded}.blob`);
    const row = { name: 'Example Bot', avatarPhoto: { kind: 'file', key } };
    await writeFile(roster, JSON.stringify({ schemaVersion: 4, value: { rows: [row] } }));
    const env = { GROKBOT_AGENT_NAME: 'Example Bot' };
    assert.deepEqual(await resolveAvatar(env, root), { path: image, source: 'cached bot avatar' });
    const custom = join(root, 'custom.png');
    await writeFile(custom, await readFile(image));
    assert.deepEqual(await resolveAvatar({ ...env, GROKBOT_AVATAR_PATH: custom }, root), { path: custom, source: 'custom image' });
    assert.equal((await resolveAvatar({ ...env, GROKBOT_AVATAR_PATH: join(root, 'missing.png') }, root)).path, image);
    assert.equal((await resolveAvatar({ GROKBOT_AGENT_NAME: 'Missing Bot' }, root)).path, '');
    await writeFile(roster, JSON.stringify({ schemaVersion: 4, value: { rows: [row, { name: row.name }] } }));
    assert.equal((await resolveAvatar(env, root)).path, '');
    await writeFile(roster, JSON.stringify({ schemaVersion: 4, value: { rows: [{ ...row, avatarPhoto: { kind: 'file', key: '../custom.png' } }] } }));
    assert.equal((await resolveAvatar(env, root)).path, '');
    await writeFile(roster, '{invalid');
    assert.equal((await resolveAvatar(env, root)).path, '');
    await writeFile(roster, JSON.stringify({ schemaVersion: 5, value: { rows: [row] } }));
    assert.equal((await resolveAvatar(env, root)).path, '');
    await writeFile(roster, JSON.stringify({ schemaVersion: 4, value: { rows: [row] } }));
    await rm(image);
    assert.equal((await resolveAvatar(env, root)).path, '');
    assert.equal((await resolveAvatar(env, join(root, 'absent'))).path, '');
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
