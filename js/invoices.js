/* Overdue invoices (2026-10-28; the user: "pull those overdues data from
 * bukku and inside Portal and selectively send by users"): Clients' second
 * view, read from Bukku through `bukku-sync` when it opens and on Read
 * again, never stored. Every unpaid invoice past its date, held by the
 * server to the clients the colleague sees, worst first, in a card for each
 * age, with each one's last reminder. Ticked invoices are reminded one
 * email a client: Review and send shows each email as it will arrive
 * (Edit changes its subject and message alone), and the server reads every
 * invoice from Bukku again before it builds the table and sends.
 *
 *   ADspaceInvoices.may()          — whether the view is offered
 *   ADspaceInvoices.on()           — whether it is on screen
 *   ADspaceInvoices.show(quiet)    — draws it (Clients' view strip)
 *   ADspaceInvoices.hide()         — gives the list back
 *   ADspaceInvoices.client(host, client, again) — a client's Unpaid
 *                                    invoices on its Billing: those past
 *                                    their date and those not yet due, with
 *                                    the reminders sent; Send reminder opens
 *                                    the same Review and send
 *   ADspaceInvoices.openTemplate(btn, say) — Settings' Overdue reminder
 *   ADspaceInvoices.templateLine() — Settings' value line
 */
(function () {
  'use strict';
  var API = window.ADspaceAPI;
  function db() { return API && API.client; }
  function $(id) { return document.getElementById(id); }
  function esc(s) { return window.ADspaceWords.esc(s); }
  function may(k, l) { var A = window.ADspaceAdmin; return Boolean(A && A.may && A.may(k, l)); }
  var UI = window.ADspaceState;
  var C = window.ADspaceClock;

  var SAID = {
    denied: 'This needs Clients: Billing.',
    'bukku-not-set-up': 'Bukku is not connected. Add its token and subdomain to the portal\'s secrets.',
    'bukku-token': 'Bukku refused the portal\'s token. Make a new one in Bukku and replace it in the secrets.',
    'bukku-unreachable': 'Bukku did not respond. Try again in a few minutes.',
    'bukku-refused': 'Bukku refused the request.',
    'mail-not-set-up': 'Email is not set up. Add the Resend key to the portal\'s secrets.',
    'needs-update': 'This needs a database update.',
    'no-email': 'No email address is held for this client. Add one to its billing contact.',
    'nothing-overdue': 'These invoices are no longer overdue.',
    sending: 'A reminder to this client is being sent. Read again in a minute to see its status.',
    'bad-subject': 'The subject must be 2 to 200 characters.',
    'bad-body': 'The message must be 2 to 5,000 characters.',
    'no-invoices': 'The message must keep {invoices}, where the table of invoices goes.',
    'too-long': 'The legal note and the disclaimer hold 1,000 characters each.',
    'not-sent': 'Not sent. Resend refused the email.',
    'not-confirmed': 'Not confirmed. Check the record before sending again.',
    'bad-request': 'The invoices changed after they were read. Read again, then send.',
    failed: 'The request failed. Try again.'
  };
  function said(d) { return (d && SAID[d.error]) || (d && d.error) || SAID.failed; }

  function call(body) {
    return db().functions.invoke('bukku-sync', { body: body }).then(function (r) {
      /* A refusal in the answer keeps what came with it (recent, paid). */
      if (r && r.data && r.data.error) return r.data;
      return API.fnRefusal(r).then(function (code) {
        if (code) return { error: code };
        return r.data || { error: 'failed' };
      });
    }, function () { return { error: 'failed' }; });
  }
  function rpc(fn, args) {
    return db().rpc(fn, args || {}).then(function (r) {
      if (r.error) return { error: /could not find|does not exist|schema cache/i.test(r.error.message || '') ? 'needs-update' : 'failed' };
      return r.data || {};
    }, function () { return { error: 'failed' }; });
  }

  /* ---- Words ------------------------------------------------------------ */
  function money(n, cur) {
    var v = Math.round((Number(n) || 0) * 100) / 100;
    return (cur === 'SGD' ? 'S$ ' : cur === 'MYR' || !cur ? 'RM ' : cur + ' ') +
      v.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }
  /* Totals are kept per currency, never added across (RM, then S$). */
  function totals(rows) {
    var by = {};
    rows.forEach(function (l) { by[l.currency] = Math.round(((by[l.currency] || 0) + l.amount) * 100) / 100; });
    return Object.keys(by).sort(function (a, b) { return a === 'MYR' ? -1 : b === 'MYR' ? 1 : a < b ? -1 : 1; })
      .map(function (c) { return money(by[c], c); });
  }
  function day(d) { return d && C ? C.date(d.length === 10 ? d + 'T00:00:00+08:00' : d) : ''; }
  function when(iso) { return iso && C ? C.date(iso).replace(/ \d{4}$/, '') + ', ' + C.clock(iso) : ''; }
  var STATUS = { sending: ['Sending', 'is-warn'], sent: ['Sent', 'is-live'], delivered: ['Delivered', 'is-live'],
    opened: ['Opened', 'is-ok'], bounced: ['Bounced', 'is-danger'], complained: ['Marked as spam', 'is-danger'],
    failed: ['Not sent', 'is-danger'], unknown: ['Not confirmed', 'is-warn'] };
  function statusOf(e) { return STATUS[e.status] || [e.status, '']; }
  function nameOf(l) { return l.client_name || l.contact_name || 'Bukku contact'; }
  function plural(n, one, many) { return n + ' ' + (n === 1 ? one : many); }

  /* ---- State ------------------------------------------------------------ */
  var st = { on: false, rows: null, err: null, rem: [], send: false, pick: {}, q: '', loading: false, wired: false };
  var BUCKETS = [['over90', 'Over 90 days', 91, 1e9], ['61', '61 to 90 days', 61, 90], ['31', '31 to 60 days', 31, 60], ['1', '1 to 30 days', 1, 30]];
  function bucketOf(d) { for (var i = 0; i < BUCKETS.length; i++) if (d >= BUCKETS[i][2] && d <= BUCKETS[i][3]) return BUCKETS[i][0]; return '1'; }
  /* The newest reminder naming each invoice. */
  function lastOf(id) {
    for (var i = 0; i < st.rem.length; i++) {
      var e = st.rem[i];
      if ((e.invoices || []).some(function (x) { return Number(x.id) === Number(id); })) return e;
    }
    return null;
  }
  function sentTo(contact) { return (rv.rem || []).filter(function (e) { return Number(e.contact) === Number(contact); }); }

  /* ---- The view --------------------------------------------------------- */
  function mayView() { return may('clients.billing', 'view') && Boolean(window.ADspaceAPI && API.client); }
  function strip(on) {
    var box = $('crmViewsBox');
    if (!box) return;
    box.hidden = !mayView();
    /* The strip answers from the list too, before the view has been shown. */
    if (!box.hidden) wire();
    Array.prototype.forEach.call(document.querySelectorAll('#crmViews .acttab'), function (b) {
      var me = b.getAttribute('data-cv') === (on ? 'overdue' : 'list');
      b.classList.toggle('is-on', me);
      b.setAttribute('aria-pressed', String(me));
    });
    if (window.ADspaceForm && window.ADspaceForm.thumb) window.ADspaceForm.thumb($('crmViews'));
  }
  function wire() {
    if (st.wired) return;
    st.wired = true;
    $('crmViews').addEventListener('click', function (e) {
      var b = e.target.closest && e.target.closest('.acttab');
      if (!b) return;
      if (b.getAttribute('data-cv') === 'overdue') { if (!st.on) show(); }
      else if (st.on) { hide(); if (window.ADspaceCRM && window.ADspaceCRM.showList) window.ADspaceCRM.showList(); }
    });
    $('odFind').addEventListener('input', function () { st.q = this.value.trim().toLowerCase(); paint(); });
    $('odRead').addEventListener('click', function () { load(true); });
    $('odBulkAll').addEventListener('change', function () {
      var on = this.checked;
      shown().forEach(function (l) { if (on) st.pick[l.id] = true; else delete st.pick[l.id]; });
      paint();
    });
    $('odBulkDone').addEventListener('click', function () { st.pick = {}; paint(); });
    $('odBulkSend').addEventListener('click', function () {
      review(this, (st.rows || []).filter(function (l) { return st.pick[l.id]; }), function () { st.pick = {}; load(true); }, st.rem);
    });
    $('odSheetClose').addEventListener('click', function () { $('odCancel').click(); });
    $('odCancel').addEventListener('click', shutReview);
    $('odGo').addEventListener('click', sendAll);
  }
  function show(quiet) {
    if (!mayView()) return false;
    wire();
    st.on = true;
    $('crmListView').hidden = true;
    $('odView').hidden = false;
    strip(true);
    var A = window.ADspaceAdmin;
    if (!quiet && A && A.setUrl) A.setUrl();
    load(false);
    return true;
  }
  function hide() {
    st.on = false;
    if ($('odView')) $('odView').hidden = true;
    strip(false);
  }
  function load(again) {
    if (st.loading) return;
    if (!st.rows || again) UI.skeleton($('odList'), 4);
    st.loading = true;
    $('odRead').disabled = true;
    call({ action: 'invoices' }).then(function (d) {
      st.loading = false;
      $('odRead').disabled = false;
      if (d.error) { st.err = d; st.rows = null; paint(); return; }
      st.err = null;
      st.rows = d.rows || [];
      st.rem = d.reminders || [];
      st.send = d.send === true;
      var have = {};
      st.rows.forEach(function (l) { have[l.id] = true; });
      Object.keys(st.pick).forEach(function (k) { if (!have[k]) delete st.pick[k]; });
      paint();
    });
  }
  function shown() {
    var q = st.q;
    return (st.rows || []).filter(function (l) {
      if (!q) return true;
      return [nameOf(l), l.client_code || '', l.number].join(' ').toLowerCase().indexOf(q) > -1;
    });
  }
  function paint() {
    var list = $('odList');
    if (!st.on || !list) return;
    if (st.err) {
      $('odTallies').hidden = true; $('odBulk').hidden = true; $('odCount').textContent = '';
      UI.failLine(list, 'The overdue invoices', said(st.err), function () { load(true); });
      return;
    }
    if (!st.rows) return;
    var rows = shown();
    var clients = {};
    rows.forEach(function (l) { clients[l.contact] = true; });
    $('odCount').textContent = rows.length ? plural(rows.length, 'invoice', 'invoices') + ' · ' + plural(Object.keys(clients).length, 'client', 'clients') : '';
    paintTallies(rows);
    paintBulk(rows);
    list.innerHTML = '';
    if (!rows.length) { UI.emptyLine(list, st.q ? 'No matches.' : 'No overdue invoices.'); return; }
    BUCKETS.forEach(function (b) {
      var items = rows.filter(function (l) { return bucketOf(l.days) === b[0]; });
      if (!items.length) return;
      var G = window.ADspaceGroup;
      list.appendChild(G.section({
        route: 'overdue', key: b[0], name: b[1], count: items.length,
        marks: '<span class="inv-sum">' + esc(totals(items).join(' · ')) + '</span>',
        shut: st.q ? false : G.shut('overdue', b[0], false),
        table: function () {
          var t = document.createElement('div');
          t.className = 'crm-table softpanel inv-table' + (st.send ? ' can-pick' : '');
          t.innerHTML = '<div class="inv-row crm-head">' + (st.send ? '<span></span>' : '') +
            '<span>Client · Invoice</span><span class="inv-amt">Overdue amount</span><span>Due date</span><span>Overdue</span><span>Last reminded</span></div>';
          G.more(t, items, 30, '', rowOf);
          return t;
        }
      }));
    });
  }
  function paintTallies(rows) {
    var box = $('odTallies');
    box.hidden = !rows.length;
    if (!rows.length) return;
    var cell = function (name, items, warn) {
      var t = totals(items);
      return '<div class="tally-cell' + (warn ? " is-total" : "") + '"><span>' + esc(name) + '</span>' +
        (t.length ? t.map(function (x) { return '<b>' + esc(x) + '</b>'; }).join('') : '<b class="muted">—</b>') + '</div>';
    };
    box.innerHTML = '<div class="tally inv-tally">' + cell("Overdue", rows, true) +
      BUCKETS.slice().reverse().map(function (b) {
        return cell(b[1], rows.filter(function (l) { return bucketOf(l.days) === b[0]; }));
      }).join('') + '</div>';
  }
  function paintBulk(rows) {
    var ids = Object.keys(st.pick);
    var bar = $('odBulk');
    bar.hidden = !st.send || !ids.length;
    if (bar.hidden) return;
    var picked = (st.rows || []).filter(function (l) { return st.pick[l.id]; });
    var cl = {};
    picked.forEach(function (l) { cl[l.contact] = true; });
    $('odBulkCount').textContent = picked.length + ' selected · ' + plural(Object.keys(cl).length, 'client', 'clients');
    var all = $('odBulkAll');
    var on = rows.filter(function (l) { return st.pick[l.id]; }).length;
    all.checked = on > 0 && on === rows.length;
    all.indeterminate = on > 0 && on < rows.length;
  }
  var OUT = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 5h5v5"/><path d="M19 5l-8 8"/><path d="M18 14v5H5V6h5"/></svg>';
  function rowOf(l) {
    var row = document.createElement(st.send ? 'label' : 'div');
    row.className = 'inv-row' + (st.pick[l.id] ? ' is-picked' : '');
    var e = lastOf(l.id), s = e ? statusOf(e) : null;
    var meta = esc(l.number) + (l.part ? ' · Instalment ' + l.part.n + ' of ' + l.part.of : '') +
      (l.client ? '' : ' · Not linked to a client');
    row.innerHTML = (st.send ? '<span class="inv-tick"><input type="checkbox"' + (st.pick[l.id] ? ' checked' : '') +
        ' aria-label="' + esc(l.number + ', ' + nameOf(l)) + '"></span>' : '') +
      '<span class="inv-who"><b>' + esc(nameOf(l)) + '</b><small>' + meta + '</small></span>' +
      '<span class="inv-amt">' + esc(money(l.amount, l.currency)) +
        (l.amount < l.balance ? '<small>of ' + esc(money(l.balance, l.currency)) + '</small>' : '') + '</span>' +
      '<span class="inv-due">' + esc(day(l.due)) + '</span>' +
      '<span class="inv-days">' + esc(plural(l.days, 'day', 'days')) + '</span>' +
      '<span class="inv-last">' + (e ? '<span class="chip-state chip ' + s[1] + '">' + esc(s[0] + ' ' + C.date(e.at).replace(/ \d{4}$/, '')) + '</span>' +
          (e.status === 'bounced' && l.client ? '<button class="linkbtn inv-fix" type="button">Open contacts</button>' : '')
        : '<span class="muted">Not reminded</span>') +
        (l.link ? '<a class="linkbtn inv-open" href="' + esc(l.link) + '" target="_blank" rel="noopener">Open in Bukku' + OUT + '</a>' : '') + '</span>';
    var box = row.querySelector('input');
    if (box) box.addEventListener('change', function () { if (box.checked) st.pick[l.id] = true; else delete st.pick[l.id]; row.classList.toggle('is-picked', box.checked); paintBulk(shown()); });
    var fix = row.querySelector('.inv-fix');
    if (fix) fix.addEventListener('click', function (ev) { ev.preventDefault(); openClient(l, 'account'); });
    var open = row.querySelector('.inv-open');
    if (open) open.addEventListener('click', function (ev) { ev.stopPropagation(); });
    return row;
  }
  function openClient(l, tab) {
    if (!l.client) return;
    history.pushState(null, '', '/admin/?client=' + encodeURIComponent(l.client_slug || l.client) + (tab ? '&tab=' + tab : ''));
    hide();
    var A = window.ADspaceAdmin;
    if (A && A.restore) A.restore(); else location.reload();
  }

  /* ---- Review and send -------------------------------------------------- */
  var rv = { groups: [], on: 0, tpl: null, edits: {}, opener: null, done: {}, after: null, rem: [] };
  /* The sheet the Overdue invoices bar and a client's Billing both open:
     `after` reads again what a send changed. */
  function review(btn, picked, after, rem) {
    if (!picked || !picked.length) return;
    rv.after = after || null;
    rv.rem = rem || [];
    var by = {};
    rv.groups = [];
    picked.forEach(function (l) {
      if (!by[l.contact]) { by[l.contact] = { contact: l.contact, name: nameOf(l), lines: [], to: l.to || null, email: l.contact_email, client: l.client, cc: true }; rv.groups.push(by[l.contact]); }
      by[l.contact].lines.push(l);
    });
    rv.groups.forEach(function (g) { g.lines.sort(function (a, b) { return a.due < b.due ? -1 : a.due > b.due ? 1 : 0; }); });
    rv.on = 0; rv.edits = {}; rv.done = {}; rv.opener = btn || null;
    $('odMsg').textContent = ''; $('odMsg').className = 'msg';
    $('odGo').disabled = false;
    rpc('invoice_email_template_get').then(function (t) {
      if (t.error) { $('odMsg').textContent = said(t); $('odMsg').className = 'msg err'; return; }
      rv.tpl = t;
      paintReview();
    });
    paintReview();
    if (window.ADspaceSheet) window.ADspaceSheet.show($('odSheet'), { opener: btn, onClose: afterReview }); else $('odSheet').hidden = false;
  }
  function shutReview() {
    if (window.ADspaceSheet && window.ADspaceSheet.isOpen($('odSheet'))) window.ADspaceSheet.close();
    else { $('odSheet').hidden = true; afterReview(); }
  }
  /* What was sent is read back from Bukku and the record. */
  function afterReview() {
    if (!Object.keys(rv.done).length) return;
    rv.done = {};
    if (rv.after) rv.after();
  }
  /* The words a client's email will carry, filled as the server fills
     them: {contact name}, {client}, {invoice no}, {count}, {total} and
     {sign off}; {invoices} is the table. */
  function filled(g) {
    var t = rv.tpl || {};
    var ed = rv.edits[g.contact] || {};
    var n = g.lines.length;
    var nos = g.lines.map(function (l) { return l.number; });
    var who = (g.to && g.to.name) || null;
    var v = {
      'contact name': who || (g.to && g.to.company) || g.name,
      client: (g.to && g.to.company) || g.name,
      'invoice no': n === 1 ? nos[0] : nos.slice(0, -1).join(', ') + ' and ' + nos[n - 1],
      count: String(n),
      total: totals(g.lines).map(function (x) { return x.replace(' ', '\u00a0'); }).join(' and '),
      'sign off': who ? 'Yours sincerely' : 'Yours faithfully'
    };
    var fill = function (s) {
      return String(s || '').replace(/\{\s*([a-z ]+?)\s*\}/gi, function (m, k) { var key = k.toLowerCase().replace(/\s+/g, ' '); return v[key] != null ? v[key] : m; });
    };
    return { subject: fill(ed.subject || (n === 1 ? t.subject_one : t.subject_many)), body: fill(ed.body || t.body), raw: ed };
  }
  function toOf(g) { return (g.to && g.to.email) || g.email || ''; }
  function ccOf(g) { return g.to && g.to.cc && g.to.cc.toLowerCase() !== toOf(g).toLowerCase() ? g.to.cc : ''; }
  function paintReview() {
    var list = $('odRvList'), pv = $('odRvPane');
    list.innerHTML = rv.groups.map(function (g, i) {
      var d = rv.done[g.contact];
      return '<button class="inv-rv-row' + (i === rv.on ? ' is-on' : '') + '" type="button" data-i="' + i + '" aria-pressed="' + (i === rv.on) + '">' +
        '<b>' + esc(g.name) + '</b><small>' + esc(g.lines.length === 1 ? g.lines[0].number : plural(g.lines.length, 'invoice', 'invoices')) +
        ' · ' + esc(totals(g.lines).join(' · ')) + '</small>' +
        (d ? '<span class="chip-state chip ' + (d.ok ? 'is-live' : 'is-danger') + '">' + esc(d.ok ? 'Sent' : 'Not sent') + '</span>' : '') + '</button>';
    }).join('');
    Array.prototype.forEach.call(list.querySelectorAll('.inv-rv-row'), function (b) {
      b.addEventListener('click', function () { rv.on = Number(b.getAttribute('data-i')); paintReview(); });
    });
    var g = rv.groups[rv.on];
    if (!g) { pv.innerHTML = ''; return; }
    var f = filled(g), to = toOf(g), cc = ccOf(g), d = rv.done[g.contact];
    var paras = String(f.body).replace(/\r/g, '').replace(/\{\s*invoices\s*\}/i, '\n\n{invoices}\n\n').split(/\n\s*\n/).map(function (p) { return p.trim(); }).filter(Boolean);
    var table = '<div class="inv-mail-t"><div class="r hd"><span>Invoice</span><span>Due</span><span class="n">Amount due</span>' +
      (g.lines.length > 1 ? '<span></span>' : '') + '</div>' +
      g.lines.map(function (l) {
        return '<div class="r"><span>' + esc(l.number) + (l.part ? '<small>Instalment ' + l.part.n + ' of ' + l.part.of + '</small>' : '') + '</span>' +
          '<span>' + esc(day(l.due)) + '</span><span class="n">' + esc(money(l.amount, l.currency)) + '</span>' +
          (g.lines.length > 1 ? '<span class="lk">View PDF</span>' : '') + '</div>';
      }).join('') +
      '<div class="r tot"><span>Total due</span><span></span><span class="n">' + esc(totals(g.lines).join(' · ')) + '</span>' + (g.lines.length > 1 ? '<span></span>' : '') + '</div></div>' +
      (g.lines.length === 1 && g.lines[0].link ? '<span class="inv-mail-btn">View PDF</span>' : '');
    var mail = '<div class="inv-mail"><div class="inv-mail-card"><div class="inv-mail-mark">ADspace</div>' +
      '<h4>' + esc(String(f.subject).split(/\s+·\s+/)[0]) + '</h4>' +
      paras.map(function (p) { return /^\{\s*invoices\s*\}$/i.test(p) ? table : '<p>' + esc(p).replace(/\n/g, '<br>') + '</p>'; }).join('') +
      '<p class="inv-mail-fine">' + esc((rv.tpl && rv.tpl.legal) || '') + '</p>' +
      '<p class="inv-mail-fine">' + esc((rv.tpl && rv.tpl.disclaimer) || '') + '</p></div></div>';
    var sent = sentTo(g.contact);
    var log = sent.length ? '<div class="inv-log"><h4 class="fsec-h">Sent before</h4><div class="inv-log-t">' +
      '<div class="r hd"><span>When</span><span>Channel</span><span>Sent by</span><span>Status</span></div>' +
      sent.slice(0, 8).map(function (e) {
        var s = statusOf(e);
        return '<div class="r"><span class="w">' + esc(when(e.at)) + '</span><span class="c">Email</span><span class="b">' + esc(e.by || 'Not known') + '</span>' +
          '<span><span class="chip-state chip ' + s[1] + '">' + esc(s[0]) + '</span></span></div>';
      }).join('') + '</div></div>' : '';
    pv.innerHTML = '<div class="inv-rv-head"><dl class="ovfacts">' +
        '<dt>To</dt><dd>' + (to ? esc(((g.to && g.to.name) ? g.to.name + ' · ' : '') + to) : '<span class="err-ink">No email address held</span>') + '</dd>' +
        (cc ? '<dt>Copy</dt><dd><label class="tickline"><input type="checkbox" data-cc' + (g.cc ? ' checked' : '') + '> ' + esc(cc) + '</label></dd>' : '') +
        '<dt>Subject</dt><dd>' + esc(f.subject) + '</dd></dl>' +
        (d ? '' : '<button class="btn btn-sm" type="button" data-a="edit"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 20h4L19 9l-4-4L4 16v4Z"/></svg>Edit</button>') + '</div>' +
      (d ? '<p class="msg ' + (d.ok ? 'ok' : 'err') + '">' + esc(d.text) + '</p>' : '') +
      mail + log;
    var ccBox = pv.querySelector('[data-cc]');
    if (ccBox) ccBox.addEventListener('change', function () { g.cc = ccBox.checked; });
    var ed = pv.querySelector('[data-a="edit"]');
    if (ed) ed.addEventListener('click', function () { editOne(g, ed); });
    var left = rv.groups.filter(function (x) { return !(rv.done[x.contact] && rv.done[x.contact].ok); });
    var n = left.length;
    $('odGo').textContent = n ? 'Send ' + plural(n, 'email', 'emails') : 'Done';
    var lines = [];
    left.forEach(function (x) { lines = lines.concat(x.lines); });
    $('odRvCount').textContent = n ? plural(lines.length, 'invoice', 'invoices') + ' · ' + plural(n, 'client', 'clients') + ' · ' + totals(lines).join(' · ') : '';
  }
  function editOne(g, btn) {
    var t = rv.tpl || {}, ed = rv.edits[g.contact] || {}, n = g.lines.length;
    window.ADspaceConfirm.ask({
      title: 'Edit email', go: 'Done',
      body: 'For ' + g.name + ' alone. {invoices} is where the table of invoices goes.',
      fields: [{ name: 'subject', label: 'Subject', value: ed.subject || (n === 1 ? t.subject_one : t.subject_many) || '' },
        { name: 'body', label: 'Message', rows: 12, value: ed.body || t.body || '' }],
      check: function (v) {
        if (String(v.subject || '').trim().length < 2) return SAID['bad-subject'];
        if (!/\{\s*invoices\s*\}/i.test(String(v.body || ''))) return SAID['no-invoices'];
        return '';
      }
    }, function (v) {
      rv.edits[g.contact] = { subject: String(v.subject || '').trim(), body: String(v.body || '').trim() };
      paintReview();
      if (btn && btn.focus) btn.focus();
    });
  }
  function sendAll() {
    var left = rv.groups.filter(function (x) { return !(rv.done[x.contact] && rv.done[x.contact].ok); });
    if (!left.length) { shutReview(); return; }
    var hours = window.ADspaceMoney && window.ADspaceMoney.setting ? Number(window.ADspaceMoney.setting('wa_repeat_hours')) : 24;
    if (!(hours >= 0)) hours = 24;
    var since = Date.now() - hours * 3600e3;
    var recent = left.filter(function (g) { return hours > 0 && sentTo(g.contact).some(function (e) { return e.status !== 'failed' && Date.parse(e.at) > since; }); });
    var names = left.map(function (g) { return g.name + ' (' + (toOf(g) || 'no email') + ')'; });
    window.ADspaceConfirm.ask({
      title: 'Send ' + plural(left.length, 'reminder', 'reminders') + '?',
      body: names.join(', ') + '.' + (recent.length ? ' ' + recent.map(function (g) { return g.name; }).join(', ') +
        (recent.length === 1 ? ' was' : ' were') + ' reminded in the last ' + plural(hours, 'hour', 'hours') + '.' : ''),
      go: recent.length ? 'Send again' : 'Send', tone: recent.length ? 'warn' : undefined
    }, function () { run(left, recent); });
  }
  function run(left, recent) {
    var go = $('odGo');
    go.disabled = true;
    if (window.ADspaceActs && window.ADspaceActs.busy) window.ADspaceActs.busy(go, true);
    var i = 0;
    var next = function () {
      if (i >= left.length) {
        go.disabled = false;
        if (window.ADspaceActs && window.ADspaceActs.busy) window.ADspaceActs.busy(go, false);
        var bad = left.filter(function (g) { return !rv.done[g.contact].ok; }).length;
        $('odMsg').textContent = bad ? plural(left.length - bad, 'email', 'emails') + ' sent. ' + bad + ' not sent. The reason is shown against each client.' : 'Sent.';
        $('odMsg').className = 'msg ' + (bad ? 'warn' : 'ok');
        var firstBad = rv.groups.findIndex ? rv.groups.findIndex(function (g) { return rv.done[g.contact] && !rv.done[g.contact].ok; }) : -1;
        if (firstBad > -1) rv.on = firstBad;
        paintReview();
        return;
      }
      var g = left[i++];
      var ed = rv.edits[g.contact] || {};
      call({ action: 'remind', contact: g.contact, invoices: g.lines.map(function (l) { return l.id; }), cc: g.cc !== false,
        subject: ed.subject || '', body: ed.body || '', again: recent.indexOf(g) > -1 }).then(function (d) {
        var paid = (d.paid || []).length ? ' Not included, as already paid: ' + d.paid.join(', ') + '.' : '';
        if (d.ok) rv.done[g.contact] = { ok: true, text: 'Sent to ' + d.to + (d.cc ? ', copy to ' + d.cc : '') + '.' + paid };
        else if (d.error === 'recent') {
          /* Sent meanwhile by somebody else: kept here, so the next Send asks
             Send again for this client alone. */
          if (d.recent) rv.rem = [{ contact: g.contact, status: d.recent.status || 'sent', at: d.recent.at, by: d.recent.by, to: d.recent.to }].concat(rv.rem || []);
          rv.done[g.contact] = { ok: false, text: 'Reminded ' + when(d.recent && d.recent.at) + (d.recent && d.recent.by ? ' by ' + d.recent.by : '') + '. Not sent again.' };
        }
        else rv.done[g.contact] = { ok: false, text: said(d) + paid };
        paintReview();
        next();
      });
    };
    next();
  }

  /* ---- A client's Billing: its unpaid invoices ----------------------- */
  /* Read from Bukku when Billing is shown and once a visit, never stored:
     the client's Bukku contacts alone, overdue first then by due date, each
     with its last reminder; then every reminder sent, as a table. A client
     linked to no Bukku contact draws nothing. */
  var cg = { host: null, client: null, d: null, busy: false };
  function clientGroup(host, client, again) {
    if (!host || !client) return;
    if (!mayView()) { host.hidden = true; return; }
    if (cg.client === client.id && cg.host === host && !again && (cg.d || cg.busy)) return;
    cg.host = host; cg.client = client.id; cg.d = null; cg.busy = true;
    host.hidden = false;
    host.innerHTML = '<div class="readgroup-head"><h4 class="fsec-h">Unpaid invoices</h4></div>';
    var body = document.createElement('div');
    host.appendChild(body);
    UI.skeleton(body, 2);
    call({ action: 'invoices', client: client.id }).then(function (d) {
      if (cg.client !== client.id) return;
      cg.busy = false;
      if (d.error) {
        UI.failLine(body, 'The unpaid invoices', said(d), function () { clientGroup(host, client, true); });
        return;
      }
      if (d.linked === false) { host.hidden = true; host.innerHTML = ''; return; }
      cg.d = d;
      paintClient(host, client, d);
    });
  }
  function paintClient(host, client, d) {
    var rows = d.rows || [], rem = d.reminders || [];
    var late = rows.filter(function (l) { return l.days > 0; });
    var lastFor = function (id) {
      for (var i = 0; i < rem.length; i++) if ((rem[i].invoices || []).some(function (x) { return Number(x.id) === Number(id); })) return rem[i];
      return null;
    };
    host.innerHTML = '<div class="readgroup-head"><h4 class="fsec-h">Unpaid invoices</h4>' +
      (d.send && late.length ? '<button class="btn btn-sm" type="button" data-a="remind">Send reminder</button>' : '') + '</div>' +
      (rows.length ? '<div class="od-mini">' + rows.map(function (l) {
        var e = lastFor(l.id), s = e ? statusOf(e) : null;
        return '<div class="od-crow"><span class="od-who"><b>' + esc(l.number) + (l.part ? ' · Instalment ' + l.part.n + ' of ' + l.part.of : '') + '</b>' +
          '<small>Due ' + esc(day(l.due)) + (l.days > 0 ? ' · <span class="od-late">' + esc(plural(l.days, 'day', 'days')) + ' overdue</span>' : ' · Not due') + '</small></span>' +
          '<span class="od-amt">' + esc(money(l.amount, l.currency)) + '</span>' +
          '<span class="od-st">' + (e ? '<span class="chip-state chip ' + s[1] + '">' + esc(s[0] + ' ' + C.date(e.at).replace(/ \d{4}$/, '')) + '</span>' : '') + '</span></div>';
      }).join('') + '</div>' : '<p class="muted od-none">No unpaid invoices.</p>') +
      (rem.length ? '<h4 class="fsec-h od-sent-h">Reminders sent</h4><div class="inv-log-t od-log">' +
        '<div class="r hd"><span>When</span><span>Invoices</span><span>Sent by</span><span>Status</span></div>' +
        rem.slice(0, 10).map(function (e) {
          var s = statusOf(e);
          return '<div class="r"><span class="w">' + esc(when(e.at)) + '</span><span class="c">' + esc((e.invoices || []).map(function (x) { return x.number; }).join(', ')) + '</span>' +
            '<span class="b">' + esc(e.by || 'Not known') + '</span><span><span class="chip-state chip ' + s[1] + '">' + esc(s[0]) + '</span></span></div>';
        }).join('') + '</div>' : '');
    var b = host.querySelector('[data-a="remind"]');
    if (b) b.addEventListener('click', function () {
      review(b, late.slice(), function () { clientGroup(host, client, true); }, rem);
    });
  }

  /* ---- The Dashboard's Needs attention ------------------------------- */
  /* Every client owing past its date, once: the worst invoice's days and
     the count, never an amount (the Dashboard's one money figure is
     Committed monthly value). Bukku not connected owes nothing. */
  function overdue() {
    return call({ action: 'invoices' }).then(function (d) {
      if (d.error === 'bukku-not-set-up') return [];
      if (d.error) throw new Error(said(d));
      var by = {}, out = [];
      (d.rows || []).forEach(function (l) {
        var g = by[l.contact];
        if (!g) { g = by[l.contact] = { client: l.client || null, slug: l.client_slug || null, name: nameOf(l), lines: [], days: 0 }; out.push(g); }
        g.lines.push(l);
        if (l.days > g.days) g.days = l.days;
      });
      return out.map(function (g) {
        return { client: g.client, slug: g.slug, name: g.name, days: g.days,
          meta: plural(g.lines.length, 'overdue invoice', 'overdue invoices') };
      });
    });
  }

  /* ---- Settings: Overdue reminder --------------------------------------- */
  function templateLine() {
    return rpc('invoice_email_template_get').then(function (t) {
      if (t.error) throw new Error(t.error);
      return t.updated_by ? 'Changed ' + C.date(t.updated_at) + ' by ' + t.updated_by : 'Standard wording';
    });
  }
  function openTemplate(btn, say) {
    rpc('invoice_email_template_get').then(function (t) {
      if (t.error) { if (say) say(said(t), 'err'); return; }
      window.ADspaceConfirm.ask({
        title: 'Overdue reminder', go: 'Save', wait: true,
        body: 'Fields: {contact name}, {client}, {invoice no}, {count}, {total}, {sign off}. {invoices} is where the table of invoices goes.',
        fields: [{ name: 'one', label: 'Subject, one invoice', value: t.subject_one || '' },
          { name: 'many', label: 'Subject, several invoices', value: t.subject_many || '' },
          { name: 'body', label: 'Message', rows: 12, value: t.body || '' },
          { name: 'legal', label: 'Legal note', rows: 3, value: t.legal || '', required: false },
          { name: 'disclaimer', label: 'Disclaimer', rows: 3, value: t.disclaimer || '', required: false }],
        check: function (v) { return /\{\s*invoices\s*\}/i.test(String(v.body || '')) ? '' : SAID['no-invoices']; }
      }, function (v) {
        return rpc('invoice_email_template_save', { p_subject_one: String(v.one || '').trim(), p_subject_many: String(v.many || '').trim(),
          p_body: String(v.body || '').trim(), p_legal: String(v.legal || '').trim(), p_disclaimer: String(v.disclaimer || '').trim() })
          .then(function (d) {
            if (d.error) return said(d);
            if (say) say('Saved.', 'ok');
            return '';
          });
      });
    });
  }

  window.ADspaceInvoices = {
    may: mayView,
    on: function () { return st.on; },
    show: show,
    hide: hide,
    strip: strip,
    client: clientGroup,
    overdue: overdue,
    openTemplate: openTemplate,
    templateLine: templateLine
  };
})();
