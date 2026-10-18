const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { spawn } = require('child_process');

const dataDir = process.env.USAGEFAIRY_DATA_DIR || path.join(__dirname, 'data');
const dataFile = path.join(dataDir, 'allowances.json');
const historyFile = path.join(dataDir, 'weekly-history.jsonl');
const claudeDesktopFile = path.join(dataDir, 'claude-desktop-usage.json');
const claudePeekCooldownMs = 15 * 60 * 1000;
const now = () => Date.now();
const remaining = used => Number.isFinite(Number(used))
  ? Math.max(0, Math.min(100, Math.round(100 - Number(used)))) : null;
let lastClaudeLiveAt = 0;
let lastClaudeAutoPeekAt = 0;
try { lastClaudeLiveAt = Number(JSON.parse(fs.readFileSync(claudeDesktopFile, 'utf8')).sampledAt) || 0; } catch {}

function codexExecutable(platform = process.platform, env = process.env, home = os.homedir()) {
  if (env.CODEX_BIN && fs.existsSync(env.CODEX_BIN)) return env.CODEX_BIN;
  if (platform !== 'win32') {
    const candidates = [
      '/Applications/Codex.app/Contents/Resources/codex',
      ...(env.PATH || '').split(path.delimiter).filter(Boolean).map(dir => path.join(dir, 'codex')),
      ...['/opt/homebrew/bin', '/usr/local/bin', path.join(home, '.local', 'bin'), path.join(home, '.volta', 'bin')].map(dir => path.join(dir, 'codex'))
    ];
    for (const root of [path.join(home, '.nvm', 'versions', 'node'), path.join(home, '.local', 'share', 'nvm')]) {
      try {
        for (const name of fs.readdirSync(root).filter(name => /^v\d+\.\d+\.\d+$/.test(name)).sort((a, b) => b.localeCompare(a, undefined, { numeric: true }))) {
          candidates.push(path.join(root, name, 'bin', 'codex'));
        }
      } catch {}
    }
    for (const file of candidates) {
      try {
        fs.accessSync(file, fs.constants.X_OK);
        if (fs.statSync(file).isFile()) return file;
      } catch {}
    }
    throw new Error('Install Codex CLI or set CODEX_BIN');
  }
  const binRoot = path.join(env.LOCALAPPDATA || '', 'OpenAI', 'Codex', 'bin');
  const candidates = fs.readdirSync(binRoot)
    .map(name => path.join(binRoot, name, 'codex.exe'))
    .filter(fs.existsSync)
    .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
  if (!candidates.length) throw new Error('Codex executable unavailable');
  return candidates[0];
}

function claudeHistoryFile(platform = process.platform, env = process.env, home = os.homedir()) {
  const base = platform === 'darwin' ? path.join(home, 'Library', 'Application Support') : env.APPDATA;
  return base ? path.join(base, 'Claude', 'plan-usage-history.json') : null;
}

function fetchCodex() {
  return new Promise((resolve, reject) => {
    const child = spawn(codexExecutable(), ['app-server', '--stdio'], {
      stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true
    });
    let buffer = '';
    let settled = false;
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      child.kill();
      error ? reject(error) : resolve(value);
    };
    const timer = setTimeout(() => finish(new Error('Codex timeout')), 12000);
    child.on('error', error => finish(error));
    child.on('exit', code => { if (!settled) finish(new Error(`Codex exited ${code}`)); });
    child.stdout.on('data', chunk => {
      buffer += chunk.toString();
      while (buffer.includes('\n')) {
        const end = buffer.indexOf('\n');
        const line = buffer.slice(0, end).trim();
        buffer = buffer.slice(end + 1);
        if (!line) continue;
        let message;
        try { message = JSON.parse(line); } catch { continue; }
        if (message.id === 1) {
          child.stdin.write(JSON.stringify({ method: 'initialized' }) + '\n');
          child.stdin.write(JSON.stringify({ id: 2, method: 'account/rateLimits/read', params: {} }) + '\n');
        } else if (message.id === 2) {
          if (message.error) {
            const rejected = /\b401\b|unauthorized|not logged in/i.test(message.error.message || '');
            return finish(new Error(rejected ? 'Codex sign-in rejected; sign in again on this computer' : 'Codex rate-limit read failed'));
          }
          const result = message.result || {};
          const bucket = result.rateLimitsByLimitId?.codex || result.rateLimits;
          const windows = [bucket?.primary, bucket?.secondary].filter(Boolean);
          const weekly = windows.find(value => value.windowDurationMins >= 10000);
          if (!weekly) return finish(new Error('Codex weekly limit missing'));
          finish(null, { remainingPercent: remaining(weekly.usedPercent), sampledAt: now(), resetsAt: weekly.resetsAt * 1000 });
        }
      }
    });
    child.stderr.on('data', () => {});
    child.stdin.write(JSON.stringify({ id: 1, method: 'initialize', params: {
      clientInfo: { name: 'UsageFairy', version: '1.0' }, capabilities: {}
    } }) + '\n');
  });
}

