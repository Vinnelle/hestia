// Loaded without defer so the theme is set before first paint — an inline script
// would need a CSP hash, and script-src is 'self' only.
(function () {
  var d = document.documentElement, s = localStorage;
  d.dataset.theme = s.theme || (matchMedia('(prefers-color-scheme:light)').matches ? 'light' : 'dark');
  d.addEventListener('click', function (e) {
    if (!e.target.closest('.toggle')) return;
    d.dataset.themeTransitioning = '';
    d.dataset.theme = d.dataset.theme === 'dark' ? 'light' : 'dark';
    s.theme = d.dataset.theme;
    setTimeout(function () { delete d.dataset.themeTransitioning; }, 500);
  });
})();
