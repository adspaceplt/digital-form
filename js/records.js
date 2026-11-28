/* Records — one way to draw what happened.
 *
 * Every history in the console (the Activity record, a client's and a
 * campaign's Activity, a task's log and its recent activity) is drawn here:
 * one entry each, the time and who in the quiet ink, then what happened and
 * on what, with what changed on a second row, under a heading per day. The user, 2026-09-26:
 * the records were "too brief", "too airy", and "all terms used are
 * different".
 *
 * A run of the same act by the same person on the same thing within ten
 * minutes is one line, its details joined in the order they were made, so
 * six saves of one form read once. A sticky entry (Performance, an HR
 * document, a void or a delete, billing, money, access) is never folded
 * into another, because each of those is read on its own.
 *
 *   ADspaceRecords.paint(host, items, { empty, limit, offset, days })
 *   ADspaceRecords.fold(items)
 *   ADspaceRecords.changes(before, after, [[key, label, fmt]], { names })
 *
 * An item is { at, who, what, on, key, detail, tone, sticky, facts }, newest
 * first. `facts` ([[label, value]], a function's line alone) is drawn as the
 * fact list the entry opens to, and such an entry never folds.
 * `key` is what the line is about where the subject does not say it (a
 * document's reference, or the record a pane belongs to); without either,
 * only identical lines fold, because a line about nothing named cannot be
 * said to be about the same thing as another (2026-09-27).
 *
 * A field changed twice in one run reads as its path (User group: Admin →
 * Team → Admin), and a run reads "· 3 times". A long line shows three lines
 * and opens on a press or Enter.
 */
