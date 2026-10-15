/* ADspace Digital Portal — a client's checklists (2026-10-15).
 *
 * The team's New Client Onboarding Checklist and Pre-Advertising Checklist,
 * kept on the client's record item by item, once a client (the user,
 * 2026-10-15). The form is the database's (`checklist_template`, kept with
 * the checklist once started); every item is recorded on the press through
 * `client_checklist_set`, signed off through `client_checklist_step`:
 * prepared by one colleague, reviewed by another, which ticks the client's
 * month's check of the same name in My Work. Download draws it as the
 * team's form, never stored.
 *
 * crm.js calls mount(host, ctx): ctx { db, client, msg(id, text, kind),
 * undo(text, fn, host) }.
 */
(function () {
  'use strict';
  var $ = function (id) { return document.getElementById(id); };
  var esc = function (s) {
    return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  };
  var KINDS = [['onboarding', 'New Client Onboarding Checklist'], ['pre_ads', 'Pre-Advertising Checklist']];
  var STATE = { open: ['In progress', 'is-warn'], prepared: ['Waiting for review', 'is-warn'], signed: ['Signed off', 'is-ok'] };
  var SAID = {
    denied: 'This needs Clients at Work.', 'client-scope': 'This client is outside your access.',
    locked: 'This checklist is waiting for review or signed off. Send it back or reopen it to change it.',
    'bad-value': 'That answer is not one the checklist takes.', 'bad-item': 'This checklist has changed. Open it again.',
    'too-long': 'A note is 1,000 characters at most.', own: 'Somebody other than the person who prepared it signs it off.',
    'not-started': 'Nothing has been recorded on this checklist.',
    'no-analysis': 'Write with AI reads the client\'s confirmed Brand analysis. Confirm one on the Brand tab first.',
    'ai-not-set-up': 'AI needs its key in Supabase.', 'ai-key': 'AI refused its key in Supabase.',
    'ai-busy': 'AI is busy. Try again in a minute.', 'ai-credit': 'The AI account has no credit left.',
    'ai-slow': 'AI took too long. Try again.', 'ai-failed': 'Not written. Try again.', 'ai-incomplete': 'Not written. Try again.',
    'ai-model': 'The AI model in Supabase is not available.', 'needs-update': 'This needs a database update.'
  };
  var AI = function () { return (window.ADspaceConfirm && window.ADspaceConfirm.ai && window.ADspaceConfirm.ai.glyph) || ''; };
  var TICK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>';
  function said(e) {
    if (!e) return '';
    var m = String(e.message || e);
    if (/could not find|does not exist|schema cache/i.test(m)) return 'This needs a database update.';
    return SAID[m] || m;
  }
  function day(ts) { return ts && window.ADspaceClock ? window.ADspaceClock.date(ts) : ''; }

  var V = null;   // { host, ctx, kind, data } while a checklist is open

  /* Each tick item, and how many are answered, outside the sections marked
     not applicable. */
  function count(d) {
    var n = 0, done = 0, na = d.sections_na || [];
    (d.sections || []).forEach(function (s) {
      if (na.indexOf(s.key) >= 0) return;
      s.items.forEach(function (it) {
        if (it.kind !== 'tick') return;
        n++;
        var a = d.answers[s.key + '.' + it.key];
        if (a && (a.state === 'done' || a.state === 'na')) done++;
      });
    });
    return { n: n, done: done };
  }
  function stateOf(d) {
    if (!d.started) return ['Not started', 'is-off'];
    return STATE[d.status] || STATE.open;
  }

  /* ---- The pane: the two checklists, each a row ------------------------ */
  function mount(host, ctx) {
    V = null;
    host.innerHTML = '<div class="msg" id="ckMsg"></div><div class="crm-table softpanel ck-list">' +
      KINDS.map(function (k) {
        return '<button class="ck-item" type="button" data-kind="' + k[0] + '"><span class="ck-item-name"><b>' + esc(k[1]) +
          '</b><small class="ck-item-meta">Reading</small></span><span class="ck-item-state"></span>' +
          '<span class="ck-chev" aria-hidden="true">' + TICK + '</span></button>';
      }).join('') + '</div>';
    KINDS.forEach(function (k) {
      var row = host.querySelector('[data-kind="' + k[0] + '"]');
      row.addEventListener('click', function () { open(host, ctx, k[0]); });
      ctx.db.rpc('client_checklist', { p_client: ctx.client.id, p_kind: k[0] }).then(function (r) {
        var d = r.data || {};
        if (r.error || d.error) { row.querySelector('.ck-item-meta').textContent = 'Could not load: ' + said(r.error || d.error); return; }
        var c = count(d), st = stateOf(d);
        row.querySelector('.ck-item-meta').textContent = 'Ver. ' + d.version + ' · ' + c.done + ' of ' + c.n + ' done' +
          (d.reviewed ? ' · Signed off by ' + d.reviewed.name + ', ' + day(d.reviewed.at) : '');
        row.querySelector('.ck-item-state').innerHTML = '<span class="chip-state ' + st[1] + '">' + esc(st[0]) + '</span>';
      }).catch(function (e) { row.querySelector('.ck-item-meta').textContent = 'Could not load: ' + said(e); });
    });
    var want = new URLSearchParams(location.search).get('list');
    if (want && KINDS.some(function (k) { return k[0] === want; })) open(host, ctx, want);
  }

  function setAddr(kind) {
    var u = new URL(location.href);
    if (kind) u.searchParams.set('list', kind); else u.searchParams.delete('list');
    history.replaceState(history.state, '', u.pathname + u.search);
  }

  function open(host, ctx, kind) {
    host.innerHTML = '<div class="skel skel-row"></div>';
    ctx.db.rpc('client_checklist', { p_client: ctx.client.id, p_kind: kind }).then(function (r) {
      var d = r.data || {};
      if (r.error || d.error) { host.innerHTML = '<p class="msg err">' + esc(said(r.error || d.error)) + '</p>'; return; }
      V = { host: host, ctx: ctx, kind: kind, data: d };
      setAddr(kind);
      paint();
      window.scrollTo(0, 0);
    }).catch(function (e) { host.innerHTML = '<p class="msg err">' + esc(said(e)) + '</p>'; });
  }

  function valueOf(d, key) {
    var a = d.answers[key];
    if (a && a.value != null) return a.value;
    return d.started ? null : (d.prefill || {})[key];
  }
  function editable(d) { return d.can_work && d.status === 'open'; }

  /* Read first (the user, 2026-10-15: "the checklist is coming back in the
     wrong design"): a tick is pressed where it is read, every other answer
     reads as a fact, and the section's Edit opens its fields in a sheet. */
  var PEN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 20h4L19 9l-4-4L4 16z"/><path d="m13.5 6.5 4 4"/></svg>';
  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>';
  var XMARK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>';
  function tickHtml(d, s, it, can) {
    var key = s.key + '.' + it.key, a = d.answers[key] || {}, hint = (d.hints || {})[key];
    var done = a.state === 'done', na = a.state === 'na';
    var by = (done || na) && a.by ? (na ? 'Not applicable · ' : '') + a.by + ', ' + day(a.at) : '';
    return '<div class="ck-row is-tick' + (done ? ' is-done' : '') + (na ? ' is-na' : '') + '" data-key="' + esc(key) + '">' +
      (can && !na ? '<button class="tcheck' + (done ? ' is-done' : '') + '" type="button" data-a="tick" aria-pressed="' + done + '" aria-label="' + esc(it.label) + '"></button>'
                  : '<span class="tcheck' + (done ? ' is-done' : '') + '" aria-hidden="true"></span>') +
      '<span class="ck-lab"><b>' + esc(it.label) + '</b>' + (it.detail ? '<small>' + esc(it.detail) + '</small>' : '') +
        (hint && !done ? '<small class="ck-hint">' + esc(hint) + '</small>' : '') +
        (a.note ? '<span class="ck-note-read">' + esc(a.note) + '</span>' : '') +
        (by ? '<small class="ck-by">' + esc(by) + '</small>' : '') + '</span></div>';
  }
  function factWord(it, v) {
    if (it.kind === 'multi') return Array.isArray(v) && v.length ? v.join(' · ') : '';
    return v == null ? '' : String(v);
  }
  function readTable(it, rows) {
    var cols = it.columns || [];
    if (!rows.length) return '<span class="ck-text-read"><span class="muted">Not set</span></span>';
    return '<div class="ck-table is-read" style="--ck-cols:' + cols.length + '"><div class="ck-tr ck-th">' +
      cols.map(function (c) { return '<span>' + esc(c[1]) + '</span>'; }).join('') + '</div>' +
      rows.map(function (r) {
        return '<div class="ck-tr">' + cols.map(function (c) {
          return '<span class="ck-td" data-label="' + esc(c[1]) + '">' + (r[c[0]] ? esc(r[c[0]]) : '<span class="muted">Not set</span>') + '</span>';
        }).join('') + '</div>';
      }).join('') + '</div>';
  }
  function sectionBody(d, s, can) {
    var out = '', facts = '';
    var flush = function () { if (facts) { out += '<dl class="ovfacts ck-facts">' + facts + '</dl>'; facts = ''; } };
    s.items.forEach(function (it) {
      var key = s.key + '.' + it.key;
      if (it.kind === 'tick') { flush(); out += tickHtml(d, s, it, can); return; }
      var v = valueOf(d, key);
      if (it.kind === 'table') {
        flush();
        out += '<div class="ck-row is-table" data-key="' + esc(key) + '"><span class="ck-lab"><b>' + esc(it.label) + '</b></span>' +
          readTable(it, Array.isArray(v) ? v : []) + '</div>';
        return;
      }
      var w = factWord(it, v);
      facts += '<div data-key="' + esc(key) + '"><dt>' + esc(it.label) + '</dt><dd class="ck-text-read">' + (w ? esc(w) : '<span class="muted">Not set</span>') + '</dd></div>';
    });
    flush();
    return out;
  }

  function tableRows(row) {
    return Array.prototype.map.call(row.querySelectorAll('.ck-tr[data-row]'), function (tr) {
      var o = {};
      Array.prototype.forEach.call(tr.querySelectorAll('.ck-cell'), function (c) { o[c.getAttribute('data-col')] = c.value.replace(/\s+/g, ' ').trim(); });
      return o;
    });
  }
  function itemOf(d, key) {
    var p = key.split('.'), s = (d.sections || []).filter(function (x) { return x.key === p[0]; })[0];
    return s && (s.items || []).filter(function (x) { return x.key === p[1]; })[0];
  }

  function paint() {
    var d = V.data, c = count(d), st = stateOf(d), na = d.sections_na || [];
    var cl = V.ctx.client, can = editable(d);
    var html = '<button class="backlink ck-back" type="button" data-a="back"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M19 12H5"/><path d="m11 6-6 6 6 6"/></svg>All checklists</button>' +
      '<section class="ovcard ck-head"><div class="ck-title"><h3>' + esc(d.title) + '</h3><small>Ver. ' + esc(d.version) + ' · ' + esc(d.lead || '') + '</small></div>' +
      '<div class="ck-ctl"><span class="chip-state ' + st[1] + '">' + esc(st[0]) + '</span>' +
      (V.kind === 'pre_ads' && can ? '<button class="btn btn-sm" type="button" data-a="ai" id="ckAi">' + AI() + 'Write with AI</button>' : '') +
      '<span class="team-act"><button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
      '<div class="kmenu" data-menu hidden><button class="kmenu-item" type="button" data-a="pdf"><b>Download</b></button></div></span></div>' +
      '<dl class="ovfacts ck-facts"><div><dt>Client / Brand</dt><dd>' + esc(cl.name) + '</dd></div>' +
        '<div><dt>Project Manager</dt><dd>' + (cl.owner ? esc(cl.owner) : '<span class="muted">Not set</span>') + '</dd></div>' +
        '<div><dt>Progress</dt><dd>' + c.done + ' of ' + c.n + ' done</dd></div></dl></section>' +
      '<div class="msg" id="ckMsg"></div>';
    d.sections.forEach(function (s, i) {
      var off = na.indexOf(s.key) >= 0;
      html += '<section class="ovcard ck-sec' + (off ? ' is-off' : '') + '" data-sec="' + esc(s.key) + '"><div class="ck-sec-head"><h4 class="fsec-h">' +
        (i + 1) + '. ' + esc(s.title) + '</h4><span class="ck-sec-acts">' +
        (off ? '<span class="chip">Not applicable</span>' : '') +
        (s.platform && can ? '<button class="btn btn-sm" type="button" data-a="secna">' + (off ? 'Applicable' : 'Not applicable') + '</button>' : '') +
        (can && !off ? '<button class="btn btn-sm" type="button" data-a="edit">' + PEN + 'Edit</button>' : '') + '</span></div>' +
        (s.note && !off ? '<p class="ck-sec-note">' + esc(s.note) + '</p>' : '') +
        (off ? '' : sectionBody(d, s, can)) + '</section>';
    });
    /* The sign-off: prepared by one colleague, reviewed by another. */
    var acts = '', me = d.me, prep = d.prepared;
    if (d.status === 'open' && d.can_work) acts = '<button class="btn btn-primary" type="button" data-a="prepare">Mark as prepared</button>';
    if (d.status === 'prepared' && d.can_work) {
      acts = (prep && prep.id !== me ? '<button class="btn btn-primary" type="button" data-a="review">Sign off</button>' : '') +
        '<button class="btn" type="button" data-a="return">Send back</button>';
    }
    if (d.status === 'signed' && d.can_manage) acts = '<button class="btn" type="button" data-a="reopen">Reopen</button>';
    html += '<section class="ovcard ck-sec ck-sign"><h4 class="fsec-h">Sign-off</h4><dl class="ovfacts ck-facts">' +
      '<div><dt>Prepared by</dt><dd>' + (prep ? esc(prep.name + ', ' + day(prep.at)) : '<span class="muted">Not yet</span>') + '</dd></div>' +
      '<div><dt>Reviewed by</dt><dd>' + (d.reviewed ? esc(d.reviewed.name + ', ' + day(d.reviewed.at)) : '<span class="muted">Not yet</span>') + '</dd></div></dl>' +
      (d.status === 'prepared' && prep && prep.id === me ? '<p class="ck-sec-note">Somebody other than you signs it off.</p>' : '') +
      (acts ? '<div class="row acts ck-acts">' + acts + '</div>' : '') + '</section>';
    V.host.innerHTML = html;
    wire();
  }

  function send(args, row, ok) {
    var d = V.data, ctx = V.ctx;
    return ctx.db.rpc('client_checklist_set', Object.assign({ p_client: ctx.client.id, p_kind: V.kind, p_state: null, p_note: null, p_value: null }, args))
      .then(function (r) {
        var x = r.data || {};
        if (r.error || x.error) { ctx.msg('ckMsg', said(r.error || x.error), 'err'); return; }
        V.data = x;
        if (ok) ok(x);
      }).catch(function (e) { ctx.msg('ckMsg', said(e), 'err'); });
  }

  function wire() {
    var host = V.host, ctx = V.ctx;
    host.querySelector('[data-a="back"]').addEventListener('click', function () { setAddr(null); mount(host, ctx); });
    var menuBtn = host.querySelector('.ck-head [data-a="menu"]'), menu = host.querySelector('.ck-head [data-menu]');
    menuBtn.addEventListener('click', function () {
      var open = menu.hidden;
      Array.prototype.forEach.call(document.querySelectorAll('.kmenu'), function (m) { m.hidden = true; });
      menu.hidden = !open;
      menuBtn.setAttribute('aria-expanded', String(open));
      if (open && window.ADspaceMenu) window.ADspaceMenu.place(menuBtn, menu);
    });
    host.querySelector('[data-a="pdf"]').addEventListener('click', function () { menu.hidden = true; menuBtn.setAttribute('aria-expanded', 'false'); download(menuBtn); });
    var aiB = host.querySelector('[data-a="ai"]');
    if (aiB) aiB.addEventListener('click', function () { write(aiB); });
    Array.prototype.forEach.call(host.querySelectorAll('[data-a="tick"]'), function (tk) {
      var row = tk.closest('.ck-row'), key = row.getAttribute('data-key');
      tk.addEventListener('click', function () {
        tk.disabled = true;
        send({ p_item: key, p_state: row.classList.contains('is-done') ? '' : 'done' }, row, paint).then(function () { tk.disabled = false; });
      });
    });
    Array.prototype.forEach.call(host.querySelectorAll('[data-a="edit"]'), function (b) {
      b.addEventListener('click', function () { editSection(b.closest('[data-sec]').getAttribute('data-sec'), b); });
    });
    wireSteps(host, ctx);
  }

  /* ---- A section's Edit: every answer of the section in one sheet ------- */
  function editSection(secKey, opener) {
    var d = V.data, s = (d.sections || []).filter(function (x) { return x.key === secKey; })[0];
    if (!s) return;
    var box = $('ckEditSheet');
    if (!box) {
      box = document.createElement('div');
      box.className = 'sheet'; box.id = 'ckEditSheet'; box.hidden = true;
      box.innerHTML = '<div class="sheet-card formsheet" role="dialog" aria-modal="true" aria-labelledby="ckEditTitle" tabindex="-1" data-narrow="560">' +
        '<div class="sheet-head"><h3 id="ckEditTitle"></h3><button class="iconbtn" type="button" data-a="x" aria-label="Close">' + XMARK + '</button></div>' +
        '<div class="sheet-body"><div data-m="body"></div><p class="msg" data-m="msg"></p></div>' +
        '<div class="sheet-foot"><button class="btn btn-primary" type="button" data-a="save">Save</button><button class="btn-quiet" type="button" data-a="cancel">Cancel</button></div></div>';
      document.body.appendChild(box);
      box.querySelector('[data-a="x"]').addEventListener('click', function () { window.ADspaceSheet.close(); });
      box.querySelector('[data-a="cancel"]').addEventListener('click', function () { window.ADspaceSheet.close(); });
      if (window.ADspaceState && window.ADspaceState.fit) window.ADspaceState.fit('#' + box.id + ' .sheet-card');
    }
    box.querySelector('#ckEditTitle').textContent = s.title;
    var body = box.querySelector('[data-m="body"]'), msg = box.querySelector('[data-m="msg"]');
    msg.textContent = ''; msg.className = 'msg';
    body.innerHTML = s.items.map(function (it) {
      var key = s.key + '.' + it.key, a = d.answers[key] || {};
      if (it.kind === 'tick') {
        return '<div class="ck-ed" data-key="' + esc(key) + '" data-kind="tick"><label class="ck-ed-lab" for="ckEd-' + esc(key) + '">' + esc(it.label) + '</label>' +
          '<textarea class="input" id="ckEd-' + esc(key) + '" data-oneline data-nodraft rows="1" data-f="note" placeholder="Notes">' + esc(a.note || '') + '</textarea>' +
          '<label class="tickline"><input type="checkbox" data-f="na"' + (a.state === 'na' ? ' checked' : '') + '><span>Not applicable</span></label></div>';
      }
      var v = valueOf(d, key);
      if (it.kind === 'table') {
        return '<div class="ck-ed" data-key="' + esc(key) + '" data-kind="table"><span class="ck-ed-lab">' + esc(it.label) + '</span>' +
          (it.detail ? '<small class="ck-ed-note">' + esc(it.detail) + '</small>' : '') + edTable(it, Array.isArray(v) ? v : []) + '</div>';
      }
      if (it.kind === 'choice' || it.kind === 'multi') {
        var on = it.kind === 'multi' ? (Array.isArray(v) ? v : []) : (v ? [v] : []);
        return '<div class="ck-ed" data-key="' + esc(key) + '" data-kind="' + it.kind + '"><span class="ck-ed-lab">' + esc(it.label) + '</span>' +
          '<span class="ck-chips" role="group" aria-label="' + esc(it.label) + '">' + it.choices.map(function (c) {
            var sel = on.indexOf(c) >= 0;
            return '<button class="ck-chip' + (sel ? ' is-on' : '') + '" type="button" data-c="' + esc(c) + '" aria-pressed="' + sel + '">' + esc(c) + '</button>';
          }).join('') + '</span></div>';
      }
      return '<div class="ck-ed" data-key="' + esc(key) + '" data-kind="text"><label class="ck-ed-lab" for="ckEd-' + esc(key) + '">' + esc(it.label) + '</label>' +
        '<textarea class="input" id="ckEd-' + esc(key) + '" data-nodraft data-f="value"' + (Number(it.rows) > 1 ? ' rows="' + it.rows + '"' : ' data-oneline rows="1"') + '>' +
        esc(v || '') + '</textarea></div>';
    }).join('');
    Array.prototype.forEach.call(body.querySelectorAll('.ck-ed'), function (ed) {
      var kind = ed.getAttribute('data-kind');
      Array.prototype.forEach.call(ed.querySelectorAll('.ck-chip'), function (b) {
        b.addEventListener('click', function () {
          var sel = !b.classList.contains('is-on');
          if (kind === 'choice' && sel) Array.prototype.forEach.call(ed.querySelectorAll('.ck-chip'), function (y) { y.classList.remove('is-on'); y.setAttribute('aria-pressed', 'false'); });
          b.classList.toggle('is-on', sel); b.setAttribute('aria-pressed', String(sel));
        });
      });
      if (kind === 'table') wireEdTable(ed, itemOf(d, ed.getAttribute('data-key')));
    });
    var save = box.querySelector('[data-a="save"]');
    save.onclick = function () {
      var calls = [];
      Array.prototype.forEach.call(body.querySelectorAll('.ck-ed'), function (ed) {
        var key = ed.getAttribute('data-key'), kind = ed.getAttribute('data-kind'), a = d.answers[key] || {};
        if (kind === 'tick') {
          var note = ed.querySelector('[data-f="note"]').value.trim(), na = ed.querySelector('[data-f="na"]').checked;
          var args = {};
          if (note !== (a.note || '')) args.p_note = note;
          if (na !== (a.state === 'na')) args.p_state = na ? 'na' : '';
          if (Object.keys(args).length) calls.push(Object.assign({ p_item: key }, args));
          return;
        }
        var now = valueOf(d, key), next;
        if (kind === 'table') next = tableRows(ed).filter(function (r) { return Object.keys(r).some(function (k) { return r[k]; }); });
        else if (kind === 'multi') next = Array.prototype.map.call(ed.querySelectorAll('.ck-chip.is-on'), function (x) { return x.getAttribute('data-c'); });
        else if (kind === 'choice') { var o = ed.querySelector('.ck-chip.is-on'); next = o ? o.getAttribute('data-c') : ''; }
        else next = ed.querySelector('[data-f="value"]').value.trim();
        var empty = function (x) { return x == null || x === '' || (Array.isArray(x) && !x.length); };
        if (empty(now) && empty(next)) return;
        if (JSON.stringify(now) === JSON.stringify(next) && (d.answers[key] || {}).value != null) return;
        calls.push({ p_item: key, p_value: next });
      });
      if (!calls.length) { window.ADspaceSheet.close(); return; }
      save.disabled = true;
      var chain = Promise.resolve(true);
      calls.forEach(function (args) {
        chain = chain.then(function (ok) {
          if (!ok) return false;
          return V.ctx.db.rpc('client_checklist_set', Object.assign({ p_client: V.ctx.client.id, p_kind: V.kind, p_state: null, p_note: null, p_value: null }, args))
            .then(function (r) {
              var x = r.data || {};
              if (r.error || x.error) { msg.textContent = said(r.error || x.error); msg.className = 'msg err'; return false; }
              V.data = x; return true;
            }).catch(function (e) { msg.textContent = said(e); msg.className = 'msg err'; return false; });
        });
      });
      chain.then(function (ok) {
        save.disabled = false;
        paint();
        if (!ok) return;
        window.ADspaceSheet.close();
        V.ctx.msg('ckMsg', 'Saved.', 'ok');
      });
    };
    window.ADspaceSheet.show(box, { opener: opener });
  }

  /* A table in the sheet: a row an ad set, each cell a one-line box. */
  function edTable(it, rows) {
    var cols = it.columns || [];
    if (!rows.length) rows = [{}];
    return '<div class="ck-table" style="--ck-cols:' + cols.length + '"><div class="ck-tr ck-th">' +
      cols.map(function (c) { return '<span>' + esc(c[1]) + '</span>'; }).join('') + '<span></span></div>' +
      rows.map(function (r, i) { return edRow(cols, r, i); }).join('') + '</div>' +
      '<button class="btn btn-sm ck-addrow" type="button" data-a="addrow"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>Add row</button>';
  }
  function edRow(cols, r, i) {
    return '<div class="ck-tr" data-row="' + i + '">' + cols.map(function (c) {
      return '<textarea class="input input-sm ck-cell" data-col="' + esc(c[0]) + '" data-oneline data-nodraft rows="1" aria-label="' +
        esc(c[1] + ', row ' + (i + 1)) + '" placeholder="' + esc(c[1]) + '">' + esc(r[c[0]] || '') + '</textarea>';
    }).join('') + '<button class="iconbtn ck-rowx" type="button" data-a="rowx" aria-label="Remove row ' + (i + 1) + '">' + XMARK + '</button></div>';
  }
  function wireEdTable(ed, it) {
    var table = ed.querySelector('.ck-table');
    var wireX = function (b) { b.addEventListener('click', function () { b.closest('.ck-tr').remove(); }); };
    Array.prototype.forEach.call(ed.querySelectorAll('[data-a="rowx"]'), wireX);
    ed.querySelector('[data-a="addrow"]').addEventListener('click', function () {
      var n = table.querySelectorAll('.ck-tr[data-row]').length;
      if (n >= 12) return;
      var hold = document.createElement('div');
      hold.innerHTML = edRow(it.columns || [], {}, n);
      var tr = hold.firstChild;
      table.appendChild(tr);
      wireX(tr.querySelector('[data-a="rowx"]'));
      tr.querySelector('.ck-cell').focus();
    });
  }

  function wireSteps(host, ctx) {
    Array.prototype.forEach.call(host.querySelectorAll('[data-a="secna"]'), function (b) {
      var sec = b.closest('[data-sec]').getAttribute('data-sec');
      b.addEventListener('click', function () {
        b.disabled = true;
        send({ p_item: sec, p_state: b.closest('.ck-sec').classList.contains('is-off') ? '' : 'na' }, null, paint);
      });
    });
    ['prepare', 'return', 'review', 'reopen'].forEach(function (step) {
      var b = host.querySelector('[data-a="' + step + '"]');
      if (!b) return;
      b.addEventListener('click', function () {
        var go = function () {
          b.disabled = true;
          ctx.db.rpc('client_checklist_step', { p_client: ctx.client.id, p_kind: V.kind, p_step: step }).then(function (r) {
            var x = r.data || {};
            b.disabled = false;
            if (r.error || x.error) {
              ctx.msg('ckMsg', x.error === 'incomplete' ? x.left + (x.left === 1 ? ' item is' : ' items are') + ' not done or marked not applicable.' : said(r.error || x.error), 'err');
              return;
            }
            V.data = x; paint();
            ctx.msg('ckMsg', { prepare: 'Prepared for review.', 'return': 'Sent back.', review: 'Signed off.', reopen: 'Reopened.' }[step], 'ok');
          }).catch(function (e) { b.disabled = false; ctx.msg('ckMsg', said(e), 'err'); });
        };
        if (step === 'reopen') {
          window.ADspaceConfirm.ask({ title: 'Reopen this checklist?', body: 'The signed copy is kept, and the month\'s check in My Work is unticked until it is signed off again.', go: 'Reopen', tone: 'warn' }, go);
        } else if (step === 'review') {
          window.ADspaceConfirm.ask({ title: 'Sign off this checklist?', body: 'It is locked once signed, and the month\'s check in My Work is ticked.', go: 'Sign off' }, go);
        } else go();
      });
    });
  }

  /* ---- Write with AI (2026-10-15): the playbook's pre-advertising read --
     What the team knows is asked up front (kept in this browser); the
     function reads the confirmed Brand analysis, the Ad benchmarks and the
     linked Meta accounts and proposes an answer for each field; the
     colleague chooses which to keep in a sheet, declares them read, and
     each is saved as if typed, with Undo where it happened. */
  var keep = function (k, v) {
    try { if (v === undefined) return JSON.parse(localStorage.getItem(k) || '{}') || {}; localStorage.setItem(k, JSON.stringify(v)); } catch (e) {}
    return {};
  };
  function brandIn(v, name) {
    if (typeof v === 'string') return v.replace(/\{brand\}/g, name);
    if (Array.isArray(v)) return v.map(function (x) { return brandIn(x, name); });
    if (v && typeof v === 'object') { var o = {}; Object.keys(v).forEach(function (k) { o[k] = brandIn(v[k], name); }); return o; }
    return v;
  }
  function word(v) {
    if (Array.isArray(v)) return v.map(function (x) { return typeof x === 'object' ? Object.keys(x).map(function (k) { return x[k]; }).join(' · ') : x; }).join('\n');
    return v == null ? '' : String(v);
  }
  /* One press from the checklist (the user, 2026-10-15: "i need to go brand
     do first then go back to engagements"): with no confirmed Brand
     analysis the same question runs it first, shows it here to confirm
     (which fills the empty Content brief), then writes the checklist. */
  var OBJ_BA = { Leads: 'enquiries', Sales: 'traffic', Traffic: 'traffic', Awareness: 'awareness' };
  function write(btn) {
    var ctx = V.ctx, cl = ctx.client, k = 'adspace-checklist-inputs:' + cl.id;
    ctx.msg('ckMsg', '');
    btn.disabled = true;
    Promise.all([ctx.db.rpc('ai_checklist_left'), ctx.db.rpc('ai_brand_ready', { p_client: cl.id }), ctx.db.rpc('ai_analysis_left')]).then(function (rs) {
      btn.disabled = false;
      var l = rs[0].data || {}, ready = rs[1].data || {}, al = rs[2].data || {};
      if (rs[0].error || l.error) { ctx.msg('ckMsg', said(rs[0].error || l.error), 'err'); return; }
      if (!l.left) {
        ctx.msg('ckMsg', l.limit === 0 ? 'Write with AI on checklists is turned off for you. An admin can turn it on.'
          : 'No checklist drafts left today. The next is free at 12:00 am.', 'err');
        return;
      }
      var needBa = !rs[1].error && !ready.error && !ready.analysis;
      if (needBa && !al.left) { ctx.msg('ckMsg', 'No Brand analysis is confirmed, and no analyses are left today. The next is free at 12:00 am.', 'err'); return; }
      var was = keep(k);
      window.ADspaceConfirm.ask({
        title: 'Write with AI',
        body: (needBa
          ? 'No Brand analysis is confirmed for this client, so one is run first from the website, the profiles and Meta, for you to confirm here; confirming it also fills the Content brief where it is empty. Then the checklist is written. '
          : 'Reads the confirmed Brand analysis, the Ad benchmarks and the linked Meta accounts, then proposes an answer for each field to review before it is saved. ') +
          l.left + (l.left === 1 ? ' checklist draft' : ' checklist drafts') + (needBa ? ' and ' + al.left + (al.left === 1 ? ' analysis' : ' analyses') : '') + ' left today.',
        go: needBa ? 'Run' : 'Write',
        fields: [
          { name: 'budget', label: 'Monthly ad budget (RM)', type: 'number', required: false, placeholder: 'Optional', value: was.budget || '' },
          { name: 'objective', label: 'Main objective', required: false, value: was.objective || '',
            choices: [['', 'Not decided'], ['Leads', 'Leads'], ['Sales', 'Sales'], ['Traffic', 'Traffic'], ['Awareness', 'Awareness']] },
          { name: 'destination', label: 'Ads send people to', required: false, value: was.destination || '',
            choices: [['', 'Not decided'], ['Instant Form', 'An instant form'], ['WhatsApp', 'WhatsApp'], ['Messenger', 'Messenger'], ['Website', 'The website']] },
          { name: 'account', label: 'Ad account', required: false, seg: true, value: was.account || '',
            choices: [['', 'Not known'], ['new', 'New'], ['mature', 'Mature']] },
          { name: 'notes', label: 'Notes for the checklist', rows: 3, required: false, placeholder: 'Optional', value: was.notes || '' }],
        check: function (v) {
          var b = String(v.budget == null ? '' : v.budget).trim();
          return b && !(Number(b) > 0 && Number(b) <= 10000000) ? 'Monthly ad budget: a figure above 0.' : '';
        }
      }, function (v) {
        var inputs = { budget: String(v.budget == null ? '' : v.budget).trim(), objective: v.objective || '', destination: v.destination || '',
          account: v.account || '', notes: String(v.notes || '').trim() };
        keep(k, inputs);
        if (needBa) analyseFirst(inputs); else draft(inputs);
      });
    }).catch(function (e) { btn.disabled = false; ctx.msg('ckMsg', said(e), 'err'); });
  }
  function busy(on) {
    var b = V && V.host.querySelector('[data-a="ai"]');
    if (!b) return;
    b.disabled = on;
    if (on) b.setAttribute('aria-busy', 'true'); else b.removeAttribute('aria-busy');
    b.lastChild.textContent = on ? 'Writing' : 'Write with AI';
  }
  function analyseFirst(inputs) {
    var ctx = V.ctx, cl = ctx.client;
    busy(true);
    var obj = inputs.objective === 'Leads' && (inputs.destination === 'WhatsApp' || inputs.destination === 'Messenger') ? 'messages' : OBJ_BA[inputs.objective] || null;
    ctx.db.functions.invoke('brand-analysis', { body: { client_id: cl.id, notes: inputs.notes,
      inputs: { objective: obj, budget: inputs.budget ? Number(inputs.budget) : null, account: inputs.account || null } } }).then(function (res) {
      var d = res && res.data;
      if (res.error || !d || d.error || !d.analysis) { var e = new Error((d && d.error) || 'ai-failed'); e.d = d; throw e; }
      busy(false);
      if (!V || V.ctx.client.id !== cl.id) return;
      showAnalysis(d.analysis, inputs);
    }).catch(function (e) {
      busy(false);
      var m = e && e.message;
      ctx.msg('ckMsg', m === 'no-source' ? 'Add the website, an Instagram or Facebook handle, or link Meta accounts on Brand first.'
        : m === 'ai-limit' ? 'No analyses left today. The next is free at 12:00 am.' : said(e), 'err');
    });
  }
  /* The analysis read here before it is confirmed: the parts the checklist
     and the brief are written from. */
  function showAnalysis(row, inputs) {
    var a = row.analysis || {}, p = a.positioning || {}, sw = a.swot || {}, ct = a.content || {}, ad = a.ads || {}, br = a.brief || {};
    var lst = function (x) { return (x || []).length ? '<ul class="ck-ba-list">' + x.map(function (y) { return '<li>' + esc(y) + '</li>'; }).join('') + '</ul>' : ''; };
    var sec = function (t, body) { return body ? '<section class="ck-ba-sec"><h4 class="fsec-h">' + esc(t) + '</h4>' + body + '</section>' : ''; };
    var fact = function (rows) {
      rows = rows.filter(function (r) { return r[1]; });
      return rows.length ? '<dl class="ovfacts">' + rows.map(function (r) { return '<div><dt>' + esc(r[0]) + '</dt><dd>' + r[1] + '</dd></div>'; }).join('') + '</dl>' : '';
    };
    var box = $('ckBaSheet');
    if (!box) {
      box = document.createElement('div');
      box.className = 'sheet'; box.id = 'ckBaSheet'; box.hidden = true;
      box.innerHTML = '<div class="sheet-card formsheet" role="dialog" aria-modal="true" aria-labelledby="ckBaTitle" tabindex="-1" data-narrow="560">' +
        '<div class="sheet-head"><h3 id="ckBaTitle">Brand analysis</h3><button class="iconbtn" type="button" data-a="x" aria-label="Close">' + XMARK + '</button></div>' +
        '<div class="sheet-body" data-m="body"></div>' +
        '<div class="sheet-foot"><button class="btn btn-primary" type="button" data-a="go">Confirm and write</button><button class="btn-quiet" type="button" data-a="cancel">Cancel</button></div></div>';
      document.body.appendChild(box);
      box.querySelector('[data-a="x"]').addEventListener('click', function () { window.ADspaceSheet.close(); });
      box.querySelector('[data-a="cancel"]').addEventListener('click', function () { window.ADspaceSheet.close(); });
      if (window.ADspaceState && window.ADspaceState.fit) window.ADspaceState.fit('#ckBaSheet .sheet-card');
    }
    box.querySelector('[data-m="body"]').innerHTML =
      (row.hypothesis ? '<p class="msg warn ck-ba-hyp">A starting hypothesis to test</p>' : '') +
      sec('Brand positioning', fact([['Stands for now', esc(p.now || '')], ['Could own', esc(p.could_own || '')],
        ['Competitors', esc((p.competitors || []).join(', '))]])) +
      sec('Target audiences', fact((a.audiences || []).map(function (x) { return [x.name, esc([x.who, x.pains].filter(Boolean).join(' · '))]; }))) +
      sec('SWOT', fact([['Strengths', lst(sw.strengths)], ['Weaknesses', lst(sw.weaknesses)], ['Opportunities', lst(sw.opportunities)], ['Threats', lst(sw.threats)]])) +
      sec('Content brief', fact([['Audience', esc(br.audience || '')], ['Content pillars', lst(br.pillars && br.pillars.length ? br.pillars : ct.pillars)], ['Tone of voice', esc(br.tone || '')]])) +
      sec('Ad targeting', fact([['Objectives', lst(ad.objectives)], ['Budget realism', esc(ad.realism || '')]]));
    var go = box.querySelector('[data-a="go"]');
    go.disabled = false;
    go.onclick = function () {
      window.ADspaceSheet.close();
      window.ADspaceConfirm.ai.declare('analysis', 'Confirm', function () {
        V.ctx.db.rpc('brand_analysis_confirm', { p_id: row.id, p_on: true }).then(function (r) {
          var x = r.data || {};
          if (r.error || x.error) { V.ctx.msg('ckMsg', said(r.error || x.error), 'err'); return; }
          if (V.ctx.brief) V.ctx.brief(x.filled || []);
          draft(inputs);
        }).catch(function (e) { V.ctx.msg('ckMsg', said(e), 'err'); });
      });
    };
    window.ADspaceSheet.show(box, { opener: V.host.querySelector('[data-a="ai"]') });
    V.ctx.msg('ckMsg', 'Brand analysis version ' + row.version + ' written. Confirm it to write the checklist; until then it waits as a draft on Brand.', 'ok');
  }
  function draft(inputs) {
    var ctx = V.ctx, cl = ctx.client;
    busy(true);
    ctx.db.functions.invoke('checklist-draft', { body: { client_id: cl.id, notes: inputs.notes,
      inputs: { budget: inputs.budget ? Number(inputs.budget) : null, objective: inputs.objective || null,
        destination: inputs.destination || null, account: inputs.account || null } } }).then(function (res) {
      var d = res && res.data;
      if (res.error || !d || d.error || !d.fill) {
        var e = new Error((d && d.error) || 'ai-failed'); e.d = d; throw e;
      }
      busy(false);
      if (!V || V.ctx.client.id !== cl.id) return;
      ctx.msg('ckMsg', '');
      review(brandIn(d.fill, cl.name));
    }).catch(function (e) {
      busy(false);
      var d = e && e.d;
      ctx.msg('ckMsg', d && d.error === 'ai-limit' ? 'No checklist drafts left today. The next is free at 12:00 am.' : said(e), 'err');
    });
  }

  /* The proposals, one a field, each ticked to keep; what the field holds
     now is said under it where it differs. */
  function review(fill) {
    var d = V.data, box = $('ckAiSheet');
    if (!box) {
      box = document.createElement('div');
      box.className = 'sheet'; box.id = 'ckAiSheet'; box.hidden = true;
      box.innerHTML = '<div class="sheet-card formsheet" role="dialog" aria-modal="true" aria-labelledby="ckAiTitle" tabindex="-1" data-narrow="560">' +
        '<div class="sheet-head"><h3 id="ckAiTitle">Written by AI</h3><button class="iconbtn" type="button" data-a="x" aria-label="Close">' +
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg></button></div>' +
        '<div class="sheet-body" data-m="body"></div>' +
        '<div class="sheet-foot"><button class="btn btn-primary" type="button" data-a="apply">Apply</button><button class="btn-quiet" type="button" data-a="cancel">Cancel</button></div></div>';
      document.body.appendChild(box);
      box.querySelector('[data-a="x"]').addEventListener('click', function () { window.ADspaceSheet.close(); });
      box.querySelector('[data-a="cancel"]').addEventListener('click', function () { window.ADspaceSheet.close(); });
      if (window.ADspaceState && window.ADspaceState.fit) window.ADspaceState.fit('#' + box.id + ' .sheet-card');
    }
    var rows = [], na = d.sections_na || [];
    d.sections.forEach(function (s) {
      if (na.indexOf(s.key) >= 0) return;
      s.items.forEach(function (it) {
        var key = s.key + '.' + it.key;
        if (it.kind === 'tick' || !(key in fill)) return;
        var now = valueOf(d, key), next = fill[key];
        if (JSON.stringify(now == null ? '' : now) === JSON.stringify(next)) return;
        rows.push({ key: key, sec: s.title, it: it, now: now, next: next });
      });
    });
    var body = box.querySelector('[data-m="body"]');
    if (!rows.length) { V.ctx.msg('ckMsg', 'Written by AI: every field already holds what it proposes.', 'ok'); return; }
    body.innerHTML = rows.map(function (r, i) {
      var nx = r.it.kind === 'table'
        ? '<div class="ck-table is-read" style="--ck-cols:' + r.it.columns.length + '"><div class="ck-tr ck-th">' + r.it.columns.map(function (c) { return '<span>' + esc(c[1]) + '</span>'; }).join('') + '</div>' +
          r.next.map(function (row) { return '<div class="ck-tr">' + r.it.columns.map(function (c) { return '<span class="ck-td" data-label="' + esc(c[1]) + '">' + esc(row[c[0]] || '') + '</span>'; }).join('') + '</div>'; }).join('') + '</div>'
        : '<span class="ck-ai-val">' + esc(word(r.next)) + '</span>';
      var nw = r.now == null || r.now === '' || (Array.isArray(r.now) && !r.now.length) ? '' : '<small class="ck-ai-now">Now: ' + esc(word(r.now)) + '</small>';
      return '<label class="tickline ck-ai-row"><input type="checkbox" checked data-i="' + i + '"><span><b>' + esc(r.sec + ' · ' + r.it.label) + '</b>' + nx + nw + '</span></label>';
    }).join('');
    var go = box.querySelector('[data-a="apply"]');
    var count = function () {
      var n = body.querySelectorAll('input:checked').length;
      go.textContent = n ? 'Apply ' + n : 'Apply'; go.disabled = !n;
    };
    Array.prototype.forEach.call(body.querySelectorAll('input'), function (x) { x.addEventListener('change', count); });
    count();
    go.onclick = function () {
      var picks = Array.prototype.filter.call(body.querySelectorAll('input:checked'), function () { return true; })
        .map(function (x) { return rows[Number(x.getAttribute('data-i'))]; });
      window.ADspaceSheet.close();
      window.ADspaceConfirm.ai.declare('checklist', 'Apply', function () { apply(picks); });
    };
    window.ADspaceSheet.show(box, { opener: V.host.querySelector('[data-a="ai"]') });
  }

  /* Each kept answer saved as if typed; Undo puts back each field's own. */
  function apply(picks, undoing) {
    var ctx = V.ctx, back = [], fail = 0;
    var chain = Promise.resolve();
    picks.forEach(function (p) {
      chain = chain.then(function () {
        var to = p.next;
        if (to == null) to = p.it.kind === 'multi' || p.it.kind === 'table' ? [] : '';
        return ctx.db.rpc('client_checklist_set', { p_client: ctx.client.id, p_kind: V.kind, p_item: p.key, p_state: null, p_note: null, p_value: to })
          .then(function (r) {
            var x = r.data || {};
            if (r.error || x.error) { fail++; return; }
            V.data = x;
            back.push({ key: p.key, it: p.it, next: p.now == null ? null : p.now, now: to });
          }).catch(function () { fail++; });
      });
    });
    return chain.then(function () {
      paint();
      if (fail) ctx.msg('ckMsg', fail + (fail === 1 ? ' answer was' : ' answers were') + ' not saved.', 'err');
      if (undoing || !back.length || !ctx.undo) return;
      ctx.undo('Written by AI. Read before signing off.', function () { apply(back, true); }, $('ckMsg'));
    });
  }

  /* ---- Download: the team's form, drawn in the browser ----------------- */
  function download(btn) {
    var docs = window.ADspaceDocs, d = V.data, cl = V.ctx.client;
    if (!docs) return;
    var tab = docs.tabFor ? docs.tabFor() : null;
    btn.disabled = true;
    draw(d, cl).then(function (blob) {
      btn.disabled = false;
      return docs.save(blob, cl.name + ' ' + d.title + '.pdf', tab);
    }).catch(function (e) { btn.disabled = false; docs.shut(tab); V.ctx.msg('ckMsg', said(e), 'err'); });
  }

  function draw(d, cl) {
    var docs = window.ADspaceDocs;
    var all = JSON.stringify(d.answers) + cl.name;
    var cjk = /[　-鿿＀-￯]/.test(all + JSON.stringify(d.sections));
    return docs.lib().then(function (PDF) {
      var pdf;
      return PDF.PDFDocument.create().then(function (doc) {
        pdf = doc;
        pdf.setTitle(d.title); pdf.setAuthor('ADSPACE PLT'); pdf.setCreator('ADspace Digital Portal'); pdf.setProducer('ADspace Digital Portal');
        return docs.embedFonts(pdf, PDF, { cjk: cjk });
      }).then(function (fonts) {
        layout(pdf, PDF, fonts, d, cl);
        return pdf.save();
      }).then(function (bytes) { return new Blob([bytes], { type: 'application/pdf' }); });
    });
  }

  function layout(pdf, PDF, fonts, d, cl) {
    var W = 595.28, H = 841.89, M = 42, R = W - M, FULL = R - M, FLOOR = 60;
    var ink = PDF.rgb(0.251, 0.251, 0.251), dark = PDF.rgb(0.106, 0.102, 0.090), mute = PDF.rgb(0.4, 0.4, 0.4);
    var fill = PDF.rgb(0.949, 0.949, 0.949), edge = PDF.rgb(0.91, 0.91, 0.91);
    var book = fonts.font, reg = fonts.bold, med = fonts.med || fonts.bold, mark = fonts.mark || med;
    var hasCjk = function (s) { return /[　-鿿＀-￯]/.test(String(s)); };
    var face = function (s, f) { return fonts.cjk && hasCjk(s) ? fonts.cjk : f; };
    var safe = function (s) { s = String(s == null ? '' : s); return fonts.custom ? s : s.replace(/[^\x20-\x7E\xA0-\xFF]/g, '-'); };
    var width = function (s, size, f) { f = face(s, f || book); return f.widthOfTextAtSize(safe(s), size); };
    var page, y, pages = [];
    var text = function (s, x, yy, size, f, color) {
      if (s == null || s === '') return;
      f = face(s, f || book);
      page.drawText(safe(s), { x: x, y: yy, size: size, font: f, color: color || ink });
    };
    var wrap = function (s, max, size, f) {
      var out = [];
      String(s == null ? '' : s).split('\n').forEach(function (para) {
        var cur = '';
        para.split(/(\s+)/).forEach(function (w) {
          if (!w) return;
          var t = cur + w;
          if (width(t, size, f) <= max || !cur.trim()) { cur = t; return; }
          out.push(cur.replace(/\s+$/, '')); cur = /^\s+$/.test(w) ? '' : w;
        });
        out.push(cur.replace(/\s+$/, ''));
      });
      return out.length ? out : [''];
    };
    var rect = function (x, yy, w, h, bg) { page.drawRectangle({ x: x, y: yy, width: w, height: h, color: bg || undefined, borderColor: edge, borderWidth: 0.8 }); };
    var newPage = function () {
      page = pdf.addPage([W, H]); pages.push(page);
      text('ADspace', M, H - 52, 16, mark, ink);
      /* Centred on the paper, measured in its own face (the user, 2026-10-15). */
      text('FOR INTERNAL USE', (W - width('FOR INTERNAL USE', 7.5, med)) / 2, H - 50, 7.5, med, dark);
      y = H - 74;
    };
    var room = function (h) { if (y - h < FLOOR) { newPage(); return true; } return false; };
    var SZ = 9, LH = 12.5;
    var cols = [FULL * 0.3, FULL * 0.38, FULL * 0.08, FULL * 0.24];
    var cx = [M, M + cols[0], M + cols[0] + cols[1], M + cols[0] + cols[1] + cols[2]];
    var tableHead = function () {
      var h = 20;
      ['Item', 'Details', 'Done', 'Notes'].forEach(function (t, i) { rect(cx[i], y - h, cols[i], h, fill); text(t, cx[i] + 6, y - 13.5, SZ, book, dark); });
      y -= h;
    };
    var factRow = function (label, value) {
      var lines = wrap(value || '', FULL * 0.62 - 12, SZ);
      var h = Math.max(1, lines.length) * LH + 9;
      room(h);
      rect(M, y - h, FULL * 0.38, h, fill); rect(M + FULL * 0.38, y - h, FULL * 0.62, h);
      text(label, M + 6, y - 13, SZ, book, dark);
      lines.forEach(function (l, k) { text(l, M + FULL * 0.38 + 6, y - 13 - k * LH, SZ); });
      y -= h;
    };

    newPage();
    text(d.title, M, y - 16, 18, reg, dark); y -= 26;
    text(d.lead || '', M, y - 6, 9, book, mute); y -= 22;
    factRow('Client / Brand', cl.name);
    factRow('Version', 'ver. ' + d.version);
    factRow('Project Manager / PM', cl.owner || '');
    y -= 14;
    var na = d.sections_na || [];
    d.sections.forEach(function (s, i) {
      room(60);
      text((i + 1) + '. ' + s.title + (na.indexOf(s.key) >= 0 ? ' (Not applicable)' : ''), M, y - 10, 10.5, med, dark); y -= 16;
      if (s.note) { wrap(s.note, FULL, 8.5).forEach(function (l) { text(l, M, y - 8, 8.5, book, mute); y -= 11; }); y -= 3; }
      if (na.indexOf(s.key) >= 0) { y -= 8; return; }
      var ticks = s.items.filter(function (it) { return it.kind === 'tick'; });
      if (ticks.length) {
        tableHead();
        ticks.forEach(function (it) {
          var a = d.answers[s.key + '.' + it.key] || {};
          var l1 = wrap(it.label, cols[0] - 12, SZ), l2 = wrap(it.detail || '', cols[1] - 12, SZ);
          var nt = [a.note || '', a.state && a.by ? (a.state === 'na' ? 'Not applicable · ' : '') + a.by + ', ' + day(a.at) : ''].filter(Boolean).join('\n');
          var l4 = wrap(nt, cols[3] - 12, 8);
          var h = Math.max(l1.length, l2.length, l4.length * 0.85, 1) * LH + 9;
          if (room(h)) tableHead();
          for (var k = 0; k < 4; k++) rect(cx[k], y - h, cols[k], h);
          l1.forEach(function (l, j) { text(l, cx[0] + 6, y - 13 - j * LH, SZ); });
          l2.forEach(function (l, j) { text(l, cx[1] + 6, y - 13 - j * LH, SZ); });
          var bx = cx[2] + cols[2] / 2 - 4, by = y - 16;
          page.drawRectangle({ x: bx, y: by, width: 8, height: 8, borderColor: ink, borderWidth: 0.7 });
          if (a.state === 'done') {
            page.drawLine({ start: { x: bx + 1.5, y: by + 4 }, end: { x: bx + 3.5, y: by + 1.5 }, thickness: 1, color: dark });
            page.drawLine({ start: { x: bx + 3.5, y: by + 1.5 }, end: { x: bx + 7, y: by + 7 }, thickness: 1, color: dark });
          }
          if (a.state === 'na') text('N/A', cx[2] + 4, y - 26, 7, book, mute);
          l4.forEach(function (l, j) { text(l, cx[3] + 6, y - 13 - j * 10.5, 8); });
          y -= h;
        });
      }
      s.items.filter(function (it) { return it.kind !== 'tick'; }).forEach(function (it) {
        var v = (d.answers[s.key + '.' + it.key] || {}).value;
        /* A table (r1.2): its columns over a row each, under its label. */
        if (it.kind === 'table') {
          var tc = it.columns || [], share = [0.22, 0.27, 0.21, 0.13, 0.17];
          var tw = tc.map(function (c, i) { return FULL * (share[i] || 1 / tc.length); }), tx = [M];
          for (var q = 1; q < tc.length; q++) tx[q] = tx[q - 1] + tw[q - 1];
          room(44);
          text(it.label, M, y - 10, SZ, med, dark); y -= 16;
          var th = function () { tc.forEach(function (c, i) { rect(tx[i], y - 20, tw[i], 20, fill); text(c[1], tx[i] + 6, y - 13.5, SZ, book, dark); }); y -= 20; };
          th();
          (Array.isArray(v) && v.length ? v : [{}]).forEach(function (row) {
            var ls = tc.map(function (c, i) { return wrap(row[c[0]] || '', tw[i] - 12, 8.5); });
            var h = Math.max.apply(null, ls.map(function (l) { return l.length; }).concat([1])) * 11 + 9;
            if (room(h)) th();
            tc.forEach(function (c, i) { rect(tx[i], y - h, tw[i], h); ls[i].forEach(function (l, j) { text(l, tx[i] + 6, y - 13 - j * 11, 8.5); }); });
            y -= h;
          });
          y -= 8;
          return;
        }
        var word = Array.isArray(v) ? v.join(' / ') : v || '';
        if (!word && (it.kind === 'choice' || it.kind === 'multi')) word = '';
        factRow(it.label, word);
      });
      y -= 14;
    });
    room(70);
    text((d.sections.length + 1) + '. Sign-off', M, y - 10, 10.5, med, dark); y -= 16;
    factRow('Prepared By, Name & Date', d.prepared ? d.prepared.name + ', ' + day(d.prepared.at) : '');
    factRow('Reviewed By, Name & Date', d.reviewed ? d.reviewed.name + ', ' + day(d.reviewed.at) : '');
    pages.forEach(function (p, i) {
      page = p;
      text('PRIVATE & CONFIDENTIAL (ver. ' + d.version + ')', M, 34, 7.5, med, dark);
      var w = 'Page ' + (i + 1) + ' of ' + pages.length;
      text(w, R - width(w, 7.5, book), 34, 7.5, book, ink);
    });
  }

  window.ADspaceChecklists = { mount: mount, count: count, draw: draw };
})();
