const frame = document.getElementById('service-frame');
const home = document.getElementById('frame-empty');
const satisfactoryPage = document.getElementById('page-satisfactory');
const minecraftPage = document.getElementById('page-minecraft');
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

function bar(percent) {
  const cls = percent >= 90 ? ' meter--crit' : percent >= 75 ? ' meter--warn' : '';
  return '<div class="meter"><span class="meter-fill' + cls +
    '" data-pct="' + Math.min(percent, 100).toFixed(1) + '"></span></div>' +
    '<span class="meter-text">' + pct(percent) + '</span>';
}

function applyMeters(root) {
  for (const el of root.querySelectorAll('.meter-fill[data-pct]')) {
    el.style.width = el.dataset.pct + '%';
  }
}

async function loadCluster() {
  const err = document.getElementById('cluster-error');
  try {
    const c = await (await fetch('/api/cluster')).json();
    err.hidden = !c.err;
    if (c.err) err.textContent = c.err;

    text('stat-nodes', c.nodesReady + ' / ' + (c.nodes || []).length);
    text('stat-pods', c.podsRunning + ' / ' + c.podsTotal);
    text('stat-cpu', pct(c.cpuTotal ? (c.cpuUsed / c.cpuTotal) * 100 : 0));
    text('stat-cpu-sub', (c.cpuUsed || 0).toFixed(1) + ' / ' + (c.cpuTotal || 0).toFixed(0) + ' cores');
    text('stat-mem', pct(c.memTotal ? (c.memUsed / c.memTotal) * 100 : 0));
    text('stat-mem-sub', fmtBytes(c.memUsed) + ' / ' + fmtBytes(c.memTotal));

    const tbody = document.getElementById('nodes-tbody');
    tbody.innerHTML = (c.nodes || []).map((n) => {
      const dot = '<span class="dot' + (n.ready ? ' dot--ok' : ' dot--bad') + '"></span>';
      return '<tr><td>' + dot + escapeHtml(n.name) + '</td>' +
        '<td class="meter-cell">' + bar(n.cpuPercent) + '</td>' +
        '<td class="meter-cell">' + bar(n.memPercent) + '</td>' +
        '<td>' + n.podCount + ' / ' + n.podTotal + '</td>' +
        '<td class="dim">' + escapeHtml(n.kubelet || '') + '</td></tr>';
    }).join('');
    applyMeters(tbody);
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
      '<td class="dim">' + escapeHtml(v.class || '—') + '</td>' +
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
    s = await (await fetch('/api/gameservers/satisfactory')).json();
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
    s = await (await fetch('/api/gameservers/minecraft')).json();
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
      const r = await (await fetch(url, { method: 'POST' })).json();
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
      const res = await fetch(endpoint, {
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

show(location.hash.slice(1));
