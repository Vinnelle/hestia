const frame = document.getElementById('service-frame');
const home = document.getElementById('frame-empty');
const satisfactoryPage = document.getElementById('page-satisfactory');
const minecraftPage = document.getElementById('page-minecraft');
const blogPage = document.getElementById('page-blog');
const back = document.getElementById('frame-back');
const frameTitle = document.getElementById('frame-title');
const fullscreenBtn = document.getElementById('frame-fullscreen');
const routed = document.querySelectorAll('.service-link[data-url]');
const allNavLinks = document.querySelectorAll('.sidebar-link');
const sidebar = document.getElementById('sidebar');
const sidebarToggle = document.getElementById('sidebar-toggle');
const sidebarBackdrop = document.getElementById('sidebar-backdrop');
const mobileSidebarQuery = matchMedia('(max-width: 640px)');

const internalPages = {
  'gameservers/satisfactory': { el: satisfactoryPage, title: 'Satisfactory', onShow: loadSatisfactoryStatus },
  'gameservers/minecraft': { el: minecraftPage, title: 'Minecraft', onShow: loadMinecraftStatus },
  blog: { el: blogPage, title: 'Blog', onShow: loadBlogPosts },
};

function expandSectionFor(slug) {
  if (!slug) return;
  const link = allNavLinks.length && Array.from(allNavLinks).find((el) => el.dataset.slug === slug);
  const section = link && link.closest('.sidebar-section');
  if (!section) return;
  section.hidden = false;
  const btn = document.querySelector('.sidebar-section-label[data-section="' + section.dataset.section + '"]');
  if (btn) btn.setAttribute('aria-expanded', 'true');
}

function show(slug) {
  let active = null;
  for (const el of routed) {
    if (el.dataset.slug === slug) active = el;
  }

  if (active && active.dataset.frame !== '1') {
    window.open(active.dataset.url, '_blank', 'noopener,noreferrer');
    history.replaceState(null, '', location.pathname + location.search);
    active = null;
    slug = '';
  }

  for (const el of allNavLinks) {
    el.classList.toggle('active', el.dataset.slug === slug);
  }

  expandSectionFor(slug);

  const page = internalPages[slug];

  if (document.fullscreenElement) document.exitFullscreen();

  home.hidden = true;
  satisfactoryPage.hidden = true;
  minecraftPage.hidden = true;
  blogPage.hidden = true;
  frame.hidden = true;
  back.hidden = true;
  fullscreenBtn.hidden = true;

  for (const [consoleSlug, c] of Object.entries(consoles)) {
    if (consoleSlug === slug) c.start();
    else c.stop();
  }

  if (page) {
    page.el.hidden = false;
    document.title = page.title + ' — vinnel.cloud';
    page.onShow();
    return;
  }

  if (!active) {
    frame.removeAttribute('src');
    home.hidden = false;
    document.title = 'admin — vinnel.cloud';
    refresh();
    return;
  }

  frame.hidden = false;
  back.hidden = false;
  fullscreenBtn.hidden = false;
  frameTitle.textContent = active.dataset.label;
  document.title = active.dataset.label + ' — vinnel.cloud';

  if (frame.getAttribute('src') !== active.dataset.url) {
    frame.setAttribute('src', active.dataset.url);
  }
}

addEventListener('hashchange', () => show(location.hash.slice(1)));

function pushTheme() {
  const src = frame.getAttribute('src');
  if (!src || !frame.contentWindow) return;
  const theme = document.documentElement.dataset.theme;
  if (!theme) return;
  frame.contentWindow.postMessage({ vinnelTheme: theme }, new URL(src).origin);
}

new MutationObserver(pushTheme).observe(document.documentElement, {
  attributes: true,
  attributeFilter: ['data-theme'],
});

function setSidebarCollapsed(collapsed) {
  sidebar.classList.toggle('sidebar--collapsed', collapsed);
  sidebarToggle.setAttribute('aria-pressed', String(collapsed));
  sidebarBackdrop.classList.toggle('active', !collapsed && mobileSidebarQuery.matches);
}

setSidebarCollapsed(mobileSidebarQuery.matches);
sidebarToggle.addEventListener('click', () => setSidebarCollapsed(!sidebar.classList.contains('sidebar--collapsed')));
sidebarBackdrop.addEventListener('click', () => setSidebarCollapsed(true));
mobileSidebarQuery.addEventListener('change', (e) => setSidebarCollapsed(e.matches));

fullscreenBtn.addEventListener('click', () => {
  if (document.fullscreenElement) document.exitFullscreen();
  else frame.requestFullscreen().catch(() => {});
});

document.addEventListener('fullscreenchange', () => {
  const active = document.fullscreenElement === frame;
  fullscreenBtn.querySelector('.icon-expand').hidden = active;
  fullscreenBtn.querySelector('.icon-collapse').hidden = !active;
  fullscreenBtn.setAttribute('aria-pressed', String(active));
});

for (const btn of document.querySelectorAll('.sidebar-section-label')) {
  btn.addEventListener('click', () => {
    const expanded = btn.getAttribute('aria-expanded') === 'true';
    btn.setAttribute('aria-expanded', String(!expanded));
    document.querySelector('.sidebar-section[data-section="' + btn.dataset.section + '"]').hidden = expanded;
  });
}

