// Loaded without defer so the theme lands before first paint. One identical
// copy per site (vinnel.cloud, auth.vinnel.cloud, admin.vinnel.cloud): the
// choice is shared through a Domain=.vinnel.cloud cookie, read here in
// preference to localStorage, which is per-origin and only a legacy fallback.
// Unset means "follow the OS", which the CSS light-dark() palette already does,
// so nothing is written to the root element in that case.
(function () {
  var root = document.documentElement;
  try {
    var m = document.cookie.match(/(?:^|; )theme=(dark|light)/);
    var t = (m && m[1]) || localStorage.theme;
    if (t) root.dataset.theme = t;
  } catch (e) {}

  addEventListener('DOMContentLoaded', function () {
    var opts = Array.prototype.slice.call(document.querySelectorAll('.theme-opt'));
    var mq = matchMedia('(prefers-color-scheme: dark)');
    function sync() {
      var active = root.dataset.theme || (mq.matches ? 'dark' : 'light');
      opts.forEach(function (b) { b.setAttribute('aria-pressed', b.dataset.themeChoice === active); });
    }
    opts.forEach(function (b) {
      b.addEventListener('click', function () {
        root.dataset.theme = b.dataset.themeChoice;
        try { localStorage.theme = b.dataset.themeChoice; } catch (e) {}
        document.cookie = 'theme=' + b.dataset.themeChoice + '; domain=.vinnel.cloud; path=/; max-age=31536000; secure; samesite=lax';
        sync();
      });
    });
    sync();
    mq.addEventListener('change', sync);
  });
})();
