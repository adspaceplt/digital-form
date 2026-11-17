/*
 * Onboarding — the Welcome Kit and a colleague's onboarding checklist
 * (2026-11-17, Hiring and People release H2 step E1; the mockups the user
 * approved on 2026-11-17).
 *
 *   * The Welcome Kit: the first step of the onboarding page a new colleague
 *     meets at first sign-in, before the Handbook's required files
 *     (js/handbook.js draws it through `ADspaceOnboard.kit`). Their own facts
 *     from the record, the team's words from Settings; the Wi-Fi password and
 *     the door PIN always read "Please check with your direct manager."
 *   * Settings, Portal, Hiring: Welcome Kit (`openKit`, Business settings): the
 *     words a section at a time.
 *   * Team, a colleague's record, Onboarding (`mtab=onboarding`, the Hiring or
 *     Personnel part; `paneTeam`): the checklist (what the portal knows ticks
 *     itself, the rest ticked by hand), the assets issued and returned, and
 *     the internal entry and exit steps, each tick naming who and when.
 *
 * What a reader is sent is the database's decision (`welcome_kit_*`,
 * `onboarding_*`); no table is readable directly. Never a salary.
 */
(function () {
  'use strict';
  var API = window.ADspaceAPI;
  var db = API && API.client;
  if (!API || !API.configured || !db) return;

  var $ = function (id) { return document.getElementById(id); };
  var bridge = window.ADspaceAdmin || {};
  function esc(s) { return window.ADspaceWords.esc(s); }
  var UI = window.ADspaceState;
  var PEN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>';
  var PLUS = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>';
  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/></svg>';
  var DM_ASK = 'Please check with your direct manager.';

  function msg(id, text, kind) { var m = typeof id === 'string' ? $(id) : id; if (!m) return; m.textContent = text || ''; m.className = 'msg' + (kind && text ? ' ' + kind : ''); }
  function day(s) { return s ? (window.ADspaceClock.date(String(s).slice(0, 10)) || String(s)) : ''; }
  function longDay(s) {
    if (!s) return '';
    var d = String(s).slice(0, 10), C = window.ADspaceClock;
    var n = C.weekday ? C.weekday(d) : null;
    var w = n == null ? '' : ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][n];
    var M = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    var p = d.split('-');
    return (w ? w + ', ' : '') + Number(p[2]) + ' ' + M[Number(p[1]) - 1] + ' ' + p[0];
  }
  var SAID = {
    denied: 'You do not have permission to change this. Please ask an admin.',
    stale: 'Not saved. This record was changed by someone else. The latest version is now shown.',
    'bad-title': 'Enter a title of 2 to 60 characters.',
    'bad-body': 'Enter the section\'s text, 3,000 characters at most.',
    secret: 'Remove the password or PIN. New colleagues ask their direct manager for it.',
    'bad-count': 'The Welcome Kit has 12 sections at most. Delete a section first.',
    'bad-kind': 'Choose an item.',
    'bad-detail': 'Enter the detail, 200 characters at most.',
    'bad-date': 'Choose the date it was issued.',
    'bad-returned': 'The return date cannot be before the date it was issued.'
  };
  function said(r) {
    var d = (r && r.data) || {};
    if (d.error && SAID[d.error]) return SAID[d.error];
    if (r && r.error && /PGRST202|42883/.test(String(r.error.code || ''))) return 'This feature is not available yet. Please contact an admin.';
    return 'Not saved. Please try again.';
  }
  function rpc(fn, args) { return db.rpc(fn, args).then(function (r) { return r; }).catch(function (e) { return { error: e }; }); }

  /* A section's text: a line "Label: value" reads as a fact, any other as a
     paragraph, in the order written. */
  function sectionHtml(body) {
    var out = '', facts = '';
    var flush = function () { if (facts) { out += '<dl class="ovfacts wk-facts">' + facts + '</dl>'; facts = ''; } };
    String(body || '').split('\n').forEach(function (line) {
      var l = line.trim();
      if (!l) return;
      var at = l.indexOf(': ');
      if (at > 0 && at <= 40) {
        facts += '<div><dt>' + esc(l.slice(0, at)) + '</dt><dd>' + esc(l.slice(at + 2)) + '</dd></div>';
      } else { flush(); out += '<p class="wk-para">' + esc(l) + '</p>'; }
    });
    flush();
    return out;
  }

  // ---- The Welcome Kit, at first sign-in ------------------------------------
  /* Drawn into the onboarding page by js/handbook.js: `opts.step` and
     `opts.total` say where the kit stands among the steps; `opts.done` is
     called once the colleague has acknowledged it. */
  function kit(box, k, opts) {
    opts = opts || {};
    var first = String(k.name || '').trim().split(/\s+/)[0];
    var dm = k.dm ? k.dm.name + (k.dm.mobile && window.ADspaceCard && window.ADspaceCard.phone ? ' · ' + window.ADspaceCard.phone(k.dm.mobile)
      : k.dm.mobile ? ' · ' + k.dm.mobile : '') : '';
    var f = function (label, value, mute) { return '<div><dt>' + esc(label) + '</dt><dd' + (mute ? ' class="is-empty"' : '') + '>' + esc(value || 'Not set') + '</dd></div>'; };
    var mine = f('First day', longDay(k.first_day)) + f('Employee ID', k.staff_code) + f('Department', k.department) +
      f('Position', k.designation) + f('Direct manager', dm) + f('Company email', k.email) +
      f('Wi-Fi password', DM_ASK, true) + f('Door PIN', DM_ASK, true);
    var total = opts.total || 1, step = opts.step || 1;
    box.hidden = false;
    box.innerHTML = '<div class="wk">' +
      (total > 1 ? '<div class="hbo-progress"><span class="hbo-count">Step ' + step + ' of ' + total + '</span>' +
        '<span class="hbo-track" aria-hidden="true"><span style="width:' + Math.round(step / total * 100) + '%"></span></span></div>' : '') +
      '<h2 class="hbo-title wk-title">' + esc(first ? 'Welcome to ADspace, ' + first : 'Welcome to ADspace') + '</h2>' +
      '<section class="panel wk-card"><h3 class="wk-h">Your employment details</h3><dl class="ovfacts wk-facts">' + mine + '</dl></section>' +
      (k.sections || []).map(function (s) {
        return '<section class="panel wk-card"><h3 class="wk-h">' + esc(s.title) + '</h3>' + sectionHtml(s.body) + '</section>';
      }).join('') +
      '<div class="msg" id="wkGateMsg"></div>' +
      '<div class="wk-foot"><button class="btn btn-primary" id="wkAck" type="button">Acknowledge</button></div></div>';
    $('wkAck').addEventListener('click', function (e) {
      var b = e.currentTarget; b.disabled = true;
      msg('wkGateMsg', '');
      rpc('welcome_kit_ack', {}).then(function (r) {
        if (r.error || (r.data || {}).error) { b.disabled = false; msg('wkGateMsg', 'Not saved. Please try again.', 'err'); return; }
        if (opts.done) opts.done();
      });
    });
  }

  // ---- Settings: the Welcome Kit's words ---------------------------------------
  var wk = { rows: null, at: null, err: null, wired: false };
  function wkRead() {
    return rpc('welcome_kit_get', {}).then(function (r) {
      var d = r.data || {};
      wk.err = r.error || d.error ? r : null;
      wk.rows = wk.err ? null : (d.sections || []);
      wk.at = wk.err ? null : d.updated_at;
      wkPaint();
    });
  }
  function wkPaint() {
    var box = $('wkList');
    if (!box) return;
    if (wk.err) { UI.failLine(box, 'The Welcome Kit', said(wk.err), wkRead); return; }
    if (!wk.rows) { UI.skeleton(box, 3); return; }
    $('wkCount').textContent = wk.rows.length + (wk.rows.length === 1 ? ' section' : ' sections');
    box.innerHTML = wk.rows.map(function (s, i) {
      var line = String(s.body || '').split('\n').filter(function (x) { return x.trim(); })[0] || '';
      return '<div class="ind-row is-wk" data-i="' + i + '"><span class="wk-row-who"><span class="ind-name">' + esc(s.title) + '</span>' +
        '<span class="wk-row-line">' + esc(line) + '</span></span>' +
        '<span class="ind-acts"><button class="iconbtn" type="button" data-k="edit" aria-label="Edit ' + esc(s.title) + '" title="Edit">' + PEN + '</button>' +
        (wk.rows.length > 1 ? '<span class="team-act"><button class="kmenu-btn" type="button" data-k="menu" aria-label="More actions for ' + esc(s.title) + '" aria-expanded="false">' + DOTS + '</button>' +
          '<div class="kmenu" hidden role="menu"><button class="kmenu-item is-danger" data-g="6" type="button" role="menuitem" data-k="delete">Delete</button></div></span>' : '') +
        '</span></div>';
    }).join('');
  }
  function wkSave(list, done) {
    return rpc('welcome_kit_save', { p_sections: list, p_expected: wk.at }).then(function (r) {
      var d = r.data || {};
      if (d.error === 'stale') { wk.rows = d.sections || wk.rows; wk.at = d.updated_at; wkPaint(); }
      if (r.error || d.error) return said(r);
      wk.rows = d.sections; wk.at = d.updated_at;
      wkPaint();
      if (done) done();
      return '';
    });
  }
  function wkAsk(i) {
    var s = i == null ? null : wk.rows[i], n = wk.rows.length + (s ? 0 : 1);
    var places = [];
    for (var p = 1; p <= n; p++) places.push([String(p), String(p)]);
    window.ADspaceConfirm.ask({ title: s ? 'Edit ' + s.title : 'Add section', go: s ? 'Save' : 'Add section', wait: true,
      fields: [
        { name: 'title', label: 'Title', value: s ? s.title : '', placeholder: 'Your first day' },
        { name: 'body', label: 'Text', rows: 8, value: s ? s.body : '', placeholder: 'One point per line',
          note: 'Write "Label: value" to show a fact. Do not include a password or PIN.' },
        { name: 'place', label: 'Position', choices: places, value: String(s ? i + 1 : n) }] },
    function (v) {
      var list = wk.rows.slice();
      var row = { title: String(v.title || '').trim(), body: String(v.body || '').trim() };
      if (s) list.splice(i, 1);
      list.splice(Math.max(0, Math.min(list.length, Number(v.place) - 1)), 0, row);
      return wkSave(list, function () { msg('wkMsg', 'Saved.', 'ok'); });
    });
  }
  function openKit(opener) {
    var sh = $('wkSheet');
    if (!sh) return;
    if (!wk.wired) {
      wk.wired = true;
      $('wkCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
      $('wkClose').addEventListener('click', function () { $('wkCancel').click(); });
      $('wkAdd').addEventListener('click', function () { msg('wkMsg', ''); if (wk.rows) wkAsk(null); });
      $('wkList').addEventListener('click', function (e) {
        var b = e.target.closest('[data-k]'), row = b && b.closest('.ind-row');
        if (!row) return;
        var i = Number(row.getAttribute('data-i')), s = wk.rows[i];
        var k = b.getAttribute('data-k');
        if (k === 'menu') {
          e.stopPropagation();
          var mn = row.querySelector('.kmenu'), open = mn.hidden;
          Array.prototype.forEach.call(document.querySelectorAll('#wkList .kmenu'), function (m) { m.hidden = true; });
          mn.hidden = !open; b.setAttribute('aria-expanded', String(open));
          if (open) { if (window.ADspaceMenu.tidy) window.ADspaceMenu.tidy(mn); window.ADspaceMenu.place(b, mn); }
          return;
        }
        if (k === 'edit') { msg('wkMsg', ''); wkAsk(i); return; }
        if (k === 'delete') {
          window.ADspaceConfirm.ask({ title: 'Delete', tone: 'danger', go: 'Delete', wait: true,
            body: 'The ' + s.title + ' section will be deleted from the Welcome Kit. This cannot be undone.' },
          function () {
            var list = wk.rows.slice(); list.splice(i, 1);
            return wkSave(list, function () { msg('wkMsg', 'Deleted.', 'ok'); });
          });
        }
      });
    }
    msg('wkMsg', ''); wk.rows = null; wk.err = null; wkPaint();
    window.ADspaceSheet.show(sh, { opener: opener });
    wkRead();
  }

  // ---- Team: a colleague's Onboarding tab --------------------------------------
  var DOCS = [['nda', 'Non-Disclosure Agreement'], ['tp', 'TP1 / TP2 / TP3'], ['entryexit', 'Entry/Exit Form']];
  var STEPS = [['email', 'Company email'], ['systems', 'AutoCount HRMS, Bukku and Digital Portal'], ['files', 'Work files access'],
    ['cp22', 'CP22 / CP22A'], ['tp3', 'TP3 / PCB release'], ['device', 'Device setup / cleanup'], ['desk', 'Desk setup / cleanup']];
  var KINDS = [['access_card', 'Access card'], ['key', 'Key'], ['device', 'Company device'], ['namecard', 'Business namecard'],
    ['folder', 'Folder'], ['other', 'Other']];
  function kindWord(k) { return (KINDS.filter(function (x) { return x[0] === k; })[0] || [])[1] || k; }
  var team = { m: null, host: null, live: null, rec: null };
  function paneTeam(m, host, live) {
    team.m = m; team.host = host; team.live = live;
    if (!team.rec || team.rec.member !== m.id) team.rec = null;
    host.innerHTML = '<div class="panel mrec-card onb-card"><div class="msg" id="onbMsg"></div><div id="onbBox"></div></div>';
    if (!team.rec) UI.skeleton($('onbBox'), 4);
    rpc('onboarding_get', { p_member: m.id }).then(function (r) {
      if (!live()) return;
      var d = r.data || {};
      if (r.error || d.error) { UI.failLine($('onbBox'), 'The onboarding', said(r), function () { paneTeam(m, host, live); }); return; }
      d.member = m.id;
      team.rec = d;
      paint();
    });
  }
  function known(label, at, word, note) {
    return '<div class="onb-row is-known"><span class="onb-mark' + (at ? ' is-on' : '') + '" aria-hidden="true"></span>' +
      '<span class="onb-name">' + esc(label) + '</span>' +
      '<span class="onb-when">' + (at ? '<span class="chip-state is-ok">' + esc(word + ' ' + day(at)) + '</span>'
        : '<span class="chip-state is-off">' + esc(note || 'Not done') + '</span>') + '</span></div>';
  }
  function tick(side, key, label, ticks, words) {
    var t = ticks[side + ':' + key], id = 'onb-' + side + '-' + key;
    var who = t ? (t.by ? t.by + ', ' : '') + day(t.at) : '';
    return '<input class="onb-tick" type="checkbox" id="' + id + '" data-side="' + side + '" data-key="' + key + '"' + (t ? ' checked' : '') +
      ' aria-label="' + esc(words || label) + (who ? ', ticked by ' + esc(who) : '') + '"' + (who ? ' title="' + esc(who) + '"' : '') + '>';
  }
  function paint() {
    var box = $('onbBox'), r = team.rec;
    if (!box || !r) return;
    var k = r.known || {}, ticks = r.ticks || {};
    var hbTotal = Number(k.handbook_total) || 0, hbDone = Number(k.handbook_done) || 0;
    var rows = [
      known('Employment Offer', k.offer, 'Confirmed', 'Not confirmed'),
      known('Employment Contract', k.contract, 'Confirmed', 'Not confirmed'),
      known('Employee record form', k.record, 'Declared', 'Not declared'),
      known('NRIC (front and back)', k.nric, 'Uploaded', 'Not uploaded'),
      known('Welcome Kit', k.welcome, 'Acknowledged', k.welcome_due ? 'Not acknowledged' : 'Not required'),
      '<div class="onb-row is-known"><span class="onb-mark' + (hbTotal && hbDone >= hbTotal ? ' is-on' : '') + '" aria-hidden="true"></span>' +
        '<span class="onb-name">Handbook files</span><span class="onb-when"><span class="chip-state ' + (hbTotal && hbDone >= hbTotal ? 'is-ok' : 'is-off') + '">' +
        esc(hbTotal ? hbDone + ' of ' + hbTotal + ' acknowledged' : 'None required') + '</span></span></div>'
    ].concat(DOCS.map(function (x) {
      var t = ticks['doc:' + x[0]];
      return '<label class="onb-row" for="onb-doc-' + x[0] + '">' + tick('doc', x[0], x[1], ticks) +
        '<span class="onb-name">' + esc(x[1]) + '</span><span class="onb-when onb-by">' + (t ? esc(day(t.at) + (t.by ? ' · ' + t.by : '')) : '') + '</span></label>';
    }));
    var done = 0, all = 6 + DOCS.length;
    ['offer', 'contract', 'record', 'nric', 'welcome'].forEach(function (x) { if (k[x]) done++; });
    if (hbTotal && hbDone >= hbTotal) done++;
    DOCS.forEach(function (x) { if (ticks['doc:' + x[0]]) done++; });
    var assets = (r.assets || []);
    var grp = function (title, inner, act, cls) {
      return '<section class="readgroup' + (cls ? ' ' + cls : '') + '"><div class="readgroup-head"><h4 class="fsec-h">' + title + '</h4>' + (act || '') + '</div>' + inner + '</section>';
    };
    box.innerHTML = '<div class="onb-grid"><div class="onb-main readgroups">' +
      grp('Checklist <span class="tab-n">' + done + ' of ' + all + '</span>', '<div class="onb-list">' + rows.join('') + '</div>') +
      grp('Assets', assets.length ? '<div class="onb-assets">' +
          '<div class="onb-asset is-head" aria-hidden="true"><span>Item</span><span>Detail</span><span>Issued</span><span>Returned</span><span></span></div>' +
          assets.map(function (a, i) {
            return '<div class="onb-asset" data-i="' + i + '"><span class="onb-a-kind">' + esc(kindWord(a.kind)) + '</span>' +
              '<span class="onb-a-detail">' + esc(a.detail) + '</span>' +
              '<span class="onb-a-day"><span class="onb-a-lbl">Issued </span>' + esc(day(a.issued)) + '</span>' +
              '<span class="onb-a-day' + (a.returned ? '' : ' is-empty') + '"><span class="onb-a-lbl">Returned </span>' + (a.returned ? esc(day(a.returned)) : '—') + '</span>' +
              '<span class="onb-a-acts"><button class="iconbtn" type="button" data-a="edit" aria-label="Edit ' + esc(kindWord(a.kind)) + '" title="Edit">' + PEN + '</button>' +
              '<span class="team-act"><button class="kmenu-btn" type="button" data-a="menu" aria-label="More actions for ' + esc(kindWord(a.kind)) + '" aria-expanded="false">' + DOTS + '</button>' +
              '<div class="kmenu" hidden role="menu"><button class="kmenu-item is-danger" data-g="6" type="button" role="menuitem" data-a="delete">Delete</button></div></span></span></div>';
          }).join('') + '</div>' : '<p class="emptyline">No assets.</p>',
        '<button class="btn btn-sm btn-quiet" type="button" id="onbAddAsset">' + PLUS + 'Add asset</button>') +
      '</div><div class="onb-side readgroups">' +
      grp('Entry and exit', '<div class="onb-steps"><div class="onb-step is-head" aria-hidden="true"><span>Item</span><span>Entry</span><span>Exit</span></div>' +
        STEPS.map(function (x) {
          return '<div class="onb-step"><span class="onb-name">' + esc(x[1]) + '</span>' +
            '<span class="onb-cell">' + tick('entry', x[0], x[1], ticks, x[1] + ', entry') + '</span>' +
            '<span class="onb-cell">' + tick('exit', x[0], x[1], ticks, x[1] + ', exit') + '</span></div>';
        }).join('') + '</div>') +
      /* The colleague as an employee in Bukku (HR-SPEC decision 12). */
      '<div class="readgroup" id="onbBukku" hidden></div>' +
      '</div></div>';
    Array.prototype.forEach.call(box.querySelectorAll('.onb-tick'), function (c) {
      c.addEventListener('change', function () {
        c.disabled = true;
        rpc('onboarding_tick', { p_member: team.m.id, p_side: c.getAttribute('data-side'), p_key: c.getAttribute('data-key'), p_on: c.checked }).then(function (x) {
          var d = x.data || {};
          if (x.error || d.error) { c.checked = !c.checked; c.disabled = false; msg('onbMsg', said(x), 'err'); return; }
          team.rec.ticks = d.ticks; team.rec.updated_at = d.updated_at;
          paint();
          var f = $(c.id); if (f) f.focus();
        });
      });
    });
    if (window.ADspaceBukku && $('onbBukku')) window.ADspaceBukku.group($('onbBukku'), 'member', team.m.id);
    $('onbAddAsset').addEventListener('click', function () { msg('onbMsg', ''); askAsset(null); });
    Array.prototype.forEach.call(box.querySelectorAll('.onb-asset[data-i]'), function (row) {
      var i = Number(row.getAttribute('data-i'));
      row.querySelector('[data-a="edit"]').addEventListener('click', function () { msg('onbMsg', ''); askAsset(i); });
      var mb = row.querySelector('[data-a="menu"]');
      mb.addEventListener('click', function (e) {
        e.stopPropagation();
        var mn = row.querySelector('.kmenu'), open = mn.hidden;
        Array.prototype.forEach.call(box.querySelectorAll('.kmenu'), function (m) { m.hidden = true; });
        mn.hidden = !open; mb.setAttribute('aria-expanded', String(open));
        if (open) { if (window.ADspaceMenu.tidy) window.ADspaceMenu.tidy(mn); window.ADspaceMenu.place(mb, mn); }
      });
      row.querySelector('[data-a="delete"]').addEventListener('click', function () {
        row.querySelector('.kmenu').hidden = true;
        var a = team.rec.assets[i];
        window.ADspaceConfirm.ask({ title: 'Delete', tone: 'danger', go: 'Delete', wait: true,
          body: kindWord(a.kind) + ' (' + a.detail + ') will be deleted from the assets. This cannot be undone.' },
        function () {
          var list = team.rec.assets.slice(); list.splice(i, 1);
          return saveAssets(list, 'Deleted.');
        });
      });
    });
    if (window.ADspaceActs && window.ADspaceActs.scan) window.ADspaceActs.scan(box);
  }
  function saveAssets(list, said0) {
    return rpc('onboarding_assets_save', { p_member: team.m.id, p_assets: list, p_expected: team.rec.updated_at || null }).then(function (x) {
      var d = x.data || {};
      if (d.error === 'stale') { team.rec.assets = d.assets; team.rec.ticks = d.ticks; team.rec.updated_at = d.updated_at; paint(); }
      if (x.error || d.error) return said(x);
      team.rec.assets = d.assets; team.rec.updated_at = d.updated_at;
      paint();
      msg('onbMsg', said0, 'ok');
      return '';
    });
  }
  function askAsset(i) {
    var a = i == null ? null : team.rec.assets[i];
    var today = window.ADspaceClock.today();
    window.ADspaceConfirm.ask({ title: a ? 'Edit asset' : 'Add asset', go: a ? 'Save' : 'Add asset', wait: true,
      fields: [
        { name: 'kind', label: 'Item', choices: KINDS, value: a ? a.kind : 'access_card' },
        { name: 'detail', label: 'Detail', value: a ? a.detail : '', placeholder: 'Serial No., model or location' },
        { name: 'issued', label: 'Issued', type: 'date', value: a ? a.issued : today, half: true },
        { name: 'returned', label: 'Returned', type: 'date', value: a && a.returned ? a.returned : '', required: false }],
      check: function (v) {
        if (!String(v.detail || '').trim()) return 'Enter the detail.';
        if (!v.issued) return 'Choose the date it was issued.';
        if (v.returned && v.returned < v.issued) return SAID['bad-returned'];
        return '';
      } },
    function (v) {
      var row = { kind: v.kind, detail: String(v.detail || '').trim(), issued: v.issued };
      if (v.returned) row.returned = v.returned;
      var list = team.rec.assets.slice();
      if (a) list[i] = row; else list.push(row);
      return saveAssets(list, 'Saved.');
    });
  }

  window.ADspaceOnboard = { kit: kit, openKit: openKit, paneTeam: paneTeam, sectionHtml: sectionHtml };
})();
