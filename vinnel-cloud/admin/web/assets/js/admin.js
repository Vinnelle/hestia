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

// Fire-and-forget so the click is never delayed by the beacon.
function beacon(slug) {
  if (!slug) return;
  navigator.sendBeacon('/api/open?slug=' + encodeURIComponent(slug));
}

for (const el of document.querySelectorAll('.service-link[data-slug]')) {
  el.addEventListener('click', () => beacon(el.dataset.slug));
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
  } catch (e) {
    err.hidden = false;
    err.textContent = 'Could not load cluster stats.';
  }
}

let usageChart = null;

async function loadUsage() {
  try {
    const u = await (await fetch('/api/usage')).json();
    text('stat-opens', u.opens);
    text('stat-sessions', u.sessions);
    text('stat-users', u.users);

    document.getElementById('services-tbody').innerHTML = (u.services || [])
      .map((s, i) => '<tr><td class="dim">' + (i + 1) + '</td><td>' +
        escapeHtml(s.label) + '</td><td>' + s.opens + '</td></tr>').join('');

    const css = getComputedStyle(document.documentElement);
    const accent = css.getPropertyValue('--accent').trim();
    const muted = css.getPropertyValue('--muted').trim();
    const labels = (u.daily || []).map((d) => d.day);
    const data = (u.daily || []).map((d) => d.count);

    if (usageChart) {
      usageChart.data.labels = labels;
      usageChart.data.datasets[0].data = data;
      usageChart.update();
      return;
    }
    usageChart = new Chart(document.getElementById('usage-chart'), {
      type: 'line',
      data: {
        labels,
        datasets: [{
          data,
          borderColor: accent,
          backgroundColor: accent + '33',
          fill: true,
          tension: 0.3,
          pointRadius: 0,
        }],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: { legend: { display: false } },
        scales: {
          x: { ticks: { color: muted }, grid: { display: false } },
          y: { beginAtZero: true, ticks: { color: muted, precision: 0 }, grid: { color: muted + '22' } },
        },
      },
    });
  } catch (e) {
    /* usage is non-critical; the service tiles above still work */
  }
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

function refresh() {
  if (home.hidden) return;
  loadCluster();
  loadUsage();
}

// Only polls while Home is actually visible, so an open frame costs nothing.
setInterval(refresh, 30000);

show(location.hash.slice(1));
