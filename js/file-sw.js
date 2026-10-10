/* Files under their own name (2026-10-07; the user: an iPhone named every
   previewed PDF Unknown.pdf). Safari names a file after the last part of its
   address, and a blob: address has none, so a page that drew a PDF hands it
   to its worker by message and opens {scope}file/{id}/{its name}; the worker
   answers that address from Cache Storage for an hour. Nothing else is held:
   never a script, a style or a page. Imported by admin/sw.js and
   client/sw.js; registered for the console and the client portal. */
var ADSPACE_FILES = 'adspace-files';
var ADSPACE_FILE_HOURS = 1;
function adspaceFilePath() { return new URL(self.registration.scope).pathname + 'file/'; }

self.addEventListener('message', function (e) {
  var d = e.data || {}, port = e.ports && e.ports[0];
  if (d.type !== 'adspace-file' || !d.path || !d.blob || d.path.indexOf(adspaceFilePath()) !== 0) return;
  var res = new Response(d.blob, { headers: {
    'Content-Type': d.blob.type || 'application/pdf',
    'Content-Disposition': "inline; filename*=UTF-8''" + encodeURIComponent(d.name || 'file.pdf'),
    'X-Kept-At': String(Date.now()), 'Cache-Control': 'no-store' } });
  e.waitUntil(caches.open(ADSPACE_FILES).then(function (c) {
    return c.put(d.path, res).then(function () {
      if (port) port.postMessage({ ok: true });
      return c.keys().then(function (reqs) {
        return Promise.all(reqs.map(function (q) {
          return c.match(q).then(function (m) {
            var at = Number(m && m.headers.get('X-Kept-At')) || 0;
            if (Date.now() - at > ADSPACE_FILE_HOURS * 3600000) return c.delete(q);
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
  if (url.origin !== self.location.origin || url.pathname.indexOf(adspaceFilePath()) !== 0) return;
  /* The hour is kept on every read, not only when another file arrives: a
     file past it is let go and never answered (audit F6, 2026-10-10). */
  var gone = function () { return new Response('This file is no longer held. Open it again from the page.', { status: 404, headers: { 'Content-Type': 'text/plain' } }); };
  e.respondWith(caches.open(ADSPACE_FILES).then(function (c) {
    return c.match(url.pathname).then(function (m) {
      if (!m) return gone();
      var at = Number(m.headers.get('X-Kept-At')) || 0;
      if (Date.now() - at > ADSPACE_FILE_HOURS * 3600000) return c.delete(url.pathname).then(gone, gone);
      return m;
    });
  }));
});
