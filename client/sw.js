/* The client portal's service worker: it holds one thing, a PDF the page has
   just drawn, at /client/file/{id}/{its name} for an hour, so an iPhone's
   Save to Files keeps the file's name (js/file-sw.js). It caches nothing
   else and answers no other request. Scope is /client/. */
importScripts('/js/file-sw.js?v=20261007a');
self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (e) { e.waitUntil(self.clients.claim()); });
