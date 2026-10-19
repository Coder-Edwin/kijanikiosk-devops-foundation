'use strict';

// Build: syntax-check every source file, copy it to dist/, and stamp dist/build-info.json
// with the version and commit, so the published tarball says exactly what it is.
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const root = path.join(__dirname, '..');
const src = path.join(root, 'src');
const dist = path.join(root, 'dist');
const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));

fs.rmSync(dist, { recursive: true, force: true });
fs.mkdirSync(dist);

const files = fs.readdirSync(src).filter((f) => f.endsWith('.js'));
for (const file of files) {
  execFileSync(process.execPath, ['--check', path.join(src, file)], { stdio: 'inherit' });
  fs.copyFileSync(path.join(src, file), path.join(dist, file));
}

// The built package must load and expose its public API, or the build fails.
const api = require(dist);
for (const name of ['normalisePhone', 'calculateFee', 'createLedger', 'createServer']) {
  if (typeof api[name] !== 'function') throw new Error(`build output is missing ${name}()`);
}

const info = {
  name: pkg.name,
  version: pkg.version,
  commit: process.env.GIT_COMMIT || 'local',
  builtAt: new Date().toISOString(),
  node: process.version,
  files,
};
fs.writeFileSync(path.join(dist, 'build-info.json'), `${JSON.stringify(info, null, 2)}\n`);
console.log(`built ${files.length} files into dist/ for ${pkg.name}@${pkg.version}`);
