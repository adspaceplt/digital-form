/* The Video Script PDF (2026-10-09), for the crew on site: drawn in the
 * browser from the scripts as they stand, never stored.
 *
 * The page furniture and the type are the Reports PDF's (the user,
 * 2026-10-09: "refer back to the Reports style"; js/smreport.js): the
 * Optima wordmark in ink at the head of every page and the client's name in
 * small capitals at its right; PRIVATE & CONFIDENTIAL in Slate Medium at the
 * foot on the margin's line, the page count at its right; sizes and spaces
 * on S(k) = 10·φ^(k/2) with the S(5) margin; tables of white cells under a
 * shaded title row, the title row and the grid in one grey (#f2f2f2), heads
 * in Slate Regular. The content keeps the user's template: Video Script and
 * its type and month, the header table (Video #, Platform, Client/Brand,
 * Language, Shooting Date & Time, Venue, Est. Shooting Duration, Cast
 * Members/Talent), then each video under its code and title: its script by
 * its kind, every scene with a VC# cell (a clip number recorded in the
 * console printed, an empty one left for the crew's pen), and Notes /
 * Remarks with room to write. Videos of one month that share their header
 * and kind share one header table.
 */
(function () {
  'use strict';
  var D = function () { return window.ADspaceDocs; };
  var W = 595.28, H = 841.89;
  var PHI = 1.6180339887;
  var S = function (k) { return 10 * Math.pow(PHI, k / 2); };
  var M = S(5), R = W - M;            // the Reports PDF's margin, 33.3pt
  var HEAD_Y = H - M - 11.6;          // the wordmark's baseline
  var FOOT_Y = M;                     // the foot, on the margin's line
  var FLOOR = M + S(1) + S(4);        // nothing draws below this
  var CJK = /[⺀-鿿豈-﫿＀-￯]/;

  function draw(videos) {
    var docs = D();
    if (!docs) return Promise.reject(new Error('The PDF tools are not loaded.'));
    var needCjk = JSON.stringify(videos).search(CJK) > -1;
    return docs.lib().then(function (PDF) {
      var pdf;
      return PDF.PDFDocument.create().then(function (doc) {
        pdf = doc;
        var v0 = videos[0] || {};
        pdf.setTitle([((v0.clients || {}).name || ''), 'Video Script', v0.month_word || ''].filter(Boolean).join(' '));
        pdf.setAuthor('ADspace');
        pdf.setSubject('Video Script');
        pdf.setCreator('ADspace Digital Portal');
        pdf.setProducer('ADspace Digital Portal');
        return docs.embedFonts(pdf, PDF, { cjk: needCjk });
      }).then(function (fonts) {
        if (needCjk && !fonts.cjk) throw new Error('The Chinese typeface could not be loaded.');
        layout(pdf, PDF, fonts, videos);
        return pdf.save();
      }).then(function (bytes) { return new Blob([bytes], { type: 'application/pdf' }); });
    });
  }

  function layout(pdf, PDF, fonts, videos) {
    var ink = PDF.rgb(0.251, 0.251, 0.251), mute = PDF.rgb(0.40, 0.40, 0.40);   // the Reports PDF's ink and soft
    var grey = PDF.rgb(0.949, 0.949, 0.949);
    var book = fonts.font, reg = fonts.bold, med = fonts.med || fonts.bold, mark = fonts.mark || med;
    var page = null, y = 0;
    var body = S(0), lead = S(0) * 1.45, small = S(-1);
    var client = String(((videos[0] || {}).clients || {}).name || '').toUpperCase();

    var faceOf = function (s, f) { return fonts.cjk && CJK.test(s || '') ? fonts.cjk : f || fonts.font; };
    var safe = function (s) {
      s = String(s == null ? '' : s);
      return fonts.custom ? s : s.replace(/[^\x20-\x7E -ÿ]/g, '-');
    };
    var width = function (s, size, f) { return faceOf(s, f).widthOfTextAtSize(safe(s), size); };
    var text = function (s, x, yy, size, f, color) {
      if (!s) return;
      page.drawText(safe(s), { x: x, y: yy, size: size, font: faceOf(s, f), color: color || ink });
    };
    /* Words wrap at their spaces; Chinese, with none, where the next glyph
       would cross the column; a line break typed is kept. */
    var wrap = function (s, max, size, f) {
      var out = [];
      String(s == null ? '' : s).split(/\r?\n/).forEach(function (para) {
        if (!para.trim()) { out.push(''); return; }
        var face = faceOf(para, f), cur = '';
        var fits = function (t) { return face.widthOfTextAtSize(safe(t), size) <= max; };
        var tokens = CJK.test(para) ? para.match(/[⺀-鿿豈-﫿＀-￯]|[^\s⺀-鿿豈-﫿＀-￯]+|\s+/g) : para.split(/(\s+)/);
        tokens.forEach(function (w) {
          if (!w) return;
          var t = cur + w;
          if (fits(t) || !cur.trim()) { cur = t; return; }
          out.push(cur.replace(/\s+$/, ''));
          cur = /^\s+$/.test(w) ? '' : w;
        });
        /* A word longer than the column is cut where it overflows. */
        while (cur && !fits(cur)) {
          var n = cur.length;
          while (n > 1 && !fits(cur.slice(0, n))) n--;
          out.push(cur.slice(0, n));
          cur = cur.slice(n);
        }
        if (cur.trim()) out.push(cur.replace(/\s+$/, ''));
      });
      while (out.length && out[out.length - 1] === '') out.pop();
      return out.length ? out : [''];
    };

    /* The head on every page: the wordmark, and the client in small
       capitals at the right. */
    var newPage = function () {
      page = pdf.addPage([W, H]);
      text('ADspace', M, HEAD_Y, S(2), mark, ink);
      if (client) text(client, R - width(client, small, med), HEAD_Y + 0.9, small, med, ink);
      y = HEAD_Y - S(4);
    };
    var room = function (h) { if (y - h < FLOOR) { newPage(); return true; } return false; };

    var box = function (x, top, w, h, fill) {
      page.drawRectangle({ x: x, y: top - h, width: w, height: h, color: fill || undefined,
        borderColor: grey, borderWidth: 0.8 });
    };
    var PAD = S(-1);
    /* One row of cells: each {w, text, head, size, f, align}. Returns its
       height; draws only where `go`. */
    var rowOf = function (cells, go) {
      var lines = cells.map(function (c) { return wrap(c.text, c.w - PAD * 2, c.size || body, c.f); });
      var hgt = Math.max.apply(null, lines.map(function (l) { return l.length; })) * lead + PAD * 2 - (lead - body) + 2;
      hgt = Math.max(hgt, S(4), Math.max.apply(null, cells.map(function (c) { return c.minH || 0; })));
      if (!go) return hgt;
      var x = M;
      cells.forEach(function (c, i) {
        box(x, y, c.w, hgt, c.head ? grey : null);
        var yy = y - PAD - (c.size || body);
        lines[i].forEach(function (ln) {
          var tx = c.align === 'center' ? x + (c.w - width(ln, c.size || body, c.f)) / 2 : x + PAD;
          text(ln, tx, yy, c.size || body, c.f, c.color);
          yy -= lead;
        });
        x += c.w;
      });
      y -= hgt;
      return hgt;
    };
    /* A table: its head row repeats at the top of a page it runs onto. */
    var table = function (head, rows) {
      var drawHead = function () { if (head) rowOf(head, true); };
      var hh = head ? rowOf(head, false) : 0;
      room(hh + (rows.length ? rowOf(rows[0], false) : 0));
      drawHead();
      rows.forEach(function (r) {
        if (room(rowOf(r, false))) drawHead();
        rowOf(r, true);
      });
    };
    /* A block's head: the code and title in Slate Medium, a line under it
       in the soft ink where there is one. */
    var blockHead = function (title, sub) {
      var ts = wrap(title, R - M, S(1), med);
      var ss = sub ? wrap(sub, R - M, small) : [];
      room(ts.length * S(1) * 1.3 + ss.length * small * 1.5 + S(3) + S(4) * 2);
      ts.forEach(function (l) { text(l, M, y - S(1), S(1), med); y -= S(1) * 1.3; });
      ss.forEach(function (l) { text(l, M, y - small - 2, small, book, mute); y -= small * 1.5; });
      y -= S(-1) + 4;
    };

    var full = R - M;
    var labW = 118, valW = (full - labW * 2) / 2;
    var header = function (group) {
      var v = group[0];
      var nos = group.map(function (x) { return x.code; }).join(', ');
      var L = function (t) { return { w: labW, text: t, head: true, f: reg }; };
      var V = function (t) { return { w: valW, text: t || '' }; };
      room(S(5) + S(4) * 5);
      /* The page title on the Reports PDF's title step, its type and month
         under it. */
      y = HEAD_Y - S(5);
      text('Video Script', M, y, S(3), med);
      y -= S(2) + 2;
      text([v.kind_word, v.month_word].filter(Boolean).join(' · '), M, y, small, book, mute);
      y -= S(3);
      [[L('Video #'), V(nos), L('Platform'), V(v.platform)],
       [L('Client/Brand'), V((v.clients || {}).name), L('Language'), V(v.language === 'Malay' ? 'Bahasa Melayu' : v.language)],
       [L('Shooting Date & Time'), V(v.when), L('Venue'), V(v.venue)],
       [L('Est. Shooting Duration'), V(v.duration), L('Cast Members/Talent'), V(v.cast_names)]]
        .forEach(function (r) { room(rowOf(r, false)); rowOf(r, true); });
      y -= S(4);
    };

    var vcW = S(9), noW = S(6);
    var video = function (v) {
      blockHead(v.code + (v.title ? ' · ' + v.title : ''), v.reference_url ? 'Reference: ' + v.reference_url : '');
      var H2 = function (t, w) { return { w: w, text: t, head: true, f: reg }; };
      var VC = function (t, head) { return head ? { w: vcW, text: 'VC#', head: true, f: reg, align: 'center' } : { w: vcW, text: t || '', align: 'center' }; };
      if (v.kind === 'scenes') {
        var vis = (full - noW - vcW) / 2;
        table([H2('Scene', noW), H2('Visual', vis), H2('Script', vis), VC('', true)],
          (v.scenes.length ? v.scenes : [{}]).map(function (sc, i) {
            return [{ w: noW, text: String(i + 1), align: 'center' }, { w: vis, text: sc.visual || '' },
                    { w: vis, text: sc.line || '' }, VC(sc.vc)];
          }));
      } else {
        var wide = full - vcW;
        table([H2(v.kind === 'products' ? 'Products/Context' : 'Hook/Story', wide), VC('', true)],
          [[{ w: wide, text: v.context || '' }, VC('')]]);
        y -= S(2);
        table([H2('Scenes', wide), VC('', true)],
          (v.scenes.length ? v.scenes : [{}]).map(function (sc, i) {
            return [{ w: wide, text: (v.scenes.length ? (i + 1) + '.  ' : '') + (sc.visual || '') }, VC(sc.vc)];
          }));
        if (v.kind === 'story') {
          y -= S(2);
          table([H2('Script (Read Here)', wide), VC('', true)], [[{ w: wide, text: v.vo || '' }, VC(v.vo_vc)]]);
        }
      }
      y -= S(4);
    };
    var notes = function (group) {
      var many = group.length > 1;
      var parts = group.filter(function (v) { return (v.remarks || '').trim(); })
        .map(function (v) { return (many ? v.code + ': ' : '') + v.remarks; });
      /* A box to write in on the day: the notes typed, then room below. */
      var noteRows = parts.length ? [[{ w: full, text: parts.join('\n') }]] : [];
      noteRows.push([{ w: full, text: '', minH: S(8) }]);
      table([{ w: full, text: 'Notes / Remarks', head: true, f: reg }], noteRows);
    };

    /* Scripts of one month that share their kind and header read under one
       header table; any other starts its own page. */
    var key = function (v) {
      return [v.client_id, v.period, v.kind, v.platform, v.language, v.when, v.venue, v.duration, v.cast_names].join('\u0001');
    };
    var groups = [];
    videos.forEach(function (v) {
      var last = groups[groups.length - 1];
      if (last && key(last[0]) === key(v)) last.push(v); else groups.push([v]);
    });
    groups.forEach(function (g) {
      newPage();
      header(g);
      g.forEach(function (v) { video(v); });
      notes(g);
    });

    var pages = pdf.getPages();
    pages.forEach(function (pg, i) {
      page = pg;
      text('PRIVATE & CONFIDENTIAL', M, FOOT_Y, small, med, ink);
      var t = 'Page ' + (i + 1) + ' of ' + pages.length;
      text(t, R - width(t, small, book), FOOT_Y, small, book, ink);
    });
  }

  window.ADspaceScriptPdf = { draw: draw };
})();
