const root = document.documentElement;
const themeOpts = [...document.querySelectorAll('.theme-opt')];

const syncTheme = () => {
  const active = root.dataset.theme || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
  for (const b of themeOpts) b.setAttribute('aria-pressed', b.dataset.themeChoice === active);
};
syncTheme();
matchMedia('(prefers-color-scheme: dark)').addEventListener('change', syncTheme);

for (const b of themeOpts) {
  b.addEventListener('click', () => {
    root.dataset.theme = b.dataset.themeChoice;
    try { localStorage.theme = b.dataset.themeChoice; } catch {}
    syncTheme();
    b.classList.add('pop');
  });
  b.addEventListener('animationend', () => b.classList.remove('pop'));
}

const syncPicks = () => {
  const os = ['macos', 'windows'].includes(root.dataset.os) ? root.dataset.os : 'linux';
  const channel = root.dataset.channel === 'beta' ? 'beta' : 'stable';
  for (const b of document.querySelectorAll('[data-os-choice]')) b.setAttribute('aria-pressed', b.dataset.osChoice === os);
  for (const b of document.querySelectorAll('[data-channel-choice]')) b.setAttribute('aria-pressed', b.dataset.channelChoice === channel);
};
syncPicks();
new MutationObserver(syncPicks).observe(document.body, { childList: true, subtree: true });

document.addEventListener('click', (e) => {
  const tab = e.target.closest('[data-os-choice], [data-channel-choice]');
  if (!tab) return;
  const [key, value] = tab.dataset.osChoice ? ['os', tab.dataset.osChoice] : ['channel', tab.dataset.channelChoice];
  root.dataset[key] = value;
  try { localStorage[key] = value; } catch {}
  syncPicks();
});

document.addEventListener('click', async (e) => {
  const button = e.target.closest('[data-copy]');
  if (!button) return;
  try {
    await navigator.clipboard.writeText(button.dataset.copy);
    button.dataset.state = 'done';
  } catch {
    button.dataset.state = 'fail';
  }
  clearTimeout(button.copyReset);
  button.copyReset = setTimeout(() => delete button.dataset.state, 1400);
});
