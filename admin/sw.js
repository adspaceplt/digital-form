/* The console's service worker. It makes the console installable, answers a
   lost connection with a page that says so, and keeps the console's own
   files on the phone so the app opens without asking for them again.

   What it keeps (2026-10-26; the user: "frequent delay while trying to open
   the PWA on mobile"): every same-origin file whose address carries a `?v=`
   stamp, answered from the store first. A release changes the stamp, so the
   page asks for a new address, which the store cannot hold yet and fetches;
   yesterday's file is never served for today's address (the risk this file
   was first written against, 2026-09-25). The page itself always goes to
   the network, so a release reaches everybody on their next load; a file
   with no stamp goes to the network as before. Each file is kept once: the
   copy under an older stamp goes when the new one is stored. Measured on a
   throttled phone, a reopen after ten minutes was ready in 2.2s against
   3.4s. Scope is /admin/: the client pages and the root site are never
   touched.

   Navigation preload sends the page's request while the worker starts, so
   a cold worker never holds the page back.

   One more thing it holds: a PDF the console has just drawn, for an hour,
   at /admin/file/{id}/{its name}.pdf (the user, 2026-10-07: an iPhone named
   every previewed PDF Unknown.pdf, because a blob: address has no name;
   Safari names a file after the last part of its address). The page hands
   the file over by message and opens that address (js/file-sw.js). */
var VERSION = 'adspace-console-20261026a';
// The stamped files, kept across worker versions (Refresh app empties it).
var ASSETS = 'adspace-console-assets';
// A colleague's notifications, shown and opened (the one copy for every page).
importScripts('/js/push-sw.js');
// A PDF the console drew, held under its own name (the one copy for both pages).
importScripts('/js/file-sw.js?v=20261031w');
var OFFLINE = '/admin/offline.html';
var KEEP = [OFFLINE, '/admin/icons/wordmark.png'];

self.addEventListener('install', function (e) {
  e.waitUntil(caches.open(VERSION).then(function (c) { return c.addAll(KEEP); }).then(function () {
    return self.skipWaiting();
  }));
});

self.addEventListener('activate', function (e) {
  e.waitUntil(caches.keys().then(function (keys) {
    /* Only the console's own older stores: another page's worker keeps its
       own, and the held files are js/file-sw.js's (audit F7, 2026-10-10). */
    return Promise.all(keys.filter(function (k) { return /^adspace-console/.test(k) && k !== VERSION && k !== ASSETS; }).map(function (k) { return caches.delete(k); }));
  }).then(function () {
    if (self.registration.navigationPreload) return self.registration.navigationPreload.enable().catch(function () {});
  }).then(function () { return self.clients.claim(); }));
});

self.addEventListener('fetch', function (e) {
  var r = e.request;
  if (r.method !== 'GET') return;
  var url = new URL(r.url);
  if (url.origin !== self.location.origin) return;
  // A drawn file is js/file-sw.js's to answer.
  if (url.pathname.indexOf('/admin/file/') === 0) return;
  // What the offline page itself needs, from the store it was put in.
  if (KEEP.indexOf(url.pathname) !== -1 && !url.search) {
    e.respondWith(fetch(r).catch(function () { return caches.match(url.pathname); }));
    return;
  }
  if (r.mode === 'navigate') {
    e.respondWith(Promise.resolve(e.preloadResponse).then(function (res) { return res || fetch(r); }).catch(function () {
      return caches.match(OFFLINE).then(function (res) {
        return res || new Response('Offline', { status: 503, headers: { 'Content-Type': 'text/plain' } });
      });
    }));
    return;
  }
  if (/[?&]v=[^&]+/.test(url.search)) e.respondWith(stamped(r, url));
});

/* A stamped file: from the store, else the network, stored once it answers
   whole and the copy under any other stamp let go. */
function stamped(r, url) {
  return caches.open(ASSETS).then(function (c) {
    return c.match(r).then(function (hit) {
      if (hit) return hit;
      return fetch(r).then(function (res) {
        if (res && res.ok && res.type === 'basic') {
          var copy = res.clone();
          c.keys().then(function (ks) {
            ks.forEach(function (k) {
              var u = new URL(k.url);
              if (u.pathname === url.pathname && u.search !== url.search) c.delete(k);
            });
            return c.put(r, copy);
          }).catch(function () {});
        }
        return res;
      });
    });
  }).catch(function () { return fetch(r); });
}
