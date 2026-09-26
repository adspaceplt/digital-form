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
 *
 * An item is { at, who, what, on, detail, tone, sticky }, newest first.
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
    return d.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });
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
      if (top && !top.sticky && !x.sticky && top.who === x.who && top.what === x.what &&
          (top.on || '') === (x.on || '') && !isNaN(t) && !isNaN(tt) && tt - t <= RUN_MS && tt - t >= 0) {
        top.n += 1;
        top.last = x.at;
        if (x.detail && top.details.indexOf(x.detail) < 0) top.details.unshift(x.detail);
        return;
      }
      out.push({ at: x.at, last: x.at, who: x.who, what: x.what, on: x.on, tone: x.tone,
                 sticky: x.sticky, n: 1, details: x.detail ? [x.detail] : [] });
    });
    return out;
  }

  function line(x) {
    var detail = x.details.join('; ');
    return '<li class="recline">' +
      '<time class="rl-time" datetime="' + esc(x.at || '') + '">' + esc(time(x.at)) + '</time>' +
      '<p class="rl-body">' +
        (x.who ? '<span class="rl-who">' + esc(x.who) + '</span> ' : '') +
        '<b class="rl-what' + (x.tone ? ' ' + esc(x.tone) : '') + '">' + esc(x.what) + '</b>' +
        (x.on ? ' <span class="rl-on">' + esc(x.on) + '</span>' : '') +
        (detail ? '<span class="rl-detail">' + (x.on ? ': ' : ' ') + esc(detail) + '</span>' : '') +
        (x.n > 1 ? ' <span class="rl-n">×' + x.n + '</span>' : '') +
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
  }

  window.ADspaceRecords = { paint: paint, fold: fold, day: day, time: time };
})();