const menuBtn = document.getElementById('user-menu-btn');
menuBtn.addEventListener('click', () => {
  const expanded = menuBtn.getAttribute('aria-expanded') === 'true';
  document.getElementById('user-dropdown').hidden = expanded;
  menuBtn.setAttribute('aria-expanded', String(!expanded));
});

const fmtBytes = (b) => {
  if (!b) return '0 B';
  const u = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  const i = Math.min(Math.floor(Math.log(b) / Math.log(1024)), u.length - 1);
  return (b / Math.pow(1024, i)).toFixed(i ? 1 : 0) + ' ' + u[i];
};
const pct = (n) => (n || 0).toFixed(0) + '%';
const text = (id, v) => { document.getElementById(id).textContent = v; };

function setMeter(id, percent) {
  const el = document.getElementById(id);
  const p = Math.max(0, Math.min(percent || 0, 100));
  el.style.width = p.toFixed(1) + '%';
  el.classList.toggle('meter--warn', p >= 75 && p < 90);
  el.classList.toggle('meter--crit', p >= 90);
}

let reauthing = false;

function reauth() {
  if (reauthing) return;
  reauthing = true;
  const snapshot = blogSnapshot();
  if (snapshot) {
    try {
      sessionStorage.setItem(BLOG_DRAFT_KEY, JSON.stringify(snapshot));
    } catch {}
  }
  location.reload();
}

async function api(path, options) {
  const res = await fetch(path, { ...options, redirect: 'manual' });
  if (res.type === 'opaqueredirect' || res.status === 401) {
    reauth();
    throw new Error('Session expired, signing in again.');
  }
  return res;
}

async function loadCluster() {
  const err = document.getElementById('cluster-error');
  try {
    const c = await (await api('/api/cluster')).json();
    err.hidden = !c.err;
    if (c.err) err.textContent = c.err;

    text('stat-nodes', c.nodesReady + ' / ' + (c.nodes || []).length);
    text('stat-pods', c.podsRunning + ' / ' + c.podsTotal);
    text('stat-cpu', pct(c.cpuTotal ? (c.cpuUsed / c.cpuTotal) * 100 : 0));
    text('stat-cpu-sub', (c.cpuUsed || 0).toFixed(1) + ' / ' + (c.cpuTotal || 0).toFixed(0) + ' cores');
    text('stat-mem', pct(c.memTotal ? (c.memUsed / c.memTotal) * 100 : 0));
    text('stat-mem-sub', fmtBytes(c.memUsed) + ' / ' + fmtBytes(c.memTotal));

    setMeter('stat-cpu-fill', c.cpuTotal ? (c.cpuUsed / c.cpuTotal) * 100 : 0);
    setMeter('stat-mem-fill', c.memTotal ? (c.memUsed / c.memTotal) * 100 : 0);
    renderStorage(c);
  } catch (e) {
    err.hidden = false;
    err.textContent = 'Could not load cluster stats.';
  }
}

function renderStorage(c) {
  const vols = c.volumes || [];
  text('stat-vols', vols.length);
  text('stat-vol-bytes', fmtBytes(c.volumeBytes));

  const rows = vols.slice().sort((a, b) => b.capacity - a.capacity);
  document.getElementById('volumes-tbody').innerHTML = rows.map((v) => {
    const bound = v.phase === 'Bound';
    return '<tr><td>' + escapeHtml(v.claim || v.name) + '</td>' +
      '<td class="dim">' + escapeHtml(v.namespace || '—') + '</td>' +
      '<td>' + fmtBytes(v.capacity) + '</td>' +
      '<td><span class="dot' + (bound ? ' dot--ok' : ' dot--bad') + '"></span>' +
      escapeHtml(v.phase || '') + '</td></tr>';
  }).join('');
}

const fmtDuration = (s) => {
  s = Math.floor(s || 0);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (h) return h + 'h ' + m + 'm';
  return m + 'm';
};

