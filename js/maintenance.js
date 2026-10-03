/* Upgrade mode (2026-10-03): one copy, loaded by every portal page but the
 * front door and the 404. It asks `maintenance_state()` once on load; while
 * it is on, a client-facing page is one cover in the page's language, and
 * the console hands the answer to js/admin.js, which covers it for everyone
 * but an admin (who works on under a banner). The database keeps answering:
 * this is the page's cover, not a lock.
 *
 * Set for later, a page already open covers itself when the start arrives;
 * with an end, a covered page lifts itself when it passes.
 *
 *   ADspaceMaintenance.ready        — a promise of { on, set, note, starts_at, ends_at }
 *   ADspaceMaintenance.cover(d)     — draws the cover for that state
 *   ADspaceMaintenance.when(iso)    — a moment in Malaysia time, in the page's language
 *   ADspaceMaintenance.watch(d, fn) — calls fn at the state's next change (within a day)
 */
(function () {
  var API = window.ADspaceAPI;
  var off = { on: false, set: false };
  var DAY = 864e5;

  function zh() { return String(document.documentElement.lang || '').indexOf('zh') === 0; }

  function when(iso) {
    var d = new Date(iso);
    if (isNaN(d)) return '';
    try {
      if (zh()) {
        return d.toLocaleString('zh-CN', { timeZone: 'Asia/Kuala_Lumpur', year: 'numeric', month: 'long',
          day: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false });
      }
      return d.toLocaleString('en-GB', { timeZone: 'Asia/Kuala_Lumpur', day: 'numeric', month: 'short',
        year: 'numeric', hour: 'numeric', minute: '2-digit', hour12: true })
        .replace(/\bSep\b/, 'Sept').replace(/\s?([ap])\.?m\.?$/i, function (m, x) { return ' ' + x.toLowerCase() + 'm'; });
    } catch (e) { return d.toISOString(); }
  }

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  var shown = null;
  function paint() {
    var box = document.getElementById('maintCover');
    if (!box || !shown) return;
    var W = window.ADspaceWords || {};
    var set = (zh() ? W.zh : W.en) || {};
    var back = shown.ends_at ? (set.maintBack || 'Expected back by {when}.').replace('{when}', when(shown.ends_at)) : '';
    box.querySelector('.cover-panel').innerHTML =
      '<h2 id="maintTitle">' + esc(set.maintTitle || 'Upgrading in progress') + '</h2>' +
      '<p>' + esc(set.maintText || 'The portal is being upgraded. Please check back shortly.') + '</p>' +
      (back ? '<p class="maint-back">' + esc(back) + '</p>' : '') +
      (shown.note ? '<p class="maint-note">' + esc(shown.note) + '</p>' : '') +
      (shown.out ? '<button class="btn btn-sm maint-out" type="button" id="maintOut">Sign out</button>' : '');
    var out = document.getElementById('maintOut');
    if (out) out.addEventListener('click', shown.out);
  }

  /* The portal's own cover, laid over everything the page drew: a client
     page's bar stays (its 中文 switch included), and the work under it is out
     of reach and out of the tab order. `d.out`, where given, is a way to
     sign out (the console's). */
  function cover(d) {
    d = d || {};
    /* Asked from the page's head, the answer can land before the body is
       parsed: the cover waits for the page it lies over. */
    if (!document.body || document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', function () { cover(d); }, { once: true });
      return;
    }
    shown = d;
    var box = document.getElementById('maintCover');
    if (!box) {
      box = document.createElement('section');
      box.className = 'cover maint-cover';
      box.id = 'maintCover';
      box.setAttribute('role', 'alertdialog');
      box.setAttribute('aria-modal', 'true');
      box.setAttribute('aria-labelledby', 'maintTitle');
      box.innerHTML = '<div class="cover-inner"><div class="cover-panel"></div></div>';
      document.body.appendChild(box);
      document.body.classList.add('is-maint');
      Array.prototype.forEach.call(document.body.children, function (el) {
        if (el !== box && !el.classList.contains('topbar') && el.tagName !== 'SCRIPT') {
          el.setAttribute('inert', '');
        }
      });
      if (window.MutationObserver) {
        new MutationObserver(paint).observe(document.documentElement, { attributes: true, attributeFilter: ['lang'] });
      }
    }
    paint();
    var a = document.activeElement;
    if (a && a !== document.body && !box.contains(a) && !(a.closest && a.closest('.topbar'))) {
      try { a.blur(); } catch (e) {}
    }
  }

  /* The next moment this state changes on its own: a start ahead, or an end
     while it covers. Only within a day, since a page left open longer reads
     again on its next load anyway. */
  function watch(d, fn) {
    var at = d.set && !d.on && d.starts_at ? d.starts_at : (d.on && d.ends_at ? d.ends_at : null);
    if (!at) return;
    var ms = new Date(at).getTime() - Date.now();
    if (ms > 0 && ms < DAY) setTimeout(fn, ms + 1000);
  }

  function ask() {
    return (API && API.client && API.client.rpc)
      ? Promise.resolve(API.client.rpc('maintenance_state')).then(function (r) {
          var d = r && !r.error && r.data;
          return d && (d.on || d.set) ? d : off;
        }).catch(function () { return off; })
      : Promise.resolve(off);
  }

  var ready = ask();

  var inConsole = /^\/admin(\/|$)/.test(location.pathname);
  if (!inConsole) {
    ready.then(function (d) {
      if (d.on) cover(d);
      watch(d, function () { location.reload(); });
    });
  }

  window.ADspaceMaintenance = { ready: ready, ask: ask, cover: cover, when: when, watch: watch };
})();
