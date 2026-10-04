/* A form in a sheet, and the one copy of how it opens and shuts.
 *
 * Three sections were three shapes for one act. A creator is edited in a
 * sheet over the list; a colleague and a user group were edited in a panel
 * that unfolded at the top of the page, so on a phone the form was a screen
 * above the row it belonged to and pressing Edit looked like nothing had
 * happened. One shape, and it is the sheet: on a phone it comes up from the
 * floor over the row, at a desk it is a card over the list, and either way
 * what is being edited is in front of what it is being edited from.
 *
 * What this file exists for, beyond not writing the same twenty lines three
 * times, is the part the creator sheet got wrong: the scrim closed it on any
 * stray click, so a click that missed the card by a few pixels threw away
 * whatever had been typed. A sheet that holds typed changes is not dismissed
 * by the scrim at all — the close mark and Cancel are the ways out, and they
 * are both on the card the person is looking at. Escape still closes at every
 * point, because nobody presses Escape by accident with a mouse and a dialog
 * a keyboard cannot leave is a dialog nobody can leave.
 *
 * Focus is trapped while it is open and handed back to the control that
 * opened it, which is what `js/confirm.js` already does for a question.
 */
(function () {
  var open = null;   // { box, opener, dirty, onClose }

  function fields(box) {
    return Array.prototype.slice.call(box.querySelectorAll(
      'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]),' +
      'textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'))
      .filter(function (el) { return el.offsetParent !== null || el === document.activeElement; });
  }

  function onKey(e) {
    if (!open) return;
    /* A value being edited in place answers its own Escape (js/ask.js). */
    if (e.key === 'Escape' && e.target && e.target.classList && e.target.classList.contains('askfield')) return;
    if (e.key === 'Escape') { e.preventDefault(); shut(); return; }
    if (e.key !== 'Tab') return;
    var f = fields(open.box);
    if (!f.length) return;
    var first = f[0], last = f[f.length - 1];
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
  }

  /* Anything typed, ticked or picked since it opened makes it dirty, which is
     the whole of what the scrim then refuses to throw away. */
  function onEdit() { if (open) open.dirty = true; }

  function onScrim(e) {
    if (!open || e.target !== open.box) return;
    if (open.dirty) return;   // a stray click never costs somebody their typing
    shut();
  }

  function shut() {
    if (!open) return;
    var o = open;
    open = null;
    o.box.hidden = true;
    document.removeEventListener('keydown', onKey, true);
    o.box.removeEventListener('input', onEdit);
    o.box.removeEventListener('change', onEdit);
    o.box.removeEventListener('mousedown', onScrim);
    if (o.opener && document.body.contains(o.opener)) o.opener.focus();
    if (o.onClose) o.onClose();
  }

  /* `box` is the `.sheet`, `o.focus` the field to land on, `o.opener` the
     control that opened it and `o.onClose` whatever the section has to put
     back. A second open shuts the first, so two sheets are never stacked. */
  function show(box, o) {
    o = o || {};
    if (open) shut();
    /* **A sheet belongs to the page, not to the list it was authored in.** It
       is `position: fixed`, so where it sits in the DOM decides nothing about
       where it draws — except that an ancestor which is `hidden` hides it
       completely. The client form is authored inside the clients list, and
       that list is hidden the moment a record is open, so Edit on a record
       opened a sheet nobody could see. The form used to be carried into the
       record by hand for that reason; moving every sheet to the page once, on
       first open, is the same fix made once instead of per form. Listeners and
       typed values survive a move, and a second open costs nothing. */
    if (box.parentNode !== document.body) document.body.appendChild(box);
    box.hidden = false;
    open = { box: box, opener: o.opener || null, dirty: false, onClose: o.onClose || null };
    document.addEventListener('keydown', onKey, true);
    box.addEventListener('input', onEdit);
    box.addEventListener('change', onEdit);
    box.addEventListener('mousedown', onScrim);
    /* **The card takes focus, never a field.** A sheet that focused its first
       input raised the phone's keyboard the moment it opened, and on iOS a
       field taking focus zooms the page — so the reader landed on a form
       scrolled and magnified past most of what they had opened it to read,
       already typing into a field that is rarely the one they came to change.
       A sheet opens on what there is to change; the caret is the reader's to
       place. The card is what takes focus, so Escape still closes, the trap
       still holds and a screen reader still announces the dialog.
       `o.focus` survives for a sheet whose whole purpose is one value. */
    /* **A sheet opens at its top, every time.** The same sheet serves Add
       and Edit and is only hidden between uses, so its body kept the scroll
       it was left at: a lead added after a record was edited opened part way
       down, on Source and Industry, with the brand name above the fold
       (reported 2026-09-26 on Add lead and on Billing's Edit). And focus is
       placed without scrolling: the card is still lifting into place when it
       takes focus, and a browser that scrolls to reveal it moves the body
       under the reader's eye. */
    box.scrollTop = 0;
    Array.prototype.forEach.call(box.querySelectorAll('.sheet-body'), function (b) { b.scrollTop = 0; });
    var f = o.focus && box.querySelector(o.focus);
    if (f) { f.focus({ preventScroll: true }); return; }
    var card = box.querySelector('.sheet-card') || box;
    if (!card.hasAttribute('tabindex')) card.setAttribute('tabindex', '-1');
    card.focus({ preventScroll: true });
  }

  /* Every sheet in the portal, including those a section opens by
     unhiding it directly rather than through show(), starts at its top when
     it appears: reused between Add and Edit, a hidden sheet otherwise kept
     the scroll it was left at. */
  if (window.MutationObserver) {
    new MutationObserver(function (list) {
      list.forEach(function (m) {
        var el = m.target;
        if (!el.classList || !el.classList.contains('sheet') || el.hidden) return;
        if (m.oldValue === null) return;
        el.scrollTop = 0;
        Array.prototype.forEach.call(el.querySelectorAll('.sheet-body'), function (b) { b.scrollTop = 0; });
      });
    }).observe(document.documentElement, { subtree: true, attributes: true, attributeFilter: ['hidden'], attributeOldValue: true });
  }

  window.ADspaceSheet = {
    show: show,
    close: shut,
    /* A section that has just saved and repainted marks the sheet clean so
       the next stray click is not refused over work that is already stored. */
    clean: function () { if (open) open.dirty = false; },
    isOpen: function (box) { return Boolean(open && (!box || open.box === box)); }
  };
})();

