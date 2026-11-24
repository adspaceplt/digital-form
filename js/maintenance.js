/* Upgrade mode (2026-10-03), a page at a time since 2026-10-29 (Page
 * availability: Upgrade in progress or Temporarily unavailable, each page's
 * own row from `page_states()`): one copy, loaded by every portal page but the
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
  /* Page availability (2026-10-29): each page reads its own row
     (`page_states`), by the first part of its address; a database before
     answers the whole portal (`maintenance_state`). */
  /* Every page, the system pages included (EVERY PAGE AVAILABLE, 2026-11-21):
     the front door by its root, the 404 by its own script tag's
     `data-page="notfound"` (it answers any address). */
  var OWN = document.currentScript && document.currentScript.getAttribute('data-page');
  var PAGE = (function () {
    if (OWN) return OWN;
    var m = /^\/([a-z-]+)/.exec(location.pathname), k = m ? m[1] : '';
    if (!k && /^\/(index\.html)?$/.test(location.pathname)) return 'home';
    return k === 'supplier-details' ? 'supplier'
      : ['admin', 'client', 'review', 'script', 'details', 'creators', 'creator', 'quote', 'supplier', 'verify', 'careers', 'card', 'feedback'].indexOf(k) >= 0 ? k : null;
  })();
  /* A page with no database library (the front door, the 404) asks the one
     read itself, with the public key, as the front door asks its holidays. */
  function rpc(name, args) {
    if (API && API.client && API.client.rpc) return Promise.resolve(API.client.rpc(name, args));
    /* A page that loads js/api.js and holds no client (a demo whose sample
       data did not arrive, a library that failed) reaches no database. */
    if (API || window.ADSPACE_DEMO) return Promise.resolve({ error: { message: 'no client' } });
    var cfg = window.ADSPACE_CONFIG || {};
    if (!cfg.supabaseUrl || !cfg.supabaseAnonKey || !window.fetch) return Promise.resolve({ error: { message: 'no client' } });
    return fetch(cfg.supabaseUrl + '/rest/v1/rpc/' + name, { method: 'POST',
      headers: { apikey: cfg.supabaseAnonKey, Authorization: 'Bearer ' + cfg.supabaseAnonKey, 'Content-Type': 'application/json' },
      body: JSON.stringify(args || {}) })
      .then(function (r) { return r.json().then(function (d) { return r.ok ? { data: d } : { error: d || { message: String(r.status) } }; }); });
  }
  function canAsk() { return Boolean((API && API.client && API.client.rpc) || (!API && !window.ADSPACE_DEMO && (window.ADSPACE_CONFIG || {}).supabaseUrl && window.fetch)); }
  /* A quotation link already sent keeps opening while the quotation
     website is only paused: the builder alone is covered. */
  /* Every page's state as last read (`page_states`, the minute's
     `page_pulse`), kept for the console, which warns beside a link it hands
     out while that link's page is set (SWITCHED-OFF ACTS, 2026-11-21). */
  var allPages = null;
  function keep(all) {
    var was = JSON.stringify(allPages), now = JSON.stringify(all || {});
    allPages = all || {};
    if (was !== now) { try { document.dispatchEvent(new CustomEvent('adspace-pages')); } catch (e) { /* an old browser */ } }
  }
  function mine(all) {
    keep(all);
    var d = all && PAGE ? all[PAGE] : null;
    if (!d || !(d.on || d.set)) return off;
    if (PAGE === 'quote' && d.kind === 'paused' && /[?&]q=/.test(location.search)) return off;
    return d;
  }
  var DAY = 864e5;
  var EVERY = 60000;

  function zh() { return String(document.documentElement.lang || '').indexOf('zh') === 0; }

  /* A moment in Malaysia's time, written as every client page and the
     console write it (js/clock.js): 2 Nov 2026, 10:00am; 2026年11月2日 上午10:00
     (2026-10-31, G-4: the paused cover read 10:00 am beside /quote/'s 6:31pm). */
  function when(iso) {
    var d = new Date(iso), C = window.ADspaceClock;
    if (isNaN(d)) return '';
    if (C && C.date && C.clock) {
      return zh() ? C.date(d, { zh: true }) + ' ' + C.clock(d, { zh: true }) : C.date(d) + ', ' + C.clock(d);
    }
    try {
      if (zh()) {
        return d.toLocaleString('zh-CN', { timeZone: 'Asia/Kuala_Lumpur', year: 'numeric', month: 'long',
          day: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false });
      }
      return d.toLocaleString('en-GB', { timeZone: 'Asia/Kuala_Lumpur', day: 'numeric', month: 'short',
        year: 'numeric', hour: 'numeric', minute: '2-digit', hour12: true })
        .replace(/\bSep\b/, 'Sept').replace(/\s?([ap])\.?m\.?$/i, function (m, x) { return x.toLowerCase() + 'm'; });
    } catch (e) { return d.toISOString(); }
  }

  /* A moment the reader waits on (the page back by, a window starting):
     its weekday after the date, 20 Nov 2026 (Friday), 12:30pm;
     2026年11月20日（星期五）下午12:30 (2026-11-20, the user). */
  function due(iso) {
    var C = window.ADspaceClock;
    if (!iso || isNaN(new Date(iso))) return '';
    return C && C.due ? C.due(iso, { zh: zh() }) : when(iso);
  }

  function esc(s) { return window.ADspaceWords.esc(s); }

  var shown = null;
  function paint() {
    var box = document.getElementById('maintCover');
    if (!box || !shown) return;
    var W = window.ADspaceWords || {};
    var set = (zh() ? W.zh : W.en) || {};
    var paused = shown.kind === 'paused';
    /* With an end set, the time is the one line: "shortly" beside a time
       hours away said the same thing twice and the two disagreed (the
       user's sweep, 2026-11-12). */
    /* The lead words, then the date and time on a line of their own. */
    var back = shown.ends_at ? (set.maintBack || 'The portal will be available again by\n{when}.').split('\n').map(function (line) {
      return esc(line.replace('{when}', due(shown.ends_at)));
    }).join('<br>') : '';
    var note = zh() && shown.note_zh ? shown.note_zh : shown.note;
    /* Chat on WhatsApp carries the chat mark, as on /quote/ (2026-10-31). */
    var CHAT_MARK = '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 12a8 8 0 0 1-11.8 7L4 20l1.1-4A8 8 0 1 1 20 12z"/></svg>';
    var chat = paused && shown.whatsapp ? (window.ADSPACE_CONFIG && window.ADSPACE_CONFIG.quoteWhatsApp) || 'https://wa.me/adspace' : '';
    /* The console's cover is the whole screen, its bar under it: the
       wordmark leads it, as every page's bar would (2026-11-20). */
    var logo = shown.out && window.ADSPACE_CONFIG && window.ADSPACE_CONFIG.brandLogo;
    var panel = box.querySelector('.cover-panel');
    panel.setAttribute('data-glyph', paused ? 'pause' : 'tool');
    panel.innerHTML =
      (shown.out ? (logo ? '<img class="cover-mark" src="' + esc(logo) + '" alt="ADspace">' : '<b class="cover-mark">ADspace</b>') : '') +
      '<h2 id="maintTitle">' + esc(paused ? set.pausedTitle || 'Temporarily unavailable' : set.maintTitle || 'Upgrade in progress') + '</h2>' +
      (back ? '<p class="maint-back">' + back + '</p>'
        : '<p>' + esc(paused ? set.pausedText || 'Please check again later.' : set.maintText || 'The portal will be available again shortly.') + '</p>') +
      (note ? '<p class="maint-note">' + esc(note) + '</p>' : '') +
      (chat || shown.out ? '<div class="cover-acts">' +
        (shown.out ? '<button class="btn maint-out" type="button" id="maintOut">Sign out</button>' : '') +
        (chat ? '<a class="btn btn-primary maint-chat" href="' + esc(chat) + '" target="_blank" rel="noopener">' + CHAT_MARK + esc(set.pausedChat || 'Chat on WhatsApp') + '</a>' : '') +
        '</div>' : '');
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

  var legacy = false;
  function askWhole(failed) {
    return rpc('maintenance_state').then(function (r) {
      if (!r || r.error) return failed;
      var d = r.data;
      return d && (d.on || d.set) ? d : off;
    }).catch(function () { return failed; });
  }
  function ask(strict) {
    var failed = strict ? null : off;
    if (!canAsk()) return Promise.resolve(failed);
    if (legacy || !PAGE) return askWhole(failed);
    return rpc('page_states').then(function (r) {
      if (r && r.error && /PGRST202|page_states|schema cache/i.test(String(r.error.code || '') + ' ' + String(r.error.message || ''))) {
        legacy = true; return askWhole(failed);
      }
      if (!r || r.error) return failed;
      return mine(r.data || {});
    }).catch(function () { return failed; });
  }

  function norm(d) { return d && (d.on || d.set) ? d : off; }

  /* Every minute while on screen, and on every return to it, one request
     answers every check the page keeps (`page_pulse`: upgrade mode, the
     announcements, the bell), each answer handed to the part that joined
     for it (2026-10-09: an open console made four requests a minute, each a
     line Supabase logs and meters). `often(key, take, alone, opts)`: `take`
     is handed the part's answer; `alone` asks by itself, which every part
     does while the database holds no `page_pulse`. `opts.audience` names
     the announcements a page shows, `opts.bell` asks for the bell,
     `opts.each` runs every minute beside the request. A read that fails
     changes nothing. */
  var parts = [], pulse = { audience: null, bell: false }, alone = false, ticking = false;
  function tick() {
    if (document.visibilityState !== 'visible' || !parts.length) return;
    /* A part's own work of the minute that asks no database (the console's
       /version.json, 2026-11-17), run whatever the request answers. */
    parts.forEach(function (p) { if (p.each) { try { p.each(); } catch (e) {} } });
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
        if (p.key === 'maintenance') { p.take(d.pages && PAGE && !legacy ? mine(d.pages) : norm(d.maintenance)); return; }
        if (Object.prototype.hasOwnProperty.call(d, p.key)) p.take(d[p.key]);
      });
    }).catch(function () {});
  }
  function often(key, take, ask1, opts) {
    parts.push({ key: key, take: take || function () {}, alone: ask1 || function () {}, each: opts && opts.each });
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


  /* A cover's reference (2026-11-20, as RIMOWA's notice carries one): where
     this browser holds a sign-in, every full-page notice ends Reference
     {code}, the sign-in's code as a colleague's Devices block shows it, so
     an admin can match a report to its device. Signed out, no line at all.
     One watcher for every cover the page draws, the console's and the
     client portal's alike (`ADspaceAPI.sessionCode`, no network). */
  /* A notice's mark (the cover family, 2026-11-22): a cover or a lock names
     its state's glyph (`data-glyph`), and this one watcher draws it first,
     in the locks' own disc (`.lockcard-mark`, js/icons.js), so no page
     draws its own. */
  /* A page that holds no icon set fetches it the first time a notice wants
     a glyph, never on load (the namecard and /quote/ hold their weight
     budgets). Its stamp is the icon set's own, bumped with it. */
  var ICONS = '/js/icons.js?v=20261125vg', iconsAsked = false;
  function marks() {
    var I = window.ADspaceIcons, W = window.ADspaceWords;
    var want = [].filter.call(document.querySelectorAll('[data-glyph], .cover .cover-panel'), function (x) {
      return x.getClientRects().length;
    }).map(function (x) {
      var g = x.getAttribute('data-glyph');
      if (g === null) { var h = x.querySelector(':scope > h1, :scope > h2'); g = h && W && W.glyphOf ? W.glyphOf(h.textContent) : ''; }
      var has = x.querySelector(':scope > .lockcard-mark');
      return { x: x, g: g, has: has };
    }).filter(function (o) { return !(o.has && o.has.getAttribute('data-mark') === o.g) && !(!o.has && !o.g); });
    if (!want.length) return;
    if (!I) {
      if (iconsAsked) return;
      iconsAsked = true;
      var tag = document.createElement('script');
      tag.src = ICONS;
      tag.onload = refSoon;
      document.head.appendChild(tag);
      return;
    }
    want.forEach(function (o) {
      if (o.has) o.has.remove();
      if (!o.g || !I.svg(o.g)) return;
      /* After the wordmark where a notice leads with it (no bar above). */
      var lead = o.x.querySelector(':scope > .cover-mark');
      (lead || o.x).insertAdjacentHTML(lead ? 'afterend' : 'afterbegin',
        '<span class="lockcard-mark" data-mark="' + o.g + '" aria-hidden="true">' + I.svg(o.g) + '</span>');
    });
  }
  /* Only where a colleague or a client signs in (the console, the client
     portal): a public page (/verify/, /quote/, a link's page) never draws
     a sign-in it does not use, which read as a second reference beside
     /verify/'s own field (the user, 2026-11-23: "what is the eaeb08"). */
  var REF_PAGE = /^\/(admin|client)\//.test(location.pathname);
  var refBusy = false;
  function refs() {
    marks();
    if (refBusy) return;
    if (!REF_PAGE) { [].forEach.call(document.querySelectorAll('.cover-ref'), function (x) { x.remove(); }); return; }
    var panels = [].filter.call(document.querySelectorAll('.cover .cover-panel'), function (x) { return x.getClientRects().length; });
    var stale = [].filter.call(document.querySelectorAll('.cover-ref'), function (x) { return panels.indexOf(x.parentNode) < 0 || x !== x.parentNode.lastElementChild; });
    stale.forEach(function (x) { x.remove(); });
    var need = panels.filter(function (x) { return !x.querySelector(':scope > .cover-ref'); });
    if (!need.length || !API || !API.sessionCode) return;
    refBusy = true;
    API.sessionCode().then(function (code) {
      refBusy = false;
      if (!code) return;
      var W = window.ADspaceWords || {};
      var set = (zh() ? W.zh : W.en) || {};
      need.forEach(function (x) {
        if (x.querySelector(':scope > .cover-ref')) return;
        var line = document.createElement('p');
        line.className = 'cover-ref';
        line.textContent = (set.coverRef || 'Reference') + ' ' + code;
        x.appendChild(line);
      });
    }, function () { refBusy = false; });
  }
  var refTick = 0;
  function refSoon() { if (!refTick) refTick = requestAnimationFrame(function () { refTick = 0; refs(); }); }
  function refWatch() {
    if (!window.MutationObserver || !document.body) return;
    new MutationObserver(refSoon).observe(document.body, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ['hidden', 'data-glyph'] });
    new MutationObserver(function () { [].forEach.call(document.querySelectorAll('.cover-ref'), function (x) { x.remove(); }); refSoon(); })
      .observe(document.documentElement, { attributes: true, attributeFilter: ['lang'] });
    refSoon();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', refWatch, { once: true });
  else refWatch();

  window.ADspaceMaintenance = { ready: ready, ask: ask, cover: cover, when: when, due: due, watch: watch, often: often, page: PAGE,
    pages: function () { return allPages; } };
})();
