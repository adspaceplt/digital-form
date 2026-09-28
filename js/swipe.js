/* ADspace swipe — a sideways swipe moves to the next or the previous tab.
 *
 * Asked for by the user on 2026-09-27 for the phone and the installed app:
 * every tab strip (a record's panes, My Work's views, Campaigns and the
 * Creators List, Team, the Activity record) answers a swipe across the page
 * by pressing the tab beside the chosen one, so a swipe does exactly what a
 * tap on that tab does: the address, Back, the parts a person may not open.
 *
 * A region names its strip, `data-swipe="<strip id>"`, and the nearest region
 * around the touch whose strip is on the screen answers it. A swipe is left
 * alone where it is something else:
 *   - it starts within 24px of either edge (the system's back gesture);
 *   - it starts on a field, a select, editable text, a drag grip, media, or
 *     anything marked `data-noswipe`;
 *   - it starts inside anything that scrolls sideways (the strip itself, a
 *     board, a wide table), which keeps its own scroll;
 *   - a ⋯ menu is open, text is selected, or the rail drawer is open;
 *   - it starts in a sheet that has no strip of its own (a sheet with one,
 *     the Activity record, is its own region);
 *   - it is not plainly sideways (the first 10px decide: across by one and a
 *     half times the down), too short (under 56px, or a fifth of the screen)
 *     or too slow (over 0.8s).
 *
 *   <div data-swipe="crmTabs"> … <nav id="crmTabs"> <button class="tab"> …
 *
 * A region may name a pair of buttons instead of a strip, and the swipe
 * presses one of them: the Review Canvas steps through a set this way
 * (the user, 2026-09-28). The finger moving left presses Next, as a strip's
 * next tab and every photo viewer do; a disabled button is left alone.
 * `data-swipe-media` lets a swipe start on a post's video, except over its
 * own controls along the foot.
 *
 *   <div data-swipe-prev="canvasPrev" data-swipe-next="canvasNext" data-swipe-media>
 */
(function () {
  'use strict';

  var EDGE = 24, LOCK = 10, MIN = 56, SLOW = 800;
  var FIELDS = 'input, textarea, select, [contenteditable=""], [contenteditable="true"], ' +
               '.bcard-grip, canvas, [data-noswipe]';
  var CONTROLS = 56;
  var start = null;

  function tabsOf(strip) {
    return Array.prototype.filter.call(strip.children, function (b) {
      return (b.classList.contains('tab') || b.classList.contains('acttab')) &&
        !b.hidden && !b.disabled && b.getClientRects().length > 0;
    });
  }
  function shown(b) { return b && !b.hidden && b.getClientRects().length > 0; }
  function regionOf(el) {
    for (var n = el; n && n.nodeType === 1; n = n.parentElement) {
      var nx = n.getAttribute('data-swipe-next');
      if (nx) {
        var prev = document.getElementById(n.getAttribute('data-swipe-prev') || ''),
            next = document.getElementById(nx);
        if (shown(prev) || shown(next)) return { el: n, prev: prev, next: next };
        continue;
      }
      var id = n.getAttribute('data-swipe');
      if (!id) continue;
      var strip = document.getElementById(id);
      if (strip && strip.getClientRects().length && tabsOf(strip).length > 1) return { el: n, strip: strip };
    }
    return null;
  }
  /* Anything between the touch and the region that scrolls sideways keeps
     the gesture: a strip wider than the screen, a board, a wide table. */
  function scrollsAcross(el, stop) {
    for (var n = el; n && n !== stop && n.nodeType === 1; n = n.parentElement) {
      if (n.scrollWidth > n.clientWidth + 1) {
        var o = getComputedStyle(n).overflowX;
        if (o === 'auto' || o === 'scroll') return true;
      }
    }
    return false;
  }

  document.addEventListener('touchstart', function (e) {
    start = null;
    if (!e.touches || e.touches.length !== 1) return;
    var t = e.touches[0], tg = e.target;
    if (!tg || !tg.closest) return;
    if (t.clientX < EDGE || t.clientX > window.innerWidth - EDGE) return;
    if (tg.closest(FIELDS)) return;
    if (document.querySelector('.kmenu:not([hidden]), .sidebar.is-open')) return;
    if (window.getSelection && String(window.getSelection())) return;
    var r = regionOf(tg);
    if (!r) return;
    var media = tg.closest('video, audio');
    if (media) {
      /* A post's video takes the swipe where its region says so, but never
         over its own controls along the foot. */
      if (!r.el.hasAttribute('data-swipe-media')) return;
      if (t.clientY > media.getBoundingClientRect().bottom - CONTROLS) return;
    }
    var sheet = tg.closest('.sheet');
    if (sheet && !sheet.contains(r.el)) return;
    if (scrollsAcross(tg, r.el)) return;
    start = { x: t.clientX, y: t.clientY, at: Date.now(), r: r, across: false };
  }, { passive: true });

  document.addEventListener('touchmove', function (e) {
    if (!start || start.across || !e.touches || !e.touches[0]) return;
    var t = e.touches[0], dx = t.clientX - start.x, dy = t.clientY - start.y;
    if (Math.abs(dx) < LOCK && Math.abs(dy) < LOCK) return;
    if (Math.abs(dx) > Math.abs(dy) * 1.5) start.across = true;
    else start = null;
  }, { passive: true });

  document.addEventListener('touchend', function (e) {
    var s = start;
    start = null;
    if (!s || !s.across || !e.changedTouches || !e.changedTouches[0]) return;
    var t = e.changedTouches[0], dx = t.clientX - s.x, dy = t.clientY - s.y;
    if (Date.now() - s.at > SLOW) return;
    if (Math.abs(dx) < Math.max(MIN, window.innerWidth / 5) || Math.abs(dx) < Math.abs(dy) * 1.5) return;
    if (!s.r.strip) {
      var b = dx < 0 ? s.r.next : s.r.prev;
      if (shown(b) && !b.disabled) b.click();
      return;
    }
    var tabs = tabsOf(s.r.strip), i = -1;
    for (var k = 0; k < tabs.length; k++) if (tabs[k].classList.contains('is-on')) i = k;
    var j = dx < 0 ? i + 1 : i - 1;
    if (i < 0 || j < 0 || j >= tabs.length) return;
    tabs[j].click();
  }, { passive: true });

  document.addEventListener('touchcancel', function () { start = null; }, { passive: true });
})();
