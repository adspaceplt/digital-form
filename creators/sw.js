/* The creators page's service worker. It exists only to receive notifications
   (js/push-sw.js) and caches nothing, so every release reaches the page on
   its next load. Scope is /creators/: no other page is touched. */
importScripts('/js/push-sw.js');
self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (e) { e.waitUntil(self.clients.claim()); });
