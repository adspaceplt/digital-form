/*
 * Documents — quotations and invoices as PDFs.
 *
 * Drawn in the browser from a client's service lines and kept as a snapshot
 * in client_documents, so a document can be downloaded again exactly as it
 * was issued whatever the lines or the rate card do afterwards.
 *
 * Numbers: AQT/INT/YYMMXXX for a quotation (internal, sequence per month),
 * AINVYYMMDDXXX for an invoice (sequence per day).
 *
 * The layout follows the reference invoice: title, the document's facts,
 * issuer and bill-to side by side, the amount and its date in one line, the
 * lines with qty, unit price, tax and amount, then the totals. The brand
 * mark and font come from ADSPACE_ORG when set; otherwise the wordmark and
 * Helvetica.
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
  var actor = bridge.actor || function () { return ''; };

  var KIND = {
    quotation: { prefix: 'AQT/INT/', title: 'Quotation', states: ['quoted', 'confirmed'], word: 'Quotation', per: 'month', validDays: 30 },
    invoice:   { prefix: 'AINV',     title: 'Invoice',   states: ['confirmed'],           word: 'Invoice',   per: 'day',   dueDays: 7 }
  };

  function pad(n) { return String(n).padStart(2, '0'); }
  function yymm(d) { return String(d.getFullYear()).slice(2) + pad(d.getMonth() + 1); }
  function yymmdd(d) { return yymm(d) + pad(d.getDate()); }
  function dateOf(s) { var d = new Date(String(s).slice(0, 10) + 'T00:00:00'); return isNaN(d.getTime()) ? null : d; }
  function plusDays(s, n) { var d = dateOf(s); if (!d) return ''; d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); }
  function longDate(s) {
    var d = dateOf(s);
    return d ? d.toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' }) : String(s || '');
  }
  function monthWord(ym) {
    var d = dateOf(String(ym).slice(0, 7) + '-01');
    return d ? d.toLocaleDateString('en-GB', { month: 'short', year: 'numeric' }) : String(ym || '');
  }
  function amountOf(l) { return Number(l.qty || 0) * Number(l.rate || 0) * Math.max(1, Number(l.tenure || 1)); }
  /* "Oct 2026 to Mar 2027" for a termed line, "Oct 2026" for a dated one,
     "6 months" for a term without a start. */
  function periodOf(l) {
    var n = Math.max(1, Number(l.tenure || 1));
    if (!l.start_on) return n > 1 ? n + ' months' : '';
    if (n === 1) return monthWord(l.start_on);
    var d = dateOf(String(l.start_on).slice(0, 7) + '-01');
    d.setMonth(d.getMonth() + n - 1);
    return monthWord(l.start_on) + ' to ' + monthWord(d.toISOString().slice(0, 7));
  }

  /* The next number: prefix, the period stamp, then a three digit sequence
     over what has already been issued in that period. The unique index on
     number catches a clash and the caller retries once. */
  function nextNumber(kind, then) {
    var k = KIND[kind];
    var pre = k.prefix + (k.per === 'month' ? yymm(new Date()) : yymmdd(new Date()));
    db.from('client_documents').select('number').ilike('number', pre + '%').then(function (r) {
      var used = (r.data || []).map(function (d) { return Number(String(d.number).slice(pre.length)) || 0; });
      var n = used.length ? Math.max.apply(null, used) + 1 : 1;
      then(pre + String(n).padStart(3, '0'));
    }, function () { then(pre + '001'); });
  }

  function issue(kind, client, lines, then) {
    var k = KIND[kind];
    var use = (lines || []).filter(function (l) { return k.states.indexOf(l.state) > -1; });
    if (!use.length) {
      then({ error: kind === 'invoice' ? 'No confirmed lines.' : 'No quoted or confirmed lines.' });
      return;
    }
    var subtotal = use.reduce(function (s, l) { return s + amountOf(l); }, 0);
    var taxOn = client.sst_applies !== false;
    var tax = MON.taxOf(subtotal, client.market, taxOn);
    var doc = {
      client_id: client.id, kind: kind,
      issued_at: new Date().toISOString().slice(0, 10),
      market: client.market || 'MY',
      subtotal: subtotal, tax: tax, total: Math.round((subtotal + tax) * 100) / 100,
      bill_to: {
        name: client.legal_name || client.name || '', address: client.billing_address || '',
        regno: client.company_no || '', tin: client.tin || '',
        contact: client.bill_contact || '', email: client.bill_contact_email || ''
      },
      lines: use.map(function (l) {
        return { label: l.label, unit: l.unit || '', note: l.note || '', qty: Number(l.qty || 0), rate: Number(l.rate || 0),
                 tenure: Math.max(1, Number(l.tenure || 1)), start_on: l.start_on || '', tax: taxOn };
      }),
      issued_by: actor() || null
    };
    var attempt = function (left) {
      nextNumber(kind, function (number) {
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
      if (then) then('');
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
    return Promise.all([fetchBytes(ORG.font), ORG.fontBold ? fetchBytes(ORG.fontBold) : null])
      .then(function (b) {
        return Promise.all([pdf.embedFont(b[0], { subset: true }), b[1] ? pdf.embedFont(b[1], { subset: true }) : null])
          .then(function (f) { return { font: f[0], bold: f[1] || f[0], custom: true }; });
      })
      .catch(std);
  }
  function embedLogo(pdf) {
    var url = ORG.logo || CFG.brandLogo;
    if (!url) return Promise.resolve(null);
    return fetchBytes(url).then(function (bytes) {
      return /\.jpe?g(\?|$)/i.test(url) ? pdf.embedJpg(bytes) : pdf.embedPng(bytes);
    }).catch(function () { return null; });
  }

  // ---- Drawing ---------------------------------------------------------------
  var QUOTE_TERMS = [
    'This quotation is valid until the date above.',
    'Rates exclude 8% Service Tax (SST) unless stated. The amount payable inclusive of SST is shown above.',
    'Payment terms are net seven (7) days from the invoice date. Recurring engagements are invoiced in advance of each cycle.',
    'Advertising budget, platform charges and creator talent fees are billed separately where applicable.',
    'Subject to the ADspace service terms at go.adspace.me/svc-terms.'
  ];
  function invoiceTerms() {
    return [
      'Payment is due by the date above.',
      ORG.bank ? 'Bank transfer: ' + ORG.bank : '',
      'Please quote the invoice number as the payment reference.',
      'Subject to the ADspace service terms at go.adspace.me/svc-terms.'
    ].filter(Boolean);
  }

  function render(doc) {
    var PDF = window.PDFLib;
    if (!PDF) return Promise.reject(new Error('PDF library not loaded'));
    var k = KIND[doc.kind] || KIND.quotation;
    var W = 595.28, H = 841.89, M = 48;
    var pdf, fonts, logo;
    return PDF.PDFDocument.create().then(function (p) {
      pdf = p;
      return Promise.all([embedFonts(pdf, PDF), embedLogo(pdf)]);
    }).then(function (got) {
      fonts = got[0]; logo = got[1];
      var font = fonts.font, bold = fonts.bold;
      var ink = PDF.rgb(0.075, 0.094, 0.102), mute = PDF.rgb(0.39, 0.43, 0.44), line = PDF.rgb(0.87, 0.89, 0.89);
      var pages = [];
      var page, y;
      var safe = function (s) {
        s = String(s == null ? '' : s);
        return fonts.custom ? s : s.replace(/[^\x20-\x7E -ÿ]/g, '-');
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

      // Mark, then the title under it.
      if (logo) {
        var lh = 26, lw = logo.width * (lh / logo.height);
        page.drawImage(logo, { x: M, y: y - lh + 6, width: lw, height: lh });
      } else {
        text('ADspace', M, y - 10, 20, bold);
      }
      y -= 44;
      text(k.title, M, y, 22, bold);
      y -= 30;

      // The document's facts, label and value.
      var facts = [
        [k.word + ' number', doc.number],
        ['Date of issue', longDate(doc.issued_at)],
        [doc.kind === 'invoice' ? 'Date due' : 'Valid until',
         longDate(plusDays(doc.issued_at, doc.kind === 'invoice' ? k.dueDays : k.validDays))]
      ];
      if (ORG.sst) facts.push(['SST registration', ORG.sst]);
      facts.forEach(function (f) { text(f[0], M, y, 9, font, mute); text(f[1], M + 110, y, 9, bold); y -= 13; });
      y -= 12;

      // Issuer left, bill-to right.
      var colR = W / 2 + 10;
      var top = y;
      var ly = y;
      text(ORG.name || 'ADSPACE PLT', M, ly, 10, bold); ly -= 13;
      [ORG.regno ? 'Reg. no. ' + ORG.regno : '']
        .concat(String(ORG.address || '').split(/\r?\n/), [ORG.email, ORG.phone])
        .filter(Boolean).forEach(function (s) { text(s, M, ly, 9, font, mute); ly -= 12; });
      var b = doc.bill_to || {};
      var ry = top;
      text('Bill to', colR, ry, 9, bold, mute); ry -= 13;
      text(b.name || '', colR, ry, 10, bold); ry -= 13;
      String(b.address || '').split(/\r?\n/).filter(Boolean).forEach(function (s) { text(s, colR, ry, 9, font, mute); ry -= 12; });
      [b.email, b.regno ? 'Reg. no. ' + b.regno : '', b.tin ? 'TIN ' + b.tin : '', b.contact]
        .filter(Boolean).forEach(function (s) { text(s, colR, ry, 9, font, mute); ry -= 12; });
      y = Math.min(ly, ry) - 22;

      // The amount and its date, in one line.
      var when = doc.kind === 'invoice'
        ? MON.money2(doc.total, doc.market) + ' due ' + longDate(plusDays(doc.issued_at, k.dueDays))
        : MON.money2(doc.total, doc.market) + ' valid until ' + longDate(plusDays(doc.issued_at, k.validDays));
      text(when, M, y, 15, bold);
      y -= 34;

      // Lines.
      var cols = { desc: M, qty: W - M - 250, unit: W - M - 150, tax: W - M - 90, amt: W - M };
      var descW = cols.qty - cols.desc - 50;
      var head = function () {
        text('Description', cols.desc, y, 8.5, bold, mute);
        right('Qty', cols.qty, y, 8.5, bold, mute); right('Unit price', cols.unit, y, 8.5, bold, mute);
        right('Tax', cols.tax, y, 8.5, bold, mute); right('Amount', cols.amt, y, 8.5, bold, mute);
        y -= 8; rule(y); y -= 16;
      };
      head();
      (doc.lines || []).forEach(function (l) {
        var ls = wrap(l.label, descW, 9.5);
        var sub = [periodOf(l), l.unit, l.note].filter(Boolean).join('  ');
        var subs = sub ? wrap(sub, descW + 50, 8.5) : [];
        if (y - (ls.length * 13 + subs.length * 11 + 6) < 90) { newPage(); head(); }
        var q = Number(l.qty || 0), n = Math.max(1, Number(l.tenure || 1));
        text(ls[0] || '', cols.desc, y, 9.5);
        right((q % 1 ? q.toFixed(2) : String(q)) + (n > 1 ? ' x ' + n : ''), cols.qty, y, 9.5);
        right(MON.money2(l.rate, doc.market), cols.unit, y, 9.5);
        right(l.tax === false ? '-' : '8%', cols.tax, y, 9.5);
        right(MON.money2(amountOf(l), doc.market), cols.amt, y, 9.5);
        y -= 13;
        ls.slice(1).forEach(function (s) { text(s, cols.desc, y, 9.5); y -= 13; });
        subs.forEach(function (s) { text(s, cols.desc, y, 8.5, font, mute); y -= 11; });
        y -= 6;
      });
      rule(y); y -= 18;

      // Totals, right.
      need(90);
      var lx = W - M - 230;
      var trow = function (label, value, strong) {
        text(label, lx, y, strong ? 10.5 : 9.5, strong ? bold : font, strong ? ink : mute);
        right(value, cols.amt, y, strong ? 10.5 : 9.5, strong ? bold : font);
        y -= 15;
      };
      trow('Subtotal', MON.money2(doc.subtotal, doc.market));
      trow('Total excluding tax', MON.money2(doc.subtotal, doc.market));
      trow(Number(doc.tax) ? 'SST Malaysia 8% on ' + MON.money2(doc.subtotal, doc.market) : 'SST not applicable',
           MON.money2(doc.tax, doc.market));
      y += 4; rule(y, lx, W - M, true); y -= 14;
      trow('Total', MON.money2(doc.total, doc.market), true);
      if (doc.kind === 'invoice') trow('Amount due', MON.money2(doc.total, doc.market), true);
      y -= 16;

      // Terms.
      (doc.kind === 'invoice' ? invoiceTerms() : QUOTE_TERMS).forEach(function (s) {
        need(24);
        wrap(s, W - 2 * M, 8.5).forEach(function (ln) { text(ln, M, y, 8.5, font, mute); y -= 11; });
        y -= 3;
      });

      // Acceptance, on a quotation: the client signs this copy.
      if (doc.kind !== 'invoice') {
        need(120);
        y -= 12;
        text('Accepted for and on behalf of ' + (b.name || ''), M, y, 8.5, bold, mute); y -= 44;
        var half = (W - 2 * M - 24) / 2;
        [['Signature', M], ['Date', M + half + 24]].forEach(function (f) { rule(y, f[1], f[1] + half); text(f[0], f[1], y - 11, 8, font, mute); });
        y -= 44;
        [['Name', M], ['Designation', M + half + 24]].forEach(function (f) { rule(y, f[1], f[1] + half); text(f[0], f[1], y - 11, 8, font, mute); });
      }

      // Every page: the number bottom left, the page count top right.
      pages.forEach(function (pg, i) {
        page = pg;
        text((ORG.name || 'ADSPACE PLT') + '  ' + doc.number, M, 40, 8, font, mute);
        right('Page ' + (i + 1) + ' of ' + pages.length, W - M, H - 40, 8, font, mute);
      });
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
