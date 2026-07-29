// Custom front-end for Authelia's first-party API. The stock React portal is
// compiled into the Authelia binary and can't be restyled structurally, so this
// page replaces it at the ingress for `/` while /api (and the /consent and
// /settings SPA routes, still served by Authelia) remain untouched.
//
// The API is Authelia's internal portal contract, not a stable public API — all
// of the below was read out of authelia/authelia v4.39.20 (internal/server
// handlers.go, internal/handlers/types.go, web/src/services, web/src/constants)
// and must be re-verified after an Authelia upgrade:
//   GET  /api/state                 -> data.authentication_level (0|1|2), data.username
//   POST /api/firstfactor           {username, password, keepMeLoggedIn, targetURL?, requestMethod?, flow?, flowID?, subflow?}
//   GET  /api/user/info             -> data.method ("totp" | "webauthn" | "mobile_push")
//   POST /api/secondfactor/totp     {token, targetURL?, flow?, flowID?, subflow?}
//   GET  /api/firstfactor/passkey   -> data.publicKey (PublicKeyCredentialRequestOptionsJSON)
//   POST /api/firstfactor/passkey   {response, keepMeLoggedIn, targetURL?, requestMethod?, flow?, flowID?, subflow?}
//   GET  /api/secondfactor/webauthn -> data.publicKey
//   POST /api/secondfactor/webauthn {response, targetURL?, flow?, flowID?, subflow?}
//   POST /api/logout                {}
// Responses are {status: "OK"|"KO", data?, message?}; a redirect target, when
// Authelia knows one, arrives as data.redirect. Second factors implemented here:
// TOTP and WebAuthn — mobile_push still points at /settings (stock UI).
//
// The passkey routes exist only while `webauthn.enable_passkey_login` is true in
// hestia/authelia/configuration.yml.tftpl; with it false they 404, which is what
// hides the button.
(function () {
  'use strict';

  // Query names are Authelia's own (web/src/constants/SearchParams.ts): rd, rm,
  // flow, flow_id, subflow. The POST bodies spell the same things targetURL,
  // requestMethod, flow, flowID, subflow — unknown keys are silently dropped, so
  // a wrong name here costs the OIDC flow context with no error anywhere.
  var qs = new URLSearchParams(location.search);
  var rd = qs.get('rd') || '';
  var rm = qs.get('rm') || '';
  var flow = qs.get('flow') || '';
  var flowID = qs.get('flow_id') || '';
  var subflow = qs.get('subflow') || '';

  // WebAuthn Level 3 JSON serialization does the base64url plumbing natively, so
  // no library and no hand-rolled codec. Where it is missing, the passkey button
  // stays hidden and password login is unaffected.
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

  // Same-site targets only; anything else falls back to the "signed in" stage.
  function finish(redirect) {
    var target = redirect || rd;
    if (sameSite(target)) {
      location.replace(target);
      return;
    }
    state();
  }

  // Only one WebAuthn ceremony may be outstanding: a second GET rotates the
  // challenge Authelia stored in the session and invalidates the first one.
  var busy = false;
  // The second factor is auto-started at most once. Everything after that is a
  // button press, so nothing can prompt in a loop.
  var autoAsserted = false;
  var autofill = null;

  function stopAutofill() {
    if (autofill) { autofill.abort(); autofill = null; }
  }

  // One assertion ceremony for both routes: the passkey (first factor) and
  // WebAuthn (second factor) endpoints take the same shape, differing only in the
  // extra fields withFlow/keepMeLoggedIn add to the POST. `mediation` is
  // 'conditional' for the silent autofill attempt and unset for a modal prompt.
  function assert(path, body, levelBefore, mediation) {
    // `busy` only guards modal ceremonies. The conditional one is long-lived by
    // design — it sits waiting on the autofill dropdown — so letting it hold the
    // lock would leave the passkey button dead until its abort landed.
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
      return api('POST', path, withFlow(body));
    }).then(function (res) {
      if (modal) busy = false;
      autofill = null;
      settle(res, levelBefore);
    }).catch(function (err) {
      if (modal) busy = false;
      autofill = null;
      // A dismissed OS prompt (NotAllowedError) and an aborted conditional
      // request (AbortError) are both ordinary, not failures to report.
      if (err && (err.name === 'NotAllowedError' || err.name === 'AbortError')) return;
      msg('passkey sign-in failed — use your password, or check /settings.');
    });
  }

  function settle(res, levelBefore) {
    if (!res.ok) { msg('that key was not accepted.'); return; }
    if (res.data.redirect) { location.replace(res.data.redirect); return; }
    api('GET', '/api/state').then(function (s) {
      // Accepted but no elevation — Authelia counts a passkey as one factor
      // unless it verified the user (see experimental_enable_passkey_uv_two_factors
      // in authelia/configuration.yml.tftpl). Without this guard the router would
      // walk straight back into the same ceremony and prompt forever.
      if ((s.data.authentication_level || 0) <= levelBefore) {
        secondFactor('that key only counts as one factor — finish with a code, or check /settings.');
        return;
      }
      route(s);
    });
  }

  // `note` is applied after show(), which clears whatever msg() held.
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

  // Non-modal: the browser offers any discoverable vinnel.cloud passkey straight
  // from the username field (which is why that input is autocomplete="username
  // webauthn"). A platform with no passkey shows nothing, so this can never get in
  // the way of password login.
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
    // The pending conditional request has to go before a password login: the two
    // ceremonies share one session-side challenge.
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

  // Revealed only where the browser can do the ceremony. Enrolment stays on
  // Authelia's own /settings — registration is a different set of endpoints and
  // the stock UI already covers it.
  if (canPasskey) {
    $('passkey').hidden = false;
    $('passkey-sep').hidden = false;
    $('passkey').addEventListener('click', function () {
      msg('');
      // Cancels the conditional attempt so the modal one can take the challenge.
      stopAutofill();
      assert('/api/firstfactor/passkey', { keepMeLoggedIn: $('login').remember.checked }, 0);
    });
  }

  state();
})();
