/* Video Scripts (2026-10-09): a client's scripts by content month, one a video,
 * published to the client on its link and printed for the crew on site.
 *
 * The user: "a script table covers one video, hence there is a # … three
 * different types of script, detailed scenes / products + scenes / story +
 * VO. VC# is the video clip number on camera … one digital similar as content
 * review able to view online, another is export pdf for on-site use."
 *
 * One script is one full video, made in a client's content month and
 * numbered in it, YYMMVSNN (2026-10-09-scripts-by-month.sql; the user: "we
 * are working on content month, monthly basis"). The list is a card a
 * client, a row a script. A script opens in its content month's record:
 * the client and the month with the client's link once, a tab a script, and
 * the script on show with its own head (state, Edit, Publish), its facts in
 * one card, the script in another, and on the day each scene's tick and clip
 * number (VC#). Edit is a page of its own; Add script makes the next number
 * of the same month with its header copied. Publish shows it on the client link
 * (`/script/?k=`), where it is read and the clip numbers can be recorded on
 * site; nobody decides on it there. Every write is a function
 * (`video_script_*`); the PDF is drawn here, never stored.
 */
(function () {
  'use strict';
  var API = window.ADspaceAPI;
  var db = API && API.client;
  if (!API || !API.configured || !db) return;
  var bridge = window.ADspaceAdmin || {};
  var $ = function (id) { return document.getElementById(id); };
  var UI = window.ADspaceState;

  var KINDS = [['scenes', 'Detailed scenes'], ['products', 'Products and scenes'], ['story', 'Story and voice-over']];
  /* Edit, Publish and Unpublish are drawn as words: js/acts.js gives each
     its mark, so the console draws an act one way (2026-10-14). */
  var KIND_WORD = {};
  KINDS.forEach(function (k) { KIND_WORD[k[0]] = k[1]; });
  var CONTEXT_WORD = { products: 'Products and context', story: 'Hook and story' };
  var SCENE_WORD = { scenes: 'Visual', products: 'Scene', story: 'Scene' };
  var PLATFORMS = ['Instagram', 'TikTok', 'Facebook', 'rednote', 'YouTube'];
  var LANGS = ['English', 'Chinese', 'Malay', 'English and Chinese'];
  /* The stored word stays; the page says Bahasa Melayu, as Write caption does. */
  function langWord(v) { return v === 'Malay' ? 'Bahasa Melayu' : v; }
  var DURATIONS = [30, 60, 90, 120, 180, 240, 300, 360, 480, 600, 720];
  /* The brief's lists and a shot's words (2026-11-05, the shot table). The
     stored keys never move; the page says the words. */
  var OBJECTIVES = [['awareness', 'Awareness'], ['traffic', 'Traffic'], ['leads', 'Leads'], ['sales', 'Sales'], ['app_install', 'App install']];
  var FORMATS = [['talking_head', 'Talking head'], ['skit', 'Skit'], ['ugc', 'UGC style'], ['demo', 'Product demo'],
                 ['testimonial', 'Testimonial'], ['montage', 'Voice-over montage']];
  var SHOT_SIZES = ['Extreme wide', 'Wide', 'Medium', 'Medium close-up', 'Close-up', 'Extreme close-up', 'Insert'];
  var ANGLES = ['Eye level', 'High angle', 'Low angle', 'Overhead', 'From behind', 'Over the shoulder', 'Through objects', 'Point of view'];
  var PLAN = [['core_message', 'Core message'], ['hook', 'Hook (0 to 3 seconds)'], ['concept', 'Concept'], ['cta', 'Call to action in the video'],
              ['cast', 'Cast roles'], ['locations', 'Locations'], ['props', 'Props'], ['music', 'Music mood']];
  var BRIEF_WORDS = [['offer', 'Product or offer'], ['objective', 'Objective'], ['audience', 'Target audience'], ['key_message', 'Key message'],
                     ['cta', 'Call to action'], ['must_include', 'Must include'], ['must_avoid', 'Must avoid'], ['tone', 'Tone'], ['format', 'Format']];
  function wordOf(list, k) { var m = list.filter(function (x) { return x[0] === k; })[0]; return m ? m[1] : k; }
  /* A second into the video as the crew reads it: 0:03. */
  function clockOf(n) { n = Number(n); return Math.floor(n / 60) + ':' + ('0' + (n % 60)).slice(-2); }
  function timeOf(sc) {
    if (sc.t_from == null && sc.t_to == null) return '';
    return (sc.t_from == null ? '' : clockOf(sc.t_from)) + (sc.t_to == null ? '' : '\u2013' + clockOf(sc.t_to));
  }
  /* A scene's timing and camera on one line over what is seen. */
  function camOf(sc) { return [timeOf(sc), sc.shot_size, sc.angle, sc.camera_move].filter(Boolean).join(' \u00b7 '); }
  function lengthWord(n) { return n ? n + 's' : ''; }
  var MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
  var STATE = { draft: ['Draft', 'is-off'], shared: ['Published', 'is-live'] };
  var ICON = {
    dots: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="5" cy="12" r="1.6" fill="currentColor"/><circle cx="12" cy="12" r="1.6" fill="currentColor"/><circle cx="19" cy="12" r="1.6" fill="currentColor"/></svg>',
    plus: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>',
    copy: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/></svg>',
    camera: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/></svg>',
    up: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 14 6-6 6 6"/></svg>',
    down: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 10 6 6 6-6"/></svg>',
    x: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>',
    out: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 4h6v6"/><path d="M20 4 11 13"/><path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg>'
  };

  var st = { list: [], clients: [], loaded: false, open: null, scenes: [],
             series: [], key: null, draft: [], idem: null, find: '', editing: null, base: '' };

  function esc(s) { return window.ADspaceWords.esc(s); }
  function say(el, text, tone) {
    if (!el) return;
    el.textContent = text || '';
    el.className = 'msg' + (text ? ' ' + (tone || 'err') : '');
  }
  function may(level) { return Boolean(bridge.may && bridge.may('scripts', level || 'work')); }
  function dayWord(iso) {
    if (!iso) return '';
    return window.ADspaceClock.date(iso);
  }
  /* A time of day as every console page writes it, Malaysia's clock's one
     copy: 10:00am, no space (2026-10-22, VS-2). */
  function timeWord(t) {
    var m = /^(\d{1,2}):(\d{2})/.exec(t || '');
    if (!m) return '';
    return window.ADspaceClock.clock('2000-01-01T' + (m[1].length < 2 ? '0' : '') + m[1] + ':' + m[2]);
  }
  function durWord(n) {
    n = Number(n) || 0;
    if (!n) return '';
    var h = Math.floor(n / 60), m = n % 60;
    return (h ? h + (h === 1 ? ' hour' : ' hours') : '') + (h && m ? ' ' : '') + (m ? m + ' min' : '');
  }
  function codeOf(s) { return s.code || 'V' + s.video_no; }
  function label(s) { return codeOf(s) + (s.title ? ' · ' + s.title : ''); }
  function typedName(s) { return s.title ? s.title : codeOf(s); }
  /* A content month: `2026-10` reads Oct 2026. */
  function monthWord(p) {
    var m = /^(\d{4})-(\d{2})$/.exec(p || '');
    return m ? MON[Number(m[2]) - 1] + ' ' + m[1] : '';
  }
  /* The months a script is made in: last month, this month and the next
     six (MYT), as My Work offers them, and the month it holds. */
  function monthsAround(cur) {
    var now = window.ADspaceClock.today(), out = [];
    for (var i = -1; i <= 6; i++) out.push(window.ADspaceClock.addMonths(now, i));
    if (cur && out.indexOf(cur) < 0) { out.push(cur); out.sort(); }
    return out;
  }
  function thisMonth() { return monthsAround()[1]; }
  function fillMonth(sel, cur) {
    sel.innerHTML = monthsAround(cur).map(function (p) {
      return '<option value="' + p + '"' + (p === cur ? ' selected' : '') + '>' + esc(monthWord(p)) + '</option>';
    }).join('');
  }
  function uuid() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    return 'x' + Date.now() + Math.random().toString(16).slice(2);
  }

  /* A refusal in the team's words. */
  var SAID = {
    denied: 'You do not have permission to change video scripts. Please ask an admin.',
    'client-scope': 'This client is outside your access.',
    'not-found': 'This script is no longer available.',
    'bad-kind': 'Choose the script type.',
    'bad-period': 'Choose the content month.',
    'bad-title': 'A title is 200 characters at most.',
    'bad-link': 'A reference link starts with https://.',
    'bad-duration': 'Choose a duration between 5 minutes and 24 hours.',
    'bad-date': 'Choose a date from 14 Aug 2023.',
    'too-long': 'A field is too long to save.',
    'too-many': 'A month can have up to 99 scripts, and a script up to 60 scenes.',
    'bad-scenes': 'The scenes could not be read.',
    'bad-time': 'Enter each scene\'s time in whole seconds from 0 to 600, the end after the start.',
    'bad-aspect': 'Choose the aspect ratio.',
    'bad-length': 'Choose the video length.',
    'bad-brief': 'The brief could not be saved. Check each field and try again.',
    'bad-plan': 'Enter up to 2,000 characters in each field.',
    'bad-review': 'The AI review could not be saved. Write with AI again.',
    stale: 'Not saved. This script was changed by someone else. The latest version is now shown. Please enter your change again.',
    'denied-delete': 'You do not have permission to delete scripts. Please ask an admin.',
    name: 'The name does not match.'
  };
  function said(e) {
    var m = String((e && (e.message || e.error)) || e || '');
    if (SAID[m]) return SAID[m];
    if (/function .* does not exist|schema cache|relation .*video_script|PGRST20[25]/i.test(m)) return 'This feature is not available yet. Please contact an admin.';
    if (/row-level security|new row violates|client-scope/i.test(m)) return SAID.denied;
    return m || 'Not saved. Try again.';
  }
  function rpc(name, args) {
    return db.rpc(name, args).then(function (r) {
      if (r.error) throw r.error;
      var d = r.data || {};
      if (d.error) { var e = new Error(d.error); e.data = d; throw e; }
      return d;
    });
  }

  /* Where a script stands: a draft, or published on the client link. */
  function stateOf(s) { return s.status === 'shared' ? 'shared' : 'draft'; }
  function chip(key) {
    var w = STATE[key] || STATE.draft;
    return '<span class="chip-state ' + w[1] + '">' + esc(w[0]) + '</span>';
  }

  /* ---- The list ------------------------------------------------------------ */
  function load() {
    var box = $('vsList');
    if (!st.loaded) UI.skeleton(box, 4);
    /* Read a thousand at a time: thirty to fifty scripts a client a year
       pass PostgREST's 1,000 inside a year (2026-10-22, VS-1). Ordered to
       the id, so a page boundary never repeats or drops a row. */
    return API.readPages(function () {
      return db.from('video_scripts')
        .select('id, client_id, period, seq, code, video_no, kind, title, status, shoot_on, venue, updated_at, created_at, clients(name, client_code)')
        .order('period', { ascending: false }).order('seq').order('id');
    })
      .then(function (r) {
        if (r.error) throw r.error;
        st.list = r.data || [];
        st.loaded = true;
        paint();
      }).catch(function (e) {
        UI.failLine(box, 'Video Scripts', said(e), load);
      });
  }

  function shown() {
    var q = st.find.trim().toLowerCase();
    if (!q) return st.list;
    return st.list.filter(function (s) {
      return [s.title, s.venue, s.clients && s.clients.name, s.clients && s.clients.client_code, s.code, monthWord(s.period)]
        .join(' ').toLowerCase().indexOf(q) > -1;
    });
  }

  function paint() {
    var box = $('vsList');
    if ($('vsNew')) $('vsNew').hidden = !may('work');
    var list = shown();
    var all = st.list.length;
    $('vsCount').textContent = !all ? '' : list.length !== all ? list.length + ' of ' + all
      : all + (all === 1 ? ' script' : ' scripts');
    box.innerHTML = '';
    if (!all) {
      UI.emptyLine(box, 'No scripts.', may('work') ? 'New script' : '', function () { openNew($('vsNew')); });
      return;
    }
    if (!list.length) {
      UI.emptyLine(box, 'No matches.', 'Clear search', function () { $('vsFind').value = ''; st.find = ''; paint(); });
      return;
    }
    /* A card a content month, newest first (the user, 2026-10-10: thirty
       to fifty videos a client a year), as Reports runs a card a report
       month: the newest open, the rest shut until opened. A row is one
       client's month, opening its record on its first script (on the
       script a search found). */
    var GRP = window.ADspaceGroup;
    var byMonth = {}, months = [];
    list.forEach(function (s) {
      var p = String(s.period || '').slice(0, 7) || 'none';
      if (!byMonth[p]) { byMonth[p] = {}; months.push(p); }
      var g = byMonth[p][s.client_id] || (byMonth[p][s.client_id] = { client: s.clients || {}, period: s.period, scripts: [] });
      g.scripts.push(s);
    });
    /* Newest month first, No month last (2026-11-03): 'none' sorted above
       every real month. */
    months.sort(function (a, b) { return (a === 'none') - (b === 'none') || b.localeCompare(a); });
    months.forEach(function (p, i) {
      var groups = Object.keys(byMonth[p]).map(function (k) { return byMonth[p][k]; });
      groups.forEach(function (g) { g.scripts.sort(function (a, b) { return (a.seq || 0) - (b.seq || 0); }); });
      groups.sort(function (a, b) { return String(a.client.name || '').localeCompare(String(b.client.name || ''), 'en', { sensitivity: 'base' }); });
      var n = groups.reduce(function (t, g) { return t + g.scripts.length; }, 0);
      box.appendChild(GRP.section({
        route: 'scripts', key: 'm' + p, name: p === 'none' ? 'No month' : monthWord(p), count: n,
        shut: !st.find && GRP.shut('scripts', 'm' + p, i > 0, months.length === 1),
        table: function () {
          /* The column is the state, as the month's list heads it; its chip
             never repeats a heading (2026-10-20, VS-1). */
          var table = GRP.table('vs-row', ['Client', 'Next shoot', 'State', '']);
          GRP.more(table, groups, 30, 'scripts', rowOf);
          return table;
        }
      }));
    });
  }

  /* One client's month: the client over its codes and scripts, the next
     shoot (else the last), and how many of its scripts are published. */
  /* The mark that says a row opens something, in the column every list
     keeps for it (2026-11-03). */
  var GO = '<svg class="crm-c-go" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>';
  function rowOf(g) {
    var row = document.createElement('button');
    row.type = 'button';
    row.className = 'crm-row vs-row';
    var list = g.scripts, n = list.length;
    var pub = list.filter(function (x) { return stateOf(x) === 'shared'; }).length;
    var codes = list.map(function (x) { return tabWord(x); });
    var today = window.ADspaceClock.today();
    var days = list.map(function (x) { return x.shoot_on; }).filter(Boolean).sort();
    var ahead = days.filter(function (d) { return d >= today; })[0], shoot = ahead || days[days.length - 1];
    row.setAttribute('data-id', list[0].id);
    row.innerHTML =
      '<span class="vs-c-name"><b>' + esc(g.client.name || 'Client') + (window.ADspaceAdmin ? window.ADspaceAdmin.vicTag(list[0].client_id, true) : '') + '</b><small>' +
        esc((n === 1 ? codes[0] : codes[0] + ' to ' + codes[n - 1]) + ' · ' + n + (n === 1 ? ' script' : ' scripts')) + '</small></span>' +
      '<span class="vs-c-shoot">' + (shoot ? esc(dayWord(shoot)) + (ahead ? '' : ' <span class="mute">· Last</span>') : '<span class="mute">Not set</span>') + '</span>' +
      '<span class="vs-c-state">' + (pub === n ? chip('shared') : pub ? '<span class="chip-state is-warn">' + pub + ' of ' + n + '</span>' : chip('draft')) + '</span>' + GO;
    row.addEventListener('click', function () { openMonth(list[0].id, true); });
    return row;
  }

  var lastFind = '';
  ['input', 'change'].forEach(function (ev) {
    $('vsFind').addEventListener(ev, function () {
      if ($('vsFind').value === lastFind) return;
      lastFind = st.find = $('vsFind').value;
      if (st.loaded) paint();
    });
  });

  /* ---- New script ------------------------------------------------------------ */
  function loadClients() {
    return db.from('clients').select('id, name, client_code').eq('stage', 'active').order('name').then(function (r) {
      if (r.error) throw r.error;
      var F = window.ADspaceForm;
      st.clients = (r.data || []).slice().sort(F && F.sequence ? F.sequence('client_code') : undefined);
      return st.clients;
    });
  }
  function openNew(opener) {
    say($('vsNewMsg'), '');
    st.idem = uuid();
    var sel = $('vsNewClient');
    sel.innerHTML = '<option value="">Loading…</option>';
    fillMonth($('vsNewMonth'), thisMonth());
    window.ADspaceSheet.show($('vsNewSheet'), { opener: opener || null });
    loadClients().then(function (list) {
      var F = window.ADspaceForm;
      sel.innerHTML = '<option value="">Choose a client</option>' + list.map(function (c) {
        return '<option value="' + esc(c.id) + '">' + esc(F && F.named ? F.named(c.client_code, c.name) : c.name) + '</option>';
      }).join('');
    }).catch(function (e) {
      sel.innerHTML = '<option value="">Clients could not be loaded</option>';
      say($('vsNewMsg'), 'Clients could not be loaded. ' + said(e));
    });
  }
  $('vsNew').addEventListener('click', function () { openNew($('vsNew')); });
  $('vsNewCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
  $('vsNewClose').addEventListener('click', function () { $('vsNewCancel').click(); });
  $('vsNewGo').addEventListener('click', function () {
    var m = $('vsNewMsg'), btn = $('vsNewGo');
    var client = $('vsNewClient').value;
    if (!client) { say(m, 'Choose a client.'); $('vsNewClient').focus(); return; }
    /* The editor opens on the new script, stored only by its Save
       (2026-10-15, audit VS-1 as Add script): Cancel leaves no empty
       numbered script on the month or the client's link. */
    var c = st.clients.filter(function (x) { return x.id === client; })[0] || {};
    var period = $('vsNewMonth').value, kind = $('vsNewKind').value;
    window.ADspaceSheet.clean();
    window.ADspaceSheet.close();
    st.open = null;
    st.pending = {
      args: { p_client: client, p_period: period, p_kind: kind, p_from: null, p_idem: st.idem },
      s: { id: null, client_id: client, period: period, kind: kind, title: '', reference_url: null,
           platform: null, language: null, shoot_on: null, shoot_time: null, venue: null,
           duration_minutes: null, cast_names: null, context: '', vo: '', remarks: '',
           clients: { name: c.name, client_code: c.client_code }, version: null }
    };
    openEdit(btn, false);
  });

  /* ---- One video ------------------------------------------------------------- */
  /* A month (its scripts as rows) and one script (its page, with Previous
     and Next) are two views of the same record (2026-10-10). */
  function openMonth(id, push) { return openScript(id, push, false, true); }
  function openScript(id, push, edit, month) {
    st.mode = month ? 'month' : 'script';
    st.open = { id: id };
    $('vsListView').hidden = true;
    $('vsRecord').hidden = false;
    window.scrollTo(0, 0);
    if (push && bridge.pushUrl) bridge.pushUrl(); else if (bridge.setUrl) bridge.setUrl();
    UI.skeleton($('vsRecBody'), 3);
    return readScript(id).then(pingDraw).then(function () {
      paintRecord();
      if (edit && may('work')) openEdit($('vsRecBody').querySelector('[data-a="edit"]'), push);
      else if (!month) bringShot();
    }).catch(function (e) {
      if (e && e.message === 'not-found') {
        backToList();
        say($('vsListMsg'), 'That script is no longer available.', 'warn');
        return;
      }
      UI.failLine($('vsRecBody'), 'The script', said(e), function () { openScript(id, false, false, month); });
    });
  }
  function readScript(id) {
    return db.from('video_scripts').select('*, clients(name, client_code, slug, logo_url)').eq('id', id).maybeSingle().then(function (r) {
      if (r.error) throw r.error;
      if (!r.data) throw new Error('not-found');
      st.open = r.data;
      return Promise.all([
        db.from('video_script_scenes').select('id, position, visual, line, vc, shot_at, shot_by, t_from, t_to, shot_size, angle, camera_move, on_screen, sound, photo_url, photo_by, photo_thumb, ai_url').eq('script_id', id).order('position'),
        db.from('video_scripts').select('id, code, seq, video_no, title, status, kind, shoot_on, venue').eq('client_id', st.open.client_id)
          .eq('period', st.open.period).order('seq')
      ]);
    }).then(function (rs) {
      rs.forEach(function (x) { if (x.error) throw x.error; });
      st.scenes = rs[0].data || [];
      st.series = rs[1].data || [];
    });
  }
  /* On its shooting day (Malaysia) a script opens on the first scene not yet
     shot, for whoever records them (VS-3): brought to the middle of the
     screen, never focused (a focused field zooms an iPhone). */
  function bringShot() {
    var s = st.open;
    if (!s || !may('work') || !s.shoot_on || String(s.shoot_on).slice(0, 10) !== window.ADspaceClock.today()) return;
    var row = null;
    Array.prototype.some.call($('vsRecBody').querySelectorAll('[data-scene]'), function (r) {
      var box = r.querySelector('[data-shot]');
      if (box && !box.checked) { row = r; return true; }
      return false;
    });
    if (!row && $('vsVoShot') && !$('vsVoShot').checked) row = $('vsRecBody').querySelector('[data-vo]');
    if (!row) return;
    var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    /* Two frames: the pane's width classes (`is-narrow`, js/state.js) are
       written by a ResizeObserver after the first layout. */
    requestAnimationFrame(function () { requestAnimationFrame(function () {
      if (!row.isConnected) return;
      var r = row.getBoundingClientRect();
      if (r.top >= 0 && r.bottom <= window.innerHeight * 0.8) return;
      var to = window.scrollY + r.top - Math.max(0, (window.innerHeight - r.height) / 2);
      window.scrollTo({ top: Math.max(0, to), behavior: reduce ? 'auto' : 'smooth' });
    }); });
  }
  function backToList() {
    st.open = null;
    $('vsRecord').hidden = true;
    $('vsListView').hidden = false;
    if (bridge.setUrl) bridge.setUrl();
    load();
  }
  /* Back from a script is its month; from the month, the list. */
  $('vsBack').addEventListener('click', function () {
    if (st.mode === 'script' && st.open && st.open.id) openMonth(st.open.id, true); else backToList();
  });

  function facts(s) {
    var f = [];
    f.push(['Platform', s.platform || '']);
    f.push(['Language', langWord(s.language) || '']);
    f.push(['Aspect ratio', s.aspect || '']);
    f.push(['Video length', lengthWord(s.length_seconds)]);
    f.push(['Shooting date', [dayWord(s.shoot_on), timeWord(s.shoot_time)].filter(Boolean).join(', ')]);
    f.push(['Venue', s.venue || '']);
    f.push(['Estimated duration', durWord(s.duration_minutes)]);
    f.push(['Cast', s.cast_names || '']);
    var ref = s.reference_url
      ? '<div class="vs-ref"><dt>Reference video</dt><dd><a class="plink" href="' + esc(s.reference_url) +
        '" target="_blank" rel="noopener">' + '<span class="vs-ref-url">' + esc(s.reference_url.replace(/^https:\/\//, '')) + '</span>' + ICON.out + '</a></dd></div>'
      : '';
    return '<dl class="facts vs-facts">' + f.map(function (x) {
      return '<div><dt>' + esc(x[0]) + '</dt><dd>' + (x[1] ? esc(x[1]) : '<span class="mute">Not set</span>') + '</dd></div>';
    }).join('') + ref + '</dl>' + briefHtml(s);
  }
  /* The brief the script is written to, the team's alone: only what is
     set, the shoot's limits on one line. */
  function briefHtml(s) {
    var b = s.brief || {};
    var rows = BRIEF_WORDS.filter(function (x) { return b[x[0]]; }).map(function (x) {
      var v = x[0] === 'objective' ? wordOf(OBJECTIVES, b.objective) : x[0] === 'format' ? wordOf(FORMATS, b.format) : b[x[0]];
      return [x[1], v];
    });
    var lim = [b.max_locations ? b.max_locations + (b.max_locations === 1 ? ' location' : ' locations') : '',
               b.max_cast ? b.max_cast + ' cast' : '', b.max_shoot_hours ? b.max_shoot_hours + (b.max_shoot_hours === 1 ? ' hour' : ' hours') : '']
      .filter(Boolean).join(' \u00b7 ');
    if (lim) rows.push(['Shoot limits', lim]);
    if (!rows.length) return '';
    return '<section class="vs-block vs-brief"><h4 class="fsec-h">Brief</h4>' + planList(rows) + '</section>';
  }
  function planList(rows) {
    return '<dl class="vs-plan">' + rows.map(function (x) {
      return '<div><dt>' + esc(x[0]) + '</dt><dd>' + esc(x[1]) + '</dd></div>';
    }).join('') + '</dl>';
  }
  function planHtml(s) {
    var p = s.plan || {};
    var rows = PLAN.filter(function (x) { return p[x[0]]; }).map(function (x) { return [x[1], p[x[0]]]; });
    return rows.length ? '<section class="vs-block"><h4 class="fsec-h">Plan</h4>' + planList(rows) + '</section>' : '';
  }

  /* THE AI REVIEW (2026-11-05): what a fresh reader found in the script Write
     with AI drafted, kept with the version it was saved at: Passed, or Check
     needed where a critical problem stood after the one rewrite; the story
     and the core message as the reviewer read them; each problem with its
     scene, the fix, its severity and, where unsure, Possible; what the first
     reading found that the rewrite fixed; and the facts the brief lacked. */
  function issueRows(list) {
    return '<div class="vs-issues">' + list.map(function (x) {
      return '<div class="vs-issue"><span class="vs-n">' + (x.shot ? esc(String(x.shot)) : '<span class="vs-all">All</span>') + '</span>' +
        '<span class="vs-issue-text"><span>' + esc(x.problem || '') + '</span>' +
        (x.fix ? '<span class="vs-issue-fix">Fix: ' + esc(x.fix) + '</span>' : '') + '</span>' +
        '<span class="vs-issue-tags">' + (x.severity === 'critical' ? '<span class="chip chip-state is-danger">Critical</span>' : '<span class="chip">Minor</span>') +
        (x.certainty === 'possible' ? '<span class="chip">Not certain</span>' : '') + '</span></div>';
    }).join('') + '</div>';
  }
  function reviewHtml(rv, stale) {
    if (!rv) return '';
    var pass = rv.verdict === 'pass';
    var issues = Array.isArray(rv.issues) ? rv.issues : [];
    var first = rv.first && Array.isArray(rv.first.issues) ? rv.first.issues : [];
    var qs = Array.isArray(rv.questions) ? rv.questions.filter(Boolean) : [];
    var notes = ['', stale ? 'The script changed after this review.' : ''].filter(Boolean).join(' ');
    var out = '<div class="vs-rvhead"><h4 class="fsec-h">AI review</h4>' +
      '<span class="chip chip-state ' + (pass ? 'is-ok' : 'is-warn') + '">' + (pass ? 'Passed' : 'Check needed') + '</span></div>';
    if (notes) out += '<p class="vs-rvnote">' + esc(notes) + '</p>';
    var read = [rv.story ? ['Story', rv.story] : null, rv.core_message ? ['Core message', rv.core_message] : null].filter(Boolean);
    if (read.length) out += planList(read);
    out += issues.length ? issueRows(issues) : '<p class="vs-rvnote">No problems.</p>';
    if (first.length) {
      out += '<details class="vs-rvfold"><summary>Fixed in the rewrite <span class="tab-n">' + first.length + '</span></summary>' + issueRows(first) + '</details>';
    }
    if (qs.length) {
      out += '<div class="vs-rvq"><span class="field-label">Open questions</span><ul>' + qs.map(function (q) { return '<li>' + esc(q) + '</li>'; }).join('') + '</ul></div>';
    }
    return out;
  }

  /* ON THE DAY (the user, 2026-10-09: "make it simple to enter"): each
     scene's clip number is one field; Enter records it, ticks Shot and moves
     to the next scene's field, and an empty field offers the next number
     after the last one recorded (C0042, then C0043), which Enter takes. */
  function clipField(v, name, id) {
    return '<input class="input input-sm" type="text" maxlength="40" value="' + esc(v || '') + '" data-saved="' + esc(v || '') + '"' +
      (id ? ' id="' + id + '"' : '') + ' aria-label="' + esc(name) + '" placeholder="VC#" data-vc autocomplete="off"' +
      ' autocapitalize="characters" spellcheck="false" enterkeyhint="next">';
  }
  function nextClip(v) {
    var m = /^(.*?)(\d+)(\D*)$/.exec(String(v || '').trim());
    if (!m) return '';
    var n = String(Number(m[2]) + 1);
    while (n.length < m[2].length) n = '0' + n;
    return m[1] + n + m[3];
  }
  /* Every empty field's suggestion, read down the page from the last number
     recorded above it. */
  function suggest() {
    var last = '';
    Array.prototype.forEach.call($('vsRecBody').querySelectorAll('input[data-vc]'), function (i) {
      var v = i.value.trim();
      if (v) { last = v; i.placeholder = 'VC#'; i.removeAttribute('data-next'); return; }
      var next = last ? nextClip(last) : '';
      i.placeholder = next || 'VC#';
      if (next) { i.setAttribute('data-next', next); last = next; } else i.removeAttribute('data-next');
    });
  }

  /* The script as the team reads it, with the crew's tick and clip number on
     each scene. */
  /* SCENE PICTURES (2026-11-05; the user: all three, the team's alone): the
     best picture a scene has, the colleague's photo or sketch, else the one
     AI drew, else the frame drawn from its shot (js/frames.js); Add photo
     opens the camera on a phone, Remove takes the photo away with Undo. */
  function picOf(sc) {
    if (sc.photo_url) return { url: sc.photo_url, tag: sc.photo_by ? 'Photo by ' + sc.photo_by : 'Photo', kind: 'photo' };
    if (sc.ai_url) return { url: sc.ai_url, tag: 'Drawn with AI', kind: 'ai' };
    var f = window.ADspaceFrames ? window.ADspaceFrames.svg(sc, st.open && st.open.aspect) : '';
    return f ? { svg: f, tag: 'Sketch from shot', kind: 'frame' } : null;
  }
  function picCell(sc, i, s, work) {
    var p = picOf(sc);
    var box = !p ? '<span class="vs-pic-box is-none" aria-hidden="true"></span>'
      : p.svg ? '<span class="vs-pic-box">' + p.svg + '</span>'
      : '<a class="vs-pic-box" href="' + esc(p.url) + '" target="_blank" rel="noopener" aria-label="Open the picture for scene ' + (i + 1) + '">' +
        '<img src="' + esc(p.url) + '" alt="" loading="lazy" decoding="async"></a>';
    var act = !work ? '' : sc.photo_url
      ? '<button class="btn btn-sm" type="button" data-pic="remove">Remove</button>'
      : '<label class="btn btn-sm vs-pic-add">' + ICON.camera + 'Add photo<input type="file" accept="image/jpeg,image/png,image/webp" capture="environment" data-pic="add" hidden></label>';
    return '<span class="vs-pic">' + box + (p ? '<span class="vs-pic-tag">' + esc(p.tag) + '</span>' : '') + act + '</span>';
  }
  /* Draw with AI on the Scenes heading: drawn only where the picture
     writer answers that it is set up, with what is left today. */
  function drawAct() {
    if (!may('work') || !st.drawReady) return '';
    return '<span class="vs-draw"><span class="vs-draw-left" id="vsDrawLeft">' + (st.drawLeft == null ? '' : esc(String(st.drawLeft)) + ' left today') + '</span>' +
      '<button class="btn btn-sm btn-icon" type="button" id="vsDraw">' + AI_GLYPH + 'Draw with AI</button></span>';
  }
  /* What is seen: the timing and camera over it, the on-screen text and the
     sound under it, each only where set. */
  function shotCell(sc) {
    var cam = camOf(sc);
    return (cam ? '<span class="vs-cam">' + esc(cam) + '</span>' : '') + esc(sc.visual || '') +
      (sc.on_screen ? '<span class="vs-extra"><b>On-screen text</b> ' + esc(sc.on_screen) + '</span>' : '') +
      (sc.sound ? '<span class="vs-extra"><b>Sound</b> ' + esc(sc.sound) + '</span>' : '');
  }
  var NOT_SHOT = '<span class="mute vs-dash">—</span><span class="mute vs-notshot">Not shot</span>';
  function sceneRows(s) {
    var work = may('work');
    var kind = s.kind;
    var head = '<div class="crm-head vs-scene">' +
      '<span>#</span><span>Picture</span><span>' + esc(SCENE_WORD[kind]) + '</span>' + (kind === 'scenes' ? '<span>Script</span>' : '') +
      '<span>VC#</span><span>Shot</span></div>';
    var cls = 'crm-table vs-scenes has-pics' + (kind === 'scenes' ? ' is-two' : '');
    if (!st.scenes.length) return '<div class="' + cls + '">' + head + '<p class="vs-empty">No scenes.</p></div>';
    return '<div class="' + cls + '">' + head + st.scenes.map(function (sc, i) {
      return '<div class="vs-scene" data-scene="' + esc(sc.id) + '">' +
        '<span class="vs-n">' + (i + 1) + '</span>' + picCell(sc, i, s, work) +
        '<span class="vs-text vs-vis">' + shotCell(sc) + '</span>' +
        (kind === 'scenes' ? '<span class="vs-text vs-line">' + esc(sc.line || '') + '</span>' : '') +
        '<span class="vs-vc"><span class="vs-lbl" aria-hidden="true">VC#</span>' +
          (work ? clipField(sc.vc, 'Clip number for scene ' + (i + 1)) : (sc.vc ? esc(sc.vc) : '<span class="mute">—</span>')) + '</span>' +
        /* At View the tick is a word, never a control that cannot be pressed
           (VS-4); on a narrow pane its word stands beside it (VS-5). */
        '<span class="vs-shot">' + (work
          ? '<label><input type="checkbox" ' + (sc.shot_at ? 'checked ' : '') + 'aria-label="Scene ' + (i + 1) + ' shot" data-shot>' +
            '<span class="vs-lbl" aria-hidden="true">Shot</span></label>'
          : (sc.shot_at ? '<span class="vs-shotword">Shot</span>' : NOT_SHOT)) + '</span>' +
      '</div>';
    }).join('') + '</div>';
  }
  function scriptBody(s) {
    var out = planHtml(s);
    if (CONTEXT_WORD[s.kind]) {
      out += '<section class="vs-block"><h4 class="fsec-h">' + esc(CONTEXT_WORD[s.kind]) + '</h4>' +
        '<p class="vs-prose">' + (s.context ? esc(s.context) : '<span class="mute">Not written</span>') + '</p></section>';
    }
    out += '<section class="vs-block"><div class="vs-scenehead"><h4 class="fsec-h">Scenes</h4>' + drawAct() + '</div>' +
      '<p class="msg vs-pic-msg" id="vsPicMsg" role="status"></p>' + sceneRows(s) +
      '<p class="msg vs-shot-msg" id="vsShotMsg" role="status"></p></section>';
    /* A voice-over not yet written is no row to shoot: its clip number and
       Shot wait for its words (2026-10-27, VS-11). */
    if (s.kind === 'story' && !String(s.vo || '').trim() && !s.vo_vc && !s.vo_shot_at) {
      out += '<section class="vs-block"><h4 class="fsec-h">Script (read here)</h4><p class="vs-prose"><span class="mute">Not written</span></p></section>';
    } else if (s.kind === 'story') {
      var work = may('work');
      out += '<section class="vs-block"><h4 class="fsec-h">Script (read here)</h4>' +
        /* The words read here are one more row in the scenes' own tracks: the
           words, then its clip number and Shot (VS-8). */
        '<div class="crm-table vs-scenes vs-vorow"><div class="crm-head vs-scene"><span></span><span>Words</span><span>VC#</span><span>Shot</span></div>' +
        '<div class="vs-scene" data-vo>' +
          '<span class="vs-n" aria-hidden="true"></span>' +
          '<span class="vs-text vs-vis">' + (s.vo ? esc(s.vo) : '<span class="mute">Not written</span>') + '</span>' +
          '<span class="vs-vc"><span class="vs-lbl" aria-hidden="true">VC#</span>' +
            (work ? clipField(s.vo_vc, 'Clip number for the voice-over', 'vsVoVc') : (s.vo_vc ? esc(s.vo_vc) : '<span class="mute">—</span>')) + '</span>' +
          '<span class="vs-shot">' + (work
            ? '<label><input type="checkbox" id="vsVoShot" ' + (s.vo_shot_at ? 'checked ' : '') + 'aria-label="Voice-over shot">' +
              '<span class="vs-lbl" aria-hidden="true">Shot</span></label>'
            : (s.vo_shot_at ? '<span class="vs-shotword">Shot</span>' : NOT_SHOT)) + '</span>' +
        '</div></div></section>';
    }
    if (s.review) out += '<section class="vs-block vs-review">' + reviewHtml(s.review, s.review_version !== s.version) + '</section>';
    out += '<section class="vs-block"><h4 class="fsec-h">Notes</h4><p class="vs-prose">' +
      (s.remarks ? esc(s.remarks) : '<span class="mute">None</span>') + '</p></section>';
    return out;
  }

  /* The month's ⋯: Download, and Reset link at Work (Preview PDF
     sits in the head, as a report's). A script's ⋯: Delete at Full Access. */
  function menuOf(id, items) {
    if (!items) return '';
    return '<button class="kmenu-btn" id="' + id + '" type="button" aria-label="More actions" aria-expanded="false">' + ICON.dots + '</button>' +
      '<div class="kmenu" data-menu hidden>' + items + '</div>';
  }

  /* THE RECORD IS THE CLIENT'S CONTENT MONTH (the user, 2026-10-09: "show
     similar link in one card for different videos?", "why is the tab
     selection of each video below?"): the head names the client and the
     month and holds the client's link once; a tab a script runs under it;
     the script on show carries its own head, with its state, Edit and
     Publish. */
  function paintRecord() {
    var s = st.open;
    var c = s.clients || {};
    /* The client's logo, else its initials, as every client's record. */
    var mark = $('vsRecMark'), initials = window.ADspaceState ? window.ADspaceState.initials(c.name) : '';
    if (c.logo_url) {
      mark.className = 'rec-mark has-logo';
      mark.innerHTML = '<img src="' + esc(c.logo_url) + '" alt="">';
      mark.querySelector('img').addEventListener('error', function () { mark.className = 'rec-mark'; mark.textContent = initials; });
    } else { mark.className = 'rec-mark'; mark.textContent = initials; }
    $('vsRecName').textContent = c.name || 'Client';
    /* The content month, opening the client's Months in My Work where the
       month is there and the colleague reads My Work. */
    var month = monthWord(s.period);
    var toMonth = s.engagement_id && c.slug && bridge.may && bridge.may('ops', 'view');
    var n = st.series.length, pub = st.series.filter(function (x) { return x.status === 'shared'; }).length;
    $('vsRecMeta').innerHTML = (month ? (toMonth ? '<button class="linkbtn" type="button" data-a="month">' + esc(month) + '</button>' : esc(month)) + ' · ' : '') +
      esc(n + (n === 1 ? ' script' : ' scripts') + (pub ? ' · ' + pub + ' published' : ''));
    var mb2 = $('vsRecMeta').querySelector('[data-a="month"]');
    if (mb2) mb2.addEventListener('click', function () {
      history.pushState(null, '', '?s=work&view=months&wc=' + encodeURIComponent(c.slug));
      if (bridge.restore) bridge.restore();
    });
    $('vsRecCtl').innerHTML =
      '<button class="btn btn-sm btn-icon" type="button" data-a="pdf" aria-label="Preview PDF"><span class="vs-pdf-long">Preview PDF</span><span class="vs-pdf-short">PDF</span> ' + ICON.out + '</button>' +
      menuOf('vsRecMore', '<button class="kmenu-item" data-g="1" data-a="download" type="button" role="menuitem">Download</button>' +
        (may('work') ? '<button class="kmenu-item" data-g="5" data-a="reset" type="button" role="menuitem">Reset link</button>' : ''));
    wireHead();
    paintLink();
    var inMonth = st.mode === 'month';
    /* The client's link belongs to the month; on a narrow pane a script's
       page leaves it out, so the scenes come first (VS-3). */
    $('vsRecord').classList.toggle('vs-onscript', !inMonth);
    $('vsMonthList').hidden = !inMonth;
    $('vsNav').hidden = inMonth || st.series.length < 2;
    $('vsRecBody').hidden = inMonth;
    if (inMonth) paintMonth(); else { paintNav(); paintScript(); }
  }

  /* A script's number within the month (VS01). */
  function tabWord(x) { var c = codeOf(x); return /VS\d+$/.test(c) ? c.replace(/^\d{4}/, '') : c; }
  /* The month's scripts as rows: the code and title over the type, the
     shoot, the state, each opening its script. The code is written whole,
     as the script's own head writes it (2026-10-22, VS-4). */
  function paintMonth() {
    $('vsNextVideo').hidden = !may('work');
    var rows = st.series.map(function (x) {
      return '<button class="crm-row vs-row vs-mrow" type="button" data-v="' + esc(x.id) + '">' +
        '<span class="vs-c-name"><b>' + esc(codeOf(x) + (x.title ? ' · ' + x.title : '')) + '</b><small>' + esc(KIND_WORD[x.kind] || '') + '</small></span>' +
        '<span class="vs-c-shoot">' + (x.shoot_on ? esc(dayWord(x.shoot_on)) : '<span class="mute">Not set</span>') + '</span>' +
        '<span class="vs-c-state">' + chip(stateOf(x)) + '</span>' + GO + '</button>';
    }).join('');
    $('vsMonthRows').innerHTML = '<div class="crm-table vs-mtable"><div class="crm-head vs-row"><span>Script</span><span>Shoot</span><span>State</span><span></span></div>' + rows + '</div>';
    Array.prototype.forEach.call($('vsMonthRows').querySelectorAll('[data-v]'), function (r) {
      r.addEventListener('click', function () { openScript(r.getAttribute('data-v'), true); });
    });
  }
  /* Where the script stands in its month, and its neighbours. */
  function paintNav() {
    var i = st.series.map(function (x) { return x.id; }).indexOf(st.open.id);
    $('vsPos').textContent = (i + 1) + ' of ' + st.series.length;
    $('vsPrev').disabled = i <= 0;
    $('vsNextS').disabled = i < 0 || i >= st.series.length - 1;
    $('vsNav').classList.toggle('is-one', st.series.length < 2);
  }
  function step(d) {
    var i = st.series.map(function (x) { return x.id; }).indexOf(st.open.id);
    var to = st.series[i + d];
    if (to) openScript(to.id, true);
  }
  $('vsPrev').addEventListener('click', function () { step(-1); });
  $('vsNextS').addEventListener('click', function () { step(1); });
  $('vsNextVideo').addEventListener('click', function () { nextVideo($('vsNextVideo')); });

  /* The script on show: its head (code and title over its type; the state,
     Edit, Publish or Unpublish and the ⋯ at the right edge), its facts, then
     the script. */
  function paintScript() {
    var s = st.open;
    var key = stateOf(s);
    var acts = '';
    /* A script with no scenes and no words is not offered to the client
       (VS-1): Publish waits until there is something to read. */
    var empty = !st.scenes.length && !String(s.context || '').trim() && !String(s.vo || '').trim();
    if (may('work')) {
      acts += '<button class="btn btn-sm" type="button" data-a="edit">Edit</button>';
      acts += s.status === 'shared'
        ? '<button class="btn btn-sm btn-warn" type="button" data-a="unpublish">Unpublish</button>'
        : empty ? '' : '<button class="btn btn-sm btn-go" type="button" data-a="publish">Publish</button>';
    }
    /* The state sits on the title row at its right edge; the acts follow,
       taking the line under it on a narrow pane (VS-6). */
    $('vsRecBody').innerHTML = '<section class="panel vs-factcard">' +
        '<div class="vs-cardhead"><div class="vs-cardwho"><h3 id="vsScriptName">' + esc(label(s)) + '</h3>' +
          '<p>' + esc(KIND_WORD[s.kind] || '') + '</p></div>' +
          '<span class="vs-cardstate">' + chip(key) + '</span>' +
          '<div class="vs-cardctl">' + acts +
            menuOf('vsCardMore', may('manage') ? '<button class="kmenu-item is-danger" data-g="6" data-a="del" type="button" role="menuitem">Delete</button>' : '') +
          '</div></div>' +
        '<div class="msg" id="vsCardMsg" role="status"></div>' +
        facts(s) + '</section>' +
      '<section class="panel vs-sheetview">' + scriptBody(s) + '</section>';
    wireRecord();
  }

  function onAct(root, a, fn) { var b = root && root.querySelector('[data-a="' + a + '"]'); if (b) b.addEventListener('click', function () { fn(b); }); }
  /* A ⋯ and its items: opened on its button, placed on the viewport. */
  function wireMenu(id) {
    var mb = $(id);
    if (!mb) return;
    var menu = mb.parentNode.querySelector('[data-menu]');
    mb.addEventListener('click', function (e) {
      e.stopPropagation();
      var open = menu.hidden;
      shutMenu();
      menu.hidden = !open;
      mb.setAttribute('aria-expanded', String(open));
      if (open) window.ADspaceMenu.place(mb, menu);
    });
    onAct(menu, 'download', function () { shutMenu(); drawPdf(mb, true); });
    onAct(menu, 'reset', function () { shutMenu(); resetLink(); });
    onAct(menu, 'del', function () { shutMenu(); remove(); });
  }
  /* The record's head (Preview PDF and its ⋯) is wired as it is drawn, on
     the month as on a script (the user, 2026-10-10: the month's ⋯ opened
     nothing). */
  function wireHead() {
    onAct($('vsRecCtl'), 'pdf', function (b) { drawPdf(b, false); });
    wireMenu('vsRecMore');
  }
  /* ---- Scene pictures --------------------------------------------------- */
  function sayPic(text, tone) { say($('vsPicMsg'), text, tone); }
  var PIC_SAID = {
    'bad-url': 'The picture could not be saved. Try again.',
    'bad-press': 'The picture could not be saved. Draw with AI again.',
    'ai-not-set-up': 'Draw with AI is not set up yet. Please contact an admin.',
    'ai-key': 'Draw with AI is not available at the moment. Please contact an admin.',
    'ai-model': 'Draw with AI is not available at the moment. Please contact an admin.',
    'ai-billing': 'Draw with AI is not available at the moment. Please contact an admin.',
    'ai-busy': 'The AI service is busy. Try again in a minute.',
    'ai-failed': 'No pictures were drawn. Try again.',
    'ai-incomplete': 'No pictures were drawn. Try again.'
  };
  function picSaid(e) {
    var m = String((e && e.message) || '');
    if (m === 'ai-limit') {
      var d = (e && (e.data || e.d)) || {};
      if (d.scope === 'stopped') return 'Draw with AI is turned off for you. Please ask an admin to turn it on.';
      if (d.left) return d.left + (d.left === 1 ? ' scene picture' : ' scene pictures') + ' left today. Choose fewer scenes.';
      return 'You have used all ' + (d.limit || 0) + ' scene pictures for today.' + (d.next ? ' Resets at ' + writeClock(d.next) + '.' : '');
    }
    return PIC_SAID[m] || said(e);
  }
  /* A picture as a JPEG no wider than `max` (1280) on its longer side; with
     `data` its data URL (the thumbnail the crew PDF draws). */
  function jpegOf(src, max, data) {
    max = max || 1280;
    return new Promise(function (resolve, reject) {
      var url = typeof src === 'string' ? src : URL.createObjectURL(src);
      var img = new Image();
      img.onload = function () {
        var k = Math.min(1, max / Math.max(img.naturalWidth, img.naturalHeight));
        var c = document.createElement('canvas');
        c.width = Math.max(1, Math.round(img.naturalWidth * k)); c.height = Math.max(1, Math.round(img.naturalHeight * k));
        var g = c.getContext('2d');
        g.fillStyle = '#fff'; g.fillRect(0, 0, c.width, c.height);
        g.drawImage(img, 0, 0, c.width, c.height);
        if (typeof src !== 'string') URL.revokeObjectURL(url);
        if (data) { resolve(c.toDataURL('image/jpeg', 0.75)); return; }
        c.toBlob(function (b) { if (b) resolve(b); else reject(new Error('The picture could not be read.')); }, 'image/jpeg', 0.85);
      };
      img.onerror = function () { if (typeof src !== 'string') URL.revokeObjectURL(url); reject(new Error('The picture could not be read.')); };
      img.src = url;
    });
  }
  /* Stored in the client's own folder through sign-upload (purpose script). */
  function storePic(blob) {
    var s = st.open;
    var cfg = window.ADSPACE_CONFIG || {};
    return db.functions.invoke((cfg.s3 && cfg.s3.functionName) || 'sign-upload', {
      body: { ext: 'jpg', clientId: s.client_id, size: blob.size, purpose: 'script', scriptId: s.id }
    }).then(function (r) {
      if (!r.error && r.data && r.data.uploadUrl) return r;
      return API.fnRefusal(r).then(function (code) { throw new Error(code === 'not_allowed' ? SAID.denied : 'The picture could not be saved. Try again.'); });
    }).then(function (r) {
      return fetch(r.data.uploadUrl, { method: 'PUT', headers: { 'Content-Type': r.data.contentType || 'image/jpeg' }, body: blob })
        .then(function (res) { if (!res.ok) throw new Error('The picture could not be saved. Try again.'); return r.data.publicUrl; });
    });
  }
  function scenePos(id) { var sc = st.scenes.filter(function (x) { return x.id === id; })[0]; return sc ? st.scenes.indexOf(sc) + 1 : ''; }
  function setPic(id, kind, url, press, thumb) {
    return rpc('video_script_picture', { p_script: st.open.id, p_scene: id, p_kind: kind, p_url: url, p_press: press || null,
                                         p_thumb: thumb || null }).then(function () {
      var sc = st.scenes.filter(function (x) { return x.id === id; })[0];
      if (sc && kind === 'ai') { sc.ai_url = url; sc.ai_at = new Date().toISOString(); }
      if (sc && kind === 'photo') { sc.photo_url = url; if (!url) sc.photo_by = null; }
    });
  }
  function repaintScenes(msg, tone) {
    var y = window.pageYOffset;
    paintScript();
    window.scrollTo(0, y);
    if (msg) sayPic(msg, tone);
  }
  function wirePics(body) {
    Array.prototype.forEach.call(body.querySelectorAll('[data-scene] input[data-pic="add"]'), function (inp) {
      var id = inp.closest('[data-scene]').getAttribute('data-scene');
      inp.addEventListener('change', function () {
        var f = inp.files && inp.files[0];
        if (!f) return;
        var lab = inp.closest('label');
        if (lab) lab.classList.add('is-busy');
        sayPic('Adding the photo…', 'ok');
        Promise.all([jpegOf(f).then(storePic), jpegOf(f, 360, true)]).then(function (two) { return setPic(id, 'photo', two[0], null, two[1]); })
          .then(function () { return readScript(st.open.id); })
          .then(function () { repaintScenes('Photo added to scene ' + scenePos(id) + '.', 'ok'); })
          .catch(function (e) { if (lab) lab.classList.remove('is-busy'); sayPic(picSaid(e)); });
      });
    });
    Array.prototype.forEach.call(body.querySelectorAll('[data-scene] [data-pic="remove"]'), function (b) {
      var id = b.closest('[data-scene]').getAttribute('data-scene');
      b.addEventListener('click', function () {
        var sc = st.scenes.filter(function (x) { return x.id === id; })[0] || {};
        var was = sc.photo_url, wasThumb = sc.photo_thumb;
        b.disabled = true;
        setPic(id, 'photo', null).then(function () {
          repaintScenes();
          undoBar('Photo removed from scene ' + scenePos(id) + '.', function () {
            setPic(id, 'photo', was, null, wasThumb).then(function () { return readScript(st.open.id); }).then(function () { repaintScenes(); })
              .catch(function (e) { sayPic(picSaid(e)); });
          }, $('vsPicMsg'));
        }).catch(function (e) { b.disabled = false; sayPic(picSaid(e)); });
      });
    });
    if ($('vsDraw')) $('vsDraw').addEventListener('click', function () { drawWithAi($('vsDraw')); });
  }
  /* Is the picture writer set up? Asked once a visit, counting nothing. */
  function pingDraw() {
    if (!may('work') || st.drawAsked) return Promise.resolve();
    st.drawAsked = true;
    return db.functions.invoke('script-pictures', { body: { ping: true } }).then(function (r) {
      st.drawReady = Boolean(r && r.data && r.data.ready);
      if (!st.drawReady) return null;
      return rpc('ai_picture_left', {}).then(function (d) { st.drawLeft = d.left; }).catch(function () {});
    }).catch(function () { st.drawReady = false; });
  }
  function base64Blob(b64, mime) {
    var bin = atob(b64), n = bin.length, u = new Uint8Array(n);
    for (var i = 0; i < n; i++) u[i] = bin.charCodeAt(i);
    return new Blob([u], { type: mime || 'image/png' });
  }
  function drawWithAi(btn) {
    var s = st.open;
    var missing = st.scenes.filter(function (x) { return !x.photo_url && !x.ai_url; });
    sayPic('');
    btn.disabled = true;
    rpc('ai_picture_left', {}).then(function (left) {
      btn.disabled = false;
      st.drawLeft = left.left;
      if (!left.left) { sayPic(picSaid({ message: 'ai-limit', data: left })); return; }
      var choices = [];
      if (missing.length) choices.push(['missing', 'Scenes with no picture (' + missing.length + ')']);
      choices.push(['all', 'All scenes (' + st.scenes.length + ')']);
      window.ADspaceConfirm.ask({
        title: 'Draw with AI',
        body: 'Draws a storyboard picture for each scene from its shot. Each scene counts as one picture; ' + left.left + (left.left === 1 ? ' picture' : ' pictures') + ' left today.',
        go: 'Draw', field: { label: 'Scenes', choices: choices, seg: true, value: choices[0][0] }
      }, function (v) {
        var list = (v === 'all' ? st.scenes : missing).slice(0, 30);
        if (list.length > left.left) { sayPic(picSaid({ message: 'ai-limit', data: left })); return; }
        var sid = s.id;
        btn.disabled = true;
        btn.innerHTML = AI_GLYPH + 'Drawing';
        sayPic('Drawing ' + list.length + (list.length === 1 ? ' picture' : ' pictures') + '. This can take a minute.', 'ok');
        db.functions.invoke('script-pictures', { body: { script_id: sid, scenes: list.map(function (x) { return x.id; }) } }).then(function (res) {
          var d = res && res.data;
          if (res.error || !d || d.error || !d.pictures) { var x = new Error((d && d.error) || 'ai-failed'); x.d = d; x.data = d; throw x; }
          /* Each picture stored and kept on its scene in turn. */
          return d.pictures.reduce(function (p, pic) {
            return p.then(function (n) {
              var src = 'data:' + (pic.mime || 'image/png') + ';base64,' + pic.data;
              return Promise.all([jpegOf(src).then(storePic), jpegOf(src, 360, true)])
                .then(function (two) { return setPic(pic.scene, 'ai', two[0], pic.press, two[1]); })
                .then(function () { return n + 1; }, function () { return n; });
            });
          }, Promise.resolve(0)).then(function (n) { return { n: n, missed: (d.missed || 0) + d.pictures.length - n }; });
        }).then(function (r) {
          if (!st.open || st.open.id !== sid) return;
          return rpc('ai_picture_left', {}).then(function (l) { st.drawLeft = l.left; }, function () {})
            .then(function () { return readScript(sid); })
            .then(function () {
              repaintScenes(r.n + (r.n === 1 ? ' picture drawn.' : ' pictures drawn.') +
                (r.missed ? ' No picture was drawn for ' + r.missed + (r.missed === 1 ? ' scene' : ' scenes') + '. Try again.' : ''), r.missed ? 'warn' : 'ok');
            });
        }).catch(function (e) {
          if (!st.open || st.open.id !== sid) return;
          btn.disabled = false;
          btn.innerHTML = AI_GLYPH + 'Draw with AI';
          sayPic(picSaid(e));
        });
      });
    }).catch(function (e) { btn.disabled = false; sayPic(picSaid(e)); });
  }

  function wireRecord() {
    var on = onAct;
    var body = $('vsRecBody');
    on(body, 'edit', function (b) { openEdit(b); });
    on(body, 'publish', function (b) { publish(true, b); });
    on(body, 'unpublish', function (b) { publish(false, b); });
    wireMenu('vsCardMore');
    var fields = Array.prototype.slice.call(body.querySelectorAll('input[data-vc]'));
    fields.forEach(function (input, k) {
      var row = input.closest('[data-scene]');
      var id = row ? row.getAttribute('data-scene') : null;
      var box = row ? row.querySelector('[data-shot]') : $('vsVoShot');
      var commit = function (enter) {
        var v = input.value.trim();
        if (!v && enter && input.getAttribute('data-next')) { v = input.getAttribute('data-next'); input.value = v; }
        if (v !== (input.getAttribute('data-saved') || '')) {
          /* A clip number recorded is a scene shot. */
          var on = v && box && !box.checked ? true : null;
          if (on) box.checked = true;
          input.setAttribute('data-saved', v);
          tick(id, on, v, input, box);
          suggest();
        }
        if (enter) {
          var to = fields[k + 1];
          if (to) { to.focus(); if (to.select) to.select(); } else input.blur();
        }
      };
      input.addEventListener('keydown', function (e) {
        if (e.key !== 'Enter' || e.isComposing) return;
        e.preventDefault();
        commit(true);
      });
      input.addEventListener('change', function () { commit(false); });
    });
    Array.prototype.forEach.call(body.querySelectorAll('[data-scene] [data-shot]'), function (shot) {
      var id = shot.closest('[data-scene]').getAttribute('data-scene');
      shot.addEventListener('change', function () { tick(id, shot.checked, null, null, shot); });
    });
    if ($('vsVoShot')) $('vsVoShot').addEventListener('change', function () { tick(null, $('vsVoShot').checked, null, null, $('vsVoShot')); });
    wirePics(body);
    suggest();
  }
  function shutMenu() {
    Array.prototype.forEach.call(document.querySelectorAll('#vsRecord [data-menu]'), function (m) { m.hidden = true; });
    ['vsRecMore', 'vsCardMore'].forEach(function (id) { if ($(id)) $(id).setAttribute('aria-expanded', 'false'); });
  }
  document.addEventListener('click', function (e) {
    if (!e.target.closest || !e.target.closest('#vsRecord .kmenu, #vsRecMore, #vsCardMore')) shutMenu();
  });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') shutMenu(); });
  if (window.ADspaceMenu) window.ADspaceMenu.onScroll(shutMenu);

  /* On the day: a tick or a clip number, saved as it changes, put back on a
     refusal. */
  /* One save for a clip number, a tick or both; a refusal puts back what
     changed. */
  function tick(sceneId, on, vc, input, box) {
    var m = $('vsShotMsg');
    say(m, '');
    rpc('video_script_shot', { p_script: st.open.id, p_scene: sceneId, p_on: on, p_vc: vc }).then(function () {
      var sc = sceneId && st.scenes.filter(function (x) { return x.id === sceneId; })[0];
      var stamp = new Date().toISOString();
      if (sc) { if (on != null) sc.shot_at = on ? stamp : null; if (vc != null) sc.vc = vc.trim() || null; }
      if (!sceneId) { if (on != null) st.open.vo_shot_at = on ? stamp : null; if (vc != null) st.open.vo_vc = vc.trim() || null; }
      say($('vsCardMsg'), '');
      say(m, 'Saved.', 'ok');
    }).catch(function (e) {
      var sc2 = sceneId && st.scenes.filter(function (x) { return x.id === sceneId; })[0];
      if (box && on != null) box.checked = sceneId ? Boolean(sc2 && sc2.shot_at) : Boolean(st.open.vo_shot_at);
      if (input && vc != null) {
        input.value = sceneId ? (sc2 && sc2.vc) || '' : st.open.vo_vc || '';
        input.setAttribute('data-saved', input.value);
        suggest();
      }
      say(m, said(e));
    });
  }

  /* The way back, drawn where the act happened: one line under `host`. */
  function undoBar(text, undo, host) { window.ADspaceAdmin.undoHere(text, undo, host); }

  function clientLink(key) { return location.origin + '/script/?k=' + key; }
  /* The address and Copy link give the short link (hi.adspace.me/s/{key},
     2026-10-13), so a chat app's preview names the brand; Preview is the
     page itself. */
  function shareLink(key) { return bridge.shortLink ? bridge.shortLink('script', key, clientLink(key)) : clientLink(key); }
  function withKey(reset) {
    var cid = st.open.client_id;
    return rpc('script_link', { p_client: cid, p_reset: Boolean(reset) }).then(function (d) {
      st.key = d.key;
      st.keyFor = cid;
      return d.key;
    });
  }
  /* The client's link, one for all its videos: read once a client (made the
     first time by a colleague at Work), drawn as a campaign's. At View with
     none made, the address is left out. */
  function paintLink() {
    var s = st.open;
    var show = function () {
      if (!st.open || st.open.id !== s.id) return;
      var has = Boolean(st.key && st.keyFor === s.client_id);
      if (has) { $('vsLink').value = shareLink(st.key); $('vsOpen').href = clientLink(st.key); }
      $('vsLinkTools').hidden = !has;
    };
    show();
    if (st.keyFor === s.client_id || st.keyTried === s.client_id) return;
    st.keyTried = s.client_id;
    withKey(false).then(show).catch(show);
  }
  $('vsCopy').addEventListener('click', function () {
    if (st.key) window.ADspaceCopy.to($('vsCopy'), shareLink(st.key));
  });
  function publish(on, btn, quiet) {
    var m = $('vsCardMsg');
    var go = function () {
      if (btn) btn.disabled = true;
      rpc('video_script_share', { p_ids: [st.open.id], p_on: on }).then(function () {
        return readScript(st.open.id);
      }).then(function () {
        paintRecord();
        say($('vsCardMsg'), on ? '' : 'Unpublished.', 'ok');
        if (on) undoBar('Published to the client.', function () { publish(false, null, true); }, $('vsCardMsg'));
      }).catch(function (e) { if (btn) btn.disabled = false; say(m, said(e)); });
    };
    if (on || quiet) { go(); return; }
    window.ADspaceConfirm.ask({ title: 'Unpublish?', body: 'The client no longer sees this script on their link. Its clip numbers are kept.',
      go: 'Unpublish', tone: 'warn' }, go);
  }
  function resetLink() {
    window.ADspaceConfirm.ask({ title: 'Reset the script link',
      body: 'The current link for ' + (((st.open || {}).clients || {}).name || 'this client') + ' stops working immediately. The new one has to be sent to the client.',
      go: 'Reset link', tone: 'warn' }, function () {
      withKey(true).then(function () { paintLink(); say($('vsRecMsg'), 'Link reset.', 'ok'); })
        .catch(function (e) { say($('vsRecMsg'), said(e)); });
    });
  }
  function remove() {
    var s = st.open;
    var nm = typedName(s);
    window.ADspaceConfirm.ask({
      title: 'Delete',
      body: label(s) + ', its scenes and their clip numbers will be deleted. This cannot be undone.',
      go: 'Delete', tone: 'danger',
      field: { label: 'Type ' + (s.title ? 'the title' : nm) + ' to confirm', match: nm, mismatch: 'The name does not match.' }
    }, function (typed) {
      rpc('video_script_delete', { p_id: s.id, p_typed: typed }).then(function () {
        /* The month's next script opens in its place; the last one gone,
           the list. */
        var rest = st.series.filter(function (x) { return x.id !== s.id; });
        if (rest.length) {
          openMonth(rest[0].id, false).then(function () { say($('vsRecMsg'), label(s) + ' deleted.', 'ok'); });
          return;
        }
        backToList();
        say($('vsListMsg'), 'Deleted.', 'ok');
      }).catch(function (e) { say($('vsCardMsg'), said(e) === SAID.denied ? SAID['denied-delete'] : said(e)); });
    });
  }
  /* Add script (VS-1, 2026-10-14): the editor opens on the month's next
     script with the header copied, but nothing is stored until Save, which
     makes it (`video_script_new`, the arguments this press would have sent)
     and then saves its fields. Cancel on it stores nothing, so no empty
     numbered script is left for the month or the client's link. */
  function nextVideo(btn, push) {
    var b = st.open;
    if (!b || !may('work')) return;
    say($('vsRecMsg'), '');
    st.pending = {
      args: { p_client: b.client_id, p_period: b.period, p_kind: b.kind, p_from: b.id, p_idem: uuid() },
      s: { id: null, client_id: b.client_id, period: b.period, kind: b.kind, title: '', reference_url: null,
           platform: b.platform, language: b.language, shoot_on: b.shoot_on, shoot_time: b.shoot_time, venue: b.venue,
           duration_minutes: b.duration_minutes, cast_names: b.cast_names, context: '', vo: '', remarks: '',
           clients: b.clients, version: null }
    };
    openEdit(btn, push);
  }
  /* The script on the editor: the one open, else the one Add script will make. */
  function edited() { return st.pending ? st.pending.s : st.open; }
  /* A new script is made once, the same press's key making a retry the same
     act; a script already made answers its id. */
  function made() {
    var P = st.pending;
    if (!P) return Promise.resolve(st.open.id);
    if (P.s.id) return Promise.resolve(P.s.id);
    return rpc('video_script_new', P.args).then(function (d) {
      P.s.id = d.id;
      if (st.pending === P) st.editing = d.id;
      return d.id;
    });
  }

  /* ---- Edit: the whole script in one sheet ---------------------------------- */
  function fillSelect(sel, values, cur, words) {
    var opts = values.slice();
    if (cur && opts.indexOf(cur) < 0) opts.push(cur);
    sel.innerHTML = '<option value="">Not set</option>' + opts.map(function (v) {
      return '<option value="' + esc(v) + '"' + (String(v) === String(cur) ? ' selected' : '') + '>' + esc(words ? words(v) : v) + '</option>';
    }).join('');
  }
  function kindPaint() {
    var k = $('vsKind').value;
    $('vsContextRow').hidden = !CONTEXT_WORD[k];
    $('vsContextLabel').textContent = CONTEXT_WORD[k] || '';
    $('vsVoRow').hidden = k !== 'story';
    paintDraftScenes();
  }
  $('vsKind').addEventListener('change', kindPaint);

  /* ---- Edit: the whole script on a page of its own ------------------------- */
  /* What the editor holds, to know whether anything changed. */
  function snapshot() {
    return JSON.stringify([$('vsKind').value, $('vsMonth').value, $('vsTitle').value, $('vsRef').value,
      $('vsPlatform').value, $('vsLang').value, $('vsDate').value, $('vsTime').value, $('vsVenue').value,
      $('vsDur').value, $('vsCast').value, $('vsContext').value, $('vsVo').value, $('vsNotes').value,
      $('vsAspect').value, $('vsLength').value, briefIn(), planIn(), st.rev && st.rev.set ? st.rev.value : 'kept',
      st.draft.map(function (x) { return SCENE_KEYS.map(function (k) { return x[k]; }); })]);
  }
  /* A scene as the editor holds it: every field a string. */
  var SCENE_KEYS = ['visual', 'line', 't_from', 't_to', 'shot_size', 'angle', 'camera_move', 'on_screen', 'sound'];
  function sceneIn(x) {
    var o = { id: (x && x.id) || null };
    SCENE_KEYS.forEach(function (k) { o[k] = x && x[k] != null ? String(x[k]) : ''; });
    return o;
  }
  var BRIEF_FIELDS = [['offer', 'vsOffer'], ['audience', 'vsAudience'], ['key_message', 'vsKey'], ['cta', 'vsCta'],
                      ['must_include', 'vsInclude'], ['must_avoid', 'vsAvoid'], ['tone', 'vsTone'], ['objective', 'vsObjective'],
                      ['format', 'vsFormat'], ['max_locations', 'vsMaxLoc'], ['max_cast', 'vsMaxCast'], ['max_shoot_hours', 'vsMaxHours']];
  var PLAN_FIELDS = [['core_message', 'vsCore'], ['hook', 'vsHook'], ['concept', 'vsConcept'], ['cta', 'vsPlanCta'],
                     ['cast', 'vsRoles'], ['locations', 'vsLocs'], ['props', 'vsProps'], ['music', 'vsMusic']];
  function briefIn() {
    var o = {};
    BRIEF_FIELDS.forEach(function (f) {
      var v = $(f[1]).value.trim();
      if (!v) return;
      o[f[0]] = /^max_/.test(f[0]) ? Number(v) : v;
    });
    return o;
  }
  function planIn() {
    var o = {};
    PLAN_FIELDS.forEach(function (f) { var v = $(f[1]).value.trim(); if (v) o[f[0]] = v; });
    return o;
  }
  function putPlan(p) {
    PLAN_FIELDS.forEach(function (f) { $(f[1]).value = (p && p[f[0]]) || ''; });
    if (window.ADspaceGrow && window.ADspaceGrow.fit) PLAN_FIELDS.forEach(function (f) { window.ADspaceGrow.fit($(f[1])); });
  }
  /* The review of a draft just written, shown under Write with AI until it
     is saved with the script or undone. */
  function paintEditReview() {
    var box = $('vsEditReview');
    var rv = st.rev && st.rev.set ? st.rev.value : null;
    box.hidden = !rv;
    box.innerHTML = rv ? reviewHtml(rv, false) : '';
  }
  function dirty() { return Boolean(st.editing) && snapshot() !== st.base; }
  function showEditor() {
    $('vsListView').hidden = true;
    $('vsRecord').hidden = true;
    $('vsEditView').hidden = false;
  }
  function closeEditor() {
    st.editing = null;
    st.pending = null;
    st.base = '';
    $('vsEditView').hidden = true;
    /* New script's editor returns to the list it was opened from. */
    if (st.open) $('vsRecord').hidden = false; else $('vsListView').hidden = false;
    if (bridge.setUrl) bridge.setUrl();
  }
  /* Cancel with changes asks first; nothing else leaves the page with them
     (the section's own address and Back bring the editor back). */
  function leaveEditor() {
    if (!dirty()) { closeEditor(); return; }
    var s = edited();
    window.ADspaceConfirm.ask({ title: 'Discard changes?', body: s.id || !st.pending ? 'The changes to ' + label(s) + ' are not saved.' : 'The new script is not saved.',
      go: 'Discard', tone: 'warn' }, function () { closeEditor(); if (st.open) paintRecord(); });
  }
  window.addEventListener('beforeunload', function (e) {
    if (!dirty()) return;
    e.preventDefault();
    e.returnValue = '';
  });

  function openEdit(opener, push) {
    var s = edited();
    say($('vsMsg'), '');
    $('vsSheetTitle').textContent = s.id ? 'Edit ' + label(s) : 'New script';
    $('vsEditMeta').textContent = [(s.clients || {}).name, monthWord(s.period)].filter(Boolean).join(' · ');
    fillMonth($('vsMonth'), s.period);
    $('vsKind').value = s.kind;
    $('vsKind').dispatchEvent(new Event('change', { bubbles: true }));
    $('vsTitle').value = s.title || '';
    $('vsRef').value = s.reference_url || '';
    fillSelect($('vsPlatform'), PLATFORMS, s.platform);
    fillSelect($('vsLang'), LANGS, s.language, langWord);
    $('vsDate').value = s.shoot_on || '';
    $('vsTime').value = s.shoot_time ? String(s.shoot_time).slice(0, 5) : '';
    $('vsVenue').value = s.venue || '';
    fillSelect($('vsDur'), DURATIONS, s.duration_minutes, durWord);
    $('vsCast').value = s.cast_names || '';
    $('vsContext').value = s.context || '';
    $('vsVo').value = s.vo || '';
    $('vsNotes').value = s.remarks || '';
    $('vsAspect').value = s.aspect || '';
    $('vsLength').value = s.length_seconds ? String(s.length_seconds) : '';
    ['vsAspect', 'vsLength'].forEach(function (id) { $(id).dispatchEvent(new Event('change', { bubbles: true })); });
    var b = s.brief || {};
    fillSelect($('vsObjective'), OBJECTIVES.map(function (x) { return x[0]; }), b.objective, function (k) { return wordOf(OBJECTIVES, k); });
    fillSelect($('vsFormat'), FORMATS.map(function (x) { return x[0]; }), b.format, function (k) { return wordOf(FORMATS, k); });
    BRIEF_FIELDS.forEach(function (f) { if (f[0] !== 'objective' && f[0] !== 'format') $(f[1]).value = b[f[0]] != null ? String(b[f[0]]) : ''; });
    putPlan(s.plan || {});
    st.rev = { set: false };
    paintEditReview();
    st.draft = (st.pending ? [] : st.scenes).map(sceneIn);
    if (!st.draft.length) st.draft.push(sceneIn(null));
    kindPaint();
    sayWrite('');
    var ub = $('vsWriteMsg').parentNode.querySelector(':scope > .undobar-here');
    if (ub) ub.parentNode.removeChild(ub);
    var busy = Boolean(s.id) && st.writing === s.id;
    $('vsWrite').disabled = busy;
    writeWord(busy);
    st.ai = null;
    st.editing = s.id || 'new';
    showEditor();
    window.scrollTo(0, 0);
    if (push !== false && bridge.pushUrl) bridge.pushUrl(); else if (bridge.setUrl) bridge.setUrl();
    st.base = snapshot();
    if (window.ADspaceGrow && window.ADspaceGrow.fit) {
      Array.prototype.forEach.call($('vsEditView').querySelectorAll('textarea'), function (t) { window.ADspaceGrow.fit(t); });
    }
    if (s.id && st.kept && st.kept.id === s.id) {
      var held = st.kept.words;
      st.kept = null;
      showWritten(held, sheetWords());
    }
  }

  function paintDraftScenes() {
    var box = $('vsScenes');
    if (!box) return;
    var two = $('vsKind').value === 'scenes';
    box.innerHTML = st.draft.map(function (x, i) {
      var n = i + 1;
      return '<div class="vs-edit-scene" data-i="' + i + '">' +
        '<div class="vs-edit-head"><span class="field-label">Scene ' + n + '</span><span class="vs-edit-acts">' +
          '<button class="iconbtn" type="button" data-m="up" aria-label="Move scene ' + n + ' up"' + (i ? '' : ' disabled') + '>' + ICON.up + '</button>' +
          '<button class="iconbtn" type="button" data-m="down" aria-label="Move scene ' + n + ' down"' + (i < st.draft.length - 1 ? '' : ' disabled') + '>' + ICON.down + '</button>' +
          '<button class="iconbtn" type="button" data-m="x" aria-label="Remove scene ' + n + '">' + ICON.x + '</button>' +
        '</span></div>' +
        '<div class="row fgrid-3 vs-edit-shot">' +
          '<div class="vs-edit-time"><span class="field-label" id="vsTl' + i + '">Time (seconds)</span><span class="vs-edit-pair">' +
            '<input class="input" id="vsTa' + i + '" type="number" inputmode="numeric" min="0" max="600" step="1" data-f="t_from" value="' + esc(x.t_from) + '" aria-labelledby="vsTl' + i + '" aria-label="Starts at" placeholder="From">' +
            '<input class="input" id="vsTb' + i + '" type="number" inputmode="numeric" min="1" max="600" step="1" data-f="t_to" value="' + esc(x.t_to) + '" aria-label="Ends at" placeholder="To"></span></div>' +
          '<div><label class="field-label" for="vsSz' + i + '">Shot size</label><select class="select" id="vsSz' + i + '" data-f="shot_size">' + optsOf(SHOT_SIZES, x.shot_size) + '</select></div>' +
          '<div><label class="field-label" for="vsAn' + i + '">Angle</label><select class="select" id="vsAn' + i + '" data-f="angle">' + optsOf(ANGLES, x.angle) + '</select></div>' +
        '</div>' +
        '<div class="row"><div><label class="field-label" for="vsMv' + i + '">Camera move</label>' +
          '<textarea class="input" id="vsMv' + i + '" rows="1" data-oneline maxlength="60" data-f="camera_move" placeholder="Slow push in">' + esc(x.camera_move) + '</textarea></div></div>' +
        '<div class="row' + (two ? ' fgrid' : '') + '">' +
          '<div><label class="field-label" for="vsV' + i + '">' + esc(SCENE_WORD[$('vsKind').value] || 'Visual') + '</label>' +
            '<textarea class="input" id="vsV' + i + '" rows="2" data-f="visual">' + esc(x.visual) + '</textarea></div>' +
          (two ? '<div><label class="field-label" for="vsL' + i + '">Script</label>' +
            '<textarea class="input" id="vsL' + i + '" rows="2" data-f="line">' + esc(x.line) + '</textarea></div>' : '') +
        '</div>' +
        '<div class="row fgrid">' +
          '<div><label class="field-label" for="vsOs' + i + '">On-screen text</label>' +
            '<textarea class="input" id="vsOs' + i + '" rows="1" data-oneline maxlength="120" data-f="on_screen" placeholder="Optional">' + esc(x.on_screen) + '</textarea></div>' +
          '<div><label class="field-label" for="vsSd' + i + '">Sound</label>' +
            '<textarea class="input" id="vsSd' + i + '" rows="1" data-oneline maxlength="200" data-f="sound" placeholder="Optional">' + esc(x.sound) + '</textarea></div>' +
        '</div></div>';
    }).join('');
    Array.prototype.forEach.call(box.querySelectorAll('.vs-edit-scene'), function (row) {
      var i = Number(row.getAttribute('data-i'));
      Array.prototype.forEach.call(row.querySelectorAll('[data-f]'), function (t) {
        ['input', 'change'].forEach(function (ev) { t.addEventListener(ev, function () { st.draft[i][t.getAttribute('data-f')] = t.value; }); });
      });
      Array.prototype.forEach.call(row.querySelectorAll('[data-m]'), function (b) {
        b.addEventListener('click', function () {
          var mv = b.getAttribute('data-m');
          if (mv === 'x') st.draft.splice(i, 1);
          else {
            var j = mv === 'up' ? i - 1 : i + 1;
            var tmp = st.draft[i]; st.draft[i] = st.draft[j]; st.draft[j] = tmp;
          }
          paintDraftScenes();
        });
      });
    });
  }
  /* A select's options, the value held kept where the list lacks it (a
     word Write with AI chose). */
  function optsOf(list, cur) {
    var o = list.slice();
    if (cur && o.indexOf(cur) < 0) o.push(cur);
    return '<option value="">Not set</option>' + o.map(function (v) {
      return '<option value="' + esc(v) + '"' + (v === cur ? ' selected' : '') + '>' + esc(v) + '</option>';
    }).join('');
  }
  $('vsAddScene').addEventListener('click', function () {
    if (st.draft.length >= 60) { say($('vsMsg'), SAID['too-many']); return; }
    st.draft.push(sceneIn(null));
    paintDraftScenes();
    var last = $('vsV' + (st.draft.length - 1));
    if (last) last.focus();
  });
  $('vsCancel').addEventListener('click', function () { leaveEditor(); });
  $('vsSave').addEventListener('click', function () {
    /* A script written with AI is declared read before it is kept
       (2026-10-10). */
    var cur = edited();
    if (st.ai && cur && cur.id && st.ai === cur.id && window.ADspaceConfirm.ai) {
      window.ADspaceConfirm.ai.declare('script', 'Confirm and save', function () { saveScript(true); });
      return;
    }
    saveScript(false);
  });
  function saveScript(declared) {
    var m = $('vsMsg'), btn = $('vsSave'), s = edited(), fresh = Boolean(st.pending);
    var ref = $('vsRef').value.trim().replace(/^https:\/\//i, 'https://');
    if (ref && !/^https:\/\//.test(ref)) { say(m, SAID['bad-link']); $('vsRef').focus(); return; }
    var head = {
      kind: $('vsKind').value, title: $('vsTitle').value.trim(), reference_url: ref,
      platform: $('vsPlatform').value, language: $('vsLang').value,
      shoot_on: $('vsDate').value, shoot_time: $('vsTime').value, venue: $('vsVenue').value.trim(),
      duration_minutes: $('vsDur').value, cast_names: $('vsCast').value.trim(),
      context: CONTEXT_WORD[$('vsKind').value] ? $('vsContext').value.trim() : s.context || '',
      vo: $('vsKind').value === 'story' ? $('vsVo').value.trim() : s.vo || '',
      remarks: $('vsNotes').value.trim(), period: $('vsMonth').value,
      aspect: $('vsAspect').value, length_seconds: $('vsLength').value, brief: briefIn(), plan: planIn()
    };
    if (st.rev && st.rev.set) head.review = st.rev.value || null;
    var lim = [['vsMaxLoc', 10], ['vsMaxCast', 50], ['vsMaxHours', 24]].filter(function (f) {
      var v = $(f[0]).value.trim();
      return v && !(/^\d+$/.test(v) && Number(v) >= 1 && Number(v) <= f[1]);
    })[0];
    if (lim) { say(m, 'Enter a whole number from 1 to ' + lim[1] + '.'); $(lim[0]).focus(); return; }
    var bad = -1;
    var scenes = st.draft.filter(function (x) { return x.visual.trim() || x.line.trim(); })
      .map(function (x, i) {
        var a = x.t_from.trim(), b2 = x.t_to.trim();
        if ((a && !/^\d{1,3}$/.test(a)) || (b2 && !/^\d{1,3}$/.test(b2)) || Number(a) > 600 || Number(b2) > 600 ||
            (b2 && Number(b2) < 1) || (a && b2 && Number(b2) <= Number(a))) { if (bad < 0) bad = i; }
        return { id: x.id, visual: x.visual.trim(), line: $('vsKind').value === 'scenes' ? x.line.trim() : '',
                 t_from: a, t_to: b2, shot_size: x.shot_size, angle: x.angle, camera_move: x.camera_move.trim(),
                 on_screen: x.on_screen.trim(), sound: x.sound.trim() };
      });
    if (bad > -1) { say(m, SAID['bad-time']); var tf = $('vsTa' + st.draft.indexOf(st.draft.filter(function (x) { return x.visual.trim() || x.line.trim(); })[bad])); if (tf) tf.focus(); return; }
    btn.disabled = true;
    say(m, '');
    var sid = null;
    made().then(function (id) {
      sid = id;
      return rpc('video_script_save', { p_id: id, p_head: head, p_scenes: scenes, p_version: fresh ? null : s.version });
    }).then(function (d) {
      btn.disabled = false;
      if (declared) st.ai = null;
      st.rev = { set: false };
      closeEditor();
      if (fresh) {
        /* The new script opens on its own page, its number assigned. */
        st.loaded = false;
        st.mode = 'script';
        $('vsListView').hidden = true;
        $('vsRecord').hidden = false;
        st.open = { id: sid };
      }
      return readScript(sid).then(function () {
        if (declared && bridge.log) bridge.log('script.saved', ((st.open.clients || {}).name || '') + ' · ' + codeOf(st.open),
          'Script written with AI, read and confirmed');
        paintRecord();
        if (bridge.setUrl) bridge.setUrl();
        say($('vsCardMsg'), !fresh && !d.changed ? 'No changes.' : 'Saved.', 'ok');
      });
    }).catch(function (e) {
      btn.disabled = false;
      if (e && e.message === 'stale' && !fresh) {
        readScript(s.id).then(function () { paintRecord(); });
      }
      say(m, said(e));
    });
  }

  /* ---- Write script (AI) ------------------------------------------------------ */
  /* The sheet's script drafted by `script-draft` from the colleague's notes
     and what the sheet holds (2026-10-09). It asks first, counts against the
     colleague's scripts a day, and puts the words in the fields with Undo
     where it happened; Save keeps them. An answer that lands after the sheet
     was shut is held for that video and put in when it is next edited. */
  var WRITE_SAID = {
    'needs-update': 'This feature is not available yet. Please contact an admin.',
    'ai-not-set-up': 'Write with AI is not set up yet. Please contact an admin.',
    'ai-key': 'Write with AI is not available at the moment. Please contact an admin.',
    'ai-busy': 'The AI service is busy. Try again in a minute.',
    'ai-credit': 'Write with AI is not available at the moment. Please contact an admin.',
    'ai-model': 'Write with AI is not available at the moment. Please contact an admin.',
    'ai-failed': 'No script came back. Try again.',
    'ai-incomplete': 'No script came back. Try again.',
    denied: 'You do not have permission to change video scripts. Please ask an admin.',
    'client-scope': 'This client is outside your access.',
    'not-found': 'This script is no longer available.'
  };
  var LENGTHS = [['15', '15s'], ['30', '30s'], ['60', '60s'], ['120', '120s']];
  function keep(key, v) {
    try {
      if (v === undefined) return localStorage.getItem(key) || '';
      if (v) localStorage.setItem(key, v); else localStorage.removeItem(key);
    } catch (e) {}
    return '';
  }
  function writeClock(iso) {
    return window.ADspaceClock.clock(iso);
  }
  function writeLimit(d) {
    d = d || {};
    if (d.scope === 'stopped' || d.limit === 0) return 'Scripts with AI are turned off for you. An admin can turn them on.';
    var n = d.limit || 10;
    return 'You have used your ' + n + (n === 1 ? ' script' : ' scripts') + ' for today.' + (d.next ? ' Resets at ' + writeClock(d.next) + '.' : '');
  }
  function writeSaid(e) {
    var m = String((e && e.message) || '');
    if (m === 'ai-limit') return writeLimit(e.data || e.d);
    if (WRITE_SAID[m]) return WRITE_SAID[m];
    if (/function .* does not exist|schema cache|PGRST20[25]/i.test(m)) return WRITE_SAID['needs-update'];
    return m || WRITE_SAID['ai-failed'];
  }
  function sheetWords() {
    return {
      kind: $('vsKind').value, context: $('vsContext').value, vo: $('vsVo').value, plan: planIn(),
      rev: st.rev ? { set: st.rev.set, value: st.rev.value } : { set: false },
      scenes: st.draft.map(sceneIn)
    };
  }
  function putWords(w) {
    if ($('vsKind').value !== w.kind) {
      $('vsKind').value = w.kind;
      $('vsKind').dispatchEvent(new Event('change', { bubbles: true }));
    }
    $('vsContext').value = w.context || '';
    $('vsVo').value = w.vo || '';
    putPlan(w.plan || {});
    st.rev = w.rev || { set: false };
    paintEditReview();
    st.draft = w.scenes.length ? w.scenes.map(sceneIn) : [sceneIn(null)];
    paintDraftScenes();
  }
  function hasWords(kind) {
    return st.draft.some(function (x) { return x.visual.trim() || (kind === 'scenes' && x.line.trim()); }) ||
      (CONTEXT_WORD[kind] && $('vsContext').value.trim()) || (kind === 'story' && $('vsVo').value.trim());
  }
  /* The answer, filled: {brand} with the client's name and {handle} with the
     platform's handle (else the name). */
  function written(s, kind, d) {
    var nm = (s.clients || {}).name || '';
    var fill = function (t) {
      return String(t || '').replace(/\{\s*brand\s*\}/gi, nm).replace(/\{\s*handle\s*\}/gi, d.handle || nm);
    };
    var plan = {};
    Object.keys(d.draft.plan || {}).forEach(function (k) { plan[k] = fill(d.draft.plan[k]); });
    /* The review's words are filled the same way, so the colleague reads
       the client's name where the reviewer read {brand}. */
    var rv = d.review ? JSON.parse(JSON.stringify(d.review), function (k, v) { return typeof v === 'string' ? fill(v) : v; }) : null;
    return {
      kind: kind, context: fill(d.draft.context), vo: fill(d.draft.vo), plan: plan, rev: { set: true, value: rv },
      scenes: (d.draft.scenes || []).map(function (x) {
        var o = sceneIn(x);
        SCENE_KEYS.forEach(function (k) { o[k] = fill(o[k]); });
        o.id = null;
        return o;
      })
    };
  }
  function sayWrite(text) {
    var m = $('vsWriteMsg');
    m.textContent = text || '';
    m.className = 'msg capmsg' + (text ? ' err' : '');
  }
  /* The AI mark and the act's one word (2026-10-10): Write with AI. */
  var AI_GLYPH = (window.ADspaceConfirm && window.ADspaceConfirm.ai && window.ADspaceConfirm.ai.glyph) || '';
  function writeWord(busy) { $('vsWrite').innerHTML = AI_GLYPH + (busy ? 'Writing' : 'Write with AI'); }
  function showWritten(w, before) {
    putWords(w);
    st.ai = st.editing;
    sayWrite('');
    undoBar('Written by AI. Read before saving.', function () { putWords(before); st.ai = null; }, $('vsWriteMsg'));
  }
  $('vsWrite').addEventListener('click', function () {
    var btn = $('vsWrite'), s = edited();
    if (!s || !may('work')) return;
    var noteKey = s.id || 'new';
    sayWrite('');
    btn.disabled = true;
    var AD = window.ADspaceAdmin;
    Promise.all([rpc('ai_script_left', {}), AD.brandGate(s.client_id, true)]).then(function (both) {
      var left = both[0];
      btn.disabled = false;
      if (both[1]) { AD.brandSay($('vsWriteMsg'), both[1].text, s.client_id); return; }
      if (!left.left) { sayWrite(writeLimit(left)); return; }
      var kind = $('vsKind').value, plat = $('vsPlatform').value;
      /* The length and aspect ratio are the script's own (2026-11-05): asked
         here only where the editor holds none, and put in its field. */
      var fields = [];
      if (!$('vsLength').value) fields.push({ name: 'length', label: 'Video length', choices: LENGTHS, seg: true,
        value: keep('adspace-script-length:' + noteKey) || '30' });
      if (plat === 'rednote') fields.push({ name: 'safe', label: 'XHS Safe Mode', tick: true, value: false });
      fields.push({ name: 'notes', label: 'Notes for the script', rows: 4, required: false,
        placeholder: 'What the video is for, the product or offer, the call to action',
        value: keep('adspace-script-notes:' + noteKey) });
      window.ADspaceConfirm.ask({
        title: 'Write with AI',
        body: (st.pending && !st.pending.s.id ? 'The new script is saved first, taking its number. ' : '') + (hasWords(kind) ? 'Replaces the script in these fields. ' : '') + left.left + (left.left === 1 ? ' script' : ' scripts') + ' left today.',
        go: 'Write', fields: fields
      }, function (v) {
        var notes = String(v.notes || '').trim();
        if (v.length && !$('vsLength').value) {
          $('vsLength').value = String(v.length);
          $('vsLength').dispatchEvent(new Event('change', { bubbles: true }));
        }
        var length = Number($('vsLength').value) || 30;
        var before = sheetWords();
        var cur = sheetWords();
        var sid = null;
        var here = function () { var e = edited(); return Boolean(e && sid && e.id === sid); };
        var settle = function () {
          st.writing = null;
          if (here()) { btn.disabled = false; writeWord(false); }
        };
        btn.disabled = true;
        writeWord(true);
        /* A script Add script has not made yet is made first: the writer
           reads the script, its client and its month as the caller. */
        made().then(function (id) {
          sid = id;
          keep('adspace-script-notes:' + id, notes);
          keep('adspace-script-length:' + id, String(length));
          st.writing = id;
          return db.functions.invoke('script-draft', { body: {
          script_id: id, kind: kind, title: $('vsTitle').value.trim(), platform: plat, language: $('vsLang').value,
          length: length, aspect: $('vsAspect').value, venue: $('vsVenue').value.trim(), brief: briefIn(),
          cast: $('vsCast').value.split(/[,，;\n]+/).filter(function (x) { return x.trim(); }).length,
          notes: notes, safe: plat === 'rednote' && v.safe === 'on',
          current: { context: CONTEXT_WORD[kind] ? cur.context : '', vo: kind === 'story' ? cur.vo : '',
                     scenes: cur.scenes.map(function (x) {
                       var o = sceneIn(x);
                       delete o.id;
                       if (kind !== 'scenes') o.line = '';
                       return o;
                     }) }
        } });
        }).then(function (res) {
          var d = res && res.data;
          if (res.error || !d || d.error || !d.draft) { var x = new Error((d && d.error) || 'ai-failed'); x.d = d; throw x; }
          settle();
          var w = written(s, kind, d);
          var open = !$('vsEditView').hidden && st.editing === sid;
          if (open) showWritten(w, before);
          else st.kept = { id: sid, words: w };
        }).catch(function (e) {
          settle();
          if (sid ? !here() : edited() !== s) return;
          var code = e && e.message;
          if (code === 'no-brief' || code === 'no-analysis') AD.brandSay($('vsWriteMsg'), AD.brandWords(code, e.d && e.d.missing), s.client_id);
          else sayWrite(writeSaid(e));
        });
      });
    }).catch(function (e) { btn.disabled = false; sayWrite(writeSaid(e)); });
  });

  /* ---- The PDF, for the crew on site --------------------------------------- */
  /* Preview PDF opens a tab at the press and puts the drawn file in it;
     Download (the ⋯) saves it under its own name, as a report's do. With
     two scripts or more in the month, either asks which. */
  function openTab() { return window.ADspaceDocs.previewTab(); }
  function drawPdf(btn, save) {
    /* From the month the whole month is drawn; on a script's own page, with
       others in its month, the question is that script or the month (VS-2). */
    var month = st.mode === 'month';
    var many = !month && st.series.length > 1;
    var go = function (whole) {
      var m = $('vsRecMsg');
      var tab = save ? (window.ADspaceDocs.tabFor ? window.ADspaceDocs.tabFor() : null) : openTab();
      btn.disabled = true;
      say(m, 'Drawing the PDF…', 'ok');
      var ids = whole ? st.series.map(function (x) { return x.id; }) : [st.open.id];
      gather(ids).then(function (videos) {
        return window.ADspaceScriptPdf.draw(videos);
      }).then(function (blob) {
        btn.disabled = false;
        var c = (st.open.clients || {}).name || 'Client';
        var name = c + ' Video Script ' + (whole && st.series.length > 1 ? codeOf(st.series[0]) + '-' + codeOf(st.series[st.series.length - 1]) : codeOf(whole ? st.series[0] : st.open)) + '.pdf';
        say(m, save || (tab && !tab.closed) ? '' : 'Downloaded.', 'ok');
        window.ADspaceDocs.save(blob, name.replace(/[\\/:*?"<>|]+/g, ' '), tab);
      }).catch(function (e) {
        btn.disabled = false;
        if (window.ADspaceDocs.shut) window.ADspaceDocs.shut(tab);
        say(m, 'Not drawn. ' + said(e));
      });
    };
    if (!many) { go(month); return; }
    window.ADspaceConfirm.ask({ title: save ? 'Download' : 'Preview PDF', go: save ? 'Download' : 'Preview',
      field: { label: 'Scripts', choices: [['one', 'This script'], ['all', 'Whole month']], seg: true, value: 'all' }
    }, function (v) { go(v === 'all'); });
  }
  function gather(ids) {
    return Promise.all([
      db.from('video_scripts').select('*, clients(name)').in('id', ids).order('seq'),
      db.from('video_script_scenes').select('script_id, position, visual, line, vc, shot_at, t_from, t_to, shot_size, angle, camera_move, on_screen, sound, photo_thumb, ai_thumb').in('script_id', ids).order('position')
    ]).then(function (rs) {
      rs.forEach(function (x) { if (x.error) throw x.error; });
      var by = {};
      (rs[1].data || []).forEach(function (sc) { (by[sc.script_id] = by[sc.script_id] || []).push(sc); });
      return (rs[0].data || []).map(function (s) {
        s.scenes = by[s.id] || [];
        s.kind_word = KIND_WORD[s.kind];
        s.context_word = CONTEXT_WORD[s.kind] || '';
        s.when = [dayWord(s.shoot_on), timeWord(s.shoot_time)].filter(Boolean).join(', ');
        s.duration = durWord(s.duration_minutes);
        s.month_word = monthWord(s.period);
        s.length_word = lengthWord(s.length_seconds);
        s.scenes.forEach(function (sc) { sc.cam = camOf(sc); });
        return s;
      });
    }).then(function (videos) {
      /* Each scene's picture for the crew: its thumbnail, else its frame
         drawn to a PNG (2026-11-05). */
      var jobs = [];
      videos.forEach(function (v) {
        v.scenes.forEach(function (sc) {
          sc.pic = sc.photo_thumb || sc.ai_thumb || null;
          if (sc.pic || !window.ADspaceFrames) return;
          var svg = window.ADspaceFrames.svg(sc, v.aspect);
          if (svg) jobs.push(framePng(svg).then(function (d) { sc.pic = d; }, function () {}));
        });
      });
      return Promise.all(jobs).then(function () { return videos; });
    });
  }
  /* A drawn frame as a PNG data URL, in ink on white, twice its size. */
  function framePng(svg) {
    return new Promise(function (resolve, reject) {
      var src = svg.replace('<svg ', '<svg xmlns="http://www.w3.org/2000/svg" style="color:#1b1a17" ').replace(/currentColor/g, '#1b1a17');
      var img = new Image();
      img.onload = function () {
        var c = document.createElement('canvas');
        c.width = img.naturalWidth * 2; c.height = img.naturalHeight * 2;
        var g = c.getContext('2d');
        g.fillStyle = '#fff'; g.fillRect(0, 0, c.width, c.height);
        g.drawImage(img, 0, 0, c.width, c.height);
        resolve(c.toDataURL('image/png'));
      };
      img.onerror = reject;
      img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(src);
    });
  }

  /* ---- The address -------------------------------------------------------- */
  function urlState() {
    if (!st.open || !st.open.id) return {};
    /* Add script's editor names the month it adds to; a refresh opens it
       again, nothing having been stored. */
    if (st.pending) return { month: st.open.id, add: '1' };
    if (st.mode === 'month' && st.editing !== st.open.id) return { month: st.open.id };
    return st.editing === st.open.id ? { script: st.open.id, edit: '1' } : { script: st.open.id };
  }
  function enter() {
    st.drawAsked = false;
    say($('vsListMsg'), '');
    say($('vsRecMsg'), '');
    /* An editor holding changes is never left by an address: Back, the rail
       or a refresh-free return brings it back as it was. */
    if (dirty()) {
      showEditor();
      if (bridge.setUrl) bridge.setUrl();
      say($('vsMsg'), 'Save or cancel the changes first.', 'warn');
      return;
    }
    var q = new URLSearchParams(location.search);
    var id = q.get('script');
    if (st.editing) closeEditor();
    if (id) { openScript(id, false, q.get('edit') === '1' && may('work')); return; }
    if (q.get('month')) {
      var add = q.get('add') === '1' && may('work');
      openMonth(q.get('month'), false).then(function () {
        if (add && st.open && st.open.client_id && st.mode === 'month') nextVideo($('vsNextVideo'), false);
      });
      return;
    }
    st.open = null;
    $('vsEditView').hidden = true;
    $('vsRecord').hidden = true;
    $('vsListView').hidden = false;
    if (bridge.setUrl) bridge.setUrl();
    load();
  }

  window.ADspaceScripts = { enter: enter, urlState: urlState, reload: load };
  if (bridge.scriptsReady) bridge.scriptsReady();
})();
