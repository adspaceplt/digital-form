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
      window.ADspaceMenu.place(held.btn, held.menu, held.align);
    });
  });

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
         ancestor is transformed. A sheet on a phone is (`will-change:
         transform`, so it lifts in one piece), which makes the card the box a
         fixed menu is placed in: a ⋯ inside a sheet opened as far below its
         button as the card is from the top of the screen, and off the bottom
         for a row low in the list. The card's own offset is taken off. Read
         from the card and never from the menu, because the menu is itself
         mid-way through its opening move when it is placed. */
      var card = menu.closest && menu.closest('.sheet-card');
      if (card) {
        var cs = getComputedStyle(card);
        if ((cs.transform && cs.transform !== 'none') || /transform/.test(cs.willChange || '')) {
          var cr = card.getBoundingClientRect();
          menu.style.left = (parseFloat(menu.style.left) - cr.left - card.clientLeft) + 'px';
          menu.style.top = (parseFloat(menu.style.top) - cr.top - card.clientTop) + 'px';
        }
      }
      held = { btn: btn, top: r.top, menu: menu, align: align };
    },
    // How this page shuts its own menus, for a scroll that has really moved.
    onScroll: function (shut) { closers.push(shut); }
  };
})();
