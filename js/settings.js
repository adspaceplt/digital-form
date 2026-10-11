/* ADspaceSettings — the console's Settings page (`?s=settings`, 2026-10-10).
   The user, 2026-10-09: the account menu grew long with the portal's
   switches, and AI usage hid under Reports while it covers every section.
   One page at the rail's foot, above the Activity record, holds what changes
   the portal for everybody: upgrade mode, announcements and notices; the
   business figures; Meta checks; WhatsApp's templates; AI usage and limits; document types and
   task numbering. Each row is drawn only for a colleague holding its granted
   part, and each opens the one sheet that already edits it (one copy of
   every mechanism). The account menu keeps what is the person's own. */
(function () {
  'use strict';
  var bridge = window.ADspaceAdmin;
  if (!bridge) return;
  var db = window.ADspaceAPI.client;
  function $(id) { return document.getElementById(id); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  var PEN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 20h4L19 9l-4-4L4 16z"/><path d="m13.5 6.5 4 4"/></svg>';
  var CHEV = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 18 6-6-6-6"/></svg>';
  /* Every part a row of this page answers to. The route is offered to a
     colleague holding any of them (`ADspaceSettings.allowed`). */
  var KEYS = ['team.upgrade', 'team.announce', 'team.notice', 'team.settings', 'reports.ai', 'register.types', 'ops.numbering'];
  function may(k) { return Boolean(bridge.may && bridge.may(k, 'work')); }
  function allowed() { return KEYS.some(may); }
  function say(text, tone) {
    var m = $('settingsMsg');
    if (!m) return;
    m.textContent = text || '';
    m.className = 'msg' + (tone ? ' ' + tone : '');
  }
  function num(k) { var M = window.ADspaceMoney; return M && M.setting ? M.setting(k) : null; }
  function plural(n, one, many) { return n + ' ' + (n === 1 ? one : many); }
  function pct(n) { return (n > 0 ? '+' : n < 0 ? '\u2212' : '') + Math.abs(n) + '%'; }
  /* A line of parts wraps between its parts, never inside one. */
  function parts(list) { return list.map(function (x) { return String(x).replace(/ /g, '\u00a0'); }).join(' · '); }
  var MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
  function when(iso) {
    if (!iso) return '';
    var d = new Date(new Date(iso).getTime() + 8 * 3600000);
    var h = d.getUTCHours(), mi = d.getUTCMinutes();
    return d.getUTCDate() + ' ' + MON[d.getUTCMonth()] + ' ' + d.getUTCFullYear() + ', ' +
      ((h % 12) || 12) + ':' + (mi < 10 ? '0' : '') + mi + (h < 12 ? ' am' : ' pm');
  }

  /* The rows, group by group (regrouped 2026-10-11, the queue's task 46:
     "Vertical list at a desk, drill-down on a phone (iPhone/Mac Settings
     style)"). A group is named for what its rows change; `kind` is the
     control at the row's right edge: a switch (saved at the press), Edit (a
     sheet of figures) or Open (a list in a sheet). `meta` says the value as
     it stands, where there is one. A group with no row drawn is left out. */
  function groups() {
    var up = bridge.upgradeState ? bridge.upgradeState() : { on: false, set: false };
    var biz = may('team.settings');
    var out = [];
    function add(key, name, rows) { rows = rows.filter(Boolean); if (rows.length) out.push({ key: key, name: name, rows: rows }); }
    add('portal', 'Portal', [
      may('team.upgrade') && { id: 'upgrade', name: 'Upgrade mode', kind: 'switch', on: Boolean(up.set),
        meta: up.on ? 'On' + (up.ends_at ? ' until ' + when(up.ends_at) : '') : up.set ? 'Starts ' + when(up.starts_at) : 'Off' },
      may('team.announce') && { id: 'announce', name: 'Announcements', kind: 'open' },
      may('team.notice') && { id: 'notice', name: 'Notices', kind: 'open' }]);
    var lead = num('lead_followup_hours'), prop = num('proposal_followup_days');
    add('clients', 'Clients', [
      biz && { id: 'followup', name: 'Follow-up limits', kind: 'edit',
        meta: lead == null ? '' : parts(['Lead ' + plural(lead, 'hour', 'hours'), 'Proposal ' + plural(prop, 'day', 'days')]) }]);
    var rep = num('report_due_days'), rev = num('revision_due_days');
    add('work', 'My Work', [
      biz && { id: 'due', name: 'Due dates', kind: 'edit',
        meta: rep == null ? '' : parts(['Report ' + plural(rep, 'day', 'days') + ' after the month', 'Revision ' + plural(rev, 'day', 'days')]
          .concat(num('approval_reminder_days') == null ? [] : ['Approval reminder ' + plural(num('approval_reminder_days'), 'day', 'days')])) },
      may('ops.numbering') && { id: 'numbering', name: 'Task numbering', kind: 'edit' }]);
    var meta = num('meta_checks') === 1;
    add('reports', 'Reports', [
      biz && { id: 'meta', name: 'Meta checks', kind: 'switch', on: meta,
        meta: meta ? 'Import from Meta and the Report audit are on' : 'Import from Meta and the Report audit are off' },
      biz && { id: 'reach', name: 'Reach allowance', kind: 'edit',
        meta: num('reach_allowance_pct') == null ? '' : 'The Report audit accepts Reach within ' + num('reach_allowance_pct') + '% of Meta' }]);
    var pin = num('ai_price_in'), pout = num('ai_price_out');
    add('money', 'Money', [
      biz && { id: 'tax', name: 'Tax and terms', kind: 'edit',
        meta: num('sst_pct') == null ? '' : parts(['SST ' + num('sst_pct') + '%', '1 to 3 months ' + pct(num('term_1_3')), '24 months ' + pct(num('term_24'))]) },
      biz && { id: 'prices', name: 'AI prices', kind: 'edit',
        meta: pin == null ? '' : parts(['US$ ' + pin + ' input', 'US$ ' + pout + ' output']) + ', a million tokens' +
          (num('ai_price_search') == null ? '' : ' · US$ ' + num('ai_price_search') + ' a thousand web searches') }]);
    add('ai', 'AI', [may('reports.ai') && { id: 'aiuse', name: 'AI usage and limits', kind: 'open' }]);
    /* WhatsApp (2026-10-10): its templates are set in the WhatsApp section
       at Full Access; this row opens them there. */
    add('whatsapp', 'WhatsApp', [window.ADspaceWhatsApp && bridge.may && bridge.may('whatsapp', 'manage') &&
      { id: 'whatsapp', name: 'Templates', kind: 'open' }]);
    add('documents', 'Documents', [may('register.types') && { id: 'types', name: 'Document types', kind: 'open' }]);
    return out;
  }

  function rowHtml(r) {
    var ctl = r.kind === 'switch'
      ? '<button class="switch" type="button" role="switch" aria-checked="' + (r.on ? 'true' : 'false') + '" aria-label="' + esc(r.name) + '" data-a="' + r.id + '"></button>'
      : r.kind === 'edit'
        ? '<button class="btn btn-sm" type="button" data-a="' + r.id + '" aria-label="Edit ' + esc(r.name) + '">' + PEN + 'Edit</button>'
        : '<button class="btn btn-sm" type="button" data-a="' + r.id + '" aria-label="Open ' + esc(r.name) + '">Open' + CHEV + '</button>';
    return '<div class="stg-row" data-row="' + r.id + '">' +
      '<div class="stg-what"><p class="stg-name">' + esc(r.name) + '</p>' +
        (r.meta ? '<p class="stg-meta">' + esc(r.meta) + '</p>' : '') + '</div>' +
      '<div class="stg-ctl">' + ctl + '</div></div>';
  }

  /* Where the page stands: the group in the address (`tab=`), else none.
     At a desk none is the first group, left out of the address; on a phone
     (the tab bar's width) none is the list of groups. */
  var phoneMedia = window.matchMedia && window.ADSPACE_TABBAR ? window.matchMedia(window.ADSPACE_TABBAR) : null;
  function phone() { return Boolean(phoneMedia && phoneMedia.matches); }
  var chosen = '';
  var pushed = false;
  function fromUrl() { chosen = new URLSearchParams(location.search).get('tab') || ''; }

  function pane(g, back) {
    return '<section class="stg-pane" aria-labelledby="stgTitle">' +
      (back ? '<button class="backlink" type="button" data-back="1"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M19 12H5"/><path d="m11 6-6 6 6 6"/></svg>Back</button>' : '') +
      '<h3 class="stg-title" id="stgTitle" tabindex="-1">' + esc(g.name) + '</h3>' +
      '<div class="stg-card">' + g.rows.map(rowHtml).join('') + '</div></section>';
  }

  function paint() {
    var box = $('setList');
    if (!box) return;
    var list = groups();
    box.innerHTML = '';
    if (!list.length) { window.ADspaceState.emptyLine(box, 'No settings.'); return; }
    var g = list.filter(function (x) { return x.key === chosen; })[0];
    if (phone()) {
      box.className = 'stg is-phone';
      if (g) { box.innerHTML = pane(g, true); return; }
      box.innerHTML = '<nav class="stg-nav stg-list" aria-label="Settings">' + list.map(function (x) {
        return '<button class="stg-go" type="button" data-g="' + x.key + '"><span class="stg-what"><span class="stg-name">' + esc(x.name) + '</span>' +
          '<span class="stg-meta">' + esc(parts(x.rows.map(function (r) { return r.name; }))) + '</span></span>' + CHEV + '</button>';
      }).join('') + '</nav>';
      return;
    }
    g = g || list[0];
    box.className = 'stg is-desk';
    box.innerHTML = '<nav class="stg-nav" aria-label="Settings">' + list.map(function (x) {
      return '<button class="stg-go" type="button" data-g="' + x.key + '"' + (x === g ? ' aria-current="page"' : '') + '>' + esc(x.name) + '</button>';
    }).join('') + '</nav>' + pane(g, false);
  }

  /* The address names the group unless it is the desk's first. */
  function urlState() {
    var list = groups();
    if (!chosen || !list.some(function (x) { return x.key === chosen; })) return {};
    if (!phone() && list[0].key === chosen) return {};
    return { tab: chosen };
  }

  /* A group opened. At a desk it replaces the address (a note of where you
     are); on a phone it is a screen moved to, so Back and Forward walk it. */
  function go(key) {
    chosen = key;
    say('');
    paint();
    if (phone()) {
      pushed = true;
      if (bridge.pushUrl) bridge.pushUrl();
      window.scrollTo(0, 0);
      var t = $('stgTitle');
      if (t) t.focus({ preventScroll: true });
    } else {
      if (bridge.setUrl) bridge.setUrl();
      var cur = document.querySelector('#setList .stg-go[aria-current]');
      if (cur) cur.focus({ preventScroll: true });
    }
  }
  function back() {
    var was = chosen;
    if (pushed) { history.back(); return; }
    chosen = '';
    say('');
    paint();
    if (bridge.setUrl) bridge.setUrl();
    land(was);
  }
  function land(was) {
    var b = was && document.querySelector('#setList .stg-go[data-g="' + was + '"]');
    if (b) b.focus({ preventScroll: true });
  }
  function shown() { var s = $('sectionSettings'); return s && !s.hidden; }
  window.addEventListener('popstate', function () {
    if (!shown()) return;
    var was = chosen;
    fromUrl();
    pushed = Boolean(chosen);
    say('');
    paint();
    if (!chosen) land(was);
  });
  function follow() { if (shown()) { paint(); if (bridge.setUrl) bridge.setUrl(); } }
  if (phoneMedia) {
    if (phoneMedia.addEventListener) phoneMedia.addEventListener('change', follow);
    else if (phoneMedia.addListener) phoneMedia.addListener(follow);
  }

  /* Meta checks (2026-10-10): one figure, 0 or 1, from today. Saved at the
     press and put back on a refusal; the page's figures are read again so
     Reports follows at once. */
  function flipMeta(sw) {
    var to = sw.getAttribute('aria-checked') !== 'true';
    var day = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Kuala_Lumpur' });
    sw.setAttribute('aria-checked', to ? 'true' : 'false');
    sw.disabled = true;
    db.rpc('app_settings_set', { p_from: day, p_values: { meta_checks: to ? 1 : 0 } }).then(function (r) {
      var d = r.data || {};
      if (r.error || d.error) {
        throw new Error(r.error ? (/function|schema cache/i.test(r.error.message) ? 'This needs a database update.' : r.error.message)
          : d.error === 'denied' ? 'This needs Team: Business settings.' : d.error === 'bad-value' ? 'This needs a database update.' : d.error);
      }
      return window.ADspaceMoney.load(true);
    }).then(function () {
      say(to ? 'Meta checks are on.' : 'Meta checks are off.', 'ok');
      paint();
    }).catch(function (e) {
      sw.setAttribute('aria-checked', to ? 'false' : 'true');
      sw.disabled = false;
      say(String((e && e.message) || e), 'err');
    });
  }

  function press(a, btn) {
    say('');
    var edit = bridge.editSettings;
    var again = { msg: 'settingsMsg', done: paint };
    function ed(spec) { Object.keys(again).forEach(function (k) { spec[k] = again[k]; }); edit(spec, btn); }
    if (a === 'upgrade') { if (bridge.upgradeToggle) bridge.upgradeToggle(btn); return; }
    if (a === 'announce') { if (window.ADspaceAnnounce) window.ADspaceAnnounce.manage(btn); return; }
    if (a === 'notice') { if (window.ADspaceNotice) window.ADspaceNotice.manage(btn); return; }
    if (a === 'followup') {
      ed({ title: 'Follow-up limits', keys: [['lead_followup_hours', 'A lead waits (hours)', 'hours'], ['proposal_followup_days', 'A proposal waits (days)', 'days']] });
      return;
    }
    if (a === 'tax') {
      ed({ title: 'Tax and terms', keys: [['sst_pct', 'SST (%)', 'pct'], ['term_1_3', '1 to 3 months (%)', 'adj'], ['term_4_5', '4 and 5 months (%)', 'adj'],
        ['term_6_11', '6 to 11 months (%)', 'adj'], ['term_12_23', '12 to 23 months (%)', 'adj'], ['term_24', '24 months and more (%)', 'adj']] });
      return;
    }
    if (a === 'due') {
      ed({ title: 'Due dates', keys: [['report_due_days', 'Report: days after the month ends', 'due'],
        ['revision_due_days', 'Revision (Client): days after changes are asked', 'due'],
        ['approval_reminder_days', 'Approval reminder: days a client has not approved', 'due']] });
      return;
    }
    if (a === 'prices') { ed({ title: 'AI prices, US$', keys: [['ai_price_in', 'Input, a million tokens', 'usd'], ['ai_price_out', 'Output, a million tokens', 'usd'],
      ['ai_price_search', 'Web searches, a thousand', 'usd']] }); return; }
    if (a === 'meta') { flipMeta(btn); return; }
    if (a === 'reach') { ed({ title: 'Reach allowance', keys: [['reach_allowance_pct', 'Reach within (%) of Meta', 'allow']] }); return; }
    if (a === 'whatsapp') { if (window.ADspaceWhatsApp) window.ADspaceWhatsApp.manage(btn); return; }
    if (a === 'aiuse') { if (window.ADspaceReports && window.ADspaceReports.aiUsage) window.ADspaceReports.aiUsage(btn); return; }
    if (a === 'types') { if (window.ADspaceRegister && window.ADspaceRegister.openTypes) window.ADspaceRegister.openTypes(btn); return; }
    if (a === 'numbering') { if (window.ADspaceOps && window.ADspaceOps.openNumbering) window.ADspaceOps.openNumbering('settingsMsg'); return; }
  }

  function enter() {
    say('');
    fromUrl();
    pushed = false;
    var M = window.ADspaceMoney;
    paint();
    /* The figures are read once a page; a colleague who changed one in
       another tab sees it here on the way in. */
    if (M && M.load) M.load(true).then(paint).catch(function () {});
    if (bridge.restoreScroll) bridge.restoreScroll();
  }

  var wired = false;
  function wire() {
    if (wired || !$('setList')) return;
    wired = true;
    $('setList').addEventListener('click', function (e) {
      var gb = e.target.closest('[data-g]');
      if (gb && $('setList').contains(gb)) { go(gb.getAttribute('data-g')); return; }
      if (e.target.closest('[data-back]')) { back(); return; }
      var b = e.target.closest('[data-a]');
      if (!b || b.disabled || !$('setList').contains(b)) return;
      press(b.getAttribute('data-a'), b);
    });
  }
  wire();

  window.ADspaceSettings = { enter: function () { wire(); enter(); }, paint: paint, urlState: urlState, allowed: allowed, say: say };
  if (bridge.settingsReady) bridge.settingsReady();
})();
