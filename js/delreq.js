/* Delete requests (2026-11-17, the access restructure, release 2; the
   user: "Full control deletes; Edit files a request an admin approves").

   At Edit a section's Delete reads Request delete. Pressed, the screen
   asks its own question (the name typed back, as ever) with a Reason, and
   the call it then makes (a delete function and its arguments, or a
   delete from a table by its key) is kept as a request in place of being
   made: `delete_request_file`. Every admin is told; the record stays.

   An admin decides in Settings, Portal, Delete requests (`open`): Approve
   makes the very call the screen made, as the admin, so every check the
   delete holds still applies, then closes the request
   (`delete_request_done`); Decline asks a note. The requester is told
   either way, and may withdraw a request still waiting.

   What may be requested is the database's list (`delete_request_kinds`):
   a call it does not name is made as before, and refused as before. */
(function () {
  'use strict';
  var API = window.ADspaceAPI;
  var db = API && API.client;
  if (!db) return;
  var W = window.ADspaceWords || {};
  var esc = W.esc || function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return '&#' + c.charCodeAt(0) + ';'; }); };

  var kinds = null;          /* kind → { kind, section, word } */
  var sections = {};         /* section → true, where a kind asks it */
  var armed = null;          /* { section, host, at, reason } while a request is made */
  var bypass = false;        /* an admin's approval makes the call itself */
  var LINE = {
    title: 'Request delete',
    body: 'An admin approves the request before anything is deleted.',
    reason: 'Reason',
    done: 'Delete requested. An admin will decide.',
    withdrawn: 'Request withdrawn.'
  };

  function load() {
    if (kinds) return Promise.resolve(kinds);
    return Promise.resolve(db.rpc('delete_request_kinds')).then(function (r) {
      var list = (r && !r.error && Array.isArray(r.data)) ? r.data : [];
      kinds = {}; sections = {};
      list.forEach(function (k) { kinds[k.kind] = k; sections[k.section] = true; });
      return kinds;
    }).catch(function () { kinds = {}; return kinds; });
  }

  function A() { return window.ADspaceAdmin; }
  function may(k, l) { var a = A(); return Boolean(a && a.may && a.may(k, l)); }
  /* A Delete is a request where the section is at Edit but not Full
     control, and a kind asks that section. */
  function asksFor(section) {
    return Boolean(section) && Boolean(sections[section]) && may(section, 'work') && !may(section, 'manage');
  }
  function sectionOf(need) {
    var p = String(need || '').split(':');
    return p[1] === 'manage' ? p[0] : null;
  }
  function isDelete(it) {
    return it && it.getAttribute('data-g') === '6' && /^\s*Delete\s*$/.test(it.textContent || '');
  }

  /* A ⋯ is tidied as it shows (js/menu.js): its Delete, at Edit, becomes
     Request delete. */
  function adapt(menu) {
    if (!kinds || !menu || !menu.querySelectorAll) return;
    Array.prototype.forEach.call(menu.querySelectorAll('.kmenu-item[data-g="6"]'), function (it) {
      if (!isDelete(it)) return;
      var sec = sectionOf(it.getAttribute('data-need'));
      if (!asksFor(sec)) return;
      it.setAttribute('data-need', sec + ':work');
      it.setAttribute('data-req', sec);
      it.textContent = LINE.title;
    });
  }
  /* Whether a ⋯ holding only Delete is still drawn at Edit. */
  function liveItem(it) {
    return isDelete(it) && asksFor(sectionOf(it.getAttribute('data-need')));
  }

  /* The press arms the request; the screen's own handler runs on. */
  document.addEventListener('click', function (e) {
    var it = e.target && e.target.closest && e.target.closest('.kmenu-item[data-req]');
    if (!it) return;
    var open = document.querySelector('.kmenu-btn[aria-expanded="true"]');
    armed = { section: it.getAttribute('data-req'), host: open, at: Date.now(), reason: '' };
  }, true);
  function active() {
    if (armed && Date.now() - armed.at > 10 * 60 * 1000) armed = null;
    return Boolean(armed);
  }

  /* The question the screen asks: a Reason (or its own, where it asks
     one), its button Request delete. */
  function wraps(o) {
    return active() && o && (o.tone === 'danger' || /^Delete\b/.test(String(o.go || '')));
  }
  function fields(specs) {
    var own = specs.filter(function (f) { return f && /^Reason\b/.test(String(f.label || '')); })[0];
    if (own) { own.reasonToo = true; return specs; }
    return specs.concat([{ name: '__reason', label: LINE.reason, rows: 2, need: 'Enter a reason.' }]);
  }

  function said(e) {
    var c = (e && (e.error || e.code)) || e;
    return ({
      'bad-reason': 'Enter a reason of 3 to 500 characters.',
      already: 'A request to delete this is already waiting for an admin.',
      'too-many': 'Thirty requests have been made today. Try again tomorrow.',
      'not-found': 'This record no longer exists.',
      denied: 'You do not have permission to request this. Please ask an admin.',
      'may-delete': 'Reload the page to delete it.'
    })[c] || 'Not requested. Please try again.';
  }

  function tell(text, id) {
    var a = A();
    var host = armed && armed.host && armed.host.isConnected ? armed.host : null;
    if (a && a.undoHere && host && id) {
      a.undoHere(text, function () { withdraw(id); }, host);
      return;
    }
    if (window.ADspaceConfirm) window.ADspaceConfirm.ask({ title: LINE.title, body: text, go: 'Close', cancel: false });
  }

  /* The call kept in place of being made. The screen's own promise is left
     waiting: it never reads a refusal it would word as Not deleted. */
  function file(kind, args) {
    var why = armed ? armed.reason : '';
    var ask = function (reason) {
      return Promise.resolve(db.rpc('delete_request_file', { p_kind: kind, p_args: args || {}, p_reason: reason }));
    };
    var go = function (reason) {
      ask(reason).then(function (r) {
        var d = r && r.data;
        if (window.ADspaceConfirm && window.ADspaceConfirm.close) window.ADspaceConfirm.close();
        if (r && r.error) { tell(said('x')); return; }
        if (!d || !d.ok) { tell(said(d)); return; }
        tell(LINE.done, d.id);
      }).catch(function () { tell(said('x')); }).then(function () { armed = null; });
    };
    if (why) go(why);
    else if (window.ADspaceConfirm) {
      window.ADspaceConfirm.ask({ title: LINE.title, body: LINE.body, go: LINE.title,
        field: { label: LINE.reason, rows: 2, need: 'Enter a reason.' } }, function (v) { go(v); });
    }
    return new Promise(function () {});
  }

  function withdraw(id) {
    Promise.resolve(db.rpc('delete_request_withdraw', { p_id: id })).then(function (r) {
      var d = r && r.data;
      if (d && d.ok) tell(LINE.withdrawn);
    });
  }

  /* The client's calls, read where a request is armed. */
  var rpc = db.rpc;
  db.rpc = function (name, args) {
    if (!bypass && active() && kinds && kinds['rpc:' + name] && kinds['rpc:' + name].section === armed.section) {
      return file('rpc:' + name, args);
    }
    return rpc.apply(db, arguments);
  };
  var from = db.from;
  db.from = function (table) {
    var b = from.apply(db, arguments);
    var k = kinds && kinds['table:' + table];
    if (!k || !b || !b.delete) return b;
    var del = b.delete;
    b.delete = function () {
      if (bypass || !active() || k.section !== armed.section) return del.apply(b, arguments);
      /* The key the screen names (eq on it), kept as the call's argument. */
      var args = {}, q = {};
      ['select', 'neq', 'is', 'in', 'order', 'limit', 'single', 'maybeSingle', 'match', 'filter'].forEach(function (m) { q[m] = function () { return q; }; });
      q.eq = function (col, val) { args[col] = val; return q; };
      q.then = function (ok, bad) { return file(k.kind, args).then(ok, bad); };
      q.catch = function () { return q; };
      return q;
    };
    return b;
  };

  /* ---- An admin's list: Settings, Portal, Delete requests --------------- */
  function replay(kind, args) {
    var p = kind.split(':'), name = p[1];
    bypass = true;
    var run;
    try {
      if (p[0] === 'rpc') run = db.rpc(name, args || {});
      else {
        var q = db.from(name).delete();
        Object.keys(args || {}).forEach(function (c) { q = q.eq(c, args[c]); });
        run = q.select ? q.select() : q;
      }
    } finally { bypass = false; }
    return Promise.resolve(run).then(function (r) {
      if (r && r.error) return { ok: false, why: r.error.message || 'Refused.' };
      var d = r && r.data;
      if (p[0] === 'table') return Array.isArray(d) && d.length ? { ok: true } : { ok: false, why: 'Not deleted. The database refused the request.' };
      if (d && d.error) return { ok: false, why: String(d.error) };
      if (d === false) return { ok: false, why: 'Not deleted.' };
      return { ok: true };
    });
  }

  var box = null;
  function sheet() {
    if (box) return box;
    box = document.createElement('div');
    box.className = 'sheet';
    box.id = 'delReqSheet';
    box.hidden = true;
    box.innerHTML = '<div class="sheet-scrim" data-close></div>' +
      '<div class="sheet-card formsheet" role="dialog" aria-modal="true" aria-labelledby="delReqTitle" tabindex="-1">' +
        '<div class="sheet-head"><h2 id="delReqTitle">Delete requests</h2>' +
          '<button class="iconbtn sheet-x" data-close type="button" aria-label="Close">' +
          '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg></button></div>' +
        '<div class="sheet-body"><div id="delReqList"></div></div>' +
      '</div>';
    document.body.appendChild(box);
    box.addEventListener('click', function (e) {
      if (e.target.closest('[data-close]')) { show(false); return; }
      var b = e.target.closest('button[data-act]');
      if (b) act(b);
    });
    return box;
  }
  function show(on) {
    sheet();
    if (window.ADspaceSheet && window.ADspaceSheet.sheet) window.ADspaceSheet.sheet('delReqSheet', on);
    else box.hidden = !on;
    if (on) paint();
  }
  var rows = [];
  function when(at) {
    var C = window.ADspaceClock;
    return C && C.date ? C.date(at) + (C.clock ? ', ' + C.clock(at) : '') : String(at || '').slice(0, 10);
  }
  var STATE = { open: ['Waiting', 'is-warn'], approving: ['Waiting', 'is-warn'], approved: ['Deleted', 'is-ok'],
    declined: ['Declined', 'is-off'], withdrawn: ['Withdrawn', 'is-off'] };
  function paint() {
    var host = document.getElementById('delReqList');
    host.innerHTML = '<p class="emptyline">Loading…</p>';
    Promise.resolve(db.rpc('delete_requests_list')).then(function (r) {
      var d = r && r.data;
      if (r && r.error || !d || !d.ok) { host.innerHTML = '<p class="emptyline">Could not load the requests.</p>'; return; }
      rows = d.rows || [];
      if (!rows.length) { host.innerHTML = '<p class="emptyline">No requests.</p>'; return; }
      host.innerHTML = rows.map(function (x) {
        var st = STATE[x.state] || ['', ''];
        var waiting = x.state === 'open' || x.state === 'approving';
        var acts = waiting && d.admin
          ? '<div class="dr-acts"><button class="btn btn-sm" data-act="decline" data-id="' + esc(x.id) + '" type="button">Decline</button>' +
            '<button class="btn btn-sm btn-primary" data-act="approve" data-id="' + esc(x.id) + '" type="button">Approve</button></div>'
          : waiting && x.mine ? '<div class="dr-acts"><button class="btn btn-sm" data-act="withdraw" data-id="' + esc(x.id) + '" type="button">Withdraw</button></div>' : '';
        return '<div class="dr-row" data-id="' + esc(x.id) + '">' +
          '<div class="dr-main"><p class="dr-name">' + esc(x.word) + ' · ' + esc(x.label) + '</p>' +
            '<p class="dr-meta">' + esc(x.by || '') + ' · ' + esc(when(x.at)) + '</p>' +
            '<p class="dr-why">' + esc(x.reason) + '</p>' +
            (x.note ? '<p class="dr-meta">' + esc((x.decided_by ? x.decided_by + ': ' : '') + x.note) + '</p>' : '') +
            '<p class="msg dr-msg" hidden></p></div>' +
          '<div class="dr-end"><span class="chip chip-state ' + st[1] + '">' + st[0] + '</span>' + acts + '</div></div>';
      }).join('');
    }).catch(function () { host.innerHTML = '<p class="emptyline">Could not load the requests.</p>'; });
  }
  function say(btn, text) {
    var m = btn.closest('.dr-row').querySelector('.dr-msg');
    m.hidden = !text; m.textContent = text || ''; m.className = 'msg err dr-msg';
  }
  function act(btn) {
    var id = btn.getAttribute('data-id'), a = btn.getAttribute('data-act');
    var x = rows.filter(function (r) { return r.id === id; })[0];
    if (!x) return;
    var C = window.ADspaceConfirm;
    if (a === 'withdraw') {
      Promise.resolve(db.rpc('delete_request_withdraw', { p_id: id })).then(function () { paint(); });
      return;
    }
    if (a === 'decline') {
      C.ask({ title: 'Decline request?', body: x.word + ' · ' + x.label, go: 'Decline',
        field: { label: 'Note', rows: 2, need: 'Enter a note.' } }, function (note) {
        Promise.resolve(db.rpc('delete_request_decide', { p_id: id, p_approve: false, p_note: note })).then(function (r) {
          var d = r && r.data;
          if (!d || !d.ok) say(btn, 'Not saved. Please try again.');
          else paint();
        });
      });
      return;
    }
    C.ask({ title: 'Delete?', body: x.word + ' · ' + x.label + '. Requested by ' + (x.by || 'a colleague') + ': ' + x.reason + ' This cannot be undone.',
      go: 'Delete', tone: 'danger' }, function () {
      Promise.resolve(db.rpc('delete_request_decide', { p_id: id, p_approve: true, p_note: null })).then(function (r) {
        var d = r && r.data;
        if (!d || !d.ok) { say(btn, 'Not deleted. Please try again.'); return null; }
        return replay(d.kind, d.args).then(function (res) {
          return Promise.resolve(db.rpc('delete_request_done', { p_id: id, p_ok: res.ok, p_error: res.ok ? null : res.why })).then(function () {
            if (!res.ok) { paint(); setTimeout(function () { var b = document.querySelector('.dr-row[data-id="' + id + '"] .dr-acts button'); if (b) say(b, res.why); }, 400); }
            else paint();
          });
        });
      });
    });
  }

  window.ADspaceDelReq = {
    load: load, adapt: adapt, liveItem: liveItem,
    asking: active, wraps: wraps, fields: fields,
    title: function () { return LINE.title + '?'; },
    body: function (b) { return (b ? b.replace(/\s*This cannot be undone\.?\s*$/, '').replace(/\s*There is no restore\.?\s*$/, '') + ' ' : '') + LINE.body; },
    go: function () { return LINE.title; },
    reason: function (v) { if (armed && v) armed.reason = v; },
    open: function () { show(true); }
  };
}());