async function loadSatisfactoryStatus() {
  const err = document.getElementById('satisfactory-error');
  let s;
  try {
    s = await (await api('/api/gameservers/satisfactory')).json();
  } catch (e) {
    err.hidden = false;
    err.textContent = 'Could not load server status.';
    return;
  }

  const stopped = renderPower('sat', s.desired);

  const problems = stopped ? [] : [s.podErr, s.apiErr, s.saveErr].filter(Boolean);
  err.hidden = problems.length === 0;
  err.textContent = problems.join(' · ');

  const dot = document.getElementById('sat-status-dot');
  const up = !!(s.api && s.api.healthy);
  dot.className = 'dot' + (stopped ? '' : up ? ' dot--ok' : ' dot--bad');
  text('sat-status-text', stopped ? 'Stopped' : (up ? 'Online' : 'Offline'));
  text('sat-status-sub', stopped ? 'Scaled to 0 replicas' : (s.pod ? s.pod.phase + (s.pod.ready ? ', ready' : '') : (s.podErr || '')));

  if (s.api) {
    text('sat-players', s.api.connectedPlayers + ' / ' + s.api.playerLimit);
    text('sat-tickrate', s.api.averageTickRate ? s.api.averageTickRate.toFixed(1) + ' ticks/s' : '');
    text('sat-session', s.api.sessionName || '—');
    text('sat-phase', s.api.gamePhase || '—');
    text('sat-tier', s.api.techTier != null ? String(s.api.techTier) : '—');
  } else {
    text('sat-players', '—');
    text('sat-tickrate', '');
    text('sat-session', '—');
    text('sat-phase', '—');
    text('sat-tier', '—');
  }

  if (s.pod) {
    text('sat-resources', s.pod.cpuUsed.toFixed(2) + ' / ' + fmtBytes(s.pod.memUsed));
    text('sat-node', s.pod.node || '—');
    text('sat-image', s.pod.image || '—');
    text('sat-restarts', String(s.pod.restarts));
    text('sat-started', s.pod.startTime && s.pod.startTime !== '0001-01-01T00:00:00Z' ? new Date(s.pod.startTime).toLocaleString() : '—');
  } else {
    text('sat-resources', '—');
    text('sat-node', '—');
    text('sat-image', '—');
    text('sat-restarts', '—');
    text('sat-started', '—');
  }

  if (s.save) {
    text('sat-save-file', s.save.fileName || '—');
    text('sat-save-map', s.save.mapName || '—');
    text('sat-save-session', s.save.sessionName || '—');
    text('sat-save-playtime', fmtDuration(s.save.playDurationSeconds));
    text('sat-save-time', s.save.savedAt ? new Date(s.save.savedAt).toLocaleString() : '—');
    text('sat-save-creative', s.save.isCreativeModeEnabled ? 'Yes' : 'No');
    document.getElementById('sat-save-download').removeAttribute('hidden');
  } else {
    text('sat-save-file', '—');
    text('sat-save-map', '—');
    text('sat-save-session', '—');
    text('sat-save-playtime', '—');
    text('sat-save-time', '—');
    text('sat-save-creative', '—');
    document.getElementById('sat-save-download').setAttribute('hidden', '');
  }
}

async function loadMinecraftStatus() {
  const err = document.getElementById('minecraft-error');
  let s;
  try {
    s = await (await api('/api/gameservers/minecraft')).json();
  } catch (e) {
    err.hidden = false;
    err.textContent = 'Could not load server status.';
    return;
  }

  const stopped = renderPower('mc', s.desired);

  const problems = stopped ? [] : [s.podErr, s.pingErr].filter(Boolean);
  err.hidden = problems.length === 0;
  err.textContent = problems.join(' · ');

  if (s.address) text('mc-address', s.address);

  const up = !!s.ping;
  document.getElementById('mc-status-dot').className = 'dot' + (stopped ? '' : up ? ' dot--ok' : ' dot--bad');
  text('mc-status-text', stopped ? 'Stopped' : (up ? 'Online' : 'Offline'));
  text('mc-status-sub', stopped ? 'Scaled to 0 replicas' : (s.pod ? s.pod.phase + (s.pod.ready ? ', ready' : '') : (s.podErr || '')));

  if (s.ping) {
    text('mc-players', s.ping.playersOnline + ' / ' + s.ping.playersMax);
    text('mc-player-names', (s.ping.players || []).join(', '));
    text('mc-latency', s.ping.latencyMs + ' ms ping');
    text('mc-motd', s.ping.motd || '—');
    text('mc-version', s.ping.version ? s.ping.version + ' (protocol ' + s.ping.protocol + ')' : '—');
  } else {
    text('mc-players', '—');
    text('mc-player-names', '');
    text('mc-latency', '');
    text('mc-motd', '—');
    text('mc-version', '—');
  }

  if (s.pod) {
    text('mc-resources', s.pod.cpuUsed.toFixed(2) + ' / ' + fmtBytes(s.pod.memUsed));
    text('mc-node', s.pod.node || '—');
    text('mc-image', s.pod.image || '—');
    text('mc-restarts', String(s.pod.restarts));
    text('mc-started', s.pod.startTime && s.pod.startTime !== '0001-01-01T00:00:00Z' ? new Date(s.pod.startTime).toLocaleString() : '—');
  } else {
    text('mc-resources', '—');
    text('mc-node', '—');
    text('mc-image', '—');
    text('mc-restarts', '—');
    text('mc-started', '—');
  }
}

function renderPower(prefix, desired) {
  const stopped = desired === 0;
  const known = desired === 0 || desired === 1;
  document.getElementById(prefix + '-power-start').hidden = !known || !stopped;
  document.getElementById(prefix + '-power-stop').hidden = !known || stopped;
  document.getElementById(prefix + '-power-hint').hidden = !stopped;
  return stopped;
}

function wirePower(prefix, startUrl, stopUrl, statusLoader) {
  const startBtn = document.getElementById(prefix + '-power-start');
  const stopBtn = document.getElementById(prefix + '-power-stop');

  async function call(url) {
    startBtn.disabled = true;
    stopBtn.disabled = true;
    try {
      const r = await (await api(url, { method: 'POST' })).json();
      if (r.err) alert(r.err);
    } catch (e) {
      alert('Request failed.');
    } finally {
      startBtn.disabled = false;
      stopBtn.disabled = false;
      statusLoader();
    }
  }

  startBtn.addEventListener('click', () => call(startUrl));
  stopBtn.addEventListener('click', () => {
    if (confirm('Stop the server? Connected players will be disconnected.')) call(stopUrl);
  });
}

