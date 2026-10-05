import { readdir, readFile, lstat, stat } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { homedir } from 'node:os';

export async function resolveAvatar(env, userData = join(homedir(), 'Library/Application Support/Grok Bot')) {
  if (env.GROKBOT_AVATAR_PATH) {
    const path = resolve(env.GROKBOT_AVATAR_PATH);
    try {
      if ((await stat(path)).isFile()) return { path, source: 'custom image' };
    } catch (error) {
      if (error.code !== 'ENOENT') console.warn('Custom avatar is unavailable; checking the bot cache.');
    }
  }
  const name = env.GROKBOT_AGENT_NAME;
  if (!name) return { path: '', source: 'generic dot' };
  const persistence = join(userData, 'sand-client-persistence');
  const candidates = new Set();
  let matches = 0;
  try {
    for (const file of await readdir(persistence)) {
      if (!file.endsWith('.blob')) continue;
      let bits = 0, value = 0, decoded = '';
      for (const char of file.slice(0, -5).toUpperCase()) {
        const digit = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'.indexOf(char);
        if (digit < 0) { decoded = ''; break; }
        value = (value << 5) | digit;
        bits += 5;
        if (bits >= 8) {
          bits -= 8;
          decoded += String.fromCharCode((value >>> bits) & 255);
          value &= (1 << bits) - 1;
        }
      }
      if (!decoded.endsWith('.roster.last-roster')) continue;
      const path = join(persistence, file);
      const stat = await lstat(path);
      if (!stat.isFile() || stat.size > 2_000_000) continue;
      let cache;
      try { cache = JSON.parse(await readFile(path, 'utf8')); }
      catch { continue; }
      if (cache.schemaVersion !== 4 || !Array.isArray(cache.value?.rows)) continue;
      for (const row of cache.value.rows) {
        if (row?.name !== name) continue;
        matches += 1;
        const photo = row.avatarPhoto;
        if (photo?.kind !== 'file' || typeof photo.key !== 'string' || !/^[0-9a-f]{32}$/.test(photo.key)) continue;
        candidates.add(join(userData, 'roster-avatars', photo.key));
      }
    }
    if (matches === 1 && candidates.size === 1) {
      const [path] = candidates;
      const stat = await lstat(path);
      if (stat.isFile() && stat.size > 0 && stat.size <= 20_000_000) {
        return { path, source: 'cached bot avatar' };
      }
    }
  } catch {
    return { path: '', source: 'generic dot' };
  }
  return { path: '', source: 'generic dot' };
}
