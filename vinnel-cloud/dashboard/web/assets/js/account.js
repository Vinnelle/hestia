fetch('/api/me').then(r => r.ok ? r.json() : Promise.reject()).then(me => {
  document.getElementById('profile-name').textContent = me.name || me.email;
  document.getElementById('profile-email-display').textContent = me.email;
  if (me.picture) document.getElementById('profile-avatar').src = me.picture;
}).catch(() => { window.location.href = '/login.html'; });
