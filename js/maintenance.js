/* Upgrade mode (2026-10-03): one copy, loaded by every portal page but the
 * front door and the 404. It asks `maintenance_state()` once on load; while
 * it is on, a client-facing page is one cover in the page's language, and
 * the console hands the answer to js/admin.js, which covers it for everyone
 * but an admin (who works on under a banner). The database keeps answering:
 * this is the page's cover, not a lock.
 *
 * Set for later, a page already open covers itself when the start arrives;
 * with an end, a covered page lifts itself when it passes. An open page also
 * asks again every minute while it is on screen and on every return to it
 * (2026-10-04), so switching on covers it and switching off reloads it,
 * which brings the page's latest version. A read that fails changes nothing.
 *
 *   ADspaceMaintenance.ready        — a promise of { on, set, note, starts_at, ends_at }
 *   ADspaceMaintenance.cover(d)     — draws the cover for that state
 *   ADspaceMaintenance.when(iso)    — a moment in Malaysia time, in the page's language
 *   ADspaceMaintenance.watch(d, fn) — calls fn at the state's next change (within a day);
 *                                    answers its timer
 *   ADspaceMaintenance.ask(strict)  — the state now; strict answers null for a failed read
 *   ADspaceMaintenance.often(key, take, alone, opts)
 *                                  — joins the page's one check a minute (`page_pulse`)
 */
(function () {
  var API = window.ADspaceAPI;
  var off = { on: false, set: false };
  var DAY = 864e5;
  var EVERY = 60000;

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
      '<p>' + esc(set.maintText || "We'll be right back!") + '</p>' +
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
      /* A dialog only where it holds something to press (the console's Sign
         out); else a named region. Either way it takes focus, so a screen
         reader reads it first. */
      box.setAttribute('role', d.out ? 'alertdialog' : 'region');
      if (d.out) box.setAttribute('aria-modal', 'true');
      box.setAttribute('aria-labelledby', 'maintTitle');
      box.setAttribute('tabindex', '-1');
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
    if (!a || a === document.body || (!box.contains(a) && !(a.closest && a.closest('.topbar')))) {
      try { box.focus({ preventScroll: true }); } catch (e) {}
    }
  }

  /* The next moment this state changes on its own: a start ahead, or an end
     while it covers. Only within a day, since a page left open longer reads
     again on its next load anyway. */
  function watch(d, fn) {
    var at = d.set && !d.on && d.starts_at ? d.starts_at : (d.on && d.ends_at ? d.ends_at : null);
    if (!at) return null;
    var ms = new Date(at).getTime() - Date.now();
    return ms > 0 && ms < DAY ? setTimeout(fn, ms + 1000) : null;
  }

  function ask(strict) {
    var failed = strict ? null : off;
    return (API && API.client && API.client.rpc)
      ? Promise.resolve(API.client.rpc('maintenance_state')).then(function (r) {
          if (!r || r.error) return failed;
          var d = r.data;
          return d && (d.on || d.set) ? d : off;
        }).catch(function () { return failed; })
      : Promise.resolve(failed);
  }

  function norm(d) { return d && (d.on || d.set) ? d : off; }

  /* Every minute while on screen, and on every return to it, one request
     answers every check the page keeps (`page_pulse`: upgrade mode, the
     announcements, the bell), each answer handed to the part that joined
     for it (2026-10-09: an open console made four requests a minute, each a
     line Supabase logs and meters). `often(key, take, alone, opts)`: `take`
     is handed the part's answer; `alone` asks by itself, which every part
     does while the database holds no `page_pulse`. `opts.audience` names
     the announcements a page shows, `opts.bell` asks for the bell. A read
     that fails changes nothing. */
  var parts = [], pulse = { audience: null, bell: false }, alone = false, ticking = false;
  function tick() {
    if (document.visibilityState !== 'visible' || !parts.length) return;
    var each = function () { parts.forEach(function (p) { p.alone(); }); };
    if (alone || !(API && API.client && API.client.rpc)) { each(); return; }
    Promise.resolve(API.client.rpc('page_pulse', { p_audience: pulse.audience, p_bell: pulse.bell })).then(function (r) {
      if (r && r.error) {
        if (/PGRST202|page_pulse|schema cache/i.test(String(r.error.code || '') + ' ' + String(r.error.message || ''))) {
          alone = true; each();
        }
        return;
      }
      var d = r && r.data;
      if (!d) return;
      parts.forEach(function (p) {
        if (Object.prototype.hasOwnProperty.call(d, p.key)) p.take(p.key === 'maintenance' ? norm(d[p.key]) : d[p.key]);
      });
    }).catch(function () {});
  }
  function often(key, take, ask1, opts) {
    parts.push({ key: key, take: take || function () {}, alone: ask1 || function () {} });
    if (opts && opts.audience) pulse.audience = opts.audience;
    if (opts && opts.bell) pulse.bell = true;
    if (ticking) return;
    ticking = true;
    document.addEventListener('visibilitychange', tick);
    setInterval(tick, EVERY);
  }

  var ready = ask();

  var inConsole = /^\/admin(\/|$)/.test(location.pathname);
  if (!inConsole) {
    var timer = null;
    var settle = function (d) {
      if (!d) return;
      if (document.getElementById('maintCover') && !d.on) { location.reload(); return; }
      if (d.on) cover(d);
      if (timer) clearTimeout(timer);
      timer = watch(d, again);
    };
    var again = function () { ask(true).then(settle); };
    ready.then(settle);
    often('maintenance', settle, again);
  }

  window.ADspaceMaintenance = { ready: ready, ask: ask, cover: cover, when: when, watch: watch, often: often };
})();
