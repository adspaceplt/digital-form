/* ADspaceSettings — the console's Settings page (`?s=settings`, 2026-10-10).
   The user, 2026-10-09: the account menu grew long with the portal's
   switches, and AI usage hid under Reports while it covers every section.
   One page at the rail's foot, above the Activity record, holds what changes
   the portal for everybody: upgrade mode, announcements and notices; the
   business figures; Meta checks; AI usage and limits; task numbering; and,
   since 2026-10-29, every template (WhatsApp, emails, document types, task
   templates, the rate card's wording) in one Templates group. Each row is drawn only for a colleague holding its granted
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
  function esc(s) { return window.ADspaceWords.esc(s); }
  var PEN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 20h4L19 9l-4-4L4 16z"/><path d="m13.5 6.5 4 4"/></svg>';
  /* A table's add row: its Add carries the plus, as Reports' does (gate 2026-11-05). */
  var PLUS = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>';
  var CHEV = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 18 6-6-6-6"/></svg>';
  /* Every part a row of this page answers to. The route is offered to a
     colleague holding any of them, or Suppliers, WhatsApp or Services at
     Full Access (Supplier emails, WhatsApp templates, Rate card wording)
     (`ADspaceSettings.allowed`). */
  var KEYS = ['team.upgrade', 'team.announce', 'team.notice', 'team.settings', 'reports.ai', 'register.types', 'ops.numbering', 'ops.workflows'];
  var FULL = ['suppliers', 'whatsapp', 'services'];
  function may(k) { return Boolean(bridge.may && bridge.may(k, 'work')); }
  function full(k) { return Boolean(bridge.may && bridge.may(k, 'manage')); }
  /* Performance (2026-10-29): management at View reads the figures, behind
     the master code; only its admins change them (the sheet says so). */
  function perfMay() { return Boolean(bridge.may && bridge.may('team.performance', 'view')) && Boolean(window.ADspacePerf && window.ADspacePerf.openSettings); }
  function allowed() { return KEYS.some(may) || FULL.some(full) || perfMay(); }
  function say(text, tone) {
    var m = $('settingsMsg');
    if (!m) return;
    m.textContent = text || '';
    m.className = 'msg' + (tone ? ' ' + tone : '');
  }
  function num(k) { var M = window.ADspaceMoney; return M && M.setting ? M.setting(k) : null; }
  function plural(n, one, many) { return n + ' ' + (n === 1 ? one : many); }
  /* A line of parts wraps between its parts, never inside one. */
  function parts(list) { return list.map(function (x) { return String(x).replace(/ /g, '\u00a0'); }).join(' · '); }
  /* A moment in Malaysia's day and time, from its clock (js/clock.js). */
  function when(iso) {
    if (!iso) return '';
    var C = window.ADspaceClock;
    return C.date(iso) + ', ' + C.clock(iso, { space: true });
  }

  /* The figures each Edit row's sheet asks: js/admin.js's one list, which
     My Work's ⋯, the Services bar and AI usage open alike (2026-10-22). */
  var SPECS = bridge.SETTING_SHEETS || {};
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
    /* Page availability (2026-10-29): which pages show their notice page
       now, and which are set for later (2026-10-31: "2 covered" read as
       nothing to the user). */
    pages: function () {
      return readPg().then(function (rows) {
        var set = rows.filter(function (p) { return p.set; });
        if (!set.length) return 'All pages available';
        return parts(pgCounts(rows).concat(set.length <= 3 ? [set.map(function (p) { return p.name; }).join(', ')] : []));
      });
    },
    /* What the Departments row holds, from the list (2026-10-23). */
    depts: function () {
      return db.rpc('departments_list').then(function (r) {
        if (r.error || (r.data && r.data.error)) throw r.error || new Error(r.data.error);
        var on = (r.data || []).filter(function (d) { return d.active; });
        var inp = on.filter(function (d) { return d.in_prize; }).length;
        return parts([on.length <= 3 ? on.map(function (d) { return d.name; }).join(', ') : plural(on.length, 'department', 'departments'),
          plural(inp, 'in the prize', 'in the prize')]);
      });
    },
    /* What the Industries row holds (2026-11-04). */
    /* Creator and campaign IDs (2026-11-08): the next of each. */
    ids: function () {
      return db.rpc('id_formats_list').then(function (r) {
        if (r.error || !Array.isArray(r.data)) throw r.error || new Error('ids');
        return parts(r.data.filter(function (f) { return f.kind !== 'job'; }).map(function (f) {
          return (f.kind === 'creator' ? 'Next creator ' : 'Next campaign ') + idNext(f);
        }));
      });
    },
    industries: function () {
      return db.rpc('industries_list').then(function (r) {
        if (r.error || !Array.isArray(r.data)) throw r.error || new Error('industries');
        return plural(r.data.length, 'industry', 'industries');
      });
    },
    bukku: function () { return window.ADspaceBukku && window.ADspaceBukku.configLine(); },
    /* Overdue reminder (2026-10-28): who last changed the words. */
    /* Demo access (2026-10-27): on or off, and whether a PIN is held. */
    demo: function () {
      return db.rpc('demo_state').then(function (r) {
        if (r.error || (r.data && r.data.error)) throw r.error || new Error(r.data.error);
        var d = r.data || {};
        return d.on ? 'On · PIN set' : d.pin_set ? 'Off · PIN set' : 'Off';
      });
    },
    taxcodes: function () {
      var M = window.ADspaceMoney;
      return biz() && M && M.taxCodes && M.taxCodes(true).then(function (list) {
        var on = list.filter(function (t) { return t.active; });
        return on.length ? parts(on.map(function (t) { return t.code + ' ' + (Math.round(Number(t.rate) * 100) / 100) + '%'; })) : 'None set';
      });
    },
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
    /* Every email's wording (2026-11-10): how many each recipient holds. */
    mailtpl: function () { return window.ADspaceMailTpl && window.ADspaceMailTpl.line(); },
    /* The payments sheet (2026-11-09): on or off, and rows added. */
    crsheet: function () {
      return db.rpc('creator_sheet_get').then(function (r) {
        var d = r.data || {};
        if (r.error || d.error) throw new Error('unread');
        if (!d.on) return 'Off';
        return parts(['On', plural(Number(d.added || 0), 'row added', 'rows added'),
          Number(d.failed || 0) ? plural(Number(d.failed), 'row not added', 'rows not added') : ''].filter(Boolean));
      });
    },
    /* The meeting message (2026-10-29): who last changed its words. */
    meetmsg: function () { return window.ADspaceOps && window.ADspaceOps.meetMessageLine && window.ADspaceOps.meetMessageLine(); },
    /* Task templates (2026-10-29): the families, and how many fill a task. */
    tasktpl: function () {
      return db.from('ops_task_templates').select('id, active').then(function (r) {
        if (r.error) throw r.error;
        var all = r.data || [], on = all.filter(function (t) { return t.active !== false; }).length;
        return parts([plural(all.length, 'template', 'templates'), on + ' active']);
      });
    },
    /* Rate card wording (2026-10-29): its blocks, published with the card. */
    wording: function () {
      return db.from('rate_card_text').select('key').then(function (r) {
        if (r.error) throw r.error;
        return parts([plural((r.data || []).length, 'block', 'blocks'), 'published with the rate card']);
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
  /* The groups, each a few short sections of at most five rows (the
     overnight review, 2026-11-10: Apple's System Settings, inset cards under
     short headings). A row carries its own control and what a press opens
     (`open`); a row whose figures one sheet edits is a SETTING_SHEETS key
     and needs neither. `meta` says the value as it stands. */
  function groups() {
    var biz = may('team.settings');
    var out = [];
    function add(key, name, glyph, secs) {
      secs = secs.map(function (x) { return { name: x[0], rows: x[1].filter(Boolean) }; }).filter(function (x) { return x.rows.length; });
      if (!secs.length) return;
      out.push({ key: key, name: name, glyph: glyph, secs: secs,
        rows: secs.reduce(function (all, x) { return all.concat(x.rows); }, []) });
    }
    function opens(fn) { return function (btn) { if (fn) fn(btn); }; }
    var W = window;
    add('portal', 'Portal', 'settings', [
      ['Pages and notices', [
        /* Page availability (2026-10-29): Upgrade mode a page at a time. */
        may('team.upgrade') && { id: 'pages', name: 'Page availability', kind: 'open', meta: line('pages'), open: openPages },
        may('team.announce') && { id: 'announce', name: 'Announcements', kind: 'open', meta: line('announce'),
          open: opens(W.ADspaceAnnounce && W.ADspaceAnnounce.manage) },
        may('team.notice') && { id: 'notice', name: 'Notices', kind: 'open', meta: line('notice'),
          open: opens(W.ADspaceNotice && W.ADspaceNotice.manage) },
        /* Demo access (2026-10-27): the PIN typed in the sign-in's email box
           that opens the console on sample data (js/demo.js). */
        biz && { id: 'demo', name: 'Demo access', kind: 'edit', meta: line('demo'), open: function () { openDemo(); } }]],
      ['Company', [
        biz && { id: 'holidays', name: 'Public holidays', kind: 'open', meta: holMeta(), open: openHol },
        biz && { id: 'depts', name: 'Departments', kind: 'open', meta: line('depts'), open: openDepts },
        /* Overseas approval (2026-10-24): how long an approval runs at most
           and how often a waiting request reminds. */
        biz && { id: 'abroadays', name: 'Overseas approval', kind: 'edit',
          meta: num('abroad_days') == null ? '' : parts(['Up to ' + plural(num('abroad_days'), 'day', 'days'),
            num('abroad_remind_hours') == null ? '' : num('abroad_remind_hours') === 0 ? 'No reminder'
              : 'Reminder every ' + plural(num('abroad_remind_hours'), 'hour', 'hours')].filter(Boolean)) },
        biz && { id: 'healthkeep', name: 'Health data kept', kind: 'edit',
          meta: num('health_keep_months') == null ? '' : parts(['Check-ins ' + plural(num('health_keep_months'), 'month', 'months'),
            'Leavers ' + plural(num('health_leaver_months'), 'month', 'months')]) }]]]);
    var lead = num('lead_followup_hours'), prop = num('proposal_followup_days');
    add('clients', 'Clients', 'clients', [
      ['Clients', [
        biz && { id: 'industries', name: 'Industries', kind: 'open', meta: line('industries'), open: openInd },
        biz && { id: 'followup', name: 'Follow-up limits', kind: 'edit',
          meta: lead == null ? '' : parts(['Lead ' + plural(lead, 'hour', 'hours'), 'Proposal ' + plural(prop, 'day', 'days'),
            num('vic_lead_followup_hours') == null ? '' : 'VIC ' + plural(num('vic_lead_followup_hours'), 'hour', 'hours') + ' and ' + plural(num('vic_proposal_followup_days'), 'day', 'days')].filter(Boolean)) },
        /* Its days open a supplier's link too (2026-10-22, SET2-2). */
        biz && { id: 'details', name: 'Details forms', kind: 'edit',
          meta: num('details_form_days') == null ? '' : 'Client and supplier links open ' + plural(num('details_form_days'), 'day', 'days').replace(' ', ' ') },
        /* The month Analytics counts leads and clients from (2026-10-25). */
        biz && { id: 'analytics', name: 'Analytics', kind: 'edit',
          meta: num('analytics_from') == null ? '' : parts(['Counts from ' + bridge.monthOfSetting(num('analytics_from'))]
            .concat(num('analytics_churn_pct') == null ? [] : ['Churn alert ' + num('analytics_churn_pct') + '% a quarter'])) }]],
      ['Creators', [
        /* Creator and campaign IDs and the Job reference (2026-11-08). */
        biz && { id: 'ids', name: 'Creator and campaign IDs', kind: 'edit', meta: line('ids'), open: function () { openIds(); } },
        /* When a creator is paid after their post (2026-11-09). */
        biz && { id: 'creatorpay', name: 'Creator payments', kind: 'edit',
          meta: num('creator_pay_days_myr') == null ? '' : parts(['MYR ' + plural(num('creator_pay_days_myr'), 'working day', 'working days'),
            'Other currencies ' + plural(num('creator_pay_days_other'), 'working day', 'working days')]) },
        biz && { id: 'crsheet', name: 'Creator payments sheet', kind: 'edit', meta: line('crsheet'), open: function () { openCrSheet(); } }]]]);
    var rep = num('report_due_days'), rev = num('revision_due_days');
    add('work', 'My Work', 'ops', [['', [
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
      may('ops.numbering') && { id: 'numbering', name: 'Task numbering', kind: 'edit', meta: line('numbering'),
        open: function () { if (W.ADspaceOps && W.ADspaceOps.openNumbering) W.ADspaceOps.openNumbering(rowSay('numbering')); } }]]]);
    var meta = num('meta_checks') === 1;
    add('reports', 'Reports', 'reports', [['', [
      biz && { id: 'meta', name: 'Meta checks', kind: 'switch', on: meta,
        meta: meta ? 'On · Import from Meta, Report audit' : 'Off', open: flipMeta },
      /* Report posts linked to their My Work tasks (2026-11-06). */
      biz && { id: 'postlinks', name: 'Posts linked to tasks', kind: 'switch', on: num('report_post_links') === 1,
        meta: num('report_post_links') === 1 ? 'On · Accounts Reports' : 'Off',
        open: function (btn) { flipOwn(btn, 'postlinks', 'report_links_set', 'Posts linked to tasks'); } },
      biz && { id: 'reach', name: 'Reach allowance', kind: 'edit',
        meta: num('reach_allowance_pct') == null ? '' : 'Within ' + num('reach_allowance_pct') + '% of Meta' },
      biz && { id: 'bench', name: 'Ad benchmarks', kind: 'edit',
        meta: num('bench_msg_target') == null ? '' : parts(['Messaging RM ' + num('bench_msg_target'), 'Lead form RM ' + num('bench_form_target')]) }]]]);
    var pin = num('ai_price_in'), pout = num('ai_price_out');
    add('money', 'Money', 'services', [['', [
      biz && { id: 'tax', name: 'Tax and terms', kind: 'edit',
        meta: num('sst_pct') == null ? '' : parts(['SST ' + num('sst_pct') + '%'].concat(num('quote_valid_days') == null ? [] : ['Quotation ' + plural(num('quote_valid_days'), 'day', 'days')])) },
      biz && { id: 'taxcodes', name: 'Tax codes', kind: 'open', meta: line('taxcodes'), open: openTax },
      biz && W.ADspaceBukku && { id: 'bukku', name: 'Bukku', kind: 'edit', meta: line('bukku'),
        open: function (btn) { W.ADspaceBukku.openConfig(btn, rowSay('bukku')); } }]]]);
    add('ai', 'AI', 'ai', [['', [
      may('reports.ai') && { id: 'aiuse', name: 'AI usage and limits', kind: 'open', meta: line('aiuse'),
        open: function (btn) { if (W.ADspaceReports && W.ADspaceReports.aiUsage) W.ADspaceReports.aiUsage(btn); } },
      biz && { id: 'prices', name: 'AI prices', kind: 'edit',
        meta: pin == null ? '' : parts(['US$ ' + pin + ' in', 'US$ ' + pout + ' out per million tokens']) }]]]);
    /* Messages (the overnight review, 2026-11-10): what the portal sends
       and how, by channel, as the Messages section is (Email, WhatsApp). */
    var rep2 = num('wa_repeat_hours'), qwa = num('quote_wa_day');
    add('messages', 'Messages', 'whatsapp', [
      ['Email', [
        /* Send by email (2026-10-31): whether a quotation, a Letter of Offer
           and a client letter offer it at all. */
        biz && W.ADspaceDocMail && { id: 'clientmailon', name: 'Send by email', kind: 'switch', on: num('client_email_on') === 1,
          meta: num('client_email_on') === 1 ? 'On · Quotations and letters' : 'Off', open: flipMail },
        /* Every email's wording, by recipient, in one editor (2026-11-10). */
        (biz || full('suppliers')) && W.ADspaceMailTpl && { id: 'mailtpl', name: 'Email templates', kind: 'open', meta: line('mailtpl'),
          open: function (btn) { W.ADspaceMailTpl.open(btn, rowSay('mailtpl')); } },
        /* Sent again (2026-10-14): the same message sent within the window
           asks again before it goes, WhatsApp and emails alike (SET2-1). */
        biz && { id: 'resend', name: 'Sent again', kind: 'edit',
          meta: rep2 == null ? '' : rep2 === 0 ? 'Off' : parts(['WhatsApp and emails', 'Within ' + plural(rep2, 'hour', 'hours')]) }]],
      ['WhatsApp', [
        W.ADspaceWhatsApp && full('whatsapp') && { id: 'whatsapp', name: 'WhatsApp templates', kind: 'open', meta: line('whatsapp'),
          open: function (btn) { W.ADspaceWhatsApp.manage(btn); } },
        /* The content meeting's message to the client, copied from a month's
           card (2026-10-29). */
        biz && W.ADspaceOps && { id: 'meetmsg', name: 'Meeting message', kind: 'edit', meta: line('meetmsg'),
          open: function (btn) { if (W.ADspaceOps.openMeetMessage) W.ADspaceOps.openMeetMessage(btn, rowSay('meetmsg')); } },
        /* Website quotations (2026-10-29): how many a day are sent on
           WhatsApp, each a message ADspace pays for. */
        biz && { id: 'quotewa', name: 'Website quotations', kind: 'edit',
          meta: qwa == null ? '' : qwa === 0 ? 'Not sent on WhatsApp' : 'Up to ' + plural(qwa, 'quotation', 'quotations') + ' a day on WhatsApp' }]]]);
    /* Performance (the user, 2026-10-29: "approve all"): one row a view,
       each opening the one sheet on its part behind the master code. */
    add('performance', 'Performance', 'mine', [['', perfMay() ? W.ADspacePerf.VIEWS.map(function (v) {
      return { id: 'perf-' + v[0], name: v[1], kind: 'open', meta: PERF_META[v[0]],
        open: function (btn) { W.ADspacePerf.openSettings(v[0], btn); } };
    }) : []]]);
    /* Templates: the wording that is no message (the overnight review,
       2026-11-10: the emails and WhatsApp went to Messages). */
    add('templates', 'Templates', 'register', [['', [
      may('register.types') && { id: 'types', name: 'Document types', kind: 'open', meta: line('types'),
        open: function (btn) { if (W.ADspaceRegister && W.ADspaceRegister.openTypes) W.ADspaceRegister.openTypes(btn); } },
      W.ADspaceOps && may('ops.workflows') && { id: 'tasktpl', name: 'Task templates', kind: 'open', meta: line('tasktpl'),
        open: function (btn) { if (W.ADspaceOps.openTemplates) W.ADspaceOps.openTemplates(btn); } },
      W.ADspaceCRM && W.ADspaceCRM.openWording && full('services') && { id: 'wording', name: 'Rate card wording', kind: 'open', meta: line('wording'),
        open: function (btn) { W.ADspaceCRM.openWording(btn); } }]]]);
    return out;
  }

  /* What each Performance part holds, as its sheet heads them. */
  var PERF_META = { months: 'Grades, issue points, queries, reminders', quarters: 'Prizes, flexible hours',
    company: 'Bonus pool, company trip, shares', commission: 'Score needed' };
  var reread = '';
  /* What a press said, kept on its row through a repaint (audit SET-2). */
  var said = null;
  function rowSay(id) {
    return function (text, tone) { said = text ? { row: id, text: text, tone: tone || '' } : null; paint(); };
  }
  /* A switch acts at the press and offers its way back where it happened
     (the overnight review, 2026-11-10). */
  function undoSwitch(id, text, on) {
    var row = document.querySelector('#setList .stg-row[data-row="' + id + '"]');
    if (!row || !bridge.undoHere) return;
    bridge.undoHere(text, function () {
      var sw = document.querySelector('#setList .stg-row[data-row="' + id + '"] [role="switch"]');
      if (sw && (sw.getAttribute('aria-checked') === 'true') === on) sw.click();
    }, row.closest('.stg-card'));
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

  /* One group at a time (the user, 2026-10-24: "the business settings are
     getting longer … categorize or structure it into a proper settings
     page", one group at a time chosen over folds): at a desk the groups run
     down the left and a press shows that group's card alone; on a phone
     the strip does the same, a sideways swipe moving along it. Still one
     press from Settings to a row and one to its sheet, never a drill-down
     (refused 2026-10-11: "It now takes five layers"). The group shown is
     in the address (`tab=`, the first left out), so a refresh lands on
     it. */
  var phoneMedia = window.matchMedia && window.ADSPACE_TABBAR ? window.matchMedia(window.ADSPACE_TABBAR) : null;
  function phone() { return Boolean(phoneMedia && phoneMedia.matches); }
  var chosen = '';
  function fromUrl() { chosen = new URLSearchParams(location.search).get('tab') || ''; }

  function current(list) {
    return list.some(function (x) { return x.key === chosen; }) ? chosen : (list[0] ? list[0].key : '');
  }
  /* A group's mark: its section's rail glyph, the AI's spark for AI. */
  function glyphOf(g) {
    if (g.glyph === 'ai') return window.ADspaceConfirm && window.ADspaceConfirm.ai && window.ADspaceConfirm.ai.glyph ? window.ADspaceConfirm.ai.glyph : '';
    return bridge.glyph ? bridge.glyph(g.glyph) : (window.ADspaceAdmin && window.ADspaceAdmin.glyph ? window.ADspaceAdmin.glyph(g.glyph) : '');
  }
  function sec(g, on) {
    return '<section class="stg-sec" id="stg-' + g.key + '" data-sec="' + g.key + '" aria-labelledby="stgT-' + g.key + '"' + (on ? '' : ' hidden') + '>' +
      '<h3 class="stg-title" id="stgT-' + g.key + '">' + esc(g.name) + '</h3>' +
      g.secs.map(function (x) {
        return '<div class="stg-part">' + (x.name ? '<h4 class="stg-part-h">' + esc(x.name) + '</h4>' : '') +
          '<div class="stg-card">' + x.rows.map(rowHtml).join('') + '</div></div>';
      }).join('') + '</section>';
  }
  /* What a search finds (the overnight review, 2026-11-10): a row by its
     name, its group's or its value, across every group; the group list
     steps aside while it holds words. */
  var query = '';
  function norm(t) { return String(t || '').toLowerCase().replace(/\s+/g, ' ').trim(); }
  function hits(list) {
    var q = norm(query).split(' ').filter(Boolean), out = [];
    list.forEach(function (g) {
      g.rows.forEach(function (r) {
        var hay = norm([r.name, g.name, r.meta === ' ' ? '' : r.meta, lines[r.id] || ''].join(' '));
        if (q.every(function (w) { return hay.indexOf(w) >= 0; })) out.push({ g: g, r: r });
      });
    });
    return out;
  }
  function found(list) {
    var h = hits(list);
    if (!h.length) return '<p class="emptyline stg-none">No matching settings.</p>';
    return '<div class="stg-card stg-found">' + h.map(function (x) {
      return '<button class="stg-hit" type="button" data-hit="' + x.r.id + '" data-hg="' + x.g.key + '">' +
        '<span class="stg-hit-g" aria-hidden="true">' + glyphOf(x.g) + '</span>' +
        '<span class="stg-what"><span class="stg-name">' + esc(x.r.name) + '</span><span class="stg-meta">' + esc(x.g.name) + '</span></span>' +
        CHEV + '</button>';
    }).join('') + '</div>';
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
    /* On a phone the groups are the view strip, sticky under the head,
       scrolling sideways; a press scrolls to the group as the desk's list
       does (the user, 2026-10-22, SET2-17: "approve"; never a drill-down,
       refused 2026-10-11). */
    var strip = phone() && list.length >= 3;
    var cls = 'stg ' + (desk ? 'is-desk' : phone() ? 'is-phone' : 'is-single');
    var find = '<div class="stg-find"><label class="sr" for="stgFind">Search settings</label>' +
      '<input class="input" type="search" id="stgFind" placeholder="Search" autocomplete="off" value="' + esc(query) + '"></div>';
    var html = (desk ? '<nav class="stg-nav" aria-label="Settings">' + find + list.map(function (x) {
      return '<button class="stg-go" type="button" data-g="' + x.key + '" aria-controls="stg-' + x.key + '">' +
        '<span class="stg-go-g" aria-hidden="true">' + glyphOf(x) + '</span>' + esc(x.name) + '</button>';
    }).join('') + '</nav>' : '') +
      (strip && !query ? '<div class="actstrip stg-strip"><span class="cmdbar-views actviews" id="stgStrip" role="group" aria-label="Settings">' + list.map(function (x) {
        return '<button class="acttab btn-sm stg-tab" type="button" data-g="' + x.key + '" aria-controls="stg-' + x.key + '" aria-pressed="false">' + esc(x.name) + '</button>';
      }).join('') + '</span></div>' : '') +
      /* On a phone the strip stands where every section's does, the
         search under it (2026-11-10, cmdbar). */
      (!desk ? find : '') +
      (query ? '<div class="stg-groups">' + found(list) + '</div>' :
      '<div class="stg-groups"' + (strip ? ' data-swipe="stgStrip"' : '') + '>' + list.map(function (g) {
        /* With fewer than three groups there is nothing to move between,
           and every group shows (2026-10-14, SET-5). */
        return sec(g, !(desk || strip) || g.key === current(list));
      }).join('') + '</div>');
    if (html !== drawn || box.className !== cls || !box.firstChild) {
      var had = document.activeElement && box.contains(document.activeElement) ? document.activeElement.getAttribute('data-a') : '';
      drawn = html;
      box.className = cls;
      box.innerHTML = html;
      var back = had && box.querySelector('[data-a="' + had + '"]');
      if (back) back.focus({ preventScroll: true });
      if ($('stgStrip') && window.ADspaceForm && window.ADspaceForm.thumb) window.ADspaceForm.thumb($('stgStrip'));
      if (window.ADspaceGuide && window.ADspaceGuide.relay) window.ADspaceGuide.relay();
    }
    mark();
  }

  /* The group shown wears the list's fill; never more than one. */
  function mark() {
    var box = $('setList');
    if (!box) return;
    var key = current(groups());
    Array.prototype.forEach.call(box.querySelectorAll('.stg-go'), function (b) {
      if (b.getAttribute('data-g') === key) b.setAttribute('aria-current', 'true'); else b.removeAttribute('aria-current');
    });
    /* The strip's chosen tab, its thumb sliding to it. */
    Array.prototype.forEach.call(box.querySelectorAll('.stg-tab'), function (b) {
      var on = b.getAttribute('data-g') === key;
      if (b.classList.contains('is-on') === on) return;
      b.classList.toggle('is-on', on);
      b.setAttribute('aria-pressed', String(on));
    });
  }
  function shown() { var s = $('sectionSettings'); return s && !s.hidden; }

  function urlState() {
    var list = groups();
    if (!chosen || !list.some(function (x) { return x.key === chosen; }) || list[0].key === chosen) return {};
    return { tab: chosen };
  }

  /* A group pressed is shown alone, the page at its top. */
  function go(key) {
    chosen = key;
    say('');
    var box = $('setList');
    if (box) Array.prototype.forEach.call(box.querySelectorAll('.stg-sec'), function (x) {
      x.hidden = box.classList.contains('is-single') ? false : x.getAttribute('data-sec') !== key;
    });
    mark();
    window.scrollTo(0, 0);
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
    var day = window.ADspaceClock.today();
    sw.setAttribute('aria-checked', to ? 'true' : 'false');
    sw.disabled = true;
    db.rpc('app_settings_set', { p_from: day, p_values: { meta_checks: to ? 1 : 0 } }).then(function (r) {
      var d = r.data || {};
      if (r.error || d.error) {
        throw new Error(r.error ? (/function|schema cache/i.test(r.error.message) ? window.ADspaceWords.line.notYet : r.error.message)
          : d.error === 'denied' ? window.ADspaceWords.line.noSettings : d.error === 'bad-value' ? window.ADspaceWords.line.notYet : d.error);
      }
      /* Saved: a failed read of the figures afterwards keeps the switch as
         pressed (the overnight review, 2026-11-10). */
      return window.ADspaceMoney.load(true).catch(function () {});
    }).then(function () {
      said = null; paint();
      undoSwitch('meta', to ? 'Meta checks are on.' : 'Meta checks are off.', to);
    }).catch(function (e) {
      sw.setAttribute('aria-checked', to ? 'false' : 'true');
      sw.disabled = false;
      rowSay('meta')(String((e && e.message) || e), 'err');
    });
  }

  /* Send by email (2026-10-31): on or off from today through its own
     function, saved at the press and put back on a refusal. */
  function flipMail(sw) { flipOwn(sw, 'clientmailon', 'client_email_set', 'Send by email'); }
  function flipOwn(sw, id, fn, word) {
    var to = sw.getAttribute('aria-checked') !== 'true';
    sw.setAttribute('aria-checked', to ? 'true' : 'false');
    sw.disabled = true;
    db.rpc(fn, { p_on: to }).then(function (r) {
      var d = r.data || {};
      if (r.error || d.error) {
        throw new Error(r.error ? (/function|schema cache/i.test(r.error.message) ? window.ADspaceWords.line.notYet : r.error.message)
          : d.error === 'denied' ? window.ADspaceWords.line.noSettings : d.error);
      }
      /* Saved: a failed read of the figures afterwards keeps the switch as
         pressed (the overnight review, 2026-11-10). */
      return window.ADspaceMoney.load(true).catch(function () {});
    }).then(function () {
      said = null; paint();
      undoSwitch(id, word + (to ? ' is on.' : ' is off.'), to);
    }).catch(function (e) {
      sw.setAttribute('aria-checked', to ? 'false' : 'true');
      sw.disabled = false;
      rowSay(id)(String((e && e.message) || e), 'err');
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
      bridge.editSettings({ title: sp.title, keys: sp.keys.map(function (k) { return [k[0], k[1], k[2], k[3], k[4], k[5]]; }), msg: rowSay(a), done: paint }, btn);
      return;
    }
    var row = rowOf(a);
    if (row && row.open) row.open(btn);
  }
  function rowOf(id) {
    var hit = null;
    groups().forEach(function (g) { g.rows.forEach(function (r) { if (r.id === id) hit = r; }); });
    return hit;
  }

  /* ---- Demo access (2026-10-27) ----------------------------------------
     One sheet: On or Off, and a new PIN (4 to 8 digits; empty keeps the
     one held). The PIN is never read back: the database keeps its hash. */
  var DEMO_SAID = { denied: window.ADspaceWords.line.noSettings, 'bad-pin': 'Enter a PIN of 4 to 8 digits.',
    'no-pin': 'Set a PIN before turning demo access on.' };
  function openDemo() {
    db.rpc('demo_state').then(function (r) {
      var d = (r && r.data) || {};
      if (r.error || d.error) { rowSay('demo')(r.error ? (/function|schema cache/i.test(r.error.message) ? window.ADspaceWords.line.notYet : r.error.message) : DEMO_SAID[d.error] || d.error, 'err'); return; }
      window.ADspaceConfirm.ask({
        title: 'Demo access', go: 'Save', wait: true,
        fields: [{ name: 'on', label: 'Demo access', seg: true, value: d.on ? 'on' : 'off', choices: [['on', 'On'], ['off', 'Off']] },
          { name: 'pin', label: d.pin_set ? 'New PIN' : 'PIN', type: 'tel', required: !d.pin_set, placeholder: '4 to 8 digits', value: '',
            note: d.pin_set ? 'Leave blank to keep the current PIN. Enter it in the sign-in email field to open the console with sample data.'
              : 'Enter it in the sign-in email field to open the console with sample data.' }],
        check: function (v) {
          var pin = String(v.pin || '').trim();
          if (pin && !/^[0-9]{4,8}$/.test(pin)) return DEMO_SAID['bad-pin'];
          if (v.on === 'on' && !pin && !d.pin_set) return DEMO_SAID['no-pin'];
          return '';
        }
      }, function (v) {
        return db.rpc('demo_set', { p_on: v.on === 'on', p_pin: String(v.pin || '').trim() || null }).then(function (r2) {
          var e = r2.error ? (/function|schema cache/i.test(r2.error.message) ? window.ADspaceWords.line.notYet : r2.error.message)
            : r2.data && r2.data.error ? DEMO_SAID[r2.data.error] || r2.data.error : '';
          if (e) return e;
          var n = r2.data || {};
          fillLine('demo', n.on ? 'On · PIN set' : n.pin_set ? 'Off · PIN set' : 'Off');
          rowSay('demo')('Saved.', 'ok');
          return '';
        }).catch(function (e) { return (e && e.message) || 'Not saved.'; });
      });
    }).catch(function () { rowSay('demo')('Could not load.', 'err'); });
  }

  /* ---- Creator and campaign IDs (2026-11-08) ---------------------------
     Each kind's prefix, digits and next number, and the Job reference's
     shape; a change applies to the next one made. */
  function idNext(f) {
    var n = String(f.next || 1);
    while (n.length < Number(f.width || 0)) n = '0' + n;
    return f.prefix + n;
  }
  var IDS_SAID = { denied: window.ADspaceWords.line.noSettings,
    'bad-prefix': 'Enter a prefix of 1 to 6 capital letters.', 'bad-width': 'Choose 2 to 6 digits.',
    'bad-next': 'Enter a next number of 1 or more.', 'bad-pattern': 'Enter a job reference of up to 40 characters that includes {creator} and {campaign}.',
    'bad-request-pattern': 'Enter a payment details reference of up to 40 characters that includes {creator} and {nnn}.' };
  /* ---- Creator payments sheet (2026-11-09) ----------------------------------
     Whether approved payment details are added as a row, the spreadsheet's
     link and its tab; after a save the sheet's headers are read and the
     row says how many take a value. */
  var CS_SAID = { denied: window.ADspaceWords.line.noSettings,
    'bad-sheet': 'Enter the Google Sheets link or ID.', 'bad-tab': 'Enter a tab name of up to 100 characters.',
    'no-sheet': 'Enter the Google Sheets link or ID.',
    'google-not-set-up': 'Google Sheets is not connected yet. Please contact an admin.',
    'google-refused': 'Google could not open the sheet. Share it with the ADspace Google account, then try again.',
    'needs-update': window.ADspaceWords.line.notYet };
  function checkCrSheet() {
    return db.functions.invoke('creator-mail', { body: { action: 'check' } }).then(function (r) {
      return window.ADspaceAPI.fnRefusal(r).then(function (code) {
        var d = code ? { error: code } : (r.data || {});
        if (d.error) { rowSay('crsheet')(CS_SAID[d.error] || 'The sheet could not be read. Check the link and that the sheet is shared with the ADspace Google account.', 'err'); return; }
        var cols = d.columns || [], used = cols.filter(function (c) { return c.value; }).length;
        rowSay('crsheet')(used ? 'Saved. ' + used + ' of ' + plural(cols.length, 'column', 'columns') + ' in ' + d.tab + ' will be filled.'
          : 'Saved. No column in ' + d.tab + ' matches a payment detail. Rename the headers to match, then save again.', used ? 'ok' : 'err');
      });
    }).catch(function () { rowSay('crsheet')('Saved. The sheet could not be read. Check the link and the tab name.', 'err'); });
  }
  function openCrSheet() {
    db.rpc('creator_sheet_get').then(function (r) {
      var d = r.data || {};
      if (r.error || d.error) {
        rowSay('crsheet')(r.error && /function|schema cache/i.test(r.error.message) ? CS_SAID['needs-update'] : (CS_SAID[d.error] || 'Could not load.'), 'err');
        return;
      }
      window.ADspaceConfirm.ask({
        title: 'Creator payments sheet', go: 'Save', wait: true,
        fields: [
          { name: 'on', label: 'Add a row when payment details are approved', tick: true, value: d.on ? 'on' : '' },
          { name: 'sheet', label: 'Google Sheets link', value: d.spreadsheet_id ? 'https://docs.google.com/spreadsheets/d/' + d.spreadsheet_id : '', required: false },
          { name: 'tab', label: 'Tab', value: d.tab || '', required: false, note: 'Leave empty for the first tab.' }
        ]
      }, function (v) {
        return db.rpc('creator_sheet_set', { p_on: v.on === 'on', p_sheet: String(v.sheet || '').trim() || null, p_tab: String(v.tab || '').trim() || null }).then(function (r2) {
          if (r2.error) return /function|schema cache/i.test(r2.error.message) ? CS_SAID['needs-update'] : r2.error.message;
          var e = (r2.data || {}).error;
          if (e) return CS_SAID[e] || 'Not saved.';
          readLine('crsheet');
          if (v.on === 'on') checkCrSheet(); else rowSay('crsheet')('Saved.', 'ok');
          return '';
        }).catch(function (e) { return (e && e.message) || 'Not saved.'; });
      });
    }).catch(function () { rowSay('crsheet')('Could not load.', 'err'); });
  }

  /* A payment details reference as the database writes it (creator_pay_ref). */
  function payRefOf(pat, codeWord, n) {
    var run = (String(pat).match(/\{(n+)\}/) || [])[1], out = String(pat).replace('{creator}', codeWord);
    if (!run) return out + n;
    var num = String(n);
    while (num.length < run.length) num = '0' + num;
    return out.replace('{' + run + '}', num);
  }
  var IDS_WORD = { creator: 'Creator ID', campaign: 'Campaign ID', job: 'Job reference' };
  function openIds() {
    db.rpc('id_formats_list').then(function (r) {
      var list = (r && r.data) || [];
      if (r.error || !Array.isArray(list) || !list.length) {
        rowSay('ids')(r.error && /function|schema cache/i.test(r.error.message) ? window.ADspaceWords.line.notYet : 'Could not load.', 'err');
        return;
      }
      var by = {};
      list.forEach(function (f) { by[f.kind] = f; });
      var fields = [];
      [['creator', 'Creator ID'], ['campaign', 'Campaign ID']].forEach(function (k) {
        var f = by[k[0]] || {};
        fields.push({ name: k[0] + '_prefix', label: 'Prefix', head: k[1], third: true, value: f.prefix || '', required: true });
        fields.push({ name: k[0] + '_width', label: 'Digits', third: true, value: String(f.width || ''), required: true });
        fields.push({ name: k[0] + '_next', label: 'Next number', third: true, value: String(f.next || ''), required: true });
      });
      fields.push({ name: 'job', label: 'Pattern', head: 'Job reference', value: (by.job || {}).pattern || '', required: true,
        note: 'A booking reads, for example, ' + ((by.job || {}).pattern || '').replace('{creator}', idNext(by.creator || {})).replace('{campaign}', idNext(by.campaign || {})) + '.' });
      /* A creator's payment details reference (2026-11-08): its Creator ID
         and a run of n for the number, held on the creator's row. */
      var payPat = (by.creator || {}).pattern || '{creator}/R{nnn}';
      fields.push({ name: 'payref', label: 'Pattern', head: 'Payment details reference', value: payPat, required: true,
        note: 'A creator\'s first set of details reads, for example, ' + payRefOf(payPat, idNext(by.creator || {}), 1) + '.' });
      window.ADspaceConfirm.ask({
        title: 'Creator and campaign IDs', go: 'Save', wait: true, fields: fields,
        check: function (v) {
          var bad = '';
          ['creator', 'campaign'].forEach(function (k) {
            if (bad) return;
            if (!/^[A-Za-z]{1,6}$/.test(String(v[k + '_prefix'] || '').trim())) bad = IDS_SAID['bad-prefix'];
            else if (!/^[2-6]$/.test(String(v[k + '_width'] || '').trim())) bad = IDS_SAID['bad-width'];
            else if (!/^[1-9]\d{0,8}$/.test(String(v[k + '_next'] || '').trim())) bad = IDS_SAID['bad-next'];
          });
          var j = String(v.job || '').trim();
          if (!bad && (j.length > 40 || j.indexOf('{creator}') < 0 || j.indexOf('{campaign}') < 0)) bad = IDS_SAID['bad-pattern'];
          var pr = String(v.payref || '').trim();
          if (!bad && (pr.length > 40 || pr.indexOf('{creator}') < 0 || !/\{n{1,6}\}/.test(pr))) bad = IDS_SAID['bad-request-pattern'];
          return bad;
        }
      }, function (v) {
        var steps = ['creator', 'campaign', 'job'].filter(function (k) {
          var f = by[k] || {};
          if (k === 'job') return String(v.job || '').trim() !== (f.pattern || '');
          return String(v[k + '_prefix']).trim().toUpperCase() !== f.prefix || Number(v[k + '_width']) !== Number(f.width) || Number(v[k + '_next']) !== Number(f.next) ||
            (k === 'creator' && String(v.payref || '').trim() !== (f.pattern || '{creator}/R{nnn}'));
        });
        function one(i) {
          if (i >= steps.length) return Promise.resolve('');
          var k = steps[i];
          return db.rpc('id_format_set', k === 'job'
            ? { p_kind: 'job', p_prefix: null, p_width: null, p_next: null, p_pattern: String(v.job || '').trim() }
            : { p_kind: k, p_prefix: String(v[k + '_prefix']).trim().toUpperCase(), p_width: Number(v[k + '_width']),
                p_next: Number(v[k + '_next']), p_pattern: k === 'creator' ? String(v.payref || '').trim() : null }).then(function (r2) {
            if (r2.error) return /function|schema cache/i.test(r2.error.message) ? window.ADspaceWords.line.notYet : r2.error.message;
            var d = r2.data || {};
            if (d.error === 'bad-next' && d.top != null) {
              return idNext({ prefix: String(v[k + '_prefix']).trim().toUpperCase(), width: Number(v[k + '_width']), next: d.top }) +
                ' is already used. Enter a next number above ' + d.top + '.';
            }
            if (d.error) {
              /* What saved before the refusal is said, and its line read again
                 (the overnight review, 2026-11-10). */
              var done = steps.slice(0, i).map(function (x) { return IDS_WORD[x]; });
              if (done.length) readLine('ids');
              return (IDS_SAID[d.error] || IDS_WORD[k] + ' not saved.') + (done.length ? ' ' + done.join(' and ') + ' saved.' : '');
            }
            return one(i + 1);
          });
        }
        return one(0).then(function (e) {
          if (e) return e;
          readLine('ids');
          rowSay('ids')(steps.length ? 'Saved.' : 'No change.', 'ok');
          return '';
        }).catch(function (e) { return (e && e.message) || 'Not saved.'; });
      });
    }).catch(function () { rowSay('ids')('Could not load.', 'err'); });
  }

  /* ---- Public holidays (2026-10-14) ------------------------------------
     The days the office is closed: the front door draws them Closed and My
     Work marks them. Read for this year and the next in one request; the
     row says the next one, the sheet lists a year at a time. */
  var hol = { rows: null, err: null, year: null };
  var HOL_SAID = {
    taken: 'A holiday is already set on this date.', 'bad-name': 'Enter a name of 2 to 80 characters.',
    'bad-day': 'Choose a date from 14 Aug 2023 to 31 Dec 2099.', 'not-found': 'This holiday no longer exists.',
    denied: window.ADspaceWords.line.noSettings
  };
  function holSaid(r) {
    var e = r && (r.error || (r.data && r.data.error));
    if (!e) return '';
    if (e.message) return /function|schema cache/i.test(e.message) ? window.ADspaceWords.line.notYet : e.message;
    return e === 'taken' && r.data.name ? r.data.name + ' is already set on this date.' : HOL_SAID[e] || 'Not saved.';
  }
  function holToday() { return window.ADspaceClock.today(); }
  function holDay(d, withDow) { return window.ADspaceClock.date(d, { weekday: Boolean(withDow) }); }
  function holMeta() {
    /* Its line's room is kept while the read is out, so nothing below moves
       when it arrives. */
    if (!hol.rows) return hol.err ? 'Could not load.' : '\u00a0';
    var t = holToday(), next = hol.rows.filter(function (h) { return h.day >= t; })[0];
    return next ? 'Next ' + next.name + ', ' + holDay(next.day) : 'No holidays listed ahead';
  }
  function holLine() { var meta = holMeta(); if (meta) fillLine('holidays', meta); }
  function readHol(done) {
    var y = Number(holToday().slice(0, 4));
    db.rpc('public_holidays_between', { p_from: y + '-01-01', p_to: (y + 1) + '-12-31' }).then(function (r) {
      if (r.error) throw r.error;
      hol.rows = r.data || []; hol.err = null;
    }).catch(function (e) { hol.rows = null; hol.err = e; }).then(function () { if (done) done(); });
  }
  function holSpan() {
    var y = Number(holToday().slice(0, 4));
    return ' min="' + y + '-01-01" max="' + (y + 1) + '-12-31"';
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
    /* One table, as Industries (revamp A, 2026-11-04): Date · Holiday · the
       pen; the pen opens its row in place, Delete among Cancel and Save;
       the last row adds one. */
    var body = rows.map(function (h) {
      if (h.day === hol.editing) {
        return '<div class="ind-row is-hol is-edit" data-day="' + esc(h.day) + '">' +
          '<input class="input input-sm" type="date" id="holEdDay" aria-label="Date"' + holSpan() + ' value="' + esc(h.day) + '">' +
          '<input class="input input-sm" id="holEdName" maxlength="80" aria-label="Holiday" value="' + esc(h.name) + '">' +
          '<span class="ind-acts"><button class="btn btn-danger btn-sm" type="button" data-h="delete">Delete</button>' +
            '<button class="btn btn-quiet btn-sm" type="button" data-h="cancel">Cancel</button>' +
            '<button class="btn btn-primary btn-sm" type="button" data-h="save">Save</button></span></div>';
      }
      return '<div class="ind-row is-hol' + (h.day < t ? ' is-past' : '') + '" data-day="' + esc(h.day) + '">' +
        '<span class="ind-zh hol-date">' + esc(holDay(h.day, true)) + '</span>' +
        '<span class="ind-name">' + esc(h.name) + '</span>' +
        '<span class="ind-acts"><button class="iconbtn" type="button" data-h="edit" aria-label="Edit ' + esc(h.name) + '" title="Edit">' + PEN + '</button></span></div>';
    }).join('');
    var firstDay = String(hol.year) === t.slice(0, 4) ? t : hol.year + '-01-01';
    box.innerHTML = (rows.length ? '<div class="ind-row ind-head is-hol" aria-hidden="true"><span>Date</span><span>Holiday</span><span></span></div>' + body
        : '<div class="hol-none"></div>') +
      '<div class="ind-row is-hol ind-add">' +
        '<input class="input input-sm" type="date" id="holNewDay" aria-label="New holiday\'s date"' + holSpan() + ' value="' + esc(firstDay) + '">' +
        '<input class="input input-sm" id="holNewName" maxlength="80" placeholder="Deepavali" aria-label="New holiday">' +
        '<span class="ind-acts"><button class="btn btn-sm" type="button" data-h="add">' + PLUS + 'Add</button></span></div>';
    if (!rows.length) window.ADspaceState.emptyLine(box.querySelector('.hol-none'), 'No holidays.');
    if (window.ADspaceForm && window.ADspaceForm.scan) window.ADspaceForm.scan(box);
    if (hol.editing) { var f = $('holEdName'); if (f) f.focus(); }
  }
  /* A holiday saved from its row or the add row. */
  function holSave(was) {
    var dayF = $(was ? 'holEdDay' : 'holNewDay'), nameF = $(was ? 'holEdName' : 'holNewName');
    var day = String(dayF.value || ''), name = String(nameF.value || '').replace(/\s+/g, ' ').trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) { holMsg('Choose a date.'); dayF.focus(); return; }
    /* The list reads this year and next: a day outside them would save and
       then be out of reach (the overnight review, 2026-11-10). */
    var y = Number(holToday().slice(0, 4));
    if (day < y + '-01-01' || day > (y + 1) + '-12-31') { holMsg('Choose a date in ' + y + ' or ' + (y + 1) + '.'); dayF.focus(); return; }
    if (!name) { holMsg('Enter the holiday\'s name.'); nameF.focus(); return; }
    var btn = $('holList').querySelector(was ? '.is-edit [data-h="save"]' : '[data-h="add"]');
    if (btn && btn.disabled) return;
    if (btn) btn.disabled = true;
    db.rpc('public_holiday_save', { p_day: day, p_name: name, p_was: was || null }).then(function (r) {
      var said = holSaid(r);
      if (said) { holMsg(said); if (btn) btn.disabled = false; nameF.focus(); return; }
      hol.year = Number(day.slice(0, 4)); hol.editing = null;
      readHol(function () {
        paintHol(); paint(); say(''); holMsg(was ? 'Saved.' : 'Added.', 'ok');
        if (!was) { var n = $('holNewName'); if (n) n.focus(); }
      });
    }).catch(function (e) { holMsg((e && e.message) || 'Not saved. Please try again.'); if (btn) btn.disabled = false; });
  }
  /* Shuts a list's ⋯ menus (`#depList`, `#taxList`). */
  function shutMenus(list, k) {
    Array.prototype.forEach.call(document.querySelectorAll(list + ' .kmenu'), function (m) { m.hidden = true; });
    Array.prototype.forEach.call(document.querySelectorAll(list + ' [data-' + k + '="menu"]'), function (b) { b.setAttribute('aria-expanded', 'false'); });
  }
  function holMsg(text, tone) { var m = $('holMsg'); if (!m) return; m.textContent = text || ''; m.className = 'msg' + (text ? ' ' + (tone || 'err') : ''); }
  function holDelete(h) {
    window.ADspaceConfirm.ask({ title: 'Delete this holiday?', body: h.name + ', ' + holDay(h.day) + ', is removed from the list. This cannot be undone.', go: 'Delete', tone: 'danger', wait: true },
      function () {
        return db.rpc('public_holiday_delete', { p_day: h.day }).then(function (r) {
          var said = holSaid(r);
          if (said) return said;
          hol.editing = null;
          return new Promise(function (ok) { readHol(function () { paintHol(); paint(); holMsg('Deleted.', 'ok'); ok(''); }); });
        }).catch(function (e) { return (e && e.message) || 'Not deleted.'; });
      });
  }
  /* ---- Departments (2026-10-23) ------------------------------------------
     The team's departments (the user: "can add more departments?"): a
     colleague's department on Team, and the departments the quarter's
     department prize is worked out across. A department in the prize names
     its five criteria; one nobody is in can be deleted, one somebody is in
     set inactive (offered to nobody, out of the prize). */
  var dep = { rows: null, err: null };
  var DEP_SAID = {
    denied: window.ADspaceWords.line.noSettings, 'bad-name': 'Enter a name of 2 to 40 characters.',
    taken: 'A department with this name already exists.', 'criteria-needed': 'Name its five criteria to put it in the department prize.',
    'bad-criteria': 'Each criterion is 2 to 60 characters, and all five are named.', 'not-found': 'This department was removed in the meantime.'
  };
  function depSaid(r) {
    var d = r && r.data, e = r && (r.error || (d && d.error));
    if (!e) return '';
    if (e.message) return /function|schema cache/i.test(e.message) ? window.ADspaceWords.line.notYet : e.message;
    if (e === 'in-use') return d.members ? plural(d.members, 'colleague is', 'colleagues are') + ' in this department. Move them first, or set it inactive.'
      : 'Performance records name this department. Set it inactive instead.';
    return DEP_SAID[e] || 'Not saved.';
  }
  function depMsg(text, tone) { var m = $('depMsg'); if (!m) return; m.textContent = text || ''; m.className = 'msg' + (text ? ' ' + (tone || 'err') : ''); }
  function readDeps(done) {
    db.rpc('departments_list').then(function (r) {
      if (r.error || (r.data && r.data.error)) throw r.error || new Error(r.data.error);
      dep.rows = r.data || []; dep.err = null;
    }).catch(function (e) { dep.rows = null; dep.err = e; }).then(function () { if (done) done(); });
  }
  /* After a change the list is read again here, by the console's own copy
     (Team, Performance) and on the Settings row. */
  function depChanged(text) {
    return new Promise(function (ok) {
      readDeps(function () {
        paintDeps(); readLine('depts'); depMsg(text, 'ok');
        var A = window.ADspaceAdmin;
        if (A && A.deptsReload) A.deptsReload();
        ok('');
      });
    });
  }
  function paintDeps() {
    var box = $('depList');
    if (!box) return;
    if (dep.err) {
      window.ADspaceState.failLine(box, 'Departments', (dep.err && dep.err.message) || '', function () { readDeps(paintDeps); });
      return;
    }
    if (!dep.rows) { window.ADspaceState.skeleton(box, 3); return; }
    $('depCount').textContent = plural(dep.rows.length, 'department', 'departments');
    if (!dep.rows.length) { box.innerHTML = ''; window.ADspaceState.emptyLine(box, 'No departments.'); return; }
    /* One table, as Industries, Public holidays and Tax codes (the user,
       2026-11-10: "yes"): Department · Colleagues · Prize · Status, then the
       pen and a ⋯; the pen asks in a question, a department's five criteria
       being too many for its row. */
    box.innerHTML = '<div class="ind-row ind-head is-dep" aria-hidden="true"><span>Department</span><span>Colleagues</span><span>Prize</span><span>Status</span><span></span></div>' +
      dep.rows.map(function (d) {
        var n = d.members || 0;
        return '<div class="ind-row is-dep dep-row' + (d.active ? '' : ' is-past') + '" data-key="' + esc(d.key) + '">' +
          '<span class="ind-name dep-name">' + esc(d.name) + '</span>' +
          '<span class="ind-n dep-n">' + n + '<span class="ind-unit"> ' + (n === 1 ? 'colleague' : 'colleagues') + (d.in_prize ? ' · In the department prize' : '') + '</span></span>' +
          '<span class="dep-prize">' + (d.in_prize ? 'Included' : '<span class="ind-none">—</span>') + '</span>' +
          '<span class="dep-on"><span class="chip-state ' + (d.active ? 'is-ok' : 'is-off') + '">' + (d.active ? 'Active' : 'Inactive') + '</span></span>' +
          '<span class="ind-acts"><button class="iconbtn" type="button" data-d="edit" aria-label="Edit ' + esc(d.name) + '" title="Edit">' + PEN + '</button>' +
          '<span class="team-act"><button class="kmenu-btn" type="button" data-d="menu" aria-label="More actions for ' + esc(d.name) + '" aria-expanded="false">' +
            '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/></svg></button>' +
          '<div class="kmenu" data-menu hidden role="menu">' +
            '<button class="kmenu-item" data-g="5" type="button" role="menuitem" data-d="active">' + (d.active ? 'Set inactive' : 'Set active') + '</button>' +
            /* Offered only where it would go through: nobody in it and no
               record naming it (`in_records`, TEAM2-15). */
            (n || d.in_records ? '' : '<button class="kmenu-item is-danger" data-g="6" type="button" role="menuitem" data-d="delete">Delete</button>') +
          '</div></span></span></div>';
      }).join('');
  }
  function depShut() { shutMenus('#depList', 'd'); }
  var CRIT_MAX = [25, 25, 20, 15, 15];
  function depAsk(d) {
    var crit = (d && d.criteria) || [];
    var fields = [{ name: 'name', label: 'Name', value: d ? d.name : '', placeholder: 'Sales', required: true },
      { name: 'prize', label: 'In the department prize', tick: true, value: d && d.in_prize ? 'on' : '' }];
    CRIT_MAX.forEach(function (mx, i) {
      fields.push({ name: 'c' + i, label: 'Criterion ' + (i + 1) + ', out of ' + mx, value: crit[i] || '', required: false,
        head: i === 0 ? 'Department prize criteria' : undefined,
        note: i === 0 ? 'Needed to put the department in the prize.' : undefined });
    });
    window.ADspaceConfirm.ask({
      title: d ? 'Edit department' : 'Add department', go: 'Save', wait: true, fields: fields,
      check: function (v) {
        var named = CRIT_MAX.filter(function (x, i) { return String(v['c' + i] || '').trim(); }).length;
        if (v.prize === 'on' && named < 5) return DEP_SAID['criteria-needed'];
        if (named && named < 5) return 'Name all five criteria, or leave them all empty.';
        return '';
      }
    }, function (v) {
      var cr = CRIT_MAX.map(function (x, i) { return String(v['c' + i] || '').trim(); });
      return db.rpc('department_save', { p_key: d ? d.key : null, p_name: v.name, p_in_prize: v.prize === 'on',
        p_criteria: cr.every(function (c) { return !c; }) ? null : cr }).then(function (r) {
        return depSaid(r) || depChanged('Saved.');
      }).catch(function (e) { return (e && e.message) || 'Not saved.'; });
    });
  }
  function depActive(d) {
    db.rpc('department_set_active', { p_key: d.key, p_on: !d.active }).then(function (r) {
      var said = depSaid(r);
      if (said) { depMsg(said); return; }
      depChanged(d.active ? 'Set inactive.' : 'Set active.');
    }).catch(function (e) { depMsg((e && e.message) || 'Not saved.'); });
  }
  function depDelete(d) {
    window.ADspaceConfirm.ask({ title: 'Delete', body: d.name + ' is removed from the list. This cannot be undone.', go: 'Delete', tone: 'danger', wait: true },
      function () {
        return db.rpc('department_delete', { p_key: d.key }).then(function (r) {
          return depSaid(r) || depChanged('Deleted.');
        }).catch(function (e) { return (e && e.message) || 'Not deleted.'; });
      });
  }
  function openDepts(opener) {
    if (!biz()) return;
    depMsg('');
    paintDeps();
    window.ADspaceSheet.show($('depSheet'), { opener: opener });
    readDeps(paintDeps);
  }
  var depWired = false;
  function wireDeps() {
    if (depWired || !$('depSheet')) return;
    depWired = true;
    $('depCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('depClose').addEventListener('click', function () { $('depCancel').click(); });
    $('depAdd').addEventListener('click', function () { depMsg(''); depAsk(null); });
    $('depList').addEventListener('click', function (e) {
      var b = e.target.closest('[data-d]');
      if (!b) return;
      var row = b.closest('.dep-row'), key = row && row.getAttribute('data-key');
      var d = (dep.rows || []).filter(function (x) { return x.key === key; })[0];
      if (!d) return;
      var k = b.getAttribute('data-d');
      if (k === 'menu') {
        e.stopPropagation();
        var mn = row.querySelector('[data-menu]'), open = mn.hidden;
        depShut();
        mn.hidden = !open; b.setAttribute('aria-expanded', String(open));
        if (open) window.ADspaceMenu.place(b, mn);
        return;
      }
      depShut(); depMsg('');
      if (k === 'edit') depAsk(d);
      if (k === 'active') depActive(d);
      if (k === 'delete') depDelete(d);
    });
  }

  /* ---- Industries (2026-11-04) ------------------------------------------
     The industries a client is put in (the user, 2026-11-04: "can do a
     setting for industry?"): the console's pickers and the quotation
     website read this list. One table, A to Z with Other last (the user:
     "option 1 ... 3 or 4 columns": English, 中文, Clients, the pen): the
     pen turns its row into the two fields, a rename carrying onto every
     client holding the old name ("A"); Delete stands in that row only for
     an industry no client holds; the last row adds one. */
  var ind = { rows: null, err: null, editing: null };
  var IND_SAID = {
    denied: window.ADspaceWords.line.noSettings, 'bad-name': 'Enter a name of 2 to 40 characters.',
    'bad-name-zh': 'Enter a Chinese name of 40 characters at most.', taken: 'An industry with this name already exists.',
    'not-found': 'This industry no longer exists. The latest list is now shown.',
    fixed: 'Other cannot be renamed or deleted. Only its Chinese name can be changed.'
  };
  function indSaid(r) {
    var d = r && r.data, e = r && (r.error || (d && d.error));
    if (!e) return '';
    if (e.message) return /function|schema cache/i.test(e.message) ? window.ADspaceWords.line.notYet : e.message;
    if (e === 'in-use') return (d.clients === 1 ? '1 client is in this industry. Move it' : plural(d.clients || 0, 'client', 'clients') + ' are in this industry. Move them') + ' to another industry first.';
    return IND_SAID[e] || (r && r.deleting ? 'Not deleted. Please try again.' : 'Not saved. Please try again.');
  }
  function indMsg(text, tone) { var m = $('indMsg'); if (!m) return; m.textContent = text || ''; m.className = 'msg' + (text ? ' ' + (tone || 'err') : ''); }
  function readInd(done) {
    db.rpc('industries_list').then(function (r) {
      if (r.error || !Array.isArray(r.data)) throw r.error || new Error((r.data && r.data.error) || 'industries');
      ind.rows = r.data; ind.err = null;
    }).catch(function (e) { ind.rows = null; ind.err = e; }).then(function () { if (done) done(); });
  }
  function indChanged(text, focus) {
    ind.editing = null;
    readInd(function () {
      paintInd(); readLine('industries'); indMsg(text, 'ok');
      if (window.ADspaceCRM && window.ADspaceCRM.industriesReload) window.ADspaceCRM.industriesReload();
      var f = focus && $(focus); if (f) f.focus();
    });
  }
  function indOne(name) { return (ind.rows || []).filter(function (x) { return x.name === name; })[0]; }
  /* The figure alone under its Clients head; the word too where the heads
     leave (a phone). */
  function indCount(n) { return '<span class="ind-n">' + (n || 0) + '<span class="ind-unit"> ' + (n === 1 ? 'client' : 'clients') + '</span></span>'; }
  function paintInd() {
    var box = $('indList');
    if (!box) return;
    if (ind.err) {
      window.ADspaceState.failLine(box, 'Industries', (ind.err && ind.err.message) || '', function () { readInd(paintInd); });
      return;
    }
    if (!ind.rows) { window.ADspaceState.skeleton(box, 3); return; }
    $('indCount').textContent = plural(ind.rows.length, 'industry', 'industries');
    var rows = ind.rows.map(function (i) {
      if (i.name === ind.editing) {
        return '<div class="ind-row is-edit" data-name="' + esc(i.name) + '">' +
          /* Other keeps its name, the last choice everywhere (review 6). */
          (i.name === 'Other' ? '<span class="ind-name" id="indEdFixed">Other</span>'
            : '<input class="input input-sm" id="indEdName" maxlength="40" aria-label="Industry in English" value="' + esc(i.name) + '">') +
          '<input class="input input-sm" id="indEdZh" maxlength="40" aria-label="Industry in Chinese" value="' + esc(i.name_zh || '') + '">' +
          indCount(i.clients) +
          (i.clients ? '<p class="ind-note">Saving a new name will also change the industry of ' + esc(plural(i.clients, 'client', 'clients')) + '.</p>' : '') +
          '<span class="ind-acts">' +
            (i.clients || i.name === 'Other' ? '' : '<button class="btn btn-danger btn-sm" type="button" data-i="delete">Delete</button>') +
            '<button class="btn btn-quiet btn-sm" type="button" data-i="cancel">Cancel</button>' +
            '<button class="btn btn-primary btn-sm" type="button" data-i="save">Save</button></span>' +
          '</div>';
      }
      return '<div class="ind-row" data-name="' + esc(i.name) + '">' +
        '<span class="ind-name">' + esc(i.name) + '</span>' +
        '<span class="ind-zh">' + (i.name_zh ? esc(i.name_zh) : '<span class="ind-none">—</span>') + '</span>' +
        indCount(i.clients) +
        '<span class="ind-acts"><button class="iconbtn" type="button" data-i="edit" aria-label="Edit ' + esc(i.name) + '" title="Edit">' + PEN + '</button></span></div>';
    }).join('');
    box.innerHTML = '<div class="ind-row ind-head" aria-hidden="true"><span>English</span><span>中文</span><span>Clients</span><span></span></div>' + rows +
      '<div class="ind-row ind-add">' +
        '<input class="input input-sm" id="indNewName" maxlength="40" placeholder="Hospitality" aria-label="New industry in English">' +
        '<input class="input input-sm" id="indNewZh" maxlength="40" placeholder="酒店业" aria-label="New industry in Chinese">' +
        '<span class="ind-acts"><button class="btn btn-sm" type="button" data-i="add">' + PLUS + 'Add</button></span></div>';
    if (ind.editing) { var f = $('indEdName') || $('indEdZh'); if (f) f.focus(); }
  }
  function indSave(was) {
    var nm = $(was ? 'indEdName' : 'indNewName'), zh = $(was ? 'indEdZh' : 'indNewZh');
    if (!nm) nm = zh;  // Other: its name stays, its Chinese name is changed
    var name = was === 'Other' ? 'Other' : (nm.value || '').replace(/\s+/g, ' ').trim();
    if (!name) { indMsg('Enter the industry\'s name.'); nm.focus(); return; }
    var btn = $('indList').querySelector(was ? '.is-edit [data-i="save"]' : '[data-i="add"]');
    // A second Enter while the first is saving is the same press (audit 2026-11-04, 6).
    if (btn && btn.disabled) return;
    if (btn) btn.disabled = true;
    db.rpc('industry_save', { p_was: was || null, p_name: name, p_name_zh: (zh.value || '').trim() || null }).then(function (r) {
      var said = indSaid(r);
      if (said) { indMsg(said); if (btn) btn.disabled = false; nm.focus(); return; }
      var moved = r.data && r.data.clients;
      indChanged(!was ? 'Added.' : moved ? 'Saved. ' + plural(moved, 'client', 'clients') + ' updated.' : 'Saved.', was ? null : 'indNewName');
    }).catch(function (e) { indMsg((e && e.message) || 'Not saved. Please try again.'); if (btn) btn.disabled = false; });
  }
  function indDelete(i) {
    window.ADspaceConfirm.ask({ title: 'Delete', body: i.name + ' will be deleted from the list. This cannot be undone.', go: 'Delete', tone: 'danger', wait: true },
      function () {
        return db.rpc('industry_delete', { p_name: i.name }).then(function (r) {
          if (r) r.deleting = true;
          var said = indSaid(r);
          if (said) return said;
          indChanged('Deleted.');
          return '';
        }).catch(function (e) { return (e && e.message) || 'Not deleted. Please try again.'; });
      });
  }
  function openInd(opener) {
    if (!biz()) return;
    indMsg(''); ind.editing = null;
    paintInd();
    window.ADspaceSheet.show($('indSheet'), { opener: opener });
    readInd(paintInd);
  }
  var indWired = false;
  function wireInd() {
    if (indWired || !$('indSheet')) return;
    indWired = true;
    $('indCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('indClose').addEventListener('click', function () { $('indCancel').click(); });
    var list = $('indList');
    list.addEventListener('click', function (e) {
      var b = e.target.closest('[data-i]');
      if (!b) return;
      var k = b.getAttribute('data-i'), row = b.closest('.ind-row'), name = row && row.getAttribute('data-name');
      if (k === 'add') { indMsg(''); indSave(null); return; }
      var i = indOne(name);
      if (!i) return;
      if (k === 'edit') { indMsg(''); ind.editing = i.name; paintInd(); }
      else if (k === 'cancel') { ind.editing = null; paintInd(); var p = list.querySelector('.ind-row[data-name="' + CSS.escape(i.name) + '"] [data-i="edit"]'); if (p) p.focus(); }
      else if (k === 'save') indSave(i.name);
      else if (k === 'delete') indDelete(i);
    });
    rowKeys(list, 'i', function (row) { indSave(row.classList.contains('ind-add') ? null : row.getAttribute('data-name')); });
  }

  /* A short table's keys (Industries, Public holidays): Enter saves the row
     it is typed in, Escape leaves an edit, both heard before the sheet's
     own capture. One copy (audit 2026-11-04, 9). */
  function rowKeys(list, attr, save) {
    window.addEventListener('keydown', function (e) {
      if (e.isComposing || e.keyCode === 229) return;
      var row = e.target.closest && list.contains(e.target) && e.target.closest('.ind-row');
      if (!row || e.target.tagName !== 'INPUT') return;
      if (e.key === 'Enter') { e.preventDefault(); e.stopPropagation(); save(row); }
      else if (e.key === 'Escape' && row.classList.contains('is-edit')) { e.preventDefault(); e.stopPropagation(); row.querySelector('[data-' + attr + '="cancel"]').click(); }
    }, true);
  }

  /* ---- Page availability (2026-10-29) ------------------------------------
     Upgrade mode a page at a time (the user, 2026-10-29: "Upgrade for
     /client page, Temporarily Unavailable for /admin, or selectively"):
     each page Available, Upgrade in progress or Temporarily unavailable,
     with its window and note; several set at once through Select. The
     front door, the 404 and namecards are never covered. */
  var pg = { rows: null, err: null, picking: false, picked: {} };
  var PG_GROUPS = [['Team', ['admin']], ['Clients', ['client', 'review', 'script', 'details']],
    ['Creators', ['creators', 'creator']], ['Public', ['quote', 'supplier', 'verify']]];
  var PG_WORD = { upgrade: 'Upgrade in progress', paused: 'Temporarily unavailable' };
  var PG_SAID = { denied: 'You do not have permission to change page availability. Please ask an admin.', 'bad-window': 'Choose an end after the start, and later than now.',
    'bad-page': 'Choose a page.', 'bad-kind': 'Choose the availability.' };
  function pgMsg(text, tone) { var m = $('pgMsg'); if (!m) return; m.textContent = text || ''; m.className = 'msg' + (text ? ' ' + (tone || 'err') : ''); }
  function readPg() {
    return db.rpc('page_states_all').then(function (r) {
      if (r.error || (r.data && r.data.error)) throw r.error || new Error(PG_SAID[r.data.error] || r.data.error);
      pg.rows = r.data || []; pg.err = null;
      return pg.rows;
    });
  }
  function pgOf(k) { return (pg.rows || []).filter(function (p) { return p.key === k; })[0]; }
  function pgName(k) { var p = pgOf(k); return p ? p.name : k; }
  function pgState(p) {
    if (!p.set) return ['is-ok', 'Available', ''];
    var w = p.on ? (p.ends_at ? 'Until ' + when(p.ends_at) : 'No end set')
      : 'From ' + when(p.starts_at) + (p.ends_at ? ' to ' + when(p.ends_at) : '');
    return [p.kind === 'paused' ? 'is-off' : 'is-warn', PG_WORD[p.kind] || PG_WORD.upgrade, w];
  }
  /* How many pages are unavailable now and how many are set for later. */
  /* With the noun (the Settings row: 2 pages unavailable) or after a count
     that already names it (the sheet's foot: 10 pages · 2 unavailable). */
  function pgCounts(rows, bare) {
    var now = rows.filter(function (p) { return p.set && p.on; }).length,
        later = rows.filter(function (p) { return p.set && !p.on; }).length;
    return [now ? (bare ? now : plural(now, 'page', 'pages')) + ' unavailable' : '', later ? later + ' scheduled' : ''].filter(Boolean);
  }
  function pgFoot() {
    var n = Object.keys(pg.picked).length, counts = pgCounts(pg.rows || [], true);
    /* While several are chosen the count is the tick for all ten (DESIGN.md
       §4 Several records at once; 2026-10-29, audit SET-1). */
    var all = (pg.rows || []).length;
    $('pgCount').hidden = !!pg.picking;
    $('pgCount').textContent = pg.picking ? '' : pg.rows ? [plural(all, 'page', 'pages')].concat(counts).join(' · ') : '';
    $('pgAllLine').hidden = !pg.picking;
    $('pgAllCount').textContent = n + ' selected';
    $('pgAll').checked = !!all && n === all;
    $('pgAll').indeterminate = n > 0 && n < all;
    $('pgSelect').textContent = pg.picking ? 'Done' : 'Select';
    $('pgSelect').hidden = !pg.rows;
    // Set availability is drawn once a page is ticked, never greyed (MENU-12).
    $('pgSetMany').hidden = !pg.picking || !n;
  }
  function paintPg() {
    var box = $('pgList');
    if (!box) return;
    if (pg.err) { window.ADspaceState.failLine(box, 'Page availability', (pg.err && pg.err.message) || '', function () { readPg().then(paintPg, function (e) { pg.err = e; paintPg(); }); }); return; }
    if (!pg.rows) { window.ADspaceState.skeleton(box, 4); return; }
    pgFoot();
    box.innerHTML = PG_GROUPS.map(function (g) {
      return '<h4 class="fsec-h pg-grp">' + esc(g[0]) + '</h4>' + g[1].map(function (k) {
        var p = pgOf(k);
        if (!p) return '';
        var st = pgState(p);
        /* While several are chosen the whole row is the tick's label, so a
           press anywhere on it ticks it (2026-10-29). */
        var tag = pg.picking ? 'label' : 'div';
        return '<' + tag + ' class="dtrow pg-row' + (pg.picking ? ' is-picking' : '') + '" data-key="' + esc(k) + '">' +
          '<span class="dtrow-name">' + (pg.picking ? '<input type="checkbox" class="pg-tick" aria-label="' + esc(p.name) + '"' + (pg.picked[k] ? ' checked' : '') + '>' : '') +
            '<b>' + esc(p.name) + '</b><small class="mono">/' + esc(k) + '/</small></span>' +
          '<span class="pg-state"><span class="chip-state ' + st[0] + '">' + esc(st[1]) + '</span>' + (st[2] ? '<small>' + esc(st[2]) + '</small>' : '') + '</span>' +
          /* The pen alone, as every short table in Settings (revamp D). */
          (pg.picking ? '' : '<span class="hol-acts"><button class="iconbtn" type="button" data-p="edit" aria-label="Edit ' + esc(p.name) + '" title="Edit">' + PEN + '</button></span>') +
          '</' + tag + '>';
      }).join('');
    }).join('');
  }
  function openPages(opener) {
    pgMsg(''); pg.picking = false; pg.picked = {};
    paintPg();
    window.ADspaceSheet.show($('pgSheet'), { opener: opener });
    readPg().then(paintPg, function (e) { pg.err = e; paintPg(); });
  }
  /* What setting the page does, said under the choice. */
  function pgNote(keys) {
    if (keys.indexOf('quote') >= 0) return 'No new quotations can be requested during this period. Quotation links already sent still open while the website is Temporarily unavailable.';
    if (keys.indexOf('admin') >= 0) return 'Admins continue to work under a notice bar; every other colleague sees the notice page.';
    return 'Visitors see the notice page in its place. Nothing on the page is changed.';
  }
  function pgDay(iso) { return iso ? window.ADspaceClock.day(iso) : ''; }
  function pgTime(iso) {
    if (!iso) return '';
    var p = window.ADspaceClock.parts(iso);
    return (p.h < 10 ? '0' : '') + p.h + ':' + (p.mi < 10 ? '0' : '') + p.mi;
  }
  function pgArgs(p) {
    return { p_pages: [p.key], p_kind: p.set ? p.kind : 'none', p_note: p.note || null, p_note_zh: p.note_zh || null,
      p_starts: p.set && !p.on ? p.starts_at : null, p_ends: p.set ? p.ends_at : null, p_whatsapp: !!p.whatsapp };
  }
  function pgSave(args, then) {
    return db.rpc('page_set', args).then(function (r) {
      var d = r.data || {};
      if (r.error || d.error) throw new Error(r.error ? (/function|schema cache/i.test(r.error.message) ? window.ADspaceWords.line.notYet : r.error.message) : PG_SAID[d.error] || d.error);
      pg.rows = d.pages || pg.rows;
      if (bridge.upgradeRead) bridge.upgradeRead();
      return then ? then() : null;
    });
  }
  function pgAsk(keys, opener) {
    var one = keys.length === 1 ? pgOf(keys[0]) : null;
    var today = pgDay(new Date().toISOString());
    var cur = one && one.set ? one : null;
    window.ADspaceConfirm.ask({
      title: one ? one.name : 'Set availability · ' + plural(keys.length, 'page', 'pages'), go: 'Save', wait: true,
      fields: [{ name: 'kind', label: 'Availability', seg: true, value: cur ? cur.kind : 'none', note: pgNote(keys),
                 choices: [['none', 'Available'], ['upgrade', 'Upgrading'], ['paused', 'Unavailable']] },
               { name: 'sday', label: 'Starts', type: 'date', min: today, required: false, half: true, value: cur && !cur.on ? pgDay(cur.starts_at) : '' },
               { name: 'stime', label: 'Start time', type: 'time', required: false, half: true, hint: 'Optional', value: cur && !cur.on ? pgTime(cur.starts_at) : '' },
               { name: 'eday', label: 'Ends', type: 'date', min: today, required: false, half: true, value: cur ? pgDay(cur.ends_at) : '' },
               { name: 'etime', label: 'End time', type: 'time', required: false, half: true, hint: 'Optional', value: cur ? pgTime(cur.ends_at) : '' },
               { name: 'note', label: 'Note to visitors', placeholder: 'Optional', required: false, value: cur ? cur.note || '' : '' },
               { name: 'note_zh', label: '中文 note', placeholder: 'Optional', required: false, value: cur ? cur.note_zh || '' : '' }]
        .concat(keys.length === 1 && keys[0] === 'admin' ? [] : [{ name: 'whatsapp', label: 'Show Chat on WhatsApp', tick: true, value: cur && cur.whatsapp ? 'on' : '' }]),
      check: function (v) { return v.kind === 'none' ? '' : bridge.upgradeWindow(v).bad; }
    }, function (v) {
      var w = bridge.upgradeWindow(v), was = keys.map(pgOf).filter(Boolean).map(pgArgs);
      var args = { p_pages: keys, p_kind: v.kind, p_note: v.kind === 'none' ? null : v.note || null, p_note_zh: v.kind === 'none' ? null : v.note_zh || null,
        p_starts: v.kind === 'none' ? null : w.starts, p_ends: v.kind === 'none' ? null : w.ends, p_whatsapp: v.kind !== 'none' && v.whatsapp === 'on' };
      return pgSave(args).then(function () {
        pg.picking = false; pg.picked = {};
        paintPg();
        pgMsg('Saved.', 'ok');
        fillLine('pages', null); if (READ.pages) READ.pages().then(function (t) { fillLine('pages', t); });
        bridge.undoHere('Saved.', function () {
          /* Every page is put back that can be, and those that cannot are
             named (the overnight review, 2026-11-10). */
          var left = [];
          was.reduce(function (pr, a) { return pr.then(function () { return pgSave(a).catch(function () { left = left.concat(a.p_pages.map(pgName)); }); }); }, Promise.resolve())
            .then(function () {
              paintPg();
              pgMsg(left.length ? 'The change to ' + left.join(', ') + ' could not be undone. Set ' + (left.length > 1 ? 'their' : 'its') + ' availability again.' : 'Undone.', left.length ? 'err' : 'ok');
              READ.pages().then(function (t) { fillLine('pages', t); });
            });
        }, $('pgMsg'));
        return '';
      }).catch(function (e) { return e.message || String(e); });
    });
  }
  var pgWired = false;
  function wirePg() {
    if (pgWired || !$('pgSheet')) return;
    pgWired = true;
    $('pgCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('pgClose').addEventListener('click', function () { $('pgCancel').click(); });
    $('pgSelect').addEventListener('click', function () { pg.picking = !pg.picking; pg.picked = {}; pgMsg(''); paintPg(); });
    $('pgSetMany').addEventListener('click', function () { pgAsk(Object.keys(pg.picked), this); });
    $('pgAll').addEventListener('change', function () {
      var on = this.checked;
      pg.picked = {};
      if (on) (pg.rows || []).forEach(function (p) { pg.picked[p.key] = true; });
      paintPg();
    });
    $('pgList').addEventListener('change', function (e) {
      var t = e.target.closest('.pg-tick'); if (!t) return;
      var k = t.closest('.pg-row').getAttribute('data-key');
      if (t.checked) pg.picked[k] = true; else delete pg.picked[k];
      pgFoot();
    });
    $('pgList').addEventListener('click', function (e) {
      var b = e.target.closest('[data-p="edit"]'); if (!b) return;
      pgMsg(''); pgAsk([b.closest('.pg-row').getAttribute('data-key')], b);
    });
  }

  /* ---- Tax codes (2026-10-22) --------------------------------------------
     The codes a service line or a quotation line may carry: read from
     Bukku, so the letter and the Bukku invoice name the same code, or added
     by hand. Read from Bukku lists Bukku's codes to tick and keeps only the
     ticked ones offered; a code no line, quotation or letter names may be
     deleted, one that is named is set not offered. */
  var tax = { rows: null, err: null, mode: 'list', bukku: null, picked: {} };
  function taxMsg(text, tone) { var m = $('taxMsg'); if (!m) return; m.textContent = text || ''; m.className = 'msg' + (text ? ' ' + (tone || 'err') : ''); }
  var TAX_SAID = {
    denied: 'You do not have permission to change tax codes. Please ask an admin.',
    'bad-row': 'A code is up to 30 letters, digits, spaces, dots or dashes, its rate 0 to 100.'
  };
  function taxRefusal(d) {
    if (d.error === 'in-use') {
      var c = d.codes || [];
      return c.join(', ') + (c.length === 1 ? ' is' : ' are') + ' on a service line, a quotation or a letter, so ' +
        (c.length === 1 ? 'it stays. Untick Offered on new lines to stop offering it.' : 'they stay. Untick Offered on new lines to stop offering them.');
    }
    return TAX_SAID[d.error] || d.error;
  }
  function taxPct(r) { return String(Math.round(Number(r) * 100) / 100) + '%'; }
  function readTax(then) {
    window.ADspaceMoney.taxCodes(true).then(function (list) { tax.rows = list; tax.err = null; then(); })
      .catch(function (e) { tax.err = e; then(); });
  }
  function taxFoot() {
    var m = tax.mode, n = Object.keys(tax.picked).length;
    $('taxBukku').hidden = m !== 'list' || !window.ADspaceBukku;
    $('taxAdd').hidden = m !== 'list';
    $('taxCancel').textContent = m === 'pick' ? 'Cancel' : 'Close';
    $('taxKeep').hidden = m !== 'pick';
    $('taxKeep').textContent = 'Keep ' + n + (n === 1 ? ' code' : ' codes');
    $('taxKeep').disabled = m === 'pick' && !n;
    // Delete is drawn once a code is ticked, never greyed (MENU-12, MENU-13).
    $('taxDel').hidden = m !== 'select' || !n;
    $('taxHead').textContent = m === 'pick' ? 'Choose from Bukku' : 'Tax codes';
    var bar = $('taxBar');
    if (bar) {
      $('taxSelect').hidden = !(tax.rows && tax.rows.length);
      bar.hidden = m === 'pick';
      $('taxCount').textContent = m === 'select' ? n + ' selected'
        : (tax.rows ? tax.rows.length + (tax.rows.length === 1 ? ' code' : ' codes') + ' · ' + tax.rows.filter(function (t) { return t.active; }).length + ' offered' : '');
      $('taxSelect').textContent = m === 'select' ? 'Done' : 'Select';
    }
  }
  function paintTax() {
    var box = $('taxList');
    if (!box) return;
    taxFoot();
    if (tax.mode === 'pick') {
      var held = {};
      (tax.rows || []).forEach(function (t) { held[t.code] = t; });
      box.innerHTML = '<div class="tax-pick" role="group" aria-label="Bukku tax codes">' + tax.bukku.map(function (t) {
        var h = held[t.code];
        return '<label class="tickline"><input type="checkbox" value="' + esc(t.code) + '"' + (tax.picked[t.code] ? ' checked' : '') + '> <span><b>' +
          esc(t.code) + ' · ' + esc(taxPct(t.rate)) + '</b>' + (t.name || h ? '<small>' + esc([t.name, h ? (h.active ? 'Offered' : 'Not offered') : ''].filter(Boolean).join(' · ')) + '</small>' : '') + '</span></label>';
      }).join('') + '</div>';
      return;
    }
    if (!tax.rows) { window.ADspaceState.skeleton(box, 3); return; }
    if (!tax.rows.length) { box.innerHTML = ''; window.ADspaceState.emptyLine(box, 'No tax codes.'); return; }
    var picking = tax.mode === 'select';
    /* One table, as Industries (revamp B, 2026-11-04): Code · Rate · Name ·
       Offered, then the pen and a ⋯ holding Delete; Select puts a tick at
       the row's end in their place. */
    box.innerHTML = '<div class="ind-row ind-head is-tax" aria-hidden="true"><span>Code</span><span>Rate</span><span>Name</span><span>Offered</span><span></span></div>' +
      tax.rows.map(function (t) {
        var cells = '<span class="ind-name tax-code">' + esc(t.code) + '</span><span class="tax-rate">' + esc(taxPct(t.rate)) + '</span>' +
          '<span class="ind-zh tax-name">' + (t.name ? esc(t.name) : '<span class="ind-none">—</span>') + '</span>' +
          '<span class="tax-on"><span class="chip-state ' + (t.active ? 'is-ok' : 'is-off') + '">' + (t.active ? 'Offered' : 'Not offered') + '</span></span>';
        if (picking) {
          return '<label class="ind-row is-tax tax-row is-picking' + (t.active ? '' : ' is-past') + '" data-code="' + esc(t.code) + '">' + cells +
            '<span class="ind-acts"><input type="checkbox" value="' + esc(t.code) + '"' + (tax.picked[t.code] ? ' checked' : '') + ' aria-label="Select ' + esc(t.code) + '"></span></label>';
        }
        return '<div class="ind-row is-tax tax-row' + (t.active ? '' : ' is-past') + '" data-code="' + esc(t.code) + '">' + cells +
          '<span class="ind-acts"><button class="iconbtn" type="button" data-t="edit" aria-label="Edit ' + esc(t.code) + '" title="Edit">' + PEN + '</button>' +
          '<span class="team-act"><button class="kmenu-btn" type="button" data-t="menu" aria-label="More actions for ' + esc(t.code) + '" aria-expanded="false">' +
            '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/></svg></button>' +
          '<div class="kmenu" data-menu hidden role="menu"><button class="kmenu-item is-danger" data-g="6" type="button" role="menuitem" data-t="delete">Delete</button></div></span></span></div>';
      }).join('');
  }
  function taxShut() { shutMenus('#taxList', 't'); }
  function taxSet(mode) { tax.mode = mode; tax.picked = {}; paintTax(); }
  function taxSave(rows, replace, done) {
    return db.rpc('tax_codes_save', { p_rows: rows, p_replace: Boolean(replace) }).then(function (r) {
      var d = r.data || {};
      if (r.error) return /could not find|does not exist|schema cache/i.test(r.error.message || '') ? window.ADspaceWords.line.notYet : (r.error.message || 'Not saved.');
      if (d.error) return taxRefusal(d);
      tax.rows = d.codes || [];
      paintTax(); readLine('taxcodes');
      if (done) done();
      return '';
    }).catch(function (e) { return (e && e.message) || 'Not saved.'; });
  }
  function taxDelete(codes) {
    var one = codes.length === 1;
    window.ADspaceConfirm.ask({
      title: one ? 'Delete ' + codes[0] + '?' : 'Delete ' + codes.length + ' tax codes?',
      body: (one ? codes[0] + ' is' : codes.join(', ') + ' are') + ' removed from the list. This cannot be undone.',
      go: 'Delete', tone: 'danger', wait: true,
      field: one ? null : { name: 'n', label: 'Type ' + codes.length + ' to confirm', match: String(codes.length),
        need: 'Type ' + codes.length + ' to confirm.', mismatch: 'Type ' + codes.length + ' to confirm.' }
    }, function () {
      return db.rpc('tax_codes_delete', { p_codes: codes }).then(function (r) {
        var d = r.data || {};
        if (r.error) return /could not find|does not exist|schema cache/i.test(r.error.message || '') ? window.ADspaceWords.line.notYet : (r.error.message || 'Not deleted.');
        if (d.error) return taxRefusal(d);
        tax.rows = d.codes || [];
        tax.mode = 'list'; tax.picked = {};
        paintTax(); readLine('taxcodes');
        taxMsg('Deleted.', 'ok');
        return '';
      }).catch(function (e) { return (e && e.message) || 'Not deleted.'; });
    });
  }
  function taxAsk(t) {
    window.ADspaceConfirm.ask({
      title: t ? 'Edit ' + t.code : 'Add tax code', go: 'Save', wait: true,
      fields: [t ? null : { name: 'code', label: 'Code', placeholder: 'SV8', required: true },
        { name: 'rate', label: 'Rate (%)', value: t ? String(t.rate) : '', placeholder: '8', required: true },
        { name: 'name', label: 'Name', value: t ? t.name : '', placeholder: 'Service tax 8%' },
        { name: 'active', label: 'Offered on new lines', tick: true, value: !t || t.active ? 'on' : '' }].filter(Boolean),
      check: function (v) {
        if (!t && !/^[A-Za-z0-9._ -]{1,30}$/.test(String(v.code || '').trim())) return TAX_SAID['bad-row'];
        if (String(v.name || '').trim().length > 80) return 'Enter a name of up to 80 characters.';
        return /^[0-9]{1,3}(\.[0-9]{1,2})?$/.test(String(v.rate || '').trim()) && Number(v.rate) <= 100 ? '' : 'A rate is 0 to 100, to two decimals.';
      }
    }, function (v) {
      return taxSave([{ code: t ? t.code : String(v.code || '').trim(), name: String(v.name || '').trim(), rate: String(v.rate).trim(), active: v.active === 'on' }], false,
        function () { taxMsg('Saved.', 'ok'); });
    });
  }
  function taxBukku(btn) {
    if (!window.ADspaceBukku || !window.ADspaceBukku.taxes) return;
    taxMsg('');
    btn.disabled = true;
    window.ADspaceBukku.taxes().then(function (d) {
      btn.disabled = false;
      if (d.error) { taxMsg(d.error); return; }
      if (!(d.codes || []).length) { taxMsg('Bukku has no tax codes the portal can read.'); return; }
      tax.bukku = d.codes.slice().sort(function (a, b) { return (b.rate - a.rate) || (a.code < b.code ? -1 : 1); });
      tax.mode = 'pick'; tax.picked = {};
      (tax.rows || []).forEach(function (t) { if (t.active && tax.bukku.some(function (b) { return b.code === t.code; })) tax.picked[t.code] = true; });
      paintTax();
      $('taxSheet').querySelector('.sheet-body').scrollTop = 0;
    });
  }
  /* Only the codes ticked are kept as offered: a code ticked is added or
     updated from Bukku, one held and not ticked is set not offered, and
     one not held and not ticked is left out. */
  function taxKeep() {
    var held = {}, rows = [];
    (tax.rows || []).forEach(function (t) { held[t.code] = t; });
    tax.bukku.forEach(function (b) {
      if (tax.picked[b.code]) rows.push({ code: b.code, name: b.name || '', rate: String(b.rate), active: true, bukku_id: b.bukku_id });
      else if (held[b.code] && held[b.code].active) rows.push({ code: b.code, name: held[b.code].name || '', rate: String(held[b.code].rate), active: false });
    });
    var n = Object.keys(tax.picked).length;
    $('taxKeep').disabled = true;
    taxSave(rows, false).then(function (err) {
      $('taxKeep').disabled = false;
      if (err) { taxMsg(err); return; }
      tax.mode = 'list'; tax.picked = {};
      paintTax();
      taxMsg(n + (n === 1 ? ' code' : ' codes') + ' offered from Bukku.', 'ok');
    });
  }
  function openTax(opener) {
    if (!biz() || !$('taxSheet')) return;
    taxMsg('');
    tax.rows = null; tax.mode = 'list'; tax.picked = {};
    paintTax();
    window.ADspaceSheet.show($('taxSheet'), { opener: opener });
    readTax(paintTax);
  }
  var taxWired = false;
  function wireTax() {
    if (taxWired || !$('taxSheet')) return;
    taxWired = true;
    $('taxCancel').addEventListener('click', function () {
      // Cancel ends choosing from Bukku; Close shuts the sheet, ticks and all.
      if (tax.mode === 'pick') { taxMsg(''); taxSet('list'); return; }
      tax.mode = 'list'; window.ADspaceSheet.close();
    });
    $('taxClose').addEventListener('click', function () { tax.mode = 'list'; window.ADspaceSheet.close(); });
    $('taxAdd').addEventListener('click', function () { taxMsg(''); taxAsk(null); });
    $('taxBukku').addEventListener('click', function () { taxBukku(this); });
    $('taxKeep').addEventListener('click', taxKeep);
    $('taxDel').addEventListener('click', function () { var c = Object.keys(tax.picked).sort(); if (c.length) taxDelete(c); });
    $('taxSelect').addEventListener('click', function () { taxMsg(''); taxSet(tax.mode === 'select' ? 'list' : 'select'); });
    $('taxList').addEventListener('change', function (e) {
      var c = e.target.closest('input[type="checkbox"]');
      if (!c) return;
      if (c.checked) tax.picked[c.value] = true; else delete tax.picked[c.value];
      taxFoot();
    });
    $('taxList').addEventListener('click', function (e) {
      var b = e.target.closest('[data-t]');
      if (!b) return;
      var row = b.closest('.tax-row'), code = row && row.getAttribute('data-code');
      var t = (tax.rows || []).filter(function (x) { return x.code === code; })[0];
      if (!t) return;
      var k = b.getAttribute('data-t');
      if (k === 'menu') {
        e.stopPropagation();
        var mn = row.querySelector('[data-menu]'), open = mn.hidden;
        taxShut();
        mn.hidden = !open; b.setAttribute('aria-expanded', String(open));
        if (open) window.ADspaceMenu.place(b, mn);
        return;
      }
      taxShut(); taxMsg('');
      if (k === 'edit') taxAsk(t);
      if (k === 'delete') taxDelete([t.code]);
    });
  }
  wireTax();

  function openHol(opener) {
    if (!biz()) return;
    holMsg(''); hol.editing = null;
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
    $('holYear').addEventListener('change', function () { hol.year = Number(this.value); hol.editing = null; holMsg(''); paintHol(); });
    var list = $('holList');
    list.addEventListener('click', function (e) {
      var b = e.target.closest('[data-h]');
      if (!b) return;
      var k = b.getAttribute('data-h'), row = b.closest('.ind-row'), day = row && row.getAttribute('data-day');
      if (k === 'add') { holMsg(''); holSave(null); return; }
      var h = (hol.rows || []).filter(function (x) { return x.day === day; })[0];
      if (!h) return;
      if (k === 'edit') { holMsg(''); hol.editing = h.day; paintHol(); }
      else if (k === 'cancel') { hol.editing = null; paintHol(); var p = list.querySelector('.ind-row[data-day="' + h.day + '"] [data-h="edit"]'); if (p) p.focus(); }
      else if (k === 'save') holSave(h.day);
      else if (k === 'delete') holDelete(h);
    });
    rowKeys(list, 'h', function (row) { holSave(row.classList.contains('ind-add') ? null : row.getAttribute('data-day')); });
  }
  wireHol();
  wireDeps();
  wireInd();
  wirePg();
  /* A press outside a list's ⋯ shuts it: one listener for every list. */
  document.addEventListener('click', function (e) {
    if (!e.target.closest('#depList .team-act')) depShut();
    if (!e.target.closest('#taxList .team-act')) taxShut();
  });

  function enter() {
    say('');
    query = '';
    said = null;
    lines = {};
    fromUrl();
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
    /* The page's own scroll, within the group shown. */
    if (bridge.restoreScroll) bridge.restoreScroll();
  }

  var wired = false;
  function wire() {
    if (wired || !$('setList')) return;
    wired = true;
    $('setList').addEventListener('focusin', function (e) {
      var b = e.target.closest && e.target.closest('[data-a]');
      if (!reread || !b || b.getAttribute('data-a') !== reread) return;
      var id = reread; reread = '';
      /* Focus comes back while the sheet is still shutting: the row is read
         once it has shut, never skipped (2026-10-20, SET-2). */
      var open = function () { return document.querySelector('.sheet:not([hidden])'); };
      /* Asked a tick later: a sheet that swaps for another (Notices' list
         for New) hands focus back between the two, and the row was read
         before the send (2026-10-27, SET-2). */
      setTimeout(function () {
        if (!open()) { readLine(id); return; }
        var mo = new MutationObserver(function () {
          if (open()) return;
          mo.disconnect(); readLine(id);
        });
        mo.observe(document.body, { subtree: true, attributes: true, attributeFilter: ['hidden'] });
      }, 0);
    });
    $('setList').addEventListener('input', function (e) {
      if (e.target.id !== 'stgFind') return;
      query = e.target.value;
      var at = e.target.selectionStart;
      paint();
      var f = $('stgFind');
      if (f) { f.focus({ preventScroll: true }); try { f.setSelectionRange(at, at); } catch (x) { /* a search box keeps no caret in some browsers */ } }
    });
    $('setList').addEventListener('keydown', function (e) {
      if (e.target.id !== 'stgFind') return;
      if (e.key === 'Escape' && query) { e.preventDefault(); e.stopPropagation(); query = ''; paint(); var f = $('stgFind'); if (f) f.focus(); }
      if (e.key === 'Enter') { var first = document.querySelector('#setList .stg-hit'); if (first) { e.preventDefault(); first.click(); } }
    });
    $('setList').addEventListener('click', function (e) {
      var hit = e.target.closest('[data-hit]');
      if (hit) { query = ''; chosen = hit.getAttribute('data-hg'); paint(); if (bridge.setUrl) bridge.setUrl(); focusRow(hit.getAttribute('data-hit')); return; }
      var gb = e.target.closest('[data-g]');
      if (gb && $('setList').contains(gb)) { go(gb.getAttribute('data-g')); return; }
      var b = e.target.closest('[data-a]');
      if (!b || b.disabled || !$('setList').contains(b)) return;
      press(b.getAttribute('data-a'), b);
    });
  }
  wire();

  /* Every row this colleague is drawn, with its group, for console search
     (2026-10-27, SET-9: 26 rows in eight groups, one shown at a time). */
  function rows() {
    var out = [];
    groups().forEach(function (g) { g.rows.forEach(function (r) { out.push({ id: r.id, name: r.name, group: g.key, groupName: g.name }); }); });
    return out;
  }
  /* A row found by search: its group shown and its control focused. */
  function focusRow(id) {
    var b = document.querySelector('#setList .stg-row[data-row="' + id + '"] [data-a]');
    if (b) b.focus();
  }
  window.ADspaceSettings = { enter: function () { wire(); enter(); }, paint: paint,
    pagesChanged: function (rows) { if (rows) pg.rows = rows; paintPg(); if (READ.pages) READ.pages().then(function (t) { fillLine('pages', t); }).catch(function () {}); }, urlState: urlState, allowed: allowed, say: say, rows: rows, focusRow: focusRow };
  if (bridge.settingsReady) bridge.settingsReady();
})();
