/*
 * The command bar on a phone: one row, and the filters behind one button.
 *
 * At a desk the bar is the search, the filters, the count, the `?` and the
 * route's one or two actions on one line. Drawn the same way at 390 it was
 * four rows and 430px of controls before the first record, on a screen 700px
 * tall, which the user sent back on 2026-09-22. The two controls used all day
 * (the search, the view) keep the bar; the ones changed rarely (the selects,
 * the count, the `?`) go behind a Filters button and come up in a sheet from
 * the floor, which is the shape every list app on a phone already has.
 *
 * Nothing is duplicated. The selects are the same elements with the same
 * listeners: on open they are moved into the sheet, each under a label taken
 * from its own accessible name, and on close they are put back where they
 * stood. A badge on the button counts the filters that are off their default
 * (`data-default`, else the first option; `data-nofilter` is never counted,
 * because a workflow axis is not a filter). Clear puts every one back and
 * fires `change`, so the page repaints exactly as it would from the bar.
 *
 * Search is a mark too, and the widest control in the bar: on a phone it
 * grows into the field when it is pressed (the `.namebox` move the client's
 * Approve makes) and collapses again when it is left empty, which is what
 * leaves room for the count and the `?` on the right of the same row. It
 * stays open while it holds a value, and the mark carries the ink edge while
 * it is shut, because a filtered list has to say why on the screen.
 *
 * The primary action keeps its fill and gives up its word on a phone (the
 * word stays as its accessible name); a second action goes into a ⋯ beside
 * it, placed by `ADspaceMenu` like every other menu. A bar with no selects
 * (Content Review) draws no Filters button, and a lone action that is not the
 * primary (Manage clients) keeps its word, because it fits.
 *
 * At a desk the same button holds the same selects (the user, 2026-10-01:
 * the filters behind one button on every bar), in a card that hangs from it
 * (`ADspaceMenu.pop`) rather than a sheet, because a desk has the room to
 * keep the list in sight while it is filtered. A select that is a view and
 * not a filter (`data-nofilter`: whose work, the workflow, a month or a
 * quarter) stays in the bar at a desk, where it is read all day.
 */
