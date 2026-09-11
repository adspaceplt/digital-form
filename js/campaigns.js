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
  var putToS3 = bridge.putToS3;
  var cfg     = window.ADSPACE_CONFIG || {};
  var setUrl  = bridge.setUrl || function () {};
  var restoreScroll = bridge.restoreScroll || function () {};

  /* ---- A form's memory -----------------------------------------------------
     What was typed, whether the form was open, and what it was editing, kept
     until it is submitted or cancelled. A refresh in the middle of a campaign
     used to throw all of it away. `extra` is for the parts that are not plain
     fields: the profile link rows and the platform ticks. */
  var DRAFT = 'adspace.admin.draft.';
  function keepDraft(boxId, ids, extra) {
    var key = DRAFT + boxId;
    var meta = {};
    function save() {
      var box = $(boxId); if (!box) return;
      var v = {};
      ids.forEach(function (id) { var el = $(id); if (el) v[id] = el.value; });
      var d = { open: !box.hidden, v: v, meta: meta };
      if (extra && extra.get) d.extra = extra.get();
      try { sessionStorage.setItem(key, JSON.stringify(d)); } catch (e) {}
    }
    ids.forEach(function (id) {
      var el = $(id); if (!el) return;
      el.addEventListener('input', save);
      el.addEventListener('change', save);
    });
    return {
      save: save,
      note: function (m) { meta = m || {}; save(); },
      read: function () {
        try { return JSON.parse(sessionStorage.getItem(key) || 'null'); } catch (e) { return null; }
      },
      fill: function (d) {
        ids.forEach(function (id) { var el = $(id); if (el && d.v && d.v[id] != null) el.value = d.v[id]; });
        if (extra && extra.set && d.extra) extra.set(d.extra);
      },
      clear: function () { meta = {}; try { sessionStorage.removeItem(key); } catch (e) {} }
    };
  }

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
  /* Currency belongs to the client, not to the office. A Singapore client is
     quoted in S$ everywhere the number appears, including here. */
  var MON = window.ADspaceMoney;
  function mkt() {
    var c = state.campaign || {};
    return (c.clients && c.clients.market) || c.market || 'MY';
  }
  function taxOn() {
    var c = state.campaign || {};
    var v = (c.clients && c.clients.sst_applies);
    return v === undefined || v === null ? true : v;
  }
  function money(n)  { return MON.money(n, mkt()); }
  function money2(n) { return MON.money2(n, mkt()); }
  function sstOf(subtotal) { return MON.taxOf(subtotal, mkt(), taxOn()); }
  function taxWord() { return taxOn() ? MON.taxLabel(mkt()) : 'Tax'; }

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
  var PLATFORM_NAMES = ['RedNote', 'Instagram', 'TikTok', 'Facebook'];

  /* Where she posts for THIS campaign is proposed by us, one tick per
     platform. Her profile links only decide which boxes start ticked; a
     creator with two accounts may still be booked for one of them. */
  function platformBoxes(ticked) {
    return '<span class="pboxes">' + PLATFORM_NAMES.map(function (name) {
      return '<label class="pbox"><input type="checkbox" value="' + name + '"' +
        (ticked.indexOf(name) > -1 ? ' checked' : '') + '>' + name + '</label>';
    }).join('') + '</span>';
  }
  function readBoxes(container) {
    return Array.prototype.slice.call(container.querySelectorAll('.pbox input:checked'))
      .map(function (i) { return i.value; });
  }

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
    setUrl();
    if (name === 'roster') loadRoster(function () { rosterDraft.restore(); restoreScroll(); });
    if (name === 'campaigns' && !state.campaign) { loadCampaigns(); campDraft.restore(); restoreScroll(); }
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
                               : 'No creators yet.') + '</div>';
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
  // Two forms build these: the roster's, and the one inside a campaign. Each
  // names its own rows, name field and warning line.
  var ROSTER_CTX = { rows: 'profRows',   name: 'crName', warn: 'dupeWarn' };
  var NC_CTX     = { rows: 'ncProfRows', name: 'ncName', warn: 'ncDupe' };

  function profRow(p, ctx) {
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
      warnDupes(ctx);
      if (ctx === NC_CTX) tickFromLinks();
    }
    input.addEventListener('input', reflect);
    row.querySelector('.iconbtn').addEventListener('click', function () { row.remove(); warnDupes(ctx); });
    reflect();
    return row;
  }

  function profValues(ctx) {
    return Array.prototype.slice.call(document.querySelectorAll('#' + ctx.rows + ' .prof-url'))
      .map(function (i) { return readProfile(i.value); })
      .filter(Boolean);
  }

  /* Before saving, say who else already owns one of these identities. The
     database refuses it outright; this is so the person finds out while they
     still have the form open. */
  function warnDupes(ctx) {
    var mine = profValues(ctx).filter(function (p) { return p.handle; });
    if (!mine.length) { msg(ctx.warn, ''); return; }
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
      msg(ctx.warn, 'Already in the roster as ' + hits.join(', ') + '. Saving will be refused.', 'err');
      return;
    }
    // Nothing identical. Names close enough to be worth a second look.
    var name = ($(ctx.name).value || '').trim().toLowerCase().replace(/[^a-z0-9一-鿿]/g, '');
    if (name.length > 1) {
      var near = state.creators.filter(function (c) {
        if (state.editing && c.id === state.editing.id) return false;
        var o = c.name.toLowerCase().replace(/[^a-z0-9一-鿿]/g, '');
        return o && (o.indexOf(name) > -1 || name.indexOf(o) > -1);
      }).map(function (c) { return c.name; });
      if (near.length) {
        msg(ctx.warn, 'Similar name already in the roster: ' + near.join(', ') + '.', 'warn');
        return;
      }
    }
    msg(ctx.warn, '');
  }

  var rosterDraft = keepDraft('addCreatorBox', ['crName', 'crRate', 'crNotes'], {
    get: function () {
      return { links: Array.prototype.slice.call(document.querySelectorAll('#profRows .prof-url'))
        .map(function (i) { return i.value; }) };
    },
    set: function (x) {
      var rows = $('profRows'); rows.innerHTML = '';
      (x.links && x.links.length ? x.links : ['']).forEach(function (u) {
        rows.appendChild(profRow(u ? { url: u } : null, ROSTER_CTX));
      });
    }
  });
  rosterDraft.restore = function () {
    var d = rosterDraft.read();
    if (!d || !d.open) return;
    var editing = d.meta && d.meta.editing
      ? state.creators.filter(function (c) { return c.id === d.meta.editing; })[0] : null;
    openCreator(editing || null, true);
    rosterDraft.fill(d);
    warnDupes(ROSTER_CTX);
  };
  document.addEventListener('input', function (e) {
    if (e.target.closest && e.target.closest('#profRows')) rosterDraft.save();
  });

  function openCreator(c, restoring) {
    state.editing = c || null;
    $('creatorFormTitle').textContent = c ? 'Edit creator' : 'New creator';
    $('saveCreator').textContent = c ? 'Save' : 'Create';
    $('crName').value = c ? c.name : '';
    $('crRate').value = c && c.client_rate != null ? c.client_rate : '';
    $('crNotes').value = c ? (c.notes || '') : '';
    var rows = $('profRows');
    rows.innerHTML = '';
    var ps = (c && c.creator_profiles) || [];
    if (!ps.length) rows.appendChild(profRow(null, ROSTER_CTX));
    else ps.forEach(function (p) { rows.appendChild(profRow(p, ROSTER_CTX)); });
    msg('creatorMsg', ''); msg('dupeWarn', '');
    $('addCreatorBox').hidden = false;
    if (!restoring) rosterDraft.note({ editing: c ? c.id : null });
    $('crName').focus();
  }

  $('showAddCreator').addEventListener('click', function () { openCreator(null); });
  $('cancelAddCreator').addEventListener('click', function () {
    $('addCreatorBox').hidden = true; state.editing = null; rosterDraft.clear();
  });
  $('addProfRow').addEventListener('click', function () { $('profRows').appendChild(profRow(null, ROSTER_CTX)); });
  $('rosterSearch').addEventListener('input', paintRoster);
  $('crName').addEventListener('input', function () { warnDupes(ROSTER_CTX); });

  $('saveCreator').addEventListener('click', function () {
    var name = ($('crName').value || '').trim();
    if (!name) { msg('creatorMsg', 'A name is required.', 'err'); return; }

    var raw = Array.prototype.slice.call(document.querySelectorAll('#profRows .prof-url'))
      .map(function (i) { return i.value.trim(); }).filter(Boolean);
    var bad = raw.filter(function (u) { return !readProfile(u); });
    if (bad.length) {
      msg('creatorMsg', 'Unrecognised profile links: ' + bad.join(', '), 'err');
      return;
    }
    var profiles = profValues(ROSTER_CTX);

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
              ? 'A profile link is already assigned to another creator.'
              : res.error.message, 'err');
            return;
          }
          log(created ? 'creator.added' : 'creator.updated', name, '');
          $('addCreatorBox').hidden = true;
          state.editing = null;
          rosterDraft.clear();
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
    if (!confirm('Remove ' + c.name + ' from the roster?\n\nExisting campaign records are kept.')) return;
    db.from('creators').delete().eq('id', c.id).then(function (r) {
      if (r.error) {
        alert(/foreign key|violates/i.test(r.error.message)
          ? c.name + ' has been offered in a campaign and cannot be removed. Mark them inactive instead.'
          : r.error.message);
        return;
      }
      log('creator.removed', c.name, '');
      loadRoster();
    });
  }

  // ---- Campaigns ----------------------------------------------------------
  /* Only an active client can be proposed to, and the list of those is the
     CRM's. A campaign never creates a company; if the client is not on this
     list, they are not active yet and the CRM says why. */
  function loadClients(then) {
    db.from('clients').select('id, name, market').eq('stage', 'active').order('name')
      .then(function (r) {
        state.clients = (r.data) || [];
        var sel = $('campClient');
        var keep = sel.value;
        sel.innerHTML = '<option value="">Choose a client…</option>' +
          state.clients.map(function (c) {
            return '<option value="' + esc(c.id) + '">' + esc(c.name) +
              (c.market === 'SG' ? ' · S$' : '') + '</option>';
          }).join('');
        if (keep) sel.value = keep;
        $('campClientNone').hidden = state.clients.length > 0;
        if (then) then();
      });
  }

  function loadCampaigns() {
    db.from('campaigns').select('*, clients(name, market, sst_applies)').order('created_at', { ascending: false })
      .then(function (r) {
        var box = $('campCards');
        if (r.error) {
          box.innerHTML = '<div class="empty">Could not load campaigns. ' + esc(r.error.message) + '</div>';
          return;
        }
        box.innerHTML = '';
        if (!r.data.length) {
          box.innerHTML = '<div class="empty">No campaigns yet.</div>';
          return;
        }
        // The amount on a card is what the client is charged: the rates of
        // everyone selected or booked, plus tax, in the client's currency.
        db.from('campaign_options').select('campaign_id, rate, state').then(function (q) {
          var sums = {};
          (q.data || []).forEach(function (o) {
            if (CHARGED.indexOf(o.state) < 0) return;
            sums[o.campaign_id] = (sums[o.campaign_id] || 0) + Number(o.rate || 0);
          });
          r.data.forEach(function (c) {
            var cl = c.clients || {};
            var mk = cl.market || 'MY';
            var ap = cl.sst_applies == null ? true : cl.sst_applies;
            var sub = sums[c.id] || 0;
            var b = document.createElement('button');
            b.className = 'bigcard';
            b.type = 'button';
            b.innerHTML =
              '<b>' + esc(c.title) + '</b>' +
              '<span class="muted">' + esc(cl.name || '') + '</span>' +
              '<span class="muted">' + c.slots + ' creator' + (c.slots === 1 ? '' : 's') +
                (sub ? ' · ' + esc(MON.money2(sub + MON.taxOf(sub, mk, ap), mk)) : '') + '</span>' +
              '<span class="chip' + (c.state === 'draft' ? '' : ' is-live') + '">' +
                esc(STATE_WORD[c.state] || c.state) + '</span>';
            b.addEventListener('click', function () { openCampaign(c); });
            box.appendChild(b);
          });
        });
      });
  }

  // The states whose rate the client pays for.
  var CHARGED = ['shortlisted', 'confirmed', 'pending_visit', 'pending_draft', 'reviewing',
                 'changes', 'scheduled', 'posted', 'completed'];

  var STATE_WORD = { draft: 'Draft', open: 'Open for selection', production: 'In production', completed: 'Completed' };
  var FORMAT_WORD = {
    site_visit: 'Site visit', event: 'Event', seeding: 'Product seeding',
    tenant_trail: 'Tenant trail', teaser: 'Pre-launch teaser', always_on: 'Always-on review'
  };
  var editingCamp = null;

  /* One form for both. Editing prefills it from the campaign; the invoice
     shows without its fixed prefix because the field puts that back. */
  var campDraft = keepDraft('addCampBox',
    ['campClient', 'campTitle', 'campPurpose', 'campSlots', 'campDeadline', 'campFormat', 'campDeliverable', 'campOwner']);
  campDraft.restore = function () {
    var d = campDraft.read();
    if (!d || !d.open) return;
    var editId = d.meta && d.meta.editing;
    if (editId && !(state.campaign && state.campaign.id === editId)) return;   // belongs to another view
    loadClients(function () {
      openCampForm(editId ? state.campaign : null, true);
      campDraft.fill(d);
    });
  };

  /* Editing happens in the campaign's own card: the form takes the place of
     the summary and gives it back on save or cancel. Creating happens above
     the list, where the form lives otherwise. */
  function placeCampForm(inline) {
    var box = $('addCampBox');
    if (inline) {
      $('campHead').appendChild(box);
      box.classList.add('is-inline');
      $('campSummary').hidden = true;
    } else {
      var list = $('campListView');
      if (box.parentNode !== list.parentNode) list.parentNode.insertBefore(box, list);
      box.classList.remove('is-inline');
      $('campSummary').hidden = false;
    }
    $('campDangerRow').hidden = !inline;
  }

  function openCampForm(c, restoring) {
    editingCamp = c || null;
    placeCampForm(!!c);
    $('campFormTitle').textContent = c ? 'Edit campaign' : 'New campaign';
    $('addCamp').textContent = c ? 'Save' : 'Create';
    $('campClient').value = c ? (c.client_id || '') : ($('campClient').value || '');
    $('campTitle').value = c ? c.title : '';
    $('campPurpose').value = c ? (c.purpose || '') : '';
    $('campSlots').value = c ? c.slots : 10;
    $('campDeadline').value = c ? (c.deadline || '') : '';
    $('campFormat').value = c ? (c.push_format || 'site_visit') : 'site_visit';
    $('campDeliverable').value = c ? (c.deliverable || 'video') : 'video';
    $('campOwner').value = c ? (c.owner || '') : '';
    msg('campMsg', '');
    $('addCampBox').hidden = false;
    if (!restoring) campDraft.note({ editing: c ? c.id : null });
    (c ? $('campTitle') : $('campClient')).focus();
  }
  function parkCampForm() { $('addCampBox').hidden = true; placeCampForm(false); }
  function shutCampForm() { parkCampForm(); editingCamp = null; campDraft.clear(); }

  $('showAddCamp').addEventListener('click', function () {
    loadClients(function () { openCampForm(null); });
  });
  $('campEdit').addEventListener('click', function () {
    loadClients(function () { openCampForm(state.campaign); });
  });
  $('cancelAddCamp').addEventListener('click', shutCampForm);

  // Every invoice starts AINV2, so the field carries it and only the rest is
  // typed. Stored whole, because that is what is on the document.
  function invoiceNo() {
    var rest = ($('invNo').value || '').trim().replace(/^AINV2/i, '');
    return rest ? 'AINV2' + rest : null;
  }

  $('addCamp').addEventListener('click', function () {
    var title = ($('campTitle').value || '').trim();
    var clientId = $('campClient').value;
    if (!clientId) { msg('campMsg', 'Choose the client this proposal is for.', 'err'); return; }
    if (!title) { msg('campMsg', 'A campaign name is required.', 'err'); return; }
    var slots = Number($('campSlots').value || 0);
    if (!slots || slots < 1) { msg('campMsg', 'At least one creator is required.', 'err'); return; }

    // A slot with a creator booked into it cannot be taken away by editing a
    // number. Free the booking first, then lower the count.
    if (editingCamp) {
      var booked = state.options.filter(isLive).length;
      if (slots < booked) {
        msg('campMsg', booked + ' creators are already booked; the count cannot go below ' + booked + '.', 'err');
        return;
      }
    }

    if (editingCamp) saveCampaign(clientId, title, slots);
    else createCampaign(clientId, title, slots);
  });

  function saveCampaign(clientId, title, slots) {
    var c = editingCamp;
    var patch = {
      client_id: clientId, title: title,
      purpose: ($('campPurpose').value || '').trim() || null,
      slots: slots,
      deadline: $('campDeadline').value || null,
      push_format: $('campFormat').value,
      deliverable: $('campDeliverable').value,
      owner: ($('campOwner').value || '').trim() || null
    };
    db.from('campaigns').update(patch).eq('id', c.id).select('*, clients(name, market, sst_applies)').single().then(function (r) {
      if (r.error) { msg('campMsg', r.error.message, 'err'); return; }
      log('campaign.edited', title, slots + ' slots');
      shutCampForm();
      openCampaign(r.data);
    });
  }

  function createCampaign(clientId, title, slots) {
    db.from('campaigns').insert({
      client_id: clientId, title: title,
      purpose: ($('campPurpose').value || '').trim() || null,
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
    }).select('*, clients(name, market, sst_applies)').single().then(function (r) {
      if (r.error) { msg('campMsg', r.error.message, 'err'); return; }
      log('campaign.created', title, slots + ' slots');
      shutCampForm();
      openCampaign(r.data);
    });
  }

  function campaignUrl(c) { return location.origin + '/creators/?k=' + c.access_token; }

  var ncDraft = keepDraft('addOptionBox', ['ncName', 'ncRate', 'optionSearch'], {
    get: function () {
      return {
        links: Array.prototype.slice.call(document.querySelectorAll('#ncProfRows .prof-url'))
          .map(function (i) { return i.value; }),
        plats: readBoxes($('ncPlatforms'))
      };
    },
    set: function (x) {
      var rows = $('ncProfRows'); rows.innerHTML = '';
      (x.links && x.links.length ? x.links : ['']).forEach(function (u) {
        rows.appendChild(profRow(u ? { url: u } : null, NC_CTX));
      });
      $('ncPlatforms').innerHTML = platformBoxes(x.plats || []);
    }
  });
  ncDraft.restore = function () {
    var d = ncDraft.read();
    if (!d || !d.open || !(d.meta && state.campaign && d.meta.campaign === state.campaign.id)) return;
    $('addOptionBox').hidden = false;
    loadRoster(function () { ncDraft.fill(d); paintPicker(); warnDupes(NC_CTX); });
  };
  document.addEventListener('input', function (e) {
    if (e.target.closest && e.target.closest('#ncProfRows, #ncPlatforms')) ncDraft.save();
  });
  document.addEventListener('change', function (e) {
    if (e.target.closest && e.target.closest('#ncPlatforms')) ncDraft.save();
  });

  function openCampaign(c, restoring) {
    // A repaint of the campaign already open keeps its panels as they are;
    // arriving at a campaign starts with them folded.
    var same = !!(state.campaign && state.campaign.id === c.id);
    state.campaign = c;
    parkCampForm();
    $('campListView').hidden = true;
    setUrl();
    $('campWork').hidden = false;
    $('campName').textContent = c.title;
    // Not the form's input of the same name: this is the line under the title.
    $('campPurposeLine').textContent = c.purpose || '';
    $('campPurposeLine').hidden = !c.purpose;
    $('campState').textContent = STATE_WORD[c.state] || c.state;
    $('campState').classList.toggle('is-live', c.state !== 'draft');
    $('campFacts').innerHTML = [
      ['Client',            (c.clients && c.clients.name) || ''],
      ['Push format',       FORMAT_WORD[c.push_format] || c.push_format || ''],
      ['Deliverable',       c.deliverable === 'graphic' ? 'One graphic' : 'One video'],
      ['Person in charge',  c.owner || '<span class="muted">Unassigned</span>'],
      ['Campaign due',      c.deadline ? niceDate(c.deadline) : '<span class="muted">No date set</span>'],
      ['Created',           c.created_at ? niceDate(String(c.created_at).slice(0, 10)) : '']
    ].filter(function (f) { return f[1] !== ''; }).map(function (f) {
      return '<div><dt>' + f[0] + '</dt><dd>' + (f[1].indexOf('<span') === 0 ? f[1] : esc(f[1])) + '</dd></div>';
    }).join('');
    $('campLink').value = campaignUrl(c);
    $('campOpen').href = campaignUrl(c);
    if (!same) setOpen('invoiceToggle', 'invoiceBody', false);
    paintInvoice(c);
    // Publishing is the forward move and carries the weight. Unpublishing and
    // reopening are warnings, drawn as such.
    var move = publishMove(c.state);
    $('campPublish').innerHTML = move.icon + esc(move.label);
    $('campPublish').className = 'btn ' + move.cls;
    msg('campWorkMsg', '');
    loadOptions();
    if (restoring) { campDraft.restore(); ncDraft.restore(); restoreScroll(); }
  }

  $('campBack').addEventListener('click', function () {
    state.campaign = null;
    $('campWork').hidden = true;
    $('campListView').hidden = false;
    $('addOptionBox').hidden = true;
    ncDraft.clear();
    setUrl();
    loadCampaigns();
  });

  $('campCopy').addEventListener('click', function () {
    navigator.clipboard.writeText($('campLink').value).then(function () {
      var b = $('campCopy').querySelector('span');
      b.textContent = 'Copied';
      setTimeout(function () { b.textContent = 'Copy link'; }, 1600);
    });
  });

  /* The campaign moves forward and back. A locked selection the client wants to
     revisit reopens; a campaign marked finished too early comes back. Neither
     needs the campaign rebuilding. */
  var ICON = {
    send:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 3 10 14"/><path d="M21 3 14.5 21l-4.5-7-7-4.5z"/></svg>',
    eyeOff: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m3 3 18 18"/><path d="M10.6 5.1A9.6 9.6 0 0 1 12 5c5 0 9 4.5 9 7a12 12 0 0 1-2.4 3.4"/><path d="M6.5 7.6C4.3 9.1 3 11.2 3 12c0 2.5 4 7 9 7a9.7 9.7 0 0 0 4.2-1"/></svg>',
    reopen: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 12a9 9 0 1 0 2.6-6.4"/><path d="M3 4v4h4"/></svg>',
    play:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m7 5 12 7-12 7z"/></svg>'
  };
  function publishMove(s) {
    if (s === 'draft')      return { to: 'open',  label: 'Publish to client', cls: 'btn-go', icon: ICON.send };
    if (s === 'open')        return { to: 'draft', label: 'Unpublish', cls: 'btn-warn', icon: ICON.eyeOff,
      ask: 'Unpublish this campaign?\n\nThe client link stops working until published again. Selections are kept.' };
    if (s === 'production')  return { to: 'open',  label: 'Reopen selection', cls: 'btn-warn', icon: ICON.reopen,
      ask: 'Reopen selection for the client?\n\nExisting bookings are kept.' };
    return { to: 'production', label: 'Resume campaign', cls: '', icon: ICON.play,
      ask: 'Resume this campaign?' };
  }

  $('campPublish').addEventListener('click', function () {
    var c = state.campaign;
    var move = publishMove(c.state);
    if (move.ask && !confirm(move.ask)) return;
    db.from('campaigns').update({ state: move.to }).eq('id', c.id).then(function (r) {
      if (r.error) { msg('campWorkMsg', r.error.message, 'err'); return; }
      c.state = move.to;
      log(move.to === 'open' ? 'campaign.opened' : 'campaign.closed', c.title, move.to);
      openCampaign(c);
    });
  });

  $('campDelete').addEventListener('click', function () {
    var c = state.campaign;
    if (!confirm('Delete ' + c.title + '?\n\nAll offers and selections will be removed. This cannot be undone.')) return;
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
    var chosen = state.options.filter(function (o) { return CHARGED.indexOf(o.state) > -1; });
    var goodwill = state.options.filter(function (o) { return o.goodwill; });
    var total = chosen.reduce(function (s, o) { return s + Number(o.rate || 0); }, 0);

    // Invoiced against booked. They should agree; when they do not, the reason
    // is a goodwill replacement and somebody needs to have decided that on
    // purpose rather than discover it at reconciliation.
    var booked = chosen.length + goodwill.length;
    // Counts, then what the client sees: the quoted rates and 8% SST on top.
    $('campTally').innerHTML =
      stat('Creators', c.slots) +
      stat('Options', live.length) +
      stat('Selected', chosen.length + ' of ' + c.slots) +
      '<i class="stat-gap" aria-hidden="true"></i>' +
      stat('Subtotal', money2(total)) +
      stat(taxWord(), money2(sstOf(total))) +
      stat('Total', money2(total + sstOf(total)), 'is-total') +
      (booked > c.slots
        ? '<div class="stat is-warn"><b>' + booked + '</b><span>Booked · ' +
          goodwill.length + ' goodwill</span></div>' : '');

    /* One card per creator. An option and a booking were two lists showing the
       same people at different moments, which meant reading both to know where
       anyone stood. Now the card is the person and the sections inside it are
       the moments: terms first, production once accepted, results once live.
       Order runs by how live the work is. */
    var box = $('creatorList');
    box.innerHTML = '';
    if (!state.options.length) {
      box.innerHTML = '<div class="empty">No creators offered yet.</div>';
    } else {
      state.options.slice().sort(function (a, b) {
        return (cardRank(a) - cardRank(b)) || (Number(a.position || 0) - Number(b.position || 0));
      }).forEach(function (o, i) { box.appendChild(creatorCard(o, i + 1)); });
    }

    // Accepting is offered exactly when the client has chosen something.
    var waiting = state.options.filter(function (o) { return o.state === 'shortlisted'; });
    $('campLock').hidden = !waiting.length;
    $('campLock').textContent = 'Confirm ' + waiting.length +
      (waiting.length === 1 ? ' creator' : ' creators');

    var working = state.options.filter(isLive);
    $('bulkToggle').hidden = !working.length;
    if (!working.length) $('bulkBox').hidden = true;
    $('bulkTitle').textContent = (isDelivery() ? 'Delivery' : 'Shoot') + ' date for all';
    paintRollup(working);
  }

  function cardRank(o) {
    if (isLive(o)) return 0;                                   // the live work
    if (o.state === 'shortlisted') return 1;                   // chosen, awaiting accept
    if (o.state === 'withdrawn' || o.state === 'replaced') return 3;
    return 2;                                                  // still on offer
  }

  function stat(label, value, cls) {
    return '<div class="stat' + (cls ? ' ' + cls : '') + '"><b>' + esc(String(value)) +
      '</b><span>' + esc(label) + '</span></div>';
  }

  function tallyCell(label, value) {
    return '<div class="tally-cell"><b>' + esc(String(value)) + '</b><span>' + esc(label) + '</span></div>';
  }

  /* The rate is this campaign's, so it is changed here and nowhere else. Once
     the client has accepted at a number, that number is what they agreed to,
     and the editor goes away. */
  function editRate(card, o) {
    var body = card.querySelector('.kstep-terms');
    if (body.querySelector('.rate-edit')) return;
    var ed = document.createElement('div');
    ed.className = 'rate-edit';
    var current = String(o.platforms || '').split(',').map(function (x) { return x.trim(); });
    ed.innerHTML =
      platformBoxes(current) +
      '<span class="slugfield"><span class="slugfield-pre">RM</span>' +
      '<input class="input" type="number" min="0" step="10" value="' + esc(o.rate) + '"></span>' +
      '<button class="btn btn-sm btn-primary" type="button">Save</button>' +
      '<button class="btn btn-sm btn-quiet" type="button">Cancel</button>';
    body.appendChild(ed);
    // The platform boxes are inputs too and come first; this is the number.
    var input = ed.querySelector('input[type="number"]');
    input.focus(); input.select();
    ed.querySelectorAll('button')[1].addEventListener('click', function () { ed.remove(); });
    ed.querySelectorAll('button')[0].addEventListener('click', function () {
      var rate = Number(input.value || 0);
      var plats = readBoxes(ed);
      if (!rate || rate <= 0) { msg('campWorkMsg', 'Enter a rate above zero.', 'err'); input.focus(); return; }
      if (!plats.length) { msg('campWorkMsg', 'Tick at least one platform.', 'err'); return; }
      db.from('campaign_options').update({ rate: rate, platforms: plats.join(', ') })
        .eq('id', o.id).then(function (r) {
          if (r.error) { msg('campWorkMsg', r.error.message, 'err'); return; }
          log('campaign.rate', (o.creators || {}).name || '',
              money(o.rate) + ' → ' + money(rate) + ' · ' + plats.join(', '));
          msg('campWorkMsg', '');
          loadOptions();
        });
    });
  }

  /* A client who answers on WhatsApp has still chosen. This is how that choice
     gets into the record, and the lock records that it was keyed in by us. */
  function keyIn(o, to) {
    var name = (o.creators || {}).name || '';
    var chosen = state.options.filter(function (x) { return x.state === 'shortlisted'; }).length;
    var booked = state.options.filter(isLive).length;
    if (to === 'shortlisted' && chosen + booked >= state.campaign.slots) {
      msg('campWorkMsg', 'All creator places are filled.', 'err');
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
      alert(name + ' has been selected by the client. Manage them under Production.');
      return;
    }
    if (!confirm('Withdraw ' + name + ' from the options?')) return;
    db.from('campaign_options').delete().eq('id', o.id).then(function (r) {
      if (r.error) { msg('campWorkMsg', r.error.message, 'err'); return; }
      loadOptions();
    });
  }

  $('optionCancel').addEventListener('click', function () {
    $('addOptionBox').hidden = true;
  });
  $('showAddOption').addEventListener('click', function () {
    $('addOptionBox').hidden = false;
    resetNc();
    ncDraft.note({ campaign: state.campaign.id });
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
        '<span class="muted"> ' + (uniq.join(', ') || 'no links') + '</span></div>' +
        (inCamp ? '<span class="muted">Already offered</span>'
                : '<span class="pickadd">' + platformBoxes(uniq) +
                  '<span class="slugfield"><span class="slugfield-pre">RM</span>' +
                  '<input class="input pickrate" type="number" min="0" step="10" value="' +
                  (c.client_rate || '') + '" placeholder="rate"></span>' +
                  '<button class="btn btn-sm btn-primary" type="button">Add</button></span>');
      if (!inCamp) {
        row.querySelector('button').addEventListener('click', function () {
          addOption(c, readBoxes(row), Number(row.querySelector('.pickrate').value || 0));
        });
      }
      box.appendChild(row);
    });
  }

  function addOption(c, platformNames, rate) {
    if (!platformNames.length) {
      msg('optionMsg', 'Tick at least one platform for ' + c.name + ' to post on.', 'err');
      return;
    }
    if (!rate || rate <= 0) {
      msg('optionMsg', 'Set a rate for ' + c.name + ' on this campaign.', 'err');
      return;
    }
    db.from('campaign_options').insert({
      campaign_id: state.campaign.id,
      creator_id: c.id,
      rate: rate,
      platforms: platformNames.join(', '),
      state: 'option',
      position: state.options.length
    }).then(function (r) {
      if (r.error) {
        msg('optionMsg', /duplicate|unique/i.test(r.error.message)
          ? c.name + ' is already offered in this campaign.' : r.error.message, 'err');
        return;
      }
      msg('optionMsg', c.name + ' added at ' + money(rate) + '.', 'ok');
      loadOptions();
      setTimeout(paintPicker, 150);
    });
  }

  // ---- A new creator, made from inside the campaign ----------------------
  function resetNc() {
    $('ncName').value = ''; $('ncRate').value = '';
    $('ncProfRows').innerHTML = '';
    $('ncProfRows').appendChild(profRow(null, NC_CTX));
    $('ncPlatforms').innerHTML = platformBoxes([]);
    msg('ncDupe', ''); msg('ncMsg', '');
  }
  // A recognised link ticks its platform. It never unticks one, so a box
  // someone cleared on purpose stays cleared.
  function tickFromLinks() {
    var box = $('ncPlatforms');
    if (!box) return;
    profValues(NC_CTX).forEach(function (p) {
      var name = PLATFORM_LABEL[p.platform];
      var input = box.querySelector('.pbox input[value="' + name + '"]');
      if (input && !input.dataset.cleared) input.checked = true;
    });
  }
  $('ncPlatforms').addEventListener('change', function (e) {
    if (e.target.type === 'checkbox' && !e.target.checked) e.target.dataset.cleared = '1';
  });
  $('ncAddProf').addEventListener('click', function () { $('ncProfRows').appendChild(profRow(null, NC_CTX)); });
  $('ncName').addEventListener('input', function () { warnDupes(NC_CTX); });

  $('ncSave').addEventListener('click', function () {
    var name = ($('ncName').value || '').trim();
    var rate = Number($('ncRate').value || 0);
    if (!name) { msg('ncMsg', 'A name is required.', 'err'); return; }
    if (!rate || rate <= 0) { msg('ncMsg', 'Set the rate for this campaign.', 'err'); return; }
    var raw = Array.prototype.slice.call(document.querySelectorAll('#ncProfRows .prof-url'))
      .map(function (i) { return i.value.trim(); }).filter(Boolean);
    var bad = raw.filter(function (u) { return !readProfile(u); });
    if (bad.length) { msg('ncMsg', 'Unrecognised profile links: ' + bad.join(', '), 'err'); return; }
    var profiles = profValues(NC_CTX);
    var plats = readBoxes($('ncPlatforms'));
    if (!plats.length) { msg('ncMsg', 'Select at least one platform.', 'err'); return; }

    // Kept in the roster with this as her usual rate, since it is the only
    // number known for her yet. The offer carries it independently.
    db.from('creators').insert({ name: name, client_rate: rate, created_by: who() || null })
      .select().single().then(function (r) {
        if (r.error) { msg('ncMsg', r.error.message, 'err'); return; }
        var created = r.data;
        var rows = profiles.map(function (p) {
          return { creator_id: created.id, platform: p.platform, url: p.url, handle: p.handle };
        });
        var offer = function (res) {
          if (res && res.error) {
            msg('ncMsg', /duplicate|unique/i.test(res.error.message)
              ? 'A profile link is already assigned to another creator.' : res.error.message, 'err');
            return;
          }
          log('creator.added', name, 'from a campaign');
          created.client_rate = rate;
          loadRoster(function () {
            resetNc();
            ncDraft.note({ campaign: state.campaign.id });
            addOption(created, plats, rate);
          });
        };
        if (!rows.length) offer(null);
        else db.from('creator_profiles').insert(rows).then(offer);
      });
  });

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

  /* Every step forward has a step back. Things go wrong, a status gets clicked
     twice, a client asks to undo: none of that should mean deleting the
     campaign and building it again. */
  function prevState(s) {
    if (s === 'changes') return 'reviewing';           // the branch folds back
    var i = PIPELINE.indexOf(s);
    return i > 0 ? PIPELINE[i - 1] : null;             // confirmed is the floor
  }
  function wordFor(s) { return (OPTION_WORD[s] || [s])[0]; }

  function isLive(o) { return IN_PRODUCTION.indexOf(o.state) > -1; }

  // Reads the same way it does on the client's page.
  function niceDate(d) {
    if (!d) return '';
    var dt = new Date(d + 'T00:00:00');
    if (isNaN(dt.getTime())) return String(d);
    return dt.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
  }

  var TICK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m5 13 4 4L19 7"/></svg>';
  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>';

  function field(label, id, value, type, ph, cls) {
    return '<label class="kfield ' + (cls || '') + '"><span>' + esc(label) + '</span>' +
      '<input class="input" data-f="' + id + '" type="' + (type || 'text') + '" value="' +
      esc(value == null ? '' : value) + '" placeholder="' + esc(ph || '') + '"></label>';
  }

  /* The exceptional actions. They used to be buttons in the row, at the same
     weight as Save, which is the wrong weight for something that happens a few
     times a year. A menu says "there is more here" without shouting it. */
  function menuItem(action, label, cls) {
    return '<button class="kmenu-item ' + (cls || '') + '" data-a="' + action + '" type="button">' +
      '<b>' + esc(label) + '</b></button>';
  }

  function cardMenu(o) {
    var items = '';
    if (o.state === 'option' || o.state === 'backup') {
      items += menuItem('pick', 'Confirm for client');
      items += menuItem('del', 'Remove', 'is-danger');
    }
    if (o.state === 'shortlisted') {
      items += menuItem('unpick', 'Undo selection');
    }
    if (isLive(o)) {
      items += menuItem('unbook', 'Revert to options');
      items += menuItem('withdraw', 'Withdrawn');
      items += menuItem('replace', 'Replaced', 'is-danger');
    }
    return items ? '<div class="kmenu" data-menu hidden>' + items + '</div>' : '';
  }

  var CHEV = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>';

  /* Which production cards are open. Ten creators in production is ten
     cards; folded, each is one line, and the one being worked on is open. */
  var openCards = {};

  /* One creator, one card. What is inside depends only on where they have got
     to: terms while they are an option, terms plus production once accepted,
     results once the post is live. */
  function creatorCard(o, no) {
    var cr = o.creators || {};
    var word = OPTION_WORD[o.state] || [o.state, ''];
    var live = isLive(o);
    var dead = o.state === 'withdrawn' || o.state === 'replaced';
    var agreed = live || o.state === 'shortlisted';
    var canEdit = ['option', 'backup', 'shortlisted'].indexOf(o.state) > -1;
    var plats = platformsOf(o).join(' · ');
    var advance = live ? nextState(o.state) : null;
    var back = live ? prevState(o.state) : null;

    // The draft is a step of its own: it exists only once filming is done.
    var stage = PIPELINE.indexOf(o.state === 'changes' ? 'reviewing' : o.state);
    var drafting = live && stage >= PIPELINE.indexOf('pending_draft');
    var open = !live || !!openCards[o.id];

    var card = document.createElement('article');
    card.className = 'kcard' + (live ? ' is-live' : '') + (dead ? ' is-off' : '') +
      (o.state === 'reviewing' ? ' is-waiting' : '') + (live && !open ? ' is-folded' : '');
    card.setAttribute('data-state', o.state);

    // Folded, the card is one line: the date, the platforms, the money.
    var sum = live ? [
      o.visit_date ? niceDate(o.visit_date) + (o.visit_time ? ', ' + o.visit_time : '')
                   : visitWord() + ' TBC',
      plats, money(o.rate)
    ].filter(Boolean).join(' · ') : '';

    card.innerHTML =
      '<header class="kcard-head">' +
        (live ? '<button class="kfold" data-a="fold" type="button" aria-label="Details" ' +
          'aria-expanded="' + String(open) + '">' + CHEV + '</button>' : '') +
        (no ? '<span class="kcard-no">' + no + '</span>' : '') +
        '<span class="kcard-name">' + esc(cr.name || '') + '</span>' +
        '<span class="tone ' + (word[1] || 'tone-plain') + '">' + esc(word[0]) + '</span>' +
        (o.is_replacement ? '<span class="tone is-warn">Replacement</span>' : '') +
        (o.goodwill ? '<span class="tone is-warn">Goodwill</span>' : '') +
        (sum ? '<span class="kcard-sum">' + esc(sum) + '</span>' : '') +
        (dead ? '' : '<button class="kmenu-btn" data-a="menu" type="button" ' +
          'aria-label="More actions" aria-expanded="false">' + DOTS + '</button>') +
      '</header>' +
      cardMenu(o) +
      '<div class="kcard-body" data-body' + (open ? '' : ' hidden') + '>' +

      // Money and platforms: one line, ticked off once the client has agreed.
      '<div class="kstep kstep-terms' + (agreed ? ' is-done' : '') + '">' +
        '<span class="kstep-mark" aria-hidden="true">' + (agreed ? TICK : '') + '</span>' +
        '<span class="kstep-label">Terms</span>' +
        '<span class="kstep-sum"><b>' + esc(money(o.rate)) + '</b>' +
          (plats ? '<span>' + esc(plats) + '</span>' : '') + '</span>' +
        (canEdit ? '<button class="btn btn-sm btn-quiet" data-a="rate" type="button">Edit</button>'
                 : '<span class="kstep-note">Agreed</span>') +
      '</div>' +

      (live ?
      '<div class="kstep kstep-work">' +
        '<div class="kstep-title">' + (isDelivery() ? 'Delivery' : 'Shoot') + '</div>' +
        '<div class="kfields">' +
          field('Date', 'visit_date', o.visit_date, 'date') +
          field('Time', 'visit_time', o.visit_time, 'text', '') +
          (isDelivery() ? field('Tracking no.', 'tracking_no', o.tracking_no, 'text', '') : '') +
          field('Publish date', 'planned_publish', o.planned_publish, 'date', '', 'kfield-pub') +
          '<label class="kfield kfield-wide"><span>Notes</span>' +
            '<input class="input" data-f="notes" value="' + esc(o.notes || '') + '"></label>' +
        '</div>' +
      '</div>' +
      (drafting ?
      '<div class="kstep kstep-work">' +
        '<div class="kstep-title">Draft</div>' +
        '<div class="kfields">' +
          '<label class="kfield kfield-wide"><span>Draft link</span>' +
            '<input class="input" data-f="draft_url" value="' + esc(o.draft_url || '') +
            '" placeholder="https://"></label>' +
        '</div>' +
      '</div>' : '') +
      '<div class="kstep kstep-work">' +
        '<div class="kactions">' +
          '<button class="btn btn-sm btn-primary" data-a="save" type="button">Save</button>' +
          (advance ? '<button class="btn btn-sm btn-go" data-a="advance" type="button">' +
            esc(wordFor(advance)) + CHEV + '</button>' : '') +
          (back ? '<button class="btn btn-sm btn-quiet" data-a="back" type="button">Revert</button>' : '') +
        '</div>' +
        '<div class="msg" data-msg></div>' +
      '</div>' : '') +

      '<div data-posts></div>' +

      (dead ?
      '<div class="kstep kstep-ended">' +
        '<p class="hint">' + esc(o.drop_reason || 'No reason recorded.') + '</p>' +
        '<button class="btn btn-sm btn-quiet" data-a="reinstate" type="button">Reinstate</button>' +
      '</div>' : '') +
      '</div>';

    if (live) paintPosts(card.querySelector('[data-posts]'), o);
    wireCard(card, o);
    return card;
  }

  function wireCard(card, o) {
    var on = function (sel, fn) {
      var el = card.querySelector('[data-a="' + sel + '"]');
      if (el) el.addEventListener('click', fn);
    };

    var menu = card.querySelector('[data-menu]');
    on('menu', function () {
      var open = menu && menu.hidden;
      shutMenus();
      if (menu) {
        menu.hidden = !open;
        this.setAttribute('aria-expanded', String(open));
      }
    });

    // The header is the fold target; its buttons keep their own jobs.
    var body = card.querySelector('[data-body]');
    var foldBtn = card.querySelector('[data-a="fold"]');
    if (foldBtn) card.querySelector('.kcard-head').addEventListener('click', function (e) {
      if (e.target.closest('button') && e.target.closest('button') !== foldBtn) return;
      var show = body.hidden;
      openCards[o.id] = show;
      body.hidden = !show;
      card.classList.toggle('is-folded', !show);
      foldBtn.setAttribute('aria-expanded', String(show));
    });

    on('rate',      function () { editRate(card, o); });
    on('pick',      function () { keyIn(o, 'shortlisted'); });
    on('unpick',    function () { keyIn(o, 'option'); });
    on('del',       function () { dropOption(o); });
    on('unbook',    function () { unbook(o); });
    on('withdraw',  function () { endOption(o, 'withdrawn'); });
    on('replace',   function () { endOption(o, 'replaced'); });
    on('reinstate', function () { reinstate(o); });
    // Moving forward saves what is typed and checks the step has what it
    // needs: a draft before review, a publish date before scheduling, and
    // the date reached before posted.
    on('advance', function () {
      var to = nextState(o.state);
      var patch = readCard(card);
      var why = blockAdvance(to, patch);
      var m = card.querySelector('[data-msg]');
      if (why) { m.textContent = why; m.className = 'msg err'; return; }
      advanceOption(o, to, patch);
    });
    on('back',      function () { stepBack(o, prevState(o.state)); });

    on('save', function () {
      db.from('campaign_options').update(readCard(card)).eq('id', o.id).then(function (r) {
        var m = card.querySelector('[data-msg]');
        if (r.error) { m.textContent = r.error.message; m.className = 'msg err'; return; }
        m.textContent = 'Saved.'; m.className = 'msg ok';
        loadOptions();
      });
    });
  }

  function readCard(card) {
    var patch = {};
    Array.prototype.forEach.call(card.querySelectorAll('[data-f]'), function (i) {
      var k = i.getAttribute('data-f');
      var v = i.value.trim();
      if (k === 'draft_url') v = absUrl(v);
      patch[k] = v === '' ? null : v;
    });
    return patch;
  }

  function blockAdvance(to, p) {
    if (to === 'reviewing' && !p.draft_url) return 'Draft link required.';
    if (to === 'scheduled' && !p.planned_publish) return 'Publish date required.';
    if (to === 'posted') {
      if (!p.planned_publish) return 'Publish date required.';
      if (p.planned_publish > today()) return 'Publish date is ' + niceDate(p.planned_publish) + '.';
    }
    return '';
  }

  function today() {
    var d = new Date();
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' +
      String(d.getDate()).padStart(2, '0');
  }

  // A link typed without its scheme is still a link.
  function absUrl(u) {
    u = String(u || '').trim();
    if (!u) return '';
    return /^[a-z][a-z0-9+.-]*:\/\//i.test(u) ? u : 'https://' + u.replace(/^\/+/, '');
  }

  function shutMenus() {
    Array.prototype.forEach.call(document.querySelectorAll('.kmenu'), function (m) {
      m.hidden = true;
    });
    Array.prototype.forEach.call(document.querySelectorAll('.kmenu-btn'), function (b) {
      b.setAttribute('aria-expanded', 'false');
    });
  }
  document.addEventListener('click', function (e) {
    if (!e.target.closest || !e.target.closest('.kcard-head, .kmenu')) shutMenus();
  });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') shutMenus(); });

  /* One step back up the line. Posts and results stay where they are, so
     stepping back out of Posted and forward again does not lose the numbers
     somebody already typed in. */
  function stepBack(o, to) {
    var name = (o.creators || {}).name || 'this creator';
    if (!to || !confirm('Revert ' + name + ' to ' + wordFor(to) + '?')) return;
    db.from('campaign_options').update({ state: to }).eq('id', o.id).then(function (r) {
      if (r.error) { msg('campWorkMsg', r.error.message, 'err'); return; }
      log('campaign.stage', name, 'back to ' + to);
      msg('campWorkMsg', name + ': ' + wordFor(to) + '.', 'ok');
      loadOptions();
    });
  }

  /* The booking was made and the client has changed their mind before anything
     was spent. They go back among the options and the slot frees up. */
  function unbook(o) {
    var name = (o.creators || {}).name || 'this creator';
    if (!confirm('Revert ' + name + ' to options?\n\nDates and notes are kept.')) return;
    db.from('campaign_options').update({ state: 'option' }).eq('id', o.id).then(function (r) {
      if (r.error) { msg('campWorkMsg', r.error.message, 'err'); return; }
      log('campaign.unbooked', name, '');
      msg('campWorkMsg', name + ' reverted to options.', 'ok');
      loadOptions();
    });
  }

  // A withdrawal or replacement keyed on the wrong card, undone.
  function reinstate(o) {
    var name = (o.creators || {}).name || 'this creator';
    if (!confirm('Reinstate ' + name + '?\n\nThe recorded reason is cleared.')) return;
    db.from('campaign_options')
      .update({ state: 'confirmed', drop_reason: null, goodwill: false })
      .eq('id', o.id).then(function (r) {
        if (r.error) { msg('campWorkMsg', r.error.message, 'err'); return; }
        log('campaign.reinstated', name, '');
        msg('campWorkMsg', name + ' reinstated.', 'ok');
        loadOptions();
      });
  }

  /* Moving to posted needs somewhere for the numbers to go, and there is one
     row per platform because two placements are two posts. */
  function advanceOption(o, to, fields) {
    var patch = Object.assign({}, fields || {}, { state: to });
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
    var head = '<div class="kstep-title">Results</div>';
    box.className = 'kstep kstep-results';
    box.innerHTML = head + '<div class="empty">Loading…</div>';
    db.from('option_posts').select('*').eq('option_id', o.id).then(function (r) {
      var rows = r.data || [];
      if (!rows.length) {
        box.innerHTML = head + '<div class="empty">No placements recorded.</div>';
        return;
      }
      box.innerHTML = head;
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
          (p.measured_at ? '<div class="muted postrow-measured">Measured ' + esc(niceDate(p.measured_at)) + '</div>' : '') +
          '<div class="msg" data-p-msg></div>';
        w.querySelector('[data-p-save]').addEventListener('click', function () {
          var patch = {};
          Array.prototype.forEach.call(w.querySelectorAll('[data-p]'), function (i) {
            var k = i.getAttribute('data-p');
            var v = i.value.trim();
            if (k === 'post_url') v = absUrl(v);
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
      if (!confirm(name + ' has already filmed.\n\nReplacing them is goodwill: the creator is still paid. Continue?')) return;
      goodwill = true;
    } else if (!confirm((kind === 'withdrawn' ? 'Mark ' + name + ' as withdrawn?'
                                              : 'Replace ' + name + '?') +
        '\n\nThe record is kept for invoice reconciliation.')) {
      return;
    }

    var why = prompt(kind === 'withdrawn' ? 'Reason for withdrawal:' : 'Reason for replacement:') || '';
    db.from('campaign_options')
      .update({ state: kind, drop_reason: why.trim() || null, goodwill: goodwill })
      .eq('id', o.id).then(function (r) {
        if (r.error) { msg('campWorkMsg', r.error.message, 'err'); return; }
        log(kind === 'withdrawn' ? 'campaign.withdrawn' : 'campaign.replaced', name, why);
        msg('campWorkMsg', kind === 'withdrawn'
          ? name + ' withdrawn. The place is open for a replacement.'
          : name + ' replaced.' + (goodwill ? ' Recorded as goodwill.' : ' The place is open.'), 'warn');
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
        (eng ? tallyCell('Cost per engagement', money2(spend / eng)) : '');
    });
  }

  // ---- Closed panels: open on demand, or on their own when there is reason to
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
  disclose('invoiceToggle', 'invoiceBody');

  // ---- Invoice: raised after confirmation, attached here -----------------
  function paintInvoice(c) {
    // The closed panel says what it holds, and opens itself once it holds something.
    $('invoiceSummary').textContent = c.invoice_url
      ? (c.invoice_no ? c.invoice_no + ' · PDF attached' : 'PDF attached')
      : (c.invoice_no ? c.invoice_no + ' · no PDF' : 'Not issued');
    $('invNo').value = String(c.invoice_no || '').replace(/^AINV2/i, '');
    $('invFile').value = '';
    var cur = $('invCurrent');
    if (c.invoice_url) {
      cur.innerHTML =
        '<a class="btn btn-icon" href="' + esc(c.invoice_url) + '" target="_blank" rel="noopener">View invoice' +
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" ' +
        'stroke-linejoin="round" aria-hidden="true"><path d="M14 4h6v6"/><path d="M20 4 11 13"/>' +
        '<path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg></a>' +
        (c.invoice_uploaded_at
          ? '<span class="muted">Uploaded ' + niceDate(String(c.invoice_uploaded_at).slice(0, 10)) + '</span>' : '');
    } else {
      cur.innerHTML = '<span class="muted">No PDF</span>';
    }
    msg('invMsg', '');
  }

  $('invSaveNo').addEventListener('click', function () {
    var c = state.campaign;
    var no = invoiceNo();
    db.from('campaigns').update({ invoice_no: no }).eq('id', c.id).then(function (r) {
      if (r.error) { msg('invMsg', r.error.message, 'err'); return; }
      c.invoice_no = no;
      log('campaign.invoice', c.title, no || 'cleared');
      openCampaign(c);
      msg('invMsg', no ? 'Invoice number saved.' : 'Invoice number cleared.', 'ok');
    });
  });

  /* The PDF goes to S3 by the same signed path media takes, and the campaign
     keeps the public URL. Only the URL is ours to store; the file is the
     accountant's. */
  $('invUpload').addEventListener('click', function () {
    var c = state.campaign;
    var file = $('invFile').files && $('invFile').files[0];
    if (!file) { msg('invMsg', 'Choose the invoice PDF first.', 'err'); return; }
    if (!/pdf$/i.test(file.type) && !/\.pdf$/i.test(file.name)) {
      msg('invMsg', 'The invoice has to be a PDF.', 'err'); return;
    }
    if (!putToS3) { msg('invMsg', 'Uploads are not available on this page.', 'err'); return; }
    msg('invMsg', 'Uploading…');
    db.functions.invoke((cfg.s3 && cfg.s3.functionName) || 'sign-upload', {
      body: { ext: 'pdf', clientId: c.client_id, size: file.size }
    }).then(function (r) {
      if (r.error) throw new Error('Could not start the upload. ' + r.error.message);
      if (!r.data || !r.data.uploadUrl) throw new Error('Upload was refused: ' + ((r.data && r.data.error) || 'unknown reason'));
      return putToS3(r.data.uploadUrl, file, 'application/pdf').then(function () { return r.data.publicUrl; });
    }).then(function (url) {
      var stamp = new Date().toISOString();
      return db.from('campaigns').update({ invoice_url: url, invoice_uploaded_at: stamp })
        .eq('id', c.id).then(function (r) {
          if (r.error) throw new Error(r.error.message);
          c.invoice_url = url; c.invoice_uploaded_at = stamp;
          log('campaign.invoice_file', c.title, c.invoice_no || '');
          openCampaign(c);
          msg('invMsg', 'Invoice uploaded.', 'ok');
        });
    }).catch(function (e) { msg('invMsg', e.message, 'err'); });
  });

  // ---- Locking the selection ---------------------------------------------
  $('campLock').addEventListener('click', function () {
    var picked = state.options.filter(function (o) { return o.state === 'shortlisted'; });
    if (!picked.length) {
      msg('campWorkMsg', 'No creators selected.', 'err');
      return;
    }
    $('lockHeading').textContent = 'Confirm ' + picked.length +
      (picked.length === 1 ? ' creator' : ' creators');
    $('lockList').innerHTML = picked.map(function (o) {
      return '<div class="act"><span class="act-subject">' + esc((o.creators || {}).name || '') +
        '</span><span class="muted act-when">' + money(o.rate) + '</span></div>';
    }).join('');
    $('lockPerson').value = '';
    $('lockBy').textContent = (bridge.actor && bridge.actor()) || '';
    msg('lockMsg', '');
    $('lockSheet').hidden = false;
  });

  function shutLock() { $('lockSheet').hidden = true; }
  $('lockClose').addEventListener('click', shutLock);
  $('lockCancel').addEventListener('click', shutLock);
  $('lockSheet').addEventListener('click', function (e) {
    if (e.target === $('lockSheet')) shutLock();
  });

  $('lockGo').addEventListener('click', function () {
    // Who did this is whoever is signed in; the client's own name is worth
    // keeping when we have it but is not a gate.
    var who = (bridge.actor && bridge.actor()) || '';
    var person = ($('lockPerson').value || '').trim() || who;
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
    return {
      visit_date: $('bulkDate').value || null,
      visit_time: ($('bulkTime').value || '').trim() || null
    };
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
        : 'All rows already have these values. Use Overwrite to replace them.',
        touched ? 'ok' : 'warn');
      log('campaign.bulk', state.campaign.title, touched + ' rows');
      loadOptions();
    }
  }

  $('bulkApply').addEventListener('click', function () { applyBulk(false); });
  $('bulkApplyAll').addEventListener('click', function () {
    if (!confirm('Overwrite these fields on every creator?')) return;
    applyBulk(true);
  });

  // ---- Entry --------------------------------------------------------------
  window.ADspaceCampaigns = {
    // What the address bar should carry for this section.
    urlState: function () {
      return {
        campaign: state.campaign ? state.campaign.id : '',
        tab: (!state.campaign && state.tab === 'roster') ? 'roster' : ''
      };
    },
    /* On entry, read the address rather than starting from the list. An open
       campaign is fetched by id so a refresh lands inside it, not in front of it. */
    enter: function () {
      var params = new URLSearchParams(location.search);
      var id = params.get('campaign');
      if (id && !(state.campaign && state.campaign.id === id)) {
        db.from('campaigns').select('*, clients(name, market, sst_applies)').eq('id', id).single().then(function (r) {
          if (r.error || !r.data) { state.campaign = null; showTab('campaigns'); return; }
          state.tab = 'campaigns';
          Array.prototype.forEach.call(document.querySelectorAll('#sectionCampaigns .tab'), function (b) {
            b.classList.toggle('is-on', b.getAttribute('data-tab') === 'campaigns');
          });
          $('rosterView').hidden = true;
          openCampaign(r.data, true);
        });
        return;
      }
      if (state.campaign) { showTab('campaigns'); return; }
      showTab(params.get('tab') === 'roster' ? 'roster' : 'campaigns');
      var forClient = params.get('new');
      if (forClient) {
        loadClients(function () {
          openCampForm(null);
          $('campClient').value = forClient;
          $('campTitle').focus();
        });
      }
    }
  };
  if (bridge.campaignsReady) bridge.campaignsReady();
})();
