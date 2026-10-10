/*
 * Register — every document the portal has issued or been told about, and
 * the sheet that issues one.
 *
 * The list is every reference this portal has issued: the documents table,
 * and the Letters of Offer, which live in a table of their own because a
 * letter of words and a priced snapshot are not one shape. Leaving them out
 * meant the verify page answered a reference the Documents section had never
 * heard of, and the team kept two lists in their heads. Rows are banded by
 * family (quotation covers, Letters of Offer, client letters, HR letters,
 * other), and an HR row reaches this page only where the database's own
 * policy lets it: HR is its own section in the access ladder, so nothing
 * here decides who may read a colleague's letter.
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
  /* The Letter of Offer's own engine: it is redrawn from a priced snapshot,
     which js/letters.js knows nothing about. */
  var DOCS = window.ADspaceDocs;
  var UI  = window.ADspaceState;
  var bridge = window.ADspaceAdmin || {};
  if (!API || !API.configured || !db || !LET || !UI) return;

  function $(id) { return document.getElementById(id); }
  var esc = UI.esc || function (s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  };
  /* A document's kind is its formal name, so it reads in title case however
     it was typed (js/form.js). */
  function nameOf(k) { return window.ADspaceForm && window.ADspaceForm.title ? window.ADspaceForm.title(k) : String(k || ''); }
  /* Clients and colleagues in a picker lead with their code (js/form.js). */
  var F = window.ADspaceForm;
  function msg(id, text, kind) {
    var el = $(id); if (!el) return;
    el.textContent = text || '';
    el.className = 'msg' + (kind && text ? ' ' + kind : '');
  }
  function niceDate(d) {
    if (!d) return '';
    var dt = new Date(String(d).slice(0, 10) + 'T00:00:00');
    if (isNaN(dt.getTime())) return String(d);
    return dt.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }).replace(/\bSep\b/, 'Sept');
  }
  function today() { return new Date().toISOString().slice(0, 10); }
  function may(section, level) { return Boolean(bridge.may && bridge.may(section, level)); }
  /* Client letters answer to the Register's Documents part or to the client
     record's, as the database's register_may() does; HR letters answer to
     the Register's HR part alone. */
  function mayFamily(family, level) {
    if (family === 'hr') return may('register.hr', level);
    if (family === 'other') return may('register.documents', level);
    /* A Letter of Offer is a client's document and answers to the client
       record's part alone, which is the policy on its own table. It is not
       the Register's to issue or to correct: it is issued from the record
       that holds the service lines it prices. */
    if (family === 'offer') return may('clients.documents', level);
    return may('register.documents', level) || may('clients.documents', level);
  }
  /* The part a row's acts name in `data-need`, on the Register. */
  function needOf(family) {
    if (family === 'hr') return 'register.hr';
    if (family === 'offer') return 'clients.documents';
    return 'register.documents';
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
  var state = { docs: null, clients: [], members: [], types: [], me: null, find: '', sort: 'newest', err: null };
  var FAMILIES = ['quote_cover', 'offer', 'client', 'hr', 'other'];
  var BAND = {
    quote_cover: 'Quotation Covers', offer: 'Letters of Offer',
    client: 'Client Letters', hr: 'HR Letters', other: 'Other documents'
  };

  function clientOf(id) { return state.clients.filter(function (c) { return c.id === id; })[0]; }
  function memberOf(id) { return state.members.filter(function (m) { return m.id === id; })[0]; }
  /* A row names the brand the team knows the client by and the entity the
     letter was addressed to, because the two differ (ADspace and ADSPACE
     PLT) and a register read by one alone is a register somebody has to
     open to search (the user, 2026-09-26). An HR letter has no brand: its
     second column is the colleague as the Team directory names them, and
     the recipient is the name the letter was addressed to. */
  function brandOf(d) {
    if (d.family === 'hr') { var m = teamOf(d); return (m && m.name) || ''; }
    var c = clientOf(d.client_id);
    return (c && c.name) || '';
  }
  /* The colleague a letter concerns: the one it was issued to, else the one
     whose Employee ID the reference carries (ADHR/AD014/E2601,
     AD004-P2405001), which is how the letters imported from the old list
     find their person. A candidate's offer (ADHR/EMP…) carries no ID and
     names nobody. */
  function teamOf(d) {
    var m = d.member_id && memberOf(d.member_id);
    if (m) return m;
    var parts = String(d.serial || '').toUpperCase().split(/[\/\-]/);
    return state.members.filter(function (x) {
      return x.staff_code && parts.indexOf(String(x.staff_code).toUpperCase()) > -1;
    })[0] || null;
  }
  function recipientOf(d) {
    var rc = d.recipient || {};
    if (d.family === 'hr') { var m = teamOf(d); return rc.name || (m && m.name) || ''; }
    var c = clientOf(d.client_id);
    return rc.name || (c && (c.legal_name || c.name)) || '';
  }

  function loadPeople(then) {
    Promise.all([
      /* The registered name and the billing address are Billing's columns,
         answered to Documents at Work by `client_billing()`. */
      db.from('clients').select('id, name, client_code, market, stage, created_at').order('name')
        .then(function (r) { return r.error ? r : API.withBilling(r.data || []).then(function () { return r; }); }),
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
    var vl = $('regVerifyLink');
    if (vl) vl.textContent = location.host + '/verify';
    if (bar) bar.hidden = !(mayFamily('client', 'work') || mayFamily('hr', 'work') || mayFamily('quote_cover', 'work'));
    if (add) add.hidden = !(may('register.documents', 'work') || mayFamily('client', 'work'));
    if ($('regTypes')) $('regTypes').hidden = !may('register.types', 'work');
    load();
  }

  function load() {
    var box = $('regList');
    if (!box) return;
    if (!box.querySelector('.crm-table')) UI.skeleton(box, 5);
    state.err = null;
    /* Only ask for what this person may read. A permission not held is not a
       refusal to report: the band simply is not theirs, and asking anyway
       would fail the whole register over a family they cannot see. */
    LET.listAll.offers = mayFamily('offer', 'view');
    loadPeople(function () {
      LET.listAll(function (rows, err) {
        if (err) { state.err = err; UI.failLine(box, 'the register', err.message || String(err), load); return; }
        perfRows(function (pr) {
          state.docs = (rows || []).concat(pr);
          paint();
        });
      });
    });
  }

  /* A monthly performance record, once downloaded, is a document ADspace has
     issued, so it is listed under HR Letters with its reference, colleague
     and month and nothing of its content (the user, 2026-09-26). It is read
     only where both HR Letters and Performance are held, and made and opened
     in Performance, behind its own code. A refused read lists none. */
  function perfRows(then) {
    if (!(may('register.hr', 'view') && may('team.performance', 'view'))) { then([]); return; }
    db.rpc('perf_register').then(function (r) {
      var rows = (!r.error && r.data && r.data.rows) || [];
      then(rows.map(function (x) {
        return { id: 'perf-' + x.id, serial: x.serial, family: 'hr', kind: 'Monthly Performance Record',
                 source: 'perf', member_id: x.member_id, issued_at: x.released_at || x.downloaded_at,
                 recipient: { name: x.name }, period: x.period, created_at: x.downloaded_at };
      }));
    }, function () { then([]); });
  }

  function matches(d) {
    if (!state.find) return true;
    var hay = [d.serial, d.kind, brandOf(d), recipientOf(d), (d.recipient || {}).name, d.issued_by].join(' ').toLowerCase();
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
        state.find = '';
        if ($('regFind')) $('regFind').value = '';
        paint();
      });
      return;
    }
    box.innerHTML = '';
    /* A card per family under its own heading, the way the rate card lists
       Services and Add-ons, and newest at the top of each: the last thing
       issued is the one somebody came back for. The sort is the person's to
       change from the bar. */
    var GRP = window.ADspaceGroup;
    var filtered = rows.length !== all.length;
    FAMILIES.forEach(function (f, i) {
      var mine = rows.filter(function (d) { return d.family === f; }).sort(sorter());
      if (!mine.length) return;
      box.appendChild(GRP.section({
        route: 'register', key: f, name: BAND[f], count: mine.length,
        /* Every family opens: a document just issued lands in its family's
           card, and a card shut by default would hide the row the person
           came back for. A long card draws thirty and offers the rest; the
           fold is remembered for anybody who shuts one. */
        shut: !filtered && GRP.shut('register', f, false),
        table: function () {
          var table = GRP.table('svc-row reg-row', ['Document', f === 'hr' ? 'Team' : 'Brand', 'Recipient', 'Issued', '']);
          GRP.more(table, mine, 30, 'documents', function (d) { return row(d, needOf(f)); });
          return table;
        }
      }));
    });
  }
  /* Newest first is issued date, then when the row was added, so a row with
     no date sits under the dated ones rather than among them. */
  function sorter() {
    var s = state.sort;
    var when = function (d) { return String(d.issued_at || '') + '|' + String(d.created_at || ''); };
    if (s === 'reference') return function (a, b) { return String(a.serial).localeCompare(String(b.serial)); };
    if (s === 'oldest') return function (a, b) { return when(a) < when(b) ? -1 : when(a) > when(b) ? 1 : 0; };
    return function (a, b) { return when(a) > when(b) ? -1 : when(a) < when(b) ? 1 : 0; };
  }

  /* One row shape on the Register and on the client record: the reference
     and what it is, who it went to, when. Valid is the ordinary case, so the
     row says nothing while it holds and names Void beside the reference. */
  function row(d, need, onChange, own) {
    /* `need` is the part the row answers to (`register.documents`,
       `register.hr`, or `clients.documents` on the record); the level is
       the act's own: reissue is work, void and delete are manage. */
    /* A Letter of Offer is read here and lives on the client record: it is a
       priced snapshot, and every act on it (Mark signed, Verify, Void,
       Delete) turns on which service lines it holds, which is a fact the
       register has not loaded and must not guess at. So the row offers what
       it can answer for — the file and the record — and the rest is one press
       away, where the consequence can be counted. */
    var offer = d.family === 'offer';
    var perf = d.source === 'perf';
    var el = document.createElement('div');
    /* `own` is the client record's pane, where every row is that client's,
       so the brand would say the same thing on every line. */
    el.className = 'svc-row reg-row' + (own ? ' is-own' : '') + (d.voided_at || d.superseded_by ? ' is-off' : '');
    /* The kind, and who issued it where the portal did. A row added by hand
       says nothing about how it arrived and names nobody: an import is not a
       person, and the fact is in the ⋯ (Edit is offered on it). */
    var sub = [nameOf(d.kind), d.source === 'portal' ? d.issued_by : ''].filter(Boolean).join(' · ');
    el.innerHTML =
      /* The reference is what somebody came to copy, so the reference is
         the control: one press, and it says Copied the way every other copy
         in this portal does. */
      '<span class="svc-name"><b><button class="serial-copy" type="button" data-a="copy" aria-label="Copy ' + esc(d.serial) + '">' + esc(d.serial) + '</button>' +
        /* The version a reissue replaced says so, because on this list the
           team can see both versions and the word tells them which is which;
           the verify page never says it. */
        (d.voided_at || d.superseded_by
          ? ' <span class="tone">' + esc(d.voided_at ? (d.void_reason === 'Reissued' ? 'Reissued' : 'Void') : 'Superseded') + '</span>'
          : '') + '</b>' +
        '<small>' + esc(sub) + '</small></span>' +
      (own ? '' : '<span class="reg-brand">' + (brandOf(d) ? esc(brandOf(d)) : '<span class="muted">—</span>') + '</span>') +
      '<span class="reg-who">' + esc(recipientOf(d)) + '</span>' +
      '<span class="reg-date">' + esc(niceDate(d.issued_at)) + '</span>' +
      '<span class="team-act">' +
        '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
        '<div class="kmenu" data-menu hidden>' +
          (d.source === 'portal' ? menuItem('download', 'Download') : '') +
          (d.file_url ? menuItem('open', 'Open file') : '') +
          (offer ? menuItem('record', 'Open client record') : '') +
          (perf ? menuItem('review', 'Open review') : '') +
          (offer || perf ? '' :
            (d.source === 'manual' ? menuItem('edit', 'Edit', '', need + ':work') : '') +
            /* A portal document is corrected by reissuing it: the same serial,
               the earlier version kept and voided as Reissued. */
            (d.source === 'portal' && !(d.voided_at && d.void_reason === 'Reissued') ? menuItem('reissue', 'Reissue', '', need + ':work') : '') +
            /* An HR letter is the colleague's to read once shared (My
               performance, Letters); shared later, or taken back. */
            (d.family === 'hr' && d.member_id && !d.voided_at
              ? menuItem('share', d.shared_at ? 'Stop sharing' : 'Share with ' + shareName(d), '', 'register.hr:work') : '') +
            (d.voided_at ? '' : menuItem('void', 'Void', 'is-danger', need + ':manage')) +
            /* Delete, not "Delete permanently": the menu has named what this
               is and the sheet states that there is no restore. */
            menuItem('del', 'Delete', 'is-danger', need + ':manage')) +
        '</div>' +
      '</span>';
    wireMenu(el);
    var on = function (a, fn) { var b = el.querySelector('[data-a="' + a + '"]'); if (b) b.addEventListener('click', function () { shutMenus(); fn(); }); };
    var cp = el.querySelector('[data-a="copy"]');
    if (cp) cp.addEventListener('click', function (e) {
      e.stopPropagation();
      if (window.ADspaceCopy) window.ADspaceCopy.to(this, d.serial);
    });
    on('download', function () {
      /* Two engines, because they are two documents: a Letter of Offer is
         redrawn from its priced snapshot by js/documents.js, every other
         document from its words by js/letters.js. */
      if (offer) { DOCS.download(d.offer, function (warn) { if (warn) say(warn, 'err'); }); return; }
      LET.download(d, function (warn) { if (warn) say(warn, 'err'); });
    });
    on('open', function () { window.open(d.file_url, '_blank', 'noopener'); });
    /* The letter's own acts live on the record that priced it, so the row
       carries the way there rather than a copy of them. The address is
       written first, the way the bell opens a task, because the Clients
       section reads it on entry. */
    on('record', function () {
      var c = clientOf(d.client_id);
      var key = (window.ADspaceCRM && c && window.ADspaceCRM.keyOf(c)) || d.client_id;
      if (!key) return;
      history.replaceState(null, '', '/admin/?client=' + encodeURIComponent(key) + '&tab=documents');
      if (bridge.show) bridge.show('clients');
    });
    /* The record is made, corrected and downloaded in Performance, which
       asks for its own code; the row carries the way there. */
    on('review', function () {
      history.replaceState(null, '', '/admin/?s=team&tab=performance&m=' + String(d.period || '').slice(0, 7));
      if (bridge.show) bridge.show('team');
    });
    on('edit', function () { openAdd(d, onChange); });
    on('reissue', function () { openIssue({ reissue: d, onDone: onChange, msg: sayTo }); });
    on('void', function () { openVoid(d, onChange); });
    on('share', function () {
      var on2 = !d.shared_at;
      db.rpc('document_share', { p_id: d.id, p_on: on2 }).then(function (r) {
        var x = r.data || {};
        if (r.error || x.error) { say('Not changed. The database refused the request.', 'err'); return; }
        say(on2 ? 'Shared with ' + shareName(d) + '.' : 'No longer shared.', 'ok');
        if (onChange) onChange(); else load();
      }).catch(function () { say('Not changed. The database refused the request.', 'err'); });
    });
    on('del', function () { openDelete(d, onChange); });
    return el;
  }
  function shareName(d) { var m = memberOf(d.member_id) || teamOf(d); return m && m.name ? m.name.split(' ')[0] : 'the colleague'; }
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
        table.innerHTML = '<div class="crm-head svc-row reg-row is-own"><span>Document</span><span>Recipient</span><span>Issued</span><span></span></div>';
        rows.forEach(function (d) {
          table.appendChild(row(d, 'clients.documents', function () { paintFor(clientId, box, then); }, true));
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
  if ($('regSort')) $('regSort').addEventListener('change', function () {
    if (this.value === state.sort) return;
    state.sort = this.value; paint();
  });

  // ---- Issuing ----------------------------------------------------------------
  var issuing = null;   // { client, member, families, idem, onDone, reissue }

  function typeById(id) { return state.types.filter(function (t) { return t.id === id; })[0]; }
  /* FIELDS PER TYPE (the user, 2026-10-06: "go on the Document types page
     with fields per type"). A type's fields are the words its wording holds
     in braces ({intern name}, {from}); each is asked for on Issue as its
     type says (text, a date, a paragraph; a name with "date" in it is a date
     until somebody says otherwise) and filled in where it stands. {first
     name}, {role} and {client} fill themselves and are never asked, and on
     an HR letter {name}, the colleague's full name (2026-10-07). */
  var GROUPS = ['quote_cover', 'client', 'hr'];
  var GROUP_WORD = { quote_cover: 'Quotation', client: 'Client letters', hr: 'HR letters' };
  var SELF = { hr: ['first name', 'name', 'role'], client: ['first name', 'client'], quote_cover: ['first name', 'client'] };
  var KINDS = [['text', 'Text'], ['date', 'Date'], ['long', 'Paragraph']];
  function fieldKey(k) { return String(k || '').trim().toLowerCase().replace(/\s+/g, ' '); }
  function fieldWord(k) { return k.charAt(0).toUpperCase() + k.slice(1); }
  function fieldsIn(family, texts) {
    var self = SELF[family] || ['first name'], out = [];
    texts.forEach(function (x) {
      String(x || '').replace(/\{([^{}\n]+)\}/g, function (m, k) {
        k = fieldKey(k);
        if (k && k.length <= 40 && self.indexOf(k) < 0 && out.indexOf(k) < 0) out.push(k);
        return m;
      });
    });
    return out;
  }
  function typeFields(t) { return t ? fieldsIn(t.family, [t.title, t.salutation, t.closing, t.body_en, t.body_zh, t.body_ms]) : []; }
  function kindOf(t, k) { var f = (t && t.fields) || {}; return f[k] || (/\bdate\b/.test(k) ? 'date' : 'text'); }
  /* A date in a letter's prose reads as the agreement does: 16 September 2026. */
  function proseDate(v) {
    var d = new Date(String(v || '').slice(0, 10) + 'T00:00:00');
    return isNaN(d.getTime()) ? String(v || '') : d.toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' });
  }
  function fillKinds() {
    var sel = $('docKind');
    var allowed = state.types.filter(function (t) {
      if (issuing.families && issuing.families.indexOf(t.family) < 0) return false;
      return mayFamily(t.family, 'work');
    });
    /* Grouped as the register is (Quotation, Client letters, HR letters)
       where more than one group is offered. */
    var opt = function (t) { return '<option value="' + esc(t.id) + '">' + esc(t.name) + '</option>'; };
    var fams = GROUPS.filter(function (f) { return allowed.some(function (t) { return t.family === f; }); });
    sel.innerHTML = fams.length > 1 ? fams.map(function (f) {
      return '<optgroup label="' + esc(GROUP_WORD[f]) + '">' + allowed.filter(function (t) { return t.family === f; }).map(opt).join('') + '</optgroup>';
    }).join('') : allowed.map(opt).join('');
    /* A reissue keeps its kind whatever the kind list says now: the type may
       since have been retired, and the document is still what it was. */
    var re = issuing.reissue;
    if (re && mayFamily(re.family, 'work') && !allowed.some(function (t) { return t.id === re.type_id; })) {
      sel.innerHTML += '<option value="' + esc(re.type_id || '') + '">' + esc(re.kind) + '</option>';
      allowed = allowed.concat([{ id: re.type_id, name: re.kind, family: re.family }]);
    }
    return allowed;
  }
  /* Every record in Clients, in the directory's own bands (Leads, Clients,
     Past clients), each in code order A to Z with the ID leading the line,
     so the numbers stand in one column and are found where expected (the
     user, 2026-09-26). */
  function fillClients() {
    var sel = $('docClient');
    var CRM = window.ADspaceCRM || {};
    var order = F.byClient;
    var bands = CRM.bands || [['all', 'Clients']];
    var bandOf = CRM.bandOf || function () { return 'all'; };
    sel.innerHTML = '<option value="">Choose a client</option>' + bands.map(function (b) {
      var mine = state.clients.filter(function (c) { return bandOf(c.stage) === b[0]; }).sort(order);
      if (!mine.length) return '';
      return '<optgroup label="' + esc(b[1]) + '">' + mine.map(function (c) {
        return '<option value="' + esc(c.id) + '">' + esc(F.named(c.client_code, c.name)) + '</option>';
      }).join('') + '</optgroup>';
    }).join('');
  }
  function fillMembers() {
    var sel = $('docMember');
    sel.innerHTML = '<option value="">Choose a colleague</option>' + state.members.filter(function (m) { return m.active !== false && !(window.ADspaceAdmin && window.ADspaceAdmin.isSystem && window.ADspaceAdmin.isSystem(m)); }).sort(F.byStaff).map(function (m) {
      return '<option value="' + esc(m.id) + '">' + esc(F.named(m.staff_code, m.name)) + '</option>';
    }).join('');
  }

  /* A form sheet opens on its card, never on a field: a field taking focus
     raises the iPhone keyboard and zooms the page past what the sheet was
     opened to read (DESIGN.md, 2026-09-20). */
  function cardFocus(id) {
    var card = $(id) && $(id).querySelector('.sheet-card');
    if (!card) return;
    if (!card.hasAttribute('tabindex')) card.setAttribute('tabindex', '-1');
    card.focus({ preventScroll: true });
  }
  function firstName(s) { return String(s || '').trim().split(/\s+/)[0] || ''; }

  /* What the kind decides: which fields draw, what they start with. A person
     may overwrite anything; the type only seeds. Changing the client or the
     colleague afterwards reseeds the recipient and, where the words have not
     been touched since they were seeded, the salutation and the body: a body
     somebody has already edited is never overwritten by a select. */
  var seeded = { title: null, sal: null, body: null, zh: null, ms: null, to: null, addr: null };
  /* The Details section: one field a name the type's wording holds. */
  function paintDocFields(t) {
    var keys = typeFields(t), box = $('docFields');
    if (!box) return;
    $('docFieldsSec').hidden = !keys.length || Boolean(issuing && issuing.reissue);
    box.innerHTML = keys.map(function (k, i) {
      var kind = kindOf(t, k), id = 'docF' + i;
      var ctl = kind === 'long'
        ? '<textarea class="input" id="' + id + '" data-key="' + esc(k) + '" rows="3" aria-required="true"></textarea>'
        : kind === 'date'
          ? '<input class="input" id="' + id + '" data-key="' + esc(k) + '" type="date" aria-required="true">'
          : '<textarea class="input" id="' + id + '" data-key="' + esc(k) + '" rows="1" data-oneline aria-required="true"></textarea>';
      return '<div' + (kind === 'long' ? ' class="span-all"' : '') + '><label class="field-label" for="' + id + '">' + esc(fieldWord(k)) + '</label>' + ctl + '</div>';
    }).join('');
    if (F && F.scan) F.scan(box);
    Array.prototype.forEach.call(box.querySelectorAll('[data-key]'), function (el) {
      el.addEventListener('input', refill);
      el.addEventListener('change', refill);
    });
  }
  function fieldInput(k) {
    return Array.prototype.filter.call(($('docFields') || document).querySelectorAll('[data-key]'), function (el) { return el.getAttribute('data-key') === k; })[0];
  }
  function fieldValues() {
    var out = {};
    Array.prototype.forEach.call(($('docFields') || document).querySelectorAll('[data-key]'), function (el) {
      var v = String(el.value || '').trim();
      if (v) out[el.getAttribute('data-key')] = v;
    });
    return out;
  }
  function addFieldVars(vars, t) {
    var vals = fieldValues();
    Object.keys(vals).forEach(function (k) { vars[k] = kindOf(t, k) === 'date' ? proseDate(vals[k]) : vals[k]; });
    return vars;
  }
  /* What fills itself, as seed() fills it, with the fields typed so far. */
  function selfVars(t) {
    var vars = {};
    if (!t) return vars;
    if (t.family === 'hr') {
      var m = memberOf($('docMember').value);
      if (m) { vars['first name'] = firstName(m.name); vars['name'] = m.name || ''; vars['role'] = $('docRole').value.trim() || m.designation || ''; }
    } else {
      var c = (issuing && issuing.client) || clientOf($('docClient').value);
      if (c) { vars['client'] = c.legal_name || c.name; vars['first name'] = firstName(((issuing && issuing.contact) || {}).name); }
    }
    return addFieldVars(vars, t);
  }
  /* A field typed fills the words still as they were seeded; words somebody
     has typed over are left, and filled on Issue. */
  function refill() {
    var t = typeById($('docKind').value);
    if (!t || !issuing || issuing.reissue) return;
    var vars = selfVars(t);
    [['docTitleIn', 'title', t.title], ['docSal', 'sal', t.salutation], ['docBodyEn', 'body', t.body_en],
     ['docBodyZh', 'zh', t.body_zh], ['docBodyMs', 'ms', t.body_ms]].forEach(function (x) {
      var el = $(x[0]);
      if (!el || el.value !== seeded[x[1]]) return;
      el.value = LET.fill(x[2], vars); seeded[x[1]] = el.value;
    });
  }
  function seed(e) {
    var t = typeById($('docKind').value);
    if (!t) return;
    var reseed = !(e && e.target && e.target.id !== 'docKind');
    if (reseed) paintDocFields(t);
    var keepTitle = !reseed && $('docTitleIn').value !== seeded.title;
    var keepSal = !reseed && $('docSal').value !== seeded.sal;
    var keepBody = !reseed && $('docBodyEn').value !== seeded.body;
    /* The registered name and address follow the client chosen, and are the
       person's to change for a letter to another entity: a new client puts
       them back, a new kind keeps what was typed over them. */
    var moved = !e || (e.target && e.target.id === 'docClient');
    var hr = t.family === 'hr', quote = t.family === 'quote_cover';
    $('docClientWrap').hidden = hr || Boolean(issuing.client);
    $('docMemberWrap').hidden = !hr;
    shareRow(hr, null);
    $('docToRow').hidden = hr;
    $('docAttnRow').hidden = hr;
    $('docHrRow').hidden = !hr;
    $('docLangRow').hidden = !quote;
    $('docSignRow').hidden = false;
    if (reseed) $('docSigned').checked = Boolean(t.signed);
    $('docSerial').placeholder = quote ? 'AQT2601001' : 'Assigned on issue';
    if (reseed) $('docSerial').value = '';
    var c = issuing.client || clientOf($('docClient').value);
    var m = memberOf($('docMember').value);
    var vars = {};
    if (!hr && c) {
      if (moved || !$('docTo').value.trim() || $('docTo').value === seeded.to) {
        $('docTo').value = c.legal_name || c.name || ''; seeded.to = $('docTo').value;
      }
      if (moved || !$('docAddr').value.trim() || $('docAddr').value === seeded.addr) {
        $('docAddr').value = c.billing_address || ''; seeded.addr = $('docAddr').value;
      }
      var main = issuing.contact || {};
      $('docAttn').value = main.name || '';
      $('docAttnRole').value = main.role || '';
      vars['client'] = c.legal_name || c.name;
      vars['first name'] = firstName(main.name);
    }
    if (hr && m) {
      $('docRole').value = m.designation || '';
      vars['first name'] = firstName(m.name);
      vars['name'] = m.name || '';
      vars['role'] = m.designation || '';
    }
    addFieldVars(vars, t);
    if (!keepTitle) { $('docTitleIn').value = LET.fill(t.title, vars); seeded.title = $('docTitleIn').value; }
    if (!keepSal) { $('docSal').value = LET.fill(t.salutation, vars); seeded.sal = $('docSal').value; }
    if (!keepBody) { $('docBodyEn').value = LET.fill(t.body_en, vars); seeded.body = $('docBodyEn').value; }
    if (reseed) {
      $('docBodyZh').value = LET.fill(t.body_zh, vars); seeded.zh = $('docBodyZh').value;
      $('docBodyMs').value = LET.fill(t.body_ms, vars); seeded.ms = $('docBodyMs').value;
      $('docLangEn').checked = true;
      $('docLangZh').checked = quote && Boolean(t.body_zh);
      $('docLangMs').checked = quote && Boolean(t.body_ms);
      langBodies();
    }
    /* Who issues it is named on every letter; the tick only decides whether
       the letter leaves space to sign over the name (the user, 2026-10-01). */
    if (reseed) {
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
    var re = opts.reissue && opts.reissue.id ? opts.reissue : null;
    issuing = { client: opts.client || null, contact: opts.contact || null,
                families: re ? [re.family] : (opts.families || null),
                idem: null, onDone: opts.onDone || null, reissue: re };
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
      $('docGo').textContent = re ? 'Reissue' : 'Issue';
      /* What a reissue fixes is what the document says; what it is, whose
         it is and its reference are not up for change. */
      $('docKind').disabled = Boolean(re); $('docClient').disabled = Boolean(re); $('docMember').disabled = Boolean(re);
      $('docSerial').readOnly = Boolean(re);
      /* A new document starts empty: the last sheet's recipient is not this
         one's. */
      if (!re) ['docTo', 'docAddr', 'docAttn', 'docAttnRole', 'docRole', 'docIc'].forEach(function (id) { if ($(id)) $(id).value = ''; });
      if (re) prefill(re); else seed();
      $('docSheet').hidden = false;
      cardFocus('docSheet');
    };
    if (state.types.length) go(); else loadPeople(go);
  }
  /* The sheet filled from the version being replaced, field for field. */
  function prefill(d) {
    var t = typeById(d.type_id) || { family: d.family, signed: Boolean(d.signed) };
    var hr = d.family === 'hr', quote = d.family === 'quote_cover';
    var rc = d.recipient || {}, body = d.body || {}, langs = d.languages || ['en'], sg = d.signatory || {};
    $('docKind').value = d.type_id || '';
    $('docClient').value = d.client_id || '';
    $('docMember').value = d.member_id || '';
    $('docClientWrap').hidden = hr; $('docMemberWrap').hidden = !hr;
    shareRow(hr, d);
    $('docToRow').hidden = hr; $('docAttnRow').hidden = hr; $('docHrRow').hidden = !hr;
    $('docLangRow').hidden = !quote; $('docSignRow').hidden = false;
    $('docSigned').checked = Boolean(d.signed); $('docSigned').disabled = true;
    $('docSerial').value = d.serial || '';
    $('docDate').value = String(d.issued_at || today()).slice(0, 10);
    $('docTitle').textContent = 'Reissue ' + d.serial;
    $('docTitleIn').value = d.title || '';
    $('docTo').value = rc.name || ''; $('docAddr').value = rc.address || '';
    $('docAttn').value = rc.attn || ''; $('docAttnRole').value = rc.attn_role || '';
    $('docRole').value = rc.role || ''; $('docIc').value = rc.ic || '';
    $('docSal').value = d.salutation || '';
    $('docBodyEn').value = body.en || ''; $('docBodyZh').value = body.zh || ''; $('docBodyMs').value = body.ms || '';
    $('docLangEn').checked = true;
    $('docLangZh').checked = langs.indexOf('zh') > -1; $('docLangMs').checked = langs.indexOf('ms') > -1;
    langBodies();
    $('docSigName').value = sg.name || ''; $('docSigRole').value = sg.designation || '';
    /* A reissue's words already hold what its fields said. */
    $('docFieldsSec').hidden = true; $('docFields').innerHTML = '';
    seeded.title = null; seeded.sal = null; seeded.body = null; seeded.zh = null; seeded.ms = null; seeded.to = null; seeded.addr = null;
  }
  /* An HR letter is shared with the colleague it names by default (the user,
     2026-10-06), the tick turned off for one not yet theirs; a reissue keeps
     the earlier version's choice. The tick names who is told. */
  function shareRow(hr, d) {
    if (!$('docShareRow')) return;
    $('docShareRow').hidden = !hr;
    if (d) $('docShare').checked = Boolean(d.shared_at);
    else if (!issuing || !issuing.shareSet) $('docShare').checked = true;
    var m = memberOf($('docMember').value);
    $('docShareWord').textContent = 'Share with ' + (m && m.name ? m.name.split(' ')[0] : 'the colleague');
  }
  if ($('docShare')) $('docShare').addEventListener('change', function () { if (issuing) issuing.shareSet = true; });
  if ($('docMember')) $('docMember').addEventListener('change', function () {
    if (!$('docShareRow') || $('docShareRow').hidden) return;
    var m = memberOf($('docMember').value);
    $('docShareWord').textContent = 'Share with ' + (m && m.name ? m.name.split(' ')[0] : 'the colleague');
  });
  function shutIssue() {
    $('docSheet').hidden = true; issuing = null;
    $('docKind').disabled = false; $('docClient').disabled = false; $('docMember').disabled = false;
    $('docSerial').readOnly = false; $('docGo').textContent = 'Issue'; $('docSigned').disabled = false;
  }

  function ticked(id) { return $(id).checked; }
  /* The sheet read and checked once, for Issue and for Preview alike:
     null after naming the first thing missing. */
  function gather(forIssue) {
    if (!issuing) return null;
    var re = issuing.reissue;
    var t = typeById($('docKind').value) || (re ? { id: re.type_id, family: re.family, signed: Boolean(re.signed) } : null);
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
    var title = $('docTitleIn').value.trim(), salutation = $('docSal').value.trim();
    if (!re) {
      /* Whatever still stands in braces is filled from the fields, and on
         Issue a field the words still ask for is required. */
      var vars = selfVars(t), keys = typeFields(t);
      title = LET.fill(title, vars); salutation = LET.fill(salutation, vars);
      Object.keys(body).forEach(function (l) { body[l] = LET.fill(body[l], vars); });
      var left = null;
      if (forIssue) {
        [title, salutation, body.en, body.zh || '', body.ms || ''].join('\n').replace(/\{([^{}\n]+)\}/g, function (m, k) {
          k = fieldKey(k);
          if (!left && keys.indexOf(k) > -1) left = k;
          return m;
        });
      }
      if (left) { msg('docMsg', 'Fill in ' + fieldWord(left) + '.', 'err'); var fe = fieldInput(left); if (fe) fe.focus(); return; }
      if (keys.length) body.fields = fieldValues();
    }
    if (!body.en) { msg('docMsg', 'The letter needs a body.', 'err'); $('docBodyEn').focus(); return; }
    var recipient = hr
      ? { name: (memberOf($('docMember').value) || {}).name || '', role: $('docRole').value.trim(),
          staff_code: (memberOf($('docMember').value) || {}).staff_code || '', ic: $('docIc').value.trim() }
      : { name: $('docTo').value.trim(), address: $('docAddr').value.trim(),
          attn: $('docAttn').value.trim(), attn_role: $('docAttnRole').value.trim() };
    if (!hr && !recipient.name) { msg('docMsg', 'Say who the letter is to.', 'err'); $('docTo').focus(); return; }
    var signed = $('docSigned').checked;
    var signatory = $('docSigName').value.trim() ? { name: $('docSigName').value.trim(), designation: $('docSigRole').value.trim() } : null;
    if (signed && !signatory) { msg('docMsg', 'A signatory is required.', 'err'); $('docSigName').focus(); return; }
    return { re: re, t: t, args: {
      type: t.id, client: hr ? null : client, member: hr ? $('docMember').value : null,
      serial: serial || null, issued_at: $('docDate').value || null, title: title,
      salutation: salutation, recipient: recipient, body: body, signatory: signatory, languages: languages,
      signed: signed
    } };
  }
  /* Preview draws the letter from the sheet as it stands, on the same pen
     and letterhead, without issuing it: nothing is written and no number
     is spent, and the reference reads PREVIEW until Issue gives it one
     (the user, 2026-10-01). Every page carries DRAFT (INTERNAL USE ONLY)
     on the diagonal, as a report not yet confirmed does (2026-10-06). It
     opens in a new tab, else downloads. */
  function previewIssue() {
    var g = gather(false);
    if (!g) return;
    msg('docMsg', '');
    var a = g.args, t = g.t;
    var doc = {
      serial: g.re ? g.re.serial : (a.serial || 'PREVIEW'), family: t.family, signed: a.signed, draft: true,
      closing: t.closing != null ? t.closing : (g.re ? g.re.closing : 'Yours sincerely,'),
      issued_at: a.issued_at || today(), title: a.title, salutation: a.salutation,
      recipient: a.recipient, body: a.body, signatory: a.signatory, languages: a.languages
    };
    var btn = $('docPreview'), tab = null;
    try { tab = window.open('', '_blank'); } catch (e) { tab = null; }
    btn.disabled = true;
    LET.render(doc).then(function (bytes) {
      btn.disabled = false;
      window.ADspaceDocs.save(new Blob([bytes], { type: 'application/pdf' }), 'Preview ' + LET.fileName(doc), tab);
    }).catch(function (e) {
      btn.disabled = false;
      if (tab && !tab.closed) tab.close();
      msg('docMsg', 'The preview could not be drawn: ' + ((e && e.message) || e), 'err');
    });
  }
  function sendIssue() {
    var g = gather(true);
    if (!g) return;
    var re = g.re, args = g.args;
    issuing.idem = issuing.idem || (window.ADspaceDocs && window.ADspaceDocs.idemKey());
    args.idem = issuing.idem;
    var go = $('docGo');
    go.disabled = true; go.textContent = re ? 'Reissuing…' : 'Issuing…';
    var done = issuing.onDone;
    var share = args.member && !$('docShareRow').hidden && $('docShare').checked;
    var shareTo = share ? ((memberOf(args.member) || {}).name || 'the colleague') : '';
    var back = function (r) {
      go.disabled = false; go.textContent = re ? 'Reissue' : 'Issue';
      if (r.error) { msg('docMsg', r.error, 'err'); return; }
      shutIssue();
      var line = r.serial + (re ? ' reissued.' : r.repeat ? ' was already issued.' : ' issued.') + (r.warn ? ' ' + r.warn : '');
      var finish = function (extra, tone) {
        say(line + (extra ? ' ' + extra : ''), tone || (r.warn ? 'warn' : 'ok'));
        if (done) done(r); else load();
      };
      if (!share || !r.id) { finish(); return; }
      db.rpc('document_share', { p_id: r.id, p_on: true }).then(function (s2) {
        var d2 = s2.data || {};
        if (s2.error || d2.error) finish('Not shared: the database refused the request.', 'warn');
        else finish('Shared with ' + shareTo + '.');
      }).catch(function () { finish('Not shared: the database refused the request.', 'warn'); });
    };
    if (re) LET.reissue(re, args, back); else LET.issue(args, back);
  }

  // ---- Document types ----------------------------------------------------------
  /* The kinds of letter Issue offers, added and edited by the team (the user,
     2026-10-06: "go on the Document types page with fields per type"), as My
     Work's templates are: a list in a sheet, and one type in a sheet of its
     own. Documents: Document types, a granted part (an admin's by itself).
     A type is never removed, only no longer offered, because every document
     issued names its type. */
  var PEN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>';
  var dt = { all: [], editing: null, kinds: {} };
  var DT_SAID = {
    'denied':       'You do not have permission to do this.',
    'bad-name':     'A name is 2 to 80 characters.',
    'taken':        'Another document type has that name.',
    'bad-family':   'Choose a group.',
    'family-fixed': 'The group stays as the type was made.',
    'bad-code':     'An HR letter takes a reference code of 1 to 4 capital letters or digits, as IC.',
    'code-taken':   'Another HR letter uses that reference code.',
    'bad-fields':   'A field name is up to 40 characters.',
    'too-long':     'The wording is too long.',
    'not-found':    'That document type is no longer there.'
  };
  function dtSaid(r) {
    var m = r && r.error && (r.error.message || '');
    if (m && /could not find|does not exist|schema cache/i.test(m)) return 'This needs a database update.';
    var k = (r && r.data && r.data.error) || m;
    return DT_SAID[k] || k || 'The request failed.';
  }
  /* Every type, offered or not; Issue keeps the offered ones. */
  function readTypes(then) {
    db.from('doc_types').select('*').order('position').order('name').then(function (r) {
      if (r.error) { then(r.error); return; }
      dt.all = r.data || [];
      state.types = dt.all.filter(function (t) { return t.active !== false; });
      then(null);
    }).catch(function (e) { then(e || new Error('read')); });
  }
  /* The whole reference a type's code makes, never the code alone (the
     user, 2026-10-08: "give the full syntax not shortcuts"). */
  function hrRef(code) { return 'ADHR/{Employee ID}/' + code + '{YYMM}'; }
  function showRef() {
    var out = $('dtCodeRef'), v = ($('dtCode').value || '').trim().toUpperCase();
    if (out) out.textContent = 'Reference: ' + hrRef(v || '{code}');
  }
  function typeMeta(t) {
    var n = typeFields(t).length;
    return [t.family === 'hr' && t.code ? hrRef(t.code) : '', t.signed === false ? 'Not signed' : 'To be signed',
      n ? n + (n === 1 ? ' field' : ' fields') : ''].filter(Boolean).join(' · ');
  }
  function paintTypes() {
    var box = $('dtList');
    if (!box) return;
    var html = GROUPS.map(function (f) {
      var rows = dt.all.filter(function (t) { return t.family === f; });
      if (!rows.length) return '';
      return '<section class="fsec"><h4 class="fsec-h">' + esc(GROUP_WORD[f]) + '</h4>' + rows.map(function (t) {
        var off = t.active === false;
        return '<div class="dtrow' + (off ? ' is-off' : '') + '">' +
          '<span class="dtrow-name"><span class="dtrow-title"><b>' + esc(t.name) + '</b>' + (off ? '<span class="tone is-off">Inactive</span>' : '') + '</span>' +
          '<small>' + esc(typeMeta(t)) + '</small></span>' +
          '<button class="btn btn-quiet btn-sm" data-edit="' + esc(t.id) + '" type="button">' + PEN + 'Edit</button></div>';
      }).join('') + '</section>';
    }).join('');
    if (html) box.innerHTML = html; else UI.emptyLine(box, 'No document types.');
    Array.prototype.forEach.call(box.querySelectorAll('[data-edit]'), function (b) {
      b.addEventListener('click', function () {
        openTypeEdit(dt.all.filter(function (t) { return t.id === b.getAttribute('data-edit'); })[0] || null, b);
      });
    });
  }
  function openTypes(opener, said) {
    if (!may('register.types', 'work')) return;
    var box = $('dtList');
    msg('dtMsg', said || '', said ? 'ok' : '');
    UI.skeleton(box, 4);
    window.ADspaceSheet.show($('dtSheet'), { opener: opener || $('regTypes') });
    readTypes(function (err) {
      if (err) { UI.failLine(box, 'Document types', (err && err.message) || '', function () { openTypes(opener); }); return; }
      paintTypes();
    });
  }
  /* The wording as it stands in the sheet, every language. */
  function dtTexts() {
    return ['dtTitle', 'dtSal', 'dtClosing', 'dtBodyEn', 'dtBodyZh', 'dtBodyMs'].map(function (id) { return $(id).value; });
  }
  function dtFamily() { return dt.editing ? dt.editing.family : $('dtFamily').value; }
  /* The Fields section follows the wording: a line a field, its kind a
     segment, a choice kept while the sheet is open. */
  function paintTypeFields() {
    var fam = dtFamily(), keys = fieldsIn(fam, dtTexts()), box = $('dtFields');
    $('dtFieldsSec').hidden = !keys.length;
    box.innerHTML = keys.map(function (k, i) {
      var kind = dt.kinds[k] || kindOf(dt.editing, k);
      return '<div class="dtfield"><span class="dtfield-name" id="dtFieldName' + i + '">' + esc(fieldWord(k)) +
        '<code class="dtfield-key">{' + esc(k) + '}</code></span>' +
        '<select class="select select-sm" data-seg data-key="' + esc(k) + '" aria-labelledby="dtFieldName' + i + '">' +
        KINDS.map(function (o) { return '<option value="' + o[0] + '"' + (o[0] === kind ? ' selected' : '') + '>' + o[1] + '</option>'; }).join('') +
        '</select></div>';
    }).join('');
    if (F && F.scan) F.scan(box);
    Array.prototype.forEach.call(box.querySelectorAll('select[data-key]'), function (sel) {
      sel.addEventListener('change', function () { dt.kinds[sel.getAttribute('data-key')] = sel.value; });
    });
  }
  var dtFieldsLater = null;
  function dtWordingTyped() {
    clearTimeout(dtFieldsLater);
    dtFieldsLater = setTimeout(paintTypeFields, 250);
  }
  /* A new type's salutation and closing start as its group writes them, and
     follow the group while nobody has typed over them. */
  var DT_OPEN = { hr: ['Dear {first name},', 'Warm regards,'], client: ['Dear Sir/Madam,', 'Yours sincerely,'], quote_cover: ['Dear Sir/Madam,', 'Yours sincerely,'] };
  function dtGroupShown() {
    var fam = dtFamily();
    $('dtCodeWrap').hidden = fam !== 'hr';
    /* Chinese and Malay are a quotation's, or a type that already holds them. */
    $('dtBodyZhWrap').hidden = fam !== 'quote_cover' && !$('dtBodyZh').value.trim();
    $('dtBodyMsWrap').hidden = fam !== 'quote_cover' && !$('dtBodyMs').value.trim();
  }
  function dtGroupMoved() {
    if (dt.editing) return;
    var fam = $('dtFamily').value;
    var was = Object.keys(DT_OPEN).map(function (k) { return DT_OPEN[k]; });
    if (was.some(function (w) { return w[0] === $('dtSal').value; }) || !$('dtSal').value.trim()) $('dtSal').value = DT_OPEN[fam][0];
    if (was.some(function (w) { return w[1] === $('dtClosing').value; }) || !$('dtClosing').value.trim()) $('dtClosing').value = DT_OPEN[fam][1];
    dtGroupShown();
    paintTypeFields();
  }
  /* The instruction beside Body opens by itself three times, then waits
     behind its mark (DESIGN.md: an instruction). */
  function dtHint(open) {
    var seen = 0;
    try { seen = Number(localStorage.getItem('adspace-hint-doctype-fields') || 0); } catch (e) { seen = 3; }
    var show = open == null ? seen < 3 : open;
    $('dtHintText').hidden = !show;
    $('dtHintBtn').setAttribute('aria-expanded', String(show));
    if (open == null && show) { try { localStorage.setItem('adspace-hint-doctype-fields', String(seen + 1)); } catch (e) {} }
  }
  function openTypeEdit(t, opener) {
    if (!may('register.types', 'work')) return;
    dt.editing = t || null;
    dt.kinds = {};
    var fam = t ? t.family : 'client';
    $('dtEditHead').textContent = t ? t.name : 'New document type';
    $('dtFamily').value = fam;
    $('dtFamily').disabled = Boolean(t);
    $('dtName').value = t ? t.name : '';
    $('dtCode').value = t ? (t.code || '') : '';
    showRef();
    $('dtSigned').checked = t ? t.signed !== false : true;
    $('dtActive').checked = t ? t.active !== false : true;
    $('dtTitle').value = t ? (t.title || '') : '';
    $('dtSal').value = t ? (t.salutation || '') : DT_OPEN[fam][0];
    $('dtClosing').value = t ? (t.closing || '') : DT_OPEN[fam][1];
    $('dtBodyEn').value = t ? (t.body_en || '') : '';
    $('dtBodyZh').value = t ? (t.body_zh || '') : '';
    $('dtBodyMs').value = t ? (t.body_ms || '') : '';
    $('dtSave').disabled = false; $('dtSave').textContent = 'Save';
    msg('dtEditMsg', '');
    dtGroupShown();
    paintTypeFields();
    dtHint();
    window.ADspaceSheet.show($('dtEditSheet'), { opener: opener || null });
  }
  function shutTypeEdit(said) {
    dt.editing = null;
    openTypes($('regTypes'), said);
  }
  function saveType() {
    var t = dt.editing, fam = dtFamily(), btn = $('dtSave');
    var name = $('dtName').value.trim().replace(/\s+/g, ' ');
    if (name.length < 2) { msg('dtEditMsg', 'A name is required.', 'err'); $('dtName').focus(); return; }
    var code = $('dtCode').value.trim().toUpperCase();
    if (fam === 'hr' && !/^[A-Z0-9]{1,4}$/.test(code)) { msg('dtEditMsg', DT_SAID['bad-code'], 'err'); $('dtCode').focus(); return; }
    var fields = {};
    fieldsIn(fam, dtTexts()).forEach(function (k) { fields[k] = dt.kinds[k] || kindOf(t, k); });
    var wantOn = $('dtActive').checked, wasOn = t ? t.active !== false : true;
    btn.disabled = true; btn.textContent = 'Saving…';
    var fail = function (r) { btn.disabled = false; btn.textContent = 'Save'; msg('dtEditMsg', dtSaid(r), 'err'); };
    db.rpc('doc_type_save', {
      p_id: t ? t.id : null, p_family: t ? null : fam, p_name: name, p_code: fam === 'hr' ? code : null,
      p_title: $('dtTitle').value.trim(), p_salutation: $('dtSal').value.trim(), p_closing: $('dtClosing').value.trim(),
      p_body_en: $('dtBodyEn').value.trim(), p_body_zh: $('dtBodyZh').value.trim(), p_body_ms: $('dtBodyMs').value.trim(),
      p_signed: $('dtSigned').checked, p_fields: fields
    }).then(function (r) {
      var d = r.data || {};
      if (r.error || d.error) { fail(r); return; }
      var moved = wantOn !== wasOn;
      var next = moved ? db.rpc('doc_type_set_active', { p_id: d.id, p_on: wantOn }) : Promise.resolve({ data: { ok: true } });
      return next.then(function (r2) {
        if (r2.error || (r2.data && r2.data.error)) { fail(r2); return; }
        btn.disabled = false; btn.textContent = 'Save';
        shutTypeEdit(d.unchanged && !moved ? 'No changes.' : 'Saved.');
      });
    }).catch(function (e) { fail({ error: e }); });
  }

  // ---- A serial added by hand ------------------------------------------------
  /* The same sheet adds a row and edits a hand-added one: with a row the
     serial is read only, because a wrong serial is deleted and added again
     so the deletions remember it. */
  var editing = null;   // { d, then }
  /* The recipient a client pick last wrote, so a name somebody typed over
     it is never replaced by the next pick. */
  var addSeed = null;
  function openAdd(d, onChange) {
    if (!(may('register.documents', 'work') || mayFamily('client', 'work'))) return;
    if (!(d && d.id)) d = null;
    editing = d ? { d: d, then: onChange } : null;
    if (!d) sayTo = 'regMsg';
    msg('regAddMsg', '');
    var go = function () {
      fillClients(); fillMembers();
      var sel = $('regAddClient');
      sel.innerHTML = $('docClient').innerHTML;
      /* The colleague an HR row concerns, read the way the register's Team
         column reads it, kept on the list even once they have left. */
      var ms = $('regAddMember'), tm = d && d.family === 'hr' ? teamOf(d) : null;
      ms.innerHTML = $('docMember').innerHTML;
      if (tm && !ms.querySelector('option[value="' + tm.id + '"]')) {
        ms.add(new Option(F.named(tm.staff_code, tm.name), tm.id));
      }
      ms.value = tm ? tm.id : '';
      var rc = (d && d.recipient) || {};
      $('regAddTitle').textContent = d ? 'Edit ' + d.serial : 'Add entry';
      $('regAddGo').textContent = d ? 'Save' : 'Add';
      $('regAddSerial').value = d ? d.serial : '';
      $('regAddSerial').readOnly = Boolean(d);
      $('regAddWho').value = d ? (rc.name || '') : '';
      $('regAddNote').value = d ? (d.note || '') : '';
      $('regAddUrl').value = d ? (d.file_url || '') : '';
      $('regAddDate').value = d ? String(d.issued_at || '').slice(0, 10) : today();
      $('regAddFam').value = d ? d.family : (may('register.documents', 'work') ? 'other' : 'client');
      sel.value = d ? (d.client_id || '') : '';
      var was = d && clientOf(d.client_id);
      addSeed = was && rc.name === (was.legal_name || was.name) ? rc.name
        : (tm && rc.name === tm.name ? rc.name : null);
      fillKindPick(d ? d.kind : '');
      regAddFit();
      $('regAddSheet').hidden = false;
      cardFocus('regAddSheet');
    };
    if (state.clients.length) go(); else loadPeople(go);
  }
  /* The document types a kind already carries: the seeded types and every
     name its documents were saved under, title-cased and said once, so a
     type is chosen and only a new one is typed (the user, 2026-09-26). */
  function kindsFor(fam) {
    var seen = {}, out = [];
    var add = function (k) {
      k = nameOf(String(k || '').trim());
      if (!k || seen[k.toLowerCase()]) return;
      seen[k.toLowerCase()] = true; out.push(k);
    };
    state.types.forEach(function (t) { if (t.family === fam) add(t.name); });
    (state.docs || []).forEach(function (x) { if (x.family === fam) add(x.kind); });
    return out.sort(function (a, b) { return a.localeCompare(b); });
  }
  function kindNow() {
    var v = $('regAddKindPick').value;
    return v === '__new' ? $('regAddKind').value.trim() : v;
  }
  function fillKindPick(keep) {
    var sel = $('regAddKindPick'), list = kindsFor($('regAddFam').value);
    sel.innerHTML = '<option value="">Choose a type</option>' + list.map(function (k) {
      return '<option value="' + esc(k) + '">' + esc(k) + '</option>';
    }).join('') + '<option value="__new">Other (new type)</option>';
    keep = String(keep || '').trim();
    var hit = keep && list.filter(function (k) { return k.toLowerCase() === keep.toLowerCase(); })[0];
    if (hit) { sel.value = hit; $('regAddKind').value = ''; }
    else if (keep) { sel.value = '__new'; $('regAddKind').value = keep; }
    else { sel.value = ''; $('regAddKind').value = ''; }
    $('regAddKindNewRow').hidden = sel.value !== '__new';
  }
  /* An HR letter is addressed to a colleague, never to a client (the user,
     2026-09-26): the kind decides which picker the sheet draws. */
  function regAddFit() {
    var hr = $('regAddFam').value === 'hr';
    $('regAddClientWrap').hidden = hr;
    $('regAddMemberWrap').hidden = !hr;
    $('regAddWho').placeholder = hr ? 'John Doe' : 'COMPANY NAME SDN BHD';
  }
  function shutAdd() { $('regAddSheet').hidden = true; editing = null; }
  function sendAdd() {
    var serial = $('regAddSerial').value.trim(), typed = $('regAddKindPick').value === '__new';
    var kind = nameOf(kindNow());
    if (typed) $('regAddKind').value = kind;
    if (!serial) { msg('regAddMsg', 'A reference is required.', 'err'); $('regAddSerial').focus(); return; }
    if (!kind) {
      msg('regAddMsg', typed ? 'Type the new document type.' : 'Choose a document type.', 'err');
      $(typed ? 'regAddKind' : 'regAddKindPick').focus(); return;
    }
    var go = $('regAddGo');
    go.disabled = true;
    var hr = $('regAddFam').value === 'hr';
    var fields = {
      serial: serial, family: $('regAddFam').value, kind: kind, issued_at: $('regAddDate').value || null,
      recipient: $('regAddWho').value.trim(),
      client: hr ? null : ($('regAddClient').value || null),
      member: hr ? ($('regAddMember').value || null) : null,
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
    on('docClose', shutIssue); on('docCancel', shutIssue); on('docGo', sendIssue); on('docPreview', previewIssue);
    on('regAddClose', shutAdd); on('regAddCancel', shutAdd); on('regAddGo', sendAdd);
    on('rvoidClose', shutVoid); on('rvoidCancel', shutVoid);
    on('rdelClose', shutDel); on('rdelCancel', shutDel);
    if ($('docKind')) $('docKind').addEventListener('change', seed);
    if ($('docClient')) $('docClient').addEventListener('change', seed);
    if ($('docMember')) $('docMember').addEventListener('change', seed);
    if ($('regAddKind')) $('regAddKind').addEventListener('change', function () { this.value = nameOf(this.value); });
    if ($('regAddClient')) $('regAddClient').addEventListener('change', function () {
      var c = clientOf(this.value), who = $('regAddWho');
      if (!c) return;
      if (!who.value.trim() || who.value === addSeed) { who.value = c.legal_name || c.name || ''; addSeed = who.value; }
    });
    /* A colleague's name fills the recipient the way a client's does, and
       never replaces a name somebody typed. */
    if ($('regAddMember')) $('regAddMember').addEventListener('change', function () {
      var m = memberOf(this.value), who = $('regAddWho');
      if (!m) return;
      if (!who.value.trim() || who.value === addSeed) { who.value = m.name || ''; addSeed = who.value; }
    });
    if ($('regAddFam')) $('regAddFam').addEventListener('change', function () {
      fillKindPick(kindNow());
      regAddFit();
    });
    if ($('regAddKindPick')) $('regAddKindPick').addEventListener('change', function () {
      var n = this.value === '__new';
      $('regAddKindNewRow').hidden = !n;
      if (n) $('regAddKind').focus();
    });
    ['docLangZh', 'docLangMs'].forEach(function (id) { if ($(id)) $(id).addEventListener('change', langBodies); });
    /* Document types: the list, one type, the way back to the list. */
    on('regTypes', function () { openTypes(this); });
    on('dtNew', function () { openTypeEdit(null, this); });
    on('dtCancel', function () { window.ADspaceSheet.close(); });
    on('dtClose', function () { $('dtCancel').click(); });
    on('dtEditCancel', function () { shutTypeEdit(''); });
    on('dtEditClose', function () { $('dtEditCancel').click(); });
    on('dtSave', saveType);
    if ($('dtCode')) $('dtCode').addEventListener('input', showRef);
    on('dtHintBtn', function () { dtHint($('dtHintText').hidden); });
    if ($('dtFamily')) $('dtFamily').addEventListener('change', dtGroupMoved);
    ['dtTitle', 'dtSal', 'dtClosing', 'dtBodyEn', 'dtBodyZh', 'dtBodyMs'].forEach(function (id) {
      if ($(id)) $(id).addEventListener('input', dtWordingTyped);
    });
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
    /* A click outside the card closes a sheet only while nothing has been
       typed, ticked or picked in it, as js/sheet.js holds for every other
       sheet: a stray click never costs somebody their letter (the user,
       2026-10-01). The close mark, Cancel and Escape still close it. */
    ['docSheet', 'regAddSheet', 'rvoidSheet', 'rdelSheet'].forEach(function (id) {
      var el = $(id);
      if (!el) return;
      var touch = function (e) { if (e.isTrusted) el.__touched = true; };
      el.addEventListener('input', touch);
      el.addEventListener('change', touch);
      new MutationObserver(function () { if (el.hidden) el.__touched = false; }).observe(el, { attributes: true, attributeFilter: ['hidden'] });
      el.addEventListener('click', function (e) {
        if (e.target !== this) return;
        if (el.__touched) return;
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

  window.ADspaceRegister = { enter: enter, load: load, openIssue: openIssue, paintFor: paintFor, openTypes: function (opener) { openTypes(opener); } };
})();