wirePower('sat', '/api/gameservers/satisfactory/start', '/api/gameservers/satisfactory/stop', loadSatisfactoryStatus);
wirePower('mc', '/api/gameservers/minecraft/start', '/api/gameservers/minecraft/stop', loadMinecraftStatus);

const CONSOLE_MAX_LINES = 500;

function wireConsole(prefix, endpoint, streamUrl, after) {
  const out = document.getElementById(prefix + '-console');
  const form = document.getElementById(prefix + '-console-form');
  const input = document.getElementById(prefix + '-console-input');
  const send = document.getElementById(prefix + '-console-send');
  const followBtn = document.getElementById(prefix + '-console-follow');
  const history = [];
  let historyIndex = 0;
  let stream = null;
  let streamBroken = false;
  let follow = true;

  const setFollow = (on) => {
    follow = on;
    followBtn.setAttribute('aria-pressed', String(on));
    followBtn.textContent = on ? 'Following' : 'Paused';
    if (on) out.scrollTop = out.scrollHeight;
  };

  const write = (cls, s) => {
    const line = document.createElement('div');
    if (cls) line.className = cls;
    line.textContent = s;
    out.appendChild(line);
    while (out.childElementCount > CONSOLE_MAX_LINES) out.removeChild(out.firstElementChild);
    if (follow) out.scrollTop = out.scrollHeight;
  };

  followBtn.addEventListener('click', () => setFollow(!follow));

  out.addEventListener('scroll', () => {
    const atBottom = out.scrollHeight - out.scrollTop - out.clientHeight < 40;
    if (atBottom !== follow) setFollow(atBottom);
  });

  const start = () => {
    if (stream) return;
    setFollow(true);
    stream = new EventSource(streamUrl);
    stream.addEventListener('open', () => {
      if (streamBroken) write('console-log', '— reconnected —');
      streamBroken = false;
    });
    stream.addEventListener('message', (e) => write('console-log', e.data));
    stream.addEventListener('error', () => {
      if (streamBroken) return;
      streamBroken = true;
      write('console-err', '— log stream lost, reconnecting —');
      api('/api/cluster').catch(() => {});
    });
  };

  const stop = () => {
    if (!stream) return;
    stream.close();
    stream = null;
  };

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const cmd = input.value.trim();
    if (!cmd) return;

    history.push(cmd);
    historyIndex = history.length;
    write('console-echo', '> ' + cmd);
    input.value = '';
    input.disabled = true;
    send.disabled = true;

    try {
      const res = await api(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ command: cmd }),
      });
      const r = await res.json();
      if (r.err) write('console-err', r.err);
      else write(null, r.output && r.output.trim() ? r.output : '(no output)');
    } catch (e) {
      write('console-err', 'Request failed.');
    } finally {
      input.disabled = false;
      send.disabled = false;
      input.focus();
      after();
    }
  });

  input.addEventListener('keydown', (e) => {
    if (e.key !== 'ArrowUp' && e.key !== 'ArrowDown') return;
    if (!history.length) return;
    e.preventDefault();
    historyIndex += e.key === 'ArrowUp' ? -1 : 1;
    historyIndex = Math.max(0, Math.min(historyIndex, history.length));
    input.value = history[historyIndex] || '';
  });

  return { start, stop };
}

const consoles = {
  'gameservers/minecraft': wireConsole('mc', '/api/gameservers/minecraft/command', '/api/gameservers/minecraft/logs/stream?lines=200', loadMinecraftStatus),
  'gameservers/satisfactory': wireConsole('sat', '/api/gameservers/satisfactory/command', '/api/gameservers/satisfactory/logs/stream?lines=200', loadSatisfactoryStatus),
};

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

function refresh() {
  if (document.hidden) return;
  if (!home.hidden) loadCluster();
  if (!satisfactoryPage.hidden) loadSatisfactoryStatus();
  if (!minecraftPage.hidden) loadMinecraftStatus();
}

setInterval(refresh, 30000);
document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });

const blogList = document.getElementById('blog-list');
const blogEditor = document.getElementById('blog-editor');
const blogError = document.getElementById('blog-error');
const blogStatus = document.getElementById('blog-status');
const blogTitle = document.getElementById('blog-title');
const blogDate = document.getElementById('blog-date');
const blogSlug = document.getElementById('blog-slug');
const blogBody = window.markdownEditor.create(document.getElementById('blog-body'), {
  nonce: document.querySelector('meta[name="csp-nonce"]').content,
  mediaOrigin: document.querySelector('meta[name="media-origin"]').content,
  onFiles: (files) => blogUpload(files),
  onCommand: (name) => mdApply(name),
});
const blogPublish = document.getElementById('blog-publish');
const blogUnpublish = document.getElementById('blog-unpublish');
const blogDelete = document.getElementById('blog-delete');
const blogPublishingOff = document.getElementById('blog-publishing-off');
const blogToolbar = document.getElementById('blog-toolbar');
const blogPreviewToggle = document.getElementById('blog-preview-toggle');
const blogImageInput = document.getElementById('blog-image-input');
const blogFileInput = document.getElementById('blog-file-input');
const blogFilesOrigin = document.querySelector('meta[name="files-origin"]').content;

