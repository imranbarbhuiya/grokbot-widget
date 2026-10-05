import { spawnSync } from 'node:child_process';
import { readFile, mkdir, cp, writeFile, mkdtemp, rm, chmod } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';

function run(command, args) {
  const result = spawnSync(command, args, { stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed (${result.status}).`);
}

if (process.platform !== 'darwin') throw new Error('Build this package on macOS.');
const { version } = JSON.parse(await readFile('package.json', 'utf8'));
if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error('Use a stable semantic version in package.json.');
const arch = process.arch;
if (!['arm64', 'x64'].includes(arch)) throw new Error('Unsupported Mac architecture.');
const output = resolve('dist');
const bundle = join(output, 'GrokbotWidget.app');
const resources = join(bundle, 'Contents/Resources');
const scratch = await mkdtemp(join(tmpdir(), 'grokbot-package-'));
try {
  const sumsResponse = await fetch('https://nodejs.org/dist/latest-v24.x/SHASUMS256.txt');
  if (!sumsResponse.ok) throw new Error('Could not retrieve the Node release checksums.');
  const sums = await sumsResponse.text();
  const match = sums.match(new RegExp(`^([a-f0-9]{64})\\s+(node-v(24\\.[0-9]+\\.[0-9]+)-darwin-${arch}\\.tar\\.gz)$`, 'm'));
  if (!match) throw new Error('No matching Node 24 macOS distribution found.');
  const [, expected, filename, nodeVersion] = match;
  const response = await fetch(`https://nodejs.org/dist/v${nodeVersion}/${filename}`);
  if (!response.ok) throw new Error('Could not download the Node runtime.');
  const archive = Buffer.from(await response.arrayBuffer());
  if (createHash('sha256').update(archive).digest('hex') !== expected) throw new Error('Node checksum mismatch.');
  const tar = join(scratch, filename);
  await writeFile(tar, archive);
  run('tar', ['-xzf', tar, '-C', scratch]);
  const nodeRoot = join(scratch, filename.slice(0, -7));
  run('swift', ['build', '-c', 'release', '--package-path', 'native']);
  const bin = spawnSync('swift', ['build', '-c', 'release', '--package-path', 'native', '--show-bin-path'], { encoding: 'utf8' });
  if (bin.status !== 0) throw new Error('Could not locate the Swift executable.');
  await rm(bundle, { recursive: true, force: true });
  await mkdir(join(bundle, 'Contents/MacOS'), { recursive: true });
  await mkdir(join(resources, 'scripts'), { recursive: true });
  await mkdir(join(resources, 'grokbot-widget'), { recursive: true });
  await mkdir(join(resources, 'licenses'), { recursive: true });
  await cp('assets/GrokbotWidget.icns', join(resources, 'GrokbotWidget.icns'));
  await cp(join(bin.stdout.trim(), 'GrokbotWidget'), join(bundle, 'Contents/MacOS/GrokbotWidget'));
  await cp(join(nodeRoot, 'bin/node'), join(resources, 'node'));
  await cp(join(nodeRoot, 'lib/node_modules/npm'), join(resources, 'npm'), { recursive: true });
  await cp(join(nodeRoot, 'LICENSE'), join(resources, 'licenses/Node-LICENSE'));
  await cp('LICENSE', join(resources, 'licenses/Widget-LICENSE'));
  for (const file of ['desktop.mjs', 'avatar.mjs']) await cp(join('scripts', file), join(resources, 'scripts', file));
  for (const file of ['package.json', 'package-lock.json', 'bot']) await cp(file, join(resources, 'grokbot-widget', file), { recursive: true });
  await chmod(join(resources, 'node'), 0o755);
  await writeFile(join(bundle, 'Contents/Info.plist'), `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.grokbotwidget.desktop</string>
<key>CFBundleName</key><string>Grokbot Widget</string>
<key>CFBundleDisplayName</key><string>Grokbot Widget</string>
<key>CFBundleExecutable</key><string>GrokbotWidget</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>GrokbotWidget</string>
<key>CFBundleShortVersionString</key><string>${version}</string>
<key>CFBundleVersion</key><string>${version}</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>`);
  run('codesign', ['--force', '--sign', '-', join(resources, 'node')]);
  run('codesign', ['--force', '--deep', '--sign', '-', bundle]);
  run('codesign', ['--verify', '--deep', '--strict', bundle]);
  run(join(resources, 'node'), ['--version']);
  run(join(resources, 'node'), [join(resources, 'npm/bin/npm-cli.js'), '--version']);
  const zip = join(output, `GrokbotWidget-macos-${arch}.zip`);
  run('ditto', ['-c', '-k', '--sequesterRsrc', '--keepParent', bundle, zip]);
  const digest = createHash('sha256').update(await readFile(zip)).digest('hex');
  await writeFile(`${zip}.sha256`, `${digest}  ${zip.split('/').at(-1)}\n`);
  console.log(`Packaged ${zip} with Node ${nodeVersion}.`);
} finally {
  await rm(scratch, { recursive: true, force: true });
}