function decryptZCode(value) {
  const prefix = 'enc:v1:';
  if (!value.startsWith(prefix)) return value;
  const [iv, tag, encrypted] = value.slice(prefix.length).split('.');
  const secret = process.env.ZCODE_CREDENTIAL_SECRET ||
    `zcode-credential-fallback:${os.platform()}:${os.homedir()}:${os.userInfo().username}`;
  const key = crypto.createHash('sha256').update(secret).digest();
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(iv, 'base64url'));
  decipher.setAuthTag(Buffer.from(tag, 'base64url'));
  return Buffer.concat([decipher.update(Buffer.from(encrypted, 'base64url')), decipher.final()]).toString('utf8');
}

async function fetchZCode() {
  const file = path.join(os.homedir(), '.zcode', 'v2', 'credentials.json');
  const credentials = JSON.parse(fs.readFileSync(file, 'utf8'));
  const entry = Object.entries(credentials).find(([name]) => name.endsWith(':api-key') && name.includes(':zai-'));
  if (!entry || typeof entry[1] !== 'string') throw new Error('ZCode Coding Plan credential missing');
  const apiKey = decryptZCode(entry[1]);
  const response = await fetch('https://api.z.ai/api/monitor/usage/quota/limit', {
    headers: { Authorization: `Bearer ${apiKey}` }, signal: AbortSignal.timeout(10000)
  });
  const body = await response.json();
  if (!response.ok || body.code !== 200 || !body.success) throw new Error('ZCode usage unavailable');
  const weekly = (body.data?.limits || []).find(item =>
    (item.type === 'CREDIT_LIMIT' || item.type === 'TOKENS_LIMIT') &&
    Number(item.unit) === 6 && Number(item.number) === 1);
  if (!weekly) throw new Error('ZCode weekly limit missing');
  return { remainingPercent: remaining(weekly.percentage), sampledAt: now(), resetsAt: weekly.nextResetTime };
}

async function fetchClaude() {
  try {
    const allowPeek = now() - Math.max(lastClaudeLiveAt, lastClaudeAutoPeekAt) >= claudePeekCooldownMs;
    const desktop = await readClaudeDesktop(allowPeek);
    lastClaudeLiveAt = desktop.sampledAt;
    fs.writeFileSync(claudeDesktopFile, JSON.stringify(desktop));
    return desktop;
  } catch {}

  const candidates = [];
  try {
    const cached = JSON.parse(fs.readFileSync(claudeDesktopFile, 'utf8'));
    if (now() - cached.sampledAt < 12 * 60 * 60 * 1000 &&
        Number.isFinite(Number(cached.remainingPercent))) {
      candidates.push({ ...cached, stale: true });
    }
  } catch {}

  // Claude Desktop may also update this file without a Claude Code login.
  const historyFile = claudeHistoryFile();
  if (historyFile && fs.existsSync(historyFile)) {
    const history = JSON.parse(fs.readFileSync(historyFile, 'utf8'));
    const latest = history.samples?.at(-1);
    if (latest && now() - Number(latest.t) < 12 * 60 * 60 * 1000 && Number.isFinite(Number(latest.u?.sd))) {
      candidates.push({ remainingPercent: remaining(latest.u.sd),
        sampledAt: Number(latest.t), resetsAt: null,
        stale: now() - Number(latest.t) >= 35 * 60 * 1000 });
    }
  }
  if (candidates.length) return candidates.sort((a, b) => b.sampledAt - a.sampledAt)[0];
  throw new Error(process.platform === 'darwin'
    ? 'Open Claude Usage; allow UsageFairy in Accessibility'
    : 'Claude current local usage unavailable');
}

function resetTimeFromLabel(label) {
  const match = /^Resets (Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Mon|Tue|Wed|Thu|Fri|Sat|Sun) (\d{1,2}):(\d{2}) ([AP]M)$/.exec(label || '');
  if (!match) return null;
  const weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const day = match[1].length === 3 ? weekdays.find(name => name.startsWith(match[1])) : match[1];
  const hour = Number(match[2]) % 12 + (match[4] === 'PM' ? 12 : 0);
  const reset = new Date();
  reset.setHours(hour, Number(match[3]), 0, 0);
  reset.setDate(reset.getDate() + (weekdays.indexOf(day) - reset.getDay() + 7) % 7);
  if (reset.getTime() <= now()) reset.setDate(reset.getDate() + 7);
  return reset.getTime();
}

