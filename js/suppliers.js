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
    'bad-brn': 'Enter the 12-digit BRN.', 'bad-nric': 'Enter the NRIC, as 000814-01-2023.', 'bad-tin': 'Enter the TIN, 5 to 20 letters or digits.',
    'bad-sst_no': 'Enter the SST no. as J31-2601-32100001.', 'bad-phone': 'Enter a Malaysian or Singapore number, as 07-123 4567.',
    'bad-mobile': 'Enter a Malaysian or Singapore mobile number, as 012-345 6789.', 'bad-address': 'Enter the full billing address.',
    'bad-contact_name': 'Enter the legal name.', 'bad-designation': 'Enter the designation.', 'bad-email': 'Enter a valid email.',
    'bad-finance_email': 'Enter a valid finance email.', 'bad-payment_term': 'Choose a payment term.', 'bad-currency': 'Choose a currency.',
    'bad-payee_name': 'Enter the payee name.', 'bad-bank_name': 'Choose a bank.', 'bad-bank_account': 'Enter the account number, digits only.',
    'bad-swift': 'Enter the SWIFT code, 8 or 11 letters or digits.', 'bad-bank_address': 'The bank address is up to 300 characters.',
    'incomplete': 'Approve once the details, the payment term and the bank account are saved.'
  };
  function said(r) {
    var m = r && r.error && (r.error.message || '');
    if (m && /could not find|does not exist|schema cache/i.test(m)) return 'This needs a database update.';
    var k = (r && r.data && r.data.error) || m;
    if (k === 'code-taken' && r.data.name) return 'Another supplier holds that Supplier ID: ' + r.data.name + '.';
    return SAID[k] || k || 'The request failed.';
  }
  function rpc(fn, args) {
    return db.rpc(fn, args).then(function (r) { return r; }, function (e) { return { error: e }; });
  }
  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>';
  var CHEV = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>';
  var BACK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m15 6-6 6 6 6"/></svg>';

  var state = { tab: 'documents', rows: null, find: '', open: null, rec: null, form: null, wired: false };

  function urlState() { return { supplier: state.open || '' }; }
  function setUrl() { if (bridge.setUrl) bridge.setUrl(); }
  /* What a supplier is called: its name, else its Supplier ID until its own
     form names it. */
  function nameOf(x) { return x.name || x.code; }
  function wire() {
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
    state.open = new URLSearchParams(location.search).get('supplier') || null;
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
  function chip(s) {
    var st = STATE[s.status] || STATE.pending;
    return '<span class="chip-state ' + st[1] + '">' + esc(s.waiting ? 'Details received' : st[0]) + '</span>';
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
    b.innerHTML = '<span class="svc-name"><b>' + esc(nameOf(s)) + '</b>' + (s.name ? '<small class="sup-code">' + esc(s.code) + '</small>' : '<small>Waiting for their details</small>') + '</span>' +
      '<span class="sup-who">' + (s.contact_name ? esc(s.contact_name) + (s.designation ? '<small>' + esc(s.designation) + '</small>' : '') : '<span class="muted">—</span>') + '</span>' +
      '<span class="sup-term">' + (s.payment_term ? esc(s.payment_term) : '<span class="muted">—</span>') + '</span>' +
      '<span class="sup-state">' + chip(s) + '</span>' +
      '<span class="sup-go">' + CHEV + '</span>';
    b.addEventListener('click', function () { state.open = s.id; setUrl(); openRec(s.id); });
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
    rpc('supplier_get', { p_id: id }).then(function (r) {
      var d = r.data || {};
      if (r.error || d.error) {
        if (d.error === 'not-found') { state.open = null; setUrl(); msg('supMsg', 'That supplier is no longer there.', 'err'); paint(); return; }
        UI.failLine(rec, 'the supplier', said(r), function () { openRec(id); });
        return;
      }
      state.rec = d.supplier; state.form = d.form; state.pay = d.pay;
      paintRec();
      letters(id);
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
  function formBlock() {
    var f = state.form, work = may('suppliers', 'work'), s = state.rec;
    var head = function (act) { return '<div class="readgroup-head"><h4 class="fsec-h">Details form</h4>' + (act || '') + '</div>'; };
    if (f && f.state === 'submitted') {
      return head(work ? '<button class="btn btn-sm btn-primary" type="button" data-s="use">Use details</button>' : '') +
        '<dl class="ovfacts"><div><dt>State</dt><dd>Received ' + esc(day(f.submitted_at)) + ', waiting to be taken in</dd></div></dl>';
    }
    if (f && f.state === 'open') {
      var url = f.key ? linkOf(f.key) : '';
      return head(work ? '<span class="dform-acts team-act"><button class="kmenu-btn" type="button" data-s="fmenu" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
          '<div class="kmenu" data-s-menu="form" hidden><button class="kmenu-item" type="button" data-s="reset"><b>Reset link</b></button></div></span>' : '') +
        '<dl class="ovfacts"><div><dt>State</dt><dd>Sent, open until ' + esc(day(f.expires_at)) + '</dd></div></dl>' +
        (url ? '<div class="rec-linktools"><div class="linkbox">' +
          '<input class="input readfield" id="supLink" readonly aria-label="Details form link" value="' + esc(url) + '">' +
          '<button class="btn btn-icon" type="button" data-s="copy"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15H4.5A1.5 1.5 0 0 1 3 13.5v-9A1.5 1.5 0 0 1 4.5 3h9A1.5 1.5 0 0 1 15 4.5V5"/></svg><span>Copy link</span></button>' +
          '<a class="btn btn-icon" href="' + esc(url) + '" target="_blank" rel="noopener">Preview <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 4h6v6"/><path d="M20 4 11 13"/><path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg></a>' +
          '</div></div>' : '');
    }
    if (!work && !f) return '';
    return head(work ? '<button class="btn btn-sm" type="button" data-s="link">Create link</button>' : '') +
      '<dl class="ovfacts"><div><dt>State</dt><dd>' + (!f ? 'Not sent' : f.state === 'used'
        ? 'Received ' + esc(day(f.submitted_at)) + ', taken in' : 'Link expired ' + esc(day(f.expires_at))) + '</dd></div></dl>';
  }
  function paintRec() {
    var s = state.rec, rec = $('supRec'), work = may('suppliers', 'work');
    var complete = s.name && s.kind && s.tin && s.address && s.email && s.payment_term;
    var menu = (work ? '<button class="kmenu-item" type="button" data-s="edit"><b>Edit</b></button>' +
        (s.status === 'active' ? '<button class="kmenu-item" type="button" data-s="off"><b>Set inactive</b></button>' : '') +
        (s.status === 'inactive' ? '<button class="kmenu-item" type="button" data-s="on"><b>Set active</b></button>' : '') : '') +
      (may('suppliers', 'manage') ? '<button class="kmenu-item is-danger" type="button" data-s="del"><b>Delete</b></button>' : '');
    rec.innerHTML =
      '<div class="sup-back"><button class="btn btn-quiet btn-sm" type="button" data-s="back">' + BACK + 'Suppliers</button></div>' +
      '<div class="panel sup-rec">' +
        '<div class="sup-head"><div class="sup-who-h"><h2>' + esc(nameOf(s)) + '</h2><span class="sup-meta">' + (s.name ? '<span class="sup-code">' + esc(s.code) + '</span>' : 'Waiting for their details') +
          (s.approved_at ? ' · Approved ' + esc(day(s.approved_at)) + (s.approved_by ? ' by ' + esc(s.approved_by) : '') : '') + '</span></div>' +
          '<div class="sup-ctl">' + chip(s) +
            (s.status === 'pending' && work && complete ? '<button class="btn btn-sm btn-primary" type="button" data-s="approve">Approve</button>' : '') +
            (menu ? '<span class="team-act"><button class="kmenu-btn" type="button" data-s="menu" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
              '<div class="kmenu" data-s-menu="rec" hidden>' + menu + '</div></span>' : '') +
          '</div></div>' +
        '<div class="msg" id="supRecMsg"></div>' +
        '<div class="readgroups">' +
        (formBlock() ? '<section class="readgroup sup-form">' + formBlock() + '</section>' : '') +
        GROUPS.map(function (g) { return '<section class="readgroup"><div class="readgroup-head"><h4 class="fsec-h">' + esc(g[0]) + '</h4></div>' + factsOf(s, g[1]) + '</section>'; }).join('') +
        '<section class="readgroup" id="supLetters"><div class="readgroup-head"><h4 class="fsec-h">Letters</h4>' +
          (may('suppliers', 'work') ? '<button class="btn btn-sm" type="button" data-s="issue">Issue document</button>' : '') + '</div>' +
          '<div id="supLetterList"><p class="muted">Loading.</p></div></section>' +
      '</div></div>';
    if (window.ADspaceActs && window.ADspaceActs.scan) window.ADspaceActs.scan(rec);
    wireRec();
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
    on('back', function () { state.open = null; state.rec = null; setUrl(); paint(); });
    on('edit', function () { openEdit(null); });
    on('use', function () { openEdit(state.form); });
    on('link', function (b) { link(false, b); });
    on('reset', function () {
      window.ADspaceConfirm.ask({ title: 'Reset link?', body: 'The link sent before stops opening. A new link is made.', go: 'Reset link', tone: 'warn' },
        function () { link(true); });
    });
    on('copy', function (b) { if (window.ADspaceCopy) window.ADspaceCopy.to(b, $('supLink').value); });
    on('approve', function (b) { status('active', b); });
    on('off', function () { status('inactive'); });
    on('on', function () { status('active'); });
    on('issue', function () {
      if (!window.ADspaceRegister) return;
      window.ADspaceRegister.openIssue({ supplier: s, families: ['supplier'], msg: 'supRecMsg', onDone: function () { letters(s.id); } });
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
      if (btn) btn.disabled = false;
      var d = r.data || {};
      if (r.error || d.error) { msg('supRecMsg', said(r), 'err'); return; }
      state.rows = null;
      rpc('suppliers_list', {}).then(function (r2) { if (r2.data && r2.data.rows) state.rows = r2.data.rows; });
      openRec(s.id);
      setTimeout(function () {
        if (was === 'pending') { msg('supRecMsg', 'Approved.', 'ok'); return; }
        if (window.ADspaceAdmin && window.ADspaceAdmin.undoBar && $('supRecMsg')) {
          window.ADspaceAdmin.undoBar(nameOf(s) + (to === 'inactive' ? ' set inactive.' : ' set active.'), function () { status(was); }, $('supRecMsg'));
        }
      }, 400);
    });
  }

  /* A supplier's letters, as the Register reads them. */
  function letters(id) {
    var box = $('supLetterList');
    if (!box) return;
    db.from('documents').select('id, serial, kind, issued_at, voided_at, void_reason, source, family, type_id, title, salutation, closing, recipient, body, languages, signatory, signed, client_id, member_id, supplier_id, created_at')
      .eq('supplier_id', id).order('created_at', { ascending: false }).then(function (r) {
        if (!$('supLetterList')) return;
        if (r.error) { UI.failLine(box, 'the letters', r.error.message || '', function () { letters(id); }); return; }
        var rows = r.data || [];
        if (!rows.length) { box.innerHTML = '<p class="muted">No letters.</p>'; return; }
        box.innerHTML = '<dl class="ovfacts">' + rows.map(function (d, i) {
          return '<div><dt>' + esc(day(d.issued_at)) + '</dt><dd><button class="linkbtn" type="button" data-l="' + i + '">' +
            esc(d.serial) + ' · ' + esc(d.kind) + (d.voided_at ? ' · ' + esc(d.void_reason === 'Reissued' ? 'Reissued' : 'Void') : '') + '</button></dd></div>';
        }).join('') + '</dl>';
        Array.prototype.forEach.call(box.querySelectorAll('[data-l]'), function (b) {
          b.addEventListener('click', function () {
            var d = rows[Number(b.getAttribute('data-l'))];
            if (window.ADspaceLetters) window.ADspaceLetters.download(d, function (warn) { if (warn) msg('supRecMsg', warn, 'err'); });
          });
        });
      }, function (e) { UI.failLine(box, 'the letters', String(e && e.message || e), function () { letters(id); }); });
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
    /* Five fields in two columns leave one alone: the number takes its row. */
    $('supEdPhoneWrap').classList.toggle('span-all', !$('supEdNricWrap').hidden);
    $('supEdBrn').setAttribute('aria-required', String(!ind));
    $('supEdBrn').placeholder = ind ? 'Optional' : '202304002162';
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
    kindRows();
    if (window.ADspaceForm && window.ADspaceForm.thumb) window.ADspaceForm.thumb();
    $('supEditTitle').textContent = form ? 'Use details' : 'Edit supplier';
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
      setTimeout(function () { msg('supRecMsg', 'Saved.', 'ok'); }, 400);
    });
  }

  window.ADspaceSuppliers = { enter: enter, urlState: urlState, load: load };
})();
