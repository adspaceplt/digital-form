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

  var W = window.ADspaceWords;   // read by STATE_WORD below, so it is set first
  // The mark that says a link leaves the page.
  var EXT = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" '
    + 'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
    + '<path d="M14 4h6v6"/><path d="M20 4 11 13"/>'
    + '<path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg>';
  var LINK_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" ' +
    'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7"/>' +
    '<path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7"/></svg>';
  var bridge = window.ADspaceAdmin || {};
  var ICON    = bridge.ICON || {};
  var log     = bridge.log || function () {};
  var who     = bridge.actor || function () { return ''; };
  /* A logged address read as a person, through the console's one map. */
  var whoName = bridge.whoName || function (e) { return e || ''; };
  var putToS3 = bridge.putToS3;
  var cfg     = window.ADSPACE_CONFIG || {};
  var setUrl  = bridge.setUrl || function () {};
  /* A pane is a move somebody made, so it pushes a history entry and Back and
     Forward walk the campaign. */
  var pushUrl = bridge.pushUrl || setUrl;
  var restoreScroll = bridge.restoreScroll || function () {};

  function maySeeActivity() {
    return Boolean(bridge.may && bridge.may('activity', 'view'));
  }

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
    /* rednote serves the same profile under two hostnames: xiaohongshu.com,
       and rednote.com, which is the one the app hands out now. The profile id
       in the path is identical, so both resolve to the same creator and a
       link copied from either is accepted. */
    { id: 'xhs',       label: 'rednote',   re: /(?:xiaohongshu\.com|rednote\.com)\/user\/profile\/([0-9a-zA-Z]{8,40})/i },
    { id: 'xhs',       label: 'rednote',   re: /xhslink\.(?:com|cn)\/\S+/i, anonymous: true },
    { id: 'instagram', label: 'Instagram', re: /instagram\.com\/([A-Za-z0-9._]{1,40})/i },
    { id: 'tiktok',    label: 'TikTok',    re: /tiktok\.com\/@([A-Za-z0-9._]{1,40})/i },
    { id: 'facebook',  label: 'Facebook',  re: /facebook\.com\/([A-Za-z0-9.]{2,60})/i }
  ];
  var PLATFORM_LABEL = { xhs: 'rednote', instagram: 'Instagram', tiktok: 'TikTok', facebook: 'Facebook' };
  var PLATFORM_NAMES = ['rednote', 'Instagram', 'TikTok', 'Facebook'];

  /* Where she posts for THIS campaign is proposed by us, one tick per
     platform. Her profile links only decide which boxes start ticked; a
     creator with two accounts may still be booked for one of them. */
  /* With `links`, each box carries the field the tick may make necessary,
     folded to nothing inside the box itself. A labelled field arriving after
     the Add button put what you type downstream of the button that sends it,
     and reflowed the row every time a tick moved. */
  function platformBoxes(ticked, links) {
    return '<span class="pboxes">' + PLATFORM_NAMES.map(function (name) {
      return '<span class="pbox">' +
        '<label class="pbox-tick"><input type="checkbox" value="' + name + '"' +
        (ticked.indexOf(name) > -1 ? ' checked' : '') + '><span>' + name + '</span></label>' +
        (links ? '<input class="input input-sm pbox-link" data-p="' + name + '" disabled' +
          ' aria-label="' + name + ' profile URL" placeholder="Profile URL">' : '') +
        '</span>';
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

  var state = { tab: 'campaigns', campaign: null, creators: [], clients: [], options: [], team: [], editing: null };
  /* Loading, empty and failed are said one way across the console. */
  var UI = window.ADspaceState;

  // ---- Tabs ---------------------------------------------------------------
  function mayPart(part, level) { return Boolean(bridge.may && bridge.may(part, level || 'work')); }
  function showTab(name) {
    // The Creators List is a part of the section and may be shut to a group.
    if (name === 'roster' && !mayPart('campaigns.creators', 'view')) name = 'campaigns';
    state.tab = name;
    $('campListView').hidden = !(name === 'campaigns' && !state.campaign);
    $('campWork').hidden     = !(name === 'campaigns' && state.campaign);
    $('rosterView').hidden   = name !== 'roster';
    Array.prototype.forEach.call(document.querySelectorAll('#campSectionTabs .tab'), function (b) {
      b.classList.toggle('is-on', b.getAttribute('data-tab') === name);
    });
    setUrl();
    if (name === 'roster') loadRoster(function () { rosterDraft.restore(); restoreScroll(); });
    if (name === 'campaigns' && !state.campaign) { loadCampaigns(); campDraft.restore(); restoreScroll(); }
  }
  Array.prototype.forEach.call(document.querySelectorAll('#campSectionTabs .tab'), function (b) {
    b.addEventListener('click', function () { showTab(b.getAttribute('data-tab')); });
  });

  // ---- Creators list ------------------------------------------------------
  function loadRoster(then) {
    if (!state.creators.length) UI.skeleton($('rosterList'), 4);
    db.from('creators').select('*, creator_profiles(*)').order('name').then(function (r) {
      if (r.error) {
        state.creators = [];
        UI.failLine($('rosterList'), 'The creators list', r.error.message, function () { loadRoster(then); });
        return;
      }
      state.creators = r.data || [];
      loadRecord(function () { paintRoster(); if (then) then(); });
    });
  }

  /* What tells two creators apart is not what they are, it is what they have
     done. Five rows reading rednote · RM 360 differ in nothing but a name, and
     a monogram cannot rescue that: most of this roster is Chinese names, so a
     first character disc gave 是yy呀 and 是甜甜啊 the same grey circle. The
     record is the differentiator a campaign is planned on, so the row carries
     it: how many campaigns they have run for us, when they last shot, and
     whether they are on one right now. */
  /* Confirmed onwards is what counts as having worked with us: an offer
     nobody took up is not a campaign they have run. There is deliberately no
     "on a campaign" mark, because a creator is often on several at once, so
     the chip was true of nearly every row and told nobody anything. */
  /* Every step from Confirmed onward counts as a campaign the creator has
     run, whichever step it is at now. `submitted` arrived after this list
     was written and was left out of it, so a creator whose draft was waiting
     on release showed — in the Campaigns column and came back to `1` when
     the team released it: a booking that vanishes and reappears with its
     step is not a record. Only an offer never confirmed, a withdrawal and a
     replacement stay out. */
  var DONE_STATES = ['confirmed', 'pending_visit', 'pending_delivery', 'pending_draft',
                     'submitted', 'reviewing', 'changes', 'scheduled', 'posted', 'completed'];

  function loadRecord(then) {
    state.record = {};
    db.from('campaign_options').select('creator_id, state, visit_date, added_at')
      .then(function (r) {
        (r.data || []).forEach(function (o) {
          if (DONE_STATES.indexOf(o.state) < 0) return;
          var rec = state.record[o.creator_id] ||
            (state.record[o.creator_id] = { n: 0, last: '' });
          rec.n++;
          var when = o.visit_date || (o.added_at || '').slice(0, 10);
          if (when > rec.last) rec.last = when;
        });
        then();
      });
  }

  /* "4 · last Aug 2026" for somebody who has worked, and the same mute mark
     every other cell in this console gives a value nobody has filled in for
     somebody who has not. "None yet" written out on every row of a roster
     where almost nobody has been booked is a sentence repeated three hundred
     times where one character says it, under a heading that has already said
     what the cell is. */
  function recordLine(c) {
    var rec = state.record && state.record[c.id];
    if (!rec) return '';
    return rec.n + (rec.last ? ' · last ' + monthOf(rec.last) : '');
  }
  function monthOf(d) {
    var t = new Date(d + 'T00:00:00');
    if (isNaN(t)) return d;
    return ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct',
            'Nov', 'Dec'][t.getMonth()] + ' ' + t.getFullYear();
  }

  /* The creators list is a few hundred people, so it needs the two things a
     list that long always needs: a way to cut it down, and somewhere to be
     inside it. The cut is the platform, because that is the first thing a
     campaign fixes. The bands are the fee, because that is the second, because
     every creator is in exactly one, and because a flat four hundred rows with one
     heading at the top tells you nothing about where you are. */
  var BANDS = [
    ['Up to RM 300',    function (r) { return r > 0 && r <= 300; }, 'rm300'],
    ['RM 301 to 500',   function (r) { return r > 300 && r <= 500; }, 'rm500'],
    ['RM 501 to 800',   function (r) { return r > 500 && r <= 800; }, 'rm800'],
    ['Above RM 800',    function (r) { return r > 800; }, 'rm800plus'],
    ['On quote',        function (r) { return !r; }, 'quote']
  ];

  function paintRoster() {
    var box = $('rosterList');
    if (!box) return;
    var q = ($('rosterSearch').value || '').trim().toLowerCase();
    var plat = $('rosterPlatform') ? $('rosterPlatform').value : 'all';
    var shown = state.creators.filter(function (c) {
      if (plat !== 'all' && !(c.creator_profiles || []).some(function (p) { return p.platform === plat; })) return false;
      if (!q) return true;
      var hay = c.name + ' ' +
        (c.creator_profiles || []).map(function (p) { return p.handle || p.url; }).join(' ');
      return hay.toLowerCase().indexOf(q) > -1;
    });
    var narrowed = q || plat !== 'all';
    $('rosterCount').textContent = !state.creators.length ? '' :
      (narrowed ? shown.length + ' of ' + state.creators.length
                : state.creators.length + (state.creators.length === 1 ? ' creator' : ' creators'));

    box.innerHTML = '';
    if (!state.creators.length) {
      UI.emptyLine(box, 'No creators yet.', 'Add the first creator', function () {
        $('showAddCreator').click();
      });
      return;
    }
    if (!shown.length) {
      UI.emptyLine(box, 'No matches.', 'Clear the filters', function () {
        $('rosterSearch').value = '';
        if ($('rosterPlatform')) $('rosterPlatform').value = 'all';
        paintRoster();
      });
      return;
    }
    /* A card per fee band under its own heading, the shape every directory
       in this console takes. A creator is a person with a fee, so the row is
       the one this console uses for every list of records: name heaviest,
       the money next, the rest mute. It used to borrow the Short Links row,
       which set the name in the slug's monospace face and pushed two icon
       buttons onto a line of their own. */
    var GRP = window.ADspaceGroup;
    var byName = function (a) {
      return a.slice().sort(function (x, y) { return String(x.name || '').localeCompare(String(y.name || '')); });
    };
    /* Stood down people are not booked, so they are not in the budget bands:
       they are one card at the foot, shut by default, where they can still be
       edited and put back without sitting between two creators who are
       available. */
    var live = shown.filter(function (c) { return c.active !== false; });
    var down = shown.filter(function (c) { return c.active === false; });
    var groups = BANDS.map(function (band) {
      return [band[2], band[0], byName(live.filter(function (c) { return band[1](Number(c.client_rate || 0)); })), false];
    });
    groups.push(['inactive', 'Inactive', byName(down), true]);
    groups.forEach(function (g) {
      if (!g[2].length) return;
      box.appendChild(GRP.section({
        route: 'creators', key: g[0], name: g[1], count: g[2].length,
        shut: !narrowed && GRP.shut('creators', g[0], g[3], g[2].length === shown.length),
        table: function () {
          var table = GRP.table('svc-row cr-row',
            ['Creator', 'Profiles', 'Campaigns', { text: 'Fee', cls: 'svc-rate' }, '']);
          GRP.more(table, g[2], 30, 'creators', rosterRow);
          return table;
        }
      }));
    });
  }

  /* The monogram is gone. It was put here to make a row findable by eye, the
     way every contacts list does it, and on this roster it cannot: a first
     character disc is the same index that was already rejected for the bands,
     and it fails for the same reason. Five identical grey circles over five
     identical platform chips is decoration standing where information should
     be. The name starts the row now, and what follows it is what differs. */

  function rosterRow(c) {
    {
      var row = document.createElement('div');
      var off = c.active === false;
      row.className = 'svc-row cr-row' + (off ? ' is-off' : '');
      /* One line under the name carrying everything that differs: where they
         post, who they are there, and what they have done for us. The profile
         used to be a column of outbound buttons, which on a phone took a third
         line of its own and left a row 110px tall with an empty half; the
         platform is a word here and opening the profile is an item in the ⋯,
         because on this screen a creator is a record being managed rather than
         a profile being browsed. The handle rides along only where it reads as
         a name: rednote keeps a profile id in that field and
         5e3262fd00000000010015b6 is longer than the creator it belongs to. */
      /* The profile is a link on the row again, as the word and the mark that
         says it leaves the page, without the chip's border: a creator is
         looked up constantly and a link folded into the ⋯ costs two taps for
         the commonest thing on this screen. The handle rides along only where
         it reads as a name, because rednote keeps a profile id in that field
         and 5e3262fd00000000010015b6 says nothing to anybody. */
      var profs = c.creator_profiles || [];
      var links = profs.map(function (p) {
        var h = String(p.handle || '');
        return '<a class="plink plink-bare" href="' + esc(p.url) + '" target="_blank" rel="noopener">' +
          esc(PLATFORM_LABEL[p.platform] || p.platform) +
          (h && h.length <= 18 ? ' <b>' + esc(h) + '</b>' : '') + EXT + '</a>';
      }).join('');
      row.innerHTML =
        '<span class="svc-name cr-who"><b>' + esc(c.name) +
          (off ? ' <span class="tone">Inactive</span>' : '') + '</b></span>' +
        '<span class="cr-links">' + (links || '<span class="muted">No links</span>') + '</span>' +
        '<span class="cr-rec">' + (recordLine(c)
          ? esc(recordLine(c)) : '<span class="muted">—</span>') + '</span>' +
        '<span class="svc-rate">' + (c.client_rate ? esc(money(c.client_rate))
                                                   : '<span class="muted">RM</span>') + '</span>' +
        '<span class="team-act">' +
          '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
          '<div class="kmenu" data-menu hidden>' +
            menuItem('edit', 'Edit') +
            /* Standing a creator down was named by the error you got when a
               delete was refused and existed nowhere on the page. */
            menuItem('state', off ? 'Set active' : 'Set inactive') +
            menuItem('del', 'Remove', 'is-danger', 'campaigns:manage') +
          '</div>' +
        '</span>';
      rowMenu(row);
      row.querySelector('[data-a="edit"]').addEventListener('click', function () {
        creatorOpener = this; openCreator(c);
      });
      row.querySelector('[data-a="del"]').addEventListener('click', function () { removeCreator(c); });
      row.querySelector('[data-a="state"]').addEventListener('click', function () {
        shutMenus();
        db.from('creators').update({ active: off }).eq('id', c.id).then(function (r) {
          if (r.error) { alert(r.error.message); return; }
          log(off ? 'creator.on' : 'creator.off', c.name, '');
          loadRoster();
        });
      });
      return row;
    }
  }

  /* A creators list ⋯ hangs off a table row, so it is placed on the viewport
     rather than inside the row that would clip it. */
  function rowMenu(row) {
    var btn = row.querySelector('[data-a="menu"]'), menu = row.querySelector('[data-menu]');
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

  // ---- Profile link rows --------------------------------------------------
  // Two forms build these: the creators list's, and the one inside a campaign. Each
  // names its own rows, name field and warning line.
  var ROSTER_CTX = { rows: 'profRows',   name: 'crName', warn: 'dupeWarn' };
  var NC_CTX     = { rows: 'ncProfRows', name: 'ncName', warn: 'ncDupe' };

  function profRow(p, ctx) {
    var row = document.createElement('div');
    row.className = 'profrow';
    row.innerHTML =
      '<input class="input prof-url" aria-label="Profile link" placeholder="https://www.xiaohongshu.com/user/profile/…">' +
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
      msg(ctx.warn, 'Already in the creators list as ' + hits.join(', ') + '. Saving will be refused.', 'err');
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
        msg(ctx.warn, 'Similar name already in the creators list: ' + near.join(', ') + '.', 'warn');
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
    paintCode(c);
    msg('creatorMsg', ''); msg('dupeWarn', '');
    $('addCreatorBox').hidden = false;
    if (!restoring) rosterDraft.note({ editing: c ? c.id : null });
    $('crName').focus();
  }

  /* The code reads in two groups of four, because it is meant to be read down
     a phone. The stored value has no dash in it, and the page strips whatever
     a creator types, so the grouping is presentation and nothing depends on
     it. */
  function prettyCode(c) {
    var v = String(c || '');
    return v.length === 8 ? v.slice(0, 4) + '-' + v.slice(4) : v;
  }
  function creatorLink(c) {
    return location.origin + '/creator/?k=' + encodeURIComponent(c || '');
  }
  function paintCode(c) {
    var box = $('crCodeBox');
    if (!box) return;
    // Nothing to show until the row exists: the code is made when it is saved.
    box.hidden = !(c && c.access_code);
    msg('crCodeMsg', '');
    if (box.hidden) return;
    $('crCode').value = prettyCode(c.access_code);
    $('crCodeLink').value = creatorLink(c.access_code);
  }
  if ($('crCodeCopy')) {
    $('crCodeCopy').addEventListener('click', function () {
      window.ADspaceCopy.to(this, $('crCodeLink').value);
    });
  }
  /* Resetting is how a code that has been forwarded to the wrong person is
     taken back, so it asks first: the creator's old link stops working and
     they have to be sent the new one. */
  if ($('crCodeReset')) {
    $('crCodeReset').addEventListener('click', function () {
      var c = state.editing;
      if (!c) return;
      if (!confirm('Reset the access code for ' + c.name + '? Their current link stops working.')) return;
      db.rpc('reset_creator_code', { p_creator: c.id }).then(function (r) {
        if (r.error) { msg('crCodeMsg', r.error.message, 'err'); return; }
        var code = (r.data && r.data.code) || '';
        c.access_code = code;
        paintCode(c);
        msg('crCodeMsg', 'New code issued. Send them the new link.', 'ok');
        log('creator.code', c.name, '');
        loadRoster();
      });
    });
  }

  /* The sheet opens over the list and hands it straight back, so comparing
     one creator against the rest never costs the page you were reading. */
  var creatorOpener = null;
  function shutCreatorSheet() {
    $('addCreatorBox').hidden = true;
    state.editing = null;
    rosterDraft.clear();
    if (creatorOpener && document.body.contains(creatorOpener)) creatorOpener.focus();
    creatorOpener = null;
  }
  $('creatorSheetClose').addEventListener('click', shutCreatorSheet);
  $('addCreatorBox').addEventListener('click', function (e) {
    if (e.target === this) shutCreatorSheet();
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && !$('addCreatorBox').hidden) shutCreatorSheet();
  });
  $('showAddCreator').addEventListener('click', function () {
    creatorOpener = this;
    openCreator(null);
  });
  $('cancelAddCreator').addEventListener('click', function () {
    shutCreatorSheet();
  });
  $('addProfRow').addEventListener('click', function () { $('profRows').appendChild(profRow(null, ROSTER_CTX)); });
  $('rosterSearch').addEventListener('input', paintRoster);
  $('rosterPlatform').addEventListener('change', paintRoster);
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
          shutCreatorSheet();
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
    if (!confirm('Remove ' + c.name + ' from the creators list?\n\nExisting campaign records are kept.')) return;
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
  /* The same list, the same rule, as the client record's Person in charge: the
     team is chosen from, never typed, and a name already on a campaign that has
     since left the team stays as its own option rather than being cleared by
     the next save. */
  function peopleSelect(el, team, current) {
    if (!el) return;
    var keep = current != null ? current : el.value;
    var names = team.map(function (m) { return m.name; });
    if (keep && names.indexOf(keep) < 0) names.push(keep);
    el.innerHTML = '<option value="">Unassigned</option>' +
      names.map(function (n) { return '<option value="' + esc(n) + '">' + esc(n) + '</option>'; }).join('');
    el.value = keep || '';
  }

  function loadTeam(then) {
    db.from('team_members').select('name').eq('active', true).order('name').then(function (r) {
      state.team = (r.data) || [];
      if (then) then();
    }, function () { if (then) then(); });
  }

  function loadClients(then) {
    // The form needs both lists, and the team is small, so they travel together
    // rather than leaving four call sites to remember the second one.
    var inner = then;
    then = function () { loadTeam(inner); };
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

  var campFind = '', campStateFilter = 'all', campSums = {};

  function loadCampaigns() {
    var box = $('campCards');
    fillCampStates();
    if (!state.campaigns) UI.skeleton(box, 3);
    db.from('campaigns').select('*, clients(name, market, sst_applies, logo_url)').order('created_at', { ascending: false })
      .then(function (r) {
        if (r.error) {
          state.campaigns = null;
          UI.failLine(box, 'Campaigns', r.error.message, loadCampaigns);
          return;
        }
        state.campaigns = r.data || [];
        // The amount on a card is what the client is charged: the rates of
        // everyone selected or booked, plus tax, in the client's currency.
        db.from('campaign_options').select('campaign_id, rate, state').then(function (q) {
          campSums = {};
          (q.data || []).forEach(function (o) {
            if (CHARGED.indexOf(o.state) < 0) return;
            campSums[o.campaign_id] = (campSums[o.campaign_id] || 0) + Number(o.rate || 0);
          });
          paintCampaigns();
        });
      });
  }

  function campMatch(c) {
    if (campStateFilter !== 'all' && c.state !== campStateFilter) return false;
    if (!campFind) return true;
    var hay = (campName(c) + ' ' + ((c.clients || {}).name || '')).toLowerCase();
    return hay.indexOf(campFind) >= 0;
  }

  function paintCampaigns() {
    var box = $('campCards');
    var all = state.campaigns || [];
    var rows = all.filter(campMatch);
    var count = $('campCount');
    if (count) {
      count.textContent = !all.length ? ''
        : rows.length === all.length ? all.length + (all.length === 1 ? ' campaign' : ' campaigns')
        : rows.length + ' of ' + all.length;
    }
    box.innerHTML = '';
    if (!all.length) { box.innerHTML = '<div class="empty">No campaigns.</div>'; return; }
    if (!rows.length) {
      UI.emptyLine(box, 'No matches.', 'Clear the filters', function () {
        campFind = ''; campStateFilter = 'all';
        if ($('campFind')) $('campFind').value = '';
        if ($('campStatePick')) $('campStatePick').value = 'all';
        paintCampaigns();
      });
      return;
    }
    /* A card per state under its own heading, the shape every directory in
       this console takes: three campaigns as three tiles read as a dashboard
       and thirty as a wall, and one surface with the states as uppercase
       divider rows was sent back on Clients. Completed stays shut by
       default; a filter opens every card. */
    var GRP = window.ADspaceGroup;
    var filtered = rows.length !== all.length;
    CAMP_GROUPS.forEach(function (g) {
      var mine = rows.filter(function (c) { return c.state === g; });
      if (!mine.length) return;
      box.appendChild(GRP.section({
        route: 'campaigns', key: g, name: STATE_WORD[g] || g, count: mine.length,
        shut: !filtered && GRP.shut('campaigns', g, g === 'completed', mine.length === rows.length),
        table: function () {
          /* The money column's heading is right aligned over the figures it
             names, but it is still an eyebrow: `.svc-rate` carries the row's
             own 13.5px and set the word AMOUNT three sizes above every other
             heading beside it. */
          var table = GRP.table('camp-row',
            ['Campaign', 'Client', 'Creators', { text: 'Amount', cls: 'is-end' }, 'State', ''], 'crm-register');
          GRP.more(table, mine, 30, 'campaigns', function (c) { return campRow(c, campSums); });
          return table;
        }
      }));
    });
  }

  /* Draft first, then the two live states, then what is finished: the order a
     campaign actually moves in, which is also the order somebody scans for
     what needs them. A state the vocabulary grows is added here. */
  var CAMP_GROUPS = ['draft', 'open', 'production', 'completed'];

  function campRow(c, sums) {
    var cl = c.clients || {};
    var mk = cl.market || 'MY';
    var ap = cl.sst_applies == null ? true : cl.sst_applies;
    var sub = sums[c.id] || 0;
    var amount = sub ? MON.money2(sub + MON.taxOf(sub, mk, ap), mk) : '';
    var row = document.createElement('button');
    row.type = 'button';
    row.className = 'crm-row camp-row';
    row.innerHTML =
      '<span class="crm-c crm-c-name">' + esc(campName(c)) + '</span>' +
      '<span class="crm-c camp-c-client">' + esc(cl.name || '\u2014') + '</span>' +
      '<span class="crm-c camp-c-slots">' + esc(String(c.slots || 0)) + '</span>' +
      /* A campaign nobody has been booked on yet has no amount, and the
         currency sign alone is a fragment that reads like a broken field. */
      '<span class="crm-c svc-rate">' + (amount ? esc(amount)
        : '<span class="muted">' + esc(MON.market(mk).sign) + '</span>') + '</span>' +
      '<span class="crm-c crm-c-stage"><span class="tone ' +
        (c.state === 'draft' ? '' : 'is-ok') + '">' +
        esc(STATE_WORD[c.state] || c.state) + '</span></span>' +
      /* The one line the phone gets: the client, how many creators, and what
         it is worth where that is known. */
      '<span class="crm-c crm-c-meta">' +
        [cl.name, c.slots + (Number(c.slots) === 1 ? ' creator' : ' creators'), amount]
          .filter(Boolean).map(esc).join(' \u00b7 ') + '</span>' +
      '<span class="crm-c crm-c-go" aria-hidden="true">' + CHEV_R + '</span>';
    row.addEventListener('click', function () { openCampaign(c); });
    return row;
  }

  var CHEV_R = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' +
    'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 18l6-6-6-6"/></svg>';

  if ($('campFind')) $('campFind').addEventListener('input', function () {
    campFind = this.value.trim().toLowerCase(); paintCampaigns();
  });
  /* Filled from the one vocabulary, on the first load rather than at parse
     time: `STATE_WORD` is assigned further down this file. */
  function fillCampStates() {
    var pick = $('campStatePick');
    if (!pick || pick.dataset.filled) return;
    pick.dataset.filled = '1';
    Object.keys(STATE_WORD).forEach(function (k) {
      var o = document.createElement('option');
      o.value = k; o.textContent = STATE_WORD[k];
      pick.appendChild(o);
    });
    pick.addEventListener('change', function () { campStateFilter = this.value; paintCampaigns(); });
  }

  // The states whose rate the client pays for.
  var CHARGED = ['shortlisted', 'confirmed', 'pending_visit', 'pending_draft',
                 'submitted', 'reviewing', 'changes', 'scheduled', 'posted', 'completed'];

  /* One vocabulary, from the file that holds it. This map, the one in crm.js
     and the one in words.js each said something different for `open`. */
  var STATE_WORD = W.en.campState;
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
    $('campBackups').checked = c ? Boolean(c.backups_open) : false;
    peopleSelect($('campOwner'), state.team, c ? (c.owner || '') : '');
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
  /* The record's ⋯, placed on the viewport like every other one; Edit details
     is its one item, and choosing it shuts the menu the item sits in. */
  (function () {
    var btn = $('campMenuBtn'), menu = $('campMenu');
    if (!btn || !menu) return;
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      var open = menu.hidden;
      shutMenus();
      menu.hidden = !open;
      btn.setAttribute('aria-expanded', String(open));
      if (open) window.ADspaceMenu.place(btn, menu);
    });
  })();
  $('campEdit').addEventListener('click', function () {
    shutMenus();
    loadClients(function () { openCampForm(state.campaign); });
  });
  $('cancelAddCamp').addEventListener('click', shutCampForm);

  // Every invoice starts AINV, so the field carries it and only the rest is
  // typed. Stored whole, because that is what is on the document.
  function invoiceNo() {
    var rest = ($('invNo').value || '').trim().replace(/^AINV/i, '');
    return rest ? 'AINV' + rest : null;
  }

  /* A campaign is found by its name on every screen that lists one, so a name
     that renders as nothing is a row nobody can pick out. One is live called
     `0`, which JavaScript reads as absent everywhere it is tested for, and the
     strings "null" and "undefined" arrive the same way from a form that was
     handed a value it did not have. The record is never renamed behind
     somebody's back: a row that already carries one is drawn under a stand in
     and stays editable, and a new one is refused at the door. */
  function badTitle(t) {
    var v = String(t == null ? '' : t).trim();
    return !v || v === '0' || v === 'null' || v === 'undefined';
  }
  function campName(c) {
    return badTitle(c && c.title) ? 'Untitled campaign' : String(c.title).trim();
  }

  /* What a campaign's own entry is filed under. The Activity pane reads
     `activity_log` by subject, and every per-creator event was written under
     the creator's name instead of the campaign's: a step moved, a shoot date
     changed, a fee corrected — none of it reached the pane, which showed the
     invoice and the lock and nothing else. The campaign is the subject and the
     creator is named in the detail, which is also how it reads in the global
     record. It is the raw title, because that is the value the pane queries
     with. */
  function logSubject() {
    return (state.campaign && state.campaign.title) || '';
  }

  $('addCamp').addEventListener('click', function () {
    var title = ($('campTitle').value || '').trim();
    var clientId = $('campClient').value;
    if (!clientId) { msg('campMsg', 'A client is required.', 'err'); return; }
    if (badTitle(title)) { msg('campMsg', 'A campaign name is required.', 'err'); return; }
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
      owner: ($('campOwner').value || '').trim() || null,
      backups_open: $('campBackups').checked
    };
    db.from('campaigns').update(patch).eq('id', c.id).select('*, clients(name, market, sst_applies, logo_url)').single().then(function (r) {
      if (r.error) { msg('campMsg', r.error.message, 'err'); return; }
      log('campaign.edited', title, slots + ' creators');
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
      backups_open: $('campBackups').checked,
      access_token: token(),
      // Stated rather than left to the column default. The object we go on to
      // work with is the one we sent, so it has to be complete on its own.
      state: 'draft',
      created_by: who() || null
    }).select('*, clients(name, market, sst_applies, logo_url)').single().then(function (r) {
      if (r.error) { msg('campMsg', r.error.message, 'err'); return; }
      log('campaign.created', title, slots + ' creators');
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
    loadRoster(function () {
      ncDraft.fill(d);
      /* A half typed creator restored into a folded form is a draft nobody can
         see: the fold opens for the work that is already in it. */
      var typed = ($('ncName').value || '').trim() || ($('ncRate').value || '').trim() ||
        Array.prototype.some.call(document.querySelectorAll('#ncProfRows .prof-url'),
          function (i) { return (i.value || '').trim(); });
      $('ncBox').hidden = !typed;
      $('ncToggle').setAttribute('aria-expanded', String(Boolean(typed)));
      paintPicker(); warnDupes(NC_CTX);
    });
  };
  document.addEventListener('input', function (e) {
    if (e.target.closest && e.target.closest('#ncProfRows, #ncPlatforms')) ncDraft.save();
  });
  document.addEventListener('change', function (e) {
    if (e.target.closest && e.target.closest('#ncPlatforms')) ncDraft.save();
  });

  /* ---- The campaign as a command centre -------------------------------
     One campaign is a booking desk, a schedule, a set of deliverables, a
     conversation with the client and an invoice, and all five used to be one
     column: the invoice was above the creators, the results below them, and
     the dates lived inside each card. Seven panes, the pane in the address,
     and the one line that says what it is waiting on us for above them all. */
  var CPANES = ['overview', 'creators', 'schedule', 'client', 'finance', 'activity'];
  var campPane = 'overview';

  function campPaneFromUrl() {
    var t = new URLSearchParams(location.search).get('pane') || '';
    return CPANES.indexOf(t) >= 0 ? t : 'overview';
  }

  function gateCampTabs() {
    Array.prototype.forEach.call(document.querySelectorAll('#campTabs [data-part]'), function (b) {
      b.hidden = !mayPart(b.getAttribute('data-part'), 'view');
    });
  }
  function showCampPane(key) {
    if (CPANES.indexOf(key) < 0) key = 'overview';
    if (key === 'activity' && !maySeeActivity()) key = 'overview';
    var tabOf = document.querySelector('#campTabs .tab[data-pane="' + key + '"]');
    if (tabOf && tabOf.hasAttribute('data-part') && !mayPart(tabOf.getAttribute('data-part'), 'view')) key = 'overview';
    campPane = key;
    Array.prototype.forEach.call(document.querySelectorAll('#campTabs .tab'), function (b) {
      var on = b.getAttribute('data-pane') === key;
      b.classList.toggle('is-on', on);
      b.setAttribute('aria-selected', String(on));
    });
    Array.prototype.forEach.call(document.querySelectorAll('#campWork .rec-pane'), function (el) {
      el.hidden = el.getAttribute('data-pane') !== key;
    });
    if (key === 'finance') setOpen('invoiceToggle', 'invoiceBody', true);
    if (key === 'activity') loadCampLog();
  }

  gateCampTabs();
  Array.prototype.forEach.call(document.querySelectorAll('#campTabs .tab'), function (b) {
    if (b.hasAttribute('data-needs-activity')) b.hidden = !maySeeActivity();
    b.addEventListener('click', function () {
      if (b.getAttribute('data-pane') === campPane) return;
      showCampPane(b.getAttribute('data-pane'));
      pushUrl();
    });
  });
  window.addEventListener('popstate', function () {
    if ($('campWork').hidden) return;
    showCampPane(campPaneFromUrl());
  });

  /* One bulk-date panel, moved to whichever pane asked for it.
     It is markup inside the Creators pane, so Schedule's own Bulk dates
     forwarded the click and opened the form inside a pane nobody was looking
     at: the button appeared to do nothing, and the panel was waiting on the
     Creators tab when somebody next opened it. A second copy of the form would
     be two panels to keep in step, so the panel travels instead — the same
     move the Review Canvas makes with a card's own blocks. */
  function bulkOpen(btn) {
    var box = $('bulkBox');
    var head = btn && btn.closest ? btn.closest('.viewhead') : null;
    if (!box || !head) return;
    var moved = box.previousElementSibling !== head;
    if (moved) head.parentNode.insertBefore(box, head.nextSibling);
    // Moving it means somebody asked for it here; only a second press closes it.
    box.hidden = moved ? false : !box.hidden;
    if (!box.hidden && box.scrollIntoView) box.scrollIntoView({ block: 'nearest' });
  }
  if ($('schedBulk')) $('schedBulk').addEventListener('click', function () { bulkOpen(this); });

  function openCampaign(c, restoring) {
    // A repaint of the campaign already open keeps its panels as they are;
    // arriving at a campaign starts with them folded.
    var same = !!(state.campaign && state.campaign.id === c.id);
    state.campaign = c;
    Array.prototype.forEach.call(document.querySelectorAll('#campTabs [data-needs-activity]'), function (b) {
      b.hidden = !maySeeActivity();
    });
    gateCampTabs();
    parkCampForm();
    $('campListView').hidden = true;
    setUrl();
    $('campWork').hidden = false;
    $('campName').textContent = campName(c);
    // Not the form's input of the same name: this is the line under the title.
    $('campPurposeLine').textContent = c.purpose || '';
    $('campPurposeLine').hidden = !c.purpose;
    paintCampState(c);
    paintCampIdentity(c);
    /* The client and who owns the campaign are on the identity line and the
       due date is in Key dates, so none of the three is repeated here: a fact
       printed twice on one screen is the reader wondering which one is right.
       What is left is what the campaign is, which nothing else says. */
    $('campFacts').innerHTML = [
      ['Push format',       FORMAT_WORD[c.push_format] || c.push_format || ''],
      ['Deliverable',       c.deliverable === 'graphic' ? 'One graphic' : 'One video'],
      ['Slots',             c.slots ? String(c.slots) + (Number(c.slots) === 1 ? ' creator' : ' creators') : ''],
      ['Backups',           c.backups_open ? 'Client may mark backups' : 'Not offered']
    ].filter(function (f) { return f[1] !== ''; }).map(function (f) {
      return '<div><dt>' + f[0] + '</dt><dd>' + (f[1].indexOf('<span') === 0 ? f[1] : esc(f[1])) + '</dd></div>';
    }).join('');
    $('campLink').value = campaignUrl(c);
    $('campOpen').href = campaignUrl(c);
    var linkOpen = c.state !== 'draft';
    $('campLinkState').className = 'tone' + (linkOpen ? ' is-ok' : '');
    $('campLinkState').textContent = linkOpen ? 'Live' : 'Not published';
    showCampPane(restoring ? campPaneFromUrl() : (same ? campPane : 'overview'));
    if (!same) setOpen('invoiceToggle', 'invoiceBody', false);
    // The invoice panel depends on who is confirmed, so it is painted once the
    // creators are in (paintOptions), never from the stale list.
    $('invoicePanel').hidden = true;
    msg('campWorkMsg', '');
    loadOptions();
    if (restoring) {
      campDraft.restore(); ncDraft.restore();
      /* A half typed creator lives in the Creators pane, so a restored draft
         brings its pane with it: the work was there and invisible otherwise. */
      if (!$('addOptionBox').hidden) { showCampPane('creators'); setUrl(); }
      restoreScroll();
    }
  }

  /* The state word and the one forward action are the same two things wherever
     the state moves, so they are painted in one place. Publishing is the
     forward move and carries the weight; unpublishing and reopening are
     warnings, drawn as such. */
  /* The campaign opens on who it is for. The mark is the client's own logo
     where we hold one and their initials where we do not, exactly as the
     client record draws it; `ADspaceState.initials` is the one copy of that
     reading, so "Dale & Cecil" is DC on both screens or on neither. The disc
     stays light in both themes because a client's logo is their artwork. */
  function paintCampIdentity(c) {
    var mark = $('campMark');
    var cl = c.clients || {};
    if (mark) {
      if (cl.logo_url) {
        mark.className = 'rec-mark has-logo';
        mark.innerHTML = '<img src="' + esc(cl.logo_url) + '" alt="">';
      } else {
        mark.className = 'rec-mark';
        mark.textContent = UI.initials(cl.name || campName(c));
      }
    }
    var meta = $('campIdMeta');
    if (!meta) return;
    var bits = [];
    if (cl.name) bits.push(esc(cl.name));
    if (c.owner) bits.push('Person in charge: ' + esc(c.owner));
    meta.innerHTML = bits.join(' &middot; ');
    meta.hidden = !bits.length;
  }

  function paintCampState(c) {
    $('campState').textContent = STATE_WORD[c.state] || c.state;
    $('campState').classList.toggle('is-live', c.state !== 'draft');
    var move = publishMove(c.state);
    $('campPublish').innerHTML = move.icon + esc(move.label);
    $('campPublish').className = 'btn ' + move.cls;
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
    window.ADspaceCopy.to(this, $('campLink').value);
  });

  /* The campaign moves forward and back. A locked selection the client wants to
     revisit reopens; a campaign marked finished too early comes back. Neither
     needs the campaign rebuilding. */
  /* Named apart from the bridge's `ICON`, which this file already holds at the
     top. Two `var ICON` in one scope is one variable: the second assignment
     ran at load and won everywhere, so `ICON.trash` — a bridge key, and the
     only thing the Remove button on a profile link row draws — resolved to
     undefined and that button rendered as an empty red square with no glyph
     and no name on it. The two maps are not even the same shape: the bridge
     holds path data, this one holds whole `<svg>` elements. */
  var STATE_ICON = {
    send:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 3 10 14"/><path d="M21 3 14.5 21l-4.5-7-7-4.5z"/></svg>',
    eyeOff: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m3 3 18 18"/><path d="M10.6 5.1A9.6 9.6 0 0 1 12 5c5 0 9 4.5 9 7a12 12 0 0 1-2.4 3.4"/><path d="M6.5 7.6C4.3 9.1 3 11.2 3 12c0 2.5 4 7 9 7a9.7 9.7 0 0 0 4.2-1"/></svg>',
    reopen: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 12a9 9 0 1 0 2.6-6.4"/><path d="M3 4v4h4"/></svg>',
    play:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m7 5 12 7-12 7z"/></svg>'
  };
  function publishMove(s) {
    if (s === 'draft')      return { to: 'open',  label: 'Publish to client', cls: 'btn-go', icon: STATE_ICON.send };
    if (s === 'open')        return { to: 'draft', label: 'Unpublish', cls: 'btn-warn', icon: STATE_ICON.eyeOff,
      ask: 'Unpublish this campaign?\n\nThe client link stops working until published again. Selections are kept.' };
    if (s === 'production')  return { to: 'open',  label: 'Reopen selection', cls: 'btn-warn', icon: STATE_ICON.reopen,
      ask: 'Reopen selection for the client?\n\nExisting bookings are kept.' };
    return { to: 'production', label: 'Resume campaign', cls: '', icon: STATE_ICON.play,
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
    if (!confirm('Delete ' + campName(c) + '?\n\nAll offers and selections will be removed. This cannot be undone.')) return;
    db.from('campaigns').delete().eq('id', c.id).then(function (r) {
      if (r.error) { msg('campWorkMsg', r.error.message, 'err'); return; }
      log('campaign.deleted', c.title, c.invoice_no || '');
      $('campBack').click();
    });
  });

  // ---- Options ------------------------------------------------------------
  /* The step words and their colours come from js/words.js, so the card here
     and the chip on the client's page cannot drift. "Replaced" is the console's
     alone: a client never sees that a creator was swapped, only who is on the
     campaign now. */
  var OPTION_WORD = Object.keys(W.en.step).reduce(function (m, k) {
    m[k] = [W.en.step[k], W.tone(k)]; return m;
  }, { replaced: ['Replaced', 'is-danger'] });

  function loadOptions() {
    db.from('campaign_options').select('*, creators(name, access_code, creator_profiles(platform, url))')
      .eq('campaign_id', state.campaign.id).order('position').then(function (r) {
        state.options = (r.data) || [];
        syncCampState();
        /* What each creator uploaded on their own page, so the team reviews it
           here rather than opening a folder somebody had to find. Scoped to
           this campaign's bookings: an unfiltered read takes the first page of
           every deliverable in the database, so once the archive passes a
           thousand files the newest campaign is the one that comes back
           empty. */
        var ids = state.options.map(function (o) { return o.id; });
        state.files = {};
        if (!ids.length) { paintOptions(); return; }
        db.from('campaign_deliverables').select('*').is('removed_at', null)
          .in('option_id', ids).order('uploaded_at')
          .then(function (d) {
            (d.data || []).forEach(function (f) {
              (state.files[f.option_id] || (state.files[f.option_id] = [])).push(f);
            });
            paintOptions();
          }, paintOptions);
      });
  }

  /* The Draft step has two routes into it and only ever named one. A field
     labelled "Draft link" beside nothing else read as the only way, so nobody
     was reminded that the creator can send it themselves, and the Drive
     shuffle carried on. The step says which route it is waiting on, and names
     the paste field as the fallback it is. */
  function draftGuide(o) {
    var files = (state.files && state.files[o.id]) || [];
    if (files.length || o.draft_url) return '';
    return hint('draft-route',
      'Send ' + ((o.creators || {}).name || 'the creator') + ' their portal link and they upload here ' +
      'themselves. Upload for them below if they cannot, or paste a link.');
  }

  /* An instruction is for the first few times somebody meets a screen, and
     after that it is furniture: this portal carries no explanatory copy for
     exactly that reason. So it opens by itself while the step is still new and
     retires behind its own mark once it has been read three times, where it
     can still be opened by anybody who wants it. A button and not a `title`,
     because a hover tooltip is unreachable on the device most of this is read
     on. */
  var HINT_SHOWS = 3;
  function bumpHint(id) {
    try { localStorage.setItem('adspace-hint-' + id, String(hintSeen(id) + 1)); } catch (e) {}
  }
  function hintSeen(id) {
    try { return Number(localStorage.getItem('adspace-hint-' + id) || 0); } catch (e) { return HINT_SHOWS; }
  }
  function hint(id, text) {
    var open = hintSeen(id) < HINT_SHOWS;
    return '<div class="hintline" data-hint="' + esc(id) + '">' +
      '<button class="hintbtn" type="button" data-a="hint" aria-expanded="' + open + '" ' +
      'aria-label="What happens at this step">?</button>' +
      '<p class="hinttext"' + (open ? '' : ' hidden') + '>' + esc(text) + '</p></div>';
  }

  /* What the creator sent from their own page, and the caption they wrote with
     it. Drawn above the Draft link rather than instead of it: a link pasted by
     hand still works, and an older campaign has nothing else. */
  var MEDIA_EXT = { mp4: 'video', m4v: 'video', mov: 'video', webm: 'video', mkv: 'video',
                    jpg: 'image', jpeg: 'image', png: 'image', gif: 'image', webp: 'image', heic: 'image', heif: 'image' };
  function mediaKind(f) {
    if (f.kind === 'video' || f.kind === 'image') return f.kind;
    var ext = String(f.name || f.url || '').split('?')[0].split('.').pop().toLowerCase();
    return MEDIA_EXT[ext] || f.kind || 'file';
  }
  function handedIn(o) {
    var files = (state.files && state.files[o.id]) || [];
    if (!files.length && !o.draft_caption) return '';
    /* Media is watched and everything else is opened, so they are two shapes,
       not one grid of squares. A 9:16 player beside a square tile left the
       third file orphaned on a row of its own with a gap beside it, which is
       the ragged grid this portal's own checklist rules out; and a PDF drawn
       at 9:16 to even it up is a tall empty box saying PDF. The creator's own
       page settled this months ago: what can be played is played, what cannot
       is an attachment line. */
    /* A file recorded as `file` because the phone sent no type is still a
       video if its name says so, and a video is watched here, not downloaded. */
    var media = files.map(function (f) { return Object.assign({}, f, { kind: mediaKind(f) }); })
      .filter(function (f) { return f.kind === 'video' || f.kind === 'image'; });
    var rest  = files.filter(function (f) { var k = mediaKind(f); return k !== 'video' && k !== 'image'; });
    return '<div class="handedin">' +
      (media.length
        ? '<div class="filegrid">' + media.map(function (f) {
            /* A thumbnail that cannot load shows what the file is rather than
               the browser's broken image mark, which tells a reviewer the
               creator's work is gone when only the preview failed. The
               creator's own page has done this since it shipped; the console
               was drawing the broken mark. */
            var ext = esc(String(f.name || '').split('.').pop().toUpperCase() || 'FILE');
            /* A video plays here. The console drew it as a square with MP4
               written on it, so the only way to watch a creator's work before
               releasing it to a client was to download every file — on the one
               screen whose whole job is to look at it before a client does.
               The client's own page has had a player since it shipped; this is
               the same treatment on our side of the glass, with the remove
               control the client's page has no business carrying.
               `preload="metadata"` so five creators' videos cost five poster
               frames rather than five downloads. */
            if (f.kind === 'video') {
              return '<div class="filecard filecard-video" data-file="' + esc(f.id) + '">' +
                '<video controls playsinline preload="metadata" src="' + esc(f.url) + '"></video>' +
                '<span class="filecard-name">' + esc(f.name) + '</span>' +
                '<button class="filecard-x" type="button" data-a="removefile" aria-label="Remove submitted file">×</button></div>';
            }
            /* A thumbnail that cannot load shows what the file is rather than
               the browser's broken image mark, which tells a reviewer the
               creator's work is gone when only the preview failed. */
            return '<div class="filecard filecard-image" data-file="' + esc(f.id) + '">' +
              '<a class="filecard-open" href="' + esc(f.url) +
              '" target="_blank" rel="noopener" aria-label="Open submitted file">' +
              '<img src="' + esc(f.url) + '" alt="" loading="lazy" onerror="this.remove()">' +
              '<span class="filecard-kind">' + ext + '</span>' +
              '<span class="filecard-name">' + esc(f.name) + '</span></a>' +
              '<button class="filecard-x" type="button" data-a="removefile" aria-label="Remove submitted file">×</button></div>';
          }).join('') + '</div>'
        : '') +
      (rest.length
        ? '<div class="filepins">' + rest.map(function (f) {
            return '<span class="filepin filepin-row" data-file="' + esc(f.id) + '">' +
              '<a class="filepin-open" href="' + esc(f.url) + '" target="_blank" rel="noopener">' +
              '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" ' +
                'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
                '<path d="M21 11.5 12.5 20a5 5 0 0 1-7-7l8-8a3.3 3.3 0 0 1 4.7 4.7l-8 8a1.7 1.7 0 0 1-2.4-2.4l7.3-7.3"/>' +
              '</svg><span class="filepin-name">' + esc(f.name) + '</span></a>' +
              '<button class="filepin-x" type="button" data-a="removefile" ' +
              'aria-label="Remove submitted file">×</button></span>';
          }).join('') + '</div>'
        : '') +
      (o.draft_caption
        ? '<label class="kfield kfield-wide"><span>Their caption</span>' +
          '<textarea class="input textarea" rows="3" data-f="draft_caption">' +
          esc(o.draft_caption) + '</textarea></label>'
        : '') +
      '</div>';
  }

  /* In production is not a flag somebody sets and forgets: it means at least
     one creator is in production. Reverting, withdrawing or replacing the last
     of them puts the campaign back where the client can still choose, so the
     card stops reading In production over a list with nobody in it. Derived
     here rather than in each of the three menu actions, because it is one
     fact about the campaign and not three. */
  function syncCampState() {
    var c = state.campaign;
    if (!c || c.state !== 'production' || state.options.some(isLive)) return;
    db.from('campaigns').update({ state: 'open' }).eq('id', c.id).then(function (r) {
      if (r.error) return;
      c.state = 'open';
      log('campaign.opened', c.title, 'no creators in production');
      paintCampState(c);
    });
  }

  /* ---- Schedule -------------------------------------------------------
     This is the operational order: the next booking first, undated work after
     it, and elapsed bookings in their own section at the foot. The option's
     position is deliberately untouched, so the client continues to see the
     creators in the order in which they were offered and selected. */
  function paintSchedule(live) {
    var box = $('schedList');
    if (!box) return;
    var rows = live.filter(function (o) { return CHARGED.indexOf(o.state) > -1; });
    if (!rows.length) {
      UI.emptyLine(box, 'No creators booked yet.', 'Go to Creators', function () {
        showCampPane('creators'); pushUrl();
      });
      return;
    }
    var t = document.createElement('div');
    t.className = 'crm-table softpanel';
    t.innerHTML = '<div class="crm-head svc-row sched-row"><span>Creator</span><span>' +
      (isDelivery() ? 'Delivery' : 'Shoot') + '</span><span>Draft due</span>' +
      '<span>Publish</span></div>';
    var now = today();
    var upcoming = rows.filter(function (o) { return !o.visit_date || o.visit_date >= now; });
    var passed = rows.filter(function (o) { return o.visit_date && o.visit_date < now; });
    function byDate(a, b) {
      var ak = (a.visit_date || '9999-12-31') + ' ' + (a.visit_time || '');
      var bk = (b.visit_date || '9999-12-31') + ' ' + (b.visit_time || '');
      return ak.localeCompare(bk) || Number(a.position || 0) - Number(b.position || 0);
    }
    upcoming.sort(byDate);
    passed.sort(function (a, b) { return -byDate(a, b); });

    function band(label, count) {
      var el = document.createElement('div');
      el.className = 'svc-cat crm-band';
      el.innerHTML = esc(label) + ' <span>' + count + '</span>';
      t.appendChild(el);
    }
    function row(o) {
      var el = document.createElement('div');
      el.className = 'svc-row sched-row';
      el.innerHTML =
        '<span class="sched-who"><b>' + esc((o.creators || {}).name || '') + '</b></span>' +
        '<span class="sched-when sched-edit" data-label="' + (isDelivery() ? 'Delivery' : 'Shoot') + '"><input class="input input-sm" data-schedule="visit_date" ' +
          'type="date" value="' + esc(o.visit_date || '') + '" aria-label="' +
          (isDelivery() ? 'Delivery' : 'Shoot') + ' date">' +
          '<input class="input input-sm" data-schedule="visit_time" type="time" value="' +
          esc(clockValue(o.visit_time)) + '" aria-label="Optional time"></span>' +
        '<span class="sched-when sched-edit sched-one" data-label="Draft due"><span class="sched-field">' +
          '<input class="input input-sm" data-schedule="submission_due" ' +
          'type="date" value="' + esc(o.submission_due || '') + '" aria-label="Draft due date"></span></span>' +
        '<span class="sched-when sched-edit sched-one" data-label="Publish"><span class="sched-field">' +
          '<input class="input input-sm" data-schedule="planned_publish" ' +
          'type="date" value="' + esc(o.planned_publish || '') + '" aria-label="Publish date"></span></span>';
      /* An empty `input[type=date]` draws nothing at all on iOS — no
         mm/dd/yyyy, no caret, just an empty pill — so a Publish date nobody
         has set yet reads as a box with no explanation. The hint hangs off
         `.sched-field`, which wraps the field and nothing else, so it is
         centred on the box it explains. Hung off the cell it would be centred
         on the label as well: on a phone that put "Not set" a third of the way
         up the field, printed over its top border. */
      function markEmpty(input) {
        var cell = input.closest('.sched-one');
        if (cell) cell.classList.toggle('is-unset', !input.value);
      }
      Array.prototype.forEach.call(el.querySelectorAll('.sched-one input'), markEmpty);
      Array.prototype.forEach.call(el.querySelectorAll('[data-schedule]'), function (input) {
        input.addEventListener('change', function () {
          markEmpty(this);
          var patch = {}; patch[this.getAttribute('data-schedule')] = this.value || null;
          /* A visit creates a real production deadline. No-visit campaigns
             leave the visit blank and use the adjacent Draft due field. */
          if (this.getAttribute('data-schedule') === 'visit_date') {
            patch.submission_due = this.value ? addDays(this.value, 7) : o.submission_due || null;
          }
          db.from('campaign_options').update(patch).eq('id', o.id).then(function (r) {
            if (r.error) { msg('campWorkMsg', r.error.message, 'err'); return; }
            Object.keys(patch).forEach(function (k) { o[k] = patch[k]; });
            log('campaign.dates', logSubject(), ((o.creators || {}).name || 'A creator') + ' · schedule updated');
            paintOptions();
          });
        });
      });
      t.appendChild(el);
    }
    band('Upcoming', upcoming.length);
    upcoming.forEach(row);
    if (passed.length) { band('Past', passed.length); passed.forEach(row); }
    box.innerHTML = '';
    box.appendChild(t);
  }

  /* Older rows stored friendly strings such as "2pm". Native time inputs
     need 24-hour values; blank remains the explicit no-time option. */
  function clockValue(value) {
    var s = String(value || '').trim().toLowerCase();
    if (/^\d{2}:\d{2}$/.test(s)) return s;
    var m = s.match(/^(\d{1,2})(?::(\d{2}))?\s*(am|pm)$/);
    if (!m) return '';
    var h = Number(m[1]) % 12;
    if (m[3] === 'pm') h += 12;
    return String(h).padStart(2, '0') + ':' + (m[2] || '00');
  }

  function addDays(day, n) {
    var d = new Date(day + 'T00:00:00Z');
    if (isNaN(d)) return null;
    d.setUTCDate(d.getUTCDate() + n);
    return d.toISOString().slice(0, 10);
  }

  /* ---- Deliverables ----------------------------------------------------
     What each creator has handed in, gathered. The files and the caption are
     the ones on the booking; the creator's own card carries the same rows
     with the actions beside them, so this pane reads and never writes. */
  function paintDeliverables(live) {
    var box = $('delivList');
    if (!box) return;
    var rows = live.filter(function (o) { return ((state.files || {})[o.id] || []).length || o.draft_url; });
    if (!rows.length) {
      UI.emptyLine(box, 'Nothing handed in yet.');
      return;
    }
    box.innerHTML = '';
    rows.forEach(function (o) {
      var files = (state.files || {})[o.id] || [];
      var w = OPTION_WORD[o.state] || [o.state, ''];
      var sec = document.createElement('section');
      sec.className = 'softpanel deliv';
      var head = '<div class="deliv-head"><b>' + esc((o.creators || {}).name || '') + '</b>' +
        '<span class="tone ' + esc(w[1] || '') + '">' + esc(w[0]) + '</span></div>';
      var body = files.map(function (f) {
        return '<a class="deliv-file" href="' + esc(f.url) + '" target="_blank" rel="noopener">' +
          '<span class="deliv-name">' + esc(f.name || f.url) + '</span>' +
          '<span class="deliv-kind">' + esc((f.kind || '').split('/')[0] || 'file') + '</span></a>';
      }).join('');
      var pasted = o.draft_url
        ? '<a class="deliv-file" href="' + esc(o.draft_url) + '" target="_blank" rel="noopener">' +
          '<span class="deliv-name">' + esc(o.draft_url) + '</span>' +
          '<span class="deliv-kind">link</span></a>' : '';
      var cap = o.draft_caption
        ? '<p class="deliv-caption">' + esc(o.draft_caption) + '</p>' : '';
      sec.innerHTML = head + '<div class="deliv-files">' + body + pasted + '</div>' + cap;
      box.appendChild(sec);
    });
  }

  /* ---- What the client chose ------------------------------------------
     The selection as the client made it, beside the link they made it on.
     It was only ever readable by counting chips down the creator cards. */
  function paintPicks(live) {
    var box = $('pickList');
    if (!box) return;
    var picked = live.filter(function (o) { return CHARGED.indexOf(o.state) > -1; });
    /* Backup is a state, not a flag: the flow is option → shortlisted →
       backup → confirmed, and a backup the client never called on stays a
       backup rather than becoming an offer nobody took. */
    var backups = live.filter(function (o) { return o.state === 'backup'; });
    var waiting = live.filter(function (o) {
      return o.state !== 'backup' && CHARGED.indexOf(o.state) < 0;
    });
    if (!live.length) { UI.emptyLine(box, 'No creators offered yet.'); return; }
    var t = document.createElement('div');
    t.className = 'crm-table softpanel';
    t.innerHTML = '<div class="crm-head svc-row pick-row"><span>Creator</span><span>Placements</span>' +
      '<span class="svc-rate">Fee</span><span>State</span></div>';
    var band = function (name, n) {
      var el = document.createElement('div');
      el.className = 'svc-cat';
      el.innerHTML = esc(name) + ' <span>' + n + '</span>';
      return el;
    };
    var add = function (o) {
      var w = OPTION_WORD[o.state] || [o.state, ''];
      var el = document.createElement('div');
      el.className = 'svc-row pick-row';
      el.innerHTML =
        '<span class="pick-who"><b>' + esc((o.creators || {}).name || '') + '</b></span>' +
        '<span class="pick-plat">' + esc(o.platforms || '') + '</span>' +
        '<span class="svc-rate">' + esc(money(o.rate)) + '</span>' +
        '<span class="pick-state"><span class="tone ' + esc(w[1] || '') + '">' + esc(w[0]) + '</span></span>';
      t.appendChild(el);
    };
    if (picked.length) { t.appendChild(band('Chosen', picked.length)); picked.forEach(add); }
    if (backups.length) { t.appendChild(band('Backups', backups.length)); backups.forEach(add); }
    if (waiting.length) { t.appendChild(band('Offered, not chosen', waiting.length)); waiting.forEach(add); }
    box.innerHTML = '';
    box.appendChild(t);
  }

  /* The portal's record for this campaign. `activity_log` carries no campaign
     id, only the subject it was written with, which is the campaign's name at
     the time; a rename leaves the older entries behind. */
  function loadCampLog() {
    var box = $('campLogList');
    var c = state.campaign;
    if (!box || !c) return;
    UI.skeleton(box, 3);
    db.from('activity_log').select('*').eq('subject', c.title)
      .order('created_at', { ascending: false }).limit(50)
      .then(function (r) {
        if (r.error) { UI.failLine(box, 'The activity record', r.error.message, loadCampLog); return; }
        var rows = r.data || [];
        if (!rows.length) { box.innerHTML = '<div class="empty">No entries.</div>'; return; }
        var A = (window.ADspaceAdmin && window.ADspaceAdmin.actionLabel) || {};
        var t = document.createElement('div');
        t.className = 'crm-table softpanel';
        t.className += ' activity-list';
        t.innerHTML = '<div class="crm-head svc-row log-row"><span>When</span><span>Activity</span>' +
          '<span>By</span></div>';
        rows.forEach(function (x) {
          var el = document.createElement('div');
          el.className = 'svc-row log-row';
          var actor = x.actor || '';
          /* Preserve main's email-to-name resolver through conflict merges;
             fall back to the stored actor on older deployments. */
          var actorLabel = typeof whoName === 'function' ? whoName(actor) : actor;
          el.innerHTML =
            '<time class="log-when" datetime="' + esc(x.created_at || '') + '">' + esc(logDate(x.created_at)) + '</time>' +
            '<span class="log-event"><b class="log-what">' +
              esc((A[x.action] || [])[0] || String(x.action || '').replace(/[._]/g, ' ')) + '</b>' +
              (x.detail ? '<span class="log-detail">' + esc(x.detail) + '</span>' : '') + '</span>' +
            '<span class="log-who"><span class="log-avatar" aria-hidden="true">' +
              esc(actorInitial(actorLabel)) + '</span><span class="log-person">' +
              esc(actorLabel || 'System') + '</span></span>';
          t.appendChild(el);
        });
        box.innerHTML = '';
        box.appendChild(t);
      });
  }
  function logDate(iso) {
    var d = new Date(iso);
    return isNaN(d.getTime()) ? '' :
      d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) +
      ' · ' + d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
  }
  function actorInitial(actor) {
    var s = String(actor || 'S').trim();
    return (s.match(/[A-Za-z0-9\u3400-\u9fff]/) || ['S'])[0].toUpperCase();
  }

  /* ---- What this campaign is waiting on us for --------------------------
     Derived from the bookings on every repaint, never stored: a state written
     once by the action that caused it is a state that goes stale the moment
     somebody reverts. The order is the order the work actually blocks in. */
  function nextAction(c, live) {
    var n = function (st) { return live.filter(function (o) { return o.state === st; }).length; };
    var submitted = n('submitted'), changes = n('changes');
    var drafts = n('pending_draft'), shortlisted = n('shortlisted'), posted = n('posted');
    /* Pending visit is the step, not the absence of a date: a booking sits at
       it from confirmation until the shoot has happened, dated or not. The
       line used to read every one of them as "no date yet", so a campaign
       with every shoot in the diary told the team two were unscheduled. */
    var pending = live.filter(function (o) { return o.state === 'pending_visit'; });
    var undated = pending.filter(function (o) { return !o.visit_date; }).length;
    var ahead = pending.map(function (o) { return o.visit_date; })
      .filter(function (d) { return d && d >= today(); }).sort();
    var one = isDelivery() ? 'delivery' : 'shoot', many = isDelivery() ? 'deliveries' : 'shoots';
    if (submitted) return submitted + (submitted === 1 ? ' draft is' : ' drafts are') + ' waiting to be released to the client.';
    if (shortlisted) return shortlisted + (shortlisted === 1 ? ' creator has' : ' creators have') + ' been chosen and still need confirming.';
    if (c.state === 'draft') return 'Not published yet. The client cannot see it.';
    if (changes) return changes + (changes === 1 ? ' creator is' : ' creators are') + ' reworking a draft.';
    if (undated) return undated + ' ' + (undated === 1 ? one + ' has' : many + ' have') + ' no date yet.';
    if (ahead.length) {
      return ahead.length + ' ' + (ahead.length === 1 ? one + ' is' : many + ' are') + ' scheduled, next on ' + niceDate(ahead[0]) + '.';
    }
    if (pending.length) {
      return pending.length + ' ' + (pending.length === 1 ? one + ' has' : many + ' have') +
        ' passed and still read Pending visit.';
    }
    if (drafts) return drafts + (drafts === 1 ? ' draft is' : ' drafts are') + ' with the creators.';
    if (posted) return posted + (posted === 1 ? ' post is' : ' posts are') + ' live and waiting on results.';
    return '';
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
    // Two labelled groups of cells, the same cells as the results card.
    var next = nextAction(c, live);
    $('campNext').textContent = next;
    $('campNext').hidden = !next;
    paintSchedule(live);
    paintDeliverables(live);
    paintPicks(live);

    /* Six equal statistic cards carried three numbers and a scoreboard's worth
       of white space, and pushed the bookings — the thing anybody opens a
       campaign to see — behind a tab. The counts and the money are facts about
       the campaign, so they are in the rail with the rest of the facts; the
       pane carries the work. */
    paintCampOv(c, live, chosen);
    paintCampRail(c, live, chosen, total, booked, goodwill);

    /* One card per creator. An option and a booking were two lists showing the
       same people at different moments, which meant reading both to know where
       anyone stood. Now the card is the person and the sections inside it are
       the moments: terms first, production once accepted, results once live.
       Order runs by how live the work is. */
    var box = $('creatorList');
    box.innerHTML = '';
    box.className = '';
    if (!state.options.length) {
      UI.emptyLine(box, 'No creators yet.', 'Add creators', function () { $('showAddOption').click(); });
    } else {
      /* One surface with a header over it, not a stack of bordered cards: ten
         bookings were ten floating panels with 12px of page ground between
         rows that belong to one list, and the state was something read from
         each card rather than down a column. The card is still the record —
         the steps open inside it — it just stops being a card. */
      box.className = 'bookreg';
      box.innerHTML = '<div class="bookreg-head"><span></span><span>Creator</span>' +
        '<span>Booking</span><span>Step</span><span></span></div>';
      state.options.slice().sort(function (a, b) {
        return (cardRank(a) - cardRank(b)) || (Number(a.position || 0) - Number(b.position || 0));
      }).forEach(function (o, i) { box.appendChild(creatorCard(o, i + 1)); });
    }

    // Accepting is offered exactly when the client has chosen something.
    var waiting = state.options.filter(function (o) { return o.state === 'shortlisted'; });
    $('campLock').hidden = !waiting.length;
    /* The row leaves with the button, or an empty row keeps the block step
       under the list and the pane ends on a gap nobody put there. */
    if ($('campLockRow')) $('campLockRow').hidden = !waiting.length;
    $('campLock').textContent = 'Confirm ' + waiting.length +
      (waiting.length === 1 ? ' creator' : ' creators');

    var working = state.options.filter(isLive);
    $('bulkToggle').hidden = !working.length;
    // Schedule's copy of the action answers to the same fact, or it offers a
    // form that refuses every press with "Nothing is in production yet."
    if ($('schedBulk')) $('schedBulk').hidden = !working.length;
    if (!working.length) $('bulkBox').hidden = true;
    $('bulkTitle').textContent = (isDelivery() ? 'Delivery' : 'Shoot') + ' date for all';
    paintRollup(working);
    paintInvoice(c);
  }

  /* ---- The campaign's Overview: the record, not a scoreboard ------------
     Flat titled sections inside one bounded surface, each a heading, the one
     control that opens its own pane, and real rows under it. Built only from
     what `loadOptions` has already read, so the pane costs nothing and cannot
     hold a figure that has gone stale. A section with nothing says so in a
     line, because "None yet." is itself an answer. */
  var OVCHEV = '<svg class="ovgo-chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
    'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<path d="M9 18l6-6-6-6"/></svg>';

  function ovSec(title, pane, word, body) {
    return '<section class="ovsec"><div class="ovsec-head"><h3>' + esc(title) + '</h3>' +
      '<button class="btn btn-quiet btn-sm ovgo" type="button" data-go="' + esc(pane) + '">' +
      esc(word) + OVCHEV + '</button></div>' + body + '</section>';
  }
  function ovNone(t) { return '<p class="ovnone">' + esc(t) + '</p>'; }

  function paintCampOv(c, live, chosen) {
    var box = $('campOv');
    if (!box) return;
    box.innerHTML = '<div class="ovcard">' +
      ovBookings(live) + ovDates(live) + ovHandins(live) + '</div>';
    Array.prototype.forEach.call(box.querySelectorAll('[data-go]'), function (b) {
      b.addEventListener('click', function () { showCampPane(b.getAttribute('data-go')); pushUrl(); });
    });
  }

  /* The bookings, which is the campaign. Who, where they post, where the work
     has got to, and what it costs — the four things anybody asks — on one grid
     so a column starts at the same x on every row. */
  function ovBookings(live) {
    if (!live.length) return ovSec('Bookings', 'creators', 'Creators', ovNone('No creators offered yet.'));
    var rows = live.slice().sort(function (a, b) {
      return (cardRank(a) - cardRank(b)) || (Number(a.position || 0) - Number(b.position || 0));
    }).slice(0, 8).map(function (o) {
      var w = OPTION_WORD[o.state] || [o.state, ''];
      return '<div class="ovrow ovrow-book">' +
        '<span class="ovname">' + esc((o.creators || {}).name || '') + '</span>' +
        '<span class="ovdim">' + esc(platformsOf(o).join(' · ') || '—') + '</span>' +
        '<span><span class="tone ' + esc(w[1] || 'tone-plain') + '">' + esc(w[0]) + '</span></span>' +
        '<span class="ovamt">' + esc(money(o.rate)) + '</span></div>';
    }).join('');
    var more = live.length > 8
      ? '<p class="ovmore">' + (live.length - 8) + ' more on the Creators pane.</p>' : '';
    return ovSec('Bookings', 'creators', 'Creators',
      '<div class="ovtable"><div class="ovhead ovrow-book"><span>Creator</span>' +
      '<span>Posting on</span><span>Step</span><span class="ovamt">Fee</span></div>' +
      rows + '</div>' + more);
  }

  /* When the work happens. Only bookings the client is paying for have dates,
     so this is the same set the Schedule pane reads and never a second store. */
  function ovDates(live) {
    var rows = live.filter(function (o) { return CHARGED.indexOf(o.state) > -1; });
    if (!rows.length) return ovSec('Schedule', 'schedule', 'Schedule', ovNone('Nothing booked yet.'));
    /* The column heading leaves with the header on a phone, so each date
       carries its own caption, shown only where the header is not. Two
       unlabelled dates stacked under each other are two dates nobody reads. */
    var shootWord = isDelivery() ? 'Delivery' : 'Shoot';
    var body = rows.slice(0, 6).map(function (o) {
      return '<div class="ovrow ovrow-date">' +
        '<span class="ovname">' + esc((o.creators || {}).name || '') + '</span>' +
        '<span class="ovamt"><span class="ovcap">' + esc(shootWord) + '</span>' + (o.visit_date
          ? esc(niceDate(o.visit_date) + (o.visit_time ? ', ' + o.visit_time : ''))
          : '<span class="muted">—</span>') + '</span>' +
        '<span class="ovamt"><span class="ovcap">Publish</span>' + (o.planned_publish
          ? esc(niceDate(o.planned_publish)) : '<span class="muted">—</span>') + '</span></div>';
    }).join('');
    var more = rows.length > 6 ? '<p class="ovmore">' + (rows.length - 6) + ' more on the Schedule pane.</p>' : '';
    return ovSec('Schedule', 'schedule', 'Schedule',
      '<div class="ovtable"><div class="ovhead ovrow-date"><span>Creator</span>' +
      '<span class="ovamt">' + (isDelivery() ? 'Delivery' : 'Shoot') + '</span>' +
      '<span class="ovamt">Publish</span></div>' + body + '</div>' + more);
  }

  /* What has come in. A draft waiting on us is the one thing on this page
     somebody has to act on today, so it is named here rather than counted. */
  function ovHandins(live) {
    var rows = live.filter(function (o) {
      return ((state.files || {})[o.id] || []).length || o.draft_url;
    });
    if (!rows.length) return ovSec('Deliverables', 'creators', 'Creators', ovNone('Nothing handed in yet.'));
    var body = rows.slice(0, 6).map(function (o) {
      var n = ((state.files || {})[o.id] || []).length;
      var w = OPTION_WORD[o.state] || [o.state, ''];
      return '<div class="ovrow ovrow-book">' +
        '<span class="ovname">' + esc((o.creators || {}).name || '') + '</span>' +
        '<span class="ovdim">' + esc(n ? n + (n === 1 ? ' file' : ' files') : 'Pasted link') + '</span>' +
        '<span><span class="tone ' + esc(w[1] || 'tone-plain') + '">' + esc(w[0]) + '</span></span>' +
        '<span class="ovamt"></span></div>';
    }).join('');
    return ovSec('Deliverables', 'creators', 'Creators',
      '<div class="ovtable"><div class="ovhead ovrow-book"><span>Creator</span>' +
      '<span>Handed in</span><span>Step</span><span class="ovamt"></span></div>' + body + '</div>');
  }

  /* ---- The rail: one block per question --------------------------------
     What it is waiting on us for, how far the selection has got, what it is
     worth, the dates it holds, whether the client can see it, and the facts
     that place it. A block leaves entirely when its data does not exist, so
     the rule under the last one is set here: `:last-child` counts a hidden
     sibling and would draw a hairline under nothing. */
  function paintCampRail(c, live, chosen, total, booked, goodwill) {
    /* What the campaign is waiting on us for is deliberately NOT a rail block:
       it is the warn line under the identity, on every pane, which is both
       more prominent and already the locked behaviour. Drawing it twice would
       be the one thing this portal's copy rules forbid outright. */
    var pb = $('campPickBlock');
    if (pb) {
      var slots = Number(c.slots || 0);
      pb.hidden = !slots;
      if (slots) {
        var pct = Math.min(100, Math.round((chosen.length / slots) * 100));
        $('campPickRail').innerHTML =
          '<p class="railpct"><b>' + chosen.length + ' of ' + slots + ' chosen</b>' +
          '<span>' + pct + '%</span></p>' +
          '<span class="railbar"><span class="railbar-fill" style="width:' + pct + '%"></span></span>' +
          (booked > slots
            ? '<p class="railwarn">' + booked + ' booked · ' + goodwill.length + ' goodwill</p>'
            : '') +
          (live.length
            ? '<p class="railfoot">' + live.length +
              (live.length === 1 ? ' creator offered' : ' creators offered') + '</p>' : '');
      }
    }

    /* The money the client is quoted, right aligned on one grid so the total
       sits under the figures it is the sum of. */
    var finance = $('campFinanceTotal');
    if (finance) {
      finance.hidden = !chosen.length;
      if (chosen.length) {
        var moneyRows =
          railMoney('Subtotal', money2(total)) +
          railMoney(taxWord(), money2(sstOf(total))) +
          railMoney('Total', money2(total + sstOf(total)), 'is-total');
        $('campFinanceMoney').innerHTML = moneyRows;
      }
    }

    var db = $('campDateBlock');
    if (db) {
      var dates = [];
      if (c.deadline) dates.push(['Campaign due', niceDate(c.deadline)]);
      /* "Next" has to mean next. This took the earliest date of every live
         booking and called it the next one, so the moment the first shoot
         passed the rail went on promising a date that was already behind us —
         12 Sept still reading as the next shoot in the middle of October.
         The next one is the earliest date from today onward; where every date
         is behind us there is no next one, so the row says what it is instead
         of what it hoped to be. */
      var today = new Date(); today.setHours(0, 0, 0, 0);
      function aheadOf(list) {
        var all = list.filter(Boolean).sort();
        if (!all.length) return null;
        for (var i = 0; i < all.length; i++) {
          if (new Date(all[i] + 'T00:00:00') >= today) return { on: all[i], ahead: true };
        }
        return { on: all[all.length - 1], ahead: false };
      }
      var vis = aheadOf(live.map(function (o) { return o.visit_date; }));
      var pub = aheadOf(live.map(function (o) { return o.planned_publish; }));
      var what = isDelivery() ? 'delivery' : 'shoot';
      if (vis) dates.push([(vis.ahead ? 'Next ' : 'Last ') + what, niceDate(vis.on)]);
      if (pub) dates.push([(pub.ahead ? 'Next' : 'Last') + ' publish', niceDate(pub.on)]);
      db.hidden = !dates.length;
      $('campDateRail').innerHTML = dates.map(function (d) {
        return '<div><dt>' + esc(d[0]) + '</dt><dd>' + esc(d[1]) + '</dd></div>';
      }).join('');
    }

    /* The rule under the last block, set in the paint. */
    var blocks = ['campFactBlock', 'campPickBlock', 'campDateBlock'].map($).filter(Boolean);
    blocks.forEach(function (b) { b.classList.remove('is-last'); });
    var shown = blocks.filter(function (b) { return !b.hidden; });
    if (shown.length) shown[shown.length - 1].classList.add('is-last');
  }

  function railMoney(label, value, cls) {
    return '<div' + (cls ? ' class="' + cls + '"' : '') + '><dt>' + esc(label) +
      '</dt><dd>' + esc(value) + '</dd></div>';
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
          log('campaign.rate', logSubject(), ((o.creators || {}).name || 'A creator') + ' · ' +
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
    $('ncBox').hidden = true;
    $('ncToggle').setAttribute('aria-expanded', 'false');
    resetNc();
    ncDraft.note({ campaign: state.campaign.id });
    loadRoster(paintPicker);
    $('optionSearch').focus();
  });
  /* Keying somebody in is the rarer of the two jobs, so it is folded: the
     panel opens on the creators list, which is what it is usually for. */
  $('ncToggle').addEventListener('click', function () {
    var open = $('ncBox').hidden;
    $('ncBox').hidden = !open;
    this.setAttribute('aria-expanded', String(open));
    if (open) $('ncName').focus();
  });
  $('ncClose').addEventListener('click', function () {
    $('ncBox').hidden = true;
    $('ncToggle').setAttribute('aria-expanded', 'false');
    resetNc();
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

    var free = list.filter(function (c) { return !already[c.id]; }).length;
    $('optionCount').textContent = !state.creators.length ? ''
      : free + ' to add';

    box.innerHTML = '';
    if (!list.length) {
      box.innerHTML = '<div class="empty">No matches.</div>';
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
                : '<span class="pickadd">' + platformBoxes(uniq, true) +
                  '<span class="slugfield"><span class="slugfield-pre">RM</span>' +
                  '<input class="input pickrate" type="number" min="0" step="10" ' +
                  'aria-label="Rate for ' + esc(c.name) + ' on this campaign" value="' +
                  (c.client_rate || '') + '" placeholder="rate"></span>' +
                  /* Neutral, not the filled action: this is one button per
                     addable row, so a list of twenty creators drew twenty
                     filled slabs and the panel's own primary — the one that
                     actually finishes the job — had nothing left to be. */
                  '<button class="btn btn-sm" type="button">Add</button></span>');
      if (!inCamp) {
        /* Ticking a platform this creator has no link for used to mean leaving
           the campaign, opening the creators list, adding the link, and coming
           back; or ticking it and never adding one at all, which is how a
           client ends up looking at a platform with nowhere to go. The tick
           opens into the field instead, in place, and what is typed is saved
           to the creator so it is asked for once and never again. */
        var have = {};
        (c.creator_profiles || []).forEach(function (pr) { have[PLATFORM_LABEL[pr.platform] || pr.platform] = true; });
        var askLinks = function () {
          Array.prototype.forEach.call(row.querySelectorAll('.pbox'), function (box) {
            var tick = box.querySelector('.pbox-tick input');
            var field = box.querySelector('.pbox-link');
            if (!field) return;
            var need = tick.checked && !have[tick.value];
            box.classList.toggle('needs-link', need);
            field.disabled = !need;
            if (!need) field.value = '';
          });
        };
        Array.prototype.forEach.call(row.querySelectorAll('.pbox-tick input'), function (b) {
          b.addEventListener('change', askLinks);
        });
        row.querySelector('button').addEventListener('click', function () {
          var links = Array.prototype.slice.call(row.querySelectorAll('.pbox.needs-link .pbox-link'))
            .map(function (i) { return { name: i.getAttribute('data-p'), url: (i.value || '').trim() }; })
            .filter(function (x) { return x.url; });
          addOption(c, readBoxes(row), Number(row.querySelector('.pickrate').value || 0), links);
        });
      }
      box.appendChild(row);
    });
  }

  function addOption(c, platformNames, rate, links) {
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
      /* A link typed here belongs to the creator, not to this campaign: the
         next campaign asks nobody for it again. */
      /* readProfile is what already turns a URL into a platform and an identity
         everywhere else, so a link typed here is read the same way and a URL
         that is not a profile we recognise is simply not recorded. */
      var rows = (links || []).map(function (x) { return readProfile(x.url); })
        .filter(Boolean)
        .map(function (pr) {
          return { creator_id: c.id, platform: pr.platform, url: pr.url, handle: pr.handle };
        });
      var after = function () { loadOptions(); loadRoster(paintPicker); };
      if (rows.length) db.from('creator_profiles').insert(rows).then(after, after);
      else { loadOptions(); setTimeout(paintPicker, 150); }
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

    // Kept in the creators list with this as her usual rate, since it is the only
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
  var PIPELINE = ['confirmed', 'pending_visit', 'pending_draft', 'submitted',
                  'reviewing', 'scheduled', 'posted', 'completed'];
  var IN_PRODUCTION = PIPELINE.concat(['changes']);

  /* The step is named for where the work is; the button is named for what
     pressing it does. "Reviewing →" on a card sitting at Submitted says
     nothing about who is about to see it, and releasing a draft to a client
     is the one move on this card that cannot be taken back quietly. */
  var ADVANCE_WORD = { submitted: 'Mark submitted', reviewing: 'Release to client' };

  /* THE QUALITY CHECK BEFORE A CLIENT SEES THE WORK.
     Release is the only move on this card a client sees the moment it is
     made, and until now it was one press. These are the team's own checks,
     in the order somebody watches a video: what is written on it, then who
     it is for, then how it plays. All of them are required — a check that
     can be skipped is a check nobody makes — and the count says how far it
     has got, so a control that will not move is never a mystery.

     They are stated here and nowhere else. A list somebody can edit on a
     settings page is a later thing and would need a table; what this needed
     first was the gate. */
  var QC_CHECKS = [
    ['Copy and facts', [
      'Spelling and grammar',
      'Brand and product names spelled correctly',
      'Client name, location and contact details correct',
      'Campaign name and dates correct',
      'Prices, offers and terms correct'
    ]],
    ['The brief', [
      'Caption, hashtags and mentions match the brief',
      'Call to action present',
      'Paid partnership label where required',
      'No competitor brands or third parties visible'
    ]],
    ['The file', [
      'Correct cut and aspect ratio for the platform',
      'Nothing important under the platform\'s own overlays',
      'Duration within the platform\'s limit',
      'Audio audible throughout, music cleared for use',
      'Visual flow, no lag or dropped frames'
    ]]
  ];
  function qcAll() {
    return QC_CHECKS.reduce(function (a, g) { return a.concat(g[1]); }, []);
  }

  /* Whose round a `changes` is. The client's own decision is stamped by
     review_draft; a round the team sent back is stamped here. Rows that
     predate the column can only be the client's. */
  function changesBy(o) { return o.changes_by || 'client'; }

  // Product seeding has no visit. Asking for a location would mean typing N/A
  // into a box forever, so the same fields are labelled for what they are.
  function isDelivery() {
    return (state.campaign || {}).push_format === 'seeding';
  }
  function visitWord() { return isDelivery() ? 'Delivery' : 'Visit'; }

  function nextState(s) {
    // Re-uploaded after edits, which lands with us again and not with the client.
    if (s === 'changes') return 'submitted';
    var i = PIPELINE.indexOf(s);
    return i > -1 && i < PIPELINE.length - 1 ? PIPELINE[i + 1] : null;
  }

  /* Every step forward has a step back. Things go wrong, a status gets clicked
     twice, a client asks to undo: none of that should mean deleting the
     campaign and building it again. */
  function prevState(s, o) {
    // The branch folds back to whichever side raised it.
    if (s === 'changes') return (o && changesBy(o) === 'team') ? 'submitted' : 'reviewing';
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
  function menuItem(action, label, cls, need) {
    return '<button class="kmenu-item ' + (cls || '') + '" data-a="' + action + '"' +
      (need ? ' data-need="' + need + '"' : '') + ' type="button">' +
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
    var back = live ? prevState(o.state, o) : null;

    // The draft is a step of its own: it exists only once filming is done.
    var stage = PIPELINE.indexOf(o.state === 'changes'
      ? (changesBy(o) === 'team' ? 'submitted' : 'reviewing') : o.state);
    var drafting = live && stage >= PIPELINE.indexOf('pending_draft');

    /* Submitted is the one step that is waiting on us, so the card opens by
       itself. Folded, it was a name, a chip and a summary line: the files the
       creator sent, the caption they wrote, Release to client and Request
       changes were all behind a fold nobody knew to open, which read as a
       booking with no next action at all. Deliberately folding it is still
       remembered, because openCards stores the false. */
    var waiting = o.state === 'submitted';
    var open = !live || (waiting ? openCards[o.id] !== false : !!openCards[o.id]);

    var card = document.createElement('article');
    card.className = 'kcard' + (live ? ' is-live' : '') + (dead ? ' is-off' : '') +
      (waiting ? ' is-waiting' : '') + (live && !open ? ' is-folded' : '');
    card.setAttribute('data-state', o.state);

    /* Folded, the card is one line: the date, the platforms, the money. A card
       waiting on us leads with what arrived, because how much was sent is the
       first thing anybody wants to know before opening it. */
    /* Four facts in one cell needed 280px and the column is 178: the line was
       cut mid-figure, so the money a booking is worth read as "RM 8,0". Where
       they post and what they cost are columns on the Overview's Bookings
       table and rows in the Terms step one click below this, so the summary
       carries what only it can: how much has arrived, and when the work is. */
    var waitFiles = (state.files && state.files[o.id]) || [];
    var sum = live ? [
      waiting && waitFiles.length
        ? waitFiles.length + ' file' + (waitFiles.length === 1 ? '' : 's') : '',
      o.visit_date ? niceDate(o.visit_date) + (o.visit_time ? ', ' + o.visit_time : '')
                   : visitWord() + ' TBC'
    ].filter(Boolean).join(' · ') : '';

    /* The head is a register row: five stable cells on a stated grid, so the
       name, the summary, the state and the actions each start at the same x on
       every booking. `order` on a flex row put the state second from the end
       but could not make two rows agree on where that end was, and a column of
       bookings is read down for where each one has got to. */
    card.innerHTML =
      '<header class="kcard-head">' +
        '<span class="kcard-lead">' +
          (live ? '<button class="kfold" data-a="fold" type="button" aria-label="Details" ' +
            'aria-expanded="' + String(open) + '">' + CHEV + '</button>' : '') +
          (no ? '<span class="kcard-no">' + no + '</span>' : '') +
        '</span>' +
        '<span class="kcard-name">' + esc(cr.name || '') + '</span>' +
        '<span class="kcard-sum">' + (sum ? esc(sum) : '') + '</span>' +
        '<span class="kcard-tags">' +
          '<span class="tone ' + (word[1] || 'tone-plain') + '">' + esc(word[0]) + '</span>' +
          (o.is_replacement ? '<span class="tone is-warn">Replacement</span>' : '') +
          (o.goodwill ? '<span class="tone is-warn">Goodwill</span>' : '') +
        '</span>' +
        '<span class="kcard-act">' +
          /* Sending a creator their link is the everyday action on this row, so
             it is a control here and not three steps away inside their record.
             Sent again costs nothing and saves the creator digging through
             WhatsApp for a message from three weeks ago. */
          (!dead && cr.access_code
            ? '<button class="iconbtn kcard-link" data-a="copylink" type="button" ' +
              'aria-label="Copy portal link for ' + esc(cr.name || '') + '" ' +
              'title="Copy portal link">' + LINK_ICON + '</button>' : '') +
          (dead ? '' : '<button class="kmenu-btn" data-a="menu" type="button" ' +
            'aria-label="More actions" aria-expanded="false">' + DOTS + '</button>') +
        '</span>' +
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
          field('Draft due', 'submission_due', o.submission_due, 'date', '', 'kfield-pub') +
          field('Publish date', 'planned_publish', o.planned_publish, 'date', '', 'kfield-pub') +
          '<label class="kfield kfield-wide"><span>Notes</span>' +
            '<input class="input" data-f="notes" value="' + esc(o.notes || '') + '"></label>' +
        '</div>' +
      '</div>' +
      (drafting ?
      '<div class="kstep kstep-work">' +
        '<div class="kstep-title">Draft</div>' +
        draftGuide(o) +
        handedIn(o) +
        '<div class="kfields">' +
          /* The team can hand a file in for the creator, at the same steps
             the creator's own page accepts one (`creator_can_deliver`: pending
             draft, changes requested, submitted): a creator who cannot get a
             file up their line used to leave the booking stuck until somebody
             found a Drive folder, and the console had no way to help. The file
             takes the console's own signed PUT to S3 and lands in the same
             hand-in the creator's files do, so the card, the release and the
             client's page cannot tell whose hand put it there. */
          (teamMayDeliver(o) && putToS3
            ? '<label class="kfield kfield-wide"><span>Upload for ' +
                esc((o.creators || {}).name || 'the creator') + '</span>' +
                '<input class="input" type="file" multiple data-a="teamfiles" ' +
                'accept="video/*,image/*,.pdf,.zip"></label>' +
              '<div class="progress kupload" data-teamup hidden>' +
                '<div class="progress-head"><span data-teamlabel></span><span data-teampct></span></div>' +
                '<div class="progress-track"><div class="progress-fill" data-teamfill></div></div>' +
              '</div>'
            : '') +
          '<label class="kfield kfield-wide"><span>Or paste a link</span>' +
            '<input class="input" data-f="draft_url" value="' + esc(o.draft_url || '') +
            '" placeholder="https://"></label>' +
        '</div>' +
      '</div>' : '') +
      '<div class="kstep kstep-work">' +
        '<div class="kactions">' +
          '<button class="btn btn-sm btn-primary" data-a="save" type="button">Save</button>' +
          /* Blue moves work to somebody else, and exactly one step on this
             card does: Release to client. The other five — pending visit,
             pending draft, scheduled, posted, completed — are the team
             recording its own progress, and drawing them blue put one filled
             accent on every creator card, so a pane with five creators in it
             carried five equally loud buttons and none of them said which
             step mattered. It also broke the law this portal counts in the
             audit: one prominent blue action per view, two at most. The rest
             are the ordinary outline action, and what differentiates them is
             the word on them, not the paint. */
          (advance ? '<button class="btn btn-sm' + (advance === 'reviewing' ? ' btn-go' : '') +
            '" data-a="advance" type="button">' +
            esc(ADVANCE_WORD[advance] || wordFor(advance)) + CHEV + '</button>' : '') +
          /* Back to the creator without the client ever seeing the round.
             Warn and outlined: it is reversible and it is not the way out. */
          (o.state === 'submitted'
            ? '<button class="btn btn-sm btn-warn" data-a="sendback" type="button">' +
              'Request changes</button>' : '') +
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

  /* The steps at which a file may be handed in, the creator's page's rule
     (`creator_can_deliver`) read here so the two cannot drift. */
  function teamMayDeliver(o) {
    return ['pending_draft', 'changes', 'submitted'].indexOf(o.state) > -1;
  }

  /* One file at a time: signed by the console's own path (a team member,
     the campaign's client folder), sent to S3 with the progress the creator
     sees on their page, then recorded on the booking. It is not handed in
     until the row exists, and a row the policy refused comes back empty
     rather than as an error, so the empty answer is the refusal. One bad
     file never abandons the rest, and the outcome is written after the
     repaint that follows it, or the redraw throws the line away. */
  function teamDeliver(card, o, files) {
    var cap = ((cfg.s3 && cfg.s3.maxUploadMB) || 1024) * 1024 * 1024;
    var mb = (cfg.s3 && cfg.s3.maxUploadMB) || 1024;
    var big = files.filter(function (f) { return f.size > cap; });
    var queue = files.filter(function (f) { return f.size <= cap; });
    var box = card.querySelector('[data-teamup]');
    var label = card.querySelector('[data-teamlabel]');
    var pct = card.querySelector('[data-teampct]');
    var fill = card.querySelector('[data-teamfill]');
    var pick = card.querySelector('[data-a="teamfiles"]');
    var tooBig = big.length === 1
      ? big[0].name + ' is larger than ' + mb + ' MB.'
      : big.length > 1 ? big.length + ' files are larger than ' + mb + ' MB.' : '';
    if (!queue.length) { if (tooBig) msg('campWorkMsg', tooBig, 'err'); return; }
    if (!state.campaign || !state.campaign.client_id) { msg('campWorkMsg', 'The campaign has no client to file this under.', 'err'); return; }

    function show(i, n, file, p, saving) {
      if (!box) return;
      box.hidden = false;
      label.textContent = (n > 1 ? i + '/' + n + ' · ' : '') + file.name;
      pct.textContent = saving ? 'Saving' : Math.round(p * 100) + '%';
      fill.style.width = Math.round(p * 100) + '%';
    }
    function sendOne(file, i, n) {
      show(i, n, file, 0, false);
      var ext = (file.name.split('.').pop() || 'bin').toLowerCase().replace(/[^a-z0-9]/g, '') || 'bin';
      return db.functions.invoke((cfg.s3 && cfg.s3.functionName) || 'sign-upload', {
        body: { ext: ext, clientId: state.campaign.client_id, size: file.size }
      }).then(function (r) {
        if (r.error) throw new Error(r.error.message || 'could not be signed');
        if (!r.data || !r.data.uploadUrl) throw new Error((r.data && r.data.error) || 'refused');
        var kind = mediaKind({ name: file.name, kind: (file.type || '').split('/')[0] });
        return putToS3(r.data.uploadUrl, file, file.type || 'application/octet-stream', function (p) {
          show(i, n, file, p, p >= 1);
        }).then(function () {
          show(i, n, file, 1, true);
          return db.from('campaign_deliverables').insert({
            option_id: o.id, url: r.data.publicUrl, name: file.name,
            kind: kind === 'video' || kind === 'image' ? kind : 'file',
            bytes: file.size, round: Math.max(o.revision_round || 0, 1)
          }).select('id');
        }).then(function (w) {
          if (w.error) throw new Error(w.error.message);
          if (!(w.data || []).length) throw new Error('the database refused the record');
          log('campaign.file_added', logSubject(), (o.creators || {}).name + ' · ' + file.name + ' · uploaded by ' + (who() || 'team'));
        });
      });
    }

    pick.disabled = true;
    var done = 0, failed = [];
    var chain = Promise.resolve();
    queue.forEach(function (file, idx) {
      chain = chain.then(function () {
        return sendOne(file, idx + 1, queue.length).then(function () { done++; }, function (e) {
          failed.push(file.name + ': ' + (e && e.message ? e.message : 'failed'));
        });
      });
    });
    chain.then(function () {
      if (box) box.hidden = true;
      pick.disabled = false;
      var text = (done ? done + (done === 1 ? ' file' : ' files') + ' handed in for ' +
        ((o.creators || {}).name || 'the creator') + '.' : '') +
        (failed.length ? ' Not saved: ' + failed.join('; ') : '') +
        (tooBig ? ' ' + tooBig : '');
      loadOptions();
      /* After the repaint, or the redraw throws the line away. */
      setTimeout(function () { msg('campWorkMsg', text.trim(), failed.length || tooBig ? 'err' : 'ok'); }, 50);
    });
  }

  function wireCard(card, o) {
    var on = function (sel, fn) {
      var el = card.querySelector('[data-a="' + sel + '"]');
      if (el) el.addEventListener('click', fn);
    };

    /* Copied in place, and the button says so for a moment rather than
       opening a bar or a sheet over the card it belongs to. */
    Array.prototype.forEach.call(card.querySelectorAll('[data-a="hint"]'), function (hb) {
      var line = hb.parentNode;
      var id = line.getAttribute('data-hint');
      var body = line.querySelector('.hinttext');
      // Shown by itself counts: three readings and it steps back.
      if (!body.hidden) bumpHint(id);
      hb.addEventListener('click', function () {
        body.hidden = !body.hidden;
        hb.setAttribute('aria-expanded', String(!body.hidden));
      });
      /* Hover is a preview; click pins it. Pointer events also cover a stylus,
         while the same button remains the complete interaction on touch. */
      hb.addEventListener('pointerenter', function () { body.hidden = false; });
      hb.addEventListener('pointerleave', function () {
        if (hb.getAttribute('aria-expanded') !== 'true') body.hidden = true;
      });
    });

    on('copylink', function () {
      window.ADspaceCopy.to(this, creatorLink((o.creators || {}).access_code));
    });

    /* TAKING A CREATOR'S WORK OFF IS TWO PRESSES, AND THE SECOND ONE WARNS.
       It was one press on an × that sits in the corner of the card somebody
       is watching the video in, and the only safeguard was the eight second
       Undo — which is no safeguard at all against a press nobody noticed,
       and the user reported exactly that: an accidental click and the
       creator has to upload the file again. The × arms the file instead and
       the confirm takes its place, naming what it costs; Escape, Cancel or
       a press anywhere else puts it back, one file armed at a time. The
       soft remove and the Undo stay behind it, so there are three steps
       between a stray click and lost work. */
    var armed = null;
    function disarm() {
      if (!armed) return;
      var box = armed.querySelector('.filearm');
      if (box) box.remove();
      armed.classList.remove('is-arming');
      var x = armed.querySelector('[data-a="removefile"]');
      if (x) { x.hidden = false; x.setAttribute('aria-expanded', 'false'); }
      armed = null;
    }
    card.addEventListener('click', function (e) {
      if (armed && !e.target.closest('.filearm') && !e.target.closest('[data-a="removefile"]')) disarm();
    });
    card.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && armed) {
        var x = armed.querySelector('[data-a="removefile"]');
        disarm();
        if (x) x.focus();
      }
    });
    function arm(button, file, go) {
      disarm();
      armed = file;
      file.classList.add('is-arming');
      button.hidden = true;
      button.setAttribute('aria-expanded', 'true');
      var box = document.createElement('div');
      box.className = 'filearm';
      box.setAttribute('role', 'group');
      box.setAttribute('aria-label', 'Confirm removing this file');
      box.innerHTML =
        '<span class="filearm-ask">Remove? The creator would have to upload it again.</span>' +
        '<span class="filearm-acts">' +
          '<button class="btn btn-sm btn-danger" type="button" data-a="rmyes">Remove</button>' +
          '<button class="btn btn-sm btn-quiet" type="button" data-a="rmno">Cancel</button>' +
        '</span>';
      file.appendChild(box);
      box.querySelector('[data-a="rmno"]').addEventListener('click', function () {
        disarm();
        button.focus();
      });
      box.querySelector('[data-a="rmyes"]').addEventListener('click', function () {
        armed = null;               // the file is about to go with its box
        go();
      });
      box.querySelector('[data-a="rmyes"]').focus();
    }

    Array.prototype.forEach.call(card.querySelectorAll('[data-a="removefile"]'), function (button) {
      button.setAttribute('aria-expanded', 'false');
      button.addEventListener('click', function () {
        var file = button.closest('[data-file]');
        var id = file && file.getAttribute('data-file');
        if (!id) return;
        arm(button, file, function () { removeFile(button, file, id); });
      });
    });

    function removeFile(button, file, id) {
      {
        /* A creator's work, so the line names which file went: "Submission
           removed." over a grid of three said nothing about which one. */
        var what = (file.querySelector('.filecard-name, .filepin-name') || {}).textContent || '';
        var block = file.closest('.handedin') || file.parentNode;
        db.from('campaign_deliverables').update({ removed_at: new Date().toISOString() })
          .eq('id', id).select('id').then(function (r) {
            if (r.error) { msg('campWorkMsg', r.error.message, 'err'); return; }
            /* A refused update comes back with no error and no rows, the way a
               refused delete does, so the card would have lost a file the
               database still holds. */
            if (!(r.data || []).length) {
              msg('campWorkMsg', 'Not removed. The database refused the request.', 'err');
              return;
            }
            file.remove();
            undoBar((what ? what.trim() + ' removed.' : 'Submission removed.'), function () {
              db.from('campaign_deliverables').update({ removed_at: null }).eq('id', id)
                .then(function () { loadOptions(); });
            }, block);
          });
      }
    }

    var pick = card.querySelector('[data-a="teamfiles"]');
    if (pick) pick.addEventListener('change', function () {
      var picked = Array.prototype.slice.call(this.files || []);
      this.value = '';
      if (!picked.length) return;
      teamDeliver(card, o, picked);
    });

    var menu = card.querySelector('[data-menu]');
    on('menu', function () {
      var open = menu && menu.hidden;
      shutMenus();
      if (menu) {
        menu.hidden = !open;
        this.setAttribute('aria-expanded', String(open));
        /* Placed on the viewport, like every other ⋯ in this portal. This card
           was the one that never called in, so a creator low on the list opened
           a menu that ran past the bottom of the window, which is nowhere a
           phone can reach. */
        if (open) window.ADspaceMenu.place(this, menu);
      }
    });

    // The header is the fold target; its buttons keep their own jobs.
    var body = card.querySelector('[data-body]');
    var foldBtn = card.querySelector('[data-a="fold"]');
    var visitInput = card.querySelector('[data-f="visit_date"]');
    var dueInput = card.querySelector('[data-f="submission_due"]');
    if (visitInput && dueInput) visitInput.addEventListener('change', function () {
      if (this.value) dueInput.value = addDays(this.value, 7);
    });
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
      patch.id = o.id;                      // so the gate can see what was handed in
      var why = blockAdvance(to, patch);
      var m = card.querySelector('[data-msg]');
      if (why) { m.textContent = why; m.className = 'msg err'; return; }
      delete patch.id;
      /* Every other step is the team recording its own progress and moves on
         the press. This one hands the work to the client, so it is checked
         first and the sheet is what releases it. */
      if (to === 'reviewing') { openQc(o, patch); return; }
      advanceOption(o, to, patch);
    });
    on('back',      function () { stepBack(o, prevState(o.state, o)); });
    on('sendback',  function () { sendBack(o, card); });

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
    /* A draft is a draft whether the creator uploaded it on their own page or
       somebody pasted a link: the gate is that something arrived, not which
       route it came by. */
    var files = (state.files && state.files[p.id]) || [];
    if ((to === 'submitted' || to === 'reviewing') && !p.draft_url && !files.length) {
      return 'Draft link or files required.';
    }
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
    if (!e.target.closest || !e.target.closest('.kcard-head, .kmenu, .team-act')) shutMenus();
  });
  // A creators list ⋯ is placed on the viewport, so a scroll that really moved closes it.
  window.ADspaceMenu.onScroll(shutMenus);
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') shutMenus(); });

  /* One step back up the line. Posts and results stay where they are, so
     stepping back out of Posted and forward again does not lose the numbers
     somebody already typed in. */
  function stepBack(o, to) {
    var name = (o.creators || {}).name || 'this creator';
    if (!to || !confirm('Revert ' + name + ' to ' + wordFor(to) + '?')) return;
    var patch = { state: to };
    if (o.state === 'changes') patch.changes_by = null;   // the round is over
    db.from('campaign_options').update(patch).eq('id', o.id).then(function (r) {
      if (r.error) { msg('campWorkMsg', r.error.message, 'err'); return; }
      log('campaign.stage', logSubject(), name + ' · back to ' + wordFor(to));
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
      log('campaign.unbooked', logSubject(), name);
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
        log('campaign.reinstated', logSubject(), name);
        msg('campWorkMsg', name + ' reinstated.', 'ok');
        loadOptions();
      });
  }

  /* Moving to posted needs somewhere for the numbers to go, and there is one
     row per platform because two placements are two posts. */
  /* A round the team turns down. It goes back to the creator with a note and
     a fresh revision number, exactly as a client's rejection does, but the
     client's page never learns the round happened: `changes_by` is what
     get_campaign reads to report it as Pending draft instead. */
  /* The note opens under the button that sends it, which is the shape the
     client's own Request changes already has on /creators/. It used to be a
     browser prompt: a window over the card, in the browser's language, asking
     for several lines in a control that is one line high. */
  function sendBack(o, card) {
    var btn = card.querySelector('[data-a="sendback"]');
    if (!btn) return;
    if (btn._ask) { btn._ask.open(); return; }
    btn._ask = window.ADspaceAsk.note(btn.closest('.kactions') || btn, {
      label: 'What needs changing', send: 'Send to creator',
      placeholder: 'What needs changing? The creator reads this.',
      save: function (why) { sendBackNow(o, card, why); }
    });
    btn._ask.open();
  }

  function sendBackNow(o, card, why) {
    var m = card.querySelector('[data-msg]');
    db.from('campaign_options').update({
      state: 'changes', changes_by: 'team', drop_reason: why,
      revision_round: Math.max(o.revision_round || 0, 1) + 1
    }).eq('id', o.id).then(function (r) {
      if (r.error) { m.textContent = r.error.message; m.className = 'msg err'; return; }
      log('campaign.stage', logSubject(), ((o.creators || {}).name || 'A creator') + ' · changes requested');
      loadOptions();
    });
  }

  /* ---- The quality check ------------------------------------------------
     One sheet, opened by the one control it gates. It holds what it was
     opened with rather than reading the card again, because the card can
     repaint underneath an open sheet. */
  var qc = null;

  function openQc(o, patch) {
    qc = { o: o, patch: patch, done: {} };
    var files = (state.files && state.files[o.id]) || [];
    var name = (o.creators || {}).name || 'this creator';
    $('qcWho').textContent = name + ' · ' +
      (files.length ? files.length + (files.length === 1 ? ' file' : ' files') : 'pasted link');
    msg('qcMsg', '');
    var box = $('qcList');
    box.innerHTML = '';
    /* Fourteen checks read as fourteen only when they are one run. In three
       groups — what it says, what the brief asked for, how the file plays —
       it is three things to hold, which is what a person can. */
    var n = 0;
    QC_CHECKS.forEach(function (group) {
      var head = document.createElement('p');
      head.className = 'qcgroup';
      head.textContent = group[0];
      box.appendChild(head);
      group[1].forEach(function (word) {
        var row = document.createElement('label');
        row.className = 'qcrow';
        row.innerHTML = '<input type="checkbox" data-qc="' + n + '"><span>' + esc(word) + '</span>';
        box.appendChild(row);
        n++;
      });
    });
    Array.prototype.forEach.call(box.querySelectorAll('input'), function (el) {
      el.addEventListener('change', function () {
        qc.done[this.getAttribute('data-qc')] = this.checked;
        qcCount();
      });
    });
    qcCount();
    $('qcSheet').hidden = false;
    var first = box.querySelector('input');
    if (first) first.focus();
  }

  function qcCount() {
    if (!qc) return;
    var all = qcAll();
    var n = all.filter(function (_, i) { return qc.done[i]; }).length;
    $('qcCount').textContent = n + ' of ' + all.length + ' checked';
    /* All of them, or the gate is decoration. The count is what says why the
       button will not move, so nothing has to be explained in a sentence. */
    $('qcGo').disabled = n < all.length;
  }

  function shutQc() { $('qcSheet').hidden = true; qc = null; }

  $('qcClose').addEventListener('click', shutQc);
  $('qcCancel').addEventListener('click', shutQc);
  $('qcSheet').addEventListener('click', function (e) { if (e.target === this) shutQc(); });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && !$('qcSheet').hidden) shutQc();
  });

  $('qcGo').addEventListener('click', function () {
    if (!qc) return;
    var o = qc.o, patch = qc.patch;
    /* Who checked it and when. The step itself is the evidence the check was
       made, because nothing else opens this gate, so the record carries the
       name rather than a second copy of the list. */
    log('campaign.qc', logSubject(),
      ((o.creators || {}).name || 'A creator') + ' · quality checked by ' +
      ((bridge.actorName && bridge.actorName()) || 'the team'));
    shutQc();
    advanceOption(o, 'reviewing', patch);
  });

  function advanceOption(o, to, fields) {
    var patch = Object.assign({}, fields || {}, { state: to });
    // Leaving `changes` ends that round, so whose it was goes with it.
    if (o.state === 'changes') patch.changes_by = null;
    db.from('campaign_options').update(patch).eq('id', o.id).then(function (r) {
      if (r.error) { msg('campWorkMsg', r.error.message, 'err'); return; }
      log('campaign.stage', logSubject(), ((o.creators || {}).name || 'A creator') + ' · ' + wordFor(to));
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
        box.innerHTML = head + '<div class="empty">No placements.</div>';
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

    /* STILL A PROMPT, deliberately, until the sheet that replaces it ships.
       This act states a consequence ("the record is kept for invoice
       reconciliation") and then takes a reason, which is the definition of a
       sheet in this portal, not of a field growing out of a button. Deleting
       the prompt without building the sheet would cost the audit record the
       reason it carries, so it stays until there is somewhere better to put
       it. See the withdraw/replace sheet. */
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

  /* ---- Invoice: raised after confirmation, attached here -----------------
     An invoice follows an accepted booking, so the panel is not there to fill
     in before one exists. Accepted means at least one creator is in
     production: reverting the last of them back to options takes the panel
     away again, on this page and on the client's. */
  function accepted() {
    return (state.options || []).some(function (o) { return IN_PRODUCTION.indexOf(o.state) > -1; });
  }

  function paintInvoice(c) {
    var on = accepted();
    $('invoicePanel').hidden = !on;
    if (!on) { setOpen('invoiceToggle', 'invoiceBody', false); return; }
    // The closed panel says what it holds, and opens itself once it holds something.
    $('invoiceSummary').textContent = c.invoice_url
      ? (c.invoice_no ? c.invoice_no + ' · PDF attached' : 'PDF attached')
      : (c.invoice_no ? c.invoice_no + ' · no PDF' : 'Not issued');
    $('invNo').value = String(c.invoice_no || '').replace(/^AINV/i, '');
    $('invFile').value = '';
    var cur = $('invCurrent');
    if (c.invoice_url) {
      cur.innerHTML =
        '<a class="btn btn-icon" href="' + esc(c.invoice_url) + '" target="_blank" rel="noopener">View invoice' +
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" ' +
        'stroke-linejoin="round" aria-hidden="true"><path d="M14 4h6v6"/><path d="M20 4 11 13"/>' +
        '<path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg></a>' +
        (c.invoice_uploaded_at
          ? '<span class="muted">Uploaded ' + niceDate(String(c.invoice_uploaded_at).slice(0, 10)) + '</span>' : '') +
        '<button class="btn btn-warn" id="invRemove" type="button">Remove PDF</button>';
      cur.querySelector('#invRemove').addEventListener('click', function () { setInvoiceFile(c, null, null); });
    } else {
      cur.innerHTML = '<span class="muted">No PDF</span>';
    }
    msg('invMsg', '');
  }

  /* Removing the PDF clears the link the client sees; the file itself stays
     with the accountant. Undo puts the link back. */
  var undoTimer = null;
  /* The way back is drawn where the act happened.

     `#campUndo` is one bar at the top of the campaign record, above the pane
     strip. Taking a handed-in file off happens inside a creator's card, which
     on a campaign of five creators is most of a screen further down: the file
     vanished from under the pointer and the bar offering it back rendered
     223px above the top of the window, measured. A safeguard nobody can see is
     not one, and this is the fault behind "there is no way back" on a control
     that has had a way back since it shipped.

     `host` is the element the act belongs to; the bar is put directly after it
     and taken away again. Without one it falls back to the record's own bar,
     which is right for something at the top of the record. */
  function undoBar(text, undo, host) {
    var bar = $('campUndo');
    if (host && host.parentNode) {
      bar = host.parentNode.querySelector(':scope > .undobar-here');
      if (!bar) {
        bar = document.createElement('div');
        bar.className = 'undobar undobar-here';
        host.parentNode.insertBefore(bar, host.nextSibling);
      }
    }
    bar.hidden = false;
    bar.innerHTML = '<span>' + esc(text) + '</span><button class="btn btn-sm" type="button">Undo</button>';
    bar.querySelector('button').addEventListener('click', function () { shutUndo(bar); undo(); });
    clearTimeout(undoTimer);
    undoTimer = setTimeout(function () { shutUndo(bar); }, 8000);
    /* It is put where the act was, so it is already on screen in the ordinary
       case; this is for the one where the card sits at the very foot of the
       pane and the bar lands under the fold it opened in. */
    if (bar.scrollIntoViewIfNeeded) bar.scrollIntoViewIfNeeded();
    else if (bar.getBoundingClientRect().bottom > window.innerHeight) {
      bar.scrollIntoView({ block: 'nearest' });
    }
  }
  function shutUndo(bar) {
    bar.hidden = true;
    if (bar.classList.contains('undobar-here') && bar.parentNode) bar.parentNode.removeChild(bar);
  }
  function setInvoiceFile(c, url, stamp) {
    var was = { url: c.invoice_url, stamp: c.invoice_uploaded_at };
    db.from('campaigns').update({ invoice_url: url, invoice_uploaded_at: stamp }).eq('id', c.id).then(function (r) {
      if (r.error) { msg('invMsg', r.error.message, 'err'); return; }
      c.invoice_url = url; c.invoice_uploaded_at = stamp;
      log(url ? 'campaign.invoice_file' : 'campaign.invoice_removed', c.title, c.invoice_no || '');
      paintInvoice(c);
      /* Same reason as the handed-in file above: the Finance pane sits inside
         the record, and the record's own bar is above the pane strip. */
      if (!url) undoBar('Invoice PDF removed.',
        function () { setInvoiceFile(c, was.url, was.stamp); }, $('invMsg'));
    });
  }

  /* The number and the PDF are one invoice, so they are saved together. The
     PDF goes to S3 by the same signed path media takes, and the campaign keeps
     the public URL. Only the URL is ours to store; the file is the
     accountant's. */
  $('invSave').addEventListener('click', function () {
    var c = state.campaign;
    if (!accepted()) { msg('invMsg', 'Confirm the creators first.', 'err'); return; }
    var no = invoiceNo();
    var file = $('invFile').files && $('invFile').files[0];
    if (file && !/pdf$/i.test(file.type) && !/\.pdf$/i.test(file.name)) {
      msg('invMsg', 'The invoice has to be a PDF.', 'err'); return;
    }
    if (file && !putToS3) { msg('invMsg', 'Uploads are not available on this page.', 'err'); return; }

    msg('invMsg', file ? 'Uploading…' : 'Saving…');
    var step = file
      ? db.functions.invoke((cfg.s3 && cfg.s3.functionName) || 'sign-upload', {
          body: { ext: 'pdf', clientId: c.client_id, size: file.size }
        }).then(function (r) {
          if (r.error) throw new Error('Could not start the upload. ' + r.error.message);
          if (!r.data || !r.data.uploadUrl) throw new Error('Upload was refused: ' + ((r.data && r.data.error) || 'unknown reason'));
          return putToS3(r.data.uploadUrl, file, 'application/pdf').then(function () { return r.data.publicUrl; });
        })
      : Promise.resolve(null);

    step.then(function (url) {
      var patch = { invoice_no: no };
      var stamp = null;
      if (url) { stamp = new Date().toISOString(); patch.invoice_url = url; patch.invoice_uploaded_at = stamp; }
      return db.from('campaigns').update(patch).eq('id', c.id).then(function (r) {
        if (r.error) throw new Error(r.error.message);
        c.invoice_no = no;
        if (url) { c.invoice_url = url; c.invoice_uploaded_at = stamp; }
        log(url ? 'campaign.invoice_file' : 'campaign.invoice', c.title, no || 'cleared');
        paintInvoice(c);
        msg('invMsg', 'Saved.', 'ok');
      });
    }).catch(function (e) { msg('invMsg', e.message, 'err'); });
  });

  // Cancel puts back what is stored, so a typed number that was never saved
  // leaves no trace.
  $('invCancel').addEventListener('click', function () {
    paintInvoice(state.campaign);
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
  $('bulkToggle').addEventListener('click', function () { bulkOpen(this); });
  $('bulkCancel').addEventListener('click', function () { $('bulkBox').hidden = true; });

  function bulkValues() {
    var day = $('bulkDate').value || null;
    return {
      visit_date: day,
      visit_time: ($('bulkTime').value || '').trim() || null,
      submission_due: day ? addDays(day, 7) : null
    };
  }

  function applyBulk(overwrite) {
    var vals = bulkValues();
    var keys = Object.keys(vals).filter(function (k) { return vals[k] !== null; });
    if (!keys.length) { msg('bulkMsg', 'A date or a note is required.', 'err'); return; }

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
        tab: (!state.campaign && state.tab === 'roster') ? 'roster' : '',
        /* Overview is the default, so a link to a campaign is the campaign
           and not the campaign on its first pane. */
        pane: (state.campaign && campPane !== 'overview') ? campPane : ''
      };
    },
    /* On entry, read the address rather than starting from the list. An open
       campaign is fetched by id so a refresh lands inside it, not in front of it. */
    enter: function () {
      var params = new URLSearchParams(location.search);
      var id = params.get('campaign');
      if (id && !(state.campaign && state.campaign.id === id)) {
        db.from('campaigns').select('*, clients(name, market, sst_applies, logo_url)').eq('id', id).single().then(function (r) {
          if (r.error || !r.data) { state.campaign = null; showTab('campaigns'); return; }
          state.tab = 'campaigns';
          Array.prototype.forEach.call(document.querySelectorAll('#campSectionTabs .tab'), function (b) {
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
