/* ADspace Digital Portal — reloading the installed console.

   The console installs as an app (admin/manifest.webmanifest), and an app
   opened from the home screen has no address bar and no reload button, so
   two ways back to a fresh page live here (the brief of 2026-09-26).

   1. Pull to refresh. On a list, with the page at its top, a finger drawn
      down past the mark and let go asks the service worker to check for a
      new copy and reloads. Only in the installed app: in a browser tab the
      browser draws its own, and two would fight over one gesture. Never while
      a sheet, a menu or a record is open, where a pull is a scroll through
      something being worked on and a reload would throw typed work away.
      It clears nothing.

   2. Refresh app, in the account menu. For a console that is stuck on an
      old copy: it takes the service worker off, empties the Cache Storage
      and reloads. It never touches localStorage, IndexedDB or the sign-in,
      so the person comes back signed in, in the theme and the folds they
      chose. */
(function () {
  'use strict';

  function standalone() {
    try {
      return (window.matchMedia && matchMedia('(display-mode: standalone)').matches) || navigator.standalone === true;
    } catch (e) { return false; }
  }

  /* A record, a task, a report or a content set in the address is a thing
     being worked on, not a list. */
  var RECORD = ['client', 'campaign', 'task', 'open', 'report', 'set', 'new'];
  function onList() {
    var q = new URLSearchParams(location.search);
    for (var i = 0; i < RECORD.length; i++) if (q.get(RECORD[i])) return false;
    return true;
  }
  function busy() {
    if (window.ADspaceSheet && window.ADspaceSheet.isOpen && window.ADspaceSheet.isOpen()) return true;
    if (document.querySelector('.sheet:not([hidden]), .kmenu:not([hidden]), .sidebar.is-open')) return true;
    return false;
  }

  function reload() {
    var go = function () { location.reload(); };
    try {
      if (!('serviceWorker' in navigator)) { go(); return; }
      var done = false;
      var once = function () { if (!done) { done = true; go(); } };
      setTimeout(once, 1500);
      navigator.serviceWorker.getRegistration('/admin/').then(function (reg) {
        if (!reg) { once(); return; }
        return reg.update().then(once, once);
      }).catch(once);
    } catch (e) { go(); }
  }

  /* ---- Refresh app ----------------------------------------------------- */
  function hard() {
    var jobs = [];
    try {
      if ('serviceWorker' in navigator && navigator.serviceWorker.getRegistrations) {
        jobs.push(navigator.serviceWorker.getRegistrations().then(function (list) {
          return Promise.all(list.map(function (r) { return r.unregister(); }));
        }));
      }
      if (window.caches && caches.keys) {
        jobs.push(caches.keys().then(function (keys) {
          return Promise.all(keys.map(function (k) { return caches.delete(k); }));
        }));
      }
    } catch (e) {}
    var go = function () { location.reload(); };
    Promise.all(jobs).then(go, go);
    setTimeout(go, 3000);
  }

  /* ---- Pull to refresh ------------------------------------------------- */
  var LIMIT = 64;          // how far the mark travels before a release reloads
  var mark = null, startY = 0, startX = 0, pulling = false, dist = 0, armed = false;

  function drawMark() {
    if (mark) return mark;
    mark = document.createElement('div');
    mark.className = 'pullmark';
    mark.setAttribute('aria-hidden', 'true');
    mark.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M20 11a8 8 0 1 0-2.3 5.7"/><path d="M20 4v7h-7"/></svg>';
    document.body.appendChild(mark);
    return mark;
  }
  function show(d) {
    var m = drawMark();
    var p = Math.min(1, d / LIMIT);
    m.style.transform = 'translate(-50%, ' + Math.round(Math.min(d, LIMIT + 16)) + 'px) rotate(' + Math.round(p * 270) + 'deg)';
    m.style.opacity = String(Math.min(1, p * 1.4));
    m.classList.toggle('is-armed', d >= LIMIT);
  }
  function hide() {
    if (!mark) return;
    mark.classList.remove('is-armed', 'is-busy');
    mark.style.transform = '';
    mark.style.opacity = '';
  }

  function wirePull() {
    if (!('ontouchstart' in window)) return;
    document.addEventListener('touchstart', function (e) {
      pulling = false; armed = false; dist = 0;
      if (e.touches.length !== 1 || !standalone() || !onList() || busy()) return;
      if ((window.scrollY || document.documentElement.scrollTop) > 0) return;
      var t = e.target;
      /* A gesture that belongs to something else: a board drag, a strip that
         scrolls sideways, a field. */
      if (t.closest && t.closest('input, textarea, select, .bcard-grip, .board, .cmdbar-views, .rectabs, .tabrow')) return;
      startY = e.touches[0].clientY; startX = e.touches[0].clientX;
      pulling = true;
    }, { passive: true });
    document.addEventListener('touchmove', function (e) {
      if (!pulling) return;
      var dy = e.touches[0].clientY - startY, dx = e.touches[0].clientX - startX;
      /* A move that has not gone anywhere yet (a finger settling) is not a
         change of mind; going up, sideways or scrolling the page is. */
      if (dy === 0 && Math.abs(dx) < 4) return;
      if (dy < 0 || Math.abs(dx) > dy || (window.scrollY || document.documentElement.scrollTop) > 0) {
        hide();
        pulling = false; dist = 0; armed = false;
        return;
      }
      dist = dy * 0.5;          // resistance, so the mark trails the finger
      armed = dist >= LIMIT;
      show(dist);
    }, { passive: true });
    var end = function () {
      if (!pulling) return;
      pulling = false;
      if (armed) {
        var m = drawMark();
        m.classList.add('is-busy');
        m.style.transform = 'translate(-50%, ' + LIMIT + 'px)';
        m.style.opacity = '1';
        reload();
      } else hide();
      dist = 0; armed = false;
    };
    document.addEventListener('touchend', end, { passive: true });
    document.addEventListener('touchcancel', function () { pulling = false; hide(); }, { passive: true });
  }

  window.ADspaceRefresh = { hard: hard, reload: reload, standalone: standalone };
  wirePull();
})();