/* Cmd + Enter on a Mac, Ctrl + Enter elsewhere, presses the action the
 * reader is on (asked for by the user on 2026-09-24, "like most AI tools").
 *
 * What it presses, nearest first:
 *   1. the submit of the small form the caret is in (a comment, a brief, a
 *      checklist item in the task sheet), so a chord typed in a comment posts
 *      the comment and never moves the task on;
 *   2. else the main action of the sheet on top: its first filled button,
 *      primary or forward, in the foot (a sheet with no foot, such as the
 *      task sheet, is a record and not a form, and is left alone);
 *   3. else the main action of the pane form the caret is in (Billing, Brand).
 * **A destructive act is never a chord.** A red button is skipped wherever it
 * is, so Delete, Void and Remove stay a deliberate press on the screen. A
 * disabled or hidden button is not pressed, which is how a gate that is shut
 * stays shut. The plain Enter is untouched: in a text box it is a new line.
 * It is one listener for the whole console, because sheets are opened by four
 * different helpers and a rule written into each would drift. */
(function () {
  var MAC = /Mac|iPhone|iPad|iPod/.test(navigator.platform || navigator.userAgent || '');
  var GO = '.btn-primary, .btn-go';

  function usable(b) {
    return b && !b.disabled && !b.hidden && !b.closest('[hidden]') &&
      !b.classList.contains('btn-danger') && b.getClientRects().length > 0;
  }
  function firstIn(root, sel) {
    var list = root ? root.querySelectorAll(sel) : [];
    for (var i = 0; i < list.length; i++) if (usable(list[i])) return list[i];
    return null;
  }
  /* The sheet on top: the highest stacking order, the later one on a tie. */
  function topSheet() {
    var best = null, bestZ = -Infinity;
    Array.prototype.forEach.call(document.querySelectorAll('.sheet'), function (s) {
      if (s.hidden || !s.getClientRects().length) return;
      var z = parseInt(getComputedStyle(s).zIndex, 10) || 0;
      if (z >= bestZ) { best = s; bestZ = z; }
    });
    return best;
  }
  function target(from) {
    var form = from && from.closest && from.closest('form');
    if (form) {
      var sub = firstIn(form, 'button[type="submit"]');
      if (sub) return sub;
    }
    /* Only a sheet with a foot: the task sheet and the review sheet are
       records with many actions, and a chord there must not move a task on
       because the caret happened to be on the card. */
    var sheet = topSheet();
    if (sheet) return firstIn(sheet.querySelector('.sheet-foot'), GO);
    var pane = from && from.closest && from.closest('.pane-form, .panel');
    return pane ? firstIn(pane, GO) : null;
  }

  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Enter' || e.shiftKey || e.altKey) return;
    if (!(e.metaKey || e.ctrlKey)) return;
    if (e.isComposing) return;   // a Chinese or Malay input method is choosing a word
    if (e.defaultPrevented) return;   // the field already acted on its own Enter (Add task's title)
    var b = target(document.activeElement);
    if (!b) return;
    e.preventDefault();
    b.click();
  });

  /* Say so on the control, for the keyboard and the pointer that hovers. */
  function label() {
    Array.prototype.forEach.call(document.querySelectorAll('.sheet-foot ' + '.btn-primary, .sheet-foot .btn-go, .qform-acts [type="submit"]'), function (b) {
      if (b.classList.contains('btn-danger') || b.hasAttribute('aria-keyshortcuts')) return;
      b.setAttribute('aria-keyshortcuts', 'Meta+Enter Control+Enter');
      if (!b.title) b.title = MAC ? '⌘ Enter' : 'Ctrl + Enter';
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', label);
  else label();
})();

/* On a phone a sheet is pulled down to close, and a half-filled form is kept
 * (the user's UX brief, approved 2026-10-01: "swipe down to close on mobile
 * sheets, backdrop tap to close, and keep a draft of half filled sheets so
 * reopening restores the input").
 *
 * The pull starts on the sheet's head (the grabber drawn over it): a drag
 * that is plainly downward moves the card with the finger, and let go past
 * 90px, or flicked, it presses the sheet's own close mark, so the section's
 * own way out is what runs. Anywhere else the body scrolls as it always has.
 *
 * A form sheet (a foot with a filled action, and fields) keeps a draft of
 * what the person typed when it is left any way but its action: the scrim,
 * the pull, Escape, Cancel. It is kept against the state the sheet opened
 * in (every field's value, hidden ones included, so an Edit of another
 * record is another form), and only the fields the person changed are kept.
 * Opened again in that same state, those fields are put back and the sheet
 * says so, with Discard as the way back. Pressing the sheet's action ends
 * the draft, whether it saves or not: a failed save keeps the sheet open
 * with its fields, and a saved one must never fill the next form with it.
 * It is the phone's alone, where a thumb on the scrim or a pull costs the
 * typing; a desk keeps the rule that the scrim never closes a touched form.
 * Files, passwords and codes are never kept (`data-nodraft` opts a field out).
 */
(function () {
  var phone = window.matchMedia ? window.matchMedia('(max-width: 640px)') : null;
  var KEY = 'adspace-draft:';
  var EXCLUDE = '#askSheet, #cmdSheet, #searchSheet, #activitySheet';
  var live = {};   // sheet id -> { base, edited: {key: true}, pressed: time }

  function isPhone() { return !!(phone && phone.matches); }
  function cardOf(sheet) { return sheet.querySelector('.sheet-card') || sheet; }
  function closeOf(sheet) {
    return cardOf(sheet).querySelector('.sheet-head [aria-label="Close"], .sheet-head .iconbtn');
  }
  function formSheet(sheet) {
    if (!sheet.id || sheet.matches(EXCLUDE)) return false;
    var foot = sheet.querySelector('.sheet-foot');
    return !!(foot && foot.querySelector('.btn-primary, .btn-go') && sheet.querySelector('input, textarea, select'));
  }
  function keyOf(el) { return el.id || (el.name ? 'name:' + el.name : ''); }
  function keepable(el) {
    var t = (el.type || '').toLowerCase();
    return !!keyOf(el) && t !== 'file' && t !== 'password' && t !== 'hidden' &&
      !el.hasAttribute('data-nodraft') && el.autocomplete !== 'one-time-code';
  }
  function valueOf(el) {
    var t = (el.type || '').toLowerCase();
    if (t === 'checkbox' || t === 'radio') return el.checked ? '1' : '0';
    return el.value == null ? '' : String(el.value);
  }
  function fieldsOf(sheet) {
    return Array.prototype.filter.call(sheet.querySelectorAll('input, textarea, select'), function (el) {
      return !!keyOf(el) && (el.type || '').toLowerCase() !== 'file';
    });
  }
  function snapshot(sheet) {
    var out = {};
    fieldsOf(sheet).forEach(function (el) { out[keyOf(el)] = valueOf(el); });
    return JSON.stringify(out);
  }
  function read(id) {
    try { var s = sessionStorage.getItem(KEY + id); return s ? JSON.parse(s) : null; } catch (e) { return null; }
  }
  function write(id, d) {
    try { if (d) sessionStorage.setItem(KEY + id, JSON.stringify(d)); else sessionStorage.removeItem(KEY + id); } catch (e) {}
  }
  function put(el, v) {
    var t = (el.type || '').toLowerCase();
    if (t === 'checkbox' || t === 'radio') el.checked = v === '1'; else el.value = v;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }
  function find(sheet, k) {
    var all = fieldsOf(sheet);
    for (var i = 0; i < all.length; i++) if (keyOf(all[i]) === k) return all[i];
    return null;
  }

  function drop(sheet) {
    var line = sheet.querySelector('.draftline');
    if (line) line.parentNode.removeChild(line);
  }
  function say(sheet, d) {
    drop(sheet);
    var body = sheet.querySelector('.sheet-body');
    if (!body) return;
    var line = document.createElement('div');
    line.className = 'draftline';
    line.innerHTML = '<span>Draft restored.</span><button class="btn btn-sm btn-quiet" type="button">Discard</button>';
    body.insertBefore(line, body.firstChild);
    line.querySelector('button').addEventListener('click', function () {
      var base = JSON.parse(d.base);
      Object.keys(d.vals).forEach(function (k) {
        var el = find(sheet, k);
        if (el && k in base) put(el, base[k]);
      });
      write(sheet.id, null);
      if (live[sheet.id]) live[sheet.id].edited = {};
      drop(sheet);
      var card = cardOf(sheet);
      try { card.focus({ preventScroll: true }); } catch (e) {}
    });
  }

  function opened(sheet) {
    if (!formSheet(sheet)) return;
    drop(sheet);
    /* After the section has filled it: most fill before unhiding, and the
       rest within a frame or two. */
    setTimeout(function () {
      if (sheet.hidden) return;
      var base = snapshot(sheet);
      live[sheet.id] = { base: base, edited: {}, pressed: 0 };
      if (!isPhone()) return;
      var d = read(sheet.id);
      if (!d || d.base !== base) return;
      var put1 = false;
      Object.keys(d.vals).forEach(function (k) {
        var el = find(sheet, k);
        if (el && keepable(el)) { put(el, d.vals[k]); put1 = true; live[sheet.id].edited[k] = true; }
      });
      if (put1) say(sheet, d);
    }, 120);
  }
  function closed(sheet) {
    var s = live[sheet.id];
    delete live[sheet.id];
    drop(sheet);
    if (!s || !isPhone()) return;
    /* The action was pressed: the draft has done its work either way. */
    if (s.pressed && Date.now() - s.pressed < 20000) { write(sheet.id, null); return; }
    var keys = Object.keys(s.edited);
    if (!keys.length) return;
    var vals = {};
    keys.forEach(function (k) {
      var el = find(sheet, k);
      if (el && keepable(el)) vals[k] = valueOf(el);
    });
    write(sheet.id, Object.keys(vals).length ? { base: s.base, vals: vals } : null);
  }

  /* What the person changed: a trusted edit only, never the section's own
     filling. */
  function edited(e) {
    if (!e.isTrusted) return;
    var el = e.target, sheet = el && el.closest && el.closest('.sheet');
    if (!sheet || !live[sheet.id]) return;
    var k = keyOf(el);
    if (k) live[sheet.id].edited[k] = true;
  }
  document.addEventListener('input', edited, true);
  document.addEventListener('change', edited, true);
  document.addEventListener('click', function (e) {
    var b = e.target && e.target.closest && e.target.closest('.sheet-foot .btn-primary, .sheet-foot .btn-go');
    var sheet = b && b.closest('.sheet');
    if (sheet && live[sheet.id]) live[sheet.id].pressed = Date.now();
  }, true);

  if (window.MutationObserver) {
    new MutationObserver(function (list) {
      list.forEach(function (m) {
        var el = m.target;
        if (!el.classList || !el.classList.contains('sheet')) return;
        var was = m.oldValue !== null;   // hidden before
        if (was && !el.hidden) opened(el);
        else if (!was && el.hidden) closed(el);
      });
    }).observe(document.documentElement, { subtree: true, attributes: true, attributeFilter: ['hidden'], attributeOldValue: true });
  }

  /* On a phone the scrim closes a form sheet that has been touched as well,
     because what was typed is kept. */
  document.addEventListener('click', function (e) {
    var sheet = e.target;
    if (!isPhone() || !sheet.classList || !sheet.classList.contains('sheet') || sheet.hidden) return;
    if (!formSheet(sheet)) return;
    var x = closeOf(sheet);
    if (x) x.click();
  });

  /* The pull. */
  var drag = null;
  document.addEventListener('touchstart', function (e) {
    if (!isPhone() || e.touches.length !== 1) return;
    var t = e.target, head = t.closest && t.closest('.sheet-head');
    var sheet = head && head.closest('.sheet');
    if (!sheet || sheet.hidden || !closeOf(sheet)) return;
    if (t.closest('input, textarea, select, [contenteditable]')) return;
    var card = cardOf(sheet);
    drag = { sheet: sheet, card: card, x: e.touches[0].clientX, y: e.touches[0].clientY, t: Date.now(), dy: 0, on: false };
  }, { passive: true });
  document.addEventListener('touchmove', function (e) {
    if (!drag) return;
    var dx = e.touches[0].clientX - drag.x, dy = e.touches[0].clientY - drag.y;
    if (!drag.on) {
      if (Math.abs(dy) < 8) return;
      if (dy < 0 || Math.abs(dy) < Math.abs(dx) * 1.5) { drag = null; return; }
      drag.on = true;
      drag.card.style.transition = 'none';
    }
    drag.dy = Math.max(0, dy);
    drag.card.style.transform = 'translateY(' + drag.dy + 'px)';
    if (e.cancelable) e.preventDefault();
  }, { passive: false });
  function release() {
    if (!drag) return;
    var d = drag; drag = null;
    if (!d.on) return;
    var fast = d.dy > 40 && d.dy / Math.max(1, Date.now() - d.t) > 0.5;
    d.card.style.transition = 'transform var(--t) var(--ease)';
    if (d.dy > 90 || fast) {
      d.card.style.transform = 'translateY(100%)';
      setTimeout(function () {
        d.card.style.transition = ''; d.card.style.transform = '';
        var x = closeOf(d.sheet);
        if (x && !d.sheet.hidden) x.click();
      }, 180);
    } else {
      d.card.style.transform = '';
      setTimeout(function () { d.card.style.transition = ''; }, 220);
    }
  }
  document.addEventListener('touchend', release);
  document.addEventListener('touchcancel', release);
})();
