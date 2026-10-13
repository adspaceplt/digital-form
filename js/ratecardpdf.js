/* The Rate Card & Packages PDF (2026-10-13), the team's own copy of the
 * card: drawn in the browser from a published version of the rate card
 * (`rate_card_current()`: its lines, its words, SST and the term
 * percentages as they stood when it was published), never stored.
 *
 * It keeps the card as the team issued it (v.2.0.6, six A4 pages; the
 * user, 2026-10-13: "their exact format"): the Optima wordmark at the head
 * of every page with FOR INTERNAL USE beside it, PRIVATE & CONFIDENTIAL and
 * the page count at the foot over the version line (`v.2.0.6 exp.
 * 20261231`), the 54pt margin of the letterhead, tables of white cells
 * under a #f2f2f2 title row, a What's Included cell a step darker. Pages:
 * the cover, Ala Carté, Social Media Services (the plans, without ads and
 * with ads), KOC Programmes, KOL Programmes, Add-ons with the term
 * commitment and the Terms of Service. A line set inactive is left out; a
 * line no page holds (an additional content rate, on request) is never
 * printed. Every figure is read from the version; none is typed here.
 */
(function () {
  'use strict';
  var D = function () { return window.ADspaceDocs; };
  var W = 595.28, H = 841.89;
  var M = 54, R = W - M, FULL = R - M;
  var HEAD_Y = H - 62;                // the wordmark's baseline
  var FLOOR = 64;                     // nothing draws below this
  var BODY = 8.8, LEAD = 11.6, PAD = 4.5;

  function draw(card) {
    var docs = D();
    if (!docs) return Promise.reject(new Error('The PDF tools are not loaded.'));
    if (!card || !card.snapshot) return Promise.reject(new Error('No published version of the rate card.'));
    return docs.lib().then(function (PDF) {
      var pdf;
      return PDF.PDFDocument.create().then(function (doc) {
        pdf = doc;
        pdf.setTitle('ADspace Rate Card & Packages v.' + card.version);
        pdf.setAuthor('ADspace');
        pdf.setSubject('Rate Card & Packages');
        pdf.setCreator('ADspace Digital Portal');
        pdf.setProducer('ADspace Digital Portal');
        return docs.embedFonts(pdf, PDF);
      }).then(function (fonts) {
        layout(pdf, PDF, fonts, card);
        return pdf.save();
      }).then(function (bytes) { return new Blob([bytes], { type: 'application/pdf' }); });
    });
  }

  /* RM 1,310 for a whole figure, RM 1,299.50 where there are sen. */
  function rm(n) {
    var v = Number(n);
    if (n == null || n === '' || isNaN(v)) return '';
    var whole = Math.abs(v - Math.round(v)) < 0.005;
    return 'RM ' + v.toLocaleString('en-MY', { minimumFractionDigits: whole ? 0 : 2, maximumFractionDigits: whole ? 0 : 2 });
  }
  function lines(s) {
    return String(s || '').split(/\r?\n/).map(function (l) { return l.replace(/^\s*(::|[-•])\s*/, '').trim(); })
      .filter(Boolean);
  }
  function cols(s) { return String(s || '').split('|').map(function (x) { return x.trim(); }); }
  var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
    'October', 'November', 'December'];
  function longDay(iso) {
    var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso || ''));
    return m ? Number(m[3]) + ' ' + MONTHS[Number(m[2]) - 1] + ' ' + m[1] : '';
  }

  function layout(pdf, PDF, fonts, card) {
    var snap = card.snapshot || {};
    var T = snap.text || {};
    var set = snap.settings || {};
    var live = (snap.services || []).filter(function (s) { return s.active !== false; });
    var role = function (r) {
      return live.filter(function (s) { return (s.spec || {}).role === r; })
        .sort(function (a, b) { return (a.position || 0) - (b.position || 0); });
    };
    var ink = PDF.rgb(0.251, 0.251, 0.251), dark = PDF.rgb(0.106, 0.102, 0.090);
    var head = PDF.rgb(0.949, 0.949, 0.949), deep = PDF.rgb(0.851, 0.851, 0.851);
    var edge = PDF.rgb(0.902, 0.902, 0.902);
    var book = fonts.font, reg = fonts.bold, med = fonts.med || fonts.bold, mark = fonts.mark || med;
    var page = null, y = 0;

    var safe = function (s) {
      s = String(s == null ? '' : s);
      return fonts.custom ? s : s.replace(/[^\x20-\x7E -ÿ]/g, '-');
    };
    var width = function (s, size, f) { return (f || book).widthOfTextAtSize(safe(s), size); };
    var text = function (s, x, yy, size, f, color) {
      if (!s) return;
      page.drawText(safe(s), { x: x, y: yy, size: size, font: f || book, color: color || ink });
    };
    var wrap = function (s, max, size, f) {
      var out = [], cur = '';
      String(s == null ? '' : s).split(/(\s+)/).forEach(function (w) {
        if (!w) return;
        var t = cur + w;
        if (width(t, size, f) <= max || !cur.trim()) { cur = t; return; }
        out.push(cur.replace(/\s+$/, ''));
        cur = /^\s+$/.test(w) ? '' : w;
      });
      if (cur.trim()) out.push(cur.replace(/\s+$/, ''));
      return out.length ? out : [''];
    };

    var version = 'v.' + card.version + (card.valid_until ? ' exp. ' + String(card.valid_until).slice(0, 10).replace(/-/g, '') : '');
    var newPage = function (title) {
      page = pdf.addPage([W, H]);
      text('ADspace', M, HEAD_Y, 14, mark, ink);
      text('FOR INTERNAL USE', 265, HEAD_Y + 2, 5.6, med, dark);
      y = HEAD_Y - 14;
      if (title) { text(title, M, y - 14, 15.5, reg, ink); y -= 28; }
    };
    var room = function (h) { if (y - h < FLOOR) { newPage(''); return true; } return false; };
    var label = function (t) { room(LEAD + 30); text(t, M, y - BODY - 2, BODY + 0.5, book, dark); y -= BODY + 7; };
    var gap = function (n) { y -= n == null ? 10 : n; };

    /* A cell: { t: words, b: bullet lines, w: width, fill, align, f, or: true
       where bullets are split by OR }. The row's height is its tallest
       cell. A cell marked `skip` draws nothing: a merged cell above it
       covers it. */
    var cellLines = function (c) {
      var inner = c.w - PAD * 2, out = [];
      (c.parts || [{ t: c.t, b: c.b }]).forEach(function (p, pi) {
        if (pi && c.or) out.push({ s: 'OR', x: 0 });
        if (p.t != null && p.t !== '') {
          String(p.t).split(/\r?\n/).forEach(function (para) {
            wrap(para, inner, BODY, c.f).forEach(function (l) { out.push({ s: l, x: 0 }); });
          });
        }
        (p.b || []).forEach(function (bl) {
          wrap(bl, inner - 18, BODY, c.f).forEach(function (l, i) { out.push({ s: l, x: 18, dot: i === 0 }); });
        });
      });
      return out.length ? out : [{ s: '', x: 0 }];
    };
    var rowHeight = function (cells) {
      return Math.max(17.6, Math.max.apply(null, cells.map(function (c) {
        return c.skip ? 0 : cellLines(c).length * LEAD + PAD * 2 - (LEAD - BODY) + 1;
      })));
    };
    var drawCell = function (c, x, top, h) {
      page.drawRectangle({ x: x, y: top - h, width: c.w, height: h, color: c.fill || PDF.rgb(1, 1, 1),
        borderColor: edge, borderWidth: 0.8 });
      var ls = cellLines(c);
      var block = ls.length * LEAD - (LEAD - BODY);
      var yy = c.top ? top - PAD - BODY : top - (h - block) / 2 - BODY + 0.5;
      ls.forEach(function (l) {
        var tx = c.align === 'center' && !l.x ? x + (c.w - width(l.s, BODY, c.f)) / 2 : x + PAD + l.x;
        if (l.dot) text('•', x + PAD + 5, yy, BODY, book, ink);
        text(l.s, tx, yy, BODY, c.f, ink);
        yy -= LEAD;
      });
    };
    var row = function (cells) {
      var h = rowHeight(cells);
      room(h);
      var x = M;
      cells.forEach(function (c) { if (!c.skip) drawCell(c, x, y, h); x += c.w; });
      y -= h;
      return h;
    };
    /* A cell merged down several rows: drawn over the rows once they are
       laid, its words centred in it. */
    var merged = function (c, x, top, bottom) { drawCell(c, x, top, top - bottom); };
    var C = function (t, w, o) { var c = { t: t, w: w, align: 'center' }; for (var k in o) c[k] = o[k]; return c; };
    var L = function (t, w, o) { var c = { t: t, w: w }; for (var k in o) c[k] = o[k]; return c; };
    var thirds = [FULL / 3, FULL / 3, FULL - 2 * (FULL / 3)];
    var included = function (lab, key, span) {
      row([C(lab, thirds[0], { fill: deep }), L('', span, { b: lines(T[key]) })]);
    };
    var bullets = function (key, numbered) {
      lines(T[key]).forEach(function (l, i) {
        var lead = numbered ? (i + 1) + '.' : '•';
        var ws = wrap(l, FULL - 18, BODY);
        room(ws.length * LEAD + 2);
        text(lead, M + 4, y - BODY - 1, BODY, book, dark);
        ws.forEach(function (w) { text(w, M + 18, y - BODY - 1, BODY, book, dark); y -= LEAD; });
      });
    };
    var plain = function (s, size, f) {
      String(s || '').split(/\r?\n/).forEach(function (para) {
        wrap(para, FULL, size || BODY, f).forEach(function (w) {
          room(LEAD); text(w, M, y - (size || BODY) - 1, size || BODY, f || book, dark); y -= (size || BODY) * 1.35;
        });
      });
    };

    /* 1. The cover. */
    newPage('');
    text(T.cover_title || 'Rate Card & Packages', 126, H - 375, 22, med, ink);

    /* 2. Ala Carté. */
    newPage('Ala Carté');
    var content = role('content');
    if (content.length) {
      label('Social Media Contents');
      row([C('Deliverable', thirds[0], { fill: head }), C('Rate', thirds[1], { fill: head }), C('Unit', thirds[2], { fill: head })]);
      content.forEach(function (s) {
        var m = /^(.*?)(,\s*up to .*)$/i.exec(s.name || '');
        var name = m ? m[1] : s.name, more = m ? m[2] : '';
        row([L(name, thirds[0]), C(rm(s.rate), thirds[1]), L((s.unit || '') + more, thirds[2])]);
      });
      gap();
    }
    var accounts = role('platform');
    if (accounts.length) {
      label('Social Media Accounts');
      included('What’s Included', 'accounts_included', thirds[1] + thirds[2]);
      row([C('Management', thirds[0], { fill: head }), C('Service Fee', thirds[1] + thirds[2], { fill: head })]);
      accounts.forEach(function (s) { row([L(s.name, thirds[0]), C(rm(s.rate), thirds[1] + thirds[2])]); });
      gap();
    }
    var verify = role('verify');
    if (verify.length) {
      label('Account Verifications');
      included('What’s Included', 'verify_included', thirds[1] + thirds[2]);
      row([C('Account', thirds[0], { fill: head }), C('Service Fee', thirds[1], { fill: head }), C('Additional Fees', thirds[2], { fill: head })]);
      verify.forEach(function (s) { row([L(s.name, thirds[0]), C(rm(s.rate), thirds[1]), C((s.spec || {}).fee || '', thirds[2])]); });
      gap();
    }
    var ads = role('ads');
    if (ads.length) {
      label('Digital Advertising');
      included('What’s Included', 'ads_included', thirds[1] + thirds[2]);
      row([C('Platform', thirds[0], { fill: head }), C('Service Fee', thirds[1], { fill: head }), C('Service Fee Coverage', thirds[2], { fill: head })]);
      ads.forEach(function (s) {
        row([L(String(s.name || '').split(' · ')[0], thirds[0]), C(rm(s.rate), thirds[1]),
          C('Up to ' + rm((s.spec || {}).budget) + ' ads budget', thirds[2])]);
      });
      gap();
    }
    if (T.alacarte_note) { label('Note'); bullets('alacarte_note'); gap(8); }
    if (T.verify_footnote) plain(T.verify_footnote);

    /* 3. Social Media Services: the plans, without ads and with ads. */
    newPage('Social Media Services');
    var plans = role('plan').sort(function (a, b) { return String(a.spec.plan).localeCompare(String(b.spec.plan)); });
    var boosters = role('booster').sort(function (a, b) { return (a.spec.budget || 0) - (b.spec.budget || 0); });
    var mixParts = function (mix) {
      return (mix || []).map(function (m) {
        var b = [];
        if (m.graphic) b.push(m.graphic + (m.graphic === 1 ? ' graphic' : ' graphics'));
        if (m.reel) b.push(m.reel + (m.reel === 1 ? ' reel, up to 60s' : ' reels, up to 60s each'));
        return { b: b };
      });
    };
    var planTable = function (group, withAds) {
      if (!group.length) return;
      var lw = 105, pw = (FULL - lw) / group.length;
      var wide = FULL - lw;
      var cells = function (lab, f) {
        return [C(lab, lw, { fill: head })].concat(group.map(function (p, i) {
          var c = f(p);
          c.w = i === group.length - 1 ? wide - pw * (group.length - 1) : pw;
          return c;
        }));
      };
      row([C(withAds ? 'With Ads' : 'Without Ads', lw, { fill: deep })].concat(group.map(function (p, i) {
        return C(p.spec.plan, i === group.length - 1 ? wide - pw * (group.length - 1) : pw, { fill: head });
      })));
      row(cells('Service Fee', function (p) { return C(rm(p.rate) + ' / month', 0); }));
      row(cells('Platform', function (p) {
        var n = Number(p.spec.platforms);
        return C(n === 1 ? '1 platform' : 'Up to ' + n + ' platforms', 0);
      }));
      row(cells('Content', function (p) {
        var parts = mixParts(p.spec.mix);
        parts[0].t = p.spec.contents + ' contents / month';
        return L('', 0, { parts: parts, or: true, top: true });
      }));
      row([C('What’s Included', lw, { fill: head }), L('', wide, { b: lines(T[withAds ? 'plans_ads_included' : 'plans_included']) })]);
      if (withAds) {
        var top = y;
        row([C('', lw, { skip: true })].concat(group.map(function (p, i) {
          return C('Up to ' + rm(p.spec.ad_budget) + ' / month', i === group.length - 1 ? wide - pw * (group.length - 1) : pw);
        })));
        if (boosters.length) {
          row([C('', lw, { skip: true }), L(boosters.map(function (b) {
            return '+ ' + rm(b.rate) + ' service fee to cover up to ' + rm(b.spec.budget) + ' / month';
          }).join('\n'), wide)]);
        }
        merged(C('Advertising Budget*', lw, { fill: head }), M, top, y);
      }
      row(cells('Best for', function (p) { return L(p.spec.best_for || '', 0); }));
      gap();
    };
    planTable(plans.filter(function (p) { return !p.spec.ads; }), false);
    planTable(plans.filter(function (p) { return p.spec.ads; }), true);
    if (T.custom_pricing) {
      var cp = wrap(T.custom_pricing, FULL - 20, BODY);
      var ch = 22 + cp.length * LEAD + 12;
      room(ch);
      page.drawRectangle({ x: M, y: y - ch, width: FULL, height: ch, borderColor: edge, borderWidth: 0.8 });
      text('Custom Pricing', M + 8, y - 20, 13, reg, ink);
      var cy = y - 34;
      cp.forEach(function (l) { text(l, M + 8, cy, BODY, book, ink); cy -= LEAD; });
      y -= ch;
      gap(18);
    }
    if (T.plans_note) { label('Note'); plain(T.plans_note); }

    /* 4. KOC Programmes. */
    var koc = role('koc');
    newPage('KOC Programmes');
    if (T.koc_intro) {
      var intro = lines(T.koc_intro).map(function (l) { return l.replace(/\s*\|\s*/, ' — '); });
      var il = [];
      intro.forEach(function (l) { il = il.concat(wrap(l, FULL - 16, BODY)); });
      var ih = il.length * LEAD + 14;
      page.drawRectangle({ x: M, y: y - ih, width: FULL, height: ih, color: head });
      var iy = y - 7 - BODY;
      il.forEach(function (l) { text(l, M + 8, iy, BODY, book, ink); iy -= LEAD; });
      y -= ih;
      gap(14);
    }
    var fw = [FULL * 0.23, FULL * 0.385, FULL - FULL * 0.23 - FULL * 0.385];
    if (T.koc_formats) {
      row([L('Push Formats', fw[0], { fill: deep }), C('What It Involves', fw[1], { fill: head }), C('Best For', fw[2], { fill: head })]);
      lines(T.koc_formats).forEach(function (l) {
        var c = cols(l);
        row([L(c[0], fw[0]), L(c[1] || '', fw[1]), L(c[2] || '', fw[2])]);
      });
      gap();
    }
    var packs = koc.filter(function (s) { return s.spec.creators; });
    if (packs.length) {
      label('Services & Pricing');
      var kw = [FULL * 0.23, FULL * 0.385, FULL - FULL * 0.23 - FULL * 0.385];
      row([L('KOC Services', kw[0], { fill: deep }), C('I – Package', kw[1], { fill: head }), C('II – Custom', kw[2], { fill: head })]);
      var ktop = y;
      packs.forEach(function (s) {
        var avg = Math.round(Number(s.rate) / Number(s.spec.creators) / 10) * 10;   // the card's average, to the RM 10
        row([L(s.spec.creators + ' creators', kw[0]), C(rm(s.rate) + ' (avg. ' + rm(avg) + ' per KOC)', kw[1]), C('', kw[2], { skip: true })]);
      });
      merged(C(T.koc_custom_price || '', kw[2]), M + kw[0] + kw[1], ktop, y);
      row([L('What’s Included', kw[0]), L('', kw[1], { b: lines(T.koc_package_included) }), L('', kw[2], { b: lines(T.koc_custom_included) })]);
      if (T.koc_lead_time) { var lt = cols(T.koc_lead_time); row([L('Lead time', kw[0]), C(lt[0], kw[1]), C(lt[1] || '', kw[2])]); }
      if (T.koc_best_for) { var bf = cols(T.koc_best_for); row([L('Best For', kw[0]), L(bf[0], kw[1]), L(bf[1] || '', kw[2])]); }
      gap();
    }
    if (T.koc_timeline) {
      label('Timeline');
      var steps = lines(T.koc_timeline).map(cols);
      var sw = FULL / steps.length;
      row(steps.map(function (s) { return C(s[0], sw, { fill: head }); }));
      row(steps.map(function (s) { return C(s[1] || '', sw); }));
      gap();
    }
    if (T.koc_note) { label('Note'); bullets('koc_note'); }

    /* 5. KOL Programmes. */
    newPage('KOL Programmes');
    if (T.kol_intro) { plain(T.kol_intro); gap(4); }
    if (T.kol_tiers) {
      row([L('Tier', thirds[0], { fill: head }), C('Followers', thirds[1], { fill: head }), C('Indicative** Talent Fee', thirds[2], { fill: head })]);
      lines(T.kol_tiers).forEach(function (l) { var c = cols(l); row([L(c[0], thirds[0]), C(c[1] || '', thirds[1]), C(c[2] || '', thirds[2])]); });
      gap(4);
      if (T.kol_tiers_note) plain(T.kol_tiers_note, 6.5);
      gap(14);
    }
    var kol = role('kol')[0];
    if (kol) {
      label('Management Fee');
      included('What’s Included', 'kol_included', thirds[1] + thirds[2]);
      row([C('Talent Fee (Per)', thirds[0], { fill: head }), C('Management Fee (Per Talent)', thirds[1], { fill: head }), C('Minimum', thirds[2], { fill: head })]);
      var prev = 0;
      (kol.spec.tiers || []).forEach(function (t) {
        var band = t.upto == null ? 'Above ' + rm(prev) : prev ? rm(prev + 1) + ' to ' + rm(t.upto) : 'Up to ' + rm(t.upto);
        row([L(band, thirds[0]), C(t.pct + '%', thirds[1]), C(rm(t.min), thirds[2])]);
        if (t.upto != null) prev = Number(t.upto);
      });
      gap();
      if (T.kol_fee_note) plain(T.kol_fee_note);
    }

    /* 6. Add-ons, the term commitment and the Terms of Service. */
    newPage('Add-ons');
    var addons = live.filter(function (s) { var r = (s.spec || {}).role; return (r === 'addon' || r === 'language') && s.spec.group; })
      .sort(function (a, b) { return (a.position || 0) - (b.position || 0); });
    if (addons.length) {
      row([C('Item', thirds[0], { fill: head }), C('Rate', thirds[1], { fill: head }), C('Unit', thirds[2], { fill: head })]);
      var groups = [];
      addons.forEach(function (s) { if (groups.indexOf(s.spec.group) < 0) groups.push(s.spec.group); });
      groups.forEach(function (g, gi) {
        row([L(g, FULL, { fill: head })]);
        if (!gi && T.addons_included) { var ai = cols(T.addons_included); row([L(ai[0], thirds[0]), C(ai[1] || '', thirds[1]), C(ai[2] || '', thirds[2])]); }
        addons.filter(function (s) { return s.spec.group === g; }).forEach(function (s) {
          var from = /,\s*from$/i.test(s.unit || '');
          row([L(s.name, thirds[0]), C((from ? 'From ' : '') + rm(s.rate), thirds[1]), C(String(s.unit || '').replace(/,\s*from$/i, ''), thirds[2])]);
        });
      });
      gap(16);
    }
    var TERMS = [['term_1_3', '1 – 3 months'], ['term_4_5', '4 – 5.9 months'], ['term_6_11', '6 months'],
      ['term_12_23', '12 months'], ['term_24', '24 months']];
    var termRows = TERMS.filter(function (t) { return set[t[0]] != null && set[t[0]] !== ''; });
    if (termRows.length) {
      row([C('Discount', thirds[0], { fill: head }), C('Qualifying Condition', thirds[1], { fill: head }), C('Rate', thirds[2], { fill: head })]);
      var ttop = y;
      termRows.forEach(function (t) {
        var v = Number(set[t[0]]);
        row([C('', thirds[0], { skip: true }), L(t[1], thirds[1]), C(v > 0 ? '+' + v + '%' : v < 0 ? '- ' + Math.abs(v) + '%' : 'Quoted', thirds[2])]);
      });
      merged(L('Term Commitment', thirds[0], { fill: head }), M, ttop, y);
      gap(40);
    }
    if (T.terms) {
      label('Terms of Service');
      var until = longDay(card.valid_until);
      var terms = lines(T.terms).map(function (l) { return l.replace(/\{valid until\}/gi, until || 'further notice'); });
      terms.forEach(function (l, i) {
        var ws = wrap(l, FULL - 18, BODY);
        room(ws.length * LEAD + 2);
        text((i + 1) + '.', M + 2, y - BODY - 1, BODY, book, dark);
        ws.forEach(function (w) { text(w, M + 18, y - BODY - 1, BODY, book, dark); y -= LEAD; });
      });
    }

    /* The foot on every page: PRIVATE & CONFIDENTIAL and the page count on
       one line, the version under it. */
    var pages = pdf.getPages();
    pages.forEach(function (pg, i) {
      page = pg;
      text('PRIVATE & CONFIDENTIAL', M, 52, 6.4, med, dark);
      var t = 'Page ' + (i + 1) + ' of ' + pages.length;
      text(t, R - width(t, 6.4, book), 52, 6.4, book, dark);
      text(version, M, 34, 5.8, book, dark);
    });
  }

  window.ADspaceRateCardPdf = { draw: draw };
})();