blogBody.view.contentDOM.setAttribute('aria-labelledby', 'blog-body-label');

let blogCurrent = null;
let blogDraft = true;
let blogPublishing = false;
const BLOG_DRAFT_KEY = 'vinnel:blog-draft';

function blogSnapshot() {
  if (blogEditor.hidden) return null;
  return {
    current: blogCurrent,
    post: {
      slug: blogSlug.value,
      draft: blogDraft,
      title: blogTitle.value,
      date: blogDate.value,
      body: blogBody.value,
    },
  };
}

function blogRestore() {
  let saved = null;
  try {
    saved = JSON.parse(sessionStorage.getItem(BLOG_DRAFT_KEY) || 'null');
    sessionStorage.removeItem(BLOG_DRAFT_KEY);
  } catch {}
  if (!saved || !saved.post) return;
  blogOpen(saved.post);
  blogCurrent = saved.current;
  blogHighlight();
  blogSyncActions();
  blogSay('Restored unsaved changes');
}

function blogSay(message, bad) {
  blogStatus.textContent = message;
  blogStatus.classList.toggle('blog-status--bad', Boolean(bad));
}

function blogFail(err) {
  blogError.textContent = String(err && err.message ? err.message : err);
  blogError.hidden = false;
}

async function blogFetch(path, options) {
  const res = await api(path, options);
  const text = await res.text();
  let data = {};
  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    throw new Error(text.slice(0, 200) || res.statusText);
  }
  if (!res.ok) {
    const err = new Error(data.err || res.statusText);
    err.status = res.status;
    throw err;
  }
  return data;
}

function blogUploadRequest(method, path, body, onProgress) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.withCredentials = true;
    xhr.upload.addEventListener('progress', (event) => {
      if (event.lengthComputable && onProgress) onProgress(event.loaded, event.total);
    });
    xhr.addEventListener('load', () => {
      const text = xhr.responseText;
      let data = {};
      try {
        data = text ? JSON.parse(text) : {};
      } catch {
        reject(new Error(text.slice(0, 200) || xhr.statusText || 'Upload failed'));
        return;
      }
      if (xhr.status < 200 || xhr.status >= 300) {
        reject(new Error(data.err || xhr.statusText || 'Upload failed'));
        return;
      }
      resolve(data);
    });
    xhr.addEventListener('error', () => reject(new Error('Network request failed.')));
    xhr.addEventListener('abort', () => reject(new Error('Upload canceled.')));
    xhr.addEventListener('timeout', () => reject(new Error('Upload timed out.')));
    xhr.open(method, path);
    xhr.send(body);
  });
}

function blogRender(posts) {
  blogList.replaceChildren();
  if (!posts.length) {
    const empty = document.createElement('li');
    empty.className = 'blog-list-empty';
    empty.textContent = 'No posts yet.';
    blogList.append(empty);
    return;
  }
  for (const post of posts) {
    const item = document.createElement('li');
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'blog-list-item';
    button.dataset.slug = post.slug;
    button.classList.toggle('active', blogCurrent === post.slug);

    const title = document.createElement('span');
    title.className = 'blog-list-title';
    title.textContent = post.title;

    const meta = document.createElement('span');
    meta.className = 'blog-list-meta';
    meta.textContent = post.date;

    const badge = document.createElement('span');
    badge.className = post.draft ? 'blog-badge blog-badge--draft' : 'blog-badge';
    badge.textContent = post.draft ? 'draft' : 'live';

    meta.append(' ', badge);
    button.append(title, meta);
    item.append(button);
    blogList.append(item);
  }
}

async function loadBlogPosts() {
  blogError.hidden = true;
  try {
    const data = await blogFetch('/api/blog/posts');
    blogPublishing = Boolean(data.publishing);
    blogPublishingOff.hidden = blogPublishing;
    blogSyncActions();
    blogRender(data.posts || []);
    blogRestore();
  } catch (err) {
    blogFail(err);
  }
}

function blogSyncActions() {
  blogPublish.textContent = blogDraft ? 'Publish' : 'Update';
  blogPublish.disabled = !blogPublishing;
  blogUnpublish.hidden = blogDraft;
  blogDelete.hidden = !blogCurrent;
}

function blogOpen(post) {
  blogCurrent = post.slug || null;
  blogDraft = post.draft !== false;
  blogTitle.value = post.title || '';
  blogDate.value = post.date || new Date().toISOString().slice(0, 10);
  blogSlug.value = post.slug || '';
  blogBody.value = post.body || '';
  blogSyncActions();
  blogEditor.hidden = false;
  blogSay(post.slug ? '' : 'New post');
  blogHighlight();
}

function blogHighlight() {
  for (const el of blogList.querySelectorAll('.blog-list-item')) {
    el.classList.toggle('active', el.dataset.slug === blogCurrent);
  }
}

async function blogSelect(button) {
  blogError.hidden = true;
  try {
    blogOpen(await blogFetch('/api/blog/posts/' + encodeURIComponent(button.dataset.slug)));
  } catch (err) {
    blogFail(err);
  }
}

const MD_WRAPS = {
  bold: ['**', '**'],
  italic: ['*', '*'],
  underline: ['<u>', '</u>'],
  strike: ['~~', '~~'],
  code: ['`', '`'],
};

