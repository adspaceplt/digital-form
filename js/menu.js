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
  // Open, Change, Send, Mark, Lifecycle, Remove and destroy.
  var GROUPS = 6;

  window.ADspaceMenu = {
    /* Placed on the viewport rather than in the row, so the table's own
       overflow cannot clip it, and upwards where the room is above: a ⋯ on
       the last row used to open past the bottom of the window, which is
       nowhere a phone can reach. Call it with the menu already visible; the
       height cannot be measured otherwise. */
    place: function (btn, menu, align) {
      tidy(menu);
      /* Every ⋯ hangs from its own button, on a phone as at a desk, so the
         menu opens where the finger already is (DESIGN.md §5 Menus, 11; the
         user, 2026-10-24). */
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
      /* The phone tab bar holds the foot of the screen (:root.has-tabbar):
         a menu outside a sheet keeps above it, and opens upward sooner. A
         sheet covers the bar, so a menu inside one has the whole height. */
      var floor = window.innerHeight - 8;
      var tabbar = document.getElementById('tabBar');
      if (tabbar && document.documentElement.classList.contains('has-tabbar') && !btn.closest('.sheet')) {
        var tb = tabbar.getBoundingClientRect();
        if (tb.height) floor = Math.min(floor, tb.top - 8);
      }
      menu.style.top = (r.bottom + 4 + h <= floor || r.top - 4 - h < 8)
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
      /* Docked from inside a sheet, the card keeps the sheet's foot: the
         sheet covers the tab bar, so there is no bar to rise above. */
      card.classList.toggle('is-insheet', Boolean(btn.closest && btn.closest('.sheet')));
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
    onScroll: function (shut) { closers.push(shut); },
    /* One way to write a ⋯ menu's items (DESIGN.md §5 Menus and action
       groups; the user, 2026-10-22: "MENU standard: approve"). `groups` is
       the six groups in their fixed order, Open, Change, Send, Mark,
       Lifecycle, Remove and destroy; each an array of items, a falsy item
       left out (an item that cannot apply in the record's state is not
       drawn). An item is { a, label, need, attrs, id, hidden }: `a` its
       `data-a` (or `key` names another attribute, `data-i` for My Work),
       `attrs` any further attributes as written. The group's number rides
       each item (`data-g`), so `tidy` lays the separators and the red for
       whatever the page shows or hides afterwards. */
    items: function (groups, key) {
      var out = '', k = key || 'data-a';
      for (var g = 0; g < groups.length && g < GROUPS; g++) {
        var list = groups[g] || [];
        for (var i = 0; i < list.length; i++) {
          var it = list[i];
          if (!it) continue;
          out += '<button class="kmenu-item' + (g === GROUPS - 1 ? ' is-danger' : '') + '" type="button" role="menuitem" data-g="' + (g + 1) + '"' +
            (it.a ? ' ' + k + '="' + attr(it.a) + '"' : '') +
            (it.id ? ' id="' + attr(it.id) + '"' : '') +
            (it.need ? ' data-need="' + attr(it.need) + '"' : '') +
            (it.attrs ? ' ' + it.attrs : '') +
            (it.hidden ? ' hidden' : '') + '>' + text(it.label) + '</button>';
        }
      }
      return out;
    },
    /* A menu's items in order, as the page shows them now: roles, the red
       of group 6 and nothing else, and a separator before group 6 when
       anything precedes it, and between every other change of group once
       four items or more show. Run by itself whenever a menu is shown. */
    tidy: tidy,
    GROUPS: GROUPS,
    /* The group a label belongs to (DESIGN.md §5 Menus and action groups),
       for a page that writes its items one at a time: `item(a, label,
       need, key, attrs)` writes one as `items` would. 0 is a label the standard
       does not name, which the page must place itself. */
    groupOf: groupOf,
    item: function (a, label, need, key, attrs) {
      var g = groupOf(label) || 2, one = [[], [], [], [], [], []];
      one[g - 1].push({ a: a, label: label, need: need, attrs: attrs });
      return this.items(one, key);
    }
  };

  var WORDS = [
    /^(Open|Open .+|Versions|Download|Preview|Link history|Compare groups)$/,
    /^(Edit|Rename|Make a copy|New version|Take|Take lead|Offer to the team|Withdraw offer|Reassign|Change reviewer|Assign reviewer|Transfer client|White label|Change content month|Access code|Pair with video|Select|Select .+|Templates|Task numbering|Due dates|Make main contact|Move to objective|Rename brand|Use ADspace logo|Use .+ logo|Meta accounts|Use billing details|Issue Letter of Offer|Issue document|Add existing document|Hand over work|Confirm without letter|Repeat on a schedule|Reissue|Replace|Add tasks|Import from .+|Pictures from Meta|Move to .+|Review profile|Tax and terms|Document types|Bulk import)$/,
    /^(Send on WhatsApp|Request feedback on WhatsApp|Resend booking|Send invitation|Share with .+|Stop sharing|Request re-approval|Send email)$/,
    /^(Mark .+|Remove VIC|Verify signed letter|Confirm internally|Confirm for client|Revert confirmation|Clear ad error)$/,
    /^(Set inactive|Set active|Archive|Restore|Pause|Resume|Resume .+|Not proceeding|Unpublish|Withdraw|Revert (?!confirmation).+|Reopen|Reopen .+|Stop|Cancel month|Reset link|Close link|Revoke portal access|Enable portal access|Extend access|End access|Set access expiry|Withdraw confirmation)$/,
    /^(Remove|Remove from .+|Void|Delete)$/
  ];
  function groupOf(label) {
    var w = String(label == null ? '' : label).replace(/\s+/g, ' ').trim();
    // Mark .+ is a flag, but never Mark as sent's way back read as a Remove.
    for (var i = WORDS.length - 1; i >= 0; i--) if (WORDS[i].test(w)) return i + 1;
    return 0;
  }

  function attr(v) {
    return String(v).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
  function text(v) {
    return String(v == null ? '' : v).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
  function shown(el) {
    return !el.hidden && el.style.display !== 'none' && !el.closest('[hidden]:not(.kmenu)') &&
      (!el.isConnected || getComputedStyle(el).display !== 'none');
  }
  function tidy(menu) {
    if (!menu || !menu.querySelector || !menu.querySelector('[data-g]')) return;
    if (menu.getAttribute('role') !== 'menu') menu.setAttribute('role', 'menu');
    var old = menu.querySelectorAll('hr.kmenu-sep[data-auto]');
    for (var i = 0; i < old.length; i++) old[i].parentNode.removeChild(old[i]);
    /* Items in their group's order, whatever order the page wrote them:
       a stable sort by group, the page's order kept within a group. */
    var all = Array.prototype.slice.call(menu.querySelectorAll('.kmenu-item[data-g]'));
    var sorted = all.slice().sort(function (x, y) { return (+x.getAttribute('data-g') - +y.getAttribute('data-g')) || (all.indexOf(x) - all.indexOf(y)); });
    if (sorted.some(function (e, n) { return e !== all[n]; }) && all.every(function (e) { return e.parentNode === all[0].parentNode; })) {
      var tail = all[all.length - 1].nextSibling, host = all[0].parentNode;
      sorted.forEach(function (e) { host.insertBefore(e, tail); });
    }
    var items = Array.prototype.filter.call(menu.querySelectorAll('.kmenu-item[data-g]'), function (e) {
      if (e.getAttribute('role') !== 'menuitem') e.setAttribute('role', 'menuitem');
      e.classList.toggle('is-danger', e.getAttribute('data-g') === String(GROUPS));
      return shown(e);
    });
    var many = items.length >= 4;
    for (var j = 1; j < items.length; j++) {
      var a = items[j - 1].getAttribute('data-g'), b = items[j].getAttribute('data-g');
      if (a === b) continue;
      if (b !== String(GROUPS) && !many) continue;
      var hr = document.createElement('hr');
      hr.className = 'kmenu-sep';
      hr.setAttribute('role', 'separator');
      hr.setAttribute('data-auto', '');
      items[j].parentNode.insertBefore(hr, items[j]);
    }
  }
  /* Every menu is tidied the moment it is shown, and again while it is
     open if an item shows or hides: the pages keep their own wiring. */
  if (window.MutationObserver) {
    new MutationObserver(function (list) {
      var seen = [];
      for (var i = 0; i < list.length; i++) {
        var t = list[i].target;
        var m = t.classList && t.classList.contains('kmenu') ? t : (t.closest ? t.closest('.kmenu') : null);
        if (m && seen.indexOf(m) < 0) { seen.push(m); if (!m.hidden) tidy(m); }
      }
    }).observe(document.documentElement, { subtree: true, attributes: true, attributeFilter: ['hidden'] });
  }
})();
