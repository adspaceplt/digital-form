/* The quotation PDF, drawn in the browser from a quotation as it was kept
 * (`quotations`: its lines, totals, reference, validity and the rate card
 * version it was priced from), never stored and never priced here: every
 * figure is the database's.
 *
 * Three pages, as approved (the user, 2026-10-31: one document, the
 * quotation acting as the Letter of Offer):
 *   1. the Quotation Cover, the team's letter on the letterhead, drawn by
 *      the letter engine itself (`ADspaceDocs.letterPages`), so it is the
 *      template exactly;
 *   2. the quotation on a continuation page (no second letterhead): a lead
 *      sentence, Description, Qty, Rate, Amount between hairlines, the
 *      totals at the right ending at the one bold figure, then TERMS;
 *   3. Acceptance of quotation: the figures agreed, Issued for and on behalf
 *      of ADSPACE PLT (Prepared by, Reviewed by), and the client's block to
 *      sign and stamp (Name, Designation, Date), left empty until signed.
 * Every page's foot is the reference, PRIVATE & CONFIDENTIAL and the page
 * count. A preview carries DRAFT over every page.
 */
(function () {
  'use strict';
  var D = function () { return window.ADspaceDocs; };
  var FLOOR = 70;
  var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
    'October', 'November', 'December'];
  var WORDS = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve',
    'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'];
  var TENS = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];
  /* The cover's words where the team's own Quotation Cover type is not to
     hand (a client page reads no document types): the type as seeded. */
  var COVER = {
    title: 'QUOTATION FOR DIGITAL MARKETING SERVICES', salutation: 'Dear Sir/Madam,', closing: 'Yours sincerely,',
    body_en: 'We are pleased to submit our quotation for your consideration. It has been prepared based on the scope and ' +
      'requirements discussed, with full details set out in the attached quotation.\n\nShould you need any clarification or ' +
      'additional information, please do not hesitate to reach out. We are happy to provide further materials to support ' +
      'your evaluation.\n\nThank you for the opportunity. We look forward to working with you and your team.'
  };
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
  function clockOf(ts) { return window.ADspaceClock ? window.ADspaceClock.clock(ts) : String(ts).slice(11, 16); }
  function cur(q) { return (q.totals || {}).currency === 'SGD' ? 'S$ ' : 'RM '; }
  function amt(n, q) {
    var v = Number(n || 0), s = window.ADspaceMoney.money2(Math.abs(v), 'MY').replace(/^RM /, cur(q));
    return v < 0 ? '(' + s + ')' : s;
  }
  function fileName(q) { return 'ADspace Quotation ' + String(q.ref || '').replace(/\//g, '-') + '.pdf'; }

  /* opts: attention (the contact named), attentionRole, to { name, address }
     (the registered company where known, else the brand), cover (the team's
     Quotation Cover type), preparedBy and reviewedBy ({ name, designation,
     day }), signed ({ name, designation, day, signature, record, via }:
     the client's signature on the acceptance page and how it was made),
     client (for the S$ line), draft. */
  function draw(q, opts) {
    var docs = D();
    opts = opts || {};
    if (!docs) return Promise.reject(new Error('The PDF tools are not loaded.'));
    var to = opts.to || {};
    var cjk = /[　-鿿＀-￯]/.test(String(q.brand || '') + String(opts.attention || '') + String(to.name || '') + String(to.address || ''));
    return docs.lib().then(function (PDF) {
      var pdf;
      return PDF.PDFDocument.create().then(function (doc) {
        pdf = doc;
        return Promise.all([docs.embedFonts(pdf, PDF, { cjk: cjk }), docs.embedLogo(pdf)]);
      }).then(function (got) {
        layout(pdf, PDF, got[0], got[1], q, opts);
        /* The reference in the file's title: a send by WhatsApp or email is
           checked against it (`_shared/pdfref.ts`). */
        pdf.setTitle('Quotation ' + q.ref);
        pdf.setAuthor('ADSPACE PLT');
        pdf.setSubject('Quotation');
        pdf.setCreator('ADspace Digital Portal');
        pdf.setProducer('ADspace Digital Portal');
        return pdf.save();
      }).then(function (bytes) { return new Blob([bytes], { type: 'application/pdf' }); });
    });
  }

  function layout(pdf, PDF, fonts, logo, q, opts) {
    var docs = D();
    var to = opts.to || {}, cover = opts.cover || COVER, prep = opts.preparedBy || {};
    var person = String(opts.attention || '').trim();

    // Page 1: the Quotation Cover, the letter engine's own page.
    var first = docs.letterPages(pdf, PDF, fonts, logo, {
      family: 'quote_cover', serial: q.ref, issued_at: q.issued_at, languages: ['en'], signed: false,
      recipient: { name: to.name || q.brand, address: to.address || '', attn: person, attn_role: opts.attentionRole || '' },
      title: cover.title || COVER.title,
      salutation: person ? 'Dear ' + person + ',' : (cover.salutation || COVER.salutation),
      closing: cover.closing || COVER.closing,
      body: { en: cover.body_en || COVER.body_en },
      signatory: { name: prep.name || '', designation: prep.designation || '' }
    });
    var pn = first.pn, pages = first.pages.slice();
    var W = pn.W, H = pn.H, M = pn.M, R = pn.R, FULL = R - M;
    var ink = pn.ink, mute = pn.mute, hair = PDF.rgb(0.812, 0.8, 0.776);
    var book = fonts.font, reg = fonts.bold;
    var hasCjk = function (s) { return /[　-鿿＀-￯]/.test(String(s)); };
    var face = function (s, f) { return fonts.cjk && hasCjk(s) ? fonts.cjk : f; };
    var safe = function (s) {
      s = String(s == null ? '' : s);
      return fonts.custom ? s : s.replace(/[^\x20-\x7E\xA0-\xFF]/g, '-');
    };
    var width = function (s, size, f) { f = face(s, f || book); return f.widthOfTextAtSize(safe(s), size); };
    var text = function (s, x, yy, size, f, color) {
      if (s == null || s === '') return;
      f = face(s, f || book);
      pn.page.drawText(safe(s), { x: x, y: yy, size: size, font: f, color: color || ink });
    };
    var right = function (s, xr, yy, size, f, color) { text(s, xr - width(s, size, f), yy, size, f, color); };
    var wrap = function (s, max, size, f) {
      var out = [], line = '';
      String(s == null ? '' : s).split(/(\s+)/).forEach(function (w) {
        if (!w) return;
        var t = line + w;
        if (width(t, size, f) <= max || !line.trim()) { line = t; return; }
        out.push(line.replace(/\s+$/, ''));
        line = /^\s+$/.test(w) ? '' : w;
      });
      if (line.trim()) out.push(line.replace(/\s+$/, ''));
      return out.length ? out : [''];
    };
    var rule = function (yy, x1, x2, heavy) {
      pn.page.drawLine({ start: { x: x1 == null ? M : x1, y: yy }, end: { x: x2 == null ? R : x2, y: yy },
        thickness: heavy ? 0.9 : 0.6, color: heavy ? ink : hair });
    };
    var box = function (x, yy, w, h) {
      pn.page.drawRectangle({ x: x, y: yy, width: w, height: h, borderColor: hair, borderWidth: 0.6 });
    };
    var y;
    /* A continuation page: no second letterhead (the user, 2026-10-31), a
       hairline across the top where the letterhead's foot would sit. */
    var newPage = function () {
      pn.page = pdf.addPage([W, H]);
      pages.push(pn.page);
      y = H - 50;
      rule(y);
      y -= 14;
    };
    var room = function (h) { if (y - h < FLOOR) { newPage(); return true; } return false; };
    var heading = function (s) { y -= 11; text(s, M, y, 11, reg); y -= 10; };
    var para = function (s, size, lead, f, color) {
      wrap(s, FULL, size, f).forEach(function (ln) { room(lead); y -= lead; text(ln, M, y + lead - size, size, f, color); });
    };

    var t = q.totals || {};
    var buyer = String(to.name || q.brand || '').toUpperCase();

    // Page 2: the quotation.
    newPage();
    heading('Quotation');
    para('Quotation ' + q.ref + ', dated ' + longDay(dayOf(q.issued_at)) + ' and valid until ' + longDay(q.valid_until) +
      ', for ' + buyer + ', setting out the services and fees proposed.', 11, 14.5);
    y -= 16;

    var TB = 10, SM = 8, cwQ = 30, cwR = 84, cwA = 92;
    var xA = R, xR = R - cwA - 8, xQ = xR - cwR - 8, wD = xQ - cwQ - 12 - M;
    var headRow = function () {
      y -= 9;
      text('Description', M, y, 8.5, book, mute);
      right('Qty', xQ, y, 8.5, book, mute);
      right('Rate', xR, y, 8.5, book, mute);
      right('Amount', xA, y, 8.5, book, mute);
      y -= 5;
      rule(y);
    };
    headRow();
    var taxed = window.ADspaceMoney.sstOf(q.lines, t.sst_pct);
    (q.lines || []).forEach(function (l) {
      var name = wrap(l.label, wD, TB, reg);
      var small = [];
      (l.detail || []).forEach(function (d, i) {
        /* The first inclusion on its own line, the rest run together. */
        if (i < 2) small.push(String(d)); else small[1] += ' · ' + d;
      });
      var sub = [];
      small.forEach(function (s) { sub = sub.concat(wrap(s, wD, SM, book)); });
      var under = [];
      if (l.basis === 'once') under.push('one-off');
      else if (l.basis === 'month') under.push(l.months && Number(l.months) !== Number(t.term) ? l.months + (Number(l.months) === 1 ? ' month' : ' months') : 'per month');
      var tag = taxed.tag(l);
      if (tag) under.push(tag);
      var h = 7 + Math.max(name.length * 13 + sub.length * 11, 13 + under.length * 11);
      if (room(h + 4)) headRow();
      var top = y - 7;
      name.forEach(function (s, k) { text(s, M, top - 10 - k * 13, TB, reg); });
      sub.forEach(function (s, k) { text(s, M, top - 10 - name.length * 13 + 2 - k * 11, SM, book, mute); });
      right(String(l.qty), xQ, top - 10, TB);
      right(amt(l.rate, q), xR, top - 10, TB);
      right(amt(l.amount, q), xA, top - 10, TB);
      under.forEach(function (s, k) { right(s, xA, top - 10 - 13 + 2 - k * 11, SM, book, mute); });
      y -= h;
    });
    y -= 6;
    rule(y);
    y -= 8;

    /* The totals: ADspaceMoney.quoteRows, one copy (QT-4), named as the
       Letter of Offer names them: where a monthly line runs months of its
       own the month's figures are the first month's, the one-off items in
       it (the user, 2026-10-18). */
    var own = (q.lines || []).some(function (l) { return l.basis === 'month' && l.months && Number(l.months) !== Number(t.term); });
    var sstOn = taxed.on, incl = sstOn ? ' incl. SST' : '';
    var WORD = { monthSub: 'Monthly subtotal', onceSub: 'One-off subtotal', firstExcl: 'First month excl. SST', monthExcl: 'Monthly excl. SST',
      sst: taxed.word, first: 'First month' + incl, monthly: 'Monthly' + incl, oneOff: sstOn ? 'One-off incl. SST' : 'One-off total',
      term: t.term + '-month ' + (t.term_pct < 0 ? 'commitment (' + Math.abs(t.term_pct) + '%)' : 'term (' + t.term_pct + '%)') };
    var tot = window.ADspaceMoney.quoteRows(t, q.lines, sstOn).map(function (x) { return [WORD[x[0]], amt(x[1], q), x[2]]; });
    var TW = 255, tx = R - TW;
    room(tot.length * 17 + 12);
    tot.forEach(function (r) {
      if (r[2]) { y -= 6; rule(y, tx, R, true); y -= 5; }
      y -= 17;
      text(r[0], tx, y + 5, TB, r[2] ? reg : book, r[2] ? ink : mute);
      right(r[1], R, y + 5, TB, r[2] ? reg : book);
    });
    /* A Singapore client billed in RM reads the figure in S$ under it, at
       the rate in force on the day of issue (2026-10-22). */
    var MONY = window.ADspaceMoney, last = tot.filter(function (r) { return r[2]; }).pop();
    var lastVal = last ? Number(String(last[1]).replace(/[^0-9.\-]/g, '')) : 0;
    var near = opts.client && t.currency !== 'SGD' && MONY && MONY.approx && last ? MONY.approx(lastVal, opts.client, dayOf(q.issued_at)) : '';
    if (near) { y -= 13; right(near.replace(/^ \(|\)$/g, '').replace(/^approx/, 'Approx'), R, y + 3, SM, book, mute); }
    y -= 22;

    // TERMS.
    var days = Math.round((Date.parse(q.valid_until + 'T00:00:00Z') - Date.parse(dayOf(q.issued_at) + 'T00:00:00Z')) / 864e5);
    var notes = ['This quotation is valid for ' + both(days) + ' days from its date of issue, until ' + longDay(q.valid_until) + '.'];
    var holds = [];
    if (own && t.once) holds.push('the one-off items');
    if (sstOn) holds.push(/\d/.test(taxed.word) ? taxed.word.replace(/^SST /, 'SST at ') : 'SST');
    if (t.month && holds.length) notes.push((own ? 'The first month\'s amount' : 'The amount per month') + ' includes ' + holds.join(' and ') + '.');
    if (Number(t.budget) > 0 || (q.lines || []).some(function (l) { return l.kind === 'ads' || l.kind === 'plan'; })) {
      notes.push('The advertising budget is not included in the service fee and is billed separately.');
    }
    if ((t.on_request || []).length) {
      notes.push('The following are quoted on request: ' + t.on_request.map(function (x) {
        return x === 'budget' ? 'an advertising budget above the highest tier on our rate card' : x;
      }).join(', ') + '.');
    }
    if (t.month) {
      notes.push((own ? 'The total commitment over the months stated for each line' : 'The total commitment for ' + both(t.term) + ' months') +
        ' is ' + amt(t.commitment, q) + incl + (t.once ? ', one-off items included.' : '.'));
    }
    notes.push('This quotation becomes binding once accepted and signed on its acceptance page. Together with the ADspace ' +
      'Service Terms at go.adspace.me/svc-terms, it forms the contract between the parties.');
    notes.push('Rates are based on the ADspace Rate Card v.' + q.version + '. E&OE.');
    room(30);
    y -= 8;
    text('TERMS', M, y, SM, book, mute);
    y -= 6;
    notes.forEach(function (n, i) {
      var ls = wrap(n, FULL - 14, 8.5, book);
      room(ls.length * 12 + 2);
      y -= 12;
      text((i + 1) + '.', M, y + 3, 8.5);
      ls.forEach(function (s, k) { text(s, M + 14, y + 3 - k * 12, 8.5); });
      y -= (ls.length - 1) * 12;
    });

    // Page 3: Acceptance of quotation, always a page of its own.
    newPage();
    heading('Acceptance of quotation');
    para('By signing below, the Client accepts Quotation ' + q.ref + ', dated ' + longDay(dayOf(q.issued_at)) + ', including the ' +
      'services, fees and terms set out in this document and the ADspace Service Terms at go.adspace.me/svc-terms.', 11, 14.5);
    y -= 12;
    var agreed = [];
    if (last) agreed.push([last[0], last[1]]);
    if (t.month) {
      agreed.push(['Minimum term', t.term + ' months']);
      agreed.push(['Total for the term' + incl, amt(t.commitment, q)]);
    }
    rule(y);
    y -= 4;
    agreed.forEach(function (r) { y -= 16; text(r[0], M, y + 4, TB); right(r[1], R, y + 4, TB); });
    y -= 8;
    rule(y);
    y -= 24;

    var block = function (title) { text(title, M, y, 11, reg); y -= 12; };
    // Issued for and on behalf of ADSPACE PLT: Prepared by, Reviewed by.
    block('Issued for and on behalf of ADSPACE PLT');
    var rev = opts.reviewedBy || {};
    var halfW = FULL / 2, ih = 56;
    box(M, y - ih, halfW, ih);
    box(M + halfW, y - ih, halfW, ih);
    [['Prepared by', prep.name, [prep.designation, longDay(prep.day || dayOf(q.issued_at))]],
      ['Reviewed by', rev.name, rev.name ? [rev.designation, longDay(rev.day)] : []]].forEach(function (c, i) {
      var x = M + i * halfW + 8;
      text(c[0], x, y - 15, 8.5, book, mute);
      if (c[1]) text(c[1], x, y - 30, TB, reg);
      var meta = (c[2] || []).filter(Boolean).join(' · ');
      if (meta) text(meta, x, y - 44, 8.5, book, mute);
    });
    y -= ih + 26;

    // The client's block: sign and stamp, Name, Designation, Date.
    var signer = opts.signed || null;
    block('Confirmed and accepted for and on behalf of ' + buyer);
    var sh = 96, cw = FULL * 0.48, lw = 62, rh = sh / 3;
    box(M, y - sh, cw, sh);
    text(signer ? 'Authorised signatory' : 'Authorised signatory and company stamp', M + 6, y - sh + 6, 8.5, book, mute);
    [['Name', signer && signer.name], ['Designation', signer && signer.designation], ['Date', signer && longDay(signer.day)]].forEach(function (r, i) {
      var top = y - i * rh;
      box(M + cw, top - rh, lw, rh);
      box(M + cw + lw, top - rh, FULL - cw - lw, rh);
      text(r[0], M + cw + 6, top - rh / 2 - 3, 8.5, book, mute);
      if (r[1]) text(r[1], M + cw + lw + 8, top - rh / 2 - 3.5, TB, reg);
    });
    /* The signature as the client drew it (an SVG path in a 300 by 100
       box) or typed it; a signature made on paper is held by its scan. */
    var sig = signer && signer.signature;
    if (sig && sig.type === 'drawn' && /^[MLQCZmlqcz0-9 .,-]+$/.test(String(sig.path || ''))) {
      var sc = Math.min((cw - 16) / 300, (sh - 22) / 100);
      try {
        pn.page.drawSvgPath(sig.path, { x: M + 8 + ((cw - 16) - 300 * sc) / 2, y: y - 4, scale: sc,
          borderColor: ink, borderWidth: 1.6 / sc });
      } catch (e) { /* a path the PDF tools cannot read leaves the box as signed below */ }
    } else if (sig && sig.type === 'typed' && sig.text) {
      text(sig.text, M + 10, y - sh / 2 - 2, 18, reg);
    }
    y -= sh;
    // How it was signed, under the box.
    var rec = signer && signer.record;
    if (signer && signer.via) {
      var lines2 = [];
      if (signer.via === 'online' && rec) {
        lines2.push('Signed electronically on ' + longDay(dayOf(rec.at)) + ', ' + clockOf(rec.at) + ' (GMT+8), confirmed by a code sent to ' + rec.email + '.');
        lines2.push(['IP address ' + (rec.ip || 'not recorded') + (rec.country ? ' (' + rec.country + ')' : ''),
          rec.fingerprint ? 'Document fingerprint ' + rec.fingerprint : ''].filter(Boolean).join(' · ') + '.');
      } else if (signer.via === 'paper') {
        lines2.push('Signed on paper on ' + longDay(signer.day) + '; the signed copy is kept by ADspace.');
      }
      y -= 6;
      lines2.forEach(function (s) { wrap(s, FULL, SM, book).forEach(function (ln) { y -= 11; text(ln, M, y, SM, book, mute); }); });
    }

    // The foot on every page; a preview is a draft over every page.
    docs.letterFoot(pn, pages, q.ref, 'PRIVATE & CONFIDENTIAL');
    if (opts.draft) pages.forEach(function (pg) { docs.watermark(pg, 'DRAFT (INTERNAL USE ONLY)', fonts.font); });
  }

  window.ADspaceQuotePdf = { draw: draw, fileName: fileName, COVER: COVER };
})();