const MD_PREFIXES = {
  h1: '# ',
  h2: '## ',
  h3: '### ',
  quote: '> ',
  list: '- ',
  numbers: '1. ',
};

function mdReplace(start, end, text, selStart, selEnd) {
  blogBody.focus();
  blogBody.setRangeText(text, start, end);
  blogBody.setSelectionRange(selStart, selEnd);
}

function mdWrap(name) {
  const [open, close] = MD_WRAPS[name];
  const text = blogBody.value;
  const start = blogBody.selectionStart;
  const end = blogBody.selectionEnd;
  if (text.slice(start - open.length, start) === open && text.slice(end, end + close.length) === close) {
    mdReplace(start - open.length, end + close.length, text.slice(start, end), start - open.length, end - open.length);
    return;
  }
  const selected = text.slice(start, end);
  mdReplace(start, end, open + selected + close, start + open.length, start + open.length + selected.length);
}

function mdPrefix(prefix) {
  const text = blogBody.value;
  const start = text.lastIndexOf('\n', blogBody.selectionStart - 1) + 1;
  let end = text.indexOf('\n', blogBody.selectionEnd);
  if (end < 0) end = text.length;
  const lines = text.slice(start, end).split('\n');
  const bare = (line) => line.replace(/^(#{1,6} |> |- |\d+\. )/, '');
  const drop = lines.every((line) => line.startsWith(prefix));
  const out = lines.map((line) => (drop ? bare(line) : prefix + bare(line))).join('\n');
  mdReplace(start, end, out, start, start + out.length);
}

function mdLink() {
  const text = blogBody.value;
  const start = blogBody.selectionStart;
  const selected = text.slice(start, blogBody.selectionEnd);
  if (/^(https?:\/\/|\/)\S+$/.test(selected)) {
    mdReplace(start, blogBody.selectionEnd, '[](' + selected + ')', start + 1, start + 1);
    return;
  }
  const out = '[' + selected + '](url)';
  mdReplace(start, blogBody.selectionEnd, out, start + out.length - 4, start + out.length - 1);
}

function mdInsert(text) {
  const start = blogBody.selectionStart;
  mdReplace(start, blogBody.selectionEnd, text, start + text.length, start + text.length);
}

function mdApply(name) {
  if (MD_WRAPS[name]) mdWrap(name);
  else if (MD_PREFIXES[name]) mdPrefix(MD_PREFIXES[name]);
  else if (name === 'link') mdLink();
}

blogPreviewToggle.addEventListener('click', () => {
  const on = blogPreviewToggle.getAttribute('aria-pressed') !== 'true';
  blogPreviewToggle.setAttribute('aria-pressed', String(on));
  blogBody.setRendered(on);
  blogBody.focus();
});

blogToolbar.addEventListener('click', (e) => {
  const button = e.target.closest('[data-md]');
  if (button) mdApply(button.dataset.md);
});

const BLOG_UPLOAD_CHUNK_SIZE = 16 * 1024 * 1024;
const BLOG_UPLOAD_PARALLEL = 4;
const BLOG_UPLOAD_RETRIES = 3;
const BLOG_UPLOAD_KEY = 'vinnel:blog-upload:';

function blogFilesFetch(path, options) {
  return blogFetch((blogFilesOrigin || '') + path, { credentials: 'include', ...options });
}

function blogUploadKey(file) {
  return BLOG_UPLOAD_KEY + encodeURIComponent(file.name) + ':' + file.size + ':' + file.lastModified;
}

function blogUploadSaved(file) {
  try {
    const saved = JSON.parse(localStorage.getItem(blogUploadKey(file)) || 'null');
    if (saved && saved.id && saved.size === file.size && saved.name === file.name && saved.lastModified === file.lastModified) {
      return saved;
    }
  } catch {}
  return null;
}

function blogUploadRemember(file, session) {
  try {
    localStorage.setItem(blogUploadKey(file), JSON.stringify({
      id: session.id,
      name: file.name,
      size: file.size,
      lastModified: file.lastModified,
      chunkSize: session.chunkSize,
    }));
  } catch {}
}

function blogUploadForget(file) {
  try {
    localStorage.removeItem(blogUploadKey(file));
  } catch {}
}

async function blogUploadSession(file) {
  const saved = blogUploadSaved(file);
  if (saved) {
    try {
      const status = await blogFilesFetch('/api/blog/media/uploads/' + encodeURIComponent(saved.id));
      if (status.size === file.size && status.chunkSize === saved.chunkSize) return status;
    } catch (err) {
      if (err.status !== 404) throw err;
    }
    blogUploadForget(file);
  }

  const session = await blogFilesFetch('/api/blog/media/uploads', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ filename: file.name, size: file.size, chunkSize: BLOG_UPLOAD_CHUNK_SIZE }),
  });
  blogUploadRemember(file, session);
  return session;
}

function blogUploadProgress(file, loaded, initial, started) {
  const elapsed = Math.max((performance.now() - started) / 1000, 0.001);
  const percent = file.size ? Math.min(100, (loaded / file.size) * 100) : 0;
  const speed = Math.max(0, loaded - initial) / elapsed;
  blogSay('Uploading ' + file.name + ' ' + percent.toFixed(0) + '% (' + fmtBytes(speed) + '/s)');
}

