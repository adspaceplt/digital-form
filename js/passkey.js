/* ADspacePasskey — signing in to the console with a passkey, and keeping
 * your own passkeys (asked for by the user on 2026-09-26: "we all using mac").
 *
 * A passkey is Touch ID, Face ID or the device password standing in for the
 * emailed code: no email to wait for, nothing to type, and nothing a phishing
 * page can reuse, because the browser only offers it to digital.adspace.me.
 * The email stays the way in for a new colleague and for a new device, so
 * this is a second button on the sign-in card and never a replacement.
 *
 * Supabase holds the passkeys (Authentication > Passkeys); nothing about them
 * is stored in the portal's own tables. The page never sees a secret: the
 * browser signs a challenge the server issued and the server checks it.
 *
 *   ADspacePasskey.on      whether this browser and this library can use one
 *   ADspacePasskey.open()  the Passkeys sheet, from the account menu
 *   ADspacePasskey.offer() once per browser, after an email sign-in on a
 *                          device that has Touch ID, Face ID or a device password
 */
(function () {
  'use strict';

  var API = window.ADspaceAPI;
  var db = API && API.client;
  var $ = function (id) { return document.getElementById(id); };
  var esc = function (s) {
    return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  };

  /* The library that knows passkeys is 2.117 and later; a browser with no
     WebAuthn has nothing to offer. Where either is missing the button and
     the menu item stay hidden, and the email is the way in as it always was. */
  var on = Boolean(db && db.auth && typeof db.auth.signInWithPasskey === 'function' &&
    db.auth.passkey && window.PublicKeyCredential);

  var OFFERED = 'adspace-passkey-offer';
  function seen() { try { return localStorage.getItem(OFFERED) === '1'; } catch (e) { return true; } }
  function remember() { try { localStorage.setItem(OFFERED, '1'); } catch (e) {} }

  /* The browser's and the server's answers, in our words. Pressing Cancel in
     the system's own passkey prompt is a decision, not a fault, so it says
     nothing at all. */
  function cancelled(err) {
    var code = String(err.code || ''), name = String((err.cause && err.cause.name) || err.name || '');
    return code === 'ERROR_CEREMONY_ABORTED' || /NotAllowedError|AbortError/.test(name) ||
      /not allowed|timed out|cancel/i.test(String(err.message || ''));
  }
  function said(err, act) {
    var m = String(err.message || ''), code = String(err.code || '');
    var name = String((err.cause && err.cause.name) || err.name || '');
    if (/does not support WebAuthn/i.test(m)) return 'This browser cannot use passkeys. Use your email.';
    if (err.status === 404 || /disabled|not enabled/i.test(m + ' ' + code)) {
      return 'Passkeys are not switched on yet. Use your email.';
    }
    if (/InvalidStateError/.test(name)) return 'This device already holds a passkey for you.';
    if (/captcha/i.test(m + ' ' + code)) return 'The security check did not finish. Please try again.';
    if (/rate limit|too many/i.test(m)) return 'Too many tries. Please wait a few minutes.';
    if (act === 'in' && /(credential|passkey)/i.test(m + ' ' + code) && /not found|unknown|invalid|no /i.test(m + ' ' + code)) {
      return 'This passkey is not on file. Sign in with your email, then add it again.';
    }
    return act === 'in' ? 'Not signed in. Please try again.' : 'Not added. Please try again.';
  }
  function say(id, text, tone) {
    var el = $(id);
    if (!el) return;
    el.textContent = text || '';
    el.className = 'msg' + (text ? ' ' + (tone || 'err') : '');
  }

  // ---- Sign in ------------------------------------------------------------
  var inBtn = $('authPasskey');
  if (inBtn && on) {
    inBtn.hidden = false;
    inBtn.addEventListener('click', function () {
      var b = inBtn;
      b.disabled = true;
      say('authMsg', '');
      /* The captcha guards this door as it guards the email: where Supabase
         asks for one, the challenge is only issued with a token. */
      var go = window.ADspaceCaptcha ? window.ADspaceCaptcha.options(b, {}) : Promise.resolve({});
      go.then(function (o) {
        return db.auth.signInWithPasskey({ options: o.captchaToken ? { captchaToken: o.captchaToken } : {} });
      }).then(function (r) {
        b.disabled = false;
        if (r && r.error) { if (!cancelled(r.error)) say('authMsg', said(r.error, 'in')); return; }
        /* Signed in with one, so this browser need never be asked to add one.
           The console draws itself from the auth event, as after a code. */
        remember();
      }, function (e) {
        b.disabled = false;
        if (!e || !cancelled(e)) say('authMsg', 'Not signed in. Please try again.');
      });
    });
  }

  // ---- The Passkeys sheet -------------------------------------------------
  var sheet = $('pkSheet');
  var list = $('pkList');
  var opener = null;

  function when(iso) {
    var d = new Date(iso);
    if (!iso || isNaN(d.getTime())) return '';
    return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
  }
  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="19" cy="12" r="1.8"/></svg>';
  var KEY = '<svg class="pk-ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="8" cy="15" r="4"/><path d="M10.8 12.2 20 3"/><path d="m16 7 3 3"/><path d="m14 9 2 2"/></svg>';

  var rows = [];
  function paint() {
    if (!rows.length) {
      list.innerHTML = '<p class="pk-empty">No passkeys.</p>';
      return;
    }
    list.innerHTML = rows.map(function (p) {
      var meta = ['Added ' + when(p.created_at), p.last_used_at ? 'Last used ' + when(p.last_used_at) : '']
        .filter(function (x) { return x && x !== 'Added '; }).join(' · ');
      return '<div class="pk-row" data-id="' + esc(p.id) + '">' + KEY +
        '<span class="pk-who"><b>' + esc(p.friendly_name || 'Passkey') + '</b>' +
          (meta ? '<small>' + esc(meta) + '</small>' : '') + '</span>' +
        '<span class="team-act pk-act"><button class="kmenu-btn" type="button" aria-label="More actions" aria-haspopup="true" aria-expanded="false">' + DOTS + '</button>' +
          '<div class="kmenu" hidden>' +
            '<button class="kmenu-item" data-act="rename" type="button"><b>Rename</b></button>' +
            '<button class="kmenu-item is-danger" data-soft data-act="remove" type="button"><b>Remove</b></button>' +
          '</div></span>' +
      '</div>';
    }).join('');
    Array.prototype.forEach.call(list.querySelectorAll('.kmenu-btn'), function (b) {
      b.addEventListener('click', function (e) {
        e.stopPropagation();
        var menu = b.parentNode.querySelector('.kmenu');
        var open = menu.hidden;
        shutMenus();
        menu.hidden = !open;
        b.setAttribute('aria-expanded', String(open));
        if (open && window.ADspaceMenu) window.ADspaceMenu.place(b, menu);
      });
    });
    Array.prototype.forEach.call(list.querySelectorAll('.kmenu-item[data-act]'), function (it) {
      it.addEventListener('click', function () {
        var id = it.closest('.pk-row').getAttribute('data-id');
        var p = rows.filter(function (x) { return String(x.id) === id; })[0];
        shutMenus();
        if (!p) return;
        if (it.getAttribute('data-act') === 'rename') rename(p); else remove(p);
      });
    });
  }
  function shutMenus() {
    if (!list) return;
    Array.prototype.forEach.call(list.querySelectorAll('.kmenu'), function (m) {
      m.hidden = true;
      var b = m.parentNode.querySelector('.kmenu-btn');
      if (b) b.setAttribute('aria-expanded', 'false');
    });
  }
  document.addEventListener('click', function (e) {
    if (list && !(e.target.closest && e.target.closest('.pk-act'))) shutMenus();
  });
  if (window.ADspaceMenu) window.ADspaceMenu.onScroll(shutMenus);

  /* A read that failed is not an empty list, so it says so and offers the
     way back rather than drawing "No passkeys." over a refusal. */
  function load(then) {
    db.auth.passkey.list().then(function (r) {
      if (r.error) {
        list.innerHTML = '';
        say('pkMsg', r.error.status === 404 ? 'Passkeys are not switched on yet.' : 'Passkeys could not be loaded. ' + (r.error.message || ''));
        return;
      }
      rows = (r.data || []).slice().sort(function (a, b) {
        return String(b.created_at || '').localeCompare(String(a.created_at || ''));
      });
      if (rows.length) remember();
      paint();
      if (then) then();
    }, function () { say('pkMsg', 'Passkeys could not be loaded.'); });
  }

  function open(btn) {
    if (!on || !sheet) return;
    opener = btn || null;
    say('pkMsg', '');
    list.innerHTML = '<div class="skel"><div class="skel-row"></div></div>';
    window.ADspaceSheet.show(sheet, { opener: opener });
    load();
  }
  function shut() { window.ADspaceSheet.close(); }

  function add() {
    var b = $('pkAdd');
    b.disabled = true;
    say('pkMsg', '');
    db.auth.registerPasskey().then(function (r) {
      b.disabled = false;
      if (r && r.error) { if (!cancelled(r.error)) say('pkMsg', said(r.error, 'add')); return; }
      remember();
      load(function () { say('pkMsg', 'Added. Next time, sign in with a passkey.', 'ok'); });
    }, function (e) {
      b.disabled = false;
      if (!e || !cancelled(e)) say('pkMsg', 'Not added. Please try again.');
    });
  }

  function rename(p) {
    window.ADspaceConfirm.ask({
      title: 'Rename passkey',
      go: 'Save',
      field: { label: 'Name', value: p.friendly_name || '', placeholder: 'MacBook Air', need: 'A name is required.' }
    }, function (v) {
      db.auth.passkey.update({ passkeyId: p.id, friendlyName: v }).then(function (r) {
        if (r && r.error) { say('pkMsg', 'Not saved. ' + (r.error.message || '')); return; }
        load(function () { say('pkMsg', 'Saved.', 'ok'); });
      });
    });
  }

  /* Removing a passkey cannot be taken back, but nothing is lost with it:
     the email still signs the person in and a passkey can be added again.
     The sheet says both before it goes. */
  function remove(p) {
    window.ADspaceConfirm.ask({
      title: 'Remove passkey',
      body: (p.friendly_name || 'This passkey') + ' will no longer sign you in. Your email still does, '
          + 'and a passkey can be added again.',
      go: 'Remove',
      tone: 'danger'
    }, function () {
      db.auth.passkey.delete({ passkeyId: p.id }).then(function (r) {
        if (r && r.error) { say('pkMsg', 'Not removed. ' + (r.error.message || '')); return; }
        load(function () { say('pkMsg', 'Removed.', 'ok'); });
      });
    });
  }

  if (sheet) {
    $('pkAdd').addEventListener('click', add);
    $('pkClose').addEventListener('click', shut);
    $('pkShut').addEventListener('click', shut);
  }

  /* ---- The offer, once --------------------------------------------------
     After an email sign-in on a device that can hold a passkey, and only
     while the person has none: one question, asked once per browser, with
     Not now as the way out. Asked on every sign-in it would be a nag. */
  function offer() {
    if (!on || seen()) return;
    var P = window.PublicKeyCredential;
    if (!P || typeof P.isUserVerifyingPlatformAuthenticatorAvailable !== 'function') return;
    P.isUserVerifyingPlatformAuthenticatorAvailable().then(function (yes) {
      if (!yes) return;
      db.auth.passkey.list().then(function (r) {
        if (r.error) return;
        remember();
        if ((r.data || []).length) return;
        window.ADspaceConfirm.ask({
          title: 'Sign in with a passkey',
          body: 'Add a passkey and sign in on this device with Touch ID, Face ID or your device password, '
              + 'without waiting for an email.',
          go: 'Add passkey',
          cancel: 'Not now'
        }, function () { open(null); add(); });
      }, function () {});
    }, function () {});
  }

  window.ADspacePasskey = { on: on, open: open, offer: offer };
})();
