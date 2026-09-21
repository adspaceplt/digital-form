/*
 * Documents — the Letter of Offer as a PDF.
 *
 * Sales issues a Letter of Offer to the client from the record: the quoted
 * service lines with their fees, the total with SST, and a block for the
 * client to sign. Once the client signs, the formal quotation and invoice
 * follow outside the portal. Drawn in the
 * browser and kept as a snapshot in client_documents, so it can be
 * downloaded again exactly as issued whatever the record does afterwards.
 *
 * Numbers: AQT/INT/YYMMXXX, sequence per month.
 *
 * The layout is the ADspace letterhead: wordmark, registration and address
 * left, the monogram and the office contact right, PRIVATE & CONFIDENTIAL,
 * Our Ref / Date / To / Attn, the subject, the salutation, the body with the
 * lines and totals, Yours sincerely, the acceptance block, the monogram
 * bottom centre and the page count. Fonts and images come from
 * ADSPACE_ORG; blanks fall back to Helvetica and the wordmark.
 */
(function () {
  var API = window.ADspaceAPI;
  var db  = API && API.client;
  if (!API || !API.configured || !db) return;

  var MON = window.ADspaceMoney;
  var ORG = window.ADSPACE_ORG || {};
  var CFG = window.ADSPACE_CONFIG || {};
  var bridge = window.ADspaceAdmin || {};
  var log = bridge.log || function () {};
  var actor = bridge.actorName || bridge.actor || function () { return ''; };

  var KIND = {
    offer: { prefix: 'AQT/INT/', title: 'Letter of Offer', word: 'Reference', per: 'month', validDays: 30 }
  };
  KIND.intent = KIND.cover = KIND.offer;   // rows issued before the rename

  function pad(n) { return String(n).padStart(2, '0'); }
  function yymm(d) { return String(d.getFullYear()).slice(2) + pad(d.getMonth() + 1); }
  function yymmdd(d) { return yymm(d) + pad(d.getDate()); }
  function dayOf(s) { s = String(s || ''); return s.length === 7 ? s + '-01' : s; }
  function dateOf(s) { var d = new Date(dayOf(s).slice(0, 10) + 'T00:00:00'); return isNaN(d.getTime()) ? null : d; }
  function plusDays(s, n) { var d = dateOf(s); if (!d) return ''; d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); }
  function longDate(s) {
    var d = dateOf(s);
    return d ? d.toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' }) : String(s || '');
  }
  /* The rate a line is billed at: the rate that was typed, carrying its term
     adjustment where the line was ticked to take one. One definition, in
     money.js, so the console, the letter and the client's page cannot
     disagree — and a line stored before the tick existed carries no flag at
     all, which money.js reads as on, so a letter issued then redraws at the
     figure it printed. */
  function rateOf(l) { return MON.rateFor(l.rate, l.tenure, l.term_adjust); }
  function amountOf(l) { return Number(l.qty || 0) * rateOf(l) * Math.max(1, Number(l.tenure || 1)); }

  /* One price, worked the same way when the letter is issued and when it is
     drawn again later, so the stored total and the printed one never drift.

     A letter whose lines all run the same term is priced per month, because
     that is how it is invoiced and how the client thinks about it. `each` is
     then one month's invoice and the commitment is that month times the term.
     Mixed or one off lines have no monthly figure, so `each` is the amount. */
  function priceOf(lines, market, taxOn) {
    var ns = lines.map(function (l) { return Math.max(1, Number(l.tenure || 1)); });
    var term = (ns.length && ns[0] > 1 && ns.every(function (x) { return x === ns[0]; })) ? ns[0] : 0;
    var each = lines.reduce(function (s, l) {
      return s + Number(l.qty || 0) * rateOf(l) * (term ? 1 : Math.max(1, Number(l.tenure || 1)));
    }, 0);
    var eachTax = MON.taxOf(each, market, taxOn);
    var eachTotal = Math.round((each + eachTax) * 100) / 100;
    var n = term || 1;
    return {
      term: term, each: each, eachTax: eachTax, eachTotal: eachTotal,
      subtotal: Math.round(each * n * 100) / 100,
      tax: Math.round(eachTax * n * 100) / 100,
      total: Math.round(eachTotal * n * 100) / 100
    };
  }
  // What one line puts on the invoice the Amount column is totalling.
  function lineAmount(l, term) {
    return Number(l.qty || 0) * rateOf(l) * (term ? 1 : Math.max(1, Number(l.tenure || 1)));
  }
  /* "12 October 2026 to 11 April 2027" for a termed line, "12 October 2026"
     for a dated one, "6 months" for a term without a start. */
  function periodOf(l) {
    var n = Math.max(1, Number(l.tenure || 1));
    if (!l.start_on) return n > 1 ? n + ' months' : '';
    if (n === 1) return longDate(l.start_on);
    var d = dateOf(l.start_on);
    if (!d) return n + ' months';
    d.setMonth(d.getMonth() + n);
    d.setDate(d.getDate() - 1);
    return longDate(l.start_on) + ' to ' + longDate(d.toISOString().slice(0, 10));
  }

  /* ---- Issuing -----------------------------------------------------------
     The serial and the letter are the database's to make, not the browser's.
     `nextNumber` used to read MAX(number) here and insert, which two people
     pressing Issue letter in the same second could both win; and the line set
     was picked by one predicate, `state = 'quoted'`, so a line already sent to
     a client on an earlier letter was silently carried into the next one.
     `issue_letter` reserves the serial atomically, builds the snapshot from
     the stored rows, records which services the letter captured, and answers
     the same letter twice when the same submission arrives twice. */

  /* One key per submission, so a double click, a retry after a dropped
     connection and an impatient second press are all one letter. */
  function idemKey() {
    var r = '';
    for (var i = 0; i < 4; i++) r += Math.random().toString(36).slice(2, 10);
    return r.slice(0, 32);
  }

  /* What the letter would be worth. Computed here because js/money.js is the
     one definition of a term factor and its rounding, and duplicating that in
     SQL is how the console and the letter would come to disagree. The lines
     themselves are read back from the database inside the transaction, so a
     figure sent from here can never change the words on the page. */
  function quoteOf(client, lines) {
    return priceOf(lines, client.market, client.sst_applies !== false);
  }

  /* client: the record. picked: the service rows the person chose. deal: the
     display facts the record knows that the client row does not spell out.
     opts: { idem, replaces, renewal, serial }. A blank serial is the everyday
     case and the database numbers the letter; one typed here is checked
     against every document that stands and spends no sequence number. */
  function issue(kind, client, picked, deal, opts, then) {
    opts = opts || {};
    var use = (picked || []).filter(function (l) { return l && !l.archived_at; });
    if (!use.length) { then({ error: 'Choose at least one service.' }); return; }
    var serial = String(opts.serial || '').trim();
    /* The Client ID builds an automatic reference and nothing else, so it is
       needed only where none has been typed. */
    if (!serial && !String(client.client_code || '').trim()) {
      then({ error: 'Add a Client ID to this client before issuing a letter.' });
      return;
    }
    var price = quoteOf(client, use);
    deal = deal || {};
    db.rpc('issue_letter', {
      p_client: client.id,
      p_services: use.map(function (l) { return l.id; }),
      p_idem: opts.idem || idemKey(),
      p_subtotal: price.subtotal, p_tax: price.tax, p_total: price.total,
      p_deal: { owner: deal.owner || '', source: deal.source || '', industry: deal.industry || '',
                stage: deal.stage || '', enquiry: deal.enquiry || '' },
      p_replaces: opts.replaces || null,
      p_renewal: Boolean(opts.renewal),
      p_serial: serial || null
    }).then(function (r) {
      /* The migration has to be in place before the site is. Until it is, the
         function is missing and nothing is written at all — a half issued
         letter cannot exist either way. */
      if (r.error) { then({ error: missingWord(r.error.message) }); return; }
      var out = r.data || {};
      if (out.error) { then({ error: ISSUE_WORD[out.error] || out.error }); return; }
      readBack(out.id, function (doc, err) {
        if (err || !doc) { then({ ok: true, repeat: out.repeat, number: out.number, warn: 'Issued. The file could not be drawn.' }); return; }
        download(doc, function (warn) {
          then({ ok: true, repeat: out.repeat, doc: doc, number: out.number, warn: warn });
        });
      });
    }, function (e) { then({ error: missingWord(e && e.message) }); });
  }

  function readBack(id, then) {
    db.from('client_documents').select('*').eq('id', id).single()
      .then(function (r) { then(r.data, r.error); }, function (e) { then(null, e); });
  }

  /* The database answers in one word; the console says what it means. */
  var ISSUE_WORD = {
    'not-allowed': 'You do not have permission to issue a letter.',
    'no-client-code': 'Add a Client ID to this client before issuing a letter.',
    'no-client': 'That client could not be found.',
    'no-lines': 'Choose at least one service.',
    'bad-lines': 'One of those services cannot go on a letter. Refresh and try again.',
    'already-quoted': 'One of those services is already on a letter that is still live. Void that letter, or use Replace.',
    'no-replaces': 'The letter being replaced could not be found.',
    'replaces-verified': 'A verified letter cannot be replaced.',
    'not-found': 'That letter could not be found.',
    'voided': 'That letter is void.',
    'verified': 'That letter has already been verified.',
    'superseded': 'That letter has been replaced.',
    'not-signed': 'Mark the letter signed before verifying it.',
    'no-mapping': 'This letter was issued before the change and cannot be verified. Confirm its services by hand.',
    'clash': 'Two letters were issued at once. Try again.',
    'serial-taken': 'That reference belongs to a document that still stands.',
    'serial-shape': 'A reference is 3 to 40 characters: letters, numbers and / . _ -',
    'no-serial': 'No free reference was found for this client this month. Type one.',
    'reason-required': 'Say why.',
    'not-verified': 'Only a verified letter is voided. An issued or signed letter is deleted instead.',
    'confirm-mismatch': 'That is not this letter\'s reference.',
    'issuer-name': 'A letter is signed by a person. Set your name on the Team page, then issue it.',
    'bad-state': 'That is not a state a service can be in.'
  };

  function missingWord(m) {
    m = String(m || '');
    if (/could not find|does not exist|schema cache|function public\.(issue_letter|letter_delete|letter_set_void)/i.test(m)) {
      return 'The database has not been updated yet. Run the letter lifecycle migration, then try again.';
    }
    return m || 'The letter could not be issued.';
  }

  /* One shape for the three deliberate moves a letter makes. Each is a
     server-side transaction; none of them touches a service except verify,
     which touches only the ones this letter captured. */
  function call(fn, args, then) {
    db.rpc(fn, args).then(function (r) {
      if (r.error) { then(missingWord(r.error.message)); return; }
      var out = r.data || {};
      if (out.error) { then(ISSUE_WORD[out.error] || out.error); return; }
      then(null, out);
    }, function (e) { then(missingWord(e && e.message)); });
  }

  function setSigned(doc, on, then) { call('letter_set_signed', { p_doc: doc.id, p_on: Boolean(on) }, then); }
  function verify(doc, then)        { call('verify_letter',     { p_doc: doc.id }, then); }
  /* A void is a reversal somebody has to account for, so it carries a reason
     and is not a switch. There is no un-void: the reversal put service lines
     back and reissuing is the way forward, not toggling the same row. */
  function setVoidRpc(doc, reason, then) { call('letter_set_void', { p_doc: doc.id, p_reason: reason }, then); }
  /* Permanent. The serial is typed back because it is the one thing that says
     which letter is about to stop existing. */
  function removeRpc(doc, confirmNo, reason, then) {
    call('letter_delete', { p_doc: doc.id, p_confirm: confirmNo, p_reason: reason }, then);
  }

  /* Which services a letter captured. A letter issued before the change has
     none, which is what makes it history rather than something to verify. */
  function mapOf(ids, then) {
    if (!ids || !ids.length) { then({}); return; }
    db.from('client_document_services').select('document_id, service_id').in('document_id', ids)
      .then(function (r) {
        var by = {};
        (r.data || []).forEach(function (m) {
          (by[m.document_id] = by[m.document_id] || []).push(m.service_id);
        });
        then(by);
      }, function () { then({}); });
  }

  /* A letter is live while it can still become something: not void, not
     replaced, not yet verified. A service on one of those is spoken for. */
  function liveDoc(d) {
    return d && !d.voided_at && !d.superseded_by && !d.verified_at;
  }

  /* Issued -> Signed, awaiting verification -> Verified, with Void and
     Replaced off to the side. Derived from the timestamps, never stored as a
     word, so no two screens can disagree about where a letter stands. */
  function letterState(d) {
    if (!d) return 'issued';
    if (d.voided_at) return 'void';
    if (d.superseded_by) return 'superseded';
    if (d.verified_at) return 'verified';
    if (d.signed_at) return 'signed';
    return 'issued';
  }

  function fileName(doc) { return String(doc.number).replace(/\//g, '-') + '.pdf'; }

  /* A letter that has been issued always reports itself, even when the file
     cannot be drawn: the row exists in the database and the serial is spent,
     so somebody has to be told. `render` reads `PDFLib.PDFDocument` at its
     first line, which throws where the library never loaded — before any
     promise exists, so the rejection handler beside it could not see it and
     the caller was left with an open sheet and no message at all. A `.catch`
     after the chain, and a try around the call, because a handler that can
     throw is one whose sibling handler never runs. */
  function download(doc, then) {
    var said = false;
    var say = function (w) { if (said) return; said = true; if (then) then(w); };
    try {
      render(doc).then(function (bytes) {
        var blob = new Blob([bytes], { type: 'application/pdf' });
        var a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = fileName(doc);
        document.body.appendChild(a);
        a.click();
        setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 2000);
        say(logoWarn);
      }).catch(function (e) {
        say('The file could not be drawn: ' + ((e && e.message) || e) + ' Download it from the row.');
      });
    } catch (e) {
      say('The file could not be drawn: ' + ((e && e.message) || e) + ' Download it from the row.');
    }
  }

  // ---- Brand assets ----------------------------------------------------------
  var assetCache = {};
  function fetchBytes(url) {
    if (!url) return Promise.reject(new Error('none'));
    if (assetCache[url]) return assetCache[url];
    assetCache[url] = fetch(url, { mode: 'cors' }).then(function (r) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.arrayBuffer();
    });
    return assetCache[url];
  }
  /* The four faces the letterhead uses: body (Slate Book), the heavier lines
     (Slate Regular), the headings (Slate Medium, falling back to the heavier
     face where the file is not there) and the wordmark (Optima). `extra` may
     name a fifth, the Chinese face a letter with a Chinese block embeds; it is
     fetched only then, and its absence is reported as `cjk: null` so the
     caller can refuse by name rather than draw boxes. */
  // An OpenType file with CFF outlines opens with the tag OTTO.
  function isCff(bytes) {
    var u = new Uint8Array(bytes);
    return u.length > 4 && u[0] === 0x4f && u[1] === 0x54 && u[2] === 0x54 && u[3] === 0x4f;
  }
  function embedFonts(pdf, PDF, extra) {
    var std = function () {
      return Promise.all([pdf.embedFont(PDF.StandardFonts.Helvetica), pdf.embedFont(PDF.StandardFonts.HelveticaBold)])
        .then(function (f) { return { font: f[0], bold: f[1], med: f[1], mark: f[1], custom: false, cjk: null }; });
    };
    if (!ORG.font || !window.fontkit) return std();
    pdf.registerFontkit(window.fontkit);
    var opt = function (url) { return url ? fetchBytes(url).catch(function () { return null; }) : Promise.resolve(null); };
    var cjkUrl = extra && extra.cjk ? ORG.fontCjk : '';
    return Promise.all([fetchBytes(ORG.font), opt(ORG.fontBold), opt(ORG.fontMark), opt(ORG.fontMed), opt(cjkUrl)])
      .then(function (b) {
        var emb = function (bytes) { return bytes ? pdf.embedFont(bytes, { subset: true }) : null; };
        /* The Chinese face is embedded whole when it is CFF based. pdf-lib
           subsets a CID-keyed CFF font (Noto Sans CJK is one) with the
           glyph order wrong, so every character came out as the font's first
           glyphs in sequence: `! " # $ % &` where the Chinese should be. The
           file is larger for it; a TrueType face subsets correctly and still
           does. */
        var embCjk = function (bytes) {
          if (!bytes) return null;
          return pdf.embedFont(bytes, { subset: !isCff(bytes) });
        };
        return Promise.all([emb(b[0]), emb(b[1]), emb(b[2]), emb(b[3]), embCjk(b[4])])
          .then(function (f) {
            return { font: f[0], bold: f[1] || f[0], mark: f[2] || f[1] || f[0],
                     med: f[3] || f[1] || f[0], cjk: f[4] || null, custom: true };
          });
      })
      .catch(std);
  }

  /* ---- The pen: what every letter draws with ---------------------------
     One copy of the primitives and one copy of the letterhead, so the Letter
     of Offer and the letters in js/letters.js cannot come out on two
     different sheets of paper. `ctx.page` is the page being drawn; the caller
     owns the cursor. */
  var W = 595.28, H = 841.89, M = 54, R = W - M;
  function pen(PDF, fonts, logo) {
    var font = fonts.font;
    var ink = PDF.rgb(0.075, 0.094, 0.102), mute = PDF.rgb(0.39, 0.43, 0.44), line = PDF.rgb(0.87, 0.89, 0.89);
    var p = { page: null, W: W, H: H, M: M, R: R, ink: ink, mute: mute, line: line, fonts: fonts, logo: logo };
    p.safe = function (s) {
      s = String(s == null ? '' : s);
      return fonts.custom ? s : s.replace(/[^\x20-\x7E -ÿ]/g, '-');
    };
    p.text = function (s, x, yy, size, f, color) {
      p.page.drawText(p.safe(s), { x: x, y: yy, size: size || 10, font: f || font, color: color || ink });
    };
    p.width = function (s, size, f) { return (f || font).widthOfTextAtSize(p.safe(s), size || 10); };
    p.right = function (s, xr, yy, size, f, color) { p.text(s, xr - p.width(s, size, f), yy, size, f, color); };
    p.centre = function (s, yy, size, f, color) { p.text(s, (W - p.width(s, size, f)) / 2, yy, size, f, color); };
    p.rule = function (yy, x1, x2, heavy) {
      p.page.drawLine({ start: { x: x1 || M, y: yy }, end: { x: x2 || R, y: yy }, thickness: heavy ? 1 : 0.6, color: heavy ? ink : line });
    };
    p.wrap = function (s, max, size, f) {
      var out = [], cur = '';
      p.safe(s).split(/\s+/).forEach(function (w) {
        var t = cur ? cur + ' ' + w : w;
        if (p.width(t, size, f) > max && cur) { out.push(cur); cur = w; } else cur = t;
      });
      if (cur) out.push(cur);
      return out;
    };
    /* Chinese has no spaces to break on, so a run is cut where the next
       glyph would cross the column. */
    p.wrapCjk = function (s, max, size, f) {
      var out = [], cur = '';
      String(s || '').split('').forEach(function (ch) {
        if (f.widthOfTextAtSize(cur + ch, size) > max && cur) { out.push(cur); cur = ch; } else cur += ch;
      });
      if (cur) out.push(cur);
      return out;
    };
    // The letterhead, in the reference's positions; returns the y under it.
    p.head = function () {
      var T = function (top) { return H - top; };
      p.text('ADspace', M, T(58), 14, fonts.mark || fonts.bold);
      if (ORG.regno) p.text('Co. Reg.  ' + ORG.regno, M, T(70), 9, font, mute);
      var ly = T(83);
      String(ORG.address || '').split(/\r?\n/).filter(Boolean).forEach(function (s) { p.text(s, M, ly, 11); ly -= 12.5; });
      if (logo) { var mh = 21, mw = logo.width * (mh / logo.height); p.page.drawImage(logo, { x: R - mw, y: T(65), width: mw, height: mh }); }
      var ry = T(92);
      [phoneWord(ORG.phone), ORG.email, ORG.website].filter(Boolean).forEach(function (s) { p.right(s, R, ry, 11); ry -= 12.5; });
      return Math.min(ly, ry) - 10;
    };
    // The monogram bottom centre and the page count bottom right.
    p.footMark = function (i, n) {
      if (logo) { var fh = 20, fw = logo.width * (fh / logo.height); p.page.drawImage(logo, { x: (W - fw) / 2, y: 30, width: fw, height: fh }); }
      p.right('Page ' + (i + 1) + ' of ' + n, R, 30, 7.5, font, mute);
    };
    return p;
  }
  /* The mark is ADSPACE_ORG.logo, else the header's own mark. A failure to
     load it (most often no CORS on the file) is reported, not hidden. */
  var logoWarn = '';
  function embedImage(pdf, url, onFail) {
    if (!url) return Promise.resolve(null);
    return fetchBytes(url).then(function (bytes) {
      return /\.jpe?g(\?|$)/i.test(url) ? pdf.embedJpg(bytes) : pdf.embedPng(bytes);
    }).catch(function () { delete assetCache[url]; if (onFail) onFail(); return null; });
  }
  function embedLogo(pdf) {
    logoWarn = '';
    return embedImage(pdf, ORG.logo || CFG.brandLogo, function () { logoWarn = 'Logo not loaded.'; });
  }
  /* (60)18 762 5233 from 60187625233; anything else is printed as typed. */
  function phoneWord(p) {
    var d = String(p || '').replace(/[^0-9]/g, '');
    if (d.length === 11 && d.indexOf('60') === 0) return '(60)' + d.slice(2, 4) + ' ' + d.slice(4, 7) + ' ' + d.slice(7);
    return String(p || '');
  }
  function ordinal(n) { var s = ['th', 'st', 'nd', 'rd'], v = n % 100; return n + (s[(v - 20) % 10] || s[v] || s[0]); }
  function letterDate(s) {
    var d = dateOf(s);
    return d ? ordinal(d.getDate()) + ' ' + d.toLocaleDateString('en-GB', { month: 'long', year: 'numeric' }) : String(s || '');
  }

  // ---- Drawing ---------------------------------------------------------------
  function render(doc) {
    var PDF = window.PDFLib;
    if (!PDF) return Promise.reject(new Error('PDF library not loaded'));
    var k = KIND[doc.kind] || KIND.offer;
    var pdf, fonts, logo;
    return PDF.PDFDocument.create().then(function (p) {
      pdf = p;
      return Promise.all([embedFonts(pdf, PDF), embedLogo(pdf)]);
    }).then(function (got) {
      fonts = got[0]; logo = got[1];
      var font = fonts.font, bold = fonts.bold;
      /* The pen holds the primitives and the letterhead; this letter keeps
         its own cursor and tells the pen which page it is on. */
      var pn = pen(PDF, fonts, logo);
      var ink = pn.ink, mute = pn.mute;
      var text = pn.text, width = pn.width, right = pn.right, rule = pn.rule, wrap = pn.wrap;
      var pages = [];
      var page, y;
      var newPage = function () { page = pdf.addPage([W, H]); pn.page = page; pages.push(page); y = H - 57; };
      var need = function (h) { if (y - h < 64) newPage(); };
      newPage();

      // The letterhead, on every page; the monogram again bottom centre, the
      // page count bottom right. y counts down from the top of the page.
      var head = function () { y = pn.head(); };
      /* Every page names the letter it belongs to, and every page but the one
         that is signed carries a line for the client's initials.

         A letter whose substance is on page one and whose signature is on
         page two can be executed and then have page one swapped: the signed
         sheet proves only that somebody signed something. Initials on each
         page is the ordinary commercial answer, and the reference in the foot
         means a page lifted out of this letter still says which letter it is. */
      var foot = function (i, n) {
        pn.footMark(i, n);
        text(doc.number, M, 30, 7.5, font, mute);
        /* The initials go where a hand rests to write them, which is the same
           side of the page the signature is on. They sit a row above the page
           number rather than beside it: the two are the only marks in the
           right of the foot and a collision there is a page nobody can sign. */
        if (i < n - 1) {
          rule(56, R - 96, R);
          right('Client initials', R, 45, 7.5, font, mute);
        }
      };
      var LH = 14.5, PARA = 14, BODY = 11;
      var para = function (s, f, size) {
        wrap(s, R - M, size || BODY, f).forEach(function (ln) { need(LH); text(ln, M, y, size || BODY, f); y -= LH; });
        y -= PARA;
      };
      head();

      var b = doc.bill_to || {};
      /* One name for the whole letter. `To`, the opening paragraph and the
         acceptance block each resolved this themselves and two of them used
         the opposite precedence, so a client whose registered name and
         trading name differ was addressed as one in the header and the other
         in the sentence beneath it. The letter is an agreement, so the name
         on it is the legal entity, once, everywhere. */
      var legalName = String(b.legal_name || b.name || '').trim();
      /* Worked from the snapshot, by the same function that stored it, so a
         letter drawn again a year later prints the figures it was issued
         with. Older rows carry no per line tax flag; the stored tax says. */
      var lineTax = (doc.lines && doc.lines.length && 'tax' in doc.lines[0])
        ? Boolean(doc.lines[0].tax) : Number(doc.tax) > 0;
      var price = priceOf(doc.lines || [], doc.market, lineTax);
      text('PRIVATE & CONFIDENTIAL', M, y, BODY, bold); y -= 24;

      // Our Ref / Date / To / Attn, the colons in one column.
      var refs = [
        ['Our Ref', doc.number], ['Date', letterDate(doc.issued_at)],
        ['To', legalName.toUpperCase()],
        ['Attn', b.contact ? b.contact + (b.contact_role ? ', ' + b.contact_role : '') : '']
      ].filter(function (f) { return f[1]; });
      /* The value wraps to the column it started in. A registered name or an
         Attn line carrying a full job title is longer than the page is wide,
         and an unwrapped one ran off the right edge and was simply gone:
         "Corporate Communications and B". The label and its colon stay on the
         first line, because they belong to the whole value and not to its
         first line. */
      var REFX = M + 78;
      refs.forEach(function (f) {
        text(f[0], M, y, BODY);
        text(':', M + 72, y, BODY);
        wrap(f[1], R - REFX, BODY).forEach(function (ln, i) {
          text(ln, REFX, y, BODY);
          if (i < 99) y -= LH;
        });
      });
      y -= 12;

      text(String(k.title).toUpperCase(), M, y, BODY, bold); y -= 29;
      text('Dear ' + (b.contact || 'Sir/Madam') + ',', M, y, BODY); y -= 29;

      // The offer: the services and fees, the total, the terms, the acceptance.
      para('Thank you for your interest in our marketing services. Further to our discussion, we are pleased to set out below the services and fees proposed for ' +
        (legalName || 'your company') + '.');

      /* A service is quoted by the month, not sold by the piece, so the
         columns are Description, Rate and Amount. Quantity rides inside the
         rate cell on the lines where it is not one, which frees the width a
         package needs to say what it includes. The term sits under the amount
         it explains, so a figure larger than the rate is never a surprise.

         Weight carries the reading order: the name heaviest, the amounts
         next, everything qualifying them mute and smaller. The lines under a
         name sit tighter to it than the gap to the next service, so each
         service reads as one block. */
      var cols = { desc: M, rate: R - 130, amt: R };
      var descW = cols.rate - cols.desc - 74;
      var LROW = 13, LSUB = 11, LGAP = 10;
      var thead = function () {
        text('Description', cols.desc, y, 9, bold, mute);
        right('Rate', cols.rate, y, 9, bold, mute);
        right('Amount', cols.amt, y, 9, bold, mute);
        y -= 7; rule(y); y -= 15;
      };
      need(60); thead();
      (doc.lines || []).forEach(function (l) {
        var q = Number(l.qty || 0), n = Math.max(1, Number(l.tenure || 1));
        var names = wrap(l.label, descW, 10, bold);
        /* What it includes sits with the name. How it is priced and when it
           runs are a different kind of fact, so they sit a step below on one
           line of their own: the eye reads the offer, then the terms of it. */
        var incl = [];
        String(l.detail || '').split(/\r?\n/).forEach(function (d) {
          if (d.replace(/\s/g, '')) incl = incl.concat(wrap(d, descW, 8.5));
        });
        var metaWord = [l.unit, MON.termNote(l.tenure, l.term_adjust), periodOf(l), l.note].filter(Boolean).join('  ·  ');
        var meta = metaWord ? wrap(metaWord, descW, 8.5) : [];
        var split = incl.length && meta.length ? 4 : 0;
        if (y - (names.length * LROW + (incl.length + meta.length) * LSUB + split + LGAP) < 70) { newPage(); head(); thead(); }
        text(names[0] || '', cols.desc, y, 10, bold);
        // The rate the client is billed, term adjustment included, because that
        // is the figure they are accepting. Why it differs from the rate card
        // is named on the mute line below, never left to be discovered.
        right(q === 1 ? MON.money2(rateOf(l), doc.market)
                      : (q % 1 ? q.toFixed(2) : String(q)) + ' × ' + MON.money2(rateOf(l), doc.market),
              cols.rate, y, 10);
        right(MON.money2(lineAmount(l, price.term), doc.market), cols.amt, y, 10);
        var amtNote = price.term ? 'per month' : (n > 1 ? n + ' months' : '');
        if (amtNote) right(amtNote, cols.amt, y - LROW, 8.5, font, mute);
        y -= LROW;
        names.slice(1).forEach(function (s2) { text(s2, cols.desc, y, 10, bold); y -= LROW; });
        incl.forEach(function (s2) { text(s2, cols.desc, y, 8.5, font, mute); y -= LSUB; });
        y -= split;
        meta.forEach(function (s2) { text(s2, cols.desc, y, 8.5, font, mute); y -= LSUB; });
        y -= LGAP;
      });
      rule(y); y -= 14;

      /* The figures the client is accepting are the ones they will be
         invoiced: a month at a time where the services run by the month.
         The whole commitment is a term below, in words, so it is disclosed
         without being the number in bold. */
      need(66);
      var lx = R - 230;
      var trow = function (label, value, kind) {
        var strong = kind === 'strong';
        var size = strong ? 10.5 : 10;
        var f = strong ? bold : font;
        text(label, lx, y, size, f, strong ? ink : mute);
        right(value, R, y, size, f, ink);
        y -= 15;
      };
      trow('Subtotal', MON.money2(price.each, doc.market));
      trow(Number(price.eachTax) ? 'SST 8%' : 'SST not applicable', MON.money2(price.eachTax, doc.market));
      y += 4; rule(y, lx, R, true); y -= 14;
      trow(price.term ? 'Payable monthly' : 'Total', MON.money2(price.eachTotal, doc.market), 'strong');
      y -= 12;

      /* The conditions in one block instead of a sentence here and a sentence
         there. The label matches the table's, so the letter has one voice for
         "this is a heading". The commitment line is what the client signs
         off: a monthly figure alone is not a figure anyone can be held to. */
      var terms = [];
      if (price.term) {
        terms.push('Fees are billed monthly in advance for a minimum term of ' + price.term + ' months.');
        terms.push('The total payable over the ' + price.term + ' month term is ' +
                   MON.money2(price.total, doc.market) + (Number(price.tax) ? ' including SST.' : '.'));
      }
      terms.push('This offer is valid until ' + letterDate(plusDays(doc.issued_at, k.validDays)) + '.');
      need(24 + terms.length * 26);
      text('TERMS', M, y, 9, bold, mute); y -= 15;
      terms.forEach(function (s2) {
        wrap(s2, R - M, 9.5).forEach(function (ln) { text(ln, M, y, 9.5); y -= 13; });
      });
      y -= 14;

      para('Kindly confirm your acceptance by signing below and returning a copy of this letter to us.');

      /* Closing, as the reference signs off: the person's name under the
         company. It is reserved on its own and drawn where it falls, because
         the letter reads as finished at the foot of its last page of
         substance; the acceptance is a separate act on a separate sheet.
         Reserving the closing WITH the acceptance block, which is what this
         did, moved both the moment the services carried their inclusions, and
         page two then opened with three orphaned lines of sign-off before
         anything a client could act on. */
      var closeH = LH * (doc.issued_by ? 3 : 2) + 16;
      need(closeH);
      text('Yours sincerely,', M, y, BODY); y -= LH;
      text('For and on behalf of ' + (ORG.name || 'ADSPACE PLT'), M, y, BODY, bold); y -= LH;
      /* The name of the person who issued it, and nothing else. It is never a
         permission: issue_letter refuses a team row named for a role, so
         "Superadmin" cannot reach a client's letterhead. */
      if (doc.issued_by) { text(doc.issued_by, M, y, BODY); y -= LH; }
      y -= 16;

      /* ---- The acceptance -------------------------------------------------
         What the client is agreeing to, in a sentence they can read once, and
         then the figures as a table rather than buried in the prose. The
         amounts come from the same `price` object the table above was drawn
         from, so the letter cannot quote itself two different totals.

         The whole of it is kept on one page: a stamp box on a sheet of its own
         is a signature that proves nothing about what was signed. */
      var moneyWord = function (v) {
        return MON.money2(v, doc.market) + (Number(price.tax) ? ', including SST' : '');
      };
      var sumRows = price.term
        ? [['Monthly fee', moneyWord(price.eachTotal)],
           ['Contract term', price.term + ' months'],
           ['Total contract value', moneyWord(price.total)]]
        : [['Total payable', moneyWord(price.eachTotal)]];

      var SIGH = 91;          // 32mm of signing room, not a ruled line
      var FIELDH = 29;        // 10mm for each of the three fields
      var acceptH = 18 + LH   // heading
        + LH * 2 + 10         // the sentence
        + 14 + sumRows.length * 15 + 10   // the summary
        + 26                  // the page count line
        + LH + 14             // the execution heading
        + SIGH + 30           // the signing area and its label
        + 3 * (FIELDH + 26);  // name, designation, date
      need(acceptH);

      text('Acceptance of offer', M, y, BODY, bold); y -= LH + 8;

      /* Plain prose, and a plain date: an ordinal reads as a letterhead
         flourish and this sentence is the operative one. */
      wrap('By signing below, the Client accepts Letter of Offer ' + doc.number +
           ', dated ' + longDate(doc.issued_at) +
           ', including the services, fees, and terms set out in this document.',
           R - M, BODY).forEach(function (ln) { text(ln, M, y, BODY); y -= LH; });
      y -= 10;

      // The figures, from the same calculation the price table used.
      var sumL = M, sumR = R;
      text('Item', sumL, y, 9, bold, mute);
      right('Value', sumR, y, 9, bold, mute);
      y -= 7; rule(y); y -= 13;
      sumRows.forEach(function (r) {
        text(r[0], sumL, y, 10);
        right(r[1], sumR, y, 10, bold);
        y -= 15;
      });
      y -= 4; rule(y); y -= 12;

      /* The page count stays: a letter signed on its last sheet is a letter
         whose first sheet can be swapped, and the count is one of the three
         marks that contradicts a substitution. The reference and the date are
         in the sentence above, so this line carries what is left. */
      text('This letter comprises ' + pages.length + ' pages.', M, y, 9, font, mute);
      y -= 26;

      /* A registered name can be longer than the column, and this line carries
         one. Unwrapped it ran past the right margin and the tail simply was
         not on the page. */
      wrap('Confirmed and accepted for and on behalf of ' + legalName.toUpperCase(),
           R - M, BODY, bold).forEach(function (ln) { text(ln, M, y, BODY, bold); y -= LH; });
      y -= 14;

      /* ---- The execution block -------------------------------------------
         A signature is a hand moving across a page, so the room for it is an
         area and not a ruled line: 32mm, the width of the text column. The
         three fields under it are the same width, far enough apart to write
         between, and each carries its own baseline.

         Every one of them is also a real AcroForm field, so the letter can be
         filled in a PDF reader and returned without printing. The drawn rules
         and labels stay underneath, because a printed copy is still the
         fallback and a field is invisible on paper. */
      var fieldBoxes = [];
      var signTop = y;
      rule(y - SIGH, M, R);
      text('Authorised signatory and company stamp', M, y - SIGH - 11, 8.5, font, mute);
      fieldBoxes.push(['acceptance_authorised_signatory', M, y - SIGH, R - M, SIGH, true]);
      y -= SIGH + 44;

      [['Name', 'acceptance_name'],
       ['Designation', 'acceptance_designation'],
       ['Date', 'acceptance_date']].forEach(function (f) {
        rule(y, M, R);
        text(f[0], M, y - 11, 8.5, font, mute);
        fieldBoxes.push([f[1], M, y, R - M, FIELDH, false]);
        y -= FIELDH + 26;
      });
      y -= 4;

      var signPage = page;
      pages.forEach(function (pg, i) { page = pg; pn.page = pg; foot(i, pages.length); });

      /* The fields are added last, once the page they belong to is settled.
         Their appearance font is Helvetica rather than the letter's own face:
         a subsetted custom font carries only the glyphs the letter drew, so a
         recipient typing a character the letter never used would get an
         appearance stream the reader cannot build. The fields are real widgets
         on the page and in the AcroForm tree, so they do not depend on
         NeedAppearances to be usable. */
      return pdf.embedFont(PDF.StandardFonts.Helvetica).then(function (formFont) {
        var form = pdf.getForm();
        fieldBoxes.forEach(function (f) {
          var fld = form.createTextField(f[0]);
          if (f[5]) fld.enableMultiline();
          /* addToPage is what writes the field's /DA, so the size is set after
             it and not before: pdf-lib throws on a field that has no default
             appearance yet, and the throw escaped into a download that never
             came. */
          /* Transparent, and with no border of its own: the rule and the
             label under it are what a printed copy shows, and a field drawn
             over them hides them. pdf-lib fills a field white and borders it
             black unless the key is present, so both are passed explicitly as
             undefined rather than left out. The white default is what painted
             over "Authorised signatory and company stamp". */
          fld.addToPage(signPage, {
            x: f[1], y: f[2], width: f[3], height: f[4],
            font: formFont,
            borderWidth: 0,
            borderColor: undefined,
            backgroundColor: undefined
          });
          fld.setFontSize(11);
        });
        form.updateFieldAppearances(formFont);
        return pdf.save();
      });
    });
  }

  function list(clientId, then) {
    db.from('client_documents').select('*').eq('client_id', clientId).order('created_at', { ascending: false })
      .then(function (r) { then(r.data || [], r.error); }, function (e) { then([], e); });
  }

  /* Voiding went through PostgREST and could reach a verified letter, which is
     the record of something a client signed and we accepted. It is a
     transaction now, and that one it refuses. `setVoidRpc` above is what the
     console calls; the shape of the callback is unchanged, so nothing that
     used it had to learn anything new. */

  // Only a voided document can be deleted, and its number is never reused:
  // the next number counts from the highest issued, not from the count.
  /* Deleting went through PostgREST, which meant the browser decided who was
     allowed to and what it took with it. It is a transaction now, gated on the
     portal's own hard-delete permission, and it is the only path: there is no
     stored PDF and no signed upload, so the row is the letter and removing it
     removes the whole of it. */

  window.ADspaceDocs = {
    issue: issue, download: download, render: render, list: list,
    setVoid: setVoidRpc, remove: removeRpc, KIND: KIND, fileName: fileName,
    setSigned: setSigned, verify: verify, mapOf: mapOf,
    liveDoc: liveDoc, letterState: letterState, quoteOf: quoteOf, idemKey: idemKey,
    // What js/letters.js draws with, so there is one letterhead.
    pen: pen, embedFonts: embedFonts, embedLogo: embedLogo, letterDate: letterDate,
    logoWarn: function () { return logoWarn; }
  };
})();
