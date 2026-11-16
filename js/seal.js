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
    returned: 'Sent back', confirmed: 'Confirmed', stamped: 'Stamped', sealed: 'Sealed', withdrawn: 'Withdrawn', declined: 'Declined' };
  var VIA = { link: 'on the quotation link', page: 'on the candidate page', whatsapp: 'on WhatsApp', email: 'by email' };
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
     signature stand for the rest, so the page holds one table. */
  function printable(steps) {
    var signedAt = (steps.filter(function (x) { return x.step === 'signed'; })[0] || {}).at;
    var opened = steps.filter(function (x) { return x.step === 'opened'; });
    var before = opened.filter(function (x) { return !signedAt || x.at <= signedAt; });
    var keep = [opened[0], before[before.length - 1]].filter(Boolean);
    return steps.filter(function (x) { return x.step !== 'opened' || keep.indexOf(x) >= 0; });
  }
  /* One step as the PDF's row: Step, Date and time, By, Email confirmed,
     IP · Country · Device. */
  function row(st) {
    var by;
    if (st.team) by = (st.by || 'ADspace') + (st.role ? ', ' + st.role : '') + (st.by && st.by !== 'ADspace' ? ', ADspace' : '');
    else by = st.step === 'signed' && st.by ? st.by + (st.role ? ', ' + st.role : '') : (st.party || 'Client');
    var how = st.step === 'sent' ? (VIA[st.via] || '') : st.step === 'signed' && st.via === 'paper' ? 'Signed on paper' + (st.entered_by ? ', entered by ' + st.entered_by : '') : '';
    return [STEP[st.step] || st.step, when(st.at), by,
      st.step === 'signed' || st.step === 'code' ? (st.email || '—') : '—',
      [how, where(st)].filter(Boolean).join(' · ') || '—'];
  }
  function rows(rec) { return printable(rec.steps || []).map(row); }

  // ---- The console's reading of the record -----------------------------------
  var LOCK = '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg>';
  function stateOf(rec) {
    if (rec.withdrawn) return ['Withdrawn', 'is-off'];
    if (rec.seal) return ['Confirmed · sealed', 'is-ok', true];
    if (rec.confirmed) return ['Confirmed', 'is-ok'];
    if (rec.signed) return ['Signed', 'is-warn'];
    return ['Not signed', 'is-off'];
  }
  function line(st) {
    var head = STEP[st.step] || st.step, who = '', meta = [];
    if (st.step === 'issued') who = st.by ? 'by ' + st.by : 'on the quotation website';
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
    else if (st.by) who = 'by ' + st.by;
    if (st.note && ['issued', 'withdrawn', 'declined'].indexOf(st.step) >= 0) meta.push(st.note);
    if (st.step === 'signed' && st.via === 'paper' && st.party) meta[0] = 'On paper or by scan' + (st.entered_by ? ' · entered by ' + st.entered_by : '');
    return '<li class="seal-step"><span class="seal-when">' + esc(when(st.at)) + '</span><span class="seal-what"><b>' + esc(head) + '</b>' +
      (who ? ' ' + esc(who) : '') + (meta.length ? '<span class="seal-meta">' + esc(meta.join(' · ')) + '</span>' : '') + '</span></li>';
  }
  function panel(rec, verifyUrl) {
    var st = stateOf(rec), s = rec.seal;
    var fact = function (k, v) { return '<div><dt>' + esc(k) + '</dt><dd>' + v + '</dd></div>'; };
    return '<dl class="ovfacts seal-facts">' +
      fact('State', '<span class="chip-state ' + st[1] + '">' + (st[2] ? '<span class="seal-lock">' + LOCK + '</span>' : '') + esc(st[0]) + '</span>') +
      fact('Document ID', '<span class="seal-mono">' + esc(rec.id) + '</span>') +
      (s ? fact('SHA-256', '<span class="seal-mono">' + esc(s.sha) + '</span>') : '') +
      (s && verifyUrl ? fact('Verify', esc(verifyUrl.replace(/^https?:\/\//, '').replace(/\?.*$/, '').replace(/\/$/, '') + ' · ' + rec.ref)) : '') +
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
      o.load().then(function (rec) {
        if (openNow !== mine) return;
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
  var SZ = 9, LEAD = 11.5, PADX = 5, PADY = 3.5;
  /* Long values (an ID, a hash, a device) wrap between words, else inside
     the word, never past their cell. */
  function wrapAny(pn, s, max, f) {
    var out = [];
    pn.wrap(String(s == null ? '' : s), max, SZ, f).forEach(function (ln) {
      while (pn.width(ln, SZ, f) > max) {
        var k = ln.length;
        while (k > 1 && pn.width(ln.slice(0, k), SZ, f) > max) k--;
        out.push(ln.slice(0, k));
        ln = ln.slice(k);
      }
      out.push(ln);
    });
    return out.length ? out : [''];
  }
  function cols(FULL) {
    return [0.12, 0.2, 0.22, 0.2, 0.26].map(function (w) { return FULL * w; });
  }
  function rowHeight(pn, cells, widths, f) {
    var n = 1;
    cells.forEach(function (c, i) { n = Math.max(n, wrapAny(pn, c, widths[i] - PADX * 2, f).length); });
    return n * LEAD + PADY * 2;
  }
  var TOP = 120, QR = 40;
  /* How many Record pages the steps take, asked before the signed pages
     are drawn so their foot counts them. */
  function pagesFor(PDF, fonts, info) {
    var pn = window.ADspaceDocs.pen(PDF, fonts, null), FULL = pn.R - pn.M;
    var widths = cols(FULL), room = pn.H - pn.M * 2 - TOP - 3 * (LEAD + PADY * 2) - QR - 60, n = 1, used = rowHeight(pn, HEAD, widths, fonts.font);
    (info.rows || []).forEach(function (r) {
      var h = rowHeight(pn, r, widths, fonts.font);
      if (used + h > room) { n++; used = rowHeight(pn, HEAD, widths, fonts.font); room = pn.H - pn.M * 2 - 60; }
      used += h;
    });
    return n;
  }
  var HEAD = ['Step', 'Date and time (GMT+8)', 'By', 'Email confirmed', 'IP · Country · Device'];
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
  /* info: ref, sub (the sentence under the heading), docId, pagesSha,
     signedPages (n), verifyUrl, rows, total (the file's page count). */
  function addRecord(pdf, PDF, fonts, logo, info) {
    var docs = window.ADspaceDocs;
    var pn = docs.pen(PDF, fonts, logo), W = pn.W, H = pn.H, M = pn.M, R = pn.R, FULL = R - M;
    var f = fonts.font, grid = PDF.rgb(0.949, 0.949, 0.949), pages = [];
    var page = function () { pn.page = pdf.addPage([W, H]); pages.push(pn.page); };
    page();
    var y = H - M - 10;
    pn.text('ADspace', M, y, 14, fonts.mark || fonts.bold);
    y -= 32;
    // The padlock, then the heading.
    try {
      pn.page.drawSvgPath('M5 11h14v10H5zM8 11V7a4 4 0 0 1 8 0v4', { x: M - 1, y: y + 12, scale: 0.55, borderColor: pn.ink, borderWidth: 1.1 / 0.55 });
    } catch (e) { /* the heading stands alone */ }
    pn.text('Record of this Document', M + 16, y, 13, fonts.med || f);
    y -= 16;
    pn.wrap(info.sub || '', FULL, 9.5, f).forEach(function (ln) { pn.text(ln, M, y, 9.5, f, pn.mute); y -= 12.5; });
    y -= 8;
    var cell = function (x, yy, w, h, shade) {
      pn.page.drawRectangle({ x: x, y: yy - h, width: w, height: h, borderColor: grid, borderWidth: 0.8, color: shade ? grid : undefined });
    };
    var put = function (lines, x, yy, color) {
      lines.forEach(function (ln, i) { pn.text(ln, x + PADX, yy - PADY - SZ - i * LEAD + 1.5, SZ, f, color); });
    };
    // The top table: Document ID, the signed pages' hash, Verify.
    var kw = FULL * 0.26, vw = FULL - kw;
    var top = [['Document ID', info.docId], ['SHA-256 of pages 1 to ' + info.signedPages, info.pagesSha]];
    top.forEach(function (r) {
      var vl = wrapAny(pn, r[1], vw - PADX * 2, f), h = vl.length * LEAD + PADY * 2;
      cell(M, y, kw, h); cell(M + kw, y, vw, h);
      put([r[0]], M, y, pn.mute); put(vl, M + kw, y);
      y -= h;
    });
    var qr = qrModules(info.verifyUrl);
    var words = info.verifyUrl.replace(/^https?:\/\//, '').replace(/\?.*$/, '').replace(/\/$/, '') + ' · ' + info.ref + ' · scan to check this copy';
    var qh = Math.max(qr ? QR + PADY * 2 : 0, LEAD + PADY * 2);
    cell(M, y, kw, qh); cell(M + kw, y, vw, qh);
    put(['Verify'], M, y, pn.mute);
    var tx = M + kw;
    if (qr) {
      var n = qr.length, u = QR / n, x0 = M + kw + PADX, y0 = y - PADY;
      for (var r = 0; r < n; r++) for (var c = 0; c < n; c++) {
        if (qr[r][c]) pn.page.drawRectangle({ x: x0 + c * u, y: y0 - (r + 1) * u, width: u + 0.05, height: u + 0.05, color: pn.ink });
      }
      tx = x0 + QR + 4;
    }
    wrapAny(pn, words, M + FULL - tx - PADX * 2, f).forEach(function (ln, i) {
      pn.text(ln, tx + PADX, y - qh / 2 + 3 - i * LEAD, SZ, f);
    });
    y -= qh + 12;
    // The steps.
    var widths = cols(FULL);
    var drawRow = function (cells, shade) {
      var h = rowHeight(pn, cells, widths, f), x = M;
      cells.forEach(function (c2, i) {
        cell(x, y, widths[i], h, shade);
        put(wrapAny(pn, c2, widths[i] - PADX * 2, f), x, y);
        x += widths[i];
      });
      y -= h;
    };
    drawRow(HEAD, true);
    (info.rows || []).forEach(function (r) {
      if (y - rowHeight(pn, r, widths, f) < M + 30) { page(); y = H - M - 10; drawRow(HEAD, true); }
      drawRow(r, false);
    });
    docs.letterFoot(pn, pages, info.ref, 'PRIVATE & CONFIDENTIAL', info.total, info.total - pages.length);
    return pages.length;
  }

  window.ADspaceSeal = {
    device: device, sha256: sha256, when: when, rows: rows, panel: panel, stateOf: stateOf, open: open,
    pagesFor: pagesFor, addRecord: addRecord, LOCK: LOCK
  };
})();
