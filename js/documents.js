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
 * lines and totals, Yours sincerely, the acceptance block and the page
 * count. Fonts and images come from
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
    /* `validDays` is what a letter issued before 23 Oct 2026 printed, kept
       so it redraws as issued; a letter since carries its validity in its
       own terms, from Tax and terms (`validLine`). */
    offer: { prefix: 'AQT/INT/', title: 'Letter of Offer', word: 'Reference', per: 'month', validDays: 30 }
  };
  KIND.intent = KIND.cover = KIND.offer;   // rows issued before the rename

  /* A day is Malaysia's (js/clock.js): a moment (a letter's issued_at)
     reads as its day here, whatever the device's clock. */
  function dayOf(s) { s = String(s || ''); return s.length === 7 ? s + '-01' : s.length > 10 ? ADspaceClock.day(s) : s; }
  function plusDays(s, n) { var d = dayOf(s); return /^\d{4}-\d{2}-\d{2}$/.test(d) ? ADspaceClock.addDays(d, n) : ''; }
  function longDate(s) { return (s && ADspaceClock.date(dayOf(s), { long: true })) || String(s || ''); }
  /* The rate a line is billed at: the rate that was typed, carrying its term
     adjustment where the line was ticked to take one. One definition, in
     money.js, so the console, the letter and the client's page cannot
     disagree — and a line stored before the tick existed carries no flag at
     all, which money.js reads as on, so a letter issued then redraws at the
     figure it printed. */
  function rateOf(l) { return MON.rateFor(l.rate, l.tenure, l.term_adjust, l.term_pct); }

  /* One price, worked the same way when the letter is issued (by
     `issue_letter`, to the sen) and when it is drawn again later, so the
     stored total and the printed one never drift.

     Where every line of more than a month runs the same term, those lines are
     priced per month, because that is how they are invoiced and how the client
     thinks about them: `each` is one month's invoice. A line of one month
     beside them is a one-off item (`once`), with its own SST, never folding
     the monthly figures into one whole (the user, 2026-10-15). Lines of mixed
     terms have no monthly figure: every line is its whole amount, in `each`.
     The subtotal, SST and total are the whole commitment: the term's months
     and the one-off items. */
  function isMonthly(l, term) { return term > 0 && Math.max(1, Number(l.tenure || 1)) === term; }
  /* A letter whose every line came from one quotation is priced as that
     quotation was (audit F, 2026-10-17): the term percentage taken once on
     each subtotal, never rounded line by line, and SST at the rate the
     quotation was made with (`quote_sst`, kept on each line), as
     `issue_letter` prices it. Any other letter is priced as before. */
  function quoteMode(lines) {
    var q = lines.length ? lines[0].quotation_id : null;
    var sst = lines.length ? lines[0].quote_sst : null;
    if (!q || sst == null || sst === '') return null;
    if (!lines.every(function (l) { return l.quotation_id === q && Number(l.quote_sst) === Number(sst); })) return null;
    /* A snapshot keeping the quotation's term (2026-10-17, the review's
       finding 7) is priced as quote_adjust totals it: a line with its term
       ticked is monthly whatever its months, one with none one-off. One
       issued before keeps the reading it was issued on. */
    var term = lines[0].quote_term == null || lines[0].quote_term === '' ? null : Math.max(1, Number(lines[0].quote_term));
    if (term != null) {
      if (lines.some(function (l) { return l.term_adjust !== true && Math.max(1, Number(l.tenure || 1)) > 1; })) return null;
      var mp = lines.filter(function (l) { return l.term_adjust === true; }).map(function (l) { return Number(l.term_pct || 0); })
        .filter(function (v, i, a) { return a.indexOf(v) === i; });
      return mp.length > 1 ? null : { pct: mp[0] || 0, sst: Number(sst), term: term };
    }
    var longs = lines.filter(function (l) { return Math.max(1, Number(l.tenure || 1)) > 1; });
    if (longs.some(function (l) { return l.term_adjust === false; })) return null;
    var pcts = longs.map(function (l) { return Number(l.term_pct || 0); })
      .filter(function (v, i, a) { return a.indexOf(v) === i; });
    if (pcts.length > 1) return null;
    return { pct: pcts[0] || 0, sst: Number(sst) };
  }
  /* A quoted letter priced as quote_adjust totals it (2026-10-17): where
     every monthly line runs the quotation's term, by the month, its SST
     rounded once; else the whole span (each line's amount × its months)
     with the percentage and SST taken once on it; one-off lines apart. */
  function quotePrice(lines, qm, taxOn) {
    var sst = taxOn === false ? 0 : qm.sst;
    /* Each line at its own tax code's rate where it carries one (2026-10-22),
       else the quotation's; the SST worked a rate at a time, rounded once
       each, as quote_totals works it. */
    var msub = 0, span = 0, once = 0, month = false, even = true, g = {};
    lines.forEach(function (l) {
      var n = Math.max(1, Number(l.tenure || 1)), v = Number(l.qty || 0) * Number(l.rate || 0);
      var r = l.tax_pct == null || l.tax_pct === '' ? sst : Number(l.tax_pct);
      var b = g[r] || (g[r] = { r: r, msub: 0, span: 0, once: 0 });
      if (l.term_adjust === true) { month = true; msub += v; span += cents(v) * n; b.msub += v; b.span += cents(v) * n; if (n !== qm.term) even = false; }
      else { once += v; b.once += v; }
    });
    var r2 = function (v) { return Math.round(v * 100) / 100; };
    var by = function (f) { return r2(Object.keys(g).reduce(function (a, k) { return a + f(g[k]); }, 0)); };
    var otax = by(function (b) { return cents(b.once * b.r / 100); });
    var mtaxOf = function (b) { return cents((b.msub + cents(b.msub * qm.pct / 100)) * b.r / 100); };
    var out = { sstPct: qm.sst, term: 0, each: 0, eachTax: 0, eachTotal: 0, once: once, onceTax: otax, onceTotal: r2(once + otax) };
    if (month && even) {
      var adj = cents(msub * qm.pct / 100), each = msub + adj, etax = by(mtaxOf);
      out.term = qm.term; out.each = each; out.eachTax = etax; out.eachTotal = r2(each + etax);
      out.quote = { pct: qm.pct, base: r2(msub), adj: adj, rest: once };
      out.subtotal = r2(r2(each * qm.term) + once); out.tax = r2(r2(etax * qm.term) + otax);
      out.total = r2(r2(out.eachTotal * qm.term) + out.onceTotal);
      return out;
    }
    /* Whole amounts: one subtotal, the term's row on the span, one SST
       figure, the total incl. SST. */
    /* The quotation's own month and term stay on the letter (2026-10-18):
       its Monthly incl. SST, as quote_adjust gives it (every monthly line
       at the percentage, SST rounded once), and its term for the commitment
       wording. */
    if (month) {
      var pex = msub + cents(msub * qm.pct / 100);
      /* The first month holds the one-off items too (the user, 2026-10-18),
         as the quotation's First month incl. SST does. */
      out.plan = qm.term; out.planMonth = r2(pex + by(mtaxOf) + once + otax); out.planOnce = once > 0;
    }
    var mex = month ? cents(span * (1 + qm.pct / 100)) : 0;
    var mtot = month ? by(function (b) { return cents(b.span * (1 + qm.pct / 100) * (1 + b.r / 100)); }) : 0;
    out.quote = month ? { pct: qm.pct, base: r2(span), adj: r2(mex - span), rest: once } : null;
    out.each = r2(mex + once); out.eachTotal = r2(mtot + once + otax); out.eachTax = r2(out.eachTotal - out.each);
    out.once = 0; out.onceTax = 0; out.onceTotal = 0;
    out.subtotal = out.each; out.tax = out.eachTax; out.total = out.eachTotal;
    return out;
  }
  /* To the cent, a half away from nought, as the database rounds. */
  function cents(v) {
    var a = Math.round(Math.abs(v) * 100 + 1e-7) / 100;
    return v < 0 ? -a : a;
  }
  function priceOf(lines, market, taxOn, at) {
    var long = lines.map(function (l) { return Math.max(1, Number(l.tenure || 1)); }).filter(function (x) { return x > 1; });
    var term = (long.length && long.every(function (x) { return x === long[0]; })) ? long[0] : 0;
    var each = 0, once = 0, quote = null, g = null;
    var qm = quoteMode(lines);
    if (qm && qm.term != null) return quotePrice(lines, qm, taxOn);
    if (qm) {
      var base = 0, rest = 0;
      lines.forEach(function (l) {
        var n = Math.max(1, Number(l.tenure || 1)), v = Number(l.qty || 0) * Number(l.rate || 0);
        if (term ? n === term : n > 1) base += term ? v : v * n; else rest += v * n;
      });
      var adj = base + cents(base * qm.pct / 100);
      if (term) { each = adj; once = rest; } else { each = adj + rest; }
      /* What the letter prints: the lines at their rates before the term, and
         the term's percentage as one row on their subtotal, as the quotation
         prints it, so the rows add up to the subtotal (2026-10-17). */
      quote = { pct: qm.pct, base: base, adj: cents(base * qm.pct / 100), rest: rest };
    } else {
      /* Each line at its own tax code's rate where it carries one
         (`tax_pct`, 2026-10-22), else the client's: the SST worked a rate
         at a time, rounded once each, as issue_letter works it. */
      g = {};
      lines.forEach(function (l) {
        var v = Number(l.qty || 0) * rateOf(l);
        var r = l.tax_pct == null || l.tax_pct === '' ? '' : Number(l.tax_pct);
        var b = g[r] || (g[r] = { r: r, each: 0, once: 0 });
        if (isMonthly(l, term)) { each += v; b.each += v; }
        else { var w = v * Math.max(1, Number(l.tenure || 1)); once += w; b.once += w; }
      });
      if (!term) { each = once; once = 0; Object.keys(g).forEach(function (k) { g[k].each = g[k].once; g[k].once = 0; }); }
    }
    var taxOn1 = function (v) { return qm ? (taxOn === false ? 0 : cents(v * qm.sst / 100)) : MON.taxOf(v, market, taxOn, at); };
    var taxOn2 = function (v, part) {
      if (!g) return taxOn1(v);
      return Math.round(Object.keys(g).reduce(function (a, k) {
        var b = g[k];
        return a + (b.r === '' ? taxOn1(b[part]) : cents(b[part] * b.r / 100));
      }, 0) * 100) / 100;
    };
    var eachTax = taxOn2(each, 'each');
    var eachTotal = Math.round((each + eachTax) * 100) / 100;
    var onceTax = taxOn2(once, 'once');
    var onceTotal = Math.round((once + onceTax) * 100) / 100;
    var n = term || 1;
    var r2 = function (v) { return Math.round(v * 100) / 100; };
    return {
      sstPct: qm ? qm.sst : null, quote: quote,
      term: term, each: each, eachTax: eachTax, eachTotal: eachTotal,
      once: once, onceTax: onceTax, onceTotal: onceTotal,
      subtotal: r2(r2(each * n) + once),
      tax: r2(r2(eachTax * n) + onceTax),
      total: r2(r2(eachTotal * n) + onceTotal)
    };
  }
  // What one line puts on the invoice the Amount column is totalling.
  function lineAmount(l, term) {
    return Number(l.qty || 0) * rateOf(l) * (isMonthly(l, term) ? 1 : Math.max(1, Number(l.tenure || 1)));
  }
  /* "12 October 2026 to 11 April 2027" for a termed line, "12 October 2026"
     for a dated one, "6 months" for a term without a start. */
  function periodOf(l) {
    var n = Math.max(1, Number(l.tenure || 1));
    if (!l.start_on) return n > 1 ? n + ' months' : '';
    if (n === 1) return longDate(l.start_on);
    var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(dayOf(l.start_on));
    if (!m) return n + ' months';
    var end = new Date(Date.UTC(+m[1], +m[2] - 1 + n, +m[3] - 1)).toISOString().slice(0, 10);
    return longDate(l.start_on) + ' to ' + longDate(end);
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

  /* What the letter would be worth, as the letter draws it. The database
     works the same price from the stored lines and keeps these figures only
     where they agree to the sen (audit S4, 2026-10-10), so a line changed
     since the sheet opened is refused rather than printed at the old price. */
  /* The rate of each tax code a service line may carry (2026-10-22), read
     once a page: a line holding a code is priced at its rate, as
     issue_letter prices it. */
  var TAXR = {};
  function taxRates(list) { TAXR = {}; (list || []).forEach(function (t) { TAXR[t.code] = Number(t.rate); }); return TAXR; }
  var taxAsked = false;
  function quoteOf(client, lines, quotes, renewal) {
    if (!taxAsked && MON.taxCodes) { taxAsked = true; MON.taxCodes().then(taxRates); }
    lines = lines.map(function (l) {
      return l.tax_code && (l.tax_pct == null || l.tax_pct === '') && TAXR[l.tax_code] != null
        ? Object.assign({}, l, { tax_pct: TAXR[l.tax_code] }) : l;
    });
    /* Lines a quotation made carry its SST rate, read from the quotation
       the page holds, as the database reads it: only while it stands
       (unexpired, not removed) and never on a renewal (2026-10-17). */
    var q = lines.length ? lines[0].quotation_id : null;
    var hit = !renewal && q && lines.every(function (l) { return l.quotation_id === q; }) &&
      (quotes || []).filter(function (x) {
        return x.id === q && !x.removed_at && String(x.valid_until || '').slice(0, 10) >= window.ADspaceClock.today();
      })[0];
    if (hit && hit.totals) {
      lines = lines.map(function (l) {
        return Object.assign({}, l, { quote_sst: client.sst_applies === false ? 0 : Number(hit.totals.sst_pct || 0),
                                      quote_term: Math.max(1, Number(hit.totals.term || 1)) });
      });
    }
    return priceOf(lines, MON.curOf(client), client.sst_applies !== false);
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
    deal = deal || {};
    /* Priced once the tax codes are read, so a line's own code is priced
       at its rate (2026-10-22). */
    (MON.taxCodes ? MON.taxCodes() : Promise.resolve([])).then(function (list) {
    if (list && list.length) taxRates(list);
    var price = quoteOf(client, use, opts.quotes, opts.renewal);
    db.rpc('issue_letter', {
      p_client: client.id,
      p_services: use.map(function (l) { return l.id; }),
      p_idem: opts.idem || idemKey(),
      p_subtotal: price.subtotal, p_tax: price.tax, p_total: price.total,
      p_deal: { owner: deal.owner || '', source: deal.source || '', industry: deal.industry || '',
                stage: deal.stage || '', enquiry: deal.enquiry || '', terms: deal.terms || [], terms_own: true },
      p_replaces: opts.replaces || null,
      p_renewal: Boolean(opts.renewal),
      p_serial: serial || null
    }).then(function (r) {
      /* The migration has to be in place before the site is. Until it is, the
         function is missing and nothing is written at all — a half issued
         letter cannot exist either way. */
      if (r.error) { then({ error: missingWord(r.error.message) }); return; }
      var out = r.data || {};
      if (out.error) { then({ error: ISSUE_WORD[out.error] || out.error, code: out.error }); return; }
      readBack(out.id, function (doc, err) {
        if (err || !doc) { then({ ok: true, repeat: out.repeat, number: out.number, warn: 'Issued. The file could not be drawn.' }); return; }
        download(doc, function (warn) {
          then({ ok: true, repeat: out.repeat, doc: doc, number: out.number, warn: warn });
        });
      });
    }).catch(function (e) { then({ error: missingWord(e && e.message) }); });
    });
  }

  function readBack(id, then) {
    db.from('client_documents').select('*').eq('id', id).single()
      .then(function (r) { then(r.data, r.error); }).catch(function (e) { then(null, e); });
  }

  /* The database answers in one word; the console says what it means. */
  var ISSUE_WORD = {
    'not-allowed': 'You do not have permission to issue a letter.',
    'no-client-code': 'Add a Client ID to this client before issuing a letter.',
    'no-client': 'That client could not be found.',
    'no-lines': 'Choose at least one service.',
    'bad-lines': 'One of those services cannot go on a letter. Refresh and try again.',
    'bad-tax': 'One of those services carries a tax code that is no longer offered. Choose another on the service.',
    'already-quoted': 'One of those services is already on a letter that is still live. Void that letter, or use Replace.',
    'bad-terms': 'Terms hold ten points at most, each up to 400 characters.',
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
    'bad-state': 'That is not a state a service can be in.',
    'stale': 'The services or their quotation changed since this sheet was opened. They have been read again: check them and issue the letter again.',
    'changed-terms': 'A service on this letter changed after it was issued. Reissue the letter.',
    'archived-line': 'A service on this letter was removed after it was issued. Reissue the letter, or restore the service.'
  };

  function missingWord(m) {
    m = String(m || '');
    if (/could not find|does not exist|schema cache|function public\.(issue_letter|letter_delete|letter_set_void)/i.test(m)) {
      return 'This needs a database update.';
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
    }).catch(function (e) { then(missingWord(e && e.message)); });
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
      }).catch(function () { then({}); });
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
    var said = false, tab = tabFor();
    var say = function (w) { if (said) return; said = true; if (then) then(w); };
    try {
      render(doc).then(function (bytes) {
        save(new Blob([bytes], { type: 'application/pdf' }), fileName(doc), tab);
        say(logoWarn);
      }).catch(function (e) {
        shut(tab);
        say('The file could not be drawn: ' + ((e && e.message) || e) + ' Download it from the row.');
      });
    } catch (e) {
      shut(tab);
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
    /* The page count bottom right. The monogram belongs to the letterhead at
       the top of the page and nowhere else: the foot carried a second one,
       which ADspace has dropped (the user, 2026-09-25). */
    p.footMark = function (i, n, size) {
      p.right('Page ' + (i + 1) + ' of ' + n, R, 30, size || 7.5, font, mute);
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
    var p = s ? ADspaceClock.parts(dayOf(s)) : null;
    return p ? ordinal(p.d) + ' ' + ADspaceClock.LONG[p.mo] + ' ' + p.y : String(s || '');
  }

  // ---- The PDF library, fetched on the first drawing ----------------------
  /* pdf-lib and fontkit are 1.1 MB, and every console and portal load ran
     them in the head (about 200 ms at a desk and 600 ms on a phone, measured
     on 2026-10-02) for a PDF most visits never draw. They are fetched here
     instead, once, the first time anything is drawn; every drawing (a letter,
     a report, a performance record) waits on this. A failed fetch is said
     by name and fetched again on the next press. Each is pinned by the hash
     of the file the CDN serves, as every script tag on a page is (a new
     version is hashed from the file the CDN serves; tests/sql.js holds it). */
  var LIBS = [
    ['PDFLib', 'https://cdnjs.cloudflare.com/ajax/libs/pdf-lib/1.17.1/pdf-lib.min.js', 'sha384-weMABwrltA6jWR8DDe9Jp5blk+tZQh7ugpCsF3JwSA53WZM9/14PjS5LAJNHNjAI'],
    ['fontkit', 'https://cdn.jsdelivr.net/npm/@pdf-lib/fontkit@1.1.1/dist/fontkit.umd.min.js', 'sha384-2p6U+1mmqF10USehFeRiyG2ESG9FwIqN+jxULn5w9jjQIihSn9Pt13dVCn/Hawjn']
  ];
  var libWait = null;
  /* A script refused for its hash and one that never arrived both fire
     onerror alone. The file is fetched once more and hashed: one that
     arrives and does not match has changed at the CDN, which no retry
     mends (2026-10-18). Anything that cannot be told reads as the
     connection. */
  function whyNot(l) {
    if (!l[2] || !window.fetch || !window.crypto || !crypto.subtle) return Promise.resolve(false);
    var alg = l[2].split('-')[0], want = l[2].slice(alg.length + 1);
    var name = { sha256: 'SHA-256', sha384: 'SHA-384', sha512: 'SHA-512' }[alg];
    if (!name) return Promise.resolve(false);
    return fetch(l[1], { mode: 'cors', cache: 'no-store', credentials: 'omit' }).then(function (r) {
      if (!r.ok) return false;
      return r.arrayBuffer().then(function (buf) { return crypto.subtle.digest(name, buf); }).then(function (d) {
        var bin = '', b = new Uint8Array(d);
        for (var i = 0; i < b.length; i++) bin += String.fromCharCode(b[i]);
        return btoa(bin) !== want;
      });
    }).catch(function () { return false; });
  }
  function lib() {
    if (window.PDFLib) return Promise.resolve(window.PDFLib);
    if (libWait) return libWait;
    libWait = Promise.all(LIBS.map(function (l) {
      if (window[l[0]]) return null;
      return new Promise(function (ok, bad) {
        var s = document.createElement('script');
        if (l[2]) { s.integrity = l[2]; s.crossOrigin = 'anonymous'; }
        s.src = l[1];
        s.onload = ok;
        s.onerror = function () {
          s.remove();
          whyNot(l).then(function (changed) {
            bad(new Error(changed
              ? 'The PDF library has changed at its source and was not loaded. Please contact ADspace.'
              : 'The PDF library could not be loaded. Check the connection and try again.'));
          });
        };
        document.head.appendChild(s);
      });
    })).then(function () {
      if (!window.PDFLib) throw new Error('PDF library not loaded');
      return window.PDFLib;
    }).catch(function (e) { libWait = null; throw e; });
    return libWait;
  }

  // ---- Drawing ---------------------------------------------------------------
  function render(doc) {
    return lib().then(function () { return drawDoc(doc); });
  }
  function drawDoc(doc) {
    var PDF = window.PDFLib;
    if (!PDF) return Promise.reject(new Error('PDF library not loaded'));
    var k = KIND[doc.kind] || KIND.offer;
    var pdf, fonts, logo;
    return PDF.PDFDocument.create().then(function (p) {
      pdf = p;
      /* The file names its reference: wa-send sends a letter only where it
         does (2026-10-15). */
      pdf.setTitle(k.title + ' ' + String(doc.number || '')); pdf.setAuthor('ADSPACE PLT');
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

      // The letterhead, on every page; the page count bottom right. y counts down from the top of the page.
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
      var price = priceOf(doc.lines || [], doc.market, lineTax, doc.issued_at);
      /* Each line at its own tax code's rate where it carries one
         (2026-10-22): the SST row names the rate, and a line on another
         rate says so under its name. */
      var taxed = MON.sstOf(doc.lines || [], lineTax === false ? 0 :
        price.sstPct != null ? price.sstPct : MON.setting('sst_pct', dayOf(doc.issued_at)));
      text('PRIVATE & CONFIDENTIAL', M, y, BODY, bold); y -= 24;

      // Our Ref / Date / To / Attn, the colons in one column. The contact is
      // addressed with their salutation where one is held (2026-10-14).
      var who = ((b.contact_salutation ? b.contact_salutation + ' ' : '') + (b.contact || '')).trim();
      var refs = [
        ['Our Ref', doc.number], ['Date', letterDate(doc.issued_at)],
        ['To', legalName.toUpperCase()],
        ['Attn', b.contact ? who + (b.contact_role ? ', ' + b.contact_role : '') : '']
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
      text('Dear ' + (who || 'Sir/Madam') + ',', M, y, BODY); y -= 29;

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
        /* A quoted letter prints the rate before the term and the term as
           one row of the summary, so the line names no adjustment. */
        var qd = price.quote;
        var shownRate = qd ? Number(l.rate || 0) : rateOf(l);
        var shownAmt = qd ? q * shownRate * (isMonthly(l, price.term) ? 1 : n) : lineAmount(l, price.term);
        var metaWord = [l.unit, qd ? '' : MON.termNote(l.tenure, l.term_adjust, l.term_pct), periodOf(l), l.note].filter(Boolean).join('  ·  ');
        var meta = metaWord ? wrap(metaWord, descW, 8.5) : [];
        var split = incl.length && meta.length ? 4 : 0;
        if (y - (names.length * LROW + (incl.length + meta.length) * LSUB + split + LGAP) < 70) { newPage(); head(); thead(); }
        text(names[0] || '', cols.desc, y, 10, bold);
        // A letter priced line by line prints the rate the client is billed,
        // term adjustment included, because that is the figure they are
        // accepting, and names why it differs from the rate card on the mute
        // line below. A quoted letter prints the rate before the term: the
        // term is one row of the summary, taken once on the subtotal with
        // SST on what it leaves, as the quotation prints it (2026-10-18).
        // SST is never part of a line's rate.
        right(q === 1 ? MON.money2(shownRate, doc.market)
                      : (q % 1 ? q.toFixed(2) : String(q)) + ' × ' + MON.money2(shownRate, doc.market),
              cols.rate, y, 10);
        right(MON.money2(shownAmt, doc.market), cols.amt, y, 10);
        var amtNote = isMonthly(l, price.term) ? 'per month' : price.term ? 'one-off' : (n > 1 ? n + ' months' : '');
        /* Where the lines are on more than one rate, each amount says its
           own under it, (+8% SST) or (0% SST) (the user, 2026-10-23: under
           the description it read as part of the item). */
        var amtNotes = [amtNote, taxed.tag(l)].filter(Boolean);
        amtNotes.forEach(function (w, i) { right(w, cols.amt, y - LROW - i * LSUB, 8.5, font, mute); });
        var top = y;
        y -= LROW;
        names.slice(1).forEach(function (s2) { text(s2, cols.desc, y, 10, bold); y -= LROW; });
        incl.forEach(function (s2) { text(s2, cols.desc, y, 8.5, font, mute); y -= LSUB; });
        y -= split;
        meta.forEach(function (s2) { text(s2, cols.desc, y, 8.5, font, mute); y -= LSUB; });
        /* The amount's notes never run into the next line. */
        y = Math.min(y, top - LROW - amtNotes.length * LSUB);
        y -= LGAP;
      });
      rule(y); y -= 14;

      /* The figures the client is accepting are the ones they will be
         invoiced: a month at a time where the services run by the month.
         The whole commitment is a term below, in words, so it is disclosed
         without being the number in bold. */
      /* The one-off summary is five rows and a rule, about 85pt: kept whole
         on its page (audit I11, 2026-10-15). */
      var qd = price.quote, qadj = qd && Number(qd.pct) ? 1 : 0;
      need((price.term && price.once > 0 ? 90 : 66) + qadj * 15 + (price.plan ? 15 : 0));
      var lx = R - 230;
      var trow = function (label, value, kind) {
        var strong = kind === 'strong';
        var size = strong ? 10.5 : 10;
        var f = strong ? bold : font;
        text(label, lx, y, size, f, strong ? ink : mute);
        right(value, R, y, size, f, ink);
        y -= 15;
      };
      var taxWord = !(Number(price.eachTax) || Number(price.onceTax)) ? MON.SST_NONE : taxed.word;
      var oneOff = price.term && price.once > 0;
      /* One summary, one figure to pay first (the user, 2026-10-15: "just
         provide first month due total at the summary table part instead of
         spliting it"; "use Monthly incl. SST" as the quotation does). The
         one-off items are billed with the first month, so their subtotal
         sits beside the month's and one SST line covers both; the first
         month due is the figure in bold, then what each later month is. */
      var sst = Number(price.tax) > 0;
      var incl = sst ? ' incl. SST' : '';
      var firstDue = Math.round((Number(price.eachTotal) + Number(price.onceTotal || 0)) * 100) / 100;
      /* A quoted letter: the rows' subtotal, then the term's row, as the
         quotation's totals read (`12-Month Commitment (5%)`). */
      var signed = function (v) { return v < 0 ? '(' + MON.money2(-v, doc.market) + ')' : MON.money2(v, doc.market); };
      /* A Singapore client billed in RM reads the figure in bold in S$
         under it, at the rate kept when the letter was issued (2026-10-22). */
      var nearRow = function (v) {
        var fx = Number(b.fx_sgd);
        if (String(b.market || '').toUpperCase() !== 'SG' || String(doc.market || '').toUpperCase() === 'SG' || !(fx > 0)) return;
        right('Approx. ' + MON.money2(Math.round(Number(v) / fx * 100) / 100, 'SG'), R, y + 2, 9, font, mute);
        y -= 13;
      };
      var termRow = function () {
        if (!qadj) return;
        var pc = Math.round(Math.abs(qd.pct) * 100) / 100, tn = price.term || price.plan;
        trow((tn ? tn + '-month ' : '') + (qd.pct < 0 ? 'commitment (' + pc + '%)' : 'term (+' + pc + '%)')
          .replace(/^./, function (c) { return tn ? c : c.toUpperCase(); }), signed(qd.adj));
      };
      if (oneOff) {
        trow('Monthly subtotal', MON.money2(qd ? qd.base : price.each, doc.market));
        termRow();
        trow('One-off subtotal', MON.money2(price.once, doc.market));
        trow(taxWord, MON.money2(Math.round((Number(price.eachTax) + Number(price.onceTax)) * 100) / 100, doc.market));
        y += 4; rule(y, lx, R, true); y -= 14;
        trow('First month due', MON.money2(firstDue, doc.market), 'strong');
        nearRow(firstDue);
        trow('Monthly' + incl, MON.money2(price.eachTotal, doc.market));
      } else {
        trow('Subtotal', MON.money2(qd ? qd.base + (price.term ? 0 : qd.rest) : price.each, doc.market));
        termRow();
        trow(taxWord, MON.money2(price.eachTax, doc.market));
        y += 4; rule(y, lx, R, true); y -= 14;
        trow(price.term ? 'Monthly' + incl : 'Total' + incl, MON.money2(price.eachTotal, doc.market), 'strong');
        nearRow(price.eachTotal);
        /* Lines running months of their own: the figure is the first
           month's, every monthly line running in it (the user, 2026-10-18),
           as the quotation names it. */
        if (price.plan) trow('First month' + incl, MON.money2(price.planMonth, doc.market));
      }
      y -= 12;

      /* The conditions in one block instead of a sentence here and a sentence
         there. The label matches the table's, so the letter has one voice for
         "this is a heading". The commitment line is what the client signs
         off: a monthly figure alone is not a figure anyone can be held to. */
      var terms = [];
      if (price.term) {
        /* The term is stated once (the user, 2026-10-15). */
        terms.push('Fees are billed monthly in advance for a minimum term of ' + price.term + ' months, a total of ' +
                   MON.money2(price.total, doc.market) + incl + (price.once > 0 ? ' with the one-off items' : '') + '.');
      } else if (price.plan) {
        /* A quoted letter whose lines run months of their own: the
           quotation's term, and the total over the months stated for each
           line, as the quotation says it (2026-10-18). */
        terms.push('Fees are billed monthly in advance for a minimum term of ' + price.plan + ' months, a total of ' +
                   MON.money2(price.total, doc.market) + incl + ' over the months stated for each line' +
                   (price.planOnce ? ', with the one-off items' : '') + '.');
      }
      /* A letter whose terms carry its validity (`terms_own`) prints them
         as typed; one issued before prints the validity it was issued with. */
      if (!b.terms_own) terms.push('This offer is valid until ' + letterDate(plusDays(doc.issued_at, k.validDays)) + '.');
      /* The letter's own terms, typed one point a line when it was issued
         (2026-10-23), after the ones it works out. */
      (Array.isArray(b.terms) ? b.terms : []).forEach(function (t) { if (String(t).trim()) terms.push(String(t).trim()); });
      need(24 + 26 * Math.min(terms.length, 3));
      text('TERMS', M, y, 9, bold, mute); y -= 15;
      /* Ten typed points can run past the page, so each line asks for its
         room. */
      terms.forEach(function (s2) {
        wrap(s2, R - M, 9.5).forEach(function (ln) { need(13); text(ln, M, y, 9.5); y -= 13; });
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
      /* The figures named as the summary names them, each carrying incl.
         SST in its label once, never a column of "including SST". */
      var sumRows = price.term
        ? [['Monthly' + incl, MON.money2(price.eachTotal, doc.market)],
           ['Minimum term', price.term + ' months']]
            .concat(price.once > 0 ? [['First month due', MON.money2(firstDue, doc.market)]] : [])
            .concat([['Total for the term' + incl, MON.money2(price.total, doc.market)]])
        : price.plan
          ? [['First month' + incl, MON.money2(price.planMonth, doc.market)], ['Minimum term', price.plan + ' months'],
             ['Total for the term' + incl, MON.money2(price.total, doc.market)]]
          : [['Total' + incl, MON.money2(price.eachTotal, doc.market)]];

      var SIGH = 91;          // 32mm of signing room, not a ruled line
      var FIELDH = 29;        // 10mm for each of the three fields
      var acceptH = 18 + LH   // heading
        + LH * 2 + 10         // the sentence
        + 8 + sumRows.length * 15 + 10    // the summary
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
      rule(y); y -= 15;
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
      .then(function (r) { then(r.data || [], r.error); }).catch(function (e) { then([], e); });
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

  /* A document not yet final carries its stage over every page (the user,
     2026-10-02 for reports, 2026-10-06 for a letter's Preview): light text
     repeated on the diagonal, drawn last and faint so nothing on the page
     hides it and it hides nothing. On the report's golden scale: S(4) in the
     book face, a gap along the line of the size times φ², rows the size
     times φ⁴ apart, at the golden angle (atan 1/φ, 31.7°), each row half a
     step along from the last, in a light ink at a tenth. One copy for every
     PDF the portal draws. */
  function watermark(page, word, font) {
    var PDF = window.PDFLib;
    if (!page || !word || !font || !PDF) return;
    var PHI = 1.6180339887, size = 10 * PHI * PHI;
    var dim = page.getSize(), W = dim.width, H = dim.height;
    var ang = Math.atan(1 / PHI), cos = Math.cos(ang), sin = Math.sin(ang);
    var tw = font.widthOfTextAtSize(word, size), step = tw + size * PHI * PHI, rowGap = size * Math.pow(PHI, 4);
    var reach = Math.sqrt(W * W + H * H) / 2 + step, cx = W / 2, cy = H / 2;
    for (var v = -reach, k = 0; v <= reach; v += rowGap, k++) {
      for (var u = -reach - (k % 2) * step / 2; u <= reach; u += step) {
        var x = cx + u * cos - v * sin, y = cy + u * sin + v * cos;
        if (x < -tw || x > W + tw || y < -tw || y > H + tw) continue;
        page.drawText(word, { x: x, y: y, size: size, font: font, color: PDF.rgb(0.55, 0.55, 0.55), opacity: 0.1, rotate: PDF.radians(ang) });
      }
    }
  }

  /* Hand the person a file under its own name (the user, 2026-10-07: "when
     saving / exporting to iphone, the pdf will become unknown.pdf"; "the
     preview save to files needs to render the correct name ... doesnt need
     the extra steps"; "Client view usually just focus on opening browser
     then go save to files"). Safari names a file after the last part of its
     address, and a blob: address has none; so the page's worker
     (js/file-sw.js, in the console and the client portal) holds the drawn
     file at {scope}file/{id}/{its name}, and a tab opened at the press opens
     there. A Preview always has its tab; on an iPhone a save opens one too
     (`tabFor()`, at the press), so Save to Files keeps the name and nothing
     is asked. A download link never points at the worker's address (Chrome
     sends a `download` past the worker), so a desk downloads the blob: under
     its name. Where no worker answers (a first visit) an iPhone's tab shows
     the blob:, and a save with no tab takes the share sheet, asking File
     ready · Save only if Safari refuses a stale press. `zh` words that
     question in Chinese on a client page. */
  var IOS = /iP(hone|od|ad)/.test(navigator.userAgent) ||
            (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  function fileOf(blob, name) {
    try { return new File([blob], name, { type: blob.type || 'application/pdf' }); }
    catch (e) { return blob; }
  }
  function anchor(href, name) {
    var a = document.createElement('a');
    a.href = href; a.download = name;
    document.body.appendChild(a); a.click(); a.remove();
  }
  function blobUrl(file) {
    var url = URL.createObjectURL(file);
    setTimeout(function () { URL.revokeObjectURL(url); }, 60000);
    return url;
  }
  function scope() {
    var p = location.pathname;
    return p.indexOf('/admin/') === 0 ? '/admin/' : p.indexOf('/client/') === 0 ? '/client/' : '';
  }
  function named(file, name) {
    var sw = navigator.serviceWorker && navigator.serviceWorker.controller;
    if (!sw || !scope() || typeof MessageChannel === 'undefined') return Promise.resolve(null);
    var id = (window.crypto && crypto.getRandomValues)
      ? Array.prototype.map.call(crypto.getRandomValues(new Uint8Array(8)), function (b) { return ('0' + b.toString(16)).slice(-2); }).join('')
      : String(Date.now());
    var path = scope() + 'file/' + id + '/' + encodeURIComponent(String(name).replace(/[\\/]+/g, '-'));
    return new Promise(function (ok) {
      var ch = new MessageChannel(), done = false;
      var end = function (v) { if (!done) { done = true; ok(v); } };
      ch.port1.onmessage = function (e) { end(e.data && e.data.ok ? path : null); };
      try { sw.postMessage({ type: 'adspace-file', path: path, name: name, blob: file }, [ch.port2]); }
      catch (e) { end(null); }
      setTimeout(function () { end(null); }, 2000);
    });
  }
  /* The installed app on a touch screen (the user, 2026-10-22: "when pdf
     generated from PWA there is no button to share to close the windows
     whatsoever"). A window it opens on its own address (the worker's file,
     a blob:) opens inside the app with no browser bar, so there is no
     Share, Done or Back; there a file goes to the share sheet instead, and
     no window is opened at the press. */
  var TOUCH = IOS || (/Android/i.test(navigator.userAgent) && navigator.maxTouchPoints > 0);
  function installed() {
    var alone = navigator.standalone === true;
    try { alone = alone || matchMedia('(display-mode: standalone)').matches; } catch (e) { /* no media queries */ }
    return TOUCH && alone;
  }
  /* A tab for a save, opened at the press: on an iPhone or iPad alone, where
     the browser's own viewer is the way to Save to Files; never in the
     installed app. */
  function tabFor() {
    if (!IOS || installed()) return null;
    try { return window.open('', '_blank'); } catch (e) { return null; }
  }
  /* A Preview's tab, opened at the press, saying what it waits on; none in
     the installed app, where the file goes to the share sheet. */
  function previewTab(zh) {
    if (installed()) return null;
    var tab = null;
    try { tab = window.open('', '_blank'); } catch (e) { tab = null; }
    if (tab) { try { tab.document.title = 'PDF'; tab.document.body.textContent = zh ? '正在生成PDF…' : 'Drawing the PDF…'; } catch (e) { /* still blank */ } }
    return tab;
  }
  /* Where the installed app has no share sheet for files: the PDF in a
     sheet over the page, with Close and Download in its foot, so the
     person always has a way back. */
  function viewer(file, name, zh) {
    var url = URL.createObjectURL(file);
    var box = document.createElement('div');
    box.className = 'sheet'; box.id = 'pdfViewSheet'; box.hidden = true;
    var e = function (t) { return String(t).replace(/[&<>"']/g, function (c) { return '&#' + c.charCodeAt(0) + ';'; }); };
    box.innerHTML = '<div class="sheet-card sheet-wide pdfview-card" role="dialog" aria-modal="true" aria-labelledby="pdfViewTitle">' +
      '<div class="sheet-head"><h3 id="pdfViewTitle">' + e(name) + '</h3>' +
      '<button class="iconbtn" type="button" data-a="x" aria-label="' + (zh ? '关闭' : 'Close') + '">' +
      '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg></button></div>' +
      '<div class="sheet-body"><iframe class="pdfview" title="' + e(name) + '" src="' + e(url) + '"></iframe></div>' +
      '<div class="sheet-foot"><button class="btn btn-primary" type="button" data-a="dl">' + (zh ? '下载' : 'Download') + '</button>' +
      '<button class="btn btn-quiet" type="button" data-a="x">' + (zh ? '关闭' : 'Close') + '</button></div></div>';
    var gone = function () { box.remove(); URL.revokeObjectURL(url); };
    Array.prototype.forEach.call(box.querySelectorAll('[data-a="x"]'), function (b) {
      b.addEventListener('click', function () { if (window.ADspaceSheet) window.ADspaceSheet.close(); else gone(); });
    });
    box.querySelector('[data-a="dl"]').addEventListener('click', function () { anchor(url, name); });
    document.body.appendChild(box);
    if (window.ADspaceSheet) window.ADspaceSheet.show(box, { opener: document.activeElement, onClose: gone });
    else box.hidden = false;
  }
  function share(file, name, zh) {
    var go = function () {
      return navigator.share({ files: [file] }).catch(function (e) {
        if (e && e.name === 'AbortError') return;
        throw e;
      });
    };
    /* In the installed app a link to the file would open it inside the app
       with no way back, so what cannot be shared is shown in the viewer. */
    var app = installed();
    var fall = function () { if (app) viewer(file, name, zh); else anchor(blobUrl(file), name); };
    return go().catch(function (e) {
      if (!(e && e.name === 'NotAllowedError')) { fall(); return; }
      if (window.ADspaceConfirm) {
        window.ADspaceConfirm.ask({ title: zh ? '文件已准备好' : 'File ready', body: name,
          go: app ? (zh ? '分享' : 'Share') : (zh ? '保存' : 'Save'), cancel: zh ? '取消' : 'Cancel' },
          function () { go().catch(fall); });
      } else fall();
    });
  }
  function save(blob, name, tab, zh) {
    var file = fileOf(blob, name);
    if (tab && !tab.closed) {
      return named(file, name).then(function (url) { tab.location.href = url || blobUrl(file); });
    }
    var app = installed();
    var shareable = (IOS || app) && navigator.share && navigator.canShare && file !== blob &&
      (function () { try { return navigator.canShare({ files: [file] }); } catch (e) { return false; } })();
    if (shareable) return share(file, name, zh);
    if (app) { viewer(file, name, zh); return Promise.resolve(); }
    anchor(blobUrl(file), name);
    return Promise.resolve();
  }
  /* Shut a tab opened at the press when there is nothing to put in it. */
  function shut(tab) { try { if (tab && !tab.closed) tab.close(); } catch (e) {} }

  /* Signing out lets go of the files this page drew for its worker, so the
     next person at this browser cannot reopen them (audit F6, 2026-10-10).
     Only this page's own scope; never a stored letter or an S3 file. */
  function forgetFiles() {
    var sc = scope();
    if (!sc || !window.caches || !caches.open) return Promise.resolve();
    return caches.open('adspace-files').then(function (c) {
      return c.keys().then(function (reqs) {
        return Promise.all(reqs.filter(function (q) {
          try { return new URL(q.url).pathname.indexOf(sc + 'file/') === 0; } catch (e) { return false; }
        }).map(function (q) { return c.delete(q); }));
      });
    }).catch(function () {});
  }

  /* The validity a new letter's terms open on: today in Malaysia plus the
     days set in Tax and terms (`quote_valid_days`), never a figure here. */
  function validLine() {
    var today = ADspaceClock.today();
    var days = Number(MON.setting('quote_valid_days', today)) || 0;
    return days > 0 ? 'This offer is valid until ' + letterDate(plusDays(today, days)) + '.' : '';
  }

  window.ADspaceDocs = {
    validLine: validLine,
    save: save, tabFor: tabFor, previewTab: previewTab, installed: installed, shut: shut, ios: IOS, forgetFiles: forgetFiles,
    issue: issue, download: download, render: render, lib: lib, list: list,
    setVoid: setVoidRpc, remove: removeRpc, KIND: KIND, fileName: fileName,
    setSigned: setSigned, verify: verify, mapOf: mapOf,
    liveDoc: liveDoc, letterState: letterState, quoteOf: quoteOf, idemKey: idemKey,
    // What js/letters.js draws with, so there is one letterhead.
    pen: pen, embedFonts: embedFonts, embedLogo: embedLogo, letterDate: letterDate, watermark: watermark,
    logoWarn: function () { return logoWarn; }
  };
})();
