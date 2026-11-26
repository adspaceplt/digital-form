/* A signed document's seal and record (SIGNED DOCUMENT SEAL, 2026-11-17;
 * digital-form-tests specs/SEAL-SPEC.md, decisions 1 to 5).
 *
 * One mechanism for every document a client or candidate signs: quotations
 * first, the Employment Offer and Contract after. It holds
 *   - `device()`: the device as the browser reports it (browser, system,
 *     screen, time zone, language); a browser never gives a MAC address;
 *   - `sha256(bytes)`: a file's hash, in the browser;
 *   - `pagesFor` / `addRecord`: the Record of this Document, the sealed
 *     file's last page, in the letterhead's own type and inks: the Document
 *     ID, the SHA-256 of the signed pages, a QR code of the verify page, and
 *     every step to the second, one face at one size;
 *   - `rows(rec)`: the record's steps as the PDF and the console say them;
 *   - `panel(rec)`: the console's reading of the record.
 * A file cannot print its own hash: the signed pages are drawn and hashed
 * first, that hash is printed on the Record page appended after them, and
 * the whole file's hash is stored beside it for /verify/'s file check.
 */
(function () {
  'use strict';
  var esc = function (s) { return window.ADspaceWords && window.ADspaceWords.esc ? window.ADspaceWords.esc(s) : String(s == null ? '' : s); };
  var C = function () { return window.ADspaceClock; };

  // ---- The device, as the browser reports it -------------------------------
  function browserOf(ua) {
    var m;
    if ((m = /Edg(?:e|A|iOS)?\/(\d+)/.exec(ua))) return 'Edge ' + m[1];
    if ((m = /OPR\/(\d+)/.exec(ua))) return 'Opera ' + m[1];
    if ((m = /SamsungBrowser\/(\d+)/.exec(ua))) return 'Samsung Internet ' + m[1];
    if ((m = /(?:Firefox|FxiOS)\/(\d+)/.exec(ua))) return 'Firefox ' + m[1];
    if ((m = /(?:Chrome|CriOS)\/(\d+)/.exec(ua))) return 'Chrome ' + m[1];
    if ((m = /Version\/(\d+)(?:\.\d+)?.*Safari/.exec(ua))) return 'Safari ' + m[1];
    return '';
  }
  function systemOf(ua) {
    var m;
    if ((m = /(?:iPhone|iPad|iPod).*? OS (\d+)/.exec(ua))) return (/iPad/.test(ua) ? 'iPadOS ' : 'iOS ') + m[1];
    if ((m = /Android (\d+)/.exec(ua))) return 'Android ' + m[1];
    if ((m = /Mac OS X (\d+)[._](\d+)/.exec(ua))) return 'macOS ' + (m[1] === '10' && Number(m[2]) >= 15 ? '10.' + m[2] : m[1] === '10' ? '10.' + m[2] : m[1]);
    if (/Windows NT 10/.test(ua)) return 'Windows 10 or 11';
    if ((m = /Windows NT (\d+\.\d+)/.exec(ua))) return 'Windows NT ' + m[1];
    if (/CrOS/.test(ua)) return 'ChromeOS';
    if (/Linux/.test(ua)) return 'Linux';
    return '';
  }
  function device() {
    var ua = String((navigator && navigator.userAgent) || '');
    var b = browserOf(ua), s = systemOf(ua);
    var parts = [b && s ? b + ' on ' + s : b || s || 'Browser not identified'];
    try { if (screen && screen.width) parts.push(screen.width + '×' + screen.height); } catch (e) {}
    try { var tz = Intl.DateTimeFormat().resolvedOptions().timeZone; if (tz) parts.push(tz); } catch (e) {}
    if (navigator && navigator.language) parts.push(navigator.language);
    return parts.join(' · ').slice(0, 200);
  }

  // ---- A file's hash --------------------------------------------------------
  function sha256(bytes) {
    var buf = bytes instanceof ArrayBuffer ? bytes : bytes.buffer ? bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) : bytes;
    return crypto.subtle.digest('SHA-256', buf).then(function (d) {
      return Array.prototype.map.call(new Uint8Array(d), function (x) { return ('0' + x.toString(16)).slice(-2); }).join('');
    });
  }

  // ---- The record's words ---------------------------------------------------
  var STEP = { issued: 'Issued', sent: 'Sent', opened: 'Opened', code: 'Code sent', signed: 'Signed', submitted: 'Submitted',
    returned: 'Sent back', confirmed: 'Confirmed', stamped: 'Stamped', sealed: 'Sealed', withdrawn: 'Withdrawn', declined: 'Declined',
    voided: 'Void' };
  var VIA = { link: 'on the quotation portal', page: 'on the candidate page', whatsapp: 'on WhatsApp', email: 'by email' };
  /* Time to the second, Malaysia's (GMT+8): 17 Nov 2026, 10:42:15am. */
  function when(iso) {
    if (!iso || !C()) return '';
    return C().date(iso) + ', ' + C().clock(iso, { sec: true });
  }
  function country(code) {
    var c = String(code || '').toUpperCase();
    if (!/^[A-Z]{2}$/.test(c)) return '';
    try { return new Intl.DisplayNames(['en'], { type: 'region' }).of(c) || c; } catch (e) { return c; }
  }
  function where(st) {
    return [st.ip ? 'IP ' + st.ip : '', country(st.country), st.device || ''].filter(Boolean).join(' · ');
  }
  /* The steps the PDF prints: the first opening and the last before the
     signature stand for the rest, so the page stays short. */
  function printable(steps) {
    var signedAt = (steps.filter(function (x) { return x.step === 'signed'; })[0] || {}).at;
    var opened = steps.filter(function (x) { return x.step === 'opened'; });
    var before = opened.filter(function (x) { return !signedAt || x.at <= signedAt; });
    var keep = [opened[0], before[before.length - 1]].filter(Boolean);
    return steps.filter(function (x) { return x.step !== 'opened' || keep.indexOf(x) >= 0; });
  }
  /* A device's time zone: the day heading names GMT+8, so the line drops it. */
  var ZONE = /^(UTC|GMT([+-]\d+)?|[A-Z][A-Za-z_]+(\/[A-Za-z0-9_+-]+)+)$/;
  /* One step as the Record page's timeline says it: its Malaysian day and
     time to the second, the step's word, the rest as a sentence (who, or
     to whom a code went), and one line of where it was done: the email
     confirmed (Signed), how, the address, the country and the device. */
  function row(st) {
    var party = 'the ' + String(st.party || 'Client').toLowerCase(), by;
    /* The agency's own name (the demo's sample agency on sample data). */
    var ag = (window.ADSPACE_CONFIG || {}).agencyName || 'ADspace';
    if (st.team) by = (st.by || ag) + (st.role ? ', ' + st.role : '') + (st.by && st.by !== ag ? ', ' + ag : '');
    else by = st.step === 'signed' && st.by ? st.by + (st.role ? ', ' + st.role : '') : party;
    var rest = st.step === 'code' ? 'to ' + (st.email || '') :
      st.step === 'sent' ? [VIA[st.via] || '', 'by ' + by].filter(Boolean).join(' ') :
      st.step === 'issued' && !st.team && !st.by ? 'on the quotation portal' : 'by ' + by;
    var how = st.step === 'signed' && st.via === 'paper' ? 'Signed on paper' + (st.entered_by ? ', entered by ' + st.entered_by : '') : '';
    var dev = String(st.device || '').split(' · ').filter(function (x) { return x && !ZONE.test(x); }).join(' · ');
    var place = [st.ip || '', country(st.country), dev].filter(Boolean).join(' · ');
    return { step: st.step, word: STEP[st.step] || st.step, day: st.at && C() ? C().date(st.at) : '',
      time: st.at && C() ? C().clock(st.at, { sec: true }) : '', rest: rest,
      dev: [st.step === 'signed' && st.email ? st.email + ' confirmed' : '', how, place].filter(Boolean).join(' · '),
      key: st.step === 'signed' || st.step === 'confirmed' };
  }
  function rows(rec) { return printable(rec.steps || []).map(row); }

  // ---- The console's reading of the record -----------------------------------
  var LOCK = window.ADspaceIcons.glyph('lock', '', 'width="15" height="15"');
  function stateOf(rec) {
    if (rec.stateWord) return rec.stateWord;
    if (rec.withdrawn) return ['Withdrawn', 'is-off'];
    if (rec.seal) return ['Confirmed · sealed', 'is-ok', true];
    if (rec.confirmed) return ['Confirmed', 'is-ok'];
    if (rec.signed) return ['Signed', 'is-warn'];
    return ['Not signed', 'is-off'];
  }
  function line(st) {
    var head = STEP[st.step] || st.step, who = '', meta = [];
    if (st.step === 'issued') who = st.by ? 'by ' + st.by : 'on the quotation portal';
    else if (st.step === 'sent') { who = (VIA[st.via] || '') + (st.by ? ' by ' + st.by : ''); if (st.to) meta.push('To ' + st.to); if (st.state && st.via !== 'link') meta.push(String(st.state).replace(/^./, function (c) { return c.toUpperCase(); })); }
    else if (st.step === 'opened') { who = 'by the ' + String(st.party || 'Client').toLowerCase(); meta.push(where(st)); }
    else if (st.step === 'stamped') { who = st.by ? 'by ' + st.by : ''; if (st.note) meta.push('Stamp certificate ' + st.note); }
    else if (st.step === 'code') { meta.push('To ' + (st.email || '') + (st.in_contacts === true ? ' (in Contacts)' : st.in_contacts === false ? ' (not in Contacts)' : '')); if (where(st)) meta.push(where(st)); }
    else if (st.step === 'signed') {
      who = 'by ' + (st.by || '') + (st.role ? ', ' + st.role : '');
      if (st.via === 'paper') meta.push('On paper' + (st.entered_by ? ' · entered by ' + st.entered_by : ''));
      else { meta.push('Code confirmed' + (st.email ? ' · ' + st.email : '')); if (where(st)) meta.push(where(st)); }
    }
    else if (st.step === 'submitted') who = 'by ' + (st.by || '') + (st.to ? ' to ' + st.to : '');
    else if (st.step === 'returned') { who = 'by ' + (st.by || ''); if (st.note) meta.push(st.note); }
    else if (st.step === 'confirmed') who = 'by ' + (st.by || '') + (st.role ? ', ' + st.role : '');
    else if (st.step === 'sealed') { who = st.by ? 'by ' + st.by : ''; if (st.note) meta.push('SHA-256 ' + st.note.slice(0, 4) + '…' + st.note.slice(-4)); }
    else if (st.step === 'declined') { who = 'by the ' + String(st.party || 'Client').toLowerCase(); if (where(st)) meta.push(where(st)); }
    else if (st.by) who = 'by ' + st.by;
    if (st.note && ['issued', 'withdrawn', 'declined', 'voided'].indexOf(st.step) >= 0) meta.push(st.note);
    if (st.step === 'signed' && st.via === 'paper' && st.party) meta[0] = 'On paper or by scan' + (st.entered_by ? ' · entered by ' + st.entered_by : '');
    return '<li class="seal-step"><span class="seal-when">' + esc(when(st.at)) + '</span><span class="seal-what"><b>' + esc(head) + '</b>' +
      (who ? ' ' + esc(who) : '') + (meta.length ? '<span class="seal-meta">' + esc(meta.join(' · ')) + '</span>' : '') + '</span></li>';
  }
  /* How many times a document has been checked on /verify/ (VERIFY CHECKS
     COUNTED, 2026-11-21): a lookup that found it, once an address a day.
     Never 0 on a screen: a document nobody checked leaves the line out. */
  function checksWord(n) {
    n = Math.floor(Number(n));
    return n >= 1 ? window.ADspaceWords.line.checked(n) : '';
  }
  /* The Verify fact: the page and the reference where the copy is sealed,
     and the count under it where there is one. */
  function verifyFact(where, n, fact) {
    var said = checksWord(n);
    if (!where && !said) return '';
    return fact('Verify', (where ? esc(where) : '') + (where && said ? '<br>' : '') + (said ? '<span class="seal-checks">' + esc(said) + '</span>' : ''));
  }
  /* A document's count for its record, the team's alone (verify_checks_of):
     one read a record opened; a refusal or a missing function answers null,
     and the fact is left out. */
  function checksOf(kind, id) {
    var api = window.ADspaceAPI, db = api && api.client;
    if (!kind || !id || !db) return Promise.resolve(null);
    return Promise.resolve(db.rpc('verify_checks_of', { p_kind: kind, p_id: id })).then(function (r) {
      return r && !r.error && typeof r.data === 'number' ? r.data : null;
    }).catch(function () { return null; });
  }
  function panel(rec, verifyUrl) {
    var st = stateOf(rec), s = rec.seal;
    var fact = function (k, v) { return '<div><dt>' + esc(k) + '</dt><dd>' + v + '</dd></div>'; };
    return '<dl class="ovfacts seal-facts">' +
      fact('State', '<span class="chip-state ' + st[1] + '">' + (st[2] ? '<span class="seal-lock">' + LOCK + '</span>' : '') + esc(st[0]) + '</span>') +
      fact('Document ID', '<span class="seal-mono">' + esc(rec.id) + '</span>') +
      (s ? fact('SHA-256', '<span class="seal-mono">' + esc(s.sha) + '</span>') : '') +
      verifyFact(s && verifyUrl ? verifyUrl.replace(/^https?:\/\//, '').replace(/\?.*$/, '').replace(/\/$/, '') + ' · ' + rec.ref : '', rec.checks, fact) +
      '</dl><ol class="seal-steps" aria-label="Steps">' + (rec.steps || []).map(line).join('') + '</ol>';
  }
  /* The record as a sheet over the page (#sealSheet): o.title, o.sub,
     o.load() answering the record, o.download(btn) for the sealed copy,
     o.verifyUrl, o.opener. One sheet for every signed document. */
  var openNow = null;
  function open(o) {
    var sh = document.getElementById('sealSheet');
    if (!sh) return;
    var body = document.getElementById('sealBody'), msg = document.getElementById('sealMsg');
    document.getElementById('sealTitle').textContent = o.title || 'Record of this Document';
    document.getElementById('sealFor').textContent = o.sub || '';
    msg.textContent = ''; msg.className = 'msg';
    var x = document.getElementById('sealClose');
    if (!x.getAttribute('data-wired')) {
      x.setAttribute('data-wired', '1');
      x.addEventListener('click', function () { window.ADspaceSheet.close(); });
    }
    if (window.ADspaceState && window.ADspaceState.skeleton) window.ADspaceState.skeleton(body, 4); else body.innerHTML = '';
    var mine = openNow = {};
    window.ADspaceSheet.show(sh, { opener: o.opener || null, onClose: function () { openNow = null; } });
    var paint = function () {
      /* The count rides beside the record, never holding it up or failing it. */
      Promise.all([o.load(), o.checks ? checksOf(o.checks.kind, o.checks.id) : null]).then(function (both) {
        var rec = both[0];
        if (openNow !== mine) return;
        if (rec && both[1] != null) rec.checks = both[1];
        if (!rec || rec.error) throw new Error((rec && rec.error) || 'not-found');
        body.innerHTML = panel(rec, o.verifyUrl) + (rec.seal && o.download
          ? '<div class="seal-acts"><button class="btn btn-sm" id="sealDl" type="button">Download</button></div>' : '');
        var dl = document.getElementById('sealDl');
        if (dl) {
          if (window.ADspaceActs && window.ADspaceActs.mark) window.ADspaceActs.mark(dl);
          dl.addEventListener('click', function () { o.download(dl); });
        }
      }).catch(function () {
        if (openNow !== mine) return;
        if (window.ADspaceState && window.ADspaceState.failLine) window.ADspaceState.failLine(body, 'Record of this Document', '', paint);
        else body.textContent = 'Unable to load. Refresh the page.';
      });
    };
    paint();
  }

  // ---- The Record of this Document, the PDF's last page ---------------------
  /* A dated timeline (the user, 2026-11-21: "Sorry what i mean is to use
     this", a compact record after Apple's print design): the title and the
     Document ID on one line, the sentence, a hairline, then the steps at the
     left grouped under their Malaysian day, and the QR code with the signed
     pages' SHA-256 at the right. The template's inks alone: the words
     #515151, a step's word, the title and the Document ID #1a1a1a, the
     hairlines #cfd0d4 (`#a1a1a1` stays the head's and the foot's); nothing
     under 6pt, the verify foot's size. */
  var T = { title: 13, sub: 8, subLead: 11, id: 7, code: 9, day: 7, dayLead: 9, step: 8, lead: 10, gap: 2.5, dayGap: 3, under: 2,
    dev: 6.3, devLead: 8, side: 6, sideLead: 8, hashLead: 7, part: 3, rule: 7, rail: 12, timeW: 54, sideW: 96, colGap: 24, dot: 4 };
  /* The QR code is 32pt square (about 11.3mm; the user, 2026-11-21: "Qr
     code can go smaller"): a verify address up to 59 characters (every
     reference sealed today) is 33 modules at level M, 0.34mm each, over
     the 0.33mm a phone reads. */
  var QR = 32;
  /* A module is never under 0.34mm (0.964pt): an address too long for 33
     modules grows the code rather than shrinking what a phone reads. */
  var QR_MODULE = 0.34 / 25.4 * 72;
  /* What the QR code holds (the user, 2026-11-21: a scan passes straight
     to the details, a shared link never does): the verify address, then
     the Document ID in the fragment (`#d=`), which a browser never sends to
     a server, a log or a referrer; /verify/ takes it out of the address at
     once (js/verify.js). A copy with no Document ID holds the address
     alone. The printed caption never carries it. */
  function scanUrl(verifyUrl, docId) {
    var url = String(verifyUrl || ''), code = String(docId || '');
    if (!url || !/^[2-9A-Z]{4}-[2-9A-Z]{4}$/.test(code)) return url;
    return url.replace(/#.*$/, '') + '#d=' + code.replace('-', '');
  }
  /* A baseline in a line box of `lead` from its top. */
  function base(top, size, lead) { return top - (lead - size) / 2 - size * 0.8; }
  /* Words over lines of `max` (the first may be shorter): between words,
     else inside a word, never past their column. */
  function flow(pn, s, first, max, size, f) {
    var out = [], cur = '', room = first;
    var push = function () { out.push(cur); cur = ''; room = max; };
    String(s == null ? '' : s).split(/\s+/).filter(Boolean).forEach(function (w) {
      var t = cur ? cur + ' ' + w : w;
      if (pn.width(t, size, f) <= room) { cur = t; return; }
      if (cur) push();
      while (pn.width(w, size, f) > room) {
        var k = w.length;
        while (k > 1 && pn.width(w.slice(0, k), size, f) > room) k--;
        cur = w.slice(0, k); push(); w = w.slice(k);
      }
      cur = w;
    });
    if (cur || !out.length) out.push(cur);
    return out;
  }
  /* The Record page continues the document it seals: that document's
     template (an Employment Contract's ACL_SIGN, a quotation's AL), its
     continuation head and its foot, the verify line included, and its
     Document ID where the document holds one (VERIFY DETAILS, 2026-11-20;
     a copy sealed before printed its uuid). */
  function recordPen(PDF, fonts, logo, info) {
    var code = /^[2-9A-Z]{4}-[2-9A-Z]{4}$/.test(String(info.docId || '')) ? info.docId : '';
    var pn = window.ADspaceDocs.pen(PDF, fonts, logo, { kind: info.kind || 'seal', signed: true, cont: true, code: code });
    pn.white = PDF.rgb(1, 1, 1);
    return pn;
  }
  /* The QR code's modules, from the console's own QR library (qrcodejs):
     drawn as squares, so it is sharp at any size. */
  function qrModules(text) {
    if (!window.QRCode) return null;
    try {
      var box = document.createElement('div');
      var q = new window.QRCode(box, { text: text, width: 64, height: 64, correctLevel: window.QRCode.CorrectLevel.M });
      var m = q && q._oQRCode;
      if (!m || !m.getModuleCount) return null;
      var n = m.getModuleCount(), out = [];
      for (var r = 0; r < n; r++) { out.push([]); for (var c = 0; c < n; c++) out[r].push(m.isDark(r, c)); }
      return out;
    } catch (e) { return null; }
  }
  /* The page laid out once, drawn or only counted: `draw` false answers how
     many pages the steps take, asked before the signed pages are drawn so
     their foot counts them. */
  function lay(pn, fonts, info, draw, newPage) {
    var f = fonts.font, fm = fonts.med || f, M = pn.M, R = pn.R, FULL = R - M;
    var top0 = pn.H - pn.TOP - 10, y = top0, pages = 1;
    var txt = function (s, x, yy, size, font, color) { if (draw) pn.text(s, x, yy, size, font, color); };
    var right = function (s, xr, yy, size, font, color) { txt(s, xr - pn.width(s, size, font), yy, size, font, color); };
    // Row 1: the padlock and the title; the Document ID at the right edge on its baseline.
    if (draw) {
      try {
        pn.page.drawSvgPath('M5 11h14v10H5zM8 11V7a4 4 0 0 1 8 0v4', { x: M - 1, y: y + 12, scale: 0.55, borderColor: pn.strong, borderWidth: 1.1 / 0.55 });
      } catch (e) { /* the title stands alone */ }
    }
    txt('Record of this Document', M + 16, y, T.title, fm, pn.strong);
    var code = String(info.docId || '');
    if (code) {
      right(code, R, y, T.code, fm, pn.strong);
      right('Document ID', R - pn.width(code, T.code, fm) - 6, y, T.id, f, pn.ink);
    }
    y -= T.title * 0.25 + T.under;
    pn.wrap(info.sub || '', FULL, T.sub, f).forEach(function (ln) { txt(ln, M, base(y, T.sub, T.subLead), T.sub, f, pn.ink); y -= T.subLead; });
    y -= T.rule;
    if (draw) pn.page.drawLine({ start: { x: M, y: y }, end: { x: R, y: y }, thickness: 0.6, color: pn.line });
    y -= T.rule;
    var bodyTop = y;
    // The right column: the QR code, its caption, the signed pages' hash.
    var hash = String(info.pagesSha || ''), halves = [hash.slice(0, 32), hash.slice(32)].filter(Boolean);
    var qr = info.verifyUrl ? qrModules(scanUrl(info.verifyUrl, info.docId)) : null;
    var side = qr ? Math.max(QR, qr.length * QR_MODULE) : QR;
    var sideW = Math.max(T.sideW, side, pn.width('Scan to check this copy', T.side, fm),
      halves.reduce(function (w, h) { return Math.max(w, pn.width(h, T.side, f)); }, 0));
    var addr = String(info.verifyUrl || '').replace(/^https?:\/\//, '').replace(/[?#].*$/, '').replace(/\/$/, '');
    var sy = bodyTop;
    if (qr && draw) {
      var n = qr.length, u = side / n, x0 = R - side;
      for (var r = 0; r < n; r++) for (var c = 0; c < n; c++) {
        if (qr[r][c]) pn.page.drawRectangle({ x: x0 + c * u, y: sy - (r + 1) * u, width: u + 0.05, height: u + 0.05, color: pn.strong });
      }
    }
    sy -= side + T.part;
    right('Scan to check this copy', R, base(sy, T.side, T.sideLead), T.side, fm, pn.ink); sy -= T.sideLead;
    if (addr) { right(addr, R, base(sy, T.side, T.sideLead), T.side, f, pn.ink); sy -= T.sideLead; }
    sy -= T.part;
    right('SHA-256, pages 1 to ' + (info.signedPages || ''), R, base(sy, T.side, T.sideLead), T.side, f, pn.ink); sy -= T.sideLead;
    halves.forEach(function (h) { right(h, R, base(sy, T.side, T.hashLead), T.side, f, pn.ink); sy -= T.hashLead; });
    // The timeline: the rail, the time, the step's sentence, its device.
    var xRail = M + T.dot / 2, xTime = M + T.rail, xText = xTime + T.timeW;
    var colW = R - sideW - T.colGap - xText, fullW = R - xText;
    var dots = [], day = '', prevStep = false;
    var flush = function () {
      if (!draw || !dots.length) return;
      if (dots.length > 1) pn.page.drawLine({ start: { x: xRail, y: dots[0].y }, end: { x: xRail, y: dots[dots.length - 1].y }, thickness: 0.6, color: pn.line });
      dots.forEach(function (d) {
        pn.page.drawCircle({ x: xRail, y: d.y, size: T.dot / 2, borderColor: pn.strong, borderWidth: 0.8, color: d.key ? pn.strong : pn.white });
      });
      dots = [];
    };
    var heading = function () {
      txt(day + ' · GMT+8', xTime, base(y, T.day, T.dayLead), T.day, fm, pn.ink);
      y -= T.dayLead + T.under;
    };
    var turn = function () {
      flush();
      pages++;
      if (draw) newPage();
      y = top0;
      sy = Infinity;
    };
    (info.rows || []).forEach(function (st) {
      // Beside the right column the step keeps clear of it; under it, the line runs on.
      var wide = function (yy) { return yy < sy - 2 ? fullW : colW; };
      var lines = flow(pn, st.rest, wide(y) - pn.width(st.word + ' ', T.step, fm), wide(y), T.step, f);
      var devs = st.dev ? flow(pn, st.dev, wide(y), wide(y), T.dev, f) : [];
      var newDay = st.day !== day;
      var need = lines.length * T.lead + devs.length * T.devLead + (newDay ? T.dayLead + T.under + (prevStep ? T.dayGap : 0) : prevStep ? T.gap : 0);
      if (y - need < pn.BOT + 4 && prevStep) { turn(); newDay = true; prevStep = false; }
      if (newDay) { if (prevStep) y -= T.dayGap; day = st.day; heading(); }
      else if (prevStep) y -= T.gap;
      dots.push({ y: y - 3 - T.dot / 2, key: st.key });
      txt(st.time, xTime, base(y, T.step, T.lead), T.step, f, pn.ink);
      txt(st.word, xText, base(y, T.step, T.lead), T.step, fm, pn.strong);
      lines.forEach(function (ln, i) {
        var x = i ? xText : xText + pn.width(st.word + ' ', T.step, fm);
        if (ln) txt(ln, x, base(y, T.step, T.lead), T.step, f, pn.ink);
        y -= T.lead;
      });
      devs.forEach(function (ln) { txt(ln, xText, base(y, T.dev, T.devLead), T.dev, f, pn.ink); y -= T.devLead; });
      prevStep = true;
    });
    flush();
    return pages;
  }
  function pagesFor(PDF, fonts, info) {
    return lay(recordPen(PDF, fonts, null, info), fonts, info, false);
  }
  /* info: ref, sub (the sentence under the title), docId, pagesSha,
     signedPages (n), verifyUrl, rows (`rows(rec)`), total (the file's page
     count). */
  function addRecord(pdf, PDF, fonts, logo, info) {
    var docs = window.ADspaceDocs, pn = recordPen(PDF, fonts, logo, info), pages = [];
    var page = function () { pn.page = pdf.addPage([pn.W, pn.H]); pages.push(pn.page); pn.head(); };
    page();
    lay(pn, fonts, info, true, page);
    docs.letterFoot(pn, pages, info.ref, '', info.total, info.total - pages.length);
    return pages.length;
  }

  // ---- Print only: the sealed file's protection ---------------------------
  /* js/sealprotect.js, at the seal alone, under this file's ?v=. */
  var V = (/\?v=[^&#]+/.exec((document.currentScript || {}).src || '') || [''])[0], protWait = null;
  function finish(bytes) {
    protWait = protWait || new Promise(function (ok, bad) {
      var s = document.createElement('script');
      s.src = '/js/sealprotect.js' + V;
      s.onload = ok;
      s.onerror = function () { s.remove(); protWait = null; bad(new Error(window.ADspaceWords.line.pdfLib)); };
      document.head.appendChild(s);
    });
    return protWait.then(function () { return window.ADspaceSealProtect(bytes, sha256); });
  }

  window.ADspaceSeal = {
    device: device, sha256: sha256, when: when, rows: rows, panel: panel, stateOf: stateOf, open: open, checksOf: checksOf, checksWord: checksWord,
    pagesFor: pagesFor, addRecord: addRecord, finish: finish, scanUrl: scanUrl, LOCK: LOCK
  };
})();
