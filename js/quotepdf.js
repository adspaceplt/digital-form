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
  /* The issuer and the agency, read from the shared config at the draw, as
     every PDF reads them (the demo's sample agency on sample data). */
  function CFG() { return window.ADSPACE_CONFIG || {}; }
  var KEPT = null;
  function agency() { return (KEPT && KEPT.a) || CFG().agencyName || 'ADspace'; }
  function issuer() { return (window.ADSPACE_ORG || {}).name || 'ADSPACE PLT'; }
  /* The Service Terms clause, left out where none is set. */
  function termsAt(lead) { var u = KEPT ? KEPT.t : CFG().serviceTermsUrl; return u ? lead + agency() + ' Service Terms at ' + u : ''; }
  var FLOOR = 76;
  var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
    'October', 'November', 'December'];
  var WORDS = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve',
    'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'];
  /* The days a quotation stands (QUOTATION VALID FOR ITS OWN DAYS,
     2026-11-27): its own Valid for, else the days from the day it went out
     (a website request's send, a team's date) to its valid_until. */
  function validDays(q) {
    var v = Number(q && q.selection && q.selection.valid);
    if ([14, 30, 45, 60, 90].indexOf(v) > -1) return v;
    return Math.round((Date.parse(q.valid_until + 'T00:00:00Z') - Date.parse(dayOf(q.released_at || q.issued_at) + 'T00:00:00Z')) / 864e5);
  }
  var TENS = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];
  /* The cover's words where the team's own Quotation Cover type is not to
     hand (a client page reads no document types): the type as seeded. */
  var COVER = {
    title: 'QUOTATION FOR DIGITAL MARKETING SERVICES', salutation: 'Dear Sir/Madam,', closing: 'Yours sincerely,',
    body_en: 'We are pleased to submit our quotation for your consideration. It has been prepared based on the scope and ' +
      'requirements discussed, with full details set out in the following pages.\n\nShould you need any clarification or ' +
      'additional information, please do not hesitate to contact us. We would be pleased to provide further materials to support ' +
      'your evaluation.'
  };
  function inWords(n) {
    n = Math.floor(Number(n) || 0);
    if (n < 20) return WORDS[n];
    if (n < 100) return TENS[Math.floor(n / 10)] + (n % 10 ? '-' + WORDS[n % 10] : '');
    return String(n);
  }
  function both(n) { return inWords(n) + ' (' + n + ')'; }
  /* HOW AD SPEND WORKS (2026-11-27, the user): where the advertising
     budget is not in the quotation, the PDF says so and names the two ways
     it is paid, with Settings' figures as they stood on the quotation's day
     (`ad_prepay_pct`, `ad_credit_fee_pct`; js/money.js), so a copy redrawn
     later reads as issued. `formal`: TERMS in a contract's register. */
  function pctOf(v) { return String(Math.round(Number(v) * 100) / 100) + '%'; }
  function adWays(q, formal) {
    var M = window.ADspaceMoney, at = q.issued_at || undefined;
    var pct = pctOf(M && M.setting ? M.setting('ad_prepay_pct', at) : 80), fee = pctOf(M && M.setting ? M.setting('ad_credit_fee_pct', at) : 20);
    return formal
      ? 'The Advertising Budget is paid either by the Client\'s own credit card through the Client\'s own ad account, or in advance to ' + agency() +
        ' each month before the ads run. Each following month is requested when about ' + pct + ' of the current budget is spent. Where it is ' +
        'instead invoiced on the payment terms of this Quotation, an Agency Credit Term Fee of ' + fee + ' of the Advertising Budget applies.'
      : 'It is paid by the client\'s own credit card through the client\'s own ad account, or prepaid to ' + agency() + ' each month before the ads run. ' +
        'Each following month is requested when about ' + pct + ' of the current budget is spent. Where the advertising budget is invoiced on this quotation\'s payment terms instead, an Agency Credit Term Fee of ' +
        fee + ' of the advertising budget applies.';
  }
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
  /* A period's last day: ADspaceClock's, one copy (2026-11-12). */
  function endOf(day, n) { return window.ADspaceClock.periodEnd(day, n); }
  function fileName(q) { return agency() + ' Quotation ' + String(q.ref || '').replace(/\//g, '-') + '.pdf'; }

  /* opts: attention (the contact named), attentionRole, to { name, address }
     (the registered company where known, else the brand), cover (the team's
     Quotation Cover type), preparedBy and reviewedBy ({ name, designation,
     day }), signed ({ name, designation, day, signature, record, via }:
     the client's signature on the acceptance page and how it was made),
     client (for the S$ line), draft. */
  function draw(q, opts) {
    var docs = D();
    opts = opts || {};
    if (!docs) return Promise.reject(new Error(window.ADspaceWords.line.pdfLib));
    var to = opts.to || {};
    var cjk = /[　-鿿＀-￯]/.test(String(q.brand || '') + String(opts.attention || '') + String(to.name || '') + String(to.address || ''));
    /* The sealed copy (SIGNED DOCUMENT SEAL, 2026-11-17): opts.seal holds
       the record (`quotation_record`) and the verify address. The signed
       pages are drawn and hashed first; the Record of this Document is then
       appended, printing that hash, and the whole file is hashed too. The
       blob carries both (`seal.sha`, `seal.pagesSha`). */
    var seal = opts.seal || null, S = window.ADspaceSeal, got, info, signedN;
    if (seal && !S) return Promise.reject(new Error(window.ADspaceWords.line.pdfLib));
    /* Settings' figures read before the draw (the ad spend line's). */
    var M = window.ADspaceMoney, figures = M && M.load ? M.load() : null;
    return Promise.resolve(figures).catch(function () {}).then(function () { return docs.lib(); }).then(function (PDF) {
      var pdf;
      return PDF.PDFDocument.create().then(function (doc) {
        pdf = doc;
        /* Its Document ID (VERIFY DETAILS, 2026-11-20), never a draft's. */
        return Promise.all([docs.embedFonts(pdf, PDF, { cjk: cjk }), docs.embedLogo(pdf), docs.codeOf ? docs.codeOf('quotation', opts.draft ? null : q.id, opts.key) : '']);
      }).then(function (g) {
        got = g;
        opts.code = g[2] || '';
        if (seal) {
          var co = seal.record.company || (opts.to && opts.to.name) || q.brand;
          /* A copy sealed from this release prints the Document ID the foot
             of every page prints; one sealed before printed its uuid, which
             /verify/ still takes for a sealed copy. */
          info = { ref: q.ref, docId: opts.code || seal.record.id, kind: 'quotation', verifyUrl: seal.verifyUrl, rows: S.rows(seal.record),
            sub: 'Quotation ' + q.ref + ', accepted by ' + co + ' and confirmed by ' + issuer() + '.' };
          opts.extraPages = S.pagesFor(PDF, got[0], info);
        }
        KEPT = opts.agency ? { a: opts.agency, t: opts.termsUrl || '' } : null;
        var form = layout(pdf, PDF, got[0], got[1], q, opts);
        signedN = pdf.getPageCount();
        return docs.formFields(pdf, PDF, form.page, form.boxes);
      }).then(function () {
        /* The reference in the file's title: a send by WhatsApp or email is
           checked against it (`_shared/pdfref.ts`). */
        docs.meta(pdf, agency() + ' Quotation ' + q.ref, 'Quotation');
        KEPT = null;
        if (!seal) return pdf.save();
        return pdf.save().then(S.sha256).then(function (pagesSha) {
          info.pagesSha = pagesSha; info.signedPages = signedN; info.total = signedN + opts.extraPages;
          S.addRecord(pdf, PDF, got[0], got[1], info);
          return pdf.save().then(S.finish).then(function (f) { return { bytes: f.bytes, sha: f.sha, pagesSha: pagesSha }; });
        });
      }).then(function (out) {
        if (!seal) return new Blob([out], { type: 'application/pdf' });
        var blob = new Blob([out.bytes], { type: 'application/pdf' });
        blob.seal = { sha: out.sha, pagesSha: out.pagesSha };
        return blob;
      });
    });
  }

  function layout(pdf, PDF, fonts, logo, q, opts) {
    var docs = D();
    var to = opts.to || {}, cover = opts.cover || COVER, prep = opts.preparedBy || {};
    /* Bill to (2026-11-12): the billing entity the quotation names, as it
       printed it, in place of the client's own. */
    var bt = (q.totals || {}).bill_to;
    if (bt && bt.legal_name) to = { name: bt.legal_name, address: bt.billing_address || '' };
    var person = String(opts.attention || '').trim();

    // Page 1: the Quotation Cover, the letter engine's own page.
    var first = docs.letterPages(pdf, PDF, fonts, logo, {
      family: 'quote_cover', pdfKind: 'quotation', serial: q.ref, issued_at: q.issued_at, languages: ['en'], signed: false, code: opts.code || '',
      recipient: { name: to.name || q.brand, address: to.address || '', attn: person, attn_role: opts.attentionRole || '' },
      title: cover.title || COVER.title,
      salutation: person ? 'Dear ' + person + ',' : (cover.salutation || COVER.salutation),
      closing: cover.closing || COVER.closing,
      body: { en: cover.body_en || COVER.body_en },
      signatory: { name: prep.name || '', designation: prep.designation || '' }
    });
    var pn = first.pn, pages = first.pages.slice();
    var W = pn.W, H = pn.H, M = pn.M, R = pn.R, FULL = R - M;
    var ink = pn.ink, mute = pn.mute, hair = pn.line;
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
    /* A continuation page: the template's head (AL, the wordmark), the
       body from the top margin. */
    var newPage = function () {
      pn.page = pdf.addPage([W, H]);
      pages.push(pn.page);
      pn.head();
      y = H - pn.TOP - 10;   // under the top margin: a heading's capitals stand inside it
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
    /* The revamp (the user, 2026-11-12: "title, body, groups,
       categorization, hierarchy"): three levels only. The page title, the
       numbered sections (each part of the fee, then the terms), and the
       table heads; the quotation's own facts as one block under the title
       in place of a sentence restating them. */
    var H1 = 16.18, H2 = 12, LBL = 8.5;   // a title: the body (10pt) times φ
    /* A section's mark (QUOTATION SECTION HEADS, 2026-11-25; the mockup
       PdfQuotationBlendV7): an outline glyph about 10pt square, stroked
       0.75pt in the body's ink and never filled, in a small shaded disc
       (18pt) centred on the heading's capitals; the heading a fixed gap
       after it. One set for every glyph the quotation draws: each payable
       section's and the Add-on Rates block's. Never numbered: a figure
       before Monthly Service Fee read as one month. */
    var GLYPH = {
      month: 'M4 6h16v14H4zM4 10h16M8 3v4M16 3v4',
      once: 'M3 3h8l10 10-8 8L3 11zM8 6.5a1.5 1.5 0 1 0 0 3a1.5 1.5 0 1 0 0-3z',
      ads: 'M3 10v4h4l6 4V6L7 10zM16 9a4 4 0 0 1 0 6',
      add: 'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18zM12 8v8M8 12h8'
    };
    var DISC = 18, GL = 10, GL_STROKE = 0.75, GL_BOX = 24, GAP = 8;
    /* The heading face's own cap height, read from the font (Slate's is
       about 0.7 of the size where the face does not say). */
    var capOf = function (f, size) {
      var k = f && f.embedder && f.embedder.font, u = k && k.unitsPerEm;
      return size * (u && k.capHeight ? k.capHeight / u : 0.7);
    };
    var mark = function (g, baseline, size) {
      var cx = M + DISC / 2, cy = baseline + capOf(reg, size) / 2, sc = GL / GL_BOX;
      pn.page.drawCircle({ x: cx, y: cy, size: DISC / 2, color: pn.shade });
      try {
        pn.page.drawSvgPath(GLYPH[g], { x: cx - GL / 2, y: cy + GL / 2, scale: sc,
          borderColor: pn.ink, borderWidth: GL_STROKE / sc, borderLineCap: PDF.LineCapStyle ? PDF.LineCapStyle.Round : undefined });
      } catch (e) { /* the disc alone */ }
      return M + DISC + GAP;
    };
    /* A section the client pays: its mark and name, and how it is billed
       in the mute ink at the label size on the heading's own baseline, at
       the right margin. */
    var h2 = function (s, g, billed) {
      room(80); y -= 18;
      text(s, mark(g, y, H2), y, H2, reg);
      if (billed) right(billed, R, y, LBL, book, mute);
      y -= 14;
    };
    if (t.layout === 2) {
      y -= 6; text('Quotation', M, y, H1, reg, pn.strong); y -= 22;
      /* The quotation's own title (2026-11-16), under the heading. */
      if (t.title) {
        wrap(String(t.title), FULL, 12, reg).forEach(function (ln) { text(ln, M, y, 12, reg); y -= 15; });
        y -= 7;
      }
      var facts = [['Quotation no.', q.ref], ['Date', D().refDate(q.issued_at)],
        ['Prepared for', buyer], ['Payment term', 'NET ' + (Number(t.pay_days) || 7)]];
      /* Its brands (2026-11-24): one made from a list names its one brand. */
      if (Array.isArray(t.brands) && t.brands.length) facts.push([t.brands.length > 1 ? 'Brands' : 'Brand', t.brands.map(function (b) { return String((b && b.name) || '').trim(); }).join(', ')]);
      if (t.month) facts.push(['Minimum term', t.term + (Number(t.term) === 1 ? ' month' : ' months')]);
      var colW = FULL / 3;
      for (var fi = 0; fi < facts.length; fi += 3) {
        var rowH = 0;
        facts.slice(fi, fi + 3).forEach(function (f, k) {
          var x0 = M + k * colW;
          text(f[0], x0, y, LBL, book, mute);
          var vl = wrap(f[1], colW - 12, 10, reg);
          vl.forEach(function (v, j) { text(v, x0, y - 14 - j * 12, 10, reg); });
          rowH = Math.max(rowH, 14 + (vl.length - 1) * 12);
        });
        y -= rowH + 18;
      }
      rule(y + 6); y -= 14;
      /* The fees' head: PROPOSED FEES (a quotation proposes; 2026-11-25),
         an uppercase mark with no letter spacing, alone on its row: every
         figure under it prints its own RM or S$. */
      text('PROPOSED FEES', M, y, 8.5, reg, pn.strong);
      y -= 4;
    } else {
    heading('Quotation');
    /* Its validity is said once, in TERMS (the user, 2026-11-12: the PDF
       said too much twice). */
    para('Quotation ' + q.ref + ', dated ' + longDay(dayOf(q.issued_at)) +
      ', sets out the services and fees proposed for ' + buyer + '.', 11, 14.5);
    y -= 16;
    }

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
    var taxed = window.ADspaceMoney.sstOf(q.lines, t.sst_pct);
    var sstOn = taxed.on, incl = sstOn ? ' incl. SST' : '';
    var own = (q.lines || []).some(function (l) { return l.basis === 'month' && l.months && Number(l.months) !== Number(t.term); });
    /* `tail`: the height of the totals under the list. The last line
       carries it, so the totals never stand on a page alone; where both do
       not fit, the line moves over with them (the user, 2026-11-24). */
    /* Several brands on one quotation (2026-11-24): each brand's lines under
       its name, the totals the whole quotation's. */
    var brandNames = Array.isArray(t.brands) && t.brands.length > 1 ? t.brands.map(function (b) { return String((b && b.name) || '').trim(); }) : null;
    var drawLines = function (list, quiet, tail) {
    var lastB = null;
    list.forEach(function (l, li) {
      if (brandNames && l.brand != null && l.brand !== lastB && brandNames[l.brand]) {
        lastB = l.brand;
        if (room(48)) headRow();
        y -= 16;
        text(brandNames[l.brand], M, y + 2, TB, reg, pn.strong);
        y -= 2;
      }
      var name = wrap(l.label, wD, TB, reg);
      /* Each inclusion a point of its own, as the service lists it, its
         words hung under its first (the user, 2026-11-04: one run of
         points read as one lump). */
      var IND = 9, sub = [];
      /* A line's period where it has a start (2026-11-12). */
      if (quiet && l.start) {
        var pr = l.basis === 'month' && Number(l.months) > 1
          ? longDay(l.start) + ' to ' + longDay(endOf(l.start, Number(l.months))) : 'From ' + longDay(l.start);
        wrap(pr, wD, SM, book).forEach(function (s0) { sub.push({ s: s0, dot: false }); });
      }
      (l.detail || []).forEach(function (d) {
        d = String(d == null ? '' : d).replace(/^\s*[-•·]\s*/, '').trim();
        if (!d) return;
        wrap(d, wD - IND, SM, book).forEach(function (s, k) { sub.push({ s: s, dot: !k }); });
      });
      var under = [];
      if (quiet) { if (l.basis === 'month' && l.months && Number(l.months) !== Number(t.term)) under.push(l.months + (Number(l.months) === 1 ? ' month' : ' months')); }
      else if (l.basis === 'once') under.push('one-time');
      else if (l.basis === 'month') under.push(l.months && Number(l.months) !== Number(t.term) ? l.months + (Number(l.months) === 1 ? ' month' : ' months') : 'per month');
      var tag = taxed.tag(l);
      if (tag) under.push(tag);
      var h = 7 + Math.max(name.length * 13 + sub.length * 11, 13 + under.length * 11);
      if (room(h + 4 + (li === list.length - 1 ? (tail || 0) : 0))) headRow();
      var top = y - 7;
      name.forEach(function (s, k) { text(s, M, top - 10 - k * 13, TB, reg); });
      sub.forEach(function (s, k) {
        var yy = top - 10 - name.length * 13 + 2 - k * 11;
        if (s.dot) text('•', M + 1, yy, SM, book, mute);
        text(s.s, M + IND, yy, SM, book, mute);
      });
      right(String(l.qty), xQ, top - 10, TB);
      right(amt(l.rate, q), xR, top - 10, TB);
      right(amt(l.amount, q), xA, top - 10, TB);
      under.forEach(function (s, k) { right(s, xA, top - 10 - 13 + 2 - k * 11, SM, book, mute); });
      y -= h;
    });
    };
    var MONY = window.ADspaceMoney, agreed = [], termsOnFees = false;
    /* A figure in bold, with its S$ beside it where billed in RM. */
    var nearOf = function (label, v, many) {
      var near = opts.client && t.currency !== 'SGD' && MONY && MONY.approx ? MONY.approx(v, opts.client, dayOf(q.issued_at), opts.fx) : '';
      var word = near.replace(/^ \(|\)$/g, '').replace(/^approx/, 'Approx');
      if (near) { y -= 13; right(many ? label + ', ' + word.charAt(0).toLowerCase() + word.slice(1) : word, R, y + 3, SM, book, mute); }
    };
    if (t.layout === 2) {
      /* Three sections, each closing on its own total (the user,
         2026-11-12): the monthly service fee, one-time items and the
         advertising budget, never added into one figure; the term's total
         a sentence in TERMS. */
      var TW2 = 255, tx2 = R - TW2;
      var sums = function (rows) {
        room(rows.length * 17 + 12);
        rows.forEach(function (r) {
          if (r[2]) { y -= 6; rule(y, tx2, R, true); y -= 5; }
          y -= 17;
          text(r[0], tx2, y + 5, TB, r[2] ? reg : book, r[2] ? ink : mute);
          right(r[1], R, y + 5, TB, r[2] ? reg : book);
        });
      };
      var section = function (title, g, billed) { h2(title, g, billed); y += 2; };
      var folded = MONY.planFold(q.lines, (q.totals || {}).currency);
      var monthly = folded.filter(function (l) { return l.basis !== 'once'; });
      var onceL = folded.filter(function (l) { return l.basis === 'once'; });
      var bolds = 0;
      var pt = MONY.periodTotals(t, q.selection), WD = window.ADspaceWords.line;
      if (t.month) bolds++;
      if (t.once) bolds++;
      var mWord = own ? 'First month' + incl : sstOn ? 'Monthly incl. SST' : 'Monthly total';
      if (t.month && monthly.length) {
        section('Monthly Service Fee', 'month', 'Billed monthly');
        var mTerms = Array.isArray(t.term_rows) ? t.term_rows.filter(function (x) { return Number(x.amount); }).length : (Number(t.term_pct) ? 1 : 0);
        headRow(); drawLines(monthly, true, 14 + (3 + mTerms) * 17 + 12 + 24);
        y -= 6; rule(y); y -= 8;
        var mr = [[sstOn ? 'Subtotal excl. SST' : 'Subtotal', amt(t.month.subtotal, q)]];
        /* A row a term percentage where the lines differ (2026-11-15). */
        var cap = function (x) { return x.replace(/^./, function (c) { return c.toUpperCase(); }); };
        if (Array.isArray(t.term_rows)) t.term_rows.forEach(function (x) { if (Number(x.amount)) mr.push([cap(MONY.termLine(x.months, x.pct)), amt(x.amount, q)]); });
        else if (Number(t.term_pct)) mr.push([cap(MONY.termLine(t.term, t.term_pct)), amt(t.month.term, q)]);
        mr.push([taxed.word, amt(t.month.sst, q)], [mWord, amt(t.month.incl, q), 1]);
        sums(mr);
        nearOf(mWord, Number(t.month.incl), bolds > 1);
        if (pt) { sums([[WD.periodTotal(pt.months, sstOn), amt(pt.period, q)]]); nearOf(WD.periodTotal(pt.months, sstOn), Number(pt.period), true); }
        agreed.push([mWord, amt(t.month.incl, q)], ['Minimum term', t.term + ' months']);
        /* What is signed names the whole period's figures too (2026-11-27). */
        if (pt) agreed.push([WD.periodTotal(pt.months, sstOn), amt(pt.period, q)]);
        y -= 20;
      }
      if (t.once && onceL.length) {
        section('One-time Items', 'once', 'Billed once');
        headRow(); drawLines(onceL, true, 14 + 3 * 17 + 12 + 24);
        y -= 6; rule(y); y -= 8;
        var oWord = sstOn ? 'One-time incl. SST' : 'One-time total';
        sums([[sstOn ? 'One-time excl. SST' : 'Subtotal', amt(t.once.subtotal, q)], [taxed.word, amt(t.once.sst, q)], [oWord, amt(t.once.incl, q), 1]]);
        nearOf(oWord, Number(t.once.incl), bolds > 1);
        agreed.push([oWord, amt(t.once.incl, q)]);
        y -= 20;
      }
      /* The whole period with the one-time fees, a block of its own under
         the One-time section, never read as its total (2026-11-27). */
      if (pt && pt.total != null && onceL.length) {
        y -= 8;
        sums([[WD.periodAll(sstOn), amt(pt.total, q), 1]]);
        nearOf(WD.periodAll(sstOn), Number(pt.total), true);
        y -= 13; right(WD.periodNote(pt.months), R, y + 3, SM, book, mute);
        agreed.push([WD.periodAll(sstOn), amt(pt.total, q)]);
        y -= 20;
      }
      var ads = Array.isArray(t.ads) ? t.ads : [];
      if (ads.length) {
        section('Advertising Budget', 'ads', t.ads.some(function (r) { return r.freq !== 'once'; }) ? 'Billed monthly' : 'Billed once');
        var xs = { f: M + 120, b: R - 196, m: R - 120 };
        var adHead = function () {
          y -= 9;
          text('Platform', M, y, 8.5, book, mute); text('Frequency', xs.f, y, 8.5, book, mute);
          right('Budget', xs.b, y, 8.5, book, mute); right('Months', xs.m, y, 8.5, book, mute); right('Amount', R, y, 8.5, book, mute);
          y -= 5; rule(y);
        };
        adHead();
        /* A brand's own budget under its name (QUOTATION ADVERTISING PER
           BRAND, 2026-11-26), as its lines are. */
        var adBrand = null;
        ads.forEach(function (r) {
          if (room(24)) adHead();
          if (brandNames && r.brand != null && r.brand !== adBrand && brandNames[r.brand]) {
            adBrand = r.brand;
            y -= 16;
            text(brandNames[r.brand], M, y + 2, TB, reg, pn.strong);
          }
          y -= 18;
          text(MONY.adWord(r.platform), M, y + 4, TB, reg);
          text(r.freq === 'once' ? 'One-time' : 'Monthly', xs.f, y + 4, TB);
          right(amt(r.budget, q), xs.b, y + 4, TB);
          right(r.freq === 'once' ? '—' : String(r.months), xs.m, y + 4, TB, book, r.freq === 'once' ? mute : ink);
          right(amt(r.amount, q), R, y + 4, TB);
        });
        y -= 6; rule(y); y -= 8;
        sums([['Advertising budget for the term', amt(t.ads_total, q), 1]]);
        agreed.push(['Advertising budget for the term', amt(t.ads_total, q)]);
        y -= 20;
      }

      /* Add-on Rates (QUOTATION ADD-ON RATES, 2026-11-25): the rates the
         team ticked in Build quote, as the quotation's Rate Card prices
         them (`totals.addons`, the database's), never added to any total.
         Anchored above the foot of the fees page as a sealed copy's Record
         is; where it does not fit there it takes the next page, and a list
         longer than a page runs on under the same head. */
      var addons = Array.isArray(t.addons) ? t.addons.filter(function (r) { return r && r.name; }) : [];
      /* Where the totals end, and where an Add-on Rates block anchored on
         the same page begins: the room TERMS may take (below). */
      var feesPage = pn.page, feesY = y, addTop = null;
      if (addons.length) {
        var WL = window.ADspaceWords.line, AS = 8.5, colGap = 24, colW = (FULL - colGap) / 2;
        var units = [], lastG = null;
        addons.forEach(function (r) {
          var g = r.kind === 'extra' ? WL.addonExtraHead : (r.group || WL.addons);
          if (g !== lastG) { lastG = g; units.push({ g: g, h: 16 }); }
          var p = MONY.addonParts(r, t.currency), unit = p.unit ? ' ' + p.unit.charAt(0).toLowerCase() + p.unit.slice(1) : '';
          var runs = [[p.from ? 'from ' : '', mute], [p.fig, ink], [unit, mute]];
          var rw = runs.reduce(function (n, x) { return n + width(x[0], AS); }, 0);
          var nl = wrap(r.name, Math.max(60, colW - rw - 16), AS, book);
          units.push({ r: runs, rw: rw, nl: nl, h: nl.length * 11 + 3 });
        });
        var leadL = wrap(WL.addonLead, FULL, AS, book);
        var headH = function (lead) { return 14 + 22 + (lead ? leadL.length * 11 + 4 : 0) + 8; };
        /* Columns of at most colH, a group's name never last in one. */
        var pack = function (colH) {
          var cols = [], cur = [], h = 0, g = null;
          units.forEach(function (u) {
            if (h + u.h > colH && cur.length) {
              /* A column never ends on a group's name, and one that starts
                 inside a group names it again. */
              var carry = cur[cur.length - 1].g ? [cur.pop()] : !u.g && g ? [{ g: g, h: 16 }] : [];
              cols.push(cur); cur = carry; h = carry.reduce(function (n, x) { return n + x.h; }, 0);
            }
            if (u.g) g = u.g;
            cur.push(u); h += u.h;
          });
          if (cur.length) cols.push(cur);
          return cols;
        };
        var colHOf = function (c) { return c.reduce(function (n, x) { return n + x.h; }, 0); };
        var total = units.reduce(function (n, x) { return n + x.h; }, 0);
        var balanced = function (limit) {
          for (var ch = Math.ceil(total / 2); ch <= limit; ch += 4) { var c = pack(ch); if (c.length <= 2) return c; }
          return null;
        };
        var drawHead = function (lead) {
          rule(y); y -= 14 + 11;
          text(WL.addonRates, mark('add', y, H2), y, H2, reg);
          y -= 11 + (lead ? 4 : 0);
          if (lead) leadL.forEach(function (ln) { y -= 11; text(ln, M, y + 2, AS, book, mute); });
          y -= 8;
        };
        var drawCols = function (cols) {
          var top = y, low = y;
          cols.forEach(function (c, ci) {
            var x0 = M + ci * (colW + colGap), x1 = x0 + colW, yy = top;
            c.forEach(function (u, k) {
              if (u.g) { yy -= (k ? 16 : 11); text(u.g, x0, yy + (k ? 5 : 0), AS, reg, pn.strong); if (!k) yy -= 5; return; }
              yy -= 11;
              u.nl.forEach(function (ln, j) { text(ln, x0, yy - j * 11 + 2, AS, book); });
              var ly = yy - (u.nl.length - 1) * 11 + 2, xr = x1 - u.rw;
              var x = xr; u.r.forEach(function (run) { text(run[0], x, ly, AS, book, run[1]); x += width(run[0], AS); });
              var from = x0 + width(u.nl[u.nl.length - 1], AS) + 4, lead2 = '';
              while (from + width(lead2 + ' .', AS) < xr - 4) lead2 += ' .';
              text(lead2, xr - 4 - width(lead2, AS), ly, AS, book, mute);
              yy -= (u.nl.length - 1) * 11 + 3;
            });
            low = Math.min(low, yy);
          });
          y = low;
        };
        var full = H - pn.TOP - 10 - FLOOR;
        var fit = balanced(y - FLOOR - 16 - headH(true));
        if (fit) {
          /* At the foot of the page, its last line on the floor. */
          y = FLOOR + headH(true) + Math.max(colHOf(fit[0]), fit[1] ? colHOf(fit[1]) : 0);
          addTop = y;
          drawHead(true); drawCols(fit);
        } else {
          newPage();
          fit = balanced(full - headH(true));
          if (fit) { drawHead(true); drawCols(fit); }
          else {
            var cols = pack(full - headH(true));
            for (var ci2 = 0; ci2 < cols.length; ci2 += 2) {
              if (ci2) newPage();
              drawHead(!ci2); drawCols(cols.slice(ci2, ci2 + 2));
            }
          }
        }
      }
      /* TERMS stand on the fees page under the totals where the whole
         block fits there, clear of an Add-on Rates block anchored above
         its foot; else they open the acceptance page, above what is signed
         (QUOTATION TERMS FIT, 2026-11-26). Never split across pages. */
      /* TERMS in the register of a contract (the user, 2026-11-12: "legal
         professional since this has the legal power when signed"): one
         obligation a clause, each said once. The payment term is the one
         the team chose in Build quote, stated as decided. */
      /* What the facts block under the title states (the payment term,
         the minimum term) is referred to here, never said again; the
         validity is the first term's alone (2026-11-12). */
      var groups = [];
      var grp = function (h, list) { list = list.filter(Boolean); if (list.length) groups.push({ h: h, list: list }); };
      var fee = t.month ? Math.round((Number(t.commitment || 0) - Number((t.once || {}).incl || 0)) * 100) / 100 : 0;
      var days2 = validDays(q);
      grp('Validity', ['This Quotation is valid for ' + both(days2) + ' days from its date of issue and shall lapse on ' +
        longDay(q.valid_until) + ' unless accepted before that date.']);
      grp('Fees and payment', [
        t.month ? 'The total Monthly Service Fee payable ' + (own ? 'over the period stated for each service' : 'over the minimum term') +
          ' is ' + amt(fee, q) + (sstOn ? ', inclusive of SST' : '') + '.' : ''
      ]);
      grp('Advertising budget', ads.length
        ? ['The Advertising Budget shall be paid to the advertising platforms on the Client\'s behalf before the ' +
          'services commence. It includes any SST and withholding tax applicable to the advertising platforms\' charges.']
        : (Number(t.budget) > 0 || (q.lines || []).some(function (l) { return l.kind === 'ads' || l.kind === 'plan'; }))
          ? ['The Advertising Budget is not included in this Quotation.', adWays(q, true)] : []);
      /* Files and further filming (2026-11-12, the user's own sentence). */
      grp('Exclusions', [addons.length ? window.ADspaceWords.line.addonTerm : 'Additional footage, working files and raw files are not included and shall be charged separately upon request.',
        (t.on_request || []).length ? (function () {
          var w = t.on_request.map(function (x) { return x === 'budget' ? 'An advertising budget above the highest tier of the ' + agency() + ' Rate Card' : x; });
          return w.join(', ') + ' shall be quoted separately upon request.';
        })() : '']);
      grp('Special terms', (Array.isArray(t.terms) ? t.terms : []).map(function (x) { return String(x).trim(); }));
      grp('Agreement', ['This Quotation shall become binding upon its acceptance and signature by the Client on the Acceptance of Quotation page. ' +
        (termsAt('This Quotation, together with the ') ? termsAt('This Quotation, together with the ') + ', shall constitute the contract between the parties.'
          : 'This Quotation shall constitute the contract between the parties.'),
        'All rates are based on the ' + agency() + ' Rate Card Version ' + q.version + '. E&OE.']);
      /* TERMS under the rates, one numbered list (the user, 2026-11-12:
         "dont categorize my terms make it under the rates as usual"). */
      var all = [];
      groups.forEach(function (g) { all = all.concat(g.list); });
      var termsL = all.map(function (n) { return wrap(n, FULL - 14, 8.5, book); });
      /* As drawn below: 8 over the label, 6 under it, 12 a line. */
      var termsH = 14 + termsL.reduce(function (n, ls) { return n + ls.length * 12; }, 0);
      var drawTerms = function () {
        y -= 8;
        text('TERMS', M, y, SM, book, mute);
        y -= 6;
        termsL.forEach(function (ls, i) {
          room(ls.length * 12 + 2);
          y -= 12;
          text((i + 1) + '.', M, y + 3, 8.5);
          ls.forEach(function (s2, k) { text(s2, M + 14, y + 3 - k * 12, 8.5); });
          y -= (ls.length - 1) * 12;
        });
      };
      /* The floor TERMS may reach on the fees page: the add-on block's
         rule with the gap a section keeps above it, or the page's floor.
         TERMS name the add-ons ("not included in the fees above"), so they
         never stand before an Add-on Rates block on a later page. */
      var termsFloor = addTop != null && pn.page === feesPage ? addTop + 20 : FLOOR;
      var addLater = addons.length && addTop == null;
      if (!addLater && feesY - termsH >= termsFloor) {
        var backPage = pn.page, backY = y;
        pn.page = feesPage; y = feesY;
        drawTerms();
        pn.page = backPage; y = backY;
        termsOnFees = true;
      }
    } else {
    headRow();
    var tot0 = window.ADspaceMoney.quoteRows(t, q.lines, sstOn);
    drawLines(window.ADspaceMoney.planFold(q.lines, (q.totals || {}).currency), false, 14 + tot0.length * 17 + 12 + tot0.filter(function (x) { return x[2]; }).length * 24);
    y -= 6;
    rule(y);
    y -= 8;

    /* The totals: ADspaceMoney.quoteRows, one copy (QT-4), named as the
       Letter of Offer names them: where a monthly line runs months of its
       own the month's figures are the first month's, the one-time items in
       it (the user, 2026-10-18). */
    var WORD = { monthSub: 'Monthly subtotal', onceSub: 'One-time subtotal', firstExcl: 'First month excl. SST', monthExcl: 'Monthly excl. SST',
      sst: taxed.word, first: 'First month' + incl, monthly: 'Monthly' + incl, oneOff: sstOn ? 'One-time incl. SST' : 'One-time total',
      term: window.ADspaceMoney.termLine(t.term, t.term_pct) };
    var tot = window.ADspaceMoney.quoteRows(t, q.lines, sstOn).map(function (x) { return [x[3] ? x[3].replace(/^./, function (c) { return c.toUpperCase(); }) : WORD[x[0]], amt(x[1], q), x[2]]; });
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
    /* Every bold total is agreed, the monthly fee and the one-time total
       alike (2026-11-07: a plan with an outstation fee signed on the one-time
       figure alone), each with its S$ beside it where billed in RM. */
    var bold = tot.filter(function (r) { return r[2]; });
    bold.forEach(function (b) {
      var v = Number(String(b[1]).replace(/[^0-9.\-]/g, ''));
      var near = opts.client && t.currency !== 'SGD' && MONY && MONY.approx ? MONY.approx(v, opts.client, dayOf(q.issued_at), opts.fx) : '';
      var word = near.replace(/^ \(|\)$/g, '').replace(/^approx/, 'Approx');
      if (near) { y -= 13; right(bold.length > 1 ? b[0] + ', ' + word.charAt(0).toLowerCase() + word.slice(1) : word, R, y + 3, SM, book, mute); }
    });
    y -= 22;

    // TERMS.
    var days = validDays(q);
    var notes = ['This quotation is valid for ' + both(days) + ' days from its date of issue, until ' + longDay(q.valid_until) + '.'];
    var holds = [];
    if (own && t.once) holds.push('the one-time items');
    if (sstOn) holds.push(/\d/.test(taxed.word) ? taxed.word.replace(/^SST /, 'SST at ') : 'SST');
    if (t.month && holds.length) notes.push((own ? 'The first month\'s amount' : 'The amount per month') + ' includes ' + holds.join(' and ') + '.');
    if (Number(t.budget) > 0 || (q.lines || []).some(function (l) { return l.kind === 'ads' || l.kind === 'plan'; })) {
      notes.push(window.ADspaceWords.line.adNotIncluded + ' ' + adWays(q, false));
    }
    if ((t.on_request || []).length) {
      notes.push('The following are quoted on request: ' + t.on_request.map(function (x) {
        return x === 'budget' ? 'an advertising budget above the highest tier of the ' + agency() + ' Rate Card' : x;
      }).join(', ') + '.');
    }
    if (t.month) {
      notes.push((own ? 'The total commitment over the months stated for each service' : 'The total commitment for ' + both(t.term) + ' months') +
        ' is ' + amt(t.commitment, q) + incl + (t.once ? ', one-time items included.' : '.'));
    }
    notes.push('This quotation becomes binding once accepted and signed on its acceptance page.' +
      (termsAt('') ? ' Together with the ' + termsAt('') + ', it forms the contract between the parties.' : ''));
    notes.push('Rates are based on the ' + agency() + ' Rate Card Version ' + q.version + '. E&OE.');
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
    agreed = bold.map(function (b) { return [b[0], b[1]]; });
    if (t.month) {
      agreed.push(['Minimum term', t.term + ' months']);
      agreed.push(['Total for the term' + incl, amt(t.commitment, q)]);
    }
    }

    // Page 3: Acceptance of quotation, always a page of its own.
    newPage();
    var v2 = t.layout === 2;
    if (v2) {
      if (!termsOnFees) {
        drawTerms();
        /* What is signed keeps to one page: where TERMS leave too little
           room under them, the acceptance takes the next. */
        if (y - (200 + agreed.length * 16 + 200) < FLOOR) newPage(); else y -= 30;
      }
      y -= 6; text('Acceptance of Quotation', M, y, H1, reg, pn.strong); y -= 8;
    } else heading('Acceptance of Quotation');
    para('By signing below, the Client accepts Quotation ' + q.ref + ', dated ' + longDay(dayOf(q.issued_at)) + ', and agrees ' +
      'to be bound by the terms set out in this document.', v2 ? 10.5 : 11, 14.5);
    y -= v2 ? 22 : 12;
    if (v2) { text('Agreed figures', M, y, LBL, book, mute); y -= 6; }
    rule(y);
    y -= 4;
    agreed.forEach(function (r) { y -= 16; text(r[0], M, y + 4, TB); right(r[1], R, y + 4, TB); });
    y -= 8;
    rule(y);
    y -= v2 ? 30 : 24;

    var block = function (title) { text(title, M, y, v2 ? H2 : 11, reg); y -= v2 ? 14 : 12; };
    // Issued for and on behalf of the issuer: Prepared by, Reviewed by.
    block('Issued for and on behalf of ' + issuer());
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
    /* Unsigned, the block is a form a reader fills (2026-11-12): the
       signature box and each value, as a letter's execution block. */
    var boxes = [];
    if (!signer && !opts.draft) {
      boxes.push(['acceptance_authorised_signatory', M, y - sh + 18, cw, sh - 18, 'sig']);
      ['acceptance_name', 'acceptance_designation', 'acceptance_date'].forEach(function (k, i) {
        boxes.push([k, M + cw + lw, y - (i + 1) * rh, FULL - cw - lw, rh, false]);
      });
    }
    var formPage = pn.page;
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
        lines2.push('Signed on paper on ' + longDay(signer.day) + '; the signed copy is kept by ' + agency() + '.');
      }
      y -= 6;
      lines2.forEach(function (s) { wrap(s, FULL, SM, book).forEach(function (ln) { y -= 11; text(ln, M, y, SM, book, mute); }); });
    }

    // The foot on every page; a preview is a draft over every page.
    docs.letterFoot(pn, pages, q.ref, '', opts.extraPages ? pages.length + opts.extraPages : 0);
    if (opts.draft) pages.forEach(function (pg) { docs.watermark(pg, 'DRAFT (INTERNAL USE ONLY)', fonts.font); });
    return { page: formPage, boxes: boxes };
  }

  window.ADspaceQuotePdf = { draw: draw, fileName: fileName, COVER: COVER };
})();
