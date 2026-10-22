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
      /* A Singapore client's quotation is in S$ (its totals say so; 2026-10-15). */
      var cur = (q.totals || {}).currency === 'SGD' ? 'S$' : 'RM';
      ['Description', 'Qty', 'Rate (' + cur + ')', 'Subtotal (' + cur + ')'].forEach(function (h, i) {
        rect(cx[i], y - hh, cw[i], hh, fill);
        if (i === 0) text(h, cx[i] + 6, y - hh / 2 - 3.2, BODY, book, dark);
        else right(h, cx[i] + cw[i] - 6, y - hh / 2 - 3.2, BODY, book, dark);
      });
      y -= hh;
    };
    headRow();
    var taxed = window.ADspaceMoney.sstOf(q.lines, t.sst_pct);
    (q.lines || []).forEach(function (l) {
      var rows = wrap(l.label, cw[0] - 12, BODY, book).map(function (s) { return { s: s, c: dark }; });
      (l.detail || []).forEach(function (d) {
        wrap(d, cw[0] - 20, BODY, book).forEach(function (s, i) { rows.push({ s: s, c: mute, b: i === 0, x: 8 }); });
      });
      if (l.basis === 'once') rows.push({ s: 'One-off', c: mute });
      /* A line quoted for months of its own says so (2026-10-15). */
      if (l.basis === 'month' && l.months && Number(l.months) !== Number(t.term)) rows.push({ s: l.months + (Number(l.months) === 1 ? ' month' : ' months'), c: mute });
      /* A line on another tax rate says so (2026-10-22). */
      if (taxed.note(l)) rows.push({ s: taxed.note(l), c: mute });
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
    /* Where a monthly line runs months of its own, the month's figures are
       the first month's, every monthly line running in it, and are named so
       (the user, 2026-10-18), as the Letter of Offer names them. */
    /* The first month holds the one-off items too (the user, 2026-10-18),
       so its rows add the one-off subtotal before SST and end at one figure. */
    var own = (q.lines || []).some(function (l) { return l.basis === 'month' && l.months && Number(l.months) !== Number(t.term); });
    var tot = [], sum = function (a, b) { return Math.round((Number(a || 0) + Number(b || 0)) * 100) / 100; };
    /* SST said as the Letter of Offer says it (ADspaceMoney.sstApplies). */
    /* Each line at its own tax code's rate where it carries one (2026-10-22). */
    var sstOn = taxed.on, incl = sstOn ? ' incl. SST' : '';
    var sstRow = taxed.word;
    var excl = function (label, v) { if (sstOn) tot.push([label + ' excl. SST', amt(v)]); };
    if (t.month) {
      tot.push(['Monthly subtotal', amt(t.month.subtotal)]);
      if (Number(t.term_pct)) {
        tot.push([t.term + '-Month ' + (t.term_pct < 0 ? 'Commitment (' + Math.abs(t.term_pct) + '%)' : 'Term (' + t.term_pct + '%)'), amt(t.month.term)]);
      }
      if (own) {
        var o = t.once || {};
        if (t.once) tot.push(['One-off subtotal', amt(o.subtotal)]);
        excl('First month', sum(t.month.excl, o.subtotal));
        tot.push([sstRow, amt(sum(t.month.sst, o.sst))], ['First month' + incl, amt(sum(t.month.incl, o.incl)), 1]);
      } else {
        excl('Monthly', t.month.excl);
        tot.push([sstRow, amt(t.month.sst)], ['Monthly' + incl, amt(t.month.incl), 1]);
      }
    }
    if (t.once && !(t.month && own)) {
      tot.push(['One-off subtotal', amt(t.once.subtotal)], [sstRow, amt(t.once.sst)], [sstOn ? 'One-off incl. SST' : 'One-off total', amt(t.once.incl), 1]);
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
    /* A Singapore client billed in RM reads the figure in S$ beside it, at
       the rate in force on the day of issue (2026-10-22). */
    var MONY = window.ADspaceMoney, last = tot.filter(function (r) { return r[2]; }).pop();
    var near = opts.client && t.currency !== 'SGD' && MONY && MONY.approx && last ? MONY.approx(Number(String(last[1]).replace(/[^0-9.\-]/g, '')), opts.client, dayOf(q.issued_at)) : '';
    if (near) { y -= 4; right(near.replace(/^ \(|\)$/g, '').replace(/^approx/, 'Approx'), R - 6, y - 9, BODY - 1, book, mute); y -= 14; }
    y -= 18;

    // Remarks / Terms.
    var days = Math.round((Date.parse(q.valid_until + 'T00:00:00Z') - Date.parse(dayOf(q.issued_at) + 'T00:00:00Z')) / 864e5);
    var notes = ['This quotation is valid for ' + both(days) + ' days from its date of issue.'];
    /* One sentence of what the figure holds; SST named only where it applies. */
    var holds = [];
    if (own && t.once) holds.push('the one-off items');
    if (sstOn) holds.push('SST at ' + t.sst_pct + '%');
    if (t.month && holds.length) notes.push((own ? 'The first month\'s amount' : 'The amount per month') + ' includes ' + holds.join(' and ') + '.');
    if (Number(t.budget) > 0 || (q.lines || []).some(function (l) { return l.kind === 'ads' || l.kind === 'plan'; })) {
      notes.push('The advertising budget is not included in the service fee and is billed separately.');
    }
    if ((t.on_request || []).length) {
      notes.push('The following are quoted on request: ' + t.on_request.map(function (x) {
        return x === 'budget' ? 'an advertising budget above the highest tier on our rate card' : x;
      }).join(', ') + '.');
    }
    notes.push('Upon your written confirmation of this quotation, or the issue of a PO reference, a Letter of Offer will be issued ' +
      'and work will begin per the agreed timeline. The Letter of Offer and our Service Terms at go.adspace.me/svc-terms together ' +
      'form the binding contract.');
    if (t.month) {
      notes.push((own ? 'The total commitment over the months stated for each line' : 'The total commitment for ' + both(t.term) + ' months') +
        ' is ' + ((q.totals || {}).currency === 'SGD' ? 'S$ ' : 'RM ') + amt(t.commitment) + incl +
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
