/*
 * Documents — quotations and invoices as PDFs.
 *
 * Drawn in the browser from a client's service lines, numbered
 * AQTYYMMDDXXX (quotation) and AINVYYMMDDXXX (invoice), and kept as a
 * snapshot in client_documents so a document can be downloaded again as it
 * was issued, whatever the lines or the rate card do afterwards.
 */
(function () {
  var API = window.ADspaceAPI;
  var db  = API && API.client;
  if (!API || !API.configured || !db) return;

  var MON = window.ADspaceMoney;
  var ORG = window.ADSPACE_ORG || {};
  var bridge = window.ADspaceAdmin || {};
  var log = bridge.log || function () {};
  var actor = bridge.actor || function () { return ''; };

  var KIND = {
    quotation: { prefix: 'AQT',  title: 'QUOTATION', states: ['quoted', 'confirmed'], word: 'Quotation' },
    invoice:   { prefix: 'AINV', title: 'INVOICE',   states: ['confirmed'],           word: 'Invoice' }
  };

  function pad(n) { return String(n).padStart(2, '0'); }
  function stamp(d) { return String(d.getFullYear()).slice(2) + pad(d.getMonth() + 1) + pad(d.getDate()); }
  function niceDate(s) {
    var d = new Date(String(s).slice(0, 10) + 'T00:00:00');
    return isNaN(d.getTime()) ? String(s) : d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
  }
  function amountOf(l) { return Number(l.qty || 0) * Number(l.rate || 0); }

  /* The next number for today: prefix, YYMMDD, then a three digit sequence
     over what has already been issued today. The unique index on number
     catches a clash and the caller retries once. */
  function nextNumber(kind, then) {
    var pre = KIND[kind].prefix + stamp(new Date());
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
    var tax = MON.taxOf(subtotal, client.market, client.sst_applies !== false);
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
        return { label: l.label, unit: l.unit || '', note: l.note || '', qty: Number(l.qty || 0), rate: Number(l.rate || 0) };
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

  function download(doc, then) {
    render(doc).then(function (bytes) {
      var blob = new Blob([bytes], { type: 'application/pdf' });
      var a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = doc.number + '.pdf';
      document.body.appendChild(a);
      a.click();
      setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 2000);
      if (then) then('');
    }, function (e) {
      if (then) then('PDF not drawn: ' + ((e && e.message) || e));
    });
  }

  // ---- Drawing ------------------------------------------------------------
  var QUOTE_TERMS = [
    'This quotation is valid for 30 days from the date above.',
    'Rates exclude 8% Service Tax (SST) unless stated. The amount payable inclusive of SST is shown above.',
    'Payment terms are net seven (7) days from the invoice date. Recurring engagements are invoiced in advance of each cycle.',
    'Advertising budget, platform charges and creator talent fees are billed separately where applicable.',
    'Subject to the ADspace service terms at go.adspace.me/svc-terms.'
  ];
  function invoiceTerms() {
    return [
      'Payment is due within seven (7) days of the invoice date.',
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
    return PDF.PDFDocument.create().then(function (pdf) {
      return Promise.all([pdf.embedFont(PDF.StandardFonts.Helvetica), pdf.embedFont(PDF.StandardFonts.HelveticaBold)])
        .then(function (fonts) {
          var font = fonts[0], bold = fonts[1];
          var ink = PDF.rgb(0.075, 0.094, 0.102), mute = PDF.rgb(0.39, 0.43, 0.44), line = PDF.rgb(0.87, 0.89, 0.89);
          var page = pdf.addPage([W, H]);
          var y = H - 56;
          var safe = function (s) { return String(s == null ? '' : s).replace(/[^\x20-\x7E -ÿ]/g, '-'); };
          var text = function (s, x, yy, size, f, color) {
            page.drawText(safe(s), { x: x, y: yy, size: size || 10, font: f || font, color: color || ink });
          };
          var width = function (s, size, f) { return (f || font).widthOfTextAtSize(safe(s), size || 10); };
          var right = function (s, xr, yy, size, f, color) { text(s, xr - width(s, size, f), yy, size, f, color); };
          var rule = function (yy, x1, x2) {
            page.drawLine({ start: { x: x1 || M, y: yy }, end: { x: x2 || W - M, y: yy }, thickness: 0.6, color: line });
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
          var newPage = function () { page = pdf.addPage([W, H]); y = H - 60; };

          // Issuer left, document right.
          text('ADspace', M, y, 20, bold);
          right(k.title, W - M, y, 16, bold);
          var ly = y - 16;
          [ORG.name || 'ADSPACE PLT',
           ORG.regno ? 'Reg. no. ' + ORG.regno : '', ORG.sst ? 'SST no. ' + ORG.sst : '',
           ORG.address || '', [ORG.email, ORG.phone].filter(Boolean).join('  ')]
            .filter(Boolean).forEach(function (s) { text(s, M, ly, 9, font, mute); ly -= 12; });
          var ry = y - 20;
          right(doc.number, W - M, ry, 10, bold); ry -= 13;
          right('Date ' + niceDate(doc.issued_at), W - M, ry, 9, font, mute); ry -= 13;
          right(doc.kind === 'invoice' ? 'Due 7 days from date' : 'Valid 30 days', W - M, ry, 9, font, mute); ry -= 13;
          y = Math.min(ly, ry) - 14;
          rule(y); y -= 22;

          // Bill to.
          var b = doc.bill_to || {};
          text('BILL TO', M, y, 8, bold, mute); y -= 14;
          text(b.name || '', M, y, 11, bold); y -= 14;
          [b.regno ? 'Reg. no. ' + b.regno : '', b.tin ? 'TIN ' + b.tin : ''].filter(Boolean)
            .forEach(function (s) { text(s, M, y, 9, font, mute); y -= 12; });
          String(b.address || '').split(/\r?\n/).filter(Boolean).forEach(function (s) { text(s, M, y, 9.5); y -= 12; });
          if (b.contact || b.email) { text([b.contact, b.email].filter(Boolean).join('  '), M, y, 9.5, font, mute); y -= 12; }
          y -= 14;

          // Lines.
          var cols = { no: M, desc: M + 22, qty: W - M - 200, rate: W - M - 105, amt: W - M };
          var descW = cols.qty - cols.desc - 40;
          text('#', cols.no, y, 8, bold, mute); text('DESCRIPTION', cols.desc, y, 8, bold, mute);
          right('QTY', cols.qty, y, 8, bold, mute); right('RATE', cols.rate, y, 8, bold, mute); right('AMOUNT', cols.amt, y, 8, bold, mute);
          y -= 8; rule(y); y -= 16;
          (doc.lines || []).forEach(function (l, i) {
            if (y < 170) newPage();
            var ls = wrap(l.label, descW, 9.5);
            text(String(i + 1), cols.no, y, 9.5, font, mute);
            text(ls[0] || '', cols.desc, y, 9.5);
            var q = Number(l.qty || 0);
            right(q % 1 ? q.toFixed(2) : String(q), cols.qty, y, 9.5);
            right(MON.money2(l.rate, doc.market), cols.rate, y, 9.5);
            right(MON.money2(amountOf(l), doc.market), cols.amt, y, 9.5);
            y -= 13;
            ls.slice(1).forEach(function (s) { text(s, cols.desc, y, 9.5); y -= 13; });
            var sub = [l.unit, l.note].filter(Boolean).join('  ');
            if (sub) wrap(sub, descW + 40, 8.5).forEach(function (s) { text(s, cols.desc, y, 8.5, font, mute); y -= 11; });
            y -= 5;
          });
          rule(y); y -= 18;

          // Totals.
          if (y < 150) newPage();
          var lx = W - M - 200;
          text('Subtotal', lx, y, 9.5, font, mute); right(MON.money2(doc.subtotal, doc.market), cols.amt, y, 9.5); y -= 14;
          text(Number(doc.tax) ? MON.taxLabel() : 'SST not applicable', lx, y, 9.5, font, mute);
          right(MON.money2(doc.tax, doc.market), cols.amt, y, 9.5); y -= 8;
          rule(y, lx); y -= 16;
          text('Total', lx, y, 11, bold); right(MON.money2(doc.total, doc.market), cols.amt, y, 11, bold); y -= 34;

          // Terms.
          (doc.kind === 'invoice' ? invoiceTerms() : QUOTE_TERMS).forEach(function (s) {
            if (y < 70) newPage();
            wrap(s, W - 2 * M, 8.5).forEach(function (ln) { text(ln, M, y, 8.5, font, mute); y -= 11; });
            y -= 3;
          });

          // Foot.
          text((ORG.name || 'ADSPACE PLT') + '  ' + doc.number, M, 40, 8, font, mute);
          return pdf.save();
        });
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

  window.ADspaceDocs = { issue: issue, download: download, render: render, list: list, setVoid: setVoid, KIND: KIND };
})();
