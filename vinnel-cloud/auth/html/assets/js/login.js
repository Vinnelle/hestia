// Custom front-end for Authelia's first-party API. The stock React portal is
// compiled into the Authelia binary and can't be restyled structurally, so this
// page replaces it at the ingress for `/` while /api (and the /consent and
// /settings SPA routes, still served by Authelia) remain untouched.
//
// The API is Authelia's internal portal contract, not a stable public API —
// verify against the running version after an Authelia upgrade:
//   GET  /api/state            -> data.authentication_level (0|1|2), data.username
//   POST /api/firstfactor      {username, password, keepMeLoggedIn, targetURL?, requestMethod, workflow?, workflowID?}
//   GET  /api/user/info        -> data.method ("totp" | "webauthn" | "mobile_push")
//   POST /api/secondfactor/totp {token, targetURL?, workflow?, workflowID?}
//   POST /api/logout           {}
// Responses are {status: "OK"|"KO", data?, message?}; a redirect target, when
// Authelia knows one, arrives as data.redirect. Only TOTP is implemented as a
// second factor — for anything else this page points at /settings (stock UI).
(function () {
  'use strict';

  var qs = new URLSearchParams(location.search);
  var rd = qs.get('rd') || '';
  var workflow = qs.get('workflow') || '';
  var workflowID = qs.get('workflow_id') || '';

  function $(id) { return document.getElementById(id); }
  var stages = ['login', 'totp', 'done'];

  function show(stage, subtitle) {
    stages.forEach(function (s) { $(s).hidden = s !== stage; });
    $('subtitle').textContent = subtitle;
    msg('');
    var first = $(stage).querySelector('input');
    if (first) first.focus();
  }

  function msg(text) {
    $('msg').textContent = text;
    $('msg').hidden = !text;
  }

  function withFlow(body) {
    if (rd) body.targetURL = rd;
    if (workflow) { body.workflow = workflow; body.workflowID = workflowID; }
    return body;
  }

  function api(method, path, body) {
    return fetch(path, {
      method: method,
      headers: body ? { 'Content-Type': 'application/json' } : {},
      body: body ? JSON.stringify(body) : undefined
    }).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (j) {
        return { ok: r.ok && j.status !== 'KO', data: j.data || {} };
      });
    });
  }

  // Same-site targets only; anything else falls back to the "signed in" stage.
  function finish(redirect) {
    var target = redirect || rd;
    if (target && /^https:\/\/([a-z0-9-]+\.)*vinnel\.cloud([/?#]|$)/.test(target)) {
      location.replace(target);
      return;
    }
    state();
  }

  function secondFactor() {
    api('GET', '/api/user/info').then(function (res) {
      if (res.data.method === 'totp') {
        show('totp', 'one more step.');
      } else {
        show('totp', 'one more step.');
        msg('non-TOTP 2FA is not supported here — manage methods at /settings.');
      }
    });
  }

  function state() {
    api('GET', '/api/state').then(function (res) {
      var lvl = res.data.authentication_level || 0;
      if (location.pathname === '/logout') {
        api('POST', '/api/logout', {}).then(function () {
          history.replaceState(null, '', '/');
          show('login', 'signed out.');
        });
      } else if (lvl >= 2) {
        $('who').textContent = res.data.username || '';
        if (rd) { finish(''); return; }
        show('done', 'welcome back.');
      } else if (lvl === 1) {
        secondFactor();
      } else {
        show('login', 'sign in.');
      }
    }).catch(function () {
      show('login', 'sign in.');
      msg('authelia is unreachable.');
    });
  }

  $('login').addEventListener('submit', function (e) {
    e.preventDefault();
    var f = e.target;
    api('POST', '/api/firstfactor', withFlow({
      username: f.username.value,
      password: f.password.value,
      keepMeLoggedIn: f.remember.checked,
      requestMethod: 'GET'
    })).then(function (res) {
      if (!res.ok) { msg('invalid credentials.'); f.password.value = ''; return; }
      if (res.data.redirect) { location.replace(res.data.redirect); return; }
      api('GET', '/api/state').then(function (s) {
        if ((s.data.authentication_level || 0) >= 2) finish('');
        else secondFactor();
      });
    });
  });

  $('totp').addEventListener('submit', function (e) {
    e.preventDefault();
    var f = e.target;
    api('POST', '/api/secondfactor/totp', withFlow({
      token: f.token.value
    })).then(function (res) {
      if (!res.ok) { msg('invalid code.'); f.token.value = ''; f.token.focus(); return; }
      if (res.data.redirect) { location.replace(res.data.redirect); return; }
      finish('');
    });
  });

  $('logout').addEventListener('click', function (e) {
    e.preventDefault();
    api('POST', '/api/logout', {}).then(function () {
      show('login', 'signed out.');
    });
  });

  state();
})();
