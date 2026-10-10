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
 * A guide is { name, steps: [{ at, text, title? }], within?, then? };
 * `name`, `title` and `text` are a string or { en, zh } (client pages follow
 * their 中文 switch). `within` names the sheet a guide lives in (Arrange
 * sections, a new WhatsApp message): that sheet does not count as something
 * over the page, and the card stands above it. `then` runs once the guide is
 * finished or skipped (never when the route changes under it): the phone's
 * tab bar guide hands on to the section's. Of a guide's steps, the first
 * three whose control is drawn are shown, so a screen with two states (Health
 * before and after agreeing) holds the steps of both.
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
    return (guide.steps || []).filter(function (s) { return targetOf(s); }).slice(0, 3);
  }
  /* Something else is over the page: a sheet, a menu or popover card, a
     question, the review canvas, the finder, a cover. Drawn, not merely
     present: the console's Access denied cover sits in a hidden shell. */
  var LAYERS = '.sheet, #askSheet, .kmenu, .popcard, .canvas, #pickerBox, .maint-cover, .cover';
  function covered(within) {
    var own = within ? document.querySelector(within) : null;
    var list = document.querySelectorAll(LAYERS);
    for (var i = 0; i < list.length; i++) {
      var el = list[i];
      if (el === card || el.classList.contains('is-off') || el.closest('[hidden]')) continue;
      // The sheet the guide lives in, and what that sheet holds.
      if (own && (el === own || own.contains(el))) continue;
      if (el.getClientRects().length) return true;
    }
    return false;
  }
  // Or the console is still booting.
  function busy(within) { return covered(within) || !!document.querySelector('.console.is-booting'); }
  // A list on the page still drawing its loading rows.
  function loading() {
    return Array.prototype.some.call(document.querySelectorAll('.skel'), function (s) {
      return !s.closest('[hidden]') && s.getClientRects().length > 0;
    });
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

  /* `reveal` brings the step's control into view: a step newly shown. A
     re-lay (a scroll, a press on the page, 中文) never scrolls the page,
     so the guide follows its control and never pulls the page back. */
  function paint(reveal) {
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
    c.classList.toggle('is-insheet', !!cur.guide.within);
    c.hidden = false;
    /* On a phone the card docks at the foot of the screen, so the control is
       brought to the middle, clear of it, never to the edge it covers. */
    if (reveal) {
      var dock = !!(window.matchMedia && window.matchMedia('(max-width: 640px)').matches);
      try { t.scrollIntoView({ block: dock ? 'center' : 'nearest', inline: 'nearest' }); } catch (e) {}
    }
    var r = t.getBoundingClientRect();
    window.ADspaceMenu.pop(t, c, r.left + r.width / 2 < window.innerWidth / 2 ? 'left' : 'right');
  }

  function step(d) {
    if (!cur) return;
    if (cur.i + d >= cur.steps.length) { close(true); return; }
    cur.i = Math.max(0, cur.i + d);
    paint(true);
  }

  /* `why` 'leave': the route changed under it, so nothing follows. */
  function close(done, why) {
    clearTimeout(waitT);
    if (!cur) return;
    unring();
    var key = cur.key, then = why !== 'leave' && cur.guide.then;
    cur = null;
    if (card) card.hidden = true;
    if (done !== false) markSeen(key);
    if (typeof then === 'function') setTimeout(then, 0);
  }

  function show(key, guide, focus) {
    var steps = guide ? liveSteps(guide) : [];
    if (!steps.length) return false;
    close(false);
    cur = { key: key, guide: guide, steps: steps, i: 0, t: null };
    paint(true);
    if (focus && cur && card) { try { card.querySelector('#guideNext').focus({ preventScroll: true }); } catch (e) {} }
    return true;
  }

  /* After a press or a key on the page: something it opened over the page
     (a sheet, a menu, the review canvas) means the person has moved on, and
     the guide ends, met; otherwise the card is laid against its control
     again, or the next step whose control is still drawn. */
  var settleT = 0;
  function settle() {
    clearTimeout(settleT);
    settleT = setTimeout(function () {
      if (!cur) return;
      if (covered(cur.guide.within)) close(true); else paint(false);
    }, 60);
  }
  /* Pressing the control a step points at is doing what it says: the guide
     has done its work. */
  document.addEventListener('click', function (e) {
    if (!cur || (card && card.contains(e.target))) return;
    if (cur.t && cur.t.contains(e.target)) { close(true); return; }
    settle();
  }, true);
  /* Escape ends it, before anything under it hears the key (the window
     hears it before the page's own listeners, a sheet's among them); while
     something else is over the page, that hears it first. */
  window.addEventListener('keydown', function (e) {
    if (!cur || !card || card.hidden) return;
    if (e.key === 'Enter' || e.key === ' ') { if (!card.contains(e.target)) settle(); return; }
    if (e.key !== 'Escape' || covered(cur.guide.within)) return;
    close(true);
    e.stopPropagation();
  }, true);
  // A scroll that carried its control away lays the card against it again.
  if (window.ADspaceMenu) window.ADspaceMenu.onScroll(function () { if (cur) paint(false); });
  // The client pages' 中文 switch re-words a guide on screen.
  try {
    new MutationObserver(function () { if (cur) paint(false); })
      .observe(document.documentElement, { attributes: true, attributeFilter: ['lang'] });
  } catch (e) {}

  window.ADspaceGuide = {
    offer: function (key, guide) {
      if (!key || !guide) return;
      clearTimeout(waitT);
      var mine = ++offerSeq;
      var go = function () {
        if (mine !== offerSeq || cur || seen(key)) return;
        var tries = 0, last = -1, all = Math.min(3, (guide.steps || []).length);
        (function wait() {
          if (mine !== offerSeq || cur || seen(key)) return;
          /* Shown once what it can point at has stopped changing: a list
             still loading draws its rows a moment after its bar, and a step
             counted before them would be left out. */
          var n = busy(guide.within) || loading() ? 0 : liveSteps(guide).length;
          if (n && (n === all || n === last)) { show(key, guide, false); return; }
          last = n;
          if (++tries < 24) waitT = setTimeout(wait, 250);
        })();
      };
      if (server.on) (server.ready || Promise.resolve()).then(go, go);
      else go();
    },
    open: function (key, guide) { return show(key, guide, true); },
    // A step of it is on the screen now.
    can: function (guide) { return !!guide && liveSteps(guide).length > 0; },
    leave: function () { offerSeq++; close(true, 'leave'); },
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
