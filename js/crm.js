/*
 * Clients — the CRM.
 *
 * A client used to be a name typed into a box, created from wherever it was
 * first needed. Content Review made one, Creator Campaigns made another, and
 * both wrote to the same table without either being the place a client
 * actually lives. This is that place. The other sections point at it.
 *
 * Content Review publishes deliverables. Creator Campaigns runs campaigns.
 * Neither creates a company; they pick one from here.
 */
(function () {
  var API = window.ADspaceAPI;
  var db  = API && API.client;
  if (!API || !API.configured || !db) return;

  var $ = function (id) { return document.getElementById(id); };
  var bridge = window.ADspaceAdmin || {};
  var log = bridge.log || function () {};
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

  /* Stage is the one word that tells the team how to treat someone. A lead and
     a paying client sit on the same list precisely so nobody keeps a second
     list somewhere else. */
  var STAGES = [
    ['lead',     'Lead',          ''],
    ['proposal', 'Proposal sent', 'is-warn'],
    ['active',   'Active',        'is-ok'],
    ['paused',   'Paused',        'is-warn'],
    ['past',     'Past',          '']
  ];
  var INDUSTRIES = ['Property', 'F&B', 'Retail', 'Wellness', 'Lifestyle',
                    'Automotive', 'Tech', 'Education', 'Other'];

  function stageWord(v) {
    for (var i = 0; i < STAGES.length; i++) if (STAGES[i][0] === v) return STAGES[i];
    return [v, v || 'Lead', ''];
  }

  var state = { clients: [], team: [], client: null, editing: null, contacts: [] };

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
    var q = ($('crmSearch').value || '').trim().toLowerCase();
    var stage = $('crmStage').value;
    var owner = $('crmOwner').value;
    return state.clients.filter(function (c) {
      if (q && String(c.name || '').toLowerCase().indexOf(q) < 0) return false;
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
                              : 'No clients yet. Add the first one above.') + '</div>';
      return;
    }
    rows.forEach(function (c) {
      var w = stageWord(c.stage || 'lead');
      var row = document.createElement('button');
      row.type = 'button';
      row.className = 'crm-row';
      row.innerHTML =
        '<span class="crm-row-name">' + esc(c.name || '') + '</span>' +
        '<span class="tone ' + w[2] + '">' + esc(w[1]) + '</span>' +
        '<span class="crm-row-meta">' +
          [c.industry, MON.market(c.market).sign, c.owner].filter(Boolean).map(esc).join(' · ') +
        '</span>';
      row.addEventListener('click', function () { openClient(c); });
      box.appendChild(row);
    });
  }

  ['crmSearch', 'crmStage', 'crmOwner'].forEach(function (id) {
    $(id).addEventListener('input', paintList);
    $(id).addEventListener('change', paintList);
  });

  // ---- Create and edit ----------------------------------------------------
  function openForm(c) {
    state.editing = c || null;
    $('crmFormTitle').textContent = c ? 'Edit client' : 'New client';
    $('crmSave').textContent = c ? 'Save changes' : 'Add client';
    $('crmName').value = c ? (c.name || '') : '';
    $('crmFormStage').value = c ? (c.stage || 'lead') : 'lead';
    $('crmIndustry').value = c ? (c.industry || '') : '';
    $('crmOwnerPick').value = c ? (c.owner || '') : '';
    $('crmMarket').value = c ? (c.market || 'MY') : 'MY';
    msg('crmMsg', '');
    $('crmAddBox').hidden = false;
    $('crmName').focus();
  }
  function shutForm() {
    $('crmAddBox').hidden = true;
    state.editing = null;
  }
  $('crmNew').addEventListener('click', function () { openForm(null); });
  $('crmCancel').addEventListener('click', shutForm);

  $('crmSave').addEventListener('click', function () {
    var name = ($('crmName').value || '').trim();
    if (!name) { msg('crmMsg', 'A client needs a name.', 'err'); $('crmName').focus(); return; }
    var patch = {
      name: name,
      stage: $('crmFormStage').value,
      industry: $('crmIndustry').value || null,
      owner: ($('crmOwnerPick').value || '').trim() || null,
      market: $('crmMarket').value
    };
    if (state.editing) {
      var id = state.editing.id;
      db.from('clients').update(patch).eq('id', id).then(function (r) {
        if (r.error) { msg('crmMsg', r.error.message, 'err'); return; }
        log('client.edited', name, patch.stage);
        shutForm();
        loadClients(function () {
          var found = state.clients.filter(function (x) { return x.id === id; })[0];
          if (state.client && found) openClient(found);
        });
      });
      return;
    }
    // Every client carries its own review link from the moment it exists, so
    // Content Review has nothing left to create.
    patch.access_token = token();
    db.from('clients').insert(patch).select().single().then(function (r) {
      if (r.error) { msg('crmMsg', r.error.message, 'err'); return; }
      log('client.added', name, patch.stage);
      shutForm();
      loadClients(function () { openClient(r.data); });
    });
  });

  // ---- One client ---------------------------------------------------------
  function openClient(c, restoring) {
    state.client = c;
    $('crmListView').hidden = true;
    $('crmWork').hidden = false;
    $('crmClientName').textContent = c.name || '';
    var w = stageWord(c.stage || 'lead');
    $('crmClientStage').textContent = w[1];
    $('crmClientStage').className = 'chip' + (w[2] === 'is-ok' ? ' is-live' : '');

    var mk = MON.market(c.market);
    $('crmFacts').innerHTML = [
      ['Industry', c.industry || '<span class="muted">Not set</span>'],
      ['Market',   (c.market === 'SG' ? 'Singapore' : 'Malaysia') + ' · ' + mk.sign],
      ['Owner',    c.owner || '<span class="muted">Unassigned</span>'],
      ['Tax',      c.sst_applies === false ? 'Not charged' : MON.taxLabel()],
      ['Added',    c.created_at ? niceDate(String(c.created_at).slice(0, 10)) : '']
    ].filter(function (f) { return f[1] !== ''; }).map(function (f) {
      return '<div><dt>' + f[0] + '</dt><dd>' +
        (String(f[1]).indexOf('<span') === 0 ? f[1] : esc(f[1])) + '</dd></div>';
    }).join('');

    $('crmCompanyNo').value = c.company_no || '';
    $('crmSstNo').value = c.sst_no || '';
    $('crmBillAddr').value = c.billing_address || '';
    $('crmSstApplies').checked = c.sst_applies !== false;
    $('crmSstLabel').textContent = 'Charge ' + MON.taxLabel() + ' on this client\'s quotes';
    $('crmBillSummary').textContent = c.company_no ? 'On file' : 'Not entered';
    $('crmNotes').value = c.brand_notes || '';
    $('crmNotesSummary').textContent = c.brand_notes ? 'Written' : 'None yet';
    setOpen('crmBillToggle', 'crmBillBody', false);
    setOpen('crmNotesToggle', 'crmNotesBody', false);
    msg('crmWorkMsg', ''); msg('crmBillMsg', ''); msg('crmNotesMsg', '');
    shutContact();
    loadContacts();
    loadWork();
    setUrl();
    if (restoring) restoreScroll();
  }

  function niceDate(d) {
    if (!d) return '';
    var dt = new Date(d + 'T00:00:00');
    if (isNaN(dt.getTime())) return String(d);
    return dt.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
  }

  $('crmBack').addEventListener('click', function () {
    state.client = null;
    $('crmWork').hidden = true;
    $('crmListView').hidden = false;
    setUrl();
    loadClients();
  });
  $('crmEdit').addEventListener('click', function () {
    $('crmWork').hidden = true;
    $('crmListView').hidden = false;
    openForm(state.client);
  });

  // ---- Contacts -----------------------------------------------------------
  function loadContacts() {
    var box = $('crmContacts');
    box.innerHTML = '<div class="empty">Loading…</div>';
    db.from('client_contacts').select('*').eq('client_id', state.client.id)
      .order('is_primary', { ascending: false }).order('name').then(function (r) {
        if (r.error) {
          box.innerHTML = '<div class="empty">Could not load contacts.</div>';
          return;
        }
        state.contacts = r.data || [];
        if (!state.contacts.length) {
          box.innerHTML = '<div class="empty">No one recorded yet. A company does not ' +
            'answer the phone; add the person who does.</div>';
          return;
        }
        box.innerHTML = '';
        state.contacts.forEach(function (ct) { box.appendChild(contactRow(ct)); });
      });
  }

  var LANG_WORD = { en: 'English', zh: '中文', ms: 'Bahasa Malaysia' };

  function contactRow(ct) {
    var row = document.createElement('div');
    row.className = 'kcard';
    var wa = String(ct.whatsapp || ct.phone || '').replace(/[^0-9]/g, '');
    row.innerHTML =
      '<header class="kcard-head">' +
        '<span class="kcard-name">' + esc(ct.name) + '</span>' +
        (ct.is_primary ? '<span class="tone is-ok">Main contact</span>' : '') +
        (ct.role ? '<span class="tone">' + esc(ct.role) + '</span>' : '') +
        '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' +
          '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>' +
        '</button>' +
      '</header>' +
      '<div class="kmenu" data-menu hidden>' +
        (ct.is_primary ? '' :
          '<button class="kmenu-item" data-a="primary" type="button"><b>Make main contact</b>' +
          '<span>The person we deal with by default.</span></button>') +
        '<button class="kmenu-item is-danger" data-a="del" type="button"><b>Remove contact</b>' +
        '<span>They have left, or were entered twice.</span></button>' +
      '</div>' +
      '<div class="kstep kstep-terms">' +
        '<span class="kstep-label">Reach</span>' +
        '<span class="crm-reach">' +
          (ct.phone ? '<a class="plink" href="tel:' + esc(ct.phone) + '">' + esc(ct.phone) + '</a>' : '') +
          (wa ? '<a class="plink" href="https://wa.me/' + esc(wa) + '" target="_blank" rel="noopener">WhatsApp</a>' : '') +
          (ct.email ? '<a class="plink" href="mailto:' + esc(ct.email) + '">' + esc(ct.email) + '</a>' : '') +
          (!ct.phone && !ct.email ? '<span class="muted">Nothing recorded</span>' : '') +
        '</span>' +
        '<span class="kstep-note">Writes in ' + esc(LANG_WORD[ct.lang] || 'English') + '</span>' +
      '</div>';

    var menu = row.querySelector('[data-menu]');
    row.querySelector('[data-a="menu"]').addEventListener('click', function () {
      var open = menu.hidden;
      Array.prototype.forEach.call(document.querySelectorAll('.kmenu'), function (m) { m.hidden = true; });
      menu.hidden = !open;
      this.setAttribute('aria-expanded', String(open));
    });
    var prim = row.querySelector('[data-a="primary"]');
    if (prim) prim.addEventListener('click', function () { makePrimary(ct); });
    row.querySelector('[data-a="del"]').addEventListener('click', function () { dropContact(ct); });
    return row;
  }

  function openContact() {
    $('crmContactBox').hidden = false;
    ['ctName', 'ctRole', 'ctPhone', 'ctEmail'].forEach(function (id) { $(id).value = ''; });
    $('ctLang').value = 'en';
    $('ctPrimary').checked = !state.contacts.length;   // the first one is the main one
    msg('ctMsg', '');
    $('ctName').focus();
  }
  function shutContact() { $('crmContactBox').hidden = true; }
  $('crmAddContact').addEventListener('click', openContact);
  $('ctCancel').addEventListener('click', shutContact);

  $('ctSave').addEventListener('click', function () {
    var name = ($('ctName').value || '').trim();
    if (!name) { msg('ctMsg', 'A contact needs a name.', 'err'); $('ctName').focus(); return; }
    var phone = ($('ctPhone').value || '').trim();
    var row = {
      client_id: state.client.id, name: name,
      role: ($('ctRole').value || '').trim() || null,
      phone: phone || null, whatsapp: phone || null,
      email: ($('ctEmail').value || '').trim() || null,
      lang: $('ctLang').value,
      is_primary: $('ctPrimary').checked
    };
    var go = function () {
      db.from('client_contacts').insert(row).then(function (r) {
        if (r.error) { msg('ctMsg', r.error.message, 'err'); return; }
        log('contact.added', state.client.name + ' · ' + name, row.role || '');
        shutContact();
        loadContacts();
      });
    };
    // Only one person can be the main one, so stand the others down first.
    if (row.is_primary && state.contacts.length) clearPrimary(go); else go();
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

  function dropContact(ct) {
    if (!confirm('Remove ' + ct.name + ' from ' + state.client.name + '?')) return;
    db.from('client_contacts').delete().eq('id', ct.id).then(function (r) {
      if (r.error) { msg('crmWorkMsg', r.error.message, 'err'); return; }
      log('contact.removed', state.client.name + ' · ' + ct.name, '');
      loadContacts();
    });
  }

  // ---- What is live with them --------------------------------------------
  function loadWork() {
    var box = $('crmWorkList');
    box.innerHTML = '<div class="empty">Loading…</div>';
    var id = state.client.id;
    var out = { sets: null, camps: null };
    var done = function () {
      if (out.sets === null || out.camps === null) return;
      paintWork(out.sets, out.camps);
    };
    db.from('batches').select('id, title, state, created_at').eq('client_id', id)
      .order('created_at', { ascending: false }).limit(20)
      .then(function (r) { out.sets = r.data || []; done(); },
            function () { out.sets = []; done(); });
    db.from('campaigns').select('id, title, state, slots, created_at').eq('client_id', id)
      .order('created_at', { ascending: false }).limit(20)
      .then(function (r) { out.camps = r.data || []; done(); },
            function () { out.camps = []; done(); });
  }

  var CAMP_WORD = { draft: 'Draft', open: 'With the client', production: 'In production',
                    completed: 'Completed' };

  function paintWork(sets, camps) {
    var box = $('crmWorkList');
    $('crmTally').innerHTML =
      statCell('Content sets', sets.length) +
      statCell('Campaigns', camps.length) +
      statCell('Contacts', state.contacts.length);
    if (!sets.length && !camps.length) {
      box.innerHTML = '<div class="empty">Nothing running for them yet. Content sets and ' +
        'creator campaigns made for this client appear here.</div>';
      return;
    }
    box.innerHTML = '';
    camps.forEach(function (c) {
      box.appendChild(workRow(c.title, 'Creator campaign · ' + (CAMP_WORD[c.state] || c.state) +
        ' · ' + c.slots + ' slots', 'campaigns', c.id));
    });
    sets.forEach(function (b) {
      box.appendChild(workRow(b.title || 'Content set',
        'Content Review · ' + (b.state === 'published' ? 'With the client' : 'Draft'),
        'review', b.id));
    });
  }

  function statCell(label, value) {
    return '<div class="stat"><b>' + esc(String(value)) + '</b><span>' + esc(label) + '</span></div>';
  }

  function workRow(title, meta, section, id) {
    var row = document.createElement('button');
    row.type = 'button';
    row.className = 'crm-row';
    row.innerHTML =
      '<span class="crm-row-name">' + esc(title) + '</span>' +
      '<span class="crm-row-meta">' + esc(meta) + '</span>';
    row.addEventListener('click', function () {
      // Hand over to the section that owns this work, on the item itself.
      var q = section === 'campaigns' ? '?s=campaigns&campaign=' + encodeURIComponent(id)
                                      : '?s=review&client=' + encodeURIComponent(state.client.id);
      location.href = '/admin/' + q;
    });
    return row;
  }

  // ---- Billing and notes --------------------------------------------------
  $('crmBillSave').addEventListener('click', function () {
    var patch = {
      company_no: ($('crmCompanyNo').value || '').trim() || null,
      sst_no: ($('crmSstNo').value || '').trim() || null,
      billing_address: ($('crmBillAddr').value || '').trim() || null,
      sst_applies: $('crmSstApplies').checked
    };
    db.from('clients').update(patch).eq('id', state.client.id).then(function (r) {
      if (r.error) { msg('crmBillMsg', r.error.message, 'err'); return; }
      Object.keys(patch).forEach(function (k) { state.client[k] = patch[k]; });
      log('client.billing', state.client.name, patch.sst_applies ? 'tax on' : 'tax off');
      msg('crmBillMsg', 'Saved.', 'ok');
      $('crmBillSummary').textContent = patch.company_no ? 'On file' : 'Not entered';
      openClient(state.client);
      setOpen('crmBillToggle', 'crmBillBody', true);
    });
  });

  $('crmNotesSave').addEventListener('click', function () {
    var notes = ($('crmNotes').value || '').trim() || null;
    db.from('clients').update({ brand_notes: notes }).eq('id', state.client.id)
      .then(function (r) {
        if (r.error) { msg('crmNotesMsg', r.error.message, 'err'); return; }
        state.client.brand_notes = notes;
        msg('crmNotesMsg', 'Saved.', 'ok');
        $('crmNotesSummary').textContent = notes ? 'Written' : 'None yet';
      });
  });

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
  disclose('crmNotesToggle', 'crmNotesBody');

  // ---- Entry --------------------------------------------------------------
  fillSelect($('crmStage'), STAGES.map(function (s) { return [s[0], s[1]]; }), 'Every stage');
  fillSelect($('crmFormStage'), STAGES.map(function (s) { return [s[0], s[1]]; }));
  fillSelect($('crmIndustry'), INDUSTRIES.map(function (i) { return [i, i]; }), 'Not set');

  window.ADspaceCRM = {
    urlState: function () {
      return { client: state.client ? state.client.id : '' };
    },
    /* On entry the address is read before it is written, so a refresh inside a
       client lands back inside it rather than in front of the list. */
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
    // Other sections ask for the list rather than keeping one of their own.
    clients: function () { return state.clients.slice(); }
  };

  function showList() {
    $('crmWork').hidden = true;
    $('crmListView').hidden = false;
    setUrl();
    loadClients(function () { restoreScroll(); });
  }

  if (bridge.crmReady) bridge.crmReady();
})();