function readClaudeDesktop(allowPeek) {
  return new Promise((resolve, reject) => {
    const helper = path.join(__dirname, 'ClaudeDesktopUsage.ps1');
    const isMac = process.platform === 'darwin';
    const executable = isMac ? process.env.USAGEFAIRY_MAC_HELPER : 'powershell.exe';
    if (!executable) return reject(new Error('UsageFairy Mac helper unavailable'));
    const args = isMac ? ['--read-claude'] : ['-NoProfile', '-Sta', '-ExecutionPolicy', 'Bypass', '-File', helper];
    if (allowPeek && !isMac) args.push('-PeekIfIdle');
    const child = spawn(executable, args,
      { stdio: ['ignore', 'pipe', 'ignore'], windowsHide: true });
    let output = '';
    let settled = false;
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (error) child.kill();
      error ? reject(error) : resolve(value);
    };
    const timer = setTimeout(() => finish(new Error('Claude Desktop read timeout')), 8000);
    child.on('error', error => finish(error));
    child.stdout.on('data', chunk => { output += chunk.toString(); });
    child.on('exit', code => {
      if (code !== 0) return finish(new Error('Claude Usage view unavailable'));
      try {
        const parsed = JSON.parse(output);
        if (parsed.autoPeeked) lastClaudeAutoPeekAt = now();
        if (parsed.usedPercent == null || !Number.isFinite(Number(parsed.usedPercent)))
          throw new Error('Claude usage missing');
        finish(null, { remainingPercent: remaining(parsed.usedPercent),
          sampledAt: parsed.sampledAt, resetsAt: resetTimeFromLabel(parsed.resetLabel), source: 'Claude Desktop' });
      } catch (error) { finish(error); }
    });
  });
}

function recordHourly(result) {
  const hour = new Date(result.polledAt).toISOString().slice(0, 13);
  let previous = null;
  if (fs.existsSync(historyFile)) {
    const lines = fs.readFileSync(historyFile, 'utf8').trimEnd().split(/\r?\n/);
    for (let index = lines.length - 1; index >= 0; index--) {
      try { previous = JSON.parse(lines[index]); break; } catch {}
    }
  }
  if (previous?.hour === hour) return;

  const weekly = {};
  for (const name of ['codex', 'claude', 'zcode']) {
    const reading = result[name];
    const fresh = reading && !reading.stale && reading.remainingPercent !== null &&
      Number.isFinite(Number(reading.remainingPercent)) &&
      Number.isFinite(Number(reading.sampledAt)) &&
      result.polledAt - Number(reading.sampledAt) < 45 * 60 * 1000;
    const value = fresh ? Number(reading.remainingPercent) : null;
    const previousValue = previous?.weekly?.[name]?.remainingPercent;
    weekly[name] = {
      remainingPercent: value,
      changePercentPoints: value !== null && typeof previousValue === 'number'
        ? value - previousValue : null,
      resetsAt: fresh ? reading.resetsAt ?? null : null,
      sampledAt: fresh ? reading.sampledAt : null
    };
  }
  fs.appendFileSync(historyFile, JSON.stringify({
    hour, recordedAt: new Date(result.polledAt).toISOString(), weekly
  }) + '\n');
}

async function main(quiet = false) {
  fs.mkdirSync(dataDir, { recursive: true, mode: 0o700 });
  let previous = {};
  try { previous = JSON.parse(fs.readFileSync(dataFile, 'utf8')); } catch {}
  const providers = { codex: fetchCodex, claude: fetchClaude, zcode: fetchZCode };
  const settled = await Promise.allSettled(Object.values(providers).map(fetcher => fetcher()));
  const result = { polledAt: now() };
  Object.keys(providers).forEach((name, index) => {
    const item = settled[index];
    if (item.status === 'fulfilled' && item.value.remainingPercent !== null) {
      result[name] = item.value;
    } else if (previous[name]?.sampledAt && now() - previous[name].sampledAt < 15 * 60 * 1000) {
      result[name] = { ...previous[name], stale: true };
    } else {
      result[name] = { remainingPercent: null, sampledAt: null, error: item.reason?.message || 'Unavailable' };
    }
  });
  const temp = `${dataFile}.${process.pid}.tmp`;
  fs.writeFileSync(temp, JSON.stringify(result));
  fs.renameSync(temp, dataFile);
  recordHourly(result);
  if (!quiet) console.log(JSON.stringify(Object.fromEntries(Object.entries(result).map(([key, value]) =>
    [key, value && typeof value === 'object' ? { remainingPercent: value.remainingPercent, stale: !!value.stale, error: value.error } : value]))));
}

module.exports = { codexExecutable, claudeHistoryFile, remaining, resetTimeFromLabel, dataDirectory: dataDir };

if (require.main === module) {
  const loopIndex = process.argv.indexOf('--loop');
  if (loopIndex >= 0) {
    const parentPid = Number(process.argv[loopIndex + 1]);
    let polling = false;
    async function tick() {
      if (polling) return;
      polling = true;
      try { await main(true); } catch (error) { console.error(error.message); }
      finally { polling = false; }
    }
    tick();
    setInterval(() => {
      if (parentPid > 0) {
        try { process.kill(parentPid, 0); }
        catch { process.exit(0); }
      }
      tick();
    }, 30000);
  } else {
    main().catch(error => { console.error(error.message); process.exitCode = 1; });
  }
}
