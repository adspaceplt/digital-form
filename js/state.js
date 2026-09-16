/* The only copy of how a list says it is loading, has nothing in it, or could
   not be read.

   Three pages had written these three states four different ways: a dashed
   box saying "Loading…", a `.msg.err` line under a heading with an empty card
   area beside it, and — the one that actually cost somebody time — a failed
   read reported as an empty list, so "No content sets." and "0 posts" were
   printed over a network fault and sent people to build records that were
   already there. A read that failed is not an empty list, and saying so once
   is the only way the whole console can agree on it. */
(function () {
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  /* The shape of what is coming, rather than the word for it. */
  function skeleton(box, n) {
    if (!box) return;
    var s = '';
    for (var i = 0; i < (n || 3); i++) s += '<div class="skel-row"></div>';
    box.innerHTML = '<div class="softpanel"><div class="skel">' + s + '</div></div>';
  }

  /* What could not be read, what the database said about it, and the one
     thing that helps. */
  function failLine(box, what, why, again) {
    if (!box) return;
    box.innerHTML = '<div class="softpanel"><div class="errline">' +
      '<b>' + esc(what) + ' could not be loaded.</b>' +
      (why ? '<span>' + esc(why) + '</span>' : '') +
      (again ? '<button class="btn btn-sm" data-a="retry" type="button">Try again</button>' : '') +
      '</div></div>';
    var go = box.querySelector('[data-a="retry"]');
    if (go && again) go.addEventListener('click', again);
  }

  /* Nothing there, and nothing left after a filter, are two answers. Each
     carries its own way out. */
  function emptyLine(box, text, action, onAction) {
    if (!box) return;
    box.innerHTML = '<div class="softpanel"><div class="emptyline"><b>' + esc(text) + '</b>' +
      (action ? '<button class="btn btn-sm" data-a="go" type="button">' + esc(action) + '</button>' : '') +
      '</div></div>';
    var go = box.querySelector('[data-a="go"]');
    if (go && onAction) go.addEventListener('click', onAction);
  }

  /* The two characters a record wears when we hold no logo for it. Both
     workspaces draw the same `.rec-mark`, so the reading lives once: a Chinese
     name is one word of two or three characters, so the first two characters
     are the mark; a Latin name gives the first letter of each of the first two
     words that actually begin with a letter, or "Dale & Cecil" comes out as
     "D&" and "S P Setia" as "SP". Two copies of this drifted the moment one
     screen learned about the ampersand and the other did not. */
  function initials(name) {
    var parts = String(name || '').trim().split(/\s+/).filter(Boolean);
    if (!parts.length) return '?';
    if (/[\u3400-\u9fff]/.test(parts[0])) return parts[0].slice(0, 2);
    var words = parts.filter(function (w) { return /^[A-Za-z]/.test(w); });
    if (!words.length) return parts[0].charAt(0).toUpperCase();
    if (words.length === 1) return words[0].slice(0, 2).toUpperCase();
    return (words[0].charAt(0) + words[1].charAt(0)).toUpperCase();
  }

  /* ---- A component's own width, not the window's ----------------------
     The record pane sits inside a 243px sidebar and beside a 380px rail, so at
     a 1280px window it is about 590px wide. Every `@media (max-width: 640px)`
     rule governing something inside it was therefore false exactly when it was
     needed, and the client's Services row kept a desktop grid in 591px: the
     name track collapsed to 59px and "Social media management for Instagram,
     Facebook and TikTok" came out one word per line, 210px tall.

     Container queries are the obvious answer and are the wrong one here.
     `container-type: inline-size` implies `contain: layout`, which makes the
     element a containing block for `position: fixed` descendants — and
     `ADspaceMenu.place()` positions every row ⋯ on the viewport with exactly
     that. Turning the pane into a container would put every menu in the
     console a few hundred pixels out.

     So the width is measured instead and written onto the element as a class,
     and the stylesheet keys on that. No containment, nothing for a menu to
     trip over, and the same single copy of each row template serves the phone
     and the narrow pane, because on a phone the pane is narrow too. */
  var FIT = '.console-body, .rec-pane, .rec-rail';
  /* Two thresholds, because two different things go wrong at two different
     widths. At 640 a row of four columns has to become two lines — that is the
     services row, the contacts row, the schedule. At 460 even a two column row
     has to give up its summary line, which is the booking register and the
     rate card. One threshold made the bookings three lines tall in a 591px
     pane that had room for one. */
  var NARROW = 640, TIGHT = 460;
  var obs = null;

  function markFit(el) {
    /* A hidden pane measures 0 and is not narrow, it is absent; it gets its
       class when it is shown and the observer fires with a real size. */
    var w = el.clientWidth;
    if (!w) return;
    el.classList.toggle('is-narrow', w <= NARROW);
    el.classList.toggle('is-tight', w <= TIGHT);
  }

  function fit(sel) {
    var els = document.querySelectorAll(sel || FIT);
    if (window.ResizeObserver) {
      if (!obs) {
        obs = new window.ResizeObserver(function (rs) {
          for (var i = 0; i < rs.length; i++) markFit(rs[i].target);
        });
      }
      Array.prototype.forEach.call(els, function (el) { markFit(el); obs.observe(el); });
      return;
    }
    // No ResizeObserver: the window is the only signal there is.
    var all = function () { Array.prototype.forEach.call(els, markFit); };
    all();
    window.addEventListener('resize', all);
  }

  /* Self-installing, so a page added later cannot forget it. */
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { fit(); });
  } else {
    fit();
  }

  window.ADspaceState = {
    skeleton: skeleton, failLine: failLine, emptyLine: emptyLine,
    initials: initials, fit: fit
  };
}());
