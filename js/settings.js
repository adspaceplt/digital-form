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
    var m = $('setMsg');
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

  /* The rows, group by group. `kind` is the control at the row's right edge:
     a switch (saved at the press), Edit (a sheet of figures) or Open (a list
     in a sheet). `meta` says the value as it stands, where there is one. */
  function groups() {
    var up = bridge.upgradeState ? bridge.upgradeState() : { on: false, set: false };
    var out = [];
    var portal = [];
    if (may('team.upgrade')) portal.push({ id: 'upgrade', name: 'Upgrade mode', kind: 'switch', on: Boolean(up.set),
      meta: up.on ? 'On' + (up.ends_at ? ' until ' + when(up.ends_at) : '') : up.set ? 'Starts ' + when(up.starts_at) : 'Off' });
    if (may('team.announce')) portal.push({ id: 'announce', name: 'Announcements', kind: 'open' });
    if (may('team.notice')) portal.push({ id: 'notice', name: 'Notices', kind: 'open' });
    if (portal.length) out.push({ key: 'portal', name: 'Portal', rows: portal });
    if (may('team.settings')) {
      var lead = num('lead_followup_hours'), prop = num('proposal_followup_days');
      var rep = num('report_due_days'), rev = num('revision_due_days');
      var pin = num('ai_price_in'), pout = num('ai_price_out');
      var meta = num('meta_checks') === 1;
      out.push({ key: 'business', name: 'Business figures', rows: [
        { id: 'followup', name: 'Follow-up limits', kind: 'edit',
          meta: lead == null ? '' : parts(['Lead ' + plural(lead, 'hour', 'hours'), 'Proposal ' + plural(prop, 'day', 'days')]) },
        { id: 'tax', name: 'Tax and terms', kind: 'edit',
          meta: num('sst_pct') == null ? '' : parts(['SST ' + num('sst_pct') + '%', '1 to 3 months ' + pct(num('term_1_3')), '24 months ' + pct(num('term_24'))]) },
        { id: 'due', name: 'Due dates', kind: 'edit',
          meta: rep == null ? '' : parts(['Report ' + plural(rep, 'day', 'days') + ' after the month', 'Revision ' + plural(rev, 'day', 'days')]) },
        { id: 'prices', name: 'AI prices', kind: 'edit',
          meta: pin == null ? '' : parts(['US$ ' + pin + ' input', 'US$ ' + pout + ' output']) + ', a million tokens' },
        { id: 'meta', name: 'Meta checks', kind: 'switch', on: meta,
          meta: meta ? 'Import from Meta and the Report audit are on' : 'Import from Meta and the Report audit are off' },
        { id: 'reach', name: 'Reach allowance', kind: 'edit',
          meta: num('reach_allowance_pct') == null ? '' : 'The Report audit accepts Reach within ' + num('reach_allowance_pct') + '% of Meta' }
      ] });
    }
    /* WhatsApp (2026-10-10; the user: "Whatsapp business settings not moved
       to settings section"): the templates each message is sent with and the
       last fifty messages, a Business setting. */
    if (may('team.settings') && window.ADspaceWhatsApp) out.push({ key: 'whatsapp', name: 'WhatsApp', rows: [
      { id: 'whatsapp', name: 'Templates and recent messages', kind: 'open' }] });
    if (may('reports.ai')) out.push({ key: 'ai', name: 'AI', rows: [
      { id: 'aiuse', name: 'AI usage and limits', kind: 'open' }] });
    var lists = [];
    if (may('register.types')) lists.push({ id: 'types', name: 'Document types', kind: 'open' });
    if (may('ops.numbering')) lists.push({ id: 'numbering', name: 'Task numbering', kind: 'edit' });
    if (lists.length) out.push({ key: 'records', name: 'Records', rows: lists });
    return out;
  }

  function rowHtml(r) {
    var ctl = r.kind === 'switch'
      ? '<button class="switch" type="button" role="switch" aria-checked="' + (r.on ? 'true' : 'false') + '" aria-label="' + esc(r.name) + '" data-a="' + r.id + '"></button>'
      : r.kind === 'edit'
        ? '<button class="btn btn-sm" type="button" data-a="' + r.id + '" aria-label="Edit ' + esc(r.name) + '">' + PEN + 'Edit</button>'
        : '<button class="btn btn-sm" type="button" data-a="' + r.id + '" aria-label="Open ' + esc(r.name) + '">Open' + CHEV + '</button>';
    return '<div class="set-row" data-row="' + r.id + '">' +
      '<div class="set-what"><p class="set-name">' + esc(r.name) + '</p>' +
        (r.meta ? '<p class="set-meta">' + esc(r.meta) + '</p>' : '') + '</div>' +
      '<div class="set-ctl">' + ctl + '</div></div>';
  }

  function paint() {
    var box = $('setList');
    if (!box) return;
    var list = groups();
    box.innerHTML = '';
    if (!list.length) { window.ADspaceState.emptyLine(box, 'No settings.'); return; }
    list.forEach(function (g) {
      box.appendChild(window.ADspaceGroup.section({
        route: 'settings', key: g.key, name: g.name, count: g.rows.length, shut: false,
        table: function () {
          var t = document.createElement('div');
          t.className = 'crm-table softpanel set-table';
          t.innerHTML = g.rows.map(rowHtml).join('');
          return t;
        }
      }));
    });
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
    var again = { msg: 'setMsg', done: paint };
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
        ['revision_due_days', 'Revision (Client): days after changes are asked', 'due']] });
      return;
    }
    if (a === 'prices') { ed({ title: 'AI prices, US$ a million tokens', keys: [['ai_price_in', 'Input', 'usd'], ['ai_price_out', 'Output', 'usd']] }); return; }
    if (a === 'meta') { flipMeta(btn); return; }
    if (a === 'reach') { ed({ title: 'Reach allowance', keys: [['reach_allowance_pct', 'Reach within (%) of Meta', 'allow']] }); return; }
    if (a === 'whatsapp') { if (window.ADspaceWhatsApp) window.ADspaceWhatsApp.manage(btn); return; }
    if (a === 'aiuse') { if (window.ADspaceReports && window.ADspaceReports.aiUsage) window.ADspaceReports.aiUsage(btn); return; }
    if (a === 'types') { if (window.ADspaceRegister && window.ADspaceRegister.openTypes) window.ADspaceRegister.openTypes(btn); return; }
    if (a === 'numbering') { if (window.ADspaceOps && window.ADspaceOps.openNumbering) window.ADspaceOps.openNumbering('setMsg'); return; }
  }

  function enter() {
    say('');
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
      var b = e.target.closest('[data-a]');
      if (!b || b.disabled || !$('setList').contains(b)) return;
      press(b.getAttribute('data-a'), b);
    });
  }
  wire();

  window.ADspaceSettings = { enter: function () { wire(); enter(); }, paint: paint, allowed: allowed, say: say };
  if (bridge.settingsReady) bridge.settingsReady();
})();
