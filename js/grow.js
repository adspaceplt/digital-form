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
 * The handle at a box's corner (the user, the same day: "The drag handle is
 * good to add in longer text cells but it should compromise the viewbox and
 * couldnt be drag around like a toy the purpose is to just expand the textbox
 * input longer larger") only makes a box taller: it never moves sideways
 * (`resize: vertical`, the width the row's), never shrinks a box below the
 * words it holds (its `min-height` is the fitted height), and stops short of
 * the screen's foot (85% of it). A height somebody dragged to is kept while
 * they type (`data-floor`), and forgotten when the page puts new words in.
 *
 * A one-line field that may hold more than its width (a title, a link, a
 * summary line) is a textarea marked `data-oneline`: it reads as a field one
 * line high, wraps its words onto more lines instead of hiding them, never
 * takes a new line (Enter submits its form as a field's Enter would; a pasted
 * line break becomes a space) and carries no handle.
 *
 * `ADspaceGrow.fit(el)` fits one box, or every box inside an element.
 */
(function () {
  var CAP = 0.6;
  var DRAG_CAP = 0.85;

  function screenHeight() {
    return window.visualViewport ? window.visualViewport.height : window.innerHeight;
  }

  /* The height this file last gave each box, so a height that changed under
     a finger is told apart from one this file set. */
  var given = typeof WeakMap === 'function' ? new WeakMap() : null;

  function one(t) {
    if (!t || t.tagName !== 'TEXTAREA' || t.hasAttribute('data-nogrow') || !t.offsetParent) return;
    var cs = getComputedStyle(t);
    var edge = (parseFloat(cs.borderTopWidth) || 0) + (parseFloat(cs.borderBottomWidth) || 0);
    var line = t.hasAttribute('data-oneline');
    var tall = screenHeight();
    var cap = Math.round(tall * CAP);
    var most = line ? cap : Math.max(Math.round(tall * DRAG_CAP), cap);
    var floor = line ? 0 : (parseFloat(t.getAttribute('data-floor')) || 0);
    /* Measuring sets the box to its natural height for a moment; a scroller
       around it would jump to make up the difference, so each is put back. */
    var kept = [];
    for (var p = t.parentElement; p; p = p.parentElement) {
      if (p.scrollTop) kept.push([p, p.scrollTop]);
    }
    var root = document.scrollingElement;
    var rootTop = root ? root.scrollTop : 0;
    t.style.minHeight = '';
    t.style.maxHeight = '';
    t.style.height = 'auto';
    var want = t.scrollHeight + edge;
    var fitted = Math.max(Math.min(want, cap), parseFloat(getComputedStyle(t).minHeight) || 0);
    var h = Math.min(Math.max(fitted, floor), Math.max(most, fitted));
    t.style.height = h + 'px';
    t.style.overflowY = want > h ? 'auto' : 'hidden';
    /* The handle's reach: never below the words, never past the screen. */
    t.style.minHeight = fitted + 'px';
    t.style.maxHeight = Math.max(most, fitted) + 'px';
    if (given) given.set(t, h);
    kept.forEach(function (k) { k[0].scrollTop = k[1]; });
    if (root && root.scrollTop !== rootTop) root.scrollTop = rootTop;
  }

  function fit(el) {
    if (!el) return;
    if (el.tagName === 'TEXTAREA') { one(el); return; }
    if (el.querySelectorAll) Array.prototype.forEach.call(el.querySelectorAll('textarea'), one);
  }

  /* As it is typed in. A one-line field never holds a line break: a pasted
     one becomes a space, the caret kept where it was. */
  document.addEventListener('input', function (e) {
    var t = e.target;
    if (t && t.tagName === 'TEXTAREA' && t.hasAttribute('data-oneline') && /[\r\n]/.test(t.value)) {
      var at = t.selectionStart;
      var before = t.value.slice(0, at).replace(/\s*[\r\n]+\s*/g, ' ');
      t.value = before + t.value.slice(at).replace(/\s*[\r\n]+\s*/g, ' ');
      try { t.setSelectionRange(before.length, before.length); } catch (x) { /* not focused */ }
    }
    one(t);
  }, true);
  document.addEventListener('focusin', function (e) { one(e.target); }, true);

  /* Enter in a one-line field is a field's Enter: it never makes a new line,
     and inside a form it submits it. A page that listens for Enter on the
     field itself (an in-place rename) hears it first and decides; Cmd or
     Ctrl + Enter stays js/sheet.js's. */
  document.addEventListener('keydown', function (e) {
    var t = e.target;
    if (e.key !== 'Enter' || e.isComposing || e.metaKey || e.ctrlKey) return;
    if (!t || t.tagName !== 'TEXTAREA' || !t.hasAttribute('data-oneline')) return;
    if (e.defaultPrevented) return;
    e.preventDefault();
    /* As a field's own Enter: only a form with a button to submit it is
       submitted (the browser's implicit submission), and through that
       button. */
    var f = t.form;
    var b = f && f.querySelector('button[type="submit"], input[type="submit"], button:not([type])');
    if (b && !b.disabled && !b.hidden) b.click();
  });

  /* A height dragged to with the handle is kept: the corner was pressed on
     this box, and its height is no longer the one this file gave it. */
  var pressed = null;
  document.addEventListener('pointerdown', function (e) {
    var t = e.target;
    pressed = t && t.tagName === 'TEXTAREA' && !t.hasAttribute('data-oneline') ? t : null;
  }, true);
  function release() {
    var t = pressed;
    pressed = null;
    if (!t || !given) return;
    var h = Math.round(t.getBoundingClientRect().height);
    var was = given.get(t);
    if (was != null && Math.abs(h - was) > 1) {
      t.setAttribute('data-floor', String(h));
      one(t);
    }
  }
  document.addEventListener('pointerup', release, true);
  document.addEventListener('pointercancel', release, true);

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
     a restored draft): the native setter, then a fit once it has drawn. New
     words from the page forget a height somebody dragged to. */
  var proto = window.HTMLTextAreaElement && HTMLTextAreaElement.prototype;
  var desc = proto && Object.getOwnPropertyDescriptor(proto, 'value');
  if (desc && desc.set && desc.configurable) {
    Object.defineProperty(proto, 'value', {
      configurable: true, enumerable: desc.enumerable,
      get: function () { return desc.get.call(this); },
      set: function (v) {
        desc.set.call(this, v);
        var t = this;
        if (t.hasAttribute && t.hasAttribute('data-floor')) t.removeAttribute('data-floor');
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
