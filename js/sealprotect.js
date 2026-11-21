/* A sealed copy's protection (2026-11-21), fetched by js/seal.js at the
 * seal alone, never by a page: seal.js reads its own ?v= stamp to fetch it,
 * so a change here bumps seal.js's stamp. */
(function () {
  'use strict';
  /* The sealed copy opens with no password and allows printing (high
     quality) and the reading a screen reader needs; changing it, notes on
     it, filling its fields, moving its pages and copying its words are
     refused (PDF standard security, AES-256, R6; the user, 2026-11-21:
     "no annotation, no edits etc. except printing only to the pdf"). The
     owner password is 32 random bytes made here for this one file and
     dropped with it: never stored, sent or written anywhere. The library
     is fetched only when a copy is sealed, pinned by the hash of the file
     the CDN serves, as documents.js fetches pdf-lib (which it needs
     loaded first). */
  var ENC = ['PDFEncrypt', 'https://cdn.jsdelivr.net/npm/@pdfsmaller/pdf-encrypt@1.2.0/dist/pdf-encrypt.umd.js',
    'sha384-2hwSGXr8axN0+sSOKhag0nzBhyxPSfoSu++CGxImIikMbN3Ox0kRlKwKTq0zCYie'];
  var encWait = null;
  function encLib() {
    if (window[ENC[0]]) return Promise.resolve(window[ENC[0]]);
    if (encWait) return encWait;
    encWait = new Promise(function (ok, bad) {
      var s = document.createElement('script');
      s.integrity = ENC[2]; s.crossOrigin = 'anonymous'; s.src = ENC[1];
      s.onload = function () { if (window[ENC[0]]) ok(window[ENC[0]]); else s.onerror(); };
      s.onerror = function () { s.remove(); encWait = null; bad(new Error(window.ADspaceWords.line.pdfLib)); };
      document.head.appendChild(s);
    });
    return encWait;
  }
  function protect(bytes) {
    return encLib().then(function (E) {
      var key = new Uint8Array(32);
      crypto.getRandomValues(key);
      return E.encryptPDF(bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes), '', {
        algorithm: 'AES-256',
        ownerPassword: Array.prototype.map.call(key, function (x) { return ('0' + x.toString(16)).slice(-2); }).join(''),
        allowPrinting: true, allowHighQualityPrint: true, allowExtraction: true,
        allowModifying: false, allowAnnotating: false, allowFillingForms: false, allowAssembly: false, allowCopying: false
      });
    });
  }
  /* The sealed file as it is kept: protected, then hashed whole (seal.js's
     sha256), so the hash stored is of the bytes every Download and
     /verify/ meet. */
  window.ADspaceSealProtect = function (bytes, sha256) {
    return protect(bytes).then(function (out) {
      return sha256(out).then(function (sha) { return { bytes: out, sha: sha }; });
    });
  };
})();
