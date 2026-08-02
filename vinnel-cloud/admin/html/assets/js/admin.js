const frame = document.getElementById('service-frame');
const home = document.getElementById('frame-empty');
const satisfactoryPage = document.getElementById('page-satisfactory');
const back = document.getElementById('frame-back');
const frameTitle = document.getElementById('frame-title');
const routed = document.querySelectorAll('.service-link[data-url]');
const allNavLinks = document.querySelectorAll('.sidebar-link');

const internalPages = {
  'gameservers/satisfactory': { el: satisfactoryPage, title: 'Satisfactory', onShow: refreshSatisfactory },
};

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

  const page = internalPages[slug];

  home.hidden = true;
  satisfactoryPage.hidden = true;
  frame.hidden = true;
  back.hidden = true;

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
  frameTitle.textContent = active.dataset.label;
  document.title = active.dataset.label + ' — vinnel.cloud';

  if (frame.getAttribute('src') !== active.dataset.url) {
    frame.setAttribute('src', active.dataset.url);
  }
}

addEventListener('hashchange', () => show(location.hash.slice(1)));

document.getElementById('sidebar-toggle').addEventListener('click', () => {
  document.getElementById('sidebar').classList.toggle('sidebar--collapsed');
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

  const problems = [s.podErr, s.apiErr, s.saveErr].filter(Boolean);
  err.hidden = problems.length === 0;
  err.textContent = problems.join(' · ');

  const dot = document.getElementById('sat-status-dot');
  const up = !!(s.api && s.api.healthy);
  dot.className = 'dot' + (up ? ' dot--ok' : ' dot--bad');
  text('sat-status-text', up ? 'Online' : 'Offline');
  text('sat-status-sub', s.pod ? s.pod.phase + (s.pod.ready ? ', ready' : '') : (s.podErr || ''));

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

async function loadSatisfactoryLogs() {
  const pre = document.getElementById('sat-logs');
  pre.textContent = 'Loading…';
  try {
    const r = await (await fetch('/api/gameservers/satisfactory/logs?lines=300')).json();
    pre.textContent = r.logs || r.err || '(no logs)';
  } catch (e) {
    pre.textContent = 'Could not load logs.';
  }
}

function refreshSatisfactory() {
  loadSatisfactoryStatus();
  loadSatisfactoryLogs();
}

document.getElementById('sat-logs-refresh').addEventListener('click', loadSatisfactoryLogs);

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

function refresh() {
  if (!home.hidden) loadCluster();
  if (!satisfactoryPage.hidden) loadSatisfactoryStatus();
}

setInterval(refresh, 30000);

show(location.hash.slice(1));
