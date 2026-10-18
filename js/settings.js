/* ADspaceSettings — the console's Settings page (`?s=settings`, 2026-10-10).
   The user, 2026-10-09: the account menu grew long with the portal's
   switches, and AI usage hid under Reports while it covers every section.
   One page at the rail's foot, above the Activity record, holds what changes
   the portal for everybody: upgrade mode, announcements and notices; the
   business figures; Meta checks; WhatsApp's templates; AI usage and limits; document types and
   task numbering. Each row is drawn only for a colleague holding its granted
   part, and each opens the one sheet that already edits it (one copy of
   every mechanism). The account menu keeps what is the person's own.
   Since 2026-10-11: eight groups, each a card under its heading on one
   page; at a desk a list of them beside it scrolls to one. */
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
  function allowed() { return KEYS.some(may) || Boolean(bridge.may && bridge.may('suppliers', 'manage')); }
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

  /* The figures each Edit row's sheet asks: [key, label, bound, section,
     its value in a line]. More than five read as sections (audit SET-4,
     2026-10-14). A figure changed from a later day is said on its row in
     these words (audit SET-1). */
  function per(u) { return function (v) { return plural(v, u, u + 's'); }; }
  function pctOf(v) { return v + '%'; }
  var TAX_WORD = { sst_pct: ['SST', pctOf], quote_valid_days: ['Quotation valid', per('day')],
    term_1_3: ['1 to 3 months', pct], term_4_5: ['4 and 5 months', pct], term_6_11: ['6 to 11 months', pct],
    term_12_23: ['12 to 17 months', pct], term_18_23: ['18 to 23 months', pct], term_24: ['24 months', pct],
    fx_sgd: ['S$1', function (v) { return 'RM ' + v; }] };
  var SPECS = {
    details: { title: 'Details form', keys: [['details_form_days', 'Open for (days)', 'quote', '', 'Open', per('day')]] },
    followup: { title: 'Follow-up limits', keys: [['lead_followup_hours', 'A lead waits (hours)', 'hours', 'Every client', 'Lead', per('hour')],
      ['proposal_followup_days', 'A proposal waits (days)', 'days', 'Every client', 'Proposal', per('day')],
      /* A VIC's own, shorter (2026-10-15). */
      ['vic_lead_followup_hours', 'A VIC lead waits (hours)', 'hours', 'VIC clients', 'VIC lead', per('hour')],
      ['vic_proposal_followup_days', 'A VIC proposal waits (days)', 'days', 'VIC clients', 'VIC proposal', per('day')]] },
    /* The list is js/admin.js's (the Services bar asks the same sheet). */
    tax: { title: 'Tax and terms', keys: (bridge.TAX_KEYS || []).map(function (k) { return k.concat(TAX_WORD[k[0]]); }) },
    due: { title: 'Due dates', keys: [['report_due_days', 'Report: days after the month ends', 'due', '', 'Report', per('day')],
      ['revision_due_days', 'Revision (Client): working days after changes are asked', 'due', '', 'Revision', per('working day')],
      ['approval_reminder_days', 'Approval reminder: days a client has not approved', 'due', '', 'Approval reminder', per('day')]] },
    priority: { title: 'Priority deadlines', keys: [['priority_urgent_hours', 'Urgent: hours from creation', 'hours', '', 'Urgent', per('hour')],
      ['priority_high_hours', 'High: hours from creation', 'hours', '', 'High', per('hour')],
      ['priority_medium_hours', 'Medium: hours from creation', 'hours', '', 'Medium', per('hour')]] },
    nudge: { title: 'Task reminders', keys: [['task_remind_hours', 'Every: hours between reminders (0 sends none)', 'every', '', 'Every', per('hour')],
      ['task_start_days', 'Not started: days before its date (0 sends none)', 'ahead', '', 'Not started', per('day')]] },
    prices: { title: 'AI prices, US$', keys: [['ai_price_in', 'Input, a million tokens', 'usd', '', 'Input', function (v) { return 'US$ ' + v; }],
      ['ai_price_out', 'Output, a million tokens', 'usd', '', 'Output', function (v) { return 'US$ ' + v; }],
      ['ai_price_search', 'Web searches, a thousand', 'usd', '', 'Web searches', function (v) { return 'US$ ' + v; }]] },
    reach: { title: 'Reach allowance', keys: [['reach_allowance_pct', 'Reach within (%) of Meta', 'allow', '', 'Reach within', pctOf]] },
    /* The Meta Malaysia benchmarks the Brand analysis weighs a budget
       against (2026-10-15, the client analysis playbook). */
    bench: { title: 'Ad benchmarks', keys: [
      ['bench_cpr_low', 'Tier 1 from', 'rm', 'Property cost per result (RM)', 'Property from RM', String],
      ['bench_cpr_mid', 'Tier 2 from', 'rm', 'Property cost per result (RM)', 'Tier 2 from RM', String],
      ['bench_cpr_high', 'Tier 3 from', 'rm', 'Property cost per result (RM)', 'Tier 3 from RM', String],
      ['bench_cpr_top', 'Tier 3 up to', 'rm', 'Property cost per result (RM)', 'Up to RM', String],
      ['bench_msg_min', 'Low', 'rm', 'Messaging cost per result (RM)', 'Messaging low RM', String],
      ['bench_msg_target', 'Target', 'rm', 'Messaging cost per result (RM)', 'Messaging target RM', String],
      ['bench_msg_max', 'High', 'rm', 'Messaging cost per result (RM)', 'Messaging high RM', String],
      ['bench_form_min', 'Low', 'rm', 'Lead form cost per result (RM)', 'Lead form low RM', String],
      ['bench_form_target', 'Target', 'rm', 'Lead form cost per result (RM)', 'Lead form target RM', String],
      ['bench_form_max', 'High', 'rm', 'Lead form cost per result (RM)', 'Lead form high RM', String],
      ['bench_cpm_min', '1,000 impressions, low (RM)', 'rm', 'Market', 'Impressions low RM', String],
      ['bench_cpm_max', '1,000 impressions, high (RM)', 'rm', 'Market', 'Impressions high RM', String],
      ['bench_cpl_rise', 'Cost per lead rise a year (%)', 'adj', 'Market', 'Cost per lead rise', pctOf],
      ['bench_reels_share', 'Reels share of impressions (%)', 'share', 'Market', 'Reels share', pctOf],
      ['bench_ad_spend_pct', 'Ad spend of the budget (%)', 'share', 'Budget rules', 'Ad spend', pctOf],
      ['bench_adset_daily', 'Daily budget an ad set, at least (RM)', 'rm', 'Budget rules', 'Ad set daily RM', String]] },
    /* How long health data is kept (2026-10-18, Team audit 12): PDPA 2010. */
    healthkeep: { title: 'Health data kept', keys: [['health_keep_months', 'Check-ins: months kept', 'keep', '', 'Check-ins', per('month')],
      ['health_leaver_months', 'A leaver\'s health data: months after they left', 'leave', '', 'A leaver\'s', per('month')]] },
    resend: { title: 'WhatsApp sent again', keys: [['wa_repeat_hours', 'Ask again within: hours (0 asks nothing)', 'week', '', 'Asks again within', per('hour')]] }
  };
  /* The earliest change set from a later day, in the row's words: "From
     14 Nov 2026: SST 6%". Meta checks is its one switch with a figure. */
  function nextLine(id) {
    var M = window.ADspaceMoney;
    if (!M || !M.next) return '';
    var keys = id === 'meta' ? [['meta_checks', '', '', '', 'Meta checks', function (v) { return v ? 'on' : 'off'; }]] : (SPECS[id] || {}).keys;
    if (!keys) return '';
    var first = '', bits = [];
    keys.forEach(function (k) { var x = M.next(k[0]); if (x && (!first || x.from < first)) first = x.from; });
    if (!first) return '';
    keys.forEach(function (k) { var x = M.next(k[0]); if (x && x.from === first) bits.push(k[4] + ' ' + k[5](x.value)); });
    return 'From ' + (window.ADspaceClock ? window.ADspaceClock.date(first) : first) + ': ' + parts(bits);
  }

  /* What an Open row holds, read once a visit and filled in place
     (2026-10-14, ux-audit SET-7): each from its section's own read, its
     line's room kept while the read is out, Could not load. on a refusal. */
  var lines = {};
  function line(id) { var x = lines[id]; return x == null ? '\u00a0' : x; }
  function fillLine(id, text) {
    lines[id] = text;
    var row = document.querySelector('.stg-row[data-row="' + id + '"]');
    if (!row) return;
    var m = row.querySelector('.stg-meta');
    if (!text) { if (m) m.remove(); return; }
    if (!m) {
      var name = row.querySelector('.stg-name');
      if (!name) return;
      m = document.createElement('p'); m.className = 'stg-meta';
      name.parentNode.insertBefore(m, name.nextSibling);
    }
    m.textContent = text;
  }
  var READ = {
    announce: function () {
      return window.ADspaceAnnounce && window.ADspaceAnnounce.live && window.ADspaceAnnounce.live().then(function (n) {
        return n.team || n.clients ? parts(['Team ' + n.team + ' live', 'Clients ' + n.clients + ' live']) : 'None live';
      });
    },
    notice: function () {
      return window.ADspaceNotice && window.ADspaceNotice.last && window.ADspaceNotice.last().then(function (n) {
        return n ? 'Last sent ' + when(n.created_at).split(', ')[0] : 'None sent';
      });
    },
    numbering: function () {
      return db.rpc('ops_next_task_no').then(function (r) {
        if (r.error || (r.data && r.data.error)) throw r.error || new Error(r.data.error);
        return r.data && r.data.serial ? 'Next ' + r.data.serial : '';
      });
    },
    aiuse: function () {
      return window.ADspaceReports && window.ADspaceReports.aiToday && window.ADspaceReports.aiToday().then(function (t) {
        return 'Used today ' + t.used + ' of ' + t.cap;
      });
    },
    whatsapp: function () {
      return window.ADspaceWhatsApp && window.ADspaceWhatsApp.templates && window.ADspaceWhatsApp.templates().then(function (t) {
        return t.on + ' of ' + t.all + ' on';
      });
    },
    types: function () {
      return db.from('doc_types').select('id, active').then(function (r) {
        if (r.error) throw r.error;
        return plural((r.data || []).filter(function (t) { return t.active !== false; }).length, 'type', 'types') + ' offered';
      });
    }
  };
  function readLine(id) {
    if (!document.querySelector('.stg-row[data-row="' + id + '"]')) return;
    var asked = READ[id] && READ[id]();
    if (!asked || !asked.then) { fillLine(id, ''); return; }
    asked.then(function (t) { fillLine(id, t || ''); }).catch(function () { fillLine(id, 'Could not load.'); });
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
      may('team.announce') && { id: 'announce', name: 'Announcements', kind: 'open', meta: line('announce') },
      may('team.notice') && { id: 'notice', name: 'Notices', kind: 'open', meta: line('notice') },
      biz && { id: 'holidays', name: 'Public holidays', kind: 'open', meta: holMeta() },
      biz && { id: 'healthkeep', name: 'Health data kept', kind: 'edit',
        meta: num('health_keep_months') == null ? '' : parts(['Check-ins ' + plural(num('health_keep_months'), 'month', 'months'),
          'A leaver\'s ' + plural(num('health_leaver_months'), 'month', 'months') + ' after they left']) }]);
    var lead = num('lead_followup_hours'), prop = num('proposal_followup_days');
    add('clients', 'Clients', [
      biz && { id: 'followup', name: 'Follow-up limits', kind: 'edit',
        meta: lead == null ? '' : parts(['Lead ' + plural(lead, 'hour', 'hours'), 'Proposal ' + plural(prop, 'day', 'days'),
          num('vic_lead_followup_hours') == null ? '' : 'VIC ' + plural(num('vic_lead_followup_hours'), 'hour', 'hours') + ' and ' + plural(num('vic_proposal_followup_days'), 'day', 'days')].filter(Boolean)) },
      /* The client's details form (2026-10-14, ux-audit SET-9: it sat in
         Tax and terms). */
      biz && { id: 'details', name: 'Details form', kind: 'edit',
        meta: num('details_form_days') == null ? '' : 'Open ' + plural(num('details_form_days'), 'day', 'days') }]);
    var rep = num('report_due_days'), rev = num('revision_due_days');
    add('work', 'My Work', [
      biz && { id: 'due', name: 'Due dates', kind: 'edit',
        meta: rep == null ? '' : parts(['Report ' + plural(rep, 'day', 'days') + ' after the month', 'Revision ' + plural(rev, 'working day', 'working days')]
          .concat(num('approval_reminder_days') == null ? [] : ['Approval reminder ' + plural(num('approval_reminder_days'), 'day', 'days')])) },
      biz && { id: 'priority', name: 'Priority deadlines', kind: 'edit',
        meta: num('priority_high_hours') == null ? '' : parts(['Urgent ' + plural(num('priority_urgent_hours'), 'hour', 'hours'),
          'High ' + plural(num('priority_high_hours'), 'hour', 'hours'), 'Medium ' + plural(num('priority_medium_hours'), 'hour', 'hours')]) },
      biz && { id: 'nudge', name: 'Task reminders', kind: 'edit',
        meta: num('task_remind_hours') == null ? '' : num('task_remind_hours') === 0 ? 'Off'
          : parts(['Every ' + plural(num('task_remind_hours'), 'hour', 'hours') + ' on weekdays',
            num('task_start_days') === 0 ? 'Not started off' : 'Not started ' + plural(num('task_start_days'), 'day', 'days') + ' ahead']) },
      may('ops.numbering') && { id: 'numbering', name: 'Task numbering', kind: 'edit', meta: line('numbering') }]);
    var meta = num('meta_checks') === 1;
    add('reports', 'Reports', [
      biz && { id: 'meta', name: 'Meta checks', kind: 'switch', on: meta,
        meta: meta ? 'On · Import from Meta, Report audit' : 'Off' },
      biz && { id: 'reach', name: 'Reach allowance', kind: 'edit',
        meta: num('reach_allowance_pct') == null ? '' : 'Within ' + num('reach_allowance_pct') + '% of Meta' },
      biz && { id: 'bench', name: 'Ad benchmarks', kind: 'edit',
        meta: num('bench_msg_target') == null ? '' : parts(['Messaging RM ' + num('bench_msg_target'), 'Lead form RM ' + num('bench_form_target'),
          'Ad spend ' + num('bench_ad_spend_pct') + '%', 'Ad set RM ' + num('bench_adset_daily') + ' a day']) }]);
    var pin = num('ai_price_in'), pout = num('ai_price_out');
    add('money', 'Money', [
      biz && { id: 'tax', name: 'Tax and terms', kind: 'edit',
        meta: num('sst_pct') == null ? '' : parts(['SST ' + num('sst_pct') + '%', '1 to 3 months ' + pct(num('term_1_3')), '24 months ' + pct(num('term_24'))].concat(num('quote_valid_days') == null ? [] : ['Quotation valid ' + num('quote_valid_days') + ' days'])
          .concat(num('fx_sgd') == null ? [] : ['S$1 = RM ' + num('fx_sgd')])) }]);
    /* AI's usage and its prices in one group (2026-10-14, ux-audit SET-9). */
    add('ai', 'AI', [may('reports.ai') && { id: 'aiuse', name: 'AI usage and limits', kind: 'open', meta: line('aiuse') },
      biz && { id: 'prices', name: 'AI prices', kind: 'edit',
        meta: pin == null ? '' : parts(['US$ ' + pin + ' input', 'US$ ' + pout + ' output']) + ', a million tokens' +
          (num('ai_price_search') == null ? '' : ' · US$ ' + num('ai_price_search') + ' a thousand web searches') }]);
    /* WhatsApp (2026-10-10): its templates are set in the WhatsApp section
       at Full Access; this row opens them there. */
    var rep2 = num('wa_repeat_hours');
    add('whatsapp', 'WhatsApp', [window.ADspaceWhatsApp && bridge.may && bridge.may('whatsapp', 'manage') &&
      { id: 'whatsapp', name: 'Templates', kind: 'open', meta: line('whatsapp') },
      /* Sent again (2026-10-14): the same message sent within the window
         asks again before it goes. */
      biz && { id: 'resend', name: 'Sent again', kind: 'edit',
        meta: rep2 == null ? '' : rep2 === 0 ? 'Off' : 'Within ' + plural(rep2, 'hour', 'hours') }]);
    add('documents', 'Documents', [may('register.types') && { id: 'types', name: 'Document types', kind: 'open', meta: line('types') },
      bridge.may && bridge.may('suppliers', 'manage') && { id: 'suptpl', name: 'Supplier emails', kind: 'open', meta: '2 templates' }]);
    return out;
  }

  var reread = '';
  /* What a press said, kept on its row through a repaint (audit SET-2). */
  var said = null;
  function rowSay(id) {
    return function (text, tone) { said = text ? { row: id, text: text, tone: tone || '' } : null; paint(); };
  }
  function rowHtml(r) {
    var next = nextLine(r.id);
    var ctl = r.kind === 'switch'
      ? '<button class="switch" type="button" role="switch" aria-checked="' + (r.on ? 'true' : 'false') + '" aria-label="' + esc(r.name) + '" data-a="' + r.id + '"></button>'
      : r.kind === 'edit'
        ? '<button class="btn btn-sm" type="button" data-a="' + r.id + '" aria-label="Edit ' + esc(r.name) + '">' + PEN + 'Edit</button>'
        : '<button class="btn btn-sm" type="button" data-a="' + r.id + '" aria-label="Open ' + esc(r.name) + '">Open' + CHEV + '</button>';
    return '<div class="stg-row" data-row="' + r.id + '">' +
      '<div class="stg-what"><p class="stg-name">' + esc(r.name) + '</p>' +
        (r.meta ? '<p class="stg-meta">' + esc(r.meta) + '</p>' : '') +
        (next ? '<p class="stg-meta stg-next">' + esc(next) + '</p>' : '') +
        (said && said.row === r.id ? '<p class="msg stg-said' + (said.tone ? ' ' + said.tone : '') + '" role="status">' + esc(said.text) + '</p>' : '') + '</div>' +
      '<div class="stg-ctl">' + ctl + '</div></div>';
  }

  /* One page of every group (the user, 2026-10-11, after a drill-down was
     tried: "It now takes five layers into the individual settings"): each
     group a card under its heading, each row opening its own sheet, so a
     setting is the account menu, Settings, then its sheet. At a desk the
     groups also run down the left and a press there only scrolls the page
     to its card; the group pressed is in the address (`tab=`, the first left
     out), so a refresh lands on it. */
  var phoneMedia = window.matchMedia && window.ADSPACE_TABBAR ? window.matchMedia(window.ADSPACE_TABBAR) : null;
  function phone() { return Boolean(phoneMedia && phoneMedia.matches); }
  var chosen = '';
  function fromUrl() { chosen = new URLSearchParams(location.search).get('tab') || ''; }

  function sec(g) {
    return '<section class="stg-sec" id="stg-' + g.key + '" data-sec="' + g.key + '" aria-labelledby="stgT-' + g.key + '">' +
      '<h3 class="stg-title" id="stgT-' + g.key + '">' + esc(g.name) + '</h3>' +
      '<div class="stg-card">' + g.rows.map(rowHtml).join('') + '</div></section>';
  }

  /* A repaint that would draw the same page leaves it alone, so what is
     ringed or focused on it (a first-visit guide's step) stays. */
  var drawn = '';
  function paint() {
    var box = $('setList');
    if (!box) return;
    var list = groups();
    if (!list.length) { drawn = ''; box.className = ''; box.innerHTML = ''; window.ADspaceState.emptyLine(box, 'No settings.'); return; }
    /* The list of groups beside them only where there are three or more
       to move between (2026-10-14, ux-audit SET-5). */
    var desk = !phone() && list.length >= 3;
    var cls = 'stg ' + (desk ? 'is-desk' : phone() ? 'is-phone' : 'is-single');
    var html = (desk ? '<nav class="stg-nav" aria-label="Settings">' + list.map(function (x) {
      return '<button class="stg-go" type="button" data-g="' + x.key + '" aria-controls="stg-' + x.key + '">' + esc(x.name) + '</button>';
    }).join('') + '</nav>' : '') + '<div class="stg-groups">' + list.map(sec).join('') + '</div>';
    if (html !== drawn || box.className !== cls || !box.firstChild) {
      var had = document.activeElement && box.contains(document.activeElement) ? document.activeElement.getAttribute('data-a') : '';
      drawn = html;
      box.className = cls;
      box.innerHTML = html;
      var back = had && box.querySelector('[data-a="' + had + '"]');
      if (back) back.focus({ preventScroll: true });
      if (window.ADspaceGuide && window.ADspaceGuide.relay) window.ADspaceGuide.relay();
    }
    mark();
  }

  /* The group in view wears the list's fill; never more than one. */
  function mark(key) {
    var box = $('setList');
    if (!box) return;
    var secs = box.querySelectorAll('.stg-sec');
    if (!key) {
      key = secs[0] ? secs[0].getAttribute('data-sec') : '';
      var line = (parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--head-h')) || 64) + 24;
      Array.prototype.forEach.call(secs, function (x) { if (x.getBoundingClientRect().top <= line) key = x.getAttribute('data-sec'); });
      if (secs.length && window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2) {
        var last = secs[secs.length - 1];
        if (last.getBoundingClientRect().top < window.innerHeight) key = last.getAttribute('data-sec');
      }
      if (pinned && box.querySelector('.stg-sec[data-sec="' + pinned + '"]')) key = pinned;
    }
    Array.prototype.forEach.call(box.querySelectorAll('.stg-go'), function (b) {
      if (b.getAttribute('data-g') === key) b.setAttribute('aria-current', 'true'); else b.removeAttribute('aria-current');
    });
  }

  /* A group pressed holds the fill until the person scrolls the page
     themselves (a short last group cannot reach the top). */
  var pinned = '';
  ['wheel', 'touchmove', 'keydown'].forEach(function (ev) {
    window.addEventListener(ev, function (e) {
      if (ev === 'keydown' && e.target && e.target.closest && e.target.closest('#setList .stg-go')) return;
      pinned = '';
    }, { passive: true, capture: true });
  });
  function shown() { var s = $('sectionSettings'); return s && !s.hidden; }
  var spy = 0;
  window.addEventListener('scroll', function () {
    if (!shown() || spy) return;
    spy = requestAnimationFrame(function () { spy = 0; mark(); });
  }, { passive: true });

  function urlState() {
    var list = groups();
    if (!chosen || !list.some(function (x) { return x.key === chosen; }) || list[0].key === chosen) return {};
    return { tab: chosen };
  }

  function reveal(key, smooth) {
    var el = $('stg-' + key);
    if (!el) return;
    var top = el.getBoundingClientRect().top + window.scrollY -
      (parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--head-h')) || 64) - 12;
    window.scrollTo({ top: Math.max(0, top), behavior: smooth ? 'smooth' : 'auto' });
  }
  function go(key) {
    chosen = key;
    pinned = key;
    say('');
    mark(key);
    reveal(key, !(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches));
    if (bridge.setUrl) bridge.setUrl();
  }
  function follow() { if (shown()) paint(); }
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
      rowSay('meta')(to ? 'Meta checks are on.' : 'Meta checks are off.', 'ok');
    }).catch(function (e) {
      sw.setAttribute('aria-checked', to ? 'false' : 'true');
      sw.disabled = false;
      rowSay('meta')(String((e && e.message) || e), 'err');
    });
  }

  function press(a, btn) {
    say('');
    /* The last answer leaves its row, without a repaint under the press. */
    if (said) {
      said = null;
      Array.prototype.forEach.call(document.querySelectorAll('#setList .stg-said'), function (m) { m.remove(); });
    }
    /* A row whose sheet changes what its line says reads it again when the
       sheet hands focus back to it. */
    if (READ[a]) reread = a;
    if (SPECS[a]) {
      var sp = SPECS[a];
      bridge.editSettings({ title: sp.title, keys: sp.keys.map(function (k) { return [k[0], k[1], k[2], k[3]]; }), msg: rowSay(a), done: paint }, btn);
      return;
    }
    if (a === 'upgrade') { if (bridge.upgradeToggle) bridge.upgradeToggle(btn); return; }
    if (a === 'announce') { if (window.ADspaceAnnounce) window.ADspaceAnnounce.manage(btn); return; }
    if (a === 'notice') { if (window.ADspaceNotice) window.ADspaceNotice.manage(btn); return; }
    if (a === 'meta') { flipMeta(btn); return; }
    if (a === 'whatsapp') { if (window.ADspaceWhatsApp) window.ADspaceWhatsApp.manage(btn); return; }
    if (a === 'aiuse') { if (window.ADspaceReports && window.ADspaceReports.aiUsage) window.ADspaceReports.aiUsage(btn); return; }
    if (a === 'types') { if (window.ADspaceRegister && window.ADspaceRegister.openTypes) window.ADspaceRegister.openTypes(btn); return; }
    if (a === 'suptpl') { if (window.ADspaceSuppliers && window.ADspaceSuppliers.openTemplates) window.ADspaceSuppliers.openTemplates(btn); return; }
    if (a === 'holidays') { openHol(btn); return; }
    if (a === 'numbering') { if (window.ADspaceOps && window.ADspaceOps.openNumbering) window.ADspaceOps.openNumbering(rowSay('numbering')); return; }
  }

  /* ---- Public holidays (2026-10-14) ------------------------------------
     The days the office is closed: the front door draws them Closed and My
     Work marks them. Read for this year and the next in one request; the
     row says the next one, the sheet lists a year at a time. */
  var DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  var hol = { rows: null, err: null, year: null };
  var HOL_SAID = {
    taken: 'That date already holds a holiday.', 'bad-name': 'Enter a name of 2 to 80 characters.',
    'bad-day': 'Choose a date from 2023 to 2099.', 'not-found': 'This holiday was removed in the meantime.',
    denied: 'Business settings access is required.'
  };
  function holSaid(r) {
    var e = r && (r.error || (r.data && r.data.error));
    if (!e) return '';
    if (e.message) return /function|schema cache/i.test(e.message) ? 'This needs a database update.' : e.message;
    return e === 'taken' && r.data.name ? 'That date already holds ' + r.data.name + '.' : HOL_SAID[e] || 'Not saved.';
  }
  function holToday() { return window.ADspaceClock ? window.ADspaceClock.today() : new Date(Date.now() + 8 * 3600e3).toISOString().slice(0, 10); }
  function holDay(d, withDow) {
    var x = new Date(d + 'T00:00:00Z');
    return (withDow ? DOW[x.getUTCDay()] + ', ' : '') + x.getUTCDate() + ' ' + MON[x.getUTCMonth()] + ' ' + x.getUTCFullYear();
  }
  function holMeta() {
    /* Its line's room is kept while the read is out, so nothing below moves
       when it arrives. */
    if (!hol.rows) return hol.err ? 'Could not load.' : '\u00a0';
    var t = holToday(), next = hol.rows.filter(function (h) { return h.day >= t; })[0];
    return next ? 'Next: ' + next.name + ', ' + holDay(next.day) : 'No holidays listed ahead';
  }
  function holLine() { var meta = holMeta(); if (meta) fillLine('holidays', meta); }
  function readHol(done) {
    var y = Number(holToday().slice(0, 4));
    db.rpc('public_holidays_between', { p_from: y + '-01-01', p_to: (y + 1) + '-12-31' }).then(function (r) {
      if (r.error) throw r.error;
      hol.rows = r.data || []; hol.err = null;
    }).catch(function (e) { hol.rows = null; hol.err = e; }).then(function () { if (done) done(); });
  }
  function holYears() {
    var y = Number(holToday().slice(0, 4)), out = [y, y + 1];
    (hol.rows || []).forEach(function (h) { var hy = Number(h.day.slice(0, 4)); if (out.indexOf(hy) < 0) out.push(hy); });
    return out.sort();
  }
  function paintHol() {
    var box = $('holList');
    if (!box) return;
    if (hol.err) {
      window.ADspaceState.failLine(box, 'Public holidays', (hol.err && hol.err.message) || '', function () { readHol(paintHol); });
      $('holYearRow').hidden = true;
      return;
    }
    if (!hol.rows) { window.ADspaceState.skeleton(box, 4); return; }
    var years = holYears();
    if (!hol.year || years.indexOf(hol.year) < 0) hol.year = years[0];
    var sel = $('holYear'), opts = years.map(function (y) { return '<option value="' + y + '"' + (y === hol.year ? ' selected' : '') + '>' + y + '</option>'; }).join('');
    if (sel.innerHTML !== opts) { sel.innerHTML = opts; if (window.ADspaceForm && window.ADspaceForm.scan) window.ADspaceForm.scan($('holYearRow')); }
    sel.value = String(hol.year);
    $('holYearRow').hidden = false;
    var t = holToday();
    var rows = hol.rows.filter(function (h) { return Number(h.day.slice(0, 4)) === hol.year; });
    if (!rows.length) { box.innerHTML = ''; window.ADspaceState.emptyLine(box, 'No holidays.'); return; }
    box.innerHTML = rows.map(function (h) {
      return '<div class="dtrow hol-row' + (h.day < t ? ' is-past' : '') + '" data-day="' + esc(h.day) + '">' +
        '<span class="dtrow-name"><b>' + esc(h.name) + '</b><small>' + esc(holDay(h.day, true)) + '</small></span>' +
        '<span class="hol-acts"><button class="btn btn-quiet btn-sm" type="button" data-h="edit">' + PEN + 'Edit</button>' +
        '<span class="team-act"><button class="kmenu-btn" type="button" data-h="menu" aria-label="More actions for ' + esc(h.name) + '" aria-expanded="false">' +
          '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/></svg></button>' +
        '<div class="kmenu" data-menu hidden role="menu"><button class="kmenu-item is-danger" type="button" role="menuitem" data-h="delete">Delete</button></div></span></span></div>';
    }).join('');
  }
  function holShut() {
    Array.prototype.forEach.call(document.querySelectorAll('#holList .kmenu'), function (m) { m.hidden = true; });
    Array.prototype.forEach.call(document.querySelectorAll('#holList [data-h="menu"]'), function (b) { b.setAttribute('aria-expanded', 'false'); });
  }
  function holAsk(h, opener) {
    var t = holToday();
    window.ADspaceConfirm.ask({
      title: h ? 'Edit public holiday' : 'Add public holiday', go: 'Save', wait: true,
      fields: [{ name: 'day', label: 'Date', type: 'date', value: h ? h.day : (hol.year && String(hol.year) !== t.slice(0, 4) ? hol.year + '-01-01' : t), required: true },
        { name: 'name', label: 'Name', value: h ? h.name : '', placeholder: 'Deepavali', required: true }]
    }, function (v) {
      return db.rpc('public_holiday_save', { p_day: v.day, p_name: v.name, p_was: h ? h.day : null }).then(function (r) {
        var said = holSaid(r);
        if (said) return said;
        hol.year = Number(String(v.day).slice(0, 4));
        return new Promise(function (ok) { readHol(function () { paintHol(); paint(); say(''); holMsg('Saved.', 'ok'); ok(''); }); });
      }).catch(function (e) { return (e && e.message) || 'Not saved.'; });
    });
  }
  function holMsg(text, tone) { var m = $('holMsg'); if (!m) return; m.textContent = text || ''; m.className = 'msg' + (text ? ' ' + (tone || 'err') : ''); }
  function holDelete(h) {
    window.ADspaceConfirm.ask({ title: 'Delete this holiday?', body: h.name + ', ' + holDay(h.day) + ', is removed from the list. There is no restore.', go: 'Delete', tone: 'danger', wait: true },
      function () {
        return db.rpc('public_holiday_delete', { p_day: h.day }).then(function (r) {
          var said = holSaid(r);
          if (said) return said;
          return new Promise(function (ok) { readHol(function () { paintHol(); paint(); holMsg('Deleted.', 'ok'); ok(''); }); });
        }).catch(function (e) { return (e && e.message) || 'Not deleted.'; });
      });
  }
  function openHol(opener) {
    if (!biz()) return;
    holMsg('');
    paintHol();
    window.ADspaceSheet.show($('holSheet'), { opener: opener });
    readHol(paintHol);
  }
  function biz() { return may('team.settings'); }
  var holWired = false;
  function wireHol() {
    if (holWired || !$('holSheet')) return;
    holWired = true;
    $('holCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('holClose').addEventListener('click', function () { $('holCancel').click(); });
    $('holAdd').addEventListener('click', function () { holMsg(''); holAsk(null, this); });
    $('holYear').addEventListener('change', function () { hol.year = Number(this.value); holMsg(''); paintHol(); });
    $('holList').addEventListener('click', function (e) {
      var b = e.target.closest('[data-h]');
      if (!b) return;
      var row = b.closest('.hol-row'), day = row && row.getAttribute('data-day');
      var h = (hol.rows || []).filter(function (x) { return x.day === day; })[0];
      if (!h) return;
      var k = b.getAttribute('data-h');
      if (k === 'menu') {
        e.stopPropagation();
        var mn = row.querySelector('[data-menu]'), open = mn.hidden;
        holShut();
        mn.hidden = !open; b.setAttribute('aria-expanded', String(open));
        if (open) window.ADspaceMenu.place(b, mn);
        return;
      }
      holShut(); holMsg('');
      if (k === 'edit') holAsk(h, b);
      if (k === 'delete') holDelete(h);
    });
    document.addEventListener('click', function (e) { if (!e.target.closest('#holList .team-act')) holShut(); });
  }
  wireHol();

  function enter() {
    say('');
    said = null;
    lines = {};
    fromUrl();
    pinned = chosen;
    var M = window.ADspaceMoney;
    paint();
    /* The figures are read once a page; a colleague who changed one in
       another tab sees it here on the way in. */
    if (M && M.load) M.load(true).then(paint).catch(function () {});
    /* The holidays' line is filled in place: a repaint of the whole page
       after it arrived lost the place a refresh or an address had scrolled
       to, and the guide's ring. */
    if (biz()) readHol(holLine);
    Object.keys(READ).forEach(readLine);
    /* A group named in the address is brought to the top, else the page's
       own scroll. */
    if (chosen && $('stg-' + chosen)) reveal(chosen, false);
    else if (bridge.restoreScroll) bridge.restoreScroll();
  }

  var wired = false;
  function wire() {
    if (wired || !$('setList')) return;
    wired = true;
    $('setList').addEventListener('focusin', function (e) {
      var b = e.target.closest && e.target.closest('[data-a]');
      if (!reread || !b || b.getAttribute('data-a') !== reread || document.querySelector('.sheet:not([hidden])')) return;
      var id = reread; reread = '';
      readLine(id);
    });
    $('setList').addEventListener('click', function (e) {
      var gb = e.target.closest('[data-g]');
      if (gb && $('setList').contains(gb)) { go(gb.getAttribute('data-g')); return; }
      var b = e.target.closest('[data-a]');
      if (!b || b.disabled || !$('setList').contains(b)) return;
      press(b.getAttribute('data-a'), b);
    });
  }
  wire();

  window.ADspaceSettings = { enter: function () { wire(); enter(); }, paint: paint, urlState: urlState, allowed: allowed, say: say };
  if (bridge.settingsReady) bridge.settingsReady();
})();
