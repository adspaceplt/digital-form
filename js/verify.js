/*
 * Verify — the public page the foot of every document names.
 *
 * One exact reference in; the first answer says only that ADSPACE PLT issued
 * a document with this reference, what kind it is, when (the month) and
 * whether it stands (`verify_serial`). Its days and steps are shown only to
 * somebody holding the copy: the Document ID printed at the foot of every
 * page, or for a document issued before Document IDs, its day of issue
 * (`verify_details`, VERIFY DETAILS 2026-11-20). A sealed copy's file is
 * checked in the browser (`verify_file`). Never a recipient, a term or a
 * figure: the database answers none.
 */
(function () {
  var API = window.ADspaceAPI;
  var db = API && API.client;
  var ORG = window.ADSPACE_ORG || {};

  function $(id) { return document.getElementById(id); }
  function esc(s) { return window.ADspaceWords.esc(s); }

  var WORDS = {
    en: {
      title: 'Verify document', text: 'Enter the reference printed on the document.',
      kicker: 'Verify', go: 'Verify', checking: 'Checking…', lang: '中文',
      notFound: 'Not found', notFoundText: 'Please check the reference, or contact ADspace.', enterRef: 'Enter the reference.',
      failed: 'Unable to check', failedText: 'Please try again.',
      locked: 'Too many checks', lockedText: 'Too many checks were made from this network. Please try again in {wait}.',
      ref: 'Reference', issuedBy: 'Issued by', doc: 'Document', issued: 'Issued', docId: 'Document ID', status: 'Status',
      note: 'This result confirms that ADSPACE PLT issued a document under this reference. It does not confirm the copy you hold.',
      more: 'More details', moreText: 'Enter the Document ID printed on your copy.', moreGo: 'Show details',
      file: 'File check', fileGo: 'Check a file', fileText: 'Compare a PDF with the sealed copy. The file stays on this device.',
      codeLabel: 'Document ID', codeHint: 'XXXX-XXXX', show: 'Show details', cancel: 'Cancel', showing: 'Checking…',
      noId: 'No Document ID on your copy?', dayLabel: 'Issue date',
      enterCode: 'Enter the Document ID.', enterDay: 'Enter the Document ID or the issue date.',
      noMatch: 'No document matches these details. Please check the details entered, or contact ADspace at {contact}.',
      noMatchBare: 'No document matches these details. Please check the details entered, or contact ADspace.',
      history: 'History', never: 'The recipient\'s name, the terms and the amounts are never shown here.',
      checkedOnce: 'Checked once', checkedN: 'Checked {n} times',
      fileChecking: 'Checking the file…', fileMatch: 'Matches the sealed copy',
      fileNo: 'Does not match the sealed copy', fileFailed: 'Unable to check the file. Please try again.',
      state: { valid: 'Valid', voided: 'Void', replaced: 'Replaced', expired: 'Expired', withdrawn: 'Withdrawn', declined: 'Declined' },
      step: { issued: 'Issued', sent: 'Sent', signed: 'Signed by the recipient', confirmed: 'Confirmed by ADspace', sealed: 'Sealed copy stored',
        acknowledged: 'Acknowledged by the recipient', finalised: 'Finalised', declined: 'Declined', withdrawn: 'Withdrawn', voided: 'Void',
        replaced: 'Replaced', expired: 'Expired' }
    },
    zh: {
      title: '文件核验', text: '请输入文件上印有的编号。',
      kicker: '文件核验', go: '核验', checking: '核验中…', lang: 'EN',
      notFound: '未找到', notFoundText: '请核对编号，或联系 ADspace。', enterRef: '请输入编号。',
      failed: '无法核验', failedText: '请稍后再试。',
      locked: '查询次数过多', lockedText: '此网络的查询次数过多。请于{wait}后重试。',
      ref: '编号', issuedBy: '签发方', doc: '文件', issued: '签发', docId: '文件识别码', status: '状态',
      note: '此结果确认 ADSPACE PLT 曾以此编号签发文件，但不确认您所持有的副本。',
      more: '更多详情', moreText: '请输入您副本上印有的文件识别码。', moreGo: '显示详情',
      file: '文件比对', fileGo: '核验文件', fileText: '将 PDF 与封存副本比对。文件不会离开此设备。',
      codeLabel: '文件识别码', codeHint: 'XXXX-XXXX', show: '显示详情', cancel: '取消', showing: '核验中…',
      noId: '副本上没有文件识别码？', dayLabel: '签发日期',
      enterCode: '请输入文件识别码。', enterDay: '请输入文件识别码或签发日期。',
      noMatch: '没有与这些资料相符的文件。请核对所输入的资料，或通过 {contact} 联系 ADspace。',
      noMatchBare: '没有与这些资料相符的文件。请核对所输入的资料，或联系 ADspace。',
      history: '记录', never: '此处不会显示收件方姓名、条款或金额。',
      checkedOnce: '已核验1次', checkedN: '已核验{n}次',
      fileChecking: '核验文件中…', fileMatch: '与封存副本一致',
      fileNo: '与封存副本不一致', fileFailed: '无法核验文件，请稍后再试。',
      state: { valid: '有效', voided: '已作废', replaced: '已替换', expired: '已过期', withdrawn: '已撤回', declined: '已拒绝' },
      step: { issued: '签发', sent: '发送', signed: '收件方签署', confirmed: 'ADspace 确认', sealed: '封存副本已存档',
        acknowledged: '收件方确认收悉', finalised: '定稿', declined: '已拒绝', withdrawn: '已撤回', voided: '已作废',
        replaced: '已替换', expired: '已过期' },
      /* The kinds the database names, in Chinese; a kind not listed (a type
         the team added) reads as it was sent. */
      kind: { 'quotation': '报价单', 'letter of offer': '服务确认函', 'hr letter': '人事函件', 'client letter': '客户函件',
        'letter to client': '客户函件', 'thank you letter': '感谢函', 'quotation cover': '报价单封面函',
        'supplier service agreement': '供应商服务协议', 'letter to supplier': '供应商函件' }
    }
  };
  /* The issuer's own names, as the page's settings hold them: the demo
     (js/demo.js) answers for its sample agency, never as ADspace. */
  (function names() {
    var cfg = window.ADSPACE_CONFIG || {}, org = ORG.name || 'ADSPACE PLT', brand = cfg.agencyName || 'ADspace';
    if (org === 'ADSPACE PLT' && brand === 'ADspace') return;
    var walk = function (o) {
      Object.keys(o).forEach(function (k) {
        if (typeof o[k] === 'string') o[k] = o[k].replace(/ADSPACE PLT/g, org).replace(/ADspace/g, brand);
        else if (o[k] && typeof o[k] === 'object') walk(o[k]);
      });
    };
    walk(WORDS);
  })();
  /* A step done is green, one that closes the document grey, a void red. */
  var STEP_TONE = { voided: 'is-danger', declined: 'is-off', withdrawn: 'is-off', replaced: 'is-off', expired: 'is-off' };
  var lang = 'en';
  function t() { return WORDS[lang]; }
  /* What is on screen, repainted when the language changes: the first
     answer, the details once shown, the question while open. */
  var last = null, detail = null, asking = false, askSaid = null;

  function zh() { return lang === 'zh'; }
  /* Days are Malaysia's (js/clock.js); a history date carries no weekday. */
  function dayWord(d) { return d ? (ADspaceClock.date(String(d).slice(0, 10), { zh: zh() }) || String(d)) : ''; }
  function monthWord(m) { return m ? (ADspaceClock.month(String(m).slice(0, 7), { zh: zh() }) || String(m)) : ''; }

  function paintWords() {
    document.documentElement.setAttribute('lang', zh() ? 'zh' : 'en');
    $('vTitle').textContent = t().title;
    $('vText').textContent = t().text;
    $('vGo').textContent = t().go;
    $('vSerial').setAttribute('aria-label', t().ref);
    if ($('kicker')) $('kicker').textContent = t().kicker;
    if ($('langToggle')) $('langToggle').textContent = t().lang;
    if (last) paint(last);
  }

  /* The shared minutes and hours (js/words.js), in this page's sentence. */
  function lockedLine(minutes, line) {
    var W = window.ADspaceWords, w = {}, k, base = W[lang] || W.en;
    for (k in base) w[k] = base[k];
    w.lockedText = line || t().lockedText;
    return W.lockedLine(w, minutes);
  }

  function kindWord(k) {
    var m = t().kind;
    return (m && m[String(k || '').trim().toLowerCase()]) || k || '';
  }
  function issuer() { return (ORG.name || 'ADSPACE PLT') + (ORG.regno ? ' (' + ORG.regno + ')' : ''); }
  function stateTone(s) { return s === 'valid' ? 'is-ok' : s === 'voided' ? 'is-danger' : 'is-off'; }

  /* The facts of an answer: the first answer's month, or the details' day
     and Document ID. */
  function facts(a, d) {
    var row = function (label, value) { return '<div><dt>' + esc(label) + '</dt><dd>' + value + '</dd></div>'; };
    var state = (d && d.state) || a.state;
    /* A database from before VERIFY DETAILS answers the day of issue; the
       page draws its month alike. */
    var month = a.issued_month || (a.issued_at ? ADspaceClock.day(a.issued_at).slice(0, 7) : '');
    return '<dl class="verify-facts">' +
      row(t().ref, esc(a.serial || '')) +
      row(t().issuedBy, esc(issuer())) +
      row(t().doc, esc(kindWord(a.kind))) +
      (d ? row(t().issued, esc(dayWord(d.issued_on))) : month ? row(t().issued, esc(monthWord(month))) : '') +
      (d && d.document_id ? row(t().docId, '<span class="verify-code">' + esc(d.document_id) + '</span>') : '') +
      row(t().status, '<span class="tone ' + stateTone(state) + '">' + esc(t().state[state] || state) + '</span>') +
      '</dl>';
  }

  /* How many times this document has been checked here, one small line
     under its History (VERIFY CHECKS COUNTED, 2026-11-21): a lookup that
     found it, once an address a day. No count, no line. */
  function checksLine(n) {
    n = Math.floor(Number(n));
    if (!(n >= 1)) return '';
    return '<p class="verify-checks">' + esc(n === 1 ? t().checkedOnce : t().checkedN.replace('{n}', String(n))) + '</p>';
  }

  function paint(a) {
    last = a;
    var out = $('vOut');
    out.hidden = false;
    out.classList.toggle('is-answer', !!a.found);
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
    var html = '<div class="verify-card" id="vCard">' + facts(a, detail) +
      (detail ? '' : '<p class="verify-note">' + esc(t().note) + '</p>') + '</div>';
    if (detail) {
      html += '<section class="verify-history" aria-labelledby="vHistH"><h3 id="vHistH">' + esc(t().history) + '</h3><ol>' +
        (detail.history || []).map(function (h) {
          return '<li><span class="verify-day">' + esc(dayWord(h.day)) + '</span><span class="tone ' + (STEP_TONE[h.step] || 'is-ok') + '">' +
            esc(t().step[h.step] || h.step) + '</span></li>';
        }).join('') + '</ol>' + checksLine(detail.checks) + '<p class="verify-note">' + esc(t().never) + '</p></section>';
    } else if (asking) {
      html += askHtml(a);
    }
    var moreBox = !detail && !asking && a.more;
    if (moreBox || a.sealed) {
      html += '<div class="verify-acts">' +
        (moreBox ? '<section class="verify-pick" aria-labelledby="vMoreH"><h3 id="vMoreH">' + esc(t().more) + '</h3><p>' + esc(t().moreText) + '</p>' +
          '<button class="btn btn-sm" type="button" id="vMoreGo">' + esc(t().moreGo) + '</button></section>' : '') +
        (a.sealed ? '<section class="verify-pick" aria-labelledby="vFileH"><h3 id="vFileH">' + esc(t().file) + '</h3><p>' + esc(t().fileText) + '</p>' +
          '<input type="file" id="vFile" accept="application/pdf,.pdf" hidden>' +
          '<button class="btn btn-sm" type="button" id="vFileGo">' + esc(t().fileGo) + '</button></section>' : '') +
        '</div>';
    }
    if (a.sealed) html += '<p class="verify-file-out" id="vFileOut" role="status"' + (fileSaid ? '' : ' hidden') + '>' + (fileSaid ? fileLine(fileSaid) : '') + '</p>';
    out.innerHTML = html;
    if (moreBox) $('vMoreGo').addEventListener('click', function () { asking = true; askSaid = null; paint(last); if ($('vCode')) $('vCode').focus(); });
    if (asking && !detail) wireAsk(a);
    if (a.sealed) wireFile(a.serial);
  }

  /* View more details: the Document ID, or where the day of issue may stand
     for it (a document from before Document IDs), the day under its fold. */
  var typed = { code: '', day: '', open: false };
  function askHtml(a) {
    var said = askSaid ? '<p class="msg err" id="vDetailMsg" role="alert">' + esc(askSaid) + '</p>' : '<p class="msg err" id="vDetailMsg" role="alert" hidden></p>';
    return '<form class="verify-ask" id="vAsk" novalidate>' +
      '<label class="verify-label" for="vCode">' + esc(t().codeLabel) + '</label>' +
      '<input class="input" id="vCode" placeholder="' + esc(t().codeHint) + '" autocomplete="off" autocapitalize="characters" spellcheck="false" maxlength="40" value="' + esc(typed.code) + '">' +
      (a.by_day ? '<details class="verify-noid" id="vNoId"' + (typed.open ? ' open' : '') + '><summary>' + esc(t().noId) + '</summary>' +
        '<label class="verify-label" for="vDay">' + esc(t().dayLabel) + '</label>' +
        '<input class="input" type="date" id="vDay" min="2023-08-14" max="' + esc(ADspaceClock.today()) + '" value="' + esc(typed.day) + '"></details>' : '') +
      said +
      '<div class="row acts verify-ask-acts"><button class="btn btn-primary" type="submit" id="vDetailGo">' + esc(t().show) + '</button>' +
      '<button class="btn btn-quiet" type="button" id="vAskCancel">' + esc(t().cancel) + '</button></div>' +
      '</form>';
  }
  function wireAsk(a) {
    var form = $('vAsk');
    if (!form) return;
    var keepTyped = function () {
      typed.code = $('vCode').value;
      typed.day = $('vDay') ? $('vDay').value : '';
      typed.open = !!($('vNoId') && $('vNoId').open);
    };
    form.addEventListener('input', keepTyped);
    if ($('vNoId')) $('vNoId').addEventListener('toggle', keepTyped);
    $('vAskCancel').addEventListener('click', function () {
      asking = false; askSaid = null; typed = { code: '', day: '', open: false }; paint(last);
      if ($('vMoreGo')) $('vMoreGo').focus();
    });
    form.addEventListener('submit', function (e) {
      e.preventDefault();
      keepTyped();
      var code = typed.code.trim(), day = typed.open ? typed.day : '';
      if (!code && !day) { say(a.by_day ? t().enterDay : t().enterCode, $('vCode')); return; }
      var go = $('vDetailGo');
      go.disabled = true; go.textContent = t().showing;
      details(a, code, day, false);
    });
  }
  /* The details asked of `verify_details`: typed, or from a QR code's
     Document ID (`scanned`, the reference it was scanned for), the same
     call, refusals and count. A scanned ID refused falls back to the typed step with that refusal and an empty
     field, and its pass is let go. */
  function details(a, code, day, scanned) {
    var no = function (text, field, wrong) {
      if (scanned) { if (wrong) forgetPass(scanned); asking = true; typed = { code: '', day: '', open: false }; }
      say(text, field, scanned);
    };
    if (!db) { no(t().failedText); return; }
    db.rpc('verify_details', { p_serial: a.serial, p_code: code || null, p_day: code ? null : day }).then(function (r) {
      var d = r && r.data;
      if (last !== a) return;
      if (r.error || !d || d.error) { no(t().failed + '. ' + t().failedText); return; }
      if (d.locked) { no(lockedLine(d.minutes)); return; }
      if (!d.ok) {
        no(d.contact ? t().noMatch.replace('{contact}', d.contact) : t().noMatchBare, $('vCode') || { id: 'vCode' }, true);
        return;
      }
      detail = d; asking = false; askSaid = null; typed = { code: '', day: '', open: false };
      paint(last);
      var h = $('vHistH'); if (h) { h.setAttribute('tabindex', '-1'); h.focus({ preventScroll: true }); }
    }).catch(function () { no(t().failed + '. ' + t().failedText); });
  }
  /* A refusal stays under the fields with what was typed; one met on
     arrival (a scanned ID) marks the field without taking the focus. */
  function say(text, field, quiet) {
    askSaid = text;
    paint(last);
    var f = field && $(field.id);
    if (f) { f.setAttribute('aria-invalid', 'true'); if (!quiet) f.focus(); }
  }

  /* A QR code's pass (the user, 2026-11-21: "if they scan straight from a
     qr code then it will create a session of that doc reference … sharing
     the site link to others wont get them through"): the Document ID the
     code carried, kept in this tab alone (sessionStorage) for the
     reference it was scanned for, until `verify.passMinutes` after the
     scan, so a refresh here opens the details again; another tab, a
     shared link or a pass run out meets the typed step. */
  var PASS = 'adspace-verify-pass:';
  function passMinutes() {
    var v = ((window.ADSPACE_CONFIG || {}).verify || {}).passMinutes;
    return v > 0 ? v : 0;
  }
  function passKey(serial) { return PASS + String(serial || '').trim().toUpperCase(); }
  function keepPass(serial, code) {
    if (!passMinutes()) return;
    try { sessionStorage.setItem(passKey(serial), JSON.stringify({ code: code, until: Date.now() + passMinutes() * 60000 })); } catch (e) {}
  }
  function readPass(serial) {
    try {
      var raw = sessionStorage.getItem(passKey(serial)), p = raw && JSON.parse(raw);
      if (p && p.code && Date.now() < p.until) return String(p.code);
      if (raw) sessionStorage.removeItem(passKey(serial));
    } catch (e) {}
    return '';
  }
  function forgetPass(serial) { try { sessionStorage.removeItem(passKey(serial)); } catch (e) {} }
  /* The Document ID a QR code carries (`#d=`), taken out of the address and
     the history before anything is asked, so the address on screen, shared
     or bookmarked, holds the reference alone. */
  function takeScan() {
    var m = /(?:^#|&)d=([^&]*)/.exec(location.hash || '');
    if (!m) return '';
    try { history.replaceState(history.state, '', location.pathname + location.search); } catch (e) {}
    var code = '';
    try { code = decodeURIComponent(m[1]); } catch (e) { code = m[1]; }
    return code.replace(/[^0-9A-Za-z-]/g, '').slice(0, 40);
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
       page answers a reference no longer asked (VERIFY-4), and says what is
       needed (2026-10-27, VER-2). */
    if (!serial) {
      keep(''); detail = null; asking = false; paint({ need: true });
      $('vSerial').setAttribute('aria-invalid', 'true'); $('vSerial').focus();
      return;
    }
    $('vSerial').removeAttribute('aria-invalid');
    fileSaid = null; detail = null; asking = false; askSaid = null; typed = { code: '', day: '', open: false };
    var go = $('vGo');
    go.disabled = true; go.textContent = t().checking;
    var done = function (a) {
      go.disabled = false; go.textContent = t().go; paint(a); if (!a.failed && !a.locked) keep(serial);
      // A pass held in this tab for this reference opens its details.
      var code = a.found && a.more ? readPass(serial) : '';
      if (code) details(a, code, '', serial);
    };
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

  // A link may carry the reference, so a QR code lands on the answer, and
  // the code's Document ID becomes this tab's pass for it.
  var scanned = takeScan();
  var given = new URLSearchParams(location.search).get('s');
  if (given && scanned) keepPass(given, scanned);
  if (given) { $('vSerial').value = given; check(given); }
  /* A code scanned into a tab already on this page changes the fragment
     alone, which loads nothing: taken the same way. */
  window.addEventListener('hashchange', function () {
    var code = takeScan(), s = new URLSearchParams(location.search).get('s');
    if (!code || !s) return;
    keepPass(s, code); $('vSerial').value = s; check(s);
  });
})();
