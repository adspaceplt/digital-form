/* The Employment Offer and the Employment Contract as PDFs (2026-11-17,
 * release H2 step D; HR-SPEC.md decision 4 and the user's templates
 * EMP_Offer.txt and EMP_Contract.txt, word for word, the template's typos
 * put right). Drawn in the browser on the letterhead and never stored but
 * as the sealed copy: the console draws it behind the master code, the
 * candidate's page behind their emailed code.
 *
 *   ADspaceHrDocs.draw(doc, pay, opts) → Promise of { pdf, pages, fonts, PDF }
 *     doc: { kind, serial, sent_at, terms, name, signatory, signed }
 *     pay: { basic, probation }
 *     opts.draft: DRAFT (INTERNAL USE ONLY) over every page;
 *     opts.extraPages: the Record page to come (a sealed copy).
 *   ADspaceHrDocs.bytes(doc, pay, opts) → Promise of the file's bytes.
 *   ADspaceHrDocs.seal(doc, pay, record) → Promise of the sealed Blob, its
 *     `seal` { sha, pagesSha }: the signed pages drawn and hashed, then the
 *     Record of this Document appended (js/seal.js), then the whole hashed,
 *     as a quotation is sealed.
 *   ADspaceHrDocs.fileName(doc) → "ADHR-OFR2611001 Employment Offer.pdf".
 */
