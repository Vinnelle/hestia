fetch('/api/metrics').then(r => {
  if (!r.ok) throw new Error('request failed');
  return r.json();
}).then(data => {
  document.getElementById('loading').hidden = true;
  document.getElementById('content').hidden = false;

  document.getElementById('stat-pageviews').textContent = data.pageviews;
  document.getElementById('stat-sessions').textContent = data.sessions;
  document.getElementById('stat-users').textContent = data.users;

  const tbody = document.getElementById('pages-tbody');
  data.pages.forEach((p, i) => {
    const tr = document.createElement('tr');
    // textContent, never innerHTML: p.path is attacker-controlled (request paths)
    [i + 1, p.path, p.views].forEach(value => {
      const td = document.createElement('td');
      td.textContent = String(value);
      tr.appendChild(td);
    });
    tbody.appendChild(tr);
  });

  new Chart(document.getElementById('sessions-chart'), {
    type: 'line',
    data: {
      labels: data.daily.map(d => d.day),
      datasets: [{
        label: 'Page views',
        data: data.daily.map(d => d.count),
        borderColor: '#7c5cff',
        backgroundColor: 'rgba(124,92,255,0.15)',
        fill: true,
        tension: 0.3,
      }],
    },
    options: { responsive: true, plugins: { legend: { display: false } } },
  });
}).catch(() => {
  document.getElementById('loading').hidden = true;
  const err = document.getElementById('error');
  err.hidden = false;
  err.textContent = 'Could not load metrics.';
});
