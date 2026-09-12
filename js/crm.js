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
  var setUrl = bridge.setUrl || function () {};
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
  var STAGES = [
    ['lead',      'Lead',          '',        'leads'],
    ['contacted', 'Contacted',     '',        'leads'],
    ['proposal',  'Proposal sent', 'is-warn', 'leads'],
    ['active',   'Active',        'is-ok',   'active'],
    ['paused',   'Paused',        'is-warn', 'ended'],
    ['past',     'Past',          '',        'ended']
  ];
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

  /* What an e-invoice needs. A client is not active until all of it is here.
     Field id, column, label. */
  var BILLING = [
    ['crmLegalName',        'legal_name',         'Company name as registered'],
    ['crmCompanyNo',        'company_no',         'Business registration no.'],
    ['crmCompanyNoOld',     'company_no_old',     'Old registration no.'],
    ['crmTin',              'tin',                'TIN'],
    ['crmSstNo',            'sst_no',             'SST registration no.'],
    ['crmBillContact',      'bill_contact',       'Contact person'],
    ['crmBillContactEmail', 'bill_contact_email', 'Contact person email'],
    ['crmBillContactPhone', 'bill_contact_phone', 'Contact person mobile'],
    ['crmFinanceEmail',     'finance_email',      'Finance department email'],
    ['crmBillAddr',         'billing_address',    'Company billing address']
  ];
  function billingMissing(c) {
    return BILLING.filter(function (f) { return !String(c[f[1]] || '').trim(); })
                  .map(function (f) { return f[2]; });
  }

  var state = { clients: [], team: [], client: null, editing: null, contacts: [], touches: [], services: [] };

  // ---- List ---------------------------------------------------------------
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
      $('crmTeamList').innerHTML = state.team.map(function (m) {
        return '<option value="' + esc(m.name) + '"></option>';
      }).join('');
      fillSelect($('crmOwner'), state.team.map(function (m) { return [m.name, m.name]; }), 'Everyone');
      if (then) then();
    }, function () { if (then) then(); });
  }

  function loadClients(then) {
    db.from('clients').select('*').order('name').then(function (r) {
      if (r.error) {
        $('crmList').innerHTML = '<div class="empty">Could not load clients. ' +
          esc(r.error.message) + '</div>';
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
    $('crmCount').textContent = rows.length + (rows.length === 1 ? ' client' : ' clients');
    var box = $('crmList');
    box.innerHTML = '';
    if (!rows.length) {
      box.innerHTML = '<div class="empty">' +
        (state.clients.length ? 'No client matches that.'
                              : 'No clients yet.') + '</div>';
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
      var sec = document.createElement('section');
      sec.className = 'crm-group';
      sec.innerHTML =
        '<div class="crm-group-head"><h3>' + esc(g[1]) + ' <span>' + mine.length + '</span></h3>' +
          (worthText ? '<span class="crm-group-worth">' + esc(worthText) + '</span>' : '') +
        '</div>' +
        '<div class="crm-table">' +
          '<div class="crm-head">' + ['Client', 'Stage', 'Industry', 'Value', 'Owner']
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
      '<span class="crm-c crm-c-stage"><span class="tone ' + w[2] + '">' + esc(w[1]) + '</span></span>' +
      '<span class="crm-c crm-c-ind">' + esc(c.industry || '—') + '</span>' +
      '<span class="crm-c crm-c-mkt">' + esc(c.deal_value ? MON.money(c.deal_value, c.market) : MON.market(c.market).sign) + '</span>' +
      '<span class="crm-c crm-c-own">' + esc(c.owner || 'Unassigned') + '</span>' +
      '<span class="crm-c crm-c-meta">' +
        [c.industry, MON.market(c.market).sign, c.owner || 'Unassigned']
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
    ['crmSource', 'source']
  ];
  /* The brand as a thing to open. Edited on the record, not at intake. */
  var BRAND = [
    ['crmWebsite', 'website'], ['crmPhone', 'phone'],
    ['crmSocialIg', 'social_ig'], ['crmSocialFb', 'social_fb'],
    ['crmSocialTiktok', 'social_tiktok'], ['crmSocialXhs', 'social_xhs']
  ];
  var SOURCES = [
    ['referral', 'Referral'], ['website', 'Website'], ['instagram', 'Instagram'],
    ['facebook', 'Facebook'], ['tiktok', 'TikTok'], ['rednote', 'RedNote'],
    ['whatsapp', 'WhatsApp'], ['walk_in', 'Walk-in'], ['event', 'Event'],
    ['outreach', 'Outreach'], ['other', 'Other']
  ];
  function sourceWord(v) {
    for (var i = 0; i < SOURCES.length; i++) if (SOURCES[i][0] === v) return SOURCES[i][1];
    return v || '';
  }
  var SV_STATE = { enquired: ['Enquired', ''], quoted: ['Quoted', 'is-warn'], confirmed: ['Confirmed', 'is-ok'] };
  var CATS = ['Content', 'Account management', 'Verification', 'Monthly packages',
              'KOC programmes', 'KOL programmes', 'Add-ons'];

  function openForm(c) {
    state.editing = c || null;
    $('crmFormTitle').textContent = c ? 'Edit client' : 'New lead';
    $('crmSave').textContent = c ? 'Save' : 'Add lead';
    FORM.forEach(function (f) { $(f[0]).value = c ? (c[f[1]] || '') : ''; });
    if (!c) $('crmSource').value = 'referral';
    $('crmMarket').value = c ? (c.market || 'MY') : 'MY';
    // The person who asked, and what for. Only a new lead needs this here.
    $('crmLeadOnly').hidden = Boolean(c);
    ['crmContactName', 'crmContactPhone', 'crmContactEmail', 'crmEnquiry'].forEach(function (id) { $(id).value = ''; });
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
    if (!state.editing) { patch.stage = 'lead'; patch.deal_note = val('crmEnquiry') || null; }

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

  // ---- One client ---------------------------------------------------------
  function openClient(c, restoring) {
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
      ['Owner',    c.owner || '<span class="muted">Unassigned</span>'],
      ['Industry', c.industry || '<span class="muted">Not set</span>'],
      ['Market',   (c.market === 'SG' ? 'Singapore' : 'Malaysia') + ' · ' + mk.sign],
      ['Value',    c.deal_value ? MON.money(c.deal_value, c.market) : '<span class="muted">Not set</span>'],
      ['Added',    c.created_at ? niceDate(c.created_at) : '']
    ].filter(function (f) { return f[1] !== ''; }).map(function (f) {
      return '<div><dt>' + f[0] + '</dt><dd>' +
        (String(f[1]).indexOf('<span') === 0 ? f[1] : esc(f[1])) + '</dd></div>';
    }).join('');

    // Website, phone and the social pages, as things to open rather than read.
    var links = [];
    if (c.website) links.push(linkChip(c.website, 'Website', true));
    if (c.phone)   links.push(linkChip('tel:' + c.phone, c.phone, false));
    [['social_ig', 'Instagram'], ['social_fb', 'Facebook'],
     ['social_tiktok', 'TikTok'], ['social_xhs', 'RedNote']].forEach(function (p) {
      if (c[p[0]]) links.push(linkChip(c[p[0]], p[1], true));
    });
    $('crmLinks').innerHTML = links.join('');

    // The gate, stated once, with what is missing.
    var missing = billingMissing(c);
    $('crmGate').hidden = c.stage === 'active' || c.stage === 'past';
    $('crmGateText').textContent = missing.length
      ? 'Billing details required before Active: ' + missing.join(', ') + '.'
      : 'Billing details complete. Set the stage to Active from Edit.';

    BILLING.forEach(function (f) { $(f[0]).value = c[f[1]] || ''; });
    $('crmSstApplies').checked = c.sst_applies !== false;
    $('crmSstLabel').textContent = 'Charge ' + MON.taxLabel() + ' on this client\'s quotes';
    $('crmBillSummary').textContent = missing.length
      ? missing.length + ' of ' + BILLING.length + ' still needed' : 'Complete';
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
    loadTouches();
    loadWork();
    setUrl();
    if (restoring) restoreScroll();
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
        setOpen('crmBillToggle', 'crmBillBody', true);
        msg('crmBillMsg', 'Billing details required before Active: ' + missing.join(', ') + '.', 'err');
        var first = BILLING.filter(function (f) { return missing.indexOf(f[2]) > -1; })[0];
        if (first && $(first[0])) $(first[0]).focus();
        return;
      }
    }
    db.from('clients').update({ stage: to }).eq('id', c.id).then(function (r) {
      if (r.error) { msg('crmWorkMsg', r.error.message, 'err'); openClient(c); return; }
      c.stage = to;
      var mine = state.clients.filter(function (x) { return x.id === c.id; })[0];
      if (mine) mine.stage = to;
      log('client.edited', c.name, to);
      openClient(c);
    });
  });

  // ---- Billing and notes --------------------------------------------------
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
        ? 'Saved. Still required: ' + still.join(', ') + '.'
        : 'Saved. Billing details complete.',
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
    box.innerHTML = '<div class="empty">Loading…</div>';
    db.from('client_contacts').select('*').eq('client_id', state.client.id)
      .order('is_primary', { ascending: false }).order('name').then(function (r) {
        if (r.error) { box.innerHTML = '<div class="empty">Could not load contacts.</div>'; return; }
        var all = r.data || [];
        state.contacts = all.filter(function (c) { return !c.archived_at; });
        var gone = all.filter(function (c) { return c.archived_at; });
        $('crmContactNames').innerHTML = state.contacts.map(function (ct) {
          return '<option value="' + esc(ct.name) + '"></option>';
        }).join('');
        box.innerHTML = '';
        if (!state.contacts.length) {
          box.innerHTML = '<div class="empty">No contacts.</div>';
        }
        state.contacts.forEach(function (ct) { box.appendChild(contactRow(ct, false)); });
        if (gone.length) {
          var t = document.createElement('button');
          t.type = 'button'; t.className = 'linkish crm-removed-toggle';
          t.textContent = (showRemovedContacts ? 'Hide ' : 'Show ') + gone.length +
            ' removed contact' + (gone.length === 1 ? '' : 's');
          t.addEventListener('click', function () { showRemovedContacts = !showRemovedContacts; loadContacts(); });
          box.appendChild(t);
          if (showRemovedContacts) gone.forEach(function (ct) { box.appendChild(contactRow(ct, true)); });
        }
      });
  }

  function contactRow(ct, removed) {
    var row = document.createElement('div');
    row.className = 'kcard' + (removed ? ' is-off' : '');
    var wa = String(ct.whatsapp || ct.phone || '').replace(/[^0-9]/g, '');
    row.innerHTML =
      '<header class="kcard-head">' +
        '<span class="kcard-name">' + esc(ct.name) + '</span>' +
        (removed ? '<span class="tone">Removed</span>' : '') +
        (ct.is_primary && !removed ? '<span class="tone is-ok">Main contact</span>' : '') +
        (ct.role ? '<span class="tone">' + esc(ct.role) + '</span>' : '') +
        '<span class="crm-lang">Writes in ' + esc(LANG_WORD[ct.lang] || 'English') + '</span>' +
        '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' +
          '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>' +
        '</button>' +
      '</header>' +
      '<div class="kmenu" data-menu hidden>' +
        (removed
          ? '<button class="kmenu-item" data-a="restore" type="button"><b>Restore</b></button>'
          : '<button class="kmenu-item" data-a="edit" type="button"><b>Edit</b></button>' +
            (ct.is_primary ? '' :
              '<button class="kmenu-item" data-a="primary" type="button"><b>Main contact</b></button>') +
            '<button class="kmenu-item is-danger" data-a="del" data-soft type="button"><b>Remove</b></button>') +
      '</div>' +
      '<div class="kstep kstep-terms">' +
        '<span class="kstep-label">Reach</span>' +
        '<span class="crm-reach">' +
          (ct.phone ? '<a class="plink" href="tel:' + esc(ct.phone) + '">' + esc(ct.phone) + '</a>' : '') +
          (wa ? '<a class="plink" href="https://wa.me/' + esc(wa) + '" target="_blank" rel="noopener">WhatsApp</a>' : '') +
          (ct.email ? '<a class="plink" href="mailto:' + esc(ct.email) + '">' + esc(ct.email) + '</a>' : '') +
          (!ct.phone && !ct.email ? '<span class="muted">Nothing recorded</span>' : '') +
        '</span>' +
      '</div>';
    wireMenu(row);
    var on = function (a, fn) { var el = row.querySelector('[data-a="' + a + '"]'); if (el) el.addEventListener('click', fn); };
    on('edit',    function () { openContact(ct); });
    on('primary', function () { makePrimary(ct); });
    on('del',     function () { archiveContact(ct, true); });
    on('restore', function () { archiveContact(ct, false); });
    return row;
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
        var r = btn.getBoundingClientRect();
        menu.style.position = 'fixed';
        menu.style.top = (r.bottom + 4) + 'px';
        menu.style.right = 'auto';
        menu.style.left = Math.max(8, r.right - menu.offsetWidth) + 'px';
      }
    });
  }
  window.addEventListener('scroll', function () {
    Array.prototype.forEach.call(document.querySelectorAll('.team-act .kmenu'), function (m) { m.hidden = true; });
  }, true);

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
    box.innerHTML = '<div class="empty">Loading…</div>';
    db.from('client_touches').select('*').eq('client_id', state.client.id)
      .order('happened_at', { ascending: false }).order('created_at', { ascending: false })
      .then(function (r) {
        if (r.error) { box.innerHTML = '<div class="empty">Could not load the log.</div>'; return; }
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
          state.client.stage = 'contacted';
          var mine = state.clients.filter(function (x) { return x.id === state.client.id; })[0];
          if (mine) mine.stage = 'contacted';
          log('client.edited', state.client.name, 'contacted');
          openClient(state.client);
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
  var CAMP_WORD = { draft: 'Draft', open: 'With the client', production: 'In production',
                    completed: 'Completed' };

  function loadWork() {
    var box = $('crmWorkList');
    box.innerHTML = '<div class="empty">Loading…</div>';
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
        location.href = '/admin/?s=review&client=' + encodeURIComponent(c.id);
      });
    });
    var go = $('crmGoReview');
    if (go) go.addEventListener('click', function () {
      location.href = '/admin/?s=review&client=' + encodeURIComponent(c.id);
    });
    $('crmGoCampaign').addEventListener('click', function () {
      location.href = '/admin/?s=campaigns&new=' + encodeURIComponent(c.id);
    });

    if (!sets.length && !camps.length) {
      box.innerHTML = '<div class="empty">No engagements.</div>';
      return;
    }
    box.innerHTML = '';
    camps.forEach(function (k) {
      box.appendChild(workRow(k.title, 'Creator campaign · ' + (CAMP_WORD[k.state] || k.state) +
        ' · ' + k.slots + ' creator' + (k.slots === 1 ? '' : 's'), '/admin/?s=campaigns&campaign=' + encodeURIComponent(k.id)));
    });
    sets.forEach(function (b) {
      box.appendChild(workRow(b.title || 'Content set',
        'Content Review · ' + (b.state === 'published' ? 'With the client' : 'Draft'),
        '/admin/?s=review&client=' + encodeURIComponent(c.id) + '&set=' + encodeURIComponent(b.id)));
    });
  }

  function workRow(title, meta, href) {
    var row = document.createElement('button');
    row.type = 'button';
    row.className = 'work-row';
    row.innerHTML =
      '<span class="work-row-name">' + esc(title) + '</span>' +
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
  // qty × rate × months. A one-off line has one month.
  function amountOf(l) { return Number(l.qty || 0) * Number(l.rate || 0) * Math.max(1, Number(l.tenure || 1)); }
  function monthWord(ym) {
    if (!ym) return '';
    var d = new Date(String(ym).slice(0, 7) + '-01T00:00:00');
    return isNaN(d.getTime()) ? String(ym) : d.toLocaleDateString('en-GB', { month: 'short', year: 'numeric' });
  }
  function termWord(l) {
    var n = Math.max(1, Number(l.tenure || 1));
    if (n === 1 && !l.start_on) return '';
    return (n > 1 ? n + ' months' : '') + (l.start_on ? (n > 1 ? ' from ' : 'From ') + monthWord(l.start_on) : '');
  }

  function loadServices() {
    var box = $('crmServices');
    box.innerHTML = '<div class="empty">Loading…</div>';
    loadCatalog(function () {
      db.from('client_services').select('*').eq('client_id', state.client.id)
        .is('archived_at', null).order('created_at').then(function (r) {
          if (r.error) { box.innerHTML = '<div class="empty">' + esc(r.error.message) + '</div>'; return; }
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
    rows.forEach(function (l) { table.appendChild(serviceRow(l)); });
    var sum = function (st) {
      return rows.filter(function (l) { return l.state === st; }).reduce(function (s, l) { return s + amountOf(l); }, 0);
    };
    var quoted = sum('quoted'), confirmed = sum('confirmed');
    var tot = document.createElement('div');
    tot.className = 'csv-total';
    tot.innerHTML =
      (quoted ? '<span>Quoted<b>' + esc(MON.money2(quoted, c.market)) + '</b></span>' : '') +
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
        (l.note || l.unit || termWord(l) ? '<small>' + esc([l.unit, termWord(l), l.note].filter(Boolean).join(' · ')) + '</small>' : '') + '</span>' +
      '<span class="svc-state"><select class="select select-sm state-select ' +w[1] + '" data-f="state" aria-label="State">' +
        Object.keys(SV_STATE).map(function (k) {
          return '<option value="' + k + '"' + (k === l.state ? ' selected' : '') + '>' + esc(SV_STATE[k][0]) + '</option>';
        }).join('') + '</select></span>' +
      '<span class="svc-rate">' + esc(Number(l.qty) + ' × ' + MON.money2(l.rate, c.market) +
        (Number(l.tenure || 1) > 1 ? ' × ' + Number(l.tenure) + ' mo' : '')) + '</span>' +
      '<span class="svc-rate"><b>' + esc(MON.money2(amountOf(l), c.market)) + '</b></span>' +
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
    if (fill && s) $('svRate').value = s.rate != null ? Number(s.rate) : '';
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
      state: $('svState').value, note: val('svNote') || null
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

  // ---- Documents ------------------------------------------------------------
  /* Quotations and invoices issued from the lines above. A quotation takes
     quoted and confirmed lines; an invoice takes confirmed lines and needs an
     Active client with billing complete. Each is kept as issued. */
  var DOCS = window.ADspaceDocs;
  var DOC_WORD = { quotation: 'Quotation', invoice: 'Invoice' };

  function loadDocuments() {
    var box = $('crmDocuments');
    var c = state.client;
    $('crmInvoice').hidden = !(c.stage === 'active' && !billingMissing(c).length);
    if (!DOCS) { box.innerHTML = ''; return; }
    box.innerHTML = '<div class="empty">Loading…</div>';
    DOCS.list(c.id, function (rows, err) {
      if (err) { box.innerHTML = '<div class="empty">' + esc(err.message || err) + '</div>'; return; }
      box.innerHTML = '';
      if (!rows.length) { box.innerHTML = '<div class="empty">No documents.</div>'; return; }
      var table = document.createElement('div');
      table.className = 'crm-table';
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
      '<span class="svc-state"><select class="select select-sm state-select ' +(d.voided_at ? 'is-off' : 'is-ok') + '" data-f="state" aria-label="State">' +
        '<option value="issued"' + (d.voided_at ? '' : ' selected') + '>Issued</option>' +
        '<option value="void"' + (d.voided_at ? ' selected' : '') + '>Void</option></select></span>' +
      '<span class="svc-rate"><b>' + esc(MON.money2(d.total, d.market)) + '</b></span>' +
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

  function issueDoc(kind) {
    if (!DOCS) return;
    msg('crmDocMsg', '');
    DOCS.issue(kind, state.client, state.services, function (r) {
      if (r.error) { msg('crmDocMsg', r.error, 'err'); return; }
      msg('crmDocMsg', r.warn ? r.doc.number + ' issued. ' + r.warn : r.doc.number + ' issued.', r.warn ? 'warn' : 'ok');
      loadDocuments();
    });
  }
  $('crmQuote').addEventListener('click', function () { issueDoc('quotation'); });
  $('crmInvoice').addEventListener('click', function () { issueDoc('invoice'); });

  // ---- Rate card (the Services section) ------------------------------------
  var editingSvc = null;
  function isAdmin() { return Boolean(bridge.may && bridge.may('admin')); }
  function enterServices() {
    catalog = null;
    $('svcAdd').hidden = !isAdmin();
    $('svcBox').hidden = true;
    msg('svcListMsg', '');
    $('svcList').innerHTML = '<div class="empty">Loading…</div>';
    loadCatalog(paintCatalog);
  }
  function paintCatalog() {
    var box = $('svcList');
    box.innerHTML = '';
    var rows = catalog || [];
    if (!rows.length) { box.innerHTML = '<div class="empty">No services.</div>'; return; }
    // Two tables, not a card per category: what is sold, and what is added
    // to it. Categories are sub-headings inside each.
    var extra = rows.map(function (s) { return s.category; })
      .filter(function (k, i, a) { return CATS.indexOf(k) < 0 && a.indexOf(k) === i; });
    var TIERS = [
      ['Services', ['Content', 'Account management', 'Monthly packages', 'KOC programmes', 'KOL programmes'].concat(extra)],
      ['Add-ons',  ['Verification', 'Add-ons']]
    ];
    TIERS.forEach(function (t) {
      var cats = t[1].filter(function (k) { return rows.some(function (s) { return s.category === k; }); });
      if (!cats.length) return;
      var n = rows.filter(function (s) { return cats.indexOf(s.category) > -1; }).length;
      var sec = document.createElement('section');
      sec.className = 'crm-group';
      sec.innerHTML = '<div class="crm-group-head"><h3>' + esc(t[0]) + ' <span>' + n + '</span></h3></div>' +
        '<div class="crm-table"></div>';
      var table = sec.querySelector('.crm-table');
      cats.forEach(function (k) {
        var cat = document.createElement('div');
        cat.className = 'svc-cat';
        cat.textContent = k;
        table.appendChild(cat);
        rows.filter(function (s) { return s.category === k; }).forEach(function (s) { table.appendChild(catalogRow(s)); });
      });
      box.appendChild(sec);
    });
  }
  function catalogRow(s) {
    var row = document.createElement('div');
    row.className = 'svc-row' + (s.active === false ? ' is-off' : '');
    row.innerHTML =
      '<span class="svc-name"><b>' + esc(s.name) + '</b>' + (s.note ? '<small>' + esc(s.note) + '</small>' : '') + '</span>' +
      '<span class="svc-rate">' + (s.rate != null ? esc(MON.money2(s.rate, 'MY')) : '<span class="muted">On quote</span>') + '</span>' +
      '<span class="svc-unit">' + esc(s.unit || '') + '</span>' +
      '<span class="svc-state">' + (isAdmin()
        ? '<select class="select select-sm state-select ' +(s.active === false ? 'is-off' : 'is-ok') + '" data-f="active" aria-label="State">' +
            '<option value="on"' + (s.active === false ? '' : ' selected') + '>Active</option>' +
            '<option value="off"' + (s.active === false ? ' selected' : '') + '>Retired</option></select>'
        : (s.active === false ? '<span class="tone">Retired</span>' : '')) + '</span>' +
      '<span class="team-act">' + (isAdmin()
        ? '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
          '<div class="kmenu" data-menu hidden>' +
            '<button class="kmenu-item" data-a="edit" type="button"><b>Edit</b></button>' +
          '</div>'
        : '') + '</span>';
    row.classList.add('cat-row');
    if (isAdmin()) {
      wireMenu(row);
      row.querySelector('[data-a="edit"]').addEventListener('click', function () { openSvc(s); });
      row.querySelector('[data-f="active"]').addEventListener('change', function () {
        var on = this.value === 'on';
        patchSvc(s, { active: on }, on ? 'service.on' : 'service.off');
      });
    }
    return row;
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
                rate: val('svcRate') === '' ? null : Number(val('svcRate')), unit: val('svcUnit') || null };
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

  window.ADspaceCRM = {
    urlState: function () { return { client: state.client ? state.client.id : '' }; },
    enter: function () {
      var params = new URLSearchParams(location.search);
      var id = params.get('client');
      loadTeam();
      if (id && !(state.client && state.client.id === id)) {
        db.from('clients').select('*').eq('id', id).single().then(function (r) {
          if (r.error || !r.data) { state.client = null; showList(); return; }
          openClient(r.data, true);
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
