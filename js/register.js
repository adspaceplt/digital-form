/*
 * Register — every document the portal has issued or been told about, and
 * the sheet that issues one.
 *
 * The list is the documents table with the Letters of Offer left to the
 * client record that owns them. Rows are banded by family (quotation covers,
 * client letters, HR letters, other), and an HR row reaches this page only
 * where the database's own policy lets it: HR is its own section in the
 * access ladder, so nothing here decides who may read a colleague's letter.
 *
 * The issue sheet is one sheet for every kind. The client record opens it
 * with the client fixed (`openIssue({ client })`); the Register opens it with
 * the client or the colleague to choose. A quotation cover takes the
 * reference typed from the accounting portal; every other kind takes the one
 * the database builds unless one is typed over it.
 */
(function () {
  var API = window.ADspaceAPI;
  var db  = API && API.client;
  var LET = window.ADspaceLetters;
  var UI  = window.ADspaceState;
  var bridge = window.ADspaceAdmin || {};
  if (!API || !API.configured || !db || !LET || !UI) return;

  function $(id) { return document.getElementById(id); }
  var esc = UI.esc || function (s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  };
  function msg(id, text, kind) {
    var el = $(id); if (!el) return;
    el.textContent = text || '';
    el.className = 'msg' + (kind && text ? ' ' + kind : '');
  }
  function niceDate(d) {
    if (!d) return '';
    var dt = new Date(String(d).slice(0, 10) + 'T00:00:00');
    if (isNaN(dt.getTime())) return String(d);
    return dt.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
  }
  function today() { return new Date().toISOString().slice(0, 10); }
  function may(section, level) { return Boolean(bridge.may && bridge.may(section, level)); }
  /* Client letters answer to the Register or to Clients, as the database's
     register_may() does; HR letters answer to HR alone. */
  function mayFamily(family, level) {
    if (family === 'hr') return may('hr', level);
    if (family === 'other') return may('register', level);
    return may('register', level) || may('clients', level);
  }

  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>';
  function menuItem(action, label, cls, need) {
    return '<button class="kmenu-item ' + (cls || '') + '" data-a="' + action + '" type="button"' +
      (need ? ' data-need="' + need + '"' : '') + '><b>' + esc(label) + '</b></button>';
  }
  function shutMenus() {
    Array.prototype.forEach.call(document.querySelectorAll('.reg-row .kmenu'), function (m) { m.hidden = true; });
    Array.prototype.forEach.call(document.querySelectorAll('.reg-row .kmenu-btn'), function (b) { b.setAttribute('aria-expanded', 'false'); });
  }
  function wireMenu(el) {
    var btn = el.querySelector('[data-a="menu"]'), menu = el.querySelector('[data-menu]');
    if (!btn || !menu) return;
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      var open = menu.hidden;
      shutMenus();
      menu.hidden = !open;
      btn.setAttribute('aria-expanded', String(open));
      if (open) window.ADspaceMenu.place(btn, menu);
    });
  }
  window.ADspaceMenu.onScroll(shutMenus);
  document.addEventListener('click', function (e) {
    if (!e.target.closest || !e.target.closest('.reg-row .team-act')) shutMenus();
  });

  // ---- The list ------------------------------------------------------------
  var state = { docs: null, clients: [], members: [], types: [], me: null, find: '', fam: '', err: null };
  var FAMILIES = ['quote_cover', 'client', 'hr', 'other'];
  var BAND = { quote_cover: 'Quotation covers', client: 'Client letters', hr: 'HR letters', other: 'Other documents' };

  function clientOf(id) { return state.clients.filter(function (c) { return c.id === id; })[0]; }
  function memberOf(id) { return state.members.filter(function (m) { return m.id === id; })[0]; }
  function whoOf(d) {
    var rc = d.recipient || {};
    if (d.family === 'hr') { var m = memberOf(d.member_id); return (m && m.name) || rc.name || ''; }
    var c = clientOf(d.client_id);
    return (c && c.name) || rc.name || '';
  }

  function loadPeople(then) {
    Promise.all([
      db.from('clients').select('id, name, legal_name, client_code, billing_address, market, stage').order('name'),
      db.from('team_members').select('id, name, email, staff_code, designation, active').order('name'),
      LET.types ? new Promise(function (res) { LET.types(function (rows) { res(rows); }); }) : Promise.resolve([])
    ]).then(function (r) {
      state.clients = (r[0] && r[0].data) || [];
      state.members = (r[1] && r[1].data) || [];
      state.types = r[2] || [];
      var meMail = String(bridge.actor ? bridge.actor() : '').toLowerCase();
      state.me = state.members.filter(function (m) { return String(m.email || '').toLowerCase() === meMail; })[0] || null;
      then();
    }, function () { then(); });
  }

  function enter() {
    var bar = $('regIssue'), add = $('regAdd');
    if (bar) bar.hidden = !(mayFamily('client', 'work') || mayFamily('hr', 'work') || mayFamily('quote_cover', 'work'));
    if (add) add.hidden = !(may('register', 'work') || mayFamily('client', 'work'));
    load();
  }

  function load() {
    var box = $('regList');
    if (!box) return;
    if (!box.querySelector('.crm-table')) UI.skeleton(box, 5);
    state.err = null;
    loadPeople(function () {
      LET.listAll(function (rows, err) {
        if (err) { state.err = err; UI.failLine(box, 'the register', err.message || String(err), load); return; }
        state.docs = rows || [];
        paint();
      });
    });
  }

  function matches(d) {
    if (state.fam && d.family !== state.fam) return false;
    if (!state.find) return true;
    var hay = [d.serial, d.kind, whoOf(d), (d.recipient || {}).name, d.issued_by].join(' ').toLowerCase();
    return hay.indexOf(state.find) > -1;
  }

  function paint() {
    var box = $('regList');
    if (!box || !state.docs) return;
    var all = state.docs, rows = all.filter(matches);
    var count = $('regCount');
    if (count) {
      count.textContent = !all.length ? ''
        : rows.length === all.length ? all.length + (all.length === 1 ? ' document' : ' documents')
        : rows.length + ' of ' + all.length;
    }
    if (!all.length) {
      UI.emptyLine(box, 'No documents.', $('regAdd') && !$('regAdd').hidden ? 'Add the first entry' : '', openAdd);
      return;
    }
    if (!rows.length) {
      UI.emptyLine(box, 'No matches.', 'Clear the filters', function () {
        state.find = ''; state.fam = '';
        if ($('regFind')) $('regFind').value = '';
        if ($('regFam')) $('regFam').value = '';
        paint();
      });
      return;
    }
    box.innerHTML = '';
    var table = document.createElement('div');
    table.className = 'crm-table softpanel';
    table.innerHTML = '<div class="crm-head svc-row reg-row"><span>Document</span><span>Recipient</span><span>Issued</span><span></span></div>';
    FAMILIES.forEach(function (f) {
      var mine = rows.filter(function (d) { return d.family === f; });
      if (!mine.length) return;
      var cat = document.createElement('div');
      cat.className = 'svc-cat';
      cat.innerHTML = esc(BAND[f]) + ' <span>' + mine.length + '</span>';
      table.appendChild(cat);
      mine.forEach(function (d) { table.appendChild(row(d, f === 'hr' ? 'hr:manage' : 'register:manage')); });
    });
    box.appendChild(table);
  }

  /* One row shape on the Register and on the client record: the reference
     and what it is, who it went to, when. Valid is the ordinary case, so the
     row says nothing while it holds and names Void beside the reference. */
  function row(d, need, onChange) {
    var el = document.createElement('div');
    el.className = 'svc-row reg-row' + (d.voided_at ? ' is-off' : '');
    var sub = [d.kind, d.source === 'manual' ? 'Added by hand' : '', d.issued_by].filter(Boolean).join(' · ');
    el.innerHTML =
      '<span class="svc-name"><b>' + esc(d.serial) + (d.voided_at ? ' <span class="tone">Void</span>' : '') + '</b>' +
        '<small>' + esc(sub) + '</small></span>' +
      '<span class="reg-who">' + esc(whoOf(d)) + '</span>' +
      '<span class="reg-date">' + esc(niceDate(d.issued_at)) + '</span>' +
      '<span class="team-act">' +
        '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
        '<div class="kmenu" data-menu hidden>' +
          (d.source === 'portal' ? menuItem('download', 'Download') : '') +
          (d.file_url ? menuItem('open', 'Open file') : '') +
          (d.source === 'manual' ? menuItem('edit', 'Edit') : '') +
          (d.voided_at ? '' : menuItem('void', 'Void', 'is-danger', need)) +
          menuItem('del', 'Delete permanently', 'is-danger', need) +
        '</div>' +
      '</span>';
    wireMenu(el);
    var on = function (a, fn) { var b = el.querySelector('[data-a="' + a + '"]'); if (b) b.addEventListener('click', function () { shutMenus(); fn(); }); };
    on('download', function () {
      LET.download(d, function (warn) { if (warn) say(warn, 'err'); });
    });
    on('open', function () { window.open(d.file_url, '_blank', 'noopener'); });
    on('edit', function () { openAdd(d, onChange); });
    on('void', function () { openVoid(d, onChange); });
    on('del', function () { openDelete(d, onChange); });
    return el;
  }
  var sayTo = 'regMsg';
  function say(text, kind) { msg(sayTo, text, kind); }

  /* The client record's Documents pane draws the register rows for that
     client under its Letters of Offer, through this, so the row is the same
     shape on both pages and the client's own permission gates the acts. */
  function paintFor(clientId, box, then) {
    if (!box) return;
    loadPeople(function () {
      LET.list(clientId, function (rows, err) {
        if (err || !rows.length) { if (then) then(rows || [], err); return; }
        var table = document.createElement('div');
        table.className = 'crm-table reg-table';
        table.innerHTML = '<div class="crm-head svc-row reg-row"><span>Document</span><span>Recipient</span><span>Issued</span><span></span></div>';
        rows.forEach(function (d) {
          table.appendChild(row(d, 'clients:manage', function () { paintFor(clientId, box, then); }));
        });
        var old = box.querySelector('.reg-table');
        if (old) old.remove();
        box.appendChild(table);
        if (then) then(rows, null);
      });
    });
  }

  if ($('regFind')) $('regFind').addEventListener('input', function () {
    var v = this.value.trim().toLowerCase();
    if (v === state.find) return;
    state.find = v; paint();
  });
  if ($('regFam')) $('regFam').addEventListener('change', function () {
    if (this.value === state.fam) return;
    state.fam = this.value; paint();
  });

  // ---- Issuing ----------------------------------------------------------------
  var issuing = null;   // { client, member, families, idem, onDone }

  function typeById(id) { return state.types.filter(function (t) { return t.id === id; })[0]; }
  function fillKinds() {
    var sel = $('docKind');
    var allowed = state.types.filter(function (t) {
      if (issuing.families && issuing.families.indexOf(t.family) < 0) return false;
      return mayFamily(t.family, 'work');
    });
    sel.innerHTML = allowed.map(function (t) { return '<option value="' + esc(t.id) + '">' + esc(t.name) + '</option>'; }).join('');
    return allowed;
  }
  function fillClients() {
    var sel = $('docClient');
    sel.innerHTML = '<option value="">Choose a client</option>' + state.clients.map(function (c) {
      return '<option value="' + esc(c.id) + '">' + esc(c.name + (c.client_code ? ' · ' + c.client_code : '')) + '</option>';
    }).join('');
  }
  function fillMembers() {
    var sel = $('docMember');
    sel.innerHTML = '<option value="">Choose a colleague</option>' + state.members.filter(function (m) { return m.active !== false; }).map(function (m) {
      return '<option value="' + esc(m.id) + '">' + esc(m.name + (m.staff_code ? ' · ' + m.staff_code : '')) + '</option>';
    }).join('');
  }

  function firstName(s) { return String(s || '').trim().split(/\s+/)[0] || ''; }

  /* What the kind decides: which fields draw, what they start with. A person
     may overwrite anything; the type only seeds. Changing the client or the
     colleague afterwards reseeds the recipient and, where the words have not
     been touched since they were seeded, the salutation and the body: a body
     somebody has already edited is never overwritten by a select. */
  var seeded = { sal: null, body: null };
  function seed(e) {
    var t = typeById($('docKind').value);
    if (!t) return;
    var reseed = !(e && e.target && e.target.id !== 'docKind');
    var keepSal = !reseed && $('docSal').value !== seeded.sal;
    var keepBody = !reseed && $('docBodyEn').value !== seeded.body;
    var hr = t.family === 'hr', quote = t.family === 'quote_cover';
    $('docClientWrap').hidden = hr || Boolean(issuing.client);
    $('docMemberWrap').hidden = !hr;
    $('docToRow').hidden = hr;
    $('docAttnRow').hidden = hr;
    $('docHrRow').hidden = !hr;
    $('docLangRow').hidden = !quote;
    $('docSignRow').hidden = !t.signed;
    $('docSerial').placeholder = quote ? 'AQT2607003' : 'Assigned on issue';
    if (reseed) { $('docTitleIn').value = t.title || ''; $('docSerial').value = ''; }
    var c = issuing.client || clientOf($('docClient').value);
    var m = memberOf($('docMember').value);
    var vars = {};
    if (!hr && c) {
      $('docTo').value = c.legal_name || c.name || '';
      $('docAddr').value = c.billing_address || '';
      var main = issuing.contact || {};
      $('docAttn').value = main.name || '';
      $('docAttnRole').value = main.role || '';
      vars['client'] = c.legal_name || c.name;
      vars['first name'] = firstName(main.name);
    }
    if (hr && m) {
      $('docRole').value = m.designation || '';
      vars['first name'] = firstName(m.name);
      vars['role'] = m.designation || '';
    }
    if (!keepSal) { $('docSal').value = LET.fill(t.salutation, vars); seeded.sal = $('docSal').value; }
    if (!keepBody) { $('docBodyEn').value = LET.fill(t.body_en, vars); seeded.body = $('docBodyEn').value; }
    if (reseed) {
      $('docBodyZh').value = t.body_zh || '';
      $('docBodyMs').value = t.body_ms || '';
      $('docLangEn').checked = true;
      $('docLangZh').checked = quote && Boolean(t.body_zh);
      $('docLangMs').checked = quote && Boolean(t.body_ms);
      langBodies();
    }
    if (t.signed && reseed) {
      $('docSigName').value = (state.me && state.me.name) || (bridge.actorName ? bridge.actorName() : '') || '';
      $('docSigRole').value = (state.me && state.me.designation) || '';
    }
  }
  function langBodies() {
    $('docBodyZhWrap').hidden = !$('docLangZh').checked || $('docLangRow').hidden;
    $('docBodyMsWrap').hidden = !$('docLangMs').checked || $('docLangRow').hidden;
  }

  function openIssue(opts) {
    opts = opts || {};
    issuing = { client: opts.client || null, contact: opts.contact || null, families: opts.families || null,
                idem: null, onDone: opts.onDone || null };
    sayTo = opts.msg || 'regMsg';
    msg('docMsg', '');
    var go = function () {
      var allowed = fillKinds();
      if (!allowed.length) { say('You do not have permission to issue a document.', 'err'); return; }
      fillClients(); fillMembers();
      if (issuing.client) $('docClient').value = issuing.client.id;
      $('docSerial').value = '';
      $('docDate').value = today();
      $('docTitle').textContent = issuing.client ? 'Issue document for ' + issuing.client.name : 'Issue document';
      seed();
      $('docSheet').hidden = false;
      $('docKind').focus();
    };
    if (state.types.length) go(); else loadPeople(go);
  }
  function shutIssue() { $('docSheet').hidden = true; issuing = null; }

  function ticked(id) { return $(id).checked; }
  function sendIssue() {
    if (!issuing) return;
    var t = typeById($('docKind').value);
    if (!t) { msg('docMsg', 'Choose a document type.', 'err'); return; }
    var hr = t.family === 'hr', quote = t.family === 'quote_cover';
    var serial = $('docSerial').value.trim();
    if (quote && !serial) { msg('docMsg', 'Type the reference from the accounting portal.', 'err'); $('docSerial').focus(); return; }
    var client = issuing.client ? issuing.client.id : $('docClient').value;
    if (!hr && !client) { msg('docMsg', 'Choose a client.', 'err'); $('docClient').focus(); return; }
    if (hr && !$('docMember').value) { msg('docMsg', 'Choose a colleague.', 'err'); $('docMember').focus(); return; }
    var languages = ['en'];
    if (quote) { if (ticked('docLangZh')) languages.push('zh'); if (ticked('docLangMs')) languages.push('ms'); }
    var body = { en: $('docBodyEn').value.trim() };
    if (languages.indexOf('zh') > -1) body.zh = $('docBodyZh').value.trim();
    if (languages.indexOf('ms') > -1) body.ms = $('docBodyMs').value.trim();
    if (!body.en) { msg('docMsg', 'The letter needs a body.', 'err'); $('docBodyEn').focus(); return; }
    var recipient = hr
      ? { name: (memberOf($('docMember').value) || {}).name || '', role: $('docRole').value.trim(),
          staff_code: (memberOf($('docMember').value) || {}).staff_code || '', ic: $('docIc').value.trim() }
      : { name: $('docTo').value.trim(), address: $('docAddr').value.trim(),
          attn: $('docAttn').value.trim(), attn_role: $('docAttnRole').value.trim() };
    if (!hr && !recipient.name) { msg('docMsg', 'Say who the letter is to.', 'err'); $('docTo').focus(); return; }
    var signatory = t.signed ? { name: $('docSigName').value.trim(), designation: $('docSigRole').value.trim() } : null;
    if (t.signed && !signatory.name) { msg('docMsg', 'A signatory is required.', 'err'); $('docSigName').focus(); return; }
    issuing.idem = issuing.idem || (window.ADspaceDocs && window.ADspaceDocs.idemKey());
    var go = $('docGo');
    go.disabled = true; go.textContent = 'Issuing…';
    var done = issuing.onDone;
    LET.issue({
      type: t.id, client: hr ? null : client, member: hr ? $('docMember').value : null,
      serial: serial || null, issued_at: $('docDate').value || null, title: $('docTitleIn').value.trim(),
      salutation: $('docSal').value.trim(), recipient: recipient, body: body, signatory: signatory, languages: languages, idem: issuing.idem
    }, function (r) {
      go.disabled = false; go.textContent = 'Issue';
      if (r.error) { msg('docMsg', r.error, 'err'); return; }
      shutIssue();
      say(r.serial + (r.repeat ? ' was already issued.' : ' issued.') + (r.warn ? ' ' + r.warn : ''), r.warn ? 'warn' : 'ok');
      if (done) done(r); else load();
    });
  }

  // ---- A serial added by hand ------------------------------------------------
  /* The same sheet adds a row and edits a hand-added one: with a row the
     serial is read only, because a wrong serial is deleted and added again
     so the deletions remember it. */
  var editing = null;   // { d, then }
  function openAdd(d, onChange) {
    if (!(may('register', 'work') || mayFamily('client', 'work'))) return;
    if (!(d && d.id)) d = null;
    editing = d ? { d: d, then: onChange } : null;
    if (!d) sayTo = 'regMsg';
    msg('regAddMsg', '');
    var go = function () {
      fillClients();
      var sel = $('regAddClient');
      sel.innerHTML = $('docClient').innerHTML;
      var rc = (d && d.recipient) || {};
      $('regAddTitle').textContent = d ? 'Edit ' + d.serial : 'Add entry';
      $('regAddGo').textContent = d ? 'Save' : 'Add';
      $('regAddSerial').value = d ? d.serial : '';
      $('regAddSerial').readOnly = Boolean(d);
      $('regAddKind').value = d ? (d.kind || '') : '';
      $('regAddWho').value = d ? (rc.name || '') : '';
      $('regAddNote').value = d ? (d.note || '') : '';
      $('regAddUrl').value = d ? (d.file_url || '') : '';
      $('regAddDate').value = d ? String(d.issued_at || '').slice(0, 10) : today();
      $('regAddFam').value = d ? d.family : (may('register', 'work') ? 'other' : 'client');
      sel.value = d ? (d.client_id || '') : '';
      $('regAddSheet').hidden = false;
      (d ? $('regAddKind') : $('regAddSerial')).focus();
    };
    if (state.clients.length) go(); else loadPeople(go);
  }
  function shutAdd() { $('regAddSheet').hidden = true; editing = null; }
  function sendAdd() {
    var serial = $('regAddSerial').value.trim(), kind = $('regAddKind').value.trim();
    if (!serial) { msg('regAddMsg', 'A reference is required.', 'err'); $('regAddSerial').focus(); return; }
    if (!kind) { msg('regAddMsg', 'Say what kind of document it is.', 'err'); $('regAddKind').focus(); return; }
    var go = $('regAddGo');
    go.disabled = true;
    var fields = {
      serial: serial, family: $('regAddFam').value, kind: kind, issued_at: $('regAddDate').value || null,
      recipient: $('regAddWho').value.trim(), client: $('regAddClient').value || null,
      note: $('regAddNote').value.trim(), file_url: $('regAddUrl').value.trim()
    };
    var was = editing;
    var done = function (err, out) {
      go.disabled = false;
      if (err) { msg('regAddMsg', err, 'err'); return; }
      shutAdd();
      say(out.serial + (was ? ' saved.' : ' added.'), 'ok');
      if (was && was.then) was.then(); else load();
    };
    if (was) LET.updateManual(was.d, fields, done); else LET.addManual(fields, done);
  }

  // ---- Void and delete -------------------------------------------------------
  var voiding = null, deleting = null;
  function openVoid(d, onChange) {
    voiding = { d: d, then: onChange };
    $('rvoidWhat').textContent = 'Voiding ' + d.serial + ' marks it as no longer standing. ' +
      'The row and its reference are kept, the verify page answers Void from now on, and the reference is never reused.';
    $('rvoidReason').value = '';
    msg('rvoidMsg', '');
    $('rvoidSheet').hidden = false;
    $('rvoidReason').focus();
  }
  function openDelete(d, onChange) {
    deleting = { d: d, then: onChange };
    $('rdelWhat').textContent = 'Deleting ' + d.serial + ' removes the record. ' +
      (d.source === 'portal' ? 'The file is drawn from the record on Download and is not stored, so nothing is left to recover: ' : '') +
      'this is immediate and cannot be undone. The reference is remembered and never reused.';
    $('rdelConfirm').value = ''; $('rdelReason').value = '';
    msg('rdelMsg', '');
    $('rdelSheet').hidden = false;
    $('rdelConfirm').focus();
  }
  function shutVoid() { voiding = null; $('rvoidSheet').hidden = true; }
  function shutDel() { deleting = null; $('rdelSheet').hidden = true; }
  function after(v) { if (v && v.then) v.then(); else load(); }

  function wire() {
    var on = function (id, fn) { var el = $(id); if (el) el.addEventListener('click', fn); };
    on('regIssue', function () { openIssue({}); });
    on('regAdd', function () { openAdd(null); });
    on('docClose', shutIssue); on('docCancel', shutIssue); on('docGo', sendIssue);
    on('regAddClose', shutAdd); on('regAddCancel', shutAdd); on('regAddGo', sendAdd);
    on('rvoidClose', shutVoid); on('rvoidCancel', shutVoid);
    on('rdelClose', shutDel); on('rdelCancel', shutDel);
    if ($('docKind')) $('docKind').addEventListener('change', seed);
    if ($('docClient')) $('docClient').addEventListener('change', seed);
    if ($('docMember')) $('docMember').addEventListener('change', seed);
    ['docLangZh', 'docLangMs'].forEach(function (id) { if ($(id)) $(id).addEventListener('change', langBodies); });
    on('rvoidGo', function () {
      if (!voiding) return;
      var why = $('rvoidReason').value.trim();
      if (!why) { msg('rvoidMsg', 'A reason is required.', 'err'); $('rvoidReason').focus(); return; }
      var v = voiding, go = $('rvoidGo');
      go.disabled = true;
      LET.setVoid(v.d, why, function (err) {
        go.disabled = false;
        if (err) { msg('rvoidMsg', err, 'err'); return; }
        shutVoid();
        say(v.d.serial + ' voided.', 'ok');
        after(v);
      });
    });
    on('rdelGo', function () {
      if (!deleting) return;
      var typed = $('rdelConfirm').value.trim(), why = $('rdelReason').value.trim();
      if (typed.toUpperCase() !== String(deleting.d.serial).toUpperCase()) {
        msg('rdelMsg', 'Type ' + deleting.d.serial + ' to confirm.', 'err'); $('rdelConfirm').focus(); return;
      }
      if (!why) { msg('rdelMsg', 'A reason is required.', 'err'); $('rdelReason').focus(); return; }
      var v = deleting, go = $('rdelGo');
      go.disabled = true;
      LET.remove(v.d, typed, why, function (err) {
        go.disabled = false;
        if (err) { msg('rdelMsg', err, 'err'); return; }
        shutDel();
        say(v.d.serial + ' deleted.', 'ok');
        after(v);
      });
    });
    ['docSheet', 'regAddSheet', 'rvoidSheet', 'rdelSheet'].forEach(function (id) {
      var el = $(id);
      if (el) el.addEventListener('click', function (e) {
        if (e.target !== this) return;
        if (id === 'docSheet') shutIssue(); else if (id === 'regAddSheet') shutAdd();
        else if (id === 'rvoidSheet') shutVoid(); else shutDel();
      });
    });
    document.addEventListener('keydown', function (e) {
      if (e.key !== 'Escape') return;
      if ($('docSheet') && !$('docSheet').hidden) shutIssue();
      else if ($('regAddSheet') && !$('regAddSheet').hidden) shutAdd();
      else if ($('rvoidSheet') && !$('rvoidSheet').hidden) shutVoid();
      else if ($('rdelSheet') && !$('rdelSheet').hidden) shutDel();
    });
  }
  wire();

  window.ADspaceRegister = { enter: enter, load: load, openIssue: openIssue, paintFor: paintFor };
})();
