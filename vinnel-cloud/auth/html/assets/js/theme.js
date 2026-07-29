// Loaded without defer so the theme lands before first paint — an inline
// script would need a CSP hash, and script-src is 'self' only. Reads the
// Domain=.vinnel.cloud cookie shared with vinnel.cloud/admin.vinnel.cloud
// first, localStorage as the per-origin legacy fallback.
(function () {
  var root = document.documentElement;
  try {
    var m = document.cookie.match(/(?:^|; )theme=(dark|light)/);
    var t = (m && m[1]) || localStorage.theme;
    if (t) root.dataset.theme = t;
  } catch (e) {}

  addEventListener('DOMContentLoaded', function () {
    var opts = Array.prototype.slice.call(document.querySelectorAll('.theme-opt'));
    function sync() {
      var active = root.dataset.theme || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
      opts.forEach(function (b) { b.setAttribute('aria-pressed', b.dataset.themeChoice === active); });
    }
    sync();
    matchMedia('(prefers-color-scheme: dark)').addEventListener('change', sync);
    opts.forEach(function (b) {
      b.addEventListener('click', function () {
        root.dataset.theme = b.dataset.themeChoice;
        try { localStorage.theme = b.dataset.themeChoice; } catch (e) {}
        document.cookie = 'theme=' + b.dataset.themeChoice + '; domain=.vinnel.cloud; path=/; max-age=31536000; secure; samesite=lax';
        sync();
      });
    });
  });
})();
