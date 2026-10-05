import { spawnSync, spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { mkdirSync, copyFileSync, writeFileSync, openSync, closeSync } from 'node:fs';
import { resolveAvatar } from './avatar.mjs';

const build = spawnSync('swift', ['build', '--package-path', 'native'], { stdio: 'inherit' });
if (build.status !== 0) process.exit(build.status ?? 1);
const bundle = resolve('.local/GrokbotWidget.app');
mkdirSync(`${bundle}/Contents/MacOS`, { recursive: true });
copyFileSync(resolve('native/.build/debug/GrokbotWidget'), `${bundle}/Contents/MacOS/GrokbotWidget`);
writeFileSync(`${bundle}/Contents/Info.plist`, `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.grokbotwidget.desktop</string>
<key>CFBundleName</key><string>GrokbotWidget</string>
<key>CFBundleExecutable</key><string>GrokbotWidget</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>`);
const avatar = await resolveAvatar(process.env);
const log = openSync(resolve('.local/widget.log'), 'a');
const app = spawn(`${bundle}/Contents/MacOS/GrokbotWidget`, [], {
  detached: true,
  stdio: ['ignore', log, log],
  env: {
    ...process.env,
    GROKBOT_PROJECT_DIR: process.cwd(),
    GROKBOT_NODE_PATH: process.execPath,
    GROKBOT_AVATAR_PATH: avatar.path,
  },
});
closeSync(log);
app.on('error', (error) => { console.error(error.message); process.exitCode = 1; });
app.on('spawn', () => {
  console.log(`Widget launched independently (${avatar.source}). Right-click the widget to quit.`);
  app.unref();
});