async function blogUploadChunk(file, session, index, loaded, initial, started) {
  const offset = index * session.chunkSize;
  const length = Math.min(session.chunkSize, file.size - offset);
  const body = file.slice(offset, offset + length, 'application/octet-stream');
  const path = (blogFilesOrigin || '') + '/api/blog/media/uploads/' + encodeURIComponent(session.id) + '/chunks/' + index;
  for (let attempt = 1; attempt <= BLOG_UPLOAD_RETRIES; attempt++) {
    loaded[index] = 0;
    blogUploadProgress(file, loaded.reduce((sum, value) => sum + value, 0), initial, started);
    try {
      await blogUploadRequest('PUT', path, body, (sent) => {
        loaded[index] = Math.min(sent, length);
        blogUploadProgress(file, loaded.reduce((sum, value) => sum + value, 0), initial, started);
      });
      loaded[index] = length;
      blogUploadProgress(file, loaded.reduce((sum, value) => sum + value, 0), initial, started);
      return;
    } catch (err) {
      if (attempt === BLOG_UPLOAD_RETRIES) throw err;
      blogSay('Retrying ' + file.name + ' chunk ' + (index + 1) + ' (' + attempt + '/' + BLOG_UPLOAD_RETRIES + ')');
    }
  }
}

async function blogUploadFile(file) {
  const session = await blogUploadSession(file);
  const completePath = '/api/blog/media/uploads/' + encodeURIComponent(session.id) + '/complete';
  if (session.complete) {
    const result = await blogFilesFetch(completePath, { method: 'POST' });
    blogUploadForget(file);
    return result;
  }

  const total = session.totalChunks || Math.ceil(file.size / session.chunkSize);
  const loaded = Array(total).fill(0);
  for (const index of session.received || []) {
    if (index >= 0 && index < total) loaded[index] = Math.min(session.chunkSize, file.size - index * session.chunkSize);
  }
  const initial = loaded.reduce((sum, value) => sum + value, 0);
  const started = performance.now();
  blogUploadProgress(file, initial, initial, started);

  const pending = [];
  for (let index = 0; index < total; index++) {
    if (loaded[index] === 0) pending.push(index);
  }
  let cursor = 0;
  let failure = null;
  async function worker() {
    while (!failure) {
      const index = cursor++;
      if (index >= pending.length) return;
      try {
        await blogUploadChunk(file, session, pending[index], loaded, initial, started);
      } catch (err) {
        failure = err;
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(BLOG_UPLOAD_PARALLEL, pending.length) }, worker));
  if (failure) throw failure;

  blogSay('Finalizing ' + file.name + ' 100%');
  const result = await blogFilesFetch(completePath, { method: 'POST' });
  blogUploadForget(file);
  return result;
}

async function blogUpload(files, asImage) {
  blogError.hidden = true;
  for (const file of files) {
    blogSay('Preparing ' + file.name);
    try {
      const data = await blogUploadFile(file);
      const image = asImage === undefined ? file.type.startsWith('image/') : asImage;
      const label = image ? file.name.replace(/\.[^.]+$/, '') : file.name;
      mdInsert((image ? '!' : '') + '[' + label + '](' + data.url + ')');
      blogSay('Attached ' + data.name);
    } catch (err) {
      blogSay('Upload failed; select the file again to resume', true);
      blogFail(err);
      return;
    }
  }
}

async function blogUploadFromURL(url, filename) {
  blogError.hidden = true;
  blogSay('Downloading from URL…');
  try {
    const data = await blogFilesFetch('/api/blog/media/url', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url, filename }),
    });
    const label = filename || data.name.replace(/-[a-f0-9]{8}\.[^.]+$/, '');
    mdInsert('[' + label + '](' + data.url + ')');
    blogSay('Attached ' + data.name);
  } catch (err) {
    blogSay('Download failed', true);
    blogFail(err);
  }
}

const blogAttachFileBtn = document.getElementById('blog-attach-file');
const blogAttachFileDropdown = document.getElementById('blog-attach-file-dropdown');
const blogAttachFileMenu = blogAttachFileDropdown.querySelector('.blog-tool-dropdown-menu');
const blogUrlModal = document.getElementById('blog-url-modal');
const blogUrlInput = document.getElementById('blog-url-input');
const blogUrlFilename = document.getElementById('blog-url-filename');
const blogUrlCancel = document.getElementById('blog-url-cancel');
const blogUrlSubmit = document.getElementById('blog-url-submit');

blogAttachFileBtn.addEventListener('click', (e) => {
  e.stopPropagation();
  const expanded = blogAttachFileBtn.getAttribute('aria-expanded') === 'true';
  blogAttachFileBtn.setAttribute('aria-expanded', String(!expanded));
  blogAttachFileMenu.hidden = expanded;
});

document.addEventListener('click', (e) => {
  if (!blogAttachFileDropdown.contains(e.target)) {
    blogAttachFileBtn.setAttribute('aria-expanded', 'false');
    blogAttachFileMenu.hidden = true;
  }
});

