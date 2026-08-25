(function () {
  var root = document.documentElement;

  function persist(t) {
    try { localStorage.theme = t; } catch (e) {}
    document.cookie = 'vinnel_theme=' + t + '; domain=.vinnel.cloud; path=/; max-age=31536000; secure; samesite=lax';
  }

  try {
    document.cookie = 'theme=; domain=.vinnel.cloud; path=/; max-age=0';
    var m = document.cookie.match(/(?:^|; )vinnel_theme=(dark|light)/);
    var t = (m && m[1]) || localStorage.theme;
    if (t) {
      root.dataset.theme = t;
      if (!m) persist(t);
    }
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
        persist(b.dataset.themeChoice);
        sync();
      });
    });
    sync();
    mq.addEventListener('change', sync);
  });
})();
