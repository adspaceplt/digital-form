/*
 * FIRST-VISIT GUIDES (the user, 2026-10-07: "first time users they dont
 * usually know what to do each ... a one time tutorial kind into the entire
 * portal").
 *
 * A section's guide opens by itself the first time a person lands on it, and
 * again whenever they ask (the console's ⓘ card, Show me around). It is a
 * card, never a cover: up to three steps, each pointing at a real control,
 * ringed while its step shows. It hangs from that control with a caret at a
 * desk and docks at the foot of the screen on a phone (ADspaceMenu.pop), so
 * it never sits over the command bar, and nothing on the page is locked
 * while it shows. A step whose control the person cannot see (a permission,
 * an empty list) is left out; a guide with no step left waits for a visit
 * that has one.
 *
 * Seen is kept per person: a colleague's in the database (`guide_seen`,
 * `guides_seen()` / `guide_seen_mark()`, so a guide met at a desk is not met
 * again on a phone), a client page's in this browser. The browser keeps a
 * copy either way, so a failed read never shows a guide twice here.
 *
 * ADspaceGuide.offer(key, guide)   the first visit: shown once, when nothing
 *                                  else is open and a step's control is drawn
 * ADspaceGuide.open(key, guide)    asked for: shown now, from its first step
 * ADspaceGuide.leave()             the route changed: a guide on screen is
 *                                  closed (and counts as seen)
 * ADspaceGuide.useServer(read, mark)
 *                                  read() answers a promise of the keys seen;
 *                                  mark(key) records one. Until read answers,
 *                                  nothing is offered.
 *
 * A guide is { name, steps: [{ at, text, title? }] }; `name`, `title` and
 * `text` are a string or { en, zh } (client pages follow their 中文 switch).
 */
