/* The Video Script PDF (2026-10-09), for the crew on site: drawn in the
 * browser from the scripts as they stand, never stored.
 *
 * Laid as the user's script template is: the ADspace wordmark at the head of
 * every page, Video Script, the header table (Video #, Platform,
 * Client/Brand, Language, Shooting Date & Time, Venue, Est. Shooting
 * Duration, Cast Members/Talent), then each video: its title and reference,
 * and its script by its kind:
 *   - Detailed scenes: a table of Scene, Visual, Script, VC#;
 *   - Products and scenes: Products/Context, then Scenes, each with VC#;
 *   - Story and voice-over: Hook/Story, Scenes, Script (Read Here), each
 *     with VC#;
 * then Notes / Remarks. A clip number recorded in the portal is printed; an
 * empty VC# cell is left for the crew's pen. Videos of one shoot that share
 * their header and kind share one header table; the foot is PRIVATE &
 * CONFIDENTIAL and the page count. Tables are white cells under a shaded
 * title row, the title row and the grid in one grey (#f2f2f2), as every
 * portal document draws them.
 */
(function () {
  'use strict';
  var D = function () { return window.ADspaceDocs; };
  var W = 595.28, H = 841.89, M = 36, R = W - M, FOOT = 30, TOP = H - M;
  var CJK = /[⺀-鿿豈-﫿＀-￯]/;

  function draw(videos) {
    var docs = D();
    if (!docs) return Promise.reject(new Error('The PDF tools are not loaded.'));
    var needCjk = JSON.stringify(videos).search(CJK) > -1;
    return docs.lib().then(function (PDF) {
      var pdf;
      return PDF.PDFDocument.create().then(function (doc) {
        pdf = doc;
        pdf.setTitle('Video Script');
        pdf.setAuthor('ADspace');
        return docs.embedFonts(pdf, PDF, { cjk: needCjk });
      }).then(function (fonts) {
        if (needCjk && !fonts.cjk) throw new Error('The Chinese typeface could not be loaded.');
        layout(pdf, PDF, fonts, videos);
        return pdf.save();
      }).then(function (bytes) { return new Blob([bytes], { type: 'application/pdf' }); });
    });
  }

  function layout(pdf, PDF, fonts, videos) {
    var ink = PDF.rgb(0.075, 0.094, 0.102), mute = PDF.rgb(0.39, 0.43, 0.44);
    var grey = PDF.rgb(0.949, 0.949, 0.949);
    var page = null, y = 0;
    var body = 9.5, lead = 13;

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

    var newPage = function () {
      page = pdf.addPage([W, H]);
      /* The wordmark heads every page, as the template's header does. */
      text('ADspace', M, TOP - 14, 16, fonts.mark || fonts.bold, mute);
      y = TOP - 34;
    };
    var room = function (h) { if (y - h < FOOT + 18) { newPage(); return true; } return false; };

    var box = function (x, top, w, h, fill) {
      page.drawRectangle({ x: x, y: top - h, width: w, height: h, color: fill || undefined,
        borderColor: grey, borderWidth: 0.8 });
    };
    var PAD = 6;
    /* One row of cells: each {w, text, head, size, f, align}. Returns its
       height; draws only where `go`. */
    var rowOf = function (cells, go) {
      var lines = cells.map(function (c) { return wrap(c.text, c.w - PAD * 2, c.size || body, c.f); });
      var hgt = Math.max.apply(null, lines.map(function (l) { return l.length; })) * lead + PAD * 2 - (lead - body) + 2;
      hgt = Math.max(hgt, 22);
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
    var line = function (label, value, gap) {
      var lw = width(label, body + 0.5, fonts.bold) + 6;
      var ls = wrap(value || '', R - M - lw, body + 0.5);
      room(ls.length * lead + 4);
      text(label, M, y - body, body + 0.5, fonts.bold);
      ls.forEach(function (l, i) { text(l, M + lw, y - body - i * lead, body + 0.5); });
      y -= ls.length * lead + (gap == null ? 4 : gap);
    };

    var full = R - M;
    var labW = 118, valW = (full - labW * 2) / 2;
    var header = function (group) {
      var v = group[0];
      var nos = group.map(function (x) { return 'V' + x.video_no; }).join(', ');
      var L = function (t) { return { w: labW, text: t, head: true, f: fonts.bold, size: 9 }; };
      var V = function (t) { return { w: valW, text: t || '' }; };
      room(140);
      text('Video Script', M, y - 18, 18, fonts.med || fonts.bold);
      text(v.kind_word || '', R - width(v.kind_word || '', 9.5), y - 16, 9.5, fonts.font, mute);
      y -= 32;
      [[L('Video #'), V(nos), L('Platform'), V(v.platform)],
       [L('Client/Brand'), V((v.clients || {}).name), L('Language'), V(v.language)],
       [L('Shooting Date & Time'), V(v.when), L('Venue'), V(v.venue)],
       [L('Est. Shooting Duration'), V(v.duration), L('Cast Members/Talent'), V(v.cast_names)]]
        .forEach(function (r) { room(rowOf(r, false)); rowOf(r, true); });
      y -= 16;
    };

    var vcW = 70, noW = 40;
    var video = function (v, many) {
      var tag = many ? 'V' + v.video_no + ' ' : '';
      room(60);
      line(tag + (v.kind === 'scenes' ? 'Title:' : 'Title/Theme:'), v.title || '');
      if (v.reference_url) line('Reference:', v.reference_url);
      y -= 6;
      var H2 = function (t, w) { return { w: w, text: t, head: true, f: fonts.bold, size: 9 }; };
      var VC = function (t, head) { return head ? { w: vcW, text: 'VC#', head: true, f: fonts.bold, size: 9, align: 'center' } : { w: vcW, text: t || '', align: 'center' }; };
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
        y -= 10;
        table([H2('Scenes', wide), VC('', true)],
          (v.scenes.length ? v.scenes : [{}]).map(function (sc, i) {
            return [{ w: wide, text: (v.scenes.length ? (i + 1) + '.  ' : '') + (sc.visual || '') }, VC(sc.vc)];
          }));
        if (v.kind === 'story') {
          y -= 10;
          table([H2('Script (Read Here)', wide), VC('', true)], [[{ w: wide, text: v.vo || '' }, VC(v.vo_vc)]]);
        }
      }
      y -= 18;
    };
    var notes = function (group) {
      var many = group.length > 1;
      var parts = group.filter(function (v) { return (v.remarks || '').trim(); })
        .map(function (v) { return (many ? 'V' + v.video_no + ': ' : '') + v.remarks; });
      room(40);
      line('Notes / Remarks:', parts.join('\n') || '', 8);
    };

    /* Videos of one shoot that share their kind and header read under one
       header table; any other starts its own page. */
    var key = function (v) {
      return [v.series_id, v.kind, v.platform, v.language, v.when, v.venue, v.duration, v.cast_names].join('\u0001');
    };
    var groups = [];
    videos.forEach(function (v) {
      var last = groups[groups.length - 1];
      if (last && key(last[0]) === key(v)) last.push(v); else groups.push([v]);
    });
    groups.forEach(function (g) {
      newPage();
      header(g);
      g.forEach(function (v) { video(v, g.length > 1); });
      notes(g);
    });

    var pages = pdf.getPages();
    pages.forEach(function (pg, i) {
      page = pg;
      text('PRIVATE & CONFIDENTIAL', M, FOOT - 8, 7.5, fonts.font, mute);
      var t = 'Page ' + (i + 1) + ' of ' + pages.length;
      text(t, R - width(t, 7.5), FOOT - 8, 7.5, fonts.font, mute);
    });
  }

  window.ADspaceScriptPdf = { draw: draw };
})();