(function () {
  'use strict';
  var DOCS = function () { return window.ADspaceDocs; };
  var ORG = window.ADSPACE_ORG || {};
  var LH = 14.5, PARA = 14, BODY = 11, FLOOR = 76;

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
    return (doc.kind === 'contract' ? 'EMPLOYMENT CONTRACT' : 'EMPLOYMENT OFFER') + ' [POSITION: ' +
      String(t.position || '').toUpperCase() + ' (' + (TYPE[t.type] || TYPE.permanent)[1] + ')]';
  }
  function fileName(doc) {
    return String(doc.serial || 'PREVIEW').replace(/\//g, '-') + ' ' + (doc.kind === 'contract' ? 'Employment Contract' : 'Employment Offer') + '.pdf';
  }
  /* The candidate's one declaration, the contract's and their page's alike. */
  var DECLARE = 'I have read and fully understood the contents of this offer letter and contract, and I accept all the terms and conditions herein.';

  /* The contract's clauses: a heading, then its paragraphs; items read
     [a], [b] … as the template does. */
  function clauses(doc, pay) {
    var t = doc.terms || {}, type = t.type || 'permanent', months = Number(t.probation_months) || 0, D = DOCS();
    var start = t.start ? D.letterDate(t.start) : '';
    var position = String(t.position || '').toUpperCase() + ' (' + (TYPE[type] || TYPE.permanent)[1] + ')';
    var salary = pay && pay.basic ? (months && pay.probation
      ? 'The basic salary at the commencement of the employment will be ' + ringgit(pay.probation) + ' (' + rm(pay.probation) + ') per month during probationary period; ' +
        ringgit(pay.basic) + ' (' + rm(pay.basic) + ') after completion of probation, payable on or before the 7th day after each calendar month.'
      : 'The basic salary at the commencement of the employment will be ' + ringgit(pay.basic) + ' (' + rm(pay.basic) + ') per month, payable on or before the 7th day after each calendar month.')
      : 'The basic salary is stated in the copy sent to you.';
    var C = [];
    var head = function (h) { C.push({ h: h, p: [] }); };
    var para = function (s) { C[C.length - 1].p.push(s); };
    head('NATURE OF WORKS');
    para(String(t.duties || '') + ' In addition to normal duties, you may from time to time be required to render such other duties and services as may be necessary to meet the needs of the company’s business.');
    head('DATE OF COMMENCEMENT');
    para('Your employment shall commence on ' + start + '.' + (t.end ? ' This contract ends on ' + D.letterDate(t.end) + '.' : ''));
    head('WORKING HOURS');
    para('Normal hours of work are 8 hours per day for five days a week and one hour lunch break. The nature of the work may require you to extend your service beyond the normal working hours in fulfilment of your duties and responsibilities.');
    para('You will not receive overtime payments in respect of any such working time unless provided for in law or you are eligible for overtime pay under the Company’s policies or guidelines.');
    para('The Company additionally reserves its right to change or substitute your scheduled work hours or workdays/off days to meet business needs. The Company reserves the right to exclude office holiday(s) to staff depending on their workload / work schedule and/or programs.');
    head('PLACE OF EMPLOYMENT');
    para(t.place ? 'Your place of employment will be at ' + t.place + ' but this location may change from time to time.' : 'Your place of employment will be at the ADspace registered office but this location may change from time to time.');
    para('During the term of your employment, the Management reserves the right to transfer you to other location/position within the ADspace group of companies, departments, and associated companies.');
    if (months) {
      head('PROBATIONARY PERIOD');
      if (type === 'intern') para('(For “Internship” position, this is equivalent to your Internship Programme)');
      para('You are required to serve a probationary period of ' + NUM[months] + ' (' + months + ') month' + (months === 1 ? '' : 's') + ' during which time your employment may be terminated by either party giving the other FOURTEEN (14) days\' notice of termination or equivalent to FOURTEEN (14) days\' salary in lieu of the notice.');
      para('This probationary period may be extended on reasonable grounds.');
      para('You are not entitled to paid annual leave during probationary period. If you have been absent from work for more than 3 consecutive working days without prior approval or leave from the company and without valid reason, your employment with the Company will be deemed terminated.');
    }
    head('SALARY, BONUS AND ADVANCE WAGES');
    para(salary);
    para('No advance wages will be payable.');
    para('Payment of bonus and annual increment (if any) is based on your performance, the Company’s profit and the overall market/economic condition and is solely at the absolute discretion of the Company.');
    head('DEDUCTIONS');
    para('The Company reserves the right in its absolute discretion to deduct from your pay the Employee’s contribution to Employees’ Provident Fund (EPF), Social Security Organisation (SOCSO), Employment Insurance System (EIS) and any sums which the Employee may owe to the Company including, but without limitation, any overpayments or losses suffered by the Company as a result of the Employee’s negligence or breach of Company’s rules/terms.');
    if (type === 'intern' || type === 'part_time') para('As an intern or part-time employee, you will not enjoy the normal EPF, SOCSO and EIS benefits stipulated by EPF Ordinance currently enforced.');
    head('REST DAYS AND PUBLIC HOLIDAYS');
    para('You are entitled to ELEVEN (11) paid public holidays that are gazetted under the Public Holidays Ordinance and five of which, namely the National Day, Malaysia Day, the Birthday of the Yang Di-Pertuan Agong, the Birthday of Sultan of Johor and Labour Day are compulsory.');
    para('The remainder will be determined by the Company. You may refer to the Company’s internal list of public holidays for more information.');
    head('ANNUAL LEAVE');
    para('Upon confirmation as permanent employee, you are entitled to paid annual leave of:');
    para('[a] eight (8) days for every twelve (12) months of continuous service with the Company for the first two (2) years with the Company;');
    para('[b] twelve (12) days for every twelve (12) months of continuous service with the Company from the third year onwards; and');
    para('[c] sixteen (16) days for every twelve (12) months of continuous service with the Company from the sixth year onwards.');
    para('If your employment commences or terminates part way through the year, your entitlement to the annual leave during the year will be assessed on a pro-rata basis and deductions from final salary due to your termination of employment will be made in respect of the annual leaves taken in excess of entitlement.');
    para('Annual leave must be taken at times convenient to the Company and at least seven (7) days’ advance notice to take Annual Leave must be given to the Company. [No more than 7 days’ Annual Leave may be taken at any one time unless permission is being given by the Company through the Employee’s Direct Manager.]');
    para('Emergency Leave is strictly for emergency and limited to unavoidable circumstances such as family member in serious illness or funeral. Disciplinary action will be taken against those who do not have a valid reason for their emergency leave. You are required to inform your Direct Manager personally at the earliest time of the day.');
    head('SICK LEAVE');
    para('You shall, after examination by a registered medical practitioner duly appointed by the Company; or a medical officer of the General Hospital or Government Clinic, be entitled to paid sick leave of a maximum of fourteen (14) days in the aggregate in each calendar year.');
    para('The Company does not provide medical expenses reimbursements in respect of the hospitalization, dental treatments, specialists, and/or Chinese Physician treatments.');
    head('NOTIFICATION OF SICKNESS OR OTHER ABSENCE');
    para('If you are unable to attend work for any reason and the absence has not previously been authorized by the Company, you must inform the Company of the fact of your absence and the full reasons for it on each working day of absence until the Company is provided with a medical certificate, failing which you shall be deemed as absent without reason and may be subject to disciplinary action.');
    para('If you are absent from work without any reason, that shall be considered taking unpaid leave without prejudice to the Company’s right to impose disciplinary action against you.');
    head('PATERNITY / MATERNITY LEAVE');
    para('You are entitled to a paid maternity leave of 98 days or paternity leave of 7 days consecutively including the public holidays and weekends/rest days during the period of childbirth in accordance with Section 37 and Section 60FA of the Employment Act.');
    head('NOTICE OF TERMINATION');
    para('If your employment continues after the end of the probationary period, your employment with the Company may be terminated by giving the Company at least TWO (2) months’ notice or equivalent of TWO (2) months’ salary in lieu of the notice.');
    head('BREACH AND TERMINATION');
    para('This contract is breached and terminated when you are found guilty of misconduct, whether in the course of your duties or not, inconsistent with the fulfilment of the express or implied conditions of this contract, including but not limited to the following:');
    ['[a] For dishonesty particularly the misappropriation of the Company’s assets of any kind;', '[b] For stealing and/or taking goods without authorization of the Company;',
     '[c] Indecent and immoral acts during working hours;', '[d] Guilty of any criminal offences;',
     '[e] For wilful disobedience to lawful orders and instructions given by the Company and or insubordination;',
     '[f] For lack of skill which you have expressly or impliedly warrant yourself to possess;',
     '[g] For absence from work without leave from the Company or absence without any reasonable excuse.'].forEach(para);
    head('CONFLICT OF INTEREST');
    para('You must devote the whole of your time, attention and abilities during the hours of work for the Company to your duties for the Company. You may not, under any circumstances, whether directly or indirectly undertake any other duties, of whatever kind during the hours of work for the Company.');
    para('You may not without the knowledge and prior written consent of the Company engage, whether directly or indirectly, in any business or employment which could or might reasonably be considered by others to impair your ability to act at all times in the best interests of the Company.');
    para('You must not own shares in a non-listed competitor.');
    head('CONFIDENTIALITY');
    para('You must not at any time during or after your employment, in any fashion, form, or manner, either directly or indirectly divulge, disclose, or communicate to any person, firm or corporation in any manner whatsoever any information of any kind, nature or description concerning any matters affecting or relating to the business of the Company or any information concerning the business of the Company, its manner of operation, or its plans, processes, or other facts of any kind, nature, or description without regard to whether any or all of the foregoing matters would be deemed confidential, material, or important.');
    para('The parties hereby stipulate that as between them, the foregoing matters are important, material, and confidential and gravely affect the effectiveness and successful conduct of the business of the Company, and its goodwill, and that any breach of the terms of this section is a material breach of this contract.');
    head('NON-COMPETE CLAUSE');
    para('You agree that, during your employment with the Company and for a period of two (2) years following the termination of your employment, regardless of the reason for termination, you shall not, directly or indirectly, within Malaysia:');
    ['[a] Engage in or render services to any business in direct competition with the Company;',
     '[b] Solicit, divert, or appropriate, or attempt to solicit, divert, or appropriate, any customer or client of the Company with whom you had material contact during your employment;',
     '[c] Solicit, encourage, or induce any employee, consultant, or contractor of the Company to terminate or modify their relationship with the Company.'].forEach(para);
    para('This restriction shall not prevent you from working for a non-competitive organization or engaging in activities not directly related to the business of the Company.');
    head('COMPLIANCE WITH COMPANY POLICIES AND GUIDELINES');
    para('[a] Compliance with Company Policies');
    para('You agree to adhere and comply with all policies, guidelines, procedures, rules, and regulations established by the Company (collectively referred as the “Company Policies”), as may be updated or amended from time to time at the Company’s sole discretion.');
    para('[b] Duty to Stay Informed');
    para('It is your responsibility to familiarize yourself with the Company Policies and any subsequent updates or amendments. Failure to comply with the Company Policies may result in disciplinary action, up to and including termination of employment.');
    para('[c] Binding Nature');
    para('Compliance with the Company Policies is a condition of your continued employment. Any violation may constitute grounds for disciplinary measures, including but not limited to termination.');
    head('COMPENSATION');
    para('You shall be responsible to indemnify the Company for any loss or damages against the Company’s Property as a result of your wilful acts and/or negligence.');
    head('CHANGES TO THE TERMS OF EMPLOYMENT');
    para('The Company reserves the right to make reasonable changes to any of the terms and conditions of employment and will notify you in writing of such changes at the earliest opportunity and, in any event, within one month after such changes have taken effect.');
    para('Such changes will be deemed to be accepted unless you notify the Company of any objection in writing before the expiry of the notice period.');
    return { position: position, list: C };
  }

  function draw(doc, pay, opts) {
    opts = opts || {};
    var D = DOCS();
    return D.lib().then(function (PDF) {
      var pdf, fonts, logo;
      return PDF.PDFDocument.create().then(function (p) {
        pdf = p;
        return Promise.all([D.embedFonts(pdf, PDF, {}), D.embedLogo(pdf)]);
      }).then(function (got) {
        fonts = got[0]; logo = got[1];
        if (opts.seal && window.ADspaceSeal) opts.extraPages = window.ADspaceSeal.pagesFor(PDF, fonts, opts.seal);
        var font = fonts.font, bold = fonts.bold, med = fonts.med || bold;
        var pn = D.pen(PDF, fonts, logo);
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
        text('PRIVATE & CONFIDENTIAL', M, y, BODY, bold); y -= 24;
        var REFX = M + 78;
        var ref = function (label, value) { text(label, M, y, BODY); text(':', M + 72, y, BODY); text(value, REFX, y, BODY); y -= LH; };
        ref('Our Ref', doc.serial || 'PREVIEW');
        ref('Date', D.letterDate(doc.sent_at || window.ADspaceClock.today()));
        y -= 12;
        var contract = doc.kind === 'contract';
        if (!contract) { line(String(doc.name || '')); y -= LH * 0.5; }
        else { line('Dear ' + String(doc.name || '').trim() + ','); y -= LH * 0.5; }
        wrap(titleOf(doc), R - M, BODY, med).forEach(function (ln) { line(ln, med); });
        y -= LH * 0.5;

        if (!contract) {
          para('ADspace is pleased to offer you employment with ' + (ORG.name || 'ADSPACE PLT') + ', subject to the terms and conditions of the employment contract.');
          var months = Number(t.probation_months) || 0;
          var facts = [['Employment', (TYPE[t.type] || TYPE.permanent)[0]], ['Position', t.position || ''], ['Scope', t.scope || '']];
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
          para('Kindly indicate your acceptance of this offer on your application page within ' + (t.reply_days || 3) + ' day' + (Number(t.reply_days) === 1 ? '' : 's') +
            ' from the date of this letter. Please note that this is not an employment contract. A formal employment contract will be issued upon confirmation of acceptance.');
          para('Thank you.');
        } else {
          var cl = clauses(doc, pay);
          para('ADspace refers to your recent application and interviews, and is pleased to offer you employment as ' + cl.position +
            ' on the following terms and conditions:');
          cl.list.forEach(function (c) {
            y -= 4; need(LH * 3);
            line(c.h, med);
            c.p.forEach(function (s) { var m = /^\[([a-z])\] (.*)$/.exec(s); if (m) { need(LH); text('[' + m[1] + ']', M, y, BODY); para(m[2], font, M + 22); } else para(s); });
          });
          para('If the above terms and conditions are agreeable to you, please sign this contract on your application page as soon as possible.');
          para('This letter when signed by applicant will constitute a binding contract.');
        }

        // The company's closing and its signatory.
        var sig = doc.signatory || {};
        need(LH * 5);
        text('Yours sincerely,', M, y, BODY); y -= LH;
        text(ORG.name || 'ADSPACE PLT', M, y, BODY, bold); y -= LH * 1.5;
        if (sig.name) { text(sig.name, M, y, BODY, bold); y -= LH; if (sig.designation) { text(sig.designation, M, y, BODY, font, mute); y -= LH; } }
        y -= LH;

        // The candidate's part: an acceptance, or the contract's signing block.
        var s = doc.signed || null, rec = (s && s.record) || {};
        var how = function () {
          if (!s) return [];
          if (s.via === 'online') return ['Signed electronically on ' + D.letterDate(rec.at) + ', ' + window.ADspaceClock.clock(rec.at) + ' (GMT+8), confirmed by a code sent to ' + (rec.email || '') + '.',
            'IP address ' + (rec.ip || 'not recorded') + (rec.country ? ' (' + rec.country + ')' : '') + (rec.fingerprint ? ' · Document fingerprint ' + rec.fingerprint : '') + '.'];
          return ['Signed ' + (s.via === 'scan' ? 'and returned as a scan' : 'on paper') + (s.on ? ' on ' + D.letterDate(s.on) : '') + '; the signed copy is kept by ADspace.'];
        };
        need(LH * 10);
        pn.rule(y + 6); y -= 10;
        if (!contract) {
          line('ACCEPTANCE', bold);
          para(s ? 'I accept this Employment Offer.' : 'Acceptance is given on the application page.');
          if (s && s.name) { text('Name:', M, y, BODY); text(s.name, M + 72, y, BODY); y -= LH; }
        } else {
          line('For Applicant', bold);
          para(DECLARE);
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

        D.letterFoot(pn, pages, doc.serial || 'PREVIEW', 'PRIVATE & CONFIDENTIAL', opts.extraPages ? pages.length + opts.extraPages : 0);
        if (opts.draft) pages.forEach(function (pg) { D.watermark(pg, 'DRAFT (INTERNAL USE ONLY)', fonts.font); });
        D.meta(pdf, String(doc.serial || 'PREVIEW'), contract ? 'Employment Contract' : 'Employment Offer');
        return { pdf: pdf, pages: pages, fonts: fonts, logo: logo, PDF: PDF };
      });
    });
  }
  function seal(doc, pay, record) {
    var S = window.ADspaceSeal;
    if (!S) return Promise.reject(new Error('The seal tools are not loaded.'));
    var title = doc.kind === 'contract' ? 'Employment Contract' : 'Employment Offer';
    var info = { ref: doc.serial, docId: record.id, verifyUrl: 'https://digital.adspace.me/verify/?s=' + encodeURIComponent(doc.serial),
      rows: S.rows(record), sub: title + ' ' + doc.serial + ', ' + (doc.kind === 'contract' ? 'signed' : 'accepted') + ' by ' + (doc.name || '') + ' and confirmed by ' + (ORG.name || 'ADSPACE PLT') + '.' };
    var d;
    return draw(doc, pay, { seal: info }).then(function (x) {
      d = x;
      return d.pdf.save();
    }).then(S.sha256).then(function (pagesSha) {
      var n = d.pdf.getPageCount();
      info.pagesSha = pagesSha; info.signedPages = n; info.total = n + (window.ADspaceSeal.pagesFor(d.PDF, d.fonts, info));
      S.addRecord(d.pdf, d.PDF, d.fonts, d.logo, info);
      return d.pdf.save().then(function (b) {
        return S.sha256(b).then(function (sha) {
          var blob = new Blob([b], { type: 'application/pdf' });
          blob.seal = { sha: sha, pagesSha: pagesSha };
          return blob;
        });
      });
    });
  }
  function bytes(doc, pay, opts) {
    return draw(doc, pay, opts).then(function (d) { return d.pdf.save(); });
  }

  window.ADspaceHrDocs = { draw: draw, bytes: bytes, seal: seal, fileName: fileName, words: words, ringgit: ringgit, titleOf: titleOf, declare: DECLARE };
})();
