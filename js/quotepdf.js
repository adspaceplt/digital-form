/* The quotation PDF (2026-10-14), drawn in the browser from a quotation as
 * it was kept (`quotations`: its lines, totals, reference, validity and the
 * rate card version it was priced from), never stored and never priced
 * here: every figure is the database's.
 *
 * As approved on the canvas (the user, 2026-10-13): the wordmark with
 * ADSPACE PLT at the right of the head, Quotation, the facts (Reference,
 * Date, Prepared for, Valid until, Attention, Commitment), the lines
 * (Description, Qty, Rate (RM), Subtotal (RM)), the totals ending at Monthly
 * incl. SST, Remarks / Terms a step smaller, and over PRIVATE &
 * CONFIDENTIAL the rate card line. Amounts are right aligned to two
 * decimals, a discount in brackets; a whole term's total is said in the
 * remarks alone.
 */
(function () {
  'use strict';
  var D = function () { return window.ADspaceDocs; };
  var W = 595.28, H = 841.89, M = 33, R = W - M, FULL = R - M;
  var BODY = 9.5, LEAD = 13.8, SMALL = 8, FLOOR = 70;
  var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
    'October', 'November', 'December'];
  var WORDS = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve',
    'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'];
  var TENS = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];
  function inWords(n) {
    n = Math.floor(Number(n) || 0);
    if (n < 20) return WORDS[n];
    if (n < 100) return TENS[Math.floor(n / 10)] + (n % 10 ? '-' + WORDS[n % 10] : '');
    return String(n);
  }
  function both(n) { return inWords(n) + ' (' + n + ')'; }
  function longDay(iso) {
    var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso || ''));
    return m ? Number(m[3]) + ' ' + MONTHS[Number(m[2]) - 1] + ' ' + m[1] : '';
  }
  function dayOf(ts) { return window.ADspaceClock ? window.ADspaceClock.day(ts) : String(ts).slice(0, 10); }
  function amt(n) {
    var v = Number(n || 0), s = window.ADspaceMoney.money2(Math.abs(v), 'MY').replace(/^RM /, '');
    return v < 0 ? '(' + s + ')' : s;
  }
  function fileName(q) { return 'ADspace Quotation ' + String(q.ref || '').replace(/\//g, '-') + '.pdf'; }

  function draw(q, opts) {
    var docs = D();
    opts = opts || {};
    if (!docs) return Promise.reject(new Error('The PDF tools are not loaded.'));
    var cjk = /[　-鿿＀-￯]/.test(String(q.brand || '') + String(opts.attention || ''));
    return docs.lib().then(function (PDF) {
      var pdf;
      return PDF.PDFDocument.create().then(function (doc) {
        pdf = doc;
        pdf.setTitle('Quotation ' + q.ref);
        pdf.setAuthor('ADSPACE PLT');
        pdf.setSubject('Quotation');
        pdf.setCreator('ADspace Digital Portal');
        pdf.setProducer('ADspace Digital Portal');
        return docs.embedFonts(pdf, PDF, { cjk: cjk });
      }).then(function (fonts) {
        layout(pdf, PDF, fonts, q, opts);
        return pdf.save();
      }).then(function (bytes) { return new Blob([bytes], { type: 'application/pdf' }); });
    });
  }

  function layout(pdf, PDF, fonts, q, opts) {
    var ink = PDF.rgb(0.251, 0.251, 0.251), dark = PDF.rgb(0.106, 0.102, 0.090), mute = PDF.rgb(0.4, 0.4, 0.4);
    var fill = PDF.rgb(0.949, 0.949, 0.949), edge = PDF.rgb(0.91, 0.91, 0.91);
    var book = fonts.font, reg = fonts.bold, med = fonts.med || fonts.bold, mark = fonts.mark || med;
    var hasCjk = function (s) { return /[　-鿿＀-￯]/.test(String(s)); };
    var face = function (s, f) { return fonts.cjk && hasCjk(s) ? fonts.cjk : f; };
    var safe = function (s, f) {
      s = String(s == null ? '' : s);
      return fonts.custom ? s : s.replace(/[^\x20-\x7E\xA0-\xFF]/g, '-');
    };
    var width = function (s, size, f) { f = face(s, f || book); return f.widthOfTextAtSize(safe(s, f), size); };
    var page, y, pages = [];
    var text = function (s, x, yy, size, f, color) {
      if (s == null || s === '') return;
      f = face(s, f || book);
      page.drawText(safe(s, f), { x: x, y: yy, size: size, font: f, color: color || ink });
    };
    var right = function (s, xr, yy, size, f, color) { text(s, xr - width(s, size, f), yy, size, f, color); };
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
    var rect = function (x, yy, w, h, bg) {
      page.drawRectangle({ x: x, y: yy, width: w, height: h, color: bg || undefined, borderColor: edge, borderWidth: 0.8 });
    };
    var newPage = function () {
      page = pdf.addPage([W, H]);
      pages.push(page);
      text('ADspace', M, H - 49, 16, mark, ink);
      right('ADSPACE PLT', R, H - 46, 7.5, med, dark);
      y = H - 64;
    };
    var room = function (h) { if (y - h < FLOOR) { newPage(); return true; } return false; };

    newPage();
    text('Quotation', M, y - 19, 19, reg, dark);
    y -= 34;

    // The facts: two pairs a row, the label shaded.
    var t = q.totals || {};
    var facts = [['Reference', q.ref, 'Date', longDay(dayOf(q.issued_at))],
      ['Prepared for', q.brand, 'Valid until', longDay(q.valid_until)],
      ['Attention', opts.attention || '—', t.month ? 'Commitment' : '', t.month ? t.term + ' months' : '']];
    var lw = 96, vw = (FULL - lw * 2) / 2, fh = 24;
    facts.forEach(function (r) {
      var xs = [M, M + lw, M + lw + vw, M + lw * 2 + vw], ws = [lw, vw, lw, vw];
      for (var i = 0; i < 4; i++) {
        rect(xs[i], y - fh, ws[i], fh, i % 2 ? null : fill);
        text(r[i], xs[i] + 6, y - fh / 2 - 3.2, BODY, i % 2 ? book : book, i % 2 ? dark : ink);
      }
      y -= fh;
    });
    y -= 12;

    // The lines.
    var cw = [FULL - 46 - 88 - 88, 46, 88, 88];
    var cx = [M, M + cw[0], M + cw[0] + cw[1], M + cw[0] + cw[1] + cw[2]];
    var headRow = function () {
      var hh = 24;
      ['Description', 'Qty', 'Rate (RM)', 'Subtotal (RM)'].forEach(function (h, i) {
        rect(cx[i], y - hh, cw[i], hh, fill);
        if (i === 0) text(h, cx[i] + 6, y - hh / 2 - 3.2, BODY, book, dark);
        else right(h, cx[i] + cw[i] - 6, y - hh / 2 - 3.2, BODY, book, dark);
      });
      y -= hh;
    };
    headRow();
    (q.lines || []).forEach(function (l) {
      var rows = wrap(l.label, cw[0] - 12, BODY, book).map(function (s) { return { s: s, c: dark }; });
      (l.detail || []).forEach(function (d) {
        wrap(d, cw[0] - 20, BODY, book).forEach(function (s, i) { rows.push({ s: s, c: mute, b: i === 0, x: 8 }); });
      });
      if (l.basis === 'once') rows.push({ s: 'One-off', c: mute });
      /* A line quoted for months of its own says so (2026-10-15). */
      if (l.basis === 'month' && l.months && Number(l.months) !== Number(t.term)) rows.push({ s: l.months + ' months', c: mute });
      var h = rows.length * 12.4 + 12;
      if (room(h)) headRow();
      for (var i = 0; i < 4; i++) rect(cx[i], y - h, cw[i], h, null);
      rows.forEach(function (r, k) {
        var yy = y - 6 - 9.2 - k * 12.4;
        if (r.b) text('•', cx[0] + 6, yy, BODY, book, r.c);
        text(r.s, cx[0] + 6 + (r.x || 0), yy, BODY, book, r.c);
      });
      var y0 = y - 6 - 9.2;
      right(String(l.qty), cx[1] + cw[1] - 6, y0, BODY, book, dark);
      right(amt(l.rate), cx[2] + cw[2] - 6, y0, BODY, book, dark);
      right(amt(l.amount), cx[3] + cw[3] - 6, y0, BODY, book, dark);
      y -= h;
    });
    y -= 12;

    // The totals, ending at Monthly incl. SST (and One-off incl. SST).
    var tot = [];
    if (t.month) {
      tot.push(['Monthly subtotal', amt(t.month.subtotal)]);
      if (Number(t.term_pct)) {
        tot.push([t.term + '-Month ' + (t.term_pct < 0 ? 'Commitment (' + Math.abs(t.term_pct) + '%)' : 'Term (' + t.term_pct + '%)'), amt(t.month.term)]);
      }
      tot.push(['Monthly excl. SST', amt(t.month.excl)], ['SST ' + t.sst_pct + '%', amt(t.month.sst)], ['Monthly incl. SST', amt(t.month.incl), 1]);
    }
    if (t.once) {
      tot.push(['One-off subtotal', amt(t.once.subtotal)], ['SST ' + t.sst_pct + '%', amt(t.once.sst)], ['One-off incl. SST', amt(t.once.incl), 1]);
    }
    var tw1 = 176, tw2 = 88, tx = R - tw1 - tw2, th = 24;
    room(tot.length * th + 8);
    tot.forEach(function (r) {
      rect(tx, y - th, tw1, th, r[2] ? fill : null);
      rect(tx + tw1, y - th, tw2, th, r[2] ? fill : null);
      text(r[0], tx + 6, y - th / 2 - 3.2, BODY, book, dark);
      right(r[1], R - 6, y - th / 2 - 3.2, BODY, r[2] ? reg : book, dark);
      y -= th;
    });
    y -= 18;

    // Remarks / Terms.
    var days = Math.round((Date.parse(q.valid_until + 'T00:00:00Z') - Date.parse(dayOf(q.issued_at) + 'T00:00:00Z')) / 864e5);
    var notes = ['This quotation is valid for ' + both(days) + ' days from its date of issue.'];
    if (t.month) notes.push('The amount per month incl. SST is inclusive of applicable ' + t.sst_pct + '% SST.');
    if (Number(t.budget) > 0 || (q.lines || []).some(function (l) { return l.kind === 'ads' || l.kind === 'plan'; })) {
      notes.push('The advertising budget is not included in the service fee and is billed separately.');
    }
    if ((t.on_request || []).length) {
      notes.push('The following are quoted on request: ' + t.on_request.map(function (x) {
        return x === 'budget' ? 'advertising budget above RM 20,000' : x;
      }).join(', ') + '.');
    }
    notes.push('Upon your written confirmation of this quotation, or the issue of a PO reference, a Letter of Offer will be issued ' +
      'and work will begin per the agreed timeline. The Letter of Offer and our Service Terms at go.adspace.me/svc-terms together ' +
      'form the binding contract.');
    if (t.month) {
      var own = (q.lines || []).some(function (l) { return l.basis === 'month' && l.months && Number(l.months) !== Number(t.term); });
      notes.push((own ? 'The total commitment over the months stated for each line' : 'The total commitment for ' + both(t.term) + ' months') +
        ' is RM ' + amt(t.commitment) + ' incl. SST' +
        (t.once ? ', one-off items included.' : '.'));
    }
    room(40);
    text('Remarks / Terms', M, y - 9.5, 9.5, med, dark);
    y -= 17;
    notes.forEach(function (n, i) {
      var ls = wrap(n, FULL - 12, SMALL, book);
      room(ls.length * 11.2 + 2);
      text((i + 1) + '.', M, y - SMALL, SMALL, book, ink);
      ls.forEach(function (s, k) { text(s, M + 12, y - SMALL - k * 11.2, SMALL, book, ink); });
      y -= ls.length * 11.2 + 2;
    });

    // The foot on every page.
    pages.forEach(function (p, i) {
      page = p;
      if (i === pages.length - 1) {
        text('Rates are based on the ADspace Rate Card v.' + q.version + '. E&OE (Ref.: ' + q.ref + ')', M, 46, 7.5, book, mute);
      }
      text('PRIVATE & CONFIDENTIAL', M, 30, 7.5, med, dark);
      right('Page ' + (i + 1) + ' of ' + pages.length, R, 30, 7.5, book, dark);
    });
  }

  window.ADspaceQuotePdf = { draw: draw, fileName: fileName };
})();
