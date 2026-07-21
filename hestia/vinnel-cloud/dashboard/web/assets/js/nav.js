fetch('/api/me').then(r => r.ok ? r.json() : Promise.reject()).then(me => {
  document.getElementById('user-email').textContent = me.email || '';
  if (me.picture) document.getElementById('user-avatar').src = me.picture;
}).catch(() => { window.location.href = '/login.html'; });

document.getElementById('user-menu-btn').addEventListener('click', () => {
  const dd = document.getElementById('user-dropdown');
  const expanded = document.getElementById('user-menu-btn').getAttribute('aria-expanded') === 'true';
  dd.hidden = expanded;
  document.getElementById('user-menu-btn').setAttribute('aria-expanded', String(!expanded));
});

document.getElementById('sign-out-btn').addEventListener('click', () => {
  fetch('/auth/logout', { method: 'POST' }).then(() => { window.location.href = '/login.html'; });
});

document.getElementById('sidebar-toggle')?.addEventListener('click', () => {
  document.getElementById('sidebar').classList.toggle('sidebar--collapsed');
});
