/* ADspaceDemo — the console on sample data (2026-10-27).
   The user, 2026-10-27: a PIN typed in the sign-in's email box opens the
   portal "only show all fake populated data unable to add anything … so i
   can sell ppl this portal", under a neutral agency's name.

   The sign-in asks the database (`demo_pin_ok`, Settings: Demo access) and
   keeps `adspace-demo` in this browser for twelve hours; the page's head
   then loads demo/seed.js and demo/engine.js in place of the database, so
   nothing here reaches it again. This file, loaded after js/config.js and
   before js/api.js, does nothing unless that flag stands. Then it:
   - names a made-up agency in place of ours (the mark, the letterhead, the
     foot, the title);
   - signs in as the sample agency's director, who holds every section;
   - refuses every write (a table's insert, update or delete, a function
     that changes something, an edge function, an upload) with one line,
     Demo: changes are not saved.;
   - draws a bar under the head, Demo · Sample data, with Exit demo, which
     signing out does too.
   The client pages (the client portal, Content Review, the creator
   selection, the creator's page, Video Scripts, a namecard) load it the same
   way, so a link the demo console hands out opens on the same sample data:
   the client portal signed in as a sample client's main contact, the rest on
   their link as a client or a creator meets it. Signing out of the client
   portal returns to the console, still in the demo.
   The audit of 2026-10-27: a demo whose sample data did not load never
   falls back on the real database (the page reads Unable to load); Sign
   out in the demo ends it as Exit demo does, never clearing the
   colleague's own notes and drafts; a sheet's draft kept in the demo is
   let go when it starts and ends; and a client page loads the demo for its
   own links alone, every demo key holding a 0 that no real key's alphabet
   does (the loader in each page's head). */
