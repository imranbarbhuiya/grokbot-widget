import { readFile, mkdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

if (typeof Bun === 'undefined') throw new Error('Run this prototype build with Bun.');
const project = dirname(dirname(fileURLToPath(import.meta.url)));
const sdk = join(project, 'node_modules/@cursor/bdk');
const output = join(project, '.local/bdk-bun');
await mkdir(join(project, '.local'), { recursive: true });
const result = await Bun.build({
  entrypoints: [join(sdk, 'dist/bin/agent-serve.js')],
  compile: { outfile: output, autoloadPackageJson: true, autoloadTsconfig: true },
  plugins: [{ name: 'bdk-package-location', setup(build) {
    build.onLoad({ filter: /\/internal\/distribution\.js$/ }, async ({ path }) => {
      const source = await readFile(path, 'utf8');
      const original = 'return fileURLToPath(new URL("../..", import.meta.url));';
      if (!source.includes(original)) throw new Error('BDK package-location code changed; review this adapter.');
      return {
        contents: source.replace(original, 'return process.env.GROKBOT_BDK_ROOT ?? fileURLToPath(new URL("../node_modules/@cursor/bdk/", pathToFileURL(process.execPath)));'),
        loader: 'js',
      };
    });
  } }],
});
if (!result.success) throw new AggregateError(result.logs, 'Bun compilation failed.');
const validation = spawnSync(output, ['validate', '--dir', project], {
  cwd: project,
  env: { ...process.env, AGENT_SERVE_DISABLE_TSX: '1', GROKBOT_BDK_ROOT: sdk, GROKBOT_AGENT_NAME: 'Build Validation Fixture' },
  stdio: 'inherit',
});
if (validation.status !== 0) throw new Error('Compiled BDK validation failed.');
console.log('Experimental CLI built in .local/bdk-bun. It still uses the installed BDK files; it is not the release backend.');