(function () {
  var LOCAL = 'adspace-guide:';
  var server = { on: false, ready: null, seen: null, mark: null };
  var cur = null;      // { key, guide, steps, i, t }
  var card = null;
  var waitT = 0;
  var offerSeq = 0;

  var UI = {
    en: { next: 'Next', done: 'Done', skip: 'Skip', of: ' of ' },
    zh: { next: '下一步', done: '完成', skip: '跳过', of: ' / ' }
  };
  function zh() { return (document.documentElement.getAttribute('lang') || '').slice(0, 2) === 'zh'; }
  function ui() { return zh() ? UI.zh : UI.en; }
  function said(v) { return v && typeof v === 'object' ? ((zh() && v.zh) || v.en || '') : (v || ''); }

  function localSeen(key) { try { return localStorage.getItem(LOCAL + key) === '1'; } catch (e) { return false; } }
  function localMark(key) { try { localStorage.setItem(LOCAL + key, '1'); } catch (e) {} }
  function seen(key) {
    if (localSeen(key)) return true;
    return !!(server.seen && server.seen.indexOf(key) > -1);
  }
  function markSeen(key) {
    localMark(key);
    if (server.seen && server.seen.indexOf(key) < 0) server.seen.push(key);
    if (server.mark) { try { server.mark(key); } catch (e) {} }
  }

  /* Drawn, on the page, and not inside something hidden or shut. */
  function drawn(el) {
    if (!el || !el.isConnected || el.closest('[hidden], .is-shut .crm-group-body')) return false;
    var r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  }
  function targetOf(step) {
    var list = document.querySelectorAll(step.at);
    for (var i = 0; i < list.length; i++) if (drawn(list[i])) return list[i];
    return null;
  }
  function liveSteps(guide) {
    return (guide.steps || []).slice(0, 3).filter(function (s) { return targetOf(s); });
  }
  /* Something else has the person's attention: a sheet, a menu, a question,
     a cover, the console still booting. */
  function busy() {
    return !!document.querySelector(
      '.sheet:not([hidden]), .kmenu:not([hidden]), #askSheet:not([hidden]), ' +
      '.console.is-booting, .maint-cover:not([hidden]), .cover:not([hidden]):not(.is-off)');
  }

  function build() {
    if (card) return card;
    card = document.createElement('div');
    /* Never `.kmenu`: the pages shut every open menu on a press elsewhere,
       and a guide stays until it is finished or skipped. */
    card.className = 'guidecard';
    card.id = 'guideCard';
    card.hidden = true;
    card.setAttribute('role', 'dialog');
    card.setAttribute('aria-labelledby', 'guideTitle');
    card.setAttribute('aria-describedby', 'guideText');
    card.innerHTML =
      '<div class="popcard-head guide-head"><b class="guide-title" id="guideTitle"></b>' +
        '<span class="guide-n" id="guideN"></span></div>' +
      '<p class="guide-text" id="guideText"></p>' +
      '<div class="guide-acts">' +
        '<button class="btn btn-sm btn-primary" type="button" data-a="next" id="guideNext"></button>' +
        '<button class="btn btn-sm btn-quiet" type="button" data-a="skip" id="guideSkip"></button>' +
      '</div>';
    document.body.appendChild(card);
    card.addEventListener('click', function (e) {
      e.stopPropagation();
      var b = e.target.closest('[data-a]');
      if (!b || !cur) return;
      if (b.getAttribute('data-a') === 'skip') { close(true); return; }
      step(1);
    });
    return card;
  }

  function unring() { if (cur && cur.t) cur.t.classList.remove('guide-on'); }

  function paint() {
    if (!cur) return;
    var s = cur.steps[cur.i], t = targetOf(s);
    /* Its control has gone since (a repaint, a permission): the next step
       that still has one, else the guide ends. */
    while (!t && cur.i < cur.steps.length - 1) { cur.i++; s = cur.steps[cur.i]; t = targetOf(s); }
    if (!t) { close(true); return; }
    unring();
    cur.t = t;
    t.classList.add('guide-on');
    var c = build(), n = cur.steps.length, w = ui();
    c.querySelector('#guideTitle').textContent = said(s.title || cur.guide.name);
    var count = c.querySelector('#guideN');
    count.textContent = n > 1 ? (cur.i + 1) + w.of + n : '';
    count.hidden = n < 2;
    c.querySelector('#guideText').textContent = said(s.text);
    c.querySelector('#guideNext').textContent = cur.i === n - 1 ? w.done : w.next;
    c.querySelector('#guideSkip').textContent = w.skip;
    c.querySelector('#guideSkip').hidden = cur.i === n - 1;
    c.hidden = false;
    try { t.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch (e) {}
    var r = t.getBoundingClientRect();
    window.ADspaceMenu.pop(t, c, r.left + r.width / 2 < window.innerWidth / 2 ? 'left' : 'right');
  }

  function step(d) {
    if (!cur) return;
    if (cur.i + d >= cur.steps.length) { close(true); return; }
    cur.i = Math.max(0, cur.i + d);
    paint();
  }

  function close(done) {
    clearTimeout(waitT);
    if (!cur) return;
    unring();
    var key = cur.key;
    cur = null;
    if (card) card.hidden = true;
    if (done !== false) markSeen(key);
  }

  function show(key, guide, focus) {
    var steps = guide ? liveSteps(guide) : [];
    if (!steps.length) return false;
    close(false);
    cur = { key: key, guide: guide, steps: steps, i: 0, t: null };
    paint();
    if (focus && cur && card) { try { card.querySelector('#guideNext').focus({ preventScroll: true }); } catch (e) {} }
    return true;
  }

  /* Pressing the control a step points at is doing what it says: the guide
     has done its work. */
  document.addEventListener('click', function (e) {
    if (cur && cur.t && cur.t.contains(e.target)) close(true);
  }, true);
  // Escape ends it, before anything under it hears the key.
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape' || !cur || !card || card.hidden) return;
    if (document.querySelector('.sheet:not([hidden]), #askSheet:not([hidden])')) return;
    close(true);
    e.stopPropagation();
  }, true);
  // A scroll that carried its control away lays the card against it again.
  if (window.ADspaceMenu) window.ADspaceMenu.onScroll(function () { if (cur) paint(); });
  // The client pages' 中文 switch re-words a guide on screen.
  try {
    new MutationObserver(function () { if (cur) paint(); })
      .observe(document.documentElement, { attributes: true, attributeFilter: ['lang'] });
  } catch (e) {}

  window.ADspaceGuide = {
    offer: function (key, guide) {
      if (!key || !guide) return;
      clearTimeout(waitT);
      var mine = ++offerSeq;
      var go = function () {
        if (mine !== offerSeq || cur || seen(key)) return;
        var tries = 0;
        (function wait() {
          if (mine !== offerSeq || cur || seen(key)) return;
          if (!busy() && liveSteps(guide).length) { show(key, guide, false); return; }
          // A list still loading draws its controls within a few seconds.
          if (++tries < 24) waitT = setTimeout(wait, 250);
        })();
      };
      if (server.on) (server.ready || Promise.resolve()).then(go, go);
      else go();
    },
    open: function (key, guide) { return show(key, guide, true); },
    // A step of it is on the screen now.
    can: function (guide) { return !!guide && liveSteps(guide).length > 0; },
    leave: function () { offerSeq++; close(true); },
    isOpen: function () { return !!cur; },
    seen: seen,
    useServer: function (read, mark) {
      server.on = true;
      server.mark = mark || null;
      server.ready = Promise.resolve().then(read).then(function (keys) {
        server.seen = Array.isArray(keys) ? keys.slice() : [];
      }).catch(function () { server.seen = []; });
      return server.ready;
    }
  };
})();
