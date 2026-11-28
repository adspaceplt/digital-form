/* The Employment Offer and the Employment Contract as PDFs (2026-11-17,
 * release H2 step D; HR-SPEC.md decision 4 and the user's templates
 * EMP_Offer.txt and EMP_Contract.txt, word for word, the template's typos
 * put right). Drawn in the browser on the letterhead and never stored but
 * as the sealed copy: the console draws it behind the master code, the
 * candidate's page behind their emailed code.
 *
 *   ADspaceHrDocs.draw(doc, pay, opts) → Promise of { pdf, pages, fonts, PDF }
 *     doc: { kind, serial, sent_at, terms, name, signatory, signed, wording }
 *       (wording: the HR wording in force on its day, below)
 *     pay: { basic, probation }
 *     opts.draft: DRAFT (INTERNAL USE ONLY) over every page;
 *     opts.extraPages: the Record page to come (a sealed copy).
 *   ADspaceHrDocs.bytes(doc, pay, opts) → Promise of the file's bytes.
 *   ADspaceHrDocs.seal(doc, pay, record) → Promise of the sealed Blob, its
 *     `seal` { sha, pagesSha }: the signed pages drawn and hashed, then the
 *     Record of this Document appended (js/seal.js), then the whole hashed,
 *     as a quotation is sealed.
 *   ADspaceHrDocs.fileName(doc) → "ADHR-OFR2611001 Employment Offer.pdf".
 *   ADspaceHrDocs.declare(wording) → the declaration the candidate ticks;
 *   ADspaceHrDocs.say(wording, key, values) → one template's words, filled.
 */
