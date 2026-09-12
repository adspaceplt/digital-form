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
  var STATE_WORD = { enquired: 'Enquired', quoted: 'Quoted', confirmed: 'Confirmed' };

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
  function amountOf(l) { return Number(l.qty || 0) * Number(l.rate || 0) * Math.max(1, Number(l.tenure || 1)); }
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

  /* The next number: prefix, the period stamp, then a three digit sequence
     over what has already been issued in that period. The unique index on
     number catches a clash and the caller retries once. */
  function nextNumber(kind, then) {
    var k = KIND[kind] || KIND.offer;
    var pre = k.prefix + (k.per === 'month' ? yymm(new Date()) : yymmdd(new Date()));
    db.from('client_documents').select('number').ilike('number', pre + '%').then(function (r) {
      var used = (r.data || []).map(function (d) { return Number(String(d.number).slice(pre.length)) || 0; });
      var n = used.length ? Math.max.apply(null, used) + 1 : 1;
      then(pre + String(n).padStart(3, '0'));
    }, function () { then(pre + '001'); });
  }

  /* client: the record; contact: the billing contact (a client_contacts
     row) or null; lines: the service lines; deal: what the record knows
     that the client row does not spell out (owner, source, stage words). */
  function issue(kind, client, contact, lines, deal, then) {
    // The offer carries the quoted lines only: enquired lines are not yet
    // priced for the client and confirmed lines are already past this step.
    var use = (lines || []).filter(function (l) { return !l.archived_at && l.state === 'quoted'; });
    if (!use.length) { then({ error: 'No quoted lines.' }); return; }
    deal = deal || {};
    var subtotal = use.reduce(function (s, l) { return s + amountOf(l); }, 0);
    var taxOn = client.sst_applies !== false;
    var tax = MON.taxOf(subtotal, client.market, taxOn);
    var doc = {
      client_id: client.id, kind: kind || 'offer',
      issued_at: new Date().toISOString().slice(0, 10),
      market: client.market || 'MY',
      subtotal: subtotal, tax: tax, total: Math.round((subtotal + tax) * 100) / 100,
      bill_to: {
        name: client.name || '', legal_name: client.legal_name || '', address: client.billing_address || '',
        regno: client.company_no || '', regno_old: deal.company_no_old || client.company_no_old || '',
        tin: client.tin || '', sst_no: deal.sst_no || client.sst_no || '', sst_applies: taxOn,
        contact: contact ? (contact.name || '') : '', contact_role: contact ? (contact.role || '') : '',
        phone: contact ? (contact.phone || '') : '', email: contact ? (contact.email || '') : '',
        finance_email: deal.finance_email || client.finance_email || '',
        owner: deal.owner || '', source: deal.source || '', industry: deal.industry || '',
        stage: deal.stage || '', enquiry: deal.enquiry || ''
      },
      lines: use.map(function (l) {
        return { label: l.label, unit: l.unit || '', note: l.note || '', state: l.state || 'enquired',
                 qty: Number(l.qty || 0), rate: Number(l.rate || 0),
                 tenure: Math.max(1, Number(l.tenure || 1)), start_on: l.start_on || '', tax: taxOn };
      }),
      issued_by: actor() || null
    };
    var attempt = function (left) {
      nextNumber(doc.kind, function (number) {
        doc.number = number;
        db.from('client_documents').insert(doc).select().single().then(function (r) {
          if (r.error && left > 0 && /duplicate|unique/i.test(r.error.message)) { attempt(left - 1); return; }
          if (r.error) { then({ error: r.error.message }); return; }
          log('document.issued', client.name, number + ' · ' + MON.money2(doc.total, doc.market));
          download(r.data, function (warn) { then({ ok: true, doc: r.data, warn: warn }); });
        });
      });
    };
    attempt(1);
  }

  function fileName(doc) { return String(doc.number).replace(/\//g, '-') + '.pdf'; }

  function download(doc, then) {
    render(doc).then(function (bytes) {
      var blob = new Blob([bytes], { type: 'application/pdf' });
      var a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = fileName(doc);
      document.body.appendChild(a);
      a.click();
      setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 2000);
      if (then) then(logoWarn);
    }, function (e) {
      if (then) then('PDF not drawn: ' + ((e && e.message) || e));
    });
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
  function embedFonts(pdf, PDF) {
    var std = function () {
      return Promise.all([pdf.embedFont(PDF.StandardFonts.Helvetica), pdf.embedFont(PDF.StandardFonts.HelveticaBold)])
        .then(function (f) { return { font: f[0], bold: f[1], custom: false }; });
    };
    if (!ORG.font || !window.fontkit) return std();
    pdf.registerFontkit(window.fontkit);
    var opt = function (url) { return url ? fetchBytes(url).catch(function () { return null; }) : Promise.resolve(null); };
    return Promise.all([fetchBytes(ORG.font), opt(ORG.fontBold), opt(ORG.fontMark)])
      .then(function (b) {
        return Promise.all([pdf.embedFont(b[0], { subset: true }),
                            b[1] ? pdf.embedFont(b[1], { subset: true }) : null,
                            b[2] ? pdf.embedFont(b[2], { subset: true }) : null])
          .then(function (f) { return { font: f[0], bold: f[1] || f[0], mark: f[2] || f[1] || f[0], custom: true }; });
      })
      .catch(std);
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
    var W = 595.28, H = 841.89, M = 48;
    var pdf, fonts, logo;
    return PDF.PDFDocument.create().then(function (p) {
      pdf = p;
      return Promise.all([embedFonts(pdf, PDF), embedLogo(pdf)]);
    }).then(function (got) {
      fonts = got[0]; logo = got[1];
      var font = fonts.font, bold = fonts.bold, markFont = fonts.mark || bold;
      var ink = PDF.rgb(0.075, 0.094, 0.102), mute = PDF.rgb(0.39, 0.43, 0.44), line = PDF.rgb(0.87, 0.89, 0.89);
      var pages = [];
      var page, y;
      var safe = function (s) {
        s = String(s == null ? '' : s);
        return fonts.custom ? s : s.replace(/[^\x20-\x7E -ÿ]/g, '-');
      };
      var text = function (s, x, yy, size, f, color) {
        page.drawText(safe(s), { x: x, y: yy, size: size || 10, font: f || font, color: color || ink });
      };
      var width = function (s, size, f) { return (f || font).widthOfTextAtSize(safe(s), size || 10); };
      var right = function (s, xr, yy, size, f, color) { text(s, xr - width(s, size, f), yy, size, f, color); };
      var rule = function (yy, x1, x2, heavy) {
        page.drawLine({ start: { x: x1 || M, y: yy }, end: { x: x2 || W - M, y: yy }, thickness: heavy ? 1 : 0.6, color: heavy ? ink : line });
      };
      var wrap = function (s, max, size, f) {
        var out = [], cur = '';
        safe(s).split(/\s+/).forEach(function (w) {
          var t = cur ? cur + ' ' + w : w;
          if (width(t, size, f) > max && cur) { out.push(cur); cur = w; } else cur = t;
        });
        if (cur) out.push(cur);
        return out;
      };
      var newPage = function () { page = pdf.addPage([W, H]); pages.push(page); y = H - 56; };
      var need = function (h) { if (y - h < 64) newPage(); };
      newPage();

      // The letterhead, on every page: wordmark and registration left, the
      // monogram and how to reach the office right, in the reference's
      // positions; the monogram again bottom centre, the page count bottom
      // right. y counts down from the top of the page.
      var R = W - M, T = function (top) { return H - top; };
      var head = function () {
        text('ADspace', M, T(58), 14, markFont);
        if (ORG.regno) text('Co. Reg.  ' + ORG.regno, M, T(70), 9, font, mute);
        var ly = T(83);
        String(ORG.address || '').split(/\r?\n/).filter(Boolean).forEach(function (s) { text(s, M, ly, 11); ly -= 12.5; });
        if (logo) { var mh = 21, mw = logo.width * (mh / logo.height); page.drawImage(logo, { x: R - mw, y: T(65), width: mw, height: mh }); }
        var ry = T(92);
        [phoneWord(ORG.phone), ORG.email, ORG.website].filter(Boolean).forEach(function (s) { right(s, R, ry, 11); ry -= 12.5; });
        y = Math.min(ly, ry) - 12;
      };
      var foot = function (i, n) {
        if (logo) { var fh = 20, fw = logo.width * (fh / logo.height); page.drawImage(logo, { x: (W - fw) / 2, y: 30, width: fw, height: fh }); }
        right('Page ' + (i + 1) + ' of ' + n, R, 30, 7.5, font, mute);
      };
      var LH = 14.5, PARA = 14, BODY = 11;
      var para = function (s, f, size) {
        wrap(s, R - M, size || BODY, f).forEach(function (ln) { need(LH); text(ln, M, y, size || BODY, f); y -= LH; });
        y -= PARA;
      };
      head();

      var b = doc.bill_to || {};
      text('PRIVATE & CONFIDENTIAL', M, y, BODY, bold); y -= 27;

      // Our Ref / Date / To / Attn, the colons in one column.
      var refs = [
        ['Our Ref', doc.number], ['Date', letterDate(doc.issued_at)],
        ['To', (b.legal_name || b.name || '').toUpperCase()],
        ['Attn', b.contact ? b.contact + (b.contact_role ? ', ' + b.contact_role : '') : '']
      ].filter(function (f) { return f[1]; });
      refs.forEach(function (f) { text(f[0], M, y, BODY); text(':', M + 72, y, BODY); text(f[1], M + 78, y, BODY); y -= LH; });
      y -= 14;

      text(String(k.title).toUpperCase(), M, y, BODY, bold); y -= 29;
      text('Dear ' + (b.contact || 'Sir/Madam') + ',', M, y, BODY); y -= 29;

      // The offer: the services and fees, the total, the terms, the acceptance.
      para('Thank you for your interest in our marketing services. Further to our discussion, we are pleased to set out below the services and fees proposed for ' +
        (b.name || b.legal_name || 'your company') + '.');

      var cols = { desc: M, qty: R - 190, unit: R - 100, amt: R };
      var descW = cols.qty - cols.desc - 40;
      var thead = function () {
        text('Description', cols.desc, y, 9, bold, mute);
        right('Qty', cols.qty, y, 9, bold, mute); right('Unit price', cols.unit, y, 9, bold, mute); right('Amount', cols.amt, y, 9, bold, mute);
        y -= 7; rule(y); y -= 15;
      };
      need(60); thead();
      (doc.lines || []).forEach(function (l) {
        var ls = wrap(l.label, descW, 10);
        var sub = [periodOf(l), l.unit, l.note].filter(Boolean).join('  ');
        var subs = sub ? wrap(sub, descW + 40, 8.5) : [];
        if (y - (ls.length * 13 + subs.length * 11 + 8) < 70) { newPage(); head(); thead(); }
        var q = Number(l.qty || 0), n = Math.max(1, Number(l.tenure || 1));
        text(ls[0] || '', cols.desc, y, 10);
        right((q % 1 ? q.toFixed(2) : String(q)) + (n > 1 ? ' x ' + n + ' mo' : ''), cols.qty, y, 10);
        right(MON.money2(l.rate, doc.market), cols.unit, y, 10);
        right(MON.money2(amountOf(l), doc.market), cols.amt, y, 10);
        y -= 13;
        ls.slice(1).forEach(function (s2) { text(s2, cols.desc, y, 10); y -= 13; });
        subs.forEach(function (s2) { text(s2, cols.desc, y, 8.5, font, mute); y -= 11; });
        y -= 7;
      });
      rule(y); y -= 16;

      need(66);
      var lx = R - 230;
      var trow = function (label, value, strong) {
        text(label, lx, y, strong ? 10.5 : 10, strong ? bold : font, strong ? ink : mute);
        right(value, R, y, strong ? 10.5 : 10, strong ? bold : font);
        y -= 15;
      };
      trow('Subtotal', MON.money2(doc.subtotal, doc.market));
      trow(Number(doc.tax) ? 'SST Malaysia 8% on ' + MON.money2(doc.subtotal, doc.market) : 'SST not applicable', MON.money2(doc.tax, doc.market));
      y += 4; rule(y, lx, R, true); y -= 14;
      trow('Total', MON.money2(doc.total, doc.market), true);
      y -= 12;

      para('This offer is valid until ' + letterDate(plusDays(doc.issued_at, k.validDays)) + '.');
      para('Kindly confirm your acceptance by signing below and returning a copy of this letter to us.');

      // Closing, as the reference signs off: the sales person's name under the company.
      need(100);
      text('Yours sincerely,', M, y, BODY); y -= LH;
      text(ORG.name || 'ADSPACE PLT', M, y, BODY, bold); y -= LH;
      if (doc.issued_by) { text(doc.issued_by, M, y, BODY); y -= LH; }
      y -= 16;

      // Acceptance: the client signs this copy, on one page with the closing.
      if ((H - y) + 100 > H - 55) { newPage(); head(); }
      text('Confirmed and accepted for and on behalf of ' + (b.legal_name || b.name || '').toUpperCase(), M, y, BODY, bold); y -= 36;
      var half = (R - M - 24) / 2;
      [['Signature and company stamp', M], ['Name', M + half + 24]].forEach(function (f) { rule(y, f[1], f[1] + half); text(f[0], f[1], y - 11, 8.5, font, mute); });
      y -= 34;
      [['Designation', M], ['Date', M + half + 24]].forEach(function (f) { rule(y, f[1], f[1] + half); text(f[0], f[1], y - 11, 8.5, font, mute); });
      y -= 14;

      pages.forEach(function (pg, i) { page = pg; foot(i, pages.length); });
      return pdf.save();
    });
  }

  function list(clientId, then) {
    db.from('client_documents').select('*').eq('client_id', clientId).order('created_at', { ascending: false })
      .then(function (r) { then(r.data || [], r.error); }, function (e) { then([], e); });
  }

  function setVoid(doc, on, then) {
    db.from('client_documents').update({ voided_at: on ? new Date().toISOString() : null }).eq('id', doc.id)
      .then(function (r) {
        if (!r.error) log(on ? 'document.voided' : 'document.restored', doc.number, '');
        then(r.error);
      });
  }

  // Only a voided document can be deleted, and its number is never reused:
  // the next number counts from the highest issued, not from the count.
  function remove(doc, then) {
    if (!doc.voided_at) { then({ message: 'Void the document first.' }); return; }
    db.from('client_documents').delete().eq('id', doc.id).then(function (r) {
      if (!r.error) log('document.deleted', doc.number, '');
      then(r.error);
    });
  }

  window.ADspaceDocs = { issue: issue, download: download, render: render, list: list, setVoid: setVoid, remove: remove, KIND: KIND, fileName: fileName };
})();
