/*
 * Notifications on this device (Web Push). One copy for the three pages that
 * offer them:
 *   - the console, for the signed-in colleague's bell (audience 'team');
 *   - the creator selection page, for one campaign by its token ('client');
 *   - the creator's page, for that creator by their code ('creator').
 *
 * The page says what it follows (setup). This file asks the browser for
 * permission, subscribes the page's own service worker with the sender's
 * public key (push_public_key), and hands the device to the database
 * (push_subscribe), which proves the follow as the page proves itself.
 *
 * A device that has it on keeps a flag, per page, so one that lost its
 * subscription (Refresh app unregisters the worker; a browser rotates it)
 * takes it back on the next load without asking, while permission stands.
 *
 * Where it cannot work the reason is named, never hidden behind a dead
 * control: an iPhone only delivers to a page added to the Home Screen
 * ('install'); a site whose notifications were blocked ('blocked'). Where
 * the browser has no push at all, or the sender has no keys yet, there is
 * no control ('none', 'nokey').
 *
 * The client pages' control is a bell in the bar (chrome.js `push`) opening a
 * small named dialog; the console's is an item in the account menu (admin.js).
 */
(function () {
  var API = window.ADspaceAPI;
  var db = API && API.client;
  var cfg = null;          // { audience, ref(), lang(), sw, scope }
  var keyP = null;         // the sender's public key, asked once

  var ua = navigator.userAgent || '';
  var ios = /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);

  function standalone() {
    return navigator.standalone === true ||
      !!(window.matchMedia && window.matchMedia('(display-mode: standalone)').matches);
  }
  function able() {
    return location.protocol !== 'file:' && 'serviceWorker' in navigator &&
      'PushManager' in window && 'Notification' in window;
  }
  /* Why this device cannot, or '' where it can. */
  function why() {
    if (!able()) return ios && !standalone() ? 'install' : 'none';
    if (Notification.permission === 'denied') return 'blocked';
    return '';
  }

  function flagKey() { return 'adspace-push:' + (cfg ? cfg.scope : ''); }
  function flag(on) {
    try {
      if (on === undefined) return localStorage.getItem(flagKey()) === '1';
      if (on) localStorage.setItem(flagKey(), '1'); else localStorage.removeItem(flagKey());
    } catch (e) { return false; }
  }

  function ref() { return cfg && cfg.ref ? (cfg.ref() || null) : null; }
  function lang() { return cfg && cfg.lang ? (cfg.lang() === 'zh' ? 'zh' : 'en') : 'en'; }

  function publicKey() {
    if (!keyP) {
      keyP = db ? db.rpc('push_public_key').then(function (r) {
        return r.error ? null : (r.data || null);
      }).catch(function () { return null; }) : Promise.resolve(null);
    }
    return keyP;
  }
  function bytes(b64) {
    var s = String(b64).replace(/-/g, '+').replace(/_/g, '/');
    var bin = atob(s + '==='.slice((s.length + 3) % 4));
    var out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  function same(a, b) {
    if (!a || !b) return false;
    a = new Uint8Array(a); b = new Uint8Array(b);
    if (a.length !== b.length) return false;
    for (var i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
    return true;
  }

  /* The page's own worker, active: a subscription needs one. */
  function worker() {
    return navigator.serviceWorker.register(cfg.sw, { scope: cfg.scope }).then(function (r) {
      if (r.active) return r;
      return new Promise(function (res) {
        var w = r.installing || r.waiting;
        if (!w) { res(r); return; }
        var done = function () { res(r); };
        w.addEventListener('statechange', function () { if (w.state === 'activated') done(); });
        setTimeout(done, 8000);
      });
    });
  }
  function current() {
    if (!able()) return Promise.resolve(null);
    return navigator.serviceWorker.getRegistration(cfg.scope).then(function (r) {
      return r ? r.pushManager.getSubscription() : null;
    }).catch(function () { return null; });
  }

  /* Is this device on for what the page follows? { on, why } */
  function state() {
    if (!cfg) return Promise.resolve({ on: false, why: 'none' });
    var w = why();
    if (w === 'none' || w === 'install') return Promise.resolve({ on: false, why: w });
    return publicKey().then(function (key) {
      if (!key) return { on: false, why: 'nokey' };
      if (w) return { on: false, why: w };
      return current().then(function (s) {
        if (!s) return { on: false, why: '' };
        return db.rpc('push_status', { p_endpoint: s.endpoint, p_audience: cfg.audience, p_ref: ref() })
          .then(function (r) { return { on: !!(r.data && r.data.on), why: '' }; })
          .catch(function () { return { on: false, why: '' }; });
      });
    });
  }

  /* Subscribe and hand the device over. `quiet` never asks for permission:
     it is the heal on load, which only runs where permission stands. */
  function on(quiet) {
    if (!cfg) return Promise.resolve({ error: 'none' });
    var w = why();
    if (w) return Promise.resolve({ error: w });
    var ask = quiet ? Promise.resolve(Notification.permission) :
      new Promise(function (res) {
        var p = Notification.requestPermission(res);   // the old Safari form answers by callback
        if (p && p.then) p.then(res);
      });
    return ask.then(function (perm) {
      if (perm !== 'granted') return { error: perm === 'denied' ? 'blocked' : 'dismissed' };
      return publicKey().then(function (key) {
        if (!key) return { error: 'nokey' };
        var appKey = bytes(key);
        return worker().then(function (reg) {
          return reg.pushManager.getSubscription().then(function (s) {
            // A subscription made with another key cannot be reused.
            if (s && s.options && s.options.applicationServerKey && !same(s.options.applicationServerKey, appKey)) {
              return s.unsubscribe().then(function () { return null; });
            }
            return s;
          }).then(function (s) {
            return s || reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: appKey });
          });
        }).then(function (s) {
          var j = s.toJSON();
          return db.rpc('push_subscribe', {
            p_audience: cfg.audience, p_ref: ref(), p_endpoint: j.endpoint,
            p_p256dh: j.keys && j.keys.p256dh, p_auth: j.keys && j.keys.auth, p_lang: lang()
          }).then(function (r) {
            if (r.error) return { error: 'failed' };
            if (r.data && r.data.error) return { error: r.data.error };
            flag(true);
            return { ok: true };
          });
        });
      });
    }).catch(function () { return { error: 'failed' }; });
  }

  /* Stop what this page follows. The browser's subscription goes too once
     the device follows nothing else from this page's worker. */
  function off(all) {
    if (!cfg) return Promise.resolve({ ok: true });
    flag(false);
    return current().then(function (s) {
      if (!s) return { ok: true };
      var args = all ? { p_endpoint: s.endpoint } :
        { p_endpoint: s.endpoint, p_audience: cfg.audience, p_ref: ref() };
      return db.rpc('push_unsubscribe', args).then(function (r) {
        if (r.error) return { error: 'failed' };
        var left = r.data && r.data.left;
        return (left ? Promise.resolve() : s.unsubscribe().catch(function () {})).then(function () {
          return { ok: true };
        });
      });
    }).catch(function () { return { error: 'failed' }; });
  }

  /* On load, and when the page's language changes: a device that had it on
     is put back, with its language, without a prompt. */
  function heal() {
    if (!cfg || !flag() || why() || Notification.permission !== 'granted') return Promise.resolve(null);
    return on(true);
  }

  function setup(opts) { cfg = opts; return heal(); }

  /* ---- The bar's bell, on the client pages -------------------------------- */
  var BELL = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15z"/><path d="M10 20a2 2 0 0 0 4 0"/></svg>';
  var BELL_ON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15z"/><path d="M10 20a2 2 0 0 0 4 0"/>' +
    '<path d="M3 8.5a8 8 0 0 1 2.2-4"/><path d="M21 8.5a8 8 0 0 0-2.2-4"/></svg>';

  var ui = null;           // { btn, pop, line, go, msg, words() }
  var isOn = false, reason = '';

  function paintBell() {
    if (!ui) return;
    var w = ui.words();
    ui.btn.innerHTML = isOn ? BELL_ON : BELL;
    ui.btn.classList.toggle('is-on', isOn);
    ui.btn.setAttribute('aria-label', w.label + (isOn ? ' · ' + w.onWord : ''));
    ui.title.textContent = w.label;
    ui.x.setAttribute('aria-label', w.close || 'Close');
    ui.line.textContent = reason === 'install' ? w.install : reason === 'blocked' ? w.blocked :
      (isOn ? w.isOn : w[cfg.audience]);
    ui.go.hidden = reason === 'install' || reason === 'blocked';
    ui.go.textContent = isOn ? w.off : w.on;
    ui.go.className = 'btn btn-sm' + (isOn ? '' : ' btn-primary');
  }
  function shut(back) {
    if (!ui || ui.pop.hidden) return;
    ui.pop.hidden = true;
    ui.btn.setAttribute('aria-expanded', 'false');
    if (back) ui.btn.focus();
  }
  function openPop() {
    ui.msg.hidden = true;
    paintBell();
    ui.pop.hidden = false;
    ui.btn.setAttribute('aria-expanded', 'true');
    /* Hung from the bell with a caret at a desk, docked at the foot of the
       screen on a phone (js/menu.js). */
    if (window.ADspaceMenu && window.ADspaceMenu.pop) window.ADspaceMenu.pop(ui.btn, ui.pop, 'right');
    (ui.go.hidden ? ui.pop : ui.go).focus({ preventScroll: true });
  }

  /* Draw the bell once the page knows what it follows. `words` answers the
     page's current language (ADspaceWords' `push` group). */
  function control(words) {
    var btn = document.getElementById('pushBtn');
    if (!btn || !cfg) return;
    if (!ui) {
      var host = btn.parentNode;
      var pop = document.createElement('div');
      pop.className = 'kmenu pushpop';
      pop.id = 'pushPop';
      pop.hidden = true;
      pop.tabIndex = -1;
      pop.setAttribute('role', 'dialog');
      pop.setAttribute('aria-labelledby', 'pushPopTitle');
      pop.innerHTML = '<div class="popcard-head"><p class="pushpop-title" id="pushPopTitle"></p>' +
        '<button class="iconbtn popcard-x" id="pushX" type="button"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg></button></div>' +
        '<p class="pushpop-line" id="pushPopLine"></p>' +
        '<div class="pushpop-acts"><button class="btn btn-sm" id="pushGo" type="button"></button></div>' +
        '<p class="msg err" id="pushMsg" role="status" hidden></p>';
      host.appendChild(pop);
      ui = { btn: btn, pop: pop, title: pop.querySelector('#pushPopTitle'), line: pop.querySelector('#pushPopLine'),
             go: pop.querySelector('#pushGo'), msg: pop.querySelector('#pushMsg'), x: pop.querySelector('#pushX'), words: words };
      ui.x.addEventListener('click', function (e) { e.stopPropagation(); shut(true); });
      if (window.ADspaceMenu) window.ADspaceMenu.onScroll(function () { shut(false); });
      btn.setAttribute('aria-haspopup', 'dialog');
      btn.setAttribute('aria-expanded', 'false');
      btn.setAttribute('aria-controls', 'pushPop');
      btn.addEventListener('click', function (e) {
        e.stopPropagation();
        if (ui.pop.hidden) openPop(); else shut(true);
      });
      ui.go.addEventListener('click', function () {
        var w = ui.words();
        ui.go.disabled = true;
        ui.msg.hidden = true;
        (isOn ? off(false) : on(false)).then(function (r) {
          ui.go.disabled = false;
          if (r && r.ok) { isOn = !isOn; reason = ''; paintBell(); ui.go.focus(); return; }
          var e = r && r.error;
          if (e === 'blocked' || e === 'install') { reason = e; paintBell(); ui.pop.focus(); return; }
          if (e === 'dismissed') return;
          ui.msg.textContent = w.failed;
          ui.msg.hidden = false;
        });
      });
      document.addEventListener('click', function (e) {
        if (!ui.pop.hidden && !ui.pop.contains(e.target) && e.target !== ui.btn) shut(false);
      });
      document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && !ui.pop.hidden) { e.preventDefault(); shut(true); }
      });
    }
    ui.words = words;
    return state().then(function (s) {
      isOn = s.on;
      reason = s.why;
      ui.btn.hidden = s.why === 'none' || s.why === 'nokey';
      paintBell();
      return s;
    });
  }
  /* The page's language changed: repaint the words, and tell the database
     which language this device now reads. */
  function relabel() { paintBell(); if (isOn) heal(); }

  window.ADspacePush = {
    setup: setup, state: state, on: on, off: off, heal: heal, why: why,
    control: control, relabel: relabel, shut: function () { shut(false); }
  };
})();
