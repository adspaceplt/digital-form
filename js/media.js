/*
 * ADspaceMedia — the one place a video is given the copy a browser can play.
 *
 * Videos are uploaded as they come off a phone: an iPhone's QuickTime file
 * holding HEVC, which only Safari plays. A conversion on S3 (workers/
 * video-convert/) writes an H.264 MP4 beside each one, named after it:
 * content/…/name.mov → content/…/name.web.mp4. A player names that copy
 * first and the original second, so every browser plays the copy once it
 * exists and falls back to the original until then (Safari plays both).
 */
(function () {
  'use strict';
  var CDN = /^https:\/\/mycdn\.adspace\.me\/content\/.+\.(mov|mp4|m4v|qt)$/i;

  /* The converted copy of a video on the CDN, else null. A copy is never
     asked for a copy. */
  function webOf(url) {
    var u = String(url || '');
    if (!CDN.test(u) || /\.web\.mp4$/i.test(u)) return null;
    return u.replace(/\.[a-z0-9]+$/i, '.web.mp4');
  }
  function attr(v) {
    return String(v).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
  }
  /* The <source> children for a player: the copy first, the original after. */
  function sources(url) {
    var web = webOf(url);
    return (web ? '<source src="' + attr(web) + '" type="video/mp4">' : '') +
      '<source src="' + attr(url || '') + '">';
  }
  /* A player built in markup: every attribute the caller gives, then the
     sources. */
  function tag(url, attrs) {
    return '<video' + (attrs ? ' ' + attrs : '') + '>' + sources(url) + '</video>';
  }
  /* A still: a video drawn as its first frame (`#t=0.1`), muted and never
     playing, for a thumbnail. iPhone Safari draws a bare video blank until
     it plays (the user, 2026-10-10: a creator's post read as an empty box). */
  function still(url) {
    return '<video muted playsinline preload="metadata" tabindex="-1" aria-hidden="true">' +
      sources(url).replace(/src="([^"#]+)"/g, 'src="$1#t=0.1"') + '</video>';
  }
  /* A player built as an element. */
  function attach(video, url) {
    video.removeAttribute('src');
    video.innerHTML = sources(url);
    return video;
  }
  /* ---- The pass (2026-10-03) ----------------------------------------------
     Everything under content/ opens only with CloudFront's signed cookies
     once `privateMedia` is on (docs/S3-STORAGE.md §6). A page that has proved
     its link, code or sign-in asks `media-pass` for them before it draws a
     file, and they are set on adspace.me so mycdn.adspace.me receives them.
     Stored addresses never change. The pass lasts twelve hours and is asked
     again on a page load or a return to the tab once under two hours are left;
     a file that fails in the meantime asks again once and loads again,
     a video from the second it was at.
     Each pass is held to the folders its caller may see (audit F3,
     2026-10-10): `passes` is one policy a folder, set on that folder's own
     path so the browser sends it there alone; a colleague's is content/ on
     the root. A pass is fresh only for the proof it was asked with. */
  var CONTENT = /^https:\/\/mycdn\.adspace\.me\/content\//i;
  var UNTIL = 'adspace-media-until';
  var FOR = 'adspace-media-for';
  var HOUR = 3600 * 1000;
  var proof = null;
  var inflight = null;
  var lastAsk = 0;

  function s3() { var c = window.ADSPACE_CONFIG || {}; return c.s3 || {}; }
  function isOn() { return !!s3().privateMedia; }
  function cookie(name) {
    var m = document.cookie.match(new RegExp('(?:^|; )' + name + '=([^;]*)'));
    return m ? m[1] : '';
  }
  function until() { return (Number(cookie(UNTIL)) || 0) * 1000; }
  /* Which proof the pass was asked with, as a short hash: a pass for one
     link is not fresh for another. */
  function tagOf(p) {
    var t = p ? (p.review ? 'r' + p.review : p.campaign ? 'c' + p.campaign : p.creator ? 'k' + p.creator : 's') : '';
    var h = 5381;
    for (var i = 0; i < t.length; i++) h = ((h * 33) ^ t.charCodeAt(i)) >>> 0;
    return h.toString(36);
  }
  function fresh(margin) { return cookie(FOR) === tagOf(proof) && until() - Date.now() > margin; }
  /* adspace.me on the real site; the host alone anywhere else (the tests). */
  function scope() {
    var d = s3().mediaCookieDomain, h = location.hostname;
    return d && (h === d || h.slice(-(d.length + 1)) === '.' + d) ? '; domain=' + d : '';
  }
  function put(name, value, age, path) {
    document.cookie = name + '=' + value + scope() + '; path=' + (path || '/') + '; max-age=' + age + '; secure; samesite=lax';
  }
  var CF = ['CloudFront-Policy', 'CloudFront-Signature', 'CloudFront-Key-Pair-Id'];
  /* The folders a pass was set on, kept in this browser (2026-10-12): a
     client's link opened beside the console left its own three cookies on
     that client's folder, and CloudFront refused the file once the browser
     sent two of each. A new pass takes away every folder of the one before. */
  var PATHS = 'adspace-media-paths';
  var FOLDER = /^\/content\/((creator\/)?[A-Za-z0-9-]{1,64}\/)?$/;
  function known() {
    try { var a = JSON.parse(localStorage.getItem(PATHS) || '[]'); return Array.isArray(a) ? a : []; }
    catch (e) { return []; }
  }
  function remember(list) {
    try { localStorage.setItem(PATHS, JSON.stringify(list.slice(0, 200))); } catch (e) { /* private mode */ }
  }
  function drop(path) { CF.forEach(function (n) { put(n, '', 0, path); }); }
  /* The folder a file sits in, as a cookie path: /content/{id}/ or
     /content/creator/{id}/. */
  function folderOf(src) {
    var m = /^https:\/\/mycdn\.adspace\.me(\/content\/(?:creator\/)?[A-Za-z0-9-]{1,64}\/)/i.exec(String(src || ''));
    return m ? m[1] : '';
  }
  /* A colleague's pass covers the whole of content/ (2026-10-15, the user:
     every file in the console stopped loading once a client's link was
     opened in the same browser). A client page opened beside the console
     leaves that pass alone and sets none of its own, since CloudFront
     refuses a file sent two passes; the console, for its part, takes away
     every folder a client page left before it asks, fresh or not. */
  function colleague(p) { return !!p && !p.review && !p.campaign && !p.creator; }
  function teamPassLive() { return cookie(FOR) === tagOf({}) && until() - Date.now() > 5 * 60 * 1000; }
  function clearFolders() {
    var left = known();
    if (!left.length) return;
    left.forEach(function (path) { if (FOLDER.test(path)) drop(path); });
    remember([]);
  }
  function ask(force) {
    if (!isOn() || !proof) return Promise.resolve(false);
    if (colleague(proof)) clearFolders();
    else if (teamPassLive()) return Promise.resolve(true);
    if (!force && fresh(2 * HOUR)) return Promise.resolve(true);
    if (inflight) return inflight;
    var API = window.ADspaceAPI, db = API && API.client;
    if (!db || !db.functions) return Promise.resolve(false);
    lastAsk = Date.now();
    var timer;
    inflight = new Promise(function (resolve) {
      // A slow answer never holds the page: it draws, and a failed file asks again.
      timer = setTimeout(function () { resolve(false); }, 6000);
      db.functions.invoke('media-pass', { body: proof }).then(function (r) {
        var d = r && r.data;
        var passes = d && d.passes;
        /* The function before passes per folder answered one pass over the
           whole of content/ on the root; it is set as it always was, so a
           page served before the function is deployed keeps its media. */
        if (d && !passes && d.signature) passes = [{ path: '/', policy: d.policy, signature: d.signature }];
        if (!r || r.error || !d || d.off || !passes || !passes.length) { resolve(false); return; }
        var age = Math.max(60, d.expires - Math.floor(Date.now() / 1000));
        /* A pass for the whole of content/ left on the root by an earlier
           page is taken away unless this one is a colleague's. */
        if (!passes.some(function (x) { return x.path === '/' || x.path === '/content/'; })) {
          CF.forEach(function (n) { put(n, '', 0); put(n, '', 0, '/content/'); });
        }
        // Only a folder under content/, never another path on adspace.me.
        passes = passes.filter(function (x) { return x.path === '/' || FOLDER.test(String(x.path || '')); });
        var now = passes.map(function (x) { return x.path; });
        known().forEach(function (path) { if (now.indexOf(path) < 0 && FOLDER.test(path)) drop(path); });
        passes.forEach(function (x) {
          put('CloudFront-Policy', x.policy, age, x.path);
          put('CloudFront-Signature', x.signature, age, x.path);
          put('CloudFront-Key-Pair-Id', d.keyPairId, age, x.path);
        });
        remember(now.filter(function (path) { return path !== '/' && path !== '/content/'; }));
        put(UNTIL, String(d.expires), age);
        put(FOR, tagOf(proof), age);
        resolve(true);
      }).catch(function () { resolve(false); });
    }).then(function (ok) { clearTimeout(timer); inflight = null; return ok; });
    return inflight;
  }
  /* What the page proved: { review: key, passcode }, { campaign: key,
     passcode }, { creator: code }, or {} for a signed-in colleague. The
     promise always resolves; a page draws on it either way. */
  function pass(p) {
    proof = p || {};
    return ask(false);
  }
  /* A file under content/ that did not load: its folder's cookies are taken
     away (one left by another page's pass), and the pass is asked again. */
  function renew(src) {
    if (!isOn() || !proof) return Promise.resolve(false);
    var f = folderOf(src);
    if (f) drop(f);
    return ask(true);
  }
  /* The pass as it stands, asked only where it is not fresh. */
  function ready() { return ask(false); }

  function again(media) {
    if (media.tagName === 'IMG') {
      var s = media.getAttribute('src');
      media.addEventListener('load', function () { media.removeAttribute('data-pass-tried'); }, { once: true });
      media.removeAttribute('src');
      setTimeout(function () { media.setAttribute('src', s); }, 0);
      return;
    }
    var at = media.currentTime || 0;
    media.addEventListener('loadedmetadata', function () {
      media.removeAttribute('data-pass-tried');
      if (at > 0) {
        try { media.currentTime = at; } catch (e) { /* not seekable yet */ }
        var p = media.play();
        if (p && p.catch) p.catch(function () {});
      }
    }, { once: true });
    media.load();
  }

  // Only a page listens: the conversion's own tests load this file without one.
  if (typeof document !== 'undefined') document.addEventListener('error', function (e) {
    if (!isOn() || !proof) return;
    var el = e.target;
    if (!el || !el.tagName) return;
    var media = el.tagName === 'SOURCE' ? el.parentNode : el;
    if (!media || (media.tagName !== 'IMG' && media.tagName !== 'VIDEO')) return;
    var src = el.tagName === 'SOURCE' ? el.getAttribute('src')
      : (media.currentSrc || media.getAttribute('src'));
    if (!CONTENT.test(src || '')) return;
    // A converted copy not made yet fails by design; the original follows it.
    if (el.tagName === 'SOURCE' && /\.web\.mp4$/i.test(src)) return;
    if (media.getAttribute('data-pass-tried')) return;
    /* A pass that is still good and was asked for a moment ago is not the
       cause, unless another page left its own cookies on the file's folder:
       those are taken away and the file is loaded once more. */
    if (fresh(5 * 60 * 1000) && Date.now() - lastAsk < 60000) {
      var f = folderOf(src);
      if (!f || known().indexOf(f) >= 0) return;
      media.setAttribute('data-pass-tried', '1');
      e.stopImmediatePropagation();
      drop(f);
      again(media);
      return;
    }
    media.setAttribute('data-pass-tried', '1');
    // The page's own fallback (an onerror) waits for the answer.
    e.stopImmediatePropagation();
    renew(src).then(function (ok) {
      if (ok) again(media);
      else el.dispatchEvent(new Event('error'));
    });
  }, true);

  if (typeof document !== 'undefined') {
    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState === 'visible') ask(false);
    });
    setInterval(function () { if (document.visibilityState === 'visible') ask(false); }, 30 * 60 * 1000);
  }

  window.ADspaceMedia = { webOf: webOf, sources: sources, tag: tag, still: still, attach: attach, pass: pass, renew: renew, ready: ready };
})();
