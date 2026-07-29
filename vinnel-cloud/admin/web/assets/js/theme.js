// Loaded without defer so the theme is set before first paint — an inline script
// would need a CSP hash, and script-src is 'self' only.
(function () {
  var d = document.documentElement, s = localStorage;
  // Cookie first: vinnel.cloud shares the choice via a Domain=.vinnel.cloud cookie
  // (localStorage is per-origin). localStorage is the pre-cookie legacy fallback.
  var m = document.cookie.match(/(?:^|; )theme=(dark|light)/);
  d.dataset.theme = (m && m[1]) || s.theme || (matchMedia('(prefers-color-scheme:light)').matches ? 'light' : 'dark');
  d.addEventListener('click', function (e) {
    if (!e.target.closest('.toggle')) return;
    d.dataset.themeTransitioning = '';
    d.dataset.theme = d.dataset.theme === 'dark' ? 'light' : 'dark';
    s.theme = d.dataset.theme;
    document.cookie = 'theme=' + d.dataset.theme + '; domain=.vinnel.cloud; path=/; max-age=31536000; secure; samesite=lax';
    setTimeout(function () { delete d.dataset.themeTransitioning; }, 500);
  });
})();
