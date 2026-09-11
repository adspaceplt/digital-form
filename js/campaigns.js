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
      var hay = c.name + ' ' + (c.industries || '') + ' ' +
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
          (c.followers ? '<span class="slink-label">' + Number(c.followers).toLocaleString() + ' followers</span>' : '') +
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
    $('crFollowers').value = c && c.followers != null ? c.followers : '';
    $('crCost').value = c && c.cost_rate != null ? c.cost_rate : '';
    $('crRate').value = c && c.client_rate != null ? c.client_rate : '';
    $('crIndustries').value = c ? (c.industries || '') : '';
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
      followers: $('crFollowers').value ? Number($('crFollowers').value) : null,
      cost_rate: $('crCost').value ? Number($('crCost').value) : null,
      client_rate: $('crRate').value ? Number($('crRate').value) : null,
      industries: ($('crIndustries').value || '').trim() || null,
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
      var sel = $('campClient');
      sel.innerHTML = state.clients.map(function (c) {
        return '<option value="' + c.id + '">' + esc(c.name) + '</option>';
      }).join('');
      if (then) then();
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
      if (!state.clients.length) {
        msg('campMsg', 'Add a client under Content Review first.', 'err');
      }
      $('addCampBox').hidden = false;
      $('campTitle').focus();
    });
  });
  $('cancelAddCamp').addEventListener('click', function () { $('addCampBox').hidden = true; });

  $('addCamp').addEventListener('click', function () {
    var title = ($('campTitle').value || '').trim();
    var clientId = $('campClient').value;
    if (!clientId) { msg('campMsg', 'Pick a client.', 'err'); return; }
    if (!title) { msg('campMsg', 'A campaign name is required.', 'err'); return; }
    var slots = Number($('campSlots').value || 0);
    if (!slots || slots < 1) { msg('campMsg', 'Slots must be at least 1.', 'err'); return; }

    db.from('campaigns').insert({
      client_id: clientId, title: title,
      invoice_no: ($('campInvoice').value || '').trim() || null,
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
      ['campTitle','campInvoice','campOwner'].forEach(function (i) { $(i).value = ''; });
      msg('campMsg', '');
      openCampaign(r.data);
    });
  });

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
    db.from('campaign_options').select('*, creators(name, followers, creator_profiles(platform, url))')
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
          '<span class="slink-target">' + esc(o.platforms || '') + ' · ' + money(o.rate) +
            (cr.followers ? ' · ' + Number(cr.followers).toLocaleString() + ' followers' : '') + '</span>' +
        '</div>' +
        '<div class="slink-actions">' +
          iconBtn('trash', 'del', 'Remove option', 'is-danger') +
        '</div>';
      row.querySelector('[data-a="del"]').addEventListener('click', function () { dropOption(o); });
      box.appendChild(row);
    });
  }

  function tallyCell(label, value) {
    return '<div class="tally-cell"><b>' + esc(String(value)) + '</b><span>' + esc(label) + '</span></div>';
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
      return (c.name + ' ' + (c.industries || '')).toLowerCase().indexOf(q) > -1;
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

  // ---- Entry --------------------------------------------------------------
  window.ADspaceCampaigns = {
    enter: function () { showTab(state.tab === 'roster' ? 'roster' : 'campaigns'); }
  };
})();
