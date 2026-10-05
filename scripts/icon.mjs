import { spawnSync } from 'node:child_process';
import { mkdtemp, mkdir, rm } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';

if (process.platform !== 'darwin') throw new Error('Generate the app icon on macOS.');
const scratch = await mkdtemp(join(tmpdir(), 'grokbot-icon-'));
const iconset = join(scratch, 'GrokbotWidget.iconset');
try {
  await mkdir(iconset);
  for (const size of [16, 32, 128, 256, 512]) {
    for (const scale of [1, 2]) {
      const pixels = size * scale;
      const file = `icon_${size}x${size}${scale === 2 ? '@2x' : ''}.png`;
      const resize = spawnSync('sips', ['-z', String(pixels), String(pixels), resolve('assets/logo.png'), '--out', join(iconset, file)], { stdio: 'ignore' });
      if (resize.status !== 0) throw new Error(`Could not generate ${file}.`);
    }
  }
  const convert = spawnSync('iconutil', ['-c', 'icns', iconset, '-o', resolve('assets/GrokbotWidget.icns')], { stdio: 'inherit' });
  if (convert.status !== 0) throw new Error('Could not generate the ICNS bundle.');
} finally {
  await rm(scratch, { recursive: true, force: true });
}
