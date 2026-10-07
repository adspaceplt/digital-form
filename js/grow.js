/*
 * Every typed box grows with its words.
 *
 * The user, 2026-10-07, typing an announcement on an iPhone: "Cell not
 * increasing as i typed? Why still these issues again". The review page and
 * a performance review had each grown their own boxes, and every other
 * textarea on every page kept the height it was drawn at, so a long line was
 * written into two rows with the rest out of sight. One rule here, for every
 * textarea on every page that loads this file:
 *
 * · it grows with what it holds, up to 60% of the screen, then scrolls;
 * · it is measured as it is typed in, as it comes into view holding words
 *   (a sheet opened on a saved value or a restored draft), when a page sets
 *   its value, and when the window changes width;
 * · shrinking to measure never moves the page or the sheet under the reader:
 *   every scroller around the box keeps its place;
 * · `data-nogrow` keeps a box at its drawn height.
 *
 * `ADspaceGrow.fit(el)` fits one box, or every box inside an element.
 */
(function () {
  var CAP = 0.6;

  function screenHeight() {
    return window.visualViewport ? window.visualViewport.height : window.innerHeight;
  }

  function one(t) {
    if (!t || t.tagName !== 'TEXTAREA' || t.hasAttribute('data-nogrow') || !t.offsetParent) return;
    var cs = getComputedStyle(t);
    var edge = (parseFloat(cs.borderTopWidth) || 0) + (parseFloat(cs.borderBottomWidth) || 0);
    var cap = Math.max(Math.round(screenHeight() * CAP), parseFloat(cs.minHeight) || 0);
    /* Measuring sets the box to its natural height for a moment; a scroller
       around it would jump to make up the difference, so each is put back. */
    var kept = [];
    for (var p = t.parentElement; p; p = p.parentElement) {
      if (p.scrollTop) kept.push([p, p.scrollTop]);
    }
    var root = document.scrollingElement;
    var rootTop = root ? root.scrollTop : 0;
    t.style.height = 'auto';
    var want = t.scrollHeight + edge;
    t.style.height = Math.min(want, cap) + 'px';
    t.style.overflowY = want > cap ? 'auto' : 'hidden';
    kept.forEach(function (k) { k[0].scrollTop = k[1]; });
    if (root && root.scrollTop !== rootTop) root.scrollTop = rootTop;
  }

  function fit(el) {
    if (!el) return;
    if (el.tagName === 'TEXTAREA') { one(el); return; }
    if (el.querySelectorAll) Array.prototype.forEach.call(el.querySelectorAll('textarea'), one);
  }

  /* As it is typed in. */
  document.addEventListener('input', function (e) { one(e.target); }, true);
  document.addEventListener('focusin', function (e) { one(e.target); }, true);

  /* As it comes into view holding words: a box drawn inside a hidden sheet
     measures nothing until the sheet opens. */
  var seen = typeof IntersectionObserver === 'function'
    ? new IntersectionObserver(function (list) {
        list.forEach(function (x) { if (x.isIntersecting) one(x.target); });
      })
    : null;
  function watch(root) {
    if (!seen || !root || !root.querySelectorAll) return;
    if (root.tagName === 'TEXTAREA') { seen.observe(root); return; }
    Array.prototype.forEach.call(root.querySelectorAll('textarea'), function (t) { seen.observe(t); });
  }
  function start() {
    watch(document.body);
    if (typeof MutationObserver === 'function') {
      new MutationObserver(function (list) {
        list.forEach(function (m) { Array.prototype.forEach.call(m.addedNodes, watch); });
      }).observe(document.body, { childList: true, subtree: true });
    }
  }
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);

  /* When a page sets its value (a saved caption, a draft written by the AI,
     a restored draft): the native setter, then a fit once it has drawn. */
  var proto = window.HTMLTextAreaElement && HTMLTextAreaElement.prototype;
  var desc = proto && Object.getOwnPropertyDescriptor(proto, 'value');
  if (desc && desc.set && desc.configurable) {
    Object.defineProperty(proto, 'value', {
      configurable: true, enumerable: desc.enumerable,
      get: function () { return desc.get.call(this); },
      set: function (v) {
        desc.set.call(this, v);
        var t = this;
        if (window.requestAnimationFrame) requestAnimationFrame(function () { one(t); }); else one(t);
      }
    });
  }

  /* When the width changes, the words wrap again. */
  var wide = 0;
  window.addEventListener('resize', function () {
    var w = window.innerWidth;
    if (w === wide) return;
    wide = w;
    fit(document.body);
  });

  window.ADspaceGrow = { fit: fit };
})();