(function () {
  'use strict';
  var AGENCY = window.ADspaceAgency || {};
  var DOCS = function () { return window.ADspaceDocs; };
  var ORG = window.ADSPACE_ORG || {};
  /* The template's body: 11pt on single lines (12.5pt), a blank line
     between paragraphs; nothing under the bottom margin (72pt). */
  var LH = 12.5, PARA = 12.5, BODY = 11, FLOOR = 76;

  var TYPE = {
    permanent: ['Permanent | Regular | Full-Time', 'FULL-TIME'],
    contract: ['Contract | Full-Time', 'CONTRACT'],
    intern: ['Internship', 'INTERNSHIP'],
    part_time: ['Part-Time', 'PART-TIME']
  };
  var ONES = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen',
    'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
  var TENS = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
  /* A whole number in words, as the template writes a salary: Three
     Thousand and Six Hundred. */
  function words(n) {
    n = Math.floor(Math.abs(Number(n) || 0));
    if (!n) return 'Zero';
    var under100 = function (x) { return x < 20 ? ONES[x] : TENS[Math.floor(x / 10)] + (x % 10 ? '-' + ONES[x % 10] : ''); };
    var under1000 = function (x) {
      var h = Math.floor(x / 100), r = x % 100;
      return [h ? ONES[h] + ' Hundred' : '', r ? under100(r) : ''].filter(Boolean).join(' and ');
    };
    var th = Math.floor(n / 1000), rest = n % 1000;
    return [th ? under1000(th) + ' Thousand' : '', rest ? under1000(rest) : ''].filter(Boolean).join(' and ');
  }
  function ringgit(n) {
    var v = Number(n) || 0, cents = Math.round(v * 100) % 100;
    return words(v) + ' Ringgit Malaysia' + (cents ? ' and ' + words(cents) + ' Sen' : '');
  }
  function rm(n) {
    var MON = window.ADspaceMoney;
    return MON && MON.money2 ? MON.money2(n, 'MY') : 'RM ' + Number(n || 0).toFixed(2);
  }
  function plain(n) { return rm(n).replace(/^RM\s*/, ''); }
  var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  var NUM = ['ZERO', 'ONE', 'TWO', 'THREE', 'FOUR', 'FIVE', 'SIX', 'SEVEN', 'EIGHT', 'NINE', 'TEN', 'ELEVEN', 'TWELVE'];
  function monthOf(day, add) {
    var p = String(day || '').split('-').map(Number);
    if (p.length < 2) return '';
    var m = p[1] - 1 + (add || 0), y = p[0] + Math.floor(m / 12);
    m = ((m % 12) + 12) % 12;
    return MONTHS[m].slice(0, 3).replace('Sep', 'Sept') + ' ' + y;
  }
  function titleOf(doc) {
    var t = doc.terms || {};
    return (doc.kind === 'contract' ? 'EMPLOYMENT CONTRACT' : 'EMPLOYMENT OFFER') + ' FOR THE POSITION OF ' +
      String(t.position || '').toUpperCase() + ' (' + (TYPE[t.type] || TYPE.permanent)[1] + ')';
  }
  function fileName(doc) {
    return String(doc.serial || 'PREVIEW').replace(/\//g, '-') + ' ' + (doc.kind === 'contract' ? 'Employment Contract' : 'Employment Offer') + '.pdf';
  }
  /* The words: the template store's HR wording in force on the day the
     document went out (release 14, 2026-11-28-hr-wording.sql; kind
     `hr-document`), handed in as `doc.wording` { key: { subject, body } }
     by `hiring_doc_wording` (the console) or `careers_doc_json` (the
     candidate's page). The order of the clauses and which apply stay here;
     every sentence is the store's. A key missing refuses the draw: no
     contract goes out short of a clause. A field with no value prints
     nothing (no field mark is left in print). */
  function words0(w, key) {
    var t = w && w[key];
    if (!t || !t.body) throw new Error(window.ADspaceWords.line.notYet);
    return t;
  }
  function say(w, key, vals) {
    var f = window.ADspaceTpl.fill(words0(w, key).body, vals || {}), out = f.text;
    f.missing.forEach(function (m) { out = out.split('{' + m + '}').join(''); });
    return out;
  }
  function paras(w, key, vals) { return say(w, key, vals).split(/\n[ \t]*\n/); }
  /* The candidate's one declaration, the contract's and their page's alike. */
  function declare(w) { return say(w, 'hr.declare'); }

  /* The contract's clauses: a heading (the template's subject), then its
     paragraphs; items read [a], [b] … as the template does. */
  function clauses(doc, pay) {
    var t = doc.terms || {}, type = t.type || 'permanent', months = Number(t.probation_months) || 0, D = DOCS(), w = doc.wording;
    var position = String(t.position || '').toUpperCase() + ' (' + (TYPE[type] || TYPE.permanent)[1] + ')';
    var vals = { 'agency name': AGENCY.trading_name, position: position, duties: String(t.duties || ''), start: t.start ? D.letterDate(t.start) : '',
      end: t.end ? D.letterDate(t.end) : '', place: t.place || '', probation: months ? NUM[months] + ' (' + months + ') month' + (months === 1 ? '' : 's') : '' };
    if (pay && pay.basic) { vals.salary = rm(pay.basic); vals['salary in words'] = ringgit(pay.basic); }
    if (pay && pay.probation) { vals['probation salary'] = rm(pay.probation); vals['probation salary in words'] = ringgit(pay.probation); }
    var C = [];
    /* A clause: its heading, the paragraphs a choice puts first (`lead`),
       then its own; `join` ends its last paragraph. */
    var clause = function (key, o) {
      o = o || {};
      var p = (o.lead || []).concat(paras(w, key, vals));
      if (o.join) p[p.length - 1] += ' ' + o.join;
      C.push({ h: words0(w, key).subject, p: p });
    };
    clause('hr.contract.nature');
    clause('hr.contract.commencement', { join: t.end ? say(w, 'hr.contract.ends', vals) : '' });
    clause('hr.contract.hours');
    clause('hr.contract.place', { lead: [say(w, t.place ? 'hr.contract.place-named' : 'hr.contract.place-office', vals)] });
    if (months) clause('hr.contract.probation', { lead: type === 'intern' ? [say(w, 'hr.contract.probation-intern', vals)] : [] });
    clause('hr.contract.salary', { lead: [say(w, pay && pay.basic ? (months && pay.probation ? 'hr.contract.salary-probation' : 'hr.contract.salary-basic') : 'hr.contract.salary-unset', vals)] });
    /* Internship and Part-time carry no statutory contributions (the user,
       2026-11-20: "intern and part time contracts, all no statutories epf,
       socso eis"); a full-time contract's deduction is unchanged. */
    clause(type === 'intern' || type === 'part_time' ? 'hr.contract.deductions-no-statutory' : 'hr.contract.deductions');
    ['rest-days', 'annual-leave', 'sick-leave', 'absence', 'parental-leave', 'notice', 'breach', 'conflict', 'confidentiality',
      'non-compete', 'policies', 'compensation', 'changes'].forEach(function (k) { clause('hr.contract.' + k); });
    return { position: position, list: C, vals: vals };
  }

  function draw(doc, pay, opts) {
    opts = opts || {};
    var D = DOCS();
    return D.lib().then(function (PDF) {
      var pdf, fonts, logo;
      return PDF.PDFDocument.create().then(function (p) {
        pdf = p;
        /* Its Document ID (VERIFY DETAILS, 2026-11-20), never a draft's. */
        return Promise.all([D.embedFonts(pdf, PDF, {}), D.embedLogo(pdf), D.codeOf ? D.codeOf('hiring', opts.draft ? null : doc.id, opts.key) : '']);
      }).then(function (got) {
        fonts = got[0]; logo = got[1];
        var code = got[2] || '';
        /* A copy sealed from this release prints on its Record page the
           Document ID every page's foot prints; one sealed before printed
           its uuid, which /verify/ still takes for a sealed copy. */
        if (opts.seal && code) opts.seal.docId = code;
        if (opts.seal && window.ADspaceSeal) opts.extraPages = window.ADspaceSeal.pagesFor(PDF, fonts, opts.seal);
        var font = fonts.font, bold = fonts.bold, med = fonts.med || bold;
        /* The contract is signed (ACL_SIGN); the offer is accepted on the
           application page (ACL_NOSIGN). */
        var pn = D.pen(PDF, fonts, logo, { kind: doc.kind === 'contract' ? 'hr.contract' : 'hr.offer', code: code });
        var W = pn.W, H = pn.H, M = pn.M, R = pn.R, mute = pn.mute, text = pn.text, wrap = pn.wrap;
        var t = doc.terms || {}, pages = [], y;
        var newPage = function () { pn.page = pdf.addPage([W, H]); pages.push(pn.page); y = pn.head(); };
        var need = function (h) { if (y - h < FLOOR) newPage(); };
        var line = function (s, f, size, color) { need(LH); text(s, M, y, size || BODY, f || font, color); y -= LH; };
        var para = function (s, f, x) {
          var lines = wrap(s, R - (x || M), BODY, f || font);
          if (lines.length * LH < 300) need(lines.length * LH);
          lines.forEach(function (ln) { need(LH); text(ln, x || M, y, BODY, f || font); y -= LH; });
          y -= PARA * 0.6;
        };
        newPage();
        y = pn.pc(y);
        y = pn.ref(y, 'Our Ref', doc.serial || 'PREVIEW');
        y = pn.ref(y, 'Date', D.refDate(doc.sent_at || window.ADspaceClock.today()));
        y -= pn.G.afterPc - pn.G.refLine;
        var contract = doc.kind === 'contract';
        if (!contract) { line(String(doc.name || ''), bold); y -= LH; }
        else { line('Dear ' + String(doc.name || '').trim() + ','); y -= LH; }
        wrap(titleOf(doc), R - M, BODY, med).forEach(function (ln) { line(ln, med, BODY, pn.strong); });
        y -= LH;

        if (!contract) {
          var wv = { 'agency name': AGENCY.trading_name };
          paras(doc.wording, 'hr.offer.lead', wv).forEach(function (s) { para(s); });
          var months = Number(t.probation_months) || 0;
          var facts = [['Employment', (TYPE[t.type] || TYPE.permanent)[0]], ['Position', t.position || ''], ['Job scope', t.scope || '']];
          if (months) facts.push(['Probation', months + ' month' + (months === 1 ? '' : 's') + ' (' + monthOf(t.start, 0) + ' to ' + monthOf(t.start, months - 1) + ')']);
          facts.push(['Commencement', t.start ? D.letterDate(t.start) : '']);
          if (t.end) facts.push(['End of contract', D.letterDate(t.end)]);
          facts.push(['Basic Salary (RM)', pay && pay.basic ? plain(pay.basic) + '/month' + (months && pay.probation ? '\n' + plain(pay.probation) + '/month during probationary period' : '') : '']);
          var LX = M + 150;
          facts.forEach(function (f) {
            var lines = [];
            String(f[1]).split('\n').forEach(function (s) { lines = lines.concat(wrap(s, R - LX, BODY, font)); });
            need(LH * lines.length + 6);
            text(f[0], M, y, BODY, med);
            lines.forEach(function (ln) { text(ln, LX, y, BODY); y -= LH; });
            y -= 6;
          });
          y -= 8;
          wv['reply days'] = (t.reply_days || 3) + ' day' + (Number(t.reply_days) === 1 ? '' : 's');
          paras(doc.wording, 'hr.offer.reply', wv).forEach(function (s) { para(s); });
        } else {
          var cl = clauses(doc, pay);
          paras(doc.wording, 'hr.contract.lead', cl.vals).forEach(function (s) { para(s); });
          cl.list.forEach(function (c) {
            y -= 4; need(LH * 3);
            line(c.h, med);
            c.p.forEach(function (s) { var m = /^\[([a-z])\] (.*)$/.exec(s); if (m) { need(LH); text('[' + m[1] + ']', M, y, BODY); para(m[2], font, M + 22); } else para(s); });
          });
          paras(doc.wording, 'hr.contract.close', cl.vals).forEach(function (s) { para(s); });
        }

        // The company's closing and its signatory.
        var sig = doc.signatory || {};
        need(LH * 5);
        text('Yours sincerely,', M, y, BODY); y -= LH;
        text(ORG.name, M, y, BODY, med, pn.strong); y -= LH * 1.5;
        if (sig.name) { text(sig.name, M, y, BODY, bold); y -= LH; if (sig.designation) { text(sig.designation, M, y, BODY, font, mute); y -= LH; } }
        y -= LH;

        // The candidate's part: an acceptance, or the contract's signing block.
        var s = doc.signed || null, rec = (s && s.record) || {};
        var how = function () {
          if (!s) return [];
          if (s.via === 'online') return ['Signed electronically on ' + D.letterDate(rec.at) + ', ' + window.ADspaceClock.clock(rec.at) + ' (GMT+8), confirmed by a code sent to ' + (rec.email || '') + '.',
            'IP address ' + (rec.ip || 'not recorded') + (rec.country ? ' (' + rec.country + ')' : '') + (rec.fingerprint ? ' · Document fingerprint ' + rec.fingerprint : '') + '.'];
          return ['Signed ' + (s.via === 'scan' ? 'and returned as a scan' : 'on paper') + (s.on ? ' on ' + D.letterDate(s.on) : '') + '; the signed copy is kept by ' + AGENCY.trading_name + '.'];
        };
        need(LH * 10);
        pn.rule(y + 6); y -= 10;
        if (!contract) {
          line('ACCEPTANCE', bold);
          paras(doc.wording, s ? 'hr.offer.accepted' : 'hr.offer.pending').forEach(function (x) { para(x); });
          if (s && s.name) { text('Name:', M, y, BODY); text(s.name, M + 72, y, BODY); y -= LH; }
        } else {
          line('For Applicant', bold);
          para(declare(doc.wording));
          var boxH = 64, boxW = 220;
          need(boxH + LH * 4);
          text('Signatory:', M, y, BODY);
          pn.page.drawRectangle({ x: M + 72, y: y - boxH + 10, width: boxW, height: boxH, borderColor: PDF.rgb(0.85, 0.85, 0.85), borderWidth: 0.6 });
          if (s && s.signature && /^[MLQCZmlqcz0-9 .,-]+$/.test(s.signature)) {
            var sc = Math.min((boxW - 16) / 300, (boxH - 8) / 100);
            try { pn.page.drawSvgPath(s.signature, { x: M + 72 + (boxW - 300 * sc) / 2, y: y + 6, scale: sc, borderColor: pn.ink, borderWidth: 1.6 / sc }); } catch (e) { /* the box stays as signed below */ }
          }
          y -= boxH + 4;
          [['Print Name:', s ? s.name || '' : ''], ['NRIC or Passport Number:', s ? s.id_no || '' : ''], ['Date:', s && (rec.at || s.on) ? D.letterDate(rec.at || s.on) : '']].forEach(function (r) {
            text(r[0], M, y, BODY); if (r[1]) text(r[1], M + 140, y, BODY); y -= LH;
          });
        }
        how().forEach(function (h) { wrap(h, R - M, 8.5, font).forEach(function (ln) { need(11); text(ln, M, y, 8.5, font, mute); y -= 11; }); });

        D.letterFoot(pn, pages, doc.serial || 'PREVIEW', '', opts.extraPages ? pages.length + opts.extraPages : 0);
        if (opts.draft) pages.forEach(function (pg) { D.watermark(pg, 'DRAFT (INTERNAL USE ONLY)', fonts.font); });
        D.meta(pdf, String(doc.serial || 'PREVIEW'), contract ? 'Employment Contract' : 'Employment Offer');
        return { pdf: pdf, pages: pages, fonts: fonts, logo: logo, PDF: PDF };
      });
    });
  }
  function seal(doc, pay, record) {
    var S = window.ADspaceSeal;
    if (!S) return Promise.reject(new Error(window.ADspaceWords.line.pdfLib));
    var title = doc.kind === 'contract' ? 'Employment Contract' : 'Employment Offer';
    var info = { ref: doc.serial, docId: record.id, kind: doc.kind === 'contract' ? 'hr.contract' : 'hr.offer', verifyUrl: window.ADSPACE_CONFIG.verify.page + '?s=' + encodeURIComponent(doc.serial),
      rows: S.rows(record), sub: title + ' ' + doc.serial + ', ' + (doc.kind === 'contract' ? 'signed' : 'accepted') + ' by ' + (doc.name || '') + ' and confirmed by ' + ORG.name + '.' };
    var d;
    return draw(doc, pay, { seal: info }).then(function (x) {
      d = x;
      return d.pdf.save();
    }).then(S.sha256).then(function (pagesSha) {
      var n = d.pdf.getPageCount();
      info.pagesSha = pagesSha; info.signedPages = n; info.total = n + (window.ADspaceSeal.pagesFor(d.PDF, d.fonts, info));
      S.addRecord(d.pdf, d.PDF, d.fonts, d.logo, info);
      return d.pdf.save().then(S.finish).then(function (f) {
        var blob = new Blob([f.bytes], { type: 'application/pdf' });
        blob.seal = { sha: f.sha, pagesSha: pagesSha };
        return blob;
      });
    });
  }
  function bytes(doc, pay, opts) {
    return draw(doc, pay, opts).then(function (d) { return d.pdf.save(); });
  }

  window.ADspaceHrDocs = { draw: draw, bytes: bytes, seal: seal, fileName: fileName, words: words, ringgit: ringgit, titleOf: titleOf, declare: declare, say: say };
})();
