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
  var bridge = window.ADspaceAdmin || {};
  var log = bridge.log || function () {};
  var actor = bridge.actor || function () { return ''; };
  var actorName = bridge.actorName || actor;
  var setUrl = bridge.setUrl || function () {};
  /* A pane is a move somebody made, not a note of where the page ended up, so
     it pushes a history entry and Back and Forward walk the record. */
  var pushUrl = bridge.pushUrl || setUrl;
  var restoreScroll = bridge.restoreScroll || function () {};
  var MON = window.ADspaceMoney;

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
                ['active', 'active'], ['paused', 'ended'], ['past', 'ended']]
    .map(function (g) { return [g[0], W.en.stage[g[0]], W.tone(g[0]), g[1]]; });
  var GROUPS = [
    ['leads',  'Leads'],
    ['active', 'Active clients'],
    ['ended',  'Paused and past']
  ];
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

  /* The journey, left to right, as one line: how long each stage took and how
     long the current one has been running. Read from the stamped history, not
     from the activity record, because the record is a log of what people did
     and this is a fact about the client. */
  function journeyOf(c) {
    var log = (c && c.stage_log) || [];
    /* A record whose history predates the clock still knows when its current
       stage began, so it says that much rather than nothing. */
    if (!log.length && c && c.stage_since) log = [{ stage: c.stage || 'lead', at: c.stage_since }];
    if (!log.length) return '';
    var out = [];
    for (var i = 0; i < log.length; i++) {
      var at = Date.parse(log[i].at);
      if (isNaN(at)) continue;
      var next = i + 1 < log.length ? Date.parse(log[i + 1].at) : Date.now();
      var days = Math.max(0, Math.floor((next - at) / 86400000));
      var word = stageWord(log[i].stage)[1];
      /* The stage it is in now is running, so it reads as a duration so far;
         a stage that is over reads as how long it took. "Same day so far" was
         both at once and said neither. */
      var last = i + 1 === log.length;
      if (last) out.push(word + ' ' + (days === 0 ? 'today' : spanWord(days).toLowerCase() + ' so far'));
      else out.push(word + ' ' + (days === 0 ? 'same day' : spanWord(days).toLowerCase()));
    }
    return out.join('  ·  ');
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
  function ring(done, total) {
    var r = 8, len = 2 * Math.PI * r, off = len * (1 - (total ? done / total : 0));
    return '<span class="ringline"><svg class="ring' + (done >= total ? ' is-ok' : '') + '" viewBox="0 0 20 20" aria-hidden="true">' +
      '<circle class="ring-track" cx="10" cy="10" r="' + r + '"/>' +
      '<circle class="ring-arc" cx="10" cy="10" r="' + r + '" stroke-dasharray="' + len.toFixed(2) + '" stroke-dashoffset="' + off.toFixed(2) + '"/>' +
      '</svg>' + (done >= total ? 'Complete' : done + ' of ' + total) + '</span>';
  }

  var state = { clients: [], team: [], client: null, editing: null, contacts: [], touches: [], services: [] };

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
      if (then) then();
    });
  }

  function visible() {
    var q = val('crmSearch').toLowerCase();
    var stage = $('crmStage').value;
    var owner = $('crmOwner').value;
    return state.clients.filter(function (c) {
      if (q && String(c.name || '').toLowerCase().indexOf(q) < 0 &&
               String(c.legal_name || '').toLowerCase().indexOf(q) < 0) return false;
      if (stage !== 'all' && (c.stage || 'lead') !== stage) return false;
      if (owner !== 'all' && (c.owner || '') !== owner) return false;
      return true;
    });
  }

  function paintList() {
    var rows = visible();
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
         answers, so each carries its own way out. */
      box.innerHTML = '<div class="softpanel"><div class="emptyline">' +
        (state.clients.length
          ? '<b>No matches.</b><button class="btn btn-sm" data-a="clear" type="button">Clear the filters</button>'
          : '<b>No clients yet.</b><button class="btn btn-sm" data-a="first" type="button">Add the first lead</button>') +
        '</div></div>';
      var clear = box.querySelector('[data-a="clear"]');
      if (clear) clear.addEventListener('click', function () {
        $('crmSearch').value = ''; $('crmStage').value = 'all'; $('crmOwner').value = 'all';
        paintList();
      });
      var first = box.querySelector('[data-a="first"]');
      if (first) first.addEventListener('click', function () { $('crmNew').click(); });
      return;
    }
    GROUPS.forEach(function (g) {
      var mine = rows.filter(function (c) { return stageWord(c.stage || 'lead')[3] === g[0]; });
      if (!mine.length) return;
      // What the group is worth, per currency, so the pipeline has a number.
      var worth = {};
      mine.forEach(function (c) {
        if (!c.deal_value) return;
        var k = c.market || 'MY';
        worth[k] = (worth[k] || 0) + Number(c.deal_value);
      });
      var worthText = Object.keys(worth).map(function (k) { return MON.money(worth[k], k); }).join(' + ');
      var late = mine.filter(isStale).length;
      var sec = document.createElement('section');
      sec.className = 'crm-group';
      sec.innerHTML =
        '<div class="crm-group-head"><h3>' + esc(g[1]) + ' <span>' + mine.length + '</span></h3>' +
          /* The count that makes somebody open the group, next to the one
             that says how big it is. Absent where none has gone over, so a
             healthy stage stays quiet. */
          (late ? '<span class="tone is-warn">' + late + ' overdue</span>' : '') +
          (worthText ? '<span class="crm-group-worth">' + esc(worthText) + '</span>' : '') +
        '</div>' +
        '<div class="crm-table softpanel">' +
          '<div class="crm-head">' + ['Client', 'Stage', 'Industry', 'Value', 'Person in charge']
            .map(function (h) { return '<span>' + h + '</span>'; }).join('') + '</div>' +
        '</div>';
      var table = sec.querySelector('.crm-table');
      mine.forEach(function (c) { table.appendChild(listRow(c)); });
      box.appendChild(sec);
    });
  }

  /* A column per fact, because that is what every CRM anyone here has used
     looks like, and because the eye scans a column far faster than it scans
     a chip stranded at the other end of a wide row. */
  function listRow(c) {
    var w = stageWord(c.stage || 'lead');
    var row = document.createElement('button');
    row.type = 'button';
    row.className = 'crm-row';
    row.innerHTML =
      '<span class="crm-c crm-c-name">' + esc(c.name || '') + '</span>' +
      '<span class="crm-c crm-c-stage"><span class="tone ' + w[2] + '">' + esc(w[1]) + '</span>' +
        /* The word carries it, not the colour: the mark has to survive a
           greyscale print and a reader who cannot tell warn from mute. */
        (ageWord(c) ? '<small class="crm-age' + (isStale(c) ? ' is-late' : '') + '">' +
          esc(ageWord(c) + (isStale(c) ? ' · Overdue' : '')) + '</small>' : '') + '</span>' +
      '<span class="crm-c crm-c-ind">' + esc(c.industry || '—') + '</span>' +
      '<span class="crm-c crm-c-mkt">' + (c.deal_value ? esc(MON.money(c.deal_value, c.market)) : '<span class="muted">' + esc(MON.market(c.market).sign) + '</span>') + '</span>' +
      '<span class="crm-c crm-c-own">' + esc(c.owner || 'Unassigned') + '</span>' +
      /* The one line the phone gets, so it carries the value rather than the
         currency it would be in. A bare RM with no amount is a fragment that
         reads like a broken field, and it was shown even where the client had
         a figure: the desktop column had the money and the phone line threw it
         away for its sign. What is not known is left out rather than stood in
         for, so the line is two or three facts, never a row of placeholders. */
      '<span class="crm-c crm-c-meta">' +
        [c.industry, c.deal_value ? MON.money(c.deal_value, c.market) : '', c.owner]
          .filter(Boolean).map(esc).join(' · ') +
      '</span>';
    row.addEventListener('click', function () { openClient(c); });
    return row;
  }

  ['crmSearch', 'crmStage', 'crmOwner'].forEach(function (id) {
    $(id).addEventListener('input', paintList);
    $(id).addEventListener('change', paintList);
  });

  // ---- Create and edit ----------------------------------------------------
  /* The head of the record: who they are and where they came from. */
  var FORM = [
    ['crmName', 'name'], ['crmIndustry', 'industry'], ['crmOwnerPick', 'owner'],
    ['crmSource', 'source'], ['crmCommence', 'commence']
  ];
  /* The brand as a thing to open. Edited on the record, not at intake. */
  var BRAND = [
    ['crmWebsite', 'website'], ['crmPhone', 'phone'],
    ['crmSocialIg', 'social_ig'], ['crmSocialFb', 'social_fb'],
    ['crmSocialTiktok', 'social_tiktok'], ['crmSocialXhs', 'social_xhs']
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

  function openForm(c) {
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
    ['crmContactName', 'crmContactPhone', 'crmContactEmail'].forEach(function (id) { $(id).value = ''; });
    // What they asked for is a fact about the client, so editing shows it.
    $('crmEnquiry').value = c ? (c.deal_note || '') : '';
    msg('crmMsg', '');
    // Editing happens on the record, in place of its head; adding happens on
    // the list. One form, moved to where the person is.
    var box = $('crmAddBox');
    if (c) {
      var head = $('crmWork').querySelector('section.panel');
      $('crmWork').insertBefore(box, head);
      head.hidden = true;
    } else {
      $('crmListView').insertBefore(box, $('crmDue'));
    }
    box.hidden = false;
    $('crmName').focus();
  }
  function shutForm() {
    $('crmAddBox').hidden = true;
    var head = $('crmWork').querySelector('section.panel');
    if (head) head.hidden = false;
    state.editing = null;
  }
  $('crmNew').addEventListener('click', function () { openForm(null); });
  $('crmCancel').addEventListener('click', shutForm);

  $('crmSave').addEventListener('click', function () {
    var name = val('crmName');
    if (!name) { msg('crmMsg', 'A client needs a name.', 'err'); $('crmName').focus(); return; }
    var patch = { market: $('crmMarket').value };
    FORM.forEach(function (f) { patch[f[1]] = val(f[0]) || null; });
    patch.name = name;
    // A lead is a person who asked for something. The stage lives on the
    // record's head, not here.
    var contactName = state.editing ? '' : val('crmContactName');
    if (!state.editing && !contactName) { msg('crmMsg', 'A contact person is required.', 'err'); $('crmContactName').focus(); return; }
    patch.deal_note = val('crmEnquiry') || null;
    if (!state.editing) patch.stage = 'lead';

    if (state.editing) {
      var id = state.editing.id;
      db.from('clients').update(patch).eq('id', id).then(function (r) {
        if (r.error) { msg('crmMsg', r.error.message, 'err'); return; }
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
      var phone = val('crmContactPhone');
      db.from('client_contacts').insert({
        client_id: r.data.id, name: contactName, phone: phone || null, whatsapp: phone || null,
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
    if (!same) state.contacts = [];
    state.client = c;
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

    var mk = MON.market(c.market);
    $('crmFacts').innerHTML = [
      ['Source',   c.source ? sourceWord(c.source) : '<span class="muted">Not set</span>'],
      ['Person in charge', c.owner || '<span class="muted">Unassigned</span>'],
      ['Industry', c.industry || '<span class="muted">Not set</span>'],
      ['Market',   (c.market === 'SG' ? 'Singapore' : 'Malaysia') + ' · ' + mk.sign],
      ['Value',    c.deal_value ? MON.money(c.deal_value, c.market) : '<span class="muted">Not set</span>'],
      ['To commence', c.commence ? commenceWord(c.commence) : '<span class="muted">Not set</span>'],
      ['Added',    c.created_at ? niceDate(c.created_at) : '']
    ].filter(function (f) { return f[1] !== ''; }).map(function (f) {
      return '<div><dt>' + f[0] + '</dt><dd>' +
        (String(f[1]).indexOf('<span') === 0 ? f[1] : esc(f[1])) + '</dd></div>';
    }).join('');

    var trip = journeyOf(c);
    $('crmJourney').textContent = trip;
    $('crmJourney').hidden = !trip;

    // Website, phone and the social pages, as things to open rather than read.
    var links = [];
    if (c.website) links.push(linkChip(c.website, 'Website', true));
    if (c.phone)   links.push(linkChip('tel:' + c.phone, c.phone, false));
    [['social_ig', 'Instagram'], ['social_fb', 'Facebook'],
     ['social_tiktok', 'TikTok'], ['social_xhs', 'rednote']].forEach(function (p) {
      if (c[p[0]]) links.push(linkChip(c[p[0]], p[1], true));
    });
    $('crmLinks').innerHTML = links.join('');

    BILLING.forEach(function (f) { $(f[0]).value = c[f[1]] || ''; });
    $('crmSstApplies').checked = c.sst_applies !== false;
    $('crmSstLabel').textContent = 'Charge ' + MON.taxLabel() + ' on this client\'s quotes';
    paintBilling(c);
    BRAND.forEach(function (f) { $(f[0]).value = c[f[1]] || ''; });
    $('crmNotes').value = c.brand_notes || '';
    var linksOn = BRAND.filter(function (f) { return c[f[1]]; }).length;
    $('crmBrandSummary').textContent =
      [linksOn ? linksOn + ' link' + (linksOn === 1 ? '' : 's') : '', c.brand_notes ? 'Notes' : '']
        .filter(Boolean).join(' · ') || 'Empty';
    setOpen('crmBillToggle', 'crmBillBody', false);
    setOpen('crmBrandToggle', 'crmBrandBody', false);
    msg('crmWorkMsg', ''); msg('crmBillMsg', ''); msg('crmBrandMsg', ''); msg('crmServiceMsg', '');
    shutContact();
    shutTouch();
    shutService();
    loadContacts();
    loadServices();
    loadDocuments();
    loadRequests();
    loadTouches();
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
  var PANES = ['overview', 'contacts', 'billing', 'brand', 'services', 'documents', 'activity'];
  var pane = 'overview';

  function paneFromUrl() {
    var t = new URLSearchParams(location.search).get('tab') || '';
    return PANES.indexOf(t) >= 0 ? t : 'overview';
  }

  function showPane(key) {
    if (PANES.indexOf(key) < 0) key = 'overview';
    pane = key;
    Array.prototype.forEach.call(document.querySelectorAll('#crmTabs .tab'), function (b) {
      var on = b.getAttribute('data-pane') === key;
      b.classList.toggle('is-on', on);
      b.setAttribute('aria-selected', String(on));
    });
    Array.prototype.forEach.call(document.querySelectorAll('.rec-pane'), function (el) {
      el.hidden = el.getAttribute('data-pane') !== key;
    });
    /* A fold inside its own pane is furniture: the pane is the disclosure. */
    if (key === 'billing') setOpen('crmBillToggle', 'crmBillBody', true);
    if (key === 'brand') setOpen('crmBrandToggle', 'crmBrandBody', true);
    if (key === 'activity') loadClientLog();
  }

  Array.prototype.forEach.call(document.querySelectorAll('#crmTabs .tab'), function (b) {
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
        if (!rows.length) { box.innerHTML = '<div class="empty">No entries.</div>'; return; }
        var t = document.createElement('div');
        t.className = 'crm-table softpanel';
        t.innerHTML = '<div class="crm-head svc-row log-row"><span>When</span><span>What</span>' +
          '<span>Detail</span><span>Who</span></div>';
        rows.forEach(function (x) {
          var el = document.createElement('div');
          el.className = 'svc-row log-row';
          el.innerHTML =
            '<span class="log-when">' + esc(niceDate(x.created_at)) + '</span>' +
            '<span class="log-what">' + esc(logWord(x.action)) + '</span>' +
            '<span class="log-detail">' + esc(x.detail || '') + '</span>' +
            '<span class="log-who">' + esc(x.actor || '') + '</span>';
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

  function linkChip(href, label, external) {
    var url = /^https?:\/\/|^tel:|^mailto:/.test(href) ? href : 'https://' + href.replace(/^@/, '');
    return '<a class="plink" href="' + esc(url) + '"' +
      (external ? ' target="_blank" rel="noopener"' : '') + '>' + esc(label) + '</a>';
  }

  $('crmBack').addEventListener('click', function () {
    state.client = null;
    showList();          // the list and the next actions above it, together
  });
  $('crmEdit').addEventListener('click', function () {
    if (!state.clients.length) loadClients();
    openForm(state.client);
  });

  /* The one rule with teeth: nobody becomes active until they can be
     invoiced. The select goes back and the record opens on what is missing. */
  $('crmClientStage').addEventListener('change', function () {
    var c = state.client, to = this.value, was = c.stage || 'lead';
    if (to === was) return;
    if (to === 'active') {
      var missing = billingMissing(c);
      if (missing.length) {
        this.value = was;
        /* The refusal has to land where the fix is: the Billing pane, with
           the fold open and the first missing field focused. Opening a fold
           that is two panes away is a message about a screen nobody is on. */
        showPane('billing');
        setUrl();
        setOpen('crmBillToggle', 'crmBillBody', true);
        msg('crmBillMsg', 'Billing details required before Active: ' + missing.join(', ') + '.', 'err');
        var first = BILLING.filter(function (f) { return missing.indexOf(f[2]) > -1; })[0];
        if (first && $(first[0])) $(first[0]).focus();
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
    $('crmGate').hidden = c.stage === 'active' || c.stage === 'past';
    $('crmGateText').textContent = missing.length
      ? 'Billing details required before Active: ' + missing.join(', ') + '.'
      : 'Billing details complete.';
    $('crmBillSummary').innerHTML = ring(BILLING_REQUIRED.length - missing.length, BILLING_REQUIRED.length);
    var pick = billContact(c);
    $('crmBillContact').innerHTML = '<option value="">None</option>' + (state.contacts || []).map(function (ct) {
      return '<option value="' + esc(ct.id) + '"' + (pick && pick.id === ct.id ? ' selected' : '') + '>' + esc(ct.name) +
        (ct.is_primary ? ' · Main contact' : '') + '</option>';
    }).join('');
  }

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
      openClient(state.client);
      setOpen('crmBillToggle', 'crmBillBody', true);
      msg('crmBillMsg', still.length
        ? 'Saved. Required before Active: ' + still.join(', ') + '.'
        : 'Saved.',
        still.length ? 'warn' : 'ok');
    });
  });

  $('crmBrandSave').addEventListener('click', function () {
    var patch = { brand_notes: val('crmNotes') || null };
    BRAND.forEach(function (f) { patch[f[1]] = val(f[0]) || null; });
    db.from('clients').update(patch).eq('id', state.client.id)
      .then(function (r) {
        if (r.error) { msg('crmBrandMsg', r.error.message, 'err'); return; }
        Object.keys(patch).forEach(function (k) { state.client[k] = patch[k]; });
        log('client.brand', state.client.name, '');
        openClient(state.client);
        setOpen('crmBrandToggle', 'crmBrandBody', true);
        msg('crmBrandMsg', 'Saved.', 'ok');
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
  function contactRow(ct, removed) {
    var row = document.createElement('div');
    row.className = 'svc-row ct-row' + (removed ? ' is-off' : '');
    var wa = String(ct.whatsapp || ct.phone || '').replace(/[^0-9]/g, '');
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
        (wa ? '<a class="plink" href="https://wa.me/' + esc(wa) + '" target="_blank" rel="noopener">WhatsApp</a>' : '') +
        (ct.email ? '<a class="plink" href="mailto:' + esc(ct.email) + '">' + esc(ct.email) + '</a>' : '') +
      '</span>' +
      '<span class="team-act">' +
        '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
        '<div class="kmenu" data-menu hidden>' +
          (removed
            ? '<button class="kmenu-item" data-a="restore" type="button"><b>Restore</b></button>' +
              /* The hard delete, once the soft one has been made. No data-soft,
                 so body.no-remove hides it from anyone whose group does not
                 carry can_remove: an admin's by default. */
              '<button class="kmenu-item is-danger" data-a="del" type="button"><b>Delete permanently</b></button>'
            : '<button class="kmenu-item" data-a="edit" type="button"><b>Edit</b></button>' +
              (ct.is_primary ? '' :
                '<button class="kmenu-item" data-a="primary" type="button"><b>Main contact</b></button>') +
              (ct.portal_access
                ? '<button class="kmenu-item" data-a="invite" type="button"><b>Send invitation</b></button>' +
                  '<button class="kmenu-item" data-a="unportal" type="button"><b>Revoke portal access</b></button>'
                : '<button class="kmenu-item" data-a="portal" type="button"><b>Enable portal access</b></button>') +
              '<button class="kmenu-item is-danger" data-a="del" data-soft type="button"><b>Remove</b></button>') +
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
    if (!confirm('Send a sign-in invitation to ' + ct.email + '?')) return;
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
    $('crmContactBox').hidden = false;
    $('crmContactTitle').textContent = ct ? 'Edit contact' : 'New contact';
    $('ctSave').textContent = 'Save';
    $('ctName').value = ct ? (ct.name || '') : '';
    $('ctRole').value = ct ? (ct.role || '') : '';
    $('ctPhone').value = ct ? (ct.phone || '') : '';
    $('ctEmail').value = ct ? (ct.email || '') : '';
    $('ctLang').value = ct ? (ct.lang || 'en') : 'en';
    $('ctPrimary').checked = ct ? Boolean(ct.is_primary) : !state.contacts.length;
    msg('ctMsg', '');
    $('ctName').focus();
  }
  function shutContact() { $('crmContactBox').hidden = true; editingContact = null; }
  $('crmAddContact').addEventListener('click', function () { openContact(null); });
  $('ctCancel').addEventListener('click', shutContact);

  $('ctSave').addEventListener('click', function () {
    var name = val('ctName');
    if (!name) { msg('ctMsg', 'A contact needs a name.', 'err'); $('ctName').focus(); return; }
    var phone = val('ctPhone');
    var row = {
      name: name, role: val('ctRole') || null, phone: phone || null, whatsapp: phone || null,
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
    if (!confirm('Delete ' + ct.name + ' permanently?\n\nThis cannot be undone. Calls, letters and requests keep the name as it was written.')) return;
    db.from('client_contacts').delete().eq('id', ct.id).then(function (r) {
      if (r.error) { msg('crmWorkMsg', r.error.message, 'err'); return; }
      log('contact.deleted', state.client.name + ' · ' + ct.name, ct.email || '');
      msg('crmWorkMsg', 'Deleted.', 'ok');
      loadContacts();
      loadRequests();
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
            '<button class="btn btn-quiet btn-sm" data-a="edit" type="button">Edit</button>' +
            '<button class="btn btn-quiet btn-sm is-danger" data-a="del" type="button">Remove</button>') +
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
    $('crmTouchBox').hidden = false;
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
    $('tcSummary').focus();
  }
  function shutTouch() { $('crmTouchBox').hidden = true; editingTouch = null; }
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

  // ---- Disclosures --------------------------------------------------------
  function disclose(toggleId, bodyId) {
    var t = $(toggleId), b = $(bodyId);
    if (!t || !b) return;
    t.addEventListener('click', function () {
      var open = b.hidden;
      b.hidden = !open;
      t.setAttribute('aria-expanded', String(open));
      t.classList.toggle('is-open', open);
    });
  }
  function setOpen(toggleId, bodyId, open) {
    $(bodyId).hidden = !open;
    $(toggleId).setAttribute('aria-expanded', String(open));
    $(toggleId).classList.toggle('is-open', open);
  }
  disclose('crmBillToggle', 'crmBillBody');
  disclose('crmBrandToggle', 'crmBrandBody');

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
  function rateOf(l) { return MON.rateFor(l.rate, l.tenure); }
  function amountOf(l) { return Number(l.qty || 0) * rateOf(l) * Math.max(1, Number(l.tenure || 1)); }
  /* A start kept as a month (older lines) reads as its first day. */
  function startDay(s) { s = String(s || ''); return s.length === 7 ? s + '-01' : s; }
  function termWord(l) {
    var n = Math.max(1, Number(l.tenure || 1));
    if (n === 1 && !l.start_on) return '';
    return (n > 1 ? n + ' months' : '') + (l.start_on ? (n > 1 ? ' from ' : 'From ') + niceDate(startDay(l.start_on)) : '');
  }
  // Named where the figure changes, so a rate that is not the rate card's is
  // never something the reader has to work out for themselves.
  function adjWord(l) { return MON.termWord(l.tenure); }

  function loadServices() {
    var box = $('crmServices');
    if (!box.querySelector('.crm-table')) skeleton(box, 3);
    loadCatalog(function () {
      db.from('client_services').select('*').eq('client_id', state.client.id)
        .is('archived_at', null).order('created_at').then(function (r) {
          if (r.error) { failLine(box, 'Services', r.error.message, loadServices); return; }
          state.services = r.data || [];
          paintServices();
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
      '<span class="svc-state"><select class="select select-sm state-select ' +w[1] + '" data-f="state" aria-label="State">' +
        Object.keys(SV_STATE).map(function (k) {
          return '<option value="' + k + '"' + (k === l.state ? ' selected' : '') + '>' + esc(SV_STATE[k][0]) + '</option>';
        }).join('') + '</select></span>' +
      '<span class="team-act">' +
        '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
        '<div class="kmenu" data-menu hidden>' +
          '<button class="kmenu-item" data-a="edit" type="button"><b>Edit</b></button>' +
          '<button class="kmenu-item is-danger" data-a="del" data-soft type="button"><b>Remove</b></button>' +
        '</div>' +
      '</span>';
    wireMenu(row);
    var on = function (a, fn) { var el = row.querySelector('[data-a="' + a + '"]'); if (el) el.addEventListener('click', fn); };
    on('edit', function () { openService(l); });
    row.querySelector('[data-f="state"]').addEventListener('change', function () { saveService(l, { state: this.value }); });
    on('del', function () { saveService(l, { archived_at: new Date().toISOString() }, true); });
    return row;
  }

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
  }
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
      syncPick(!l);
      msg('svMsg', '');
      $('crmServiceBox').hidden = false;
      $('svPick').focus();
    });
  }
  function shutService() { $('crmServiceBox').hidden = true; editingService = null; }
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
      detail: val('svDetail') || null
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
    $('crmReplyBox').hidden = false;
    $('rqFee').focus();
  }
  function shutReply() { $('crmReplyBox').hidden = true; replying = null; }
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

  function loadDocuments() {
    var box = $('crmDocuments');
    var c = state.client;
    if (!DOCS) { box.innerHTML = ''; return; }
    if (!box.querySelector('.crm-table')) skeleton(box, 2);
    DOCS.list(c.id, function (rows, err) {
      if (err) { failLine(box, 'Documents', err.message || String(err), loadDocuments); return; }
      box.innerHTML = '';
      if (!rows.length) { box.innerHTML = '<div class="empty">No documents.</div>'; return; }
      var table = document.createElement('div');
      table.className = 'crm-table';
      table.innerHTML = '<div class="crm-head svc-row doc-row"><span>Document</span><span class="svc-rate">Total</span><span>State</span><span></span></div>';
      rows.forEach(function (d) { table.appendChild(documentRow(d)); });
      box.appendChild(table);
    });
  }

  function documentRow(d) {
    var row = document.createElement('div');
    row.className = 'svc-row doc-row' + (d.voided_at ? ' is-off' : '');
    row.innerHTML =
      '<span class="svc-name"><b>' + esc(d.number) + '</b><small>' + esc(DOC_WORD[d.kind] || d.kind) + ' · ' + esc(niceDate(d.issued_at)) +
        (d.issued_by ? ' · ' + esc(d.issued_by) : '') + '</small></span>' +
      '<span class="svc-rate svc-amt"><b>' + esc(MON.money2(d.total, d.market)) + '</b></span>' +
      '<span class="svc-state"><select class="select select-sm state-select ' +(d.voided_at ? 'is-off' : 'is-ok') + '" data-f="state" aria-label="State">' +
        '<option value="issued"' + (d.voided_at ? '' : ' selected') + '>Issued</option>' +
        '<option value="void"' + (d.voided_at ? ' selected' : '') + '>Void</option></select></span>' +
      '<span class="team-act">' +
        '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
        '<div class="kmenu" data-menu hidden>' +
          '<button class="kmenu-item" data-a="download" type="button"><b>Download</b></button>' +
          (d.voided_at ? '<button class="kmenu-item is-danger" data-a="del" type="button"><b>Delete</b></button>' : '') +
        '</div>' +
      '</span>';
    wireMenu(row);
    var on = function (a, fn) { var el = row.querySelector('[data-a="' + a + '"]'); if (el) el.addEventListener('click', fn); };
    on('download', function () { DOCS.download(d, function (warn) { if (warn) msg('crmDocMsg', warn, 'err'); }); });
    row.querySelector('[data-f="state"]').addEventListener('change', function () {
      var toVoid = this.value === 'void';
      DOCS.setVoid(d, toVoid, function (err) {
        if (err) { msg('crmDocMsg', err.message, 'err'); loadDocuments(); return; }
        if (toVoid) undoBar(d.number + ' voided.', function () { DOCS.setVoid(d, false, loadDocuments); });
        loadDocuments();
      });
    });
    // A voided document can go for good. The number is not reused.
    on('del', function () {
      if (!confirm('Delete ' + d.number + '?')) return;
      DOCS.remove(d, function (err) {
        if (err) { msg('crmDocMsg', err.message, 'err'); return; }
        loadDocuments();
      });
    });
    return row;
  }

  $('crmCover').addEventListener('click', function () {
    if (!DOCS) return;
    msg('crmDocMsg', '');
    var c = state.client;
    var deal = {
      owner: c.owner || '', source: c.source ? sourceWord(c.source) : '', industry: c.industry || '',
      stage: stageWord(c.stage || 'lead')[1], enquiry: c.deal_note || '',
      finance_email: c.finance_email || '', sst_no: c.sst_no || '', company_no_old: c.company_no_old || ''
    };
    DOCS.issue('offer', c, billContact(c), state.services, deal, function (r) {
      if (r.error) { msg('crmDocMsg', r.error, 'err'); return; }
      msg('crmDocMsg', r.warn ? r.doc.number + ' issued. ' + r.warn : r.doc.number + ' issued.', r.warn ? 'warn' : 'ok');
      loadDocuments();
    });
  });

  // ---- Rate card (the Services section) ------------------------------------
  var editingSvc = null;
  function isAdmin() { return Boolean(bridge.may && bridge.may('admin')); }
  /* What is typed in the command bar. Kept out of the URL: a search is what
     somebody is doing this minute, not where they are. */
  var svcFind = '', svcCat = '';

  function enterServices() {
    catalog = null;
    $('svcAdd').hidden = !isAdmin();
    $('svcBox').hidden = true;
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
        (isAdmin() ? '<button class="btn btn-sm" data-a="first" type="button">Add the first service</button>' : '') +
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

    // Two tables, not a card per category: what is sold, and what is added
    // to it. Categories are sub-headings inside each.
    svcTiers(all).forEach(function (t) {
      var cats = t[1].filter(function (k) { return rows.some(function (s) { return s.category === k; }); });
      if (!cats.length) return;
      var n = rows.filter(function (s) { return cats.indexOf(s.category) > -1; }).length;
      var sec = document.createElement('section');
      sec.className = 'crm-group';
      sec.innerHTML = '<div class="crm-group-head"><h3>' + esc(t[0]) + ' <span>' + n + '</span></h3></div>' +
        '<div class="crm-table softpanel"><div class="crm-head svc-row cat-row">' +
        '<span>Service</span><span class="svc-rate">Rate</span>' +
        '<span>Unit</span><span></span></div></div>';
      var table = sec.querySelector('.crm-table');
      cats.forEach(function (k) {
        var cat = document.createElement('div');
        cat.className = 'svc-cat';
        cat.textContent = k;
        table.appendChild(cat);
        rows.filter(function (s) { return s.category === k; })
            .forEach(function (s) { table.appendChild(catalogRow(s)); });
      });
      box.appendChild(sec);
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
      '<span class="team-act">' + (isAdmin()
        ? '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
          '<div class="kmenu" data-menu hidden>' +
            '<button class="kmenu-item" data-a="edit" type="button"><b>Edit</b></button>' +
            // Taking a line off the card is a decision of the year, not a select.
            '<button class="kmenu-item" data-a="state" type="button"><b>' +
              (off ? 'Set active' : 'Set inactive') + '</b></button>' +
            /* Inactive first, then gone, as it is for a letter and a contact:
               a line is taken off the card before it can be taken out of it.
               No data-soft, so body.no-remove holds it back from a group that
               does not carry can_remove. */
            (off ? '<button class="kmenu-item is-danger" data-a="del" type="button"><b>Delete permanently</b></button>' : '') +
          '</div>'
        : '') + '</span>';
    row.classList.add('cat-row');
    if (isAdmin()) {
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
      if (!confirm('Delete ' + s.name + ' permanently?\n\nThis cannot be undone. Letters already issued keep the line as it was written.')) return;
      db.from('services').delete().eq('slug', s.slug).then(function (r) {
        if (r.error) { msg('svcListMsg', r.error.message, 'err'); return; }
        log('service.deleted', s.name, s.category || '');
        enterServices();
        msg('svcListMsg', 'Deleted.', 'ok');
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
    $('svcBox').hidden = false;
    $('svcName').focus();
  }
  $('svcAdd').addEventListener('click', function () { openSvc(null); });
  $('svcCancel').addEventListener('click', function () { $('svcBox').hidden = true; editingSvc = null; });
  $('svcSave').addEventListener('click', function () {
    var name = val('svcName');
    if (!name) { msg('svcMsg', 'A name is required.', 'err'); $('svcName').focus(); return; }
    var row = { category: $('svcCat').value, name: name,
                rate: val('svcRate') === '' ? null : Number(val('svcRate')), unit: val('svcUnit') || null,
                min_months: Math.max(1, Number(val('svcMin') || 1)), detail: val('svcDetail') || null };
    var after = function (r) {
      if (r.error) { msg('svcMsg', r.error.message, 'err'); return; }
      log(editingSvc ? 'service.changed' : 'service.added', name, row.category);
      $('svcBox').hidden = true; editingSvc = null;
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

  if (bridge.crmReady) bridge.crmReady();
})();
