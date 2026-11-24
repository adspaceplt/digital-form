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
  var esc = window.ADspaceWords.esc;
  function may(k, l) { return Boolean(bridge.may && bridge.may(k, l)); }
  function day(iso) { return iso ? window.ADspaceClock.date(iso) : ''; }
  function msg(id, text, kind) { var m = $(id); if (!m) return; m.textContent = text || ''; m.className = 'msg' + (kind && text ? ' ' + kind : ''); }

  var BANKS = ['Maybank', 'CIMB', 'Hong Leong Bank', 'RHB', 'BSN', 'UOB', 'OCBC', 'AmBank', 'Bank Islam', 'Public Bank',
    'Alliance Bank', 'Standard Chartered Bank', 'Touch N Go Digital', '[SG] DBS/POSB', '[SG] OCBC', '[SG] UOB', '[SG] CIMB',
    '[SG] Maybank', '[SG] Bank of China'];
  var TERMS = ['NET 7', 'NET 14', 'NET 30', 'NET 45', 'NET 60'];
  var STATE = { pending: ['Pending', 'is-warn'], active: ['Active', 'is-ok'], inactive: ['Inactive', 'is-off'] };
  var SAID = {
    'send-off': window.ADspaceWords.line.emailSendOff,
    'denied': 'You do not have permission to do this. Please ask an admin.', 'not-found': 'This supplier no longer exists.',
    'bad-code': 'Enter a Supplier ID of 2 to 12 letters or digits, for example AS001.', 'code-taken': 'This Supplier ID is already used by another supplier.',
    'bad-name': 'Enter a name of 2 to 160 characters.', 'bad-kind': 'Choose how the supplier is registered.',
    'bad-brn': 'Enter the 12-digit BRN.', 'bad-nric': 'Enter the NRIC as XXXXXX-XX-XXXX.', 'bad-tin': 'Enter a TIN of 5 to 20 letters or digits.',
    'bad-sst_no': 'Enter the SST Registration No. as AXX-XXXX-XXXXXXXX.', 'bad-phone': 'Enter a Malaysian or Singaporean number, for example 07-123 4567.',
    'bad-mobile': 'Enter a Malaysian or Singaporean mobile number, for example 012-345 6789.', 'bad-address': 'Enter the full billing address.',
    'bad-contact_name': 'Enter the legal name.', 'bad-designation': 'Enter the designation.', 'bad-email': 'Enter a valid email address.', 'bad-finance_email': 'Enter a valid email address.',
    'bad-payment_term': 'Choose a payment term.', 'bad-currency': 'Choose a currency.',
    'bad-payee_name': 'Enter the payee name.', 'bad-bank_name': 'Choose a bank.', 'bad-bank_account': 'Enter the account number, digits only.',
    'bad-swift': 'Enter a SWIFT code of 8 or 11 letters or digits.', 'bad-bank_address': 'Enter a bank address of up to 300 characters.',
    'incomplete': 'Approve once the details, the payment term and the bank account are saved.',
    'no-email': 'Save the supplier\'s email first.', 'not-active': 'Approve the supplier first.',
    'bad-document': 'This letter is void or no longer belongs to this supplier. Choose another letter.', 'bad-purpose': 'Choose a template.',
    'bad-subject': window.ADspaceWords.line.subject, 'bad-body': window.ADspaceWords.line.message,
    'bad-file': 'The letter could not be attached. Download it to check, then try again.',
    'mail-not-set-up': window.ADspaceWords.line.mailOff, 'not-sent': 'Not sent. Please try again.',
    'not-confirmed': 'Not confirmed. Check with the supplier before sending again.', 'bad-request': 'Refresh the page and try again.',
    'no-client': 'This client no longer exists, or you do not have access to it.',
    'no-link': 'No link is open.'
  };
  function said(r) {
    var m = r && r.error && (r.error.message || '');
    if (m && /could not find|does not exist|schema cache/i.test(m)) return 'This feature is not available yet. Please contact an admin.';
    var k = (r && r.data && r.data.error) || m;
    if (k === 'unknown-field' && r.data) return window.ADspaceWords.line.unknownField(r.data.field, r.data.fields);
    if (k === 'code-taken' && r.data.name) return 'This Supplier ID is already used by ' + r.data.name + '.';
    return SAID[k] || k || 'The request failed. Please try again.';
  }
  function rpc(fn, args) {
    return db.rpc(fn, args).then(function (r) { return r; }).catch(function (e) { return { error: e }; });
  }
  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>';
  var CHEV = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>';
  var BACK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M19 12H5"/><path d="m11 6-6 6 6 6"/></svg>';  /* the one way back every record draws (`.backlink`) */

  var state = { pane: 'overview', rows: null, find: '', open: null, rec: null, form: null, wired: false, view: 'list' };

  /* The record's pane rides in the address (`tab=`, Overview left out) and
     pushes history, as a colleague's record does (SUP-4, 2026-10-22). */
  var PANES = [['overview', 'Overview'], ['payment', 'Payment'], ['documents', 'Documents'], ['emails', 'Emails']];
  function paneOk(k) { return PANES.some(function (x) { return x[0] === k; }); }
  function urlState() {
    return { supplier: state.open || '', tab: state.open && state.pane !== 'overview' ? state.pane : '',
      view: !state.open && state.view === 'payments' ? 'payments' : '' };
  }
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
    wireBills();
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
    state.view = q.get('view') === 'payments' ? 'payments' : 'list';
    $('supNew').hidden = !may('suppliers', 'work');
    load();
    loadBills();
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
    rec.hidden = true;
    strip();
    if (state.view === 'payments') { box.hidden = true; $('supBar').hidden = true; $('supTiles').hidden = true; $('spyView').hidden = false; paintBills(); return; }
    $('spyView').hidden = true;
    box.hidden = false; $('supBar').hidden = false;
    if (!state.rows) return;
    paintTiles();
    var all = state.rows, rows = all.filter(matches);
    $('supCount').textContent = !all.length ? '' : rows.length === all.length
      ? all.length + (all.length === 1 ? ' supplier' : ' suppliers') : rows.length + ' of ' + all.length;
    if (!all.length) { UI.emptyLine(box, 'No suppliers.', may('suppliers', 'work') ? 'New supplier' : '', create); return; }
    if (!rows.length) {
      UI.emptyLine(box, 'No matches.', 'Clear filters', function () { state.find = ''; $('supFind').value = ''; paint(); });
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
      /* A phone's second line, as Clients reads (the user, 2026-11-10): the
         Supplier ID leads it, then the person in charge and their position,
         each part kept whole; what is not known is left out. */
      '<span class="sup-line">' + [s.name ? '<span class="nb sup-line-code">' + esc(s.code) + '</span>' : '']
        .concat([s.contact_name, s.designation].filter(Boolean).map(function (x) { return '<span class="nb">' + esc(x) + '</span>'; }))
        .filter(Boolean).join(' · ') + '</span>' +
      '<span class="sup-go">' + CHEV + '</span>';
    b.addEventListener('click', function () { state.open = s.id; state.pane = 'overview'; setUrl(); openRec(s.id); });
    return b;
  }

  // ---- Bills (SUPPLIER BILLS, 2026-11-22) ------------------------------------
  /* Every supplier's purchase bills, read only, from the copy of Bukku the
     nightly run keeps (`supplier_bills`, Suppliers View; the user,
     2026-11-22, approving the Bukku structure mockup). Read from Bukku
     (Suppliers Work) reads the bills again; Open in Bukku opens one there.
     No bill is made here: a supplier's own invoice is keyed into Bukku. */
  var BILL_SAID = {
    denied: 'You do not have permission to read supplier bills. Please ask an admin.',
    'needs-update': window.ADspaceWords.line.notYet,
    'not-found': 'This bill is no longer in Bukku. Press Read from Bukku, then try again.',
    'bukku-not-set-up': window.ADspaceWords.line.bukkuNotSetUp,
    'bukku-token': 'Bukku is not available at the moment. Please contact an admin.',
    'bukku-unreachable': window.ADspaceWords.line.bukkuNoAnswer,
    'bukku-refused': window.ADspaceWords.line.bukkuRefused,
    failed: 'The request failed. Please try again.'
  };
  function billSaid(d) {
    var m = d && d.error && typeof d.error === 'object' ? d.error.message || '' : '';
    if (m && /could not find|does not exist|schema cache/i.test(m)) return BILL_SAID['needs-update'];
    return (d && typeof d.error === 'string' && BILL_SAID[d.error]) || BILL_SAID.failed;
  }
  var OUT = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" data-act="out"><path d="M14 4h6v6"/><path d="M20 4 11 13"/><path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg>';
  /* Money through js/money.js alone: RM and S$, any other currency by its code. */
  function money(n, cur) {
    var t = window.ADspaceMoney.money2(Number(n) || 0, cur === 'SGD' ? 'SG' : 'MY');
    return cur && cur !== 'MYR' && cur !== 'SGD' ? t.replace(/^RM/, cur) : t;
  }
  function billDay(d) { return d ? window.ADspaceClock.date(d + 'T00:00:00+08:00') : ''; }
  function plural(n, one, many) { return n + ' ' + (n === 1 ? one : many); }
  /* Paid once nothing stands; overdue once its due date has passed. */
  function billState(b, today) { return !(Number(b.balance) > 0) ? 'paid' : b.due < today ? 'overdue' : 'waiting'; }
  var BILL_STATE = { overdue: ['Overdue', 'is-danger'], waiting: ['Awaiting payment', 'is-warn'], paid: ['Paid', 'is-ok'] };
  function lateBy(b, today) { var n = window.ADspaceClock.between(b.due, today); return n + (n === 1 ? ' day late' : ' days late'); }
  /* Totals a currency, never added across, MYR first. */
  function byCur(list, fig) {
    var t = {};
    list.forEach(function (b) { var c = b.currency || 'MYR'; t[c] = (t[c] || 0) + Number(fig(b) || 0); });
    return Object.keys(t).sort(function (a, b) { return (a !== 'MYR') - (b !== 'MYR') || a.localeCompare(b); })
      .map(function (c) { return { cur: c, amt: Math.round(t[c] * 100) / 100 }; });
  }
  var PERIODS = [['3d', 'Last 3 days'], ['7d', 'Last 7 days'], ['mm', 'This month and last month'],
    ['lm', 'Last month'], ['3m', 'Last 3 months'], ['yr', 'This year']];
  var bills = { data: null, err: null, period: 'mm', reading: false };
  try { var keptPer = localStorage.getItem('adspace-spy-period'); if (PERIODS.some(function (x) { return x[0] === keptPer; })) bills.period = keptPer; } catch (e) {}
  function range(k) {
    var C = window.ADspaceClock, today = C.today(), p = today.split('-'), y = Number(p[0]), m = Number(p[1]);
    var first = function (yy, mm) { while (mm < 1) { mm += 12; yy -= 1; } return yy + '-' + String(mm).padStart(2, '0') + '-01'; };
    if (k === '3d') return { from: C.addDays(today, -2) };
    if (k === '7d') return { from: C.addDays(today, -6) };
    if (k === 'lm') return { from: first(y, m - 1), to: C.addDays(first(y, m), -1) };
    if (k === '3m') return { from: first(y, m - 2) };
    if (k === 'yr') return { from: y + '-01-01' };
    return { from: first(y, m - 1) };
  }
  /* The view strip: Suppliers, then Payments with its overdue bills counted
     in red; it steps away while a record is open. */
  function strip() {
    var box = $('supViewsBox');
    if (!box) return;
    box.hidden = Boolean(state.open);
    Array.prototype.forEach.call(document.querySelectorAll('#supViews .acttab'), function (b) {
      var on = b.getAttribute('data-sv') === state.view;
      b.classList.toggle('is-on', on); b.setAttribute('aria-pressed', String(on));
    });
    var n = $('supPayN'), d = bills.data, k = 0;
    if (d) k = (d.bills || []).filter(function (b) { return billState(b, d.today) === 'overdue'; }).length;
    if (n) { n.textContent = k; n.hidden = !k; }
    if (!box.hidden && window.ADspaceForm && window.ADspaceForm.thumb) window.ADspaceForm.thumb($('supViews'));
  }
  function wireBills() {
    $('supViews').addEventListener('click', function (e) {
      var b = e.target.closest && e.target.closest('.acttab');
      if (!b) return;
      var v = b.getAttribute('data-sv') === 'payments' ? 'payments' : 'list';
      if (v === state.view) return;
      state.view = v; setUrl(); paint();
      if (v === 'payments' && !bills.data) loadBills();
    });
    ['spyFind', 'spySup', 'spyClient', 'spyCur'].forEach(function (id) {
      var el = $(id), was = el.value;
      var go = function () { if (el.value === was) return; was = el.value; paintBills(); };
      el.addEventListener('input', go); el.addEventListener('change', go);
    });
    $('spyRead').addEventListener('click', function () { readBukku(this, 'spyMsg', loadBills); });
  }
  /* One read for the tiles, the strip's count and the Payments view: every
     bill owing, and those settled since the earlier of the period's start
     and this month's 1st (Paid this month). */
  function loadBills() {
    var r = range(bills.period), first = window.ADspaceClock.today().slice(0, 8) + '01';
    if (state.view === 'payments' && !bills.data) UI.skeleton($('spyList'), 4);
    return rpc('supplier_bills', { p_supplier: null, p_paid_from: r.from < first ? r.from : first, p_doc: null }).then(function (x) {
      var d = x.data || {};
      if (x.error || d.error) { bills.err = x.error ? { error: x.error } : d; bills.data = null; }
      else { bills.err = null; bills.data = d; }
      strip();
      if (state.open) return;
      if (state.view === 'payments') paintBills(); else if (state.rows) paintTiles();
    });
  }
  /* Four figures over the list, as Clients has (v3): the suppliers active
     and pending from the list read, what is owed and what is overdue from
     the bills read. */
  function paintTiles() {
    var box = $('supTiles'), rows = state.rows || [];
    if (!box || !rows.length) { if (box) box.hidden = true; return; }
    var tile = function (label, fig, sub, foot, money) {
      return '<article class="chartcard ovw-kpi crm-tile"><span class="ovw-kpi-label">' + esc(label) + '</span>' +
        '<b class="ovw-kpi-fig' + (money ? ' is-money' : '') + '">' + esc(String(fig)) + '</b>' +
        '<span class="ovw-kpi-sub">' + esc(sub) + '</span>' +
        (foot ? '<span class="crm-tile-foot' + (foot[1] ? ' is-late' : '') + '">' + esc(foot[0]) + '</span>' : '') + '</article>';
    };
    var act = rows.filter(function (x) { return x.status === 'active'; }), pend = rows.filter(function (x) { return x.status === 'pending'; });
    var change = act.filter(function (x) { return x.waiting; }).length, got = pend.filter(function (x) { return x.waiting; }).length;
    var tiles = [tile('Active suppliers', act.length, change ? plural(change, 'change waiting to be applied', 'changes waiting to be applied') : 'No changes waiting'),
      tile('Pending approval', pend.length, got ? plural(got, 'with details received', 'with details received') : 'No details received')];
    var d = bills.data;
    if (d) {
      var owe = (d.bills || []).filter(function (b) { return billState(b, d.today) !== 'paid'; });
      var late = owe.filter(function (b) { return billState(b, d.today) === 'overdue'; });
      var head = function (list, label, foot) {
        var t = byCur(list, function (b) { return b.balance; }), main = t[0] || { cur: 'MYR', amt: 0 }, rest = t.slice(1);
        var n = list.filter(function (b) { return (b.currency || 'MYR') === main.cur; }).length;
        var more = rest.map(function (x) { return money(x.amt, x.cur) + ' · ' + plural(list.filter(function (b) { return (b.currency || 'MYR') === x.cur; }).length, 'bill', 'bills'); }).join(' · ');
        return tile(label, money(main.amt, main.cur), list.length ? plural(n, 'bill', 'bills') : 'No bills', foot || (more ? [more, false] : null), true);
      };
      tiles.push(head(owe, 'Awaiting payment'));
      var oldest = late.reduce(function (m, b) { return !m || b.due < m ? b.due : m; }, '');
      tiles.push(head(late, 'Overdue bills', oldest ? ['Oldest ' + lateBy({ due: oldest }, d.today), true] : null));
    }
    box.className = 'ovw-kpis crm-tiles';
    box.style.setProperty('--n', tiles.length);
    box.innerHTML = tiles.join('');
    box.hidden = false;
  }
  function fillSelect(id, all, pairs) {
    var sel = $(id), was = sel.value;
    sel.innerHTML = '<option value="all">' + esc(all) + '</option>' + pairs.map(function (p) { return '<option value="' + esc(p[0]) + '">' + esc(p[1]) + '</option>'; }).join('');
    sel.value = pairs.some(function (p) { return p[0] === was; }) ? was : 'all';
  }
  /* Suppliers' Payments view (screen b): the tallies, then Overdue, Awaiting
     payment and Paid within its period; a row opens its bill in Bukku. */
  function paintBills() {
    var host = $('spyList');
    if (!host) return;
    $('spyRead').hidden = !(bills.data && bills.data.work);
    if (bills.err) {
      $('spyTallies').hidden = true; $('spyCount').textContent = '';
      UI.failLine(host, 'The bills', billSaid(bills.err), loadBills);
      return;
    }
    var d = bills.data;
    if (!d) { UI.skeleton(host, 4); return; }
    var all = d.bills || [], today = d.today, per = range(bills.period);
    var sups = {}, cls = {}, curs = {};
    all.forEach(function (b) {
      sups[b.supplier] = b.name;
      if (b.client) cls[b.client_code || b.client] = window.ADspaceForm.named(b.client_code, b.client);
      curs[b.currency || 'MYR'] = true;
    });
    fillSelect('spySup', 'All suppliers', Object.keys(sups).sort(function (a, b) { return sups[a].localeCompare(sups[b]); }).map(function (k) { return [k, sups[k]]; }));
    fillSelect('spyClient', 'All clients', Object.keys(cls).sort(function (a, b) { return cls[a].localeCompare(cls[b], 'en', { numeric: true }); }).map(function (k) { return [k, cls[k]]; }));
    fillSelect('spyCur', 'All currencies', Object.keys(curs).sort().map(function (k) { return [k, k]; }));
    /* A filter with nothing to choose between is not drawn. */
    $('spySup').hidden = Object.keys(sups).length < 2 && $('spySup').value === 'all';
    $('spyClient').hidden = !Object.keys(cls).length;
    $('spyCur').hidden = Object.keys(curs).length < 2 && $('spyCur').value === 'all';
    if (window.ADspaceCmdbar && window.ADspaceCmdbar.refresh) window.ADspaceCmdbar.refresh();
    var q = ($('spyFind').value || '').trim().toLowerCase(), fs = $('spySup').value, fc = $('spyClient').value, fu = $('spyCur').value;
    var match = function (b) {
      if (fs !== 'all' && b.supplier !== fs) return false;
      if (fc !== 'all' && (b.client_code || b.client) !== fc) return false;
      if (fu !== 'all' && (b.currency || 'MYR') !== fu) return false;
      if (!q) return true;
      var hay = [b.name, b.code, b.number, b.ref_no, b.client, b.client_code].join(' ').toLowerCase();
      return q.split(/\s+/).every(function (w) { return hay.indexOf(w) > -1; });
    };
    var inPer = function (b) { var p = b.paid_on || b.date; return p >= per.from && (!per.to || p <= per.to); };
    var g = { overdue: [], waiting: [], paid: [] };
    all.forEach(function (b) { var k = billState(b, today); if (k !== 'paid' || inPer(b)) g[k].push(b); });
    g.paid.sort(function (a, b) { return String(b.paid_on || b.date).localeCompare(String(a.paid_on || a.date)); });
    var pick = function (list) { return list.filter(match); };
    var od = pick(g.overdue), wt = pick(g.waiting), pd = pick(g.paid);
    var shown = od.length + wt.length + pd.length, every = g.overdue.length + g.waiting.length + g.paid.length;
    $('spyCount').textContent = !every ? '' : shown === every ? plural(every, 'bill', 'bills') : shown + ' of ' + every;
    /* The tallies follow the filters: owed (overdue too), overdue, due in
       the next seven days and paid this month, a figure a currency. */
    var owing = od.concat(wt), month = today.slice(0, 8) + '01';
    var soon = wt.filter(function (b) { return b.due <= window.ADspaceClock.addDays(today, 7); });
    var paidNow = all.filter(function (b) { return billState(b, today) === 'paid' && (b.paid_on || b.date) >= month && match(b); });
    var cell = function (label, list, fig, total) {
      var t = byCur(list, fig);
      return '<div class="tally-cell' + (total ? ' is-total' : '') + '"><span>' + esc(label) + '</span>' +
        (t.length ? t.map(function (x) { return '<b>' + esc(money(x.amt, x.cur)) + '</b>'; }).join('') : '<b>' + esc(money(0, fu !== 'all' ? fu : 'MYR')) + '</b>') + '</div>';
    };
    var tal = $('spyTallies');
    tal.innerHTML = '<div class="tally inv-tally">' + cell('Awaiting payment', owing, function (b) { return b.balance; }, true) +
      cell('Overdue', od, function (b) { return b.balance; }) + cell('Due in 7 days', soon, function (b) { return b.balance; }) +
      cell('Paid this month', paidNow, function (b) { return b.amount; }) + '</div>';
    tal.hidden = !every;
    host.innerHTML = '';
    if (!every) {
      UI.emptyLine(host, 'No bills.');
      readLine(host, d);
      return;
    }
    var GRP = window.ADspaceGroup;
    var row = function (b, fig, when, late) {
      /* The Supplier ID leads the line, as the list's phone line reads it,
         then the client it works for. */
      var sub = ['<span class="nb sup-line-code">' + esc(b.code) + '</span>'].concat(b.client
        ? ['<span class="nb">' + esc(window.ADspaceForm.named(b.client_code, b.client)) + '</span>'] : []).join(' · ');
      return '<div class="cpq-row" data-bill="' + esc(b.id) + '">' +
        '<div class="cpq-l"><span class="cpq-name">' + esc(b.name) + ' <span class="cpq-mono cpq-job">' + esc(window.ADspaceWords.line.docNo(b.number, b.ref_no)) + '</span></span>' +
          (sub ? '<span class="cpq-sub">' + sub + '</span>' : '') + '</div>' +
        '<div class="cpq-r"><span class="cpq-fig">' + esc(money(fig, b.currency)) + '</span><span class="cpq-sub' + (late ? ' is-late' : '') + '">' + esc(when) + '</span></div>' +
        '<div class="cpq-act"><button class="btn btn-sm" type="button" data-a="bukku">Open in Bukku' + OUT + '</button></div></div>';
    };
    var sum = function (list) { return '<span class="inv-sum">' + esc(byCur(list, function (b) { return b.balance; }).map(function (x) { return money(x.amt, x.cur); }).join(' · ')) + '</span>'; };
    var section = function (key, name, list, rows, marks) {
      if (!list.length) return;
      host.appendChild(GRP.section({ route: 'supplier-payments', key: key, name: name, count: list.length, marks: marks || '',
        shut: key === 'paid' && GRP.shut('supplier-payments', 'paid', false, false),
        table: function () { var t = document.createElement('div'); t.className = 'cpq-list crm-table softpanel'; t.innerHTML = rows; return t; } }));
    };
    if (!shown) { var e = document.createElement('p'); e.className = 'emptyline'; e.textContent = 'No matches.'; host.appendChild(e); }
    section('overdue', 'Overdue', od, od.map(function (b) { return row(b, b.balance, lateBy(b, today), true); }).join(''), sum(od));
    section('waiting', 'Awaiting payment', wt, wt.map(function (b) { return row(b, b.balance, 'Due ' + billDay(b.due)); }).join(''), sum(wt));
    var perSel = '<select class="select select-sm cpq-period" id="spyPeriod" aria-label="Paid period">' +
      PERIODS.map(function (p) { return '<option value="' + p[0] + '"' + (p[0] === bills.period ? ' selected' : '') + '>' + p[1] + '</option>'; }).join('') + '</select>';
    if (pd.length) section('paid', 'Paid', pd, pd.map(function (b) { return row(b, b.amount, 'Paid ' + billDay(b.paid_on || b.date)); }).join(''), perSel);
    else {
      var none = document.createElement('section'); none.className = 'crm-group cpq-paid-none';
      none.innerHTML = '<div class="crm-group-head"><h3 class="cpq-h">Paid<span class="tab-n">0</span></h3>' + perSel + '</div>';
      host.appendChild(none);
    }
    readLine(host, d);
    var ps = $('spyPeriod');
    ps.addEventListener('click', function (ev) { ev.stopPropagation(); });
    ps.addEventListener('change', function () {
      bills.period = ps.value;
      try { localStorage.setItem('adspace-spy-period', bills.period); } catch (ev) {}
      loadBills();
    });
    host.querySelectorAll('[data-a="bukku"]').forEach(function (b) {
      b.addEventListener('click', function () { openBill(b.closest('[data-bill]').getAttribute('data-bill'), 'spyMsg'); });
    });
  }
  function readLine(host, d) {
    if (!d || !d.read_at) return;
    var p = document.createElement('p'); p.className = 'muted cpay-read';
    p.textContent = 'Read from Bukku ' + window.ADspaceClock.date(d.read_at) + ', ' + window.ADspaceClock.clock(d.read_at);
    host.appendChild(p);
  }
  /* Read from Bukku: the suppliers' bills read again, asked as the caller. */
  function readBukku(btn, msgId, done) {
    if (bills.reading) return;
    bills.reading = true; btn.disabled = true; msg(msgId, '');
    db.functions.invoke('bukku-sync', { body: { action: 'supplierbills' } }).then(function (r) {
      if (r && r.data && r.data.error) return r.data;
      return API.fnRefusal(r).then(function (code) { return code ? { error: code } : (r.data || { error: 'failed' }); });
    }, function () { return { error: 'failed' }; }).then(function (d) {
      bills.reading = false; btn.disabled = false;
      if (d.error) { msg(msgId, billSaid(d), 'err'); return; }
      msg(msgId, d.more ? 'Read from Bukku. Some bills are still to be read. Press Read from Bukku again.' : 'Read from Bukku.', 'ok');
      done();
    });
  }
  /* The tab opens at the press (a later window is blocked), then goes to the
     bill's page once bukku-sync names it. */
  function openBill(id, msgId) {
    var tab = window.open('', '_blank');
    db.functions.invoke('bukku-sync', { body: { action: 'supplierbilllink', id: Number(id) } }).then(function (r) {
      if (r && r.data && r.data.error) return r.data;
      return API.fnRefusal(r).then(function (code) { return code ? { error: code } : (r.data || { error: 'failed' }); });
    }, function () { return { error: 'failed' }; }).then(function (x) {
      if (x.url) { if (tab) tab.location.href = x.url; else window.open(x.url, '_blank', 'noopener'); return; }
      if (tab) tab.close();
      msg(msgId, billSaid(x), 'err');
    });
  }
  /* A supplier's own bills (screen c-alt): under the Bukku band in Payment,
     the creator's Payment pane's rows; the Payment tab counts an overdue bill
     in red; the rail holds the totals and the record. */
  function recBills(id) {
    state.recBills = null;
    paintRail();
    if ($('supBillList')) UI.skeleton($('supBillList'), 3);
    rpc('supplier_bills', { p_supplier: id, p_paid_from: null, p_doc: null }).then(function (x) {
      if (state.open !== id) return;
      var d = x.data || {};
      state.recBills = x.error || d.error ? { err: x.error ? { error: x.error } : d } : d;
      paintRecBills();
      paintRail();
    });
  }
  var DOTS_SM = DOTS;
  function paintRecBills() {
    var host = $('supBillList'), d = state.recBills;
    var n = $('supPayTabN');
    if (!d || d.err) {
      if (n) n.hidden = true;
      if (host && d && d.err) UI.failLine(host, 'The bills', billSaid(d.err), function () { recBills(state.open); });
      return;
    }
    var today = d.today, list = (d.bills || []).slice();
    var order = { overdue: 0, waiting: 1, paid: 2 };
    list.sort(function (a, b) {
      var x = billState(a, today), y = billState(b, today);
      if (x !== y) return order[x] - order[y];
      return x === 'paid' ? String(b.paid_on || b.date).localeCompare(String(a.paid_on || a.date)) : String(a.due).localeCompare(String(b.due));
    });
    var late = list.filter(function (b) { return billState(b, today) === 'overdue'; }).length;
    if (n) { n.textContent = late; n.hidden = !late; }
    if (window.ADspaceForm && window.ADspaceForm.thumb && $('supTabs')) window.ADspaceForm.thumb($('supTabs'));
    if (!host) return;
    var read = $('supBillRead');
    if (read) read.hidden = !d.work;
    host.innerHTML = (list.length ? list.map(function (b) {
      var k = billState(b, today), st = BILL_STATE[k];
      var sub = ['<span class="nb">' + esc(money(b.amount, b.currency)) + '</span>'];
      if (k !== 'paid' && Number(b.balance) < Number(b.amount)) sub.push('<span class="nb">' + esc(money(b.balance, b.currency)) + ' owing</span>');
      var when = k === 'overdue' ? lateBy(b, today) : k === 'waiting' ? 'Due ' + billDay(b.due) : billDay(b.paid_on || b.date);
      return '<div class="cpay-job prow" data-bill="' + esc(b.id) + '">' +
        '<div class="cpay-job-l pr-main"><span class="cpay-job-ref">' + esc(window.ADspaceWords.line.docNo(b.number, b.ref_no)) + '</span><span class="cpay-job-sub">' + sub.join(' · ') + '</span></div>' +
        '<span class="cpay-job-st pr-state"><span class="chip-state ' + st[1] + '">' + esc(st[0]) + '</span></span>' +
        '<span class="cpay-job-end pr-end"><span class="cpay-job-sub">' + esc(when) + '</span></span>' +
        '<span class="pr-act"><span class="team-act"><button class="kmenu-btn" type="button" data-a="billmenu" aria-label="More actions for ' + esc(b.number || '') + '" aria-expanded="false">' + DOTS_SM + '</button>' +
          '<div class="kmenu" role="menu" hidden><button class="kmenu-item" data-g="1" type="button" role="menuitem" data-a="bukku">Open in Bukku</button></div></span></span>' +
        '</div>';
    }).join('') : '<p class="emptyline">No bills.</p>') +
      (d.read_at ? '<p class="muted cpay-read">Read from Bukku ' + esc(window.ADspaceClock.date(d.read_at) + ', ' + window.ADspaceClock.clock(d.read_at)) + '</p>' : '');
    host.querySelectorAll('[data-a="billmenu"]').forEach(function (b) {
      var m = b.parentNode.querySelector('.kmenu');
      b.addEventListener('click', function (e) {
        e.stopPropagation();
        var open = m.hidden;
        shutMenus(); m.hidden = !open; b.setAttribute('aria-expanded', String(open));
        if (open) window.ADspaceMenu.place(b, m);
      });
      m.querySelector('[data-a="bukku"]').addEventListener('click', function (e) {
        e.stopPropagation(); shutMenus();
        openBill(b.closest('[data-bill]').getAttribute('data-bill'), 'supBillMsg');
      });
    });
    if (read && !read.getAttribute('data-wired')) {
      read.setAttribute('data-wired', '1');
      read.addEventListener('click', function () { readBukku(read, 'supBillMsg', function () { recBills(state.open); loadBills(); }); });
    }
  }
  /* The rail (screen c-alt): Totals, a figure a currency, then what the
     record holds of its bills; a block with nothing leaves. */
  function paintRail() {
    var rail = $('supRail'), d = state.recBills;
    if (!rail) return;
    var list = d && !d.err ? d.bills || [] : [], html = '';
    if (list.length) {
      var today = d.today;
      var lines = function (label, fig, only) {
        var t = byCur(only ? list.filter(only) : list, fig);
        return '<div><dt>' + esc(label) + '</dt><dd class="crtot">' + (t.length ? t.map(function (x) {
          return '<span class="crtot-amt">' + esc(money(x.amt, x.cur)) + '</span>';
        }).join('') : '<span class="muted">' + esc(money(0, list[0].currency)) + '</span>') + '</dd></div>';
      };
      html += '<section class="railblock rail-after" id="supTotals"><h3 class="railtitle">Totals</h3><dl class="raildates">' +
        lines('Billed', function (b) { return b.amount; }) +
        lines('Paid', function (b) { return Number(b.amount) - Number(b.balance); }) +
        lines('Outstanding', function (b) { return b.balance; }, function (b) { return Number(b.balance) > 0; }) +
        lines('Overdue', function (b) { return b.balance; }, function (b) { return billState(b, today) === 'overdue'; }) + '</dl></section>';
      var last = list.reduce(function (m, b) { return !m || b.date > m ? b.date : m; }, '');
      var paid = list.reduce(function (m, b) { return b.paid_on && (!m || b.paid_on > m) ? b.paid_on : m; }, '');
      html += '<section class="railblock rail-after"><h3 class="railtitle">Bill history</h3><dl class="raildates">' +
        '<div><dt>Bills</dt><dd>' + list.length + '</dd></div>' +
        (last ? '<div><dt>Last bill</dt><dd>' + esc(billDay(last)) + '</dd></div>' : '') +
        (paid ? '<div><dt>Last paid</dt><dd>' + esc(billDay(paid)) + '</dd></div>' : '') + '</dl></section>';
    }
    rail.innerHTML = html;
    rail.hidden = !html;
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
    $('supTiles').hidden = true; $('spyView').hidden = true; $('supViewsBox').hidden = true;
    if (!state.rec || state.rec.id !== id) UI.skeleton(rec, 4);
    return rpc('supplier_get', { p_id: id }).then(function (r) {
      /* An answer for a record already left never paints over the one open
         now (SUP-1, 2026-10-22; as tests/crswitch.js holds for sets). */
      if (state.open !== id) return;
      var d = r.data || {};
      if (r.error || d.error) {
        if (d.error === 'not-found') { state.open = null; setUrl(); msg('supMsg', 'This supplier no longer exists.', 'err'); paint(); return; }
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
    ['Billing details', [['kind', 'Supplier type'], ['brn', 'BRN'], ['nric', 'NRIC', 1], ['tin', 'TIN'], ['sst_no', 'SST Registration No.'], ['phone', 'Office / mobile'], ['address', 'Billing address']]],
    ['Person in charge', [['contact_name', 'Legal name'], ['designation', 'Designation'], ['email', 'Email'], ['mobile', 'Mobile / WhatsApp']]],
    ['Payment details', [['payment_term', 'Payment term'], ['currency', 'Currency'], ['finance_email', 'Finance email'],
      ['payee_name', 'Payee name', 1], ['bank_name', 'Bank', 1], ['bank_account', 'Account number', 1], ['swift', 'SWIFT code', 1], ['bank_address', 'Bank address', 1]]]
  ];
  function valueOf(s, k) {
    var v = s[k];
    if (k === 'kind') return v === 'individual' ? 'Individual' : v === 'company' ? 'Company' : '';
    if (k === 'currency') return v === 'SGD' ? 'SGD / S$' : v === 'MYR' ? 'MYR / RM' : '';
    if (k === 'bank_name') return window.ADspaceWords.bank(v);
    if (k === 'phone' || k === 'mobile') return window.ADspaceAPI.phoneWord(v);
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
  /* Under the record's own three headings, so seventeen answers read as
     the record will hold them (2026-10-27, SUP-12). */
  function answersOf(f) {
    var a = f.answers || {}, out = '';
    GROUPS.forEach(function (g, gi) {
      var rows = [];
      if (gi === 0 && a.name) rows.push('<div><dt>Name</dt><dd>' + esc(a.name) + '</dd></div>');
      g[1].forEach(function (it) {
        var k = it[0];
        if (k === 'nric' && a.kind !== 'individual') return;
        var v = valueOf(a, k);
        if (!v) return;
        if (it[2] && !state.pay) return;
        rows.push('<div><dt>' + esc(it[1]) + '</dt><dd' + (k === 'address' || k === 'bank_address' ? ' class="is-pre"' : '') + '>' + esc(v) + '</dd></div>');
      });
      if (gi === 2 && !state.pay && f.bank_changed) rows.push('<div><dt>Bank details</dt><dd>Provided</dd></div>');
      if (rows.length) out += '<h5 class="sup-ans-h">' + esc(g[0]) + '</h5><dl class="ovfacts">' + rows.join('') + '</dl>';
    });
    return out;
  }
  function formBlock() {
    var f = state.form, work = may('suppliers', 'work'), s = state.rec;
    var update = f && f.purpose === 'update';
    if (f && f.state === 'submitted') {
      var held = update && f.bank_changed && !payWork();
      return formHead(update ? 'Details update' : 'Request from supplier', work && !held
          ? '<button class="btn btn-sm btn-primary" type="button" data-s="use">' + (update ? 'Use changes' : 'Use details') + '</button>' : '') +
        /* The received day is the head's; the state says what waits. */
        '<dl class="ovfacts"><div><dt>State</dt><dd>' + (update || s.name ? 'Received ' + esc(day(f.submitted_at)) + ', waiting to be applied' : 'Waiting to be applied') + '</dd></div>' +
        (update ? changesOf(f) + '</dl>' : '</dl>' + answersOf(f)) +
        (held && work ? '<p class="msg warn">The bank details changed. A colleague with access to supplier bank details must use these changes.</p>' : '');
    }
    /* An open link reads the same whether it asks for the details first or
       for a change to them (2026-10-20, the user: the update link's ⋯ alone
       read as "confusing"): what it is, until when, the link itself. */
    if (f && f.state === 'open' && (update || s.status === 'pending')) {
      var url = f.key ? linkOf(f.key) : '';
      return formHead(update ? 'Details update form' : 'Request from supplier', work ? formMenu('<button class="kmenu-item" data-g="5" type="button" data-s="reset" role="menuitem">Reset link</button><button class="kmenu-item" data-g="5" type="button" data-s="close" role="menuitem">Close link</button>') : '') +
        '<dl class="ovfacts"><div><dt>State</dt><dd>Sent, open until ' + esc(day(f.expires_at)) + '</dd></div></dl>' +
        (url ? '<div class="rec-linktools" data-page-link="supplier"><div class="linkbox">' +
          '<input class="input readfield" id="supLink" readonly aria-label="' + (update ? 'Details update form link' : 'Request from supplier link') + '" value="' + esc(url) + '">' +
          '<button class="btn btn-icon" type="button" data-s="copy"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15H4.5A1.5 1.5 0 0 1 3 13.5v-9A1.5 1.5 0 0 1 4.5 3h9A1.5 1.5 0 0 1 15 4.5V5"/></svg><span>Copy link</span></button>' +
          '<a class="btn btn-icon" href="' + esc(url) + '" target="_blank" rel="noopener">Preview <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 4h6v6"/><path d="M20 4 11 13"/><path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg></a>' +
          '</div></div>' : '');
    }
    if (s.status === 'active') {
      var mine = update ? f : null;
      if (!work && !mine) return '';
      return formHead('Details update form', work ? '<button class="btn btn-sm" type="button" data-s="link">Create link</button>' : '') +
        '<dl class="ovfacts"><div><dt>State</dt><dd>' + (!mine ? 'Not sent' : mine.state === 'used'
          ? 'Received ' + esc(day(mine.submitted_at)) + ', applied' : 'Link expired ' + esc(day(mine.expires_at))) + '</dd></div></dl>';
    }
    if (s.status !== 'pending') return '';
    if (!work && !f) return '';
    return formHead('Request from supplier', work ? '<button class="btn btn-sm" type="button" data-s="link">Create link</button>' : '') +
      '<dl class="ovfacts"><div><dt>State</dt><dd>' + (!f ? 'Not sent' : f.state === 'used'
        ? 'Received ' + esc(day(f.submitted_at)) + ', applied' : 'Link expired ' + esc(day(f.expires_at))) + '</dd></div></dl>';
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
        (noDetails ? '<section class="readgroup"><div class="readgroup-head"><h4 class="fsec-h">Details</h4></div><p class="muted">No details.</p></section>'
          : group(GROUPS[0]) + group(GROUPS[1])),
      payment: (noDetails ? '' : group(GROUPS[2])) +
        (fb && quiet ? '<section class="readgroup sup-form">' + fb + '</section>' : '') +
        (s.status === 'active' ? '<section class="readgroup bk-group" id="supBukku" hidden></section>' : '') +
        /* The supplier's bills from Bukku (SUPPLIER BILLS, 2026-11-22): after
           the Bukku band, as a creator's Payment pane holds its payments. */
        (s.status !== 'pending' ? '<section class="readgroup" id="supBills"><div class="readgroup-head"><h4 class="fsec-h">Bills</h4>' +
          '<span class="cpay-acts"><button class="btn btn-sm" type="button" id="supBillRead" data-gate="bukku" hidden>Read from Bukku</button></span></div>' +
          '<div class="msg" id="supBillMsg" role="status"></div><div id="supBillList"></div></section>' : ''),
      documents: '<section class="readgroup" id="supLetters"><div class="readgroup-head"><h4 class="fsec-h">Documents</h4>' +
          /* Each act stands in the section it fills (2026-10-20): Issue
             document beside Add existing document; Send email in Emails.
             Only an Active supplier is issued a document (DOC-3). A ⋯ of one
             item is a button (the menu standard, rule 8; SUP-3). */
          (work ? '<span class="sup-head-acts">' + (s.status === 'active' ? '<button class="btn btn-sm" type="button" data-s="issue">Issue document</button>' : '') +
            '<button class="btn btn-sm" type="button" data-s="add">Add existing document</button></span>' : '') + '</div>' +
          '<div id="supLetterList"><p class="muted">Loading.</p></div></section>',
      emails: '<section class="readgroup" id="supEmails"><div class="readgroup-head"><h4 class="fsec-h">Emails</h4>' +
          (work && s.email && may('send.email', 'work') ? '<button class="btn btn-sm" type="button" data-s="mail" data-gate="email">Send email</button>' : '') + '</div>' +
          '<div id="supEmailList"><p class="muted">Loading.</p></div></section>'
    };
    /* A Pending supplier holding no details has nothing a document or an
       email can name yet: those panes wait until it does (2026-10-27,
       SUP-13). */
    if (s.status === 'pending' && noDetails) { panes.documents = ''; panes.emails = ''; }
    var shown = PANES.filter(function (x) { return panes[x[0]]; });
    if (!shown.some(function (x) { return x[0] === state.pane; })) state.pane = 'overview';
    rec.innerHTML =
      '<button class="backlink" type="button" data-s="back">' + BACK + 'Back</button>' +
      '<div class="panel sup-rec sup-headcard">' +
        /* The record head every record draws (`.rec-id`): the name over its
         meta, the state and the ⋯ (2026-11-03); no disc, since a supplier
         holds no picture to fill one (the user, 2026-11-04). */
        '<div class="rec-id is-nomark sup-head">' +
          '<div class="rec-who sup-who-h"><div class="rec-name"><h2>' + esc(nameOf(s)) + '</h2></div><p class="rec-id-meta sup-meta">' + (s.name ? '<span class="sup-code">' + esc(s.code) + '</span>' : got ? 'Received ' + esc(day(state.form.submitted_at)) : s.waiting ? '' : 'Waiting for their details') +
          (s.approved_at ? ' · Approved ' + esc(day(s.approved_at)) + (s.approved_by ? ' by ' + esc(s.approved_by) : '') : '') + '</p></div>' +
          '<div class="rec-ctl sup-ctl">' + chip(s, got && s.status === 'pending') +
            (menu ? '<span class="team-act"><button class="kmenu-btn" type="button" data-s="menu" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
              '<div class="kmenu" data-s-menu="rec" hidden>' + menu + '</div></span>' : '') +
          '</div></div>' +
          /* The forward move under the head at its own width, so the name
             keeps its line beside the state and the ⋯ (2026-10-27, SUP-10). */
          (s.status === 'pending' && work && complete ? '<div class="sup-go"><button class="btn btn-sm btn-primary" type="button" data-s="approve">Approve</button></div>' : '') +
        '</div>' +
      /* The record's grid, as a creator's (SUPPLIER BILLS, 2026-11-22): the
         strip and the pane, and a rail of its totals that follows the pane
         on a phone. */
      '<div class="rec crr-body sup-recbody">' +
      (shown.length > 1 ? '<nav class="rectabs crr-tabs sup-tabs" id="supTabs" role="tablist" aria-label="Supplier">' + shown.map(function (x) {
        var on = x[0] === state.pane;
        return '<button class="tab' + (on ? ' is-on' : '') + '" type="button" role="tab" aria-selected="' + on + '" data-pane="' + x[0] + '">' + esc(x[1]) +
          (x[0] === 'payment' ? '<span class="tab-n is-err" id="supPayTabN" hidden></span>' : '') + '</button>';
      }).join('') + '</nav>' : '') +
      '<div class="rec-panes"><div class="msg" id="supRecMsg"></div>' +
      '<div class="rec-pane crr-pane" id="supPane" data-narrow="640"><div class="panel crr-card sup-body" data-swipe="supTabs">' + shown.map(function (x) {
        return '<div class="readgroups sup-pane" data-pane="' + x[0] + '"' + (x[0] === state.pane ? '' : ' hidden') + '>' + panes[x[0]] + '</div>';
      }).join('') + '</div></div></div>' +
      '<aside class="rec-rail" id="supRail" aria-label="Supplier facts" hidden></aside></div>';
    Array.prototype.forEach.call(rec.querySelectorAll('#supTabs .tab'), function (t) {
      t.addEventListener('click', function () { showPane(t.getAttribute('data-pane'), true); });
    });
    if (window.ADspaceActs && window.ADspaceActs.scan) window.ADspaceActs.scan(rec);
    if (window.ADspaceForm && window.ADspaceForm.thumb && $('supTabs')) window.ADspaceForm.thumb($('supTabs'));
    if (UI.fit) UI.fit();
    recBills(s.id);
    /* Bukku (2026-10-18): an approved supplier sent as a Bukku contact; one
       linked to a client is that client's contact, typed Supplier too.
       Linked first, as a client is (2026-11-22): once linked the band leads
       Payment and reads Bukku; Use Bukku's reads the supplier again; a link
       made or let go reads its bills at once. */
    if (window.ADspaceBukku && $('supBukku')) window.ADspaceBukku.group($('supBukku'), 'supplier', s.id, {
      note: s.client_id ? 'Sent as the linked client\'s contact in Bukku.' : '', lead: true,
      read: function (x) { if ((x.changed || []).length && state.open === s.id) openRec(s.id); },
      after: function () { if (state.open === s.id) recBills(s.id); loadBills(); }
    });
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
    if (window.ADspaceForm && window.ADspaceForm.thumb && $('supTabs')) window.ADspaceForm.thumb($('supTabs'));
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
      window.ADspaceConfirm.ask({ title: 'Reset link?', body: 'The link sent before will stop working. A new link will be created.', go: 'Reset link', tone: 'warn' },
        function () { link(true); });
    });
    /* Close link (2026-10-18): the link stops opening and no new one is
       made; Create link makes one again. */
    on('close', function () {
      window.ADspaceConfirm.ask({ title: 'Close link?', body: 'The link sent will stop working. A new link can be created later.', go: 'Close link', tone: 'warn', wait: true },
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
        body: nameOf(s) + ' and its details will be deleted. Letters already issued keep their words. This cannot be undone.',
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
            if (d.source === 'manual') { var u = window.ADspaceWords.absUrl(d.file_url); if (u) window.open(u, '_blank', 'noopener'); return; }
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
          '<span class="sup-mail-meta">' + (e.to ? esc(window.ADspaceWords.line.sendTo(e.to, e.cc)) : window.ADspaceWords.line.addrGone) + (e.document && e.purpose === 'message' ? ' · ' + esc(e.document) : '') + (e.by ? ' · ' + esc(e.by) : '') + '</span></dd></div>';
      }).join('') + '</dl>';
    });
  }
  function offerMail(s) {
    if (!s.email || !may('suppliers', 'work') || !may('send.email', 'work')) return;
    /* Switched off in Settings (SEND SWITCHES, 2026-11-21): the approval
       stands and nothing is offered; Send email on the record says why. */
    var A = window.ADspaceAdmin;
    if (A && A.gateState && !A.gateState('email').on) return;
    window.ADspaceConfirm.ask({ title: 'Send the approval email?', go: 'Send email', cancel: 'Not now',
      body: (s.contact_name || nameOf(s)) + ' will be told by email that the registration is approved.' }, function () { openMail('approved', null, true); });
  }

  /* Send email (#supMailSheet): the template's words filled from the record
     by supplier_email_prepare, changed here if need be, sent by
     supplier-mail; a letter is drawn here and goes as its PDF. */
  var mail = null;
  /* Opened from Approve's question, the sheet's Send sends without asking
     again: the question was asked once (the user, 2026-10-27, SUP-11: it
     asks, never sends by itself, until the portal's flows are settled). */
  function openMail(purpose, docId, asked) {
    var s = state.rec;
    mail = { supplier: s.id, docs: [], asked: Boolean(asked) };
    msg('supMailMsg', ''); $('supMailRecent').hidden = true;
    $('supMailTo').textContent = 'Loading…';
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
    if (window.ADspaceDocMail) window.ADspaceDocMail.showSender('suppliers', $('supMailFrom'), $('supMailReply'));
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
        msg('supMailMsg', SAID[code] || (r.error ? 'Not sent. Please try again.' : 'Not sent.'), 'err');
      });
    }).catch(function (e) {
      go.disabled = false;
      msg('supMailMsg', 'The letter could not be generated. Please try again.', 'err');
    });
  }
  function askMail() {
    var p = mail && mail.prep;
    if (!p) return;
    if (mail.asked) { sendMail(false); return; }
    var cc = !$('supMailCcLine').hidden && $('supMailCc').checked;
    window.ADspaceConfirm.ask({ title: 'Send email?', go: 'Send',
      body: window.ADspaceWords.line.sendTo(p.to.email, cc && p.cc) + '.' }, function () { sendMail(false); });
  }
  function shutMail() {
    $('supMailSheet').hidden = true;
    mail = null;
  }

  function wireMail() {
    if (!$('supMailSheet') || $('supMailSheet').__wired) return;
    $('supMailSheet').__wired = true;
    $('supMailTpl').addEventListener('change', function () { if (mail) prepare(); });
    $('supMailDoc').addEventListener('change', function () { if (mail) prepare(); });
    $('supMailGo').addEventListener('click', askMail);
    $('supMailCancel').addEventListener('click', shutMail);
    $('supMailClose').addEventListener('click', shutMail);
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
      $('supEdBank').innerHTML = '<option value="">Choose a bank</option>' + BANKS.map(function (t) { return '<option value="' + esc(t) + '">' + esc(window.ADspaceWords.bank(t)) + '</option>'; }).join('');
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
    var badMail = [['email', 'supEdEmail'], ['finance_email', 'supEdFin']].filter(function (x) { return v[x[0]] && !ADspaceWords.emailOk(v[x[0]]); })[0];
    if (badMail) { msg('supEditMsg', 'Enter a valid email address.', 'err'); $(badMail[1]).focus(); return; }
    /* Only what moved from the copy the sheet opened on is sent, with that
       copy's stamp: a colleague's newer bank account is never put back
       (review 2026-11-24). The Supplier ID always goes, the function's
       one check reading it. */
    var rec = state.rec, out = { code: v.code, expected: rec.updated_at || null };
    Object.keys(v).forEach(function (k) {
      if (String(v[k] == null ? '' : v[k]) !== String(rec[k] == null ? '' : rec[k])) out[k] = v[k];
    });
    if (!out.expected) delete out.expected;
    var go = $('supEditGo');
    go.disabled = true;
    rpc('supplier_save', { p_id: rec.id, p_values: out, p_form: editing.form || null }).then(function (r) {
      go.disabled = false;
      var d = r.data || {};
      if (d.error === 'stale') {
        shutEdit();
        openRec(rec.id);
        setTimeout(function () { msg('supRecMsg', window.ADspaceWords.line.stale, 'err'); }, 400);
        return;
      }
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

  window.ADspaceSuppliers = { enter: enter, urlState: urlState, load: load };
})();
