/* ADspace charts — one way to draw a figure.
 *
 * Every chart in the console and the client portal is drawn here, in the
 * page's own tokens, so it follows the theme and reads in the same words as
 * the table beside it. Four shapes, each for one kind of question:
 *
 *   bars     how much of each thing (a stage, a person, a step): a label and
 *            its figure on one line, the bar under them, an optional mark
 *            on the bar (a capacity, a target). Always printed, never hovered.
 *   columns  how a count moves month by month, one or more series side by
 *            side or stacked; the figure on hover or a tap.
 *   line     how one measure moves over time; the figure on hover or a tap.
 *   pie      the share of a whole, only for two to five slices; anything
 *            else is drawn as bars, because a sixth slice cannot be read.
 *
 * Under every chart its figures fold as a table (`details.fmore`), so the
 * numbers are there for a keyboard, a screen reader and a person who wants
 * to copy them, and the chart itself is an image with a name.
 *
 *   ADspaceChart.draw(host, spec) → the card
 *   spec: { kind, title | name, rows | cats + series, fmt, stacked, max,
 *           markLabel, valueHead, empty, table }
 *     name    the chart's name, where the section's heading stands over it
 *     none    what a month with no figure reads as on a line ("No figure")
 *     rows    [{ label, value, tone, note, noteTone, mark }]    bars, pie
 *     cats    [{ label, long, values: [n, n] }]                 columns, line
 *     series  [{ label, tone }]
 *     tone    '' (ink), 'ok', 'warn', 'err', 'mute'
 *     table   { heads: [...], rows: [[...]] } where the default is not right
 */
