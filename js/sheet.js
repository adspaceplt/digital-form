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
    var f = o.focus && box.querySelector(o.focus);
    if (f) { f.focus(); return; }
    var card = box.querySelector('.sheet-card') || box;
    if (!card.hasAttribute('tabindex')) card.setAttribute('tabindex', '-1');
    card.focus();
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
