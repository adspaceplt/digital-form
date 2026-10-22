/*
 * Suppliers — a section of its own (2026-10-18; the user: "documents also
 * need to issue to supplier"; the Jotform supplier sign-up "could jump into
 * the fill in via portal and data sync into it similar as client billing";
 * "invite only, with create link and set the supplier id before sending";
 * "nric only for individuals"; then "own section", and on the name: "i
 * wont know the company name first lol, needs them to fill in").
 *
 * The team gives a supplier its Supplier ID (New supplier), sends the
 * link it makes (`/supplier/?k=`), and takes the answers in with Use
 * details and its own Save, as a client's Billing takes its details form.
 * Approve moves a supplier with its details whole from Pending to Active.
 * The NRIC and the bank details are read only at Documents: Supplier bank
 * details (`suppliers.pay`, granted, an admin's by itself); the database
 * never sends them otherwise. A supplier's letters are issued from its
 * record through Documents' own sheet (family `supplier`). Until its form
 * names it, a supplier reads as its Supplier ID.
 */
(function () {
  var API = window.ADspaceAPI;
  var db = API && API.client;
  var UI = window.ADspaceState;
  var bridge = window.ADspaceAdmin || {};
  if (!API || !API.configured || !db || !UI) return;

  function $(id) { return document.getElementById(id); }
  var esc = UI.esc || function (s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  };
  function may(k, l) { return Boolean(bridge.may && bridge.may(k, l)); }
  function day(iso) { return iso ? window.ADspaceClock.date(iso) : ''; }
  function msg(id, text, kind) { var m = $(id); if (!m) return; m.textContent = text || ''; m.className = 'msg' + (kind && text ? ' ' + kind : ''); }

  var BANKS = ['Maybank', 'CIMB', 'Hong Leong Bank', 'RHB', 'BSN', 'UOB', 'OCBC', 'AmBank', 'Bank Islam', 'Public Bank',
    'Alliance Bank', 'Standard Chartered Bank', 'Touch N Go Digital', '[SG] DBS/POSB', '[SG] OCBC', '[SG] UOB', '[SG] CIMB',
    '[SG] Maybank', '[SG] Bank of China'];
  var TERMS = ['NET 7', 'NET 14', 'NET 30', 'NET 45', 'NET 60'];
  var STATE = { pending: ['Pending', 'is-warn'], active: ['Active', 'is-ok'], inactive: ['Inactive', 'is-off'] };
  var SAID = {
    'denied': 'You do not have permission to do this.', 'not-found': 'That supplier is no longer there.',
    'bad-code': 'A Supplier ID is 2 to 12 letters or digits, as AS001.', 'code-taken': 'Another supplier holds that Supplier ID.',
    'bad-name': 'Enter the name, 2 to 160 characters.', 'bad-kind': 'Choose how the supplier is registered.',
    'bad-brn': 'Enter the 12-digit BRN.', 'bad-nric': 'Enter the NRIC as XXXXXX-XX-XXXX.', 'bad-tin': 'Enter the TIN, 5 to 20 letters or digits.',
    'bad-sst_no': 'Enter the SST no. as AXX-XXXX-XXXXXXXX.', 'bad-phone': 'Enter a Malaysian or Singapore number, as 07-123 4567.',
    'bad-mobile': 'Enter a Malaysian or Singapore mobile number, as 012-345 6789.', 'bad-address': 'Enter the full billing address.',
    'bad-contact_name': 'Enter the legal name.', 'bad-designation': 'Enter the designation.', 'bad-email': 'Enter a valid email.',
    'bad-finance_email': 'Enter a valid finance email.', 'bad-payment_term': 'Choose a payment term.', 'bad-currency': 'Choose a currency.',
    'bad-payee_name': 'Enter the payee name.', 'bad-bank_name': 'Choose a bank.', 'bad-bank_account': 'Enter the account number, digits only.',
    'bad-swift': 'Enter the SWIFT code, 8 or 11 letters or digits.', 'bad-bank_address': 'The bank address is up to 300 characters.',
    'incomplete': 'Approve once the details, the payment term and the bank account are saved.',
    'no-email': 'Save the supplier\'s email first.', 'not-active': 'Approve the supplier first.',
    'bad-document': 'That letter is void or no longer this supplier\'s.', 'bad-purpose': 'Choose a template.',
    'bad-subject': 'Enter a subject, 2 to 200 characters.', 'bad-body': 'Enter the message, 2 to 5,000 characters.',
    'bad-file': 'The letter could not be attached. Download it to check, then try again.',
    'mail-not-set-up': 'Email is not set up yet. Tell an admin.', 'not-sent': 'Not sent. Try again.',
    'not-confirmed': 'Not confirmed. Check with the supplier before sending again.', 'bad-request': 'Reload the page and try again.',
    'no-client': 'That client is no longer there or is outside your clients.',
    'no-link': 'No link is open.'
  };
  function said(r) {
    var m = r && r.error && (r.error.message || '');
    if (m && /could not find|does not exist|schema cache/i.test(m)) return 'This needs a database update.';
    var k = (r && r.data && r.data.error) || m;
    if (k === 'code-taken' && r.data.name) return 'Another supplier holds that Supplier ID: ' + r.data.name + '.';
    return SAID[k] || k || 'The request failed.';
  }
  function rpc(fn, args) {
    return db.rpc(fn, args).then(function (r) { return r; }).catch(function (e) { return { error: e }; });
  }
  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>';
  var CHEV = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>';
  var BACK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m15 6-6 6 6 6"/></svg>';

  var state = { pane: 'overview', rows: null, find: '', open: null, rec: null, form: null, wired: false };

  /* The record's pane rides in the address (`tab=`, Overview left out) and
     pushes history, as a colleague's record does (SUP-4, 2026-10-22). */
  var PANES = [['overview', 'Overview'], ['payment', 'Payment'], ['documents', 'Documents'], ['emails', 'Emails']];
  function paneOk(k) { return PANES.some(function (x) { return x[0] === k; }); }
  function urlState() { return { supplier: state.open || '', tab: state.open && state.pane !== 'overview' ? state.pane : '' }; }
  function setUrl() { if (bridge.setUrl) bridge.setUrl(); }
  /* What a supplier is called: its name, else its Supplier ID until its own
     form names it. */
  function nameOf(x) { return x.name || x.code; }
  function wire() {
    wireMail();
    if (state.wired) return;
    state.wired = true;
    $('supFind').addEventListener('input', function () {
      var v = this.value.trim().toLowerCase();
      if (v === state.find) return;
      state.find = v; paint();
    });
    $('supNew').addEventListener('click', create);
    $('supEditCancel').addEventListener('click', shutEdit);
    $('supEditClose').addEventListener('click', shutEdit);
    $('supEditGo').addEventListener('click', save);
    $('supEdKind').addEventListener('change', kindRows);
    window.addEventListener('popstate', function () {
      if ($('sectionSuppliers') && !$('sectionSuppliers').hidden) enter();
    });
  }
  /* The record open is read from the address. */
  function enter() {
    wire();
    var q = new URLSearchParams(location.search);
    state.open = q.get('supplier') || null;
    state.pane = state.open && paneOk(q.get('tab')) ? q.get('tab') : 'overview';
    $('supNew').hidden = !may('suppliers', 'work');
    load();
  }

  // ---- The list -------------------------------------------------------------
  function load() {
    var box = $('supList');
    if (!state.rows) UI.skeleton(box, 4);
    rpc('suppliers_list', {}).then(function (r) {
      var d = r.data || {};
      if (r.error || d.error) { state.rows = null; UI.failLine(box, 'the suppliers', said(r), load); return; }
      state.rows = d.rows || [];
      if (state.open) openRec(state.open); else paint();
    });
  }
  function matches(s) {
    if (!state.find) return true;
    return [s.code, s.name || '', s.contact_name, s.email].join(' ').toLowerCase().indexOf(state.find) > -1;
  }
  function chip(s, got) {
    var st = STATE[s.status] || STATE.pending;
    return '<span class="chip-state ' + st[1] + '">' + esc(s.waiting || got ? 'Details received' : st[0]) + '</span>';
  }
  function paint() {
    var box = $('supList'), rec = $('supRec');
    rec.hidden = true; box.hidden = false; $('supBar').hidden = false;
    if (!state.rows) return;
    var all = state.rows, rows = all.filter(matches);
    $('supCount').textContent = !all.length ? '' : rows.length === all.length
      ? all.length + (all.length === 1 ? ' supplier' : ' suppliers') : rows.length + ' of ' + all.length;
    if (!all.length) { UI.emptyLine(box, 'No suppliers.', may('suppliers', 'work') ? 'New supplier' : '', create); return; }
    if (!rows.length) {
      UI.emptyLine(box, 'No matches.', 'Clear the filters', function () { state.find = ''; $('supFind').value = ''; paint(); });
      return;
    }
    box.innerHTML = '';
    var GRP = window.ADspaceGroup, filtered = rows.length !== all.length;
    [['pending', 'Pending'], ['active', 'Active'], ['inactive', 'Inactive']].forEach(function (g) {
      var mine = rows.filter(function (s) { return s.status === g[0]; });
      if (!mine.length) return;
      box.appendChild(GRP.section({
        route: 'suppliers', key: g[0], name: g[1], count: mine.length,
        shut: !filtered && GRP.shut('suppliers', g[0], g[0] === 'inactive'),
        table: function () {
          var table = GRP.table('svc-row sup-row', ['Supplier', 'Person in charge', 'Payment term', 'State', '']);
          GRP.more(table, mine, 30, 'suppliers', row);
          return table;
        }
      }));
    });
  }
  function row(s) {
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'svc-row sup-row' + (s.status === 'inactive' ? ' is-off' : '');
    b.innerHTML = '<span class="svc-name"><b>' + esc(nameOf(s)) + '</b>' + (s.name ? '<small class="sup-code">' + esc(s.code) + '</small>' : s.waiting ? '' : '<small>Waiting for their details</small>') + '</span>' +
      /* What is not known is left out on a phone, as Clients leaves it
         (2026-10-20, SUP-9). */
      '<span class="sup-who' + (s.contact_name ? '' : ' is-none') + '">' + (s.contact_name ? esc(s.contact_name) + (s.designation ? '<small>' + esc(s.designation) + '</small>' : '') : '<span class="muted">—</span>') + '</span>' +
      '<span class="sup-term' + (s.payment_term ? '' : ' is-none') + '">' + (s.payment_term ? esc(s.payment_term) : '<span class="muted">—</span>') + '</span>' +
      '<span class="sup-state">' + chip(s) + '</span>' +
      '<span class="sup-go">' + CHEV + '</span>';
    b.addEventListener('click', function () { state.open = s.id; state.pane = 'overview'; setUrl(); openRec(s.id); });
    return b;
  }

  // ---- New supplier ---------------------------------------------------------
  /* The next free AS number, written as wide as the IDs already are
     (AS0126, then AS0127), offered and the team's to change. */
  function nextCode() {
    var n = 0, w = 4;
    (state.rows || []).forEach(function (s) {
      var m = /^AS(\d+)$/i.exec(s.code || '');
      if (m && Number(m[1]) >= n) { n = Number(m[1]); w = Math.max(3, m[1].length); }
    });
    var x = String(n + 1);
    while (x.length < w) x = '0' + x;
    return 'AS' + x;
  }
  function create() {
    window.ADspaceConfirm.ask({
      title: 'New supplier', go: 'Create link', wait: true,
      /* The supplier names itself on its own form. */
      fields: [{ name: 'code', label: 'Supplier ID', value: nextCode(), required: true }]
    }, function (v) {
      return rpc('supplier_create', { p_code: v.code, p_name: null }).then(function (r) {
        var d = r.data || {};
        if (r.error || d.error) return said(r);
        state.rows = null; state.open = d.id; setUrl(); load();
        return '';
      });
    });
  }

  // ---- The record -----------------------------------------------------------
  function openRec(id) {
    var rec = $('supRec');
    $('supList').hidden = true; $('supBar').hidden = true; rec.hidden = false;
    if (!state.rec || state.rec.id !== id) UI.skeleton(rec, 4);
    return rpc('supplier_get', { p_id: id }).then(function (r) {
      /* An answer for a record already left never paints over the one open
         now (SUP-1, 2026-10-22; as tests/crswitch.js holds for sets). */
      if (state.open !== id) return;
      var d = r.data || {};
      if (r.error || d.error) {
        if (d.error === 'not-found') { state.open = null; setUrl(); msg('supMsg', 'That supplier is no longer there.', 'err'); paint(); return; }
        UI.failLine(rec, 'the supplier', said(r), function () { openRec(id); });
        return;
      }
      state.rec = d.supplier; state.form = d.form; state.pay = d.pay;
      state.client = d.client || null; state.match = d.match || [];
      paintRec();
      letters(id);
      emails(id);
    });
  }
  var GROUPS = [
    ['Billing details', [['kind', 'Registered as'], ['brn', 'BRN'], ['nric', 'NRIC', 1], ['tin', 'TIN'], ['sst_no', 'SST no.'], ['phone', 'Office / mobile'], ['address', 'Billing address']]],
    ['Person in charge', [['contact_name', 'Legal name'], ['designation', 'Designation'], ['email', 'Email'], ['mobile', 'Mobile / WhatsApp']]],
    ['Payment details', [['payment_term', 'Payment term'], ['currency', 'Currency'], ['finance_email', 'Finance email'],
      ['payee_name', 'Payee name', 1], ['bank_name', 'Bank', 1], ['bank_account', 'Account number', 1], ['swift', 'SWIFT code', 1], ['bank_address', 'Bank address', 1]]]
  ];
  function valueOf(s, k) {
    var v = s[k];
    if (k === 'kind') return v === 'individual' ? 'Individual' : v === 'company' ? 'Company' : '';
    if (k === 'currency') return v === 'SGD' ? 'SGD / S$' : v === 'MYR' ? 'MYR / RM' : '';
    return v == null ? '' : String(v);
  }
  function factsOf(s, items) {
    return '<dl class="ovfacts">' + items.filter(function (it) {
      if (it[2] && !state.pay) return false;
      if (it[0] === 'nric') return s.kind === 'individual';
      return true;
    }).map(function (it) {
      var v = valueOf(s, it[0]);
      return '<div><dt>' + esc(it[1]) + '</dt><dd' + (v ? (it[0] === 'address' || it[0] === 'bank_address' ? ' class="is-pre"' : '') : ' class="is-empty"') + '>' +
        (v ? esc(v) : 'Not set') + '</dd></div>';
    }).join('') + '</dl>';
  }
  function linkOf(key) { return location.origin + '/supplier/?k=' + key; }
  /* The details form (2026-10-18), and the update link an approved
     supplier is sent (2026-10-20; the user: an approved supplier "would like
     to change record"). A link is made for one step: approving a supplier
     ends its form. An Active supplier keeps one Details update form section
     under its details, whatever its link's state (2026-10-20, the user: the
     link's acts apart in the head's ⋯ and the section gone once the link
     ended read as confusing): Not sent, open, ended or taken in, Create link
     in its own head. What came back leads the record. */
  var FIELD = {};
  GROUPS.forEach(function (g) { g[1].forEach(function (it) { FIELD[it[0]] = it; }); });
  function formHead(title, act) { return '<div class="readgroup-head"><h4 class="fsec-h">' + esc(title) + '</h4>' + (act || '') + '</div>'; }
  function formMenu(items) {
    return '<span class="dform-acts team-act"><button class="kmenu-btn" type="button" data-s="fmenu" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
      '<div class="kmenu" data-s-menu="form" hidden>' + items + '</div></span>';
  }
  function changesOf(f) {
    var s = state.rec, a = f.answers || {}, rows = [];
    Object.keys(FIELD).forEach(function (k) {
      if (FIELD[k][2] && !state.pay) return;
      if (!(k in a) && !(k in s)) return;
      var was = valueOf(s, k), now = valueOf(a, k);
      if (was === now) return;
      rows.push('<div><dt>' + esc(FIELD[k][1]) + '</dt><dd>' + (FIELD[k][2] ? 'Changed'
        : esc(was || 'Not set') + ' → ' + esc(now || 'Not set')) + '</dd></div>');
    });
    if (!state.pay && f.bank_changed) rows.push('<div><dt>Bank details</dt><dd>Changed</dd></div>');
    return rows.length ? rows.join('') : '<div><dt>Changes</dt><dd>None</dd></div>';
  }
  /* What a details form brought back, read in place before Use details
     (2026-10-20, SUP-2): each answer under its label, the bank details by
     name alone without Supplier bank details. */
  function answersOf(f) {
    var a = f.answers || {}, rows = [];
    if (a.name) rows.push('<div><dt>Name</dt><dd>' + esc(a.name) + '</dd></div>');
    Object.keys(FIELD).forEach(function (k) {
      if (k === 'nric' && a.kind !== 'individual') return;
      var v = valueOf(a, k);
      if (!v) return;
      if (FIELD[k][2] && !state.pay) return;
      rows.push('<div><dt>' + esc(FIELD[k][1]) + '</dt><dd' + (k === 'address' || k === 'bank_address' ? ' class="is-pre"' : '') + '>' + esc(v) + '</dd></div>');
    });
    if (!state.pay && f.bank_changed) rows.push('<div><dt>Bank details</dt><dd>Given</dd></div>');
    return rows.join('');
  }
  function formBlock() {
    var f = state.form, work = may('suppliers', 'work'), s = state.rec;
    var update = f && f.purpose === 'update';
    if (f && f.state === 'submitted') {
      var held = update && f.bank_changed && !payWork();
      return formHead(update ? 'Details update' : 'Details form', work && !held
          ? '<button class="btn btn-sm btn-primary" type="button" data-s="use">' + (update ? 'Use changes' : 'Use details') + '</button>' : '') +
        '<dl class="ovfacts"><div><dt>State</dt><dd>Received ' + esc(day(f.submitted_at)) + ', waiting to be taken in</dd></div>' +
        (update ? changesOf(f) : answersOf(f)) + '</dl>' +
        (held && work ? '<p class="msg warn">The bank details changed. A colleague with Supplier bank details takes this in.</p>' : '');
    }
    /* An open link reads the same whether it asks for the details first or
       for a change to them (2026-10-20, the user: the update link's ⋯ alone
       read as "confusing"): what it is, until when, the link itself. */
    if (f && f.state === 'open' && (update || s.status === 'pending')) {
      var url = f.key ? linkOf(f.key) : '';
      return formHead(update ? 'Details update form' : 'Details form', work ? formMenu('<button class="kmenu-item" data-g="5" type="button" data-s="reset" role="menuitem">Reset link</button><button class="kmenu-item" data-g="5" type="button" data-s="close" role="menuitem">Close link</button>') : '') +
        '<dl class="ovfacts"><div><dt>State</dt><dd>Sent, open until ' + esc(day(f.expires_at)) + '</dd></div></dl>' +
        (url ? '<div class="rec-linktools"><div class="linkbox">' +
          '<input class="input readfield" id="supLink" readonly aria-label="' + (update ? 'Details update form link' : 'Details form link') + '" value="' + esc(url) + '">' +
          '<button class="btn btn-icon" type="button" data-s="copy"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15H4.5A1.5 1.5 0 0 1 3 13.5v-9A1.5 1.5 0 0 1 4.5 3h9A1.5 1.5 0 0 1 15 4.5V5"/></svg><span>Copy link</span></button>' +
          '<a class="btn btn-icon" href="' + esc(url) + '" target="_blank" rel="noopener">Preview <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 4h6v6"/><path d="M20 4 11 13"/><path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg></a>' +
          '</div></div>' : '');
    }
    if (s.status === 'active') {
      var mine = update ? f : null;
      if (!work && !mine) return '';
      return formHead('Details update form', work ? '<button class="btn btn-sm" type="button" data-s="link">Create link</button>' : '') +
        '<dl class="ovfacts"><div><dt>State</dt><dd>' + (!mine ? 'Not sent' : mine.state === 'used'
          ? 'Received ' + esc(day(mine.submitted_at)) + ', taken in' : 'Link ended ' + esc(day(mine.expires_at))) + '</dd></div></dl>';
    }
    if (s.status !== 'pending') return '';
    if (!work && !f) return '';
    return formHead('Details form', work ? '<button class="btn btn-sm" type="button" data-s="link">Create link</button>' : '') +
      '<dl class="ovfacts"><div><dt>State</dt><dd>' + (!f ? 'Not sent' : f.state === 'used'
        ? 'Received ' + esc(day(f.submitted_at)) + ', taken in' : 'Link expired ' + esc(day(f.expires_at))) + '</dd></div></dl>';
  }
  /* The client this supplier also is (2026-10-18): its own Supplier ID and
     Client ID kept apart, the two records opening each other. While none is
     linked, a client sharing the BRN is named as the likely one. */
  function clientBlock() {
    var c = state.client, m = state.match || [], cv = may('clients', 'view');
    var act = may('suppliers', 'work') && cv;
    if (!c && !act) return '';
    var name = function (x) { return esc(window.ADspaceForm.named(x.code, x.name)); };
    var dd = !c ? '' : c.hidden ? '<dd>Not in your clients</dd>'
      : '<dd>' + (cv ? '<button class="linkbtn" type="button" data-s="client-open">' + name(c) + CHEV.replace('<svg ', '<svg class="ovgo-chev" ') + '</button>' : name(c)) + '</dd>';
    return '<div class="readgroup-head"><h4 class="fsec-h">Client</h4>' +
        (act ? '<button class="btn btn-sm" type="button" data-s="client">' + (c ? 'Edit' : 'Link client') + '</button>' : '') + '</div>' +
      (!c ? '<p class="muted">Not linked.</p>' + (m.length ? '<dl class="ovfacts"><div><dt>Same BRN</dt><dd>' + m.map(name).join(', ') + '</dd></div></dl>' : '')
        : '<dl class="ovfacts"><div><dt>Linked to</dt>' + dd + '</div></dl>');
  }
  function linkClient() {
    var s = state.rec, c = state.client;
    /* Every client, a thousand at a time; a refusal in the team's words
       (SUP-2, 2026-10-22). */
    window.ADspaceAPI.readPages(function () { return db.from('clients').select('id, client_code, name').order('id'); }).then(function (r) {
      if (r.error) { msg('supRecMsg', 'Could not load the clients. ' + said(r), 'err'); return; }
      var rows = (r.data || []).slice().sort(window.ADspaceForm.byClient);
      var pick = c && c.id ? c.id : (state.match[0] || {}).id || '';
      if (pick && !rows.some(function (x) { return x.id === pick; })) pick = '';
      window.ADspaceConfirm.ask({
        title: 'Linked client', go: 'Save', wait: true,
        fields: [{ name: 'client', label: 'Client', required: false, value: pick,
          choices: [['', 'Not linked']].concat(rows.map(function (x) { return [x.id, window.ADspaceForm.named(x.client_code, x.name)]; })) }]
      }, function (v) {
        var to = v.client || null;
        if (to === ((c && c.id) || null)) return Promise.resolve('');
        return rpc('supplier_client_set', { p_id: s.id, p_client: to }).then(function (r2) {
          if (r2.error || (r2.data || {}).error) return said(r2);
          openRec(s.id);
          return '';
        });
      });
    });
  }
  function paintRec() {
    var s = state.rec, rec = $('supRec'), work = may('suppliers', 'work');
    var complete = s.name && s.kind && s.tin && s.address && s.email && s.payment_term;
    /* A form come back is never read as still waited for (2026-10-20,
       SUP-1): the chip says Details received, the meta its day. */
    var got = !!(state.form && state.form.state === 'submitted' && state.form.submitted_at);
    var fb = formBlock(), quiet = s.status !== 'pending' && !(state.form && state.form.state === 'submitted');
    var menu = (work ? '<button class="kmenu-item" data-g="2" type="button" data-s="edit" role="menuitem">Edit</button>' +
        (s.status === 'active' ? '<button class="kmenu-item" data-g="5" type="button" data-s="off" role="menuitem">Set inactive</button>' : '') +
        (s.status === 'inactive' ? '<button class="kmenu-item" data-g="5" type="button" data-s="on" role="menuitem">Set active</button>' : '') : '') +
      (may('suppliers', 'manage') ? '<button class="kmenu-item is-danger" data-g="6" type="button" data-s="del" role="menuitem">Delete</button>' : '');
    var noDetails = !GROUPS.some(function (g) { return g[1].some(function (it) { return it[0] !== 'currency' && valueOf(s, it[0]); }); });
    var group = function (g) { return '<section class="readgroup"><div class="readgroup-head"><h4 class="fsec-h">' + esc(g[0]) + '</h4></div>' + factsOf(s, g[1]) + '</section>'; };
    /* The record in panes (SUP-4, 2026-10-22; nine sections stood 2,180px
       tall on a phone): the head its own card, then the strip. Overview the
       supplier's facts, a form come back first; Payment how it is paid and
       its Details update form and Bukku; Documents; Emails. */
    var panes = {
      overview: (fb && !quiet ? '<section class="readgroup sup-form">' + fb + '</section>' : '') +
        (clientBlock() ? '<section class="readgroup" id="supClient">' + clientBlock() + '</section>' : '') +
        /* A supplier holding no details yet reads one line, never three
           groups of Not set (2026-10-20, SUP-3). */
        (noDetails ? '<section class="readgroup"><div class="readgroup-head"><h4 class="fsec-h">Details</h4></div><p class="muted">No details yet.</p></section>'
          : group(GROUPS[0]) + group(GROUPS[1])),
      payment: (noDetails ? '' : group(GROUPS[2])) +
        (fb && quiet ? '<section class="readgroup sup-form">' + fb + '</section>' : '') +
        (s.status === 'active' ? '<section class="readgroup bk-group" id="supBukku" hidden></section>' : ''),
      documents: '<section class="readgroup" id="supLetters"><div class="readgroup-head"><h4 class="fsec-h">Documents</h4>' +
          /* Each act stands in the section it fills (2026-10-20): Issue
             document beside Add existing document; Send email in Emails.
             Only an Active supplier is issued a document (DOC-3). A ⋯ of one
             item is a button (the menu standard, rule 8; SUP-3). */
          (work ? '<span class="sup-head-acts">' + (s.status === 'active' ? '<button class="btn btn-sm" type="button" data-s="issue">Issue document</button>' : '') +
            '<button class="btn btn-sm" type="button" data-s="add">Add existing document</button></span>' : '') + '</div>' +
          '<div id="supLetterList"><p class="muted">Loading.</p></div></section>',
      emails: '<section class="readgroup" id="supEmails"><div class="readgroup-head"><h4 class="fsec-h">Emails</h4>' +
          (work && s.email ? '<button class="btn btn-sm" type="button" data-s="mail">Send email</button>' : '') + '</div>' +
          '<div id="supEmailList"><p class="muted">Loading.</p></div></section>'
    };
    var shown = PANES.filter(function (x) { return panes[x[0]]; });
    if (!shown.some(function (x) { return x[0] === state.pane; })) state.pane = 'overview';
    rec.innerHTML =
      '<div class="sup-back"><button class="btn btn-quiet btn-sm" type="button" data-s="back">' + BACK + 'Suppliers</button></div>' +
      '<div class="panel sup-rec sup-headcard">' +
        '<div class="sup-head"><div class="sup-who-h"><h2>' + esc(nameOf(s)) + '</h2><span class="sup-meta">' + (s.name ? '<span class="sup-code">' + esc(s.code) + '</span>' : got ? 'Received ' + esc(day(state.form.submitted_at)) : s.waiting ? '' : 'Waiting for their details') +
          (s.approved_at ? ' · Approved ' + esc(day(s.approved_at)) + (s.approved_by ? ' by ' + esc(s.approved_by) : '') : '') + '</span></div>' +
          '<div class="sup-ctl">' + chip(s, got && s.status === 'pending') +
            (s.status === 'pending' && work && complete ? '<button class="btn btn-sm btn-primary" type="button" data-s="approve">Approve</button>' : '') +
            (menu ? '<span class="team-act"><button class="kmenu-btn" type="button" data-s="menu" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
              '<div class="kmenu" data-s-menu="rec" hidden>' + menu + '</div></span>' : '') +
          '</div></div></div>' +
      '<nav class="rectabs sup-tabs" id="supTabs" role="tablist" aria-label="Supplier">' + shown.map(function (x) {
        var on = x[0] === state.pane;
        return '<button class="tab' + (on ? ' is-on' : '') + '" type="button" role="tab" aria-selected="' + on + '" data-pane="' + x[0] + '">' + esc(x[1]) + '</button>';
      }).join('') + '</nav>' +
      '<div class="msg" id="supRecMsg"></div>' +
      '<div class="panel sup-rec sup-body" data-swipe="supTabs">' + shown.map(function (x) {
        return '<div class="readgroups sup-pane" data-pane="' + x[0] + '"' + (x[0] === state.pane ? '' : ' hidden') + '>' + panes[x[0]] + '</div>';
      }).join('') + '</div>';
    Array.prototype.forEach.call(rec.querySelectorAll('#supTabs .tab'), function (t) {
      t.addEventListener('click', function () { showPane(t.getAttribute('data-pane'), true); });
    });
    if (window.ADspaceActs && window.ADspaceActs.scan) window.ADspaceActs.scan(rec);
    /* Bukku (2026-10-18): an approved supplier sent as a Bukku contact; one
       linked to a client is that client's contact, typed Supplier too. */
    if (window.ADspaceBukku && $('supBukku')) window.ADspaceBukku.group($('supBukku'), 'supplier', s.id,
      { note: s.client_id ? 'Sent as the linked client\'s contact in Bukku.' : '' });
    wireRec();
  }
  /* One pane on show; the others stay drawn (their reads land in them),
     hidden. */
  function showPane(k, push) {
    if (!paneOk(k) || k === state.pane) return;
    state.pane = k;
    Array.prototype.forEach.call(document.querySelectorAll('#supTabs .tab'), function (t) {
      var on = t.getAttribute('data-pane') === k;
      t.classList.toggle('is-on', on); t.setAttribute('aria-selected', String(on));
    });
    Array.prototype.forEach.call(document.querySelectorAll('#supRec .sup-pane'), function (p) { p.hidden = p.getAttribute('data-pane') !== k; });
    if (push && bridge.pushUrl) bridge.pushUrl(); else setUrl();
  }
  function wireRec() {
    var rec = $('supRec'), s = state.rec;
    var on = function (a, fn) { Array.prototype.forEach.call(rec.querySelectorAll('[data-s="' + a + '"]'), function (b) { b.addEventListener('click', function (e) { e.stopPropagation(); shutMenus(); fn(b); }); }); };
    Array.prototype.forEach.call(rec.querySelectorAll('[data-s="menu"], [data-s="fmenu"]'), function (b) {
      b.addEventListener('click', function (e) {
        e.stopPropagation();
        var m = b.parentNode.querySelector('.kmenu'), open = m.hidden;
        shutMenus(); m.hidden = !open; b.setAttribute('aria-expanded', String(open));
        if (open) window.ADspaceMenu.place(b, m);
      });
    });
    on('back', function () { state.open = null; state.rec = null; state.pane = 'overview'; setUrl(); paint(); });
    on('edit', function () { openEdit(null); });
    on('use', function () { openEdit(state.form); });
    on('link', function (b) { link(false, b); });
    on('reset', function () {
      window.ADspaceConfirm.ask({ title: 'Reset link?', body: 'The link sent before stops opening. A new link is made.', go: 'Reset link', tone: 'warn' },
        function () { link(true); });
    });
    /* Close link (2026-10-18): the link stops opening and no new one is
       made; Create link makes one again. */
    on('close', function () {
      window.ADspaceConfirm.ask({ title: 'Close link?', body: 'The link sent stops opening. A new link can be made later.', go: 'Close link', tone: 'warn', wait: true },
        function () {
          return rpc('supplier_link_close', { p_id: state.open }).then(function (r) {
            var d = r.data || {};
            if (r.error || d.error) return said(r);
            load(); return '';
          });
        });
    });
    on('copy', function (b) { if (window.ADspaceCopy) window.ADspaceCopy.to(b, $('supLink').value); });
    on('approve', function (b) { status('active', b); });
    on('client', linkClient);
    on('client-open', function () {
      history.pushState(null, '', '?s=clients&client=' + encodeURIComponent(state.client.slug || state.client.id));
      if (bridge.show) bridge.show('clients');
    });
    on('mail', function () { openMail(s.status === 'active' ? 'approved' : 'document'); });
    on('off', function () { status('inactive'); });
    on('on', function () { status('active'); });
    on('issue', function () {
      if (!window.ADspaceRegister) return;
      window.ADspaceRegister.openIssue({ supplier: s, families: ['supplier'], msg: 'supRecMsg', onDone: function () { letters(s.id); } });
    });
    /* A document kept outside the portal (an agreement, an NDA) is filed
       under the supplier by hand (2026-10-18). */
    on('add', function () {
      if (!window.ADspaceRegister || !window.ADspaceRegister.openAdd) return;
      window.ADspaceRegister.openAdd({ supplier: s, msg: 'supRecMsg', onDone: function () { letters(s.id); } });
    });
    on('del', function () {
      window.ADspaceConfirm.ask({
        title: 'Delete supplier?', tone: 'danger', go: 'Delete', wait: true,
        body: nameOf(s) + ' and its details are deleted. Letters already issued keep their words. There is no restore.',
        field: { label: s.name ? 'Type the name to confirm' : 'Type the Supplier ID to confirm', match: nameOf(s) }
      }, function (v) {
        return rpc('supplier_delete', { p_id: s.id, p_name: v }).then(function (r) {
          var d = r.data || {};
          if (r.error || d.error) return said(r);
          state.open = null; state.rec = null; state.rows = null; setUrl(); load();
          msg('supMsg', nameOf(s) + ' deleted.', 'ok');
          return '';
        });
      });
    });
  }
  function shutMenus() {
    Array.prototype.forEach.call(document.querySelectorAll('#supRec .kmenu'), function (m) { m.hidden = true; });
    Array.prototype.forEach.call(document.querySelectorAll('#supRec .kmenu-btn'), function (b) { b.setAttribute('aria-expanded', 'false'); });
  }
  document.addEventListener('click', function (e) { if (!e.target.closest || !e.target.closest('#supRec .team-act')) shutMenus(); });
  if (window.ADspaceMenu) window.ADspaceMenu.onScroll(shutMenus);

  function link(reset, btn) {
    if (btn) btn.disabled = true;
    rpc('supplier_link', { p_id: state.rec.id, p_reset: Boolean(reset) }).then(function (r) {
      if (btn) btn.disabled = false;
      var d = r.data || {};
      if (r.error || d.error) { msg('supRecMsg', said(r), 'err'); return; }
      openRec(state.rec.id);
    });
  }
  function status(to, btn) {
    if (btn) btn.disabled = true;
    var s = state.rec, was = s.status;
    rpc('supplier_set_status', { p_id: s.id, p_status: to }).then(function (r) {
      var d = r.data || {};
      if (r.error || d.error) { if (btn) btn.disabled = false; msg('supRecMsg', said(r), 'err'); return; }
      state.rows = null;
      rpc('suppliers_list', {}).then(function (r2) { if (r2.data && r2.data.rows) state.rows = r2.data.rows; });
      /* The answer follows the record's read, never a timer: the button
         holds its pending state until then (2026-10-20, SUP-4). */
      openRec(s.id).then(function () {
        if (was === 'pending') { msg('supRecMsg', 'Approved.', 'ok'); offerMail(s); return; }
        if (window.ADspaceAdmin && window.ADspaceAdmin.undoBar && $('supRecMsg')) {
          window.ADspaceAdmin.undoBar(nameOf(s) + (to === 'inactive' ? ' set inactive.' : ' set active.'), function () { status(was); }, $('supRecMsg'));
        }
      });
    });
  }

  /* A supplier's letters, as the Register reads them. */
  function letters(id) {
    var box = $('supLetterList');
    if (!box) return;
    db.from('documents').select('id, serial, kind, issued_at, voided_at, void_reason, source, family, type_id, title, salutation, closing, recipient, body, languages, signatory, signed, client_id, member_id, supplier_id, file_url, created_at')
      .eq('supplier_id', id).order('created_at', { ascending: false }).then(function (r) {
        if (!$('supLetterList') || state.open !== id) return;
        if (r.error) { UI.failLine(box, 'the documents', r.error.message || '', function () { letters(id); }); return; }
        var rows = r.data || [];
        if (!rows.length) { box.innerHTML = '<p class="muted">No documents.</p>'; return; }
        box.innerHTML = '<dl class="ovfacts">' + rows.map(function (d, i) {
          var words = esc(d.serial) + ' · ' + esc(d.kind) + (d.voided_at ? ' · ' + esc(d.void_reason === 'Reissued' ? 'Reissued' : 'Void') : '');
          /* An entry added by hand is not drawn: it opens its file where one
             is linked, else it is read as it stands. */
          var hand = d.source === 'manual';
          return '<div><dt>' + esc(day(d.issued_at)) + '</dt><dd>' + (hand && !d.file_url ? words :
            '<button class="linkbtn" type="button" data-l="' + i + '">' + words + '</button>') + '</dd></div>';
        }).join('') + '</dl>';
        Array.prototype.forEach.call(box.querySelectorAll('[data-l]'), function (b) {
          b.addEventListener('click', function () {
            var d = rows[Number(b.getAttribute('data-l'))];
            if (d.source === 'manual') { window.open(d.file_url, '_blank', 'noopener'); return; }
            if (window.ADspaceLetters) window.ADspaceLetters.download(d, function (warn) { if (warn) msg('supRecMsg', warn, 'err'); });
          });
        });
      }).catch(function (e) { if (state.open === id) UI.failLine(box, 'the documents', String(e && e.message || e), function () { letters(id); }); });
  }

  /* Emails sent to the supplier (supplier_emails_of), newest first, with
     what Resend last said of each. */
  var MAIL_STATE = { sending: ['Sending', 'is-warn'], sent: ['Sent', 'is-live'], delivered: ['Delivered', 'is-ok'],
    opened: ['Opened', 'is-ok'], failed: ['Failed', 'is-danger'], bounced: ['Bounced', 'is-danger'],
    complained: ['Marked as spam', 'is-danger'], unknown: ['Not confirmed', 'is-warn'] };
  function emails(id) {
    var box = $('supEmailList');
    if (!box) return;
    rpc('supplier_emails_of', { p_supplier: id }).then(function (r) {
      if (!$('supEmailList') || !state.rec || state.rec.id !== id) return;
      var d = r.data || {};
      if (r.error || d.error) { UI.failLine(box, 'the emails', said(r), function () { emails(id); }); return; }
      var rows = d.rows || [];
      if (!rows.length) { box.innerHTML = '<p class="muted">No emails.</p>'; return; }
      box.innerHTML = '<dl class="ovfacts">' + rows.map(function (e) {
        var st = MAIL_STATE[e.status] || [e.status, ''];
        return '<div><dt>' + esc(day(e.created_at)) + '</dt><dd>' + esc(e.subject) +
          ' <span class="chip-state ' + st[1] + '">' + esc(st[0]) + '</span>' +
          '<span class="sup-mail-meta">To ' + esc(e.to) + (e.cc ? ', copy to ' + esc(e.cc) : '') + (e.by ? ' · ' + esc(e.by) : '') + '</span></dd></div>';
      }).join('') + '</dl>';
    });
  }
  function offerMail(s) {
    if (!s.email || !may('suppliers', 'work')) return;
    window.ADspaceConfirm.ask({ title: 'Send the approval email?', go: 'Send email', cancel: 'Not now',
      body: (s.contact_name || nameOf(s)) + ' is told by email that the registration is approved.' }, function () { openMail('approved'); });
  }

  /* Send email (#supMailSheet): the template's words filled from the record
     by supplier_email_prepare, changed here if need be, sent by
     supplier-mail; a letter is drawn here and goes as its PDF. */
  var mail = null;
  function openMail(purpose, docId) {
    var s = state.rec;
    mail = { supplier: s.id, docs: [] };
    msg('supMailMsg', ''); $('supMailRecent').hidden = true;
    $('supMailTo').textContent = 'Loading.';
    var tpl = $('supMailTpl');
    tpl.querySelector('option[value="approved"]').disabled = s.status !== 'active';
    db.from('documents').select('id, serial, kind, issued_at, voided_at, void_reason, source, family, type_id, title, salutation, closing, recipient, body, languages, signatory, signed, client_id, member_id, supplier_id, created_at')
      .eq('supplier_id', s.id).is('voided_at', null).order('created_at', { ascending: false }).then(function (r) {
        /* An entry added by hand has no letter to send. */
        mail.docs = ((!r.error && r.data) || []).filter(function (d) { return d.source !== 'manual'; });
        $('supMailDoc').innerHTML = mail.docs.map(function (d) {
          return '<option value="' + esc(d.id) + '">' + esc(d.serial + ' · ' + d.kind) + '</option>';
        }).join('');
        tpl.querySelector('option[value="document"]').disabled = !mail.docs.length;
        if (docId) $('supMailDoc').value = docId;
        tpl.value = purpose === 'document' && mail.docs.length ? 'document' : (s.status === 'active' ? 'approved' : (mail.docs.length ? 'document' : 'approved'));
        tpl.dispatchEvent(new Event('change'));
        prepare();
      });
    $('supMailSheet').hidden = false;
  }
  function prepare() {
    var purpose = $('supMailTpl').value, doc = purpose === 'document' ? $('supMailDoc').value : null;
    $('supMailDocWrap').hidden = purpose !== 'document';
    var at = mail.ask = (mail.ask || 0) + 1;
    rpc('supplier_email_prepare', { p_supplier: mail.supplier, p_purpose: purpose, p_document: doc }).then(function (r) {
      if (!mail || mail.ask !== at) return;
      var d = r.data || {};
      if (r.error || d.error) { $('supMailTo').textContent = ''; msg('supMailMsg', said(r), 'err'); return; }
      msg('supMailMsg', '');
      mail.prep = d;
      $('supMailTo').textContent = (d.to.name ? d.to.name + ' · ' : '') + d.to.email;
      $('supMailCcLine').hidden = !d.cc;
      $('supMailCcWord').textContent = 'Copy the finance email' + (d.cc ? ' (' + d.cc + ')' : '');
      $('supMailSubject').value = d.subject || '';
      $('supMailBody').value = d.body || '';
      var att = $('supMailAttach');
      att.hidden = !d.document;
      if (d.document) att.textContent = 'Attached: ' + window.ADspaceLetters.fileName(d.document);
      var rc = $('supMailRecent');
      rc.hidden = !d.recent;
      if (d.recent) rc.textContent = 'Sent ' + window.ADspaceClock.date(d.recent.at) + (d.recent.by ? ' by ' + d.recent.by : '') + ' to ' + d.recent.to + '.';
    });
  }
  function b64(bytes) {
    var out = '', i, CH = 0x8000;
    for (i = 0; i < bytes.length; i += CH) out += String.fromCharCode.apply(null, bytes.subarray(i, i + CH));
    return btoa(out);
  }
  function sendMail(again) {
    var go = $('supMailGo'), purpose = $('supMailTpl').value, p = mail.prep;
    if (!p) return;
    var subject = $('supMailSubject').value.trim(), body = $('supMailBody').value.trim();
    if (subject.length < 2) { msg('supMailMsg', SAID['bad-subject'], 'err'); $('supMailSubject').focus(); return; }
    if (body.length < 2) { msg('supMailMsg', SAID['bad-body'], 'err'); $('supMailBody').focus(); return; }
    var cc = !$('supMailCcLine').hidden && $('supMailCc').checked;
    var doc = purpose === 'document' ? mail.docs.filter(function (d) { return d.id === $('supMailDoc').value; })[0] : null;
    go.disabled = true; msg('supMailMsg', '');
    var file = doc ? window.ADspaceLetters.render(doc) : Promise.resolve(null);
    file.then(function (bytes) {
      return db.functions.invoke('supplier-mail', { body: { supplier: mail.supplier, purpose: purpose, document: doc ? doc.id : null,
        cc: cc, subject: subject, body: body, again: Boolean(again),
        pdf: bytes ? b64(new Uint8Array(bytes)) : undefined, filename: doc ? window.ADspaceLetters.fileName(doc) : undefined } });
    }).then(function (r) {
      return window.ADspaceAPI.fnRefusal(r).then(function (code) {
        go.disabled = false;
        if (!code && r.data && r.data.ok) {
          shutMail();
          msg('supRecMsg', 'Email sent.', 'ok');
          emails(state.rec.id);
          return;
        }
        if (code === 'recent') {
          var rc = (r.data && r.data.recent) || {};
          window.ADspaceConfirm.ask({ title: 'Sent recently', tone: 'warn', go: 'Send again',
            body: 'This email went to ' + (rc.to || 'the supplier') + (rc.at ? ' on ' + window.ADspaceClock.date(rc.at) : '') + (rc.by ? ' by ' + rc.by : '') + '.' },
            function () { sendMail(true); });
          return;
        }
        if (code === 'not-confirmed' || code === 'not-sent') emails(state.rec.id);
        msg('supMailMsg', SAID[code] || (r.error ? 'Not sent. Try again.' : 'Not sent.'), 'err');
      });
    }).catch(function (e) {
      go.disabled = false;
      msg('supMailMsg', 'The letter could not be drawn: ' + ((e && e.message) || e), 'err');
    });
  }
  function askMail() {
    var p = mail && mail.prep;
    if (!p) return;
    var cc = !$('supMailCcLine').hidden && $('supMailCc').checked;
    window.ADspaceConfirm.ask({ title: 'Send email?', go: 'Send',
      body: 'To ' + p.to.email + (cc ? ', a copy to ' + p.cc : '') + '.' }, function () { sendMail(false); });
  }
  function shutMail() {
    $('supMailSheet').hidden = true;
    mail = null;
  }

  /* Supplier emails (Settings, Documents): each template's subject and body
     at Suppliers Full Access; {fields} are filled from the supplier. */
  var FIELDS = ['contact name', 'supplier name', 'supplier id', 'payment term', 'currency', 'document title', 'document reference', 'document date', 'sender name'];
  var tpls = null;
  function openTemplates(btn) {
    tpls = { rows: {}, opener: btn || null };
    msg('supTplMsg', '');
    $('supTplFields').innerHTML = FIELDS.map(function (f) {
      return '<button class="btn btn-sm" type="button" data-f="' + esc(f) + '">{' + esc(f) + '}</button>';
    }).join('');
    rpc('supplier_email_templates_list', {}).then(function (r) {
      var d = r.data || {};
      if (r.error || d.error) { msg('supTplMsg', said(r), 'err'); return; }
      (d.rows || []).forEach(function (t) { tpls.rows[t.purpose] = { subject: t.subject, body: t.body, was: t.subject + '\n' + t.body }; });
      $('supTplPick').value = 'approved';
      $('supTplPick').dispatchEvent(new Event('change'));
    });
    $('supTplSheet').hidden = false;
  }
  function tplShow() {
    var t = tpls && tpls.rows[$('supTplPick').value];
    if (!t) return;
    tpls.on = $('supTplPick').value;
    $('supTplSubject').value = t.subject; $('supTplBody').value = t.body;
  }
  function tplKeep() {
    var t = tpls && tpls.rows[tpls.on];
    if (!t) return;
    t.subject = $('supTplSubject').value; t.body = $('supTplBody').value;
  }
  function tplSave() {
    tplKeep();
    var changed = Object.keys(tpls.rows).filter(function (k) { var t = tpls.rows[k]; return t.subject + '\n' + t.body !== t.was; });
    if (!changed.length) { shutTpl(); return; }
    var go = $('supTplGo'); go.disabled = true;
    var next = function (i) {
      if (i >= changed.length) { go.disabled = false; shutTpl(); return; }
      var k = changed[i], t = tpls.rows[k];
      rpc('supplier_email_template_save', { p_purpose: k, p_subject: t.subject.trim(), p_body: t.body.trim() }).then(function (r) {
        var d = r.data || {};
        if (r.error || d.error) {
          go.disabled = false;
          $('supTplPick').value = k; $('supTplPick').dispatchEvent(new Event('change'));
          msg('supTplMsg', said(r), 'err'); return;
        }
        t.was = t.subject + '\n' + t.body;
        next(i + 1);
      });
    };
    next(0);
  }
  function shutTpl() {
    $('supTplSheet').hidden = true;
    tpls = null;
  }
  function wireMail() {
    if (!$('supMailSheet') || $('supMailSheet').__wired) return;
    $('supMailSheet').__wired = true;
    $('supMailTpl').addEventListener('change', function () { if (mail) prepare(); });
    $('supMailDoc').addEventListener('change', function () { if (mail) prepare(); });
    $('supMailGo').addEventListener('click', askMail);
    $('supMailCancel').addEventListener('click', shutMail);
    $('supMailClose').addEventListener('click', shutMail);
    $('supTplPick').addEventListener('change', function () { if (!tpls) return; tplKeep(); tplShow(); });
    $('supTplGo').addEventListener('click', tplSave);
    $('supTplCancel').addEventListener('click', shutTpl);
    $('supTplClose').addEventListener('click', shutTpl);
    $('supTplFields').addEventListener('click', function (e) {
      var b = e.target.closest && e.target.closest('[data-f]');
      if (!b) return;
      var el = tpls && tpls.last === 'subject' ? $('supTplSubject') : $('supTplBody');
      var w = '{' + b.getAttribute('data-f') + '}', at = el.selectionStart == null ? el.value.length : el.selectionStart;
      el.value = el.value.slice(0, at) + w + el.value.slice(el.selectionEnd == null ? at : el.selectionEnd);
      el.focus(); el.selectionStart = el.selectionEnd = at + w.length;
    });
    $('supTplSubject').addEventListener('focus', function () { if (tpls) tpls.last = 'subject'; });
    $('supTplBody').addEventListener('focus', function () { if (tpls) tpls.last = 'body'; });
  }

  // ---- Edit, and Use details ------------------------------------------------
  var F = [['code', 'supEdCode'], ['name', 'supEdName'], ['kind', 'supEdKind'], ['brn', 'supEdBrn'], ['nric', 'supEdNric'],
    ['tin', 'supEdTin'], ['sst_no', 'supEdSst'], ['phone', 'supEdPhone'], ['address', 'supEdAddr'],
    ['contact_name', 'supEdContact'], ['designation', 'supEdRole'], ['email', 'supEdEmail'], ['mobile', 'supEdMobile'],
    ['payment_term', 'supEdTerm'], ['currency', 'supEdCur'], ['finance_email', 'supEdFin'],
    ['payee_name', 'supEdPayee'], ['bank_name', 'supEdBank'], ['bank_account', 'supEdAcct'], ['swift', 'supEdSwift'], ['bank_address', 'supEdBankAddr']];
  var PAY = { nric: 1, payee_name: 1, bank_name: 1, bank_account: 1, swift: 1, bank_address: 1 };
  var editing = null;
  function payWork() { return may('suppliers.pay', 'work'); }
  function kindRows() {
    var ind = $('supEdKind').value === 'individual';
    $('supEdNricWrap').hidden = !ind || !payWork();
    /* The ID's row holds Registered as alone in Use details: the kind
       then takes the row. */
    $('supEdKindWrap').classList.toggle('span-all', $('supEdCodeWrap').hidden);
    $('supEdBrnWrap').classList.toggle('span-all', $('supEdNricWrap').hidden);
    $('supEdBrn').setAttribute('aria-required', String(!ind));
    /* Its label's mark follows, as the save refuses (2026-10-20, SUP-6). */
    var brnLab = document.querySelector('label[for="supEdBrn"]');
    if (brnLab) brnLab.classList.toggle('is-req', !ind);
    /* Hints, never a real code (2026-10-20, SPF-1). */
    $('supEdBrn').placeholder = ind ? 'Optional' : '12 digits';
  }
  function openEdit(form) {
    var s = state.rec, a = (form && form.answers) || {};
    editing = { form: form && form.id };
    if (!$('supEdTerm').options.length) {
      $('supEdTerm').innerHTML = '<option value="">Choose a term</option>' + TERMS.map(function (t) { return '<option>' + t + '</option>'; }).join('');
      $('supEdBank').innerHTML = '<option value="">Choose a bank</option>' + BANKS.map(function (t) { return '<option>' + esc(t) + '</option>'; }).join('');
    }
    F.forEach(function (x) {
      var v = x[0] in a ? a[x[0]] : s[x[0]];
      if (x[0] === 'code') v = s.code;
      if (x[0] === 'kind') v = v || 'company';
      if (x[0] === 'currency') v = v || 'MYR';
      $(x[1]).value = v == null ? '' : v;
    });
    $('supPaySec').hidden = !payWork();
    /* The Supplier ID is the team's, changed in Edit alone (2026-10-20, SUP-7). */
    $('supEdCodeWrap').hidden = Boolean(form);
    kindRows();
    if (window.ADspaceForm && window.ADspaceForm.thumb) window.ADspaceForm.thumb();
    $('supEditTitle').textContent = form ? (form.purpose === 'update' ? 'Use changes' : 'Use details') : 'Edit supplier';
    msg('supEditMsg', '');
    $('supEditSheet').hidden = false;
  }
  function shutEdit() { $('supEditSheet').hidden = true; editing = null; }
  function save() {
    if (!editing) return;
    var v = {};
    F.forEach(function (x) { if (!PAY[x[0]] || payWork()) v[x[0]] = $(x[1]).value.trim(); });
    var go = $('supEditGo');
    go.disabled = true;
    rpc('supplier_save', { p_id: state.rec.id, p_values: v, p_form: editing.form || null }).then(function (r) {
      go.disabled = false;
      var d = r.data || {};
      if (r.error || d.error) {
        msg('supEditMsg', said(r), 'err');
        var k = d.error && d.error.indexOf('bad-') === 0 ? d.error.slice(4) : d.error === 'code-taken' ? 'code' : null;
        var f = k && F.filter(function (x) { return x[0] === k; })[0];
        if (f && $(f[1])) $(f[1]).focus();
        return;
      }
      shutEdit();
      state.rows = null;
      rpc('suppliers_list', {}).then(function (r2) { if (r2.data && r2.data.rows) state.rows = r2.data.rows; });
      openRec(state.rec.id);
      setTimeout(function () {
        msg('supRecMsg', d.repending ? 'Saved. The bank details changed, so the supplier is Pending until approved again.' : 'Saved.', d.repending ? 'warn' : 'ok');
      }, 400);
    });
  }

  window.ADspaceSuppliers = { enter: enter, urlState: urlState, load: load, openTemplates: function (btn) { wireMail(); openTemplates(btn); } };
})();
