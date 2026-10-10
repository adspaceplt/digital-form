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
  /* Unpublish carries the mark it carries on a campaign (one glyph an act). */
  var EYE_OFF = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m3 3 18 18"/><path d="M10.6 5.1A9.6 9.6 0 0 1 12 5c5 0 9 4.5 9 7a12 12 0 0 1-2.4 3.4"/><path d="M6.5 7.6C4.3 9.1 3 11.2 3 12c0 2.5 4 7 9 7a9.7 9.7 0 0 0 4.2-1"/></svg>';
  var KIND_WORD = {};
  KINDS.forEach(function (k) { KIND_WORD[k[0]] = k[1]; });
  var CONTEXT_WORD = { products: 'Products and context', story: 'Hook and story' };
  var SCENE_WORD = { scenes: 'Visual', products: 'Scene', story: 'Scene' };
  var PLATFORMS = ['Instagram', 'TikTok', 'Facebook', 'rednote', 'YouTube'];
  var LANGS = ['English', 'Chinese', 'Malay', 'English and Chinese'];
  /* The stored word stays; the page says Bahasa Melayu, as Write caption does. */
  function langWord(v) { return v === 'Malay' ? 'Bahasa Melayu' : v; }
  var DURATIONS = [30, 60, 90, 120, 180, 240, 300, 360, 480, 600, 720];
  var MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
  var STATE = { draft: ['Draft', 'is-off'], shared: ['Published', 'is-live'] };
  var ICON = {
    dots: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="5" cy="12" r="1.6" fill="currentColor"/><circle cx="12" cy="12" r="1.6" fill="currentColor"/><circle cx="19" cy="12" r="1.6" fill="currentColor"/></svg>',
    plus: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>',
    copy: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/></svg>',
    pen: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 20h4L19 9l-4-4L4 16z"/></svg>',
    up: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 14 6-6 6 6"/></svg>',
    down: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 10 6 6 6-6"/></svg>',
    x: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>',
    out: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 4h6v6"/><path d="M20 4 11 13"/><path d="M19 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1h5"/></svg>'
  };

  var st = { list: [], clients: [], loaded: false, open: null, scenes: [],
             series: [], key: null, draft: [], idem: null, find: '', editing: null, base: '' };

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function say(el, text, tone) {
    if (!el) return;
    el.textContent = text || '';
    el.className = 'msg' + (text ? ' ' + (tone || 'err') : '');
  }
  function may(level) { return Boolean(bridge.may && bridge.may('scripts', level || 'work')); }
  function dayWord(iso) {
    if (!iso) return '';
    var d = /^\d{4}-\d{2}-\d{2}$/.test(iso) ? new Date(iso + 'T00:00:00') : new Date(iso);
    return isNaN(d) ? '' : d.getDate() + ' ' + MON[d.getMonth()] + ' ' + d.getFullYear();
  }
  function timeWord(t) {
    var m = /^(\d{1,2}):(\d{2})/.exec(t || '');
    if (!m) return '';
    var h = Number(m[1]), ap = h >= 12 ? 'pm' : 'am';
    return ((h % 12) || 12) + ':' + m[2] + ' ' + ap;
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
    var now = new Date(Date.now() + 8 * 36e5), y = now.getUTCFullYear(), mo = now.getUTCMonth();
    var out = [];
    for (var i = -1; i <= 6; i++) {
      var d = new Date(Date.UTC(y, mo + i, 1));
      out.push(d.getUTCFullYear() + '-' + String(d.getUTCMonth() + 1).padStart(2, '0'));
    }
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
    denied: 'This needs Video Scripts at Work.',
    'client-scope': 'This client is outside your access.',
    'not-found': 'This script is no longer available.',
    'bad-kind': 'Choose the script type.',
    'bad-period': 'Choose the content month.',
    'bad-title': 'A title is 200 characters at most.',
    'bad-link': 'A reference link starts with https://.',
    'bad-duration': 'Choose a duration between 5 minutes and 24 hours.',
    'bad-date': 'Choose a date from 14 Aug 2023.',
    'too-long': 'A field is too long to save.',
    'too-many': 'A month holds 99 scripts, and a script 60 scenes, at most.',
    'bad-scenes': 'The scenes could not be read.',
    stale: 'This script was changed elsewhere and has been read again. Enter the change again.',
    'denied-delete': 'Deleting a script needs Video Scripts at Full Access.',
    name: 'The name does not match.'
  };
  function said(e) {
    var m = String((e && (e.message || e.error)) || e || '');
    if (SAID[m]) return SAID[m];
    if (/function .* does not exist|schema cache|relation .*video_script|PGRST20[25]/i.test(m)) return 'This needs a database update.';
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
    return db.from('video_scripts')
      .select('id, client_id, period, seq, code, video_no, kind, title, status, shoot_on, venue, updated_at, created_at, clients(name, client_code)')
      .order('period', { ascending: false }).order('seq')
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
      UI.emptyLine(box, 'No matches.', 'Clear the search', function () { $('vsFind').value = ''; st.find = ''; paint(); });
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
    months.sort(function (a, b) { return b.localeCompare(a); });
    months.forEach(function (p, i) {
      var groups = Object.keys(byMonth[p]).map(function (k) { return byMonth[p][k]; });
      groups.forEach(function (g) { g.scripts.sort(function (a, b) { return (a.seq || 0) - (b.seq || 0); }); });
      groups.sort(function (a, b) { return String(a.client.name || '').localeCompare(String(b.client.name || ''), 'en', { sensitivity: 'base' }); });
      var n = groups.reduce(function (t, g) { return t + g.scripts.length; }, 0);
      box.appendChild(GRP.section({
        route: 'scripts', key: 'm' + p, name: p === 'none' ? 'No month' : monthWord(p), count: n,
        shut: !st.find && GRP.shut('scripts', 'm' + p, i > 0, months.length === 1),
        table: function () {
          var table = GRP.table('vs-row', ['Client', 'Next shoot', 'Published']);
          GRP.more(table, groups, 30, 'scripts', rowOf);
          return table;
        }
      }));
    });
  }

  /* One client's month: the client over its codes and scripts, the next
     shoot (else the last), and how many of its scripts are published. */
  function rowOf(g) {
    var row = document.createElement('button');
    row.type = 'button';
    row.className = 'crm-row vs-row';
    var list = g.scripts, n = list.length;
    var pub = list.filter(function (x) { return stateOf(x) === 'shared'; }).length;
    var codes = list.map(function (x) { return tabWord(x); });
    var today = new Date().toISOString().slice(0, 10);
    var days = list.map(function (x) { return x.shoot_on; }).filter(Boolean).sort();
    var ahead = days.filter(function (d) { return d >= today; })[0], shoot = ahead || days[days.length - 1];
    row.setAttribute('data-id', list[0].id);
    row.innerHTML =
      '<span class="vs-c-name"><b>' + esc(g.client.name || 'Client') + '</b><small>' +
        esc((n === 1 ? codes[0] : codes[0] + ' to ' + codes[n - 1]) + ' · ' + n + (n === 1 ? ' script' : ' scripts')) + '</small></span>' +
      '<span class="vs-c-shoot">' + (shoot ? esc(dayWord(shoot)) + (ahead ? '' : ' <span class="mute">· Last</span>') : '<span class="mute">Not set</span>') + '</span>' +
      '<span class="vs-c-state">' + (pub === n ? chip('shared') : pub ? '<span class="chip-state is-warn">' + pub + ' of ' + n + '</span>' : chip('draft')) + '</span>';
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
    btn.disabled = true;
    rpc('video_script_new', { p_client: client, p_period: $('vsNewMonth').value, p_kind: $('vsNewKind').value, p_from: null, p_idem: st.idem })
      .then(function (d) {
        btn.disabled = false;
        window.ADspaceSheet.clean();
        window.ADspaceSheet.close();
        st.loaded = false;
        openScript(d.id, true, true);
      }).catch(function (e) { btn.disabled = false; say(m, said(e)); });
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
    return readScript(id).then(function () {
      paintRecord();
      if (edit && may('work')) openEdit($('vsRecBody').querySelector('[data-a="edit"]'), push);
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
        db.from('video_script_scenes').select('id, position, visual, line, vc, shot_at, shot_by').eq('script_id', id).order('position'),
        db.from('video_scripts').select('id, code, seq, video_no, title, status, kind, shoot_on, venue').eq('client_id', st.open.client_id)
          .eq('period', st.open.period).order('seq')
      ]);
    }).then(function (rs) {
      rs.forEach(function (x) { if (x.error) throw x.error; });
      st.scenes = rs[0].data || [];
      st.series = rs[1].data || [];
    });
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
    }).join('') + ref + '</dl>';
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
  function sceneRows(s) {
    var work = may('work');
    var kind = s.kind;
    var head = '<div class="crm-head vs-scene">' +
      '<span>#</span><span>' + esc(SCENE_WORD[kind]) + '</span>' + (kind === 'scenes' ? '<span>Script</span>' : '') +
      '<span>VC#</span><span>Shot</span></div>';
    if (!st.scenes.length) return '<div class="crm-table vs-scenes' + (kind === 'scenes' ? ' is-two' : '') + '">' + head +
      '<p class="vs-empty">No scenes.</p></div>';
    return '<div class="crm-table vs-scenes' + (kind === 'scenes' ? ' is-two' : '') + '">' + head + st.scenes.map(function (sc, i) {
      return '<div class="vs-scene" data-scene="' + esc(sc.id) + '">' +
        '<span class="vs-n">' + (i + 1) + '</span>' +
        '<span class="vs-text vs-vis">' + esc(sc.visual || '') + '</span>' +
        (kind === 'scenes' ? '<span class="vs-text vs-line">' + esc(sc.line || '') + '</span>' : '') +
        '<span class="vs-vc">' + (work ? clipField(sc.vc, 'Clip number for scene ' + (i + 1)) : esc(sc.vc || '—')) + '</span>' +
        '<span class="vs-shot"><label><input type="checkbox" ' + (sc.shot_at ? 'checked ' : '') + (work ? '' : 'disabled ') +
          'aria-label="Scene ' + (i + 1) + ' shot" data-shot></label></span>' +
      '</div>';
    }).join('') + '</div>';
  }
  function scriptBody(s) {
    var out = '';
    if (CONTEXT_WORD[s.kind]) {
      out += '<section class="vs-block"><h4 class="fsec-h">' + esc(CONTEXT_WORD[s.kind]) + '</h4>' +
        '<p class="vs-prose">' + (s.context ? esc(s.context) : '<span class="mute">Not written</span>') + '</p></section>';
    }
    out += '<section class="vs-block"><h4 class="fsec-h">Scenes</h4>' + sceneRows(s) +
      '<p class="msg vs-shot-msg" id="vsShotMsg" role="status"></p></section>';
    if (s.kind === 'story') {
      var work = may('work');
      out += '<section class="vs-block"><h4 class="fsec-h">Script (read here)</h4>' +
        '<p class="vs-prose">' + (s.vo ? esc(s.vo) : '<span class="mute">Not written</span>') + '</p>' +
        '<div class="vs-vo" data-vo>' +
          '<label class="field-label" for="vsVoVc">VC#</label>' +
          (work ? clipField(s.vo_vc, 'Clip number for the voice-over', 'vsVoVc') : '<span>' + esc(s.vo_vc || '—') + '</span>') +
          '<label class="tickline"><input type="checkbox" id="vsVoShot" ' + (s.vo_shot_at ? 'checked ' : '') + (work ? '' : 'disabled ') + '> <span>Shot</span></label>' +
        '</div></section>';
    }
    out += '<section class="vs-block"><h4 class="fsec-h">Notes</h4><p class="vs-prose">' +
      (s.remarks ? esc(s.remarks) : '<span class="mute">None</span>') + '</p></section>';
    return out;
  }

  /* The month's ⋯: Download, and Reset access link at Work (Preview PDF
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
      menuOf('vsRecMore', '<button class="kmenu-item" data-a="download" type="button"><b>Download</b></button>' +
        (may('work') ? '<button class="kmenu-item" data-a="reset" type="button"><b>Reset access link</b></button>' : ''));
    paintLink();
    var inMonth = st.mode === 'month';
    $('vsMonthList').hidden = !inMonth;
    $('vsNav').hidden = inMonth;
    $('vsRecBody').hidden = inMonth;
    if (inMonth) paintMonth(); else { paintNav(); paintScript(); }
  }

  /* A script's number within the month (VS01). */
  function tabWord(x) { var c = codeOf(x); return /VS\d+$/.test(c) ? c.replace(/^\d{4}/, '') : c; }
  /* The month's scripts as rows: the number and title over the type, the
     shoot, the state, each opening its script. */
  function paintMonth() {
    $('vsNextVideo').hidden = !may('work');
    var rows = st.series.map(function (x) {
      return '<button class="crm-row vs-row vs-mrow" type="button" data-v="' + esc(x.id) + '">' +
        '<span class="vs-c-name"><b>' + esc(tabWord(x) + (x.title ? ' · ' + x.title : '')) + '</b><small>' + esc(KIND_WORD[x.kind] || '') + '</small></span>' +
        '<span class="vs-c-shoot">' + (x.shoot_on ? esc(dayWord(x.shoot_on)) : '<span class="mute">Not set</span>') + '</span>' +
        '<span class="vs-c-state">' + chip(stateOf(x)) + '</span></button>';
    }).join('');
    $('vsMonthRows').innerHTML = '<div class="crm-table vs-mtable"><div class="crm-head vs-row"><span>Script</span><span>Shoot</span><span>State</span></div>' + rows + '</div>';
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
    if (may('work')) {
      acts += '<button class="btn btn-sm btn-icon" type="button" data-a="edit">' + ICON.pen + 'Edit</button>';
      acts += s.status === 'shared'
        ? '<button class="btn btn-sm btn-warn" type="button" data-a="unpublish">' + EYE_OFF + 'Unpublish</button>'
        : '<button class="btn btn-sm btn-go" type="button" data-a="publish">Publish</button>';
    }
    $('vsRecBody').innerHTML = '<section class="panel vs-factcard">' +
        '<div class="vs-cardhead"><div class="vs-cardwho"><h3 id="vsScriptName">' + esc(label(s)) + '</h3>' +
          '<p>' + esc(KIND_WORD[s.kind] || '') + '</p></div>' +
          '<div class="vs-cardctl">' + chip(key) + acts +
            menuOf('vsCardMore', may('manage') ? '<button class="kmenu-item is-danger" data-a="del" type="button"><b>Delete</b></button>' : '') +
          '</div></div>' +
        '<div class="msg" id="vsCardMsg" role="status"></div>' +
        facts(s) + '</section>' +
      '<section class="panel vs-sheetview">' + scriptBody(s) + '</section>';
    wireRecord();
  }

  function wireRecord() {
    var on = function (root, a, fn) { var b = root && root.querySelector('[data-a="' + a + '"]'); if (b) b.addEventListener('click', function () { fn(b); }); };
    var ctl = $('vsRecCtl'), body = $('vsRecBody');
    on(ctl, 'pdf', function (b) { drawPdf(b, false); });
    on(body, 'edit', function (b) { openEdit(b); });
    on(body, 'publish', function (b) { publish(true, b); });
    on(body, 'unpublish', function (b) { publish(false, b); });
    [['vsRecMore', ctl], ['vsCardMore', body]].forEach(function (pair) {
      var mb = $(pair[0]);
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
      on(menu, 'download', function () { shutMenu(); drawPdf(mb, true); });
      on(menu, 'reset', function () { shutMenu(); resetLink(); });
      on(menu, 'del', function () { shutMenu(); remove(); });
    });
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
  var undoTimer = null;
  function undoBar(text, undo, host) {
    if (!host || !host.parentNode) return;
    var here = host.parentNode.querySelector(':scope > .undobar-here');
    if (!here) {
      here = document.createElement('div');
      here.className = 'undobar undobar-here';
      host.parentNode.insertBefore(here, host.nextSibling);
    }
    var shut = function () { if (here.parentNode) here.parentNode.removeChild(here); };
    here.innerHTML = '<span>' + esc(text) + '</span><button class="btn btn-sm" type="button">Undo</button>';
    here.querySelector('button').addEventListener('click', function () { clearTimeout(undoTimer); shut(); undo(); });
    clearTimeout(undoTimer);
    undoTimer = setTimeout(shut, 8000);
  }

  function clientLink(key) { return location.origin + '/script/?k=' + key; }
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
      if (has) { $('vsLink').value = clientLink(st.key); $('vsOpen').href = clientLink(st.key); }
      $('vsLinkTools').hidden = !has;
    };
    show();
    if (st.keyFor === s.client_id || st.keyTried === s.client_id) return;
    st.keyTried = s.client_id;
    withKey(false).then(show).catch(show);
  }
  $('vsCopy').addEventListener('click', function () {
    if (st.key) window.ADspaceCopy.to($('vsCopy'), clientLink(st.key));
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
      body: label(s) + ', its scenes and their clip numbers will be deleted. There is no restore.',
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
  function nextVideo(btn) {
    btn.disabled = true;
    rpc('video_script_new', { p_client: st.open.client_id, p_period: st.open.period, p_kind: st.open.kind, p_from: st.open.id, p_idem: uuid() })
      .then(function (d) { btn.disabled = false; openScript(d.id, true, true); })
      .catch(function (e) { btn.disabled = false; say($('vsRecMsg'), said(e)); });
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
      st.draft.map(function (x) { return [x.visual, x.line]; })]);
  }
  function dirty() { return Boolean(st.editing) && snapshot() !== st.base; }
  function showEditor() {
    $('vsListView').hidden = true;
    $('vsRecord').hidden = true;
    $('vsEditView').hidden = false;
  }
  function closeEditor() {
    st.editing = null;
    st.base = '';
    $('vsEditView').hidden = true;
    $('vsRecord').hidden = false;
    if (bridge.setUrl) bridge.setUrl();
  }
  /* Cancel with changes asks first; nothing else leaves the page with them
     (the section's own address and Back bring the editor back). */
  function leaveEditor() {
    if (!dirty()) { closeEditor(); return; }
    window.ADspaceConfirm.ask({ title: 'Discard changes?', body: 'The changes to ' + label(st.open) + ' are not saved.',
      go: 'Discard', tone: 'warn' }, function () { closeEditor(); paintRecord(); });
  }
  window.addEventListener('beforeunload', function (e) {
    if (!dirty()) return;
    e.preventDefault();
    e.returnValue = '';
  });

  function openEdit(opener, push) {
    var s = st.open;
    say($('vsMsg'), '');
    $('vsSheetTitle').textContent = 'Edit ' + label(s);
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
    st.draft = st.scenes.map(function (x) { return { id: x.id, visual: x.visual || '', line: x.line || '' }; });
    if (!st.draft.length) st.draft.push({ id: null, visual: '', line: '' });
    kindPaint();
    sayWrite('');
    var ub = $('vsWriteMsg').parentNode.querySelector(':scope > .undobar-here');
    if (ub) ub.parentNode.removeChild(ub);
    $('vsWrite').disabled = st.writing === s.id;
    writeWord(st.writing === s.id);
    st.ai = null;
    st.editing = s.id;
    showEditor();
    window.scrollTo(0, 0);
    if (push !== false && bridge.pushUrl) bridge.pushUrl(); else if (bridge.setUrl) bridge.setUrl();
    st.base = snapshot();
    if (window.ADspaceGrow && window.ADspaceGrow.fit) {
      Array.prototype.forEach.call($('vsEditView').querySelectorAll('textarea'), function (t) { window.ADspaceGrow.fit(t); });
    }
    if (st.kept && st.kept.id === s.id) {
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
        '<div class="row' + (two ? ' fgrid' : '') + '">' +
          '<div><label class="field-label" for="vsV' + i + '">' + esc(SCENE_WORD[$('vsKind').value] || 'Visual') + '</label>' +
            '<textarea class="input" id="vsV' + i + '" rows="2" data-f="visual">' + esc(x.visual) + '</textarea></div>' +
          (two ? '<div><label class="field-label" for="vsL' + i + '">Script</label>' +
            '<textarea class="input" id="vsL' + i + '" rows="2" data-f="line">' + esc(x.line) + '</textarea></div>' : '') +
        '</div></div>';
    }).join('');
    Array.prototype.forEach.call(box.querySelectorAll('.vs-edit-scene'), function (row) {
      var i = Number(row.getAttribute('data-i'));
      Array.prototype.forEach.call(row.querySelectorAll('[data-f]'), function (t) {
        t.addEventListener('input', function () { st.draft[i][t.getAttribute('data-f')] = t.value; });
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
  $('vsAddScene').addEventListener('click', function () {
    if (st.draft.length >= 60) { say($('vsMsg'), SAID['too-many']); return; }
    st.draft.push({ id: null, visual: '', line: '' });
    paintDraftScenes();
    var last = $('vsV' + (st.draft.length - 1));
    if (last) last.focus();
  });
  $('vsCancel').addEventListener('click', function () { leaveEditor(); });
  $('vsSave').addEventListener('click', function () {
    /* A script written with AI is declared read before it is kept
       (2026-10-10). */
    if (st.ai && st.open && st.ai === st.open.id && window.ADspaceConfirm.ai) {
      window.ADspaceConfirm.ai.declare('script', 'Confirm and save', function () { saveScript(true); });
      return;
    }
    saveScript(false);
  });
  function saveScript(declared) {
    var m = $('vsMsg'), btn = $('vsSave'), s = st.open;
    var ref = $('vsRef').value.trim().replace(/^https:\/\//i, 'https://');
    if (ref && !/^https:\/\//.test(ref)) { say(m, SAID['bad-link']); $('vsRef').focus(); return; }
    var head = {
      kind: $('vsKind').value, title: $('vsTitle').value.trim(), reference_url: ref,
      platform: $('vsPlatform').value, language: $('vsLang').value,
      shoot_on: $('vsDate').value, shoot_time: $('vsTime').value, venue: $('vsVenue').value.trim(),
      duration_minutes: $('vsDur').value, cast_names: $('vsCast').value.trim(),
      context: CONTEXT_WORD[$('vsKind').value] ? $('vsContext').value.trim() : s.context || '',
      vo: $('vsKind').value === 'story' ? $('vsVo').value.trim() : s.vo || '',
      remarks: $('vsNotes').value.trim(), period: $('vsMonth').value
    };
    var scenes = st.draft.filter(function (x) { return x.visual.trim() || x.line.trim(); })
      .map(function (x) { return { id: x.id, visual: x.visual.trim(), line: $('vsKind').value === 'scenes' ? x.line.trim() : '' }; });
    btn.disabled = true;
    say(m, '');
    rpc('video_script_save', { p_id: s.id, p_head: head, p_scenes: scenes, p_version: s.version }).then(function (d) {
      btn.disabled = false;
      if (declared) {
        st.ai = null;
        if (bridge.log) bridge.log('script.saved', ((s.clients || {}).name || '') + ' · ' + codeOf(s),
          'Script written with AI, read and confirmed');
      }
      closeEditor();
      return readScript(s.id).then(function () {
        paintRecord();
        if (bridge.setUrl) bridge.setUrl();
        say($('vsCardMsg'), !d.changed ? 'No changes.' : 'Saved.', 'ok');
      });
    }).catch(function (e) {
      btn.disabled = false;
      if (e && e.message === 'stale') {
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
    'needs-update': 'This needs a database update.',
    'ai-not-set-up': 'AI needs its key in Supabase.',
    'ai-key': 'The AI key was refused. Check it in Supabase.',
    'ai-busy': 'The AI service is busy. Try again in a minute.',
    'ai-credit': 'The AI account has no credit. Top up in the Claude Console.',
    'ai-model': 'The script model name in Supabase is not recognised.',
    'ai-failed': 'No script came back. Try again.',
    'ai-incomplete': 'No script came back. Try again.',
    denied: 'This needs Video Scripts at Work.',
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
    var at = new Date(iso);
    if (isNaN(at.getTime())) return '';
    return ((at.getHours() % 12) || 12) + ':' + String(at.getMinutes()).padStart(2, '0') + (at.getHours() < 12 ? 'am' : 'pm');
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
      kind: $('vsKind').value, context: $('vsContext').value, vo: $('vsVo').value,
      scenes: st.draft.map(function (x) { return { id: x.id, visual: x.visual, line: x.line }; })
    };
  }
  function putWords(w) {
    if ($('vsKind').value !== w.kind) {
      $('vsKind').value = w.kind;
      $('vsKind').dispatchEvent(new Event('change', { bubbles: true }));
    }
    $('vsContext').value = w.context || '';
    $('vsVo').value = w.vo || '';
    st.draft = w.scenes.length ? w.scenes.map(function (x) { return { id: x.id || null, visual: x.visual || '', line: x.line || '' }; })
      : [{ id: null, visual: '', line: '' }];
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
    return {
      kind: kind, context: fill(d.draft.context), vo: fill(d.draft.vo),
      scenes: (d.draft.scenes || []).map(function (x) { return { id: null, visual: fill(x.visual), line: fill(x.line) }; })
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
    var btn = $('vsWrite'), s = st.open;
    if (!s || !may('work')) return;
    sayWrite('');
    btn.disabled = true;
    rpc('ai_script_left', {}).then(function (left) {
      btn.disabled = false;
      if (!left.left) { sayWrite(writeLimit(left)); return; }
      var kind = $('vsKind').value, plat = $('vsPlatform').value;
      var fields = [{ name: 'length', label: 'Video length', choices: LENGTHS, seg: true,
        value: keep('adspace-script-length:' + s.id) || '30' }];
      if (plat === 'rednote') fields.push({ name: 'safe', label: 'XHS Safe Mode', tick: true, value: false });
      fields.push({ name: 'notes', label: 'Notes for the script', rows: 4, required: false,
        placeholder: 'What the video is for, the product or offer, the call to action',
        value: keep('adspace-script-notes:' + s.id) });
      window.ADspaceConfirm.ask({
        title: 'Write with AI',
        body: (hasWords(kind) ? 'Replaces the script in these fields. ' : '') + left.left + (left.left === 1 ? ' script' : ' scripts') + ' left today.',
        go: 'Write', fields: fields
      }, function (v) {
        var notes = String(v.notes || '').trim();
        keep('adspace-script-notes:' + s.id, notes);
        keep('adspace-script-length:' + s.id, String(v.length || '30'));
        var before = sheetWords();
        var cur = sheetWords();
        var settle = function () {
          st.writing = null;
          if (st.open && st.open.id === s.id) { btn.disabled = false; writeWord(false); }
        };
        st.writing = s.id;
        btn.disabled = true;
        writeWord(true);
        db.functions.invoke('script-draft', { body: {
          script_id: s.id, kind: kind, title: $('vsTitle').value.trim(), platform: plat, language: $('vsLang').value,
          length: Number(v.length) || 30, venue: $('vsVenue').value.trim(),
          cast: $('vsCast').value.split(/[,，;\n]+/).filter(function (x) { return x.trim(); }).length,
          notes: notes, safe: plat === 'rednote' && v.safe === 'on',
          current: { context: CONTEXT_WORD[kind] ? cur.context : '', vo: kind === 'story' ? cur.vo : '',
                     scenes: cur.scenes.map(function (x) { return { visual: x.visual, line: kind === 'scenes' ? x.line : '' }; }) }
        } }).then(function (res) {
          var d = res && res.data;
          if (res.error || !d || d.error || !d.draft) { var x = new Error((d && d.error) || 'ai-failed'); x.d = d; throw x; }
          settle();
          var w = written(s, kind, d);
          var open = !$('vsEditView').hidden && st.editing === s.id;
          if (open) showWritten(w, before);
          else st.kept = { id: s.id, words: w };
        }).catch(function (e) {
          settle();
          if (st.open && st.open.id === s.id) sayWrite(writeSaid(e));
        });
      });
    }).catch(function (e) { btn.disabled = false; sayWrite(writeSaid(e)); });
  });

  /* ---- The PDF, for the crew on site --------------------------------------- */
  /* Preview PDF opens a tab at the press and puts the drawn file in it;
     Download (the ⋯) saves it under its own name, as a report's do. With
     two scripts or more in the month, either asks which. */
  function openTab() {
    var tab = null;
    try { tab = window.open('', '_blank'); } catch (e) { tab = null; }
    if (tab) { try { tab.document.title = 'PDF'; tab.document.body.textContent = 'Drawing the PDF…'; } catch (e) { /* still blank */ } }
    return tab;
  }
  function drawPdf(btn, save) {
    var many = st.series.length > 1;
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
        var name = c + ' Video Script ' + (whole ? codeOf(st.series[0]) + '-' + codeOf(st.series[st.series.length - 1]) : codeOf(st.open)) + '.pdf';
        say(m, save || (tab && !tab.closed) ? '' : 'Downloaded.', 'ok');
        window.ADspaceDocs.save(blob, name.replace(/[\\/:*?"<>|]+/g, ' '), tab);
      }).catch(function (e) {
        btn.disabled = false;
        if (window.ADspaceDocs.shut) window.ADspaceDocs.shut(tab);
        say(m, 'Not drawn. ' + said(e));
      });
    };
    if (!many) { go(false); return; }
    window.ADspaceConfirm.ask({ title: save ? 'Download' : 'Preview PDF', go: save ? 'Download' : 'Preview',
      field: { label: 'Scripts', choices: [['one', label(st.open)], ['all', 'The whole month (' + st.series.length + ' scripts)']], seg: false, value: 'all' }
    }, function (v) { go(v === 'all'); });
  }
  function gather(ids) {
    return Promise.all([
      db.from('video_scripts').select('*, clients(name)').in('id', ids).order('seq'),
      db.from('video_script_scenes').select('script_id, position, visual, line, vc, shot_at').in('script_id', ids).order('position')
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
        return s;
      });
    });
  }

  /* ---- The address -------------------------------------------------------- */
  function urlState() {
    if (!st.open || !st.open.id) return {};
    if (st.mode === 'month' && st.editing !== st.open.id) return { month: st.open.id };
    return st.editing === st.open.id ? { script: st.open.id, edit: '1' } : { script: st.open.id };
  }
  function enter() {
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
    if (q.get('month')) { openMonth(q.get('month'), false); return; }
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
