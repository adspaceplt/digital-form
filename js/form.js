/* The form system's two moving parts, one copy of each.
 *
 * 1. A choice of two to four is a segment, not a dropdown. A dropdown hides
 *    its options behind a press; a segment shows every one and takes one.
 *    The <select> stays in the page as the source of truth — every script
 *    that reads `.value`, sets it, or listens for `change` goes on working —
 *    and the segment is drawn beside it and kept in step. The select is taken
 *    out of sight and out of the tab order; the segment is a radio group a
 *    keyboard walks with the arrow keys.
 *
 *    Opt in with `data-seg` on the select. A select whose options are filled
 *    later is redrawn when its options change.
 *
 * 2. Defaults fold under More details. A <details class="fmore"> carries the
 *    fields a person usually leaves as they are, and its summary line says
 *    what they hold ("Engagement · Normal · Standard"), so nothing is hidden
 *    and nothing is asked twice. The line follows the fields as they change.
 *
 * Asked for by the user on 2026-09-24 after the form audit ("apply site-wide
 * where possible").
 */
(function () {
  /* ---- 1. Segments ------------------------------------------------------ */
  var ID = 0;

  function labelOf(sel) {
    var l = sel.id && document.querySelector('label[for="' + sel.id + '"]');
    if (l) {
      if (!l.id) l.id = sel.id + 'Label';
      return l;
    }
    return null;
  }

  function options(sel) {
    return Array.prototype.filter.call(sel.options, function (o) { return !o.hidden; });
  }

  function paint(sel) {
    var seg = sel.__seg;
    if (!seg) return;
    var opts = options(sel);
    var keys = opts.map(function (o) { return o.value + '\u0001' + o.text + '\u0001' + (o.disabled ? 1 : 0); }).join('\u0002');
    if (seg.__keys !== keys) {
      seg.__keys = keys;
      seg.innerHTML = opts.map(function (o) {
        return '<button type="button" role="radio" class="seg-opt" data-v="' +
          String(o.value).replace(/&/g, '&amp;').replace(/"/g, '&quot;') + '"' +
          (o.disabled ? ' disabled' : '') + '>' +
          String(o.text).replace(/&/g, '&amp;').replace(/</g, '&lt;') + '</button>';
      }).join('');
    }
    var v = sel.value;
    Array.prototype.forEach.call(seg.children, function (b) {
      var on = b.getAttribute('data-v') === v;
      b.classList.toggle('is-on', on);
      b.setAttribute('aria-checked', on ? 'true' : 'false');
      b.tabIndex = on ? 0 : -1;
    });
    if (!seg.querySelector('.is-on') && seg.firstElementChild) seg.firstElementChild.tabIndex = 0;
    fit(seg);
    seg.classList.toggle('is-disabled', sel.disabled);
    Array.prototype.forEach.call(seg.children, function (b) { if (sel.disabled) b.disabled = true; });
  }

  /* A segment whose words do not fit its track on one line (four options on
     a phone: "Google …", "Quotati…") falls to two columns rather than
     cutting a word, because a choice read by a sliced label is a guess. It is
     measured with the track unwrapped every time, so a wider sheet puts it
     back on one line. */
  function fit(seg) {
    if (!seg || !seg.clientWidth) return;
    seg.classList.remove('is-wrap');
    var cut = Array.prototype.some.call(seg.children, function (b) { return b.scrollWidth > b.clientWidth + 1; });
    seg.classList.toggle('is-wrap', cut);
  }

  function choose(sel, v) {
    if (sel.disabled || sel.value === v) { paint(sel); return; }
    sel.value = v;
    sel.dispatchEvent(new Event('input', { bubbles: true }));
    sel.dispatchEvent(new Event('change', { bubbles: true }));
    paint(sel);
  }

  /* Keep the drawing in step with a value set from a script, which fires no
     event: the instance's own `value` and `selectedIndex` repaint after the
     browser's own setter has run. */
  function watch(sel) {
    ['value', 'selectedIndex'].forEach(function (prop) {
      var d = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, prop);
      if (!d || !d.set) return;
      Object.defineProperty(sel, prop, {
        configurable: true,
        get: function () { return d.get.call(this); },
        set: function (x) { d.set.call(this, x); paint(this); }
      });
    });
    sel.addEventListener('change', function () { paint(sel); });
    if (window.MutationObserver) {
      new MutationObserver(function () { paint(sel); })
        .observe(sel, { childList: true, subtree: true, attributes: true, attributeFilter: ['disabled', 'hidden'] });
    }
  }

  function upgrade(sel) {
    if (!sel || sel.__seg) return;
    var seg = document.createElement('div');
    seg.className = 'seg';
    seg.id = 'seg' + (++ID);
    seg.setAttribute('role', 'radiogroup');
    var l = labelOf(sel);
    if (l) seg.setAttribute('aria-labelledby', l.id);
    else if (sel.getAttribute('aria-label')) seg.setAttribute('aria-label', sel.getAttribute('aria-label'));
    sel.__seg = seg;
    sel.classList.add('seg-src');
    sel.setAttribute('aria-hidden', 'true');
    sel.tabIndex = -1;
    sel.parentNode.insertBefore(seg, sel.nextSibling);
    /* The label pointed at the select; pressing it now lands on the choice. */
    if (l) l.addEventListener('click', function (e) {
      e.preventDefault();
      var on = seg.querySelector('.is-on') || seg.firstElementChild;
      if (on) on.focus();
    });
    seg.addEventListener('click', function (e) {
      var b = e.target.closest('.seg-opt');
      if (!b || b.disabled) return;
      choose(sel, b.getAttribute('data-v'));
      b.focus();
    });
    seg.addEventListener('keydown', function (e) {
      var keys = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 };
      if (!keys[e.key]) return;
      e.preventDefault();
      var list = Array.prototype.filter.call(seg.children, function (b) { return !b.disabled; });
      var at = list.indexOf(document.activeElement);
      var next = list[(at + keys[e.key] + list.length) % list.length];
      if (next) { choose(sel, next.getAttribute('data-v')); next.focus(); }
    });
    watch(sel);
    paint(sel);
    thumb(seg);
    /* Refit when the track's width changes (a sheet opening, a phone turning),
       a frame later so the change is never made inside the observer. */
    if (window.ResizeObserver) {
      var wide = -1;
      new ResizeObserver(function () {
        var w = seg.clientWidth;
        if (w === wide) return;
        wide = w;
        requestAnimationFrame(function () { fit(seg); });
      }).observe(seg);
    }
  }

  /* ---- 1b. The chosen option slides ------------------------------------ */
  /* Every segment track (`.seg` here, and the `.cmdbar-views` a page toggles
     itself) draws one raised surface and moves it under the option marked
     `is-on`. The page goes on setting the class as it always did; the track
     watches for it. Measured from the option's own box, less the 2px inset
     the fill always had. The first placement, a track coming out of a hidden
     sheet and a change of size snap, because only a choice should move.
     Asked for by the user on 2026-09-24 ("smooth sliding instead of very
     lagging click"). */
  function place(track, snap) {
    var on = track.querySelector(':scope > .is-on');
    var w = track.clientWidth, h = track.clientHeight;
    if (!w) { track.__thumbW = 0; return; }
    if (!on) { track.style.setProperty('--thumb-o', '0'); return; }
    var from = null;
    /* The chosen word is set heavier, so a choice can move a track's width by
       a pixel or two; that is the choice moving, not the track resizing, and
       it slides. A real change of size (a sheet opening, a wrap, a phone
       turning) snaps. */
    if (!track.__thumbW || Math.abs(track.__thumbW - w) > 8 || Math.abs((track.__thumbH || 0) - h) > 8) {
      /* Coming into view: snap, except where one sheet has just swapped for
         the other (Task / Content deliverable), where the surface starts on
         the option that was chosen a moment ago and slides to this one. */
      var opts = track.querySelectorAll(':scope > .acttab, :scope > .seg-opt');
      if (!track.__thumbW && opts.length === 2 && track.closest('.sheet.is-swap')) {
        from = opts[0] === on ? opts[1] : opts[0];
      }
      snap = true;
    }
    track.__thumbW = w;
    track.__thumbH = h;
    /* Read from the boxes as drawn, to the fraction of a pixel, so the
       surface's edge is the option's edge and not a rounding of it. */
    var tr = track.getBoundingClientRect();
    /* A sheet lifting in is scaled while it moves; the boxes are read back
       into the track's own unscaled pixels. */
    var k = track.offsetWidth ? tr.width / track.offsetWidth : 1;
    if (!k) k = 1;
    var set = function (b) {
      var r = b.getBoundingClientRect();
      /* A track that scrolls (the view strip on a phone) carries the surface
         in its own scrolled content, so the scroll offset is added back. */
      track.style.setProperty('--thumb-x', ((r.left - tr.left) / k - track.clientLeft + track.scrollLeft + 2) + 'px');
      track.style.setProperty('--thumb-y', ((r.top - tr.top) / k - track.clientTop + track.scrollTop + 2) + 'px');
      track.style.setProperty('--thumb-w', Math.max(0, r.width / k - 4) + 'px');
      track.style.setProperty('--thumb-h', Math.max(0, r.height / k - 4) + 'px');
      track.style.setProperty('--thumb-o', '1');
    };
    if (snap || from) {
      track.classList.add('is-snap');
      set(from || on);
      /* Read the surface's own style, so the snapped place is where the
         transition starts from rather than a value the browser never drew. */
      void getComputedStyle(track, '::before').transform;
      track.classList.remove('is-snap');
      if (from) set(on);
    } else {
      set(on);
    }
    track.classList.add('has-thumb');
    reach(track, on, snap);
  }

  /* ---- 1c. A strip wider than its row scrolls ---------------------------
     On a phone My Work's views are wider than the screen, so the strip
     scrolls sideways (the brief of 2026-09-26): the edge that has more
     beyond it fades (`is-more-start`, `is-more-end`), and a choice, or the
     page opening on one, brings the chosen view into sight. A track that
     fits carries neither class and never scrolls. */
  function edges(track) {
    var max = track.scrollWidth - track.clientWidth;
    track.classList.toggle('is-more-start', max > 1 && track.scrollLeft > 1);
    track.classList.toggle('is-more-end', max > 1 && track.scrollLeft < max - 1);
  }
  function reach(track, on, snap) {
    if (!on || track.scrollWidth <= track.clientWidth + 1) { edges(track); return; }
    var l = on.offsetLeft, r = l + on.offsetWidth, pad = 24;
    var to = track.scrollLeft;
    if (l - pad < to) to = Math.max(0, l - pad);
    else if (r + pad > to + track.clientWidth) to = r + pad - track.clientWidth;
    if (to !== track.scrollLeft) {
      var still = snap || (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches);
      if (track.scrollTo) track.scrollTo({ left: to, behavior: still ? 'auto' : 'smooth' });
      else track.scrollLeft = to;
    }
    edges(track);
  }

  function thumb(track) {
    if (!track || track.__thumb) return;
    track.__thumb = true;
    /* The track is the positioning box before anything is measured. */
    track.classList.add('has-thumb', 'is-snap');
    track.style.setProperty('--thumb-o', '0');
    place(track, true);
    var queued = false;
    var later = function () {
      if (queued) return;
      queued = true;
      requestAnimationFrame(function () { queued = false; place(track, false); });
    };
    /* A class moving between options is read as soon as the script that
       moved it has finished, not a frame later. The track's own class is
       left out: placing the thumb writes it, and reading that back would
       place it again for ever. */
    if (window.MutationObserver) {
      new MutationObserver(function (list) {
        var moved = false, grew = false;
        list.forEach(function (m) {
          if (m.target === track && m.type === 'attributes') return;
          if (m.type === 'attributes') moved = true; else grew = true;
        });
        if (moved) place(track, false); else if (grew) later();
      }).observe(track, { attributes: true, attributeFilter: ['class', 'hidden'], subtree: true, childList: true });
    }
    if (window.ResizeObserver) new ResizeObserver(later).observe(track);
    track.addEventListener('scroll', function () { edges(track); }, { passive: true });
  }

  /* ---- 2. More details -------------------------------------------------- */
  function summary(det) {
    var out = [];
    Array.prototype.forEach.call(det.querySelectorAll('select, input, textarea'), function (f) {
      if (f.closest('.fmore') !== det || f.type === 'hidden') return;
      if (f.tagName === 'SELECT') {
        var o = f.options[f.selectedIndex];
        var t = o ? o.text : '';
        if (t && f.value !== '') out.push(t);
        else if (f.getAttribute('data-none')) out.push(f.getAttribute('data-none'));
      } else if (f.type === 'checkbox') {
        if (f.checked && f.getAttribute('data-on')) out.push(f.getAttribute('data-on'));
      } else if (f.getAttribute('data-none') && !String(f.value || '').trim()) {
        out.push(f.getAttribute('data-none'));
      } else if (f.getAttribute('data-some') && String(f.value || '').trim()) {
        out.push(f.getAttribute('data-some'));
      }
    });
    return out.join(' · ');
  }

  function fold(det) {
    if (!det || det.__fold) return;
    det.__fold = true;
    var sum = det.querySelector('.fmore-sum');
    var paintSum = function () { if (sum) sum.textContent = summary(det); };
    det.addEventListener('change', paintSum);
    det.addEventListener('input', paintSum);
    det.addEventListener('toggle', paintSum);
    /* A segment under a shut fold was never measured (nothing inside a shut
       <details> is laid out for the observer to report), so it is fitted the
       moment the fold opens. */
    det.addEventListener('toggle', function () {
      if (!det.open) return;
      Array.prototype.forEach.call(det.querySelectorAll('.seg'), fit);
    });
    /* A value set from a script (the sheet resetting on open) fires nothing,
       so the line is read again whenever the sheet around it opens. */
    var sheet = det.closest('.sheet');
    if (sheet && window.MutationObserver) {
      new MutationObserver(paintSum).observe(sheet, { attributes: true, attributeFilter: ['hidden'] });
    }
    paintSum();
    det.__paint = paintSum;
  }

  /* ---- 3. An empty date field says what it wants ---------------------- */
  function hint(el) {
    if (!el) return;
    var box = el.__hintBox;
    if (!box) {
      if (!el.parentNode) return;
      box = document.createElement('span');
      box.className = 'datefield';
      box.setAttribute('data-hint', el.getAttribute('data-hint') || 'Select date');
      el.parentNode.insertBefore(box, el);
      box.appendChild(el);
      el.__hintBox = box;
      var read = function () { box.classList.toggle('is-empty', !el.value); };
      el.addEventListener('input', read);
      el.addEventListener('change', read);
      el.addEventListener('blur', read);
      el.__hintRead = read;
    }
    el.__hintRead();
  }

  function scan(root) {
    Array.prototype.forEach.call((root || document).querySelectorAll('input[data-hint]'), hint);
    Array.prototype.forEach.call((root || document).querySelectorAll('select[data-seg]'), upgrade);
    Array.prototype.forEach.call((root || document).querySelectorAll('details.fmore'), fold);
    Array.prototype.forEach.call((root || document).querySelectorAll('.cmdbar-views'), thumb);
  }

  /* A refusal that focuses a field under a shut More details has to open it
     first: a field inside a closed fold cannot take focus, so the caret would
     go nowhere and the message would name a field nobody can see. */
  function reveal(el) {
    var d = el && el.closest && el.closest('details');
    while (d) { d.open = true; d = d.parentElement && d.parentElement.closest('details'); }
    if (el && el.__seg) el = el.__seg.querySelector('.is-on') || el.__seg.firstElementChild;
    if (el && el.focus) el.focus();
  }

  window.ADspaceForm = {
    reveal: reveal,
    segment: upgrade,
    paint: paint,
    fold: fold,
    refresh: function (det) { if (det && det.__paint) det.__paint(); },
    scan: scan,
    thumb: thumb,
    /* A value set from a script fires nothing, so a page that sets one reads
       the field again through this. */
    hint: hint
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', function () { scan(); });
  else scan();
})();
