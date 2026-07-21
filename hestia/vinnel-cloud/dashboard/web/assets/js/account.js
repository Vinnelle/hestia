fetch('/api/me').then(r => r.json()).then(me => {
  document.getElementById('profile-name').textContent = me.name || me.email;
  document.getElementById('profile-email-display').textContent = me.email;
  if (me.picture) document.getElementById('profile-avatar').src = me.picture;
});
