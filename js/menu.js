/*
 * The row ⋯ menu: where it opens, and what closes it.
 *
 * Four sections draw a ⋯ at the end of a table row, and each had its own copy
 * of the same twenty lines. They drifted, and when the placement turned out to
 * be broken on a phone the fix had to be made three times and still missed the
 * fourth. The placement and the scroll guard live here; each page keeps its own
 * click wiring, because what a menu holds and what it is scoped to differ.
 */
(function () {
  /* The button the open menu hangs off, and where it was when the menu was
     placed. Clicking a ⋯ focuses it, and the browser scrolls whatever it has
     to in order to reveal the focused button; that scroll arrives a frame
     after the menu opened and used to close it again, so on a phone the ⋯ on
     the lower rows could not be opened at all. A scroll that has not moved
     the button is that one, and is no reason to close anything; one that has
     moved it has carried the menu away from its row, which is. */
  var held = null;
  var closers = [];

  function movedAway() {
    if (!held) return true;
    if (Math.abs(held.btn.getBoundingClientRect().top - held.top) < 2) return false;
    held = null;
    return true;
  }

  window.addEventListener('scroll', function () {
    if (!movedAway()) return;
    for (var i = 0; i < closers.length; i++) closers[i]();
  }, true);

  /* A resize moves the button and left the menu where it was drawn, pinned
     to the old coordinates while the bar reflowed under it (reported by the
     user on 2026-09-24). The open menu follows its button; a button the new
     width hides or takes off the page closes the menu instead. */
  var resizing = 0;
  window.addEventListener('resize', function () {
    if (resizing || !held || !held.menu) return;
    resizing = requestAnimationFrame(function () {
      resizing = 0;
      if (!held || !held.menu) return;
      var open = !held.menu.hidden && held.menu.getClientRects().length > 0;
      if (!open) { held = null; return; }
      var gone = !document.body.contains(held.btn) || !held.btn.getClientRects().length;
      if (gone) {
        held = null;
        for (var i = 0; i < closers.length; i++) closers[i]();
        return;
      }
      if (held.pop) window.ADspaceMenu.pop(held.btn, held.menu, held.align);
      else window.ADspaceMenu.place(held.btn, held.menu, held.align);
    });
  });

  /* A popover card (the bell's, the section's purpose): on a phone it docks
     at the foot of the screen, where the thumb is, and never hangs from a
     control near the top (the user, 2026-09-28: "it looks dropping down
     somewhere"); at a desk it hangs from its control with a caret pointing
     at it. */
  var phone = window.matchMedia ? window.matchMedia('(max-width: 640px)') : null;

  window.ADspaceMenu = {
    /* Placed on the viewport rather than in the row, so the table's own
       overflow cannot clip it, and upwards where the room is above: a ⋯ on
       the last row used to open past the bottom of the window, which is
       nowhere a phone can reach. Call it with the menu already visible; the
       height cannot be measured otherwise. */
    place: function (btn, menu, align) {
      var r = btn.getBoundingClientRect(), h = menu.offsetHeight;
      menu.style.position = 'fixed';
      menu.style.right = 'auto';
      /* A row ⋯ sits at the end of its row, so its menu hangs back from the
         right edge. A control at the start of a line — the section's name in
         the console head — is the other way round, and right alignment put
         its panel against the window's left edge instead of under the word it
         belongs to. Either way it is kept inside the viewport. */
      menu.style.left = (align === 'left'
        ? Math.max(8, Math.min(r.left, window.innerWidth - menu.offsetWidth - 8))
        : Math.max(8, r.right - menu.offsetWidth)) + 'px';
      menu.style.top = (r.bottom + 4 + h <= window.innerHeight - 8 || r.top - 4 - h < 8)
        ? (r.bottom + 4) + 'px'
        : (r.top - 4 - h) + 'px';
      /* `position: fixed` is measured from the viewport only while no
         ancestor is transformed, and on an iPhone not always then: a sheet
         on a phone is (`will-change: transform`, so it lifts in one piece),
         and after the date picker has closed Safari can hold fixed boxes
         some way from the viewport the button is measured in. A creator
         card's ⋯ opened 175px under its button that way (reported by the
         user on 2026-09-27, iPhone, installed app). So the menu is placed
         from where a fixed box beside it actually lands: a probe at 0,0 in
         the menu's own container reads that origin, whatever made it, and
         it is taken off. Read from the probe and never from the menu, which
         is itself mid-way through its opening move when it is placed. */
      var probe = document.createElement('i');
      probe.setAttribute('aria-hidden', 'true');
      probe.style.cssText = 'position:fixed;left:0;top:0;width:0;height:0;visibility:hidden;pointer-events:none';
      (menu.parentNode || document.body).insertBefore(probe, menu);
      var o = probe.getBoundingClientRect();
      probe.parentNode.removeChild(probe);
      if (o.left || o.top) {
        menu.style.left = (parseFloat(menu.style.left) - o.left) + 'px';
        menu.style.top = (parseFloat(menu.style.top) - o.top) + 'px';
      }
      held = { btn: btn, top: r.top, menu: menu, align: align };
    },
    /* Call it with the card already visible, as `place`. The card carries
       `.popcard`; `is-dock` and `is-up` say how it was laid, and `--caret`
       where its caret points along its top or bottom edge. */
    pop: function (btn, card, align) {
      card.classList.add('popcard');
      /* Laid from the page itself: a fixed card inside the bar took the bar
         as its box, and "the foot of the screen" became the bar's foot. */
      if (card.parentNode !== document.body) document.body.appendChild(card);
      if (phone && phone.matches) {
        card.classList.add('is-dock');
        card.classList.remove('is-up');
        card.style.position = card.style.left = card.style.top = card.style.right = '';
        held = { btn: btn, top: btn.getBoundingClientRect().top, menu: card, align: align, pop: true };
        return;
      }
      card.classList.remove('is-dock');
      this.place(btn, card, align);
      held.pop = true;
      var r = btn.getBoundingClientRect(), c = card.getBoundingClientRect(), up = c.top < r.top;
      card.classList.toggle('is-up', up);
      // Room for the caret between the control and the card.
      card.style.top = (parseFloat(card.style.top) + (up ? -6 : 6)) + 'px';
      var x = r.left + r.width / 2 - c.left;
      card.style.setProperty('--caret', Math.max(18, Math.min(c.width - 18, x)) + 'px');
    },
    // How this page shuts its own menus, for a scroll that has really moved.
    onScroll: function (shut) { closers.push(shut); }
  };
})();
