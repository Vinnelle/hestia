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
