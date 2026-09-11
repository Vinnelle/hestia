(function () {
  'use strict';

  if (!/^\/settings(?:\/|$)/.test(location.pathname)) return;

  const $ = (id) => document.getElementById(id);
  const app = $('settings-app');
  const authShell = $('auth-shell');
  const footer = document.querySelector('.site-footer');
  const alertBox = $('settings-alert');
  const model = { state: null, user: null, config: null, totp: null, keys: [] };
  let elevationAction = null;
  let elevationDeleteID = null;
  let elevationStatus = null;

  authShell.hidden = true;
  footer.hidden = true;
  app.hidden = false;
  document.title = 'Account Settings — vinnel.cloud';

  function text(id, value) {
    const el = $(id);
    if (el) el.textContent = value == null || value === '' ? '—' : String(value);
  }

  function formatDate(value) {
    if (!value) return 'Unknown date';
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? 'Unknown date' : date.toLocaleDateString();
  }

  function methodLabel(method) {
    return ({ totp: 'Authenticator app', webauthn: 'Security key or passkey', mobile_push: 'Mobile push' }[method]) || method || 'Not set';
  }

  function initials(value) {
    const parts = String(value || '?').trim().split(/\s+/).filter(Boolean);
    if (!parts.length) return '?';
    return parts.slice(0, 2).map((part) => part[0]).join('').toUpperCase();
  }

  function showAlert(message, ok) {
    alertBox.replaceChildren();
    alertBox.hidden = !message;
    alertBox.classList.toggle('settings-alert--ok', Boolean(ok));
    if (message) alertBox.append(document.createTextNode(message));
  }

  function errorMessage(error) {
    return error && error.message ? error.message : 'The request could not be completed.';
  }

  async function api(path, options) {
    const request = { credentials: 'same-origin', ...options };
    const headers = new Headers(request.headers || {});
    if (request.body && !headers.has('Content-Type')) headers.set('Content-Type', 'application/json');
    request.headers = headers;
    const response = await fetch(path, request);
    const bodyText = await response.text();
    let body = {};
    try { body = bodyText ? JSON.parse(bodyText) : {}; } catch {}
    if (!response.ok || body.status === 'KO') {
      const details = body.data && body.data.elevation === false
        ? 'Authelia requires identity verification before this action.'
        : body.message || body.data && body.data.message || response.statusText || 'Request failed.';
      const error = new Error(details);
      error.status = response.status;
      error.elevation = Boolean(body.data && body.data.elevation === true);
      error.secondFactor = Boolean(body.data && body.data.second_factor === true);
      throw error;
    }
    return body.data === undefined ? body : body.data;
  }

  async function optional(path) {
    try {
      return await api(path);
    } catch (error) {
      if (error.status === 404) return null;
      throw error;
    }
  }

  function jsonBody(value) {
    return JSON.stringify(value);
  }

  function renderOverview() {
    const name = model.user.display_name || model.state.username || 'Account';
    const email = (model.user.emails || [])[0] || 'No email address';
    text('settings-user-label', email);
    text('settings-display-name', name);
    text('settings-username', model.state.username || name);
    text('settings-email', email);
    text('settings-method', methodLabel(model.user.method));
    text('settings-avatar', initials(name));
    const enrolled = [model.user.has_totp, model.user.has_webauthn, model.user.has_duo].filter(Boolean).length;
    text('settings-mfa-summary', enrolled ? enrolled + ' enrolled second-factor method' + (enrolled === 1 ? '' : 's') : 'No second-factor method enrolled');
    $('settings-mfa-dot').classList.toggle('settings-status-dot--ok', enrolled > 0);
  }

  function renderTOTP() {
    const enabled = Boolean(model.user.has_totp);
    const status = $('totp-status');
    status.textContent = enabled ? 'Enabled' : 'Not enabled';
    status.classList.toggle('settings-badge--ok', enabled);
    $('totp-add').hidden = enabled;
    $('totp-remove').hidden = !enabled;
    if (enabled) $('totp-register').hidden = true;
  }

  function renderKeys() {
    const list = $('key-list');
    list.replaceChildren();
    const keys = model.keys || [];
    const status = $('keys-status');
    status.textContent = keys.length ? keys.length + ' registered' : 'Not enabled';
    status.classList.toggle('settings-badge--ok', keys.length > 0);
    if (!keys.length) {
      const empty = document.createElement('p');
      empty.className = 'settings-note';
      empty.textContent = 'No security keys or passkeys have been registered.';
      list.append(empty);
      return;
    }
    for (const key of keys) {
      const row = document.createElement('div');
      row.className = 'settings-key';
      const body = document.createElement('div');
      body.className = 'settings-key-body';
      const title = document.createElement('div');
      title.className = 'settings-key-title';
      title.textContent = key.description || 'Security key';
      const meta = document.createElement('div');
      meta.className = 'settings-key-meta';
      const kind = key.attachment === 'platform' ? 'Passkey' : 'Security key';
      meta.textContent = kind + ' · added ' + formatDate(key.created_at) + (key.last_used_at ? ' · last used ' + formatDate(key.last_used_at) : '');
      body.append(title, meta);
      const actions = document.createElement('div');
      actions.className = 'settings-key-actions';
      const rename = document.createElement('button');
      rename.className = 'settings-button settings-button--quiet';
      rename.type = 'button';
      rename.textContent = 'Rename';
      rename.addEventListener('click', () => renameKey(key));
      const remove = document.createElement('button');
      remove.className = 'settings-button settings-button--danger';
      remove.type = 'button';
      remove.textContent = 'Remove';
      remove.addEventListener('click', () => removeKey(key));
      actions.append(rename, remove);
      row.append(body, actions);
      list.append(row);
    }
  }

  function renderMethods() {
    const select = $('preferred-method');
    select.replaceChildren();
    const available = model.config && model.config.available_methods || [];
    const options = available.filter((method) => {
      if (method === 'totp') return model.user.has_totp;
      if (method === 'webauthn') return model.user.has_webauthn;
      if (method === 'mobile_push') return model.user.has_duo;
      return false;
    });
    for (const method of options) {
      const option = document.createElement('option');
      option.value = method;
      option.textContent = methodLabel(method);
      option.selected = model.user.method === method;
      select.append(option);
    }
    select.disabled = options.length === 0;
    if (!options.length) {
      const option = document.createElement('option');
      option.textContent = 'Enroll a method first';
      select.append(option);
    }
  }

  function render() {
    renderOverview();
    renderTOTP();
    renderKeys();
    renderMethods();
    $('password-open').disabled = Boolean(model.config && model.config.password_change_disabled);
    $('keys-support').textContent = window.PublicKeyCredential ? 'Register a hardware security key or a platform passkey.' : 'This browser does not support security-key registration.';
    $('key-add-form').hidden = !window.PublicKeyCredential;
  }

  function setPage(page, updateHash) {
    for (const link of document.querySelectorAll('[data-settings-page]')) {
      link.classList.toggle('active', link.dataset.settingsPage === page);
    }
    for (const section of document.querySelectorAll('[data-settings-page-view]')) {
      section.hidden = section.dataset.settingsPageView !== page;
    }
    if (updateHash) history.replaceState(null, '', '/settings#' + page);
  }

  function closeElevation() {
    if (elevationDeleteID) api('/api/user/session/elevation/' + encodeURIComponent(elevationDeleteID), { method: 'DELETE' }).catch(() => {});
    elevationAction = null;
    elevationDeleteID = null;
    elevationStatus = null;
    $('elevation-modal').hidden = true;
    $('elevation-methods').replaceChildren();
    $('elevation-email').hidden = true;
    $('elevation-password').hidden = true;
    $('elevation-cancel-row').hidden = false;
  }

  function elevationButton(label, handler) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'settings-button';
    button.textContent = label;
    button.addEventListener('click', handler);
    $('elevation-methods').append(button);
  }

  async function finishElevationFactor() {
    const current = await api('/api/user/session/elevation');
    if (current.elevated || current.skip_second_factor) {
      const action = elevationAction;
      closeElevation();
      if (action) await action();
      return;
    }
    beginEmailElevation();
  }

  async function beginEmailElevation() {
    try {
      const attempt = await api('/api/user/session/elevation', { method: 'POST' });
      elevationDeleteID = attempt.delete_id;
      $('elevation-methods').hidden = true;
      $('elevation-cancel-row').hidden = true;
      $('elevation-email').hidden = false;
      $('elevation-message').textContent = 'A one-time code was sent to your account email.';
      $('elevation-code').focus();
    } catch (error) {
      showAlert(errorMessage(error));
    }
  }

  async function startTOTPFactor() {
    const form = document.createElement('form');
    form.className = 'settings-form';
    const label = document.createElement('label');
    const caption = document.createElement('span');
    caption.textContent = 'Authenticator code';
    const input = document.createElement('input');
    input.inputMode = 'numeric';
    input.autocomplete = 'one-time-code';
    input.required = true;
    label.append(caption, input);
    const actions = document.createElement('div');
    actions.className = 'settings-form-actions';
    const cancel = document.createElement('button');
    cancel.type = 'button';
    cancel.className = 'settings-button settings-button--quiet';
    cancel.textContent = 'Back';
    cancel.addEventListener('click', () => openElevation(elevationStatus));
    const submit = document.createElement('button');
    submit.type = 'submit';
    submit.className = 'settings-button';
    submit.textContent = 'Verify';
    actions.append(cancel, submit);
    form.append(label, actions);
    $('elevation-methods').replaceChildren(form);
    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      submit.disabled = true;
      try {
        await api('/api/secondfactor/totp', { method: 'POST', body: jsonBody({ token: input.value }) });
        await finishElevationFactor();
      } catch (error) {
        showAlert(errorMessage(error));
        submit.disabled = false;
      }
    });
    input.focus();
  }

  function base64urlBytes(value) {
    const normalized = String(value).replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((String(value).length + 3) % 4);
    const binary = atob(normalized);
    return Uint8Array.from(binary, (char) => char.charCodeAt(0));
  }

  function base64url(value) {
    let binary = '';
    for (const byte of new Uint8Array(value)) binary += String.fromCharCode(byte);
    return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  function creationOptions(value) {
    if (window.PublicKeyCredential.parseCreationOptionsFromJSON) return window.PublicKeyCredential.parseCreationOptionsFromJSON(value);
    return {
      ...value,
      challenge: base64urlBytes(value.challenge),
      user: { ...value.user, id: base64urlBytes(value.user.id) },
      excludeCredentials: (value.excludeCredentials || []).map((item) => ({ ...item, id: base64urlBytes(item.id) })),
    };
  }

  function credentialJSON(credential) {
    if (credential.toJSON) return credential.toJSON();
    return {
      clientExtensionResults: credential.getClientExtensionResults ? credential.getClientExtensionResults() : {},
      id: credential.id,
      rawId: base64url(credential.rawId),
      response: {
        attestationObject: base64url(credential.response.attestationObject),
        clientDataJSON: base64url(credential.response.clientDataJSON),
        transports: credential.response.getTransports ? credential.response.getTransports() : undefined,
      },
      type: credential.type,
    };
  }

  async function registerKey(description) {
    let result;
    try {
      result = await api('/api/secondfactor/webauthn/credential/register', {
        method: 'PUT',
        body: jsonBody({ description }),
      });
    } catch (error) {
      throw new Error('Could not start security-key registration: ' + errorMessage(error));
    }
    const options = creationOptions(result.publicKey || result);
    let credential;
    try {
      credential = await navigator.credentials.create({ publicKey: options });
    } catch (error) {
      if (error && error.name === 'NotAllowedError') throw new Error('Security-key registration was cancelled or timed out.');
      throw error;
    }
    if (!credential) throw new Error('The browser did not return a security key credential.');
    try {
      await api('/api/secondfactor/webauthn/credential/register', { method: 'POST', body: jsonBody(credentialJSON(credential)) });
    } catch (error) {
      throw new Error('Could not save security key: ' + errorMessage(error));
    }
  }

  async function secondFactorWebAuthn() {
    if (!window.PublicKeyCredential || !navigator.credentials) throw new Error('WebAuthn is not available in this browser.');
    $('elevation-methods').replaceChildren();
    const message = document.createElement('p');
    message.className = 'settings-note';
    message.textContent = 'Touch your security key or confirm with your passkey.';
    $('elevation-methods').append(message);
    const options = await api('/api/secondfactor/webauthn');
    const rawOptions = options.publicKey || options;
    const requestOptions = window.PublicKeyCredential.parseRequestOptionsFromJSON
      ? window.PublicKeyCredential.parseRequestOptionsFromJSON(rawOptions)
      : { ...rawOptions, challenge: base64urlBytes(rawOptions.challenge), allowCredentials: (rawOptions.allowCredentials || []).map((item) => ({ ...item, id: base64urlBytes(item.id) })) };
    const credential = await navigator.credentials.get({ publicKey: requestOptions });
    if (!credential) throw new Error('The browser did not return a security key credential.');
    try {
      await api('/api/secondfactor/webauthn', { method: 'POST', body: jsonBody({ response: credential.toJSON ? credential.toJSON() : credentialJSON(credential) }) });
    } catch (error) {
      throw new Error('Could not verify security key: ' + errorMessage(error));
    }
    await finishElevationFactor();
  }

  function openElevation(status) {
    elevationStatus = status;
    $('elevation-modal').hidden = false;
    $('elevation-message').textContent = 'Authelia requires another verification step before this action.';
    $('elevation-methods').hidden = false;
    $('elevation-methods').replaceChildren();
    $('elevation-email').hidden = true;
    $('elevation-password').hidden = true;
    $('elevation-cancel-row').hidden = false;
    if (!status.require_second_factor) {
      elevationButton('Send email code', beginEmailElevation);
      return;
    }
    if (!status.factor_knowledge) {
      $('elevation-methods').hidden = true;
      $('elevation-cancel-row').hidden = true;
      $('elevation-password').hidden = false;
      $('elevation-password-input').focus();
      return;
    }
    if (model.user.has_totp) elevationButton('Authenticator code', () => startTOTPFactor().catch((error) => showAlert(errorMessage(error))));
    if (model.user.has_webauthn && window.PublicKeyCredential) elevationButton('Security key or passkey', () => secondFactorWebAuthn().catch((error) => showAlert(errorMessage(error))));
    if (status.can_skip_second_factor) elevationButton('Send email code', beginEmailElevation);
    if (!$('elevation-methods').childElementCount) $('elevation-message').textContent = 'No supported verification method is available for this account.';
  }

  async function requireElevation(action) {
    try {
      const status = await api('/api/user/session/elevation');
      if (status.elevated || status.skip_second_factor) {
        await action();
        return;
      }
      elevationAction = action;
      openElevation(status);
    } catch (error) {
      if (error.elevation && elevationAction === null) {
        elevationAction = action;
        openElevation({ require_second_factor: false, can_skip_second_factor: true });
        beginEmailElevation();
        return;
      }
      if (error.secondFactor && elevationAction === null) {
        elevationAction = action;
        openElevation({ require_second_factor: true, factor_knowledge: true, can_skip_second_factor: true });
        return;
      }
      showAlert(errorMessage(error));
    }
  }

  async function refreshSecurity() {
    model.user = await api('/api/user/info');
    model.totp = await optional('/api/secondfactor/totp');
    model.keys = model.user.has_webauthn ? (await api('/api/secondfactor/webauthn/credentials')) || [] : [];
    render();
  }

  async function beginTOTPRegister() {
    const options = await api('/api/secondfactor/totp/register');
    const fill = (id, values, selected) => {
      const select = $(id);
      select.replaceChildren();
      for (const value of values) {
        const option = document.createElement('option');
        option.value = value;
        option.textContent = value;
        option.selected = String(value) === String(selected);
        select.append(option);
      }
    };
    fill('totp-algorithm', options.algorithms || [options.algorithm], options.algorithm);
    fill('totp-length', options.lengths || [options.length], options.length);
    fill('totp-period', options.periods || [options.period], options.period);
    $('totp-add').hidden = true;
    $('totp-remove').hidden = true;
    $('totp-register').hidden = false;
    $('totp-secret-panel').hidden = true;
  }

  async function generateTOTP() {
    const result = await api('/api/secondfactor/totp/register', {
      method: 'PUT',
      body: jsonBody({
        algorithm: $('totp-algorithm').value,
        length: Number($('totp-length').value),
        period: Number($('totp-period').value),
      }),
    });
    const uri = result.otpauth_url;
    const link = $('totp-uri');
    link.href = uri;
    link.textContent = 'Open in authenticator app';
    $('totp-secret').textContent = result.base32_secret;
    $('totp-secret-panel').hidden = false;
    $('totp-code').focus();
  }

  async function cancelTOTPRegister() {
    await api('/api/secondfactor/totp/register', { method: 'DELETE' }).catch(() => {});
    $('totp-register').hidden = true;
    renderTOTP();
  }

  async function renameKey(key) {
    const description = window.prompt('New security key description', key.description || '');
    if (!description || description.length > 64) return;
    await requireElevation(async () => {
      await api('/api/secondfactor/webauthn/credential/' + encodeURIComponent(key.id), { method: 'PUT', body: jsonBody({ description }) });
      await refreshSecurity();
      showAlert('Security key renamed.', true);
    });
  }

  async function removeKey(key) {
    if (!window.confirm('Remove ' + (key.description || 'this security key') + '?')) return;
    await requireElevation(async () => {
      await api('/api/secondfactor/webauthn/credential/' + encodeURIComponent(key.id), { method: 'DELETE' });
      await refreshSecurity();
      showAlert('Security key removed.', true);
    });
  }

  async function load() {
    try {
      model.state = await api('/api/state');
      model.user = await api('/api/user/info');
      model.config = await api('/api/configuration');
      model.totp = await optional('/api/secondfactor/totp');
      model.keys = model.user.has_webauthn ? (await api('/api/secondfactor/webauthn/credentials')) || [] : [];
      render();
      setPage(location.hash.slice(1) === 'security' ? 'security' : 'overview', false);
    } catch (error) {
      if (error.status === 401 || error.status === 403) {
        showAlert('Sign in to manage your account.');
        const link = document.createElement('a');
        link.href = '/?rd=' + encodeURIComponent('https://auth.vinnel.cloud/settings');
        link.textContent = ' Sign in';
        alertBox.append(link);
        document.querySelector('.settings-layout').hidden = true;
        return;
      }
      showAlert(errorMessage(error));
    }
  }

  for (const link of document.querySelectorAll('[data-settings-page]')) {
    link.addEventListener('click', () => setPage(link.dataset.settingsPage, true));
  }

  $('password-open').addEventListener('click', () => {
    $('password-form').hidden = false;
    $('password-old').focus();
  });
  $('password-cancel').addEventListener('click', () => {
    $('password-form').reset();
    $('password-form').hidden = true;
  });
  $('password-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    if ($('password-new').value !== $('password-repeat').value) {
      showAlert('The new passwords do not match.');
      return;
    }
    await requireElevation(async () => {
      await api('/api/change-password', {
        method: 'POST',
        body: jsonBody({ username: model.state.username, old_password: $('password-old').value, new_password: $('password-new').value }),
      });
      $('password-form').reset();
      $('password-form').hidden = true;
      showAlert('Password changed successfully.', true);
    });
  });

  $('totp-add').addEventListener('click', () => requireElevation(beginTOTPRegister));
  $('totp-generate').addEventListener('click', () => generateTOTP().catch((error) => showAlert(errorMessage(error))));
  $('totp-cancel').addEventListener('click', () => cancelTOTPRegister().catch((error) => showAlert(errorMessage(error))));
  $('totp-remove').addEventListener('click', () => requireElevation(async () => {
    await api('/api/secondfactor/totp', { method: 'DELETE' });
    await refreshSecurity();
    showAlert('Authenticator removed.', true);
  }));
  $('totp-register').addEventListener('submit', async (event) => {
    event.preventDefault();
    await api('/api/secondfactor/totp/register', { method: 'POST', body: jsonBody({ token: $('totp-code').value }) });
    await refreshSecurity();
    $('totp-register').hidden = true;
    showAlert('Authenticator enabled.', true);
  });

  $('key-add-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    const description = $('key-description').value.trim();
    if (!description) return;
    await requireElevation(async () => {
      await registerKey(description);
      $('key-add-form').reset();
      await refreshSecurity();
      showAlert('Security key registered.', true);
    });
  });

  $('preferred-method').addEventListener('change', async () => {
    try {
      await api('/api/user/info/2fa_method', { method: 'POST', body: jsonBody({ method: $('preferred-method').value }) });
      model.user.method = $('preferred-method').value;
      renderOverview();
      showAlert('Preferred method updated.', true);
    } catch (error) {
      showAlert(errorMessage(error));
    }
  });

  $('elevation-email').addEventListener('submit', async (event) => {
    event.preventDefault();
    try {
      await api('/api/user/session/elevation', { method: 'PUT', body: jsonBody({ otc: $('elevation-code').value }) });
      const action = elevationAction;
      closeElevation();
      if (action) await action();
    } catch (error) {
      showAlert(errorMessage(error));
    }
  });

  $('elevation-password').addEventListener('submit', async (event) => {
    event.preventDefault();
    try {
      await api('/api/secondfactor/password', { method: 'POST', body: jsonBody({ password: $('elevation-password-input').value }) });
      await finishElevationFactor();
    } catch (error) {
      showAlert(errorMessage(error));
    }
  });

  for (const button of document.querySelectorAll('[data-elevation-cancel]')) button.addEventListener('click', closeElevation);
  $('elevation-modal').querySelector('.settings-modal-backdrop').addEventListener('click', closeElevation);
  addEventListener('hashchange', () => setPage(location.hash.slice(1) === 'security' ? 'security' : 'overview', false));
  load();
})();
