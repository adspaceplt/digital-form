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
 * Above 640 none of this draws: the bar is exactly what it was.
 */
(function () {
  'use strict';
  var $ = function (id) { return document.getElementById(id); };
  var PHONE = '(max-width: 640px)';
  var mq = window.matchMedia ? window.matchMedia(PHONE) : { matches: false, addEventListener: function () {} };
  var bars = [];
  var open = null;   // { bar, slots: [{ slot, node }], from }
  var sheet, card, body, head, title, doneBtn, clearBtn, closeBtn;

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
  function isOff(sel) {
    if (sel.hidden || sel.hasAttribute('data-nofilter')) return false;
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
      '<div class="sheet-card" role="dialog" aria-modal="true" aria-labelledby="cmdSheetTitle">' +
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
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && open) { e.stopPropagation(); shut(); }
    }, true);
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
    build();
    if (open) shut();
    open = { rec: rec, slots: [], from: document.activeElement };
    body.innerHTML = '';
    rec.selects().forEach(function (sel) {
      var field = document.createElement('div');
      field.className = 'field cmdsheet-field';
      field.hidden = sel.hidden;
      var lab = document.createElement('label');
      lab.className = 'field-label';
      lab.textContent = labelOf(sel);
      if (!sel.id) sel.id = 'cmd-' + Math.random().toString(36).slice(2, 8);
      lab.setAttribute('for', sel.id);
      field.appendChild(lab);
      body.appendChild(field);
      open.slots.push(lift(sel, field));
    });
    sheet.hidden = false;
    rec.btn.setAttribute('aria-expanded', 'true');
    var first = body.querySelector('select:not([hidden])');
    if (first) first.focus(); else doneBtn.focus();
  }
  function shut() {
    if (!open) return;
    var o = open; open = null;
    o.slots.reverse().forEach(function (s) {
      s.slot.parentNode.replaceChild(s.node, s.slot);
    });
    sheet.hidden = true;
    o.rec.btn.setAttribute('aria-expanded', 'false');
    paintBadge(o.rec);
    if (o.from && o.from.focus && document.contains(o.from)) o.from.focus(); else o.rec.btn.focus();
  }
  function clear() {
    if (!open) return;
    liveSelects(open.rec).forEach(function (sel) {
      if (sel.hidden || sel.hasAttribute('data-nofilter')) return;
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
    btn.className = 'kmenu-btn cmd-more-btn';
    btn.setAttribute('aria-haspopup', 'true');
    btn.setAttribute('aria-expanded', 'false');
    btn.setAttribute('aria-label', 'More actions');
    btn.innerHTML = GLYPH_MORE;
    var menu = document.createElement('div');
    menu.className = 'kmenu cmd-more-menu';
    menu.setAttribute('role', 'menu');
    menu.hidden = true;
    rest.forEach(function (b) {
      b.classList.add('cmd-secondary');
      var item = document.createElement('button');
      item.type = 'button';
      item.className = 'kmenu-item';
      item.setAttribute('role', 'menuitem');
      item.textContent = (b.textContent || '').trim();
      item.addEventListener('click', function () { shutMore(); b.click(); });
      menu.appendChild(item);
    });
    wrap.appendChild(btn); wrap.appendChild(menu);
    acts.insertBefore(wrap, primary);
    function shutMore() { menu.hidden = true; btn.setAttribute('aria-expanded', 'false'); }
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
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
    if (!rec.selects().length) btn.hidden = true;
    if (find && find.nextSibling) bar.insertBefore(btn, find.nextSibling); else bar.appendChild(btn);
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
  /* Growing past the phone line with the sheet open puts everything back:
     the desk bar draws its own selects and never this sheet. */
  function deskAgain() {
    shut();
    bars.forEach(function (r) {
      r.bar.classList.remove('is-searching');
      if (r.search) r.search.setAttribute('aria-expanded', 'false');
    });
  }
  if (mq.addEventListener) mq.addEventListener('change', function (m) { if (!m.matches) deskAgain(); });
  else if (mq.addListener) mq.addListener(function (m) { if (!m.matches) deskAgain(); });

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', wireAll);
  else wireAll();

  window.ADspaceCmdbar = { refresh: refresh, shut: shut, wire: wireAll };
})();