blogAttachFileMenu.addEventListener('click', (e) => {
  const button = e.target.closest('[data-action]');
  if (!button) return;
  blogAttachFileBtn.setAttribute('aria-expanded', 'false');
  blogAttachFileMenu.hidden = true;
  const action = button.dataset.action;
  if (action === 'upload') {
    blogFileInput.click();
  } else if (action === 'download') {
    blogUrlInput.value = '';
    blogUrlFilename.value = '';
    blogUrlModal.hidden = false;
    blogUrlInput.focus();
  }
});

blogUrlCancel.addEventListener('click', () => {
  blogUrlModal.hidden = true;
});

blogUrlModal.querySelector('.modal-backdrop').addEventListener('click', () => {
  blogUrlModal.hidden = true;
});

blogUrlSubmit.addEventListener('click', async () => {
  const url = blogUrlInput.value.trim();
  if (!url) return;
  const filename = blogUrlFilename.value.trim() || undefined;
  blogUrlModal.hidden = true;
  await blogUploadFromURL(url, filename);
});

blogUrlInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') {
    e.preventDefault();
    blogUrlSubmit.click();
  } else if (e.key === 'Escape') {
    blogUrlModal.hidden = true;
  }
});

document.getElementById('blog-attach-image').addEventListener('click', () => blogImageInput.click());
document.getElementById('blog-attach-file').addEventListener('click', () => blogFileInput.click());

for (const input of [blogImageInput, blogFileInput]) {
  input.addEventListener('change', () => {
    const files = Array.from(input.files);
    input.value = '';
    blogUpload(files, input === blogImageInput);
  });
}

let blogTapStart = null;
let blogTapPicked = false;

blogList.addEventListener('pointerdown', (e) => {
  blogTapStart = e.pointerType === 'mouse' ? null : { x: e.clientX, y: e.clientY };
});

blogList.addEventListener('pointerup', (e) => {
  const start = blogTapStart;
  blogTapStart = null;
  const button = e.target.closest('.blog-list-item');
  if (!start || !button) return;
  if (Math.hypot(e.clientX - start.x, e.clientY - start.y) > 10) return;
  blogTapPicked = true;
  blogSelect(button);
});

blogList.addEventListener('click', (e) => {
  if (blogTapPicked) {
    blogTapPicked = false;
    return;
  }
  const button = e.target.closest('.blog-list-item');
  if (button) blogSelect(button);
});

document.getElementById('blog-new').addEventListener('click', () => {
  blogOpen({ draft: true });
  blogTitle.focus();
});

async function blogEnsureSlug() {
  const current = blogSlug.value.trim();
  if (current) return current;
  if (!blogTitle.value.trim()) return '';
  const data = await blogFetch('/api/blog/slug?title=' + encodeURIComponent(blogTitle.value));
  blogSlug.value = data.slug;
  return data.slug;
}

async function blogSavePost() {
  const slug = await blogEnsureSlug();
  if (!slug || !blogEditor.reportValidity()) return '';
  await blogFetch('/api/blog/posts/' + encodeURIComponent(slug), {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      title: blogTitle.value,
      date: blogDate.value,
      body: blogBody.value,
      draft: blogDraft,
    }),
  });
  blogCurrent = slug;
  return slug;
}

async function blogReopen(slug) {
  await loadBlogPosts();
  blogOpen(await blogFetch('/api/blog/posts/' + encodeURIComponent(slug)));
}

blogTitle.addEventListener('blur', async () => {
  if (blogCurrent) return;
  try {
    await blogEnsureSlug();
  } catch (err) {
    blogFail(err);
  }
});

blogEditor.addEventListener('submit', async (e) => {
  e.preventDefault();
  blogError.hidden = true;
  try {
    const slug = await blogSavePost();
    if (!slug) return;
    await blogReopen(slug);
    blogSay('Saved');
  } catch (err) {
    blogSay('Not saved', true);
    blogFail(err);
  }
});

blogPublish.addEventListener('click', async () => {
  blogError.hidden = true;
  const verb = blogDraft ? 'Publishing' : 'Updating';
  blogSay(verb + '…');
  try {
    const slug = await blogSavePost();
    if (!slug) {
      blogSay('');
      return;
    }
    await blogFetch('/api/blog/posts/' + encodeURIComponent(slug) + '/publish', { method: 'POST' });
    await blogReopen(slug);
    blogSay('Published');
  } catch (err) {
    blogSay(verb + ' failed', true);
    blogFail(err);
  }
});

blogUnpublish.addEventListener('click', async () => {
  if (!blogCurrent) return;
  blogError.hidden = true;
  blogSay('Unpublishing…');
  try {
    await blogFetch('/api/blog/posts/' + encodeURIComponent(blogCurrent) + '/unpublish', { method: 'POST' });
    await blogReopen(blogCurrent);
    blogSay('Unpublished');
  } catch (err) {
    blogSay('Unpublish failed', true);
    blogFail(err);
  }
});

blogDelete.addEventListener('click', async () => {
  if (!blogCurrent) return;
  if (!confirm('Delete "' + blogTitle.value + '"? It will be removed from the repository during the nightly sync.')) return;
  blogError.hidden = true;
  try {
    await blogFetch('/api/blog/posts/' + encodeURIComponent(blogCurrent), { method: 'DELETE' });
    blogCurrent = null;
    blogEditor.hidden = true;
    await loadBlogPosts();
  } catch (err) {
    blogFail(err);
  }
});

show(location.hash.slice(1));
