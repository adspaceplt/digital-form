/*
 * Creator Campaigns — Package II only.
 *
 * Sales agrees the package and raises the invoice. The KOC team takes it from
 * there: sources creators, offers more options than there are slots, shares one
 * link, and runs the engagement to completion.
 *
 * Package I never appears here. It is a fixed set with nothing to choose.
 */
(function () {
  var API = window.ADspaceAPI;
  var db  = API && API.client;
  if (!db) return;

  var bridge = window.ADspaceAdmin || {};
  var ICON    = bridge.ICON || {};
  var iconBtn = bridge.iconBtn || function () { return ''; };
  var log     = bridge.log || function () {};
  var who     = bridge.actor || function () { return ''; };

  var $ = function (id) { return document.getElementById(id); };
  function esc(s) {
    return String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  }
  function msg(id, text, kind) {
    var n = $(id); if (!n) return;
    n.textContent = text || ''; n.className = 'msg' + (kind ? ' ' + kind : '');
  }
  function token() {
    var a = new Uint8Array(12);
    crypto.getRandomValues(a);
    return Array.from(a, function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
  }
  function money(n) {
    return 'RM ' + Number(n || 0).toLocaleString('en-MY', { minimumFractionDigits: 0 });
  }

  /* ---- Platforms -------------------------------------------------------
     Each platform states the shape of a profile URL and where the identity
     sits inside it. That identity is what makes two links the same creator;
     a short link has none, so it can be stored but never matched. */
  var PLATFORMS = [
    { id: 'xhs',       label: 'RedNote',   re: /xiaohongshu\.com\/user\/profile\/([0-9a-zA-Z]{8,40})/i },
    { id: 'xhs',       label: 'RedNote',   re: /xhslink\.(?:com|cn)\/\S+/i, anonymous: true },
    { id: 'instagram', label: 'Instagram', re: /instagram\.com\/([A-Za-z0-9._]{1,40})/i },
    { id: 'tiktok',    label: 'TikTok',    re: /tiktok\.com\/@([A-Za-z0-9._]{1,40})/i },
    { id: 'facebook',  label: 'Facebook',  re: /facebook\.com\/([A-Za-z0-9.]{2,60})/i }
  ];
  var PLATFORM_LABEL = { xhs: 'RedNote', instagram: 'Instagram', tiktok: 'TikTok', facebook: 'Facebook' };

  /* Returns what a URL is, or null when it is not a profile we recognise.
     handle null means "recognised the platform, could not read an identity",
     which is exactly the xhslink case. */
  function readProfile(url) {
    var v = String(url || '').trim();
    if (!v) return null;
    if (!/^https?:\/\//i.test(v)) v = 'https://' + v;
    for (var i = 0; i < PLATFORMS.length; i++) {
      var p = PLATFORMS[i];
      var m = v.match(p.re);
      if (m) return { platform: p.id, url: v, handle: p.anonymous ? null : (m[1] || null) };
    }
    return null;
  }

  var state = { tab: 'campaigns', campaign: null, creators: [], clients: [], options: [], editing: null };

  // ---- Tabs ---------------------------------------------------------------
  function showTab(name) {
    state.tab = name;
    $('campListView').hidden = !(name === 'campaigns' && !state.campaign);
    $('campWork').hidden     = !(name === 'campaigns' && state.campaign);
    $('rosterView').hidden   = name !== 'roster';
    Array.prototype.forEach.call(document.querySelectorAll('#sectionCampaigns .tab'), function (b) {
      b.classList.toggle('is-on', b.getAttribute('data-tab') === name);
    });
    if (name === 'roster') loadRoster();
    if (name === 'campaigns' && !state.campaign) loadCampaigns();
  }
  Array.prototype.forEach.call(document.querySelectorAll('#sectionCampaigns .tab'), function (b) {
    b.addEventListener('click', function () { showTab(b.getAttribute('data-tab')); });
  });

  // ---- Roster -------------------------------------------------------------
  function loadRoster(then) {
    db.from('creators').select('*, creator_profiles(*)').order('name').then(function (r) {
      if (r.error) {
        state.creators = [];
        $('rosterList').innerHTML = '<div class="empty">Could not load the roster. ' +
          esc(r.error.message) + '</div>';
        return;
      }
      state.creators = r.data || [];
      paintRoster();
      if (then) then();
    });
  }

  function paintRoster() {
    var box = $('rosterList');
    if (!box) return;
    var q = ($('rosterSearch').value || '').trim().toLowerCase();
    var shown = !q ? state.creators : state.creators.filter(function (c) {
      var hay = c.name + ' ' +
        (c.creator_profiles || []).map(function (p) { return p.handle || p.url; }).join(' ');
      return hay.toLowerCase().indexOf(q) > -1;
    });
    $('rosterCount').textContent = !state.creators.length ? '' :
      (q ? shown.length + ' of ' + state.creators.length
         : state.creators.length + (state.creators.length === 1 ? ' creator' : ' creators'));

    box.innerHTML = '';
    if (!shown.length) {
      box.innerHTML = '<div class="empty">' +
        (state.creators.length ? 'Nothing matches that search.'
                               : 'No creators yet. Add your first one above.') + '</div>';
      return;
    }
    shown.forEach(function (c) {
      var row = document.createElement('div');
      row.className = 'slink';
      var chips = (c.creator_profiles || []).map(function (p) {
        return '<a class="pchip" href="' + esc(p.url) + '" target="_blank" rel="noopener">' +
          esc(PLATFORM_LABEL[p.platform] || p.platform) +
          (p.handle ? '' : ' <span class="pchip-anon" title="Short link, no identity">·</span>') + '</a>';
      }).join('');
      row.innerHTML =
        '<div class="slink-body">' +
          '<span class="slink-slug">' + esc(c.name) + '</span>' +
          '<span class="slink-target">' + (chips || '<span class="muted">No profile links</span>') +
            (c.client_rate ? ' &nbsp;·&nbsp; ' + money(c.client_rate) : '') + '</span>' +
        '</div>' +
        '<div class="slink-actions">' +
          iconBtn('pencil', 'edit', 'Edit creator') +
          iconBtn('trash', 'del', 'Remove creator', 'is-danger') +
        '</div>';
      row.querySelector('[data-a="edit"]').addEventListener('click', function () { openCreator(c); });
      row.querySelector('[data-a="del"]').addEventListener('click', function () { removeCreator(c); });
      box.appendChild(row);
    });
  }

  // ---- Profile link rows --------------------------------------------------
  function profRow(p) {
    var row = document.createElement('div');
    row.className = 'profrow';
    row.innerHTML =
      '<input class="input prof-url" placeholder="https://www.xiaohongshu.com/user/profile/…">' +
      '<span class="prof-read muted"></span>' +
      '<button class="iconbtn is-danger" type="button" title="Remove" aria-label="Remove">' +
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" ' +
      'stroke-linejoin="round" aria-hidden="true">' + (ICON.trash || '') + '</svg></button>';
    var input = row.querySelector('.prof-url');
    var read = row.querySelector('.prof-read');
    if (p) input.value = p.url;
    function reflect() {
      var got = readProfile(input.value);
      if (!input.value.trim()) { read.textContent = ''; read.className = 'prof-read muted'; }
      else if (!got) { read.textContent = 'Not a profile link we recognise'; read.className = 'prof-read err'; }
      else if (!got.handle) { read.textContent = PLATFORM_LABEL[got.platform] + ' · short link'; read.className = 'prof-read muted'; }
      else { read.textContent = PLATFORM_LABEL[got.platform] + ' · ' + got.handle; read.className = 'prof-read ok'; }
      warnDupes();
    }
    input.addEventListener('input', reflect);
    row.querySelector('.iconbtn').addEventListener('click', function () { row.remove(); warnDupes(); });
    reflect();
    return row;
  }

  function profValues() {
    return Array.prototype.slice.call(document.querySelectorAll('#profRows .prof-url'))
      .map(function (i) { return readProfile(i.value); })
      .filter(Boolean);
  }

  /* Before saving, say who else already owns one of these identities. The
     database refuses it outright; this is so the person finds out while they
     still have the form open. */
  function warnDupes() {
    var mine = profValues().filter(function (p) { return p.handle; });
    if (!mine.length) { msg('dupeWarn', ''); return; }
    var hits = [];
    state.creators.forEach(function (c) {
      if (state.editing && c.id === state.editing.id) return;
      (c.creator_profiles || []).forEach(function (p) {
        if (!p.handle) return;
        mine.forEach(function (m) {
          if (p.platform === m.platform && String(p.handle).toLowerCase() === String(m.handle).toLowerCase()) {
            if (hits.indexOf(c.name) < 0) hits.push(c.name);
          }
        });
      });
    });
    if (hits.length) {
      msg('dupeWarn', 'Already in the roster as ' + hits.join(', ') + '. Saving will be refused.', 'err');
      return;
    }
    // Nothing identical. Names close enough to be worth a second look.
    var name = ($('crName').value || '').trim().toLowerCase().replace(/[^a-z0-9一-鿿]/g, '');
    if (name.length > 1) {
      var near = state.creators.filter(function (c) {
        if (state.editing && c.id === state.editing.id) return false;
        var o = c.name.toLowerCase().replace(/[^a-z0-9一-鿿]/g, '');
        return o && (o.indexOf(name) > -1 || name.indexOf(o) > -1);
      }).map(function (c) { return c.name; });
      if (near.length) {
        msg('dupeWarn', 'Similar name already in the roster: ' + near.join(', ') + '.', 'warn');
        return;
      }
    }
    msg('dupeWarn', '');
  }

  function openCreator(c) {
    state.editing = c || null;
    $('creatorFormTitle').textContent = c ? 'Edit creator' : 'New creator';
    $('saveCreator').textContent = c ? 'Save' : 'Create';
    $('crName').value = c ? c.name : '';
    $('crRate').value = c && c.client_rate != null ? c.client_rate : '';
    $('crNotes').value = c ? (c.notes || '') : '';
    var rows = $('profRows');
    rows.innerHTML = '';
    var ps = (c && c.creator_profiles) || [];
    if (!ps.length) rows.appendChild(profRow(null));
    else ps.forEach(function (p) { rows.appendChild(profRow(p)); });
    msg('creatorMsg', ''); msg('dupeWarn', '');
    $('addCreatorBox').hidden = false;
    $('crName').focus();
  }

  $('showAddCreator').addEventListener('click', function () { openCreator(null); });
  $('cancelAddCreator').addEventListener('click', function () {
    $('addCreatorBox').hidden = true; state.editing = null;
  });
  $('addProfRow').addEventListener('click', function () { $('profRows').appendChild(profRow(null)); });
  $('rosterSearch').addEventListener('input', paintRoster);
  $('crName').addEventListener('input', warnDupes);

  $('saveCreator').addEventListener('click', function () {
    var name = ($('crName').value || '').trim();
    if (!name) { msg('creatorMsg', 'A name is required.', 'err'); return; }

    var raw = Array.prototype.slice.call(document.querySelectorAll('#profRows .prof-url'))
      .map(function (i) { return i.value.trim(); }).filter(Boolean);
    var bad = raw.filter(function (u) { return !readProfile(u); });
    if (bad.length) {
      msg('creatorMsg', 'These are not profile links we recognise: ' + bad.join(', '), 'err');
      return;
    }
    var profiles = profValues();

    var body = {
      name: name,
      client_rate: $('crRate').value ? Number($('crRate').value) : null,
      notes: ($('crNotes').value || '').trim() || null,
      created_by: who() || null
    };

    var done = function (id, created) {
      // Replace the whole set rather than diffing: a handful of rows, and it
      // cannot drift out of step with what the form shows.
      db.from('creator_profiles').delete().eq('creator_id', id).then(function () {
        var rows = profiles.map(function (p) {
          return { creator_id: id, platform: p.platform, url: p.url, handle: p.handle };
        });
        var after = function (res) {
          if (res && res.error) {
            msg('creatorMsg', /duplicate|unique/i.test(res.error.message)
              ? 'One of those profile links already belongs to another creator.'
              : res.error.message, 'err');
            return;
          }
          log(created ? 'creator.added' : 'creator.updated', name, '');
          $('addCreatorBox').hidden = true;
          state.editing = null;
          loadRoster();
        };
        if (!rows.length) after(null);
        else db.from('creator_profiles').insert(rows).then(after);
      });
    };

    if (state.editing) {
      db.from('creators').update(body).eq('id', state.editing.id).then(function (r) {
        if (r.error) { msg('creatorMsg', r.error.message, 'err'); return; }
        done(state.editing.id, false);
      });
    } else {
      db.from('creators').insert(body).select().single().then(function (r) {
        if (r.error) { msg('creatorMsg', r.error.message, 'err'); return; }
        done(r.data.id, true);
      });
    }
  });

  function removeCreator(c) {
    if (!confirm('Remove ' + c.name + ' from the roster?\n\nCampaigns that already offered them keep their record.')) return;
    db.from('creators').delete().eq('id', c.id).then(function (r) {
      if (r.error) {
        alert(/foreign key|violates/i.test(r.error.message)
          ? c.name + ' has been offered in a campaign, so the record has to stay. Mark them inactive instead.'
          : r.error.message);
        return;
      }
      log('creator.removed', c.name, '');
      loadRoster();
    });
  }

  // ---- Campaigns ----------------------------------------------------------
  function loadClients(then) {
    db.from('clients').select('id, name').order('name').then(function (r) {
      state.clients = (r.data) || [];
      $('clientNames').innerHTML = state.clients.map(function (c) {
        return '<option value="' + esc(c.name) + '"></option>';
      }).join('');
      if (then) then();
    });
  }

  /* Matches an existing client by name, or makes one. Until there is a CRM to
     pick from, the name typed here is the record. */
  function resolveClient(name, then) {
    var hit = state.clients.filter(function (c) {
      return c.name.trim().toLowerCase() === name.toLowerCase();
    })[0];
    if (hit) { then(hit.id); return; }
    db.from('clients').insert({ name: name, access_token: token() })
      .select().single().then(function (r) {
        if (r.error) { msg('campMsg', r.error.message, 'err'); return; }
        state.clients.push({ id: r.data.id, name: r.data.name });
        log('client.added', name, 'from a campaign');
        then(r.data.id);
      });
  }

  function loadCampaigns() {
    db.from('campaigns').select('*, clients(name)').order('created_at', { ascending: false })
      .then(function (r) {
        var box = $('campCards');
        if (r.error) {
          box.innerHTML = '<div class="empty">Could not load campaigns. ' + esc(r.error.message) + '</div>';
          return;
        }
        box.innerHTML = '';
        if (!r.data.length) {
          box.innerHTML = '<div class="empty">No campaigns yet. Create one from an invoice above.</div>';
          return;
        }
        r.data.forEach(function (c) {
          var b = document.createElement('button');
          b.className = 'bigcard';
          b.type = 'button';
          b.innerHTML =
            '<b>' + esc(c.title) + '</b>' +
            '<span class="muted">' + esc((c.clients && c.clients.name) || '') + '</span>' +
            '<span class="muted">' + c.slots + ' slots' +
              (c.invoice_no ? ' · ' + esc(c.invoice_no) : '') + '</span>' +
            '<span class="chip' + (c.state === 'draft' ? '' : ' is-live') + '">' +
              esc(STATE_WORD[c.state] || c.state) + '</span>';
          b.addEventListener('click', function () { openCampaign(c); });
          box.appendChild(b);
        });
      });
  }

  var STATE_WORD = { draft: 'Draft', open: 'Open for selection', production: 'In production', completed: 'Completed' };

  $('showAddCamp').addEventListener('click', function () {
    loadClients(function () {
      $('addCampBox').hidden = false;
      $('campClient').focus();
    });
  });
  $('cancelAddCamp').addEventListener('click', function () { $('addCampBox').hidden = true; });

  // Every invoice starts AINV2, so the field carries it and only the rest is
  // typed. Stored whole, because that is what is on the document.
  function invoiceNo() {
    var rest = ($('campInvoice').value || '').trim().replace(/^AINV2/i, '');
    return rest ? 'AINV2' + rest : null;
  }

  $('addCamp').addEventListener('click', function () {
    var title = ($('campTitle').value || '').trim();
    var clientName = ($('campClient').value || '').trim();
    if (!clientName) { msg('campMsg', 'A client name is required.', 'err'); return; }
    if (!title) { msg('campMsg', 'A campaign name is required.', 'err'); return; }
    var slots = Number($('campSlots').value || 0);
    if (!slots || slots < 1) { msg('campMsg', 'Slots must be at least 1.', 'err'); return; }

    resolveClient(clientName, function (clientId) { createCampaign(clientId, title, slots); });
  });

  function createCampaign(clientId, title, slots) {
    db.from('campaigns').insert({
      client_id: clientId, title: title,
      invoice_no: invoiceNo(),
      slots: slots,
      deadline: $('campDeadline').value || null,
      push_format: $('campFormat').value,
      deliverable: $('campDeliverable').value,
      owner: ($('campOwner').value || '').trim() || null,
      access_token: token(),
      // Stated rather than left to the column default. The object we go on to
      // work with is the one we sent, so it has to be complete on its own.
      state: 'draft',
      created_by: who() || null
    }).select('*, clients(name)').single().then(function (r) {
      if (r.error) { msg('campMsg', r.error.message, 'err'); return; }
      log('campaign.created', title, r.data.invoice_no || '');
      $('addCampBox').hidden = true;
      ['campTitle','campInvoice','campOwner','campClient'].forEach(function (i) { $(i).value = ''; });
      msg('campMsg', '');
      openCampaign(r.data);
    });
  }

  function campaignUrl(c) { return location.origin + '/creators/?k=' + c.access_token; }

  function openCampaign(c) {
    state.campaign = c;
    $('campListView').hidden = true;
    $('campWork').hidden = false;
    $('campName').textContent = c.title;
    $('campState').textContent = STATE_WORD[c.state] || c.state;
    $('campState').classList.toggle('is-live', c.state !== 'draft');
    $('campMeta').textContent = [
      (c.clients && c.clients.name) || '',
      c.invoice_no ? 'Invoice ' + c.invoice_no : 'No invoice number',
      c.slots + ' slots',
      c.deliverable === 'graphic' ? 'One graphic' : 'One video',
      c.owner ? 'Owner: ' + c.owner : ''
    ].filter(Boolean).join('  ·  ');
    $('campLink').value = campaignUrl(c);
    $('campOpen').href = campaignUrl(c);
    $('campPublish').textContent = c.state === 'draft' ? 'Open for selection' : 'Close selection';
    msg('campWorkMsg', '');
    loadOptions();
  }

  $('campBack').addEventListener('click', function () {
    state.campaign = null;
    $('campWork').hidden = true;
    $('campListView').hidden = false;
    $('addOptionBox').hidden = true;
    loadCampaigns();
  });

  $('campCopy').addEventListener('click', function () {
    navigator.clipboard.writeText($('campLink').value).then(function () {
      var b = $('campCopy').querySelector('span');
      b.textContent = 'Copied';
      setTimeout(function () { b.textContent = 'Copy link'; }, 1600);
    });
  });

  $('campPublish').addEventListener('click', function () {
    var c = state.campaign;
    var next = c.state === 'draft' ? 'open' : 'draft';
    db.from('campaigns').update({ state: next }).eq('id', c.id).then(function (r) {
      if (r.error) { msg('campWorkMsg', r.error.message, 'err'); return; }
      c.state = next;
      log(next === 'open' ? 'campaign.opened' : 'campaign.closed', c.title, '');
      openCampaign(c);
    });
  });

  $('campDelete').addEventListener('click', function () {
    var c = state.campaign;
    if (!confirm('Delete ' + c.title + '?\n\nEvery option and selection on it goes too. This cannot be undone.')) return;
    db.from('campaigns').delete().eq('id', c.id).then(function (r) {
      if (r.error) { msg('campWorkMsg', r.error.message, 'err'); return; }
      log('campaign.deleted', c.title, c.invoice_no || '');
      $('campBack').click();
    });
  });

  // ---- Options ------------------------------------------------------------
  var OPTION_WORD = {
    option: ['Offered', ''],
    shortlisted: ['Shortlisted', 'is-warn'],
    backup: ['Backup', ''],
    confirmed: ['Confirmed', 'is-ok'],
    pending_visit: ['Pending visit', 'is-warn'],
    pending_draft: ['Pending draft', 'is-warn'],
    reviewing: ['Reviewing', 'is-warn'],
    changes: ['Changes requested', 'is-warn'],
    scheduled: ['Scheduled', 'is-ok'],
    posted: ['Posted', 'is-ok'],
    completed: ['Completed', 'is-ok'],
    withdrawn: ['Withdrawn', 'is-danger'],
    replaced: ['Replaced', 'is-danger']
  };

  function loadOptions() {
    db.from('campaign_options').select('*, creators(name, creator_profiles(platform, url))')
      .eq('campaign_id', state.campaign.id).order('position').then(function (r) {
        state.options = (r.data) || [];
        paintOptions();
      });
  }

  function paintOptions() {
    var c = state.campaign;
    var live = state.options.filter(function (o) { return o.state !== 'replaced' && o.state !== 'withdrawn'; });
    var chosen = state.options.filter(function (o) {
      return ['shortlisted','confirmed','pending_visit','pending_draft','reviewing',
              'changes','scheduled','posted','completed'].indexOf(o.state) > -1;
    });
    var goodwill = state.options.filter(function (o) { return o.goodwill; });
    var total = chosen.reduce(function (s, o) { return s + Number(o.rate || 0); }, 0);

    // Invoiced against booked. They should agree; when they do not, the reason
    // is a goodwill replacement and somebody needs to have decided that on
    // purpose rather than discover it at reconciliation.
    var booked = chosen.length + goodwill.length;
    $('campTally').innerHTML =
      tallyCell('Invoiced slots', c.slots) +
      tallyCell('Offered', live.length) +
      tallyCell('Chosen', chosen.length + ' of ' + c.slots) +
      tallyCell('Value', money(total)) +
      (booked > c.slots
        ? '<div class="tally-cell is-warn"><b>' + booked + '</b><span>Booked · ' +
          goodwill.length + ' goodwill</span></div>' : '');

    var box = $('optionList');
    box.innerHTML = '';
    if (!state.options.length) {
      box.innerHTML = '<div class="empty">No options yet. Add creators from the roster above, ' +
        'and offer more than the slot count so the client has a real choice.</div>';
      return;
    }
    state.options.forEach(function (o) {
      var word = OPTION_WORD[o.state] || [o.state, ''];
      var cr = o.creators || {};
      var row = document.createElement('div');
      row.className = 'slink';
      row.innerHTML =
        '<div class="slink-body">' +
          '<span class="slink-slug">' + esc(cr.name || '') + '</span>' +
          '<span class="act-tag ' + word[1] + '" style="margin-left:8px">' + esc(word[0]) + '</span>' +
          (o.is_replacement ? '<span class="act-tag is-warn" style="margin-left:6px">Replacement</span>' : '') +
          '<span class="slink-target">' + esc(o.platforms || '') + ' · ' + money(o.rate) + '</span>' +
        '</div>' +
        '<div class="slink-actions">' +
          (o.state === 'option' || o.state === 'backup'
            ? iconBtn('tick', 'pick', 'Shortlist on the client\'s behalf') : '') +
          (o.state === 'shortlisted'
            ? iconBtn('redo', 'unpick', 'Take off the shortlist', 'is-warn') : '') +
          iconBtn('trash', 'del', 'Remove option', 'is-danger') +
        '</div>';
      var pick = row.querySelector('[data-a="pick"]');
      if (pick) pick.addEventListener('click', function () { keyIn(o, 'shortlisted'); });
      var unpick = row.querySelector('[data-a="unpick"]');
      if (unpick) unpick.addEventListener('click', function () { keyIn(o, 'option'); });
      row.querySelector('[data-a="del"]').addEventListener('click', function () { dropOption(o); });
      box.appendChild(row);
    });

    // Locking is offered exactly when there is something to lock.
    var waiting = state.options.filter(function (o) { return o.state === 'shortlisted'; });
    $('campLock').hidden = !waiting.length;
    $('campLock').textContent = 'Lock ' + waiting.length +
      (waiting.length === 1 ? ' selection' : ' selections');

    paintProduction();
  }

  function tallyCell(label, value) {
    return '<div class="tally-cell"><b>' + esc(String(value)) + '</b><span>' + esc(label) + '</span></div>';
  }

  /* A client who answers on WhatsApp has still chosen. This is how that choice
     gets into the record, and the lock records that it was keyed in by us. */
  function keyIn(o, to) {
    var name = (o.creators || {}).name || '';
    var chosen = state.options.filter(function (x) { return x.state === 'shortlisted'; }).length;
    var booked = state.options.filter(isLive).length;
    if (to === 'shortlisted' && chosen + booked >= state.campaign.slots) {
      msg('campWorkMsg', 'Every slot is already spoken for. Take one off first.', 'err');
      return;
    }
    db.from('campaign_options').update({ state: to }).eq('id', o.id).then(function (r) {
      if (r.error) { msg('campWorkMsg', r.error.message, 'err'); return; }
      log(to === 'shortlisted' ? 'campaign.keyed' : 'campaign.unkeyed', name, '');
      msg('campWorkMsg', '');
      loadOptions();
    });
  }

  function dropOption(o) {
    var name = (o.creators && o.creators.name) || 'this creator';
    if (o.state !== 'option' && o.state !== 'backup') {
      alert(name + ' has been chosen by the client, so removing them is a replacement rather than a deletion. That flow arrives with the production board.');
      return;
    }
    if (!confirm('Withdraw ' + name + ' from the options?')) return;
    db.from('campaign_options').delete().eq('id', o.id).then(function (r) {
      if (r.error) { msg('campWorkMsg', r.error.message, 'err'); return; }
      loadOptions();
    });
  }

  $('showAddOption').addEventListener('click', function () {
    $('addOptionBox').hidden = false;
    loadRoster(paintPicker);
    $('optionSearch').focus();
  });
  $('optionSearch').addEventListener('input', paintPicker);

  function paintPicker() {
    var box = $('optionPick');
    if (!box) return;
    var already = {};
    state.options.forEach(function (o) { already[o.creator_id] = true; });
    var q = ($('optionSearch').value || '').trim().toLowerCase();
    var list = state.creators.filter(function (c) {
      if (!q) return true;
      return c.name.toLowerCase().indexOf(q) > -1;
    });

    box.innerHTML = '';
    if (!list.length) {
      box.innerHTML = '<div class="empty">Nothing in the roster matches.</div>';
      return;
    }
    list.forEach(function (c) {
      var inCamp = already[c.id];
      var row = document.createElement('div');
      row.className = 'pickrow' + (inCamp ? ' is-in' : '');
      var plats = (c.creator_profiles || []).map(function (p) { return PLATFORM_LABEL[p.platform] || p.platform; });
      var uniq = plats.filter(function (v, i) { return plats.indexOf(v) === i; });
      row.innerHTML =
        '<div><b>' + esc(c.name) + '</b>' +
        '<span class="muted"> ' + (uniq.join(', ') || 'no links') +
        (c.client_rate ? ' · ' + money(c.client_rate) : ' · no rate') + '</span></div>' +
        (inCamp ? '<span class="muted">Already offered</span>'
                : '<button class="btn btn-sm btn-primary" type="button">Add</button>');
      if (!inCamp) {
        row.querySelector('button').addEventListener('click', function () { addOption(c, uniq); });
      }
      box.appendChild(row);
    });
  }

  function addOption(c, platformNames) {
    if (!c.client_rate) {
      msg('optionMsg', c.name + ' has no client rate. Set one in the roster first, because the offer freezes the rate at this moment.', 'err');
      return;
    }
    db.from('campaign_options').insert({
      campaign_id: state.campaign.id,
      creator_id: c.id,
      rate: c.client_rate,
      platforms: platformNames.join(', '),
      state: 'option',
      position: state.options.length
    }).then(function (r) {
      if (r.error) {
        msg('optionMsg', /duplicate|unique/i.test(r.error.message)
          ? c.name + ' is already offered in this campaign.' : r.error.message, 'err');
        return;
      }
      msg('optionMsg', c.name + ' added at ' + money(c.client_rate) + '.', 'ok');
      loadOptions();
      setTimeout(paintPicker, 150);
    });
  }

  /* ---- Production --------------------------------------------------------
     The pipeline, and what each step is waiting on. Order matters: it is what
     "next" means, and what the client-facing chip is derived from. */
  /* The line forward. `changes` is deliberately not on it: it is a branch the
     client causes off `reviewing`, not a step towards being done. Putting it
     in the sequence made "next" walk reviewing → changes → reviewing forever. */
  var PIPELINE = ['confirmed', 'pending_visit', 'pending_draft', 'reviewing',
                  'scheduled', 'posted', 'completed'];
  var IN_PRODUCTION = PIPELINE.concat(['changes']);

  // Product seeding has no visit. Asking for a location would mean typing N/A
  // into a box forever, so the same fields are labelled for what they are.
  function isDelivery() {
    return (state.campaign || {}).push_format === 'seeding';
  }
  function visitWord() { return isDelivery() ? 'Delivery' : 'Visit'; }

  function nextState(s) {
    if (s === 'changes') return 'reviewing';           // re-submitted after edits
    var i = PIPELINE.indexOf(s);
    return i > -1 && i < PIPELINE.length - 1 ? PIPELINE[i + 1] : null;
  }

  function isLive(o) { return IN_PRODUCTION.indexOf(o.state) > -1; }

  // Reads the same way it does on the client's page.
  function niceDate(d) {
    if (!d) return '';
    var dt = new Date(d + 'T00:00:00');
    if (isNaN(dt.getTime())) return String(d);
    return dt.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
  }

  function paintProduction() {
    var live = state.options.filter(isLive);
    var gone = state.options.filter(function (o) {
      return o.state === 'withdrawn' || o.state === 'replaced';
    });
    $('prodWrap').hidden = !live.length && !gone.length;
    if ($('prodWrap').hidden) return;

    $('bulkTitle').textContent = 'Apply to every confirmed creator';
    $('bulkHint').textContent = isDelivery()
      ? 'Fills anything left blank on each row. Seeding has no visit, so these are delivery details.'
      : 'Fills anything left blank on each row. A row you have already set by hand is marked, and is left alone unless you say otherwise.';

    var box = $('prodList');
    box.innerHTML = '';
    live.concat(gone).forEach(function (o) { box.appendChild(prodRow(o)); });
    paintRollup(live);
  }

  function prodRow(o) {
    var cr = o.creators || {};
    var word = OPTION_WORD[o.state] || [o.state, ''];
    var row = document.createElement('div');
    row.className = 'prod' + (isLive(o) ? '' : ' is-off');

    var dead = o.state === 'withdrawn' || o.state === 'replaced';
    var summary = [];
    if (o.visit_date) summary.push(visitWord() + ' ' + niceDate(o.visit_date) + (o.visit_time ? ', ' + o.visit_time : ''));
    if (o.visit_location) summary.push(o.visit_location);
    if (o.visit_pic) summary.push('PIC ' + o.visit_pic);
    if (o.revision_round > 1) summary.push('Round ' + o.revision_round + ' of 2');

    row.innerHTML =
      '<div class="prod-head">' +
        '<b>' + esc(cr.name || '') + '</b>' +
        '<span class="act-tag ' + word[1] + '">' + esc(word[0]) + '</span>' +
        (o.is_replacement ? '<span class="act-tag is-warn">Replacement</span>' : '') +
        (o.goodwill ? '<span class="act-tag is-warn">Goodwill</span>' : '') +
        '<span class="prod-sum muted">' + esc(summary.join(' · ')) + '</span>' +
        (dead ? '' : '<button class="btn btn-sm btn-quiet prod-more" type="button">Details</button>') +
      '</div>' +
      '<div class="prod-body" hidden></div>';

    if (dead) {
      if (o.drop_reason) {
        row.querySelector('.prod-body').hidden = false;
        row.querySelector('.prod-body').innerHTML =
          '<p class="hint">' + esc(o.drop_reason) + '</p>';
      }
      return row;
    }

    var body = row.querySelector('.prod-body');
    row.querySelector('.prod-more').addEventListener('click', function () {
      body.hidden = !body.hidden;
      if (!body.hidden && !body.innerHTML) fillProdBody(body, o);
    });
    return row;
  }

  function field(label, id, value, type, ph) {
    return '<div><label class="field-label">' + esc(label) + '</label>' +
      '<input class="input" data-f="' + id + '" type="' + (type || 'text') + '" value="' +
      esc(value == null ? '' : value) + '" placeholder="' + esc(ph || '') + '"></div>';
  }

  function fillProdBody(body, o) {
    var advance = nextState(o.state);
    body.innerHTML =
      '<div class="row">' +
        field(visitWord() + ' date', 'visit_date', o.visit_date, 'date') +
        field('Time', 'visit_time', o.visit_time, 'text', '2pm') +
        (isDelivery()
          ? field('Tracking no.', 'tracking_no', o.tracking_no, 'text', '')
          : field('Location', 'visit_location', o.visit_location, 'text', '')) +
        field('PIC to look for', 'visit_pic', o.visit_pic, 'text', 'Name') +
        field('PIC contact', 'visit_pic_phone', o.visit_pic_phone, 'text', '01x-xxx xxxx') +
      '</div>' +
      '<div class="row" style="margin-top:12px">' +
        '<div style="flex:1 1 340px"><label class="field-label">Draft link (Google Drive)</label>' +
          '<input class="input" data-f="draft_url" value="' + esc(o.draft_url || '') +
          '" placeholder="https://drive.google.com/…"></div>' +
        field('Planned publish', 'planned_publish', o.planned_publish, 'date') +
      '</div>' +
      '<div class="row" style="margin-top:12px">' +
        '<div><label class="field-label">Internal note</label>' +
          '<input class="input" data-f="notes" value="' + esc(o.notes || '') + '"></div>' +
      '</div>' +
      '<div class="prod-posts" data-posts></div>' +
      '<div class="row" style="margin-top:14px">' +
        '<button class="btn btn-primary" data-a="save" type="button">Save</button>' +
        (advance ? '<button class="btn btn-go" data-a="advance" type="button">Move to ' +
          esc((OPTION_WORD[advance] || [advance])[0]) + '</button>' : '') +
        '<button class="btn btn-quiet" data-a="withdraw" type="button" style="flex:0 0 auto">Creator withdrew</button>' +
        '<button class="btn btn-quiet is-danger" data-a="replace" type="button" style="flex:0 0 auto">Client replaced</button>' +
      '</div>' +
      '<div class="msg" data-msg></div>';

    paintPosts(body.querySelector('[data-posts]'), o);

    body.querySelector('[data-a="save"]').addEventListener('click', function () {
      var patch = {};
      Array.prototype.forEach.call(body.querySelectorAll('[data-f]'), function (i) {
        var v = i.value.trim();
        patch[i.getAttribute('data-f')] = v === '' ? null : v;
      });
      db.from('campaign_options').update(patch).eq('id', o.id).then(function (r) {
        var m = body.querySelector('[data-msg]');
        if (r.error) { m.textContent = r.error.message; m.className = 'msg err'; return; }
        m.textContent = 'Saved.'; m.className = 'msg ok';
        loadOptions();
      });
    });

    var adv = body.querySelector('[data-a="advance"]');
    if (adv) adv.addEventListener('click', function () { advanceOption(o, advance); });
    body.querySelector('[data-a="withdraw"]').addEventListener('click', function () { endOption(o, 'withdrawn'); });
    body.querySelector('[data-a="replace"]').addEventListener('click', function () { endOption(o, 'replaced'); });
  }

  /* Moving to posted needs somewhere for the numbers to go, and there is one
     row per platform because two placements are two posts. */
  function advanceOption(o, to) {
    var patch = { state: to };
    db.from('campaign_options').update(patch).eq('id', o.id).then(function (r) {
      if (r.error) { msg('campWorkMsg', r.error.message, 'err'); return; }
      log('campaign.stage', (o.creators || {}).name || '', to);
      if (to !== 'posted') { loadOptions(); return; }
      seedPosts(o, function () { loadOptions(); });
    });
  }

  function platformsOf(o) {
    return String(o.platforms || '').split(',').map(function (s) { return s.trim(); })
      .filter(Boolean);
  }

  function seedPosts(o, then) {
    db.from('option_posts').select('platform').eq('option_id', o.id).then(function (r) {
      var have = {};
      (r.data || []).forEach(function (p) { have[p.platform] = true; });
      var rows = platformsOf(o).filter(function (p) { return !have[p]; })
        .map(function (p) { return { option_id: o.id, platform: p, window_days: 7 }; });
      if (!rows.length) { then(); return; }
      db.from('option_posts').insert(rows).then(function () { then(); });
    });
  }

  function paintPosts(box, o) {
    if (PIPELINE.indexOf(o.state) < PIPELINE.indexOf('posted')) { box.innerHTML = ''; return; }
    box.innerHTML = '<div class="sectionlabel">Published posts and results</div>' +
      '<div class="empty">Loading…</div>';
    db.from('option_posts').select('*').eq('option_id', o.id).then(function (r) {
      var rows = r.data || [];
      if (!rows.length) {
        box.innerHTML = '<div class="sectionlabel">Published posts and results</div>' +
          '<div class="empty">No placements recorded.</div>';
        return;
      }
      box.innerHTML = '<div class="sectionlabel">Published posts and results</div>';
      rows.forEach(function (p) {
        var w = document.createElement('div');
        w.className = 'postrow';
        w.innerHTML =
          '<div class="row">' +
            '<div style="flex:0 0 110px"><label class="field-label">Platform</label>' +
              '<input class="input" value="' + esc(p.platform) + '" readonly></div>' +
            '<div style="flex:1 1 280px"><label class="field-label">Post link</label>' +
              '<input class="input" data-p="post_url" value="' + esc(p.post_url || '') + '"></div>' +
            '<div style="flex:0 0 150px"><label class="field-label">Published</label>' +
              '<input class="input" data-p="published_at" type="date" value="' + esc(p.published_at || '') + '"></div>' +
            '<div style="flex:0 0 110px"><label class="field-label">Window (days)</label>' +
              '<input class="input" data-p="window_days" type="number" min="1" value="' + (p.window_days || 7) + '"></div>' +
          '</div>' +
          '<div class="row" style="margin-top:10px">' +
            '<div><label class="field-label">Impressions</label>' +
              '<input class="input" data-p="impressions" type="number" min="0" value="' + (p.impressions == null ? '' : p.impressions) + '"></div>' +
            '<div><label class="field-label">Engagements</label>' +
              '<input class="input" data-p="engagements" type="number" min="0" value="' + (p.engagements == null ? '' : p.engagements) + '"></div>' +
            '<div><label class="field-label">Views</label>' +
              '<input class="input" data-p="views" type="number" min="0" value="' + (p.views == null ? '' : p.views) + '"></div>' +
            '<button class="btn btn-sm btn-primary" data-p-save type="button">Save</button>' +
          '</div>' +
          '<div class="msg" data-p-msg></div>';
        w.querySelector('[data-p-save]').addEventListener('click', function () {
          var patch = {};
          Array.prototype.forEach.call(w.querySelectorAll('[data-p]'), function (i) {
            var k = i.getAttribute('data-p');
            var v = i.value.trim();
            patch[k] = v === '' ? null : (i.type === 'number' ? Number(v) : v);
          });
          patch.measured_at = new Date().toISOString().slice(0, 10);
          db.from('option_posts').update(patch).eq('id', p.id).then(function (res) {
            var m = w.querySelector('[data-p-msg]');
            if (res.error) { m.textContent = res.error.message; m.className = 'msg err'; return; }
            m.textContent = 'Saved.'; m.className = 'msg ok';
            loadOptions();
          });
        });
        box.appendChild(w);
      });
    });
  }

  /* Withdrawn and replaced both end a booking, and they are not the same
     thing. A creator pulling out frees the slot. A client changing their mind
     after the shoot does not, because the shoot still gets paid for. */
  function endOption(o, kind) {
    var name = (o.creators || {}).name || 'this creator';
    var shot = PIPELINE.indexOf(o.state) >= PIPELINE.indexOf('pending_draft');
    var goodwill = false;

    if (kind === 'replaced' && shot) {
      if (!confirm(name + ' has already filmed.\n\nReplacing them now is goodwill: they ' +
          'still get paid, so the campaign ends up costing one more creator than was ' +
          'invoiced. Continue?')) return;
      goodwill = true;
    } else if (!confirm((kind === 'withdrawn' ? 'Mark ' + name + ' as withdrawn?'
                                              : 'Replace ' + name + '?') +
        '\n\nThey stay on the record either way, because the invoice has to reconcile against them.')) {
      return;
    }

    var why = prompt(kind === 'withdrawn' ? 'Why did they withdraw?' : 'Why the replacement?') || '';
    db.from('campaign_options')
      .update({ state: kind, drop_reason: why.trim() || null, goodwill: goodwill })
      .eq('id', o.id).then(function (r) {
        if (r.error) { msg('campWorkMsg', r.error.message, 'err'); return; }
        log(kind === 'withdrawn' ? 'campaign.withdrawn' : 'campaign.replaced', name, why);
        msg('campWorkMsg', kind === 'withdrawn'
          ? name + ' is withdrawn and the slot is free again. The client can pick a replacement from the remaining options.'
          : name + ' is replaced.' + (goodwill ? ' Logged as goodwill.' : ' The slot is free again.'), 'warn');
        loadOptions();
      });
  }

  function paintRollup(live) {
    var posted = live.filter(function (o) {
      return PIPELINE.indexOf(o.state) >= PIPELINE.indexOf('posted');
    });
    if (!posted.length) { $('rollup').hidden = true; return; }
    db.from('option_posts').select('*').then(function (r) {
      var mine = {};
      posted.forEach(function (o) { mine[o.id] = true; });
      var rows = (r.data || []).filter(function (p) { return mine[p.option_id]; });
      var sum = function (k) {
        return rows.reduce(function (s, p) { return s + Number(p[k] || 0); }, 0);
      };
      var imp = sum('impressions'), eng = sum('engagements'), vie = sum('views');
      var spend = posted.reduce(function (s, o) { return s + Number(o.rate || 0); }, 0);
      $('rollup').hidden = false;
      $('rollupTally').innerHTML =
        tallyCell('Placements', rows.length) +
        tallyCell('Impressions', imp.toLocaleString()) +
        tallyCell('Engagements', eng.toLocaleString()) +
        tallyCell('Views', vie.toLocaleString()) +
        tallyCell('Spend', money(spend)) +
        (eng ? tallyCell('Cost per engagement', 'RM ' + (spend / eng).toFixed(2)) : '');
    });
  }

  // ---- Locking the selection ---------------------------------------------
  $('campLock').addEventListener('click', function () {
    var picked = state.options.filter(function (o) { return o.state === 'shortlisted'; });
    if (!picked.length) {
      msg('campWorkMsg', 'Nothing is shortlisted yet.', 'err');
      return;
    }
    $('lockBlurb').textContent = 'These ' + picked.length + ' become bookings and production starts. ' +
      'Anything still offered stays available, so the rest of the slots can be filled later.';
    $('lockList').innerHTML = picked.map(function (o) {
      return '<div class="act"><span class="act-subject">' + esc((o.creators || {}).name || '') +
        '</span><span class="muted act-when">' + money(o.rate) + '</span></div>';
    }).join('');
    $('lockPerson').value = '';
    msg('lockMsg', '');
    $('lockSheet').hidden = false;
    $('lockPerson').focus();
  });

  function shutLock() { $('lockSheet').hidden = true; }
  $('lockClose').addEventListener('click', shutLock);
  $('lockCancel').addEventListener('click', shutLock);
  $('lockSheet').addEventListener('click', function (e) {
    if (e.target === $('lockSheet')) shutLock();
  });

  $('lockGo').addEventListener('click', function () {
    var person = ($('lockPerson').value || '').trim();
    if (!person) { msg('lockMsg', 'Record who confirmed it.', 'err'); return; }
    var source = $('lockSource').value;
    var picked = state.options.filter(function (o) { return o.state === 'shortlisted'; });
    var ids = picked.map(function (o) { return o.id; });
    var stamp = new Date().toISOString();

    db.from('campaign_confirmations').insert({
      campaign_id: state.campaign.id,
      kind: source === 'portal' ? 'client' : 'keyed_in',
      person: person, source: source
    }).then(function (r) {
      if (r.error) { msg('lockMsg', r.error.message, 'err'); return; }
      // One at a time, because these are a handful of rows and a partial
      // failure should leave the rest locked rather than roll the lot back.
      var left = ids.length;
      if (!left) { shutLock(); return; }
      ids.forEach(function (id) {
        db.from('campaign_options')
          .update({ state: 'confirmed', confirmed_at: stamp, confirmed_by: person })
          .eq('id', id).then(function () {
            if (--left) return;
            db.from('campaigns').update({ state: 'production' }).eq('id', state.campaign.id)
              .then(function () {
                state.campaign.state = 'production';
                log('campaign.locked', state.campaign.title, picked.length + ' creators · ' + person);
                shutLock();
                openCampaign(state.campaign);
              });
          });
      });
    });
  });

  // ---- Bulk logistics -----------------------------------------------------
  $('bulkToggle').addEventListener('click', function () {
    $('bulkBox').hidden = !$('bulkBox').hidden;
  });
  $('bulkCancel').addEventListener('click', function () { $('bulkBox').hidden = true; });

  function bulkValues() {
    var v = {
      visit_date: $('bulkDate').value || null,
      visit_time: ($('bulkTime').value || '').trim() || null,
      visit_pic: ($('bulkPic').value || '').trim() || null,
      visit_pic_phone: ($('bulkPhone').value || '').trim() || null
    };
    var loc = ($('bulkLoc').value || '').trim() || null;
    if (isDelivery()) v.tracking_no = null; else v.visit_location = loc;
    if (isDelivery() && loc) v.visit_location = loc;
    return v;
  }

  function applyBulk(overwrite) {
    var vals = bulkValues();
    var keys = Object.keys(vals).filter(function (k) { return vals[k] !== null; });
    if (!keys.length) { msg('bulkMsg', 'Fill in something to apply.', 'err'); return; }

    var targets = state.options.filter(isLive);
    if (!targets.length) { msg('bulkMsg', 'Nothing is in production yet.', 'err'); return; }

    var left = targets.length, touched = 0;
    targets.forEach(function (o) {
      var patch = {};
      keys.forEach(function (k) {
        // "Apply to blanks" is the safe one: a row somebody set by hand keeps
        // what they set. Overwrite is the deliberate, separate button.
        if (overwrite || o[k] == null || o[k] === '') patch[k] = vals[k];
      });
      if (!Object.keys(patch).length) { if (!--left) done(); return; }
      touched++;
      db.from('campaign_options').update(patch).eq('id', o.id).then(function () {
        if (!--left) done();
      });
    });

    function done() {
      msg('bulkMsg', touched
        ? 'Applied to ' + touched + (touched === 1 ? ' creator.' : ' creators.')
        : 'Every row already had those filled in. Use Overwrite to replace them.',
        touched ? 'ok' : 'warn');
      log('campaign.bulk', state.campaign.title, touched + ' rows');
      loadOptions();
    }
  }

  $('bulkApply').addEventListener('click', function () { applyBulk(false); });
  $('bulkApplyAll').addEventListener('click', function () {
    if (!confirm('Overwrite these fields on every creator, including rows already set by hand?')) return;
    applyBulk(true);
  });

  // ---- Entry --------------------------------------------------------------
  window.ADspaceCampaigns = {
    enter: function () { showTab(state.tab === 'roster' ? 'roster' : 'campaigns'); }
  };
})();
