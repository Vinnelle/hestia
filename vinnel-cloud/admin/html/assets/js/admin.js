// The frame is driven off location.hash so a reload, a bookmark or the back
// button all land on the same service. Only frameable services carry data-url;
// the rest are plain target=_blank links and never reach this router.
const frame = document.getElementById('service-frame');
const home = document.getElementById('frame-empty');
const back = document.getElementById('frame-back');
const frameTitle = document.getElementById('frame-title');
const routed = document.querySelectorAll('.service-link[data-url]');

function show(slug) {
  let active = null;
  for (const el of routed) {
    const match = el.dataset.slug === slug;
    if (match) active = el;
    el.classList.toggle('active', match);
  }

  if (!active) {
    // Unknown or empty hash — fall back to Home rather than a blank frame.
    frame.hidden = true;
    frame.removeAttribute('src');
    home.hidden = false;
    back.hidden = true;
    document.title = 'admin — vinnel.cloud';
    refresh();
    return;
  }

  home.hidden = true;
  frame.hidden = false;
  back.hidden = false;
  frameTitle.textContent = active.dataset.label;
  document.title = active.dataset.label + ' — vinnel.cloud';

  // Only reassign src on a real change: rewriting it reloads the app and would
  // throw away whatever the user had open.
  if (frame.getAttribute('src') !== active.dataset.url) {
    frame.setAttribute('src', active.dataset.url);
  }
}

addEventListener('hashchange', () => show(location.hash.slice(1)));

document.getElementById('sidebar-toggle').addEventListener('click', () => {
  document.getElementById('sidebar').classList.toggle('sidebar--collapsed');
});

const menuBtn = document.getElementById('user-menu-btn');
menuBtn.addEventListener('click', () => {
  const expanded = menuBtn.getAttribute('aria-expanded') === 'true';
  document.getElementById('user-dropdown').hidden = expanded;
  menuBtn.setAttribute('aria-expanded', String(!expanded));
});

// ---- Home metrics -------------------------------------------------------

const fmtBytes = (b) => {
  if (!b) return '0 B';
  const u = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  const i = Math.min(Math.floor(Math.log(b) / Math.log(1024)), u.length - 1);
  return (b / Math.pow(1024, i)).toFixed(i ? 1 : 0) + ' ' + u[i];
};
const pct = (n) => (n || 0).toFixed(0) + '%';
const text = (id, v) => { document.getElementById(id).textContent = v; };

// Width is carried as data-pct and applied via CSSOM below: a literal style
// attribute would be blocked by style-src 'self', and widening the CSP for a
// progress bar is not a trade worth making.
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
  const ceph = c.ceph || {};
  if (ceph.present) {
    text('stat-ceph', pct(ceph.total ? (ceph.used / ceph.total) * 100 : 0));
    text('stat-ceph-sub', fmtBytes(ceph.used) + ' / ' + fmtBytes(ceph.total));
    text('stat-ceph-avail', fmtBytes(ceph.available));
    text('ceph-health', ceph.health
      ? 'Ceph ' + ceph.health + ' · every persistent volume'
      : 'Ceph pool and every persistent volume');
  } else {
    text('stat-ceph', 'n/a');
    text('stat-ceph-sub', 'CephCluster status unavailable');
    text('stat-ceph-avail', 'n/a');
  }

  const vols = c.volumes || [];
  text('stat-vols', vols.length);
  text('stat-vol-bytes', fmtBytes(c.volumeBytes));

  // Biggest first: the ones worth noticing are the ones taking the space.
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

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

function refresh() {
  if (home.hidden) return;
  loadCluster();
}

// Only polls while Home is actually visible, so an open frame costs nothing.
setInterval(refresh, 30000);

show(location.hash.slice(1));
