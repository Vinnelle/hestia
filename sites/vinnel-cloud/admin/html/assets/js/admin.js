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
const blogBody = document.getElementById('blog-body');
const blogPublish = document.getElementById('blog-publish');
const blogUnpublish = document.getElementById('blog-unpublish');
const blogDelete = document.getElementById('blog-delete');
const blogPublishingOff = document.getElementById('blog-publishing-off');

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
  if (!res.ok) throw new Error(data.err || res.statusText);
  return data;
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
  for (const el of blogList.querySelectorAll('.blog-list-item')) {
    el.classList.toggle('active', el.dataset.slug === blogCurrent);
  }
}

blogList.addEventListener('click', async (e) => {
  const button = e.target.closest('.blog-list-item');
  if (!button) return;
  blogError.hidden = true;
  try {
    blogOpen(await blogFetch('/api/blog/posts/' + encodeURIComponent(button.dataset.slug)));
  } catch (err) {
    blogFail(err);
  }
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
    blogSay('Removed from the repository');
  } catch (err) {
    blogSay('Unpublish failed', true);
    blogFail(err);
  }
});

blogDelete.addEventListener('click', async () => {
  if (!blogCurrent) return;
  if (!confirm('Delete "' + blogTitle.value + '"? This also removes it from the repository.')) return;
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
