/*
 * Verify — the public page the footer of every letter names.
 *
 * One exact reference in; the kind, the date and whether it stands out, or
 * Not found. The database function it calls (`verify_serial`) is granted to
 * the public key and answers nothing else: no listing, no partial match,
 * never the recipient. An HR letter is answered as an HR letter and no more.
 */
(function () {
  var API = window.ADspaceAPI;
  var db = API && API.client;

  function $(id) { return document.getElementById(id); }
  function esc(s) { return window.ADspaceWords.esc(s); }

  var WORDS = {
    en: {
      title: 'Verify document', text: 'Enter the reference printed on the document.',
      kicker: 'Verify', go: 'Verify', checking: 'Checking…', lang: '中文',
      notFound: 'Not found', notFoundText: 'Please check the reference, or contact ADspace.', enterRef: 'Enter the reference.',
      failed: 'Unable to check', failedText: 'Please try again.',
      locked: 'Too many checks', lockedText: 'Too many references were checked from this connection. Please try again in {wait}.',
      issued: 'Issued', signed: 'Signed', confirmed: 'Confirmed', docId: 'Document ID',
      fileGo: 'Check a file', fileChecking: 'Checking the file…', fileMatch: 'Matches the sealed copy',
      fileNo: 'Does not match: this file has been altered', fileFailed: 'Unable to check the file. Please try again.',
      state: { valid: 'Valid', voided: 'Void', replaced: 'Replaced', expired: 'Expired', withdrawn: 'Withdrawn' }
    },
    zh: {
      title: '文件核验', text: '请输入文件上印有的编号。',
      kicker: '文件核验', go: '核验', checking: '核验中…', lang: 'EN',
      notFound: '未找到', notFoundText: '请核对编号，或联系 ADspace。', enterRef: '请输入编号。',
      failed: '无法核验', failedText: '请稍后再试。',
      locked: '查询次数过多', lockedText: '此网络连接查询编号的次数过多。请于{wait}后重试。',
      issued: '签发于', signed: '签署于', confirmed: '确认于', docId: '文件编号',
      fileGo: '核验文件', fileChecking: '核验文件中…', fileMatch: '与封存副本一致',
      fileNo: '不一致：此文件已被更改', fileFailed: '无法核验文件，请稍后再试。',
      state: { valid: '有效', voided: '已作废', replaced: '已替换', expired: '已过期', withdrawn: '已撤回' },
      /* The kinds the database names, in Chinese; a kind not listed (a type
         the team added) reads as it was sent. */
      kind: { 'quotation': '报价单', 'letter of offer': '服务确认函', 'hr letter': '人事函件', 'client letter': '客户函件',
        'letter to client': '客户函件', 'thank you letter': '感谢函', 'quotation cover': '报价单封面函',
        'supplier service agreement': '供应商服务协议', 'letter to supplier': '供应商函件' }
    }
  };
  var lang = 'en';
  function t() { return WORDS[lang]; }
  var last = null;   // the last answer, repainted when the language changes

  function niceDate(d) {
    if (!d) return '';
    /* Days are Malaysia's (js/clock.js), whatever the device's clock. */
    var k = String(d).length > 10 ? ADspaceClock.day(d) : String(d).slice(0, 10);
    return ADspaceClock.date(k, { zh: lang === 'zh' }) || String(d);
  }

  function paintWords() {
    document.documentElement.setAttribute('lang', lang === 'zh' ? 'zh' : 'en');
    $('vTitle').textContent = t().title;
    $('vText').textContent = t().text;
    $('vGo').textContent = t().go;
    if ($('kicker')) $('kicker').textContent = t().kicker;
    if ($('langToggle')) $('langToggle').textContent = t().lang;
    if (last) paint(last);
  }

  /* The shared minutes and hours (js/words.js), in this page's sentence. */
  function lockedLine(minutes) {
    var W = window.ADspaceWords, w = {}, k, base = W[lang] || W.en;
    for (k in base) w[k] = base[k];
    w.lockedText = t().lockedText;
    return W.lockedLine(w, minutes);
  }

  function kindWord(k) {
    var m = t().kind;
    return (m && m[String(k || '').trim().toLowerCase()]) || k || '';
  }

  function paint(a) {
    last = a;
    var out = $('vOut');
    out.hidden = false;
    if (a.need) { out.innerHTML = '<span class="verify-need">' + esc(t().enterRef) + '</span>'; return; }
    if (a.failed) {
      out.innerHTML = '<b>' + esc(t().failed) + '</b><span>' + esc(t().failedText) + '</span>';
      return;
    }
    /* Thirty lookups an hour from one connection (`verify_serial`). */
    if (a.locked) {
      out.innerHTML = '<b>' + esc(t().locked) + '</b><span>' + esc(lockedLine(a.minutes)) + '</span>';
      return;
    }
    if (!a.found) {
      out.innerHTML = '<b>' + esc(t().notFound) + '</b><span>' + esc(t().notFoundText) + '</span>';
      return;
    }
    var tone = a.state === 'valid' ? 'is-ok' : a.state === 'voided' ? 'is-danger' : 'is-off';
    /* A signed quotation's days and, once sealed, its Document ID: what the
       Record page printed, never who signed it (SEAL-SPEC decision 6). */
    var days = [];
    if (a.signed_at) days.push(t().signed + ' ' + niceDate(a.signed_at));
    if (a.confirmed_at) days.push(t().confirmed + ' ' + niceDate(a.confirmed_at));
    out.innerHTML =
      '<b>' + esc(a.serial) + '</b>' +
      '<span>' + esc(kindWord(a.kind) + (a.issued_at ? ' · ' + t().issued + ' ' + niceDate(a.issued_at) : '')) + '</span>' +
      (days.length ? '<span>' + esc(days.join(' · ')) + '</span>' : '') +
      (a.document_id ? '<span class="verify-id">' + esc(t().docId + ' ' + a.document_id) + '</span>' : '') +
      '<span class="tone ' + tone + '">' + esc(t().state[a.state] || a.state) + '</span>' +
      (a.sealed ? '<div class="verify-file"><input type="file" id="vFile" accept="application/pdf,.pdf" hidden>' +
        '<button class="btn btn-sm" type="button" id="vFileGo">' + esc(t().fileGo) + '</button>' +
        '<span class="verify-file-out" id="vFileOut"' + (fileSaid ? '' : ' hidden') + '>' + (fileSaid ? fileLine(fileSaid) : '') + '</span></div>' : '');
    if (a.sealed) wireFile(a.serial);
  }

  /* Check a file: the PDF is hashed here and never leaves the device; only
     its SHA-256 is asked of `verify_file`, beside the reference. */
  var fileSaid = null;
  function fileLine(r) {
    if (r === 'checking') return esc(t().fileChecking);
    if (r === 'match') return '<span class="tone is-ok">' + esc(t().fileMatch) + '</span>';
    if (r === 'no') return '<span class="tone is-danger">' + esc(t().fileNo) + '</span>';
    if (r && r.locked) return esc(lockedLine(r.minutes));
    return esc(t().fileFailed);
  }
  function sayFile(r) {
    fileSaid = r;
    var o = $('vFileOut'); if (!o) return;
    o.hidden = false; o.innerHTML = fileLine(r);
  }
  function wireFile(serial) {
    var go = $('vFileGo'), pick = $('vFile');
    if (!go || !pick) return;
    go.addEventListener('click', function () { pick.value = ''; pick.click(); });
    pick.addEventListener('change', function () {
      var f = pick.files && pick.files[0];
      if (!f) return;
      if (!window.ADspaceSeal || !db) { sayFile('failed'); return; }
      sayFile('checking'); go.disabled = true;
      f.arrayBuffer().then(function (buf) { return window.ADspaceSeal.sha256(buf); }).then(function (sha) {
        return db.rpc('verify_file', { p_serial: serial, p_sha: sha });
      }).then(function (r) {
        go.disabled = false;
        var d = r && r.data;
        if (r.error || !d || d.error || d.none) { sayFile('failed'); return; }
        if (d.locked) { sayFile(d); return; }
        sayFile(d.match === true ? 'match' : 'no');
      }).catch(function () { go.disabled = false; sayFile('failed'); });
    });
  }

  /* The reference checked rides in the address (?s=), so the answer can be
     refreshed and passed on; replaced, never pushed. */
  function keep(serial) {
    try {
      var url = new URL(location.href);
      if (serial) url.searchParams.set('s', serial); else url.searchParams.delete('s');
      if (url.href !== location.href) history.replaceState(history.state, '', url.href);
    } catch (e) {}
  }

  function check(serial) {
    serial = String(serial || '').trim();
    /* An empty check takes the last answer away with it, so nothing on the
       page answers a reference no longer asked (VERIFY-4). */
    /* An empty check says what is needed (2026-10-27, VER-2). */
    if (!serial) {
      keep(''); paint({ need: true });
      $('vSerial').setAttribute('aria-invalid', 'true'); $('vSerial').focus();
      return;
    }
    $('vSerial').removeAttribute('aria-invalid');
    fileSaid = null;
    var go = $('vGo');
    go.disabled = true; go.textContent = t().checking;
    var done = function (a) { go.disabled = false; go.textContent = t().go; paint(a); if (!a.failed && !a.locked) keep(serial); };
    if (!db) { done({ failed: true }); return; }
    db.rpc('verify_serial', { p_serial: serial }).then(function (r) {
      if (r.error || !r.data) { done({ failed: true }); return; }
      done(r.data);
    }).catch(function () { done({ failed: true }); });
  }

  $('vForm').addEventListener('submit', function (e) { e.preventDefault(); check($('vSerial').value); });
  if ($('langToggle')) $('langToggle').addEventListener('click', function () {
    lang = lang === 'en' ? 'zh' : 'en'; paintWords();
  });
  paintWords();

  // A link may carry the reference, so a QR code lands on the answer.
  var given = new URLSearchParams(location.search).get('s');
  if (given) { $('vSerial').value = given; check(given); }
})();
