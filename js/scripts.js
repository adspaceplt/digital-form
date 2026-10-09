/* Video Scripts (2026-10-09): a shoot's scripts, one a video, read and
 * approved by the client online and printed for the crew on site.
 *
 * The user: "a script table covers one video, hence there is a # … three
 * different types of script, detailed scenes / products + scenes / story +
 * VO. VC# is the video clip number on camera … one digital similar as content
 * review able to view online, another is export pdf for on-site use."
 *
 * The list is a card a client, a row a video (V1, V2… in its shoot). A video
 * opens as a record: the header facts, the script as the client reads it,
 * and on the day each scene's tick and clip number (VC#). Edit opens the
 * whole script in a sheet; Add next video makes the next number of the same
 * shoot with its header copied. Share shows it on the client's page
 * (`/script/?k=`), where it is approved or changes are asked for under a
 * typed name. Every write is a function (`video_script_*`,
 * 2026-10-09-video-scripts.sql); the PDF is drawn here, never stored.
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
  var KIND_WORD = {};
  KINDS.forEach(function (k) { KIND_WORD[k[0]] = k[1]; });
  var CONTEXT_WORD = { products: 'Products and context', story: 'Hook and story' };
  var SCENE_WORD = { scenes: 'Visual', products: 'Scene', story: 'Scene' };
  var PLATFORMS = ['Instagram', 'TikTok', 'Facebook', 'rednote', 'YouTube'];
  var LANGS = ['English', 'Chinese', 'Malay', 'English and Chinese'];
  var DURATIONS = [30, 60, 90, 120, 180, 240, 300, 360, 480, 600, 720];
  var MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
  var STATE = {
    draft: ['Draft', 'is-off'], shared: ['With client', 'is-warn'],
    approved: ['Approved', 'is-ok'], changes: ['Changes requested', 'is-warn']
  };
  var ICON = {
    dots: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="5" cy="12" r="1.6" fill="currentColor"/><circle cx="12" cy="12" r="1.6" fill="currentColor"/><circle cx="19" cy="12" r="1.6" fill="currentColor"/></svg>',
    plus: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>',
    file: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M12 12v6"/><path d="m9 15 3 3 3-3"/></svg>',
    copy: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/></svg>',
    pen: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 20h4L19 9l-4-4L4 16z"/></svg>',
    up: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 14 6-6 6 6"/></svg>',
    down: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 10 6 6 6-6"/></svg>',
    x: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>',
    out: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 4h6v6"/><path d="M20 4 11 13"/><path d="M19 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1h5"/></svg>'
  };

  var st = { list: [], decided: {}, clients: [], loaded: false, open: null, scenes: [], reviews: [],
             series: [], key: null, draft: [], idem: null, find: '' };

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
  function label(s) { return 'V' + s.video_no + (s.title ? ' · ' + s.title : ''); }
  function typedName(s) { return s.title ? s.title : 'V' + s.video_no; }
  function uuid() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    return 'x' + Date.now() + Math.random().toString(16).slice(2);
  }

  /* A refusal in the team's words. */
  var SAID = {
    denied: 'This needs Video Scripts at Work.',
    'client-scope': 'This client is outside your access.',
    'not-found': 'This script is no longer available.',
    'bad-kind': 'Choose the type of script.',
    'bad-title': 'A title is 200 characters at most.',
    'bad-link': 'A reference link starts with https://.',
    'bad-duration': 'Choose a duration between 5 minutes and 24 hours.',
    'bad-date': 'Choose a date from 14 Aug 2023.',
    'too-long': 'A field is too long to save.',
    'too-many': 'A script holds 60 scenes at most.',
    'bad-scenes': 'The scenes could not be read.',
    stale: 'Somebody changed this script. It has been read again; make the change once more.',
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

  /* Where a video stands: a draft, with the client, or the client's decision
     on the round on show. */
  function stateOf(s, decision) {
    if (s.status !== 'shared') return 'draft';
    return decision ? decision.decision : 'shared';
  }
  function chip(key) {
    var w = STATE[key] || STATE.draft;
    return '<span class="chip-state ' + w[1] + '">' + esc(w[0]) + '</span>';
  }

  /* ---- The list ------------------------------------------------------------ */
  function load() {
    var box = $('vsList');
    if (!st.loaded) UI.skeleton(box, 4);
    return db.from('video_scripts')
      .select('id, client_id, series_id, video_no, kind, title, status, round, shoot_on, venue, updated_at, created_at, clients(name, client_code)')
      .order('created_at', { ascending: false })
      .then(function (r) {
        if (r.error) throw r.error;
        st.list = r.data || [];
        var ids = st.list.map(function (s) { return s.id; });
        /* The decisions for every video listed, in one read. */
        return ids.length
          ? db.from('video_script_reviews').select('script_id, round, decision, reviewer, note, created_at')
              .in('script_id', ids).order('created_at', { ascending: false })
          : { data: [] };
      }).then(function (r) {
        if (r.error) throw r.error;
        st.decided = {};
        var rnd = {};
        st.list.forEach(function (s) { rnd[s.id] = s.round; });
        (r.data || []).forEach(function (d) {
          if (d.round === rnd[d.script_id] && !st.decided[d.script_id]) st.decided[d.script_id] = d;
        });
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
      return [s.title, s.venue, s.clients && s.clients.name, s.clients && s.clients.client_code, 'v' + s.video_no]
        .join(' ').toLowerCase().indexOf(q) > -1;
    });
  }

  function paint() {
    var box = $('vsList');
    if ($('vsNew')) $('vsNew').hidden = !may('work');
    var list = shown();
    var all = st.list.length;
    $('vsCount').textContent = !all ? '' : list.length !== all ? list.length + ' of ' + all
      : all + (all === 1 ? ' video' : ' videos');
    box.innerHTML = '';
    if (!all) {
      UI.emptyLine(box, 'No scripts.', may('work') ? 'New script' : '', function () { openNew($('vsNew')); });
      return;
    }
    if (!list.length) {
      UI.emptyLine(box, 'No matches.', 'Clear the search', function () { $('vsFind').value = ''; st.find = ''; paint(); });
      return;
    }
    var GRP = window.ADspaceGroup;
    var byClient = {}, order = [];
    list.forEach(function (s) {
      if (!byClient[s.client_id]) { byClient[s.client_id] = []; order.push(s.client_id); }
      byClient[s.client_id].push(s);
    });
    order.sort(function (a, b) {
      var na = (byClient[a][0].clients || {}).name || '', nb = (byClient[b][0].clients || {}).name || '';
      return na.localeCompare(nb, 'en', { sensitivity: 'base' });
    });
    order.forEach(function (cid) {
      var rows = byClient[cid].slice().sort(function (a, b) {
        var da = a.shoot_on || '9999', dbb = b.shoot_on || '9999';
        return dbb.localeCompare(da) || String(a.series_id).localeCompare(String(b.series_id)) || a.video_no - b.video_no;
      });
      var c = rows[0].clients || {};
      box.appendChild(GRP.section({
        route: 'scripts', key: cid, name: c.name || 'Client', count: rows.length,
        shut: !st.find && GRP.shut('scripts', cid, false, rows.length === list.length),
        table: function () {
          var table = GRP.table('vs-row', ['Video', 'Shoot', 'State']);
          GRP.more(table, rows, 30, 'videos', rowOf);
          return table;
        }
      }));
    });
  }

  function rowOf(s) {
    var row = document.createElement('button');
    row.type = 'button';
    row.className = 'crm-row vs-row';
    row.setAttribute('data-id', s.id);
    var shoot = [dayWord(s.shoot_on), s.venue].filter(Boolean).join(' · ');
    row.innerHTML =
      '<span class="vs-c-name"><b>' + esc(label(s)) + '</b><small>' + esc(KIND_WORD[s.kind] || '') + '</small></span>' +
      '<span class="vs-c-shoot">' + (shoot ? esc(shoot) : '<span class="mute">Not set</span>') + '</span>' +
      '<span class="vs-c-state">' + chip(stateOf(s, st.decided[s.id])) + '</span>';
    row.addEventListener('click', function () { openScript(s.id, true); });
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
    rpc('video_script_create', { p_client: client, p_kind: $('vsNewKind').value, p_from: null, p_idem: st.idem })
      .then(function (d) {
        btn.disabled = false;
        window.ADspaceSheet.clean();
        window.ADspaceSheet.close();
        st.loaded = false;
        openScript(d.id, true, true);
      }).catch(function (e) { btn.disabled = false; say(m, said(e)); });
  });

  /* ---- One video ------------------------------------------------------------- */
  function openScript(id, push, edit) {
    st.open = { id: id };
    $('vsListView').hidden = true;
    $('vsRecord').hidden = false;
    window.scrollTo(0, 0);
    if (push && bridge.pushUrl) bridge.pushUrl(); else if (bridge.setUrl) bridge.setUrl();
    UI.skeleton($('vsRecBody'), 3);
    return readScript(id).then(function () {
      paintRecord();
      if (edit && may('work')) openEdit($('vsRecMore'));
    }).catch(function (e) {
      if (e && e.message === 'not-found') {
        backToList();
        say($('vsListMsg'), 'That script is no longer available.', 'warn');
        return;
      }
      UI.failLine($('vsRecBody'), 'The script', said(e), function () { openScript(id); });
    });
  }
  function readScript(id) {
    return db.from('video_scripts').select('*, clients(name, client_code)').eq('id', id).maybeSingle().then(function (r) {
      if (r.error) throw r.error;
      if (!r.data) throw new Error('not-found');
      st.open = r.data;
      return Promise.all([
        db.from('video_script_scenes').select('id, position, visual, line, vc, shot_at, shot_by').eq('script_id', id).order('position'),
        db.from('video_script_reviews').select('id, round, decision, note, reviewer, created_at').eq('script_id', id).order('created_at', { ascending: false }),
        db.from('video_scripts').select('id, video_no, title, status, round').eq('series_id', st.open.series_id).order('video_no')
      ]);
    }).then(function (rs) {
      rs.forEach(function (x) { if (x.error) throw x.error; });
      st.scenes = rs[0].data || [];
      st.reviews = rs[1].data || [];
      st.series = rs[2].data || [];
    });
  }
  function decisionOf(s) {
    s = s || st.open;
    return st.reviews.filter(function (r) { return r.round === s.round; })[0] || null;
  }
  function askedOf(s) {
    s = s || st.open;
    return st.reviews.filter(function (r) { return r.round === s.round - 1 && r.decision === 'changes'; })[0] || null;
  }
  function backToList() {
    st.open = null;
    $('vsRecord').hidden = true;
    $('vsListView').hidden = false;
    if (bridge.setUrl) bridge.setUrl();
    load();
  }
  $('vsBack').addEventListener('click', function () { backToList(); });

  function facts(s) {
    var f = [];
    f.push(['Platform', s.platform || '']);
    f.push(['Language', s.language || '']);
    f.push(['Shooting date', [dayWord(s.shoot_on), timeWord(s.shoot_time)].filter(Boolean).join(', ')]);
    f.push(['Venue', s.venue || '']);
    f.push(['Estimated duration', durWord(s.duration_minutes)]);
    f.push(['Cast', s.cast_names || '']);
    return '<dl class="facts vs-facts">' + f.map(function (x) {
      return '<div><dt>' + esc(x[0]) + '</dt><dd>' + (x[1] ? esc(x[1]) : '<span class="mute">Not set</span>') + '</dd></div>';
    }).join('') + '</dl>';
  }

  /* The client's word on the round on show, or the request this round
     answers. */
  function decisionLine(s) {
    var d = decisionOf(s), a = askedOf(s);
    if (s.status !== 'shared') return '';
    if (d && d.decision === 'approved') {
      return '<p class="vs-said"><span class="chip-state is-ok">Approved</span> by ' + esc(d.reviewer) + ' · ' + esc(dayWord(d.created_at)) + '</p>';
    }
    if (d && d.decision === 'changes') {
      return '<div class="vs-said is-ask"><p><span class="chip-state is-warn">Changes requested</span> by ' + esc(d.reviewer) + ' · ' + esc(dayWord(d.created_at)) + '</p>' +
        '<p class="vs-note">' + esc(d.note || '') + '</p></div>';
    }
    if (a) {
      return '<div class="vs-said"><p>Round ' + s.round + ' answers the request by ' + esc(a.reviewer) + ' · ' + esc(dayWord(a.created_at)) + '</p>' +
        '<p class="vs-note">' + esc(a.note || '') + '</p></div>';
    }
    return '';
  }

  /* The script as the client reads it, with the crew's tick and clip number
     on each scene. */
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
        '<span class="vs-vc">' + (work
          ? '<input class="input input-sm" type="text" maxlength="40" value="' + esc(sc.vc || '') + '" aria-label="Clip number for scene ' + (i + 1) + '" placeholder="VC#" data-vc>'
          : esc(sc.vc || '—')) + '</span>' +
        '<span class="vs-shot"><input type="checkbox" ' + (sc.shot_at ? 'checked ' : '') + (work ? '' : 'disabled ') +
          'aria-label="Scene ' + (i + 1) + ' shot" data-shot></span>' +
      '</div>';
    }).join('') + '</div>';
  }
  function scriptBody(s) {
    var out = '';
    if (s.reference_url) {
      out += '<p class="vs-ref"><span class="field-label">Reference</span> <a class="plink" href="' + esc(s.reference_url) +
        '" target="_blank" rel="noopener">' + esc(s.reference_url.replace(/^https:\/\//, '')) + ' ' + ICON.out + '</a></p>';
    }
    if (CONTEXT_WORD[s.kind]) {
      out += '<section class="vs-block"><h4 class="fsec-h">' + esc(CONTEXT_WORD[s.kind]) + '</h4>' +
        '<p class="vs-prose">' + (s.context ? esc(s.context) : '<span class="mute">Not written</span>') + '</p></section>';
    }
    out += '<section class="vs-block"><h4 class="fsec-h">Scenes</h4>' + sceneRows(s) + '</section>';
    if (s.kind === 'story') {
      var work = may('work');
      out += '<section class="vs-block"><h4 class="fsec-h">Script (read here)</h4>' +
        '<p class="vs-prose">' + (s.vo ? esc(s.vo) : '<span class="mute">Not written</span>') + '</p>' +
        '<div class="vs-vo" data-vo>' +
          '<label class="field-label" for="vsVoVc">VC#</label>' +
          (work ? '<input class="input input-sm" id="vsVoVc" type="text" maxlength="40" value="' + esc(s.vo_vc || '') + '" placeholder="VC#">' : '<span>' + esc(s.vo_vc || '—') + '</span>') +
          '<label class="tickline"><input type="checkbox" id="vsVoShot" ' + (s.vo_shot_at ? 'checked ' : '') + (work ? '' : 'disabled ') + '> <span>Shot</span></label>' +
        '</div></section>';
    }
    out += '<section class="vs-block"><h4 class="fsec-h">Notes</h4><p class="vs-prose">' +
      (s.remarks ? esc(s.remarks) : '<span class="mute">None</span>') + '</p></section>';
    return out;
  }

  function moreMenu(s) {
    var items = '';
    if (may('work')) {
      items += '<button class="kmenu-item" data-a="edit" type="button"><b>Edit</b></button>';
      items += '<button class="kmenu-item" data-a="reset" type="button"><b>Reset client link</b></button>';
    }
    if (may('manage')) items += '<button class="kmenu-item is-danger" data-a="del" type="button"><b>Delete</b></button>';
    if (!items) return '';
    return '<button class="kmenu-btn" id="vsRecMore" type="button" aria-label="More actions" aria-expanded="false">' + ICON.dots + '</button>' +
      '<div class="kmenu" data-menu hidden>' + items + '</div>';
  }

  function paintRecord() {
    var s = st.open;
    var c = s.clients || {};
    var key = stateOf(s, decisionOf(s));
    $('vsRecName').textContent = label(s);
    $('vsRecMeta').textContent = [c.name, KIND_WORD[s.kind]].filter(Boolean).join(' · ');
    var ctl = $('vsRecCtl');
    ctl.innerHTML = chip(key) +
      '<button class="btn btn-sm btn-icon" type="button" data-a="pdf" aria-label="Download PDF">' + ICON.file + '<span class="vs-pdf-long">Download PDF</span><span class="vs-pdf-short">PDF</span></button>' +
      moreMenu(s);
    var acts = '';
    if (may('work')) {
      acts = s.status === 'shared'
        ? '<button class="btn btn-warn" type="button" data-a="unshare">Unshare</button>'
        : '<button class="btn btn-go" type="button" data-a="share">Share with client</button>';
    }
    $('vsRecActs').innerHTML = acts;
    $('vsRecActs').hidden = !acts;
    paintLink();
    $('vsRecBody').innerHTML = decisionLine(s) + '<section class="panel vs-sheetview">' + facts(s) + scriptBody(s) + '</section>';
    paintSeries();
    wireRecord();
  }

  /* The other videos of the shoot, and Add next video. */
  function paintSeries() {
    var box = $('vsSeries');
    box.innerHTML = '<h3 class="railtitle">This shoot</h3>' + st.series.map(function (x) {
      var on = x.id === st.open.id;
      return '<button class="railrow vs-vrow' + (on ? ' is-on' : '') + '" type="button" data-v="' + esc(x.id) + '"' +
        (on ? ' aria-current="page"' : '') + '><span>' + esc(label(x)) + '</span></button>';
    }).join('') +
      (may('work') ? '<button class="btn btn-sm vs-next" type="button" id="vsNextVideo">' + ICON.plus + 'Add next video</button>' : '');
    Array.prototype.forEach.call(box.querySelectorAll('[data-v]'), function (b) {
      b.addEventListener('click', function () {
        var id = b.getAttribute('data-v');
        if (id !== st.open.id) openScript(id, true);
      });
    });
    if ($('vsNextVideo')) $('vsNextVideo').addEventListener('click', function () { nextVideo($('vsNextVideo')); });
  }

  function wireRecord() {
    var on = function (root, a, fn) { var b = root.querySelector('[data-a="' + a + '"]'); if (b) b.addEventListener('click', function () { fn(b); }); };
    var ctl = $('vsRecCtl');
    on(ctl, 'pdf', function (b) { downloadPdf(b); });
    on($('vsRecActs'), 'share', function (b) { share(true, b); });
    on($('vsRecActs'), 'unshare', function (b) { share(false, b); });
    var mb = $('vsRecMore');
    if (mb) {
      var menu = ctl.querySelector('[data-menu]');
      mb.addEventListener('click', function (e) {
        e.stopPropagation();
        var open = menu.hidden;
        menu.hidden = !open;
        mb.setAttribute('aria-expanded', String(open));
        if (open) window.ADspaceMenu.place(mb, menu);
      });
      on(menu, 'edit', function () { shutMenu(); openEdit(mb); });
      on(menu, 'reset', function () { shutMenu(); resetLink(); });
      on(menu, 'del', function () { shutMenu(); remove(); });
    }
    Array.prototype.forEach.call($('vsRecBody').querySelectorAll('[data-scene]'), function (row) {
      var id = row.getAttribute('data-scene');
      var vc = row.querySelector('[data-vc]'), shot = row.querySelector('[data-shot]');
      if (vc) vc.addEventListener('change', function () { tick(id, null, vc.value, vc); });
      if (shot) shot.addEventListener('change', function () { tick(id, shot.checked, null, shot); });
    });
    if ($('vsVoVc')) $('vsVoVc').addEventListener('change', function () { tick(null, null, $('vsVoVc').value, $('vsVoVc')); });
    if ($('vsVoShot')) $('vsVoShot').addEventListener('change', function () { tick(null, $('vsVoShot').checked, null, $('vsVoShot')); });
  }
  function shutMenu() {
    var m = $('vsRecCtl').querySelector('[data-menu]'), b = $('vsRecMore');
    if (m) m.hidden = true;
    if (b) b.setAttribute('aria-expanded', 'false');
  }
  document.addEventListener('click', function (e) {
    if (!e.target.closest || !e.target.closest('#vsRecCtl .kmenu, #vsRecMore')) shutMenu();
  });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') shutMenu(); });
  if (window.ADspaceMenu) window.ADspaceMenu.onScroll(shutMenu);

  /* On the day: a tick or a clip number, saved as it changes, put back on a
     refusal. */
  function tick(sceneId, on, vc, el) {
    var m = $('vsRecMsg');
    say(m, '');
    rpc('video_script_shot', { p_script: st.open.id, p_scene: sceneId, p_on: on, p_vc: vc }).then(function () {
      var sc = sceneId && st.scenes.filter(function (x) { return x.id === sceneId; })[0];
      var stamp = new Date().toISOString();
      if (sc) { if (on != null) sc.shot_at = on ? stamp : null; if (vc != null) sc.vc = vc.trim() || null; }
      if (!sceneId) { if (on != null) st.open.vo_shot_at = on ? stamp : null; if (vc != null) st.open.vo_vc = vc.trim() || null; }
      say(m, 'Saved.', 'ok');
    }).catch(function (e) {
      if (el.type === 'checkbox') el.checked = !el.checked;
      else {
        var sc2 = sceneId && st.scenes.filter(function (x) { return x.id === sceneId; })[0];
        el.value = sceneId ? (sc2 && sc2.vc) || '' : st.open.vo_vc || '';
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
      $('vsLinkBox').hidden = !has;
      if (has) { $('vsLink').value = clientLink(st.key); $('vsOpen').href = clientLink(st.key); }
      $('vsLinkTools').hidden = !has && $('vsRecActs').hidden;
    };
    show();
    if (st.keyFor === s.client_id || st.keyTried === s.client_id) return;
    st.keyTried = s.client_id;
    withKey(false).then(show).catch(show);
  }
  $('vsCopy').addEventListener('click', function () {
    if (st.key) window.ADspaceCopy.to($('vsCopy'), clientLink(st.key));
  });
  function share(on, btn, quiet) {
    var m = $('vsRecMsg');
    var go = function () {
      if (btn) btn.disabled = true;
      rpc('video_script_share', { p_ids: [st.open.id], p_on: on }).then(function () {
        return readScript(st.open.id);
      }).then(function () {
        paintRecord();
        say($('vsRecMsg'), on ? '' : 'Unshared.', 'ok');
        if (on) undoBar('Shared with the client.', function () { share(false, null, true); }, $('vsRecMsg'));
      }).catch(function (e) { if (btn) btn.disabled = false; say(m, said(e)); });
    };
    if (on || quiet) { go(); return; }
    window.ADspaceConfirm.ask({ title: 'Unshare?', body: 'The client no longer sees this video. Its decisions are kept.',
      go: 'Unshare', tone: 'warn' }, go);
  }
  function resetLink() {
    window.ADspaceConfirm.ask({ title: 'Reset client link?',
      body: 'The link the client holds stops working. Send them the new one.', go: 'Reset', tone: 'warn' }, function () {
      withKey(true).then(function () { paintLink(); say($('vsRecMsg'), 'Link reset. Copy the new link for the client.', 'ok'); })
        .catch(function (e) { say($('vsRecMsg'), said(e)); });
    });
  }
  function remove() {
    var s = st.open;
    var nm = typedName(s);
    window.ADspaceConfirm.ask({
      title: 'Delete',
      body: label(s) + ', its scenes and the client\'s decisions will be deleted. There is no restore.',
      go: 'Delete', tone: 'danger',
      field: { label: 'Type ' + (s.title ? 'the title' : nm) + ' to confirm', match: nm, mismatch: 'The name does not match.' }
    }, function (typed) {
      rpc('video_script_delete', { p_id: s.id, p_typed: typed }).then(function () {
        backToList();
        say($('vsListMsg'), 'Deleted.', 'ok');
      }).catch(function (e) { say($('vsRecMsg'), said(e)); });
    });
  }
  function nextVideo(btn) {
    btn.disabled = true;
    rpc('video_script_create', { p_client: st.open.client_id, p_kind: st.open.kind, p_from: st.open.id, p_idem: uuid() })
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

  function openEdit(opener) {
    var s = st.open;
    say($('vsMsg'), '');
    $('vsSheetTitle').textContent = 'Edit ' + label(s);
    $('vsKind').value = s.kind;
    $('vsKind').dispatchEvent(new Event('change', { bubbles: true }));
    $('vsTitle').value = s.title || '';
    $('vsRef').value = s.reference_url || '';
    fillSelect($('vsPlatform'), PLATFORMS, s.platform);
    fillSelect($('vsLang'), LANGS, s.language);
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
    window.ADspaceSheet.show($('vsSheet'), { opener: opener || null });
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
  $('vsCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
  $('vsClose').addEventListener('click', function () { $('vsCancel').click(); });
  $('vsSave').addEventListener('click', function () {
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
      remarks: $('vsNotes').value.trim()
    };
    var scenes = st.draft.filter(function (x) { return x.visual.trim() || x.line.trim(); })
      .map(function (x) { return { id: x.id, visual: x.visual.trim(), line: $('vsKind').value === 'scenes' ? x.line.trim() : '' }; });
    btn.disabled = true;
    say(m, '');
    rpc('video_script_save', { p_id: s.id, p_head: head, p_scenes: scenes, p_version: s.version }).then(function (d) {
      btn.disabled = false;
      window.ADspaceSheet.clean();
      window.ADspaceSheet.close();
      return readScript(s.id).then(function () {
        paintRecord();
        say($('vsRecMsg'), !d.changed ? 'No changes.' : d.round > s.round ? 'Saved. The client is asked again (round ' + d.round + ').' : 'Saved.', 'ok');
      });
    }).catch(function (e) {
      btn.disabled = false;
      if (e && e.message === 'stale') {
        readScript(s.id).then(function () { paintRecord(); });
      }
      say(m, said(e));
    });
  });

  /* ---- The PDF, for the crew on site --------------------------------------- */
  function downloadPdf(btn) {
    var many = st.series.length > 1;
    var go = function (whole) {
      var m = $('vsRecMsg');
      btn.disabled = true;
      say(m, 'Drawing the PDF…', 'ok');
      var ids = whole ? st.series.map(function (x) { return x.id; }) : [st.open.id];
      gather(ids).then(function (videos) {
        return window.ADspaceScriptPdf.draw(videos);
      }).then(function (blob) {
        btn.disabled = false;
        say(m, '');
        var c = (st.open.clients || {}).name || 'Client';
        var name = c + ' Video Script ' + (whole ? 'V1-V' + st.series[st.series.length - 1].video_no : 'V' + st.open.video_no) + '.pdf';
        window.ADspaceDocs.save(blob, name.replace(/[\\/:*?"<>|]+/g, ' '), window.ADspaceDocs.tabFor ? window.ADspaceDocs.tabFor() : null);
      }).catch(function (e) {
        btn.disabled = false;
        say(m, 'Not drawn. ' + said(e));
      });
    };
    if (!many) { go(false); return; }
    window.ADspaceConfirm.ask({ title: 'Download PDF', go: 'Download',
      field: { label: 'Videos', choices: [['one', label(st.open)], ['all', 'The whole shoot (' + st.series.length + ' videos)']], seg: false, value: 'all' }
    }, function (v) { go(v === 'all'); });
  }
  function gather(ids) {
    return Promise.all([
      db.from('video_scripts').select('*, clients(name)').in('id', ids).order('video_no'),
      db.from('video_script_scenes').select('script_id, position, visual, line, vc').in('script_id', ids).order('position')
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
        return s;
      });
    });
  }

  /* ---- The address -------------------------------------------------------- */
  function urlState() { return st.open && st.open.id ? { script: st.open.id } : {}; }
  function enter() {
    say($('vsListMsg'), '');
    say($('vsRecMsg'), '');
    var id = new URLSearchParams(location.search).get('script');
    if (id) { openScript(id, false); return; }
    st.open = null;
    $('vsRecord').hidden = true;
    $('vsListView').hidden = false;
    if (bridge.setUrl) bridge.setUrl();
    load();
  }

  window.ADspaceScripts = { enter: enter, urlState: urlState, reload: load };
  if (bridge.scriptsReady) bridge.scriptsReady();
})();
