const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { codexExecutable, claudeHistoryFile, remaining } = require('../TaskbarAllowancesData.js');

test('Mac finds an executable Codex CLI on PATH', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'usagefairy-test-'));
  try {
    const binary = path.join(directory, 'codex');
    fs.writeFileSync(binary, '#!/bin/sh\nexit 0\n', { mode: 0o700 });
    // An installed Codex app may take precedence on the real Mac.
    assert.ok([binary, '/Applications/Codex.app/Contents/Resources/codex'].includes(codexExecutable('darwin', { PATH: directory })));
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('explicit Codex path wins without executing it', () => {
  assert.equal(codexExecutable('darwin', { CODEX_BIN: __filename }), __filename);
});

test('Windows Codex installation discovery is unchanged', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'usagefairy-win-test-'));
  try {
    const build = path.join(directory, 'OpenAI', 'Codex', 'bin', 'test-build');
    fs.mkdirSync(build, { recursive: true });
    const binary = path.join(build, 'codex.exe');
    fs.writeFileSync(binary, 'fixture');
    assert.equal(codexExecutable('win32', { LOCALAPPDATA: directory }), binary);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('Finder-launched apps find the newest nvm Codex installation', t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'usagefairy-nvm-test-'));
  try {
    for (const version of ['v9.0.0', 'v24.0.0']) {
      const bin = path.join(directory, '.nvm', 'versions', 'node', version, 'bin');
      fs.mkdirSync(bin, { recursive: true });
      fs.writeFileSync(path.join(bin, 'codex'), '#!/bin/sh\nexit 0\n', { mode: 0o700 });
    }
    const access = fs.accessSync;
    t.mock.method(fs, 'accessSync', (file, mode) => {
      if (!file.startsWith(directory + path.sep)) throw new Error('Not a test executable');
      return access(file, mode);
    });
    assert.equal(codexExecutable('darwin', { PATH: '' }, directory), path.join(directory, '.nvm', 'versions', 'node', 'v24.0.0', 'bin', 'codex'));
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('packaged poller reads writable data outside its source bundle', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'usagefairy-data-test-'));
  try {
    const data = path.join(directory, 'Application Support', 'UsageFairy');
    const result = execFileSync(process.execPath, ['-e', 'process.stdout.write(require(process.argv[1]).dataDirectory)', path.resolve(__dirname, '..', 'TaskbarAllowancesData.js')], {
      env: { ...process.env, USAGEFAIRY_DATA_DIR: data }, encoding: 'utf8'
    });
    assert.equal(result, data);
    assert.equal(fs.existsSync(data), false);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('Claude history uses the native Mac application support directory', () => {
  assert.equal(claudeHistoryFile('darwin', {}, '/Users/test'), path.join('/Users/test', 'Library', 'Application Support', 'Claude', 'plan-usage-history.json'));
});

test('Windows Claude path still uses APPDATA', () => {
  assert.equal(claudeHistoryFile('win32', { APPDATA: '/test/roaming' }), path.join('/test/roaming', 'Claude', 'plan-usage-history.json'));
});

test('allowance readings retain percent-remaining semantics', () => {
  assert.equal(remaining(36), 64);
  assert.equal(remaining(-5), 100);
  assert.equal(remaining(150), 0);
  assert.equal(remaining(undefined), null);
});
