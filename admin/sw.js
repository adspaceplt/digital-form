/* The console's service worker. It exists to make the console installable and
   to answer a lost connection with a page that says so; it caches nothing
   else.

   Deliberately not a cache of the portal. Every script and stylesheet carries
   a `?v=` stamp that changes on each release, and a worker that served them
   from its own store would serve yesterday's console to anybody whose worker
   had not updated yet. So a request goes to the network as it always did, and
   only a page load that cannot reach the network is answered from here, with
   the one page this file keeps. Scope is /admin/: the client pages and the
   root site are never touched.

   One more thing it holds: a PDF the console has just drawn, for an hour,
   at /admin/file/{id}/{its name}.pdf (the user, 2026-10-07: an iPhone named
   every previewed PDF Unknown.pdf, because a blob: address has no name;
   Safari names a file after the last part of its address). The page hands
   the file over by message and opens that address; nothing else is kept. */
var VERSION = 'adspace-console-20261007a';
var FILES = 'adspace-files';
var FILE_PATH = '/admin/file/';
var FILE_HOURS = 1;
// A colleague's notifications, shown and opened (the one copy for every page).
importScripts('/js/push-sw.js');
var OFFLINE = '/admin/offline.html';
var KEEP = [OFFLINE, '/admin/icons/wordmark.png'];

self.addEventListener('install', function (e) {
  e.waitUntil(caches.open(VERSION).then(function (c) { return c.addAll(KEEP); }).then(function () {
    return self.skipWaiting();
  }));
});

self.addEventListener('activate', function (e) {
  e.waitUntil(caches.keys().then(function (keys) {
    return Promise.all(keys.filter(function (k) { return k !== VERSION && k !== FILES; }).map(function (k) { return caches.delete(k); }));
  }).then(function () { return self.clients.claim(); }));
});

/* A drawn file, kept under its own name; files older than an hour go. */
self.addEventListener('message', function (e) {
  var d = e.data || {}, port = e.ports && e.ports[0];
  if (d.type !== 'adspace-file' || !d.path || !d.blob || d.path.indexOf(FILE_PATH) !== 0) return;
  var res = new Response(d.blob, { headers: {
    'Content-Type': d.blob.type || 'application/pdf',
    'Content-Disposition': 'inline; filename*=UTF-8\'\'' + encodeURIComponent(d.name || 'file.pdf'),
    'X-Kept-At': String(Date.now()), 'Cache-Control': 'no-store' } });
  e.waitUntil(caches.open(FILES).then(function (c) {
    return c.put(d.path, res).then(function () {
      if (port) port.postMessage({ ok: true });
      return c.keys().then(function (reqs) {
        return Promise.all(reqs.map(function (q) {
          return c.match(q).then(function (m) {
            var at = Number(m && m.headers.get('X-Kept-At')) || 0;
            if (Date.now() - at > FILE_HOURS * 3600000) return c.delete(q);
          });
        }));
      });
    });
  }).catch(function () { if (port) port.postMessage({ ok: false }); }));
});

self.addEventListener('fetch', function (e) {
  var r = e.request;
  if (r.method !== 'GET') return;
  var url = new URL(r.url);
  if (url.origin !== self.location.origin) return;
  if (url.pathname.indexOf(FILE_PATH) === 0) {
    e.respondWith(caches.open(FILES).then(function (c) { return c.match(url.pathname); }).then(function (m) {
      return m || new Response('This file is no longer held. Draw it again from the console.', { status: 404, headers: { 'Content-Type': 'text/plain' } });
    }));
    return;
  }
  // What the offline page itself needs, from the store it was put in.
  if (KEEP.indexOf(url.pathname) !== -1 && !url.search) {
    e.respondWith(fetch(r).catch(function () { return caches.match(url.pathname); }));
    return;
  }
  if (r.mode !== 'navigate') return;
  e.respondWith(fetch(r).catch(function () {
    return caches.match(OFFLINE).then(function (res) {
      return res || new Response('Offline', { status: 503, headers: { 'Content-Type': 'text/plain' } });
    });
  }));
});