(function () {
  'use strict';
  var KEY = 'adspace-demo';
  var on = window.ADSPACE_DEMO;
  var CONSOLE = /^\/admin\//.test(location.pathname);
  /* A phone keeps a sheet's draft in the tab (js/sheet.js): none crosses
     between the demo and the real console. */
  function dropDrafts() {
    try {
      Object.keys(sessionStorage).forEach(function (k) { if (k.indexOf('adspace-draft:') === 0) sessionStorage.removeItem(k); });
    } catch (e) { /* storage refused */ }
  }
  function leave() {
    try {
      localStorage.removeItem(KEY); localStorage.removeItem('adspace-logo-ratio');
      /* A sample creator's code kept by the creator's page goes with it. */
      if (/^DEMO0/.test(localStorage.getItem('adspace-creator') || '')) localStorage.removeItem('adspace-creator');
      /* The client pages' guides the demo marked met are offered again. */
      JSON.parse(localStorage.getItem('adspace-demo-guides') || '[]').forEach(function (k) { localStorage.removeItem('adspace-guide:' + k); });
      localStorage.removeItem('adspace-demo-guides');
    } catch (e) {}
    dropDrafts();
  }
  window.ADspaceDemo = {
    on: Boolean(on),
    /* Kept for twelve hours from the sign-in. */
    enter: function () {
      try { localStorage.setItem(KEY, JSON.stringify({ until: Date.now() + 12 * 36e5 })); localStorage.removeItem('adspace-logo-ratio'); } catch (e) { return false; }
      dropDrafts();
      return true;
    },
    leave: function () { leave(); location.replace('/admin/'); }
  };
  if (!on) {
    /* A demo past its twelve hours ends here, its drafts with it. */
    try {
      var was = JSON.parse(localStorage.getItem(KEY) || 'null');
      if (was && !(was.until > Date.now())) leave();
    } catch (e) { /* storage refused */ }
    return;
  }

  var NAME = 'Sample Studio';
  var SAID = 'Demo: changes are not saved.';

  /* The mark: the name set on a canvas, a PNG the letterhead can embed. */
  function mark() {
    try {
      var c = document.createElement('canvas'), x = c.getContext('2d');
      x.font = '600 64px Georgia, "Times New Roman", serif';
      var w = Math.ceil(x.measureText(NAME).width) + 8;
      c.width = w; c.height = 84;
      x.font = '600 64px Georgia, "Times New Roman", serif';
      x.fillStyle = '#1b1a17'; x.textBaseline = 'middle';
      x.fillText(NAME, 4, 44);
      return c.toDataURL('image/png');
    } catch (e) { return ''; }
  }
  var cfg = window.ADSPACE_CONFIG || {};
  cfg.brandLogo = mark();
  cfg.agencyName = NAME;
  cfg.supportEmail = 'hello@example.com';
  cfg.accountEmail = 'hello@example.com';
  cfg.googleApiKey = '';
  cfg.turnstileSiteKey = '';
  var org = window.ADSPACE_ORG || {};
  org.name = 'SAMPLE STUDIO SDN BHD';
  /* A number no company can hold (review 2026-10-29, 9). */
  org.regno = '000000000001';
  org.sst = '';
  org.address = '1 Jalan Contoh\n81100 Johor Bahru\nJohor, Malaysia';
  org.email = 'hello@example.com';
  org.phone = '60123456789';
  org.website = 'example.com';
  org.map = '';
  org.logo = '';
  org.fontMark = '';
  org.verifyUrl = '';

  /* Writes are refused; reads are answered. A function is a write when a
     word of its name is a verb that changes something. */
  var VERB = ('set save create delete add update remove archive assign change clear decide duplicate edit generate hand over link ' +
    'mark rate request take transition withdraw log notify acknowledge void reset dispute finalise lock unlock confirm reopen release ' +
    'unrelease publish unpublish submit return revise restore move sent keep send proceed replace offer share reissue issue claim done ' +
    'begin tokens searches step used close upsert subscribe unsubscribe consent ask end expire hide revert draft shot new kick queue make profile').split(' ');
  var WRITES = { campaign_qc_pass: 1, ops_engagement_set_check: 1, override_service_state: 1, review_caption_undo: 1, sm_report_brand: 1,
    client_brand_logo: 1, verify_letter: 1, ops_recurring_daily: 1, my_hr_remind: 1 };
  var READS = { review_set_counts: 1, rate_card_current: 1, ai_draft_usage: 1, wa_compose_prepare: 1, supplier_email_prepare: 1, bukku_prepare: 1, wa_sent_recently: 1, guide_seen_mark: 1 };
  function writes(name) {
    if (WRITES[name]) return true;
    if (READS[name] || /^(get_|me$)/.test(name) || /(_list|_read|_state|_left|_last|_mine|_check|_ok|_word|_of|_get|_counts)$/.test(name)) return false;
    return name.split('_').some(function (w) { return VERB.indexOf(w) > -1; });
  }
  function refused() { return { data: null, error: { message: SAID, code: 'demo' }, status: 403, count: null }; }
  /* A refusal shaped as the builder's answer: chainable, then a promise. */
  function refusal() {
    var q = {};
    ['select', 'eq', 'neq', 'in', 'is', 'gt', 'gte', 'lt', 'lte', 'like', 'ilike', 'or', 'match', 'order', 'limit', 'range', 'single', 'maybeSingle', 'not', 'filter', 'contains']
      .forEach(function (m) { q[m] = function () { return q; }; });
    q.then = function (a, b) { return Promise.resolve(refused()).then(a, b); };
    q.catch = function (b) { return Promise.resolve(refused()).catch(b); };
    return q;
  }
  function guard(c) {
    var from = c.from, rpc = c.rpc;
    c.from = function (t) {
      var b = from.call(c, t);
      ['insert', 'update', 'upsert', 'delete'].forEach(function (m) { if (b[m]) b[m] = function () { return refusal(); }; });
      return b;
    };
    c.rpc = function (name, args) {
      if (!writes(name)) return rpc.call(c, name, args);
      (window.__demoRefused = window.__demoRefused || []).push(name);
      return refusal();
    };
    /* An edge function is refused, but for Bukku's invoices read, which the
       engine answers with no request sent: the sample agency holds none, so
       the Dashboard and a client's Billing read as they do for a client
       with nothing owing (2026-10-29, the gate). */
    if (c.functions) {
      var fi = c.functions.invoke;
      c.functions.invoke = function (name, opts) {
        if (name === 'bukku-sync' && opts && opts.body && opts.body.action === 'invoices') {
          if (!window.__bukkuInvoices) window.__bukkuInvoices = [];
          return fi.call(c.functions, name, opts);
        }
        return Promise.resolve({ data: null, error: { message: SAID, code: 'demo' } });
      };
    }
    if (c.storage && c.storage.from) {
      var sf = c.storage.from;
      c.storage.from = function (b) {
        var s = sf.call(c.storage, b);
        ['upload', 'remove', 'move', 'update'].forEach(function (m) { if (s[m]) s[m] = function () { return Promise.resolve(refused()); }; });
        return s;
      };
    }
    var out = c.auth && c.auth.signOut;
    if (out) c.auth.signOut = function () {
      if (CONSOLE) leave();
      /* A client page reloads itself once signed out, which would sign the
         sample contact in again: back to the console instead, nothing after. */
      return out.apply(c.auth, arguments).then(function (r) { location.replace('/admin/'); return CONSOLE ? r : new Promise(function () {}); });
    };
    return c;
  }
  var UNBOOKED = ['option', 'shortlisted', 'backup', 'withdrawn', 'replaced'];
  /* The client pages on the sample data, each on its own sample link, for
     the console's Client pages menu: nobody needs to know an address, and
     a public page opens the demo only in a browser that entered its PIN
     (the user, 2026-10-27). */
  function samples() {
    var D = window.__DB || {}, first = function (list, ok) { return (list || []).filter(ok)[0]; };
    var rv = first(D.clients, function (c) { return c.stage === 'active' && !c.review_hidden && c.access_token; });
    var cm = first(D.campaigns, function (c) { return c.state === 'open' && c.access_token; }) || first(D.campaigns, function (c) { return c.state !== 'draft' && c.access_token; });
    var booked = {}; (D.campaign_options || []).forEach(function (o) { if (UNBOOKED.indexOf(o.state) < 0) booked[o.creator_id] = 1; });
    var cr = first(D.creators, function (c) { return c.active !== false && booked[c.id] && c.access_code; });
    var shared = {}; (D.video_scripts || []).forEach(function (v) { if (v.status === 'shared') shared[v.client_id] = 1; });
    var vs = first(D.clients, function (c) { return shared[c.id] && c.script_key; });
    var me = first(D.team_members, function (m) { return m.email === 'alex@example.com' && m.card_key; });
    return [['Client portal', '/client/'],
      rv && ['Content Review', '/review/?k=' + rv.access_token],
      cm && ['Creator selection', '/creators/?k=' + cm.access_token],
      cr && ['Creator page', '/creator/?k=' + cr.access_code],
      vs && ['Video Scripts', '/script/?k=' + vs.script_key],
      me && ['Namecard', '/card/?k=' + me.card_key]].filter(Boolean);
  }
  var lib = window.supabase;
  /* The engine sets its own library in place of the real one and then
     __signIn, so a page holding __signIn holds the sample database. Without
     it (a file that did not arrive, or stopped part way) the real library
     is taken away: js/api.js finds none and the page reads Unable to load
     under the demo's bar, never the real database (audit, 2026-10-27). A
     refresh tries again; Exit demo ends it. */
  if (!lib || !lib.createClient || !window.__demoSeed || !window.__signIn || !window.__DB) {
    window.supabase = undefined;
    /* The console reads this to say Unable to load with Exit demo on its
       signed-out page, where the bar cannot stand (review 2026-10-29, 8). */
    window.ADspaceDemo.failed = true;
  } else {
    var made = lib.createClient;
    lib.createClient = function () { return guard(made.apply(lib, arguments)); };
    /* The engine's own client for its test hooks writes through the same door. */
    if (window.__db) guard(window.__db);
    /* Every guide already met: the demo opens on the screens, not on tours. */
    if (CONSOLE) window.__signIn('alex@example.com');
    if (/^\/client\//.test(location.pathname)) window.__signIn('client@example.com');
    /* The creator's page opened bare (no link, no code kept) opens on a
       sample creator holding a booking, as the client portal opens signed
       in; it had asked for an access code the real database answered. */
    if (/^\/creator\//.test(location.pathname) && !/[?&]k=/.test(location.search)) {
      var kept = ''; try { kept = localStorage.getItem('adspace-creator') || ''; } catch (e) {}
      if (!kept) {
        var booked = {}; (window.__DB.campaign_options || []).forEach(function (o) { if (o.creator_id && UNBOOKED.indexOf(o.state) < 0) booked[o.creator_id] = 1; });
        var who = (window.__DB.creators || []).filter(function (c) { return c.active !== false && booked[c.id] && c.access_code; })[0];
        if (who) history.replaceState(history.state, '', location.pathname + '?k=' + encodeURIComponent(who.access_code) + location.hash);
      }
    }
  }
  /* Sign out in the demo ends it as Exit demo does: the console's own Sign
     out would clear this browser's notes, drafts and notification setting,
     which are the colleague's (audit, 2026-10-27). The client portal's Sign
     out returns to the console, still in the demo. */
  /* The sample people's numbers and profiles are made up, but a number or
     a handle may be somebody's: a chat, a call or a profile is never opened
     from the demo (review 2026-10-29, 9). */
  var PERSON = /^(tel:|sms:|https?:\/\/(wa\.me|api\.whatsapp\.com|(www\.)?(instagram|facebook|tiktok|xiaohongshu)\.com)\b)/i;
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest && e.target.closest('a[href]');
    if (!a || !PERSON.test(a.getAttribute('href') || '')) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    var line = document.querySelector('#demoBar .upgradebar-text, #demoBar .annbar-text');
    if (line && !line.getAttribute('data-was')) {
      line.setAttribute('data-was', line.innerHTML);
      line.innerHTML = '<b>Demo</b> · Chats, calls and profiles are not opened.';
      setTimeout(function () { line.innerHTML = line.getAttribute('data-was'); line.removeAttribute('data-was'); }, 4000);
    }
  }, true);
  document.addEventListener('click', function (e) {
    var t = e.target && e.target.closest && e.target.closest('#signOut, #portalOut');
    if (!t) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    if (t.id === 'signOut') window.ADspaceDemo.leave();
    else location.replace('/admin/');
  }, true);

  function words() {
    if (CONSOLE) document.title = NAME + ' · Demo';
    else if (/ADspace/.test(document.title)) document.title = document.title.replace(/ADspace/g, NAME);
    var foot = document.querySelector('.portalfoot-copy');
    if (foot) foot.textContent = '© ' + new Date().getFullYear() + ' ' + NAME + '. Sample data for demonstration.';
    var link = document.querySelector('.portalfoot-link');
    if (link) link.hidden = true;
    Array.prototype.forEach.call(document.querySelectorAll('#agencyLogo, .brand-logo'), function (i) { i.alt = NAME; });
  }
  function bar() {
    if (document.getElementById('demoBar')) return;
    var b = document.createElement('div');
    b.id = 'demoBar';
    b.setAttribute('role', 'status');
    var exit = '<button class="btn btn-sm" type="button" id="demoExit">Exit demo</button>';
    var line = '<b>Demo</b> · Sample data. Changes are not saved.';
    if (CONSOLE) {
      /* Where the upgrade line stands, above it. */
      var up = document.getElementById('upgradeBar');
      if (!up) return;
      b.className = 'upgradebar demobar';
      var pages = samples();
      b.innerHTML = '<span class="upgradebar-text">' + line + '</span>' +
        '<button class="btn btn-sm" type="button" id="demoPages" aria-haspopup="menu" aria-expanded="false">Client pages</button>' + exit;
      up.parentNode.insertBefore(b, up);
      var menu = document.createElement('div');
      menu.className = 'kmenu'; menu.id = 'demoPagesMenu'; menu.setAttribute('role', 'menu'); menu.hidden = true;
      menu.innerHTML = window.ADspaceMenu ? window.ADspaceMenu.items([pages.map(function (x) { return { label: x[0], attrs: 'data-href="' + x[1] + '"' }; })]) : '';
      document.body.appendChild(menu);
      var btn = document.getElementById('demoPages');
      var shut = function () { menu.hidden = true; btn.setAttribute('aria-expanded', 'false'); };
      btn.addEventListener('click', function (e) {
        e.stopPropagation();
        if (!menu.hidden) { shut(); return; }
        menu.hidden = false; btn.setAttribute('aria-expanded', 'true');
        if (window.ADspaceMenu) { window.ADspaceMenu.tidy(menu); window.ADspaceMenu.place(btn, menu); }
        var f = menu.querySelector('.kmenu-item'); if (f) f.focus();
      });
      /* Each opens in a tab of its own, the console kept where it was. */
      menu.addEventListener('click', function (e) {
        var it = e.target.closest('[data-href]');
        if (!it) return;
        shut(); window.open(it.getAttribute('data-href'), '_blank');
      });
      document.addEventListener('click', function (e) { if (!menu.hidden && !menu.contains(e.target)) shut(); });
      document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && !menu.hidden) { shut(); btn.focus(); } });
    } else {
      /* A client page: edge to edge under its bar, as an announcement. */
      var top = document.querySelector('.topbar');
      if (!top) return;
      b.className = 'annbar demobar';
      b.innerHTML = '<p class="annbar-text">' + line + '</p><span class="annbar-acts">' + exit + '</span>';
      top.parentNode.insertBefore(b, top.nextSibling);
    }
    document.getElementById('demoExit').addEventListener('click', function () { window.ADspaceDemo.leave(); });
  }
  function ready() { words(); bar(); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ready); else ready();
  /* The console draws its shell once me() answers; the bar follows it. */
  var tries = 0;
  var t = setInterval(function () { tries++; bar(); words(); if (tries > 20) clearInterval(t); }, 500);
})();
