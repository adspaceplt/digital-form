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
  function esc(s) { return window.ADspaceWords.esc(s); }
  var PEN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 20h4L19 9l-4-4L4 16z"/><path d="m13.5 6.5 4 4"/></svg>';
  var CHEV = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 18 6-6-6-6"/></svg>';
  /* Every part a row of this page answers to. The route is offered to a
     colleague holding any of them, or Suppliers or WhatsApp at Full Access
     (Supplier emails, Templates) (`ADspaceSettings.allowed`). */
  var KEYS = ['team.upgrade', 'team.announce', 'team.notice', 'team.settings', 'reports.ai', 'register.types', 'ops.numbering'];
  function may(k) { return Boolean(bridge.may && bridge.may(k, 'work')); }
  function allowed() { return KEYS.some(may) || Boolean(bridge.may && (bridge.may('suppliers', 'manage') || bridge.may('whatsapp', 'manage'))); }
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
    bukku: function () { return window.ADspaceBukku && window.ADspaceBukku.configLine(); },
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
    /* What the Supplier emails row holds, from its own read (2026-10-20, SET-7). */
    suptpl: function () {
      return db.rpc('supplier_email_templates_list').then(function (r) {
        if (r.error || (r.data && r.data.error)) throw r.error || new Error(r.data.error);
        return plural(((r.data && r.data.rows) || []).length, 'template', 'templates');
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
      biz && { id: 'depts', name: 'Departments', kind: 'open', meta: line('depts') },
      /* Overseas approval (2026-10-24): how long an approval runs at most
         and how often a waiting request reminds; each request is decided
         on the colleague's own record. */
      biz && { id: 'abroadays', name: 'Overseas approval', kind: 'edit',
        meta: num('abroad_days') == null ? '' : parts(['Up to ' + plural(num('abroad_days'), 'day', 'days'),
          num('abroad_remind_hours') == null ? '' : num('abroad_remind_hours') === 0 ? 'No reminder'
            : 'Reminder every ' + plural(num('abroad_remind_hours'), 'hour', 'hours')].filter(Boolean)) },
      biz && { id: 'healthkeep', name: 'Health data kept', kind: 'edit',
        meta: num('health_keep_months') == null ? '' : parts(['Check-ins ' + plural(num('health_keep_months'), 'month', 'months'),
          'Leavers ' + plural(num('health_leaver_months'), 'month', 'months')]) },
      /* Demo access (2026-10-27): the PIN typed in the sign-in's email box
         that opens the console on sample data (js/demo.js). */
      biz && { id: 'demo', name: 'Demo access', kind: 'edit', meta: line('demo') }]);
    var lead = num('lead_followup_hours'), prop = num('proposal_followup_days');
    add('clients', 'Clients', [
      biz && { id: 'followup', name: 'Follow-up limits', kind: 'edit',
        meta: lead == null ? '' : parts(['Lead ' + plural(lead, 'hour', 'hours'), 'Proposal ' + plural(prop, 'day', 'days'),
          num('vic_lead_followup_hours') == null ? '' : 'VIC ' + plural(num('vic_lead_followup_hours'), 'hour', 'hours') + ' and ' + plural(num('vic_proposal_followup_days'), 'day', 'days')].filter(Boolean)) },
      /* The client's details form (2026-10-14, ux-audit SET-9: it sat in
         Tax and terms). */
      /* Its days open a supplier's link too (2026-10-22, SET2-2). */
      biz && { id: 'details', name: 'Details forms', kind: 'edit',
        meta: num('details_form_days') == null ? '' : 'Client and supplier links open ' + plural(num('details_form_days'), 'day', 'days').replace(' ', '\u00a0') },
      /* The month Analytics counts leads and clients from (2026-10-25). */
      biz && { id: 'analytics', name: 'Analytics', kind: 'edit',
        meta: num('analytics_from') == null ? '' : parts(['Counts from ' + bridge.monthOfSetting(num('analytics_from'))]
          .concat(num('analytics_churn_pct') == null ? [] : ['Churn alert ' + num('analytics_churn_pct') + '% a quarter'])) }]);
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
        meta: num('bench_msg_target') == null ? '' : parts(['Messaging RM ' + num('bench_msg_target'), 'Lead form RM ' + num('bench_form_target')]) }]);
    var pin = num('ai_price_in'), pout = num('ai_price_out');
    add('money', 'Money', [
      biz && { id: 'tax', name: 'Tax and terms', kind: 'edit',
        meta: num('sst_pct') == null ? '' : parts(['SST ' + num('sst_pct') + '%'].concat(num('quote_valid_days') == null ? [] : ['Quotation ' + plural(num('quote_valid_days'), 'day', 'days')])) },
      /* Tax codes (2026-10-22): the codes a service line or a quotation
         line may carry, read from Bukku or added by hand. */
      biz && { id: 'taxcodes', name: 'Tax codes', kind: 'open', meta: line('taxcodes') },
      /* Bukku (2026-10-18): the contact fields that hold our IDs. */
      biz && window.ADspaceBukku && { id: 'bukku', name: 'Bukku', kind: 'edit', meta: line('bukku') }]);
    /* AI's usage and its prices in one group (2026-10-14, ux-audit SET-9). */
    add('ai', 'AI', [may('reports.ai') && { id: 'aiuse', name: 'AI usage and limits', kind: 'open', meta: line('aiuse') },
      biz && { id: 'prices', name: 'AI prices', kind: 'edit',
        meta: pin == null ? '' : parts(['US$ ' + pin + ' in', 'US$ ' + pout + ' out a million tokens']) }]);
    /* WhatsApp (2026-10-10): its templates are set in the WhatsApp section
       at Full Access; this row opens them there. */
    var rep2 = num('wa_repeat_hours');
    add('whatsapp', 'WhatsApp', [window.ADspaceWhatsApp && bridge.may && bridge.may('whatsapp', 'manage') &&
      { id: 'whatsapp', name: 'Templates', kind: 'open', meta: line('whatsapp') },
      /* Sent again (2026-10-14): the same message sent within the window
         asks again before it goes, a supplier's email too (SET2-1). */
      biz && { id: 'resend', name: 'Sent again', kind: 'edit',
        meta: rep2 == null ? '' : rep2 === 0 ? 'Off' : parts(['WhatsApp and supplier emails', 'Within ' + plural(rep2, 'hour', 'hours')]) }]);
    add('documents', 'Documents', [may('register.types') && { id: 'types', name: 'Document types', kind: 'open', meta: line('types') },
      bridge.may && bridge.may('suppliers', 'manage') && { id: 'suptpl', name: 'Supplier emails', kind: 'open', meta: line('suptpl') }]);
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
  function sec(g, on) {
    return '<section class="stg-sec" id="stg-' + g.key + '" data-sec="' + g.key + '" aria-labelledby="stgT-' + g.key + '"' + (on ? '' : ' hidden') + '>' +
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
    /* On a phone the groups are the view strip, sticky under the head,
       scrolling sideways; a press scrolls to the group as the desk's list
       does (the user, 2026-10-22, SET2-17: "approve"; never a drill-down,
       refused 2026-10-11). */
    var strip = phone() && list.length >= 3;
    var cls = 'stg ' + (desk ? 'is-desk' : phone() ? 'is-phone' : 'is-single');
    var html = (desk ? '<nav class="stg-nav" aria-label="Settings">' + list.map(function (x) {
      return '<button class="stg-go" type="button" data-g="' + x.key + '" aria-controls="stg-' + x.key + '">' + esc(x.name) + '</button>';
    }).join('') + '</nav>' : '') +
      (strip ? '<div class="actstrip stg-strip"><span class="cmdbar-views actviews" id="stgStrip" role="group" aria-label="Settings">' + list.map(function (x) {
        return '<button class="acttab btn-sm stg-tab" type="button" data-g="' + x.key + '" aria-controls="stg-' + x.key + '" aria-pressed="false">' + esc(x.name) + '</button>';
      }).join('') + '</span></div>' : '') +
      '<div class="stg-groups"' + (strip ? ' data-swipe="stgStrip"' : '') + '>' + list.map(function (g) {
        /* With fewer than three groups there is nothing to move between,
           and every group shows (2026-10-14, SET-5). */
        return sec(g, !(desk || strip) || g.key === current(list));
      }).join('') + '</div>';
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
      bridge.editSettings({ title: sp.title, keys: sp.keys.map(function (k) { return [k[0], k[1], k[2], k[3], k[4], k[5]]; }), msg: rowSay(a), done: paint }, btn);
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
    if (a === 'demo') { openDemo(); return; }
    if (a === 'depts') { openDepts(btn); return; }
    if (a === 'taxcodes') { openTax(btn); return; }
    if (a === 'bukku') { if (window.ADspaceBukku) window.ADspaceBukku.openConfig(btn, rowSay('bukku')); return; }
    if (a === 'numbering') { if (window.ADspaceOps && window.ADspaceOps.openNumbering) window.ADspaceOps.openNumbering(rowSay('numbering')); return; }
  }

  /* ---- Demo access (2026-10-27) ----------------------------------------
     One sheet: On or Off, and a new PIN (4 to 8 digits; empty keeps the
     one held). The PIN is never read back: the database keeps its hash. */
  var DEMO_SAID = { denied: 'This needs Team: Business settings.', 'bad-pin': 'PIN: 4 to 8 digits.',
    'no-pin': 'Set a PIN before turning demo access on.' };
  function openDemo() {
    db.rpc('demo_state').then(function (r) {
      var d = (r && r.data) || {};
      if (r.error || d.error) { rowSay('demo')(r.error ? (/function|schema cache/i.test(r.error.message) ? 'This needs a database update.' : r.error.message) : DEMO_SAID[d.error] || d.error, 'err'); return; }
      window.ADspaceConfirm.ask({
        title: 'Demo access', go: 'Save', wait: true,
        fields: [{ name: 'on', label: 'Demo access', seg: true, value: d.on ? 'on' : 'off', choices: [['on', 'On'], ['off', 'Off']] },
          { name: 'pin', label: d.pin_set ? 'New PIN' : 'PIN', type: 'tel', required: !d.pin_set, placeholder: '4 to 8 digits', value: '',
            note: d.pin_set ? 'Empty keeps the PIN held. Typed in the sign-in\'s email box, it opens the console on sample data.'
              : 'Typed in the sign-in\'s email box, it opens the console on sample data.' }],
        check: function (v) {
          var pin = String(v.pin || '').trim();
          if (pin && !/^[0-9]{4,8}$/.test(pin)) return DEMO_SAID['bad-pin'];
          if (v.on === 'on' && !pin && !d.pin_set) return DEMO_SAID['no-pin'];
          return '';
        }
      }, function (v) {
        return db.rpc('demo_set', { p_on: v.on === 'on', p_pin: String(v.pin || '').trim() || null }).then(function (r2) {
          var e = r2.error ? (/function|schema cache/i.test(r2.error.message) ? 'This needs a database update.' : r2.error.message)
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

  /* ---- Public holidays (2026-10-14) ------------------------------------
     The days the office is closed: the front door draws them Closed and My
     Work marks them. Read for this year and the next in one request; the
     row says the next one, the sheet lists a year at a time. */
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
        rowActs('h', h.name) + '</div>';
    }).join('');
  }
  /* A list row's acts, the holidays' and the tax codes' alike: Edit, then
     a ⋯ holding Delete. `k` is the row's data attribute (data-h, data-t). */
  function rowActs(k, name) {
    return '<span class="hol-acts"><button class="btn btn-quiet btn-sm" type="button" data-' + k + '="edit">' + PEN + 'Edit</button>' +
      '<span class="team-act"><button class="kmenu-btn" type="button" data-' + k + '="menu" aria-label="More actions for ' + esc(name) + '" aria-expanded="false">' +
        '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/></svg></button>' +
      '<div class="kmenu" data-menu hidden role="menu"><button class="kmenu-item is-danger" data-g="6" type="button" role="menuitem" data-' + k + '="delete">Delete</button></div></span></span>';
  }
  /* Shuts a list's ⋯ menus (`#holList`, `#depList`, `#taxList`). */
  function shutMenus(list, k) {
    Array.prototype.forEach.call(document.querySelectorAll(list + ' .kmenu'), function (m) { m.hidden = true; });
    Array.prototype.forEach.call(document.querySelectorAll(list + ' [data-' + k + '="menu"]'), function (b) { b.setAttribute('aria-expanded', 'false'); });
  }
  function holShut() { shutMenus('#holList', 'h'); }
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
  /* ---- Departments (2026-10-23) ------------------------------------------
     The team's departments (the user: "can add more departments?"): a
     colleague's department on Team, and the departments the quarter's
     department prize is worked out across. A department in the prize names
     its five criteria; one nobody is in can be deleted, one somebody is in
     set inactive (offered to nobody, out of the prize). */
  var dep = { rows: null, err: null };
  var DEP_SAID = {
    denied: 'Business settings access is required.', 'bad-name': 'Enter a name of 2 to 40 characters.',
    taken: 'A department with this name already exists.', 'criteria-needed': 'Name its five criteria to put it in the department prize.',
    'bad-criteria': 'Each criterion is 2 to 60 characters, and all five are named.', 'not-found': 'This department was removed in the meantime.'
  };
  function depSaid(r) {
    var d = r && r.data, e = r && (r.error || (d && d.error));
    if (!e) return '';
    if (e.message) return /function|schema cache/i.test(e.message) ? 'This needs a database update.' : e.message;
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
    box.innerHTML = dep.rows.map(function (d) {
      /* Each part held whole, so a phone wraps between them (TEAM2-11). */
      var meta = [plural(d.members || 0, 'colleague', 'colleagues'), d.in_prize ? 'In the department prize' : ''].filter(Boolean)
        .map(function (x) { return '<span class="team-part">' + esc(x) + '</span>'; }).join(' · ');
      return '<div class="dtrow dep-row' + (d.active ? '' : ' is-off') + '" data-key="' + esc(d.key) + '">' +
        '<span class="dtrow-name"><b>' + esc(d.name) + (d.active ? '' : ' <span class="chip">Inactive</span>') + '</b><small>' + meta + '</small></span>' +
        '<span class="hol-acts"><button class="btn btn-quiet btn-sm" type="button" data-d="edit">' + PEN + 'Edit</button>' +
        '<span class="team-act"><button class="kmenu-btn" type="button" data-d="menu" aria-label="More actions for ' + esc(d.name) + '" aria-expanded="false">' +
          '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/></svg></button>' +
        '<div class="kmenu" data-menu hidden role="menu">' +
          '<button class="kmenu-item" data-g="5" type="button" role="menuitem" data-d="active">' + (d.active ? 'Set inactive' : 'Set active') + '</button>' +
          /* Offered only where it would go through: nobody in it and no
             record naming it (`in_records`, TEAM2-15). */
          (d.members || d.in_records ? '' : '<button class="kmenu-item is-danger" data-g="6" type="button" role="menuitem" data-d="delete">Delete</button>') +
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
    window.ADspaceConfirm.ask({ title: 'Delete', body: d.name + ' is removed from the list. There is no restore.', go: 'Delete', tone: 'danger', wait: true },
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

  /* ---- Tax codes (2026-10-22) --------------------------------------------
     The codes a service line or a quotation line may carry: read from
     Bukku, so the letter and the Bukku invoice name the same code, or added
     by hand. Read from Bukku lists Bukku's codes to tick and keeps only the
     ticked ones offered; a code no line, quotation or letter names may be
     deleted, one that is named is set not offered. */
  var tax = { rows: null, err: null, mode: 'list', bukku: null, picked: {} };
  function taxMsg(text, tone) { var m = $('taxMsg'); if (!m) return; m.textContent = text || ''; m.className = 'msg' + (text ? ' ' + (tone || 'err') : ''); }
  var TAX_SAID = {
    denied: 'Business settings are needed to change the tax codes.',
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
    box.innerHTML = tax.rows.map(function (t) {
      var name = '<span class="dtrow-name"><b>' + esc(t.code) + ' · ' + esc(taxPct(t.rate)) + '</b>' +
          '<small>' + esc([t.name, t.active ? '' : 'Not offered'].filter(Boolean).join(' · ') || 'No name') + '</small></span>';
      if (picking) {
        return '<label class="dtrow tax-row is-picking' + (t.active ? '' : ' is-past') + '" data-code="' + esc(t.code) + '">' +
          '<input type="checkbox" value="' + esc(t.code) + '"' + (tax.picked[t.code] ? ' checked' : '') + ' aria-label="Select ' + esc(t.code) + '">' + name + '</label>';
      }
      return '<div class="dtrow tax-row' + (t.active ? '' : ' is-past') + '" data-code="' + esc(t.code) + '">' + name +
        rowActs('t', t.code) + '</div>';
    }).join('');
  }
  function taxShut() { shutMenus('#taxList', 't'); }
  function taxSet(mode) { tax.mode = mode; tax.picked = {}; paintTax(); }
  function taxSave(rows, replace, done) {
    return db.rpc('tax_codes_save', { p_rows: rows, p_replace: Boolean(replace) }).then(function (r) {
      var d = r.data || {};
      if (r.error) return /could not find|does not exist|schema cache/i.test(r.error.message || '') ? 'This needs a database update.' : (r.error.message || 'Not saved.');
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
      body: (one ? codes[0] + ' is' : codes.join(', ') + ' are') + ' removed from the list. There is no restore.',
      go: 'Delete', tone: 'danger', wait: true,
      field: one ? null : { name: 'n', label: 'Type ' + codes.length + ' to confirm', match: String(codes.length),
        need: 'Type ' + codes.length + ' to confirm.', mismatch: 'Type ' + codes.length + ' to confirm.' }
    }, function () {
      return db.rpc('tax_codes_delete', { p_codes: codes }).then(function (r) {
        var d = r.data || {};
        if (r.error) return /could not find|does not exist|schema cache/i.test(r.error.message || '') ? 'This needs a database update.' : (r.error.message || 'Not deleted.');
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
      if (!(d.codes || []).length) { taxMsg('Bukku holds no tax codes the portal can read.'); return; }
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
  }
  wireHol();
  wireDeps();
  /* A press outside a list's ⋯ shuts it: one listener for every list. */
  document.addEventListener('click', function (e) {
    if (!e.target.closest('#holList .team-act')) holShut();
    if (!e.target.closest('#depList .team-act')) depShut();
    if (!e.target.closest('#taxList .team-act')) taxShut();
  });

  function enter() {
    say('');
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
    $('setList').addEventListener('click', function (e) {
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
  window.ADspaceSettings = { enter: function () { wire(); enter(); }, paint: paint, urlState: urlState, allowed: allowed, say: say, rows: rows, focusRow: focusRow };
  if (bridge.settingsReady) bridge.settingsReady();
})();
