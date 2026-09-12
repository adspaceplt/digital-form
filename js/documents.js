/*
 * Documents — the Letter of Intent as a PDF.
 *
 * Sales issues a Letter of Intent from a lead's record: who the client is,
 * who to bill, the deal, a statement of what the lead needs, and every
 * service line with its state and amount. The team that issues the formal
 * quotation works from it. Drawn in the
 * browser and kept as a snapshot in client_documents, so it can be
 * downloaded again exactly as issued whatever the record does afterwards.
 *
 * Numbers: AQT/INT/YYMMXXX, sequence per month.
 *
 * The layout follows the reference document: mark, title, the document's
 * facts, client and contact side by side, the deal facts, the lines, the
 * totals, a sign-off. The brand mark and font come from ADSPACE_ORG when
 * set; otherwise the wordmark and Helvetica.
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
    intent: { prefix: 'AQT/INT/', title: 'Letter of Intent', word: 'Reference', per: 'month' }
  };
  KIND.cover = KIND.intent;   // rows issued before the rename
  var STATE_WORD = { enquired: 'Enquired', quoted: 'Quoted', confirmed: 'Confirmed' };

  function pad(n) { return String(n).padStart(2, '0'); }
  function yymm(d) { return String(d.getFullYear()).slice(2) + pad(d.getMonth() + 1); }
  function yymmdd(d) { return yymm(d) + pad(d.getDate()); }
  function dayOf(s) { s = String(s || ''); return s.length === 7 ? s + '-01' : s; }
  function dateOf(s) { var d = new Date(dayOf(s).slice(0, 10) + 'T00:00:00'); return isNaN(d.getTime()) ? null : d; }
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
    var k = KIND[kind] || KIND.intent;
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
    var use = (lines || []).filter(function (l) { return !l.archived_at; });
    if (!use.length) { then({ error: 'No service lines.' }); return; }
    deal = deal || {};
    var counted = use.filter(function (l) { return l.state === 'quoted' || l.state === 'confirmed'; });
    var subtotal = counted.reduce(function (s, l) { return s + amountOf(l); }, 0);
    var taxOn = client.sst_applies !== false;
    var tax = MON.taxOf(subtotal, client.market, taxOn);
    var doc = {
      client_id: client.id, kind: kind || 'intent',
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
    return Promise.all([fetchBytes(ORG.font), ORG.fontBold ? fetchBytes(ORG.fontBold) : null])
      .then(function (b) {
        return Promise.all([pdf.embedFont(b[0], { subset: true }), b[1] ? pdf.embedFont(b[1], { subset: true }) : null])
          .then(function (f) { return { font: f[0], bold: f[1] || f[0], custom: true }; });
      })
      .catch(std);
  }
  /* The mark is ADSPACE_ORG.logo, else the header's own mark. A failure to
     load it (most often no CORS on the file) is reported, not hidden. */
  var logoWarn = '';
  function embedLogo(pdf) {
    var url = ORG.logo || CFG.brandLogo;
    logoWarn = '';
    if (!url) return Promise.resolve(null);
    return fetchBytes(url).then(function (bytes) {
      return /\.jpe?g(\?|$)/i.test(url) ? pdf.embedJpg(bytes) : pdf.embedPng(bytes);
    }).catch(function () { delete assetCache[url]; logoWarn = 'Logo not loaded.'; return null; });
  }

  // ---- Drawing ---------------------------------------------------------------
  function render(doc) {
    var PDF = window.PDFLib;
    if (!PDF) return Promise.reject(new Error('PDF library not loaded'));
    var k = KIND[doc.kind] || KIND.intent;
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
      var b = doc.bill_to || {};
      var facts = [
        [k.word, doc.number],
        ['Date', longDate(doc.issued_at)],
        ['Prepared by', doc.issued_by || ''],
        ['Account owner', b.owner || '']
      ].filter(function (f) { return f[1]; });
      facts.forEach(function (f) { text(f[0], M, y, 9, font, mute); text(f[1], M + 110, y, 9, bold); y -= 13; });
      y -= 12;

      // Client left, contact right.
      var colR = W / 2 + 10;
      var top = y;
      var ly = y;
      text('Client', M, ly, 9, bold, mute); ly -= 13;
      text(b.legal_name || b.name || '', M, ly, 10, bold); ly -= 13;
      [b.legal_name && b.name && b.legal_name !== b.name ? b.name : '',
       b.regno ? 'Reg. no. ' + b.regno + (b.regno_old ? ' (' + b.regno_old + ')' : '') : '',
       b.tin ? 'TIN ' + b.tin : '', b.sst_no ? 'SST no. ' + b.sst_no : '']
        .concat(String(b.address || '').split(/\r?\n/))
        .filter(Boolean).forEach(function (s) { text(s, M, ly, 9, font, mute); ly -= 12; });
      var ry = top;
      text('Billing contact', colR, ry, 9, bold, mute); ry -= 13;
      text(b.contact || '', colR, ry, 10, bold); ry -= 13;
      [b.contact_role, b.phone, b.email, b.finance_email ? 'Finance: ' + b.finance_email : '']
        .filter(Boolean).forEach(function (s) { text(s, colR, ry, 9, font, mute); ry -= 12; });
      y = Math.min(ly, ry) - 18;

      // The deal, as a line of facts.
      var deal = [
        ['Source', b.source], ['Industry', b.industry],
        ['Market', (doc.market === 'SG' ? 'Singapore' : 'Malaysia') + ' · ' + MON.market(doc.market).sign],
        ['Stage', b.stage], ['SST', b.sst_applies === false ? 'Not applicable' : '8% on the subtotal']
      ].filter(function (f) { return f[1]; });
      if (deal.length) {
        var dx = M, dw = (W - 2 * M) / deal.length;
        deal.forEach(function (f) { text(f[0].toUpperCase(), dx, y, 7.5, bold, mute); text(f[1], dx, y - 12, 9); dx += dw; });
        y -= 30;
      }
      // The statement: what the lead needs, in sentences the quotation team
      // can read without the table.
      var sumOf = function (st) {
        return (doc.lines || []).filter(function (l) { return l.state === st; })
          .reduce(function (s, l) { return s + amountOf(l); }, 0);
      };
      var para = function (s, size) {
        wrap(s, W - 2 * M, size || 9.5).forEach(function (ln) { need(14); text(ln, M, y, size || 9.5); y -= 13; });
        y -= 6;
      };
      text('STATEMENT', M, y, 7.5, bold, mute); y -= 14;
      para((b.legal_name || b.name || 'The client') + (b.legal_name && b.name && b.legal_name !== b.name ? ' (' + b.name + ')' : '') +
        ' intends to engage ' + (ORG.name || 'ADSPACE PLT') + ' for the services set out below' +
        (b.contact ? ', with ' + b.contact + (b.contact_role ? ', ' + b.contact_role + ',' : '') + ' as the point of contact' : '') + '.');
      if (b.enquiry) para('Enquiry as received: ' + b.enquiry);
      (doc.lines || []).forEach(function (l) {
        var q = Number(l.qty || 0), n = Math.max(1, Number(l.tenure || 1));
        para((q % 1 ? q.toFixed(2) : String(q)) + ' x ' + l.label + (l.unit ? ', ' + l.unit.toLowerCase() : '') +
          (n > 1 ? ', ' + n + ' months' : '') + (l.start_on ? ' from ' + longDate(l.start_on) : '') +
          ' at ' + MON.money2(l.rate, doc.market) + (n > 1 || q !== 1 ? ' each' : '') + ': ' +
          MON.money2(amountOf(l), doc.market) + ' (' + (STATE_WORD[l.state] || l.state || '').toLowerCase() + ').' +
          (l.note ? ' ' + l.note : ''));
      });
      para('Confirmed lines total ' + MON.money2(sumOf('confirmed'), doc.market) + ' and quoted lines total ' +
        MON.money2(sumOf('quoted'), doc.market) + '. ' +
        (Number(doc.tax) ? 'With SST at 8% on the subtotal, the amount for the formal quotation is ' + MON.money2(doc.total, doc.market) + '.'
                         : 'SST does not apply; the amount for the formal quotation is ' + MON.money2(doc.total, doc.market) + '.'));
      y -= 4;

      // Lines.
      var cols = { desc: M, state: W - M - 250, qty: W - M - 180, unit: W - M - 100, amt: W - M };
      var descW = cols.state - cols.desc - 70;
      var head = function () {
        text('Description', cols.desc, y, 8.5, bold, mute);
        text('State', cols.state - 60, y, 8.5, bold, mute);
        right('Qty', cols.qty, y, 8.5, bold, mute); right('Unit price', cols.unit, y, 8.5, bold, mute);
        right('Amount', cols.amt, y, 8.5, bold, mute);
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
        text(STATE_WORD[l.state] || l.state || '', cols.state - 60, y, 9.5, font, l.state === 'confirmed' ? ink : mute);
        right((q % 1 ? q.toFixed(2) : String(q)) + (n > 1 ? ' x ' + n + ' mo' : ''), cols.qty, y, 9.5);
        right(MON.money2(l.rate, doc.market), cols.unit, y, 9.5);
        right(MON.money2(amountOf(l), doc.market), cols.amt, y, 9.5);
        y -= 13;
        ls.slice(1).forEach(function (s) { text(s, cols.desc, y, 9.5); y -= 13; });
        subs.forEach(function (s) { text(s, cols.desc, y, 8.5, font, mute); y -= 11; });
        y -= 6;
      });
      rule(y); y -= 18;

      // Totals, right. Confirmed and quoted are shown apart, then together.
      need(110);
      var lx = W - M - 230;
      var trow = function (label, value, strong) {
        text(label, lx, y, strong ? 10.5 : 9.5, strong ? bold : font, strong ? ink : mute);
        right(value, cols.amt, y, strong ? 10.5 : 9.5, strong ? bold : font);
        y -= 15;
      };
      trow('Confirmed', MON.money2(sumOf('confirmed'), doc.market));
      trow('Quoted', MON.money2(sumOf('quoted'), doc.market));
      trow('Subtotal', MON.money2(doc.subtotal, doc.market));
      trow(Number(doc.tax) ? 'SST Malaysia 8% on ' + MON.money2(doc.subtotal, doc.market) : 'SST not applicable',
           MON.money2(doc.tax, doc.market));
      y += 4; rule(y, lx, W - M, true); y -= 14;
      trow('Total', MON.money2(doc.total, doc.market), true);
      y -= 16;

      // Sign-off: the person who prepared it and the person who checks it.
      need(62);
      y -= 8;
      var half = (W - 2 * M - 24) / 2;
      [['Prepared by', M], ['Checked by', M + half + 24]].forEach(function (f) { rule(y, f[1], f[1] + half); text(f[0], f[1], y - 11, 8, font, mute); });
      y -= 40;
      [['Date', M], ['Date', M + half + 24]].forEach(function (f) { rule(y, f[1], f[1] + half); text(f[0], f[1], y - 11, 8, font, mute); });

      // Every page: the number bottom left, the page count top right.
      pages.forEach(function (pg, i) {
        page = pg;
        text((ORG.name || 'ADSPACE PLT') + '  ' + doc.number + '  Internal', M, 40, 8, font, mute);
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