(function () {
  'use strict';

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function num(v) { return Number(v) || 0; }
  function plain(v) { return num(v).toLocaleString('en-GB'); }

  /* The top of the scale: the next 1, 2, 2.5 or 5 of the right power of ten,
     so a gridline reads as a round number and the tallest mark never
     touches the frame. */
  function nice(v) {
    v = Math.max(0, num(v));
    if (!v) return 1;
    var p = Math.pow(10, Math.floor(Math.log(v) / Math.LN10));
    var f = v / p;
    var step = f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10;
    return step * p;
  }
  function pct(v, max) { return max ? Math.max(0, Math.min(100, num(v) / max * 100)) : 0; }

  function toneClass(t) { return t ? ' is-' + t : ''; }

  // ---- The figure on hover or a tap ------------------------------------------
  /* One tip per card, placed over the mark it names and kept inside the
     card. A mouse shows it while over the mark; a finger shows it on a tap
     and a tap anywhere else puts it away. */
  function wireTip(card) {
    var tip = document.createElement('div');
    tip.className = 'chart-tip';
    tip.hidden = true;
    tip.setAttribute('aria-hidden', 'true');
    card.appendChild(tip);
    var shown = null;
    function show(mark) {
      shown = mark;
      tip.textContent = mark.getAttribute('data-tip');
      tip.hidden = false;
      var c = card.getBoundingClientRect(), m = mark.getBoundingClientRect();
      var w = tip.offsetWidth;
      var x = m.left - c.left + m.width / 2 - w / 2;
      x = Math.max(8, Math.min(c.width - w - 8, x));
      tip.style.left = x + 'px';
      tip.style.top = Math.max(4, m.top - c.top - tip.offsetHeight - 6) + 'px';
      Array.prototype.forEach.call(card.querySelectorAll('.is-tipped'), function (el) { el.classList.remove('is-tipped'); });
      mark.classList.add('is-tipped');
    }
    function hide() {
      shown = null;
      tip.hidden = true;
      Array.prototype.forEach.call(card.querySelectorAll('.is-tipped'), function (el) { el.classList.remove('is-tipped'); });
    }
    card.addEventListener('pointerover', function (e) {
      if (e.pointerType === 'touch') return;
      var m = e.target.closest && e.target.closest('[data-tip]');
      if (m && card.contains(m)) show(m);
    });
    card.addEventListener('pointerleave', function (e) { if (e.pointerType !== 'touch') hide(); });
    card.addEventListener('pointerdown', function (e) {
      if (e.pointerType !== 'touch') return;
      var m = e.target.closest && e.target.closest('[data-tip]');
      if (m && card.contains(m)) { if (shown === m) hide(); else show(m); }
      else hide();
    });
    document.addEventListener('pointerdown', function (e) {
      if (shown && !card.contains(e.target)) hide();
    });
  }

  // ---- Bars -------------------------------------------------------------------
  function bars(spec, fmt) {
    var rows = spec.rows || [];
    var top = 0;
    rows.forEach(function (r) { top = Math.max(top, num(r.value), num(r.mark)); });
    var max = spec.max || nice(top);
    return '<div class="chart-bars">' + rows.map(function (r) {
      var mark = r.mark != null && num(r.mark) > 0
        ? '<i class="cb-mark" style="left:' + pct(r.mark, max) + '%"></i>' : '';
      return '<div class="cb-row">' +
        '<div class="cb-head"><span class="cb-label">' + esc(r.label) +
          (r.note ? ' <small' + (r.noteTone ? ' class="is-' + esc(r.noteTone) + '"' : '') + '>' + esc(r.note) + '</small>' : '') + '</span>' +
          '<span class="cb-value' + toneClass(r.tone === 'warn' || r.tone === 'err' ? r.tone : '') + '">' + esc(fmt(r.value, r)) + '</span></div>' +
        '<div class="cb-track"><i class="cb-fill' + toneClass(r.tone) + '" style="width:' + pct(r.value, max) + '%"></i>' + mark + '</div>' +
      '</div>';
    }).join('') + '</div>';
  }

  // ---- Columns and line ------------------------------------------------------
  function axis(max, fmt) {
    return '<div class="cc-axis" aria-hidden="true">' +
      '<span style="bottom:100%">' + esc(fmt(max)) + '</span>' +
      '<span style="bottom:50%">' + esc(fmt(max / 2)) + '</span>' +
      '<span style="bottom:0">' + esc(fmt(0)) + '</span></div>';
  }
  function tipOf(c, series, fmt) {
    var parts = series.map(function (s, i) {
      return (series.length > 1 ? s.label + ' ' : '') + fmt(c.values[i]);
    });
    return (c.long || c.label) + ': ' + parts.join(' · ');
  }
  function columns(spec, fmt) {
    var cats = spec.cats || [], series = spec.series || [{ label: '' }];
    var top = 0;
    cats.forEach(function (c) {
      if (spec.stacked) top = Math.max(top, c.values.reduce(function (a, v) { return a + num(v); }, 0));
      else c.values.forEach(function (v) { top = Math.max(top, num(v)); });
    });
    var max = nice(top);
    var cols = cats.map(function (c) {
      var marks;
      if (spec.stacked) {
        marks = '<span class="cc-stack">' + c.values.map(function (v, i) {
          return num(v) ? '<i class="cc-seg' + toneClass(series[i].tone) + '" style="height:' + pct(v, max) + '%"></i>' : '';
        }).join('') + '</span>';
      } else {
        marks = c.values.map(function (v, i) {
          return '<i class="cc-bar' + toneClass(series[i].tone) + '" style="height:' + pct(v, max) + '%"></i>';
        }).join('');
      }
      return '<div class="cc-col" data-tip="' + esc(tipOf(c, series, fmt)) + '">' +
        '<div class="cc-plot">' + marks + '</div>' +
        '<span class="cc-label">' + esc(c.label) + '</span></div>';
    }).join('');
    return '<div class="chart-cols">' + axis(max, fmt) + '<div class="cc-body">' +
      '<div class="cc-grid" aria-hidden="true"><i></i><i></i><i></i></div>' + cols + '</div></div>';
  }
  function line(spec, fmt) {
    var cats = spec.cats || [], series = spec.series || [{ label: '' }];
    var top = spec.max || 0;
    if (!spec.max) cats.forEach(function (c) { c.values.forEach(function (v) { if (v != null) top = Math.max(top, num(v)); }); });
    var max = spec.max || nice(top);
    var n = cats.length;
    var xOf = function (i) { return n < 2 ? 50 : (i + .5) / n * 100; };
    var paths = series.map(function (s, si) {
      var pts = [];
      cats.forEach(function (c, i) { if (c.values[si] != null) pts.push(xOf(i) + ',' + (100 - pct(c.values[si], max))); });
      return pts.length > 1
        ? '<polyline class="cl-line' + toneClass(s.tone) + '" points="' + pts.join(' ') + '" vector-effect="non-scaling-stroke"/>' : '';
    }).join('');
    var dots = cats.map(function (c, i) {
      return series.map(function (s, si) {
        var v = c.values[si];
        return v == null ? '' : '<i class="cl-dot' + toneClass(s.tone) + '" style="left:' + xOf(i) + '%;bottom:' + pct(v, max) + '%"></i>';
      }).join('');
    }).join('');
    var hits = cats.map(function (c, i) {
      var any = c.values.some(function (v) { return v != null; });
      var none = spec.none || 'No figure';
      return '<div class="cc-col cl-hit" data-tip="' + esc(any ? tipOf(c, series, function (v) { return v == null ? none : fmt(v); }) : (c.long || c.label) + ': ' + none) + '">' +
        '<div class="cc-plot"></div><span class="cc-label">' + esc(c.label) + '</span></div>';
    }).join('');
    /* The months' hover grounds first and the line over them, so a month
       under the pointer never covers the line it is part of. */
    return '<div class="chart-cols chart-line">' + axis(max, fmt) + '<div class="cc-body">' +
      '<div class="cc-grid" aria-hidden="true"><i></i><i></i><i></i></div>' + hits +
      '<div class="cl-plot" aria-hidden="true"><svg viewBox="0 0 100 100" preserveAspectRatio="none">' + paths + '</svg>' + dots + '</div>' +
      '</div></div>';
  }

  // ---- Pie --------------------------------------------------------------------
  /* A ring in shades of the one ink, largest first, so the share is read
     against the legend's words and never by a colour somebody has to learn. */
  var SHADES = [.86, .62, .42, .26, .14];
  function pie(spec, fmt) {
    var rows = (spec.rows || []).filter(function (r) { return num(r.value) > 0; })
      .sort(function (a, b) { return num(b.value) - num(a.value); });
    var total = rows.reduce(function (a, r) { return a + num(r.value); }, 0);
    var C = 2 * Math.PI * 15.915, at = 0;
    var rings = rows.map(function (r, i) {
      var len = num(r.value) / total * C;
      var s = '<circle class="cp-seg" r="15.915" cx="21" cy="21" style="stroke-opacity:' + SHADES[i] +
        '" stroke-dasharray="' + len.toFixed(3) + ' ' + (C - len).toFixed(3) + '" stroke-dashoffset="' + (-at).toFixed(3) + '"></circle>';
      at += len;
      return s;
    }).join('');
    var key = rows.map(function (r, i) {
      /* The share is said once: where the figure is already the share (an
         age split in per cent), it is not said again beside it. */
      var share = Math.round(num(r.value) / total * 100) + '%', shown = fmt(r.value);
      var same = String(shown).replace(/\s/g, '') === share;
      return '<li class="cp-key" data-tip="' + esc(r.label + ': ' + shown + (same ? '' : ' · ' + share)) + '">' +
        '<i style="opacity:' + SHADES[i] + '"></i><span class="cp-label">' + esc(r.label) + '</span>' +
        '<span class="cp-value">' + esc(shown) + (same ? '' : '<small>' + share + '</small>') + '</span></li>';
    }).join('');
    return '<div class="chart-pie"><svg class="cp-ring" viewBox="0 0 42 42" aria-hidden="true">' +
      '<g transform="rotate(-90 21 21)">' + rings + '</g></svg><ul class="cp-keys">' + key + '</ul></div>';
  }

  // ---- The table under it ----------------------------------------------------
  function tableOf(spec, fmt) {
    if (spec.table) return spec.table;
    if (spec.kind === 'bars' || spec.kind === 'pie') {
      return { heads: ['', spec.valueHead || 'Figure'],
               rows: (spec.rows || []).map(function (r) { return [r.label, fmt(r.value, r)]; }) };
    }
    var series = spec.series || [{ label: spec.valueHead || 'Figure' }];
    return { heads: [''].concat(series.map(function (s) { return s.label || spec.valueHead || 'Figure'; })),
             rows: (spec.cats || []).map(function (c) {
               return [c.long || c.label].concat(c.values.map(function (v) { return v == null ? '—' : fmt(v); }));
             }) };
  }
  function tableHtml(t) {
    return '<div class="chart-tblwrap"><table class="chart-tbl"><thead><tr>' +
      t.heads.map(function (h, i) { return '<th scope="col"' + (i ? ' class="is-end"' : '') + '>' + esc(h) + '</th>'; }).join('') +
      '</tr></thead><tbody>' +
      t.rows.map(function (r) {
        return '<tr>' + r.map(function (c, i) {
          return i ? '<td class="is-end">' + esc(c) + '</td>' : '<th scope="row">' + esc(c) + '</th>';
        }).join('') + '</tr>';
      }).join('') + '</tbody></table></div>';
  }

  function keyHtml(series) {
    if (!series || series.length < 2) return '';
    return '<ul class="chart-key">' + series.map(function (s) {
      return '<li><i class="' + toneClass(s.tone).trim() + '"></i>' + esc(s.label) + '</li>';
    }).join('') + '</ul>';
  }

  function isEmpty(spec) {
    if (spec.kind === 'bars' || spec.kind === 'pie') {
      return !(spec.rows || []).some(function (r) { return num(r.value) > 0 || num(r.mark) > 0; });
    }
    return !(spec.cats || []).some(function (c) { return c.values.some(function (v) { return v != null && num(v) > 0; }); });
  }

  /* What the chart says, as the image's name: the title and each figure, so
     a screen reader hears what a sighted person reads off the marks. */
  function nameOf(spec, fmt) {
    var t = tableOf(spec, fmt);
    var t0 = spec.title || spec.name;
    return (t0 ? t0 + '. ' : '') + t.rows.slice(0, 12).map(function (r) {
      return r[0] + ' ' + r.slice(1).join(', ');
    }).join('; ');
  }

  function draw(host, spec) {
    spec = spec || {};
    var fmt = spec.fmt || plain;
    if (spec.kind === 'pie') {
      var live = (spec.rows || []).filter(function (r) { return num(r.value) > 0; }).length;
      if (live < 2 || live > 5) spec.kind = 'bars';
    }
    var card = document.createElement('section');
    card.className = 'chartcard' + (spec.cls ? ' ' + spec.cls : '');
    if (spec.id) card.id = spec.id;
    var head = spec.title ? '<h3 class="chart-title">' + esc(spec.title) + '</h3>' : '';
    if (isEmpty(spec)) {
      card.innerHTML = head + '<p class="chart-empty">' + esc(spec.empty || 'No entries.') + '</p>';
      if (host) host.appendChild(card);
      return card;
    }
    var body = spec.kind === 'columns' ? columns(spec, fmt)
      : spec.kind === 'line' ? line(spec, fmt)
      : spec.kind === 'pie' ? pie(spec, fmt)
      : bars(spec, fmt);
    card.innerHTML = head +
      '<div class="chart-plot" role="img" aria-label="' + esc(nameOf(spec, fmt)) + '">' + body + '</div>' +
      keyHtml(spec.kind === 'columns' || spec.kind === 'line' ? spec.series : null) +
      (spec.kind === 'bars' && spec.markLabel && (spec.rows || []).some(function (r) { return num(r.mark) > 0; })
        ? '<ul class="chart-key"><li><i class="is-mark"></i>' + esc(spec.markLabel) + '</li></ul>' : '') +
      '<details class="fmore chart-data"><summary>Figures</summary>' + tableHtml(tableOf(spec, fmt)) + '</details>';
    card.setAttribute('data-kind', spec.kind || 'bars');
    if (spec.kind === 'columns' || spec.kind === 'line' || spec.kind === 'pie') wireTip(card);
    if (host) host.appendChild(card);
    return card;
  }

  /* The last n months, oldest first, as `{ key: 'YYYY-MM', label: 'Sept',
     long: 'Sept 2026' }`, so every monthly chart names its months alike. */
  var MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
  function months(n, end) {
    var d = end ? new Date(end) : new Date();
    d = new Date(d.getFullYear(), d.getMonth(), 1);
    var out = [];
    for (var i = n - 1; i >= 0; i--) {
      var m = new Date(d.getFullYear(), d.getMonth() - i, 1);
      out.push({ key: m.getFullYear() + '-' + String(m.getMonth() + 1).padStart(2, '0'),
                 label: MON[m.getMonth()], long: MON[m.getMonth()] + ' ' + m.getFullYear(),
                 start: m, end: new Date(m.getFullYear(), m.getMonth() + 1, 1) });
    }
    return out;
  }
  function monthKey(iso) {
    var d = new Date(iso);
    return isNaN(d.getTime()) ? '' : d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0');
  }

  window.ADspaceChart = { draw: draw, nice: nice, months: months, monthKey: monthKey };
})();
