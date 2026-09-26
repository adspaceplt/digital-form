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
  /* The tabs that carry `data-part` draw only where that part is readable. */
  function gateTabs() {
    Array.prototype.forEach.call(document.querySelectorAll('#crmTabs [data-part]'), function (b) {
      b.hidden = !mayPart(b.getAttribute('data-part'), 'view');
    });
  }

  function esc(s) {
    return String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  }
  function msg(id, text, kind) {
    var el = $(id);
    if (!el) return;
    el.textContent = text || '';
    el.className = 'msg' + (kind ? ' ' + kind : '');
  }
  function token() {
    var a = new Uint8Array(16);
    (window.crypto || {}).getRandomValues ? window.crypto.getRandomValues(a)
      : a.forEach(function (_, i) { a[i] = Math.floor(Math.random() * 256); });
    return Array.from(a, function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
  }
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
  // A clash takes a number rather than failing; the database index is the
  // final word, so a race loses the insert and not the slug.
  function uniqueSlug(name, then) {
    var want = slugify(name) || 'client';
    db.from('clients').select('slug').ilike('slug', want + '%').then(function (r) {
      var used = {};
      (r.data || []).forEach(function (x) { if (x.slug) used[String(x.slug).toLowerCase()] = true; });
      if (!used[want]) { then(want); return; }
      for (var i = 2; i < 300; i++) { if (!used[want + '-' + i]) { then(want + '-' + i); return; } }
      then(want + '-' + Date.now().toString(36));
    }, function () { then(want); });
  }
  var UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  /* What the address carries: a slug now, a UUID in anything shared before
     this. Asked of the right column either way, because Postgres refuses a
     non-UUID against a uuid column. */
  function clientByKey(key, then) {
    if (!key) { then(null); return; }
    db.from('clients').select('*').eq(UUID.test(key) ? 'id' : 'slug', key).single()
      .then(function (r) { then(r.error ? null : (r.data || null)); }, function () { then(null); });
  }
  // The address of a client, wherever one is built.
  function keyOf(c) { return (c && (c.slug || c.id)) || ''; }
  function niceDate(d) {
    if (!d) return '';
    var dt = new Date(String(d).slice(0, 10) + 'T00:00:00');
    if (isNaN(dt.getTime())) return String(d);
    return dt.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
  }
  function today() { return new Date().toISOString().slice(0, 10); }

  /* Stage is the one word that tells the team how to treat someone. The list
     is grouped by it: leads being worked at the top, the clients we are
     serving below, and the ones that have ended at the bottom. */
  /* The word and the colour come from js/words.js, so a stage cannot read one
     way here and another on the client's page. What stays here is the only
     part the client page has no use for: which group of the list it falls in. */
  var W = window.ADspaceWords;
  var STAGES = [['lead', 'leads'], ['contacted', 'leads'], ['proposal', 'leads'],
                ['active', 'clients'], ['paused', 'clients'], ['past', 'past']]
    .map(function (g) { return [g[0], W.en.stage[g[0]], W.tone(g[0]), g[1]]; });
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
    db.from('clients').select('*').eq('id', c.id).single().then(function (r) {
      if (r && r.data) {
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
  function daysSince(iso) {
    if (!iso) return null;
    var t = Date.parse(iso);
    if (isNaN(t)) return null;
    return Math.max(0, Math.floor((Date.now() - t) / 86400000));
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
  var STALE_H = { lead: 48, proposal: 21 * 24 };
  function isStale(c) {
    var limit = STALE_H[(c && c.stage) || 'lead'];
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
        days: Math.max(0, Math.floor((next - at) / 86400000)),
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
  function billContact(c) {
    var list = state.contacts || [];
    return list.filter(function (x) { return x.id === c.bill_contact_id; })[0] ||
           list.filter(function (x) { return x.is_primary; })[0] || null;
  }
  function billingMissing(c) {
    return BILLING_REQUIRED.filter(function (f) {
      return f[1] === 'bill_contact_id' ? !billContact(c) : !String(c[f[1]] || '').trim();
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
    var names = team.map(function (m) { return m.name; });
    if (keep && names.indexOf(keep) < 0) names.push(keep);
    el.innerHTML = '<option value="">Unassigned</option>' +
      names.map(function (n) { return '<option value="' + esc(n) + '">' + esc(n) + '</option>'; }).join('');
    el.value = keep || '';
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
    db.from('team_members').select('*').eq('active', true).order('name').then(function (r) {
      state.team = (r.data) || [];
      peopleSelect($('crmOwnerPick'), state.team);
      fillSelect($('crmOwner'), state.team.map(function (m) { return [m.name, m.name]; }), 'Everyone');
      if (then) then();
    }, function () { if (then) then(); });
  }

  /* Loading, empty and failed are said one way across the console. */
  var UI = window.ADspaceState;
  var skeleton = UI.skeleton, failLine = UI.failLine;

  function loadClients(then) {
    var box = $('crmList');
    if (!state.clients.length) skeleton(box, 6);
    db.from('clients').select('*').order('name').then(function (r) {
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

  /* When somebody last spoke to each client. It is a column on the register
     because "who has gone quiet" is the second question anybody asks of this
     list, after "who is overdue". It reads `client_touches`, which the team
     already reads on every record, and adds no field, function or permission
     of its own; the list paints without it and fills the column in when it
     arrives, so a slow or refused read costs the list nothing. */
  function loadLastSeen() {
    db.from('client_touches').select('client_id, happened_at')
      .is('archived_at', null)
      .order('happened_at', { ascending: false })
      .then(function (r) {
        if (r.error || !r.data) return;
        var seen = {};
        r.data.forEach(function (t) {
          if (!t.client_id || !t.happened_at) return;
          if (!seen[t.client_id] || t.happened_at > seen[t.client_id]) seen[t.client_id] = t.happened_at;
        });
        state.lastSeen = seen;
        if (!$('crmListView').hidden) paintList();
      }, function () {});
  }

  function visible() {
    var q = val('crmSearch').toLowerCase();
    var stage = $('crmStage').value;
    var owner = $('crmOwner').value;
    return state.clients.filter(function (c) {
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
    var rows = visible().sort(byCode);
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
        UI.emptyLine(box, 'No clients yet.', 'Add the first lead', function () { $('crmNew').click(); });
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
          var table = GRP.table('client-row',
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
    return late ? '<span class="tone is-warn crm-band-late">' + late + ' overdue</span>' : '';
  }

  /* A column per fact, because that is what every CRM anyone here has used
     looks like, and because the eye scans a column far faster than it scans
     a chip stranded at the other end of a wide row. */
  function listRow(c) {
    var w = stageWord(c.stage || 'lead');
    var row = document.createElement('button');
    row.type = 'button';
    row.className = 'crm-row client-row';
    row.innerHTML =
      /* The number the accounting system issued, under the name it belongs to
         rather than in a column of its own: a seventh column costs the name
         its width on every row for a value that is only read when somebody is
         holding an invoice, and the phone template has nowhere to put it. Set
         the way this portal sets every other token. */
      '<span class="crm-c crm-c-name">' + esc(c.name || '') +
        (c.client_code ? '<small class="crm-c-code">' + esc(c.client_code) + '</small>' : '') +
      '</span>' +
      '<span class="crm-c crm-c-stage"><span class="tone ' + w[2] + '">' + esc(w[1]) + '</span>' +
        /* The word carries it, not the colour: the mark has to survive a
           greyscale print and a reader who cannot tell warn from mute. */
        (ageWord(c) ? '<small class="crm-age' + (isStale(c) ? ' is-late' : '') + '">' +
          esc(ageWord(c) + (isStale(c) ? ' · Overdue' : '')) + '</small>' : '') + '</span>' +
      '<span class="crm-c crm-c-ind">' + esc(c.industry || '—') + '</span>' +
      '<span class="crm-c crm-c-own">' + esc(c.owner || 'Unassigned') + '</span>' +
      /* When somebody last spoke to them. Where nobody has, the cell takes the
         same mute mark the Industry cell beside it already uses for a value
         nobody has filled in: "No calls yet" written out on every row of a
         list where almost nobody has been called yet is a sentence repeated
         seven times where one character says it, and the column heading has
         already said what the cell is. */
      '<span class="crm-c crm-c-seen">' + (lastSeenWord(c)
        ? esc(lastSeenWord(c)) : '<span class="muted">—</span>') + '</span>' +
      /* The one line the phone gets, so it carries the value rather than the
         currency it would be in. A bare RM with no amount is a fragment that
         reads like a broken field, and it was shown even where the client had
         a figure: the desktop column had the money and the phone line threw it
         away for its sign. What is not known is left out rather than stood in
         for, so the line is two or three facts, never a row of placeholders. */
      '<span class="crm-c crm-c-meta">' +
        [c.industry, c.owner, lastSeenWord(c)].filter(Boolean).map(esc).join(' · ') +
      '</span>' +
      /* The mark that says the row goes somewhere, in the column the header
         leaves empty. The row is one button, so the whole of it opens the
         client from a pointer and from the keyboard alike, and there is no
         control nested inside another control to trip a screen reader. */
      '<svg class="crm-c crm-c-go" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
        'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
        '<path d="M9 18l6-6-6-6"/></svg>';
    row.addEventListener('click', function () { openClient(c); });
    return row;
  }

  /* "12 Sept", or "Sept 2026" once the exact day has stopped mattering — the
     same units the stage clock already talks in. */
  function lastSeenWord(c) {
    var iso = (state.lastSeen || {})[c.id];
    if (!iso) return '';
    var d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    var days = Math.floor((Date.now() - d.getTime()) / 86400000);
    return d.toLocaleDateString('en-GB', days < 300
      ? { day: 'numeric', month: 'short' }
      : { month: 'short', year: 'numeric' });
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
    onFilter();
  }
  function onFilter() {
    var key = JSON.stringify([val('crmSearch'), $('crmStage').value, $('crmOwner').value]);
    if (key === filterKey) return;
    filterKey = key;
    paintList();
  }
  ['crmSearch', 'crmStage', 'crmOwner'].forEach(function (id) {
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
    peopleSelect($('crmOwnerPick'), state.team, c ? (c.owner || '') : '');
    if (!c) $('crmSource').value = 'referral';
    $('crmMarket').value = c ? (c.market || 'MY') : 'MY';
    // The person who asked, and what for. Only a new lead needs this here.
    $('crmLeadOnly').hidden = Boolean(c);
    ['crmContactName', 'crmContactPhone', 'crmContactWa', 'crmContactEmail'].forEach(function (id) { $(id).value = ''; });
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
    if (!state.editing && waUser(val('crmContactWa')) && !waUserOk(waUser(val('crmContactWa')))) {
      msg('crmMsg', 'A WhatsApp username uses letters, numbers, full stops and underscores.', 'err');
      $('crmContactWa').focus(); return;
    }
    patch.deal_note = val('crmEnquiry') || null;
    if (!state.editing) patch.stage = 'lead';

    if (state.editing) {
      var id = state.editing.id;
      db.from('clients').update(patch).eq('id', id).then(function (r) {
        if (r.error) { msg('crmMsg', saveWord(r.error.message), 'err'); return; }
        log('client.edited', name, '');
        shutForm();
        loadClients(function () {
          var found = state.clients.filter(function (x) { return x.id === id; })[0];
          if (found) openClient(found);
        });
      });
      return;
    }
    // Every client carries its own review link from the moment it exists, so
    // Content Review has nothing left to create.
    patch.access_token = token();
    uniqueSlug(name, function (slug) {
    patch.slug = slug;
    db.from('clients').insert(patch).select().single().then(function (r) {
      if (r.error) { msg('crmMsg', r.error.message, 'err'); return; }
      log('client.added', name, sourceWord(patch.source) + (contactName ? ' · ' + contactName : ''));
      var open = function () { shutForm(); loadClients(function () { openClient(r.data); }); };
      var phone = val('crmContactPhone'), waU = waUser(val('crmContactWa'));
      db.from('client_contacts').insert({
        client_id: r.data.id, name: contactName, phone: phone || null,
        whatsapp: waU ? '@' + waU : (phone || null),
        email: val('crmContactEmail') || null, lang: 'en', is_primary: true
      }).then(open, open);
    });
    });
  });

  // ---- One client ---------------------------------------------------------
  function openClient(c, restoring) {
    /* Re-opening the same record is a repaint, not a navigation: logging a
       call moves the stage, which reads the client back, and that used to
       throw somebody out of the pane they were working in. */
    var same = Boolean(state.client && state.client.id === c.id);
    if (!same) { state.contacts = []; state.log = []; }
    state.client = c;
    /* The list was read once; Content Review's settings edit the same
       handles and logo, so a record opened from the list is read again and
       repainted where the row has moved on (2026-09-26). */
    if (!same) {
      db.from('clients').select('*').eq('id', c.id).single().then(function (r) {
        if (!r || r.error || !r.data || state.client !== c) return;
        var moved = Object.keys(r.data).some(function (k) {
          return JSON.stringify(r.data[k]) !== JSON.stringify(c[k]);
        });
        if (!moved) return;
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
      return '<option value="' + s[0] + '"' + (s[0] === (c.stage || 'lead') ? ' selected' : '') + '>' + esc(s[1]) + '</option>';
    }).join('');
    sel.className = 'select select-sm state-select ' + (w[2] || '');
    /* There is no Account status block: the stage select in the head says
       where the record stands and the Timeline says for how long, with the
       overdue mark on the stage that is running. A rail block repeating the
       head's own control was the same fact twice. */

    paintIdentity(c);

    var mk = MON.market(c.market);
    /* Person in charge has moved to the identity line and Added to Key dates,
       so neither is stated twice: a rail that repeats the head is a rail
       nobody reads. */
    $('crmFacts').innerHTML = [
      ['Client ID', c.client_code || '<span class="muted">Not set</span>'],
      ['Source',   c.source ? sourceWord(c.source) : '<span class="muted">Not set</span>'],
      ['Industry', c.industry || '<span class="muted">Not set</span>'],
      ['Market',   (c.market === 'SG' ? 'Singapore' : 'Malaysia') + ' · ' + mk.sign],
      ['Value',    c.deal_value ? MON.money(c.deal_value, c.market) : '<span class="muted">Not set</span>'],
      ['To commence', c.commence ? commenceWord(c.commence) : '<span class="muted">Not set</span>']
    ].filter(function (f) { return f[1] !== ''; }).map(function (f) {
      return '<div><dt>' + f[0] + '</dt><dd>' +
        (String(f[1]).indexOf('<span') === 0 ? f[1] : esc(f[1])) + '</dd></div>';
    }).join('');

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
    loadWork();
    showPane(restoring ? paneFromUrl() : (same ? pane : 'overview'));
    setUrl();
    if (restoring) restoreScroll();
  }

  /* ---- The record's own panes ------------------------------------------
     Seven sections in one column meant Documents was a scroll away from the
     services it quotes and Billing was a scroll away from the contact it
     names. The pane is in the address, so a refresh, a pasted link, Back and
     Forward all land on the section somebody was working in. */
  var PANES = ['overview', 'contacts', 'billing', 'brand', 'services', 'documents', 'reports', 'activity'];
  var pane = 'overview';

  function paneFromUrl() {
    var t = new URLSearchParams(location.search).get('tab') || '';
    return PANES.indexOf(t) >= 0 || t === 'work' ? t : 'overview';
  }

  function showPane(key) {
    /* A client's months, meetings and tasks moved to My Work's Clients view
       (2026-09-25), so an older link to this record's Work pane lands there. */
    if (key === 'work' && state.client && bridge.show) {
      history.replaceState(null, '', '/admin/?s=work&view=clients&wc=' +
        encodeURIComponent(state.client.slug || state.client.id));
      bridge.show('work');
      return;
    }
    if (PANES.indexOf(key) < 0) key = 'overview';
    if (key === 'activity' && !maySeeActivity()) key = 'overview';
    var tabOf = document.querySelector('#crmTabs .tab[data-pane="' + key + '"]');
    if (tabOf && tabOf.hasAttribute('data-part') && !mayPart(tabOf.getAttribute('data-part'), 'view')) key = 'overview';
    pane = key;
    Array.prototype.forEach.call(document.querySelectorAll('#crmTabs .tab'), function (b) {
      var on = b.getAttribute('data-pane') === key;
      b.classList.toggle('is-on', on);
      b.setAttribute('aria-selected', String(on));
    });
    Array.prototype.forEach.call(document.querySelectorAll('.rec-pane'), function (el) {
      el.hidden = el.getAttribute('data-pane') !== key;
    });
    if (key === 'activity' && !(state.log || []).length) loadClientLog();
    if (key === 'overview') paintSummary();
    /* The client's finished reports, drawn by the report script: the reports
       are prepared in the Reports section, and this tab lists what came out
       of it, the way Documents lists the letters. */
    if (key === 'reports' && window.ADspaceReports) {
      window.ADspaceReports.clientPane($('crmReportsPane'), state.client);
    }
  }

  gateTabs();
  Array.prototype.forEach.call(document.querySelectorAll('#crmTabs .tab'), function (b) {
    if (b.hasAttribute('data-needs-activity')) b.hidden = !maySeeActivity();
    b.addEventListener('click', function () {
      if (b.getAttribute('data-pane') === pane) return;
      showPane(b.getAttribute('data-pane'));
      pushUrl();
    });
  });
  /* Back and Forward move between panes, because the pane is in the address
     and the address is what the browser remembers. */
  window.addEventListener('popstate', function () {
    if ($('crmWork').hidden) return;
    showPane(paneFromUrl());
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
        if (!rows.length) { box.innerHTML = '<div class="empty">No entries.</div>'; return; }
        var t = document.createElement('div');
        t.className = 'crm-table softpanel';
        t.className += ' activity-list';
        t.innerHTML = '<div class="crm-head svc-row log-row"><span>When</span><span>Activity</span>' +
          '<span>By</span></div>';
        rows.forEach(function (x) {
          var el = document.createElement('div');
          el.className = 'svc-row log-row';
          var actor = x.actor || '';
          /* Main resolves stored emails to team display names with whoName().
             Keep that resolution when present, while older deployments still
             have a safe actor/System fallback. */
          var actorLabel = typeof whoName === 'function' ? whoName(actor) : actor;
          el.innerHTML =
            '<time class="log-when" datetime="' + esc(x.created_at || '') + '">' + esc(activityStamp(x.created_at)) + '</time>' +
            '<span class="log-event"><b class="log-what">' + esc(logWord(x.action)) + '</b>' +
              (x.detail ? '<span class="log-detail">' + esc(x.detail) + '</span>' : '') + '</span>' +
            '<span class="log-who"><span class="log-person">' +
              esc(actorLabel || 'System') + '</span></span>';
          t.appendChild(el);
        });
        box.innerHTML = '';
        box.appendChild(t);
      });
  }

  /* The console already names every action in one place; this reads it rather
     than keeping a second list that would drift from the first. */
  function logWord(action) {
    var A = window.ADspaceAdmin && window.ADspaceAdmin.actionLabel;
    var hit = A && A[action];
    return (hit && hit[0]) || String(action || '').replace(/[._]/g, ' ');
  }
  function activityStamp(iso) {
    var d = new Date(iso);
    return isNaN(d.getTime()) ? '' : niceDate(iso) + ' · ' +
      d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
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
    }
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

    box.innerHTML = '<div class="ovcard">' + [
      ovContact(c), ovServices(c), ovDocuments(c), ovTouches()
    ].join('') + '</div>';

    wireGo(box);
    paintRail(c);
  }

  /* One handler for every control that opens a pane, in the Overview and in
     the rail alike, so the address follows wherever somebody entered. */
  function wireGo(box) {
    Array.prototype.forEach.call(box.querySelectorAll('[data-go]'), function (b) {
      b.addEventListener('click', function () {
        showPane(b.getAttribute('data-go'));
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
  /* A call's glyph is its kind; a recorded event's is the section it belongs
     to, which is what the activity record already files it under. */
  var KIND_ICON = { call: 'phone', visit: 'pin', meeting: 'person', whatsapp: 'chat', email: 'mail', note: 'chat' };
  /* Every section the Activity record files a row under, or the row falls to
     the bare dot: `register` (Documents) and `ops` (My Work) were missing, so
     a letter issued against this client drew a hollow circle in the rail. */
  var SECTION_ICON = { clients: 'person', team: 'person', review: 'image', campaigns: 'speaker',
                       links: 'link', services: 'tag', register: 'file', ops: 'calendar' };
  function logIcon(action) {
    /* The tags are `document.*` and `register.*`; `/^doc\./` matched neither,
       so the one family with an obvious glyph never got it. */
    if (/^document\.|^register\./.test(action || '')) return 'file';
    var A = window.ADspaceAdmin && window.ADspaceAdmin.actionLabel;
    var hit = A && A[action];
    return SECTION_ICON[hit && hit[2]] || 'dot';
  }

  /* A section is a heading and the one control that opens what it summarises,
     which is this portal's section head drawn flat rather than as a card. An
     Edit carries the pen and no chevron; a View all carries the chevron. */
  function ovSection(title, go, goWord, body, isEdit) {
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
      return ovSection('Contact details', 'contacts', 'Edit', ovNone('No contacts yet.'), true);
    }
    var m = list.filter(function (x) { return x.is_primary; })[0] || list[0];
    var rows = [['Main contact', '<b>' + esc(m.name || '') + '</b>' +
      (m.role ? '<span class="ovmeta">' + esc(m.role) + '</span>' : '')]];
    var mUser = waHandle(m.whatsapp);
    if (m.phone) {
      /* A button, not a word run against the number with nothing between them:
         it is a thing to press and it is the same `.plink` the contact row
         and the client's own page already draw. */
      rows.push(['Phone', '<span class="ovreach">' + esc(m.phone) +
        (mUser ? '' : waLink(m.whatsapp || m.phone, (state.client || {}).market)) + '</span>']);
    }
    if (mUser) {
      rows.push(['WhatsApp', '<span class="ovreach">@' + esc(mUser) +
        waLink(m.whatsapp, (state.client || {}).market) + '</span>']);
    }
    if (m.email) rows.push(['Email', '<a class="ovlink" href="mailto:' + esc(m.email) + '">' + esc(m.email) + '</a>']);
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
        ovNone(all.length ? all.length + (all.length === 1 ? ' line enquired, nothing quoted yet.' : ' lines enquired, nothing quoted yet.')
                          : 'Nothing quoted or confirmed.'));
    }
    var body = '<div class="ovtable">' +
      '<div class="ovhead ovrow-svc"><span>Service</span><span>Details</span><span>Amount</span><span>State</span></div>' +
      rows.slice(0, 5).map(function (l) {
        var st = SV_STATE[l.state] || ['', ''];
        return '<div class="ovrow ovrow-svc">' +
          '<span class="ovname">' + esc(l.label || '') + '</span>' +
          '<span class="ovdim">' + esc(termWord(l) || '') + '</span>' +
          '<span class="ovamt">' + esc(MON.money2(amountOf(l), c.market)) + '</span>' +
          '<span><span class="tone ' + esc(st[1] || '') + '">' + esc(st[0] || l.state) + '</span></span>' +
        '</div>';
      }).join('') +
      (rows.length > 5 ? '<p class="ovmore">' + (rows.length - 5) + ' more</p>' : '') +
      '</div>';
    return ovSection('Services', 'services', 'Manage services', body);
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
          '<span>' + (d.voided_at ? '<span class="tone">Void</span>' : '<span class="tone is-ok">Issued</span>') + '</span>' +
        '</div>';
      }).join('') +
      (rows.length > 4 ? '<p class="ovmore">' + (rows.length - 4) + ' more</p>' : '') +
      '</div>';
    return ovSection('Letters', 'documents', 'View all', body);
  }

  function ovTouches() {
    var rows = state.touches || [];
    if (!rows.length) return ovSection('Calls and visits', 'activity', 'View all', ovNone('Nothing logged.'));
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
    return ovSection('Calls and visits', 'activity', 'View all', body);
  }

  /* ---- The rail ---------------------------------------------------------
     What is true whichever pane is open. Every block leaves entirely when the
     data behind it is not there, so nothing on it is a placeholder. */
  function paintRail(c) {
    railNext(c);
    railDone(c);
    railDates(c);
    railLog();
    wireGo($('crmNextBlock'));
    wireGo($('crmDoneBlock'));
    /* The rule under a block belongs to the last block actually drawn.
       `:last-child` counts a hidden sibling, and every block here leaves when
       the data behind it is not there. */
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
      box.innerHTML = '<button class="railnext" type="button" data-go="activity">' + ico('calendar') +
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
    if (stage === 'lead') return { text: 'No call or visit logged.', go: 'activity', icon: 'phone' };
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
      '<span class="railbar"><span class="railbar-fill" style="width:' + pct + '%"></span></span>' +
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
    var nextAt = live.filter(function (t) { return t.next_action && !t.done_at && t.next_at; })
      .map(function (t) { return t.next_at; }).sort()[0];

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
    var trip = journeyOf(c).map(function (s) {
      var span = s.days === 0 ? (s.now ? 'Today' : 'Same day') : spanWord(s.days);
      var over = s.now && isStale(c);
      return '<div class="tl-row tl-stage' + (s.now ? ' is-now' : '') + '">' +
        '<span class="tl-lead"><span class="tl-what">' + esc(s.word) + '</span>' +
          '<span class="tl-when" data-stage-val="' + s.i + '">' + esc(niceDate(s.at)) + '</span></span>' +
        '<span class="tl-end"><span class="tl-span' + (over ? ' is-late' : '') + '">' +
          esc(span + (s.now && s.days > 0 ? ' so far' : '') + (over ? ' · Overdue' : '')) + '</span>' +
          '<button class="tl-pen" type="button" data-stage-pen="' + s.i + '" aria-label="Edit the ' + esc(s.word) + ' date">' + PEN + '</button>' +
        '</span></div>';
    }).join('');

    var dates = [
      ['Client since', c.created_at, true],
      ['Last contact', last, false],
      ['Next follow up', nextAt, false]
    ].filter(function (r) { return r[1]; }).map(function (r) {
      var late = r[0] === 'Next follow up' && r[1] < today();
      /* Client since is the one date here a person may correct, so the value
         itself is what opens: a field growing out of the thing it changes,
         never a second field and a Save button below the list. */
      return '<div class="tl-row tl-date">' +
        '<span class="tl-lead"><span class="tl-what">' + esc(r[0]) + '</span>' +
          '<span class="tl-when' + (late ? ' is-late' : '') + '"' + (r[2] ? ' id="crmSinceVal"' : '') + '>' +
            esc(niceDate(r[1])) + '</span></span>' +
        (r[2] ? '<button class="tl-pen" id="crmSinceEdit" type="button" aria-label="Edit client since">' + PEN + '</button>'
              : '<span class="tl-span"></span>') +
        '</div>';
    }).join('');

    if (!trip && !dates) { block.hidden = true; box.innerHTML = ''; return; }
    box.innerHTML = trip + (trip && dates ? '<div class="tl-rule"></div>' : '') + dates;
    wireSince(c);
    wireStages(c);
    block.hidden = false;
  }

  /* The day a stage began, as the log keeps it. A day typed is midnight UTC
     of that day, the same as Client since. */
  function logOf(c) {
    var log = (c.stage_log || []).slice();
    if (!log.length && c.stage_since) log = [{ stage: c.stage || 'lead', at: c.stage_since }];
    return log.map(function (x) { return { stage: x.stage, at: x.at }; });
  }
  function dayOf(at) { return at ? String(new Date(at).toISOString()).slice(0, 10) : ''; }

  /* One save for the dates the timeline holds: the stage log, the current
     stage's start (the last entry) and Client since, which is the first
     stage's start, so the two can never disagree. The order is checked
     before anything is sent: a stage cannot begin before the one before it
     or after the one after it, and no date is in the future. */
  function saveDates(c, list, created, what) {
    var days = list.map(function (x) { return dayOf(x.at); });
    for (var i = 1; i < days.length; i++) {
      if (days[i] < days[i - 1]) {
        return 'The ' + stageWord(list[i].stage)[1] + ' date cannot be before the ' + stageWord(list[i - 1].stage)[1] + ' date.';
      }
    }
    if (days.concat([dayOf(created)]).some(function (d) { return d > today(); })) return 'A date cannot be in the future.';
    var row = { stage_log: list, stage_since: list.length ? list[list.length - 1].at : c.stage_since, created_at: created };
    db.from('clients').update(row).eq('id', c.id).select('id').then(function (r) {
      if (r.error) { msg('crmSinceMsg', r.error.message, 'err'); return; }
      if (!(r.data || []).length) { msg('crmSinceMsg', 'Not saved. The database refused the request.', 'err'); return; }
      c.stage_log = list; c.stage_since = row.stage_since; c.created_at = created;
      var mine = state.clients.filter(function (x) { return x.id === c.id; })[0];
      if (mine) { mine.stage_log = list; mine.stage_since = row.stage_since; mine.created_at = created; }
      railDates(c);
      msg('crmSinceMsg', 'Saved.', 'ok');
      log('client.edited', c.name, what);
    });
    return null;
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
        value: c.created_at ? String(c.created_at).slice(0, 10) : '',
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
    var rows = (state.log || []).slice(0, 3);
    if (!rows.length) { block.hidden = true; box.innerHTML = ''; return; }
    box.innerHTML = '<ul class="raillog">' + rows.map(function (x) {
      return '<li>' + ico(logIcon(x.action)) + '<span class="raillog-what">' + esc(logWord(x.action)) + '</span>' +
        (x.detail ? '<span class="raillog-detail">' + esc(x.detail) + '</span>' : '') +
        '<span class="raillog-when">' + esc(niceDate(x.created_at)) + '</span></li>';
    }).join('') + '</ul>';
    block.hidden = false;
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
    ].filter(Boolean);
    $('cdelWhat').textContent = 'Deleting ' + c.name +
      ' removes the record and everything filed under it. This is immediate and cannot be undone.';
    $('cdelList').innerHTML = (gone.length
      ? gone.map(function (g) { return '<li>' + esc(g) + '</li>'; }).join('')
      : '<li>Nothing has been filed under this client yet.</li>') +
      '<li>Any content sets and campaigns on this client, with everything in them.</li>';
    $('cdelConfirm').value = '';
    if ($('cdelCode')) $('cdelCode').value = '';
    msg('cdelMsg', '', '');
    $('cdelSheet').hidden = false;

    /* Whether a code is set is not a secret, and the sheet has to know which
       question to ask before it asks it. Asked once and remembered. */
    var showCode = function () { $('cdelCodeRow').hidden = !codeNeeded; };
    if (codeNeeded === null) {
      db.rpc('delete_code_set').then(function (r) {
        codeNeeded = !!(r && r.data);
        showCode();
      }, function () { codeNeeded = false; showCode(); });
    } else showCode();

    $('cdelConfirm').focus();
  }

  (function wireClientDelete() {
    var shut = function () { $('cdelSheet').hidden = true; };
    ['cdelClose', 'cdelCancel'].forEach(function (id) {
      var el = $(id); if (el) el.addEventListener('click', shut);
    });
    var sheet = $('cdelSheet');
    if (sheet) sheet.addEventListener('click', function (e) { if (e.target === this) shut(); });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && sheet && !sheet.hidden) shut();
    });

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

    var go = $('cdelGo');
    if (go) go.addEventListener('click', function () {
      var c = state.client;
      if (!c) return;
      var typed = String($('cdelConfirm').value || '').trim();
      if (typed.toLowerCase() !== String(c.name || '').trim().toLowerCase()) {
        msg('cdelMsg', 'The name does not match.', 'err');
        $('cdelConfirm').focus();
        return;
      }
      var code = codeNeeded ? String($('cdelCode').value || '') : null;
      if (codeNeeded && !code) {
        msg('cdelMsg', 'The delete code is required.', 'err');
        $('cdelCode').focus();
        return;
      }
      go.disabled = true;
      var name = c.name;
      db.rpc('delete_client', { p_client: c.id, p_code: code }).then(function (r) {
        go.disabled = false;
        if (r.error) { msg('cdelMsg', r.error.message, 'err'); return; }
        var out = r.data;
        if (out === 'wrong-code') { msg('cdelMsg', 'That delete code is not right.', 'err'); return; }
        if (out === 'not-found') { msg('cdelMsg', 'That client is no longer there.', 'err'); return; }
        if (out !== 'deleted') { msg('cdelMsg', String(out || 'Unable to delete.'), 'err'); return; }
        shut();
        log('client.deleted', name, '');
        state.client = null;
        showList();
      }, function (e) {
        go.disabled = false;
        msg('cdelMsg', (e && e.message) || 'Unable to delete.', 'err');
      });
    });
  })();

  /* The one rule with teeth: nobody becomes active until they can be
     invoiced. The select goes back and the record opens on what is missing. */
  $('crmClientStage').addEventListener('change', function () {
    var c = state.client, to = this.value, was = c.stage || 'lead';
    if (to === was) return;
    if (to === 'active') {
      var missing = billingMissing(c);
      if (missing.length) {
        this.value = was;
        /* The refusal lands where the fix is, with the first missing field
           focused instead of describing a different screen. */
        showPane('billing');
        setUrl();
        if (mayPart('clients.billing', 'work')) {
          openBilling(this);
          msg('crmBillMsg', 'Billing details required before Active: ' + missing.join(', ') + '.', 'err');
          var first = BILLING.filter(function (f) { return missing.indexOf(f[2]) > -1; })[0];
          if (first && $(first[0])) $(first[0]).focus();
        } else {
          msg('crmBillNote', 'Billing details required before Active: ' + missing.join(', ') + '.', 'err');
        }
        return;
      }
    }
    db.from('clients').update({ stage: to }).eq('id', c.id).then(function (r) {
      if (r.error) { msg('crmWorkMsg', r.error.message, 'err'); openClient(c); return; }
      // Read before the local copy moves on: this is how long the stage being
      // left actually ran, which is the fact worth keeping.
      var spent = ageWord(c) || 'no time';
      c.stage = to;
      var mine = state.clients.filter(function (x) { return x.id === c.id; })[0];
      if (mine) mine.stage = to;
      log('client.stage', c.name, stageWord(to)[1] + ' after ' + spent);
      // The clock and the history are stamped by the trigger, so the row has
      // to come back from the database rather than be guessed at here.
      refreshClient(c, function () { openClient(c); });
    });
  });

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
    var pick = billContact(c);
    $('crmBillContact').innerHTML = '<option value="">None</option>' + (state.contacts || []).map(function (ct) {
      return '<option value="' + esc(ct.id) + '"' + (pick && pick.id === ct.id ? ' selected' : '') + '>' + esc(ct.name) +
        (ct.is_primary ? ' · Main contact' : '') + '</option>';
    }).join('');
  }

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
      ]) +
      readGroup('Billing contact and address', [
        ['Billing contact', pick ? esc(pick.name) + (pick.is_primary ? ' <span class="muted">· Main contact</span>' : '') : '', true],
        ['Finance email', t('finance_email')],
        ['Billing address', t('billing_address'), true, true]
      ]);
  }
  /* The sheet's fields are the record's values whenever it opens, so a Cancel
     leaves nothing half typed behind for the next Edit. */
  function fillBilling(c) {
    BILLING.forEach(function (f) { if (f[0] !== 'crmBillContact') $(f[0]).value = c[f[1]] || ''; });
    $('crmSstApplies').checked = c.sst_applies !== false;
    $('crmSstLabel').textContent = 'Charge ' + MON.taxLabel() + ' on this client\'s quotes';
  }
  function openBilling(opener) {
    fillBilling(state.client);
    paintBilling(state.client);
    msg('crmBillMsg', ''); msg('crmBillNote', '');
    openSheet('crmBillSheet', opener || $('crmBillEdit'));
  }
  $('crmBillEdit').addEventListener('click', function () { openBilling(this); });
  $('crmBillCancel').addEventListener('click', function () {
    shutSheet('crmBillSheet'); fillBilling(state.client); paintBilling(state.client); msg('crmBillMsg', '');
  });
  sheetClose('crmBillClose', 'crmBillCancel');

  function paintBrandRead(c) {
    var box = $('crmBrandRead');
    if (!box) return;
    var handle = function (k, label) {
      return c[k] ? '<a class="readlink" href="' + esc(profileUrl(k, c[k])) + '" target="_blank" rel="noopener">' + esc(c[k]) + '</a>' : '';
    };
    var site = c.website ? '<a class="readlink" href="' + esc(/^https?:/i.test(c.website) ? c.website : 'https://' + c.website) +
      '" target="_blank" rel="noopener">' + esc(c.website.replace(/^https?:\/\//i, '').replace(/\/$/, '')) + '</a>' : '';
    var logo = c.logo_url ? '<span class="readlogo"><img src="' + esc(c.logo_url) + '" alt="" onerror="this.remove()"></span>Set' : '';
    box.innerHTML =
      readGroup('Website and office', [['Website', site], ['Office phone', c.phone ? esc(c.phone) : '']]) +
      readGroup('Social handles', [
        ['Instagram', handle('handle_ig')], ['Facebook', handle('handle_fb')],
        ['TikTok', handle('handle_tiktok')], ['rednote', c.handle_xhs ? esc(c.handle_xhs) : '']
      ]) +
      readGroup('Logo and notes', [['Logo', logo], ['Brand notes', c.brand_notes ? esc(c.brand_notes) : '', false, true]]);
  }
  function fillBrand(c) {
    BRAND.forEach(function (f) { $(f[0]).value = c[f[1]] || ''; });
    $('crmNotes').value = c.brand_notes || '';
    paintLogoPreview();
  }
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
    var patch = { sst_applies: $('crmSstApplies').checked };
    BILLING.forEach(function (f) { patch[f[1]] = val(f[0]) || null; });
    if (patch.legal_name) patch.legal_name = patch.legal_name.toUpperCase();
    db.from('clients').update(patch).eq('id', state.client.id).then(function (r) {
      if (r.error) { msg('crmBillMsg', r.error.message, 'err'); return; }
      Object.keys(patch).forEach(function (k) { state.client[k] = patch[k]; });
      var still = billingMissing(state.client);
      log('client.billing', state.client.name, still.length ? still.length + ' fields still needed' : 'complete');
      if (window.ADspaceSheet) window.ADspaceSheet.clean();
      shutSheet('crmBillSheet');
      openClient(state.client);
      msg('crmBillNote', still.length
        ? 'Saved. Required before Active: ' + still.join(', ') + '.'
        : 'Saved.',
        still.length ? 'warn' : 'ok');
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
  if ($('crmLogo')) {
    $('crmLogo').addEventListener('input', paintLogoPreview);
    $('crmLogoPreviewImg').addEventListener('error', function () { this.hidden = true; });
  }

  $('crmBrandSave').addEventListener('click', function () {
    var patch = { brand_notes: val('crmNotes') || null };
    BRAND.forEach(function (f) { patch[f[1]] = val(f[0]) || null; });
    db.from('clients').update(patch).eq('id', state.client.id)
      .then(function (r) {
        if (r.error) { msg('crmBrandMsg', r.error.message, 'err'); return; }
        Object.keys(patch).forEach(function (k) { state.client[k] = patch[k]; });
        log('client.brand', state.client.name, '');
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

  function loadContacts() {
    var box = $('crmContacts');
    if (!box.querySelector('.crm-table')) skeleton(box, 3);
    db.from('client_contacts').select('*').eq('client_id', state.client.id)
      .order('is_primary', { ascending: false }).order('name').then(function (r) {
        if (r.error) { failLine(box, 'Contacts', r.error.message, loadContacts); return; }
        var all = r.data || [];
        state.contacts = all.filter(function (c) { return !c.archived_at; });
        paintSummary();
        var gone = all.filter(function (c) { return c.archived_at; });
        paintBilling(state.client);
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
  function waNumber(raw, market) {
    var d = String(raw || '').replace(/\D/g, '');
    if (!d) return '';
    if (d.indexOf('60') === 0 || d.indexOf('65') === 0) return d;
    if (d.charAt(0) === '0') return '6' + d;
    return (market === 'SG' ? '65' : '60') + d;
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
      '<span class="svc-name"><b>' + esc(ct.name) +
        /* Green is the live state, and on this row the live thing is the
           sign-in: main contact is a designation, not something running, so
           it reads neutral and the accent is spent once. Access on means
           they can sign in, full stop: the login is made on their way in by
           portal-login, so there is no second state to show. */
        (removed ? ' <span class="tone">Removed</span>' : ct.is_primary ? ' <span class="tone">Main contact</span>' : '') +
        (!removed && ct.portal_access ? ' <span class="tone is-ok">Portal access</span>' : '') +
        '</b><small>' + esc(sub) + '</small></span>' +
      '<span class="crm-reach">' +
        (ct.phone ? '<a class="plink" href="tel:' + esc(ct.phone) + '">' + esc(ct.phone) + '</a>' : '') +
        waLink(ct.whatsapp || ct.phone, (state.client || {}).market) +
        (ct.email ? '<a class="plink" href="mailto:' + esc(ct.email) + '">' + esc(ct.email) + '</a>' : '') +
      '</span>' +
      '<span class="team-act">' +
        '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
        '<div class="kmenu" data-menu hidden>' +
          (removed
            ? '<button class="kmenu-item" data-a="restore" type="button"><b>Restore</b></button>' +
              /* The hard delete, once the soft one has been made. Drawn only
                 where the Contacts part is managed. */
              '<button class="kmenu-item is-danger" data-a="del" data-need="clients.contacts:manage" type="button"><b>Delete</b></button>'
            : '<button class="kmenu-item" data-a="edit" data-need="clients.contacts:work" type="button"><b>Edit</b></button>' +
              (ct.is_primary ? '' :
                '<button class="kmenu-item" data-a="primary" type="button"><b>Main contact</b></button>') +
              (ct.portal_access
                ? '<button class="kmenu-item" data-a="invite" type="button"><b>Send invitation</b></button>' +
                  '<button class="kmenu-item" data-a="unportal" type="button"><b>Revoke portal access</b></button>'
                : '<button class="kmenu-item" data-a="portal" type="button"><b>Enable portal access</b></button>') +
              '<button class="kmenu-item is-danger" data-a="del" data-soft data-need="clients.contacts:work" type="button"><b>Remove</b></button>') +
        '</div>' +
      '</span>';
    wireMenu(row);
    var on = function (a, fn) { var el = row.querySelector('[data-a="' + a + '"]'); if (el) el.addEventListener('click', fn); };
    on('edit',    function () { openContact(ct); });
    on('primary', function () { makePrimary(ct); });
    on('portal',   function () { askPortal(ct); });
    on('invite',   function () { sendInvite(ct); });
    on('unportal', function () { setPortal(ct, false); });
    on('del',     function () { archiveContact(ct, true); });
    on('restore', function () { archiveContact(ct, false); });
    if (removed) on('del', function () { purgeContact(ct); });
    return row;
  }

  /* Portal access is one switch on the contact; the email is the sign-in
     address. Enabling it always asks the invite function to make the login,
     so the person can sign in whether or not sign-ups are open and never has
     to register anything. Whether the invitation goes out with it is asked,
     because the client is often told on a call and an email arriving out of
     nowhere is the account manager's conversation to time, not ours. */
  var portalFor = null;

  function askPortal(ct) {
    // The ⋯ it was chosen from would otherwise sit open behind the sheet.
    Array.prototype.forEach.call(document.querySelectorAll('.kmenu'), function (m) { m.hidden = true; });
    if (!ct.email) { msg('ctMsg', 'An email is required.', 'err'); openContact(ct); return; }
    portalFor = ct;
    $('portalFacts').innerHTML = [['Person', ct.name], ['Sign-in email', ct.email]]
      .map(function (f) { return '<div><dt>' + esc(f[0]) + '</dt><dd>' + esc(f[1]) + '</dd></div>'; }).join('');
    // Off by default: access is the decision, an email is a separate one, and
    // the client can sign in without ever receiving one.
    $('portalInvite').checked = false;
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
          + 'It leaves the building and cannot be recalled.',
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
    db.from('client_contacts').update({ portal_access: on }).eq('id', ct.id).then(function (r) {
      if (r.error) { msg('crmWorkMsg', r.error.message, 'err'); return; }
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
    $('ctName').value = ct ? (ct.name || '') : '';
    $('ctRole').value = ct ? (ct.role || '') : '';
    $('ctPhone').value = ct ? (ct.phone || '') : '';
    $('ctWa').value = ct ? waHandle(ct.whatsapp) : '';
    $('ctEmail').value = ct ? (ct.email || '') : '';
    $('ctLang').value = ct ? (ct.lang || 'en') : 'en';
    $('ctPrimary').checked = ct ? Boolean(ct.is_primary) : !state.contacts.length;
    msg('ctMsg', '');
    /* Nothing is focused when the sheet opens: on a phone a field taking
       focus raises the keyboard and zooms the page past the rest of the form,
       and the first field is rarely the one somebody came to change. */
  }
  function shutContact() { shutSheet('crmContactBox'); editingContact = null; }
  $('crmAddContact').addEventListener('click', function () { openContact(null); });
  $('ctCancel').addEventListener('click', shutContact);

  $('ctSave').addEventListener('click', function () {
    var name = val('ctName');
    if (!name) { msg('ctMsg', 'A contact needs a name.', 'err'); $('ctName').focus(); return; }
    var phone = val('ctPhone'), waU = waUser(val('ctWa'));
    if (waU && !waUserOk(waU)) {
      msg('ctMsg', 'A WhatsApp username uses letters, numbers, full stops and underscores.', 'err');
      $('ctWa').focus(); return;
    }
    var row = {
      name: name, role: val('ctRole') || null, phone: phone || null,
      whatsapp: waU ? '@' + waU : (phone || null),
      email: val('ctEmail') || null, lang: $('ctLang').value,
      is_primary: $('ctPrimary').checked
    };
    var after = function (r) {
      if (r.error) { msg('ctMsg', r.error.message, 'err'); return; }
      log(editingContact ? 'contact.edited' : 'contact.added', state.client.name + ' · ' + name, row.role || '');
      shutContact();
      loadContacts();
    };
    var go = function () {
      if (editingContact) {
        db.from('client_contacts').update(row).eq('id', editingContact.id).then(after);
      } else {
        row.client_id = state.client.id;
        db.from('client_contacts').insert(row).then(after);
      }
    };
    var othersPrimary = state.contacts.some(function (c) {
      return c.is_primary && !(editingContact && c.id === editingContact.id);
    });
    if (row.is_primary && othersPrimary) clearPrimary(go); else go();
  });

  function clearPrimary(then) {
    db.from('client_contacts').update({ is_primary: false })
      .eq('client_id', state.client.id).then(then, then);
  }
  function makePrimary(ct) {
    clearPrimary(function () {
      db.from('client_contacts').update({ is_primary: true }).eq('id', ct.id).then(function () {
        log('contact.primary', state.client.name + ' · ' + ct.name, '');
        loadContacts();
      });
    });
  }
  function archiveContact(ct, away) {
    var patch = away ? { archived_at: new Date().toISOString(), is_primary: false }
                     : { archived_at: null };
    db.from('client_contacts').update(patch).eq('id', ct.id).then(function (r) {
      if (r.error) { msg('crmWorkMsg', r.error.message, 'err'); return; }
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
      tone: 'danger'
    }, function () {
      db.from('client_contacts').delete().eq('id', ct.id).then(function (r) {
        if (r.error) { msg('crmWorkMsg', r.error.message, 'err'); return; }
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
  function undoBar(text, undo) {
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
        if (r.error) { failLine(box, 'Calls and visits', r.error.message, loadTouches); return; }
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
        (removed ? '<span class="tone">Removed</span>' : '') + '</div>' +
      '<div class="touch-body">' +
        '<p class="touch-summary">' + esc(tc.summary) + '</p>' +
        '<p class="touch-meta">' +
          [tc.contact_name ? 'With ' + tc.contact_name : '', tc.by_whom ? 'by ' + tc.by_whom : '',
           tc.updated_at ? 'edited' : '']
            .filter(Boolean).map(esc).join(' · ') +
        '</p>' +
        (tc.next_action ? '<p class="touch-next' + (due ? ' is-due' : '') + (tc.done_at ? ' is-done' : '') + '">' +
          (tc.done_at ? 'Done: ' : 'Next: ') + esc(tc.next_action) +
          (tc.next_at ? ' · by ' + esc(niceDate(tc.next_at)) : '') +
          (due ? ' · overdue' : '') + '</p>' : '') +
      '</div>' +
      '<div class="touch-actions">' +
        (removed
          ? '<button class="btn btn-quiet btn-sm" data-a="restore" type="button">Restore</button>'
          : (open ? '<button class="btn btn-sm" data-a="done" type="button">Done</button>' : '') +
            (tc.done_at ? '<button class="btn btn-quiet btn-sm" data-a="undone" type="button">Reopen</button>' : '') +
            '<button class="btn btn-quiet btn-sm" data-a="edit" data-need="clients.calls:work" type="button">Edit</button>' +
            '<button class="btn btn-quiet btn-sm is-danger" data-a="del" data-need="clients.calls:work" type="button">Remove</button>') +
      '</div>';
    var on = function (a, fn) { var el = row.querySelector('[data-a="' + a + '"]'); if (el) el.addEventListener('click', fn); };
    on('edit',    function () { openTouch(tc); });
    on('done',    function () { markDone(tc, true); });
    on('undone',  function () { markDone(tc, false); });
    on('del',     function () { archiveTouch(tc, true); });
    on('restore', function () { archiveTouch(tc, false); });
    return row;
  }

  function markDone(tc, done) {
    db.from('client_touches').update({ done_at: done ? new Date().toISOString() : null })
      .eq('id', tc.id).then(function (r) {
        if (r.error) { msg('crmWorkMsg', r.error.message, 'err'); return; }
        log(done ? 'client.action_done' : 'client.action_reopened', state.client.name, tc.next_action || '');
        loadTouches();
      });
  }
  function archiveTouch(tc, away) {
    db.from('client_touches').update({ archived_at: away ? new Date().toISOString() : null })
      .eq('id', tc.id).then(function (r) {
        if (r.error) { msg('crmWorkMsg', r.error.message, 'err'); return; }
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
    if (!tc) {
      var main = state.contacts.filter(function (c) { return c.is_primary; })[0];
      if (main) $('tcWith').value = main.name;
    }
    msg('tcMsg', '');
    /* Nothing is focused when the sheet opens: on a phone a field taking
       focus raises the keyboard and zooms the page past the rest of the form,
       and the first field is rarely the one somebody came to change. */
  }
  function shutTouch() { shutSheet('crmTouchBox'); editingTouch = null; }
  $('crmAddTouch').addEventListener('click', function () { openTouch(null); });
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
      next_at: $('tcNextAt').value || null
    };
    var after = function (r) {
      if (r.error) { msg('tcMsg', r.error.message, 'err'); return; }
      log(editingTouch ? 'client.touch_edited' : 'client.touch', state.client.name,
          KIND_WORD[row.kind] + (row.next_action ? ' · next: ' + row.next_action : ''));
      shutTouch();
      loadTouches();
      // The first call or visit is what makes a lead contacted.
      if (!editingTouch && (state.client.stage || 'lead') === 'lead') {
        db.from('clients').update({ stage: 'contacted' }).eq('id', state.client.id).then(function (q) {
          if (q.error) return;
          var spent = ageWord(state.client) || 'no time';
          state.client.stage = 'contacted';
          var mine = state.clients.filter(function (x) { return x.id === state.client.id; })[0];
          if (mine) mine.stage = 'contacted';
          log('client.stage', state.client.name, 'Contacted after ' + spent);
          refreshClient(state.client, function () { openClient(state.client); });
        });
      }
    };
    if (editingTouch) {
      row.updated_at = new Date().toISOString();
      db.from('client_touches').update(row).eq('id', editingTouch.id).then(after);
    } else {
      row.client_id = state.client.id;
      row.by_whom = actor() || null;
      db.from('client_touches').insert(row).then(after);
    }
  });

  // ---- Engagements --------------------------------------------------------
  /* The campaign's state, from the one file that holds it. This was a private
     map saying "With the client" where the campaign page said "Open for
     selection" and js/words.js said "Open": three words for one state, because
     the shared one was written and then never read. */
  var CAMP_WORD = W.en.campState;

  function loadWork() {
    var box = $('crmWorkList');
    if (!box.querySelector('.crm-table')) skeleton(box, 2);
    var c = state.client;
    var out = { sets: null, camps: null };
    var done = function () {
      if (out.sets === null || out.camps === null) return;
      paintWork(out.sets, out.camps);
    };
    db.from('batches').select('id, title, state, created_at').eq('client_id', c.id)
      .order('created_at', { ascending: false }).limit(20)
      .then(function (r) { out.sets = r.data || []; done(); }, function () { out.sets = []; done(); });
    db.from('campaigns').select('id, title, state, slots, created_at').eq('client_id', c.id)
      .order('created_at', { ascending: false }).limit(20)
      .then(function (r) { out.camps = r.data || []; done(); }, function () { out.camps = []; done(); });
  }

  function paintWork(sets, camps) {
    var c = state.client;
    var box = $('crmWorkList');
    var act = $('crmEngageActions');
    // Nothing to engage until the client is active, so the section waits.
    $('crmEngage').hidden = c.stage !== 'active';
    if (c.stage !== 'active') { act.innerHTML = ''; box.innerHTML = ''; return; }
    var PLUS = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>';
    var OUT = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 4h6v6"/><path d="M20 4 11 13"/><path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg>';
    act.innerHTML =
      (c.review_hidden
        ? '<button class="btn btn-icon" id="crmReviewOn" type="button">' + PLUS + '<span>Enable Content Review</span></button>'
        : '<button class="btn btn-icon" id="crmGoReview" type="button"><span>Open Content Review</span>' + OUT + '</button>') +
      '<button class="btn btn-icon" id="crmGoCampaign" type="button">' + PLUS + '<span>New campaign</span></button>';
    var on = $('crmReviewOn');
    if (on) on.addEventListener('click', function () {
      db.from('clients').update({ review_hidden: false }).eq('id', c.id).then(function () {
        c.review_hidden = false;
        log('client.review_on', c.name, '');
        location.href = '/admin/?s=review&client=' + encodeURIComponent(keyOf(c));
      });
    });
    var go = $('crmGoReview');
    if (go) go.addEventListener('click', function () {
      location.href = '/admin/?s=review&client=' + encodeURIComponent(keyOf(c));
    });
    $('crmGoCampaign').addEventListener('click', function () {
      location.href = '/admin/?s=campaigns&new=' + encodeURIComponent(c.id);
    });

    if (!sets.length && !camps.length) {
      box.innerHTML = '<div class="empty">No engagements.</div>';
      return;
    }
    box.innerHTML = '';
    /* One panel with rows in it, as every other section of this record is. */
    var list = document.createElement('div');
    list.className = 'work-list';
    box.appendChild(list);
    box = list;
    /* A row with no name is a row nobody can pick out, and one campaign is
       live called `0`. The record is never renamed behind anybody's back; it
       is drawn under a stand in and stays editable in Creator Campaigns. */
    var named = function (t) {
      var v = String(t == null ? '' : t).trim();
      return (!v || v === '0' || v === 'null' || v === 'undefined') ? 'Untitled campaign' : v;
    };
    camps.forEach(function (k) {
      box.appendChild(workRow(named(k.title),
        'Creator campaign · ' + k.slots + ' creator' + (k.slots === 1 ? '' : 's'),
        '/admin/?s=campaigns&campaign=' + encodeURIComponent(k.id),
        [CAMP_WORD[k.state] || k.state, W.tone(k.state)]));
    });
    sets.forEach(function (b) {
      var live = b.state === 'published';
      box.appendChild(workRow(b.title || 'Content set', 'Content Review',
        '/admin/?s=review&client=' + encodeURIComponent(keyOf(c)) + '&set=' + encodeURIComponent(b.id),
        [live ? 'With the client' : 'Draft', live ? 'is-ok' : '']));
    });
  }

  function workRow(title, meta, href, chip) {
    var row = document.createElement('button');
    row.type = 'button';
    row.className = 'work-row';
    row.innerHTML =
      /* The name is what gives way when the row runs out of room; the state
         is the one thing the row exists to tell you. Both used to sit in one
         clipped box, so "Open for selection" came out as "Open for selectio"
         on a phone while the name it belonged to had room to spare. */
      '<span class="work-row-name"><span class="work-row-title">' + esc(title) + '</span>' +
        (chip ? '<span class="tone ' + esc(chip[1] || '') + '">' + esc(chip[0]) + '</span>' : '') +
      '</span>' +
      '<span class="work-row-meta">' + esc(meta) + '</span>' +
      '<svg class="work-row-go" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
        'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
        '<path d="M9 18l6-6-6-6"/></svg>';
    row.addEventListener('click', function () { location.href = href; });
    return row;
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
  function svcById(slug) { return (catalog || []).filter(function (s) { return s.slug === slug; })[0]; }
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

  function loadServices() {
    var box = $('crmServices');
    if (!box.querySelector('.crm-table')) skeleton(box, 3);
    loadCatalog(function () {
      db.from('client_services').select('*').eq('client_id', state.client.id)
        .is('archived_at', null).order('created_at').then(function (r) {
          if (r.error) { failLine(box, 'Services', r.error.message, loadServices); return; }
          state.services = r.data || [];
          paintServices();
          paintSummary();
        });
    });
  }

  function paintServices() {
    var box = $('crmServices');
    var rows = state.services;
    var c = state.client;
    box.innerHTML = '';
    if (!rows.length) {
      // The enquiry as typed at intake stands in until a line is added.
      box.innerHTML = '<div class="empty">' + (c.deal_note ? esc(c.deal_note) : 'No services.') + '</div>';
      return;
    }
    var table = document.createElement('div');
    table.className = 'crm-table';
    table.innerHTML = '<div class="crm-head svc-row csv-row"><span>Service</span><span class="svc-rate">Qty × rate</span>' +
      '<span class="svc-rate">Amount</span><span>State</span><span></span></div>';
    rows.forEach(function (l) { table.appendChild(serviceRow(l)); });
    var sum = function (st) {
      return rows.filter(function (l) { return l.state === st; }).reduce(function (s, l) { return s + amountOf(l); }, 0);
    };
    var quoted = sum('quoted'), confirmed = sum('confirmed');
    var tot = document.createElement('div');
    tot.className = 'csv-total';
    tot.innerHTML =
      (quoted ? '<span>To quote<b>' + esc(MON.money2(quoted, c.market)) + '</b></span>' : '') +
      '<span class="is-total">Confirmed<b>' + esc(MON.money2(confirmed, c.market)) + '</b></span>';
    table.appendChild(tot);
    box.appendChild(table);
  }

  function serviceRow(l) {
    var c = state.client;
    var w = SV_STATE[l.state] || SV_STATE.enquired;
    var row = document.createElement('div');
    row.className = 'svc-row csv-row';
    row.innerHTML =
      '<span class="svc-name"><b>' + esc(l.label) + '</b>' +
        (l.note || l.unit || termWord(l) || adjWord(l)
          ? '<small>' + esc([l.unit, adjWord(l), termWord(l), l.note].filter(Boolean).join(' · ')) + '</small>' : '') + '</span>' +
      '<span class="svc-rate svc-calc">' + esc(Number(l.qty) + ' × ' + MON.money2(rateOf(l), c.market) +
        (Number(l.tenure || 1) > 1 ? ' × ' + Number(l.tenure) + ' mo' : '')) + '</span>' +
      '<span class="svc-rate svc-amt"><b>' + esc(MON.money2(amountOf(l), c.market)) + '</b></span>' +
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
          '<button class="kmenu-item" data-a="edit" data-need="clients.services:work" type="button"><b>Edit</b></button>' +
          /* This overrides a client's service line, not the rate card, so it
             is Clients at manage and not Services. */
          (bridge.may && bridge.may('clients', 'manage')
            ? '<button class="kmenu-item" data-a="force" type="button"><b>Update status</b></button>' : '') +
          '<button class="kmenu-item is-danger" data-a="del" data-soft data-need="clients.services:work" type="button"><b>Remove</b></button>' +
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
        title: 'Update status',
        body: 'The state of ' + l.label + ' is set by hand, past the checks the '
            + 'letter normally makes. The reason goes on the activity record.',
        go: 'Update',
        tone: 'warn',
        fields: [
          { name: 'state', label: 'State', value: l.state,
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
          }, function (e) { msg('crmServiceMsg', (e && e.message) || 'Could not set it.', 'err'); });
      });
    });
    on('del', function () { saveService(l, { archived_at: new Date().toISOString() }, true); });
    return row;
  }

  var OVERRIDE_WORD = {
    'not-allowed': 'Only an admin can set a service state by hand.',
    'bad-state': 'A service is enquired, quoted or confirmed.',
    'reason-required': 'A reason is required.',
    'not-found': 'That line could not be found.'
  };

  var editingService = null;
  function fillServicePick() {
    var groups = {};
    (catalog || []).filter(function (s) { return s.active !== false; }).forEach(function (s) {
      (groups[s.category] = groups[s.category] || []).push(s);
    });
    var cats = CATS.concat(Object.keys(groups).filter(function (k) { return CATS.indexOf(k) < 0; }));
    $('svPick').innerHTML = cats.filter(function (k) { return groups[k]; }).map(function (k) {
      return '<optgroup label="' + esc(k) + '">' + groups[k].map(function (s) {
        return '<option value="' + esc(s.slug) + '">' + esc(s.name) +
          (s.rate != null ? ' · ' + MON.money(s.rate, 'MY') : '') + '</option>';
      }).join('') + '</optgroup>';
    }).join('') + '<option value="custom">Custom</option>';
  }
  function syncPick(fill) {
    var slug = $('svPick').value;
    var s = svcById(slug);
    $('svLabelRow').hidden = slug !== 'custom';
    /* Prefilled, not fixed: the catalogue seeds the price, the term and what
       the package includes, and the line keeps its own copy from there. */
    if (fill && s) {
      $('svRate').value = s.rate != null ? Number(s.rate) : '';
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
  function syncAdjust(typing) {
    var months = Number(val('svTenure') || 1);
    var card = MON.termPct(months);
    var cur = svPctValue();
    /* The field follows the card while it still holds the card's own figure
       for the term it was filled for; a figure of the person's own stays. */
    if (typing !== true && (cur === null || cur === svPctCard)) {
      $('svPct').value = card ? String(card) : '';
      svPctCard = card;
    }
    var adj = MON.termAdj(months, svPctValue());
    $('svAdjRow').hidden = !adj && !card;
    if (adj) $('svAdjustWord').textContent = 'Apply the ' + adj;
    else if (card) $('svAdjustWord').textContent = 'Apply the term adjustment';
    else $('svAdjust').checked = false;
  }
  $('svTenure').addEventListener('input', function () { syncAdjust(false); });
  $('svPct').addEventListener('input', function () { syncAdjust(true); });
  function openService(l) {
    editingService = l || null;
    loadCatalog(function () {
      fillServicePick();
      $('crmServiceTitle').textContent = l ? 'Edit service' : 'New service';
      var first = $('svPick').options[0] ? $('svPick').options[0].value : 'custom';
      $('svPick').value = l ? (l.service_slug && svcById(l.service_slug) ? l.service_slug : 'custom') : first;
      $('svLabel').value = l ? (l.label || '') : '';
      $('svQty').value = l ? Number(l.qty || 1) : 1;
      $('svRate').value = l ? Number(l.rate || 0) : '';
      $('svState').value = l ? (l.state || 'enquired') : 'enquired';
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
      svPctCard = l ? MON.termPct(l.tenure) : null;
      if (l && l.term_pct !== null && l.term_pct !== undefined) {
        $('svPct').value = String(l.term_pct);
      } else if (l && l.term_adjust !== false && MON.termFactor(l.tenure) !== 1) {
        $('svPct').value = String(Math.round((MON.termFactor(l.tenure) - 1) * 10000) / 100);
      } else {
        $('svPct').value = '';
      }
      syncPick(!l);
      msg('svMsg', '');
      openSheet('crmServiceBox');
    });
  }
  function shutService() { shutSheet('crmServiceBox'); editingService = null; }
  $('svPick').addEventListener('change', function () {
    syncPick(true);
    if ($('svPick').value === 'custom') $('svLabel').focus();
  });
  $('crmAddService').addEventListener('click', function () { openService(null); });
  $('svCancel').addEventListener('click', shutService);
  $('svSave').addEventListener('click', function () {
    var slug = $('svPick').value;
    var s = svcById(slug);
    var label = slug === 'custom' ? val('svLabel') : (s ? s.name : '');
    if (!label) { msg('svMsg', 'A name is required.', 'err'); $('svLabel').focus(); return; }
    var row = {
      service_slug: s ? s.slug : null, label: label, unit: s ? (s.unit || null) : null,
      qty: Number(val('svQty') || 1), rate: Number(val('svRate') || 0),
      tenure: Math.max(1, Number(val('svTenure') || 1)), start_on: val('svStart') || null,
      state: $('svState').value, note: val('svNote') || null,
      detail: val('svDetail') || null,
      // Stored on every save, never left to the column's default, because the
      // rule that reads it treats a missing value as "on".
      term_adjust: !$('svAdjRow').hidden && $('svAdjust').checked,
      /* The percentage the tick applies, stored with the line whether or not
         the tick is on, so the figure the letter and the client's page work
         out is the one the person saw. */
      term_pct: !$('svAdjRow').hidden ? svPctValue() : null
    };
    if (editingService) { saveService(editingService, row); return; }
    row.client_id = state.client.id;
    db.from('client_services').insert(row).then(function (r) {
      if (r.error) { msg('svMsg', r.error.message, 'err'); return; }
      log('client.service', state.client.name, label + ' · ' + SV_STATE[row.state][0]);
      shutService();
      syncValue();
    });
  });
  function saveService(l, patch, removed) {
    db.from('client_services').update(patch).eq('id', l.id).then(function (r) {
      if (r.error) { msg('crmServiceMsg', r.error.message, 'err'); return; }
      log(removed ? 'client.service_removed' : 'client.service_changed', state.client.name,
          l.label + (patch.state ? ' · ' + SV_STATE[patch.state][0] : ''));
      if (removed) undoBar(l.label + ' removed.', function () { saveService(l, { archived_at: null }); });
      shutService();
      syncValue();
    });
  }
  /* The confirmed total, else the quoted total, is the client's value. */
  function syncValue() {
    db.from('client_services').select('*').eq('client_id', state.client.id).is('archived_at', null)
      .then(function (r) {
        var rows = r.data || [];
        var sum = function (st) {
          return rows.filter(function (l) { return l.state === st; }).reduce(function (s, l) { return s + amountOf(l); }, 0);
        };
        var v = sum('confirmed') || sum('quoted') || null;
        var was = state.client.deal_value == null ? null : Number(state.client.deal_value);
        var done = function () {
          state.client.deal_value = v;
          var mine = state.clients.filter(function (x) { return x.id === state.client.id; })[0];
          if (mine) mine.deal_value = v;
          openClient(state.client);
        };
        if (v === was) { done(); return; }
        db.from('clients').update({ deal_value: v }).eq('id', state.client.id).then(done, done);
      });
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
        table.innerHTML = '<div class="crm-head svc-row doc-row"><span>Request</span><span class="svc-rate">Fee</span><span>State</span><span></span></div>';
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
    row.className = 'svc-row doc-row' + (gone ? ' is-off' : '');
    var sub = [q.contact_name, niceDate(q.created_at), q.note].filter(Boolean).join(' · ');
    row.innerHTML =
      '<span class="svc-name"><b>' + esc((RQ_KIND[q.kind] || q.kind) + (q.service_label ? ' · ' + q.service_label : '')) + '</b>' +
        (sub ? '<small>' + esc(sub) + '</small>' : '') +
        (q.reply ? '<small>' + esc('Reply: ' + q.reply) + '</small>' : '') + '</span>' +
      '<span class="svc-rate svc-amt">' + (q.fee != null && q.fee !== '' ? '<b>' + esc(MON.money2(q.fee, c.market)) + '</b>'
        : '<span class="muted">' + esc(MON.sign(c.market)) + '</span>') + '</span>' +
      '<span class="svc-state">' + (gone ? '<span class="chip-state">Withdrawn</span>'
        : '<select class="select select-sm state-select ' + w[1] + '" data-f="state" aria-label="State">' +
          Object.keys(RQ_STATE).map(function (k) {
            return '<option value="' + k + '"' + (k === q.state ? ' selected' : '') + '>' + esc(RQ_STATE[k][0]) + '</option>';
          }).join('') + '</select>') + '</span>' +
      '<span class="team-act">' +
        (gone ? '' :
        '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
        '<div class="kmenu" data-menu hidden>' +
          '<button class="kmenu-item" data-a="reply" type="button"><b>Reply</b></button>' +
        '</div>') +
      '</span>';
    if (!gone) {
      wireMenu(row);
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
    db.from('client_requests').update(patch).eq('id', q.id).then(function (r) {
      if (r.error) { msg(replying ? 'rqMsg' : 'crmReqMsg', r.error.message, 'err'); return; }
      log(action, state.client.name, (RQ_KIND[q.kind] || q.kind) + (q.service_label ? ' · ' + q.service_label : '') +
        (patch.state ? ' · ' + RQ_STATE[patch.state][0] : '') + (patch.fee != null ? ' · ' + MON.money2(patch.fee, state.client.market) : ''));
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
      if (err) { failLine(box, 'Documents', err.message || String(err), loadDocuments); return; }
      if (!state.client || state.client.id !== c.id) return;
      /* Kept so the Summary can read them without a second call: the record
         has already paid for this. */
      state.documents = rows || [];
      paintSummary();
      /* Which service lines each letter captured. A letter issued before this
         change has none, which is what keeps it out of verification. */
      DOCS.mapOf(rows.map(function (d) { return d.id; }), function (by) {
        state.docMap = by || {};
        box.innerHTML = '';
        var empty = document.createElement('div');
        empty.className = 'empty';
        empty.textContent = 'No documents.';
        if (!rows.length) box.appendChild(empty);
        else {
          var table = document.createElement('div');
          table.className = 'crm-table';
          table.innerHTML = '<div class="crm-head svc-row doc-row"><span>Document</span><span class="svc-rate">Total</span><span>State</span><span></span></div>';
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
    var mapped = (state.docMap || {})[d.id] || [];
    /* Verification is offered only where the letter knows exactly which lines
       it carried. A legacy letter is history and is left as history. */
    var canVerify = st === 'signed' && mapped.length && mapped.length === (d.lines || []).length;
    var row = document.createElement('div');
    row.className = 'svc-row doc-row' + (d.voided_at || d.superseded_by ? ' is-off' : '');
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
      '<span class="team-act">' +
        '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
        '<div class="kmenu" data-menu hidden>' +
          '<button class="kmenu-item" data-a="download" type="button"><b>Download</b></button>' +
          (st === 'issued' ? '<button class="kmenu-item" data-a="sign" type="button"><b>Mark signed</b></button>' : '') +
          (st === 'signed' ? '<button class="kmenu-item" data-a="unsign" type="button"><b>Not signed after all</b></button>' : '') +
          (canVerify ? '<button class="kmenu-item" data-a="verify" type="button"><b>Verify signed letter</b></button>' : '') +
          /* Void reverses a confirmation, so it is offered on a verified
             letter and nowhere else: an issued or signed letter has confirmed
             nothing and there is nothing to put back. Both acts are the
             section's Manage level, so both carry the same `data-need` and
             the database decides again when the button is pressed. */
          (st === 'verified'
            ? '<button class="kmenu-item is-danger" data-a="void" data-need="clients.documents:manage" type="button"><b>Void</b></button>' : '') +
          '<button class="kmenu-item is-danger" data-a="del" data-need="clients.documents:manage" type="button"><b>Delete</b></button>' +
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
  var voiding = null, deleting = null;

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

  function openDelete(d, mapped) {
    deleting = d;
    $('delWhat').textContent =
      'Deleting ' + d.number + ' removes the letter record, its service mapping and the ' +
      'client’s access to it, and puts back the service lines this letter alone confirmed' +
      (mapped ? ', of ' + linesWord(mapped) + ' on it' : '') + '. ' +
      'The file is drawn from the record on Download and is not stored, ' +
      'so nothing is left to recover: this is immediate and cannot be undone. ' +
      'The reference is never reused.';
    $('delConfirm').value = '';
    $('delReason').value = '';
    msg('delMsg', '', '');
    $('delSheet').hidden = false;
    $('delConfirm').focus();
  }

  function wireLetterSheets() {
    var shutVoid = function () { voiding = null; $('voidSheet').hidden = true; };
    var shutDel = function () { deleting = null; $('delSheet').hidden = true; };
    ['voidClose', 'voidCancel'].forEach(function (id) {
      var el = $(id); if (el) el.addEventListener('click', shutVoid);
    });
    ['delClose', 'delCancel'].forEach(function (id) {
      var el = $(id); if (el) el.addEventListener('click', shutDel);
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

    ['voidSheet', 'delSheet'].forEach(function (id) {
      var el = $(id);
      if (el) el.addEventListener('click', function (e) {
        if (e.target === this) (id === 'voidSheet' ? shutVoid() : shutDel());
      });
    });
    document.addEventListener('keydown', function (e) {
      if (e.key !== 'Escape') return;
      if (!$('voidSheet').hidden) shutVoid();
      else if (!$('delSheet').hidden) shutDel();
    });

    var dgo = $('delGo');
    if (dgo) dgo.addEventListener('click', function () {
      if (!deleting) return;
      var typed = String($('delConfirm').value || '').trim();
      var why = String($('delReason').value || '').trim();
      if (typed !== deleting.number) {
        msg('delMsg', 'Type ' + deleting.number + ' to confirm.', 'err');
        $('delConfirm').focus(); return;
      }
      if (!why) { msg('delMsg', 'A reason is required.', 'err'); $('delReason').focus(); return; }
      var d = deleting;
      dgo.disabled = true;
      DOCS.remove(d, typed, why, function (err, out) {
        dgo.disabled = false;
        if (err) { msg('delMsg', err, 'err'); return; }
        shutDel();
        var n = (out && out.reverted) || 0;
        msg('crmDocMsg', d.number + ' deleted. ' +
          (n ? linesWord(n) + ' put back to To quote.' : 'No service line changed.'), 'ok');
        loadDocuments();
        loadServices();
        syncValue();
      });
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
          '<span class="lpickamt">' + esc(MON.money2(amountOf(l), c.market)) + '</span>' +
        '</label>';
      }).join('') +
      (note ? '<p class="lpicknote">' + esc(note) + '</p>' : '') + '</div>';
  }

  function openPick() {
    var c = state.client;
    msg('crmDocMsg', '');
    msg('pickMsg', '');
    /* The Client ID is what an automatic reference is built from, so a client
       without one is told here rather than at the end. It is a caution and no
       longer a refusal to open the sheet: a typed reference needs no code,
       and the database is what decides either way. */
    if (!String(c.client_code || '').trim()) {
      msg('pickMsg', 'This client has no Client ID, so a reference cannot be made automatically. Type one below, or set the ID on the record.', 'warn');
    }
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
          ' placeholder="Numbered automatically">' +
      '</div>';
    /* A held line is shown so the reason is on the screen, and is refused so
       the same letter cannot go out twice by accident. */
    Array.prototype.forEach.call($('pickBody').querySelectorAll('.lpickrow.is-held input'), function (i) {
      i.disabled = true;
    });
    Array.prototype.forEach.call($('pickBody').querySelectorAll('input[type="checkbox"]'), function (i) {
      i.addEventListener('change', pickSum);
    });
    pickSum();
    $('pickSheet').hidden = false;
    var first = $('pickBody').querySelector('input:not([disabled])');
    if (first) first.focus();
  }

  function pickedIds() {
    return Array.prototype.filter.call($('pickBody').querySelectorAll('input[type="checkbox"]'),
      function (i) { return i.checked && !i.disabled; }).map(function (i) { return i.value; });
  }

  function pickSum() {
    var ids = pickedIds();
    var c = state.client;
    var rows = (state.services || []).filter(function (l) { return ids.indexOf(l.id) > -1; });
    var price = rows.length ? DOCS.quoteOf(c, rows) : null;
    $('pickSum').textContent = rows.length
      ? rows.length + (rows.length === 1 ? ' service · ' : ' services · ') + MON.money2(price.total, c.market)
      : 'Nothing chosen';
    $('pickGo').disabled = !rows.length;
  }

  function shutPick() {
    $('pickSheet').hidden = true;
    picking = null;
    $('pickGo').disabled = false;
    $('pickGo').textContent = 'Issue letter';
  }
  wireLetterSheets();
  $('pickClose').addEventListener('click', shutPick);
  $('pickCancel').addEventListener('click', shutPick);
  $('pickSheet').addEventListener('click', function (e) { if (e.target === this) shutPick(); });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && !$('pickSheet').hidden) shutPick();
  });

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
      stage: stageWord(c.stage || 'lead')[1], enquiry: c.deal_note || ''
    };
    DOCS.issue('offer', c, rows, deal,
      { idem: picking.idem, replaces: picking.replaces, renewal: renewal,
        serial: ($('pickRef') && $('pickRef').value.trim()) || '' },
      function (r) {
        go.disabled = false;
        go.textContent = 'Issue letter';
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
  var svcFind = '', svcCat = '';

  function enterServices() {
    catalog = null;
    $('svcAdd').hidden = !maySvc();
    shutSheet('svcBox');
    msg('svcListMsg', '');
    skeleton($('svcList'), 6);
    loadCatalog(function () { fillSvcFilter(); paintCatalog(); });
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

  function fillSvcFilter() {
    var sel = $('svcFilter');
    if (!sel) return;
    var rows = catalog || [];
    var seen = [];
    svcTiers(rows).forEach(function (t) {
      t[1].forEach(function (k) {
        if (seen.indexOf(k) < 0 && rows.some(function (s) { return s.category === k; })) seen.push(k);
      });
    });
    sel.innerHTML = '<option value="">All categories</option>' + seen.map(function (k) {
      return '<option value="' + esc(k) + '">' + esc(k) + '</option>';
    }).join('');
    sel.value = svcCat;
  }

  /* Name, what it includes and the unit: a search on the card is somebody
     looking for a line to quote, and they rarely remember its exact title. */
  function svcMatch(s) {
    if (!svcCat && !svcFind) return true;
    if (svcCat && s.category !== svcCat) return false;
    if (!svcFind) return true;
    var hay = [s.name, s.note, s.unit, s.detail, s.category].join(' ').toLowerCase();
    return hay.indexOf(svcFind) > -1;
  }

  function paintCatalog() {
    var box = $('svcList');
    box.innerHTML = '';
    var all = catalog || [];
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

  function clearSvcFilters() {
    svcFind = ''; svcCat = '';
    if ($('svcFind')) $('svcFind').value = '';
    if ($('svcFilter')) $('svcFilter').value = '';
    paintCatalog();
  }

  if ($('svcFind')) $('svcFind').addEventListener('input', function () {
    svcFind = this.value.trim().toLowerCase();
    paintCatalog();
  });
  if ($('svcFilter')) $('svcFilter').addEventListener('change', function () {
    svcCat = this.value;
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
    row.innerHTML =
      '<span class="svc-name"><b>' + esc(s.name) + (off ? ' <span class="tone">Inactive</span>' : '') + '</b>' +
        (s.note ? '<small>' + esc(s.note) + '</small>' : '') + '</span>' +
      '<span class="svc-rate">' + (s.rate != null ? esc(MON.money2(s.rate, 'MY')) : '<span class="muted">On quote</span>') + '</span>' +
      '<span class="svc-unit">' + esc(s.unit || '') + '</span>' +
      '<span class="team-act">' + (maySvc()
        ? '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
          '<div class="kmenu" data-menu hidden>' +
            '<button class="kmenu-item" data-a="edit" type="button"><b>Edit</b></button>' +
            // Taking a line off the card is a decision of the year, not a select.
            '<button class="kmenu-item" data-a="state" type="button"><b>' +
              (off ? 'Set active' : 'Set inactive') + '</b></button>' +
            /* Inactive first, then gone, as it is for a letter and a contact:
               a line is taken off the card before it can be taken out of it.
               Drawn only where Services is managed. */
            (off ? '<button class="kmenu-item is-danger" data-a="del" data-need="services:manage" type="button"><b>Delete</b></button>' : '') +
          '</div>'
        : '') + '</span>';
    row.classList.add('cat-row');
    if (maySvc()) {
      wireMenu(row);
      row.querySelector('[data-a="edit"]').addEventListener('click', function () { openSvc(s); });
      var del = row.querySelector('[data-a="del"]');
      if (del) del.addEventListener('click', function () { purgeSvc(s); });
      row.querySelector('[data-a="state"]').addEventListener('click', function () {
        Array.prototype.forEach.call(document.querySelectorAll('.kmenu'), function (m) { m.hidden = true; });
        patchSvc(s, { active: off }, off ? 'service.on' : 'service.off');
      });
    }
    return row;
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
      var n = (q.data || []).length;
      if (n) {
        msg('svcListMsg', s.name + ' is on ' + n + ' client service line' + (n === 1 ? '' : 's') +
            '. Remove those lines first.', 'warn');
        return;
      }
      window.ADspaceConfirm.ask({
        title: 'Delete',
        body: s.name + ' leaves the rate card and cannot be quoted again. There is '
            + 'no restore. Letters already issued keep the line as it was written.',
        go: 'Delete',
        tone: 'danger'
      }, function () {
        db.from('services').delete().eq('slug', s.slug).then(function (r) {
          if (r.error) { msg('svcListMsg', r.error.message, 'err'); return; }
          log('service.deleted', s.name, s.category || '');
          enterServices();
          msg('svcListMsg', 'Deleted.', 'ok');
        });
      });
    });
  }
  function patchSvc(s, patch, action) {
    db.from('services').update(patch).eq('slug', s.slug).then(function (r) {
      if (r.error) { msg('svcListMsg', r.error.message, 'err'); return; }
      log(action, s.name, '');
      enterServices();
    });
  }
  function openSvc(s) {
    editingSvc = s || null;
    $('svcCat').innerHTML = CATS.map(function (k) { return '<option value="' + esc(k) + '">' + esc(k) + '</option>'; }).join('');
    $('svcTitle').textContent = s ? 'Edit service' : 'New service';
    $('svcCat').value = s ? s.category : CATS[0];
    $('svcName').value = s ? s.name : '';
    $('svcRate').value = s && s.rate != null ? Number(s.rate) : '';
    $('svcUnit').value = s ? (s.unit || '') : '';
    $('svcMin').value = s ? Math.max(1, Number(s.min_months || 1)) : 1;
    $('svcDetail').value = s ? (s.detail || '') : '';
    msg('svcMsg', '');
    /* Nothing is focused when the sheet opens: on a phone a field taking
       focus raises the keyboard and zooms the page past the rest of the
       form, and the first field is rarely the one somebody came to change. */
    openSheet('svcBox');
  }
  $('svcAdd').addEventListener('click', function () { openSvc(null); });
  $('svcCancel').addEventListener('click', function () { shutSheet('svcBox'); editingSvc = null; });
  $('svcSave').addEventListener('click', function () {
    var name = val('svcName');
    if (!name) { msg('svcMsg', 'A name is required.', 'err'); $('svcName').focus(); return; }
    var row = { category: $('svcCat').value, name: name,
                rate: val('svcRate') === '' ? null : Number(val('svcRate')), unit: val('svcUnit') || null,
                min_months: Math.max(1, Number(val('svcMin') || 1)), detail: val('svcDetail') || null };
    var after = function (r) {
      if (r.error) { msg('svcMsg', r.error.message, 'err'); return; }
      log(editingSvc ? 'service.changed' : 'service.added', name, row.category);
      shutSheet('svcBox'); editingSvc = null;
      enterServices();
    };
    if (editingSvc) { db.from('services').update(row).eq('slug', editingSvc.slug).then(after); return; }
    row.slug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || ('svc-' + Date.now());
    row.position = (catalog || []).length
      ? Math.max.apply(null, catalog.map(function (s) { return Number(s.position || 0); })) + 1 : 1;
    row.active = true;
    db.from('services').insert(row).then(after);
  });

  // ---- Entry --------------------------------------------------------------
  fillSelect($('crmStage'), STAGES.map(function (s) { return [s[0], s[1]]; }), 'Every stage');
  fillSelect($('crmIndustry'), INDUSTRIES.map(function (i) { return [i, i]; }), 'Not set');
  fillSelect($('crmSource'), SOURCES);
  /* Not fillSelect's "all" option: that is the filter idiom, and here the empty
     choice is a value that gets stored, so it is an empty string and saves as
     null like every other unset field. */
  $('crmCommence').innerHTML = '<option value="">Not set</option>' +
    COMMENCE.map(function (r) {
      return '<option value="' + esc(r[0]) + '">' + esc(r[1]) + '</option>';
    }).join('');

  window.ADspaceCRM = {
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
    byCode: byCode,
    bands: GROUPS,
    bandOf: function (stage) { return stageWord(stage || 'lead')[3]; },
    enter: function () {
      var params = new URLSearchParams(location.search);
      var key = params.get('client');
      loadTeam();
      if (key && !(state.client && (state.client.slug === key || state.client.id === key))) {
        clientByKey(key, function (c) {
          if (!c) { state.client = null; showList(); return; }
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
      db.from('clients').select('*').eq('stage', 'active').order('name')
        .then(function (r) { then(r.data || []); }, function () { then([]); });
    },
    billingMissing: billingMissing,
    // The rate card lives in this module because it is what a client's lines
    // are made of.
    enterServices: enterServices
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
  function loadDue() {
    var box = $('crmDueList');
    db.from('client_touches').select('*').not('next_action', 'is', null)
      .is('done_at', null).is('archived_at', null)
      .order('next_at', { ascending: true, nullsFirst: false }).limit(50)
      .then(function (r) {
        var rows = (r.data || []).filter(function (t) { return t.next_action; });
        // Soonest first, undated last.
        rows.sort(function (a, b) {
          if (a.next_at && b.next_at) return a.next_at < b.next_at ? -1 : a.next_at > b.next_at ? 1 : 0;
          return a.next_at ? -1 : b.next_at ? 1 : 0;
        });
        var byId = {};
        state.clients.forEach(function (c) { byId[c.id] = c; });
        $('crmDue').hidden = !rows.length;
        var over = rows.filter(function (t) { return t.next_at && t.next_at < today(); }).length;
        $('crmDueCount').textContent = rows.length + ' open' + (over ? ' · ' + over + ' overdue' : '');
        box.innerHTML = '';
        rows.forEach(function (t) {
          var c = byId[t.client_id];
          var due = t.next_at && t.next_at < today();
          var soon = !due && t.next_at && t.next_at <= new Date(Date.now() + 6 * 864e5).toISOString().slice(0, 10);
          var row = document.createElement('div');
          row.className = 'due-row' + (due ? ' is-due' : soon ? ' is-soon' : '');
          row.innerHTML =
            '<span class="due-when">' + esc(t.next_at ? niceDate(t.next_at) : 'No date') +
              (due ? '<em>overdue</em>' : soon ? '<em>this week</em>' : '') + '</span>' +
            '<button class="due-client" type="button">' + esc(c ? c.name : 'Client') + '</button>' +
            '<span class="due-what">' + esc(t.next_action) +
              (t.by_whom ? '<small>' + esc(t.by_whom) + '</small>' : '') + '</span>' +
            '<button class="btn btn-sm" data-a="done" type="button">Done</button>';
          row.querySelector('.due-client').addEventListener('click', function () { if (c) openClient(c); });
          row.querySelector('[data-a="done"]').addEventListener('click', function () {
            db.from('client_touches').update({ done_at: new Date().toISOString() }).eq('id', t.id)
              .then(function () {
                log('client.action_done', c ? c.name : '', t.next_action);
                undoBar('Marked done: ' + t.next_action, function () {
                  db.from('client_touches').update({ done_at: null }).eq('id', t.id).then(loadDue);
                });
                loadDue();
              });
          });
          box.appendChild(row);
        });
      }, function () { $('crmDue').hidden = true; });
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
