/* ADspace records — one way to draw what happened.
 *
 * Every history in the console (the Activity record, a client's and a
 * campaign's Activity, a task's log and its recent activity) is drawn here:
 * one line per entry, the time and who in the quiet ink, then what happened,
 * on what, and what changed, under a heading per day. The user, 2026-09-26:
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
 * An item is { at, who, what, on, key, detail, tone, sticky }, newest first.
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

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function time(iso) {
    var d = new Date(iso);
    return isNaN(d.getTime()) ? '' : d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
  }
  function day(iso) {
    var d = new Date(iso);
    if (!iso || isNaN(d.getTime())) return 'Undated';
    var now = new Date();
    var same = function (a, b) { return a.toDateString() === b.toDateString(); };
    if (same(d, now)) return 'Today';
    if (same(d, new Date(now.getTime() - 864e5))) return 'Yesterday';
    return d.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' }).replace(/\bSep\b/, 'Sept');
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
      if (top && !top.sticky && !x.sticky && top.who === x.who && top.what === x.what &&
          top.thing === thing && (thing !== '' || (x.detail || '') === top.first) &&
          !isNaN(t) && !isNaN(tt) && tt - t <= RUN_MS && tt - t >= 0) {
        top.n += 1;
        top.last = x.at;
        if (x.detail && top.details.indexOf(x.detail) < 0) top.details.unshift(x.detail);
        return;
      }
      out.push({ at: x.at, last: x.at, who: x.who, what: x.what, on: x.on, tone: x.tone, thing: thing,
                 first: x.detail || '', sticky: x.sticky, n: 1, details: x.detail ? [x.detail] : [] });
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
  function merged(list) {
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

  function line(x) {
    var detail = merged(x.details);
    return '<li class="recline">' +
      '<time class="rl-time" datetime="' + esc(x.at || '') + '">' + esc(time(x.at)) + '</time>' +
      '<p class="rl-body">' +
        (x.who ? '<span class="rl-who">' + esc(x.who) + '</span> ' : '') +
        '<b class="rl-what' + (x.tone ? ' ' + esc(x.tone) : '') + '">' + esc(x.what) + '</b>' +
        (x.on ? ' <span class="rl-on">' + esc(x.on) + '</span>' : '') +
        (detail ? '<span class="rl-detail">' + (x.on ? ': ' : ' ') + esc(detail) + '</span>' : '') +
        (x.n > 1 ? ' <span class="rl-n">\u00b7 ' + x.n + ' times</span>' : '') +
      '</p></li>';
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

  /* A line longer than three lines is cut at three and opens on a press.
     Which lines are long is only known once they are drawn at a width, and
     a list painted while its pane is hidden has none, so each list is
     measured again whenever its size changes. */
  var RO = window.ResizeObserver ? new ResizeObserver(function (es) {
    es.forEach(function (e) { measure(e.target); });
  }) : null;
  function measure(host) {
    Array.prototype.forEach.call(host.querySelectorAll('.recline'), function (li) {
      if (li.classList.contains('is-open')) return;
      var body = li.querySelector('.rl-body');
      if (!body || !body.clientHeight) return;
      var long = body.scrollHeight > body.clientHeight + 1;
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
    });
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

  window.ADspaceRecords = { paint: paint, fold: fold, day: day, time: time, changes: changes };
})();