(function () {
  'use strict';

  var RUN_MS = 10 * 60 * 1000;

  function esc(s) { return window.ADspaceWords.esc(s); }
  /* Times and days are Malaysia's (js/clock.js), whatever the device's
     clock: a history read abroad dates its entries as the office does. */
  var CK = window.ADspaceClock;
  function time(iso) { return iso ? CK.time(iso) : ''; }
  function day(iso) {
    var d = iso ? CK.day(iso) : '';
    if (!d) return 'Undated';
    var today = CK.today();
    if (d === today) return 'Today';
    if (d === CK.addDays(today, -1)) return 'Yesterday';
    return CK.date(d);
  }

  /* Newest first in, newest first out. An entry joins the one above it when
     the same person did the same thing to the same subject within the run;
     its detail goes before the newer one's, so the line reads in the order
     the changes were made. */
  function fold(items) {
    var out = [];
    (items || []).forEach(function (x) {
      var top = out[out.length - 1];
      var t = new Date(x.at).getTime(), tt = top ? new Date(top.last).getTime() : NaN;
      var thing = thingOf(x);
      if (top && !top.sticky && !x.sticky && !top.facts && !x.facts && top.who === x.who && top.what === x.what &&
          top.thing === thing && (thing !== '' || (x.detail || '') === top.first) &&
          !isNaN(t) && !isNaN(tt) && tt - t <= RUN_MS && tt - t >= 0) {
        top.n += 1;
        top.last = x.at;
        if (x.detail && top.details.indexOf(x.detail) < 0) top.details.unshift(x.detail);
        return;
      }
      out.push({ at: x.at, last: x.at, who: x.who, what: x.what, on: x.on, tone: x.tone, thing: thing,
                 first: x.detail || '', sticky: x.sticky, facts: x.facts || null, n: 1, details: x.detail ? [x.detail] : [] });
    });
    return out;
  }

  function thingOf(x) {
    return String(x.key != null ? x.key : (x.on || ''));
  }
  /* A run's details, oldest first, as one: a field changed more than once
     reads as its path, never as two changes that seem to contradict each
     other ("Admin → Team; Team → Admin"). A detail that is not a list of
     "Label: old → new" is kept whole, once. */
  var MOVE = /^(.+?): (.*) \u2192 (.*)$/;
  /* A run keyed on one creator names them once: "恩比 · back to Submitted;
     back to Pending draft", not the name before every step. */
  var LEAD = /^(.+?) \u00b7 (.+)$/;
  function merged(list) {
    var lead = list.length > 1 && LEAD.exec(String(list[0])) ? LEAD.exec(String(list[0]))[1] : null;
    if (lead && list.every(function (d) { var m = LEAD.exec(String(d)); return m && m[1] === lead; })) {
      return lead + ' \u00b7 ' + merged(list.map(function (d) { return LEAD.exec(String(d))[2]; }));
    }
    var seen = {}, order = [];
    list.forEach(function (d) {
      var parts = String(d).split('; ');
      if (!parts.every(function (s) { return MOVE.test(s); })) {
        if (!seen['t:' + d]) { seen['t:' + d] = { text: d }; order.push('t:' + d); }
        return;
      }
      parts.forEach(function (s) {
        var m = MOVE.exec(s), k = 'f:' + m[1], hit = seen[k];
        if (!hit) { seen[k] = { label: m[1], path: [m[2], m[3]] }; order.push(k); return; }
        if (hit.path[hit.path.length - 1] !== m[2]) hit.path.push(m[2]);
        hit.path.push(m[3]);
      });
    });
    return order.map(function (k) {
      var x = seen[k];
      return x.text != null ? x.text : x.label + ': ' + x.path.join(' \u2192 ');
    }).join('; ');
  }

  /* Two rows (the user, 2026-09-27: "split two rows would be better"): who
     did what, and to what, on the first, which reads down the column in one
     line; what changed on the second, in the quieter ink, only where there
     is anything to say. A wrap no longer breaks "Pending draft" across the
     time column's edge. */
  function line(x) {
    var detail = merged(x.details);
    var facts = x.facts && x.facts.length ? '<dl class="ovfacts rl-facts">' + x.facts.map(function (f) {
      return '<div><dt>' + esc(f[0]) + '</dt><dd>' + esc(f[1]) + '</dd></div>';
    }).join('') + '</dl>' : '';
    return '<li class="recline' + (facts ? ' has-facts' : '') + '">' +
      '<time class="rl-time" datetime="' + esc(x.at || '') + '">' + esc(time(x.at)) + '</time>' +
      '<div class="rl-body"><div class="rl-head">' +
        (x.who ? '<span class="rl-who">' + esc(x.who) + '</span> ' : '') +
        '<b class="rl-what' + (x.tone ? ' ' + esc(x.tone) : '') + '">' + esc(x.what) + '</b>' +
        (x.on ? ' <span class="rl-on">' + esc(x.on) + '</span>' : '') +
        (x.n > 1 ? ' <span class="rl-n">\u00b7 ' + x.n + ' times</span>' : '') +
      '</div>' +
      (detail ? '<div class="rl-detail">' + esc(detail) + '</div>' : '') + facts +
      '</div>' +
      (x.who ? '<span class="rl-by">' + esc(x.who) + '</span>' : '') + '</li>';
  }

  function paint(host, items, o) {
    if (!host) return;
    o = o || {};
    var rows = fold(items);
    if (o.offset) rows = rows.slice(o.offset);
    if (o.limit) rows = rows.slice(0, o.limit);
    if (!rows.length) {
      host.innerHTML = o.empty === false ? '' : '<div class="empty">' + esc(o.empty || 'No entries.') + '</div>';
      return;
    }
    var html = '', current = null;
    rows.forEach(function (x) {
      var d = o.days === false ? '' : day(x.at);
      if (d !== current) {
        if (current !== null) html += '</ul>';
        if (d) html += '<h4 class="recday">' + esc(d) + '</h4>';
        html += '<ul class="reclines">';
        current = d;
      }
      html += line(x);
    });
    host.innerHTML = '<div class="reclist">' + html + '</ul></div>';
    clampWatch(host);
  }

  /* A detail longer than three lines is cut at three and opens on a press.
     Which lines are long is only known once they are drawn at a width, and
     a list painted while its pane is hidden has none, so each list is
     measured again whenever its size changes. */
  var RO = window.ResizeObserver ? new ResizeObserver(function (es) {
    es.forEach(function (e) { measure(e.target); });
  }) : null;
  /* A history with room reads one line an entry, as a table does (the
     user, 2026-10-01: a long log should run down quickly): the time, what
     happened and on what, what changed in the quiet ink cut at the line's
     end, and who at the right edge. A rail or a phone reads two lines, each
     cut at its end; a press opens the whole entry. */
  var WIDE = 720;
  function measure(host) {
    var list = host.querySelector('.reclist');
    var wide = !!list && host.clientWidth >= WIDE;
    if (list) list.classList.toggle('is-wide', wide);
    Array.prototype.forEach.call(host.querySelectorAll('.recline'), function (li) {
      if (li.classList.contains('is-open')) return;
      /* An entry with facts always opens to them. */
      if (li.classList.contains('has-facts')) { mark(li, true); return; }
      var body = li.querySelector('.rl-detail'), head = li.querySelector('.rl-head');
      if (wide) {
        var cut = function (el) { return !!el && el.clientWidth > 0 && el.scrollWidth > el.clientWidth + 1; };
        if (!head || !head.clientWidth) { li.classList.remove('is-long'); return; }
        mark(li, cut(head) || cut(body));
        return;
      }
      var headCut = !!head && head.clientWidth > 0 && head.scrollWidth > head.clientWidth + 1;
      if (!body || !body.clientHeight) { mark(li, headCut); return; }
      mark(li, headCut || body.scrollHeight > body.clientHeight + 1);
    });
  }
  function mark(li, long) {
    li.classList.toggle('is-long', long);
    if (long) {
      li.tabIndex = 0;
      li.setAttribute('role', 'button');
      li.setAttribute('aria-expanded', 'false');
    } else {
      li.removeAttribute('tabindex');
      li.removeAttribute('role');
      li.removeAttribute('aria-expanded');
    }
  }
  function flip(li) {
    if (!li || !li.classList.contains('is-long')) return;
    var open = !li.classList.contains('is-open');
    li.classList.toggle('is-open', open);
    li.setAttribute('aria-expanded', String(open));
  }
  function clampWatch(host) {
    if (!host.__recWired) {
      host.__recWired = true;
      host.addEventListener('click', function (e) {
        if (e.target.closest('a, button, input, select, textarea')) return;
        if (window.getSelection && String(window.getSelection())) return;
        flip(e.target.closest('.recline'));
      });
      host.addEventListener('keydown', function (e) {
        if ((e.key === 'Enter' || e.key === ' ') && e.target.classList && e.target.classList.contains('recline')) {
          e.preventDefault();
          flip(e.target);
        }
      });
      if (RO) RO.observe(host);
    }
    measure(host);
  }

  /* What a save changed, as one detail: "Label: old → new" for each field
     whose value moved, in the order given, an empty value read as "not
     set". `o.names` names the fields and withholds the values, for a part
     somebody reading the record may not be allowed to read (billing, HR).
     A save that changed nothing returns ''. */
  function norm(v) {
    if (v === null || v === undefined) return '';
    if (typeof v === 'boolean') return v ? 'Yes' : 'No';
    return String(v).replace(/\s+/g, ' ').trim();
  }
  function clip(v) { return v.length > 60 ? v.slice(0, 57) + '…' : v; }
  function changes(before, after, fields, o) {
    o = o || {};
    before = before || {};
    var out = [];
    (fields || []).forEach(function (f) {
      var key = f[0], label = f[1], fmt = f[2];
      if (!Object.prototype.hasOwnProperty.call(after, key)) return;
      var a = norm(before[key]), b = norm(after[key]);
      if (a === b) return;
      if (o.names) { out.push(label + (a ? (b ? ' changed' : ' cleared') : ' set')); return; }
      var show = function (v) { return v ? clip(fmt ? norm(fmt(v)) : v) : 'not set'; };
      out.push(label + ': ' + show(a) + ' → ' + show(b));
    });
    return out.join('; ');
  }

  /* THE LAST DAYS FIRST (ACTIVITY KEPT BY KIND, 2026-11-28). Every list
     of `activity_log` rows opens on its last days (Settings, Activity
     history, `activity_window_days`, 7 before it is read), newest first;
     Show more reads older entries a page at a time.
       var pg = ADspaceRecords.pager(function () { return db.from(…).select(…).eq(…); }, 50);
       pg.first() / pg.next()  → the read's answer; pg.more, pg.floor, pg.days
     `query` hands back a fresh builder each call, filtered but neither
     ordered nor limited. `floor` is the oldest moment the list now holds
     whole (null once every row is read). */
  function days() {
    var M = window.ADspaceMoney, n = M && M.setting ? Number(M.setting('activity_window_days')) : NaN;
    return n > 0 ? n : 7;
  }
  function since(n) { return new Date(Date.now() - (n || days()) * 864e5).toISOString(); }
  function pager(query, page) {
    page = page || 50;
    var oldest = null;
    var self = { more: false, floor: since(), days: days() };
    var newest = function (q) { return q.order('created_at', { ascending: false }); };
    function took(rows) { if (rows.length) oldest = rows[rows.length - 1].created_at; }
    self.first = function () {
      self.days = days(); self.floor = since(self.days); oldest = null; self.more = false;
      return newest(query().gte('created_at', self.floor)).limit(page).then(function (r) {
        if (r.error) return r;
        var rows = r.data || [];
        took(rows);
        if (rows.length >= page) { self.more = true; return r; }
        /* A short window: one row older says whether Show earlier has
           anything to read. */
        return newest(query().lt('created_at', self.floor)).limit(1).then(function (o) {
          self.more = !o.error && (o.data || []).length > 0;
          return r;
        });
      });
    };
    self.next = function () {
      return newest(query().lt('created_at', oldest || self.floor)).limit(page).then(function (r) {
        if (r.error) return r;
        var rows = r.data || [];
        took(rows);
        self.more = rows.length >= page;
        self.floor = self.more ? oldest : null;
        return r;
      });
    };
    return self;
  }
  /* The press under a list that reads its earlier entries: disabled while
     the read is out, gone with the list's next paint. */
  function earlier(host, press) {
    if (!host) return null;
    var more = document.createElement('div');
    more.className = 'act-more';
    more.innerHTML = '<button class="btn btn-sm" type="button" data-a="earlier">' + esc(window.ADspaceWords.line.earlier()) + '</button>';
    host.appendChild(more);
    more.firstChild.addEventListener('click', function () { this.disabled = true; press(this); });
    return more.firstChild;
  }
  function none(n) { return window.ADspaceWords.line.recentNone(n || days()); }

  window.ADspaceRecords = { paint: paint, fold: fold, day: day, time: time, changes: changes,
    pager: pager, earlier: earlier, none: none, days: days };
})();
