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
     signing out does too. */
(function () {
  'use strict';
  var KEY = 'adspace-demo';
  var on = window.ADSPACE_DEMO;
  function leave() {
    try { localStorage.removeItem(KEY); localStorage.removeItem('adspace-logo-ratio'); } catch (e) {}
  }
  window.ADspaceDemo = {
    on: Boolean(on),
    /* Kept for twelve hours from the sign-in. */
    enter: function () {
      try { localStorage.setItem(KEY, JSON.stringify({ until: Date.now() + 12 * 36e5 })); localStorage.removeItem('adspace-logo-ratio'); } catch (e) { return false; }
      return true;
    },
    leave: function () { leave(); location.replace('/admin/'); }
  };
  if (!on) return;

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
  org.regno = '202001000001';
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
    if (c.functions) c.functions.invoke = function () { return Promise.resolve({ data: null, error: { message: SAID, code: 'demo' } }); };
    if (c.storage && c.storage.from) {
      var sf = c.storage.from;
      c.storage.from = function (b) {
        var s = sf.call(c.storage, b);
        ['upload', 'remove', 'move', 'update'].forEach(function (m) { if (s[m]) s[m] = function () { return Promise.resolve(refused()); }; });
        return s;
      };
    }
    var out = c.auth && c.auth.signOut;
    if (out) c.auth.signOut = function () { leave(); return out.apply(c.auth, arguments).then(function (r) { location.replace('/admin/'); return r; }); };
    return c;
  }
  var lib = window.supabase;
  if (!lib || !lib.createClient || !window.__demoSeed) { leave(); return; }
  var made = lib.createClient;
  lib.createClient = function () { return guard(made.apply(lib, arguments)); };
  /* The engine's own client for its test hooks writes through the same door. */
  if (window.__db) guard(window.__db);
  /* Every guide already met: the demo opens on the screens, not on tours. */
  if (window.__signIn) window.__signIn('alex@example.com');

  function words() {
    document.title = NAME + ' · Demo';
    var foot = document.querySelector('.portalfoot-copy');
    if (foot) foot.textContent = '© ' + new Date().getFullYear() + ' ' + NAME + '. Sample data for demonstration.';
    var link = document.querySelector('.portalfoot-link');
    if (link) link.hidden = true;
    Array.prototype.forEach.call(document.querySelectorAll('#agencyLogo, .brand-logo'), function (i) { i.alt = NAME; });
  }
  function bar() {
    if (document.getElementById('demoBar')) return;
    var b = document.createElement('div');
    b.className = 'upgradebar demobar';
    b.id = 'demoBar';
    b.setAttribute('role', 'status');
    b.innerHTML = '<span class="upgradebar-text"><b>Demo</b> · Sample data. Changes are not saved.</span>' +
      '<button class="btn btn-sm" type="button" id="demoExit">Exit demo</button>';
    /* Where the upgrade line stands, above it. */
    var up = document.getElementById('upgradeBar');
    if (!up) return;
    up.parentNode.insertBefore(b, up);
    document.getElementById('demoExit').addEventListener('click', function () { window.ADspaceDemo.leave(); });
  }
  function ready() { words(); bar(); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ready); else ready();
  /* The console draws its shell once me() answers; the bar follows it. */
  var tries = 0;
  var t = setInterval(function () { tries++; bar(); words(); if (tries > 20) clearInterval(t); }, 500);
})();
