import { readFile, mkdir, cp, access, open, chmod, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { resolveAvatar } from './avatar.mjs';

export async function prepareDesktop(resources, support = join(homedir(), 'Library/Application Support/Grokbot Widget')) {
  const settings = JSON.parse(await readFile(join(support, 'settings.json'), 'utf8'));
  if (typeof settings.name !== 'string' || !settings.name.trim()) throw new Error('Choose your existing bot in Settings.');
  const version = JSON.parse(await readFile(join(resources, 'grokbot-widget/package.json'), 'utf8')).version;
  const project = join(support, 'runtime', version, 'grokbot-widget');
  await mkdir(project, { recursive: true, mode: 0o700 });
  for (const file of ['package.json', 'package-lock.json', 'bot']) {
    await cp(join(resources, 'grokbot-widget', file), join(project, file), { recursive: true });
  }
  const cli = join(project, 'node_modules/@cursor/bdk/dist/bin/agent-serve.js');
  const node = join(resources, 'node');
  try { await access(join(project, ".installed")); await access(cli); }
  catch {
    const log = await open(join(support, 'runtime.log'), 'a', 0o600);
    try {
      await new Promise((resolveInstall, reject) => {
        const install = spawn(node, [join(resources, 'npm/bin/npm-cli.js'), 'ci', '--omit=dev', '--ignore-scripts', '--no-audit', '--no-fund'], {
          cwd: project,
          env: { ...process.env, PATH: `${resources}:${process.env.PATH ?? '/usr/bin:/bin'}` },
          stdio: ['ignore', log.fd, log.fd],
        });
        install.on('error', reject);
        install.on('exit', code => code === 0 ? resolveInstall() : reject(new Error('Runtime installation failed. Check your internet connection and runtime.log.')));
      });
    } finally { await log.close(); }
    await access(cli);
    await writeFile(join(project, ".installed"), version, { mode: 0o600 });
  }
  await chmod(support, 0o700);
  const avatar = await resolveAvatar({ GROKBOT_AGENT_NAME: settings.name.trim(), GROKBOT_AVATAR_PATH: settings.avatarPath || '' });
  const port = await new Promise((resolvePort, reject) => {
    const server = createServer();
    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      const port = address.port;
      server.close(error => error ? reject(error) : resolvePort(port));
    });
  });
  return {
    GROKBOT_AGENT_NAME: settings.name.trim(),
    GROKBOT_PROJECT_DIR: project,
    GROKBOT_NODE_PATH: node,
    GROKBOT_AVATAR_PATH: avatar.path,
    GROKBOT_AVATAR_CIRCULAR: avatar.source === 'cached bot avatar' ? '1' : '0',
    GROKBOT_BDK_URL: `http://127.0.0.1:${port}/grokbot-widget`,
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const resources = dirname(dirname(fileURLToPath(import.meta.url)));
  try { console.log(JSON.stringify(await prepareDesktop(resources, process.env.GROKBOT_SUPPORT_DIR))); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
