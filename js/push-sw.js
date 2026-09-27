/*
 * The notification half of a service worker, one copy for the three workers
 * that take it: /admin/sw.js, /creators/sw.js and /creator/sw.js, each
 * through importScripts. A message arrives sealed from push-send as
 * { title, body, url, tag }; it is shown at once (a push the page does not
 * show is one the browser stops delivering), and a press opens its address,
 * in a window of this page already open where there is one.
 */
self.addEventListener('push', function (e) {
  var d = {};
  try { d = e.data ? e.data.json() : {}; } catch (x) { d = { body: e.data ? e.data.text() : '' }; }
  var opts = {
    body: d.body || '',
    icon: '/admin/icons/icon-192.png',
    data: { url: d.url || self.registration.scope }
  };
  // One notification per thing: a newer word about the same booking or task
  // replaces the older one, and still sounds.
  if (d.tag) { opts.tag = d.tag; opts.renotify = true; }
  e.waitUntil(self.registration.showNotification(d.title || 'ADspace', opts));
});

self.addEventListener('notificationclick', function (e) {
  e.notification.close();
  var want = new URL((e.notification.data && e.notification.data.url) || self.registration.scope, self.location.origin).href;
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (list) {
    var i, c;
    for (i = 0; i < list.length; i++) {
      c = list[i];
      if (c.url === want && 'focus' in c) return c.focus();
    }
    for (i = 0; i < list.length; i++) {
      c = list[i];
      if (c.url.indexOf(self.registration.scope) === 0 && 'navigate' in c) {
        return c.navigate(want).then(function (w) { return w && w.focus ? w.focus() : w; });
      }
    }
    return self.clients.openWindow ? self.clients.openWindow(want) : null;
  }));
});
