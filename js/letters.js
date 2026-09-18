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
    quote_cover: 'Quotation cover', client: 'Client letter', hr: 'HR letter', other: 'Other'
  };
  var LANG_WORD = { en: 'English', zh: 'Chinese', ms: 'Malay' };

  /* The database answers in one word; the console says what it means. */
  var WORD = {
    'no-type':        'Choose a document type.',
    'not-allowed':    'You do not have permission to do this.',
    'no-client':      'Choose a client.',
    'no-member':      'Choose a colleague.',
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
      return 'The database has not been updated yet. Re-run supabase/schema.sql, then try again.';
    }
    return m || 'The request failed.';
  }

  function call(fn, args, then) {
    db.rpc(fn, args).then(function (r) {
      if (r.error) { then(missingWord(r.error.message)); return; }
      var out = r.data || {};
      if (out.error) { then(WORD[out.error] || out.error, out); return; }
      then(null, out);
    }, function (e) { then(missingWord(e && e.message)); });
  }

  // ---- Reading ---------------------------------------------------------------
  function types(then) {
    db.from('doc_types').select('*').eq('active', true).order('position').order('name')
      .then(function (r) { then(r.data || [], r.error); }, function (e) { then([], e); });
  }
  function list(clientId, then) {
    db.from('documents').select('*').eq('client_id', clientId).order('created_at', { ascending: false })
      .then(function (r) { then(r.data || [], r.error); }, function (e) { then([], e); });
  }
  function listAll(then) {
    db.from('documents').select('*').order('created_at', { ascending: false }).limit(2000)
      .then(function (r) { then(r.data || [], r.error); }, function (e) { then([], e); });
  }
  function readBack(id, then) {
    db.from('documents').select('*').eq('id', id).single()
      .then(function (r) { then(r.data, r.error); }, function (e) { then(null, e); });
  }

  // ---- Writing ---------------------------------------------------------------
  /* a: { type, client, member, serial, issued_at, title, recipient, body,
          signatory, languages, idem }. The database builds the serial where
     none is typed, refuses one already spent, and answers the same document
     twice for the same idem key. */
  function issue(a, then) {
    call('issue_document', {
      p_type: a.type, p_client: a.client || null, p_member: a.member || null,
      p_serial: a.serial || null, p_issued_at: a.issued_at || null, p_title: a.title || null,
      p_recipient: a.recipient || {}, p_body: a.body || {}, p_signatory: a.signatory || null,
      p_languages: a.languages && a.languages.length ? a.languages : ['en'],
      p_idem: a.idem || DOCS.idemKey(),
      p_salutation: a.salutation || null
    }, function (err, out) {
      if (err) { then({ error: err }); return; }
      readBack(out.id, function (doc, e2) {
        if (e2 || !doc) { then({ ok: true, repeat: out.repeat, serial: out.serial, warn: 'Issued. The file could not be drawn.' }); return; }
        download(doc, function (warn) { then({ ok: true, repeat: out.repeat, serial: out.serial, doc: doc, warn: warn }); });
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
        if (e2 || !d2) { then({ ok: true, repeat: out.repeat, serial: out.serial, warn: 'Reissued. The file could not be drawn.' }); return; }
        download(d2, function (warn) { then({ ok: true, repeat: out.repeat, serial: out.serial, doc: d2, warn: warn }); });
      });
    });
  }
  /* A serial made elsewhere, so the verify page can answer it. */
  function addManual(a, then) {
    call('register_add', {
      p_serial: a.serial, p_family: a.family || 'other', p_kind: a.kind,
      p_issued_at: a.issued_at || null, p_recipient: a.recipient || '',
      p_client: a.client || null, p_note: a.note || null, p_file_url: a.file_url || null
    }, then);
  }
  /* A hand-added row is corrected in place; the serial never changes. */
  function updateManual(doc, a, then) {
    call('register_update', {
      p_doc: doc.id, p_kind: a.kind, p_family: a.family || 'other',
      p_issued_at: a.issued_at || null, p_recipient: a.recipient || '',
      p_client: a.client || null, p_note: a.note || null, p_file_url: a.file_url || null
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
      var key = k.trim().toLowerCase();
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
      var closeH = LH * 2 + (doc.signed ? 60 + LH * 2 : 0);
      need(closeH);
      if (String(doc.closing || '').trim()) { text(doc.closing, M, y, BODY); y -= LH; }
      text(ORG.name || 'ADSPACE PLT', M, y, BODY, bold); y -= LH;
      if (doc.signed) {
        y -= 60;
        text(String(sig.name || '').toUpperCase(), M, y, BODY, bold); y -= LH;
        if (sig.designation) { text(sig.designation, M, y, BODY, font, mute); y -= LH; }
      }

      var n = pages.length;
      var footWord = 'This is a computer-generated document. ' + (doc.signed ? '' : 'No signature required. ') +
        'Verify document authenticity: ' + (ORG.verifyUrl || 'go.adspace.me/verify');
      pages.forEach(function (pg, i) {
        pn.page = pg;
        pn.footMark(i, n);
        text(doc.serial, M, 30, 7.5, font, mute);
        centre(footWord, 56, 7.5, font, mute);
      });
      return pdf.save();
    });
  }

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
        say(DOCS.logoWarn());
      }).catch(function (e) {
        say('The file could not be drawn: ' + ((e && e.message) || e));
      });
    } catch (e) {
      say('The file could not be drawn: ' + ((e && e.message) || e));
    }
  }

  window.ADspaceLetters = {
    types: types, list: list, listAll: listAll, issue: issue, reissue: reissue, addManual: addManual, updateManual: updateManual,
    setVoid: setVoid, remove: remove, render: render, download: download,
    fileName: fileName, fill: fill, stateOf: stateOf,
    FAMILY_WORD: FAMILY_WORD, LANG_WORD: LANG_WORD, WORD: WORD
  };
})();
