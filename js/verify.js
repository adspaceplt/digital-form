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
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  var WORDS = {
    en: {
      title: 'Verify document', text: 'Enter the reference printed on the document.',
      go: 'Verify', checking: 'Checking…', lang: '中文',
      notFound: 'Not found', notFoundText: 'Check the reference, or contact ADspace.',
      failed: 'Unable to check', failedText: 'Please try again.',
      issued: 'Issued', state: { valid: 'Valid', voided: 'Void', replaced: 'Replaced' }
    },
    zh: {
      title: '文件核验', text: '请输入文件上印有的编号。',
      go: '核验', checking: '核验中…', lang: 'EN',
      notFound: '未找到', notFoundText: '请核对编号，或联系 ADspace。',
      failed: '无法核验', failedText: '请稍后再试。',
      issued: '签发于', state: { valid: '有效', voided: '已作废', replaced: '已替换' }
    }
  };
  var lang = 'en';
  function t() { return WORDS[lang]; }
  var last = null;   // the last answer, repainted when the language changes

  function niceDate(d) {
    if (!d) return '';
    var x = new Date(String(d).slice(0, 10) + 'T00:00:00');
    if (isNaN(x.getTime())) return String(d);
    if (lang === 'zh') return x.getFullYear() + '年' + (x.getMonth() + 1) + '月' + x.getDate() + '日';
    return x.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
  }

  function paintWords() {
    document.documentElement.setAttribute('lang', lang === 'zh' ? 'zh' : 'en');
    $('vTitle').textContent = t().title;
    $('vText').textContent = t().text;
    $('vGo').textContent = t().go;
    if ($('langToggle')) $('langToggle').textContent = t().lang;
    if (last) paint(last);
  }

  function paint(a) {
    last = a;
    var out = $('vOut');
    out.hidden = false;
    if (a.failed) {
      out.innerHTML = '<b>' + esc(t().failed) + '</b><span>' + esc(t().failedText) + '</span>';
      return;
    }
    if (!a.found) {
      out.innerHTML = '<b>' + esc(t().notFound) + '</b><span>' + esc(t().notFoundText) + '</span>';
      return;
    }
    var tone = a.state === 'valid' ? 'is-ok' : a.state === 'voided' ? 'is-danger' : '';
    out.innerHTML =
      '<b>' + esc(a.serial) + '</b>' +
      '<span>' + esc(a.kind + (a.issued_at ? ' · ' + t().issued + ' ' + niceDate(a.issued_at) : '')) + '</span>' +
      '<span class="tone ' + tone + '">' + esc(t().state[a.state] || a.state) + '</span>';
  }

  function check(serial) {
    serial = String(serial || '').trim();
    if (!serial) { $('vSerial').focus(); return; }
    var go = $('vGo');
    go.disabled = true; go.textContent = t().checking;
    var done = function (a) { go.disabled = false; go.textContent = t().go; paint(a); };
    if (!db) { done({ failed: true }); return; }
    db.rpc('verify_serial', { p_serial: serial }).then(function (r) {
      if (r.error || !r.data) { done({ failed: true }); return; }
      done(r.data);
    }, function () { done({ failed: true }); });
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
