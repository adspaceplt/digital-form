/*
 * Clients — the CRM.
 *
 * The company list is the root of everything else in the portal. A lead is
 * entered here by anyone, the sales team works it through calls and visits,
 * and it becomes an active client only once every detail an e-invoice needs
 * is on file. Only an active client can be given content to review or a
 * creator campaign to choose from. Content Review and Creator Campaigns pick
 * from this list; neither creates a company.
 */
(function () {
  var API = window.ADspaceAPI;
  var db  = API && API.client;
  if (!API || !API.configured || !db) return;

  var $ = function (id) { return document.getElementById(id); };
  /* Clients and colleagues in a picker lead with their code (js/form.js). */
  var F = window.ADspaceForm;

  /* Every form on this route is the portal's one form sheet, so it opens and
     shuts through the one file that knows how (`js/sheet.js`): the scrim that
     refuses to throw typed work away, Escape, the focus trap, and focus handed
     back to the control that opened it. They were `.panel` blocks that
     unfolded at the top of the section or in place of the record's head, so on
     a phone pressing Edit put the form a screen away from the row and read as
     nothing having happened. Nothing inside is focused: a field taking focus
     on a phone raises the keyboard and zooms the page past the rest of the
     form, and the first field is rarely the one somebody came to change. */
  function openSheet(id, opener, onClose) {
    window.ADspaceSheet.show($(id), { opener: opener || null, onClose: onClose || null });
  }
  function shutSheet(id) {
    var box = $(id);
    if (window.ADspaceSheet.isOpen(box)) window.ADspaceSheet.close();
    else box.hidden = true;
  }
  /* The close mark in a sheet's head does what Cancel does, so it presses it
     rather than keeping a second copy of whatever Cancel has to put back. */
  function sheetClose(closeId, cancelId) {
    var x = $(closeId);
    if (x) x.addEventListener('click', function () { $(cancelId).click(); });
  }
  var bridge = window.ADspaceAdmin || {};
  var log = bridge.log || function () {};
  /* What a save changed, field by field (js/records.js). */
  function changed(before, after, fields, o) {
    return window.ADspaceRecords ? window.ADspaceRecords.changes(before, after, fields, o) : '';
  }
  var actor = bridge.actor || function () { return ''; };
  var actorName = bridge.actorName || actor;
  /* A logged address read as a person, through the console's one map. */
  var whoName = bridge.whoName || function (e) { return e || ''; };
  var setUrl = bridge.setUrl || function () {};
  /* A pane is a move somebody made, not a note of where the page ended up, so
     it pushes a history entry and Back and Forward walk the record. */
  var pushUrl = bridge.pushUrl || setUrl;
  var restoreScroll = bridge.restoreScroll || function () {};
  var MON = window.ADspaceMoney;

  function maySeeActivity() {
    return Boolean(bridge.may && bridge.may('activity', 'view'));
  }
  /* A part of the section: the pane's own level where the group set one, the
     section's where it did not. Billing was a switch beside the ladder until
     2026-09-22 and is `clients.billing` now. */
  function mayPart(part, level) {
    return Boolean(bridge.may && bridge.may(part, level || 'work'));
  }
  function maySeeBilling() { return mayPart('clients.billing', 'view'); }
  /* CLIENT SCOPE (2026-10-03): a lead answers to `clients.leads` and a past
     client to `clients.past` as well as to Clients, each part falling back to
     the section where it is unset, as the database's `client_row_seen` reads
     them. A stage a person may not work is offered greyed, and a record in
     one is read and not moved. */
  function bandKey(stage) {
    return ['lead', 'contacted', 'proposal'].indexOf(stage || 'lead') > -1 ? 'clients.leads'
      : stage === 'past' ? 'clients.past' : 'clients';
  }
  function bandMay(stage, level) {
    var k = bandKey(stage);
    return mayPart('clients', level) && (k === 'clients' || mayPart(k, level));
  }
  /* The tabs that carry `data-part` draw only where that part is readable. */
  function gateTabs() {
    Array.prototype.forEach.call(document.querySelectorAll('#crmTabs [data-part]'), function (b) {
      b.hidden = !mayPart(b.getAttribute('data-part'), 'view');
    });
    /* A tab of several parts (Services with Documents, Account) is drawn
       where any one is readable. */
    Array.prototype.forEach.call(document.querySelectorAll('#crmTabs [data-parts]'), function (b) {
      b.hidden = !b.getAttribute('data-parts').split(' ').some(function (k) { return mayPart(k, k === 'reports.whitelabel' ? 'work' : 'view'); });
    });
    /* Issue document is a client letter, which either part issues as the
       database's `register_may('client', …)` allows it (2026-10-22). */
    var issue = $('crmIssueDoc');
    if (issue) issue.hidden = !(mayPart('clients.documents', 'work') || mayPart('register.documents', 'work'));
  }

  function esc(s) { return window.ADspaceWords.esc(s); }
  function msg(id, text, kind) {
    var el = $(id);
    if (!el) return;
    el.textContent = text || '';
    el.className = 'msg' + (kind ? ' ' + kind : '');
  }
  /* One maker of link keys, in js/api.js (never Math.random: the key is the
     only thing between the link and the client's content). */
  function token() { return window.ADspaceAPI.accessToken(); }
  function val(id) { return ($(id).value || '').trim(); }

  /* A client's address. The record used to travel in the URL as a UUID, which
     nobody reads or recognises; the slug is the name, lowercased and hyphened.
     It is set once from the name and never follows a rename, because an
     address that moves under the people holding it is worse than one that
     reads a little out of date. */
  function slugify(s) {
    return String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '').slice(0, 60).replace(/-+$/, '');
  }
  // Every row of a read, a thousand at a time (`ADspaceAPI.readPages`).
  function readPages(make) { return window.ADspaceAPI.readPages(make, 50000); }
  // A clash takes a number rather than failing; the database index is the
  // final word, so a race loses the insert and not the slug.
  function uniqueSlug(name, then) {
    var want = slugify(name) || 'client';
    readPages(function () { return db.from('clients').select('slug').ilike('slug', want + '%').order('id'); }).then(function (r) {
      var used = {};
      (r.data || []).forEach(function (x) { if (x.slug) used[String(x.slug).toLowerCase()] = true; });
      if (!used[want]) { then(want); return; }
      for (var i = 2; i < 300; i++) { if (!used[want + '-' + i]) { then(want + '-' + i); return; } }
      then(want + '-' + Date.now().toString(36));
    }, function () { then(want); });
  }
  /* The next number after a slug the index refused: `client` → `client-2`. */
  function nextSlug(slug, tries) {
    var m = /^(.*)-(\d+)$/.exec(slug), base = m ? m[1] : slug, n = m ? Number(m[2]) + 1 : 2;
    return tries > 8 ? base + '-' + Date.now().toString(36) : base + '-' + n;
  }
  var UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  /* What the address carries: a slug now, a UUID in anything shared before
     this. Asked of the right column either way, because Postgres refuses a
     non-UUID against a uuid column. */
  function clientByKey(key, then) {
    if (!key) { then(null); return; }
    db.from('clients').select(API.CLIENT_COLS).eq(UUID.test(key) ? 'id' : 'slug', key).single()
      .then(function (r) {
        if (r.error || !r.data) { then(null); return; }
        API.withBilling(r.data).then(function () { then(r.data); });
      }, function () { then(null); });
  }
  // The address of a client, wherever one is built.
  function keyOf(c) { return (c && (c.slug || c.id)) || ''; }
  /* Who logged a call or visit, by name. Entries logged before 2026-10-15
     hold the sign-in email; it is read as the colleague's name, and an
     address no active colleague holds is left unsaid. */
  function whoLogged(v) {
    v = String(v || '');
    if (v.indexOf('@') < 0) return v;
    var m = (state.team || []).filter(function (t) { return String(t.email || '').toLowerCase() === v.toLowerCase(); })[0];
    return m ? m.name : '';
  }

  function niceDate(d) {
    if (!d) return '';
    /* Days are Malaysia's (js/clock.js), whatever the device's clock: a day
       stays itself, a moment reads as its day here. */
    return ADspaceClock.date(String(d).length > 10 ? d : String(d).slice(0, 10)) || String(d);
  }
  function today() { return ADspaceClock.today(); }

  /* Stage is the one word that tells the team how to treat someone. The list
     is grouped by it: leads being worked at the top, the clients we are
     serving below, and the ones that have ended at the bottom. */
  /* The word and the colour come from js/words.js, so a stage cannot read one
     way here and another on the client's page. What stays here is the only
     part the client page has no use for: which group of the list it falls in. */
  var W = window.ADspaceWords;
  var STAGES = [['lead', 'leads'], ['contacted', 'leads'], ['proposal', 'leads'],
                ['active', 'clients'], ['paused', 'paused'], ['past', 'past']]
    .map(function (g) { return [g[0], W.en.stage[g[0]], W.tone(g[0]), g[1]]; });
  /* Why a client was paused or ended (the user, 2026-10-04: required, so
     the Sales view says why clients leave as well as how many). Stored
     keys; the words are these. */
  var LEAVE = [['budget', 'Budget'], ['results', 'Results'], ['in_house', 'Moved in-house'],
               ['closed', 'Business closed'], ['no_reply', 'No reply'], ['other', 'Other']];
  function leaveWord(k) {
    for (var i = 0; i < LEAVE.length; i++) if (LEAVE[i][0] === k) return LEAVE[i][1];
    return '';
  }
  /* Three bands, in the order somebody works them.
     **Leads first**, because speed to first contact is the number that moves
     conversion and a lead under a hundred and eighty clients is a lead nobody
     rings. **Clients** is the working book of business — active and paused —
     and is named Clients rather than Active clients because a paused client is
     still a client and reads wrong filed under an ending. **Past clients** are
     ended engagements: still clients, still holding their number, and folded
     shut by default because nobody opens this page to read them. The fold is
     remembered, so somebody who does open it keeps it open. */
  var GROUPS = [
    ['leads',   'Leads'],
    ['clients', 'Clients'],
    /* Paused is a band of its own (the user, 2026-10-08), folded open by
       default: a paused client is still a client, but read apart. */
    ['paused',  'Paused'],
    ['past',    'Past clients']
  ];
  var SHUT_BY_DEFAULT = { past: true };
  /* The fold is remembered by ADspaceGroup under the route, so a Past
     clients card shut on Monday is shut on Tuesday. */
  var GRP = window.ADspaceGroup;
  function bandShut(key, lone) { return GRP.shut('clients', key, SHUT_BY_DEFAULT[key], lone); }
  var INDUSTRIES = ['Property', 'F&B', 'Retail', 'Wellness', 'Lifestyle',
                    'Automotive', 'Tech', 'Education', 'Other'];
  var LANG_WORD = { en: 'English', zh: '中文', ms: 'Bahasa Malaysia' };
  var KIND_WORD = { call: 'Call', visit: 'Site visit', meeting: 'Meeting',
                    whatsapp: 'WhatsApp', email: 'Email', note: 'Note' };

  function stageWord(v) {
    for (var i = 0; i < STAGES.length; i++) if (STAGES[i][0] === v) return STAGES[i];
    return STAGES[0];
  }

  /* The stage clock is the database's to set, so after a move the row is read
     back rather than patched from here: a guessed timestamp is a timestamp
     that disagrees with the one every other screen will load. */
  function refreshClient(c, then) {
    db.from('clients').select('stage_since, stage_log, updated_at').eq('id', c.id).single().then(function (r) {
      if (r && r.data) {
        c.updated_at = r.data.updated_at;
        c.stage_since = r.data.stage_since;
        c.stage_log = r.data.stage_log;
        var mine = state.clients.filter(function (x) { return x.id === c.id; })[0];
        if (mine) { mine.stage_since = r.data.stage_since; mine.stage_log = r.data.stage_log; }
      }
      then();
    }, then);
  }

  /* How long, in the units a sales cycle is actually discussed in. An hour's
     precision on a two week stall is noise, and "487 days" is a number nobody
     reads, so days give way to months once a stage has run long enough that
     the exact day has stopped mattering. */
  /* Calendar days in Malaysia, as the dates beside them read (2026-10-10:
     a stage begun at 3:59pm on 9 Oct read Today at noon on 10 Oct, because
     whole 24 hours were counted rather than days on the calendar). */
  function myDay(t) { return Math.floor((t + 8 * 3600e3) / 86400000); }
  function daysBetween(from, to) { return Math.max(0, myDay(to) - myDay(from)); }
  function daysSince(iso) {
    if (!iso) return null;
    var t = Date.parse(iso);
    if (isNaN(t)) return null;
    return daysBetween(t, Date.now());
  }
  function spanWord(days) {
    if (days === null) return '';
    if (days === 0) return 'Today';
    if (days === 1) return '1 day';
    if (days < 60) return days + ' days';
    var m = Math.round(days / 30.44);
    return m + (m === 1 ? ' month' : ' months');
  }
  function ageWord(c) { return spanWord(daysSince(c && c.stage_since)); }

  /* When a stage has run longer than it should have.
     Calendar days, not working days: a lead that came in on Friday is just as
     cold on Monday morning, and a client waiting on a proposal does not count
     our weekends. Lead is 48 hours, the window to make first contact, so it
     is measured in hours rather than whole days or a lead keyed in this
     morning would read overdue tomorrow. Proposal sent is 21 days, the
     longest a proposal should sit unanswered; a week is normal, so nothing is
     flagged before then without a second threshold saying so.
     Contacted carries no limit until somebody sets one: a number nobody has
     chosen is not one to invent at scanning time, and a wrong one trains the
     team to ignore the mark. */
  /* The two limits are settings an admin changes (the Clients bar's ⋯,
     Follow-up limits; `app_settings`, 2026-10-05), read in hours. */
  /* A VIC lead waits less (2026-10-15): its own two limits, Business
     settings beside the standard ones, for a client that is VIC. */
  function staleH(c) {
    var S = window.ADspaceMoney.setting;
    if (c && isVic(c.id)) return { lead: S('vic_lead_followup_hours'), proposal: S('vic_proposal_followup_days') * 24 };
    return { lead: S('lead_followup_hours'), proposal: S('proposal_followup_days') * 24 };
  }
  function isStale(c) {
    var limit = staleH(c)[(c && c.stage) || 'lead'];
    if (!limit || !c || !c.stage_since) return false;
    var t = Date.parse(c.stage_since);
    return !isNaN(t) && (Date.now() - t) / 3600000 >= limit;
  }

  /* The journey as rows: when each stage began and how long it took, with the
     current one still running. Read from the stamped history the trigger
     writes, not from the activity record, because the record is a log of what
     people did and this is a fact about the client.

     Each row's duration is one of the turnarounds the team wants to average
     later: time in Lead is how long a lead waited to be contacted, time in
     Contacted is how long from first contact to a proposal, time in Proposal
     sent is how long it took to close, and time in Active is how long this
     client has been engaged. Nothing new is stored for any of it — the
     history is already there, so a report over every client needs no field
     and no backfill. */
  function journeyOf(c) {
    var log = (c && c.stage_log) || [];
    /* A record whose history predates the clock still knows when its current
       stage began, so it says that much rather than nothing. */
    if (!log.length && c && c.stage_since) log = [{ stage: c.stage || 'lead', at: c.stage_since }];
    var out = [];
    for (var i = 0; i < log.length; i++) {
      var at = Date.parse(log[i].at);
      if (isNaN(at)) continue;
      var last = i + 1 === log.length;
      var next = last ? Date.now() : Date.parse(log[i + 1].at);
      out.push({
        i: i,
        stage: log[i].stage,
        word: stageWord(log[i].stage)[1],
        at: log[i].at,
        reason: log[i].reason || '',
        days: daysBetween(at, next),
        now: last
      });
    }
    return out;
  }

  /* What an invoice needs. Field id, column, label, required. A client is
     not active until the required ones are here. The billing contact is one
     of the client's contacts, the main contact unless another is chosen. */
  var BILLING = [
    ['crmLegalName',    'legal_name',      'Company name as registered', true],
    ['crmCompanyNo',    'company_no',      'Business registration no.',  true],
    ['crmCompanyNoOld', 'company_no_old',  'Old registration no.'],
    ['crmTin',          'tin',             'TIN'],
    ['crmSstNo',        'sst_no',          'SST registration no.'],
    ['crmBillContact',  'bill_contact_id', 'Billing contact', true],
    ['crmFinanceEmail', 'finance_email',   'Finance department email'],
    ['crmBillAddr',     'billing_address', 'Company billing address', true]
  ];
  var BILLING_REQUIRED = BILLING.filter(function (f) { return f[3]; });
  /* The billing contact follows the main contact unless somebody else is
     chosen (2026-10-13): an empty bill_contact_id is the main contact, the
     database answers a letter's Attn the same way (`issue_letter`), and a
     contact that stops being the main contact, or is removed, lets go of
     the billing contact by trigger (`client_contacts_bill_follows`). */
  function mainContact() {
    return (state.contacts || []).filter(function (x) { return x.is_primary && !x.archived_at; })[0] || null;
  }
  function billContact(c) {
    var list = state.contacts || [];
    return list.filter(function (x) { return x.id === c.bill_contact_id && !x.archived_at; })[0] || mainContact();
  }
  /* Where Billing withholds the values, the database still names the
     required fields left blank (`billing_missing`), so the gate says what is
     missing to somebody who cannot read what is there. */
  function billingMissing(c) {
    var told = !maySeeBilling() && c.billing_missing;
    return BILLING_REQUIRED.filter(function (f) {
      if (f[1] === 'bill_contact_id') return !billContact(c);
      if (told) return told.indexOf(f[1]) > -1;
      return !String(c[f[1]] || '').trim();
    }).map(function (f) { return f[2]; });
  }
  /* A ring for how much of a group is filled, with the count beside it. */
  /* Complete is a filled green disc with a white tick: a full ring read as
     an empty circle, the one shape that says "not started" (the user,
     2026-09-25). */
  function ring(done, total) {
    if (done >= total) return '<span class="ringline">' + RING_DONE + 'Complete</span>';
    var r = 8, len = 2 * Math.PI * r, off = len * (1 - (total ? done / total : 0));
    return '<span class="ringline"><svg class="ring" viewBox="0 0 20 20" aria-hidden="true">' +
      '<circle class="ring-track" cx="10" cy="10" r="' + r + '"/>' +
      '<circle class="ring-arc" cx="10" cy="10" r="' + r + '" stroke-dasharray="' + len.toFixed(2) + '" stroke-dashoffset="' + off.toFixed(2) + '"/>' +
      '</svg>' + (done >= total ? 'Complete' : done + ' of ' + total) + '</span>';
  }

  var RING_DONE = '<svg class="ring-done" viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="9.5"/><path d="M6 10.3l2.8 2.8L14.3 7.4"/></svg>';

  var state = { clients: [], team: [], client: null, editing: null, contacts: [], touches: [], services: [], documents: [], docMap: {}, log: [], lastSeen: {} };

  // ---- List ---------------------------------------------------------------
  /* The people on a record come from the team list, not from typing: a name
     keyed by hand is a name spelled two ways by Friday. A value already on a
     record that is no longer on the team is kept as its own option, so opening
     an old record and saving it cannot quietly unassign the person who owns
     it. Used for the client's and the campaign's Person in charge alike. */
  function peopleSelect(el, team, current) {
    if (!el) return;
    var keep = current != null ? current : el.value;
    var list = team.slice().sort(F.byStaff);
    if (keep && !list.some(function (m) { return m.name === keep; })) list.push({ name: keep });
    el.innerHTML = '<option value="">Unassigned</option>' +
      list.map(function (m) { return '<option value="' + esc(m.name) + '">' + esc(F.named(m.staff_code, m.name)) + '</option>'; }).join('');
    el.value = keep || '';
  }

  /* Sales by (2026-10-23): a colleague by id, Not set first; one who has
     left stays the chosen option, named as the team list last held them. */
  function salesBySelect(el, team, current) {
    if (!el) return;
    var list = team.slice().sort(F.byStaff);
    var opts = '<option value="">Not set</option>' + list.map(function (m) {
      return '<option value="' + esc(m.id) + '">' + esc(F.named(m.staff_code, m.name)) + '</option>';
    }).join('');
    if (current && !list.some(function (m) { return m.id === current; })) opts += '<option value="' + esc(current) + '">Former colleague</option>';
    el.innerHTML = opts;
    el.value = current || '';
  }
  function salesByName(id) {
    if (!id) return '';
    var m = (state.team || []).filter(function (x) { return x.id === id; })[0];
    return m ? m.name : 'Former colleague';
  }
  function fillSelect(el, rows, all) {
    if (!el) return;
    var keep = el.value;
    el.innerHTML = (all ? '<option value="all">' + esc(all) + '</option>' : '') +
      rows.map(function (r) {
        return '<option value="' + esc(r[0]) + '">' + esc(r[1]) + '</option>';
      }).join('');
    if (keep) el.value = keep;
  }

  function loadTeam(then) {
    db.from('team_members').select('id, name, email, staff_code, designation, department, role, is_admin, system, active').eq('active', true).order('name').then(function (r) {
      /* A system account (2026-10-08) holds no clients and is never offered. */
      var S = window.ADspaceAdmin;
      state.team = ((r.data) || []).filter(function (m) { return !(S && S.isSystem && S.isSystem(m)); });
      peopleSelect($('crmOwnerPick'), state.team);
      fillSelect($('crmOwner'), state.team.slice().sort(F.byStaff).map(function (m) { return [m.name, F.named(m.staff_code, m.name)]; }), 'All people');
      if (state.due) paintDue();
      if (then) then();
    }, function () { if (then) then(); });
  }

  /* Loading, empty and failed are said one way across the console. */
  var UI = window.ADspaceState;
  var skeleton = UI.skeleton, failLine = UI.failLine;

  function loadClients(then) {
    var box = $('crmList');
    if (!state.clients.length) skeleton(box, 6);
    readPages(function () { return db.from('clients').select(API.CLIENT_COLS).order('name').order('id'); }).then(function (r) {
      return r.error ? r : API.withBilling(r.data || []).then(function () { return r; });
    }).then(function (r) {
      if (r.error) {
        box.innerHTML = '<div class="softpanel"><div class="errline">' +
          '<b>Clients could not be loaded.</b><span>' + esc(r.error.message) + '</span>' +
          '<button class="btn btn-sm" data-a="retry" type="button">Try again</button></div></div>';
        box.querySelector('[data-a="retry"]').addEventListener('click', function () { loadClients(then); });
        return;
      }
      state.clients = r.data || [];
      paintList();
      loadLastSeen();
      if (then) then();
    });
  }

  /* The last thing that happened with each client. It is a column on the
     register because "who has gone quiet" is the second question anybody asks
     of this list, after "who is overdue". It is the newest of three facts the
     team already records (the user chose this on 2026-09-26): a call or visit
     logged, the stage moving, and a document issued, the Letter of Offer or
     one from Documents. Each table answers under its own read policy, so
     somebody without Documents still sees their calls and stage moves. The
     word under the date says which of the three it was. */
  function loadLastSeen() {
    var seen = {};
    function take(id, at, word) {
      if (!id || !at) return;
      var t = Date.parse(at);
      /* A date ahead of now is a plan, not something that happened. */
      if (isNaN(t) || t > Date.now() + 60000) return;
      if (!seen[id] || t > seen[id].t) seen[id] = { t: t, word: word };
    }
    state.clients.forEach(function (c) {
      if (!c.stage_since) return;
      /* A record that has never moved stage started its clock when it was
         keyed in, so its first fact is that it was added. */
      var added = !c.created_at || Math.abs(Date.parse(c.stage_since) - Date.parse(c.created_at)) < 60000;
      take(c.id, c.stage_since, added ? 'Added' : 'Stage moved');
    });
    var title = (window.ADspaceForm && window.ADspaceForm.title) || function (s) { return s; };
    /* The newest of each per client in one read (`client_last_activity`,
       2026-10-19), never every row: three unpaged reads lost the newest
       past a thousand. A refused read leaves the stage moves alone. */
    /* Read a thousand at a time: up to three rows a client passed
       PostgREST's thousand at about 350 clients (the audit of 2026-10-26,
       finding 5). */
    window.ADspaceAPI.readPages(function () { return db.rpc('client_last_activity').order('client_id').order('source'); })
      .then(function (r) { return r.data || []; }, function () { return []; }).then(function (all) {
      all.forEach(function (x) {
        take(x.client_id, x.at, x.source === 'touch' ? (KIND_WORD[x.kind] || 'Call')
          : x.source === 'letter' ? 'Letter of Offer' : (x.kind ? title(x.kind) : 'Document'));
      });
      state.lastSeen = seen;
      if (!$('crmListView').hidden) paintList();
    });
  }

  function visible() {
    var q = val('crmSearch').toLowerCase();
    var stage = $('crmStage').value;
    var owner = $('crmOwner').value;
    var vicOnly = $('crmVic') && $('crmVic').value === 'vic';
    return state.clients.filter(function (c) {
      if (vicOnly && !isVic(c.id)) return false;
      /* The number is what somebody holding an invoice searches by, so it is
         searched alongside the two names. */
      if (q && String(c.name || '').toLowerCase().indexOf(q) < 0 &&
               String(c.legal_name || '').toLowerCase().indexOf(q) < 0 &&
               String(c.client_code || '').toLowerCase().indexOf(q) < 0) return false;
      if (stage !== 'all' && (c.stage || 'lead') !== stage) return false;
      if (owner !== 'all' && (c.owner || '') !== owner) return false;
      return true;
    });
  }

  /* The newest client first, by the Client ID the accounting system issues
     in sequence (AC012 above AC011): the number is how the team counts its
     clients, so the largest is the latest (the user, 2026-09-26). The digits
     are compared as numbers, so AC100 sits above AC99. A record with no ID
     yet is a lead that has not been numbered, and follows, newest first. */
  function byCode(a, b) {
    var ca = String(a.client_code || ''), cb = String(b.client_code || '');
    if (ca && !cb) return -1;
    if (!ca && cb) return 1;
    if (ca && cb) return cb.localeCompare(ca, 'en', { numeric: true, sensitivity: 'base' });
    return String(b.created_at || '').localeCompare(String(a.created_at || ''));
  }

  function paintList() {
    /* The VIC view is drawn while any client is VIC. */
    if ($('crmVic')) {
      var anyVic = state.clients.some(function (c) { return isVic(c.id); });
      if (!anyVic && $('crmVic').value !== 'all') $('crmVic').value = 'all';
      $('crmVic').hidden = !anyVic;
    }
    var rows = visible().sort(byCode);
    state.shown = rows;
    paintBulk();
    /* The same count everywhere: how many there are, or how many of them a
       filter has left. It used to read "1 client" whether that was the whole
       list or one of forty. */
    $('crmCount').textContent = !state.clients.length ? ''
      : rows.length === state.clients.length
        ? state.clients.length + (state.clients.length === 1 ? ' client' : ' clients')
        : rows.length + ' of ' + state.clients.length;
    var box = $('crmList');
    box.innerHTML = '';
    if (!rows.length) {
      /* Nothing there and nothing left after a filter are two different
         answers, so each carries its own way out. Said through the shared
         helper, because every other list in the console says it through that
         one and this list had its own copy of the same markup. */
      if (state.clients.length) {
        UI.emptyLine(box, 'No matches.', 'Clear the filters', clearFilters);
      } else {
        if (bandMay('lead', 'work')) UI.emptyLine(box, 'No clients.', 'Add the first lead', function () { $('crmNew').click(); });
        else UI.emptyLine(box, 'No clients.');
      }
      return;
    }
    /* A card per stage, each under its own heading, the way the rate card
       lists Services and Add-ons. The register was one surface with the
       stages as uppercase divider rows inside it for a week; the user sent
       that back on 2026-09-22 (the eyebrow face and its spacing read as
       wrong), so the stages are the section headings they were before, with
       the count, the overdue mark and the value on the heading line, and
       each stage's table carries its own header. Past clients stay shut by
       default and open from the heading; a filter opens every card. */
    var groupLimit = 30;
    var filtered = rows.length !== state.clients.length;
    GROUPS.forEach(function (g) {
      var mine = rows.filter(function (c) { return stageWord(c.stage || 'lead')[3] === g[0]; });
      if (!mine.length) return;
      box.appendChild(GRP.section({
        route: 'clients', key: g[0], name: g[1], count: mine.length,
        marks: bandMarks(mine),
        shut: !filtered && bandShut(g[0], mine.length === rows.length),
        table: function () {
          var table = GRP.table('client-row' + (state.pick ? ' is-picking' : ''),
            ['Client', 'Stage', 'Industry', 'Person in charge', 'Last activity', ''], 'crm-register');
          /* A card draws its first thirty and offers the rest, so a book of a
             hundred and eighty opens as a page somebody can read rather than
             as a mile of rows. A filter narrows what reaches this point, so
             searching is always faster than scrolling. */
          GRP.more(table, mine, groupLimit, g[1].toLowerCase(), listRow);
          return table;
        }
      }));
    });
  }

  /* What sits on a stage's heading after its name and count: how many have
     run over, and what the group is worth. Absent where none has gone over,
     so a healthy stage stays quiet. */
  function bandMarks(mine) {
    /* No value on the heading or the rows (the user, 2026-09-26): what a
       client is worth is read on the record's Services, against the lines
       it is made of, not as a figure on a list. */
    var late = mine.filter(isStale).length;
    return late ? '<span class="tone is-danger crm-band-late">' + late + ' overdue</span>' : '';
  }

  /* A column per fact, because that is what every CRM anyone here has used
     looks like, and because the eye scans a column far faster than it scans
     a chip stranded at the other end of a wide row. */
  function listRow(c) {
    var w = stageWord(c.stage || 'lead');
    /* Picking (Select clients, 2026-10-07), the row is its tick's label: a
       press anywhere on it ticks it, and nothing opens. */
    var picking = Boolean(state.pick);
    var row = document.createElement(picking ? 'label' : 'button');
    if (!picking) row.type = 'button';
    row.className = 'crm-row client-row' + (picking ? ' is-picking' + (state.pick[c.id] ? ' is-picked' : '') : '');
    row.innerHTML =
      /* The number the accounting system issued, under the name it belongs to
         rather than in a column of its own: a seventh column costs the name
         its width on every row for a value that is only read when somebody is
         holding an invoice, and the phone template has nowhere to put it. Set
         the way this portal sets every other token. */
      /* The client's own logo beside the name, the record head's mark at row
         size (the user, 2026-10-03): most clients hold one, and a logo is
         found faster than a name is read. Initials stand in only while none
         is held, or where the picture fails to load, so the names keep one
         left edge. Decorative: the name beside it says who it is. */
      '<span class="crm-c crm-c-name">' +
        (picking ? '<input class="trow-pick cl-pick" type="checkbox"' + (state.pick[c.id] ? ' checked' : '') +
          ' aria-label="Select ' + esc(c.name || '') + '">' : '') +
        '<span class="cl-mark' + (c.logo_url ? ' has-logo' : '') + (isVic(c.id) ? ' is-vic' : '') + '" aria-hidden="true">' +
          (c.logo_url ? '<img src="' + esc(c.logo_url) + '" alt="" loading="lazy" decoding="async">' : esc(initialsOf(c.name || ''))) +
        '</span>' +
        '<span class="cl-who"><span class="cl-name">' + esc(c.name || '') + vicTagOf(c.id, true) + '</span>' +
          (c.client_code ? '<small class="crm-c-code">' + esc(c.client_code) + '</small>' : '') +
        '</span>' +
      '</span>' +
      '<span class="crm-c crm-c-stage"><span class="tone ' + w[2] + '">' + esc(w[1]) + '</span>' +
        /* The word carries it, not the colour: the mark has to survive a
           greyscale print and a reader who cannot tell warn from mute. */
        (ageWord(c) ? '<small class="crm-age' + (isStale(c) ? ' is-late' : '') + '">' +
          esc(ageWord(c) + (isStale(c) ? ' · Overdue' : '')) + '</small>' : '') + '</span>' +
      '<span class="crm-c crm-c-ind">' + esc(c.industry || '—') + '</span>' +
      '<span class="crm-c crm-c-own">' + esc(c.owner || 'Unassigned') + '</span>' +
      /* The last thing that happened, and under it what it was, the way the
         stage cell beside it carries its clock. Where nothing is recorded the
         cell takes the same mute mark the Industry cell uses for a value
         nobody has filled in, because the column heading has already said
         what the cell is. */
      '<span class="crm-c crm-c-seen">' + (lastSeenWord(c)
        ? esc(lastSeenWord(c)) + '<small class="crm-seen-kind">' + esc(state.lastSeen[c.id].word) + '</small>'
        : '<span class="muted">—</span>') + '</span>' +
      /* The one line the phone gets, so it carries the value rather than the
         currency it would be in. A bare RM with no amount is a fragment that
         reads like a broken field, and it was shown even where the client had
         a figure: the desktop column had the money and the phone line threw it
         away for its sign. What is not known is left out rather than stood in
         for, so the line is two or three facts, never a row of placeholders. */
      '<span class="crm-c crm-c-meta">' +
        /* A line of parts wraps between its parts, never inside one. */
        [c.industry, c.owner, lastSeenWord(c)].filter(Boolean).map(function (x) {
          return '<span class="nb">' + esc(x) + '</span>';
        }).join(' · ') +
      '</span>' +
      /* The mark that says the row goes somewhere, in the column the header
         leaves empty. The row is one button, so the whole of it opens the
         client from a pointer and from the keyboard alike, and there is no
         control nested inside another control to trip a screen reader. */
      '<svg class="crm-c crm-c-go" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
        'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
        '<path d="M9 18l6-6-6-6"/></svg>';
    /* A logo that will not load (an expired Facebook address) gives way to
       the initials, never a broken picture. */
    var logo = row.querySelector('.cl-mark img');
    if (logo) logo.addEventListener('error', function () {
      var mk = logo.parentNode;
      mk.classList.remove('has-logo');
      mk.textContent = initialsOf(c.name || '');
    });
    if (picking) {
      row.querySelector('.cl-pick').addEventListener('change', function () {
        if (this.checked) state.pick[c.id] = 1; else delete state.pick[c.id];
        row.classList.toggle('is-picked', this.checked);
        paintBulk();
      });
    } else row.addEventListener('click', function () { openClient(c); });
    return row;
  }

  /* SELECT (the user, 2026-10-06: "most of the sections are missing the
     select button"): Select clients in the bar's ⋯ (Clients Full Access)
     turns each row shown into its tick; the bar over the list counts them
     and changes Person in charge for all of them at once, each through the
     write one client takes (`.select('id')`, the owner guard re-checking),
     filed as any edit of it, with Undo putting back each client's own. */
  function setPicking(on) {
    state.pick = on ? {} : null;
    msg('crmBulkMsg', '');
    paintList();
  }
  function pickedClients() {
    return (state.shown || []).filter(function (c) { return state.pick && state.pick[c.id]; });
  }
  function paintBulk() {
    var bar = $('crmBulk');
    if (!bar) return;
    bar.hidden = !state.pick || $('crmList').hidden;
    if (bar.hidden) return;
    var ids = (state.shown || []).map(function (c) { return c.id; });
    Object.keys(state.pick).forEach(function (id) { if (ids.indexOf(id) < 0) delete state.pick[id]; });
    var n = Object.keys(state.pick).length;
    $('crmBulkCount').textContent = n + ' selected';
    var all = $('crmBulkAll');
    all.checked = n > 0 && n === ids.length;
    all.indeterminate = n > 0 && n < ids.length;
    all.setAttribute('aria-label', n && n === ids.length ? 'Clear the selection' : 'Select every client shown');
    $('crmBulkOwner').hidden = !n;
  }
  /* Each client in turn, so a refusal is named against its client. */
  function setOwners(list, nameOf, then) {
    var out = { ok: [], bad: [] };
    list.reduce(function (p, c) {
      return p.then(function () {
        var to = nameOf(c);
        return db.from('clients').update({ owner: to || null }).eq('id', c.id).select('id').then(function (r) {
          if (r.error || !(r.data || []).length) { out.bad.push({ c: c, err: r.error ? r.error.message : 'refused' }); return; }
          var was = c.owner || '';
          var mine = state.clients.filter(function (x) { return x.id === c.id; })[0];
          if (mine) mine.owner = to || null;
          c.owner = to || null;
          log('client.edited', c.name, 'Person in charge: ' + (was || 'not set') + ' → ' + (to || 'not set'));
          out.ok.push({ c: c, was: was });
        }).catch(function (e) { out.bad.push({ c: c, err: (e && e.message) || 'refused' }); });
      });
    }, Promise.resolve()).then(function () { then(out); });
  }
  function bulkOwner() {
    var list = pickedClients();
    if (!list.length) return;
    var people = (state.team || []).slice().sort(F.byStaff);
    window.ADspaceConfirm.ask({
      title: 'Change person in charge?', go: 'Change',
      field: { label: 'Person in charge', value: '', need: 'Choose a colleague.',
        choices: [['', 'Choose a colleague']].concat(people.map(function (m) { return [m.name, F.named(m.staff_code, m.name)]; })) }
    }, function (v) {
      var to = (v && typeof v === 'object' ? v[0] : v) || '';
      if (!to) return;
      var moving = list.filter(function (c) { return (c.owner || '') !== to; });
      if (!moving.length) { msg('crmBulkMsg', 'No change.', 'ok'); return; }
      setOwners(moving, function () { return to; }, function (out) {
        setPicking(false);
        var badWord = out.bad.length ? ' ' + out.bad.length + ' not: ' + out.bad.slice(0, 3).map(function (x) {
          return (x.c.name || 'a client');
        }).join(', ') + (out.bad.length > 3 ? '…' : '') + '.' : '';
        msg('crmBulkMsg', badWord.trim(), out.bad.length ? 'warn' : '');
        if (!out.ok.length) return;
        undoBar(out.ok.length + (out.ok.length === 1 ? ' client' : ' clients') + ' now with ' + to + '.', function () {
          var back = {};
          out.ok.forEach(function (x) { back[x.c.id] = x.was; });
          setOwners(out.ok.map(function (x) { return x.c; }), function (c) { return back[c.id]; }, function (res) {
            paintList();
            msg('crmBulkMsg', res.bad.length ? res.bad.length + ' not put back.' : 'Put back.', res.bad.length ? 'warn' : 'ok');
          });
        }, $('crmBulk'));
      });
    });
  }
  $('crmSelect').addEventListener('click', function () { setPicking(true); });
  $('crmBulkDone').addEventListener('click', function () { setPicking(false); });
  $('crmBulkOwner').addEventListener('click', bulkOwner);
  $('crmBulkAll').addEventListener('change', function () {
    var on = this.checked;
    state.pick = {};
    if (on) (state.shown || []).forEach(function (c) { state.pick[c.id] = 1; });
    paintList();
  });

  /* "12 Sept", or "Sept 2026" once the exact day has stopped mattering — the
     same units the stage clock already talks in. */
  function lastSeenWord(c) {
    var seen = (state.lastSeen || {})[c.id];
    if (!seen) return '';
    var d = new Date(seen.t);
    if (isNaN(d.getTime())) return '';
    var days = Math.floor((Date.now() - d.getTime()) / 86400000);
    return days < 300 ? ADspaceClock.date(d, { year: false }) : ADspaceClock.month(d);
  }

  /* A filter repaints the register when the filter has actually changed, and
     not otherwise. `input` and `change` both fire for one keystroke, and the
     second of them arrives on **blur**: pressing Clear the filters on the
     empty state moved focus off the search box, the box fired `change` with
     the value it already had, the register repainted, and the button was
     detached between mousedown and click — so the one way out of a filtered
     empty list did nothing when it was clicked with a mouse. */
  var filterKey = '';
  function clearFilters() {
    $('crmSearch').value = ''; $('crmStage').value = 'all'; $('crmOwner').value = 'all';
    if ($('crmVic')) $('crmVic').value = 'all';
    onFilter();
  }
  function onFilter() {
    var key = JSON.stringify([val('crmSearch'), $('crmStage').value, $('crmOwner').value, $('crmVic') ? $('crmVic').value : 'all']);
    if (key === filterKey) return;
    filterKey = key;
    paintList();
  }
  ['crmSearch', 'crmStage', 'crmOwner', 'crmVic'].forEach(function (id) {
    $(id).addEventListener('input', onFilter);
    $(id).addEventListener('change', onFilter);
  });

  // ---- Create and edit ----------------------------------------------------
  /* The head of the record: who they are and where they came from. */
  var FORM = [
    ['crmName', 'name'], ['crmIndustry', 'industry'], ['crmOwnerPick', 'owner'],
    ['crmSource', 'source'], ['crmCommence', 'commence'], ['crmClientCode', 'client_code']
  ];
  /* The database's own words on the two rules it holds about a Client ID. */
  function saveWord(m) {
    m = String(m || '');
    if (/clients_client_code_uidx|duplicate key/i.test(m)) return 'That Client ID is already used by another client.';
    if (/clients_client_code_fmt/i.test(m)) return 'A Client ID is 2 to 12 letters or digits, with no spaces or slashes.';
    if (/active-needs-code/.test(m)) return 'An Active client needs a Client ID.';
    if (/active-needs-billing/.test(m)) return 'An Active client needs its registered name, BRN, billing address and billing contact.';
    return m;
  }

  /* The Client ID a letter's serial is built from. Uppercase letters and
     digits only, because it travels inside AQL/AC180/260901 and a slash or a
     space would break the format it is part of. The database holds the same
     rule as a check constraint, so a bad one cannot arrive by any other door. */
  var CODE_OK = /^[A-Z0-9]{2,12}$/;
  function codeOf(v) { return String(v || '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 12); }
  /* The brand as a thing to open. Edited on the record, not at intake. */
  /* The brand profile and Content Review's client settings were two sets of
     fields over one client: `social_*` here and `handle_*` there, plus a logo
     only that screen could set. A handle corrected on the record therefore
     left the one printed on the client's own mockup untouched. There is one
     set now — the `handle_*` columns the review page already reads and the
     `logo_url` the mark and the mockups already draw — so the two screens
     cannot disagree, because they are the same row. `social_*` is backfilled
     into it and no longer written. */
  var BRAND = [
    ['crmWebsite', 'website'], ['crmPhone', 'phone'],
    ['crmSocialIg', 'handle_ig'], ['crmSocialFb', 'handle_fb'],
    ['crmSocialTiktok', 'handle_tiktok'], ['crmSocialXhs', 'handle_xhs'],
    ['crmLogo', 'logo_url']
  ];
  /* When the client wants to start. Three bands, because a lead gives you a
     rough answer and a date nobody has agreed is a false precision. No dash in
     the words: "1 to 3 months", as the copy rules have it everywhere else. */
  var COMMENCE = [
    ['1_3', '1 to 3 months'], ['3_6', '3 to 6 months'], ['6_plus', '6 months or more']
  ];
  function commenceWord(v) {
    var m = COMMENCE.filter(function (x) { return x[0] === v; })[0];
    return m ? m[1] : '';
  }

  var SOURCES = [
    ['referral', 'Referral'], ['website', 'Website'], ['instagram', 'Instagram'],
    ['facebook', 'Facebook'], ['tiktok', 'TikTok'], ['rednote', 'rednote'],
    ['whatsapp', 'WhatsApp'], ['walk_in', 'Walk-in'], ['event', 'Event'],
    ['outreach', 'Outreach'], ['other', 'Other']
  ];
  function sourceWord(v) {
    for (var i = 0; i < SOURCES.length; i++) if (SOURCES[i][0] === v) return SOURCES[i][1];
    return v || '';
  }
  /* To quote, not Quoted: the flag is set while choosing what goes into the
     Letter of Offer, before any letter exists. Past tense would claim the
     quotation had already gone out. Whether it has is the document's state,
     in Documents, not the line's. */
  var SV_STATE = ['enquired', 'quoted', 'confirmed'].reduce(function (m, k) {
    m[k] = [W.en.svState[k], W.tone(k)]; return m;
  }, {});
  var CATS = ['Content', 'Account management', 'Verification', 'Monthly packages',
              'KOC programmes', 'KOL programmes', 'Add-ons'];

  function openForm(c, btn) {
    state.editing = c || null;
    $('crmFormTitle').textContent = c ? 'Edit client' : 'New lead';
    $('crmSave').textContent = c ? 'Save' : 'Add lead';
    FORM.forEach(function (f) { $(f[0]).value = c ? (c[f[1]] || '') : ''; });
    // Rebuilt against this record, so an owner who has since left the team is
    // still the option that is selected rather than silently cleared on save.
    /* A new lead starts in the hands of whoever keys it in; they change it
       where someone else takes it (the user, 2026-10-01). */
    var self = bridge.me && bridge.me();
    peopleSelect($('crmOwnerPick'), state.team, c ? (c.owner || '') : ((self && self.name) || ''));
    /* Person in charge moves from one colleague to another at Clients Full
       Access (`clients_owner_guard`); a record nobody holds may be given. */
    $('crmOwnerPick').disabled = Boolean(c && String(c.owner || '').trim() && !mayPart('clients', 'manage'));
    /* Own clients only: a lead handed to someone else would leave the
       colleague's sight the moment it is saved (`client_row_seen`), so the
       one who keys it in holds it, and a lead nobody holds is taken with
       Take lead. */
    if (self && self.client_scope === 'own' && !self.is_admin) {
      if (!c) $('crmOwnerPick').value = self.name || '';
      $('crmOwnerPick').disabled = true;
    }
    /* Sales by: whoever keys a lead in brought it, and only Clients Full
       Access names anyone else or changes it (`clients_sales_by_guard`). */
    salesBySelect($('crmSalesBy'), state.team, c ? (c.sales_by || '') : ((self && self.id) || ''));
    $('crmSalesBy').disabled = !mayPart('clients', 'manage');
    if (!c) $('crmSource').value = 'referral';
    $('crmMarket').value = c ? (c.market || 'MY') : 'MY';
    // The person who asked, and what for. Only a new lead needs this here.
    $('crmLeadOnly').hidden = Boolean(c);
    /* The salutations are the contact sheet's own list, one copy. */
    var sal = $('crmContactSal'), ctSal = $('ctSalutation');
    if (sal && ctSal && sal.options.length < ctSal.options.length) sal.innerHTML = ctSal.innerHTML;
    ['crmContactSal', 'crmContactName', 'crmContactPhone', 'crmContactWa', 'crmContactEmail'].forEach(function (id) { if ($(id)) $(id).value = ''; });
    // What they asked for is a fact about the client, so editing shows it.
    $('crmEnquiry').value = c ? (c.deal_note || '') : '';
    msg('crmMsg', '');
    codeWarn();
    /* A sheet is over the page, so the form no longer has to be carried to
       where the person is: adding from the list and editing from the record
       are the same card over the same place. It used to be moved into the
       record and to replace its head, which on a phone hid the client while
       their own details were being corrected. Nothing is focused, because a
       field taking focus on a phone raises the keyboard and zooms the page
       over the rest of the form. */
    openSheet('crmAddBox', btn);
  }
  function shutForm() {
    shutSheet('crmAddBox');
    state.editing = null;
  }
  $('crmNew').addEventListener('click', function () { openForm(null, this); });
  $('crmCancel').addEventListener('click', shutForm);

  /* Typed the way it is stored, so nobody saves `ac180` and wonders why the
     serial does not match what they wrote down. */
  $('crmClientCode').addEventListener('input', function () {
    var at = this.selectionStart, was = this.value;
    this.value = codeOf(was);
    try { this.setSelectionRange(at - (was.length - this.value.length), at - (was.length - this.value.length)); } catch (e) {}
    codeWarn();
  });

  /* Changing a code after letters exist is allowed and says what it costs:
     the serials already issued keep the code they were built with. */
  function codeWarn() {
    var el = $('crmCodeWarn');
    if (!el) return;
    var c = state.editing;
    var had = c && String(c.client_code || '');
    var now = val('crmClientCode');
    var issued = (state.documents || []).filter(function (d) { return d.client_code; }).length;
    var show = Boolean(c && had && now && now !== had && issued);
    el.textContent = show
      ? 'Changing the Client ID does not change the ' + issued +
        (issued === 1 ? ' serial number already issued. It applies to letters issued from now on.'
                      : ' serial numbers already issued. It applies to letters issued from now on.')
      : '';
    el.hidden = !show;
  }

  $('crmSave').addEventListener('click', function () {
    var name = val('crmName');
    if (!name) { msg('crmMsg', 'A brand name is required.', 'err'); $('crmName').focus(); return; }
    var patch = { market: $('crmMarket').value };
    FORM.forEach(function (f) { patch[f[1]] = val(f[0]) || null; });
    patch.name = name;
    if (patch.client_code) {
      patch.client_code = codeOf(patch.client_code);
      if (!CODE_OK.test(patch.client_code)) {
        msg('crmMsg', 'A Client ID is 2 to 12 letters or digits, with no spaces or slashes.', 'err');
        if (window.ADspaceForm) ADspaceForm.reveal($('crmClientCode')); else $('crmClientCode').focus();
        return;
      }
    }
    // A lead is a person who asked for something. The stage lives on the
    // record's head, not here.
    var contactName = state.editing ? '' : val('crmContactName');
    if (!state.editing && !contactName) { msg('crmMsg', 'A contact person is required.', 'err'); $('crmContactName').focus(); return; }
    if (!state.editing && waUser(val('crmContactWa')) && !waIsNumber(waUser(val('crmContactWa'))) && !waUserOk(waUser(val('crmContactWa')))) {
      msg('crmMsg', 'A WhatsApp username uses letters, numbers, full stops and underscores.', 'err');
      $('crmContactWa').focus(); return;
    }
    /* A Client ID left empty where none was held is not sent: the field
       never touches what it never held. */
    if (!patch.client_code && !(state.editing && state.editing.client_code)) delete patch.client_code;
    patch.deal_note = val('crmEnquiry') || null;
    /* Sent only where it moved, so a colleague below Full Access saving a
       record never touches it. */
    var sb = $('crmSalesBy') ? $('crmSalesBy').value || null : null;
    if (!state.editing || sb !== (state.editing.sales_by || null)) patch.sales_by = sb;
    if (!state.editing) patch.stage = 'lead';

    if (state.editing) {
      var id = state.editing.id;
      db.from('clients').update(patch).eq('id', id).select('id').then(function (r) {
        if (r.error) { msg('crmMsg', saveWord(r.error.message), 'err'); return; }
        if (!(r.data || []).length) { msg('crmMsg', 'Not saved. The database refused the request.', 'err'); return; }
        var moved = changed(state.editing, patch, [
          ['name', 'Brand name'], ['client_code', 'Client ID'], ['industry', 'Industry'], ['market', 'Market'],
          ['owner', 'Person in charge'], ['sales_by', 'Sales by', salesByName], ['source', 'Source'], ['commence', 'Urgency to commence', commenceWord],
          ['deal_note', 'Enquiry']]);
        if (moved) log('client.edited', name, moved);
        shutForm();
        /* The one row read back, never the whole list with its billing
           (2026-10-22, CLI-9). */
        db.from('clients').select(API.CLIENT_COLS).eq('id', id).single().then(function (q) {
          var found = state.clients.filter(function (x) { return x.id === id; })[0];
          if (!found) return;
          Object.assign(found, (q && !q.error && q.data) || patch);
          openClient(found);
        }, function () {
          var found = state.clients.filter(function (x) { return x.id === id; })[0];
          if (found) { Object.assign(found, patch); openClient(found); }
        });
      });
      return;
    }
    // Every client carries its own review link from the moment it exists, so
    // Content Review has nothing left to create.
    patch.access_token = token();
    uniqueSlug(name, function (first) {
    var tries = 0;
    var insert = function (slug) {
    patch.slug = slug;
    db.from('clients').insert(patch).select(API.CLIENT_COLS).single().then(function (r) {
      if (r.error) {
        /* The slug was checked against the clients this colleague can see;
           one held by a client out of their scope (every Chinese name reads
           `client`) is taken by the index, and the next number is asked. */
        if (r.error.code === '23505' && /slug/.test(String(r.error.message) + String(r.error.details || '')) && tries++ < 12) {
          insert(nextSlug(slug, tries)); return;
        }
        msg('crmMsg', saveWord(r.error.message), 'err'); return;
      }
      var salW = ($('crmContactSal') && $('crmContactSal').value) || '';
      log('client.added', name, sourceWord(patch.source) + (contactName ? ' · ' + (salW ? salW + ' ' : '') + contactName : ''));
      var phone = val('crmContactPhone'), email = val('crmContactEmail');
      var ct = {
        client_id: r.data.id, salutation: salW || null, name: contactName, phone: phone || null,
        whatsapp: waStore(val('crmContactWa'), phone),
        email: email || null, lang: 'en', is_primary: true
      };
      /* The contact is a second write. A refused one is said, and what was
         typed waits in the contact sheet on the new record, never lost. */
      var open = function (failed) {
        shutForm();
        loadClients(function () {
          openClient(r.data);
          if (!failed) return;
          openContact(null);
          $('ctSalutation').value = ct.salutation || '';
          $('ctName').value = ct.name; $('ctPhone').value = ct.phone || '';
          $('ctWa').value = waHandle(ct.whatsapp) || (ct.whatsapp !== ct.phone ? ct.whatsapp || '' : '');
          $('ctEmail').value = ct.email || ''; $('ctPrimary').checked = true;
          msg('ctMsg', 'The client was added, but the contact was not saved. Save it again.', 'err');
        });
      };
      db.from('client_contacts').insert(ct).select('id').then(function (c) {
        open(Boolean(c.error || !(c.data || []).length));
      }).catch(function () { open(true); });
    }).catch(function () { msg('crmMsg', 'Not saved. Check the connection and try again.', 'err'); });
    };
    insert(first);
    });
  });

  // ---- One client ---------------------------------------------------------
  /* The record's Details: repainted alone when a service line moves the
     value (2026-10-22, SL-4). */
  function paintFacts(c) {
    var mk = MON.market(MON.curOf(c));
    /* Person in charge has moved to the identity line and Added to Key dates,
       so neither is stated twice: a rail that repeats the head is a rail
       nobody reads. */
    $('crmFacts').innerHTML = [
      /* Null is Not set; every value is typed text, so it is always escaped
         (a stored Industry reading <span… once drew as markup). */
      ['Client ID', c.client_code || null],
      ['Source',   c.source ? sourceWord(c.source) : null],
      ['Sales by', c.sales_by ? salesByName(c.sales_by) : null],
      ['Industry', c.industry || null],
      ['Market',   (c.market === 'SG' ? 'Singapore' : 'Malaysia') + ' · ' + mk.sign],
      ['Value',    c.deal_value ? MON.money(c.deal_value, MON.curOf(c)) : null],
      ['To commence', c.commence ? commenceWord(c.commence) : null]
    ].filter(function (f) { return f[1] !== ''; }).map(function (f) {
      return '<div><dt>' + f[0] + '</dt><dd>' +
        (f[1] == null ? '<span class="muted">Not set</span>' : esc(f[1])) + '</dd></div>';
    }).join('');
  }
  function openClient(c, restoring) {
    if ($('crmListMsg')) $('crmListMsg').textContent = '';
    /* Re-opening the same record is a repaint, not a navigation: logging a
       call moves the stage, which reads the client back, and that used to
       throw somebody out of the pane they were working in. */
    var same = Boolean(state.client && state.client.id === c.id);
    if (!same) { state.contacts = []; state.log = []; state.ovFail = {}; state.quotes = null; ba.id = null; if ($('crmQuotes')) $('crmQuotes').hidden = true; }
    /* A record opens at its top. Opened from a list scrolled down, it kept
       the list's scroll and drew halfway down its own page (2026-09-28). A
       refresh restores its own place (`restoring`). */
    if (!same && !restoring) window.scrollTo(0, 0);
    state.client = c;
    /* The list was read once; Content Review's settings edit the same
       handles and logo, so a record opened from the list is read again and
       repainted where the row has moved on (2026-09-26). */
    if (!same) {
      /* White label and its wide logo (2026-10-07) are read with the record
         alone, never with the list: the logo is a picture. */
      db.from('clients').select('white_label, report_logo, brief, restricted_platform, restricted_since, restricted_note').eq('id', c.id).maybeSingle().then(function (r) {
        if (!r || r.error || !r.data || state.client !== c) return;
        c.white_label = Boolean(r.data.white_label); c.report_logo = r.data.report_logo || null;
        c.brief = r.data.brief || null;
        c.restricted_platform = r.data.restricted_platform || null; c.restricted_since = r.data.restricted_since || null;
        c.restricted_note = r.data.restricted_note || null;
        paintRestrict(c);
        paintBrandRead(c);
      }).catch(function () {});
      db.from('clients').select(API.CLIENT_COLS).eq('id', c.id).single().then(function (r) {
        if (!r || r.error || !r.data || state.client !== c) return;
        /* `updated_at` is stamped by `clients_touch` on every write, so it
           alone says whether the row moved; comparing every column redrew
           every pane on a difference of form (CLI-9). */
        if (r.data.updated_at === c.updated_at) return;
        Object.assign(c, r.data);
        openClient(c, true);
      }, function () {});
    }
    Array.prototype.forEach.call(document.querySelectorAll('#crmTabs [data-needs-activity]'), function (b) {
      b.hidden = !maySeeActivity();
    });
    gateTabs();
    $('crmListView').hidden = true;
    $('crmWork').hidden = false;
    $('crmClientName').textContent = c.name || '';
    var w = stageWord(c.stage || 'lead');
    // The stage is a value, so it is a select on the head; the gate to Active
    // sits on it.
    var sel = $('crmClientStage');
    sel.innerHTML = STAGES.map(function (s) {
      var here = s[0] === (c.stage || 'lead');
      return '<option value="' + s[0] + '"' + (here ? ' selected' : '') +
        (!here && !bandMay(s[0], 'work') ? ' disabled' : '') + '>' + esc(s[1]) + '</option>';
    }).join('');
    sel.disabled = !bandMay(c.stage || 'lead', 'work');
    sel.className = 'select select-sm state-select ' + (w[2] || '');
    /* A lead nobody is in charge of is anybody's to take who may work leads. */
    $('crmTake').hidden = !(bandKey(c.stage) === 'clients.leads' && !String(c.owner || '').trim() &&
                            bandMay(c.stage, 'work') && bridge.me && bridge.me() && bridge.me().name);
    /* Edit and Brand's Edit change the record, so they ask its band at Work
       as the database does; a View group was offered both, and its save was
       refused as nothing changed (audit, 2026-10-03). The ⋯ leaves when
       nothing in it can be pressed. */
    var canWork = bandMay(c.stage || 'lead', 'work');
    $('crmEdit').hidden = !canWork;
    $('crmBrandEdit').hidden = !(canWork && mayPart('clients.brand', 'work'));
    $('crmClientMenuWrap').hidden = !canWork && !mayPart('clients', 'manage');
    /* Request feedback on WhatsApp (2026-10-09; the composer from
       2026-10-10, js/whatsapp.js): where the feedback template is on, at
       WhatsApp Manage and its Feedback request part, the client read. */
    $('crmFeedback').hidden = true;
    /* Feedback is asked of a client, never a lead (MENU-1, 2026-10-22);
       wa_compose_prepare refuses it there too (`not-client`). */
    if (bandKey(c.stage) !== 'clients.leads' && window.ADspaceWhatsApp && window.ADspaceWhatsApp.may('feedback')) {
      var fbFor = c.id;
      window.ADspaceWhatsApp.on('feedback').then(function (yes) {
        if (!state.client || state.client.id !== fbFor || !yes) return;
        $('crmFeedback').hidden = false;
        $('crmClientMenuWrap').hidden = false;
      });
    }
    paintRestrict(c);
    paintVic(c);
    /* There is no Account status block: the stage select in the head says
       where the record stands and the Timeline says for how long, with the
       overdue mark on the stage that is running. A rail block repeating the
       head's own control was the same fact twice. */

    paintIdentity(c);

    paintFacts(c);
    paintSuppliers(c, !same || restoring);

    /* The journey is the Timeline's, stated once: it was a mute line here as
       well, so a record printed "Lead 10 days · Active today" under Details
       and the same durations again in the rail. */

    // Website, phone and the social pages, as things to open rather than read.
    var links = [];
    if (c.website) links.push(linkChip(c.website, 'Website', true));
    if (c.phone)   links.push(linkChip('tel:' + c.phone, c.phone, false));
    /* The field holds a handle now, not a link, so where to open it is
       derived per platform: `https://` + a handle gives `https://starliving`,
       which is nothing. rednote addresses a profile by id, so a display name
       stored there will not resolve — the chip still carries what we hold,
       because showing it is what tells somebody it is the wrong shape. */
    [['handle_ig', 'Instagram'], ['handle_fb', 'Facebook'],
     ['handle_tiktok', 'TikTok'], ['handle_xhs', 'rednote']].forEach(function (p) {
      if (c[p[0]]) links.push(linkChip(profileUrl(p[0], c[p[0]]), p[1], true));
    });
    $('crmLinks').innerHTML = links.join('');

    fillBilling(c);
    paintBilling(c);
    fillBrand(c);
    paintBrandRead(c);
    var linksOn = BRAND.filter(function (f) { return c[f[1]]; }).length;
    $('crmBrandSummary').textContent =
      [linksOn ? linksOn + ' of ' + BRAND.length : '', c.brand_notes ? 'Notes' : '']
        .filter(Boolean).join(' · ') || 'Empty';
    msg('crmWorkMsg', ''); msg('crmBillMsg', ''); msg('crmBrandMsg', ''); msg('crmServiceMsg', '');
    shutContact();
    shutTouch();
    shutService();
    loadContacts();
    loadServices();
    loadDocuments();
    loadRequests();
    loadTouches();
    if (maySeeActivity()) loadClientLog();
    /* The Engagements pane is read when a record is opened or entered again,
       and drawn from that answer on a repaint (a save elsewhere on it). */
    loadEngage(!same || restoring);
    showPane(restoring ? paneFromUrl() : (same ? pane : 'overview'));
    setUrl();
    if (restoring) restoreScroll(true);
  }

  /* ---- The record's own panes ------------------------------------------
     Seven sections in one column meant Documents was a scroll away from the
     services it quotes and Billing was a scroll away from the contact it
     names. The pane is in the address, so a refresh, a pasted link, Back and
     Forward all land on the section somebody was working in. */
  /* Six tabs (2026-10-15; the user: the strip was "gradually increasing,
     and its getting longer"). Each tab shows its parts one under the other,
     each part keeping its own heading and its own address: `tab=billing`
     opens Account on Billing, so every link written before still lands.
     The Activity record has no tab: it opens from the rail's Recent
     activity (View all), and the strip then marks none. */
  var TABS = { overview: ['overview'], calls: ['calls'], engagements: ['engagements', 'checklists'],
    services: ['services', 'documents'], brand: ['brand'], account: ['contacts', 'billing'], activity: ['activity'] };
  var GROUP_OF = {};
  Object.keys(TABS).forEach(function (g) { TABS[g].forEach(function (k) { GROUP_OF[k] = g; }); });
  var PANES = Object.keys(GROUP_OF).concat(['account']);
  var PART_OF = { calls: 'clients.calls', contacts: 'clients.contacts', billing: 'clients.billing',
    checklists: 'clients.checklists' };
  /* A pane holding several parts is drawn where any of them is readable
     (2026-10-22): Services holds Quotations, Service lines and Requests,
     Documents the Letters and the client letters Documents issues, Brand
     the brand and a white-label client's reports. */
  var PARTS_OF = { services: ['clients.quotes', 'clients.services', 'clients.requests'],
    documents: ['clients.documents', 'register.documents'], brand: ['clients.brand', 'reports.whitelabel'] };
  var pane = 'overview';
  /* Engagements is drawn for a client engaged now or before, or one holding
     anything there (js/engage.js); a lead's waits for the answer. Its tab
     stays for the checklists. */
  var engShown = null;

  function paneFromUrl() {
    var t = new URLSearchParams(location.search).get('tab') || '';
    /* The record's Reports tab became Engagements (2026-10-10): an older
       link lands on the client's reports by month. */
    if (t === 'reports') t = 'engagements';
    return PANES.indexOf(t) >= 0 || t === 'work' ? t : 'overview';
  }
  /* A part is drawn where its reader may open it. */
  function partOk(k) {
    if (k === 'activity') return maySeeActivity();
    if (k === 'engagements') {
      var c = state.client, ENG = window.ADspaceEngage;
      return !!c && (ENGAGED.indexOf(c.stage) > -1 || !!(ENG && ENG.holds(c.id)));
    }
    if (PARTS_OF[k]) return PARTS_OF[k].some(function (p) { return mayPart(p, p === 'reports.whitelabel' ? 'work' : 'view'); });
    return !PART_OF[k] || mayPart(PART_OF[k], 'view');
  }

  /* `visit` is a move somebody made to the pane (its tab, Back, a link on
     the Overview), which reads Engagements again; a repaint does not. */
  function showPane(key, visit) {
    /* A client's months, meetings and tasks moved to My Work's Months view
       (2026-09-25), so an older link to this record's Work pane lands there. */
    if (key === 'work' && state.client && bridge.show) {
      history.replaceState(null, '', '/admin/?s=work&view=months&wc=' +
        encodeURIComponent(state.client.slug || state.client.id));
      bridge.show('work');
      return;
    }
    if (PANES.indexOf(key) < 0) key = 'overview';
    var group = TABS[key] ? key : GROUP_OF[key];
    var parts = TABS[group].filter(partOk);
    /* A part not readable falls to its tab's first readable part; a tab
       with none falls to Overview. Engagements' own part waits for its
       answer, so its tab never falls while the checklists stand. */
    if (!parts.length) { key = 'overview'; group = 'overview'; parts = ['overview']; }
    else if (!TABS[key] && parts.indexOf(key) < 0) key = parts[0];
    pane = key;
    /* On its own pane the act is the pane's head's: offered once on a screen. */
    var lc = $('crmLogCall');
    if (lc) lc.classList.toggle('is-here', group === 'calls');
    Array.prototype.forEach.call(document.querySelectorAll('#crmTabs .tab'), function (b) {
      var on = b.getAttribute('data-pane') === group;
      b.classList.toggle('is-on', on);
      b.setAttribute('aria-selected', String(on));
    });
    Array.prototype.forEach.call(document.querySelectorAll('#crmWork .rec-pane'), function (el) {
      el.hidden = parts.indexOf(el.getAttribute('data-pane')) < 0;
    });
    if (parts.indexOf('activity') > -1 && !(state.log || []).length) loadClientLog();
    if (group === 'overview') paintSummary();
    if (group === 'engagements' && visit) loadEngage(true);
    /* A visit reads the calls again: a colleague may have logged one since. */
    if (group === 'calls' && visit) loadTouches();
    if (parts.indexOf('billing') > -1) loadDetForm();
    /* The checklists are read on every visit and on a record opened on
       them (2026-10-15). */
    if (parts.indexOf('checklists') > -1 && window.ADspaceChecklists && state.client &&
        (visit || ckFor !== state.client.id)) {
      ckFor = state.client.id;
      window.ADspaceChecklists.mount($('crmChecklists'), { db: db, client: state.client, msg: msg, undo: undoBar,
        brief: function (filled) { if (filled.length) { ba.id = null; briefAgain(state.client); } } });
    }
    /* A part named by itself, below its tab's first, is brought into view. */
    if (!TABS[key] && parts[0] !== key) {
      var el = document.querySelector('#crmWork .rec-pane[data-pane="' + key + '"]');
      if (el) requestAnimationFrame(function () { el.scrollIntoView({ block: 'start' }); });
    }
  }
  var ckFor = null;

  gateTabs();
  Array.prototype.forEach.call(document.querySelectorAll('#crmTabs .tab'), function (b) {
    b.addEventListener('click', function () {
      if (b.getAttribute('data-pane') === pane) return;
      showPane(b.getAttribute('data-pane'), true);
      pushUrl();
    });
  });
  /* The whole Activity record, from the rail's Recent activity. */
  if ($('crmLogAll')) $('crmLogAll').addEventListener('click', function () {
    if (pane === 'activity') return;
    showPane('activity', true);
    pushUrl();
  });
  /* Back and Forward move between panes, because the pane is in the address
     and the address is what the browser remembers. */
  window.addEventListener('popstate', function () {
    if ($('crmWork').hidden) return;
    showPane(paneFromUrl(), true);
  });

  /* What the portal recorded about this client. `activity_log` carries no
     client id, only the subject it was written with, which is the client's
     name at the time; a rename therefore leaves the older entries behind, and
     that is stated rather than papered over. */
  function loadClientLog() {
    var box = $('crmLogList');
    var c = state.client;
    if (!box || !c) return;
    UI.skeleton(box, 3);
    db.from('activity_log').select('*').eq('subject', c.name)
      .order('created_at', { ascending: false }).limit(50)
      .then(function (r) {
        if (r.error) { UI.failLine(box, 'The record of changes', r.error.message, loadClientLog); return; }
        var rows = r.data || [];
        /* Kept so the rail can show the last three without a second read: the
           record has already paid for this one. */
        state.log = rows;
        railLog();
        /* One line an entry, the client named once by the record itself. */
        box.innerHTML = '<div class="softpanel recpanel"></div>';
        window.ADspaceRecords.paint(box.firstChild, rows.map(recordOf));
      });
  }
  function recordOf(x) {
    var A = window.ADspaceAdmin;
    var r = A && A.record ? A.record(x) : { at: x.created_at, who: x.actor || 'System', what: logWord(x.action), detail: x.detail || '' };
    r.on = '';
    /* Every line here is about this client; a document keeps its own
       reference as the thing it is about, so two documents never fold. */
    if (r.key == null) r.key = 'client';
    return r;
  }

  /* The console already names every action in one place; this reads it rather
     than keeping a second list that would drift from the first. */
  function logWord(action) {
    var A = window.ADspaceAdmin && window.ADspaceAdmin.actionLabel;
    var hit = A && A[action];
    return (hit && hit[0]) || String(action || '').replace(/[._]/g, ' ');
  }


  /* ---- Identity ---------------------------------------------------------
     The record opens on something that says which company this is. The mark
     is the client's own logo where we hold one (`clients.logo_url`, already
     read for the mockups) and their initials where we do not; the logo is the
     client's artwork and is never inverted, which is why the disc behind it
     stays light in both themes, exactly as the review mockups do. */
  /* The campaign record draws the same mark, so the reading lives once, in
     `ADspaceState.initials`. Two copies of it drifted the moment one screen
     learned about the ampersand in "Dale & Cecil" and the other did not. */
  function initialsOf(name) { return UI.initials(name); }

  /* THIS MONTH, ONE LINE (2026-10-08, the user: "All yes"). Under the
     person in charge, how the client's month is going: its tasks done of
     those it holds, what is past its due date, and the day its report is
     owed. The month whose span holds today (`start_day`), counted by
     `ops_engagement_counts` (the whole month, whoever asks) with the open
     tasks the reader sees; pressed, it opens the month in My Work. A lead, a
     client with no month now, or a reader without My Work draws nothing.
     Read with the Engagements pane (js/engage.js, 2026-10-10), so the
     record reads the client's months once. */
  var SHORT_MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
  function paintMonthLine(c) {
    var meta = $('crmIdMeta'), line = $('crmMonthLine');
    if (!meta) return;
    if (!line) {
      line = document.createElement('button');
      line.type = 'button'; line.id = 'crmMonthLine'; line.className = 'linkbtn rec-month'; line.hidden = true;
      meta.parentNode.insertBefore(line, meta.nextSibling);
    }
    line.hidden = true;
    var ENG = window.ADspaceEngage;
    if (!c || !ENG || !(bridge.may && bridge.may('ops', 'view')) || ['active', 'paused'].indexOf(c.stage) < 0) return;
    var f = ENG.monthNow(c.id);
    if (!f) return;
    var parts = ['<span class="part">' + esc(f.word + ': ' + f.done + ' of ' + f.held + ' done') + '</span>'];
    if (f.late) parts.push('<span class="part"><span aria-hidden="true">· </span><span class="is-err">' + f.late + ' overdue</span></span>');
    if (f.due) {
      var due = new Date(f.due + 'T00:00:00Z');
      parts.push('<span class="part"><span aria-hidden="true">· </span>Report due ' + due.getUTCDate() + ' ' + SHORT_MON[due.getUTCMonth()] + '</span>');
    }
    var tone = f.late ? 'is-late' : (f.held && f.done >= f.held) ? 'is-ok' : 'is-wait';
    line.innerHTML = '<span class="rec-month-dot ' + tone + '" aria-hidden="true"></span>' + parts.join('') +
      '<svg class="ovgo-chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>';
    line.setAttribute('aria-label', line.textContent.replace(/\s+/g, ' ').trim() + '. Open the month in My Work');
    line.onclick = function () {
      history.replaceState(null, '', '/admin/?s=work&view=months&wc=' + encodeURIComponent(c.slug || c.id));
      if (bridge.show) bridge.show('work');
    };
    line.hidden = false;
  }

  function paintIdentity(c) {
    var mark = $('crmClientMark');
    if (mark) {
      if (c.logo_url) {
        mark.className = 'rec-mark has-logo';
        mark.innerHTML = '<img src="' + esc(c.logo_url) + '" alt="">';
        var img = mark.querySelector('img');
        img.addEventListener('error', function () {
          mark.className = 'rec-mark';
          mark.textContent = initialsOf(c.name);
        });
      } else {
        mark.className = 'rec-mark';
        mark.textContent = initialsOf(c.name);
      }
      mark.classList.toggle('is-vic', isVic(c.id));
    }
    if ($('crmVicTag')) $('crmVicTag').innerHTML = vicTagOf(c.id);
    /* What identifies the client rather than what describes them: who we
       write to and in which language, and who here owns the account. Each
       part is omitted when it is not known, so the line never stands in for
       a fact nobody has recorded. */
    var main = (state.contacts || []).filter(function (x) { return x.is_primary; })[0] ||
               (state.contacts || [])[0];
    var bits = [];
    if (main && main.lang && LANG_WORD[main.lang]) bits.push('Prefers ' + LANG_WORD[main.lang]);
    if (c.owner) bits.push('Person in charge: ' + c.owner);
    var meta = $('crmIdMeta');
    if (meta) {
      meta.textContent = bits.join('  ·  ');
      meta.hidden = !bits.length;
    }
    paintMonthLine(c);
  }

  /* ---- The record's Overview -------------------------------------------
     Overview used to be the Engagements list and, for a lead, nothing at all:
     the pane you land on had less on it than any other. It reads as an
     operational record now — flat titled sections divided by hairlines, the
     way the rest of this console draws a table — and every row in it comes
     from what the record has already loaded: the contacts, the service lines,
     the documents and the calls. No second read, no stored number, no
     invented metric, and a section that has nothing says so in one line
     rather than disappearing, because "no documents" is itself an answer. */
  function paintSummary() {
    var box = $('crmSummary');
    var c = state.client;
    if (!box || !c) return;

    /* In the tabs' order (2026-10-11): Calls and visits, then the contacts,
       the services and the letters; a section the reader may not open is
       not drawn, and one whose read was refused says so, never empty. */
    var secs = [ovQuotes(), ovTouches(), ovContact(c), ovServices(c), ovDocuments(c)].join('');
    box.innerHTML = secs ? '<div class="ovcard">' + secs + '</div>' : '';

    wireGo(box);
    paintRail(c);
  }

  /* One handler for every control that opens a pane, in the Overview and in
     the rail alike, so the address follows wherever somebody entered. */
  function wireGo(box) {
    Array.prototype.forEach.call(box.querySelectorAll('[data-go]'), function (b) {
      b.addEventListener('click', function () {
        showPane(b.getAttribute('data-go'), true);
        pushUrl();
      });
    });
  }

  var CHEV = '<svg class="ovgo-chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
    'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<path d="M9 18l6-6-6-6"/></svg>';
  /* The same pen the Overview's Contact details carries, so the one control
     that edits a value in place is one mark everywhere in the record. */
  var PEN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" ' +
    'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>';

  /* The glyphs the record's rows carry. One per kind of thing, neutral, drawn
     at 16px with the stroke every other mark in the console uses, so a list
     can be scanned by shape before it is read. */
  var RICON = {
    calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>',
    phone:    '<path d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2z"/>',
    pin:      '<path d="M12 21s7-6.5 7-12a7 7 0 0 0-14 0c0 5.5 7 12 7 12z"/><circle cx="12" cy="9" r="2.5"/>',
    person:   '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
    chat:     '<path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.6A8 8 0 1 1 21 12z"/>',
    mail:     '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 7 9 6 9-6"/>',
    file:     '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>',
    tag:      '<path d="M20 12l-8 8-9-9V4h7z"/><circle cx="7.5" cy="7.5" r="1"/>',
    image:    '<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="1.5"/><path d="M21 16l-5-5-9 9"/>',
    speaker:  '<path d="M3 10v4a1 1 0 0 0 1 1h2l5 4V5L6 9H4a1 1 0 0 0-1 1z"/><path d="M15 9a3 3 0 0 1 0 6"/>',
    link:     '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
    pencil:   '<path d="M4 20h4L19.5 8.5a2.1 2.1 0 0 0-3-3L5 17z"/><path d="M14.5 6.5l3 3"/>',
    dot:      '<circle cx="12" cy="12" r="3"/>'
  };
  function ico(name, cls) {
    return '<svg class="' + (cls || 'railico') + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
      'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (RICON[name] || RICON.dot) + '</svg>';
  }
  /* A call's glyph is its kind. */
  var KIND_ICON = { call: 'phone', visit: 'pin', meeting: 'person', whatsapp: 'chat', email: 'mail', note: 'chat' };

  /* A section is a heading and the one control that opens what it summarises,
     which is this portal's section head drawn flat rather than as a card. An
     Edit carries the pen and no chevron; a View all carries the chevron. */
  var OV_PART = { calls: 'clients.calls', contacts: 'clients.contacts', services: 'clients.services', documents: 'clients.documents' };
  function ovFailed(go, on) {
    state.ovFail = state.ovFail || {};
    if (Boolean(state.ovFail[go]) === on) return;
    state.ovFail[go] = on;
    paintSummary();
  }
  function ovSection(title, go, goWord, body, isEdit, part) {
    var need = part || OV_PART[go];
    if (need && !mayPart(need, 'view')) return '';
    if (state.ovFail && state.ovFail[go]) { body = ovNone('Could not load.'); goWord = 'View all'; isEdit = false; }
    /* A colleague who may only read the pane is offered the way to it, never
       Edit or Manage (audit, 2026-10-03). */
    if (goWord !== 'View all' && state.client &&
        !(bandMay(state.client.stage || 'lead', 'work') && mayPart('clients.' + go, 'work'))) {
      goWord = 'View all'; isEdit = false;
    }
    return '<section class="ovsec">' +
      '<div class="ovsec-head"><h3>' + esc(title) + '</h3>' +
      '<button class="btn btn-quiet btn-sm ovgo' + (isEdit ? ' is-edit' : '') + '" type="button" data-go="' + esc(go) + '">' +
        (isEdit ? ico('pencil', 'ovgo-pen') + esc(goWord) : esc(goWord) + CHEV) + '</button></div>' + body + '</section>';
  }
  /* Nothing there is a line, not a dashed box and not a sentence explaining
     what the section would have held. */
  function ovNone(text) { return '<p class="ovnone">' + esc(text) + '</p>'; }

  function ovRows(pairs) {
    return '<dl class="ovfacts">' + pairs.map(function (p) {
      return '<div><dt>' + esc(p[0]) + '</dt><dd>' + p[1] + '</dd></div>';
    }).join('') + '</dl>';
  }

  function ovContact(c) {
    var list = state.contacts || [];
    if (!list.length) {
      return ovSection('Contact details', 'contacts', 'Edit', ovNone('No contacts.'), true);
    }
    var m = list.filter(function (x) { return x.is_primary; })[0] || list[0];
    var rows = [['Main contact', '<b>' + esc((m.salutation ? m.salutation + ' ' : '') + (m.name || '')) + '</b>' +
      (m.role ? '<span class="ovmeta">' + esc(m.role) + '</span>' : '')]];
    var mUser = waHandle(m.whatsapp);
    if (m.phone) {
      /* A button, not a word run against the number with nothing between them:
         it is a thing to press and it is the same `.plink` the contact row
         and the client's own page already draw. */
      rows.push(['Phone', '<span class="ovreach"><a class="plink" href="tel:' + esc(m.phone) + '">' + esc(m.phone) + '</a>' +
        (mUser ? '' : waLink(m.whatsapp || m.phone, (state.client || {}).market)) + '</span>']);
    }
    if (mUser) {
      rows.push(['WhatsApp', '<span class="ovreach">@' + esc(mUser) +
        waLink(m.whatsapp, (state.client || {}).market) + '</span>']);
    }
    /* Every way to reach the person is the outlined contact chip, never an
       underlined word (the user, 2026-09-28). */
    if (m.email) rows.push(['Email', '<span class="ovreach"><a class="plink" href="mailto:' + esc(m.email) + '">' + esc(m.email) + '</a></span>']);
    if (m.lang && LANG_WORD[m.lang]) rows.push(['Language', 'Prefers ' + esc(LANG_WORD[m.lang])]);
    /* Person in charge is on the identity line above and is not repeated
       here; a record that states a fact twice is a record nobody reads. */
    if (c.enquiry) rows.push(['Enquiry', esc(c.enquiry)]);
    if (list.length > 1) {
      rows.push(['Other contacts', (list.length - 1) + (list.length === 2 ? ' person' : ' people')]);
    }
    return ovSection('Contact details', 'contacts', 'Edit', ovRows(rows), true);
  }

  /* The lines the client is paying for, or was quoted. Enquired lines are not
     shown here for the same reason the letter leaves them out: nobody has put
     a price on them yet. */
  function ovServices(c) {
    var all = state.services || [];
    var rows = all.filter(function (l) { return l.state === 'confirmed' || l.state === 'quoted'; });
    if (!rows.length) {
      return ovSection('Services', 'services', 'Manage services',
        ovNone(all.length ? all.length + (all.length === 1 ? ' line enquired.' : ' lines enquired.')
                          : 'No service lines.'));
    }
    var body = '<div class="ovtable">' +
      '<div class="ovhead ovrow-svc"><span>Service</span><span>Details</span><span>Amount</span><span>State</span></div>' +
      rows.slice(0, 5).map(function (l) {
        var st = SV_STATE[l.state] || ['', ''];
        return '<div class="ovrow ovrow-svc">' +
          '<span class="ovname">' + esc(l.label || '') + '</span>' +
          '<span class="ovdim">' + esc(termWord(l) || '') + '</span>' +
          '<span class="ovamt">' + esc(MON.money2(amountOf(l), MON.curOf(c))) + '</span>' +
          '<span><span class="tone ' + esc(st[1] || '') + '">' + esc(st[0] || l.state) + '</span></span>' +
        '</div>';
      }).join('') +
      (rows.length > 5 ? '<p class="ovmore">' + (rows.length - 5) + ' more</p>' : '') +
      '</div>';
    return ovSection('Services', 'services', 'Manage services', body);
  }

  /* The quotations come first while there are any: on a lead from the
     website they are what the record is about. */
  function ovQuotes() {
    var Q = window.ADspaceQuotes;
    if (!Q || !(state.quotes || []).some(function (q) { return !q.removed_at; })) return '';
    return ovSection('Quotations', 'services', 'View all', Q.overview(state.quotes, liveMap()), false, 'clients.quotes');
  }

  function ovDocuments() {
    var rows = state.documents || [];
    if (!rows.length) return ovSection('Letters', 'documents', 'View all', ovNone('None issued.'));
    var body = '<div class="ovtable">' +
      '<div class="ovhead ovrow-doc"><span>Reference</span><span>Type</span><span>Issued</span><span>State</span></div>' +
      rows.slice(0, 4).map(function (d) {
        return '<div class="ovrow ovrow-doc">' +
          '<span class="ovname">' + esc(d.number || '') + '</span>' +
          '<span class="ovdim">' + esc(DOC_WORD[d.kind] || d.kind || '') + '</span>' +
          '<span class="ovdim">' + esc(d.issued_at ? niceDate(d.issued_at) : '') + '</span>' +
          '<span>' + (d.voided_at ? '<span class="tone is-off">Void</span>' : '<span class="tone is-ok">Issued</span>') + '</span>' +
        '</div>';
      }).join('') +
      (rows.length > 4 ? '<p class="ovmore">' + (rows.length - 4) + ' more</p>' : '') +
      '</div>';
    return ovSection('Letters', 'documents', 'View all', body);
  }

  function ovTouches() {
    var rows = state.touches || [];
    if (!rows.length) return ovSection('Calls and visits', 'calls', 'View all', ovNone('Nothing logged.'));
    var body = '<ul class="ovlog">' + rows.slice(0, 3).map(function (t) {
      return '<li class="ovlog-row">' +
        '<span class="ovlog-ico">' + ico(KIND_ICON[t.kind] || 'chat', '') + '</span>' +
        '<span class="ovlog-main">' +
          '<span class="ovlog-kind">' + esc(KIND_WORD[t.kind] || t.kind || '') + '</span>' +
          (t.summary ? '<span class="ovlog-text">' + esc(t.summary) + '</span>' : '') +
        '</span>' +
        '<span class="ovlog-when">' + esc(niceDate(t.happened_at)) +
          (t.contact_name ? '<span class="ovmeta">with ' + esc(t.contact_name) + '</span>' : '') + '</span>' +
      '</li>';
    }).join('') + '</ul>';
    return ovSection('Calls and visits', 'calls', 'View all', body);
  }

  /* ---- The rail ---------------------------------------------------------
     What is true whichever pane is open. Every block leaves entirely when the
     data behind it is not there, so nothing on it is a placeholder. */
  /* A restricted account (2026-10-10; the user: "account restricted"): which
     platform, since when and why, red in the rail while it stands, set from
     the ⋯ and cleared in place. Filed under client.edited from and to. */
  /* VERY IMPORTANT CLIENTS (2026-10-15, the user). The tag and the ring
     come from the console's one read (`ADspaceAdmin.vic`); an admin, or a
     group given `clients.vic`, marks a client VIC from the ⋯ with an
     optional note and its since date, changes the date in place under Key
     dates, and removes it without a question, Undo where it happened. Every
     change goes through `client_vic_set`, filed from and to there. */
  function vicOf(id) { var A = window.ADspaceAdmin; return A && A.vic ? A.vic(id) : null; }
  function isVic(id) { return Boolean(vicOf(id)); }
  function vicTagOf(id, inRow) { var A = window.ADspaceAdmin; return A && A.vicTag ? A.vicTag(id, inRow) : ''; }
  var VIC_SAID = { denied: 'Not saved. Only an admin marks a client VIC.', 'not-found': 'Not saved. This client is no longer available.',
    'too-long': 'The note is 300 characters at most.', 'bad-date': 'VIC since is today or earlier.' };
  function paintVic(c) {
    var on = isVic(c.id), may = mayPart('clients.vic', 'work');
    $('crmVicSet').hidden = on || !may;
    $('crmVicOff').hidden = !on || !may;
    if ($('crmVicTag')) $('crmVicTag').innerHTML = vicTagOf(c.id);
    var mark = $('crmClientMark');
    if (mark) mark.classList.toggle('is-vic', on);
  }
  function setVic(c, on, note, since, then) {
    db.rpc('client_vic_set', { p_client: c.id, p_on: on, p_note: note, p_since: since || null }).then(function (r) {
      if (r.error) { msg('crmWorkMsg', /client_vic_set/.test(r.error.message || '') ? 'This needs a database update.' : r.error.message, 'err'); return; }
      var d = r.data || {};
      if (d.error) { msg('crmWorkMsg', VIC_SAID[d.error] || 'Not saved. The database refused the request.', 'err'); return; }
      var A = window.ADspaceAdmin;
      (A && A.vicReload ? A.vicReload() : Promise.resolve()).then(function () {
        if (!state.client || state.client.id !== c.id) return;
        paintVic(c);
        railDates(c);
        if (!$('crmListView').hidden) paintList();
        if (then) then(d);
      });
    }).catch(function (e) { msg('crmWorkMsg', String((e && e.message) || e), 'err'); });
  }
  function askVic(c) {
    var day = today();
    window.ADspaceConfirm.ask({
      title: 'Mark as VIC', go: 'Mark as VIC',
      body: c.name + ' will carry the VIC tag across the console. Clients never see it.',
      fields: [{ name: 's', label: 'VIC since', type: 'date', value: day, max: day, required: true },
               { name: 'n', label: 'Note', placeholder: 'Optional', required: false }],
      check: function (v) { return !v.s ? 'VIC since is required.' : v.s > day ? 'VIC since is today or earlier.' : String(v.n || '').length > 300 ? 'The note is 300 characters at most.' : ''; }
    }, function (v) {
      setVic(c, true, String(v.n || '').trim() || null, v.s, function () { msg('crmWorkMsg', 'Marked as VIC.', 'ok'); });
    });
  }
  function vicOff(c) {
    var was = vicOf(c.id);
    if (!was) return;
    setVic(c, false, null, null, function () {
      msg('crmWorkMsg', '', '');
      undoBar('VIC removed.', function () {
        setVic(c, true, was.note || null, ADspaceClock.day(was.since));
      });
    });
  }
  function wireVicSince(c) {
    var val = $('crmVicSinceVal'), pen = $('crmVicSinceEdit'), v = vicOf(c.id);
    if (!val || !pen || !v) return;
    pen.addEventListener('click', function () {
      ADspaceAsk.rename(val, pen, {
        type: 'date',
        value: ADspaceClock.day(v.since),
        label: 'VIC since',
        saveLabel: 'Save VIC since',
        save: function (day) {
          if (day > today()) { msg('crmSinceMsg', 'VIC since is today or earlier.', 'err'); railDates(c); return; }
          setVic(c, true, v.note || null, day, function () { msg('crmSinceMsg', 'Saved.', 'ok'); });
        }
      });
    });
  }
  var RESTRICT = [['instagram', 'Instagram'], ['facebook', 'Facebook'], ['tiktok', 'TikTok'], ['xhs', 'rednote'], ['other', 'Other account']];
  function restrictWord(k) { var r = RESTRICT.filter(function (x) { return x[0] === k; })[0]; return r ? r[1] : 'Account'; }
  function paintRestrict(c) {
    var box = $('crmRestrict');
    if (!box) return;
    var on = Boolean(c && c.restricted_since);
    var canWork = bandMay((c && c.stage) || 'lead', 'work');
    box.hidden = !on;
    // A lead holds no account of ours to restrict (MENU-1).
    $('crmRestrictSet').hidden = on || !canWork || bandKey((c && c.stage) || 'lead') === 'clients.leads';
    if (!on) return;
    $('crmRestrictWord').textContent = restrictWord(c.restricted_platform) + ' restricted';
    $('crmRestrictText').textContent = ['Since ' + niceDate(c.restricted_since), c.restricted_note].filter(Boolean).join(' · ');
    $('crmRestrictClear').hidden = !canWork;
    lastRule();
  }
  function saveRestrict(c, patch, words, after) {
    var was = { p: c.restricted_platform, s: c.restricted_since, n: c.restricted_note };
    db.from('clients').update(patch).eq('id', c.id).select('id').then(function (r) {
      if (r.error) { msg('crmWorkMsg', r.error.message, 'err'); return; }
      if (!(r.data || []).length) { msg('crmWorkMsg', 'Not saved. The database refused the request.', 'err'); return; }
      Object.keys(patch).forEach(function (k) { c[k] = patch[k]; });
      log('client.edited', c.name, words(was));
      paintRestrict(c);
      if (after) after(was);
    }).catch(function (e) { msg('crmWorkMsg', String((e && e.message) || e), 'err'); });
  }
  function askRestrict(c) {
    var day = today();
    window.ADspaceConfirm.ask({
      title: 'Mark account restricted', go: 'Save',
      fields: [{ name: 'p', label: 'Platform', choices: RESTRICT, value: 'instagram', half: true },
               { name: 's', label: 'Since', type: 'date', value: day, max: day, required: true, half: true },
               { name: 'n', label: 'Note', placeholder: 'Optional', required: false }],
      check: function (v) { return !v.s ? 'Since is required.' : v.s > day ? 'Since is today or earlier.' : String(v.n || '').length > 500 ? 'The note is 500 characters at most.' : ''; }
    }, function (v) {
      saveRestrict(c, { restricted_platform: v.p, restricted_since: v.s, restricted_note: String(v.n || '').trim() || null }, function () {
        return 'Account restricted: ' + restrictWord(v.p) + ' since ' + niceDate(v.s) + (String(v.n || '').trim() ? ' · ' + String(v.n).trim() : '');
      });
    });
  }
  if ($('crmRestrictClear')) $('crmRestrictClear').addEventListener('click', function () {
    var c = state.client;
    if (!c) return;
    saveRestrict(c, { restricted_platform: null, restricted_since: null, restricted_note: null }, function (was) {
      return 'Account restriction cleared: ' + restrictWord(was.p) + ' since ' + niceDate(was.s);
    }, function (was) {
      undoBar('Restriction cleared.', function () {
        saveRestrict(c, { restricted_platform: was.p, restricted_since: was.s, restricted_note: was.n }, function () {
          return 'Account restricted: ' + restrictWord(was.p) + ' since ' + niceDate(was.s);
        });
      }, $('crmRestrict'));
    });
  });
  /* The supplier this client also is (2026-10-18), a line under Details
     opening its record; read once a record is opened, at Suppliers View. */
  var sups = { id: null, rows: [] };
  function paintSuppliers(c, fresh) {
    var box = $('crmFacts');
    var draw = function () {
      if (sups.id !== c.id || !sups.rows.length || !box) return;
      var old = box.querySelector('.crm-sup');
      if (old) old.parentNode.removeChild(old);
      var row = document.createElement('div');
      row.className = 'crm-sup';
      row.innerHTML = '<dt>Supplier</dt><dd>' + sups.rows.map(function (x) {
        return '<button class="linkbtn" type="button" data-sup="' + esc(x.id) + '">' + esc(x.name ? x.code + ' · ' + x.name : x.code) + CHEV + '</button>';
      }).join(' ') + '</dd>';
      box.appendChild(row);
      Array.prototype.forEach.call(row.querySelectorAll('[data-sup]'), function (b) {
        b.addEventListener('click', function () {
          history.pushState(null, '', '?s=suppliers&supplier=' + encodeURIComponent(b.getAttribute('data-sup')));
          if (bridge.show) bridge.show('suppliers');
        });
      });
    };
    if (!mayPart('suppliers', 'view')) return;
    if (!fresh && sups.id === c.id) { draw(); return; }
    sups = { id: c.id, rows: [] };
    db.rpc('client_suppliers', { p_client: c.id }).then(function (r) {
      var d = r && r.data;
      if (sups.id !== c.id || !d || !d.ok) return;
      sups.rows = d.rows || [];
      draw();
    });
  }
  function paintRail(c) {
    railNext(c);
    railDone(c);
    railDates(c);
    railLog();
    wireGo($('crmNextBlock'));
    wireGo($('crmDoneBlock'));
    lastRule();
  }
  /* The rule under a block belongs to the last block actually drawn.
     `:last-child` counts a hidden sibling, and every block here leaves when
     the data behind it is not there. Recent activity arrives after the rest,
     so it sets the rule again when it does. */
  function lastRule() {
    var rail = document.querySelector('.rec-rail');
    if (!rail) return;
    var shown = Array.prototype.filter.call(rail.querySelectorAll('.railblock'),
      function (b) { return !b.hidden; });
    shown.forEach(function (b, i) { b.classList.toggle('is-last', i === shown.length - 1); });
  }

  /* The next action somebody actually wrote on a call, with the date they set,
     or failing that the step this record's own state implies. A written one
     wins, because a person decided it and a derivation did not. */
  function railNext(c) {
    var block = $('crmNextBlock'), box = $('crmNext');
    if (!block || !box) return;
    var open = (state.touches || []).filter(function (t) { return t.next_action && !t.done_at; })
      .sort(function (a, b) { return String(a.next_at || '9999') < String(b.next_at || '9999') ? -1 : 1; })[0];
    if (open) {
      var late = open.next_at && open.next_at < today();
      box.innerHTML = '<button class="railnext" type="button" data-go="calls">' + ico('calendar') +
        '<span class="railnext-text">' + esc(open.next_action) + '</span>' +
        (open.next_at ? '<span class="railnext-when' + (late ? ' is-late' : '') + '">' +
          esc((late ? 'Overdue · ' : 'Due ') + niceDate(open.next_at)) + '</span>' : '') +
        CHEV + '</button>';
      block.hidden = false;
      return;
    }
    var step = nextStep(c);
    if (!step) { block.hidden = true; box.innerHTML = ''; return; }
    box.innerHTML = '<button class="railnext" type="button" data-go="' + esc(step.go) + '">' + ico(step.icon || 'dot') +
      '<span class="railnext-text">' + esc(step.text) + '</span>' + CHEV + '</button>';
    block.hidden = false;
  }

  /* The one thing this record needs next, read off the same gate, stage and
     lines every other part of the record reads. The line states what is true;
     the control opens the pane that changes it. */
  function nextStep(c) {
    var stage = c.stage || 'lead';
    var missing = billingMissing(c);
    var quoting = (state.services || []).filter(function (l) { return l.state === 'quoted'; }).length;
    var confirmed = (state.services || []).filter(function (l) { return l.state === 'confirmed'; }).length;
    var issued = (state.documents || []).filter(function (d) { return !d.voided_at; }).length;

    if (!state.contacts.length) return { text: 'No contact on the record.', go: 'contacts', icon: 'person' };
    if (stage === 'lead') return { text: 'No call or visit logged.', go: 'calls', icon: 'phone' };
    if (!(state.services || []).length) return { text: 'No service lines.', go: 'services', icon: 'tag' };
    if (quoting && !issued) {
      return { text: quoting + (quoting === 1 ? ' line' : ' lines') + ' to quote, no letter issued.', go: 'documents', icon: 'file' };
    }
    if (stage !== 'active' && stage !== 'paused' && stage !== 'past' && missing.length) {
      return { text: missing.length + (missing.length === 1 ? ' billing field' : ' billing fields') +
        ' before Active.', go: 'billing', icon: 'file' };
    }
    if (stage === 'proposal' && issued) return { text: 'Letter with the client, unsigned.', go: 'documents', icon: 'file' };
    if (stage === 'active' && !confirmed) return { text: 'Active with no confirmed line.', go: 'services', icon: 'tag' };
    return null;
  }

  /* How much of the record is filled in. A bar rather than a figure, because
     the question anybody actually asks is whether this is nearly done, and
     the line under it names what is still missing so the bar is never the
     only thing said. Counted over what the record genuinely tracks. */
  function railDone(c) {
    var block = $('crmDoneBlock'), box = $('crmDone');
    if (!block || !box) return;
    var parts = [
      ['Billing', BILLING_REQUIRED.length - billingMissing(c).length, BILLING_REQUIRED.length],
      ['Brand profile', BRAND.filter(function (f) { return c[f[1]]; }).length + (c.brand_notes ? 1 : 0), BRAND.length + 1],
      ['Contacts', Math.min((state.contacts || []).length, 1), 1],
      ['Services', Math.min((state.services || []).length, 1), 1]
    ];
    var done = parts.reduce(function (t, p) { return t + p[1]; }, 0);
    var all = parts.reduce(function (t, p) { return t + p[2]; }, 0);
    var pct = all ? Math.round(done / all * 100) : 0;
    var short = parts.filter(function (p) { return p[1] < p[2]; });
    box.innerHTML =
      '<p class="railpct"><b>' + pct + '% complete</b><span>' + done + ' of ' + all + '</span></p>' +
      '<span class="railbar"><span class="railbar-fill' + (pct >= 100 ? ' is-done' : '') + '" style="width:' + pct + '%"></span></span>' +
      (short.length
        ? '<button class="railmiss" type="button" data-go="' +
            (short[0][0] === 'Billing' ? 'billing' : short[0][0] === 'Brand profile' ? 'brand' :
             short[0][0] === 'Contacts' ? 'contacts' : 'services') + '">' +
            '<span>' + esc('Still to fill in: ' + short.map(function (p) { return p[0].toLowerCase(); }).join(', ') + '.') + '</span>' +
            CHEV + '</button>'
        : '<p class="ovnone">Nothing outstanding.</p>');
    block.hidden = false;
  }

  /* Every date and every duration the record holds, in one block: the stage
     journey and its turnarounds above a rule, then the dates themselves. A
     dated row is left out when its date is not there, because a list of three
     dates where two say "Not set" is a list that has stopped being read. */
  function railDates(c) {
    var block = $('crmDatesBlock'), box = $('crmTimeline');
    if (!block || !box) return;
    var live = (state.touches || []).filter(function (t) { return !t.archived_at; });
    var last = live.map(function (t) { return t.happened_at; }).filter(Boolean).sort().pop();

    /* The stage it is in now is the one running, so its duration reads "so
       far" and carries the overdue mark where the stage has run past its
       limit — which is why Account status no longer states a clock of its
       own: the stage select in the head says where the record is, and this
       says for how long. */
    /* Every stage's date is filled in by the stage moves and stays the
       person's to correct (the user, 2026-09-25: a client keyed in today
       who has been a client since April read "Lead, today"). The pen sits
       beside the duration, and the duration is counted from the date as it
       now stands. */
    /* The dates are corrected at the record's own band at Work, as every
       write to it is (`client_scope_guard`); a View group reads them. */
    var pens = bandMay(c.stage || 'lead', 'work');
    var trip = journeyOf(c).map(function (s) {
      var span = s.days === 0 ? (s.now ? 'Today' : 'Same day') : spanWord(s.days);
      var over = s.now && isStale(c);
      return '<div class="tl-row tl-stage' + (s.now ? ' is-now' : '') + '">' +
        '<span class="tl-lead"><span class="tl-what">' + esc(s.word) + '</span>' +
          '<span class="tl-when" data-stage-val="' + s.i + '">' + esc(niceDate(s.at)) + '</span>' +
          (s.reason && leaveWord(s.reason)
            ? (pens
              ? '<button class="tl-when tl-why tl-why-btn" type="button" data-why-pen="' + s.i + '" aria-label="Change the reason for ' + esc(s.word) + '">' + esc(leaveWord(s.reason)) + PEN + '</button>'
              : '<span class="tl-when tl-why">' + esc(leaveWord(s.reason)) + '</span>')
            : '') + '</span>' +
        '<span class="tl-end"><span class="tl-span' + (over ? ' is-late' : '') + '">' +
          esc(span + (s.now && s.days > 0 ? ' so far' : '') + (over ? ' · Overdue' : '')) + '</span>' +
          (pens ? '<button class="tl-pen" type="button" data-stage-pen="' + s.i + '" aria-label="Edit the ' + esc(s.word) + ' date">' + PEN + '</button>' : '') +
        '</span></div>';
    }).join('');

    var vicNow = vicOf(c.id);
    var dates = [
      ['Client since', c.created_at, true],
      ['VIC since', vicNow && vicNow.since, 'vic'],
      ['Last contact', last, false]
    ].filter(function (r) { return r[1]; }).map(function (r) {
      /* The next follow up is Next action's own date, said there once. */
      /* Client since is the one date here a person may correct, so the value
         itself is what opens: a field growing out of the thing it changes,
         never a second field and a Save button below the list. */
      return '<div class="tl-row tl-date">' +
        '<span class="tl-lead"><span class="tl-what">' + esc(r[0]) + '</span>' +
          '<span class="tl-when"' +
            (r[2] === 'vic' ? ' id="crmVicSinceVal"' : r[2] ? ' id="crmSinceVal"' : '') + '>' +
            esc(niceDate(r[1])) + '</span></span>' +
        (r[2] === 'vic'
          ? (mayPart('clients.vic', 'work') ? '<button class="tl-pen" id="crmVicSinceEdit" type="button" aria-label="Edit VIC since">' + PEN + '</button>'
              : '<span class="tl-span"></span>')
          : r[2] && pens ? '<button class="tl-pen" id="crmSinceEdit" type="button" aria-label="Edit client since">' + PEN + '</button>'
              : '<span class="tl-span"></span>') +
        '</div>';
    }).join('');

    if (!trip && !dates) { block.hidden = true; box.innerHTML = ''; return; }
    box.innerHTML = trip + (trip && dates ? '<div class="tl-rule"></div>' : '') + dates;
    wireSince(c);
    wireVicSince(c);
    wireStages(c);
    wireWhy(c);
    block.hidden = false;
  }

  /* The day a stage began, as the log keeps it. A day typed is midnight UTC
     of that day, the same as Client since. */
  function logOf(c) {
    var log = (c.stage_log || []).slice();
    if (!log.length && c.stage_since) log = [{ stage: c.stage || 'lead', at: c.stage_since }];
    /* A move's reason and note ride with it through a date's correction. */
    return log.map(function (x) {
      var o = { stage: x.stage, at: x.at };
      if (x.reason) o.reason = x.reason;
      if (x.note) o.note = x.note;
      return o;
    });
  }
  function dayOf(at) { return at ? ADspaceClock.day(at) : ''; }

  /* One save for the dates the timeline holds: the stage log, the current
     stage's start (the last entry) and Client since, which is the first
     stage's start, so the two can never disagree. The order is checked
     before anything is sent: a stage cannot begin before the one before it
     or after the one after it, and no date is in the future. */
  /* The timeline is written whole from the copy on screen, so it is written
     only over the row as read (`clients_touch` stamps updated_at): a move
     made meanwhile is read again, never overwritten. A refusal at the row's
     own policy reads the same way, since nothing tells the two apart. */
  function timelineOf(c) {
    return JSON.stringify([c.stage, c.stage_since, c.stage_log || null, c.created_at, c.stage_reason || null, c.stage_note || null]);
  }
  function readAgain(c, retry) {
    db.from('clients').select(API.CLIENT_COLS).eq('id', c.id).maybeSingle().then(function (r) {
      return r.data ? API.withBilling(r.data).then(function () { return r; }) : r;
    }).then(function (r) {
      /* Only another column moved (a billing save, a rename): the timeline
         is as it was read, so the write goes again, once. */
      if (r.data && retry && timelineOf(r.data) === timelineOf(c)) {
        c.updated_at = r.data.updated_at; retry(); return;
      }
      if (r.data) {
        Object.assign(c, r.data);
        var mine = state.clients.filter(function (x) { return x.id === c.id; })[0];
        if (mine && mine !== c) Object.assign(mine, r.data);
        if (state.client && state.client.id === c.id) openClient(c);
      }
      msg('crmSinceMsg', 'Not saved. This changed since it was opened, and has been read again.', 'err');
    }).catch(function () { msg('crmSinceMsg', 'Not saved. This changed since it was opened.', 'err'); });
  }
  function saveDates(c, list, created, what) {
    var days = list.map(function (x) { return dayOf(x.at); });
    for (var i = 1; i < days.length; i++) {
      if (days[i] < days[i - 1]) {
        return 'The ' + stageWord(list[i].stage)[1] + ' date cannot be before the ' + stageWord(list[i - 1].stage)[1] + ' date.';
      }
    }
    if (days.concat([dayOf(created)]).some(function (d) { return d > today(); })) return 'A date cannot be in the future.';
    var row = { stage_log: list, stage_since: list.length ? list[list.length - 1].at : c.stage_since, created_at: created };
    var send = function (again) {
    db.from('clients').update(row).eq('id', c.id).eq('updated_at', c.updated_at).select('id, updated_at').then(function (r) {
      if (r.error) { msg('crmSinceMsg', r.error.message, 'err'); return; }
      if (!(r.data || []).length) { readAgain(c, again ? null : function () { send(true); }); return; }
      c.updated_at = r.data[0].updated_at;
      c.stage_log = list; c.stage_since = row.stage_since; c.created_at = created;
      var mine = state.clients.filter(function (x) { return x.id === c.id; })[0];
      if (mine) { mine.stage_log = list; mine.stage_since = row.stage_since; mine.created_at = created; }
      railDates(c);
      msg('crmSinceMsg', 'Saved.', 'ok');
      log('client.edited', c.name, what);
    });
    };
    send(false);
    return null;
  }
  /* The reason a client was paused or ended is corrected where it is read
     (the user, 2026-10-08: "the reason should be able to change after"): the
     move's own log entry, and while it is the stage the client is in, the
     client's reason and note too. No move, so the clock is not touched. */
  function wireWhy(c) {
    Array.prototype.forEach.call(document.querySelectorAll('#crmTimeline [data-why-pen]'), function (btn) {
      var i = Number(btn.getAttribute('data-why-pen'));
      btn.addEventListener('click', function () {
        var list = logOf(c), was = list[i];
        if (!was) return;
        var word = stageWord(was.stage)[1];
        window.ADspaceConfirm.ask({
          title: 'Reason for ' + word,
          go: 'Save',
          fields: [
            { name: 'reason', label: 'Reason', choices: LEAVE, value: was.reason || '' },
            { name: 'note', label: 'Note', required: false, placeholder: 'Optional', value: was.note || '' }
          ]
        }, function (v) {
          var note = String(v.note || '').trim() || null;
          if (v.reason === was.reason && note === (was.note || null)) return;
          list[i] = Object.assign({}, was, { reason: v.reason });
          if (note) list[i].note = note; else delete list[i].note;
          var row = { stage_log: list };
          var current = i === list.length - 1 && was.stage === c.stage;
          if (current) { row.stage_reason = v.reason; row.stage_note = note; }
          var send = function (again) {
          db.from('clients').update(row).eq('id', c.id).eq('updated_at', c.updated_at).select('id, updated_at').then(function (r) {
            if (r.error) { msg('crmSinceMsg', r.error.message, 'err'); return; }
            if (!(r.data || []).length) { readAgain(c, again ? null : function () { send(true); }); return; }
            c.updated_at = r.data[0].updated_at;
            c.stage_log = list;
            if (current) { c.stage_reason = v.reason; c.stage_note = note; }
            var mine = state.clients.filter(function (x) { return x.id === c.id; })[0];
            if (mine) { mine.stage_log = list; if (current) { mine.stage_reason = v.reason; mine.stage_note = note; } }
            railDates(c);
            msg('crmSinceMsg', 'Saved.', 'ok');
            log('client.edited', c.name, window.ADspaceRecords.changes(
              { reason: leaveWord(was.reason), note: was.note || '' },
              { reason: leaveWord(v.reason), note: note || '' },
              [['reason', 'Reason for ' + word], ['note', word + ' note']]));
          }).catch(function () { msg('crmSinceMsg', 'Not saved. Please try again.', 'err'); });
          };
          send(false);
        });
      });
    });
  }
  function wireStages(c) {
    Array.prototype.forEach.call(document.querySelectorAll('#crmTimeline [data-stage-pen]'), function (pen) {
      var i = Number(pen.getAttribute('data-stage-pen'));
      var val = document.querySelector('#crmTimeline [data-stage-val="' + i + '"]');
      if (!val) return;
      pen.addEventListener('click', function () {
        var log = logOf(c);
        var word = stageWord(log[i].stage)[1];
        ADspaceAsk.rename(val, pen, {
          type: 'date',
          value: dayOf(log[i].at),
          label: word + ' date',
          saveLabel: 'Save the ' + word + ' date',
          save: function (day) {
            var at = day + 'T00:00:00.000Z';
            log[i].at = at;
            /* The first stage began when the client did. */
            var created = i === 0 ? at : c.created_at;
            var bad = saveDates(c, log, created, word + ' from ' + niceDate(at));
            if (bad) { msg('crmSinceMsg', bad, 'err'); railDates(c); }
          }
        });
      });
    });
  }

  /* Imported records may predate this portal. Their real start date is an
     operational fact, so it can be corrected without falsifying the stage
     clock or inventing a second stored date. The value on the row becomes the
     field, and the pen beside it becomes the tick that saves it, which is the
     shape `js/ask.js` gives every value already on the screen. */
  function wireSince(c) {
    var val = $('crmSinceVal'), pen = $('crmSinceEdit');
    if (!val || !pen) return;
    pen.addEventListener('click', function () {
      ADspaceAsk.rename(val, pen, {
        type: 'date',
        value: c.created_at ? dayOf(c.created_at) : '',
        label: 'Client since',
        saveLabel: 'Save client since',
        /* Client since is the first stage's start, so moving it moves that
           stage with it and the durations are counted from the new day. */
        save: function (day) {
          var created = day + 'T00:00:00.000Z';
          var log = logOf(c);
          if (log.length) log[0].at = created;
          var bad = saveDates(c, log, created, 'Client since ' + niceDate(created));
          if (bad) { msg('crmSinceMsg', bad, 'err'); railDates(c); }
        }
      });
    });
  }

  /* The last few entries the portal wrote about this client. The whole record
     is one tab away; this is the excerpt, and it draws nothing at all until
     that read has landed. */
  function railLog() {
    var block = $('crmRailLogBlock'), box = $('crmRailLog');
    if (!block || !box) return;
    if (!(state.log || []).length) { block.hidden = true; box.innerHTML = ''; lastRule(); return; }
    window.ADspaceRecords.paint(box, (state.log || []).map(recordOf), { limit: 3 });
    block.hidden = false;
    lastRule();
  }

  /* A handle is what is stored; the address is each platform's own shape. A
     value already pasted as a full URL is left as it is. */
  var PROFILE_AT = {
    handle_ig:     'https://instagram.com/',
    handle_fb:     'https://facebook.com/',
    handle_tiktok: 'https://tiktok.com/@',
    handle_xhs:    'https://www.xiaohongshu.com/user/profile/'
  };
  function profileUrl(field, value) {
    var v = String(value || '').trim();
    if (/^https?:\/\//i.test(v)) return v;
    return (PROFILE_AT[field] || 'https://') + v.replace(/^@/, '');
  }

  function linkChip(href, label, external) {
    var url = /^https?:\/\/|^tel:|^mailto:/.test(href) ? href : 'https://' + href.replace(/^@/, '');
    return '<a class="plink" href="' + esc(url) + '"' +
      (external ? ' target="_blank" rel="noopener"' : '') + '>' + esc(label) + '</a>';
  }

  $('crmBack').addEventListener('click', function () {
    state.client = null;
    showList();          // the list and the next actions above it, together
  });
  /* The gate is a fixed block, so it is wired once; the rail's other controls
     are redrawn on every paint and wired by `wireGo` each time. */
  $('crmGate').addEventListener('click', function () {
    if (!this.getAttribute('data-go')) return;
    showPane('billing');
    pushUrl();
  });

  /* ---- Deleting a client ---------------------------------------------------
     Paused and Past are how a client leaves the working list, and that is the
     everyday act. This is the other one: a lead keyed in twice, or a record
     that should never have existed. It takes everything hanging off the
     client with it, so the sheet counts what will go from the record already
     loaded rather than describing it in the abstract, and the name is typed
     back because a client carries no reference to type. `can_remove` draws
     the menu item and `delete_client` checks the same permission again when
     the button is pressed. */
  var codeNeeded = null;                 // whether a delete code is set at all

  function delCount(n, one, many) {
    return n ? n + ' ' + (n === 1 ? one : (many || one + 's')) : '';
  }

  function openClientDelete() {
    var c = state.client;
    if (!c) return;
    var gone = [
      delCount((state.contacts || []).filter(function (x) { return !x.archived_at; }).length, 'contact'),
      delCount((state.services || []).length, 'service line'),
      delCount((state.documents || []).length, 'letter'),
      delCount((state.touches || []).length, 'call or visit', 'calls and visits')
    ];
    /* What Engagements read on opening, counted where it was (CLI-8). */
    var held = window.ADspaceEngage && window.ADspaceEngage.held ? window.ADspaceEngage.held(c.id) : {};
    gone = gone.concat([
      delCount(held.content, 'content month'),
      delCount(held.sets, 'content set'),
      delCount(held.scripts, 'video script'),
      delCount(held.camps, 'campaign'),
      delCount(held.reports != null ? held.reports : held.finished, 'report')
    ]).filter(Boolean);
    /* The one question every Delete asks (2026-10-10): what goes, the name
       typed back, and the delete code where one is set, the question kept
       open on a refusal. Whether a code is set is not a secret; it is asked
       once and remembered. */
    var ask = function () {
      var fields = [{ name: 'name', label: 'Type the client name to confirm', placeholder: c.name, match: String(c.name || '').trim(),
        need: 'Type the client name to confirm.', mismatch: 'The name does not match.' }];
      if (codeNeeded) fields.push({ name: 'code', label: 'Delete code', type: 'password', need: 'The delete code is required.' });
      window.ADspaceConfirm.ask({
        title: 'Delete',
        body: 'Deleting ' + c.name + ' removes the record and everything filed under it' +
          (gone.length ? ': ' + gone.join(', ') + ', and everything in them' : '') +
          '. This is immediate and cannot be undone.',
        go: 'Delete', tone: 'danger', fields: fields, wait: true
      }, function (v) {
        return db.rpc('delete_client', { p_client: c.id, p_code: codeNeeded ? v.code : null }).then(function (r) {
          if (r.error) return r.error.message;
          var out = r.data;
          if (out === 'wrong-code') return 'That delete code is not right.';
          if (out === 'not-found') return 'That client is no longer there.';
          if (out !== 'deleted') return String(out || 'Unable to delete.');
          /* `delete_client` files the deletion itself (audit R1). */
          state.client = null;
          showList();
          return '';
        });
      });
    };
    if (codeNeeded === null) {
      db.rpc('delete_code_set').then(function (r) { codeNeeded = !!(r && r.data); ask(); })
        .catch(function () { codeNeeded = false; ask(); });
    } else ask();
  }

  (function wireClientMenu() {
    var take = $('crmTake');
    if (take) take.addEventListener('click', function () { takeLead(state.client); });
    var btn = $('crmClientMenuBtn'), menu = $('crmClientMenu');
    if (btn && menu) {
      btn.addEventListener('click', function (e) {
        e.stopPropagation();
        var open = menu.hidden;
        menu.hidden = !open;
        btn.setAttribute('aria-expanded', String(open));
        if (open && window.ADspaceMenu) ADspaceMenu.place(btn, menu);
      });
      menu.addEventListener('click', function (e) {
        var it = e.target.closest && e.target.closest('[data-a]');
        if (!it) return;
        menu.hidden = true;
        btn.setAttribute('aria-expanded', 'false');
        var a = it.getAttribute('data-a');
        if (a === 'delclient') { openClientDelete(); return; }
        if (a === 'feedback') { askFeedback(state.client); return; }
        if (a === 'restrict') { askRestrict(state.client); return; }
        if (a === 'vic') { askVic(state.client); return; }
        if (a === 'vicoff') { vicOff(state.client); return; }
        if (a === 'edit') {
          if (!state.clients.length) loadClients();
          openForm(state.client);
        }
      });
      document.addEventListener('click', function () {
        if (!menu.hidden) { menu.hidden = true; btn.setAttribute('aria-expanded', 'false'); }
      });
      // onScroll takes the shut itself: a scroll that has really moved the
      // anchoring button is the one that closes an open menu.
      if (window.ADspaceMenu) ADspaceMenu.onScroll(function () {
        if (menu.hidden) return;
        menu.hidden = true;
        btn.setAttribute('aria-expanded', 'false');
      });
    }

  })();

  /* Take a lead nobody is in charge of: Person in charge becomes the person
     pressing, filed as any other edit of it. */
  /* The feedback template to the client's main contact, in the composer
     every record shares; it asks before it sends. */
  function askFeedback(c) {
    window.ADspaceWhatsApp.compose({ purpose: 'feedback', clientId: c.id, opener: $('crmClientMenuBtn'),
      onSent: function (d, line) { msg('crmWorkMsg', line, 'ok'); } });
  }
  function takeLead(c) {
    var me = bridge.me && bridge.me();
    if (!c || !me || !me.name) return;
    db.from('clients').update({ owner: me.name }).eq('id', c.id).select('id').then(function (r) {
      if (r.error) { msg('crmWorkMsg', r.error.message, 'err'); return; }
      if (!r.data || !r.data.length) { msg('crmWorkMsg', 'Not saved. The database refused the request.', 'err'); return; }
      c.owner = me.name;
      var mine = state.clients.filter(function (x) { return x.id === c.id; })[0];
      if (mine) mine.owner = me.name;
      log('client.edited', c.name, 'Person in charge: not set → ' + me.name);
      msg('crmWorkMsg', 'Taken.', 'ok');
      openClient(c);
    }).catch(function () { msg('crmWorkMsg', 'Not saved. Please try again.', 'err'); });
  }

  /* The one rule with teeth: nobody becomes active until they can be
     invoiced. The select goes back and the record opens on what is missing. */
  $('crmClientStage').addEventListener('change', function () {
    var c = state.client, to = this.value, was = c.stage || 'lead';
    if (to === was) return;
    if (to === 'active') {
      var missing = billingMissing(c);
      if (missing.length) {
        this.value = was;
        /* Active was asked for: the Billing sheet's Save carries on into
           the move once nothing is missing (2026-10-20, CLI-6). */
        gateBilling(missing, 'Active', this, function () { state.toActive = c.id; });
        return;
      }
    }
    /* Paused and Past say why, and say what work is still open for the
       client: it shows as urgent delivery in My Work from the move on. The
       select holds the stage it had until the answer comes. */
    if (to === 'paused' || to === 'past') {
      this.value = was;
      askLeave(c, to, function (why) { moveStage(c, to, why); });
      return;
    }
    /* A Client ID is given when a client turns Active (the user,
       2026-10-18: a lead may come to no deal): the move asks for it, the
       next number offered, and both go in one write. */
    if (to === 'active' && !String(c.client_code || '').trim()) {
      this.value = was;
      askCode(c, function (code) { return moveStage(c, to, null, { client_code: code, inSheet: true }); });
      return;
    }
    moveStage(c, to, null);
  });
  /* The next AC number across every client, read from the database (a
     colleague who sees their own clients alone cannot count the rest);
     where it cannot answer, the clients this page holds. */
  function nextClientCode(then) {
    var local = function () {
      var n = 0, w = 3;
      (state.clients || []).forEach(function (x) {
        var m = /^AC(\d+)$/.exec(x.client_code || '');
        if (m && Number(m[1]) >= n) { n = Number(m[1]); w = Math.max(3, m[1].length); }
      });
      var d = String(n + 1);
      while (d.length < w) d = '0' + d;
      return 'AC' + d;
    };
    db.rpc('client_code_next').then(function (r) {
      then(r && !r.error && typeof r.data === 'string' ? r.data : local());
    }).catch(function () { then(local()); });
  }
  function askCode(c, then) {
    nextClientCode(function (next) {
      window.ADspaceConfirm.ask({
        title: 'Move to Active?',
        body: 'An Active client holds a Client ID.',
        go: 'Move', wait: true,
        fields: [{ name: 'code', label: 'Client ID', value: next, required: true }],
        check: function (v) {
          var code = codeOf(v.code);
          if (!CODE_OK.test(code)) return 'A Client ID is 2 to 12 letters or digits, with no spaces or slashes.';
          var taken = (state.clients || []).filter(function (x) { return x.id !== c.id && x.client_code === code; })[0];
          return taken ? 'That Client ID is already used by another client.' : '';
        }
      }, function (v) { return then(codeOf(v.code)); });
    });
  }
  function askLeave(c, to, then) {
    var word = stageWord(to)[1];
    var ask = function (n) {
      window.ADspaceConfirm.ask({
        title: 'Move to ' + word + '?',
        body: n ? n + (n === 1 ? ' task is' : ' tasks are') + ' still open. ' + (n === 1 ? 'It shows' : 'They show') + ' as urgent delivery in My Work.' : '',
        go: 'Move',
        fields: [
          { name: 'reason', label: 'Reason', choices: [['', 'Choose']].concat(LEAVE), need: 'Choose a reason.' },
          { name: 'note', label: 'Note', required: false, placeholder: 'Optional' }
        ]
      }, function (v) { then({ reason: v.reason, note: v.note || null }); });
    };
    db.rpc('client_open_tasks', { p_client: c.id }).then(function (r) {
      ask(r && !r.error && typeof r.data === 'number' ? r.data : 0);
    }).catch(function () { ask(0); });
  }
  function moveStage(c, to, why, also) {
    var row = { stage: to };
    if (why) { row.stage_reason = why.reason; row.stage_note = why.note; }
    if (also && also.client_code) row.client_code = also.client_code;
    /* `also.inSheet`: the question that asked the Client ID is still open,
       so a refusal is said there, with what was typed kept, and nothing else
       moves (a Client ID another client holds, which this colleague's own
       list may not show). */
    var inSheet = also && also.inSheet;
    return db.from('clients').update(row).eq('id', c.id).select('id').then(function (r) {
      if (r.error) {
        var em = r.error.message || '';
        var said = /stage-reason/.test(em) ? 'Choose a reason to move to ' + stageWord(to)[1] + '.'
          : /active-needs-code/.test(em) ? 'An Active client needs a Client ID.' : saveWord(em);
        if (inSheet) return said;
        msg('crmWorkMsg', said, 'err');
        openClient(c); return '';
      }
      if (!(r.data || []).length) {
        if (inSheet) return 'Not saved. The database refused the request.';
        msg('crmWorkMsg', 'Not saved. The database refused the request.', 'err'); openClient(c); return '';
      }
      // Read before the local copy moves on: this is how long the stage being
      // left actually ran, which is the fact worth keeping.
      /* A move on the day the stage began reads "the same day", never "after
         the same day" (2026-10-15, audit CLI-8). */
      var spent = daysSince(c.stage_since) === 0 ? 'the same day' : 'after ' + (ageWord(c) || 'no time');
      c.stage = to;
      var mine = state.clients.filter(function (x) { return x.id === c.id; })[0];
      if (mine) mine.stage = to;
      if (row.client_code) {
        c.client_code = row.client_code;
        if (mine) mine.client_code = row.client_code;
        log('client.edited', c.name, 'Client ID: not set → ' + row.client_code);
      }
      log('client.stage', c.name, stageWord(to)[1] + ' ' + spent +
        (why ? ' · ' + leaveWord(why.reason) + (why.note ? ': ' + why.note : '') : ''));
      // The clock and the history are stamped by the trigger, so the row has
      // to come back from the database rather than be guessed at here.
      /* Active asks whether the main contact gets the client portal, the
         invitation ticked (2026-10-26): nothing else leads a new client
         there. Asked, never switched on by itself. */
      var invitee = to === 'active' ? mainContact() : null;
      refreshClient(c, function () {
        openClient(c);
        if (also && also.after) requestAnimationFrame(also.after);
        if (invitee && invitee.email && !invitee.portal_access && mayPart('clients.contacts', 'work')) askPortal(invitee, true);
      });
      return '';
    }).catch(function () {
      if (inSheet) return 'Not saved. Please try again.';
      msg('crmWorkMsg', 'Not saved. Please try again.', 'err'); openClient(c); return '';
    });
  }

  // ---- Billing and notes --------------------------------------------------
  /* The gate, stated once, with what is missing; the fold's ring; the
     billing contact picked from the client's contacts. Painted again when
     the contacts arrive, since the contact is one of them. */
  function paintBilling(c) {
    var missing = billingMissing(c);
    /* Below Work on the Billing part the fields are read and not typed in;
       the database refuses the save anyway (`clients_billing_guard`). */
    var ro = !mayPart('clients.billing', 'work');
    BILLING.forEach(function (f) { if ($(f[0])) $(f[0]).disabled = ro; });
    $('crmSstApplies').disabled = ro;
    /* Drawn only while something is missing on a record that is not yet
       Active: a gate with nothing behind it is not a gate. It opens Billing
       where the person can see that pane, and is plain text where they cannot. */
    var gate = $('crmGate');
    gate.hidden = !missing.length || c.stage === 'active' || c.stage === 'past';
    if (maySeeBilling()) gate.setAttribute('data-go', 'billing'); else gate.removeAttribute('data-go');
    $('crmGateText').textContent = 'Required before Active: ' + missing.join(', ') + '.';
    $('crmBillSummary').innerHTML = ring(BILLING_REQUIRED.length - missing.length, BILLING_REQUIRED.length);
    paintBillRead(c);
    var main = mainContact(), pick = billContact(c);
    $('crmBillContact').innerHTML = '<option value="">' + (main ? 'Main contact · ' + esc((main.salutation ? main.salutation + ' ' : '') + main.name) : 'None') + '</option>' +
      (state.contacts || []).filter(function (ct) { return !ct.archived_at && !(main && ct.id === main.id); }).map(function (ct) {
        return '<option value="' + esc(ct.id) + '"' + (pick && pick.id === ct.id && !(main && pick.id === main.id) ? ' selected' : '') + '>' +
          esc((ct.salutation ? ct.salutation + ' ' : '') + ct.name) + '</option>';
      }).join('');
    var live = (state.contacts || []).some(function (ct) { return !ct.archived_at; });
    $('crmBillAddContact').hidden = live || !mayPart('clients.contacts', 'work');
  }
  $('crmBillAddContact').addEventListener('click', function () {
    $('crmBillCancel').click();
    showPane('contacts'); pushUrl();
    openContact(null);
  });

  /* Read first. The pane states what is held in the three groups the sheet
     edits, in the order an invoice reads them; a required value that is
     missing says so in red, an optional one takes the mute dash every other
     empty cell in the console takes. */
  function readGroup(title, rows) {
    return '<section class="readgroup"><h4 class="fsec-h">' + esc(title) + '</h4><dl class="ovfacts">' +
      rows.map(function (r) {
        var v = r[1];
        var dd = v ? '<dd' + (r[3] ? ' class="is-pre"' : '') + '>' + v + '</dd>'
          : r[2] ? '<dd class="is-missing">Required</dd>' : '<dd class="is-empty">—</dd>';
        return '<div><dt>' + esc(r[0]) + '</dt>' + dd + '</div>';
      }).join('') + '</dl></section>';
  }
  function paintBillRead(c) {
    var box = $('crmBillRead');
    if (!box) return;
    var pick = billContact(c);
    var t = function (k) { return c[k] ? esc(c[k]) : ''; };
    box.innerHTML =
      readGroup('Company', [['Registered name', t('legal_name'), true]]) +
      readGroup('Registration and tax', [
        ['Business registration no.', t('company_no'), true],
        ['Old registration no.', t('company_no_old')],
        ['TIN', t('tin')],
        ['SST registration no.', t('sst_no')],
        ['SST on quotes', c.sst_applies === false ? 'Not charged' : 'Charged, ' + esc(MON.taxLabel())]
      ].concat(String(c.market || '').toUpperCase() === 'SG' ? [['Bill in', c.bill_sgd ? 'S$' : 'RM']] : [])) +
      readGroup('Billing contact and address', [
        ['Billing contact', pick ? esc((pick.salutation ? pick.salutation + ' ' : '') + pick.name) + (pick.is_primary ? ' <span class="muted">· Main contact</span>' : '') : '', true],
        ['Finance email', t('finance_email')],
        ['Billing address', t('billing_address'), true, true]
      ]) +
      '<section class="readgroup bk-group" id="crmBukku" hidden></section>';
    /* Bukku (2026-10-18): the contact this client is in Bukku, sent by hand. */
    if (window.ADspaceBukku && maySeeBilling()) window.ADspaceBukku.group($('crmBukku'), 'client', c.id);
  }
  /* The sheet's fields are the record's values whenever it opens, so a Cancel
     leaves nothing half typed behind for the next Edit. */
  function fillBilling(c) {
    BILLING.forEach(function (f) { if (f[0] !== 'crmBillContact') $(f[0]).value = c[f[1]] || ''; });
    $('crmSstApplies').checked = c.sst_applies !== false;
    /* A Singapore client is billed in RM unless set to S$ (2026-10-22). */
    var sg = String(c.market || '').toUpperCase() === 'SG';
    $('crmBillInRow').hidden = !sg;
    $('crmBillIn').value = sg && c.bill_sgd ? 'SG' : 'MY';
    if (window.ADspaceForm && window.ADspaceForm.thumb) window.ADspaceForm.thumb($('crmBillIn'));
    $('crmSstLabel').textContent = 'Charge ' + MON.taxLabel() + ' on this client\'s quotes';
  }
  /* Billing comes first, for Active and for a Letter of Offer alike
     (2026-10-26: a letter printed with no registered name was signed as
     it stood). The refusal lands where the fix is: the Billing sheet on
     its first missing field, offering the details form; `then` marks what
     its Save carries on into. */
  function gateBilling(missing, before, opener, then) {
    showPane('billing');
    setUrl();
    if (mayPart('clients.billing', 'work')) {
      openBilling(opener);
      if (then) then();
      paintBillAsk();
      msg('crmBillMsg', 'Billing details required before ' + before + ': ' + missing.join(', ') + '.', 'err');
      var first = BILLING.filter(function (f) { return missing.indexOf(f[2]) > -1; })[0];
      if (first && $(first[0])) $(first[0]).focus();
    } else {
      msg('crmBillNote', 'Billing details required before ' + before + ': ' + missing.join(', ') + '.', 'err');
    }
  }
  function openBilling(opener) {
    /* The details form's answers are taken only by the Save of the sheet
       Use details filled; a sheet left any other way forgets them. */
    state.detUse = null;
    state.toActive = null;
    state.toLetter = null;
    fillBilling(state.client);
    paintBilling(state.client);
    msg('crmBillMsg', ''); msg('crmBillNote', '');
    if ($('crmBillAsk')) $('crmBillAsk').hidden = true;
    openSheet('crmBillSheet', opener || $('crmBillEdit'));
  }
  $('crmBillEdit').addEventListener('click', function () { openBilling(this); });
  $('crmBillCancel').addEventListener('click', function () {
    state.detUse = null;
    state.toActive = null; state.toLetter = null;
    shutSheet('crmBillSheet'); fillBilling(state.client); paintBilling(state.client); msg('crmBillMsg', '');
  });
  sheetClose('crmBillClose', 'crmBillCancel');

  /* The client's details form (2026-10-14; the user: "a form … for client
     to fill in (public link, no need any login …)"): a link made here,
     answered once on /details/, the answers waiting on this pane for the
     team to take into Billing with its own Save. */
  var DF_ROWS = [['legal_name', 'Registered name'], ['company_no', 'Business registration no.'],
    ['company_no_old', 'Old registration no.'], ['tin', 'TIN'], ['sst_no', 'SST registration no.'],
    ['billing_address', 'Billing address'], ['finance_email', 'Finance email']];
  var DF_FIELDS = { legal_name: 'crmLegalName', company_no: 'crmCompanyNo', company_no_old: 'crmCompanyNoOld',
    tin: 'crmTin', sst_no: 'crmSstNo', finance_email: 'crmFinanceEmail', billing_address: 'crmBillAddr' };
  var DF_SAID = { denied: 'This needs Clients: Billing.', 'not-found': 'This client is outside your access.' };
  function dfUrl(key) { return location.origin + '/details/?k=' + encodeURIComponent(key); }
  function loadDetForm() {
    var box = $('crmDetForm'), c = state.client;
    if (!box) return;
    if (!c || !mayPart('clients.billing', 'view')) { box.hidden = true; return; }
    var id = c.id;
    db.rpc('client_details_state', { p_client: id }).then(function (r) {
      if (!state.client || state.client.id !== id) return;
      var d = r.data || {};
      if (r.error || d.error) {
        box.hidden = false;
        failLine(box, 'Details form', r.error ? (/function|schema cache/i.test(r.error.message) ? 'This needs a database update.' : r.error.message) : (DF_SAID[d.error] || d.error), loadDetForm);
        return;
      }
      state.detForm = d.form || null;
      paintDetForm();
    }).catch(function (e) {
      if (!state.client || state.client.id !== id) return;
      box.hidden = false; failLine(box, 'Details form', (e && e.message) || String(e), loadDetForm);
    });
  }
  function paintDetForm() {
    var box = $('crmDetForm'), f = state.detForm, work = mayPart('clients.billing', 'work');
    if (!box) return;
    var head = function (act) { return '<div class="readgroup-head"><h4 class="fsec-h">Details form</h4>' + (act || '') + '</div>'; };
    var day = function (iso) { return window.ADspaceClock ? window.ADspaceClock.date(iso) : String(iso).slice(0, 10); };
    var make = work ? '<button class="btn btn-sm" type="button" data-df="make">Create link</button>' : '';
    if (!f || f.state === 'used' || f.state === 'expired') {
      if (!work && !f) { box.hidden = true; return; }
      var ua = f && f.state === 'used' && f.answers, uwho = ua ? dfWho(ua) : '', uin = ua ? dfContactOf(ua) : null;
      box.innerHTML = head(make) + '<dl class="ovfacts"><div><dt>State</dt><dd>' +
        (!f ? 'Not sent' : f.state === 'used' ? 'Received ' + esc(day(f.submitted_at)) + ', taken into Billing' : 'Link expired ' + esc(day(f.expires_at))) +
        '</dd></div>' + (uwho ? '<div><dt>Billing contact</dt><dd>' + esc(uwho) + (uin ? '' : '<br>Not in Contacts') + '</dd></div>' : '') + '</dl>' +
        (uwho && !uin && work && mayPart('clients.contacts', 'work') ? '<div class="dform-foot"><button class="btn btn-sm" type="button" data-df="contact">Add as contact</button></div>' : '') +
        '<div class="msg" id="crmDfMsg"></div>';
    } else if (f.state === 'open') {
      var url = f.key ? dfUrl(f.key) : '';
      box.innerHTML = head(work ? '<span class="dform-acts team-act"><button class="kmenu-btn" type="button" data-df="menu" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
          '<div class="kmenu" data-df-menu hidden><button class="kmenu-item" data-g="5" type="button" data-df="reset" role="menuitem">Reset link</button></div></span>' : '') +
        '<dl class="ovfacts"><div><dt>State</dt><dd>Sent, open until ' + esc(day(f.expires_at)) + '</dd></div></dl>' +
        (url ? '<div class="rec-linktools"><div class="linkbox">' +
          '<input class="input readfield" id="crmDfLink" readonly aria-label="Details form link" value="' + esc(url) + '">' +
          '<button class="btn btn-icon" type="button" data-df="copy"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15H4.5A1.5 1.5 0 0 1 3 13.5v-9A1.5 1.5 0 0 1 4.5 3h9A1.5 1.5 0 0 1 15 4.5V5"/></svg><span>Copy link</span></button>' +
          '<a class="btn btn-icon" href="' + esc(url) + '" target="_blank" rel="noopener">Preview <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 4h6v6"/><path d="M20 4 11 13"/><path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg></a>' +
          '</div></div>' : '') + '<div class="msg" id="crmDfMsg"></div>';
    } else {
      var a = f.answers || {};
      var who = dfWho(a), inC = dfContactOf(a);
      box.innerHTML = head(work ? '<button class="btn btn-sm btn-primary" type="button" data-df="use">Use details</button>' : '') +
        '<dl class="ovfacts"><div><dt>State</dt><dd>Received ' + esc(day(f.submitted_at)) + '</dd></div>' +
        /* An answer that differs from what Billing holds reads held → sent,
           as a supplier's update reads, so Use details is chosen knowing
           what it replaces (2026-10-20, DTL-1). */
        DF_ROWS.filter(function (r) { return a[r[0]]; }).map(function (r) {
          var held = String(state.client[r[0]] == null ? '' : state.client[r[0]]).trim(), sent = String(a[r[0]]).trim();
          var same = !held || held.replace(/\s+/g, ' ').toLowerCase() === sent.replace(/\s+/g, ' ').toLowerCase();
          return '<div' + (same ? '' : ' class="df-moved"') + '><dt>' + esc(r[1]) + '</dt><dd' + (r[0] === 'billing_address' ? ' class="is-pre"' : '') + '>' +
            (same ? esc(sent) : esc(held) + ' → ' + esc(sent)) + '</dd></div>';
        }).join('') +
        '<div><dt>Billing contact</dt><dd>' + esc(who) + '<br>' + esc(a.contact_phone || '') + '<br>' + esc(a.contact_email || '') + '</dd></div></dl>' +
        (work && !inC && mayPart('clients.contacts', 'work') ? '<div class="dform-foot"><button class="btn btn-sm" type="button" data-df="contact">Add as contact</button></div>' : '') +
        '<div class="msg" id="crmDfMsg"></div>';
    }
    box.hidden = false;
    if (window.ADspaceActs && window.ADspaceActs.scan) window.ADspaceActs.scan(box);
    if ($('crmBillAsk') && !$('crmBillAsk').hidden) paintBillAsk();
  }
  /* The billing contact the client sent (2026-10-16; the user: the full
     name sent on the form was nowhere in the portal): found among the
     client's contacts by email, else by the number's last nine digits. */
  function dfWho(a) { return ((a.contact_salutation ? a.contact_salutation + ' ' : '') + (a.contact_name || '')).trim(); }
  function dfContactOf(a) {
    var em = String(a.contact_email || '').trim().toLowerCase(), ph = String(a.contact_phone || '').replace(/\D/g, '').slice(-9);
    return (state.contacts || []).filter(function (ct) {
      if (ct.archived_at) return false;
      if (em && String(ct.email || '').trim().toLowerCase() === em) return true;
      var p = String(ct.phone || '').replace(/\D/g, '').slice(-9);
      return ph.length === 9 && p === ph;
    })[0] || null;
  }
  /* The client's answers into the Billing sheet, for its own Save. */
  function useDetails(b) {
    var f = state.detForm;
    if (!f || !f.answers) return;
    if ($('crmBillSheet').hidden) openBilling(b);
    Object.keys(DF_FIELDS).forEach(function (k) {
      var el = $(DF_FIELDS[k]);
      if (el && f.answers[k]) { el.value = f.answers[k]; el.dispatchEvent(new Event('input', { bubbles: true })); }
    });
    state.detUse = f.id;
    var ct = dfContactOf(f.answers), main = mainContact(), who = dfWho(f.answers);
    if (ct) { $('crmBillContact').value = main && ct.id === main.id ? '' : ct.id; $('crmBillContact').dispatchEvent(new Event('input', { bubbles: true })); }
    msg('crmBillMsg', ct || !who ? 'Filled from the details form. Review, then Save.'
      : 'Filled from the details form. ' + who + ' is not in Contacts: after Save, use Add as contact on the details form.', ct || !who ? 'ok' : 'warn');
  }
  /* The Active gate's Billing sheet offers the details form (2026-10-15,
     audit CLI-6): what the team would type, the client can send. */
  function paintBillAsk() {
    var box = $('crmBillAsk'), f = state.detForm;
    if (!box) return;
    if (!mayPart('clients.billing', 'work')) { box.hidden = true; return; }
    var day = function (iso) { return window.ADspaceClock ? window.ADspaceClock.date(iso) : String(iso).slice(0, 10); };
    var words, act;
    if (f && f.answers && f.state !== 'used') { words = 'The client sent these on ' + day(f.submitted_at) + '.'; act = ['use', 'Use details']; }
    else if (f && f.state === 'open' && f.key) { words = 'The details form is open until ' + day(f.expires_at) + '.'; act = ['copy', 'Copy link']; }
    else { words = 'The client can fill these in on the details form.'; act = ['make', 'Create link']; }
    box.innerHTML = '<span>' + esc(words) + '</span><button class="btn btn-sm" type="button" data-ba="' + act[0] + '">' + esc(act[1]) + '</button>';
    box.hidden = false;
    if (window.ADspaceActs && window.ADspaceActs.scan) window.ADspaceActs.scan(box);
  }
  document.addEventListener('click', function (e) {
    var b = e.target.closest && e.target.closest('#crmBillAsk [data-ba]');
    if (!b) return;
    var a = b.getAttribute('data-ba'), f = state.detForm;
    if (a === 'use') { useDetails(b); $('crmBillAsk').hidden = true; return; }
    if (a === 'copy' && f && f.key) { window.ADspaceCopy.to(b, dfUrl(f.key)); return; }
    if (a === 'make') {
      b.disabled = true;
      db.rpc('client_details_link', { p_client: state.client.id, p_reset: false }).then(function (r) {
        var d = r.data || {};
        if (r.error || d.error) { b.disabled = false; msg('crmBillMsg', r.error ? r.error.message : (DF_SAID[d.error] || d.error), 'err'); return; }
        state.detForm = { id: d.id, key: d.key, state: 'open', expires_at: d.expires_at };
        paintDetForm(); paintBillAsk();
        var c = $('crmBillAsk').querySelector('[data-ba="copy"]');
        if (c) window.ADspaceCopy.to(c, dfUrl(d.key));
      }).catch(function (x) { b.disabled = false; msg('crmBillMsg', (x && x.message) || String(x), 'err'); });
    }
  });
  function dfLink(reset, btn) {
    if (btn) btn.disabled = true;
    db.rpc('client_details_link', { p_client: state.client.id, p_reset: Boolean(reset) }).then(function (r) {
      var d = r.data || {};
      if (r.error || d.error) {
        msg('crmDfMsg', r.error ? (/function|schema cache/i.test(r.error.message) ? 'This needs a database update.' : r.error.message) : (DF_SAID[d.error] || d.error), 'err');
        if (btn) btn.disabled = false; return;
      }
      state.detForm = { id: d.id, key: d.key, state: 'open', expires_at: d.expires_at };
      paintDetForm();
      msg('crmDfMsg', reset ? 'Link reset. The earlier link no longer opens.' : 'Link created.', 'ok');
    }).catch(function (e) { msg('crmDfMsg', (e && e.message) || String(e), 'err'); if (btn) btn.disabled = false; });
  }
  document.addEventListener('click', function (e) {
    var b = e.target.closest && e.target.closest('#crmDetForm [data-df]');
    var box = $('crmDetForm');
    if (!b) { if (box && !e.target.closest('#crmDetForm .dform-acts')) Array.prototype.forEach.call(box.querySelectorAll('[data-df-menu]'), function (m) { m.hidden = true; }); return; }
    var a = b.getAttribute('data-df'), f = state.detForm;
    if (a === 'make') { dfLink(false, b); return; }
    if (a === 'menu') {
      var m = box.querySelector('[data-df-menu]'); m.hidden = !m.hidden; b.setAttribute('aria-expanded', String(!m.hidden));
      if (!m.hidden) window.ADspaceMenu.place(b, m);
      return;
    }
    if (a === 'reset') {
      box.querySelector('[data-df-menu]').hidden = true;
      window.ADspaceConfirm.ask({ title: 'Reset link?', body: 'The current link stops working. A new one is made.', go: 'Reset link', tone: 'warn' },
        function () { dfLink(true); });
      return;
    }
    if (a === 'copy') { window.ADspaceCopy.to(b, $('crmDfLink').value); return; }
    if (a === 'use' && f && f.answers) { useDetails(b); return; }
    if (a === 'contact' && f && f.answers) {
      showPane('contacts'); pushUrl();
      openContact(null);
      $('ctSalutation').value = f.answers.contact_salutation || '';
      $('ctName').value = f.answers.contact_name || '';
      $('ctRole').value = 'Billing';
      $('ctPhone').value = f.answers.contact_phone || '';
      $('ctEmail').value = f.answers.contact_email || '';
      $('ctPrimary').checked = false;
      state.dfContact = f.id;
    }
  });

  /* The content brief (2026-10-10; the user, 2026-10-09: "content not
     interesting"): read first on the Brand pane, edited in the Brand
     profile, kept as one object on the client, and read by Write with AI
     for captions and scripts. */
  var BRIEF = [['crmBrAudience', 'audience', 'Audience'], ['crmBrPains', 'pains', 'Pain points'],
    ['crmBrPillars', 'pillars', 'Content pillars'], ['crmBrTone', 'tone', 'Tone of voice'],
    ['crmBrAvoid', 'avoid', 'Topics and words to avoid'], ['crmBrRivals', 'competitors', 'Competitors'],
    ['crmBrHooks', 'hooks', 'Hooks that worked']];
  function briefOf(c) { return (c && c.brief && typeof c.brief === 'object') ? c.brief : {}; }
  function paintBrandRead(c) {
    var box = $('crmBrandRead');
    if (!box) return;
    var handle = function (k, label) {
      return c[k] ? '<a class="plink" href="' + esc(profileUrl(k, c[k])) + '" target="_blank" rel="noopener">' + esc(c[k]) + '</a>' : '';
    };
    var site = c.website ? '<a class="plink" href="' + esc(/^https?:/i.test(c.website) ? c.website : 'https://' + c.website) +
      '" target="_blank" rel="noopener">' + esc(c.website.replace(/^https?:\/\//i, '').replace(/\/$/, '')) + '</a>' : '';
    var logo = c.logo_url ? '<span class="readlogo"><img src="' + esc(c.logo_url) + '" alt="" onerror="this.remove()"></span>Set' : '';
    box.innerHTML =
      readGroup('Website and office', [['Website', site], ['Office phone', c.phone ? esc(c.phone) : '']]) +
      readGroup('Social handles', [
        ['Instagram', handle('handle_ig')], ['Facebook', handle('handle_fb')],
        ['TikTok', handle('handle_tiktok')], ['rednote', c.handle_xhs ? esc(c.handle_xhs) : '']
      ]) +
      readGroup('Logo and notes', [['Logo', logo], ['Brand notes', c.brand_notes ? esc(c.brand_notes) : '', false, true]]) +
      readGroup('Content brief', BRIEF.map(function (f) { var v = briefOf(c)[f[1]]; return [f[2], v ? esc(v) : '', false, true]; })) +
      /* White label is one group (the user, 2026-10-15): the switch, the
         wide logo and the brands it covers, read together. */
      (c.white_label ? '<section class="readgroup wl-brands" id="crmWlBrands"><h4 class="fsec-h">White label</h4><dl class="ovfacts">' +
        '<div><dt>White label</dt><dd>On</dd></div>' +
        '<div><dt>Wide logo</dt>' + (c.report_logo ? '<dd><span class="widelogo is-read"><img src="' + esc(c.report_logo) + '" alt="Wide logo"></span></dd>'
          : '<dd class="is-missing">Required</dd>') + '</div>' +
        '<div><dt>Brands</dt><dd data-m="list"></dd></div></dl></section>' : '') +
      '<section class="readgroup meta-links" id="crmMetaRead"><div class="readgroup-head"><h4 class="fsec-h">Meta</h4>' +
        (mayPart('clients.brand', 'work') ? '<button class="btn btn-sm" type="button" data-a="meta">' + PEN + 'Edit</button>' : '') +
        '</div><div data-m="list"></div></section>' +
      '<section class="readgroup ba" id="crmAnalysis"><div class="readgroup-head"><h4 class="fsec-h">Brand analysis</h4>' +
        '<span class="ba-acts" data-m="acts"></span></div><p class="msg capmsg" id="crmAnalysisMsg"></p><div data-m="body"></div></section>';
    if (c.white_label) loadBrands(c);
    loadMeta(c);
    loadAnalysis(c);
    var me0 = $('crmMetaRead').querySelector('[data-a="meta"]');
    if (me0) me0.addEventListener('click', function () { metaSheet(c, null, this); });
  }
  /* The brands a white-label client is serviced for (2026-10-07): each its
     own report a month, picked on New report and in a report's White label.
     Added and renamed here, stood down, never removed. */
  var brandSeq = 0;
  function loadBrands(c) {
    var host = $('crmWlBrands');
    if (!host) return;
    var list = host.querySelector('[data-m="list"]'), seq = ++brandSeq;
    var can = mayPart('reports.whitelabel', 'work'), canMeta = mayPart('clients.brand', 'work');
    db.rpc('client_brands_list', { p_client: c.id }).then(function (q) {
      if (seq !== brandSeq || state.client !== c) return;
      var d = (q && q.data) || {};
      if ((q && q.error) || d.error) { list.innerHTML = '<p class="msg err">Brands could not be read.</p>'; return; }
      var bs = d.brands || [];
      list.innerHTML = (bs.length ? '' : '<p class="wl-none">No brands.</p>');
      bs.forEach(function (b) {
        var row = document.createElement('div');
        row.className = 'wl-brand' + (b.active ? '' : ' is-off');
        var own = b.logo === 'adspace';
        row.innerHTML = '<span class="wl-brand-name">' + esc(b.name) + (own ? '<span class="chip">ADspace logo</span>' : '') +
          (b.active ? '' : '<span class="chip is-off">Inactive</span>') + '</span>' +
          (can || canMeta ? '<span class="team-act">' +
            '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
            '<div class="kmenu" data-menu hidden>' +
              (can ? '<button class="kmenu-item" data-g="2" data-a="rename" type="button" role="menuitem">Rename</button>' : '') +
              (canMeta ? '<button class="kmenu-item" data-g="2" data-a="meta" type="button" role="menuitem">Meta accounts</button>' : '') +
              (can ? '<button class="kmenu-item" data-g="2" data-a="logo" type="button" role="menuitem">' + (own ? 'Use ' + esc(c.name) + ' logo' : 'Use ADspace logo') + '</button>' +
              '<button class="kmenu-item" data-g="5" data-a="state" type="button" role="menuitem">' + (b.active ? 'Set inactive' : 'Set active') + '</button>' : '') +
            '</div></span>' : '');
        list.appendChild(row);
        if (!can && !canMeta) return;
        wireMenu(row);
        var mItem = row.querySelector('[data-a="meta"]');
        if (mItem) mItem.addEventListener('click', function () { metaSheet(c, b, row.querySelector('[data-a="menu"]')); });
        if (!can) return;
        row.querySelector('[data-a="rename"]').addEventListener('click', function () { brandAsk(c, b); });
        /* Whose mark heads the brand's reports (2026-10-07); reversible, so
           it never asks. A published version keeps the mark it went out with. */
        row.querySelector('[data-a="logo"]').addEventListener('click', function () {
          db.rpc('client_brand_logo', { p_id: b.id, p_logo: own ? 'partner' : 'adspace' }).then(function (q) {
            var d = (q && q.data) || {};
            if ((q && q.error) || d.error) {
              msg('crmBrandNote', d.error === 'denied' ? 'This needs Reports: White label.' : ((q && q.error && q.error.message) || 'Not saved.'), 'err');
              return;
            }
            msg('crmBrandNote', 'Saved.', 'ok');
            loadBrands(c);
          }).catch(function (e) { msg('crmBrandNote', (e && e.message) || 'Not saved.', 'err'); });
        });
        row.querySelector('[data-a="state"]').addEventListener('click', function () {
          var go = function () { saveBrand(c, b, b.name, !b.active); };
          if (!b.active) { go(); return; }
          window.ADspaceConfirm.ask({ title: 'Set ' + b.name + ' inactive?', body: 'It is no longer offered for new reports. Its reports are kept.', go: 'Set inactive', tone: 'warn' }, go);
        });
      });
      if (can) {
        var add = document.createElement('button');
        add.type = 'button'; add.className = 'btn btn-sm wl-add'; add.id = 'crmWlAdd';
        add.innerHTML = PLUS_ICON + 'Add brand';
        add.addEventListener('click', function () { brandAsk(c, null); });
        list.appendChild(add);
      }
    }).catch(function () { if (seq === brandSeq) list.innerHTML = '<p class="msg err">Brands could not be read.</p>'; });
  }
  /* META (2026-10-08): the ad accounts, Page and Instagram account a
     client's reports are read from by Import from Meta, picked from what
     ADspace's system user can see (the `meta-import` function), never typed.
     A white-label client's brands each link their own, from the brand's ⋯
     (Meta accounts), read in that sheet. */
  var metaSeq = 0, metaSheetSeq = 0, metaLinks = [];
  function metaFacts(l) {
    var names = function (v) { return Array.isArray(v) ? v.map(function (x) { return esc(x.name); }).join(', ') : v ? esc(v.name) : ''; };
    return [['Ad accounts', names(l && l.ad_accounts)], ['Facebook Page', names(l && l.page)], ['Instagram', names(l && l.instagram)]];
  }
  function loadMeta(c) {
    var host = $('crmMetaRead');
    if (!host) return;
    var list = host.querySelector('[data-m="list"]'), seq = ++metaSeq;
    db.rpc('meta_links_list', { p_client: c.id }).then(function (q) {
      if (seq !== metaSeq || state.client !== c) return;
      var d = (q && q.data) || {};
      if ((q && q.error) || d.error) {
        metaLinks = [];
        list.innerHTML = '<p class="msg err">' + ((q && q.error && /function|schema cache/i.test(q.error.message)) ? 'This needs a database update.' : 'The Meta accounts could not be read.') + '</p>';
        return;
      }
      metaLinks = d.links || [];
      var own = metaLinks.filter(function (l) { return !l.brand_id; })[0];
      var dl = function (rows) {
        return '<dl class="ovfacts">' + rows.map(function (r) {
          return '<div><dt>' + esc(r[0]) + '</dt>' + (r[1] ? '<dd>' + r[1] + '</dd>' : '<dd class="is-empty">—</dd>') + '</div>';
        }).join('') + '</dl>';
      };
      list.innerHTML = dl(metaFacts(own));
    }).catch(function () { if (seq === metaSeq) list.innerHTML = '<p class="msg err">The Meta accounts could not be read.</p>'; });
  }
  /* BRAND ANALYSIS (2026-10-10; the user: "deep analysis of this clients
     … brand part, target audiences, SWOTs, advantages disadvantages, ads
     targetting"). Run by any colleague who sees the client, through
     `brand-analysis`: the record, its reports, post results, Meta where
     linked and web research on the brand and its competitors. Each run is
     the next version, read first here; it is a draft until a colleague
     declares it read and confirmed, and only a confirmed one is read by
     Write with AI. Read once a client; a repaint draws from what was read. */
  var ba = { id: null, versions: null, failed: false, show: null, seq: 0, running: null };
  var BA_SAID = {
    'needs-update': 'This needs a database update.',
    'ai-not-set-up': 'AI needs its key in Supabase.',
    'ai-key': 'The AI key was refused. Check it in Supabase.',
    'ai-busy': 'The AI service is busy. Try again in a minute.',
    'ai-credit': 'The AI account has no credit. Top up in the Claude Console.',
    'ai-model': 'The analysis model name in Supabase is not recognised.',
    'ai-slow': 'The analysis took too long. Try again.',
    'ai-failed': 'No analysis came back. Try again.',
    'ai-incomplete': 'No analysis came back. Try again.',
    denied: 'This needs Clients: Brand at View.',
    'client-scope': 'This client is outside your access.',
    'not-found': 'This analysis is no longer available.',
    'no-source': 'Add the website, an Instagram or Facebook handle, or link Meta accounts first.'
  };
  function baDay(iso) { return iso ? niceDate(ADspaceClock.day(iso)) : ''; }
  function baClock(iso) { return iso ? ADspaceClock.clock(iso) : ''; }
  function baLimit(d) {
    d = d || {};
    if (d.scope === 'stopped' || d.limit === 0) return 'Brand analyses are turned off for you. An admin can turn them on.';
    var n = d.limit || 3;
    return 'You have used your ' + n + (n === 1 ? ' analysis' : ' analyses') + ' for today.' + (d.next ? ' Resets at ' + baClock(d.next) + '.' : '');
  }
  function baSaid(e) {
    var m = String((e && e.message) || '');
    if (m === 'ai-limit') return baLimit(e.d);
    if (BA_SAID[m]) return BA_SAID[m];
    if (/function .* does not exist|schema cache|PGRST20[25]/i.test(m)) return BA_SAID['needs-update'];
    return BA_SAID['ai-failed'];
  }
  function baKeep(key, v) {
    try {
      if (v === undefined) return localStorage.getItem(key) || '';
      if (v) localStorage.setItem(key, v); else localStorage.removeItem(key);
    } catch (e) {}
    return '';
  }
  function baList(items) {
    items = (items || []).filter(Boolean);
    return items.length ? '<ul class="ba-list">' + items.map(function (x) { return '<li>' + esc(x) + '</li>'; }).join('') + '</ul>' : '';
  }
  function baFacts(rows) {
    return '<dl class="ovfacts">' + rows.map(function (r) {
      return '<div><dt>' + esc(r[0]) + '</dt>' + (r[1] ? '<dd>' + r[1] + '</dd>' : '<dd class="is-empty">—</dd>') + '</div>';
    }).join('') + '</dl>';
  }
  /* Each section of an analysis is a fold (2026-10-22, CLI-11; the user:
     "Fix all"): its title over the line it is read for, shut until opened,
     a section opened remembered for that client (`ADspaceGroup`, route
     `brand-analysis`). A draft opens Brand positioning by itself, so
     Confirm is read against it. The head (State, Version, Read from) stays
     open. */
  var baCtx = { client: null, draft: false };
  var BA_CHEV = '<svg class="ba-fold-chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>';
  function baKey(title) { return String(title).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, ''); }
  function baN(n, one, many) { n = n || 0; return n ? n + ' ' + (n === 1 ? one : (many || one + 's')) : ''; }
  function baFold(title, summary, inner) {
    var key = baKey(title), GRP = window.ADspaceGroup;
    var dflt = !(baCtx.draft && key === 'brand-positioning');
    var shut = GRP && baCtx.client ? GRP.shut('brand-analysis', baCtx.client + ':' + key, dflt) : dflt;
    var id = 'baf-' + key;
    return '<div class="ba-sec ba-fold' + (shut ? '' : ' is-open') + '" data-fold="' + esc(key) + '">' +
      '<button class="ba-fold-head" type="button" data-a="ba-fold" aria-expanded="' + String(!shut) + '" aria-controls="' + id + '">' +
        '<span class="ba-fold-t"><span class="fsec-h">' + esc(title) + '</span>' +
        (summary ? '<span class="ba-fold-sum">' + esc(summary) + '</span>' : '') + '</span>' + BA_CHEV + '</button>' +
      '<div class="ba-fold-body" id="' + id + '"><div class="ba-fold-in">' + inner + '</div></div></div>';
  }
  function baSec(title, rows, summary) { return baFold(title, summary, baFacts(rows)); }
  /* The client analysis playbook's sections (2026-10-15): drawn only for a
     version that holds them, so an earlier version reads as it was. */
  var BA_LABEL = { official: 'Official', listing: 'Listing', third_party: 'Third party' };
  var BA_KIND = { direct: 'Direct', indirect: 'Indirect', legacy: 'Legacy', disruptor: 'Disruptor' };
  var BA_WHEN = { first: 'First', next: 'Next', later: 'Later' };
  function baMap(map) {
    return '<ul class="ba-list">' + map.map(function (x) {
      return '<li><span class="ba-name">' + esc(x.name) + ' <span class="chip">' + esc(BA_KIND[x.kind] || x.kind) + '</span></span>' + esc(x.note || '') + '</li>';
    }).join('') + '</ul>';
  }
  function baPlaybook(a) {
    var e = a.entity || {}, f = a.fit || {}, out = '';
    var facts = a.facts || [];
    if (e.name || facts.length) {
      out += baSec('What it is', [['Entity', esc(e.name || '')]]
        .concat(e.parent ? [['Parent group', esc(e.parent)]] : [])
        .concat(e.place ? [['Where', esc(e.place)]] : [])
        .concat(facts.length ? [['Facts', '<ul class="ba-list ba-facts">' + facts.map(function (x) {
          return '<li>' + esc(x.fact) + ' <span class="chip">' + esc(BA_LABEL[x.label] || 'Third party') + '</span>' +
            (x.confirm ? ' <span class="chip-state is-warn">To confirm</span>' : '') + '</li>';
        }).join('') + '</ul>']] : []), [e.name, baN(facts.length, 'fact')].filter(Boolean).join(' · '));
    }
    if ((a.works || []).length || (a.weak || []).length) {
      out += baSec('What works and what is weak', [['What works', baList(a.works)], ['What is weak', baList(a.weak)]],
        [baN((a.works || []).length, 'that works', 'that work'), baN((a.weak || []).length, 'weak', 'weak')].filter(Boolean).join(' · '));
    }
    if ((f.channels || []).length || f.angle) {
      out += baSec('Where ADspace fits', [['Channels', (f.channels || []).length ? '<ul class="ba-list">' + f.channels.map(function (x) {
          return '<li><span class="ba-name">' + esc(x.channel) + ' <span class="chip">' + esc(BA_WHEN[x.priority] || x.priority) + '</span></span>' + esc(x.why || '') + '</li>';
        }).join('') + '</ul>' : ''],
        ['Fix before paid traffic', baList(f.fix_first)], ['Commercial angle', esc(f.angle || '')]],
        [baN((f.channels || []).length, 'channel'), baN((f.fix_first || []).length, 'to fix first', 'to fix first')].filter(Boolean).join(' · '));
    }
    return out;
  }
  function baRead(b) {
    b = b || {};
    var bits = [];
    var n = function (v, one, many) { return typeof v === 'number' && v > 0 ? v + ' ' + (v === 1 ? one : many) : ''; };
    bits.push(n(b.reports, 'report', 'reports'), n(b.post_results, 'post result', 'post results'));
    var m = b.meta && typeof b.meta === 'object' ? b.meta : {};
    bits.push(n(m.instagram, 'Instagram post', 'Instagram posts'), n(m.facebook, 'Facebook post', 'Facebook posts'),
      m.followers ? 'Instagram followers' : '', n(m.ads, 'ad objective', 'ad objectives'), n(b.web_searches, 'web search', 'web searches'));
    return bits.filter(Boolean).map(function (x) { return '<span class="ba-part">' + esc(x) + '</span>'; }).join(' · ');
  }
  function paintAnalysis(c) {
    var host = $('crmAnalysis');
    if (!host || state.client !== c) return;
    var acts = host.querySelector('[data-m="acts"]'), body = host.querySelector('[data-m="body"]');
    var may = mayPart('clients.brand', 'view');
    var list = ba.versions || [];
    var v = list.filter(function (x) { return x.id === ba.show; })[0] || list[0] || null;
    var latest = v && v === list[0];
    var busy = ba.running === c.id;
    var AI = (window.ADspaceConfirm && window.ADspaceConfirm.ai && window.ADspaceConfirm.ai.glyph) || '';
    acts.innerHTML = !may ? '' :
      (v && !v.confirmed_at && !busy ? '<button class="btn btn-sm btn-primary" type="button" data-a="ba-confirm" id="crmAnalysisConfirm">Confirm</button>' : '') +
      '<button class="btn btn-sm" type="button" data-a="ba-run" id="crmAnalysisRun"' + (busy ? ' disabled aria-busy="true"' : '') + '>' + AI +
        (busy ? 'Running' : list.length ? 'Run again' : 'Run analysis') + '</button>' +
      (v && v.confirmed_at ? '<span class="team-act"><button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
        '<div class="kmenu" data-menu hidden><button class="kmenu-item" data-g="5" data-a="ba-withdraw" type="button" role="menuitem">Withdraw confirmation</button></div></span>' : '');
    if (acts.querySelector('[data-a="menu"]')) wireMenu(acts);
    if (ba.failed) { body.innerHTML = '<p class="msg err">The brand analysis could not be read.</p>'; return; }
    if (!ba.versions) { body.innerHTML = '<p class="ba-none">Loading.</p>'; return; }
    if (!v) { body.innerHTML = '<p class="ba-none">Not run.</p>'; return; }
    var a = v.analysis || {}, p = a.positioning || {}, sw = a.swot || {}, ct = a.content || {}, ad = a.ads || {};
    var earlier = list.filter(function (x) { return x !== v; });
    baCtx = { client: c.id, draft: !v.confirmed_at };
    var len = function (x) { return (x || []).length; };
    body.innerHTML =
      baFacts([
        ['State', v.confirmed_at ? '<span class="chip-state is-ok">Confirmed</span>' : '<span class="chip-state is-warn">Draft</span>'],
        ['Version', esc('Version ' + v.version + ' · ' + baDay(v.created_at) + (v.by ? ' · ' + v.by : '')) +
          (latest ? '' : ' <button class="linkbtn" type="button" data-a="ba-latest">Show latest</button>')],
        ['Confirmed', v.confirmed_at ? esc(baDay(v.confirmed_at) + (v.confirmed_by ? ' · ' + v.confirmed_by : '')) : ''],
        ['Read from', baRead(v.basis)]
      ].filter(function (r) { return r[0] !== 'Confirmed' || v.confirmed_at; })) +
      (v.hypothesis ? '<p class="msg warn ba-hypo">A starting hypothesis to test</p>' : '') +
      baPlaybook(a) +
      baSec('Brand positioning', [['Stands for now', esc(p.now || '')], ['Could own', esc(p.could_own || '')],
        (p.map || []).length ? ['Competitors', baMap(p.map)] : ['Compared with', esc((p.competitors || []).join(', '))]],
        p.could_own ? 'Could own: ' + p.could_own : (p.now || '')) +
      baFold('Target audiences', (a.audiences || []).map(function (s) { return s.name; }).filter(Boolean).join(' · '),
        baFacts((a.audiences || []).map(function (s) {
          return [s.name, [['Who they are', s.who], ['Pain points', s.pains], ['Motivations', s.motivations], ['Platforms and times', s.reach]]
            .filter(function (x) { return x[1]; }).map(function (x) { return '<p class="ba-line"><span class="ba-k">' + esc(x[0]) + '</span>' + esc(x[1]) + '</p>'; }).join('')];
        }))) +
      baSec('SWOT', [['Strengths', baList(sw.strengths)], ['Weaknesses', baList(sw.weaknesses)],
        ['Opportunities', baList(sw.opportunities)], ['Threats', baList(sw.threats)]],
        [baN(len(sw.strengths), 'strength'), baN(len(sw.weaknesses), 'weakness', 'weaknesses'),
          baN(len(sw.opportunities), 'opportunity', 'opportunities'), baN(len(sw.threats), 'threat')].filter(Boolean).join(' · ')) +
      baSec('Content', [['What worked', baList(ct.worked)], ['What did not', baList(ct.not_worked)],
        ['Pillars', baList(ct.pillars)], ['Formats', baList(ct.formats)]],
        [baN(len(ct.pillars), 'pillar'), baN(len(ct.formats), 'format')].filter(Boolean).join(' · ')) +
      baSec('Ad targeting', [['Objectives', baList(ad.objectives)], ['Age bands', esc((ad.ages || []).join(' · '))],
        ['Interests', esc((ad.interests || []).join(' · '))], ['Placements', esc((ad.placements || []).join(' · '))],
        ['Budget by objective', esc((ad.budget || []).map(function (x) { return x.objective + ' ' + x.share + '%'; }).join(' · '))],
        ['Test first', esc(ad.test || '')]].concat(ad.realism ? [['Budget realism', esc(ad.realism)]] : []),
        (ad.objectives || []).join(' · ')) +
      ((a.confirm || []).length ? baSec('To confirm with the client', [['Points', baList(a.confirm)]], baN(len(a.confirm), 'point')) : '') +
      (a.next_question ? baSec('Next question', [['Ask', esc(a.next_question)]], a.next_question) : '') +
      ((v.sources || []).length ? baFold('Sources', baN(v.sources.length, 'source'), '<div class="ba-sources">' + v.sources.map(function (x) {
        return /^https:\/\//i.test(x.url || '') ? '<a class="plink" href="' + esc(x.url) + '" target="_blank" rel="noopener">' + esc(x.title || x.url) + '</a>' : '';
      }).join('') + '</div>') : '') +
      (earlier.length ? baFold('Other versions', baN(earlier.length, 'earlier version'), '<div class="ba-versions">' + earlier.map(function (x) {
        return '<button class="linkbtn" type="button" data-a="ba-show" data-id="' + esc(x.id) + '">' +
          esc('Version ' + x.version + ' · ' + baDay(x.created_at) + (x.by ? ' · ' + x.by : '') + (x.confirmed_at ? ' · Confirmed' : ' · Draft')) + '</button>';
      }).join('') + '</div>') : '');
  }
  function loadAnalysis(c, force) {
    if (!$('crmAnalysis')) return;
    /* The Brand analysis is Clients: Brand's (2026-10-22). */
    $('crmAnalysis').hidden = !mayPart('clients.brand', 'view');
    if ($('crmAnalysis').hidden) return;
    if (ba.id === c.id && ba.versions && !force) { paintAnalysis(c); return; }
    if (ba.id !== c.id) { ba.versions = null; ba.show = null; }
    ba.id = c.id; ba.failed = false;
    var seq = ++ba.seq;
    paintAnalysis(c);
    db.rpc('brand_analyses_list', { p_client: c.id }).then(function (q) {
      if (seq !== ba.seq || state.client !== c) return;
      var d = (q && q.data) || {};
      if ((q && q.error) || d.error) { ba.failed = true; ba.versions = null; }
      else ba.versions = d.versions || [];
      paintAnalysis(c);
    }).catch(function () { if (seq === ba.seq) { ba.failed = true; paintAnalysis(c); } });
  }
  function baMsg(text, tone) {
    var el = $('crmAnalysisMsg');
    if (!el) return;
    el.textContent = text || '';
    el.className = 'msg capmsg' + (text ? ' ' + (tone || 'err') : '');
  }
  function runAnalysis(c, btn) {
    baMsg('');
    btn.disabled = true;
    /* No brief first (2026-10-15): the analysis writes it, from the
       website, the handles and Meta; confirming fills what is empty. */
    Promise.all([db.rpc('ai_analysis_left')]).then(function (both) {
      var q = both[0];
      btn.disabled = false;
      var left = (q && q.data) || {};
      if ((q && q.error) || left.error) { var x = new Error(q && q.error ? q.error.message : left.error); throw x; }
      if (!left.left) { baMsg(baLimit(left)); return; }
      var key = 'adspace-analysis-notes:' + c.id, ikey = 'adspace-analysis-inputs:' + c.id;
      /* What the team knows is asked up front (2026-10-15, the client
         analysis playbook), so the analysis never comes back with questions
         it could have been told; kept in this browser with the notes. */
      var was = {};
      try { was = JSON.parse(baKeep(ikey) || '{}') || {}; } catch (e0) { was = {}; }
      window.ADspaceConfirm.ask({
        title: 'Run analysis',
        body: 'Reads the website, public pages and competitors on the web, with the brief, published reports, post results and Meta where linked. ' +
          left.left + (left.left === 1 ? ' analysis' : ' analyses') + ' left today.',
        go: 'Run',
        fields: [
          { name: 'budget', label: 'Monthly ad budget (RM)', type: 'number', required: false, placeholder: 'Optional', value: was.budget || '' },
          { name: 'objective', label: 'Main objective', required: false, value: was.objective || '',
            choices: [['', 'Not decided'], ['enquiries', 'Enquiries (lead form)'], ['messages', 'Messages (WhatsApp)'], ['traffic', 'Website visits or sales'], ['awareness', 'Awareness']] },
          { name: 'account', label: 'Ad account', required: false, value: was.account || '', seg: true,
            choices: [['', 'Not known'], ['new', 'New'], ['mature', 'Mature']] },
          { name: 'notes', label: 'Notes for the analysis', rows: 4, required: false, placeholder: 'Optional', value: baKeep(key) }],
        check: function (v) {
          var b = String(v.budget == null ? '' : v.budget).trim();
          return b && !(Number(b) > 0 && Number(b) <= 10000000) ? 'Monthly ad budget: a figure above 0.' : '';
        }
      }, function (v) {
        var notes = String(v.notes || '').trim();
        var inputs = { objective: v.objective || '', budget: String(v.budget == null ? '' : v.budget).trim(), account: v.account || '' };
        baKeep(key, notes);
        baKeep(ikey, inputs.objective || inputs.budget || inputs.account ? JSON.stringify(inputs) : '');
        ba.running = c.id;
        paintAnalysis(c);
        db.functions.invoke('brand-analysis', { body: { client_id: c.id, notes: notes,
          inputs: { objective: inputs.objective || null, budget: inputs.budget ? Number(inputs.budget) : null, account: inputs.account || null } } }).then(function (res) {
          var d = res && res.data;
          if (res.error || !d || d.error || !d.analysis) { var e = new Error((d && d.error) || 'ai-failed'); e.d = d; throw e; }
          ba.running = null;
          if (ba.id === c.id && ba.versions) { ba.versions.unshift(d.analysis); ba.show = null; }
          paintAnalysis(c);
          if (ba.id !== c.id) return;
          baMsg('Written by AI. Read before confirming.', 'ok');
        }).catch(function (e) {
          ba.running = null;
          paintAnalysis(c);
          if (state.client !== c) return;
          baMsg(baSaid(e));
        });
      });
    }).catch(function (e) { btn.disabled = false; baMsg(baSaid(e)); });
  }
  /* The brief a confirmed analysis filled, read back onto the record. */
  /* The Brand pane drawn again with the brief the analysis filled; `then`
     runs once it is drawn (it redraws the analysis's own box). */
  function briefAgain(c, then) {
    var done = function () { if (then) then(); };
    db.from('clients').select('brief').eq('id', c.id).maybeSingle().then(function (r) {
      if (r && !r.error && r.data) {
        c.brief = r.data.brief;
        if (state.client === c) paintBrandRead(c);
      }
      done();
    }).catch(done);
  }
  function confirmAnalysis(c, v, on) {
    var go = function () {
      db.rpc('brand_analysis_confirm', { p_id: v.id, p_on: on }).then(function (q) {
        var d = (q && q.data) || {};
        if ((q && q.error) || d.error) { baMsg(q && q.error ? baSaid(q.error) : BA_SAID[d.error] || 'Not saved.'); return; }
        ba.versions = (ba.versions || []).map(function (x) { return x.id === d.id ? d : x; });
        paintAnalysis(c);
        var filled = d.filled || [];
        var said = function () {
          undoBar(on ? 'Brand analysis confirmed.' + (filled.length ? ' Content brief filled: ' + filled.join(', ') + '.' : '') : 'Confirmation withdrawn.',
            function () { confirmAnalysis(c, d, !on); }, $('crmAnalysisMsg'));
        };
        if (filled.length) briefAgain(c, said); else said();
      }).catch(function (e) { baMsg(baSaid(e)); });
    };
    baMsg('');
    if (!on) { go(); return; }
    window.ADspaceConfirm.ai.declare('analysis', 'Confirm', go);
  }
  document.addEventListener('click', function (e) {
    var t = e.target.closest && e.target.closest('#crmAnalysis [data-a]');
    var c = state.client;
    if (!t || !c) return;
    var a = t.getAttribute('data-a');
    var shown = (ba.versions || []).filter(function (x) { return x.id === ba.show; })[0] || (ba.versions || [])[0];
    if (a === 'ba-run') runAnalysis(c, t);
    else if (a === 'ba-confirm' && shown) confirmAnalysis(c, shown, true);
    else if (a === 'ba-withdraw' && shown) confirmAnalysis(c, shown, false);
    else if (a === 'ba-show') { ba.show = t.getAttribute('data-id'); paintAnalysis(c); }
    else if (a === 'ba-latest') { ba.show = null; paintAnalysis(c); }
    else if (a === 'ba-fold') {
      var fold = t.closest('.ba-fold'), open = !fold.classList.contains('is-open');
      fold.classList.toggle('is-open', open);
      t.setAttribute('aria-expanded', String(open));
      if (window.ADspaceGroup) window.ADspaceGroup.keep('brand-analysis', c.id + ':' + fold.getAttribute('data-fold'), !open);
    }
  });
  var META_SAID = {
    'not-connected': 'Meta is not connected.',
    'token-refused': 'Meta refused the portal\'s access. The token needs renewing.',
    'rate-limited': 'Meta is busy. Try again in a few minutes.',
    'denied': 'This needs Clients: Brand at Manage.'
  };
  function metaSheet(c, b, opener) {
    var id = 'crmMetaSheet', box = $(id);
    if (!box) {
      box = document.createElement('div');
      box.className = 'sheet'; box.id = id; box.hidden = true;
      box.innerHTML = '<div class="sheet-card formsheet" role="dialog" aria-modal="true" aria-labelledby="crmMetaTitle">' +
        '<div class="sheet-head"><h3 id="crmMetaTitle">Meta accounts</h3>' +
        '<button class="iconbtn" id="crmMetaClose" type="button" aria-label="Close"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg></button></div>' +
        '<div class="sheet-body"><p class="meta-for" id="crmMetaFor"></p><div class="meta-body" id="crmMetaBody"></div><div class="msg" id="crmMetaMsg"></div></div>' +
        '<div class="sheet-foot"><button class="btn btn-primary" id="crmMetaSave" type="button">Save</button>' +
        '<button class="btn btn-quiet" id="crmMetaCancel" type="button">Cancel</button></div></div>';
      var after = $('crmBrandSheet');
      after.parentNode.insertBefore(box, after.nextSibling);
      $('crmMetaCancel').addEventListener('click', function () { shutSheet(id); });
      sheetClose('crmMetaClose', 'crmMetaCancel');
    }
    var mine = metaLinks.filter(function (l) { return (l.brand_id || null) === (b ? b.id : null); })[0] || {};
    var body = $('crmMetaBody'), save = $('crmMetaSave'), seq = ++metaSheetSeq;
    $('crmMetaFor').textContent = b ? b.name : '';
    $('crmMetaFor').hidden = !b;
    msg('crmMetaMsg', '');
    save.disabled = true;
    skeleton(body, 3);
    openSheet(id, opener);
    var load = function () {
      skeleton(body, 3);
      db.functions.invoke('meta-import', { body: { action: 'assets' } }).then(function (res) {
        if (seq !== metaSheetSeq) return;
        var d = (res && res.data) || {};
        if ((res && res.error) || d.error) {
          failLine(body, 'Meta accounts', META_SAID[d.error] || 'Meta did not answer.', load);
          return;
        }
        /* A link Meta no longer shows (an account no longer shared) stays
           offered, so a save never drops it unseen. */
        var withHeld = function (list, held) {
          list = (list || []).slice();
          [].concat(held || []).forEach(function (h) { if (h && !list.some(function (x) { return x.id === h.id; })) list.push(h); });
          return list;
        };
        var accs = withHeld(d.ad_accounts, mine.ad_accounts), pages = withHeld(d.pages, mine.page), igs = withHeld(d.instagram, mine.instagram);
        var held = {};
        (mine.ad_accounts || []).forEach(function (a) { held[a.id] = true; });
        var opt = function (list, pick) {
          return '<option value="">None</option>' + list.map(function (x) {
            return '<option value="' + esc(x.id) + '"' + (pick && pick.id === x.id ? ' selected' : '') + '>' + esc(x.name) + '</option>';
          }).join('');
        };
        body.innerHTML =
          '<section class="fsec"><h4 class="fsec-h">Ad accounts</h4>' +
            (accs.length ? '<div class="meta-accs" role="group" aria-label="Ad accounts">' + accs.map(function (a) {
              return '<label class="tickline"><input type="checkbox" value="' + esc(a.id) + '"' + (held[a.id] ? ' checked' : '') + '> <span>' + esc(a.name) + '</span></label>';
            }).join('') + '</div>' : '<p class="wl-none">No ad accounts.</p>') + '</section>' +
          '<section class="fsec"><h4 class="fsec-h">Pages</h4><div class="row fgrid">' +
            '<div><label class="field-label" for="crmMetaPage">Facebook Page</label><select class="select" id="crmMetaPage">' + opt(pages, mine.page) + '</select></div>' +
            '<div><label class="field-label" for="crmMetaIg">Instagram</label><select class="select" id="crmMetaIg">' + opt(igs, mine.instagram) + '</select></div>' +
          '</div></section>';
        save.disabled = false;
        save.onclick = function () {
          var pickOf = function (list, v) { return list.filter(function (x) { return x.id === v; })[0] || null; };
          var ticked = Array.prototype.map.call(body.querySelectorAll('.meta-accs input:checked'), function (x) { return pickOf(accs, x.value); }).filter(Boolean);
          save.disabled = true;
          db.rpc('meta_links_save', { p_client: c.id, p_brand: b ? b.id : null, p_ad_accounts: ticked,
            p_page: pickOf(pages, $('crmMetaPage').value), p_instagram: pickOf(igs, $('crmMetaIg').value) }).then(function (q) {
            save.disabled = false;
            var r = (q && q.data) || {};
            if ((q && q.error) || r.error) {
              msg('crmMetaMsg', r.error === 'denied' ? 'This needs Clients: Brand at Manage.' : r.error === 'bad-asset' ? 'Pick at most 20 ad accounts.' :
                (q && q.error && /function|schema cache/i.test(q.error.message)) ? 'This needs a database update.' : 'Not saved. The database refused the request.', 'err');
              return;
            }
            if (window.ADspaceSheet) window.ADspaceSheet.clean();
            shutSheet(id);
            msg('crmBrandNote', 'Saved.', 'ok');
            loadMeta(c);
          }).catch(function () { save.disabled = false; msg('crmMetaMsg', 'Not saved. Try again.', 'err'); });
        };
      }).catch(function () { if (seq === metaSheetSeq) failLine(body, 'Meta accounts', 'Meta did not answer.', load); });
    };
    load();
  }
  var PLUS_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>';
  function brandAsk(c, b) {
    window.ADspaceConfirm.ask({ title: b ? 'Rename brand' : 'Add brand', go: b ? 'Save' : 'Add',
      field: { label: 'Brand name', need: 'Enter the brand name.', value: b ? b.name : '', placeholder: 'ADspace Advertising' } },
      function (name) { saveBrand(c, b, name, b ? b.active : true); });
  }
  function saveBrand(c, b, name, active) {
    db.rpc('client_brand_save', { p_id: b ? b.id : null, p_client: c.id, p_name: name, p_active: active }).then(function (q) {
      var d = (q && q.data) || {};
      if ((q && q.error) || d.error) {
        msg('crmBrandNote', d.error === 'taken' ? 'That brand is already on the list.' : d.error === 'bad-name' ? 'Enter the brand name.' :
          d.error === 'denied' ? 'This needs Reports: White label.' : ((q && q.error && q.error.message) || 'Not saved.'), 'err');
        return;
      }
      msg('crmBrandNote', 'Saved.', 'ok');
      loadBrands(c);
    }).catch(function (e) { msg('crmBrandNote', (e && e.message) || 'Not saved.', 'err'); });
  }
  function fillBrand(c) {
    BRAND.forEach(function (f) { $(f[0]).value = c[f[1]] || ''; });
    $('crmNotes').value = c.brand_notes || '';
    BRIEF.forEach(function (f) { $(f[0]).value = briefOf(c)[f[1]] || ''; });
    paintLogoPreview();
    /* Reports: White label at Work (2026-10-07), a granted part. */
    $('crmWlSec').hidden = !mayPart('reports.whitelabel', 'work');
    $('crmWl').checked = Boolean(c.white_label);
    wlLogo = c.report_logo || null;
    $('crmWlFile').value = '';
    paintWl();
  }
  /* White label (2026-10-07): ticked, the client's wide logo heads the
     reports set to it, so the tick needs the logo, drawn down to 1200 by 400
     as a PNG so its transparency holds on the report's white page. */
  var wlLogo = null;
  function paintWl() {
    var on = $('crmWl').checked;
    $('crmWlRow').hidden = !on && !wlLogo;
    $('crmWlOff').hidden = !wlLogo;
    $('crmWlPreview').innerHTML = wlLogo ? '<img src="' + esc(wlLogo) + '" alt="Wide logo">' : '';
    $('crmWlPreview').hidden = !wlLogo;
    $('crmWlUp').lastChild.textContent = wlLogo ? 'Replace' : 'Upload';
  }
  function logoPng(file) {
    return new Promise(function (ok, bad) {
      var fr = new FileReader();
      fr.onerror = function () { bad(new Error('The file could not be read.')); };
      fr.onload = function () {
        var img = new Image();
        img.onerror = function () { bad(new Error('Choose a PNG, JPEG, WebP or SVG image.')); };
        img.onload = function () {
          var w = img.naturalWidth || img.width || 1200, h = img.naturalHeight || img.height || 400;
          var k = Math.min(1, 1200 / w, 400 / h);
          var cv = document.createElement('canvas');
          cv.width = Math.max(1, Math.round(w * k)); cv.height = Math.max(1, Math.round(h * k));
          cv.getContext('2d').drawImage(img, 0, 0, cv.width, cv.height);
          var url = cv.toDataURL('image/png');
          if (url.length > 1500000) { bad(new Error('The logo is too large. Use a smaller file.')); return; }
          ok(url);
        };
        img.src = String(fr.result || '');
      };
      fr.readAsDataURL(file);
    });
  }
  $('crmWl').addEventListener('change', function () { paintWl(); msg('crmBrandMsg', ''); });
  $('crmWlUp').addEventListener('click', function () { $('crmWlFile').click(); });
  $('crmWlOff').addEventListener('click', function () { wlLogo = null; $('crmWlFile').value = ''; paintWl(); });
  $('crmWlFile').addEventListener('change', function () {
    var f = this.files && this.files[0];
    if (!f) return;
    logoPng(f).then(function (url) { wlLogo = url; paintWl(); msg('crmBrandMsg', ''); })
      .catch(function (e) { msg('crmBrandMsg', e.message, 'err'); });
  });
  $('crmBrandEdit').addEventListener('click', function () {
    fillBrand(state.client); msg('crmBrandMsg', ''); msg('crmBrandNote', '');
    openSheet('crmBrandSheet', this);
  });
  $('crmBrandCancel').addEventListener('click', function () {
    shutSheet('crmBrandSheet'); fillBrand(state.client); msg('crmBrandMsg', '');
  });
  sheetClose('crmBrandClose', 'crmBrandCancel');

  // The registered name goes on an invoice in capitals, so it is kept that way.
  $('crmLegalName').addEventListener('input', function () {
    var pos = this.selectionStart;
    this.value = this.value.toUpperCase();
    try { this.setSelectionRange(pos, pos); } catch (e) {}
  });

  $('crmBillSave').addEventListener('click', function () {
    var was = Object.assign({}, state.client);
    /* The main contact held by id reads as following the main contact. */
    if (mainContact() && was.bill_contact_id === mainContact().id) was.bill_contact_id = null;
    /* No setting is SST applying, as `money.js` reads it. */
    was.sst_applies = state.client.sst_applies !== false;
    was.bill_sgd = !!state.client.bill_sgd;
    var patch = { sst_applies: $('crmSstApplies').checked };
    if (!$('crmBillInRow').hidden) patch.bill_sgd = $('crmBillIn').value === 'SG';
    BILLING.forEach(function (f) { patch[f[1]] = val(f[0]) || null; });
    if (patch.legal_name) patch.legal_name = patch.legal_name.toUpperCase();
    db.from('clients').update(patch).eq('id', state.client.id).select('id').then(function (r) {
      if (r.error) { msg('crmBillMsg', r.error.message, 'err'); return; }
      if (!(r.data || []).length) { msg('crmBillMsg', 'Not saved. The database refused the request.', 'err'); return; }
      Object.keys(patch).forEach(function (k) { state.client[k] = patch[k]; });
      var still = billingMissing(state.client);
      /* Billing is its own part, so the record names what changed and never
         the values: somebody reading Clients activity may not read Billing. */
      var what = changed(was, patch, BILLING.map(function (f) { return [f[1], f[2]]; })
        .concat([['sst_applies', 'SST applies']]), { names: true });
      /* The currency is no secret: it is filed from and to. */
      if ('bill_sgd' in patch && patch.bill_sgd !== was.bill_sgd) {
        what = [what, 'Bill in: ' + (was.bill_sgd ? 'S$' : 'RM') + ' → ' + (patch.bill_sgd ? 'S$' : 'RM')].filter(Boolean).join(' · ');
      }
      log('client.billing', state.client.name, [what, still.length ? still.length + ' fields still needed' : 'complete']
        .filter(Boolean).join(' · '));
      if (window.ADspaceSheet) window.ADspaceSheet.clean();
      shutSheet('crmBillSheet');
      /* The details form's answers taken in by this Save (2026-10-14). */
      if (state.detUse) {
        var used = state.detUse; state.detUse = null;
        db.rpc('client_details_used', { p_id: used, p_client: state.client.id }).then(function () { loadDetForm(); }).catch(function () {});
      }
      var goActive = state.toActive === state.client.id && !still.length;
      var goLetter = state.toLetter && state.toLetter.id === state.client.id && !still.length ? state.toLetter : null;
      state.toActive = null; state.toLetter = null;
      openClient(state.client);
      msg('crmBillNote', still.length
        ? 'Saved. Required before Active: ' + still.join(', ') + '.'
        : 'Saved.',
        still.length ? 'warn' : 'ok');
      /* Active was asked for and billing is now complete: the move goes on
         the way the stage select takes it, the head brought back into view
         (2026-10-20, CLI-6). */
      if (goActive && (state.client.stage || 'lead') !== 'active') {
        var c = state.client;
        var toHead = function () {
          var head = document.querySelector('#sectionClients .rec-id'), bar = document.querySelector('.console-head');
          if (head) window.scrollTo(0, Math.max(0, head.getBoundingClientRect().top + window.pageYOffset - (bar ? bar.getBoundingClientRect().bottom : 0) - 12));
        };
        if (!String(c.client_code || '').trim()) {
          askCode(c, function (code) { return moveStage(c, 'active', null, { client_code: code, inSheet: true, after: toHead }); });
        } else moveStage(c, 'active', null, { after: toHead });
      }
      /* A Letter of Offer was asked for: billing now complete, the letter
         sheet opens on the lines it was asked with. */
      if (goLetter) loadServices(function () { openPick(goLetter.only); });
    });
  });

  /* The disc is how the logo is judged, because that is the shape it is drawn
     in on every mockup and on the record's own mark. A URL that will not load
     says so by staying empty rather than by drawing the browser's broken
     image mark over a client's brand. */
  function paintLogoPreview() {
    var img = $('crmLogoPreviewImg');
    if (!img) return;
    var url = val('crmLogo');
    img.hidden = !url;
    if (url) img.src = url;
  }
  if (bridge.wireLogoUpload) bridge.wireLogoUpload('crmLogoUp', 'crmLogoFile', 'crmLogo', 'crmBrandMsg', function () { return state.client; });
  if ($('crmLogo')) {
    $('crmLogo').addEventListener('input', paintLogoPreview);
    $('crmLogoPreviewImg').addEventListener('error', function () { this.hidden = true; });
  }

  $('crmBrandSave').addEventListener('click', function () {
    var was = Object.assign({}, state.client);
    var patch = { brand_notes: val('crmNotes') || null };
    BRAND.forEach(function (f) { patch[f[1]] = val(f[0]) || null; });
    was.white_label = Boolean(was.white_label); was.report_logo = was.report_logo || null;
    if (!$('crmWlSec').hidden && $('crmWl').checked && !wlLogo) {
      msg('crmBrandMsg', 'Upload the wide logo for reports.', 'err');
      $('crmWlUp').focus();
      return;
    }
    /* The brief is one object; only the parts that hold words are kept,
       and it is sent only where a part changed. */
    var brief = {}, briefWas = briefOf(was), briefMoved = [];
    BRIEF.forEach(function (f) {
      var v = val(f[0]);
      if (v) brief[f[1]] = v;
      if ((v || '') !== (briefWas[f[1]] || '')) briefMoved.push(f[2]);
    });
    if (briefMoved.length) patch.brief = Object.keys(brief).length ? brief : null;
    if (!$('crmWlSec').hidden) {
      if ($('crmWl').checked !== was.white_label) patch.white_label = $('crmWl').checked;
      if (wlLogo !== was.report_logo) patch.report_logo = wlLogo;
    }
    db.from('clients').update(patch).eq('id', state.client.id)
      .select('id').then(function (r) {
        if (r.error) { msg('crmBrandMsg', /brand-columns/.test(r.error.message || '') ? 'The content brief and brand notes need Clients: Brand at Manage.' : r.error.message, 'err'); return; }
        if (!(r.data || []).length) { msg('crmBrandMsg', 'Not saved. The database refused the request.', 'err'); return; }
        Object.keys(patch).forEach(function (k) { state.client[k] = patch[k]; });
        log('client.brand', state.client.name, [changed(was, patch, [
          ['website', 'Website'], ['phone', 'Phone'], ['handle_ig', 'Instagram'], ['handle_fb', 'Facebook'],
          ['handle_tiktok', 'TikTok'], ['handle_xhs', 'rednote'], ['logo_url', 'Logo'], ['brand_notes', 'Brand notes']]),
          briefMoved.length ? 'Content brief: ' + briefMoved.join(', ') + ' changed' : '',
          'white_label' in patch ? 'White label: ' + (was.white_label ? 'On → Off' : 'Off → On') : '',
          'report_logo' in patch ? (patch.report_logo ? (was.report_logo ? 'Wide logo replaced' : 'Wide logo set') : 'Wide logo removed') : ''
        ].filter(Boolean).join('; '));
        if (window.ADspaceSheet) window.ADspaceSheet.clean();
        shutSheet('crmBrandSheet');
        openClient(state.client);
        msg('crmBrandNote', 'Saved.', 'ok');
      });
  });

  // ---- Contacts -----------------------------------------------------------
  /* Nothing here is deleted by a click. A removed contact is hidden with a
     timestamp and sits under "Removed" until someone puts them back. */
  var showRemovedContacts = false;

  /* A contact added from the details form is the client's billing contact,
     as the client named them. */
  function dfBillTo(id, name) {
    var c = state.client;
    db.from('clients').update({ bill_contact_id: id }).eq('id', c.id).select('id').then(function (r) {
      if (!r.error && (r.data || []).length) {
        c.bill_contact_id = id;
        log('client.billing', c.name, 'Billing contact · from the details form');
      }
      loadContacts();
    }).catch(function () { loadContacts(); });
  }
  function loadContacts() {
    var box = $('crmContacts');
    if (!box.querySelector('.crm-table')) skeleton(box, 3);
    db.from('client_contacts').select('*').eq('client_id', state.client.id)
      .order('is_primary', { ascending: false }).order('name').then(function (r) {
        if (r.error) { failLine(box, 'Contacts', r.error.message, loadContacts); ovFailed('contacts', true); return; }
        ovFailed('contacts', false);
        var all = r.data || [];
        state.contacts = all.filter(function (c) { return !c.archived_at; });
        paintSummary();
        var gone = all.filter(function (c) { return c.archived_at; });
        paintBilling(state.client);
        if (state.detForm) paintDetForm();
        $('crmContactNames').innerHTML = state.contacts.map(function (ct) {
          return '<option value="' + esc(ct.name) + '"></option>';
        }).join('');
        box.innerHTML = '';
        var shown = state.contacts.concat(showRemovedContacts ? gone : []);
        if (!shown.length) {
          box.innerHTML = '<div class="empty">No contacts.</div>';
        } else {
          var table = document.createElement('div');
          table.className = 'crm-table';
          table.innerHTML = '<div class="crm-head svc-row ct-row"><span>Contact</span><span>Reach</span><span></span></div>';
          shown.forEach(function (ct) { table.appendChild(contactRow(ct, Boolean(ct.archived_at))); });
          box.appendChild(table);
        }
        if (gone.length) {
          var t = document.createElement('button');
          t.type = 'button'; t.className = 'linkish crm-removed-toggle';
          t.textContent = (showRemovedContacts ? 'Hide ' : 'Show ') + gone.length +
            ' removed contact' + (gone.length === 1 ? '' : 's');
          t.addEventListener('click', function () { showRemovedContacts = !showRemovedContacts; loadContacts(); });
          box.appendChild(t);
        }
      });
  }

  /* A contact is a row: who, how to reach them, a ⋯. The main contact
     carries the word. */
  /* wa.me wants a full international number and no punctuation. A Malaysian
     mobile is keyed as `0143132195`, and stripping the punctuation alone sent
     people to `wa.me/0143132195`, which is not a number anywhere: the country
     code is missing and the leading zero is a national prefix. Prefixing `6`
     keeps the zero and gives `60143132195`, which is the same thing as 60
     plus the number without it.

     A number already carrying its country code is left exactly as it is, and
     one with no leading zero takes its client's market, because a Singapore
     mobile has eight digits and no national prefix to replace. */
  function waNumber(raw) {
    /* As the team types numbers (the user, 2026-10-09): the one reading is
       `ADspaceAPI.waNumber`, which `wa_number` matches in SQL. */
    return window.ADspaceAPI.waNumber(raw);
  }
  /* WhatsApp lets a person hide their number behind a username, and some
     contacts now reach us that way only: `wa.me/@name` opens the chat where
     `wa.me/60…` opens it for a number. The contact's `whatsapp` column holds
     `@name` for a username and the number otherwise, so one column says how
     to reach them and every link reads it the same way. What was typed is
     taken whole or pasted as a link (`https://wa.me/@name`), with the @
     already printed in front of the field. */
  function waUser(raw) {
    var s = String(raw || '').trim()
      .replace(/^https?:\/\//i, '').replace(/^(?:www\.)?wa\.me\//i, '')
      .replace(/^@+/, '').replace(/\/+$/, '');
    return s;
  }
  function waUserOk(u) { return /^[A-Za-z0-9._]{1,35}$/.test(u); }
  function waHandle(raw) {
    var s = String(raw || '').trim();
    return s.charAt(0) === '@' ? s.slice(1) : '';
  }
  /* What the field stores. Digits typed into it are a number (WhatsApp has
     no all-digit username, and `@0123…` cannot be messaged); a name is
     `@name`; empty follows the phone. */
  function waIsNumber(u) { return /^\+?[\d\s\-()]+$/.test(u) && /\d/.test(u); }
  function waStore(raw, phone) {
    var u = waUser(raw);
    if (!u) return phone || null;
    return waIsNumber(u) ? u : '@' + u;
  }
  function waLink(raw, market, label) {
    var u = waHandle(raw);
    var n = u ? '@' + encodeURIComponent(u) : waNumber(raw, market);
    if (!n) return '';
    return '<a class="plink" href="https://wa.me/' + esc(n) +
      '" target="_blank" rel="noopener">' + esc(label || 'WhatsApp') + '</a>';
  }

  function contactRow(ct, removed) {
    var row = document.createElement('div');
    row.className = 'svc-row ct-row' + (removed ? ' is-off' : '');

    /* Their preference, not a claim about them: "Writes in English" reads as
       a judgement on what the person can do, when all it records is which
       language we write to them in. */
    var sub = [ct.role, 'Prefers ' + (LANG_WORD[ct.lang] || 'English')].filter(Boolean).join(' · ');
    row.innerHTML =
      /* The name, then its chips at the right of the same line before the ⋯,
         as every card head reads. Green is the live state, and on this row
         the live thing is the sign-in: main contact is a designation, so it
         reads neutral and the accent is spent once. */
      '<span class="svc-name"><span class="ct-top"><b>' + esc((ct.salutation ? ct.salutation + ' ' : '') + ct.name) + '</b>' +
        (removed ? '<span class="tone is-off">Removed</span>' : ct.is_primary ? '<span class="tone">Main contact</span>' : '') +
        (!removed && ct.portal_access ? '<span class="tone is-ok">Portal access</span>' : '') +
        '</span><small>' + esc(sub) + '</small></span>' +
      '<span class="crm-reach">' +
        (ct.phone ? '<a class="plink" href="tel:' + esc(ct.phone) + '">' + esc(ct.phone) + '</a>' : '') +
        waLink(ct.whatsapp || ct.phone, (state.client || {}).market) +
        (ct.email ? '<a class="plink" href="mailto:' + esc(ct.email) + '">' + esc(ct.email) + '</a>' : '') +
      '</span>' +
      '<span class="team-act">' +
        '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
        '<div class="kmenu" data-menu hidden>' +
          (removed
            /* The hard delete, once the soft one has been made, drawn only
               where the Contacts part is managed. */
            ? ADspaceMenu.items([[], [], [], [], [{ a: 'restore', label: 'Restore' }],
                [{ a: 'del', label: 'Delete', need: 'clients.contacts:manage' }]])
            : ADspaceMenu.items([[],
                [{ a: 'edit', label: 'Edit', need: 'clients.contacts:work' },
                 !ct.is_primary && { a: 'primary', label: 'Make main contact' }],
                [ct.portal_access && { a: 'invite', label: 'Send invitation' }],
                [],
                [ct.portal_access ? { a: 'unportal', label: 'Revoke portal access' } : { a: 'portal', label: 'Enable portal access' }],
                [{ a: 'del', label: 'Remove', need: 'clients.contacts:work', attrs: 'data-soft' }]])) +
        '</div>' +
      '</span>';
    wireMenu(row);
    var on = function (a, fn) { var el = row.querySelector('[data-a="' + a + '"]'); if (el) el.addEventListener('click', fn); };
    on('edit',    function () { openContact(ct); });
    on('primary', function () { makePrimary(ct); });
    on('portal',   function () { askPortal(ct); });
    on('invite',   function () { sendInvite(ct); });
    on('unportal', function () { setPortal(ct, false); });
    /* One listener for Delete: on a removed contact it was also wired to
       Remove, which removed it again, filed it and offered an Undo that
       would bring it back, whatever the question then answered. */
    on('del',     function () { if (removed) purgeContact(ct); else archiveContact(ct, true); });
    on('restore', function () { archiveContact(ct, false); });
    return row;
  }

  /* Portal access is one switch on the contact; the email is the sign-in
     address. Enabling it always asks the invite function to make the login,
     so the person can sign in whether or not sign-ups are open and never has
     to register anything. Whether the invitation goes out with it is asked,
     because the client is often told on a call and an email arriving out of
     nowhere is the account manager's conversation to time, not ours. */
  var portalFor = null;

  function askPortal(ct, invite) {
    // The ⋯ it was chosen from would otherwise sit open behind the sheet.
    Array.prototype.forEach.call(document.querySelectorAll('.kmenu'), function (m) { m.hidden = true; });
    if (!ct.email) { msg('ctMsg', 'An email is required.', 'err'); openContact(ct); return; }
    portalFor = ct;
    $('portalFacts').innerHTML = [['Person', ct.name], ['Sign-in email', ct.email]]
      .map(function (f) { return '<div><dt>' + esc(f[0]) + '</dt><dd>' + esc(f[1]) + '</dd></div>'; }).join('');
    // Off by default: access is the decision, an email is a separate one, and
    // the client can sign in without ever receiving one.
    $('portalInvite').checked = Boolean(invite);
    /* Asked at Active, it reads as the question it is (2026-10-26). */
    $('portalHeading').textContent = invite ? 'Give client portal access?' : 'Enable portal access';
    msg('portalMsg', '');
    $('portalSheet').hidden = false;
  }
  function closePortal() { $('portalSheet').hidden = true; portalFor = null; }
  $('portalClose').addEventListener('click', closePortal);
  $('portalCancel').addEventListener('click', closePortal);
  $('portalGo').addEventListener('click', function () {
    if (!portalFor) return;
    var ct = portalFor, invite = $('portalInvite').checked;
    closePortal();
    setPortal(ct, true, invite);
  });

  /* The invitation on its own, for a contact who already has access: told on
     a call today, emailed when they ask for it next week. */
  function sendInvite(ct) {
    var notify = true;
    // Nothing repaints after this one, so the menu it was chosen from has to
    // be put away here or it sits open over the answer.
    Array.prototype.forEach.call(document.querySelectorAll('.kmenu'), function (m) { m.hidden = true; });
    if (!ct.email) { msg('crmWorkMsg', 'An email is required.', 'err'); return; }
    // Mail leaves the building and cannot be recalled, and this sits one
    // place away from Edit in the same menu.
    window.ADspaceConfirm.ask({
      title: 'Send an invitation',
      body: 'An email goes to ' + ct.email + ' with a sign-in link. '
          + 'Once sent, it cannot be withdrawn.',
      go: 'Send'
    }, function () { send(); });
    function send() {
    msg('crmWorkMsg', notify ? 'Sending…' : 'Working…');
    API.invokeFn('invite-member', { email: ct.email, name: ct.name, kind: 'client', notify: Boolean(notify) })
      .then(function (res) {
        if (res.error) { msg('crmWorkMsg', res.why, 'err'); return; }
        stampLogin(ct);
        if (notify) log('contact.portal_invite', state.client.name + ' · ' + ct.name, ct.email);
        msg('crmWorkMsg', !notify ? 'Login created.'
          : res.data.already ? 'A login already exists. Sign-in link sent to ' + ct.email + '.'
          : 'Invitation sent to ' + ct.email + '.', 'ok');
      });
    }
  }

  /* The login exists from here on, whichever way it was made. Recorded on the
     contact so the row can tell the difference between a client who can sign
     in and one who only has the switch turned on. */
  function stampLogin(ct) {
    if (ct.portal_login_at) return;
    ct.portal_login_at = new Date().toISOString();
    db.from('client_contacts').update({ portal_login_at: ct.portal_login_at })
      .eq('id', ct.id).then(function () { loadContacts(); }, function () {});
  }

  function setPortal(ct, on, invite) {
    db.from('client_contacts').update({ portal_access: on }).eq('id', ct.id).select('id').then(function (r) {
      if (r.error) { msg('crmWorkMsg', r.error.message, 'err'); return; }
      if (!(r.data || []).length) { msg('crmWorkMsg', 'Not saved. The database refused the request.', 'err'); return; }
      log(on ? 'contact.portal_on' : 'contact.portal_off', state.client.name + ' · ' + ct.name, ct.email || '');
      msg('crmWorkMsg', '');
      loadContacts();
      loadRequests();
      // Putting access back does not email again: the login already exists,
      // and an undo is a correction, not a second announcement.
      if (!on) { undoBar(ct.name + ': portal access revoked.', function () { setPortal(ct, true, false); }); return; }
      /* Access on its own is enough: the login is made when they sign in.
         An invitation only goes out when somebody asked for one. */
      if (!invite) { msg('crmWorkMsg', 'Access enabled.', 'ok'); return; }
      API.invokeFn('invite-member', { email: ct.email, name: ct.name, kind: 'client', notify: true })
        .then(function (res) {
          if (res.error) { msg('crmWorkMsg', 'Access enabled. Invitation not sent: ' + res.why, 'warn'); return; }
          stampLogin(ct);
          msg('crmWorkMsg', res.data.already ? 'Access enabled. A login already exists.'
            : 'Access enabled. Invitation sent to ' + ct.email + '.', 'ok');
        });
    });
  }

  /* A menu in a table row would be clipped by the table, so it is placed on
     the viewport under its button. It closes on scroll, as a card menu does
     not need to. */
  function wireMenu(row) {
    var menu = row.querySelector('[data-menu]');
    var btn = row.querySelector('[data-a="menu"]');
    btn.addEventListener('click', function () {
      var open = menu.hidden;
      Array.prototype.forEach.call(document.querySelectorAll('.kmenu'), function (m) { m.hidden = true; });
      menu.hidden = !open;
      this.setAttribute('aria-expanded', String(open));
      if (open && btn.closest('.team-act')) {
        window.ADspaceMenu.place(btn, menu);
      }
    });
  }
  window.ADspaceMenu.onScroll(function () {
    Array.prototype.forEach.call(document.querySelectorAll('.team-act .kmenu'), function (m) { m.hidden = true; });
  });

  var editingContact = null;
  function openContact(ct) {
    editingContact = ct || null;
    openSheet('crmContactBox');
    $('crmContactTitle').textContent = ct ? 'Edit contact' : 'New contact';
    $('ctSave').textContent = 'Save';
    $('ctSalutation').value = ct ? (ct.salutation || '') : '';
    $('ctName').value = ct ? (ct.name || '') : '';
    $('ctRole').value = ct ? (ct.role || '') : '';
    $('ctPhone').value = ct ? (ct.phone || '') : '';
    /* The stored number when it is not a username: a lead from the website
       holds a number alone, and an empty field saved over it erased it. */
    $('ctWa').value = ct ? (waHandle(ct.whatsapp) || (ct.whatsapp || '')) : '';
    $('ctWa').dataset.was = $('ctWa').value;
    $('ctEmail').value = ct ? (ct.email || '') : '';
    $('ctLang').value = ct ? (ct.lang || 'en') : 'en';
    $('ctPrimary').checked = ct ? Boolean(ct.is_primary) : !state.contacts.length;
    msg('ctMsg', '');
    /* Nothing is focused when the sheet opens: on a phone a field taking
       focus raises the keyboard and zooms the page past the rest of the form,
       and the first field is rarely the one somebody came to change. */
  }
  function shutContact() { shutSheet('crmContactBox'); editingContact = null; state.dfContact = null; }
  $('crmAddContact').addEventListener('click', function () { openContact(null); });
  $('ctCancel').addEventListener('click', shutContact);

  $('ctSave').addEventListener('click', function () {
    var name = val('ctName');
    if (!name) { msg('ctMsg', 'A contact needs a name.', 'err'); $('ctName').focus(); return; }
    var phone = val('ctPhone'), waU = waUser(val('ctWa'));
    if (waU && !waIsNumber(waU) && !waUserOk(waU)) {
      msg('ctMsg', 'A WhatsApp username uses letters, numbers, full stops and underscores.', 'err');
      $('ctWa').focus(); return;
    }
    var row = {
      salutation: $('ctSalutation').value || null,
      name: name, role: val('ctRole') || null, phone: phone || null,
      whatsapp: waStore(val('ctWa'), phone),
      email: val('ctEmail') || null, lang: $('ctLang').value,
      is_primary: $('ctPrimary').checked
    };
    /* Sent only where the field changed, so an edit to the name never
       touches how the person is reached. */
    if (editingContact && val('ctWa') === ($('ctWa').dataset.was || '').trim()) delete row.whatsapp;
    /* A new main contact is the contact saved, then the swap in one
       transaction (`client_contact_make_primary`): a swap that fails leaves
       the old main contact, never a client with none. */
    var swap = row.is_primary && state.contacts.some(function (c) {
      return c.is_primary && !(editingContact && c.id === editingContact.id);
    });
    var write = Object.assign({}, row);
    if (swap) write.is_primary = false;
    var after = function (r) {
      if (r.error) { msg('ctMsg', r.error.message, 'err'); return; }
      if (!(r.data || []).length) { msg('ctMsg', 'Not saved. The database refused the request.', 'err'); return; }
      var newId = r.data[0].id;
      var done = function (swapped) {
        log(editingContact ? 'contact.edited' : 'contact.added', state.client.name + ' · ' + name,
          editingContact ? changed(editingContact, Object.assign({}, row, { is_primary: swapped ? true : Boolean(editingContact.is_primary) }), [['salutation', 'Salutation'], ['name', 'Name'], ['role', 'Role'], ['phone', 'Phone'],
            ['whatsapp', 'WhatsApp'], ['email', 'Email'], ['lang', 'Language'], ['is_primary', 'Main contact']]) : (row.role || ''));
        var fromForm = !editingContact && state.dfContact;
        shutContact();
        if (!swapped && swap) msg('crmWorkMsg', 'Saved. The main contact was not changed: the database refused the request.', 'err');
        if (fromForm && !row.is_primary && mayPart('clients.billing', 'work')) dfBillTo(newId, name); else loadContacts();
      };
      if (!swap) { done(false); return; }
      db.rpc('client_contact_make_primary', { p_contact: newId }).then(function (q) {
        done(Boolean(!q.error && q.data && q.data.ok));
      }).catch(function () { done(false); });
    };
    if (editingContact) {
      db.from('client_contacts').update(write).eq('id', editingContact.id).select('id').then(after);
    } else {
      write.client_id = state.client.id;
      db.from('client_contacts').insert(write).select('id').then(after);
    }
  });

  function makePrimary(ct) {
    db.rpc('client_contact_make_primary', { p_contact: ct.id }).then(function (r) {
      var d = r.data || {};
      if (r.error || !d.ok) {
        msg('crmWorkMsg', r.error && /function|schema cache/i.test(r.error.message) ? 'This needs a database update.'
          : 'Not saved. The database refused the request.', 'err');
        loadContacts(); return;
      }
      log('contact.primary', state.client.name + ' · ' + ct.name, '');
      loadContacts();
    }).catch(function () { msg('crmWorkMsg', 'Not saved. Please try again.', 'err'); });
  }
  function archiveContact(ct, away) {
    var patch = away ? { archived_at: new Date().toISOString(), is_primary: false }
                     : { archived_at: null };
    db.from('client_contacts').update(patch).eq('id', ct.id).select('id').then(function (r) {
      if (r.error) { msg('crmWorkMsg', r.error.message, 'err'); return; }
      if (!(r.data || []).length) { msg('crmWorkMsg', 'Not saved. The database refused the request.', 'err'); return; }
      log(away ? 'contact.removed' : 'contact.restored', state.client.name + ' · ' + ct.name, '');
      if (away) undoBar(ct.name + ' removed.', function () { archiveContact(ct, false); });
      loadContacts();
    });
  }

  /* Removed is not deleted, and both are wanted for different reasons.
     A person leaves a company and the record of the calls we had with them,
     the letter addressed to them and the billing contact they were still have
     to make sense, so Remove hides the row and keeps all of that readable.
     PDPA pulls the other way: personal data we no longer need should not be
     kept for ever, and a contact keyed in by mistake should be able to go.
     So it is Void then Delete, as it is for a letter: remove first, then an
     admin can take the row out for good. Both foreign keys to a contact are
     `on delete set null`, and a request keeps the name it was raised under as
     text, so nothing that survives is left pointing at a hole. */
  function purgeContact(ct) {
    Array.prototype.forEach.call(document.querySelectorAll('.kmenu'), function (m) { m.hidden = true; });
    window.ADspaceConfirm.ask({
      title: 'Delete',
      body: ct.name + ' goes from this client for good. There is no restore. '
          + 'Calls, letters and requests keep the name as it was written at the time.',
      go: 'Delete',
      tone: 'danger',
      field: { label: 'Type the contact name to confirm', placeholder: ct.name, match: ct.name, need: 'Type the contact name to confirm.', mismatch: 'The contact name does not match.' }
    }, function () {
      db.from('client_contacts').delete().eq('id', ct.id).select('id').then(function (r) {
        if (r.error) { msg('crmWorkMsg', r.error.message, 'err'); return; }
        if (!(r.data || []).length) { msg('crmWorkMsg', 'Not deleted. The database refused the request.', 'err'); return; }
        log('contact.deleted', state.client.name + ' · ' + ct.name, ct.email || '');
        msg('crmWorkMsg', 'Deleted.', 'ok');
        loadContacts();
        loadRequests();
      });
    });
  }

  /* One line with an Undo on it, for the few seconds after a removal when a
     person realises. Nothing is lost either way; this is only the fast path. */
  var undoTimer = null;
  function undoBar(text, undo, host) {
    /* Drawn where the act happened when it was not on a record (the list's
       Select, 2026-10-07): one line under `host`. */
    if (host && host.parentNode) { window.ADspaceAdmin.undoHere(text, undo, host); return; }
    var bar = $('crmUndo');
    bar.hidden = false;
    bar.innerHTML = '<span>' + esc(text) + '</span><button class="btn btn-sm" type="button">Undo</button>';
    bar.querySelector('button').addEventListener('click', function () { bar.hidden = true; undo(); });
    clearTimeout(undoTimer);
    undoTimer = setTimeout(function () { bar.hidden = true; }, 8000);
  }

  // ---- Calls and visits ---------------------------------------------------
  var showRemovedTouches = false;

  function loadTouches() {
    var box = $('crmTouches');
    if (!box.querySelector('.touch')) skeleton(box, 3);
    db.from('client_touches').select('*').eq('client_id', state.client.id)
      .order('happened_at', { ascending: false }).order('created_at', { ascending: false })
      .then(function (r) {
        if (r.error) { failLine(box, 'Calls and visits', r.error.message, loadTouches); ovFailed('calls', true); return; }
        ovFailed('calls', false);
        var all = r.data || [];
        state.touches = all.filter(function (t) { return !t.archived_at; });
        paintSummary();
        var gone = all.filter(function (t) { return t.archived_at; });
        box.innerHTML = '';
        if (!state.touches.length) {
          box.innerHTML = '<div class="empty">No entries.</div>';
        }
        state.touches.forEach(function (tc) { box.appendChild(touchRow(tc, false)); });
        if (gone.length) {
          var t = document.createElement('button');
          t.type = 'button'; t.className = 'linkish crm-removed-toggle';
          t.textContent = (showRemovedTouches ? 'Hide ' : 'Show ') + gone.length +
            ' removed ' + (gone.length === 1 ? 'entry' : 'entries');
          t.addEventListener('click', function () { showRemovedTouches = !showRemovedTouches; loadTouches(); });
          box.appendChild(t);
          if (showRemovedTouches) gone.forEach(function (tc) { box.appendChild(touchRow(tc, true)); });
        }
      });
  }

  function touchRow(tc, removed) {
    var open = tc.next_action && !tc.done_at;
    var due = open && tc.next_at && tc.next_at < today();
    var row = document.createElement('div');
    row.className = 'touch' + (due ? ' is-due' : '') + (removed ? ' is-off' : '');
    row.innerHTML =
      '<div class="touch-when"><b>' + esc(niceDate(tc.happened_at)) + '</b>' +
        '<span class="tone">' + esc(KIND_WORD[tc.kind] || tc.kind) + '</span>' +
        (removed ? '<span class="tone is-off">Removed</span>' : '') + '</div>' +
      '<div class="touch-body">' +
        '<p class="touch-summary">' + esc(tc.summary) + '</p>' +
        '<p class="touch-meta">' +
          [tc.contact_name ? 'With ' + tc.contact_name : '', whoLogged(tc.by_whom) ? 'by ' + whoLogged(tc.by_whom) : '',
           tc.updated_at ? 'edited' : '']
            .filter(Boolean).map(esc).join(' · ') +
        '</p>' +
        meetLine(tc, removed) +
        (tc.next_action ? '<p class="touch-next' + (due ? ' is-due' : '') + (tc.done_at ? ' is-done' : '') + '">' +
          (tc.done_at ? 'Done: ' : 'Next: ') + esc(tc.next_action) +
          (tc.next_at ? ' · by ' + esc(niceDate(tc.next_at)) : '') +
          (due ? ' · overdue' : '') + '</p>' : '') +
      '</div>' +
      '<div class="touch-actions">' +
        /* The commonest act stays on the row (Done, Reopen); Edit, Remove,
           Restore and Delete are the row's ⋯ as a contact's are, Delete
           last (2026-10-10). */
        (!removed && open ? '<button class="btn btn-sm" data-a="done" type="button">Done</button>' : '') +
        (!removed && tc.done_at ? '<button class="btn btn-quiet btn-sm" data-a="undone" type="button">Reopen</button>' : '') +
        '<span class="team-act">' +
          '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
          '<div class="kmenu" data-menu hidden>' +
            (removed
              ? ADspaceMenu.items([[], [], [], [], [{ a: 'restore', label: 'Restore' }],
                  [{ a: 'purge', label: 'Delete', need: 'clients.calls:manage' }]])
              : ADspaceMenu.items([[], [{ a: 'edit', label: 'Edit', need: 'clients.calls:work' }], [], [], [],
                  [{ a: 'del', label: 'Remove', need: 'clients.calls:work', attrs: 'data-soft' }]])) +
          '</div>' +
        '</span>' +
      '</div>';
    wireMenu(row);
    var on = function (a, fn) { var el = row.querySelector('[data-a="' + a + '"]'); if (el) el.addEventListener('click', fn); };
    on('edit',    function () { openTouch(tc); });
    on('done',    function () { markDone(tc, true); });
    on('undone',  function () { markDone(tc, false); });
    on('del',     function () { archiveTouch(tc, true); });
    on('restore', function () { archiveTouch(tc, false); });
    on('purge',   function () { purgeTouch(tc); });
    on('meet',    function (ev) { bookMeet(tc, 'create', ev.currentTarget); });
    return row;
  }

  /* A removed entry goes for good (Clients: Calls at Manage, re-checked by
     the table's delete policy), asked first, with no restore. */
  function purgeTouch(tc) {
    window.ADspaceConfirm.ask({
      title: 'Delete',
      body: 'This ' + (KIND_WORD[tc.kind] || 'entry').toLowerCase() + ' on ' + niceDate(tc.happened_at) +
          ' goes from this client for good. There is no restore.',
      go: 'Delete',
      tone: 'danger'
    }, function () {
      db.from('client_touches').delete().eq('id', tc.id).select('id').then(function (r) {
        if (r.error) { msg('crmWorkMsg', r.error.message, 'err'); return; }
        if (!(r.data || []).length) { msg('crmWorkMsg', 'Not deleted. The database refused the request.', 'err'); return; }
        log('client.touch_deleted', state.client.name, (KIND_WORD[tc.kind] || '') + ' · ' + niceDate(tc.happened_at));
        msg('crmWorkMsg', 'Deleted.', 'ok');
        loadTouches();
      }).catch(function (e) { msg('crmWorkMsg', (e && e.message) || 'Not deleted.', 'err'); });
    });
  }

  /* A meeting booked outside a month (2026-10-05): its time and length, the
     link to join while it is still ahead, and Create Google Meet where it has
     a time ahead and no link yet, through the same meet-create the month's
     content meeting uses. */
  var MEET_LINK = /^https:\/\/([a-z0-9-]+\.)*(meet\.google\.com|zoom\.us|teams\.microsoft\.com|teams\.live\.com)\//i;
  /* Hours and minutes in Malaysia, wherever the browser is. */
  function myt(d) { var x = new Date(d.getTime() + 8 * 3600000); return { h: x.getUTCHours(), m: x.getUTCMinutes() }; }
  function clockOf(d) { return window.ADspaceClock.clock(d); }
  function lengthWord(n) {
    n = Number(n) || 30;
    return n < 60 ? n + ' min' : (n % 60 ? (n / 60) + ' hours' : (n === 60 ? '1 hour' : (n / 60) + ' hours'));
  }
  function meetLine(tc, removed) {
    if (tc.kind !== 'meeting' || (!tc.meet_at && !tc.meet_link)) return '';
    var at = tc.meet_at ? new Date(tc.meet_at) : null;
    var ahead = at && at.getTime() + (Number(tc.meet_minutes) || 30) * 60000 > Date.now();
    var parts = at ? [clockOf(at), lengthWord(tc.meet_minutes)] : [];
    var acts = '';
    if (!removed && ahead && tc.meet_link) {
      acts += '<a class="plink" href="' + esc(tc.meet_link) + '" target="_blank" rel="noopener">' +
        '<span class="plink-text">' + esc(tc.meet_link.replace(/^https:\/\//, '')) + '</span></a>';
    }
    if (!removed && ahead && !tc.meet_link) {
      acts += '<button class="btn btn-sm" data-a="meet" data-need="clients.calls:work" type="button">Create Google Meet</button>';
    }
    return '<div class="touch-meet"><span>' + esc(parts.join(' · ')) + '</span>' + acts + '</div>' +
      '<p class="msg touch-meetmsg" hidden></p>';
  }
  function meetAsk(tc, action, done) {
    if (!db.functions || !db.functions.invoke) { done({ error: 'meet-not-set-up' }); return; }
    db.functions.invoke('meet-create', { body: { touchId: tc.id, action: action } })
      .then(function (r) { done(r.error ? { error: 'unreachable' } : (r.data || {})); })
      .catch(function () { done({ error: 'unreachable' }); });
  }
  function meetWords(d) {
    var ops = window.ADspaceOps;
    if (ops && ops.meetSaid) return ops.meetSaid(d);
    return 'Google Meet could not be reached. Paste a link instead.';
  }
  function bookMeet(tc, action, btn) {
    var row = btn && btn.closest('.touch');
    var line = row && row.querySelector('.touch-meetmsg');
    if (btn) { btn.disabled = true; btn.textContent = 'Creating…'; }
    meetAsk(tc, action, function (d) {
      if (d.link || d.deleted) {
        log('client.touch_edited', state.client.name, 'Meeting · ' + (d.link ? 'Google Meet created' : 'Google Meet removed'));
        loadTouches();
        return;
      }
      if (btn) { btn.disabled = false; btn.textContent = 'Create Google Meet'; }
      if (line) { line.hidden = false; line.className = 'msg err touch-meetmsg'; line.textContent = meetWords(d); }
      else msg('crmWorkMsg', meetWords(d), 'err');
    });
  }

  function markDone(tc, done) {
    db.from('client_touches').update({ done_at: done ? new Date().toISOString() : null })
      .eq('id', tc.id).select('id').then(function (r) {
        if (r.error) { msg('crmWorkMsg', r.error.message, 'err'); return; }
        if (!(r.data || []).length) { msg('crmWorkMsg', 'Not saved. The database refused the request.', 'err'); return; }
        log(done ? 'client.action_done' : 'client.action_reopened', state.client.name, tc.next_action || '');
        loadTouches();
      });
  }
  function archiveTouch(tc, away) {
    db.from('client_touches').update({ archived_at: away ? new Date().toISOString() : null })
      .eq('id', tc.id).select('id').then(function (r) {
        if (r.error) { msg('crmWorkMsg', r.error.message, 'err'); return; }
        if (!(r.data || []).length) { msg('crmWorkMsg', 'Not saved. The database refused the request.', 'err'); return; }
        log(away ? 'client.touch_removed' : 'client.touch_restored', state.client.name, KIND_WORD[tc.kind] || '');
        if (away) undoBar('Log entry removed.', function () { archiveTouch(tc, false); });
        loadTouches();
      });
  }

  var editingTouch = null;
  function openTouch(tc) {
    editingTouch = tc || null;
    openSheet('crmTouchBox');
    $('crmTouchTitle').textContent = tc ? 'Edit entry' : 'New entry';
    $('tcSave').textContent = 'Save';
    $('tcKind').value = tc ? (tc.kind || 'call') : 'call';
    $('tcDate').value = tc ? (tc.happened_at || today()) : today();
    $('tcWith').value = tc ? (tc.contact_name || '') : '';
    $('tcSummary').value = tc ? (tc.summary || '') : '';
    $('tcNext').value = tc ? (tc.next_action || '') : '';
    $('tcNextAt').value = tc ? (tc.next_at || '') : '';
    var at = tc && tc.meet_at ? new Date(tc.meet_at) : null;
    var hm = at ? myt(at) : null;
    $('tcTime').value = hm ? (hm.h < 10 ? '0' : '') + hm.h + ':' + (hm.m < 10 ? '0' : '') + hm.m : '';
    $('tcMins').value = String(tc && tc.meet_minutes || 30);
    $('tcLink').value = tc ? (tc.meet_link || '') : '';
    meetFields();
    if (!tc) {
      var main = state.contacts.filter(function (c) { return c.is_primary; })[0];
      if (main) $('tcWith').value = main.name;
    }
    msg('tcMsg', '');
    /* Nothing is focused when the sheet opens: on a phone a field taking
       focus raises the keyboard and zooms the page past the rest of the form,
       and the first field is rarely the one somebody came to change. */
  }
  /* Time, length and link belong to a meeting alone. */
  function meetFields() { $('tcMeetRow').hidden = $('tcKind').value !== 'meeting'; }
  $('tcKind').addEventListener('change', meetFields);
  function shutTouch() { shutSheet('crmTouchBox'); editingTouch = null; }
  $('crmAddTouch').addEventListener('click', function () { openTouch(null); });
  /* The head's Log call opens the same sheet, the record staying on its pane. */
  $('crmLogCall').addEventListener('click', function () { openTouch(null); });
  $('tcCancel').addEventListener('click', shutTouch);

  $('tcSave').addEventListener('click', function () {
    var summary = val('tcSummary');
    if (!summary) { msg('tcMsg', 'A summary is required.', 'err'); $('tcSummary').focus(); return; }
    var row = {
      kind: $('tcKind').value,
      happened_at: $('tcDate').value || today(),
      contact_name: val('tcWith') || null,
      summary: summary,
      next_action: val('tcNext') || null,
      next_at: $('tcNextAt').value || null,
      meet_at: null, meet_minutes: null, meet_link: null
    };
    if (row.kind === 'meeting') {
      var link = val('tcLink');
      if (link && !MEET_LINK.test(link)) {
        msg('tcMsg', 'Enter a Google Meet, Zoom or Teams link.', 'err'); $('tcLink').focus(); return;
      }
      var time = $('tcTime').value;
      /* The time is Malaysia's, wherever the colleague is. */
      row.meet_at = time ? new Date(row.happened_at + 'T' + time + ':00+08:00').toISOString() : null;
      row.meet_minutes = Number($('tcMins').value) || 30;
      row.meet_link = link || null;
    }
    var was = editingTouch;
    var after = function (r) {
      if (r.error) { msg('tcMsg', r.error.message, 'err'); return; }
      if (!(r.data || []).length) { msg('tcMsg', 'Not saved. The database refused the request.', 'err'); return; }
      /* A Google Meet already booked follows the entry: moved with its time,
         taken off the calendar when the entry is no longer a meeting at a
         time. */
      if (was && was.meet_event_id) {
        var gone = row.kind !== 'meeting' || !row.meet_at;
        var before = was.meet_at ? new Date(was.meet_at).getTime() : 0;
        var moved = !gone && (new Date(row.meet_at).getTime() !== before || row.meet_minutes !== was.meet_minutes);
        if (gone || moved) meetAsk({ id: was.id }, gone ? 'delete' : 'create', function () { loadTouches(); });
      }
      log(editingTouch ? 'client.touch_edited' : 'client.touch', state.client.name,
          KIND_WORD[row.kind] + (row.next_action ? ' · next: ' + row.next_action : ''));
      shutTouch();
      loadTouches();
      // The first call or visit is what makes a lead contacted.
      if (!editingTouch && (state.client.stage || 'lead') === 'lead') {
        db.from('clients').update({ stage: 'contacted' }).eq('id', state.client.id).select('id').then(function (q) {
          if (q.error || !(q.data || []).length) { msg('crmWorkMsg', 'Logged. The stage was not moved to Contacted: the database refused the request.', 'warn'); return; }
          var spent = daysSince(state.client.stage_since) === 0 ? 'the same day' : 'after ' + (ageWord(state.client) || 'no time');
          state.client.stage = 'contacted';
          var mine = state.clients.filter(function (x) { return x.id === state.client.id; })[0];
          if (mine) mine.stage = 'contacted';
          log('client.stage', state.client.name, 'Contacted ' + spent);
          refreshClient(state.client, function () { openClient(state.client); });
        });
      }
    };
    if (editingTouch) {
      row.updated_at = new Date().toISOString();
      db.from('client_touches').update(row).eq('id', editingTouch.id).select('id').then(after);
    } else {
      row.client_id = state.client.id;
      row.by_whom = (bridge.me && bridge.me() && bridge.me().name) || actor() || null;
      db.from('client_touches').insert(row).select('id').then(after);
    }
  });

  // ---- Engagements --------------------------------------------------------
  /* The record's Engagements pane (2026-10-10): the client's work by content
     month, its reports included, drawn by js/engage.js. This file keeps the
     pane's head (the ways into the work, while the client is Active), the
     tab's place on the strip, and the month line under the name, which is
     read from the same answer. */
  var ENGAGED = ['active', 'paused', 'past'];
  function loadEngage(fresh) {
    var c = state.client, ENG = window.ADspaceEngage;
    if (!c || !ENG) return;
    paintEngage();
    if (!fresh && ENG.loaded(c.id)) return;
    ENG.load(c, function (got) {
      if (!state.client || state.client.id !== got.id) return;
      paintEngage();
      paintMonthLine(state.client);
    });
  }

  function paintEngage() {
    var c = state.client, ENG = window.ADspaceEngage;
    if (!c || !ENG) return;
    /* The tab is drawn for a client engaged now or before, or one holding
       anything there; a lead's waits for the answer. */
    var show = ENGAGED.indexOf(c.stage) > -1 || ENG.holds(c.id);
    if (show !== engShown) {
      engShown = show;
      if (GROUP_OF[pane] === 'engagements' || pane === 'engagements') { showPane(pane); setUrl(); }
    }
    paintEngageActions(c);
    ENG.paint($('crmWorkList'), c, $('crmEngageMsg'));
  }

  function paintEngageActions(c) {
    var act = $('crmEngageActions');
    // Nothing is started for a client who is not Active, so the head waits.
    if (c.stage !== 'active') { act.innerHTML = ''; return; }
    var PLUS = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>';
    /* A way to another console page carries the chevron after its words,
       never the leaving mark: it opens in this tab (2026-10-22, CLI-5). */
    var CHEVR = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>';
    /* Each way into the work is offered where it can be taken: Enable Content
       Review writes the client (Clients at Work, or Content Review settings
       at Work, as `clients_update` asks), New campaign makes one (Campaigns
       at Work). A View group was offered both (audit, 2026-10-03). */
    var canReview = c.review_hidden
      ? (bandMay(c.stage, 'work') || mayPart('review.settings', 'work'))
      : mayPart('review', 'view');
    var canCamp = mayPart('campaigns.campaigns', 'work');
    act.innerHTML =
      (!canReview ? ''
        : c.review_hidden
        ? '<button class="btn btn-icon" id="crmReviewOn" type="button">' + PLUS + '<span>Enable Content Review</span></button>'
        : '<button class="btn btn-icon" id="crmGoReview" type="button"><span>Open Content Review</span>' + CHEVR + '</button>') +
      (canCamp ? '<button class="btn btn-icon" id="crmGoCampaign" type="button">' + PLUS + '<span>New campaign</span></button>' : '');
    var on = $('crmReviewOn');
    /* The way back from Remove from Content Review: never asks, and a
       refused write is named rather than taken for done. */
    if (on) on.addEventListener('click', function () {
      on.disabled = true;
      db.from('clients').update({ review_hidden: false }).eq('id', c.id).select('id').then(function (r) {
        if (r.error || !r.data || !r.data.length) {
          on.disabled = false;
          msg('crmEngageMsg', r.error ? r.error.message : 'Not saved. The database refused the request.', 'err');
          return;
        }
        c.review_hidden = false;
        log('client.review_on', c.name, '');
        goTo('/admin/?s=review&client=' + encodeURIComponent(keyOf(c)), 'review');
      }).catch(function (e) { on.disabled = false; msg('crmEngageMsg', (e && e.message) || String(e), 'err'); });
    });
    var go = $('crmGoReview');
    if (go) go.addEventListener('click', function () {
      goTo('/admin/?s=review&client=' + encodeURIComponent(keyOf(c)), 'review');
    });
    var nc = $('crmGoCampaign');
    if (nc) nc.addEventListener('click', function () {
      goTo('/admin/?s=campaigns&new=' + encodeURIComponent(c.id), 'campaigns');
    });
  }
  /* Into another section as an Engagements row opens one: the address,
     then the section, never a reload of the console (CLI-5). */
  function goTo(url, section) {
    if (!bridge.show) { location.href = url; return; }
    history.replaceState(null, '', url);
    if (section === 'review' && bridge.restore) bridge.restore();
    else bridge.show(section);
  }
  if (window.ADspaceEngage) {
    window.ADspaceEngage.onData(function (c) {
      if (state.client && state.client.id === c.id) { paintEngage(); paintMonthLine(state.client); }
    });
  }

  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>';

  // ---- Services on a client -----------------------------------------------
  /* What the client asked for, was quoted, and confirmed. Each line keeps its
     own label and rate, so a later price change does not rewrite history. The
     confirmed total (else the quoted total) is written back to deal_value, so
     the list and the pipeline carry it without a join. */
  var catalog = null;
  function loadCatalog(then) {
    if (catalog) { then(catalog); return; }
    db.from('services').select('*').order('position').then(function (r) {
      catalog = r.data || [];
      then(catalog);
    }, function () { catalog = []; then(catalog); });
  }
  /* qty × the billed rate × months. A one-off line has one month. The billed
     rate is the catalogue rate carrying its term adjustment, worked out once
     in money.js so this, the letter and the client's page cannot disagree. */
  function rateOf(l) { return MON.rateFor(l.rate, l.tenure, l.term_adjust, l.term_pct); }
  function amountOf(l) { return Number(l.qty || 0) * rateOf(l) * Math.max(1, Number(l.tenure || 1)); }
  /* A start kept as a month (older lines) reads as its first day. */
  function startDay(s) { s = String(s || ''); return s.length === 7 ? s + '-01' : s; }
  function termWord(l) {
    var n = Math.max(1, Number(l.tenure || 1));
    if (n === 1 && !l.start_on) return '';
    return (n > 1 ? n + ' months' : '') + (l.start_on ? (n > 1 ? ' from ' : 'From ') + niceDate(startDay(l.start_on)) : '');
  }
  // Named where the figure changes, so a rate that is not the rate card's is
  // never something the reader has to work out for themselves. It says nothing
  // where the line is billed at the rate that was typed, because then there is
  // nothing to explain.
  function adjWord(l) { return MON.termNote(l.tenure, l.term_adjust, l.term_pct); }

  /* A removed line is kept, never deleted (a letter may have quoted it), so
     its way back outlives the Undo: shown on asking, with Restore, as a
     removed contact or call is (the user's delete audit, 2026-10-07). */
  var showRemovedServices = false;

  /* `failed` hears a read that failed, so a caller waiting on the lines
     (Issue letter read again after `stale`) says so where it is. */
  function loadServices(after, failed) {
    var box = $('crmServices');
    if (!box.querySelector('.crm-table')) skeleton(box, 3);
    var fail = function (m) {
      failLine(box, 'Services', m, loadServices); ovFailed('services', true);
      if (failed) failed(m);
    };
    loadCatalog(function () {
      db.from('client_services').select('*').eq('client_id', state.client.id)
        .order('created_at').then(function (r) {
          if (r.error) { fail(r.error.message); return; }
          ovFailed('services', false);
          var all = r.data || [];
          state.services = all.filter(function (l) { return !l.archived_at; });
          state.servicesGone = all.filter(function (l) { return l.archived_at; });
          state.servicesQuoted = {};
          paintServices();
          paintDeal();
          paintSummary();
          quotedLines();
          loadQuotes();
          if (after) after();
        }).catch(function (e) { fail((e && e.message) || 'The connection was lost.'); });
    });
  }

  /* A client's quotations (js/quotes.js): read after the lines, since a
     quotation knows its lines by them, and painted above them. */
  function liveMap() {
    var live = {};
    (state.documents || []).forEach(function (d) {
      if (!DOCS || !DOCS.liveDoc(d)) return;
      ((state.docMap || {})[d.id] || []).forEach(function (id) { live[id] = d.number; });
    });
    return live;
  }
  /* The Services pane's one blue follows the deal (2026-10-22, SL-M2):
     nothing quoted and no To quote line, Build quote; a quotation that can
     be offered, its row's Issue Letter of Offer (tonal where two could be);
     To quote lines no live letter holds, Issue letter; else none. Issue
     letter is drawn once a To quote or Confirmed line exists. */
  function paintDeal() {
    var cover = $('crmCover');
    if (!cover || !state.client) return;
    var lines = state.services || [], live = liveMap();
    var letterable = lines.some(function (l) { return l.state === 'quoted' || l.state === 'confirmed'; });
    var toQuote = lines.filter(function (l) { return l.state === 'quoted'; });
    var quotes = (state.quotes || []).filter(function (q) { return !q.removed_at; });
    cover.hidden = !letterable;
    var build = $('qtBuild');
    var offers = Array.prototype.slice.call(document.querySelectorAll('#crmQuotes .qt-dl [data-a="offer"]'));
    var blue = null;
    if (state.services && state.quotes && !quotes.length && !toQuote.length) blue = build;
    else if (offers.length === 1) blue = offers[0];
    else if (toQuote.some(function (l) { return !live[l.id]; })) blue = cover;
    [build, cover].concat(offers).forEach(function (b) { if (b) b.classList.toggle('btn-primary', b === blue); });
  }
  function quoteCtx() {
    return { client: state.client, db: db, may: mayPart, msg: msg, services: state.services || [], live: liveMap(),
      undo: undoBar,
      attention: (function () {
        var m = (state.contacts || []).filter(function (x) { return x.is_primary && !x.archived_at; })[0] ||
                (state.contacts || []).filter(function (x) { return !x.archived_at; })[0];
        return m ? ((m.salutation ? m.salutation + ' ' : '') + (m.name || '')).trim() : '';
      })(),
      reload: function (done) { loadQuotes(done); },
      painted: paintDeal,
      offer: function (ids, then) { loadServices(function () { openPick(ids); if (then) then(); }, then); } };
  }
  /* `always`: done is called on a refused read too (the letter sheet reads
     again either way). */
  function loadQuotes(done, always) {
    var Q = window.ADspaceQuotes, host = $('crmQuotes');
    if (!Q || !host || !state.client || !mayPart('clients.quotes', 'view')) { if (host) host.hidden = true; return; }
    var id = state.client.id;
    Q.load(quoteCtx(), function (rows, err) {
      if (!state.client || state.client.id !== id) return;
      if (err) { state.quotes = null; failLine(host, 'Quotations', err.message || String(err), function () { loadQuotes(); }); host.hidden = false; if (always && done) done(); return; }
      state.quotes = rows;
      Q.paint(host, quoteCtx(), rows);
      paintSummary();
      if (done) done(rows);
    });
  }
  function repaintQuotes() {
    if (window.ADspaceQuotes && state.quotes && $('crmQuotes')) window.ADspaceQuotes.paint($('crmQuotes'), quoteCtx(), state.quotes);
  }

  /* A removed line a Letter of Offer quoted stays for the record (the
     letter's foreign key restricts it), so Delete is drawn only on the
     others; read once, for the removed lines alone, where Documents can be
     read; elsewhere the database names the refusal at the press. */
  function quotedLines() {
    var gone = (state.servicesGone || []).map(function (l) { return l.id; });
    if (!gone.length || !(bridge.may && bridge.may('clients.documents', 'view'))) return;
    db.from('client_document_services').select('service_id').in('service_id', gone).then(function (r) {
      if (r.error) return;
      (r.data || []).forEach(function (x) { state.servicesQuoted[x.service_id] = true; });
      if (showRemovedServices) paintServices();
    }).catch(function () {});
  }

  function deleteService(l) {
    window.ADspaceConfirm.ask({
      title: 'Delete',
      body: l.label + ' goes from this client for good. There is no restore.',
      go: 'Delete',
      tone: 'danger'
    }, function () {
      db.from('client_services').delete().eq('id', l.id).select('id').then(function (r) {
        if (r.error) {
          msg('crmServiceMsg', r.error.code === '23503'
            ? 'A Letter of Offer quotes this service, so it stays for the record.' : svSaid(r.error), 'err');
          return;
        }
        if (!(r.data || []).length) { msg('crmServiceMsg', 'Not deleted. The database refused the request.', 'err'); return; }
        log('client.service_deleted', state.client.name, l.label);
        msg('crmServiceMsg', 'Deleted.', 'ok');
        loadServices();
      }).catch(function (e) { msg('crmServiceMsg', (e && e.message) || 'Not deleted.', 'err'); });
    });
  }

  function paintServices() {
    var box = $('crmServices');
    var rows = state.services;
    var gone = state.servicesGone || [];
    var c = state.client;
    box.innerHTML = '';
    if (!rows.length && !(showRemovedServices && gone.length)) {
      // The enquiry as typed at intake stands in until a line is added.
      /* Named as the list is (2026-10-22, SL-10); its way out is the head's
         Add service, offered once on the screen. */
      box.innerHTML = '<div class="empty has-go"><span>' + (c.deal_note ? esc(c.deal_note) : 'No service lines.') + '</span>' +
        (mayPart('clients.services', 'work') ? '<button class="btn btn-sm" data-a="add" type="button">' + PLUS_ICON + 'Add service</button>' : '') + '</div>';
      var ae = box.querySelector('[data-a="add"]');
      if (ae) ae.addEventListener('click', function () { openService(null); });
    } else {
      var table = document.createElement('div');
      table.className = 'crm-table';
      table.innerHTML = '<div class="crm-head svc-row csv-row"><span>Service</span><span class="svc-rate">Qty × rate</span>' +
        '<span class="svc-rate">Amount</span><span>State</span><span></span></div>';
      rows.forEach(function (l) { table.appendChild(serviceRow(l)); });
      if (showRemovedServices) gone.forEach(function (l) { table.appendChild(serviceRow(l, true)); });
      var sum = function (st) {
        return rows.filter(function (l) { return l.state === st; }).reduce(function (s, l) { return s + amountOf(l); }, 0);
      };
      var quoted = sum('quoted'), confirmed = sum('confirmed');
      var tot = document.createElement('div');
      tot.className = 'csv-total';
      tot.innerHTML =
        (quoted ? '<span>To quote<b>' + esc(MON.money2(quoted, MON.curOf(c))) + '</b></span>' : '') +
        '<span class="is-total">Confirmed<b>' + esc(MON.money2(confirmed, MON.curOf(c))) + '</b>' +
        (MON.approx(confirmed, c) ? '<small class="muted">' + esc(MON.approx(confirmed, c).trim().replace(/^\(|\)$/g, '')) + '</small>' : '') + '</span>';
      table.appendChild(tot);
      box.appendChild(table);
    }
    if (gone.length) {
      var t = document.createElement('button');
      t.type = 'button'; t.className = 'linkish crm-removed-toggle';
      t.textContent = (showRemovedServices ? 'Hide ' : 'Show ') + gone.length +
        ' removed service' + (gone.length === 1 ? '' : 's');
      t.addEventListener('click', function () { showRemovedServices = !showRemovedServices; paintServices(); });
      box.appendChild(t);
    }
  }

  function serviceRow(l, removed) {
    var c = state.client;
    var w = SV_STATE[l.state] || SV_STATE.enquired;
    var row = document.createElement('div');
    row.className = 'svc-row csv-row' + (removed ? ' is-off' : '');
    if (removed) {
      row.innerHTML =
        '<span class="svc-name"><b>' + esc(l.label) + '</b>' +
          (l.note || l.unit ? '<small>' + esc([l.unit, l.note].filter(Boolean).join(' · ')) + '</small>' : '') + '</span>' +
        '<span class="svc-rate svc-calc">' + esc(Number(l.qty) + ' × ' + MON.money2(rateOf(l), MON.curOf(c)) +
          (Number(l.tenure || 1) > 1 ? ' × ' + Number(l.tenure) + ' mo' : '')) + '</span>' +
        '<span class="svc-rate svc-amt"><b>' + esc(MON.money2(amountOf(l), MON.curOf(c))) + '</b></span>' +
        '<span class="svc-state"><span class="tone is-off">Removed</span></span>' +
        '<span class="team-act">' +
          '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
          '<div class="kmenu" data-menu hidden>' +
            ADspaceMenu.items([[], [], [], [], [{ a: 'restore', label: 'Restore', need: 'clients.services:work' }],
              [!(state.servicesQuoted && state.servicesQuoted[l.id]) && { a: 'purge', label: 'Delete', need: 'clients.services:manage' }]]) +
          '</div>' +
        '</span>';
      wireMenu(row);
      var back = row.querySelector('[data-a="restore"]');
      if (back) back.addEventListener('click', function () { saveService(l, { archived_at: null }, 'restored'); });
      var purge = row.querySelector('[data-a="purge"]');
      if (purge) purge.addEventListener('click', function () { deleteService(l); });
      return row;
    }
    row.innerHTML =
      '<span class="svc-name"><b>' + esc(l.label) + '</b>' +
        (l.note || l.unit || termWord(l) || adjWord(l) || l.tax_code
          ? '<small>' + esc([l.unit, adjWord(l), termWord(l), l.tax_code ? 'Tax ' + l.tax_code : '', l.note].filter(Boolean).join(' · ')) + '</small>' : '') + '</span>' +
      '<span class="svc-rate svc-calc">' + esc(Number(l.qty) + ' × ' + MON.money2(rateOf(l), MON.curOf(c)) +
        (Number(l.tenure || 1) > 1 ? ' × ' + Number(l.tenure) + ' mo' : '')) + '</span>' +
      '<span class="svc-rate svc-amt"><b>' + esc(MON.money2(amountOf(l), MON.curOf(c))) + '</b></span>' +
      /* Confirmed is not in this list. A service becomes Confirmed when a
         signed letter is verified and at no other moment: a select on the row
         let anybody confirm a line nobody had signed for, and it was the only
         way it ever happened. A confirmed line still reads as a chip here,
         because it is a state, just not one this control may set. */
      '<span class="svc-state">' + (l.state === 'confirmed'
        ? '<span class="tone ' + w[1] + '">' + esc(w[0]) + '</span>'
        : '<select class="select select-sm state-select ' + w[1] + '" data-f="state" aria-label="State">' +
          Object.keys(SV_STATE).filter(function (k) { return k !== 'confirmed'; }).map(function (k) {
            return '<option value="' + k + '"' + (k === l.state ? ' selected' : '') + '>' + esc(SV_STATE[k][0]) + '</option>';
          }).join('') + '</select>') + '</span>' +
      '<span class="team-act">' +
        '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
        '<div class="kmenu" data-menu hidden>' +
          /* Confirm without letter overrides a client's service line, not the
             rate card, so it is Clients at manage and not Services; it is
             offered only while the line is not yet confirmed (MENU-14). */
          ADspaceMenu.items([[], [{ a: 'edit', label: 'Edit', need: 'clients.services:work' },
            bridge.may && bridge.may('clients', 'manage') && l.state !== 'confirmed' && { a: 'force', label: 'Confirm without letter' }],
            [], [], [], [{ a: 'del', label: 'Remove', need: 'clients.services:work', attrs: 'data-soft' }]]) +
        '</div>' +
      '</span>';
    wireMenu(row);
    var on = function (a, fn) { var el = row.querySelector('[data-a="' + a + '"]'); if (el) el.addEventListener('click', fn); };
    on('edit', function () { openService(l); });
    var sel = row.querySelector('[data-f="state"]');
    if (sel) sel.addEventListener('change', function () { saveService(l, { state: this.value }); });
    /* The way back for a legacy line or an exception. An admin only, a reason
       required, and it is written to the activity record with that reason, so
       it is never a silent edit. */
    on('force', function () {
      Array.prototype.forEach.call(row.querySelectorAll('.kmenu'), function (m) { m.hidden = true; });
      /* Two browser prompts: the first asked for the state as free text, so
         "Confirmed" with a capital or a trailing space was a refusal from the
         database rather than a choice from the three that exist, and the
         second arrived after the state had already been typed. One sheet, the
         state as a select over the states a line can hold, and the reason
         beside it, because the reason is what the activity record keeps. */
      window.ADspaceConfirm.ask({
        title: 'Confirm without letter',
        body: 'The state of ' + l.label + ' is set by hand, past the checks the '
            + 'letter normally makes. The reason goes on the activity record.',
        go: 'Set state',
        tone: 'warn',
        fields: [
          { name: 'state', label: 'State', value: 'confirmed',
            choices: Object.keys(SV_STATE).map(function (k) { return [k, SV_STATE[k][0]]; }) },
          { name: 'why', label: 'Why it is being set by hand', rows: 3,
            placeholder: 'What the checks cannot see.',
            need: 'A reason is required.' }
        ]
      }, function (a) {
        db.rpc('override_service_state', { p_service: l.id, p_state: a.state, p_reason: a.why })
          .then(function (r) {
            var out = (r && r.data) || {};
            if (r && r.error) { msg('crmServiceMsg', r.error.message, 'err'); return; }
            if (out.error) { msg('crmServiceMsg', OVERRIDE_WORD[out.error] || out.error, 'err'); return; }
            msg('crmServiceMsg', 'Set by hand.', 'ok');
            loadServices();
            /* The client's value is the confirmed total, so a state set by hand
               moves it. saveService has always called this; the override was
               added without it and left the record showing the old figure. */
            syncValue();
          }).catch(function (e) { msg('crmServiceMsg', (e && e.message) || 'Could not set it.', 'err'); });
      });
    });
    on('del', function () { saveService(l, { archived_at: new Date().toISOString() }, 'removed'); });
    return row;
  }

  var OVERRIDE_WORD = {
    'not-allowed': 'Only an admin can set a service state by hand.',
    'bad-state': 'A service is enquired, to quote or confirmed.',
    'reason-required': 'A reason is required.',
    'not-found': 'That line could not be found.'
  };

  var editingService = null;
  /* What a client's line is priced from: the live version of the rate card
     (2026-10-13), never the draft somebody is still editing. A line the
     draft no longer holds is not offered (a client's line names it). With
     no version published, the card as it stands. */
  function pickList() {
    if (!live) return catalog || [];
    var have = {};
    (catalog || []).forEach(function (s) { have[s.slug] = true; });
    return (live.snapshot.services || []).filter(function (s) { return have[s.slug]; });
  }
  function pickById(slug) { return pickList().filter(function (s) { return s.slug === slug; })[0]; }
  /* A client billed in S$ is priced in S$ from the card's RM at the rate set
     in Tax and terms, to the cent; with no rate set the rate is left for the
     team to type (2026-10-22, SL-1). Null where the client is billed in RM;
     0 where it is billed in S$ and no rate is set. */
  function svFx() {
    if (MON.curOf(state.client) !== 'SG') return null;
    return Number(MON.setting('fx_sgd')) || 0;
  }
  function svRateOf(rate) {
    var fx = svFx();
    if (rate == null) return null;
    if (fx === null) return Number(rate);
    return fx ? Math.round(Number(rate) / fx * 100) / 100 : null;
  }
  function fillServicePick() {
    var groups = {};
    pickList().filter(function (s) { return s.active !== false; }).forEach(function (s) {
      (groups[s.category] = groups[s.category] || []).push(s);
    });
    var cats = CATS.concat(Object.keys(groups).filter(function (k) { return CATS.indexOf(k) < 0; }));
    $('svPick').innerHTML = cats.filter(function (k) { return groups[k]; }).map(function (k) {
      return '<optgroup label="' + esc(k) + '">' + groups[k].map(function (s) {
        var r = svRateOf(s.rate);
        return '<option value="' + esc(s.slug) + '">' + esc(s.name) +
          (r != null ? ' · ' + MON.money(r, svFx() === null ? 'MY' : 'SG') : '') + '</option>';
      }).join('') + '</optgroup>';
    }).join('') + '<option value="custom">Custom</option>';
    /* A service is chosen, never preselected (2026-10-22, SL-5). */
    $('svPick').insertAdjacentHTML('afterbegin', '<option value="">Choose a service</option>');
  }
  function syncPick(fill) {
    var slug = $('svPick').value;
    var s = pickById(slug);
    $('svLabelRow').hidden = slug !== 'custom';
    /* Prefilled, not fixed: the catalogue seeds the price, the term and what
       the package includes, and the line keeps its own copy from there. */
    if (fill && s) {
      var r = svRateOf(s.rate);
      $('svRate').value = r != null ? r : '';
      if (s.rate != null && svFx() === 0) msg('svMsg', 'Set the Singapore dollar rate in Tax and terms.', 'warn');
      $('svTenure').value = Math.max(1, Number(s.min_months || 1));
      $('svDetail').value = s.detail || '';
    }
    syncAdjust();
  }
  /* The tick is offered only where the term has a factor, and it says what
     pressing it will do at the term that is typed: an unlabelled "apply the
     adjustment" leaves the reader to remember which way three months goes. */
  /* The percentage is the rate card's for the term typed until the person
     types one of their own, and from then on it is theirs: a negotiated 20%
     must not snap back to 25 because the term was corrected. Cleared, the
     line falls back to the older factor table, which is what a line from
     before the percentage existed carries. */
  var svPctCard = null;
  function svPctValue() {
    var v = String($('svPct').value || '').trim();
    return v === '' ? null : Number(v);
  }
  /* `typing` is the person editing the field itself: the word follows and
     the figure is left alone, or clearing it to type a new one would refill
     it under their cursor. */
  /* The term's percentage as the live rate card version holds it, as a
     quotation reads it (2026-10-22, SL-3): 18 months takes 12's on a version
     published before it had its own; with no version, today's setting. */
  function cardPct(months) {
    var set = live && live.snapshot && live.snapshot.settings;
    var key = MON.termKey(months);
    if (!set || !key) return MON.termPct(months);
    var v = set[key] != null ? set[key] : key === 'term_18_23' ? set.term_12_23 : null;
    return v == null ? MON.termPct(months) : Number(v);
  }
  function syncAdjust(typing) {
    var months = Number(val('svTenure') || 1);
    var card = cardPct(months);
    var cur = svPctValue();
    /* The field follows the card while it still holds the card's own figure
       for the term it was filled for; a figure of the person's own stays. */
    if (typing !== true && (cur === null || cur === svPctCard)) {
      $('svPct').value = card ? String(card) : '';
      svPctCard = card;
    }
    var adj = MON.termAdj(months, svPctValue());
    /* A term adjusts a monthly line alone: a line whose unit is not by the
       month (One-off) takes none, as a quotation keeps it at 0% (2026-10-22,
       SL-7). A custom line with no unit keeps the choice. */
    var pk = pickById($('svPick').value);
    var unit = pk ? pk.unit : ($('svPick').value === 'custom' && editingService ? editingService.unit : '');
    var monthly = !unit || /month/i.test(unit);
    $('svAdjRow').hidden = !monthly || (!adj && !card);
    /* The words name the kind alone; the figure is the field's (the user,
       2026-10-15: "just show the numbers changed"). */
    if (adj) $('svAdjustWord').textContent = 'Apply ' + adj.replace(/^[^A-Za-z]*%\s*/, '');
    else if (card) $('svAdjustWord').textContent = 'Apply term adjustment';
    else $('svAdjust').checked = false;
  }
  $('svTenure').addEventListener('input', function () { syncAdjust(false); });
  $('svPct').addEventListener('input', function () { syncAdjust(true); });
  function openService(l) {
    editingService = l || null;
    liveRead = false;
    loadCatalog(function () { loadLive(function () {
      fillServicePick();
      $('crmServiceTitle').textContent = l ? 'Edit service line' : 'New service line';
      $('svPick').value = l ? (l.service_slug && pickById(l.service_slug) ? l.service_slug : 'custom') : '';
      /* The rate in the currency the client is billed in (SL-1). */
      document.querySelector('label[for="svRate"]').textContent = 'Rate (' + (svFx() === null ? 'RM' : 'S$') + ')';
      $('svLabel').value = l ? (l.label || '') : '';
      $('svQty').value = l ? Number(l.qty || 1) : 1;
      $('svRate').value = l ? Number(l.rate || 0) : '';
      /* Confirmed comes from a verified signed letter alone (audit S1):
         the sheet offers Enquired and To quote, and a confirmed line reads
         its state and keeps it. */
      var fixed = Boolean(l && l.state === 'confirmed');
      $('svStateRow').hidden = fixed;
      $('svStateFixed').hidden = !fixed;
      /* A new line opens on To quote once the client is past enquiring
         (Proposal sent, Active; 2026-10-22, SL-6). */
      var c0 = state.client || {};
      $('svState').value = l && !fixed ? (l.state || 'enquired') : (c0.stage === 'proposal' || c0.stage === 'active' ? 'quoted' : 'enquired');
      $('svTenure').value = l ? Math.max(1, Number(l.tenure || 1)) : 1;
      $('svStart').value = l ? (l.start_on || '') : '';
      $('svDetail').value = l ? (l.detail || '') : '';
      $('svNote').value = l ? (l.note || '') : '';
      /* A new line is billed at the rate that was typed. An existing one is
         read as it was stored, and a line quoted before the tick existed was
         backfilled to carry it, so nobody's figure moves. */
      $('svAdjust').checked = l ? l.term_adjust !== false : false;
      /* A line already holding a percentage shows it; one from before the
         percentage existed shows the factor it was quoted at as a
         percentage, so the figure it prints is the figure on its letter. */
      svPctCard = l ? cardPct(l.tenure) : null;
      if (l && l.term_pct !== null && l.term_pct !== undefined) {
        $('svPct').value = String(l.term_pct);
      } else if (l && l.term_adjust !== false && MON.termFactor(l.tenure) !== 1) {
        $('svPct').value = String(Math.round((MON.termFactor(l.tenure) - 1) * 10000) / 100);
      } else {
        $('svPct').value = '';
      }
      syncPick(!l);
      fillTax(l);
      msg('svMsg', '');
      openSheet('crmServiceBox');
    }); });
  }
  function shutService() { shutSheet('crmServiceBox'); editingService = null; }
  /* The line's tax (2026-10-22): the client's SST, or one of the codes the
     team bills with (Settings, Money: Tax codes). A code no longer offered
     stays shown on the line that holds it. */
  function fillTax(l) {
    var sel = $('svTax'), c = state.client || {};
    var mine = l && l.tax_code ? l.tax_code : '';
    var paint = function (list) {
      var shown = list.filter(function (t) { return t.active || t.code === mine; });
      if (mine && !shown.some(function (t) { return t.code === mine; })) shown.push({ code: mine, rate: '', name: '' });
      sel.innerHTML = '<option value="">' + esc(c.sst_applies === false ? 'Client default · No SST' : 'Client default · ' + MON.taxLabel()) + '</option>' +
        shown.map(function (t) {
          return '<option value="' + esc(t.code) + '">' + esc(t.rate === '' ? t.code : MON.taxCodeWord(t)) + (t.active === false ? ' (no longer offered)' : '') + '</option>';
        }).join('');
      sel.value = mine;
    };
    paint([]);
    MON.taxCodes().then(function (list) { if (editingService === (l || null)) paint(list); });
  }
  $('svPick').addEventListener('change', function () {
    syncPick(true);
    if ($('svPick').value === 'custom') $('svLabel').focus();
  });
  $('crmAddService').addEventListener('click', function () { openService(null); });
  $('svCancel').addEventListener('click', shutService);
  $('svSave').addEventListener('click', function () {
    var slug = $('svPick').value;
    if (!slug) { msg('svMsg', 'Choose a service.', 'err'); $('svPick').focus(); return; }
    var s = pickById(slug);
    var label = slug === 'custom' ? val('svLabel') : (s ? s.name : '');
    if (!label) { msg('svMsg', 'A name is required.', 'err'); $('svLabel').focus(); return; }
    /* Never below zero (client_services_rate_check, _qty_check): a negative
       line made every Letter of Offer holding it refused as changed. */
    var svQ = Number(val('svQty') || 1), svR = Number(val('svRate') || 0);
    var svBelow = function (id, text) {
      msg('svMsg', text, 'err');
      $(id).focus({ preventScroll: true });
      $('svMsg').scrollIntoView({ block: 'nearest' });
    };
    if (!isFinite(svQ) || svQ < 0) { svBelow('svQty', 'The quantity cannot be below zero.'); return; }
    if (!isFinite(svR) || svR < 0) { svBelow('svRate', 'The rate cannot be below zero.'); return; }
    var row = {
      service_slug: s ? s.slug : null, label: label, unit: s ? (s.unit || null) : null,
      qty: svQ, rate: svR,
      tenure: Math.max(1, Number(val('svTenure') || 1)), start_on: val('svStart') || null,
      note: val('svNote') || null,
      detail: val('svDetail') || null,
      // Stored on every save, never left to the column's default, because the
      // rule that reads it treats a missing value as "on".
      term_adjust: !$('svAdjRow').hidden && $('svAdjust').checked,
      /* The percentage the tick applies, stored with the line whether or not
         the tick is on, so the figure the letter and the client's page work
         out is the one the person saw. */
      term_pct: !$('svAdjRow').hidden ? svPctValue() : null,
      /* The line's tax code, none for the client's SST (2026-10-22). */
      tax_code: $('svTax').value || null
    };
    if (!(editingService && editingService.state === 'confirmed')) row.state = $('svState').value;
    if (editingService) { saveService(editingService, row); return; }
    row.client_id = state.client.id;
    /* One press, one line: Save rests while the insert is out, and an
       answer with no row is named (2026-10-22, SL-2). */
    var go = $('svSave');
    go.disabled = true;
    db.from('client_services').insert(row).select('id').then(function (r) {
      go.disabled = false;
      if (r.error) { msg('svMsg', svSaid(r.error), 'err'); return; }
      if (!(r.data || []).length) { msg('svMsg', 'Not saved. The database refused the request.', 'err'); return; }
      log('client.service', state.client.name, label + ' · ' + SV_STATE[row.state][0]);
      shutService();
      syncValue();
    }).catch(function () { go.disabled = false; msg('svMsg', 'Not saved. Please try again.', 'err'); });
  });
  /* A line moved into Confirmed by hand is refused by the database
     (client_services_confirm_guard): said in the team's words. */
  function svSaid(e) {
    var m = (e && e.message) || '';
    if (/client_services_rate_check/.test(m)) return 'The rate cannot be below zero.';
    if (/client_services_qty_check/.test(m)) return 'The quantity cannot be below zero.';
    return /confirm-needs-letter/.test(m) ? 'A service is confirmed when its signed letter is verified.' : (m || 'Not saved.');
  }
  /* `act` names a removal or a restore, so each is filed as itself (a
     restore had read Service changed). */
  function saveService(l, patch, act) {
    db.from('client_services').update(patch).eq('id', l.id).select('id').then(function (r) {
      if (r.error) { msg('crmServiceMsg', svSaid(r.error), 'err'); return; }
      if (!(r.data || []).length) { msg('crmServiceMsg', 'Not saved. The database refused the request.', 'err'); return; }
      log(act === 'removed' ? 'client.service_removed' : act === 'restored' ? 'client.service_restored' : 'client.service_changed',
          state.client.name, l.label + (patch.state ? ' · ' + SV_STATE[patch.state][0] : ''));
      if (act === 'removed') undoBar(l.label + ' removed.', function () { saveService(l, { archived_at: null }, 'restored'); });
      shutService();
      syncValue();
    }).catch(function (e) { msg('crmServiceMsg', (e && e.message) || 'Not saved.', 'err'); });
  }
  /* The confirmed total, else the quoted total, is the client's value. */
  function syncValue() {
    var cl = state.client;
    db.from('client_services').select('*').eq('client_id', cl.id).is('archived_at', null)
      .then(function (r) {
        if (r.error) throw r.error;
        var rows = r.data || [];
        var sum = function (st) {
          return rows.filter(function (l) { return l.state === st; }).reduce(function (s, l) { return s + amountOf(l); }, 0);
        };
        var v = sum('confirmed') || sum('quoted') || null;
        var was = state.client.deal_value == null ? null : Number(state.client.deal_value);
        /* The lines and the record's figures are read again in place, never
           the whole record (2026-10-22, SL-4). */
        var done = function () {
          if (state.client !== cl) return;
          cl.deal_value = v;
          var mine = state.clients.filter(function (x) { return x.id === cl.id; })[0];
          if (mine) mine.deal_value = v;
          paintFacts(cl);
          loadServices();
        };
        if (v === was) { done(); return; }
        return db.from('clients').update({ deal_value: v }).eq('id', cl.id).then(done);
      }).catch(function () { if (state.client === cl) loadServices(); });
  }

  // ---- Requests from the portal ---------------------------------------------
  /* The client asks; the team answers. A request moves Requested → Reviewing
     → Approved or Declined → Applied, and the person may set a fee and a
     reply the client reads. Approval changes nothing by itself: a person
     applies it to the service line. The section shows once the client has
     portal access or a request exists. */
  var RQ_STATE = ['requested', 'reviewing', 'approved', 'declined', 'applied'].reduce(function (m, k) {
    m[k] = [W.en.rqState[k], W.tone(k)]; return m;
  }, {});
  var RQ_KIND = W.en.rqKind;

  function loadRequests() {
    var box = $('crmRequestList');
    var wrap = $('crmRequests');
    var id = state.client.id;
    if (!mayPart('clients.requests', 'view')) { wrap.hidden = true; return; }
    db.from('client_contacts').select('id').eq('client_id', id).eq('portal_access', true).is('archived_at', null).then(function (pr) {
      var anyPortal = Boolean((pr.data || []).length);
      return db.from('client_requests').select('*').eq('client_id', id).order('created_at', { ascending: false }).then(function (r) {
        if (r.error || state.client.id !== id) { wrap.hidden = true; return; }
        state.requests = r.data || [];
        wrap.hidden = !state.requests.length && !anyPortal;
        if (wrap.hidden) return;
        box.innerHTML = '';
        if (!state.requests.length) { box.innerHTML = '<div class="empty">No requests.</div>'; return; }
        var table = document.createElement('div');
        table.className = 'crm-table';
        table.innerHTML = '<div class="crm-head svc-row doc-row rq-row"><span>Request</span><span class="svc-rate">Fee</span><span>State</span><span></span></div>';
        state.requests.forEach(function (q) { table.appendChild(requestRow(q)); });
        box.appendChild(table);
      });
    }).then(null, function () { wrap.hidden = true; });
  }

  function requestRow(q) {
    var c = state.client;
    var gone = Boolean(q.withdrawn_at);
    var w = RQ_STATE[q.state] || RQ_STATE.requested;
    var row = document.createElement('div');
    row.className = 'svc-row doc-row rq-row' + (gone ? ' is-off' : '');
    var sub = [q.contact_name, niceDate(q.created_at), q.note].filter(Boolean).join(' · ');
    row.innerHTML =
      '<span class="svc-name"><b>' + esc((RQ_KIND[q.kind] || q.kind) + (q.service_label ? ' · ' + q.service_label : '')) + '</b>' +
        (sub ? '<small>' + esc(sub) + '</small>' : '') +
        (q.reply ? '<small>' + esc('Reply: ' + q.reply) + '</small>' : '') + '</span>' +
      '<span class="svc-rate svc-amt">' + (q.fee != null && q.fee !== '' ? '<b>' + esc(MON.money2(q.fee, MON.curOf(c))) + '</b>'
        : '<span class="muted">' + esc(MON.sign(MON.curOf(c))) + '</span>') + '</span>' +
      '<span class="svc-state">' + (gone ? '<span class="chip-state">Withdrawn</span>'
        : '<select class="select select-sm state-select ' + w[1] + '" data-f="state" aria-label="State">' +
          Object.keys(RQ_STATE).map(function (k) {
            return '<option value="' + k + '"' + (k === q.state ? ' selected' : '') + '>' + esc(RQ_STATE[k][0]) + '</option>';
          }).join('') + '</select>') + '</span>' +
      /* The row's one act is on the row (MENU-6, 2026-10-22). */
      '<span class="team-act">' +
        (gone ? '' : '<button class="btn btn-sm" data-a="reply" type="button">Reply</button>') +
      '</span>';
    if (!gone) {
      row.querySelector('[data-a="reply"]').addEventListener('click', function () { openReply(q); });
      row.querySelector('[data-f="state"]').addEventListener('change', function () { saveRequest(q, { state: this.value }, 'request.changed'); });
    }
    return row;
  }

  var replying = null;
  function openReply(q) {
    replying = q;
    $('crmReplyTitle').textContent = (RQ_KIND[q.kind] || q.kind) + (q.service_label ? ' · ' + q.service_label : '');
    $('rqFee').value = q.fee != null && q.fee !== '' ? Number(q.fee) : '';
    $('rqReply').value = q.reply || '';
    msg('rqMsg', '');
    openSheet('crmReplyBox');
    /* Nothing is focused when the sheet opens: on a phone a field taking
       focus raises the keyboard and zooms the page past the rest of the form,
       and the first field is rarely the one somebody came to change. */
  }
  function shutReply() { shutSheet('crmReplyBox'); replying = null; }
  $('rqCancel').addEventListener('click', shutReply);
  $('rqSave').addEventListener('click', function () {
    if (!replying) return;
    var fee = val('rqFee');
    saveRequest(replying, { fee: fee === '' ? null : Number(fee), reply: val('rqReply') || null }, 'request.replied');
  });
  function saveRequest(q, patch, action) {
    patch.decided_by = actorName();
    /* Written only over the request as it was read (audit C2, 2026-10-10):
       a client who withdrew it, or a colleague who answered it meanwhile,
       is not overwritten; the request is read again and that is said. */
    var w = db.from('client_requests').update(patch).eq('id', q.id);
    if (q.updated_at) w = w.eq('updated_at', q.updated_at);
    w.select('id').then(function (r) {
      var box = replying ? 'rqMsg' : 'crmReqMsg';
      if (r.error) { msg(box, r.error.message, 'err'); return; }
      if (!(r.data || []).length) {
        db.from('client_requests').select('id, updated_at').eq('id', q.id).maybeSingle().then(function (n) {
          var moved = n.data && q.updated_at && n.data.updated_at !== q.updated_at;
          msg(box, moved ? 'Not saved. This request changed since it was opened, and has been read again.'
            : 'Not saved. The database refused the request.', 'err');
          if (moved) loadRequests();
        });
        return;
      }
      log(action, state.client.name, (RQ_KIND[q.kind] || q.kind) + (q.service_label ? ' · ' + q.service_label : '') +
        (patch.state ? ' · ' + RQ_STATE[patch.state][0] : '') + (patch.fee != null ? ' · ' + MON.money2(patch.fee, MON.curOf(state.client)) : ''));
      shutReply();
      loadRequests();
    });
  }

  // ---- Documents ------------------------------------------------------------
  /* The Letter of Offer: the quoted lines and fees, for the client to sign.
     Each is kept as issued. */
  var DOCS = window.ADspaceDocs;
  var DOC_WORD = { offer: 'Letter of Offer', intent: 'Letter of Offer', cover: 'Letter of Offer', quotation: 'Quotation', invoice: 'Invoice' };

  /* A letter's own lifecycle, drawn from its timestamps: Issued, Signed
     awaiting verification, Verified, Void, Replaced. Never stored as a word,
     so the record and the row cannot disagree about where one stands. */
  var LETTER_WORD = {
    issued:     ['Issued', 'is-ok'],
    signed:     ['Signed', 'is-warn'],
    verified:   ['Verified', 'is-ok'],
    void:       ['Void', 'is-off'],
    superseded: ['Replaced', 'is-off']
  };

  function loadDocuments() {
    var box = $('crmDocuments');
    var c = state.client;
    if (!DOCS) { box.innerHTML = ''; return; }
    if (!box.querySelector('.crm-table')) skeleton(box, 2);
    DOCS.list(c.id, function (rows, err) {
      if (err) { failLine(box, 'Documents', err.message || String(err), loadDocuments); ovFailed('documents', true); return; }
      ovFailed('documents', false);
      if (!state.client || state.client.id !== c.id) return;
      /* Kept so the Summary can read them without a second call: the record
         has already paid for this. */
      state.documents = rows || [];
      paintSummary();
      /* Which service lines each letter captured. A letter issued before this
         change has none, which is what keeps it out of verification. */
      DOCS.mapOf(rows.map(function (d) { return d.id; }), function (by) {
        state.docMap = by || {};
        repaintQuotes();
        paintDeal();
        box.innerHTML = '';
        var empty = document.createElement('div');
        empty.className = 'empty';
        empty.textContent = 'No documents.';
        if (!rows.length) box.appendChild(empty);
        else {
          var table = document.createElement('div');
          table.className = 'crm-table';
          table.innerHTML = '<div class="crm-head svc-row doc-row ltr-row"><span>Document</span><span class="svc-rate">Total</span><span>State</span><span></span></div>';
          rows.forEach(function (d) { table.appendChild(documentRow(d)); });
          box.appendChild(table);
        }
        /* The client's other documents (the quotation cover, a thank-you
           letter) come from the Register and take their own row shape under
           the letters; the empty line leaves when either list has rows. */
        if (window.ADspaceRegister) {
          window.ADspaceRegister.paintFor(c.id, box, function (regRows) {
            if (state.client && state.client.id === c.id && regRows.length && empty.parentNode) empty.remove();
          });
        }
      });
    });
  }

  /* The lines this letter captured, as they read on the letter. The snapshot
     is what a person recognises; the mapping is what the database confirms. */
  function docLines(d) {
    return (d.lines || []).map(function (l) { return l.label; }).filter(Boolean);
  }

  function documentRow(d) {
    var st = DOCS.letterState(d);
    var w = LETTER_WORD[st] || LETTER_WORD.issued;
    var waOffer = Boolean(window.ADspaceWhatsApp && window.ADspaceWhatsApp.may('offer'));
    var mapped = (state.docMap || {})[d.id] || [];
    /* Verification is offered only where the letter knows exactly which lines
       it carried. A legacy letter is history and is left as history. */
    var canVerify = st === 'signed' && mapped.length && mapped.length === (d.lines || []).length;
    var row = document.createElement('div');
    row.className = 'svc-row doc-row ltr-row' + (d.voided_at || d.superseded_by ? ' is-off' : '');
    var sub = [DOC_WORD[d.kind] || d.kind, niceDate(d.issued_at), d.issued_by].filter(Boolean).join(' · ');
    var lines = docLines(d);
    row.innerHTML =
      /* The reference is the everyday act on this row: it is copied into a
         message, an invoice or the accounting portal. Same control, same
         answer, as the Documents register's own row. */
      '<span class="svc-name"><b><button class="serial-copy" type="button" data-a="copy" aria-label="Copy ' + esc(d.number) + '">' +
        esc(d.number) + '</button></b><small>' + esc(sub) + '</small>' +
        (lines.length ? '<small>' + esc(lines.join(' · ')) + '</small>' : '') +
        (d.verified_at ? '<small>' + esc('Verified ' + niceDate(d.verified_at) +
          (d.verified_by ? ' · ' + d.verified_by : '')) + '</small>' : '') + '</span>' +
      '<span class="svc-rate svc-amt"><b>' + esc(MON.money2(d.total, d.market)) + '</b></span>' +
      '<span class="svc-state"><span class="tone ' + w[1] + '">' + esc(w[0]) + '</span></span>' +
      /* A signed letter's next step, Verify, stands on the row (MENU-9,
         2026-10-22); the rest is the ⋯ in the standard's order. */
      '<span class="team-act">' +
        (canVerify ? '<button class="btn btn-sm" data-a="verify" type="button">Verify</button>' : '') +
        '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
        '<div class="kmenu" data-menu hidden>' +
          ADspaceMenu.items([
            [{ a: 'download', label: 'Download' }],
            [],
            /* Send on WhatsApp (2026-10-14): the letter's PDF to a contact,
               drawn once the template is on; never a voided or replaced one. */
            [waOffer && !d.voided_at && !d.superseded_by && { a: 'wa', label: 'Send on WhatsApp', hidden: true }],
            [st === 'issued' && { a: 'sign', label: 'Mark signed' },
             st === 'signed' && { a: 'unsign', label: 'Mark not signed' }],
            [],
            /* Void reverses a confirmation, so it is offered on a verified
               letter and nowhere else. Both acts are the section's Manage
               level; the database decides again at the press. */
            [st === 'verified' && { a: 'void', label: 'Void', need: 'clients.documents:manage' },
             { a: 'del', label: 'Delete', need: 'clients.documents:manage' }]]) +
        '</div>' +
      '</span>';
    wireMenu(row);
    var on = function (a, fn) { var el = row.querySelector('[data-a="' + a + '"]'); if (el) el.addEventListener('click', fn); };
    var cp = row.querySelector('[data-a="copy"]');
    if (cp) cp.addEventListener('click', function (e) {
      e.stopPropagation();
      if (window.ADspaceCopy) window.ADspaceCopy.to(this, d.number);
    });
    var shut = function () {
      Array.prototype.forEach.call(row.querySelectorAll('.kmenu'), function (m) { m.hidden = true; });
    };
    var done = function (err) {
      if (err) { msg('crmDocMsg', err, 'err'); loadDocuments(); return; }
      loadDocuments();
    };
    on('download', function () { DOCS.download(d, function (warn) { if (warn) msg('crmDocMsg', warn, 'err'); }); });
    var waIt = row.querySelector('[data-a="wa"]');
    if (waIt) {
      window.ADspaceWhatsApp.on('offer').then(function (yes) { if (yes) waIt.hidden = false; });
      waIt.addEventListener('click', function () {
        shut();
        window.ADspaceWhatsApp.compose({ purpose: 'offer', clientId: d.client_id || (state.client && state.client.id),
          opener: row.querySelector('[data-a="menu"]'),
          doc: { id: d.id, title: d.number, file: function () {
            return DOCS.render(d).then(function (bytes) {
              return { blob: new Blob([bytes], { type: 'application/pdf' }), name: DOCS.fileName(d) };
            });
          } },
          onSent: function (x, line) { msg('crmDocMsg', line, 'ok'); } });
      });
    }
    on('sign', function () {
      shut();
      DOCS.setSigned(d, true, function (err) {
        if (!err) msg('crmDocMsg', d.number + ' is signed, awaiting verification.', 'ok');
        done(err);
      });
    });
    on('unsign', function () { shut(); DOCS.setSigned(d, false, done); });
    /* The one action in this portal that confirms a service, so it says what
       it is about to do and names the letter it is about to do it for. */
    on('verify', function () {
      shut();
      window.ADspaceConfirm.ask({
        title: 'Verify ' + d.number,
        body: 'The ' + mapped.length
            + (mapped.length === 1 ? ' service on this letter is confirmed'
                                   : ' services on this letter are confirmed')
            + ', and nothing else. A verified letter is voided rather than deleted.',
        go: 'Verify'
      }, function () {
        DOCS.verify(d, function (err, out) {
          if (err) { msg('crmDocMsg', err, 'err'); loadDocuments(); return; }
          var n = (out && out.confirmed) || 0;
          msg('crmDocMsg', d.number + ' verified. ' + n +
            (n === 1 ? ' service confirmed.' : ' services confirmed.'), 'ok');
          loadDocuments();
          loadServices();
          /* Verifying is what confirms a service, so it is what moves the
             client's value. Without this the record kept the quoted figure
             until something else happened to save a line. */
          syncValue();
        });
      });
    });
    /* Both of these ask in a sheet rather than a confirm(): each needs a
       reason typed, and one of them needs the reference typed back. Neither
       is a question a browser dialog can carry. */
    on('void', function () { shut(); openVoid(d, mapped.length); });
    on('del', function () { shut(); openDelete(d, mapped.length); });
    return row;
  }

  /* ---- Voiding and deleting a letter -------------------------------------
     Two different acts with two different authorities, so two sheets. A void
     reverses a confirmation and says how many service lines go back; a
     deletion ends the record and takes the reference typed back, because the
     reference is the one thing that identifies which letter stops existing.

     Neither of them trusts this page: the switch that draws the menu item is
     a convenience, and `letter_set_void` and `letter_delete` check the
     signed-in person's live permission when the button is pressed. A
     permission taken away while this sheet is open is a refusal here, not a
     deletion that already happened. */
  var voiding = null;

  function linesWord(n) {
    return n === 1 ? '1 service line' : n + ' service lines';
  }

  function openVoid(d, mapped) {
    voiding = d;
    $('voidWhat').textContent =
      /* A letter issued before the mapping table carries none, and "of 0
         service lines on it" is a clause that says nothing. */
      'Voiding ' + d.number + ' puts back the service lines this letter alone confirmed' +
      (mapped ? ', of ' + linesWord(mapped) + ' on it' : '') + '. ' +
      'A line another verified letter still holds stays confirmed. ' +
      'The letter and its reference are kept, and the reference is never reused.';
    $('voidReason').value = '';
    msg('voidMsg', '', '');
    $('voidSheet').hidden = false;
    $('voidReason').focus();
  }

  /* The one question every Delete asks (2026-10-10): what goes, the
     reference typed back, a reason; kept open on a refusal. */
  function openDelete(d, mapped) {
    window.ADspaceConfirm.ask({
      title: 'Delete',
      body: 'Deleting ' + d.number + ' removes the letter record, its service mapping and the ' +
        'client’s access to it, and puts back the service lines this letter alone confirmed' +
        (mapped ? ', of ' + linesWord(mapped) + ' on it' : '') + '. ' +
        'The file is drawn from the record on Download and is not stored, ' +
        'so nothing is left to recover: this is immediate and cannot be undone. ' +
        'The reference is never reused.',
      go: 'Delete', tone: 'danger', wait: true,
      fields: [
        { name: 'ref', label: 'Type the reference to confirm', placeholder: d.number, match: d.number,
          need: 'Type ' + d.number + ' to confirm.', mismatch: 'Type ' + d.number + ' to confirm.' },
        { name: 'why', label: 'Reason', rows: 3, need: 'A reason is required.' }
      ]
    }, function (v) {
      return new Promise(function (done) {
        DOCS.remove(d, d.number, v.why, function (err, out) {
          if (err) { done(err); return; }
          var n = (out && out.reverted) || 0;
          msg('crmDocMsg', d.number + ' deleted. ' +
            (n ? linesWord(n) + ' put back to To quote.' : 'No service line changed.'), 'ok');
          loadDocuments();
          loadServices();
          syncValue();
          done('');
        });
      });
    });
  }

  function wireLetterSheets() {
    var shutVoid = function () { voiding = null; $('voidSheet').hidden = true; };
    ['voidClose', 'voidCancel'].forEach(function (id) {
      var el = $(id); if (el) el.addEventListener('click', shutVoid);
    });

    var go = $('voidGo');
    if (go) go.addEventListener('click', function () {
      if (!voiding) return;
      var why = String($('voidReason').value || '').trim();
      if (!why) { msg('voidMsg', 'A reason is required.', 'err'); $('voidReason').focus(); return; }
      var d = voiding;
      go.disabled = true;
      DOCS.setVoid(d, why, function (err, out) {
        go.disabled = false;
        if (err) { msg('voidMsg', err, 'err'); return; }
        shutVoid();
        var n = (out && out.reverted) || 0;
        msg('crmDocMsg', d.number + ' voided. ' +
          (n ? linesWord(n) + ' put back to To quote.' : 'No service line changed.'), 'ok');
        loadDocuments();
        loadServices();
        syncValue();
      });
    });

    ['voidSheet'].forEach(function (id) {
      var el = $(id);
      if (el) el.addEventListener('click', function (e) {
        if (e.target === this) shutVoid();
      });
    });
    document.addEventListener('keydown', function (e) {
      if (e.key !== 'Escape') return;
      if (!$('voidSheet').hidden) shutVoid();
    });

  }

  /* ---- Choosing what goes on the letter ---------------------------------
     A letter is issued for the services somebody chose. To quote lines that
     are not already on a live letter are ticked; a line already on one is
     listed with the letter that holds it and cannot be ticked, because the
     way through is to void that letter or replace it. A confirmed line sits
     apart, unticked, for a renewal somebody decides on deliberately. */
  var picking = null;

  function eligible() {
    var live = {};
    (state.documents || []).forEach(function (d) {
      if (!DOCS.liveDoc(d)) return;
      ((state.docMap || {})[d.id] || []).forEach(function (id) { live[id] = d.number; });
    });
    var out = { open: [], held: [], confirmed: [] };
    (state.services || []).forEach(function (l) {
      if (l.archived_at) return;
      if (l.state === 'quoted') (live[l.id] ? out.held : out.open).push({ line: l, on: live[l.id] });
      else if (l.state === 'confirmed') out.confirmed.push({ line: l, on: live[l.id] });
    });
    return out;
  }

  function pickBlock(title, rows, tick, note) {
    if (!rows.length) return '';
    var c = state.client;
    return '<div class="lpickgroup"><h4 class="svc-cat">' + esc(title) + '</h4>' +
      rows.map(function (r) {
        var l = r.line;
        return '<label class="lpickrow' + (tick ? '' : ' is-held') + '">' +
          '<input type="checkbox" value="' + esc(l.id) + '"' + (tick ? ' checked' : '') +
            (tick === false && !r.on ? '' : '') + '>' +
          '<span class="lpickname"><b>' + esc(l.label) + '</b>' +
            '<small>' + esc([l.unit, termWord(l), r.on ? 'On ' + r.on : ''].filter(Boolean).join(' · ')) + '</small></span>' +
          '<span class="lpickamt">' + esc(MON.money2(amountOf(l), MON.curOf(c))) + '</span>' +
        '</label>';
      }).join('') +
      (note ? '<p class="lpicknote">' + esc(note) + '</p>' : '') + '</div>';
  }

  function openPick(only) {
    var c = state.client;
    msg('crmDocMsg', '');
    msg('pickMsg', '');
    /* No Letter of Offer without the billing it prints (2026-10-26); the
       database refuses it too (`needs-billing`). */
    var missing = billingMissing(c);
    if (missing.length) {
      gateBilling(missing, 'a Letter of Offer', document.activeElement, function () { state.toLetter = { id: c.id, only: only || null }; });
      return;
    }
    /* The Client ID is what an automatic reference is built from, so a client
       without one is told here rather than at the end. It is a caution and no
       longer a refusal to open the sheet: a typed reference needs no code,
       and the database is what decides either way. */
    /* Said at the field it concerns, never under the button (2026-10-15,
       audit CLI-4: the field read Numbered automatically while it could not
       be). */
    var noCode = !String(c.client_code || '').trim();
    var e = eligible();
    picking = { replaces: null };
    $('pickBody').innerHTML =
      pickBlock('To quote', e.open, true, '') +
      pickBlock('Already on a live letter', e.held, false,
        'Void that letter, or issue a replacement from its ⋯, before quoting these again.') +
      pickBlock('Confirmed', e.confirmed, false,
        'Tick one only for a renewal, a variation or a replacement.') +
      (e.open.length || e.confirmed.length ? '' : '<p class="lpicknote">Nothing to quote. Add a service line and mark it To quote.</p>') +
      /* The reference is the database's to make and the office's to override.
         Blank is the everyday case and the placeholder says so without a
         sentence; a reference is typed to fill a gap a deleted letter left,
         which is the only reason this field exists. Typing one spends no
         sequence number, so the next automatic letter keeps its place. */
      '<div class="lpickref">' +
        '<label class="field-label" for="pickRef">Reference</label>' +
        '<input class="input input-sm" id="pickRef" type="text" autocomplete="off" spellcheck="false"' +
          (noCode ? ' aria-required="true" aria-describedby="pickRefNote" placeholder="AQL/AC001/261001"' : ' placeholder="Numbered automatically"') + '>' +
        (noCode ? '<p class="msg warn" id="pickRefNote">This client has no Client ID, so the reference cannot be numbered automatically. Type one, or set the ID on the record.</p>' : '') +
      '</div>' +
      /* Terms of this letter's own, one point a line, printed under TERMS
         after the term and the validity (the user, 2026-10-23). */
      '<div class="lpickref">' +
        '<label class="field-label" for="pickTerms">Terms</label>' +
        '<textarea class="input" id="pickTerms" rows="3" placeholder="One point a line">' + esc(DOCS.validLine ? DOCS.validLine() : '') + '</textarea>' +
      '</div>';
    /* A held line is shown so the reason is on the screen, and is refused so
       the same letter cannot go out twice by accident. */
    if (window.ADspaceForm && window.ADspaceForm.scan) window.ADspaceForm.scan($('pickBody'));
    Array.prototype.forEach.call($('pickBody').querySelectorAll('.lpickrow.is-held input'), function (i) {
      i.disabled = true;
    });
    /* Issued from a quotation: its own lines are the ones ticked. */
    if (only && only.length) {
      Array.prototype.forEach.call($('pickBody').querySelectorAll('input[type="checkbox"]:not([disabled])'), function (i) {
        i.checked = only.indexOf(i.value) > -1;
      });
    }
    Array.prototype.forEach.call($('pickBody').querySelectorAll('input[type="checkbox"]'), function (i) {
      i.addEventListener('change', pickSum);
    });
    pickSum();
    /* Lines from one quotation the reader cannot list (no Quotations part)
       are priced on its rate and term as the letter is (the audit of
       2026-10-26, finding 2). */
    state.letterQuotes = [];
    var tick = (state.services || []).filter(function (l) { return pickedIds().indexOf(l.id) > -1; });
    if (tick.length && DOCS.quoteTerms) {
      DOCS.quoteTerms(tick, state.quotes).then(function (qs) {
        var have = state.quotes || [];
        state.letterQuotes = qs.filter(function (x) { return have.indexOf(x) < 0; });
        if (state.letterQuotes.length && !$('pickSheet').hidden) pickSum();
      });
    }
    /* Opened and shut through js/sheet.js (2026-10-22, QT-3): the focus held
       in it and handed back, Escape, and a press outside that never throws
       away a typed reference. Read again in place while it is open. */
    if (!window.ADspaceSheet.isOpen($('pickSheet'))) {
      window.ADspaceSheet.show($('pickSheet'), { opener: document.activeElement, onClose: pickClosed });
    }
  }

  function pickAgain(ids, said) {
    var ref = $('pickRef') ? $('pickRef').value : '';
    var terms = $('pickTerms') ? $('pickTerms').value : '';
    var id = state.client && state.client.id;
    loadServices(function () {
      var reopen = function () {
        if (!state.client || state.client.id !== id || $('pickSheet').hidden) return;
        openPick(ids);
        if ($('pickRef')) $('pickRef').value = ref;
        if ($('pickTerms')) $('pickTerms').value = terms;
        msg('pickMsg', said, 'warn');
      };
      if (window.ADspaceQuotes && mayPart('clients.quotes', 'view')) loadQuotes(reopen, true); else reopen();
    }, function (m) {
      /* The lines could not be read again: the refusal stands, said with
         why, and the next press would be refused the same way. */
      if (!state.client || state.client.id !== id || $('pickSheet').hidden) return;
      msg('pickMsg', 'The services or their quotation changed since this sheet was opened, and could not be read again: ' +
        String(m).replace(/\.$/, '') + '. Close this sheet and open it again.', 'err');
    });
  }

  function pickedIds() {
    return Array.prototype.filter.call($('pickBody').querySelectorAll('input[type="checkbox"]'),
      function (i) { return i.checked && !i.disabled; }).map(function (i) { return i.value; });
  }

  function pickSum() {
    var ids = pickedIds();
    var c = state.client;
    var rows = (state.services || []).filter(function (l) { return ids.indexOf(l.id) > -1; });
    var renewal = rows.some(function (l) { return l.state === 'confirmed'; });
    var price = rows.length ? DOCS.quoteOf(c, rows, (state.quotes || []).concat(state.letterQuotes || []), renewal) : null;
    /* Lines all from one quotation read as the quotation reads, its own
       figure and term, never the letter's whole total (2026-10-22, QT-1). */
    var qid = rows.length && rows[0].quotation_id;
    var q = qid && rows.every(function (l) { return l.quotation_id === qid; }) && window.ADspaceQuotes && window.ADspaceQuotes.headline
      ? (state.quotes || []).filter(function (x) { return x.id === qid; })[0] : null;
    var h = q ? window.ADspaceQuotes.headline(q) : null;
    $('pickSum').textContent = !rows.length ? 'Nothing chosen'
      : h && h[1] ? h[0] + ' ' + h[1].charAt(0).toLowerCase() + h[1].slice(1) + (q.totals && q.totals.month && q.totals.term ? ' · ' + q.totals.term + ' months' : '')
      : rows.length + (rows.length === 1 ? ' service · ' : ' services · ') + MON.money2(price.total, MON.curOf(c));
    $('pickGo').disabled = !rows.length;
  }

  function pickClosed() {
    picking = null;
    $('pickGo').disabled = false;
    $('pickGo').textContent = 'Issue Letter of Offer';
  }
  function shutPick() {
    if (window.ADspaceSheet.isOpen($('pickSheet'))) window.ADspaceSheet.close();
    else { $('pickSheet').hidden = true; pickClosed(); }
  }
  wireLetterSheets();
  $('pickClose').addEventListener('click', shutPick);
  $('pickCancel').addEventListener('click', shutPick);

  $('crmCover').addEventListener('click', function () { if (DOCS) openPick(); });
  /* The quotation cover and the letters to a client are issued from the same
     sheet the Register uses, with this client fixed and its main contact
     seeding the Attn line. */
  $('crmIssueDoc').addEventListener('click', function () {
    var R = window.ADspaceRegister, c = state.client;
    if (!R || !c) return;
    var main = (state.contacts || []).filter(function (p) { return p.is_primary && !p.archived_at; })[0] ||
               (state.contacts || []).filter(function (p) { return !p.archived_at; })[0] || null;
    R.openIssue({ client: c, contact: main, families: ['quote_cover', 'client'], msg: 'crmDocMsg',
                  onDone: function () { loadDocuments(); } });
  });

  $('pickGo').addEventListener('click', function () {
    if (!picking || !DOCS) return;
    var ids = pickedIds();
    if (!ids.length) return;
    var c = state.client;
    if (!String(c.client_code || '').trim() && !($('pickRef').value || '').trim()) {
      msg('pickMsg', 'Type a reference.', 'err');
      $('pickRef').focus();
      return;
    }
    var terms = String(($('pickTerms') || {}).value || '').split(/\r?\n/)
      .map(function (t) { return t.trim(); }).filter(Boolean);
    if (terms.length > 10 || terms.some(function (t) { return t.length > 400; })) {
      msg('pickMsg', 'Terms hold ten points at most, each up to 400 characters.', 'err');
      $('pickTerms').focus();
      return;
    }
    var rows = (state.services || []).filter(function (l) { return ids.indexOf(l.id) > -1; });
    var renewal = rows.some(function (l) { return l.state === 'confirmed'; });
    /* One key per press of this button, held while the request is in flight,
       so a second press is the same submission and comes back as the same
       letter rather than a second one. */
    picking.idem = picking.idem || DOCS.idemKey();
    var go = $('pickGo');
    go.disabled = true;
    go.textContent = 'Issuing…';
    var deal = {
      owner: c.owner || '', source: c.source ? sourceWord(c.source) : '', industry: c.industry || '',
      stage: stageWord(c.stage || 'lead')[1], enquiry: c.deal_note || '', terms: terms
    };
    DOCS.issue('offer', c, rows, deal,
      { idem: picking.idem, replaces: picking.replaces, renewal: renewal, quotes: (state.quotes || []).concat(state.letterQuotes || []),
        serial: ($('pickRef') && $('pickRef').value.trim()) || '' },
      function (r) {
        go.disabled = false;
        go.textContent = 'Issue Letter of Offer';
        /* The services or the quotation they came from changed while the
           sheet was open (or the quotations failed to load, so the page
           priced them without their rate): both are read again and the sheet
           opened on the same ticks, so the next press prices what the
           database holds instead of being refused again (2026-10-18). */
        if (r.code === 'stale') { pickAgain(ids, r.error); return; }
        if (r.error) { msg('pickMsg', r.error, 'err'); return; }
        shutPick();
        msg('crmDocMsg', r.number + (r.repeat ? ' was already issued.' : ' issued.') +
          (r.warn ? ' ' + r.warn : ''), r.warn ? 'warn' : 'ok');
        loadDocuments();
      });
  });

  // ---- Rate card (the Services section) ------------------------------------
  var editingSvc = null;
  /* The rate card is edited by whoever manages Services. It asked for
     `admin` before the levels, which made the one person who could correct a
     price the same person who administers the team. */
  function maySvc() { return Boolean(bridge.may && bridge.may('services', 'manage')); }
  /* What is typed in the command bar. Kept out of the URL: a search is what
     somebody is doing this minute, not where they are. */
  var svcFind = '';

  function enterServices() {
    catalog = null; live = null; liveRead = false; svcText = null; svcVers = null;
    var t = new URLSearchParams(location.search).get('tab');
    svcTab = SVC_TABS.some(function (x) { return x[0] === t; }) ? t : 'card';
    $('svcAdd').hidden = !maySvc();
    $('svcTax').hidden = !window.ADspaceAdmin.may('team.settings', 'work');
    shutSheet('svcBox');
    msg('svcListMsg', '');
    skeleton($('svcList'), 6);
    $('svcLive').hidden = true;
    $('svcCardPdf').hidden = true;
    loadCatalog(function () {
      loadLive(function () {
        db.from('rate_card_text').select('key, label, page, position, value').order('position').then(function (r) {
          /* A database from before the versions has no words table: the card
             is drawn as it always was, with no strip and no version line. */
          svcText = r.error ? null : (r.data || []);
          paintServicesPage();
        }).catch(function () { svcText = null; paintServicesPage(); });
      });
    });
  }

  // ---- Rate card versions (2026-10-13) --------------------------------------
  /* The card is edited as a draft and goes live as a numbered version
     (rate_card_publish); a quote, a client's line and the export read the
     version, never the draft (the user, 2026-10-13: "every version changed
     would proceed proper updates to the site and export"). */
  var SVC_TABS = [['card', 'Rate card'], ['words', 'Wording'], ['versions', 'Versions']];
  var svcTab = 'card', live = null, liveRead = false, svcText = null, svcVers = null, diffNow = { lines: {}, words: {}, n: 0 };
  /* Review n changes (2026-10-22, SVC2-M1): the card shows only what the
     draft holds that the live version does not. */
  var svcReview = false;
  function loadLive(then) {
    if (liveRead) { then(live); return; }
    db.rpc('rate_card_current').then(function (r) {
      liveRead = true;
      live = !r.error && r.data && r.data.snapshot ? r.data : null;
      then(live);
    }).catch(function () { liveRead = true; live = null; then(null); });
  }
  function svcState() { return { tab: svcTab === 'card' ? '' : svcTab }; }
  /* One reading of a value for comparing the draft with the live version:
     keys in order, numbers as numbers, an empty value as nothing. */
  function canon(v) {
    if (v == null || v === '') return 'null';
    if (Array.isArray(v)) return '[' + v.map(canon).join(',') + ']';
    if (typeof v === 'object') return '{' + Object.keys(v).sort().map(function (k) { return k + ':' + canon(v[k]); }).join(',') + '}';
    if (typeof v === 'number' || (typeof v === 'string' && /^-?\d+(\.\d+)?$/.test(v))) return String(Number(v));
    return JSON.stringify(v);
  }
  var SVC_CMP = ['category', 'name', 'rate', 'unit', 'position', 'active', 'note', 'detail', 'min_months', 'spec'];
  /* What the draft holds that the live version does not: each line New or
     Changed, a line gone, each block of words changed. */
  function svcDiff() {
    var out = { lines: {}, was: {}, gone: 0, goneNames: [], words: {}, n: 0 };
    if (!live) return out;
    var was = {};
    (live.snapshot.services || []).forEach(function (x) { was[x.slug] = x; });
    (catalog || []).forEach(function (s) {
      var w = was[s.slug];
      if (!w) { out.lines[s.slug] = 'New'; out.n++; return; }
      if (SVC_CMP.some(function (k) { return canon(s[k]) !== canon(w[k]); })) { out.lines[s.slug] = 'Changed'; out.was[s.slug] = w; out.n++; }
      delete was[s.slug];
    });
    out.gone = Object.keys(was).length; out.n += out.gone;
    out.goneNames = Object.keys(was).map(function (k) { return was[k].name || k; });
    var said = live.snapshot.text || {};
    (svcText || []).forEach(function (b) {
      if (canon(b.value) !== canon(said[b.key])) { out.words[b.key] = 'Changed'; out.n++; }
    });
    return out;
  }
  function paintServicesPage() {
    var versioned = svcText !== null;
    var strip = $('svcTabs');
    strip.hidden = !versioned;
    if (!versioned) svcTab = 'card';
    if (versioned) {
      strip.innerHTML = SVC_TABS.map(function (t) {
        var on = t[0] === svcTab;
        return '<button class="tab' + (on ? ' is-on' : '') + '" type="button" role="tab" data-tab="' + t[0] + '" id="svcTab-' + t[0] + '"' +
          ' aria-selected="' + on + '" tabindex="' + (on ? 0 : -1) + '"><span>' + esc(t[1]) + '</span></button>';
      }).join('');
      if (window.ADspaceForm && window.ADspaceForm.thumb) window.ADspaceForm.thumb(strip);
    }
    $('svcList').hidden = svcTab !== 'card';
    $('svcWords').hidden = svcTab !== 'words';
    $('svcVersions').hidden = svcTab !== 'versions';
    diffNow = svcDiff();
    if (!live || !diffNow.n) svcReview = false;
    /* While the changes are reviewed the card is not searched: what shows
       is what changed (SVC2-M1). */
    var find = $('svcFind') && $('svcFind').closest('.cmdbar-find');
    if (find) find.hidden = svcTab !== 'card' || svcReview;
    $('svcCount').hidden = svcTab !== 'card' || svcReview;
    /* A service is added on the card itself, never from its wording or versions. */
    $('svcAdd').hidden = !maySvc() || svcTab !== 'card';
    paintLiveLine();
    if (svcTab === 'card') paintCatalog();
    if (svcTab === 'words') paintWords();
    if (svcTab === 'versions') paintVersions();
  }
  if ($('svcTabs')) {
    $('svcTabs').addEventListener('click', function (e) {
      var b = e.target.closest && e.target.closest('.tab');
      if (!b || b.getAttribute('data-tab') === svcTab) return;
      svcTab = b.getAttribute('data-tab');
      svcReview = false;
      msg('svcListMsg', '');
      paintServicesPage();
      setUrl();
    });
    $('svcTabs').addEventListener('keydown', function (e) {
      var tabs = Array.prototype.slice.call(this.querySelectorAll('.tab'));
      var i = tabs.indexOf(document.activeElement);
      if (i < 0) return;
      var to = e.key === 'ArrowRight' ? i + 1 : e.key === 'ArrowLeft' ? i - 1 : e.key === 'Home' ? 0 : e.key === 'End' ? tabs.length - 1 : null;
      if (to === null || !tabs[to]) return;
      e.preventDefault();
      tabs[to].click(); tabs[to].focus();
    });
  }
  function paintLiveLine() {
    var box = $('svcLive');
    if (svcText === null) { box.hidden = true; return; }
    var d = diffNow;
    box.hidden = false;
    box.innerHTML = '<span class="svc-live-now">' + (live
        ? '<span class="chip-state is-live">Live</span> <b>v.' + esc(live.version) + '</b>' +
          (live.valid_until ? ' · valid until ' + esc(niceDate(live.valid_until)) : '')
        : '<span class="chip-state is-off">Not published</span>') + '</span>' +
      '<span class="svc-live-acts">' +
        /* Review n changes (2026-10-22, SVC2-M1): a toggle beside Publish
           showing only what changed, each line from and to. */
        (live && d.n ? '<button class="btn btn-sm svc-live-n" id="svcReview" type="button" aria-pressed="' + svcReview + '">Review ' +
          d.n + ' change' + (d.n === 1 ? '' : 's') + '</button>' : '') +
        (maySvc() && (d.n || !live)
          ? '<button class="btn btn-sm btn-primary" id="svcPublish" type="button" data-need="services:manage">' + PLANE + 'Publish</button>' : '') +
      '</span>';
    var pb = $('svcPublish');
    if (pb) pb.addEventListener('click', function () { publishCard(pb, d); });
    var rv = $('svcReview');
    if (rv) rv.addEventListener('click', function () { reviewCard(!svcReview); });
    $('svcCardPdf').hidden = !live;
  }
  /* The rate card as the team issues it, drawn from the live version and
     saved under its own name (js/ratecardpdf.js). */
  /* `card` is the live version unless a version's row names another, which
     is read whole at the press (ux-audit SVC-9: every version downloads). */
  function cardPdf(btn, read) {
    var docs = window.ADspaceDocs, tab = docs && docs.tabFor ? docs.tabFor() : null;
    var m = $('svcLiveMsg'), card = live;
    btn.disabled = true;
    if (m) { m.hidden = true; m.textContent = ''; }
    Promise.resolve(read ? read() : live).then(function (c) {
      if (!c || !c.snapshot) throw new Error('The version could not be read.');
      card = c;
      if (!window.ADspaceRateCardPdf) throw new Error('The PDF tools are not loaded.');
      return window.ADspaceRateCardPdf.draw(card);
    }).then(function (blob) {
      btn.disabled = false;
      docs.save(blob, 'ADspace Rate Card ' + window.ADspaceRateCardPdf.tag(card) + '.pdf', tab);
    }).catch(function (e) {
      btn.disabled = false;
      if (docs && docs.shut) docs.shut(tab);
      if (m) { m.hidden = false; m.className = 'msg err'; m.textContent = 'Not drawn. ' + ((e && e.message) || 'Please try again.'); }
    });
  }
  var PLANE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M22 2 11 13"/><path d="M22 2 15 22l-4-9-9-4z"/></svg>';
  function nextVersion(v) {
    var p = String(v || '').split('.').map(Number);
    if (!p.length || p.some(isNaN)) return '';
    p[p.length - 1] += 1;
    return p.join('.');
  }
  var PUB_SAID = { 'bad-version': 'Enter the version as numbers with dots, for example 2.0.7.',
    'version-taken': 'That version is already published.', 'bad-date': 'Valid until cannot be in the past.',
    'no-change': 'Nothing has changed since the live version.', 'too-long': 'The note is too long.',
    denied: 'Publishing needs Services at Full Access.' };
  /* What a line's change moved, from and to, in the record's own words
     ("Rate: RM 2,830.00 → RM 2,900.00"; 2026-10-22, SVC2-M1). */
  var SVC_LIST = 5;
  function svcMoved(was, now) {
    var view = function (x) {
      return { name: x.name, category: x.category, rate: x.rate == null ? 'On quote' : MON.money2(x.rate, 'MY'),
        unit: x.unit, min_months: x.min_months, active: x.active === false ? 'Inactive' : 'Active', detail: x.detail, note: x.note };
    };
    var said = window.ADspaceRecords.changes(view(was), view(now), [['name', 'Name'], ['category', 'Category'], ['rate', 'Rate'],
      ['unit', 'Unit'], ['min_months', 'Minimum months'], ['active', 'State'], ['detail', 'Inclusions'], ['note', 'Note']]);
    var more = [];
    if (canon(was.spec) !== canon(now.spec)) more.push('In quotes changed');
    if (canon(was.position) !== canon(now.position)) more.push('Order changed');
    return [said].concat(more).filter(Boolean).join('; ');
  }
  function changeList(d) {
    var out = [];
    (catalog || []).forEach(function (s) {
      if (d.lines[s.slug] === 'New') out.push(s.name + ': new line');
      else if (d.lines[s.slug]) out.push(s.name + ': ' + (svcMoved(d.was[s.slug] || {}, s) || 'changed'));
    });
    (d.goneNames || []).forEach(function (n) { out.push(n + ': removed'); });
    (svcText || []).forEach(function (b) {
      if (d.words[b.key]) out.push(String(b.label || b.key).replace(/\s*\([^)]*\|[^)]*\)\s*$/, '') + ': wording changed');
    });
    return out;
  }
  function reviewCard(on) {
    svcReview = on;
    if (on && svcTab !== 'card') { svcTab = 'card'; setUrl(); }
    msg('svcListMsg', '');
    paintServicesPage();
    var rv = $('svcReview');
    if (rv) rv.focus();
  }
  function publishCard(btn, d) {
    var parts = [];
    var lines = Object.keys(d.lines).length, words = Object.keys(d.words).length;
    /* "2 lines and 1 block of wording changed." (2026-10-22, SVC2-6). */
    if (lines) parts.push(lines + ' line' + (lines === 1 ? '' : 's') + ' changed');
    if (d.gone) parts.push(d.gone + ' line' + (d.gone === 1 ? '' : 's') + ' removed');
    if (words) parts.push(words + ' block' + (words === 1 ? '' : 's') + ' of wording changed');
    var said = parts.length < 2 ? parts.join('') : parts.slice(0, -1).join(', ') + ' and ' + parts[parts.length - 1];
    /* The same changes Review shows, five, then how many more (SVC2-M1). */
    var list = changeList(d), more = list.length - SVC_LIST;
    window.ADspaceConfirm.ask({
      title: 'Publish the rate card',
      body: (said ? said.charAt(0).toUpperCase() + said.slice(1) + '.\n' : '') +
        (list.length ? list.slice(0, SVC_LIST).join('\n') + (more > 0 ? '\nand ' + more + ' more' : '') + '\n\n' : '') +
        'Quotes, client service lines and the export use this version from now on.',
      go: 'Publish', wait: true,
      fields: [
        { name: 'v', label: 'Version', value: live ? nextVersion(live.version) : '2.0.6', placeholder: '2.0.7', type: 'text',
          need: 'A version is required.' },
        { name: 'until', label: 'Valid until', type: 'date', value: live && live.valid_until ? String(live.valid_until).slice(0, 10) : '', required: false },
        { name: 'note', label: 'Note', placeholder: 'Optional', required: false }
      ]
    }, function (v) {
      return db.rpc('rate_card_publish', { p_version: v.v, p_valid_until: v.until || null, p_note: v.note || null }).then(function (r) {
        if (r.error) return /function|schema cache/i.test(r.error.message) ? 'This needs a database update.' : r.error.message;
        if (r.data && r.data.error) return PUB_SAID[r.data.error] || 'Not published.';
        liveRead = false; svcVers = null;
        loadLive(function () { paintServicesPage(); msg('svcListMsg', 'Published v.' + v.v + '.', 'ok'); });
        return '';
      });
    });
  }

  /* A block of the card's words as a row: its name, Changed where the draft
     moved it, the first line, its pen. */
  function wordRow(b, d) {
    var row = document.createElement('div');
    row.className = 'svc-row cat-row rcw-row';
    /* The label's column list and the row's pipes are how the card
       stores a table; the row reads them as words (ux-audit SVC-6). */
    var first = String(b.value || '').split('\n')[0].split(/\s*\|\s*/).join(' · ');
    var named = String(b.label || '').replace(/\s*\([^)]*\|[^)]*\)\s*$/, '');
    row.innerHTML = '<span class="svc-name"><b>' + esc(named) + (d.words[b.key] ? ' <span class="chip">' + d.words[b.key] + '</span>' : '') + '</b>' +
      '<small>' + (first ? esc(first) : '<span class="muted">Not set</span>') + '</small></span>' +
      /* Edit is the row's one act, its pen on the row, never a ⋯ of
         one item (2026-10-20, SVC-1). */
      '<span class="team-act">' + (maySvc()
        ? '<button class="kmenu-btn rcw-edit" data-a="edit" type="button" aria-label="Edit ' + esc(named) + '">' + PEN + '</button>'
        : '') + '</span>';
    if (maySvc()) row.querySelector('[data-a="edit"]').addEventListener('click', function () { editWords(b); });
    return row;
  }
  /* The card's own words, a block a key, grouped by the page they print on. */
  function paintWords() {
    var box = $('svcWords');
    box.innerHTML = '';
    var GRP = window.ADspaceGroup;
    var d = diffNow;
    var pages = [];
    (svcText || []).forEach(function (b) { if (pages.indexOf(b.page) < 0) pages.push(b.page); });
    if (!pages.length) { box.innerHTML = '<div class="softpanel"><div class="emptyline"><b>No entries.</b></div></div>'; return; }
    pages.forEach(function (pg) {
      var blocks = svcText.filter(function (b) { return b.page === pg; });
      var key = 'words-' + String(pg).toLowerCase().replace(/[^a-z0-9]+/g, '-');
      box.appendChild(GRP.section({
        route: 'services', key: key, name: pg, count: blocks.length,
        shut: GRP.shut('services', key, false),
        table: function () {
          /* Words have no price: the row is the block and its pen, the
             Changed tag after its name (2026-10-22, SVC2-8). */
          var table = GRP.table('svc-row cat-row rcw-row', ['Wording', '']);
          blocks.forEach(function (b) { table.appendChild(wordRow(b, d)); });
          return table;
        }
      }));
    });
  }
  /* A block of the card's words, edited as the card prints it: a list point
     by point (numbered, each its own field, moved up or removed), a table a
     row at a time under its columns (the label names them: "Tiers (Tier |
     Followers | Indicative Talent Fee)"), a sentence as one field. Nothing is
     typed as a box of lines (the user, 2026-10-13: "so ugly and untidy
     unstructured"). Saved as the lines the PDF reads. */
  var UP = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 19V5"/><path d="m5 12 7-7 7 7"/></svg>';
  var CROSS = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>';
  var rcw = null;
  function wordsShape(b) {
    var m = /\(([^)]*\|[^)]*)\)\s*$/.exec(b.label || '');
    var lines = String(b.value || '').split(/\r?\n/).filter(function (l) { return l.trim(); });
    if (m) return { kind: 'cols', cols: m[1].split('|').map(function (x) { return x.trim(); }), fixed: lines.length < 2 && !/Tiers|Formats|Timeline/.test(b.label) };
    if (lines.length > 1 || /Included|Note|Terms|Opening/.test(b.label)) return { kind: 'list' };
    return { kind: 'one' };
  }
  function editWords(b) {
    Array.prototype.forEach.call(document.querySelectorAll('.kmenu'), function (m) { m.hidden = true; });
    var shape = wordsShape(b);
    rcw = { b: b, shape: shape };
    $('rcwTitle').textContent = String(b.label || '').replace(/\s*\([^)]*\|[^)]*\)\s*$/, '');
    var head = $('rcwHead');
    head.hidden = shape.kind !== 'cols';
    head.classList.toggle('is-fixed', !!shape.fixed);
    head.style.setProperty('--n', shape.cols ? shape.cols.length : 1);
    head.innerHTML = shape.kind === 'cols' ? shape.cols.map(function (c) { return '<span class="field-label">' + esc(c) + '</span>'; }).join('') : '';
    $('rcwRows').innerHTML = '';
    var lines = String(b.value || '').split(/\r?\n/).filter(function (l) { return l.trim(); });
    if (shape.kind === 'one') lines = [String(b.value || '').trim()];
    if (!lines.length) lines = [''];
    lines.forEach(function (l) { rcwRow(l); });
    var add = $('rcwAdd');
    add.parentNode.hidden = shape.kind === 'one' || (shape.kind === 'cols' && shape.fixed);
    add.textContent = shape.kind === 'cols' ? 'Add row' : 'Add point';
    if (window.ADspaceActs && window.ADspaceActs.mark) window.ADspaceActs.mark(add);
    msg('rcwMsg', '', '');
    rcwNumber();
    openSheet('rcwBox');
  }
  function rcwRow(line) {
    var sh = rcw.shape, box = $('rcwRows');
    var row = document.createElement('div');
    row.className = 'rcw-pt' + (sh.kind === 'cols' ? ' is-cols' : '') + (sh.kind === 'one' ? ' is-one' : '');
    var cells = sh.kind === 'cols' ? String(line).split('|').map(function (x) { return x.trim(); }) : [line];
    var fields = sh.kind === 'cols'
      ? '<span class="rcw-cols" style="--n:' + sh.cols.length + '">' + sh.cols.map(function (c, i) {
          return '<span class="rcw-cell"><span class="field-label rcw-cl">' + esc(c) + '</span>' +
            '<textarea class="input" rows="1" data-oneline aria-label="' + esc(c) + '">' + esc(cells[i] || '') + '</textarea></span>';
        }).join('') + '</span>'
      : '<textarea class="input" rows="1" data-oneline aria-label="' + (sh.kind === 'one' ? 'Words' : 'Point') + '">' + esc(cells[0] || '') + '</textarea>';
    var fixed = sh.kind === 'one' || (sh.kind === 'cols' && sh.fixed);
    row.innerHTML = (sh.kind === 'list' ? '<span class="rcw-no"></span>' : sh.kind === 'cols' && !fixed ? '<span class="rcw-no rcw-rowno"></span>' : '') + fields +
      (fixed ? '' : '<span class="rcw-acts"><button class="iconbtn" data-a="up" type="button">' + UP + '</button>' +
        '<button class="iconbtn" data-a="x" type="button">' + CROSS + '</button></span>');
    box.appendChild(row);
    if (!fixed) {
      row.querySelector('[data-a="up"]').addEventListener('click', function () {
        var prev = row.previousElementSibling;
        if (prev) { box.insertBefore(row, prev); rcwNumber(); row.querySelector('[data-a="up"]').focus(); }
      });
      row.querySelector('[data-a="x"]').addEventListener('click', function () {
        var next = row.nextElementSibling || row.previousElementSibling;
        box.removeChild(row);
        if (!box.children.length) rcwRow('');
        rcwNumber();
        var f = (next && next.parentNode ? next : box.lastElementChild).querySelector('textarea');
        if (f) f.focus();
      });
    }
    Array.prototype.forEach.call(row.querySelectorAll('textarea'), function (t) {
      if (window.ADspaceGrow) window.ADspaceGrow.fit(t);
    });
    return row;
  }
  function rcwNumber() {
    var rows = $('rcwRows').children, word = rcw.shape.kind === 'cols' ? 'row' : 'point';
    Array.prototype.forEach.call(rows, function (r, i) {
      var no = r.querySelector('.rcw-no');
      if (no) no.textContent = rcw.shape.kind === 'cols' ? 'Row ' + (i + 1) : (i + 1) + '.';
      var up = r.querySelector('[data-a="up"]'), x = r.querySelector('[data-a="x"]');
      if (up) { up.classList.toggle('is-first', i === 0); up.disabled = i === 0; up.setAttribute('aria-label', 'Move ' + word + ' ' + (i + 1) + ' up'); }
      if (x) x.setAttribute('aria-label', 'Remove ' + word + ' ' + (i + 1));
    });
  }
  function rcwValue() {
    var sh = rcw.shape, out = [];
    Array.prototype.forEach.call($('rcwRows').children, function (r) {
      var vals = Array.prototype.map.call(r.querySelectorAll('textarea'), function (t) { return t.value.replace(/\s+/g, ' ').trim(); });
      if (sh.kind === 'cols') { if (vals.some(Boolean)) out.push(vals.join(' | ')); }
      else if (vals[0]) out.push(vals[0]);
    });
    return out.join('\n');
  }
  function rcwSave() {
    var b = rcw.b, v = rcwValue(), btn = $('rcwSave');
    if (!v) { msg('rcwMsg', 'Words are required.', 'err'); var f = $('rcwRows').querySelector('textarea'); if (f) f.focus(); return; }
    if (v === String(b.value || '').trim()) { shutSheet('rcwBox'); return; }
    btn.disabled = true;
    db.rpc('rate_card_text_save', { p_key: b.key, p_value: v }).then(function (r) {
      btn.disabled = false;
      var no = r.error ? (/function|schema cache/i.test(r.error.message) ? 'This needs a database update.' : r.error.message)
        : r.data && r.data.error ? (r.data.error === 'denied' ? 'Changing the wording needs Services at Full Access.'
          : r.data.error === 'too-long' ? 'The words are too long.' : 'Not saved.') : '';
      if (no) { msg('rcwMsg', no, 'err'); return; }
      b.value = v;
      if (window.ADspaceSheet) window.ADspaceSheet.clean();
      shutSheet('rcwBox');
      paintServicesPage();
      msg('svcListMsg', 'Saved.', 'ok');
    }).catch(function () { btn.disabled = false; msg('rcwMsg', 'Not saved. Please try again.', 'err'); });
  }
  (function () {
    if (!$('rcwBox')) return;
    $('rcwAdd').addEventListener('click', function () {
      var row = rcwRow(''); rcwNumber();
      var f = row.querySelector('textarea'); if (f) f.focus();
    });
    $('rcwSave').addEventListener('click', rcwSave);
    $('rcwCancel').addEventListener('click', function () { shutSheet('rcwBox'); });
    sheetClose('rcwClose', 'rcwCancel');
  })();

  /* Every version published, newest first; the live one marked. */
  function paintVersions() {
    var box = $('svcVersions');
    if (!svcVers) {
      skeleton(box, 3);
      db.from('rate_card_versions').select('id, version, valid_until, note, published_at, published_by')
        .order('published_at', { ascending: false }).then(function (r) {
          if (r.error) {
            window.ADspaceState.failLine(box, 'Versions', r.error.message, function () { svcVers = null; paintVersions(); });
            return;
          }
          svcVers = r.data || [];
          paintVersions();
        });
      return;
    }
    box.innerHTML = '';
    var GRP = window.ADspaceGroup;
    box.appendChild(GRP.section({
      route: 'services', key: 'versions', name: 'Versions', count: svcVers.length, shut: false,
      table: function () {
        var table = GRP.table('svc-row cat-row rcv-row', ['Version', { text: 'State', cls: 'svc-rate' }, { text: 'Valid until', cls: 'svc-unit' }, '']);
        if (!svcVers.length) {
          var e = document.createElement('div');
          e.className = 'emptyline';
          e.innerHTML = '<b>No entries.</b>';
          table.appendChild(e);
        }
        svcVers.forEach(function (v, i) {
          var row = document.createElement('div');
          row.className = 'svc-row cat-row rcv-row';
          row.innerHTML = '<span class="svc-name"><b>v.' + esc(v.version) + '</b><small>' +
              esc(niceDate(String(v.published_at).slice(0, 10)) + (v.published_by ? ' · ' + v.published_by : '') + (v.note ? ' · ' + v.note : '')) + '</small></span>' +
            '<span class="svc-rate">' + (i === 0 ? '<span class="chip-state is-live">Live</span>' : '<span class="chip-state is-off">Replaced</span>') + '</span>' +
            /* A phone hides the heading, so the date names itself there
               (ux-audit SVC-4). */
            '<span class="svc-unit">' + (v.valid_until ? '<span class="rcv-k">Valid until </span>' + esc(niceDate(v.valid_until)) : '<span class="muted">—</span>') + '</span>' +
            '<span class="team-act"><button class="btn btn-sm" type="button" data-a="dl" aria-label="Download v.' + esc(v.version) + '">Download</button></span>';
          var dl = row.querySelector('[data-a="dl"]');
          dl.addEventListener('click', function () {
            cardPdf(dl, i === 0 && live && live.version === v.version ? null : function () {
              return db.from('rate_card_versions').select('id, version, valid_until, note, snapshot, published_at, published_by')
                .eq('id', v.id).maybeSingle().then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; });
            });
          });
          table.appendChild(row);
        });
        return table;
      }
    }));
  }

  /* A line's quote details read as words: in the change log and the row. */
  function specWord(sp) {
    if (!sp || !sp.role) return '';
    var r = sp.role;
    if (r === 'plan') return 'Plan ' + sp.plan + ' · ' + sp.platforms + ' platform' + (sp.platforms == 1 ? '' : 's') + ' · ' +
      sp.contents + ' contents · ' + (sp.ads ? 'with ads to RM ' + Number(sp.ad_budget || 0).toLocaleString('en-MY') : 'without ads') +
      ' · ' + mixWord(sp.mix);
    if (r === 'platform') return 'Platform: ' + ({ meta: 'Meta', tiktok: 'TikTok', rednote: 'rednote', linkedin: 'LinkedIn' })[sp.platform];
    if (r === 'ads') return 'Advertising to RM ' + Number(sp.budget).toLocaleString('en-MY');
    if (r === 'booster') return 'Ads booster to RM ' + Number(sp.budget).toLocaleString('en-MY');
    if (r === 'language') return 'Added language';
    if (r === 'content') return 'Content: ' + sp.kind;
    if (r === 'verify') return 'Verification' + (sp.fee ? ' · ' + sp.fee : '');
    if (r === 'koc') return 'KOC package' + (sp.creators ? ' · ' + sp.creators + ' creators' : '');
    if (r === 'kol') return 'KOL management fee · ' + (sp.tiers || []).length + ' tiers';
    if (r === 'addon') return 'Add-on' + (sp.group ? ' · ' + sp.group : '');
    return r;
  }
  function mixWord(mix) {
    return (mix || []).map(function (m) {
      var p = [];
      if (m.graphic) p.push(m.graphic + ' graphic' + (m.graphic == 1 ? '' : 's'));
      if (m.reel) p.push(m.reel + ' reel' + (m.reel == 1 ? '' : 's'));
      return p.join(' + ');
    }).join('\n');
  }
  function mixOf(text) {
    var out = [], bad = false;
    String(text || '').split('\n').forEach(function (line) {
      line = line.trim();
      if (!line) return;
      var m = {}, any = false;
      line.split(/\+|,|\band\b/i).forEach(function (part) {
        part = part.trim();
        if (!part) return;
        var x = /^(\d+)\s*x?\s*(graphics?|reels?)\b/i.exec(part);
        if (!x || Number(x[1]) < 1) { bad = true; return; }
        m[/^g/i.test(x[2]) ? 'graphic' : 'reel'] = Number(x[1]);
        any = true;
      });
      if (any) out.push(m);
    });
    return bad ? null : out;
  }
  function tiersWord(t) {
    return (t || []).map(function (x) { return (x.upto == null ? 'Above' : x.upto) + ' | ' + x.pct + ' | ' + x.min; }).join('\n');
  }
  function tiersOf(text) {
    var out = [], bad = false;
    String(text || '').split('\n').forEach(function (line) {
      if (!line.trim()) return;
      var p = line.split('|').map(function (x) { return x.trim().replace(/[RM,%\s]/gi, ''); });
      var up = /^above$/i.test(p[0]) ? null : Number(p[0]);
      if (p.length !== 3 || (up !== null && !(up > 0)) || !(Number(p[1]) >= 0) || !(Number(p[2]) >= 0)) { bad = true; return; }
      out.push({ upto: up, pct: Number(p[1]), min: Number(p[2]) });
    });
    return bad ? null : out;
  }
  function syncRole() {
    var role = $('svcRole').value;
    Array.prototype.forEach.call($('svcSpecSec').querySelectorAll('[data-role]'), function (el) {
      el.hidden = !role || (' ' + el.getAttribute('data-role') + ' ').indexOf(' ' + role + ' ') < 0;
    });
    $('svcPlanBudgetWrap').hidden = $('svcAds').value !== 'yes';
  }
  $('svcRole').addEventListener('change', syncRole);
  $('svcAds').addEventListener('change', syncRole);
  function fillSpec(sp) {
    sp = sp || {};
    $('svcRole').value = sp.role || '';
    $('svcPlatform').value = sp.platform || 'meta';
    $('svcKind').value = sp.kind || 'graphic';
    $('svcFee').value = sp.fee || '';
    $('svcCreators').value = sp.creators || '';
    $('svcGroup').value = sp.group || 'Revisions & Turnaround';
    $('svcBudget').value = sp.budget || '';
    $('svcPlan').value = sp.plan || '';
    $('svcPlatforms').value = sp.platforms || '';
    $('svcContents').value = sp.contents || '';
    $('svcAds').value = sp.ads ? 'yes' : 'no';
    $('svcPlanBudget').value = sp.ad_budget || '';
    $('svcMix').value = mixWord(sp.mix);
    $('svcBest').value = sp.best_for || '';
    $('svcTiers').value = tiersWord(sp.tiers);
    syncRole();
  }
  /* The spec the sheet states, or a refusal naming the field. */
  function readSpec() {
    var role = $('svcRole').value;
    if (!role) return { spec: null };
    var n = function (id) { var v = String(val(id) || '').trim(); return v === '' ? null : Number(v); };
    var sp = { role: role };
    if (role === 'plan') {
      sp.plan = String(val('svcPlan') || '').trim().toUpperCase();
      if (!/^[A-Z]$/.test(sp.plan)) return { err: 'The plan is one letter.', at: 'svcPlan' };
      sp.ads = $('svcAds').value === 'yes';
      sp.platforms = n('svcPlatforms');
      if (!(sp.platforms >= 1 && sp.platforms <= 99 && sp.platforms % 1 === 0)) return { err: 'Platforms is required.', at: 'svcPlatforms' };
      sp.contents = n('svcContents');
      if (!(sp.contents >= 1 && sp.contents <= 99 && sp.contents % 1 === 0)) return { err: 'Contents a month is required.', at: 'svcContents' };
      sp.mix = mixOf(val('svcMix'));
      if (!sp.mix || !sp.mix.length || sp.mix.length > 3) return { err: 'Write each content option as 1 graphic + 3 reels, one a line, three at most.', at: 'svcMix' };
      if (sp.ads) {
        sp.ad_budget = n('svcPlanBudget');
        if (!(sp.ad_budget > 0)) return { err: 'The ad budget covered is required.', at: 'svcPlanBudget' };
      }
      var best = String(val('svcBest') || '').trim();
      if (best) sp.best_for = best;
    } else if (role === 'platform') sp.platform = $('svcPlatform').value;
    else if (role === 'ads' || role === 'booster') {
      sp.budget = n('svcBudget');
      if (!(sp.budget >= 1 && sp.budget % 1 === 0)) return { err: 'The ad budget covered is required.', at: 'svcBudget' };
    } else if (role === 'content') sp.kind = $('svcKind').value;
    else if (role === 'verify') { var fee = String(val('svcFee') || '').trim(); if (fee) sp.fee = fee; }
    else if (role === 'koc') { var c = n('svcCreators'); if (c) sp.creators = c; }
    else if (role === 'kol') {
      sp.tiers = tiersOf(val('svcTiers'));
      if (!sp.tiers || !sp.tiers.length) return { err: 'Write each tier as 3000 | 18 | 500, one a line.', at: 'svcTiers' };
    } else if (role === 'addon' || role === 'language') sp.group = $('svcGroup').value;
    return { spec: sp };
  }

  /* Loading is the shape of what is coming, not the word for it: a line of
     text that is replaced by rows makes the page jump by its own height. */
  function skeleton(box, n) {
    var html = '';
    for (var i = 0; i < n; i++) html += '<div class="skel-row"></div>';
    box.innerHTML = '<div class="softpanel"><div class="skel">' + html + '</div></div>';
  }

  // The tiers the card is read in, and the categories inside each.
  function svcTiers(rows) {
    var extra = rows.map(function (s) { return s.category; })
      .filter(function (k, i, a) { return CATS.indexOf(k) < 0 && a.indexOf(k) === i; });
    return [
      ['Services', ['Content', 'Account management', 'Monthly packages',
                    'KOC programmes', 'KOL programmes'].concat(extra)],
      ['Add-ons',  ['Verification', 'Add-ons']]
    ];
  }

  /* Name, what it includes and the unit: a search on the card is somebody
     looking for a line to quote, and they rarely remember its exact title. */
  function svcMatch(s) {
    if (!svcFind) return true;
    var hay = [s.name, s.sku, s.note, s.unit, s.detail, s.category].join(' ').toLowerCase();
    return hay.indexOf(svcFind) > -1;
  }

  function paintCatalog() {
    var box = $('svcList');
    box.innerHTML = '';
    var all = catalog || [];
    if (svcReview) { paintReview(box, all); return; }
    var rows = all.filter(svcMatch);
    var count = $('svcCount');
    if (count) {
      count.textContent = !all.length ? ''
        : rows.length === all.length ? all.length + ' services'
        : rows.length + ' of ' + all.length;
    }

    if (!all.length) {
      box.innerHTML = '<div class="softpanel"><div class="emptyline">' +
        '<b>The rate card is empty.</b>' +
        (maySvc() ? '<button class="btn btn-sm" data-a="first" type="button">Add the first service</button>' : '') +
        '</div></div>';
      var first = box.querySelector('[data-a="first"]');
      if (first) first.addEventListener('click', function () { openSvc(null); });
      return;
    }
    if (!rows.length) {
      box.innerHTML = '<div class="softpanel"><div class="emptyline">' +
        '<b>No matches.</b><button class="btn btn-sm" data-a="clear" type="button">Clear the filters</button>' +
        '</div></div>';
      box.querySelector('[data-a="clear"]').addEventListener('click', clearSvcFilters);
      return;
    }

    /* A card per category under its own heading, the shape every directory
       in this console takes, in the order the card sells them: what is sold
       first, then what is added to it. It was two cards with the categories
       as uppercase divider rows inside them; the user asked for a card per
       category on 2026-09-22, as the Register and the Clients list draw.
       A filter opens every card. */
    var GRP = window.ADspaceGroup;
    var filtered = rows.length !== all.length;
    var seen = {};
    svcTiers(all).forEach(function (t) {
      t[1].forEach(function (k) {
        if (seen[k]) return;
        seen[k] = true;
        var lines = rows.filter(function (s) { return s.category === k; });
        if (!lines.length) return;
        var key = String(k).toLowerCase().replace(/[^a-z0-9]+/g, '-');
        box.appendChild(GRP.section({
          route: 'services', key: key, name: k, count: lines.length,
          shut: !filtered && GRP.shut('services', key, false),
          table: function () {
            /* One heading over the amount and the unit: the unit qualifies
               the price ("RM 360.00  Per post"), so two headings over what
               reads as one value said Rate and Unit where a person reads a
               price. The cells stay two tracks so every amount keeps the
               same right edge. */
            var table = GRP.table('svc-row cat-row',
              ['Service', { text: 'Price', cls: 'svc-rate' }, { text: '', cls: 'svc-unit' }, '']);
            lines.forEach(function (s) { table.appendChild(catalogRow(s)); });
            return table;
          }
        }));
      });
    });
  }

  /* Review n changes (2026-10-22, SVC2-M1): only the lines the draft
     changed, each naming what moved from and to, then the lines removed and
     the blocks of wording changed, under one line with the way back. */
  function paintReview(box, all) {
    var d = diffNow, GRP = window.ADspaceGroup;
    var note = document.createElement('p');
    note.className = 'msg svc-review-note';
    note.innerHTML = 'Showing the ' + d.n + ' change' + (d.n === 1 ? '' : 's') + ' not published. ' +
      '<button class="linkbtn" type="button" data-a="whole">Show the whole card</button>';
    box.appendChild(note);
    note.querySelector('[data-a="whole"]').addEventListener('click', function () { reviewCard(false); });
    var seen = {};
    svcTiers(all).forEach(function (t) {
      t[1].forEach(function (k) {
        if (seen[k]) return;
        seen[k] = true;
        var lines = all.filter(function (s) { return s.category === k && d.lines[s.slug]; });
        if (!lines.length) return;
        box.appendChild(GRP.section({
          route: 'services', key: 'review-' + String(k).toLowerCase().replace(/[^a-z0-9]+/g, '-'), name: k, count: lines.length, shut: false,
          table: function () {
            var table = GRP.table('svc-row cat-row', ['Service', { text: 'Price', cls: 'svc-rate' }, { text: '', cls: 'svc-unit' }, '']);
            lines.forEach(function (s) {
              var row = catalogRow(s);
              var moved = d.lines[s.slug] === 'Changed' ? svcMoved(d.was[s.slug] || {}, s) : '';
              if (moved) row.querySelector('.svc-name').insertAdjacentHTML('beforeend', '<small class="svc-moved">' + esc(moved) + '</small>');
              table.appendChild(row);
            });
            return table;
          }
        }));
      });
    });
    if (d.gone) {
      var gone = document.createElement('div');
      gone.className = 'softpanel';
      gone.innerHTML = '<div class="emptyline"><b>' + d.gone + ' line' + (d.gone === 1 ? '' : 's') + ' removed</b>' +
        '<span class="muted">' + esc(d.goneNames.join(', ')) + '</span></div>';
      box.appendChild(gone);
    }
    var blocks = (svcText || []).filter(function (b) { return d.words[b.key]; });
    if (blocks.length) {
      box.appendChild(GRP.section({
        route: 'services', key: 'review-words', name: 'Wording', count: blocks.length, shut: false,
        table: function () {
          var table = GRP.table('svc-row cat-row rcw-row', ['Wording', '']);
          blocks.forEach(function (b) { table.appendChild(wordRow(b, d)); });
          return table;
        }
      }));
    }
  }

  function clearSvcFilters() {
    svcFind = '';
    if ($('svcFind')) $('svcFind').value = '';
    paintCatalog();
  }

  if ($('svcFind')) $('svcFind').addEventListener('input', function () {
    svcFind = this.value.trim().toLowerCase();
    paintCatalog();
  });
  function catalogRow(s) {
    var row = document.createElement('div');
    row.className = 'svc-row' + (s.active === false ? ' is-off' : '');
    var off = s.active === false;
    /* Nearly every line on the card is active, so a green Active on every row
       spent the one accent on the ordinary case and buried the price under a
       control taller than it. The row is the name and what it costs; Inactive
       is the exception, so that is what gets named. */
    row.setAttribute('data-slug', s.slug);
    /* A line of parts wraps between its parts, never inside one: a count
       keeps its word (2026-10-20, SVC-3). */
    var nameWords = esc(s.name).replace(/(\d[\d,.]*) (?=\S)/g, '$1\u00a0');
    row.innerHTML =
      '<span class="svc-name"><b>' + nameWords + (off ? ' <span class="tone is-off">Inactive</span>' : '') +
        (diffNow.lines[s.slug] ? ' <span class="chip">' + diffNow.lines[s.slug] + '</span>' : '') + '</b>' +
        /* The Bukku item code under the name, in the token face, as a
           client's ID sits under theirs (2026-10-15). */
        (s.sku ? '<small class="svc-sku">' + esc(s.sku) + '</small>' : '') +
        (s.note ? '<small>' + esc(s.note) + '</small>' : '') + '</span>' +
      /* The price is changed where it is read (ux-audit SVC-1): for whoever
         keeps the card it is the control, as My Work's due date is. */
      '<span class="svc-rate">' + (maySvc()
        ? '<button class="tinline svc-rate-edit" type="button" data-a="rate" aria-label="Change the rate of ' + esc(s.name) + '">' + rateWord(s) + '</button>'
        : rateWord(s)) + '</span>' +
      '<span class="svc-unit">' + esc(s.unit || '') + '</span>' +
      '<span class="team-act">' + (maySvc()
        ? '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
          '<div class="kmenu" data-menu hidden>' +
            '<button class="kmenu-item" data-g="2" data-a="edit" type="button" role="menuitem">Edit</button>' +
            // Taking a line off the card is a decision of the year, not a select.
            '<button class="kmenu-item" data-g="5" data-a="state" type="button" role="menuitem">' +
              (off ? 'Set active' : 'Set inactive') + '</button>' +
            /* Inactive first, then gone, as it is for a letter and a contact:
               a line is taken off the card before it can be taken out of it.
               Drawn only where Services is managed. */
            (off ? '<button class="kmenu-item is-danger" data-g="6" data-a="del" data-need="services:manage" type="button" role="menuitem">Delete</button>' : '') +
          '</div>'
        : '') + '</span>';
    row.classList.add('cat-row');
    if (maySvc()) {
      wireMenu(row);
      row.querySelector('[data-a="edit"]').addEventListener('click', function () { openSvc(s); });
      var rb = row.querySelector('[data-a="rate"]');
      rb.addEventListener('click', function () { rateInPlace(s, rb); });
      var del = row.querySelector('[data-a="del"]');
      if (del) del.addEventListener('click', function () { purgeSvc(s); });
      row.querySelector('[data-a="state"]').addEventListener('click', function () {
        Array.prototype.forEach.call(document.querySelectorAll('.kmenu'), function (m) { m.hidden = true; });
        patchSvc(s, { active: off }, off ? 'service.on' : 'service.off');
      });
    }
    return row;
  }
  function rateWord(s) {
    return s.rate != null ? esc(MON.money2(s.rate, 'MY')) : '<span class="muted">On quote</span>';
  }
  /* The figure becomes its field where it stands and a tick beside it saves
     it (js/ask.js); empty is On quote. The draft takes it, so the line reads
     Changed until the card is published again, as the sheet's Save does. */
  function rateInPlace(s, host) {
    var tick = document.createElement('button');
    tick.type = 'button';
    tick.className = 'tl-pen svc-rate-tick';
    host.parentNode.insertBefore(tick, host.nextSibling);
    window.ADspaceAsk.rename(host, tick, {
      type: 'number',
      value: s.rate == null ? '' : String(s.rate),
      allowEmpty: true,
      label: 'Rate of ' + s.name,
      saveLabel: 'Save the rate',
      onClose: function () { tick.remove(); },
      save: function (v) {
        var rate = v === '' ? null : Number(v);
        if (rate !== null && !(isFinite(rate) && rate >= 0)) { msg('svcListMsg', 'Enter the rate as an amount in RM.', 'err'); return; }
        if (rate === (s.rate == null ? null : Number(s.rate))) return;
        db.from('services').update({ rate: rate }).eq('slug', s.slug).select('slug').then(function (r) {
          if (r.error) { msg('svcListMsg', r.error.message, 'err'); return; }
          if (!(r.data || []).length) { msg('svcListMsg', 'Not saved. The database refused the request.', 'err'); return; }
          log('service.changed', s.name, changed({ rate: s.rate }, { rate: rate }, [['rate', 'Rate']]));
          /* Repainted from the row as written, never read again: nothing
             moves but the figure and its Changed tag. */
          s.rate = rate;
          paintServicesPage();
          /* Said on the row it changed, in sight (2026-10-20, SVC-2). */
          var at = document.querySelector('#svcList .svc-row[data-slug="' + (window.CSS && CSS.escape ? CSS.escape(s.slug) : s.slug) + '"] .svc-name');
          if (at) { var said = document.createElement('small'); said.className = 'msg ok svc-said'; said.setAttribute('role', 'status'); said.textContent = 'Saved.'; at.appendChild(said); }
          else msg('svcListMsg', 'Saved.', 'ok');
        }).catch(function () { msg('svcListMsg', 'Not saved. Please try again.', 'err'); });
      }
    });
  }
  /* A rate card line a client is on stays, because the card is what a person
     picks from and a line that vanishes mid-quote is a line somebody has to
     find again. A client's own service line keeps its own label and rate, so
     removing the card row costs a confirmed engagement nothing; what it costs
     is the next quote, which is why the count is the answer rather than the
     force. */
  function purgeSvc(s) {
    Array.prototype.forEach.call(document.querySelectorAll('.kmenu'), function (m) { m.hidden = true; });

    db.from('client_services').select('id').eq('service_slug', s.slug).is('archived_at', null).then(function (q) {
      if (q.error) { msg('svcListMsg', q.error.message, 'err'); return; }
      purgeAsk(s, q);
    }).catch(function () { msg('svcListMsg', 'Not deleted. Please try again.', 'err'); });
  }
  function purgeAsk(s, q) {
    var n = (q.data || []).length;
    if (n) {
      msg('svcListMsg', s.name + ' is on ' + n + ' client service line' + (n === 1 ? '' : 's') +
          '. Remove those lines first.', 'warn');
      return;
    }
    /* A line the live version still offers is quoted from until the next
       version goes live without it. */
    var liveRow = live && (live.snapshot.services || []).filter(function (x) { return x.slug === s.slug; })[0];
    if (liveRow && liveRow.active !== false) {
      msg('svcListMsg', s.name + ' is offered by the live version. Publish the rate card with it inactive first.', 'warn');
      return;
    }
    window.ADspaceConfirm.ask({
      title: 'Delete',
      body: s.name + ' leaves the rate card and cannot be quoted again. There is '
          + 'no restore. Letters already issued keep the line as it was written.',
      go: 'Delete',
      tone: 'danger',
      field: { label: 'Type the service name to confirm', placeholder: s.name, match: s.name, need: 'Type the service name to confirm.', mismatch: 'The service name does not match.' }
    }, function () {
      db.from('services').delete().eq('slug', s.slug).select('slug').then(function (r) {
        if (r.error) { msg('svcListMsg', r.error.message, 'err'); return; }
        if (!(r.data || []).length) { msg('svcListMsg', 'Not deleted. The database refused the request.', 'err'); return; }
        log('service.deleted', s.name, s.category || '');
        /* Taken off the list as read, never the whole page read again
           (2026-10-22, SVC2-7). */
        catalog = (catalog || []).filter(function (x) { return x.slug !== s.slug; });
        paintServicesPage();
        msg('svcListMsg', 'Deleted.', 'ok');
      }).catch(function () { msg('svcListMsg', 'Not deleted. Please try again.', 'err'); });
    });
  }
  /* A line set inactive or active is changed where it stands, the list
     repainted from the row as written (2026-10-22, SVC2-7). */
  function patchSvc(s, patch, action) {
    db.from('services').update(patch).eq('slug', s.slug).select('slug').then(function (r) {
      if (r.error) { msg('svcListMsg', r.error.message, 'err'); return; }
      if (!(r.data || []).length) { msg('svcListMsg', 'Not saved. The database refused the request.', 'err'); return; }
      log(action, s.name, '');
      Object.keys(patch).forEach(function (k) { s[k] = patch[k]; });
      paintServicesPage();
    }).catch(function () { msg('svcListMsg', 'Not saved. Please try again.', 'err'); });
  }
  function openSvc(s) {
    /* The row's ⋯ shuts before the sheet opens over it (SVC2-2). */
    Array.prototype.forEach.call(document.querySelectorAll('.kmenu'), function (m) { m.hidden = true; });
    editingSvc = s || null;
    $('svcCat').innerHTML = CATS.map(function (k) { return '<option value="' + esc(k) + '">' + esc(k) + '</option>'; }).join('');
    $('svcTitle').textContent = s ? 'Edit service' : 'New service';
    $('svcCat').value = s ? s.category : CATS[0];
    $('svcName').value = s ? s.name : '';
    $('svcSku').value = s ? (s.sku || '') : '';
    $('svcRate').value = s && s.rate != null ? Number(s.rate) : '';
    $('svcUnit').value = s ? (s.unit || '') : '';
    $('svcMin').value = s ? Math.max(1, Number(s.min_months || 1)) : 1;
    $('svcDetail').value = s ? (s.detail || '') : '';
    fillSpec(s ? s.spec : null);
    msg('svcMsg', '');
    /* Nothing is focused when the sheet opens: on a phone a field taking
       focus raises the keyboard and zooms the page past the rest of the
       form, and the first field is rarely the one somebody came to change. */
    openSheet('svcBox');
  }
  $('svcAdd').addEventListener('click', function () { openSvc(null); });
  $('svcCardPdf').addEventListener('click', function () { cardPdf(this); });
  /* SST and the term percentages a quote is prefilled from, an admin's,
     from a day on (2026-10-05). Follow-up limits moved to the Settings
     page's Clients group (2026-10-11). */
  $('svcTax').addEventListener('click', function () {
    var taxSheet = window.ADspaceAdmin.SETTING_SHEETS.tax;
    window.ADspaceAdmin.editSettings({ title: taxSheet.title, msg: 'svcListMsg', keys: taxSheet.keys }, this);
  });
  $('svcCancel').addEventListener('click', function () { shutSheet('svcBox'); editingSvc = null; });
  $('svcSave').addEventListener('click', function () {
    var name = val('svcName');
    if (!name) { msg('svcMsg', 'A name is required.', 'err'); $('svcName').focus(); return; }
    /* The SKU is Bukku's item code as typed: letters, digits and . _ / -,
       one line each (services_sku_idx), optional. */
    var sku = val('svcSku');
    if (sku && !/^[A-Za-z0-9][A-Za-z0-9._\/-]{0,39}$/.test(sku)) {
      msg('svcMsg', 'Enter the SKU as letters, digits and . _ / - only.', 'err'); $('svcSku').focus(); return;
    }
    var sp = readSpec();
    if (sp.err) { msg('svcMsg', sp.err, 'err'); if ($(sp.at)) $(sp.at).focus(); return; }
    var row = { category: $('svcCat').value, name: name, sku: sku || null,
                rate: val('svcRate') === '' ? null : Number(val('svcRate')), unit: val('svcUnit') || null,
                min_months: Math.max(1, Number(val('svcMin') || 1)), detail: val('svcDetail') || null, spec: sp.spec };
    /* One press, one write: Save rests while it is out (2026-10-22,
       SVC2-1). A duplicate is named by what clashed: the SKU's own index,
       else the name the line's key is made from. */
    var go = $('svcSave');
    go.disabled = true;
    var after = function (r) {
      go.disabled = false;
      if (r.error) {
        var m = r.error.message || '';
        if (/services_sku_idx/i.test(m)) { msg('svcMsg', 'That SKU is already on another line.', 'err'); $('svcSku').focus(); return; }
        if (/duplicate key|services_pkey|23505/i.test(m) || r.error.code === '23505') {
          msg('svcMsg', 'A service with this name is already on the card.', 'err'); $('svcName').focus(); return;
        }
        msg('svcMsg', m || 'Not saved.', 'err');
        return;
      }
      if (!(r.data || []).length) { msg('svcMsg', 'Not saved. The database refused the request.', 'err'); return; }
      log(editingSvc ? 'service.changed' : 'service.added', name, editingSvc
        ? changed(Object.assign({}, editingSvc, { spec: specWord(editingSvc.spec) }), Object.assign({}, row, { spec: specWord(row.spec) }),
            [['category', 'Category'], ['name', 'Name'], ['sku', 'SKU'], ['rate', 'Rate'], ['unit', 'Unit'],
            ['min_months', 'Minimum months'], ['detail', 'Inclusions'], ['spec', 'In quotes']])
        : row.category);
      var was = editingSvc;
      shutSheet('svcBox'); editingSvc = null;
      /* An edit is repainted from the row as written; a new line reads the
         rate card again, nothing else (SVC2-7). */
      if (was) { Object.keys(row).forEach(function (k) { was[k] = row[k]; }); paintServicesPage(); return; }
      catalog = null;
      loadCatalog(function () { paintServicesPage(); });
    };
    var failed = function () { go.disabled = false; msg('svcMsg', 'Not saved. Please try again.', 'err'); };
    if (editingSvc) { db.from('services').update(row).eq('slug', editingSvc.slug).select('slug').then(after).catch(failed); return; }
    row.slug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || ('svc-' + Date.now());
    row.position = (catalog || []).length
      ? Math.max.apply(null, catalog.map(function (s) { return Number(s.position || 0); })) + 1 : 1;
    row.active = true;
    db.from('services').insert(row).select('slug').then(after).catch(failed);
  });

  // ---- Entry --------------------------------------------------------------
  fillSelect($('crmStage'), STAGES.map(function (s) { return [s[0], s[1]]; }), 'All stages');
  /* The lead's industry is a stored value, so its unset choice is empty and
     saves as null: the filter idiom's `all` here showed a blank select on a
     new lead and saved "all" as the industry when Not set was picked. */
  $('crmIndustry').innerHTML = '<option value="">Not set</option>' +
    INDUSTRIES.map(function (i) { return '<option value="' + esc(i) + '">' + esc(i) + '</option>'; }).join('');
  fillSelect($('crmSource'), SOURCES);
  /* Not fillSelect's "all" option: that is the filter idiom, and here the empty
     choice is a value that gets stored, so it is an empty string and saves as
     null like every other unset field. */
  $('crmCommence').innerHTML = '<option value="">Not set</option>' +
    COMMENCE.map(function (r) {
      return '<option value="' + esc(r[0]) + '">' + esc(r[1]) + '</option>';
    }).join('');

  window.ADspaceCRM = {
    sourceWord: sourceWord,
    urlState: function () {
      var o = { client: keyOf(state.client) };
      /* Overview is the default, so it stays out of the address: a link to a
         client is the client, not the client on its first pane. */
      if (o.client && pane && pane !== 'overview') o.tab = pane;
      return o;
    },
    byKey: clientByKey,
    keyOf: keyOf,
    /* The directory's own order and bands, for every other place a client
       is picked from, so a picker reads the way the Clients list does. */
    bands: GROUPS,
    bandOf: function (stage) { return stageWord(stage || 'lead')[3]; },
    enter: function () {
      var params = new URLSearchParams(location.search);
      var key = params.get('client');
      loadTeam();
      if (key && !(state.client && (state.client.slug === key || state.client.id === key))) {
        clientByKey(key, function (c) {
          /* A link to a client outside the colleague's reach (or gone) says
             so, rather than dropping to the list as if nothing was asked. */
          if (!c) {
            state.client = null; showList();
            $('crmListMsg').textContent = 'That client is outside your access, or no longer exists.';
            return;
          }
          openClient(c, true);
        });
        return;
      }
      if (state.client) { openClient(state.client, true); return; }
      showList();
    },
    // What the other sections may offer work to. They ask here rather than
    // keeping a list of their own.
    active: function (then) {
      readPages(function () { return db.from('clients').select(API.CLIENT_COLS).eq('stage', 'active').order('name').order('id'); })
        .then(function (r) { then(r.data || []); }, function () { then([]); });
    },
    // How long a stage may run before it reads Overdue (the Overview asks).
    staleH: staleH,
    isStale: isStale,
    // The rate card lives in this module because it is what a client's lines
    // are made of.
    enterServices: enterServices,
    svcState: svcState
  };

  function showList() {
    $('crmWork').hidden = true;
    $('crmListView').hidden = false;
    setUrl();
    loadClients(function () { loadDue(); restoreScroll(); });
  }

  /* Every open next action, across every client, soonest first. Overdue ones
     lead. Each line opens its client, and Done clears it from here without
     touching the log entry it came from. */
  /* Every open one is read and counted; the fifty soonest are drawn (the
     audit of 2026-10-26, finding 11: the count read 50 where more stood). */
  var DUE_SHOW = 50;
  function loadDue() {
    window.ADspaceAPI.readPages(function () {
      return db.from('client_touches').select('*').not('next_action', 'is', null)
        .is('done_at', null).is('archived_at', null)
        .order('next_at', { ascending: true, nullsFirst: false }).order('id');
    })
      .then(function (r) {
        var rows = (r.data || []).filter(function (t) { return t.next_action; });
        // Soonest first, undated last.
        rows.sort(function (a, b) {
          if (a.next_at && b.next_at) return a.next_at < b.next_at ? -1 : a.next_at > b.next_at ? 1 : 0;
          return a.next_at ? -1 : b.next_at ? 1 : 0;
        });
        state.due = rows;
        paintDue();
      }, function () { $('crmDue').hidden = true; });
  }

  /* Draws what loadDue read. The team list may answer after it, and then
     draws it again with each colleague's name; nothing is read again. */
  function paintDue() {
    var box = $('crmDueList'), rows = state.due || [];
    var byId = {};
    state.clients.forEach(function (c) { byId[c.id] = c; });
    $('crmDue').hidden = !rows.length;
    var over = rows.filter(function (t) { return t.next_at && t.next_at < today(); }).length;
    $('crmDueCount').textContent = rows.length + ' open' + (over ? ' · ' + over + ' overdue' : '');
    box.innerHTML = '';
    rows.slice(0, DUE_SHOW).forEach(function (t) {
      var c = byId[t.client_id];
      var due = t.next_at && t.next_at < today();
      var soon = !due && t.next_at && t.next_at <= ADspaceClock.addDays(today(), 6);
      var row = document.createElement('div');
      row.className = 'due-row' + (due ? ' is-due' : soon ? ' is-soon' : '');
      row.innerHTML =
        '<span class="due-when">' + esc(t.next_at ? niceDate(t.next_at) : 'No date') +
          (due ? '<em>overdue</em>' : soon ? '<em>this week</em>' : '') + '</span>' +
        '<button class="due-client" type="button">' + esc(c ? c.name : 'Client') + '</button>' +
        '<span class="due-what">' + esc(t.next_action) +
          (whoLogged(t.by_whom) ? '<small>' + esc(whoLogged(t.by_whom)) + '</small>' : '') + '</span>' +
        '<button class="btn btn-sm" data-a="done" type="button">Done</button>';
      row.querySelector('.due-client').addEventListener('click', function () { if (c) openClient(c); });
      row.querySelector('[data-a="done"]').addEventListener('click', function () {
        db.from('client_touches').update({ done_at: new Date().toISOString() }).eq('id', t.id).select('id')
          .then(function (r) {
            if (r.error || !(r.data || []).length) { loadDue(); return; }
            log('client.action_done', c ? c.name : '', t.next_action);
            undoBar('Marked done: ' + t.next_action, function () {
              db.from('client_touches').update({ done_at: null }).eq('id', t.id).select('id').then(function (u) {
                if (u.error || !(u.data || []).length) msg('crmListMsg', 'Not restored. The database refused the request.', 'warn');
                loadDue();
              }).catch(loadDue);
            });
            loadDue();
          });
      });
      box.appendChild(row);
    });
  }

  /* The close mark in each sheet's head presses that sheet's own Cancel, so
     there is one way back per form and not two that can drift. */
  sheetClose('crmAddClose', 'crmCancel');
  sheetClose('crmContactClose', 'ctCancel');
  sheetClose('crmServiceClose', 'svCancel');
  sheetClose('crmTouchClose', 'tcCancel');
  sheetClose('crmReplyClose', 'rqCancel');
  sheetClose('svcClose', 'svcCancel');

  if (bridge.crmReady) bridge.crmReady();
})();
