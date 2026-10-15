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
    'not-started': 'Nothing has been recorded on this checklist.'
  };
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

  function itemHtml(d, s, it, off) {
    var key = s.key + '.' + it.key, a = d.answers[key] || {}, can = editable(d) && !off;
    var hint = (d.hints || {})[key];
    if (it.kind === 'tick') {
      var done = a.state === 'done', na = a.state === 'na';
      var by = (done || na) && a.by ? (na ? 'Not applicable · ' : '') + a.by + ', ' + day(a.at) : '';
      return '<div class="ck-row is-tick' + (done ? ' is-done' : '') + (na ? ' is-na' : '') + '" data-key="' + esc(key) + '">' +
        (can ? '<button class="tcheck' + (done ? ' is-done' : '') + '" type="button" data-a="tick" aria-pressed="' + done + '"' +
                 (na ? ' disabled' : '') + ' aria-label="' + esc(it.label) + '"></button>'
             : '<span class="tcheck' + (done ? ' is-done' : '') + '" aria-hidden="true"></span>') +
        '<span class="ck-lab"><b>' + esc(it.label) + '</b>' + (it.detail ? '<small>' + esc(it.detail) + '</small>' : '') +
          (hint && !done ? '<small class="ck-hint">' + esc(hint) + '</small>' : '') +
          (by ? '<small class="ck-by">' + esc(by) + '</small>' : '') + '</span>' +
        (can ? '<textarea class="input input-sm ck-note" data-oneline data-nodraft rows="1" placeholder="Notes" aria-label="' +
                 esc('Notes, ' + it.label) + '">' + esc(a.note || '') + '</textarea>'
             : '<span class="ck-note-read">' + esc(a.note || '') + '</span>') +
        (can && !done ? '<button class="btn-quiet btn-sm ck-na" type="button" data-a="na">' + (na ? 'Applicable' : 'Not applicable') + '</button>' : '') +
      '</div>';
    }
    var v = valueOf(d, key), field;
    if (it.kind === 'multi' || it.kind === 'choice') {
      var on = it.kind === 'multi' ? (Array.isArray(v) ? v : []) : (v ? [v] : []);
      field = '<span class="ck-chips" role="group" aria-label="' + esc(it.label) + '">' + it.choices.map(function (c) {
        var sel = on.indexOf(c) >= 0;
        return can ? '<button class="ck-chip' + (sel ? ' is-on' : '') + '" type="button" data-a="chip" data-c="' + esc(c) + '" aria-pressed="' + sel + '">' + esc(c) + '</button>'
                   : (sel ? '<span class="ck-chip is-on">' + esc(c) + '</span>' : '');
      }).join('') + (!can && !on.length ? '<span class="muted">Not set</span>' : '') + '</span>';
    } else {
      field = can
        ? '<textarea class="input ck-text" data-nodraft' + (Number(it.rows) > 1 ? ' rows="' + it.rows + '"' : ' data-oneline rows="1"') +
            ' aria-label="' + esc(it.label) + '">' + esc(v || '') + '</textarea>'
        : '<span class="ck-text-read">' + (v ? esc(v) : '<span class="muted">Not set</span>') + '</span>';
    }
    return '<div class="ck-row is-field" data-key="' + esc(key) + '" data-kind="' + it.kind + '"><span class="ck-lab"><b>' + esc(it.label) + '</b></span>' + field + '</div>';
  }

  function paint() {
    var d = V.data, c = count(d), st = stateOf(d), na = d.sections_na || [];
    var cl = V.ctx.client;
    var html = '<div class="ck-head"><button class="btn-quiet btn-sm ck-back" type="button" data-a="back">All checklists</button>' +
      '<div class="ck-title"><h3>' + esc(d.title) + '</h3><small>Ver. ' + esc(d.version) + ' · ' + esc(d.lead || '') + '</small></div>' +
      '<span class="chip-state ' + st[1] + '">' + esc(st[0]) + '</span>' +
      '<button class="btn btn-sm" type="button" data-a="pdf">Download</button></div>' +
      '<section class="ovcard ck-sec ck-facts"><dl class="ovfacts"><div><dt>Client / Brand</dt><dd>' + esc(cl.name) + '</dd></div>' +
        '<div><dt>Project Manager</dt><dd>' + esc(cl.owner || 'Not set') + '</dd></div>' +
        '<div><dt>Progress</dt><dd>' + c.done + ' of ' + c.n + ' done</dd></div></dl></section>' +
      '<div class="msg" id="ckMsg"></div>';
    d.sections.forEach(function (s, i) {
      var off = na.indexOf(s.key) >= 0;
      html += '<section class="ovcard ck-sec' + (off ? ' is-off' : '') + '" data-sec="' + esc(s.key) + '"><div class="ck-sec-head"><h4 class="fsec-h">' +
        (i + 1) + '. ' + esc(s.title) + '</h4>' +
        (s.platform && editable(d) ? '<button class="btn-quiet btn-sm" type="button" data-a="secna">' + (off ? 'Applicable' : 'Not applicable') + '</button>'
          : off ? '<span class="chip">Not applicable</span>' : '') + '</div>' +
        (s.note ? '<p class="ck-sec-note">' + esc(s.note) + '</p>' : '') +
        (off ? '' : s.items.map(function (it) { return itemHtml(d, s, it, off); }).join('')) + '</section>';
    });
    /* The sign-off: prepared by one colleague, reviewed by another. */
    var acts = '', me = d.me, prep = d.prepared;
    if (d.status === 'open' && d.can_work) acts = '<button class="btn btn-primary" type="button" data-a="prepare">Mark as prepared</button>';
    if (d.status === 'prepared' && d.can_work) {
      acts = (prep && prep.id !== me ? '<button class="btn btn-primary" type="button" data-a="review">Sign off</button>' : '') +
        '<button class="btn" type="button" data-a="return">Send back</button>';
    }
    if (d.status === 'signed' && d.can_manage) acts = '<button class="btn" type="button" data-a="reopen">Reopen</button>';
    html += '<section class="ovcard ck-sec ck-sign"><h4 class="fsec-h">Sign-off</h4><dl class="ovfacts">' +
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
    host.querySelector('[data-a="pdf"]').addEventListener('click', function () { download(this); });
    Array.prototype.forEach.call(host.querySelectorAll('.ck-row'), function (row) {
      var key = row.getAttribute('data-key');
      var tk = row.querySelector('[data-a="tick"]');
      if (tk) tk.addEventListener('click', function () {
        tk.disabled = true;
        send({ p_item: key, p_state: row.classList.contains('is-done') ? '' : 'done' }, row, paint);
      });
      var na = row.querySelector('[data-a="na"]');
      if (na) na.addEventListener('click', function () {
        na.disabled = true;
        send({ p_item: key, p_state: row.classList.contains('is-na') ? '' : 'na' }, row, paint);
      });
      var note = row.querySelector('.ck-note');
      if (note) note.addEventListener('change', function () { send({ p_item: key, p_note: note.value }); });
      var tx = row.querySelector('.ck-text');
      if (tx) tx.addEventListener('change', function () { send({ p_item: key, p_value: tx.value.trim() }); });
      Array.prototype.forEach.call(row.querySelectorAll('[data-a="chip"]'), function (b) {
        b.addEventListener('click', function () {
          var kind = row.getAttribute('data-kind'), c = b.getAttribute('data-c');
          var cur = Array.prototype.filter.call(row.querySelectorAll('.ck-chip.is-on'), function (x) { return true; })
            .map(function (x) { return x.getAttribute('data-c'); });
          var next;
          if (kind === 'multi') next = cur.indexOf(c) >= 0 ? cur.filter(function (x) { return x !== c; }) : cur.concat(c);
          else next = cur[0] === c ? '' : c;
          send({ p_item: key, p_value: next }, row, function (x) {
            var v = (x.answers[key] || {}).value;
            var on = kind === 'multi' ? (v || []) : (v ? [v] : []);
            Array.prototype.forEach.call(row.querySelectorAll('[data-a="chip"]'), function (y) {
              var s2 = on.indexOf(y.getAttribute('data-c')) >= 0;
              y.classList.toggle('is-on', s2); y.setAttribute('aria-pressed', String(s2));
            });
          });
        });
      });
    });
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
      text('FOR INTERNAL USE', M + 150, H - 50, 7.5, med, dark);
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
