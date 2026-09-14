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

  window.ADspaceMenu = {
    /* Placed on the viewport rather than in the row, so the table's own
       overflow cannot clip it, and upwards where the room is above: a ⋯ on
       the last row used to open past the bottom of the window, which is
       nowhere a phone can reach. Call it with the menu already visible; the
       height cannot be measured otherwise. */
    place: function (btn, menu) {
      var r = btn.getBoundingClientRect(), h = menu.offsetHeight;
      menu.style.position = 'fixed';
      menu.style.right = 'auto';
      menu.style.left = Math.max(8, r.right - menu.offsetWidth) + 'px';
      menu.style.top = (r.bottom + 4 + h <= window.innerHeight - 8 || r.top - 4 - h < 8)
        ? (r.bottom + 4) + 'px'
        : (r.top - 4 - h) + 'px';
      held = { btn: btn, top: r.top };
    },
    // How this page shuts its own menus, for a scroll that has really moved.
    onScroll: function (shut) { closers.push(shut); }
  };
})();
