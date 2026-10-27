/*
 * Letters — the quotation cover, the letters to clients and the HR letters,
 * drawn on the same letterhead as the Letter of Offer.
 *
 * One engine, four kinds. js/documents.js owns the pen (the primitives and the
 * letterhead); this file owns what a letter says and where. A row in
 * `documents` is the whole snapshot the PDF is drawn from, so a letter is
 * redrawn exactly as issued whatever the record does afterwards; the file
 * itself is never stored.
 *
 * The page is the Word template made exact: PRIVATE & CONFIDENTIAL, Our Ref
 * and Date, the recipient, the title, the salutation, the body, the closing
 * and, where the kind is signed, a signing space over the signatory's name
 * and designation. Every page carries the reference, the page count and the
 * line naming the public page a reader verifies it on. A kind that is not
 * signed says so in that line, as the template does.
 */
(function () {
  var API = window.ADspaceAPI;
  var db  = API && API.client;
  var DOCS = window.ADspaceDocs;
  if (!API || !API.configured || !db || !DOCS) return;

  var ORG = window.ADSPACE_ORG || {};

  var FAMILY_WORD = {
    quote_cover: 'Quotation Cover', client: 'Client Letter', hr: 'HR Letter', other: 'Other'
  };
  var LANG_WORD = { en: 'English', zh: 'Chinese', ms: 'Malay' };

  /* The database answers in one word; the console says what it means. */
  var WORD = {
    'no-type':        'Choose a document type.',
    'not-allowed':    'You do not have permission to do this.',
    'no-client':      'Choose a client.',
    'no-member':      'Choose a colleague.',
    'no-supplier':    'Choose a supplier.',
    'agreement-incomplete': 'Complete the schedules: the supplier\'s legal name, the start date, the fee and at least one account.',
    'no-staff-code':  'Add an Employee ID to that colleague on the Team page first.',
    'no-signatory':   'A signatory is required.',
    'issuer-name':    'A letter is signed by a person. Set your name on the Team page, then issue it.',
    'serial-required':'A reference is required.',
    'no-client-code': 'Add a Client ID to this client before issuing a letter.',
    'serial-shape':   'A reference is 3 to 40 letters, digits, slashes, dots or dashes.',
    'serial-taken':   'That reference is already in the register.',
    'bad-family':     'That is not a kind of document.',
    'kind-required':  'Say what kind of document it is.',
    'reason-required':'Say why.',
    'confirm-mismatch':'That is not this document\'s reference.',
    'not-found':      'That document could not be found.',
    'not-manual':     'A document issued by the portal is a snapshot and is not edited.',
    'not-portal':     'Only a document issued by the portal can be reissued.',
    'not-current':    'A later version of this document already stands. Reissue that one.'
  };

  function missingWord(m) {
    m = String(m || '');
    if (/could not find|does not exist|schema cache|function public\.(issue_document|register_add|document_set_void|document_delete|serial_taken)/i.test(m)) {
      return 'This needs a database update.';
    }
    return m || 'The request failed.';
  }

  function call(fn, args, then) {
    db.rpc(fn, args).then(function (r) {
      if (r.error) { then(missingWord(r.error.message)); return; }
      var out = r.data || {};
      if (out.error) { then(WORD[out.error] || out.error, out); return; }
      then(null, out);
    }).catch(function (e) { then(missingWord(e && e.message)); });
  }

  // ---- Reading ---------------------------------------------------------------
  function types(then) {
    db.from('doc_types').select('*').eq('active', true).order('position').order('name')
      .then(function (r) { then(r.data || [], r.error); }).catch(function (e) { then([], e); });
  }
  function list(clientId, then) {
    db.from('documents').select('*').eq('client_id', clientId).order('created_at', { ascending: false })
      .then(function (r) { then(r.data || [], r.error); }).catch(function (e) { then([], e); });
  }
  /* The Letter of Offer lives in its own table, because it is not a letter of
     words but a priced snapshot: the lines, the totals and the bill-to are
     redrawn from it on Download and none of that fits `documents`. What that
     cost was a register with no record of it — the verify page answered the
     reference and the Documents section had never heard of it, so the team
     had two lists to keep in their heads. It is read here and mapped into the
     register's own row shape, so Documents is the one place every reference
     this portal has issued can be found. The table is the store; the register
     is the view over both. */
  function asOffer(d) {
    var to = d.bill_to || {};
    return {
      id: d.id,
      family: 'offer',
      kind: 'Letter of Offer',
      serial: d.number,
      client_id: d.client_id,
      issued_at: d.issued_at,
      created_at: d.created_at,
      recipient: { name: to.legal_name || to.name || '' },
      issued_by: d.issued_by,
      source: 'portal',
      voided_at: d.voided_at,
      /* A letter that was replaced reads Superseded on this list for the same
         reason a reissued register document reads Reissued: the team can see
         both versions and the word says which is which. */
      void_reason: d.voided_at ? 'Void' : (d.superseded_by ? 'Superseded' : ''),
      superseded_by: d.superseded_by,
      offer: d
    };
  }
  function listAll(then) {
    /* Two reads, and a refusal on either one is the register's refusal: a
       person who may read Letters of Offer and cannot is shown why, never a
       register quietly missing a family. Where the permission is simply not
       held the caller does not ask, so nothing is refused and no band draws. */
    var jobs = [db.from('documents').select('*').order('created_at', { ascending: false }).limit(2000)];
    if (listAll.offers !== false) {
      jobs.push(db.from('client_documents').select('*').order('created_at', { ascending: false }).limit(2000));
    }
    Promise.all(jobs).then(function (r) {
      var err = (r[0] && r[0].error) || (r[1] && r[1].error);
      if (err) { then([], err); return; }
      var rows = (r[0] && r[0].data) || [];
      var offers = ((r[1] && r[1].data) || []).map(asOffer);
      then(rows.concat(offers), null);
    }).catch(function (e) { then([], e); });
  }
  listAll.offers = true;
  function readBack(id, then) {
    db.from('documents').select('*').eq('id', id).single()
      .then(function (r) { then(r.data, r.error); }).catch(function (e) { then(null, e); });
  }

  // ---- Writing ---------------------------------------------------------------
  /* a: { type, client, member, serial, issued_at, title, recipient, body,
          signatory, languages, idem }. The database builds the serial where
     none is typed, refuses one already spent, and answers the same document
     twice for the same idem key. */
  function issue(a, then) {
    var args = {
      p_type: a.type, p_client: a.client || null, p_member: a.member || null,
      p_serial: a.serial || null, p_issued_at: a.issued_at || null, p_title: a.title || null,
      p_recipient: a.recipient || {}, p_body: a.body || {}, p_signatory: a.signatory || null,
      p_languages: a.languages && a.languages.length ? a.languages : ['en'],
      p_idem: a.idem || DOCS.idemKey(),
      p_salutation: a.salutation || null,
      p_signed: typeof a.signed === 'boolean' ? a.signed : null
    };
    /* Named only for a supplier's letter (2026-10-18), so a client's or an HR
       letter is the call it always was. */
    if (a.supplier) args.p_supplier = a.supplier;
    call('issue_document', args, function (err, out) {
      if (err) { then({ error: err }); return; }
      readBack(out.id, function (doc, e2) {
        if (e2 || !doc) { then({ ok: true, id: out.id, repeat: out.repeat, serial: out.serial, warn: 'Issued. The file could not be drawn.' }); return; }
        download(doc, function (warn) { then({ ok: true, id: out.id, repeat: out.repeat, serial: out.serial, doc: doc, warn: warn }); });
      });
    });
  }
  /* A corrected version of a document that went out: the same serial, kind
     and addressee; the earlier version voided as Reissued and kept. */
  function reissue(doc, a, then) {
    call('document_reissue', {
      p_doc: doc.id, p_issued_at: a.issued_at || null, p_title: a.title || null,
      p_recipient: a.recipient || null, p_body: a.body || null, p_signatory: a.signatory || null,
      p_languages: a.languages && a.languages.length ? a.languages : null,
      p_salutation: a.salutation || null, p_idem: a.idem || DOCS.idemKey()
    }, function (err, out) {
      if (err) { then({ error: err }); return; }
      readBack(out.id, function (d2, e2) {
        if (e2 || !d2) { then({ ok: true, id: out.id, repeat: out.repeat, serial: out.serial, warn: 'Reissued. The file could not be drawn.' }); return; }
        download(d2, function (warn) { then({ ok: true, id: out.id, repeat: out.repeat, serial: out.serial, doc: d2, warn: warn }); });
      });
    });
  }
  /* A serial made elsewhere, so the verify page can answer it. */
  function addManual(a, then) {
    call('register_add', {
      p_serial: a.serial, p_family: a.family || 'other', p_kind: a.kind,
      p_issued_at: a.issued_at || null, p_recipient: a.recipient || '',
      p_client: a.client || null, p_note: a.note || null, p_file_url: a.file_url || null,
      p_member: a.member || null, p_supplier: a.supplier || null
    }, then);
  }
  /* A hand-added row is corrected in place; the serial never changes. */
  function updateManual(doc, a, then) {
    call('register_update', {
      p_doc: doc.id, p_kind: a.kind, p_family: a.family || 'other',
      p_issued_at: a.issued_at || null, p_recipient: a.recipient || '',
      p_client: a.client || null, p_note: a.note || null, p_file_url: a.file_url || null,
      p_member: a.member || null, p_supplier: a.supplier || null
    }, then);
  }
  function setVoid(doc, reason, then) { call('document_set_void', { p_doc: doc.id, p_reason: reason }, then); }
  function remove(doc, confirmNo, reason, then) {
    call('document_delete', { p_doc: doc.id, p_confirm: confirmNo, p_reason: reason }, then);
  }

  function stateOf(d) { return d && d.voided_at ? 'void' : 'valid'; }
  function fileName(doc) { return String(doc.serial).replace(/\//g, '-') + '.pdf'; }

  /* `{first name}`, `{role}` and the rest, from what the sheet knows; a
     placeholder nothing answers stays in the text, where the person sees it. */
  function fill(text, vars) {
    return String(text || '').replace(/\{([^{}]+)\}/g, function (m, k) {
      var key = k.trim().toLowerCase().replace(/\s+/g, ' ');
      var v = vars && vars[key];
      return v == null || v === '' ? m : String(v);
    });
  }

  // ---- Drawing ---------------------------------------------------------------
  var LH = 14.5, PARA = 14, BODY = 11, FLOOR = 76;

  function paragraphs(s) {
    return String(s || '').replace(/\r/g, '').split(/\n\s*\n/).map(function (p) {
      return p.replace(/\s*\n\s*/g, ' ').trim();
    }).filter(Boolean);
  }

  function render(doc) {
    var D = window.ADspaceDocs;
    if (!D || !D.lib) return Promise.reject(new Error('The document engine (js/documents.js) is not loaded'));
    return D.lib().then(function () { return doc.body && doc.body.agreement ? drawAgreement(doc) : drawLetter(doc); });
  }
  function drawLetter(doc) {
    var PDF = window.PDFLib;
    if (!PDF) return Promise.reject(new Error('PDF library not loaded'));
    var langs = (doc.languages && doc.languages.length ? doc.languages : ['en']).filter(function (l) {
      return l === 'en' || String((doc.body || {})[l] || '').trim();
    });
    var wantsCjk = langs.indexOf('zh') > -1;
    var pdf, fonts, logo;
    return PDF.PDFDocument.create().then(function (p) {
      pdf = p;
      return Promise.all([DOCS.embedFonts(pdf, PDF, { cjk: wantsCjk }), DOCS.embedLogo(pdf)]);
    }).then(function (got) {
      fonts = got[0]; logo = got[1];
      if (wantsCjk && !fonts.cjk) {
        throw new Error('The Chinese font could not be loaded, so the Chinese block cannot be drawn. Check fontCjk in js/config.js.');
      }
      var font = fonts.font, bold = fonts.bold, med = fonts.med || bold;
      var pn = DOCS.pen(PDF, fonts, logo);
      var W = pn.W, H = pn.H, M = pn.M, R = pn.R, mute = pn.mute;
      var text = pn.text, right = pn.right, rule = pn.rule, wrap = pn.wrap, centre = pn.centre;
      var pages = [], y;
      var head = function () { y = pn.head(); };
      var newPage = function () { pn.page = pdf.addPage([W, H]); pages.push(pn.page); head(); };
      var need = function (h) { if (y - h < FLOOR) newPage(); };
      var line = function (s, f, size, color) { need(LH); text(s, M, y, size || BODY, f, color); y -= LH; };
      var para = function (s, f, size) {
        wrap(s, R - M, size || BODY, f).forEach(function (ln) { line(ln, f, size); });
        y -= PARA;
      };
      var paraCjk = function (s) {
        pn.wrapCjk(s, R - M, BODY, fonts.cjk).forEach(function (ln) {
          need(LH); pn.page.drawText(ln, { x: M, y: y, size: BODY, font: fonts.cjk, color: pn.ink }); y -= LH;
        });
        y -= PARA;
      };
      newPage();

      var rc = doc.recipient || {};
      var hr = doc.family === 'hr';

      text('PRIVATE & CONFIDENTIAL', M, y, BODY, bold); y -= 24;

      // Our Ref / Date / To / Attn, the colons in one column, every value
      // wrapping to the column it started in.
      var REFX = M + 78;
      var ref = function (label, value, f) {
        var lines = [];
        String(value || '').split(/\r?\n/).forEach(function (s) {
          if (s.trim()) lines = lines.concat(wrap(s.trim(), R - REFX, BODY, f));
        });
        if (!lines.length) return;
        need(LH * lines.length);
        text(label, M, y, BODY);
        text(':', M + 72, y, BODY);
        lines.forEach(function (ln) { text(ln, REFX, y, BODY, f); y -= LH; });
      };
      ref('Our Ref', doc.serial);
      ref('Date', DOCS.letterDate(doc.issued_at));
      if (hr) {
        /* A colleague's letter names them, their position and the staff code
           the serial is built from beside the identity number they gave. */
        ref('To', [rc.name, rc.role, [rc.staff_code, rc.ic].filter(Boolean).join(' / ')].filter(Boolean).join('\n'));
        y -= 4;
        line('TO BE OPENED BY ADDRESSEE ONLY', bold);
      } else {
        ref('To', [String(rc.name || '').toUpperCase(), rc.address].filter(Boolean).join('\n'));
        ref('Attn', rc.attn ? rc.attn + (rc.attn_role ? ', ' + rc.attn_role : '') : '');
      }
      y -= 12;

      if (String(doc.title || '').trim()) {
        wrap(String(doc.title).toUpperCase(), R - M, BODY, med).forEach(function (ln) { line(ln, med); });
        y -= LH;
      }
      if (String(doc.salutation || '').trim()) { line(doc.salutation); y -= LH; }

      /* One block per language, in the order they were ticked, a hairline
         between two. Chinese has no spaces and no Slate, so it takes the
         Chinese face and breaks by glyph. */
      var body = doc.body || {};
      langs.forEach(function (l, i) {
        /* The rule sits midway between the blocks it divides, measured on
           the ink: the last line's descent above it and the next line's
           glyph height below it. Hung 18pt over the next baseline it read
           as 27 above and 10 below. After the paragraph gap y is one line
           and a gap under the last baseline; the rule goes 10 up from
           there and the next baseline 24 down from the rule. */
        if (i) { need(38); y += 10; rule(y); y -= 24; }
        paragraphs(body[l]).forEach(function (p) { l === 'zh' ? paraCjk(p) : para(p); });
      });

      /* The closing, the company, and for a signed kind a space to sign over
         the name and the designation. Reserved together: a signature on a
         page of its own is a signature to nothing. */
      var sig = doc.signatory || {};
      /* Unsigned, the name and designation follow the company with no space
         to sign (the Issue sheet's To be signed tick, 2026-10-01). */
      var named = String(sig.name || '').trim() !== '';
      var closeH = LH * 2 + (doc.signed ? 60 : 0) + (named ? LH * 2 : 0);
      need(closeH);
      if (String(doc.closing || '').trim()) { text(doc.closing, M, y, BODY); y -= LH; }
      text(ORG.name || 'ADSPACE PLT', M, y, BODY, bold); y -= LH;
      if (doc.signed) y -= 60;
      else if (named) y -= LH * 0.5;
      if (named) {
        text(String(sig.name || '').toUpperCase(), M, y, BODY, bold); y -= LH;
        if (sig.designation) { text(sig.designation, M, y, BODY, font, mute); y -= LH; }
      }

      var n = pages.length;
      var footWord = 'This is a computer-generated document. ' + (doc.signed ? '' : 'No signature required. ') +
        'Verify this document at ' + (ORG.verifyUrl || 'digital.adspace.me/verify');
      /* One row at the foot (the user, 2026-10-06): the reference on the
         left, the page count on the right, the verify line between them,
         centred on the page where it clears both, else in the room they
         leave. The row is 7.5pt; where the longest line (an unsigned letter
         beside a long HR reference) cannot clear both, the whole row is 7pt,
         the same on every page. */
      var GAP = 12, lineW = R - M;
      var rowFits = function (z) {
        return font.widthOfTextAtSize(String(doc.serial || ''), z) + font.widthOfTextAtSize(footWord, z) +
          font.widthOfTextAtSize('Page ' + n + ' of ' + n, z) + GAP * 2 <= lineW;
      };
      var FZ = rowFits(7.5) ? 7.5 : 7;
      var refEnd = M + font.widthOfTextAtSize(String(doc.serial || ''), FZ);
      var sentW = font.widthOfTextAtSize(footWord, FZ);
      pages.forEach(function (pg, i) {
        pn.page = pg;
        pn.footMark(i, n, FZ);
        text(doc.serial, M, 30, FZ, font, mute);
        var pageStart = R - font.widthOfTextAtSize('Page ' + (i + 1) + ' of ' + n, FZ);
        var x = Math.max(W / 2 - sentW / 2, refEnd + GAP);
        x = Math.min(x, pageStart - GAP - sentW);
        text(footWord, x, 30, FZ, font, mute);
        /* A Preview is a draft, and says so over every page (the user,
           2026-10-06), as a report not yet confirmed does. */
        if (doc.draft) DOCS.watermark(pg, 'DRAFT (INTERNAL USE ONLY)', font);
      });
      /* The reference in the file's title: an email of the letter is
         checked against it (supplier-mail, as wa-send checks a quotation). */
      pdf.setTitle(String(doc.kind || 'Letter') + ' ' + String(doc.serial || ''));
      pdf.setAuthor('ADSPACE PLT');
      return pdf.save();
    });
  }

  /* The Supplier Service Agreement (2026-10-18), drawn on the letterhead as
     the Word template the team signed with: Our Ref and Date, the title,
     the clauses numbered from the type's wording (`# Heading` a clause,
     `1.` a numbered point under it, `a.` a lettered item, anything else a
     paragraph of the clause), the confirmation with a signing block for
     each party, then Schedule A (the supplier and key dates; the services
     and fees) and Schedule B (the accounts, as at the document's date) as
     tables. A point is one unit: a page breaks between points, never in
     one that fits a page. */
  function clausesOf(text) {
    var out = [], n = 0, k = 0, l = 0;
    String(text || '').replace(/\r/g, '').split(/\n\s*\n/).forEach(function (raw) {
      var p = raw.replace(/\s*\n\s*/g, ' ').trim();
      if (!p) return;
      var m;
      if ((m = /^#\s*(.+)$/.exec(p))) { n++; k = 0; l = 0; out.push({ kind: 'head', label: n + '.', text: m[1] }); }
      else if ((m = /^\d+[.)]\s+(.+)$/.exec(p))) { k++; l = 0; out.push({ kind: 'point', label: n + '.' + k, text: m[1] }); }
      else if ((m = /^[a-z][.)]\s+(.+)$/.exec(p))) { out.push({ kind: 'item', label: '(' + String.fromCharCode(97 + l++) + ')', text: m[1] }); }
      else out.push({ kind: 'para', text: p });
    });
    return out;
  }
  function dmyOf(s) {
    var d = String(s || '').slice(0, 10);
    return /^\d{4}-\d{2}-\d{2}$/.test(d) ? d.slice(8, 10) + '/' + d.slice(5, 7) + '/' + d.slice(0, 4) : '';
  }
  function drawAgreement(doc) {
    var PDF = window.PDFLib;
    if (!PDF) return Promise.reject(new Error('PDF library not loaded'));
    var a = (doc.body && doc.body.agreement) || {}, p1 = a.part1 || {}, p2 = a.part2 || {};
    var MON = window.ADspaceMoney;
    var pdf, fonts, logo;
    return PDF.PDFDocument.create().then(function (p) {
      pdf = p;
      return Promise.all([DOCS.embedFonts(pdf, PDF, {}), DOCS.embedLogo(pdf)]);
    }).then(function (got) {
      fonts = got[0]; logo = got[1];
      var font = fonts.font, bold = fonts.bold, med = fonts.med || bold;
      var pn = DOCS.pen(PDF, fonts, logo);
      var W = pn.W, H = pn.H, M = pn.M, R = pn.R, mute = pn.mute;
      var text = pn.text, wrap = pn.wrap;
      var FILL = PDF.rgb(0.949, 0.949, 0.949), EDGE = PDF.rgb(0.85, 0.85, 0.85);
      var pages = [], y;
      var newPage = function () { pn.page = pdf.addPage([W, H]); pages.push(pn.page); y = pn.head(); };
      var need = function (h) { if (y - h < FLOOR) newPage(); };
      newPage();

      text('PRIVATE & CONFIDENTIAL', M, y, BODY, bold); y -= 24;
      var REFX = M + 78;
      var ref = function (label, value) {
        text(label, M, y, BODY); text(':', M + 72, y, BODY); text(value, REFX, y, BODY); y -= LH;
      };
      ref('Our Ref', doc.serial);
      ref('Date', DOCS.letterDate(doc.issued_at));
      y -= 12;
      wrap(String(doc.title || 'Service Agreement').toUpperCase(), R - M, 13, med).forEach(function (ln) {
        need(18); pn.centre(ln, y, 13, med); y -= 18;
      });
      y -= 8;

      /* The clauses: a heading with its number, points hung from their
         number, items from their letter one step further in. */
      var IN1 = 30, IN2 = 58;
      var block = function (label, s, x, xText, f) {
        var lines = wrap(s, R - xText, BODY, f || font);
        if (lines.length * LH < FLOOR + 200) need(lines.length * LH);
        if (label) text(label, x, y, BODY, f || font);
        lines.forEach(function (ln, i) { if (i) need(LH); text(ln, xText, y, BODY, f || font); y -= LH; });
        y -= 5;
      };
      clausesOf((doc.body || {}).en).forEach(function (c) {
        if (c.kind === 'head') { y -= 6; need(LH * 3); block(c.label, c.text, M, M + IN1, med); }
        else if (c.kind === 'point') block(c.label, c.text, M, M + IN1);
        else if (c.kind === 'item') block(c.label, c.text, M + IN1, M + IN2);
        else block('', c.text, M, M + IN1);
      });

      /* The confirmation: one block a party, side by side, reserved
         together. */
      var sig = doc.signatory || {};
      var SIGH = 16 + LH + 56 + 4 + LH * 5;
      need(SIGH + 30);
      y -= 14;
      text('CONFIRMATION & ACCEPTANCE', M, y, BODY, bold); y -= LH + 2;
      var colW = (R - M - 30) / 2;
      var party = function (x, who, name, desig) {
        var yy = y;
        wrap(who, colW, BODY, bold).forEach(function (ln) { text(ln, x, yy, BODY, bold); yy -= LH; });
        yy -= 52;
        pn.page.drawLine({ start: { x: x, y: yy }, end: { x: x + colW, y: yy }, thickness: 0.6, color: pn.ink });
        yy -= LH;
        text('Company Stamp & Authorised Signature', x, yy, 9, font, mute); yy -= LH;
        [['Name', name], ['NRIC No.', ''], ['Designation', desig], ['Date', '']].forEach(function (r) {
          text(r[0] + ':', x, yy, BODY); if (r[1]) text(r[1], x + 72, yy, BODY); yy -= LH;
        });
        return yy;
      };
      var y1 = party(M, 'For and on behalf of ' + (ORG.name || 'ADSPACE PLT'), String(sig.name || '').toUpperCase(), sig.designation || '');
      var y2 = party(M + colW + 30, 'For and on behalf of ' + (p1.legal_name || 'the Supplier'), '', '');
      y = Math.min(y1, y2);

      /* A table of white cells under a shaded title row, on one grid. */
      var CELL = 10, PADX = 6, PADY = 5;
      var table = function (cols, head, rows) {
        var widths = cols.map(function (c) { return (R - M) * c; });
        var draw = function (cells, f, shade) {
          var lines = cells.map(function (c, i) {
            var out = [];
            String(c == null ? '' : c).split(/\r?\n/).forEach(function (part) { out = out.concat(wrap(part, widths[i] - PADX * 2, CELL, f)); });
            return out.length ? out : [''];
          });
          var h = Math.max.apply(null, lines.map(function (l) { return l.length; })) * (CELL + 3) + PADY * 2;
          need(h);
          var x = M;
          lines.forEach(function (l, i) {
            pn.page.drawRectangle({ x: x, y: y - h, width: widths[i], height: h, color: shade ? FILL : undefined, borderColor: EDGE, borderWidth: 0.6 });
            l.forEach(function (ln, j) { text(ln, x + PADX, y - PADY - CELL + 1 - j * (CELL + 3), CELL, f); });
            x += widths[i];
          });
          y -= h;
        };
        if (head) draw(head, bold, true);
        rows.forEach(function (r) { draw(r, font, false); });
      };
      var heading = function (s, size) { need(LH * 4); text(s, M, y, size || BODY, med); y -= (size || BODY) + 10; };

      newPage();
      heading('SCHEDULE A', 13);
      heading('Part 1: Supplier Details and Key Dates');
      table([0.36, 0.64], ['Items', 'Details'], [
        ['Agreement Date', DOCS.letterDate(doc.issued_at)],
        ['Supplier Legal Name', p1.legal_name || ''],
        ['BRN / NRIC / Passport', p1.id_no || ''],
        ['Registered Address', p1.address || ''],
        ['Contact Person (if a company)', p1.contact || ''],
        ['Start Date', p1.start ? DOCS.letterDate(p1.start) : '']
      ]);
      y -= 18;
      heading('Part 2: Services and Fees');
      table([0.36, 0.64], ['Items', 'Details'], [
        ['Platforms', p2.platforms || ''], ['Tasks', p2.tasks || ''], ['Reporting', p2.reporting || ''],
        ['Response Time', p2.response || ''], ['Spend Approval Limit', p2.spend_limit || ''],
        ['Approved Budget per Account', 'As per Schedule B'], ['Budget Tolerance', p2.tolerance || ''],
        ['Fee', p2.fee || ''], ['Assigned Clients', 'As per Schedule B']
      ]);

      newPage();
      heading('SCHEDULE B', 13);
      text('Latest update as at ' + DOCS.letterDate(a.as_at || doc.issued_at), M, y, BODY, bold); y -= LH + 4;
      String(a.notes || '').replace(/\r/g, '').split(/\n\s*\n/).forEach(function (para) {
        para = para.replace(/\s*\n\s*/g, ' ').trim();
        if (para) block('', para, M, M);
      });
      y -= 6;
      table([0.07, 0.25, 0.22, 0.18, 0.14, 0.14], ['No.', 'Client', 'Ad Account', 'Ad Spend per Month', 'Start Date', 'End Date'],
        (a.accounts || []).map(function (r, i) {
          var spend = r.spend == null || r.spend === '' ? '' : MON ? MON.money2(r.spend, r.currency === 'SGD' ? 'SG' : 'MY') : String(r.spend);
          return [String(i + 1), r.client || '', r.account || '', spend, dmyOf(r.start), dmyOf(r.end)];
        }));

      var n = pages.length;
      var footWord = 'This is a computer-generated document. Verify this document at ' + (ORG.verifyUrl || 'digital.adspace.me/verify');
      var FZ = 7.5;
      var refEnd = M + font.widthOfTextAtSize(String(doc.serial || ''), FZ);
      var sentW = font.widthOfTextAtSize(footWord, FZ);
      pages.forEach(function (pg, i) {
        pn.page = pg;
        pn.footMark(i, n, FZ);
        text(doc.serial, M, 30, FZ, font, mute);
        var pageStart = R - font.widthOfTextAtSize('Page ' + (i + 1) + ' of ' + n, FZ);
        var x = Math.min(Math.max(W / 2 - sentW / 2, refEnd + 12), pageStart - 12 - sentW);
        text(footWord, x, 30, FZ, font, mute);
        if (doc.draft) DOCS.watermark(pg, 'DRAFT (INTERNAL USE ONLY)', font);
      });
      /* The reference in the file's title, which supplier-mail checks. */
      pdf.setTitle(String(doc.kind || 'Supplier Service Agreement') + ' ' + String(doc.serial || ''));
      pdf.setAuthor('ADSPACE PLT');
      return pdf.save();
    });
  }

  function download(doc, then) {
    var said = false, tab = DOCS.tabFor();
    var say = function (w) { if (said) return; said = true; if (then) then(w); };
    try {
      render(doc).then(function (bytes) {
        DOCS.save(new Blob([bytes], { type: 'application/pdf' }), fileName(doc), tab);
        say(DOCS.logoWarn());
      }).catch(function (e) {
        DOCS.shut(tab);
        say('The file could not be drawn: ' + ((e && e.message) || e));
      });
    } catch (e) {
      DOCS.shut(tab);
      say('The file could not be drawn: ' + ((e && e.message) || e));
    }
  }

  window.ADspaceLetters = {
    types: types, list: list, listAll: listAll, issue: issue, reissue: reissue, addManual: addManual, updateManual: updateManual,
    setVoid: setVoid, remove: remove, render: render, download: download,
    fileName: fileName, fill: fill, stateOf: stateOf, clausesOf: clausesOf,
    FAMILY_WORD: FAMILY_WORD, LANG_WORD: LANG_WORD, WORD: WORD
  };
})();