(function () {
  'use strict';
  var $ = function (id) { return document.getElementById(id); };
  var PHONE = '(max-width: 640px)';
  var mq = window.matchMedia ? window.matchMedia(PHONE) : { matches: false, addEventListener: function () {} };
  var bars = [];
  var open = null;   // { bar, slots: [{ slot, node }], from }
  var sheet, card, body, head, title, doneBtn, clearBtn, closeBtn;
  var pop, popBody, popClear;

  function svg(path) {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + path + '</svg>';
  }
  var GLYPH_FILTERS = svg('<path d="M4 7h10M18 7h2M4 17h4M12 17h8"/><circle cx="16" cy="7" r="2"/><circle cx="10" cy="17" r="2"/>');
  var GLYPH_PLUS = svg('<path d="M12 5v14M5 12h14"/>');
  var GLYPH_SEARCH = svg('<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>');
  var GLYPH_X = svg('<path d="M6 6l12 12M18 6 6 18"/>');
  var GLYPH_MORE = svg('<circle cx="12" cy="5" r="1.4" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.4" fill="currentColor" stroke="none"/><circle cx="12" cy="19" r="1.4" fill="currentColor" stroke="none"/>');

  function selectsOf(bar) {
    return Array.prototype.filter.call(bar.children, function (el) { return el.tagName === 'SELECT'; });
  }
  function defaultOf(sel) {
    if (sel.hasAttribute('data-default')) return sel.getAttribute('data-default');
    return sel.options.length ? sel.options[0].value : '';
  }
  /* A view (`data-view`: Group by, Sort) rides in the card beside the
     filters but narrows nothing, so it is never counted and Clear leaves it. */
  function isOff(sel) {
    if (sel.hidden || sel.hasAttribute('data-nofilter') || sel.hasAttribute('data-view')) return false;
    return sel.value !== defaultOf(sel);
  }
  function labelOf(sel) {
    var t = sel.getAttribute('aria-label') || sel.name || 'Filter';
    return t.replace(/^Filter by\s+/i, function (m) { return ''; }).replace(/^[a-z]/, function (c) { return c.toUpperCase(); });
  }

  /* ---- The badge ---------------------------------------------------------- */
  /* While the sheet is open the selects are in it, not in the bar, so they
     are read from the slots that remember them. */
  function liveSelects(rec) {
    if (open && open.rec === rec) {
      return open.slots.map(function (s) { return s.node; }).filter(function (n) { return n.tagName === 'SELECT'; });
    }
    return rec.selects();
  }
  function paintBadge(rec) {
    var n = 0;
    liveSelects(rec).forEach(function (s) { if (isOff(s)) n++; });
    rec.badge.textContent = n ? String(n) : '';
    rec.badge.hidden = !n;
    rec.btn.setAttribute('aria-label', n ? 'Filters, ' + n + ' set' : 'Filters');
    if (open && open.rec === rec && open.pop) popClear.disabled = !n;
    /* A view that hides every select (My Work's Clients, Report) has nothing
       to filter, and a Filters button over an empty sheet is a dead control.
       At a desk a view select stays in the bar, so it does not count. */
    if (!(open && open.rec === rec)) {
      var desk = !mq.matches;
      rec.btn.hidden = !rec.selects().some(function (sel) {
        return !sel.hidden && !(desk && sel.hasAttribute('data-nofilter'));
      });
    }
  }
  function refresh() { bars.forEach(function (r) { paintBadge(r); mark(r); }); }

  /* ---- The sheet ---------------------------------------------------------- */
  function build() {
    if (sheet) return;
    sheet = document.createElement('div');
    sheet.className = 'sheet cmdsheet';
    sheet.id = 'cmdSheet';
    sheet.hidden = true;
    sheet.innerHTML =
      '<div class="sheet-card" role="dialog" aria-modal="true" aria-labelledby="cmdSheetTitle" tabindex="-1">' +
        '<div class="sheet-head"><h3 id="cmdSheetTitle">Filters</h3>' +
          '<span class="cmdsheet-quiet" id="cmdSheetQuiet"></span>' +
          '<button class="iconbtn" id="cmdSheetClose" type="button" aria-label="Close">' +
            svg('<path d="M6 6l12 12M18 6 6 18"/>') + '</button></div>' +
        '<div class="sheet-body cmdsheet-body" id="cmdSheetBody"></div>' +
        '<div class="sheet-foot"><button class="btn btn-primary" id="cmdSheetDone" type="button">Done</button>' +
          '<button class="btn btn-quiet" id="cmdSheetClear" type="button">Clear</button></div>' +
      '</div>';
    document.body.appendChild(sheet);
    card = sheet.firstChild; body = $('cmdSheetBody'); head = $('cmdSheetQuiet');
    doneBtn = $('cmdSheetDone'); clearBtn = $('cmdSheetClear'); closeBtn = $('cmdSheetClose');
    doneBtn.addEventListener('click', shut);
    closeBtn.addEventListener('click', shut);
    clearBtn.addEventListener('click', clear);
    sheet.addEventListener('click', function (e) { if (e.target === sheet) shut(); });
  }
  /* Escape shuts the sheet or the card before anything under it hears it. */
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && open) { e.stopPropagation(); e.preventDefault(); shut(); }
  }, true);
  /* The desk's card: the same selects, hung from the button. */
  function buildPop() {
    if (pop) return;
    pop = document.createElement('div');
    /* Not a `.kmenu`: every section's menu-closer shuts all of those on any
       press, the one that opens this card included. */
    pop.className = 'cmdpop';
    pop.id = 'cmdPop';
    pop.hidden = true;
    pop.tabIndex = -1;
    pop.setAttribute('role', 'dialog');
    pop.setAttribute('aria-labelledby', 'cmdPopTitle');
    pop.innerHTML =
      '<div class="popcard-head"><p class="cmdpop-title" id="cmdPopTitle">Filters</p>' +
        '<button class="iconbtn popcard-x" id="cmdPopClose" type="button" aria-label="Close">' + GLYPH_X + '</button></div>' +
      '<div class="cmdpop-body" id="cmdPopBody"></div>' +
      '<div class="cmdpop-acts"><button class="btn btn-sm" id="cmdPopClear" type="button">Clear</button></div>';
    document.body.appendChild(pop);
    popBody = $('cmdPopBody'); popClear = $('cmdPopClear');
    $('cmdPopClose').addEventListener('click', function () { shut(); });
    popClear.addEventListener('click', clear);
    pop.addEventListener('click', function (e) { e.stopPropagation(); });
    /* A press anywhere else shuts it and leaves focus where the press put it. */
    document.addEventListener('click', function (e) {
      if (open && open.pop && !open.rec.btn.contains(e.target)) shut(true);
    });
    if (window.ADspaceMenu && window.ADspaceMenu.onScroll) {
      window.ADspaceMenu.onScroll(function () { if (open && open.pop) shut(true); });
    }
  }
  /* Moves a node into `to`, leaving a slot where it stood so it can go back
     to exactly that place: the bar's order is the page's, not the sheet's. */
  function lift(node, to) {
    var slot = document.createElement('span');
    slot.className = 'cmd-slot';
    slot.hidden = true;
    node.parentNode.insertBefore(slot, node);
    to.appendChild(node);
    return { slot: slot, node: node };
  }
  function show(rec) {
    var desk = !mq.matches;
    if (desk) buildPop(); else build();
    if (open) shut(true);
    var host = desk ? popBody : body;
    open = { rec: rec, slots: [], from: document.activeElement, pop: desk };
    host.innerHTML = '';
    rec.selects().forEach(function (sel) {
      if (desk && sel.hasAttribute('data-nofilter')) return;
      var field = document.createElement('div');
      field.className = 'field cmdsheet-field';
      field.hidden = sel.hidden;
      var lab = document.createElement('label');
      lab.className = 'field-label';
      lab.textContent = labelOf(sel);
      if (!sel.id) sel.id = 'cmd-' + Math.random().toString(36).slice(2, 8);
      lab.setAttribute('for', sel.id);
      field.appendChild(lab);
      host.appendChild(field);
      open.slots.push(lift(sel, field));
      /* A control the page shows or hides while the card is open (My Work's
         period, drawn once All tasks or Completed is chosen) is shown or
         hidden in the card too: read once at opening, the period stayed out
         of sight and All tasks quietly meant this week (the user, 2026-10-04). */
      if (window.MutationObserver) {
        var mo = new MutationObserver(function () { field.hidden = sel.hidden; });
        mo.observe(sel, { attributes: true, attributeFilter: ['hidden'] });
        open.watch = (open.watch || []).concat(mo);
      }
    });
    rec.btn.setAttribute('aria-expanded', 'true');
    if (desk) {
      pop.hidden = false;
      paintBadge(rec);
      if (window.ADspaceMenu) window.ADspaceMenu.pop(rec.btn, pop, 'left');
      try { pop.focus({ preventScroll: true }); } catch (e) { pop.focus(); }
      return;
    }
    sheet.hidden = false;
    /* The card takes focus, never a field: a select focused for the reader
       wears the blue ring, and iOS will not open a select that already has
       focus, so the first tap on it did nothing (the user, 2026-09-26). */
    try { card.focus({ preventScroll: true }); } catch (e) { card.focus(); }
  }
  function shut(stay) {
    if (!open) return;
    var o = open; open = null;
    (o.watch || []).forEach(function (mo) { mo.disconnect(); });
    o.slots.reverse().forEach(function (s) {
      if (s.slot.parentNode) s.slot.parentNode.replaceChild(s.node, s.slot);
    });
    if (o.pop) pop.hidden = true; else sheet.hidden = true;
    o.rec.btn.setAttribute('aria-expanded', 'false');
    paintBadge(o.rec);
    if (stay === true) return;
    if (o.from && o.from.focus && document.contains(o.from)) o.from.focus(); else o.rec.btn.focus();
  }
  function clear() {
    if (!open) return;
    liveSelects(open.rec).forEach(function (sel) {
      if (sel.hidden || sel.hasAttribute('data-nofilter') || sel.hasAttribute('data-view')) return;
      var d = defaultOf(sel);
      if (sel.value === d) return;
      sel.value = d;
      sel.dispatchEvent(new Event('change', { bubbles: true }));
    });
    paintBadge(open.rec);
  }

  /* ---- The actions ---------------------------------------------------------- */
  function wireActions(bar) {
    var acts = bar.querySelector('.cmdbar-acts');
    if (!acts) return;
    var buttons = Array.prototype.filter.call(acts.children, function (el) { return el.tagName === 'BUTTON'; });
    if (!buttons.length) return;
    var primary = buttons.filter(function (b) { return b.classList.contains('btn-primary'); })[0];
    if (!primary) return;
    /* The word stays for a screen reader; on a phone only the glyph draws. */
    var word = '';
    Array.prototype.forEach.call(primary.childNodes, function (n) {
      if (n.nodeType === 3 && n.textContent.trim()) {
        var span = document.createElement('span');
        span.className = 'btn-word';
        span.textContent = n.textContent.trim();
        word = span.textContent;
        primary.replaceChild(span, n);
      }
    });
    /* A word the page already wrapped is the same word, and names the button
       the same way. */
    var said = primary.querySelector('.btn-word');
    if (!word && said) word = said.textContent.trim();
    if (!primary.querySelector('svg')) primary.insertAdjacentHTML('afterbegin', GLYPH_PLUS);
    if (word && !primary.getAttribute('aria-label')) primary.setAttribute('aria-label', word);
    primary.classList.add('cmd-primary');
    var rest = buttons.filter(function (b) { return b !== primary; });
    if (!rest.length) return;
    /* A second action goes behind a ⋯ on a phone, the way a rare action does
       on every row; each item presses the real button, so the page's own
       wiring is what runs. */
    var wrap = document.createElement('span');
    wrap.className = 'cmd-more';
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'kmenu-btn btn-sm cmd-more-btn';
    btn.setAttribute('aria-haspopup', 'true');
    btn.setAttribute('aria-expanded', 'false');
    btn.setAttribute('aria-label', 'More actions');
    btn.innerHTML = GLYPH_MORE;
    var menu = document.createElement('div');
    menu.className = 'kmenu cmd-more-menu';
    menu.setAttribute('role', 'menu');
    menu.hidden = true;
    /* Each item follows its button: the button's permission mark rides on
       the item (`data-need`, hidden by the same body class), and a button the
       page hides hides its item. The ⋯ itself leaves when nothing in it can
       be pressed: Documents' Add entry stayed in it for a colleague at View
       after the page had hidden the button (audit, 2026-10-03). */
    var pairs = [];
    rest.forEach(function (b) {
      b.classList.add('cmd-secondary');
      var item = document.createElement('button');
      item.type = 'button';
      item.className = 'kmenu-item';
      item.setAttribute('role', 'menuitem');
      item.textContent = (b.textContent || '').trim();
      if (b.getAttribute('data-need')) item.setAttribute('data-need', b.getAttribute('data-need'));
      item.addEventListener('click', function () { shutMore(); b.click(); });
      menu.appendChild(item);
      pairs.push([b, item]);
    });
    wrap.appendChild(btn); wrap.appendChild(menu);
    acts.insertBefore(wrap, primary);
    function syncMore() {
      var any = false;
      pairs.forEach(function (pr) {
        pr[1].hidden = pr[0].hidden;
        if (!pr[1].hidden && getComputedStyle(pr[1]).display !== 'none') any = true;
      });
      wrap.hidden = !any;
      if (!any) shutMore();
    }
    if (window.MutationObserver) {
      var watch = new MutationObserver(syncMore);
      pairs.forEach(function (pr) { watch.observe(pr[0], { attributes: true, attributeFilter: ['hidden'] }); });
      watch.observe(document.body, { attributes: true, attributeFilter: ['class'] });
    }
    syncMore();
    function shutMore() { menu.hidden = true; btn.setAttribute('aria-expanded', 'false'); }
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      syncMore();
      var on = menu.hidden;
      menu.hidden = !on;
      btn.setAttribute('aria-expanded', String(on));
      if (on && window.ADspaceMenu) window.ADspaceMenu.place(btn, menu);
    });
    document.addEventListener('click', function (e) { if (!wrap.contains(e.target)) shutMore(); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') shutMore(); });
    if (window.ADspaceMenu && window.ADspaceMenu.onScroll) window.ADspaceMenu.onScroll(shutMore);
  }

  /* ---- The search, which is a mark until it is pressed -------------------- */
  function wireSearch(rec) {
    var bar = rec.bar;
    var find = bar.querySelector('.cmdbar-find');
    if (!find) return;
    var input = find.querySelector('input');
    if (!input) return;
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'iconbtn btn-sm cmdbar-search';
    btn.setAttribute('aria-label', input.getAttribute('aria-label') || 'Search');
    btn.setAttribute('aria-expanded', 'false');
    btn.innerHTML = GLYPH_SEARCH;
    find.parentNode.insertBefore(btn, find);
    var clear = document.createElement('button');
    clear.type = 'button';
    clear.className = 'cmdbar-find-clear';
    clear.setAttribute('aria-label', 'Close search');
    clear.innerHTML = GLYPH_X;
    find.appendChild(clear);
    rec.search = btn;
    rec.input = input;

    function openIt() {
      bar.classList.add('is-searching');
      btn.setAttribute('aria-expanded', 'true');
      input.focus();
    }
    /* It shuts only when it is empty: a list filtered by something the
       person cannot see is a list that looks wrong. */
    function shutIt(force) {
      if (!force && input.value.trim()) return;
      bar.classList.remove('is-searching');
      btn.setAttribute('aria-expanded', 'false');
      mark(rec);
    }
    btn.addEventListener('click', openIt);
    clear.addEventListener('click', function () {
      if (input.value) {
        input.value = '';
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
      }
      shutIt(true);
      btn.focus();
    });
    input.addEventListener('keydown', function (e) {
      if (e.key !== 'Escape') return;
      e.stopPropagation();
      if (input.value) {
        input.value = '';
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
      }
      shutIt(true);
      btn.focus();
    });
    input.addEventListener('blur', function () { setTimeout(function () { shutIt(false); }, 120); });
    input.addEventListener('input', function () { mark(rec); });
    rec.openSearch = openIt;
  }
  /* The mark says the list is filtered while the field is shut. */
  function mark(rec) {
    if (!rec.search || !rec.input) return;
    rec.search.classList.toggle('is-set', !!rec.input.value.trim());
  }

  /* ---- Wiring ------------------------------------------------------------- */
  function wire(bar) {
    if (bar.__cmdbar) return;
    var rec = { bar: bar, selects: function () { return selectsOf(bar); } };
    bar.__cmdbar = rec;
    var find = bar.querySelector('.cmdbar-find');
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'iconbtn btn-sm cmdbar-filters';
    btn.setAttribute('aria-label', 'Filters');
    btn.setAttribute('aria-haspopup', 'dialog');
    btn.setAttribute('aria-expanded', 'false');
    btn.innerHTML = GLYPH_FILTERS + '<span class="cmdbar-badge" hidden></span>';
    rec.btn = btn; rec.badge = btn.lastChild;
    var sels = rec.selects();
    if (!sels.length) btn.hidden = true;
    /* After the bar's last select, so at a desk the views kept in the bar
       come first and the button that holds the rest follows them. */
    var at = sels.length ? sels[sels.length - 1].nextSibling : (find ? find.nextSibling : null);
    if (at) bar.insertBefore(btn, at); else bar.appendChild(btn);
    btn.addEventListener('click', function () { if (open && open.rec === rec) shut(); else show(rec); });
    wireSearch(rec);
    wireActions(bar);
    bars.push(rec);
    paintBadge(rec);
  }
  function wireAll() {
    Array.prototype.forEach.call(document.querySelectorAll('.cmdbar'), wire);
  }
  document.addEventListener('change', function (e) {
    var t = e.target;
    if (t && t.tagName === 'SELECT') refresh();
  }, true);
  document.addEventListener('click', function () { setTimeout(refresh, 0); }, true);
  /* Crossing the phone line with the sheet or the card open puts everything
     back: each width has its own holder, and its own view selects. */
  function crossed(m) {
    shut(true);
    if (!m.matches) {
      bars.forEach(function (r) {
        r.bar.classList.remove('is-searching');
        if (r.search) r.search.setAttribute('aria-expanded', 'false');
      });
    }
    refresh();
  }
  if (mq.addEventListener) mq.addEventListener('change', crossed);
  else if (mq.addListener) mq.addListener(crossed);

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', wireAll);
  else wireAll();

  window.ADspaceCmdbar = { refresh: refresh, shut: shut, wire: wireAll };
})();
