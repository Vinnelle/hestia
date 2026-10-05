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

const syncOs = () => {
  const os = root.dataset.os === 'windows' ? 'windows' : 'linux';
  for (const b of document.querySelectorAll('[data-os-choice]')) b.setAttribute('aria-pressed', b.dataset.osChoice === os);
};
syncOs();
new MutationObserver(syncOs).observe(document.body, { childList: true, subtree: true });

document.addEventListener('click', (e) => {
  const tab = e.target.closest('[data-os-choice]');
  if (!tab) return;
  root.dataset.os = tab.dataset.osChoice;
  try { localStorage.os = tab.dataset.osChoice; } catch {}
  syncOs();
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
