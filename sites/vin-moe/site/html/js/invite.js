const ALPHABET = '23456789ABCDEFGHJKMNPQRSTVWXYZ';
const LIMIT = 256 - (256 % ALPHABET.length);
const RUNNER = 'https://chat.vin.moe/invite/';
const RANDOM_CODE = /^[2-9a-hjkmnp-tv-z]{12}$/;
const OWN_CODE = /^u[A-Za-z0-9_-]{2,440}$/;
const MAX_ID = 64;
const MAX_PASSWORD = 255;
const SHORT_PASSWORD = 12;
const BAD_CHARS = /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}�]/u;

const $ = (id) => document.getElementById(id);
const ui = {
  root: $('invite'),
  form: $('own'),
  out: $('out'),
  ownId: $('own-id'),
  ownPassword: $('own-password'),
  ownNote: $('own-note'),
  secretId: $('secret-id'),
  secretPassword: $('secret-password'),
  cmdSh: $('cmd-sh'),
  cmdPs: $('cmd-ps'),
  copySh: $('copy-sh'),
  copyPs: $('copy-ps'),
};

const state = { mode: 'random', random: null, joining: null, run: 0 };

const randomCode = () => {
  const alphabet = ALPHABET.toLowerCase();
  const buf = new Uint8Array(32);
  let out = '';
  while (out.length < 12) {
    crypto.getRandomValues(buf);
    for (const b of buf) {
      if (b < LIMIT && out.length < 12) out += alphabet[b % alphabet.length];
    }
  }
  buf.fill(0);
  return out;
};

const expand = async (label, code, n) => {
  let out = '';
  for (let counter = 0; out.length < n; counter++) {
    const data = new TextEncoder().encode(`${label}:${code}:${counter}`);
    const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', data));
    for (const b of digest) {
      if (b < LIMIT && out.length < n) out += ALPHABET[b % ALPHABET.length];
    }
  }
  return out;
};

const base64url = (data) => btoa(String.fromCharCode(...data)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const unbase64url = (s) => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));
const bytes = (s) => new TextEncoder().encode(s).length;

const check = (id, password) => {
  if (!id) return 'Choose a session id.';
  if (bytes(id) > MAX_ID) return `A session id can be up to ${MAX_ID} bytes long.`;
  if (id.includes(':')) return "A session id can't have a : in it.";
  if (id.trim() !== id) return "A session id can't start or end with a space.";
  if (BAD_CHARS.test(id)) return "A session id can't have control or invisible characters in it.";
  if (!password) return 'Choose a password. Without one, the session id alone gets anyone in.';
  if (bytes(password) > MAX_PASSWORD) return `A password can be up to ${MAX_PASSWORD} bytes long.`;
  if (BAD_CHARS.test(password)) return "A password can't have control or invisible characters in it.";
  return '';
};

const decode = async (code) => {
  if (RANDOM_CODE.test(code)) {
    const pw = await expand('chat-invite-pw', code, 25);
    return { id: await expand('chat-invite-id', code, 12), password: pw.match(/.{5}/g).join('-') };
  }
  if (!OWN_CODE.test(code)) return null;
  try {
    const text = new TextDecoder('utf-8', { fatal: true }).decode(unbase64url(code.slice(1)));
    const split = text.indexOf('\n');
    if (split < 1) return null;
    const session = { id: text.slice(0, split), password: text.slice(split + 1) };
    return check(session.id, session.password) ? null : session;
  } catch {
    return null;
  }
};

const encodeOwn = (id, password) => `u${base64url(new TextEncoder().encode(`${id}\n${password}`))}`;

const clear = () => {
  for (const el of [ui.cmdSh, ui.cmdPs, ui.secretId, ui.secretPassword]) el.textContent = '';
  delete ui.copySh.dataset.copy;
  delete ui.copyPs.dataset.copy;
};

const show = (code, session) => {
  const sh = ` curl -fsSL ${RUNNER}${code} | sh`;
  const ps = `irm ${RUNNER}${code} | iex`;
  ui.cmdSh.textContent = sh.trimStart();
  ui.cmdPs.textContent = ps;
  ui.copySh.dataset.copy = sh;
  ui.copyPs.dataset.copy = ps;
  ui.secretId.textContent = session.id;
  ui.secretPassword.textContent = session.password;
  ui.out.hidden = false;
};

const render = async () => {
  const run = ++state.run;
  ui.form.hidden = Boolean(state.joining);
  ui.ownNote.classList.remove('bad');
  if (state.mode === 'random') ui.ownNote.textContent = '';

  let code;
  if (state.joining) {
    code = state.joining;
  } else if (state.mode === 'random') {
    code = state.random;
  } else {
    const id = ui.ownId.value;
    const password = ui.ownPassword.value;
    const error = check(id, password);
    ui.ownNote.textContent = error || ([...password].length < SHORT_PASSWORD
      ? `A password under ${SHORT_PASSWORD} characters can be guessed by anyone who learns the session id. A random session is safer.`
      : '');
    ui.ownNote.classList.toggle('bad', Boolean(error));
    if (error) {
      ui.out.hidden = true;
      clear();
      return;
    }
    code = encodeOwn(id, password);
  }

  const session = await decode(code);
  if (run !== state.run) return;
  if (!session) {
    ui.out.hidden = true;
    clear();
    return;
  }
  show(code, session);
};

const wipe = () => {
  state.random = state.joining = null;
  ui.ownId.value = ui.ownPassword.value = '';
  ui.ownNote.textContent = '';
  clear();
};

const join = (code) => {
  state.joining = code;
  $('sub-make').hidden = true;
  $('sub-join').hidden = false;
  $('make-own').hidden = false;
};

$('regenerate').addEventListener('click', () => {
  state.mode = 'random';
  state.random = randomCode();
  ui.ownId.value = ui.ownPassword.value = '';
  render();
});
ui.form.addEventListener('input', () => {
  state.mode = ui.ownId.value || ui.ownPassword.value ? 'own' : 'random';
  render();
});
ui.form.addEventListener('submit', (e) => e.preventDefault());

addEventListener('pagehide', wipe);
addEventListener('pageshow', (e) => {
  if (!e.persisted) return;
  state.random = randomCode();
  render();
});

const hash = location.hash.slice(1);
if (hash) {
  history.replaceState(null, '', location.pathname);
  if (RANDOM_CODE.test(hash) || OWN_CODE.test(hash)) join(hash);
}
state.random = randomCode();
ui.root.hidden = false;
render();
