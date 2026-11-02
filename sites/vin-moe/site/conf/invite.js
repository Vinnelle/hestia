import fs from 'fs';
import crypto from 'crypto';

const ALPHABET = '23456789ABCDEFGHJKMNPQRSTVWXYZ';
const LIMIT = 256 - (256 % ALPHABET.length);
const RANDOM_CODE = /^[2-9a-hjkmnp-tv-z]{12}$/;
const OWN_CODE = /^u[A-Za-z0-9_-]{2,440}$/;
const MAX_ID = 64;
const MAX_PASSWORD = 255;
const SCRIPTS = '/usr/share/nginx/html/chat/scripts';

function expand(label, code, n) {
  let out = '';
  for (let counter = 0; out.length < n; counter++) {
    const digest = crypto.createHash('sha256').update(`${label}:${code}:${counter}`).digest();
    for (let i = 0; i < digest.length && out.length < n; i++) {
      if (digest[i] < LIMIT) out += ALPHABET[digest[i] % ALPHABET.length];
    }
  }
  return out;
}

function badChar(s) {
  for (let i = 0; i < s.length; i++) {
    const c = s.codePointAt(i);
    if (c > 0xffff) i++;
    if (c < 0x20 || (c >= 0x7f && c <= 0x9f) || c === 0xad || (c >= 0x200b && c <= 0x200f)
      || (c >= 0x2028 && c <= 0x202e) || (c >= 0x2060 && c <= 0x206f) || c === 0xfeff
      || (c >= 0xfff9 && c <= 0xfffb) || c === 0xfffd) return true;
  }
  return false;
}

function decode(code) {
  if (RANDOM_CODE.test(code)) {
    const pw = expand('chat-invite-pw', code, 25);
    return {
      id: expand('chat-invite-id', code, 12),
      password: [0, 5, 10, 15, 20].map((i) => pw.slice(i, i + 5)).join('-'),
    };
  }
  if (!OWN_CODE.test(code)) return null;
  let text;
  try {
    text = new TextDecoder('utf-8', { fatal: true }).decode(Buffer.from(code.slice(1), 'base64url'));
  } catch (e) {
    return null;
  }
  const split = text.indexOf('\n');
  if (split < 1) return null;
  const id = text.slice(0, split);
  const password = text.slice(split + 1);
  const idBytes = Buffer.byteLength(id);
  const pwBytes = Buffer.byteLength(password);
  if (idBytes > MAX_ID || pwBytes < 1 || pwBytes > MAX_PASSWORD) return null;
  if (id.includes(':') || id.trim() !== id || badChar(id) || badChar(password)) return null;
  return { id, password };
}

const quoteSh = (v) => `'${v.split("'").join("'\\''")}'`;
const quotePs = (v) => `'${v.replace(/['‘’‚‛]/g, (q) => q + q)}'`;

function fill(text, lines) {
  for (let i = 0; i < lines.length; i++) {
    const parts = text.split(lines[i][0]);
    if (parts.length !== 2) throw new Error('template');
    text = parts.join(lines[i][1]);
  }
  return text;
}

function runner(r) {
  try {
    const ua = r.headersIn['User-Agent'] || '';
    const ps = /PowerShell\//i.test(ua);
    const sh = /^(curl|wget2?)\//i.test(ua);
    if (!ps && !sh) {
      r.return(302, `https://invite.chat.vin.moe/#${r.variables.invite_code}`);
      return;
    }
    const session = decode(r.variables.invite_code);
    if (!session) {
      r.return(404, ps ? "Write-Error 'chat: this invite link is not valid'\n" : "echo 'chat: this invite link is not valid' >&2; exit 1\n");
      return;
    }
    const body = ps
      ? fill(fs.readFileSync(`${SCRIPTS}/chat.ps1`, 'utf8'), [
        ["\n    $session = ''\n", `\n    $session = ${quotePs(session.id)}\n`],
        ["\n    $password = ''\n", `\n    $password = ${quotePs(session.password)}\n`],
      ])
      : fill(fs.readFileSync(`${SCRIPTS}/chat.sh`, 'utf8'), [
        ['\nsession=\n', `\nsession=${quoteSh(session.id)}\n`],
        ['\npassword=\n', `\npassword=${quoteSh(session.password)}\n`],
      ]);
    r.headersOut['Content-Type'] = 'text/plain; charset=utf-8';
    r.return(200, body);
  } catch (e) {
    r.return(500, '');
  }
}

export default { runner, decode };
