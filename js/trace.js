/* The viewer's trace (2026-11-24, the user: option B, "but not to overlay
   the texts"). On a screen holding a colleague's personal data (Personnel,
   a salary, an NRIC or photograph, a performance review), the reader's own
   name, sign-in email and the time it was drawn (Malaysia's clock) are
   tiled faintly across it, so a photograph or screenshot of the screen
   names who opened it. It deters and traces; it is not access control.

   One mechanism: any element carrying `data-trace` is traced, whoever drew
   it. A canvas laid over the element (`.trace-ink`, aria-hidden, no
   pointer, never printed) draws the line at about -24°, then clears every
   line of words and every control inside the element, so the mark shows
   only in the gaps between and around them and never under a word: the
   words keep their own ground and contrast. A picture (a scan) is not
   cleared. The canvas is drawn again whenever what it covers moves. */
(function () {
  'use strict';

  var ANGLE = -24 * Math.PI / 180;
  /* What is cleared besides a run of words: every control and glyph. A
     picture is left under the mark. */
  var SOLID = 'button,input,select,textarea,label,a,[role="button"],[role="switch"],[role="tab"],svg,.chip,.tab-n,.otp-cell,.plink';
  var PAD = 4;
  var hosts = [];
  var stamp = '';

  function viewer() {
    var A = window.ADspaceAdmin, m = A && A.me ? A.me() : null;
    if (!m || !m.email) return '';
    var C = window.ADspaceClock, now = new Date().toISOString();
    var when = C ? (C.date(C.today()) + ', ' + C.clock(now)) : '';
    return [m.name, m.email, when].filter(Boolean).join('  ·  ');
  }

  function visible(el) {
    if (!el || !el.getClientRects().length) return false;
    var s = getComputedStyle(el);
    return s.visibility !== 'hidden' && Number(s.opacity) > 0;
  }

  /* Each box to clear, as rectangles in the canvas's own pixels. */
  function boxes(h, origin, k) {
    var out = [];
    var push = function (r) {
      if (!r || r.width <= 0 || r.height <= 0) return;
      out.push([(r.left - origin.left) / k - PAD, (r.top - origin.top) / k - PAD,
        r.width / k + PAD * 2, r.height / k + PAD * 2]);
    };
    var walk = document.createTreeWalker(h.el, NodeFilter.SHOW_TEXT, {
      acceptNode: function (n) {
        return /\S/.test(n.nodeValue) && n.parentNode !== h.canvas ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
      }
    });
    var range = document.createRange(), n;
    while ((n = walk.nextNode())) {
      if (!visible(n.parentElement)) continue;
      range.selectNodeContents(n);
      Array.prototype.forEach.call(range.getClientRects(), push);
    }
    Array.prototype.forEach.call(h.el.querySelectorAll(SOLID), function (el) {
      if (el.closest('svg') && el.tagName.toLowerCase() !== 'svg') return;
      if (visible(el)) push(el.getBoundingClientRect());
    });
    return out;
  }

  function draw(h) {
    h.queued = false;
    var cv = h.canvas, el = h.el;
    if (!el.isConnected) return;
    var w = el.clientWidth, ht = el.clientHeight;
    /* A host still arriving (a sheet fading in) is drawn all the same. */
    var none = function () { cv.width = 0; cv.height = 0; cv.style.width = '0'; cv.style.height = '0'; };
    if (!w || !ht || !el.getClientRects().length || getComputedStyle(el).visibility === 'hidden') { none(); return; }
    var line = h.line || (h.line = viewer());
    if (!line) { none(); return; }
    cv.setAttribute('data-trace-line', line);
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    ht = Math.min(ht, 12000);
    if (cv.width !== Math.round(w * dpr) || cv.height !== Math.round(ht * dpr)) {
      cv.width = Math.round(w * dpr); cv.height = Math.round(ht * dpr);
    }
    cv.style.width = w + 'px'; cv.style.height = ht + 'px';
    var ctx = cv.getContext('2d');
    if (!ctx) return;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, cv.width, cv.height);
    var cs = getComputedStyle(cv);
    /* Its face and size are the stylesheet's (`.trace-ink`, smaller on a
       phone); the tiles stand apart by the size. */
    var size = parseFloat(cs.fontSize) || 12;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.fillStyle = cs.color;
    ctx.font = cs.fontWeight + ' ' + size + 'px ' + cs.fontFamily;
    ctx.textBaseline = 'middle';
    var tw = ctx.measureText(line).width;
    var sx = tw + size * 5, sy = size * 7.5;
    var diag = Math.sqrt(w * w + ht * ht) / 2 + sx;
    ctx.save();
    ctx.translate(w / 2, ht / 2);
    ctx.rotate(ANGLE);
    for (var y = -diag, row = 0; y <= diag; y += sy, row++) {
      for (var x = -diag - (row % 2 ? sx / 2 : 0); x <= diag; x += sx) ctx.fillText(line, x, y);
    }
    ctx.restore();
    /* The knockout: nothing of the mark under a word or a control. */
    var origin = cv.getBoundingClientRect();
    var k = cv.offsetWidth ? origin.width / cv.offsetWidth : 1;
    boxes(h, origin, k || 1).forEach(function (b) { ctx.clearRect(b[0], b[1], b[2], b[3]); });
  }

  function queue(h) {
    if (h.queued) return;
    h.queued = true;
    requestAnimationFrame(function () { draw(h); });
  }

  function attach(el) {
    if (getComputedStyle(el).position === 'static') el.classList.add('trace-host');
    var cv = document.createElement('canvas');
    cv.className = 'trace-ink';
    cv.setAttribute('aria-hidden', 'true');
    el.appendChild(cv);
    var h = { el: el, canvas: cv, queued: false, line: '' };
    var again = function () { queue(h); };
    h.mo = new MutationObserver(function (list) {
      if (list.some(function (m) { return m.target !== cv; })) {
        /* What it covers changed: the cover keeps the canvas last, and the
           time is the time this was drawn. */
        if (el.lastElementChild !== cv) el.appendChild(cv);
        h.line = '';
        again();
      }
    });
    h.mo.observe(el, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ['hidden', 'class', 'open', 'style', 'aria-expanded'] });
    if (window.ResizeObserver) { h.ro = new ResizeObserver(again); h.ro.observe(el); }
    h.scroll = again;
    el.addEventListener('scroll', again, true);
    el.addEventListener('transitionend', again, true);
    el.addEventListener('animationend', again, true);
    el.addEventListener('load', again, true);
    hosts.push(h);
    queue(h);
  }

  function detach(h) {
    if (h.mo) h.mo.disconnect();
    if (h.ro) h.ro.disconnect();
    h.el.removeEventListener('scroll', h.scroll, true);
    h.el.removeEventListener('transitionend', h.scroll, true);
    h.el.removeEventListener('animationend', h.scroll, true);
    h.el.removeEventListener('load', h.scroll, true);
    if (h.canvas.parentNode) h.canvas.parentNode.removeChild(h.canvas);
    h.el.classList.remove('trace-host');
  }

  function scan() {
    hosts = hosts.filter(function (h) {
      if (h.el.isConnected && h.el.hasAttribute('data-trace')) return true;
      detach(h); return false;
    });
    Array.prototype.forEach.call(document.querySelectorAll('[data-trace]'), function (el) {
      if (!hosts.some(function (h) { return h.el === el; })) attach(el);
    });
  }
  var scanning = false;
  function soon() {
    if (scanning) return;
    scanning = true;
    requestAnimationFrame(function () { scanning = false; scan(); });
  }

  function all() { hosts.forEach(function (h) { h.line = ''; queue(h); }); }

  function start() {
    scan();
    new MutationObserver(soon).observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['data-trace'] });
    /* A theme chosen, a window turned, a face arrived: drawn again. */
    new MutationObserver(all).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
    window.addEventListener('resize', all);
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(all);
  }
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);

  window.ADspaceTrace = { redraw: all, line: viewer };
})();
