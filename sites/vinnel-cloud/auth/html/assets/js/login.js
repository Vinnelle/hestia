(function () {
  'use strict';

  var qs = new URLSearchParams(location.search);
  var rd = qs.get('rd') || '';
  var rm = qs.get('rm') || '';
  var flow = qs.get('flow') || '';
  var flowID = qs.get('flow_id') || '';
  var subflow = qs.get('subflow') || '';

  var canPasskey = !!(window.isSecureContext && window.PublicKeyCredential &&
    PublicKeyCredential.parseRequestOptionsFromJSON);

  function $(id) { return document.getElementById(id); }
  var stages = ['login', 'totp', 'webauthn', 'done'];

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
    if (rm) body.requestMethod = rm;
    if (flow) { body.flow = flow; body.flowID = flowID; }
    if (subflow) body.subflow = subflow;
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

  function sameSite(target) {
    return !!target && /^https:\/\/([a-z0-9-]+\.)*vinnel\.cloud([/?#]|$)/.test(target);
  }

  function finish(redirect) {
    var target = redirect || rd;
    if (sameSite(target)) {
      location.replace(target);
      return;
    }
    state();
  }

  var busy = false;
  var autoAsserted = false;
  var autofill = null;

  function stopAutofill() {
    if (autofill) { autofill.abort(); autofill = null; }
  }

  function assert(path, body, levelBefore, mediation) {
    var modal = !mediation;
    if (modal) {
      if (busy) return;
      busy = true;
    }
    api('GET', path).then(function (res) {
      if (!res.ok || !res.data.publicKey) {
        throw new Error('no challenge');
      }
      var opts = { publicKey: PublicKeyCredential.parseRequestOptionsFromJSON(res.data.publicKey) };
      if (mediation) {
        opts.mediation = mediation;
        autofill = new AbortController();
        opts.signal = autofill.signal;
      }
      return navigator.credentials.get(opts);
    }).then(function (credential) {
      body.response = credential.toJSON();
      if ('keepMeLoggedIn' in body) body.keepMeLoggedIn = $('login').remember.checked;
      return api('POST', path, withFlow(body));
    }).then(function (res) {
      if (modal) busy = false;
      autofill = null;
      settle(res, levelBefore);
    }).catch(function (err) {
      if (modal) busy = false;
      autofill = null;
      if (err && (err.name === 'NotAllowedError' || err.name === 'AbortError')) return;
      msg('passkey sign-in failed — use your password, or check /settings.');
    });
  }

  function settle(res, levelBefore) {
    if (!res.ok) { msg('that key was not accepted.'); return; }
    if (res.data.redirect) { location.replace(res.data.redirect); return; }
    api('GET', '/api/state').then(function (s) {
      if ((s.data.authentication_level || 0) <= levelBefore) {
        secondFactor('that key only counts as one factor — finish with a code, or check /settings.');
        return;
      }
      route(s);
    });
  }

  function secondFactor(note) {
    api('GET', '/api/user/info').then(function (res) {
      if (res.data.method === 'webauthn' && canPasskey) {
        show('webauthn', 'one more step.');
        if (!autoAsserted) {
          autoAsserted = true;
          webauthnAssert();
        }
      } else if (res.data.method === 'totp') {
        show('totp', 'one more step.');
      } else {
        show('totp', 'one more step.');
        note = note || 'that 2FA method is not supported here — manage methods at /settings.';
      }
      if (note) msg(note);
    });
  }

  function webauthnAssert() {
    stopAutofill();
    assert('/api/secondfactor/webauthn', {}, 1);
  }

  function passkeyAutofill() {
    if (!canPasskey || !PublicKeyCredential.isConditionalMediationAvailable) return;
    PublicKeyCredential.isConditionalMediationAvailable().then(function (ok) {
      if (ok) assert('/api/firstfactor/passkey', { keepMeLoggedIn: $('login').remember.checked }, 0, 'conditional');
    });
  }

  function route(res) {
    var lvl = res.data.authentication_level || 0;
    if (lvl >= 2) {
      $('who').textContent = res.data.username || '';
      if (rd) { finish(''); return; }
      show('done', 'welcome back.');
    } else if (lvl === 1) {
      secondFactor();
    } else {
      show('login', 'sign in.');
      passkeyAutofill();
    }
  }

  function state() {
    api('GET', '/api/state').then(function (res) {
      if (location.pathname === '/logout') {
        api('POST', '/api/logout', {}).then(function () {
          if (sameSite(rd)) { location.replace(rd); return; }
          history.replaceState(null, '', '/');
          show('login', 'signed out.');
        });
        return;
      }
      route(res);
    }).catch(function () {
      show('login', 'sign in.');
      msg('authelia is unreachable.');
    });
  }

  $('login').addEventListener('submit', function (e) {
    e.preventDefault();
    var f = e.target;
    stopAutofill();
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

  $('webauthn-go').addEventListener('click', webauthnAssert);

  if (canPasskey) {
    $('passkey').hidden = false;
    $('passkey-sep').hidden = false;
    $('passkey').addEventListener('click', function () {
      msg('');
      stopAutofill();
      assert('/api/firstfactor/passkey', { keepMeLoggedIn: $('login').remember.checked }, 0);
    });
  }

  state();
})();
