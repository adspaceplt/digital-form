/* ADspaceGroup — the one copy of a directory group: a heading that folds,
   with its count and its marks, over the card that holds the group's rows.

   Every console directory (Clients, Content Review, Creator Campaigns, the
   Creators List, Short Links, Documents, Services, Team) is drawn from this,
   so a stage on Clients, a state on Campaigns, a fee band on the Creators
   List, a category on the rate card and a user group on the Team page are
   the same shape: the 15px heading with the count, the name as the fold,
   and a card with its own header row under it. It replaced three shapes at
   once — the uppercase `.svc-cat.crm-band` divider rows inside one surface
   (sent back by the user on 2026-09-22), a card per group written twice
   with no fold, and a single card with no heading at all.

   A fold is remembered per browser under one key, by route and group, so a
   Past clients card shut on Monday is shut on Tuesday. A filter opens every
   group, because somebody who searched for a name wants the row wherever it
   is. Loaded before every section script. */
(function () {
  'use strict';

  var KEY = 'adspace-groups';

  function kept() {
    try { return JSON.parse(localStorage.getItem(KEY) || '{}') || {}; } catch (e) { return {}; }
  }
  /* Whether a group is shut: what the person chose, else the route's default.
     A group that holds everything on the page never shuts by default: a
     route whose one card is folded is a heading over nothing (every link
     paused, every campaign completed), and a person's own fold still holds. */
  function shut(route, key, dflt, lone) {
    var v = kept()[route + ':' + key];
    return typeof v === 'boolean' ? v : (!!dflt && !lone);
  }
  function keep(route, key, isShut) {
    var k = kept();
    k[route + ':' + key] = isShut;
    try { localStorage.setItem(KEY, JSON.stringify(k)); } catch (e) {}
  }

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  var CHEV = '<svg class="crm-band-fold" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
    'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<path d="M9 18l6-6-6-6"/></svg>';

  /* One group.
       route   the route the memory is filed under ('clients', 'campaigns', …)
       key     the group's own key ('past', 'production', 'rm300', …), which
               is what the card is identified by on the page (`data-band`)
       memo    optional, what the fold is remembered under instead of `key`.
               A directory that can be cut on more than one axis needs these
               apart: My Work's Overdue card is `overdue` whichever axis is
               on, but a card shut under By client has nothing to say about a
               card under By stage, so the memory carries the axis and the
               identity does not
       name    the heading
       count   how many rows the group holds, drawn on the heading
       marks   optional HTML after the fold (a warn chip, a value); the caller
               escapes it
       shut    whether it is shut now (the caller has already asked shut()
               and applied its filter rule)
       table   a function returning the card (`.crm-table.softpanel`) with
               its header row and rows; called only while the group is open,
               so a shut group costs nothing to draw
       toggle  optional, called with the new shut state after the fold is
               pressed and remembered; the card itself opens and shuts in
               place, so a caller does not repaint
     Returns the <section class="crm-group">. */
  function section(o) {
    var sec = document.createElement('section');
    sec.className = 'crm-group' + (o.shut ? ' is-shut' : '');
    sec.setAttribute('data-band', o.key);
    var head = document.createElement('div');
    head.className = 'crm-group-head' + (o.shut ? ' is-shut' : '');
    head.innerHTML =
      '<h3><button class="crm-group-fold" type="button" aria-expanded="' + (o.shut ? 'false' : 'true') + '">' +
        CHEV + esc(o.name) + '<span>' + Number(o.count || 0) + '</span></button></h3>' +
      (o.marks || '');
    sec.appendChild(head);
    /* The card opens and shuts in place, from its heading, rather than the
       whole directory repainting around it: a fold is a move somebody made
       and the eye follows a surface that arrives, not one that blinks into
       place. The body is a grid row that goes from 0fr to 1fr, which is the
       one height transition CSS can run without a stated height. A shut
       card is emptied once it has closed, so it costs nothing while it waits
       and the DOM holds only what is on the screen. */
    var body = document.createElement('div');
    body.className = 'crm-group-body';
    var inner = document.createElement('div');
    inner.className = 'crm-group-inner';
    if (!o.shut && o.table) inner.appendChild(drawn(o));
    body.appendChild(inner);
    sec.appendChild(body);
    var btn = head.querySelector('.crm-group-fold');
    var shutNow = !!o.shut;
    body.addEventListener('transitionend', function (e) {
      if (e.target !== body || !shutNow) return;
      inner.innerHTML = '';
    });
    btn.addEventListener('click', function () {
      shutNow = !shutNow;
      keep(o.route, o.memo || o.key, shutNow);
      if (!shutNow && !inner.firstChild && o.table) inner.appendChild(drawn(o));
      sec.classList.toggle('is-shut', shutNow);
      head.classList.toggle('is-shut', shutNow);
      btn.setAttribute('aria-expanded', String(!shutNow));
      if (o.toggle) o.toggle(shutNow);
    });
    return sec;
  }

  /* A card draws its first `limit` rows and offers the rest under one
     control, so a group of a hundred and eighty opens as a page somebody can
     read rather than as a mile of rows. Once somebody has asked for the
     rest, the card keeps them for as long as the page is open: a save
     repaints the directory, and a repaint that put the rows back behind
     Show more took away the row the person was working down (the user,
     2026-09-26, on Documents). The card is known by the section drawing it,
     so no caller has to say which card it is. */
  var opened = {}, drawing = null;
  function drawn(o) {
    var was = drawing;
    drawing = o.route + ':' + (o.memo || o.key);
    try { return o.table(); } finally { drawing = was; }
  }
  function more(table, items, limit, word, rowOf) {
    var card = drawing;
    if (card && opened[card]) limit = items.length;
    items.slice(0, limit).forEach(function (it) { table.appendChild(rowOf(it)); });
    if (items.length <= limit) return;
    var btn = document.createElement('button');
    btn.type = 'button'; btn.className = 'crm-group-more';
    btn.textContent = 'Show ' + (items.length - limit) + ' more' + (word ? ' ' + word : '');
    btn.addEventListener('click', function () {
      if (card) opened[card] = true;
      items.slice(limit).forEach(function (it) { table.insertBefore(rowOf(it), btn); });
      btn.remove();
    });
    table.appendChild(btn);
  }

  /* The card itself: the surface and its header row, one cell per column,
     empty over the ⋯ or the chevron. `rowClass` is the table's own row
     class, so the header shares the row's grid. */
  function table(rowClass, heads, extraClass) {
    var t = document.createElement('div');
    t.className = 'crm-table softpanel' + (extraClass ? ' ' + extraClass : '');
    var h = document.createElement('div');
    h.className = 'crm-head ' + rowClass;
    h.innerHTML = heads.map(function (x) {
      if (x && typeof x === 'object') return '<span class="' + esc(x.cls) + '">' + esc(x.text) + '</span>';
      return '<span>' + esc(x) + '</span>';
    }).join('');
    t.appendChild(h);
    return t;
  }

  window.ADspaceGroup = { shut: shut, keep: keep, section: section, more: more, table: table };
})();
