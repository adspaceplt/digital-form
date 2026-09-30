/* Client review page. Runs at /review/<token> and at /review/?k=<token>. */
(function () {
  var cfg = window.ADSPACE_CONFIG;
  var API = window.ADspaceAPI;
  var MK  = window.ADspaceMockups;
  var feed = null;

  var $ = function (id) { return document.getElementById(id); };

  // ---- Token ---------------------------------------------------------------
  // GitHub Pages serves static files only, so the token travels as ?k=.
  var token = new URLSearchParams(location.search).get('k') || '';

  var passcode = sessionStorage.getItem('adspace_pass_' + token) || '';

  // The mark is the shared chrome's job now.
  if (!API.configured) $('demoStrip').hidden = false;

  /* Nothing to review is not an error, so it gets a cover page rather than the
     look of something having gone wrong. */
  function showState(title, body, wantsPass) {
    $('content').innerHTML = '';
    $('filterbar').hidden = true;
    $('stageStrip').hidden = true;
    $('stageEmpty').hidden = true;
    $('qrBtn').hidden = true;
    $('cover').hidden = false;
    // Nothing but a notice, so the page is white to the edges rather than a
    // white panel sitting on grey.
    document.body.classList.add('is-plain');
    $('coverTitle').textContent = title;
    $('coverBody').textContent = body;
    $('passForm').hidden = !wantsPass;
    document.querySelector('.brand-for').hidden = true;
    if (wantsPass) $('passInput').focus();
  }

  /* No video loads on its own. One that has a poster already shows its frame,
     so it stays untouched until the client presses play. One without a poster
     has to read metadata to show anything, so it is woken when it comes near
     the viewport rather than on page load. Either way a set of a dozen reels
     no longer opens a dozen connections before the first card is readable. */
  var lazyVideos = window.IntersectionObserver
    ? new IntersectionObserver(function (entries, obs) {
        entries.forEach(function (e) {
          if (!e.isIntersecting) return;
          e.target.preload = 'metadata';
          e.target.dataset.lazy = 'woken';
          obs.unobserve(e.target);
        });
      }, { rootMargin: '400px 0px' })
    : null;

  function watchVideos(root) {
    var pending = (root || document).querySelectorAll('video[data-lazy="meta"]');
    if (!lazyVideos) {
      // No observer: fall back to loading metadata rather than showing nothing.
      pending.forEach(function (v) { v.preload = 'metadata'; });
      return;
    }
    pending.forEach(function (v) { lazyVideos.observe(v); });
  }

  /* A phone throws a tab away once it has been in the background long enough
     and rebuilds it from scratch on return, which lands the client back at the
     top of a long set with their filters cleared. Keep the few things that
     make a page theirs, per link, so coming back looks like coming back. */
  var PLACE = 'adspace.review.' + (new URLSearchParams(location.search).get('k') || 'demo');
  var restoring = null;

  function savePlace() {
    if (!feedLoaded) return;
    try {
      sessionStorage.setItem(PLACE, JSON.stringify({
        y: Math.round(window.scrollY),
        fmt: $('formatFilter').value,
        bat: $('batchFilter').value,
        stage: stage,
        safe: $('safeToggle').checked,
        // Only sets the reader opened or closed themselves. The rest follow
        // the automatic rule, which may have changed since they were here.
        open: Array.prototype.filter.call(document.querySelectorAll('.batch'), function (b) {
          return b.dataset.userSet && !b.classList.contains('is-folded');
        }).map(function (b) { return b.dataset.batch; }),
        shut: Array.prototype.filter.call(document.querySelectorAll('.batch'), function (b) {
          return b.dataset.userSet && b.classList.contains('is-folded');
        }).map(function (b) { return b.dataset.batch; })
      }));
    } catch (e) { /* private browsing */ }
  }

  function readPlace() {
    try {
      var p = JSON.parse(sessionStorage.getItem(PLACE) || 'null');
      if (!p) return null;
      p.open = p.open || [];
      p.shut = p.shut || [];
      return p;
    } catch (e) { return null; }
  }

  function hasOption(select, value) {
    return Array.prototype.some.call(select.options, function (o) { return o.value === value; });
  }

  var feedLoaded = false;
  var saveTimer = null;

  /* The stage strip: the posts by where they stood when the page loaded, each
     with its count, the one on show on the sliding surface of the strip.
     Pending first, because what waits on the reader is what they came for. */
  var STAGES = [['pending', 'Pending'], ['changes', 'Changes requested'], ['approved', 'Approved'], ['all', 'All']];
  var stage = null;
  function stageOf(review) {
    return !review ? 'pending' : review.decision === 'approved' ? 'approved' : 'changes';
  }
  function stageWord(s) {
    /* On a phone the longest stage takes its short word, so all four fit the
       column's width without scrolling (the user, 2026-09-30). */
    return s[0] === 'changes'
      ? '<span class="tab-long">' + s[1] + '</span><span class="tab-short">Changes</span>'
      : s[1];
  }
  function paintStages(counts) {
    var strip = $('stageStrip');
    strip.innerHTML = STAGES.map(function (s) {
      return '<button class="tab' + (s[0] === stage ? ' is-on' : '') + '" type="button" role="tab" data-stage="' + s[0] + '"' +
        ' aria-selected="' + (s[0] === stage) + '" tabindex="' + (s[0] === stage ? 0 : -1) + '">' +
        stageWord(s) + ' <span class="tab-n">' + counts[s[0]] + '</span></button>';
    }).join('');
  }
  function pickStage(to) {
    stage = to;
    Array.prototype.forEach.call(document.querySelectorAll('#stageStrip .tab'), function (b) {
      var on = b.getAttribute('data-stage') === to;
      b.classList.toggle('is-on', on);
      b.setAttribute('aria-selected', String(on));
      b.tabIndex = on ? 0 : -1;
    });
    applyFilters();
  }
  $('stageStrip').addEventListener('click', function (e) {
    var b = e.target.closest && e.target.closest('.tab');
    if (b) pickStage(b.getAttribute('data-stage'));
  });
  /* A tab list: the arrows move along it, Home and End to its ends. */
  $('stageStrip').addEventListener('keydown', function (e) {
    var tabs = Array.prototype.slice.call(this.querySelectorAll('.tab'));
    var i = tabs.indexOf(document.activeElement);
    if (i < 0) return;
    var to = e.key === 'ArrowRight' ? i + 1 : e.key === 'ArrowLeft' ? i - 1 : e.key === 'Home' ? 0 : e.key === 'End' ? tabs.length - 1 : null;
    if (to === null) return;
    e.preventDefault();
    to = (to + tabs.length) % tabs.length;
    tabs[to].focus();
    pickStage(tabs[to].getAttribute('data-stage'));
  });
  function queuePlace() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(savePlace, 200);
  }
  window.addEventListener('scroll', queuePlace, { passive: true });
  // A phone often gets no unload event, but it always gets this one.
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'hidden') savePlace();
  });
  if ('scrollRestoration' in history) history.scrollRestoration = 'manual';

  /* Cards in a row are stretched to a common height so their approve rows line
     up. That is right until someone expands a caption, at which point every
     card beside it grew too. A row holding anything expanded stops stretching,
     so only the card that was opened gets taller. */
  function syncOpenRows() {
    document.querySelectorAll('#content .grid').forEach(function (grid) {
      grid.classList.toggle('has-open',
        Boolean(grid.querySelector('.copyblock.is-open, .mk-clamp.is-open')));
    });
  }

  /* The caption toggle inside a mockup is built by the mockup itself, so catch
     it on the way up rather than reaching in to rebind it. */
  document.getElementById('content').addEventListener('click', function (e) {
    if (e.target.closest('.mk-morebtn')) syncOpenRows();
  });

  /* Only worth offering where a platform draws its own UI over the video, so
     the switch stays out of the way for a client reviewing static posts. */
  function paintSafeSwitch() {
    var any = document.querySelector('#content .mk-safe');
    $('safeWrap').hidden = !any;
  }

  $('safeToggle').addEventListener('change', function (e) {
    document.body.classList.toggle('is-safe', e.target.checked);
    savePlace();
  });

  function fmtDate(iso) {
    if (!iso) return '';
    return new Date(iso).toLocaleDateString('en-GB',
      { day: 'numeric', month: 'short', year: 'numeric' }).replace(/\bSep\b/, 'Sept');
  }

  /* A hidden element reports zero height, so a card inside a folded set or one
     filtered out would look like it never overflows and lose its toggle. Only
     decide once it can actually be measured. */
  function measureCopy(copy) {
    var more = copy.querySelector('.copy-more');
    if (!more) return;
    var texts = copy.querySelectorAll('.copytext');
    if (!texts.length || !texts[0].clientHeight) return;
    if (copy.classList.contains('is-open')) { more.hidden = false; return; }
    more.hidden = !Array.prototype.some.call(texts, function (n) {
      return n.scrollHeight > n.clientHeight + 2;
    });
  }

  /* Anything that reveals cards has to re-run those measurements. */
  function remeasure() {
    document.querySelectorAll('.copyblock').forEach(measureCopy);
    if (MK.remeasure) MK.remeasure(document);
  }

  /* The tab, and the tags a link preview reads. A crawler will not get this
     far, since it runs no scripts, but anything that does execute the page
     sees the client's name rather than the generic line in the file. */
  function setPageTitle(text) {
    document.title = text;
    ['meta[property="og:title"]', 'meta[name="twitter:title"]'].forEach(function (sel) {
      var tag = document.head.querySelector(sel);
      if (tag) tag.setAttribute('content', text);
    });
  }

  function escapeHtml(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  // ---- Rendering -----------------------------------------------------------
  function postCard(post, clientMeta) {
    var mkCfg = {
      clientName:   clientMeta.name,
      clientLogo:   clientMeta.logo_url,
      handles:      clientMeta.handles || {},
      clientHandle: post.handle || clientMeta.name.toLowerCase().replace(/[^a-z0-9]+/g, '')
    };

    var card = document.createElement('article');
    card.className = 'card';
    card.dataset.format = MK.key(post);
    /* Where the post stood when the page loaded. A decision made now repaints
       the card, but it keeps its place in the stage it was shown under until
       the next load, so a card never vanishes from under the hand that just
       approved it (the user, 2026-09-30). */
    card.dataset.stage = stageOf(post.review);

    var head = document.createElement('div');
    head.className = 'card-head';
    head.innerHTML =
      '<span class="card-title">' + MK.label(post) + '</span>' +
      '<span class="card-dims">' + MK.dimensions(post) + '</span>' +
      '<span class="badge"></span>';
    card.appendChild(head);

    var stage = document.createElement('div');
    stage.className = 'card-stage';
    stage.appendChild(MK.render(post, mkCfg));
    // Vertical formats fill the card edge to edge, so 9:16 is shown as large as
    // the column allows rather than inset inside padding.
    if (stage.querySelector('.mk-phone')) card.classList.add('is-vertical');
    if (stage.querySelector('.mk-coverwrap')) card.classList.add('is-cover');
    card.appendChild(stage);

    // The mockup truncates like the real feed. This shows the caption in full.
    if (post.caption || post.caption_zh || post.title) {
      var copy = document.createElement('div');
      copy.className = 'copyblock';
      var html = '';
      // The heading names the section once, so the caption below it needs no
      // label of its own. A title and a Chinese version are different things
      // and keep theirs.
      if (post.title)      html += '<h5>Title</h5><div class="copytext">' + escapeHtml(post.title) + '</div>';
      if (post.caption)    html += '<div class="copytext" data-cap="caption">' + escapeHtml(post.caption) + '</div>';
      if (post.caption_zh) html += '<h5>中文文案</h5><div class="copytext" data-cap="caption_zh">' + escapeHtml(post.caption_zh) + '</div>';
      // Copy text sits in the heading so it stays where the reader left it.
      // Below the words it moved every time the block was expanded, and sat
      // right beside Show full copy, which is a different kind of action.
      copy.innerHTML =
        '<div class="copyhead">' +
          '<h5>Copywriting</h5>' +
          /* The pen beside the heading edits the caption where it is read;
             the edit goes with Request changes as a suggestion the team
             accepts (the user, 2026-09-30: "why not just build a pen beside
             the copywriting to edit directly"). */
          ((post.caption || post.caption_zh)
            ? '<button class="copy-pen" type="button" aria-label="Edit caption"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 20h4L19.5 8.5a2.1 2.1 0 0 0-3-3L5 17z"/><path d="M14.5 6.5l3 3"/></svg></button>' : '') +
          /* The portal's small tonal button with the copy mark: it was
             the one outlined button left, and read "a little huge" at a
             full control's height (the user, 2026-09-30). */
          '<button class="btn btn-sm copy-btn" type="button">' +
            '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
            '<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15H4.5A1.5 1.5 0 0 1 3 13.5v-9A1.5 1.5 0 0 1 4.5 3h9A1.5 1.5 0 0 1 15 4.5V5"/></svg>' +
            '<span>Copy text</span></button>' +
        '</div>' +
        html +
        '<button class="copy-more" type="button" hidden>Show full caption</button>';

      // Long captions are clamped so cards in a row finish at the same height.
      var more = copy.querySelector('.copy-more');
      more.addEventListener('click', function () {
        var open = copy.classList.toggle('is-open');
        more.textContent = open ? 'Show less' : 'Show full caption';
        measureCopy(copy);
        syncOpenRows();
      });
      requestAnimationFrame(function () { measureCopy(copy); });
      copy.querySelector('.copy-btn').addEventListener('click', function () {
        window.ADspaceCopy.to(this, [post.title, post.caption, post.caption_zh]
          .filter(Boolean).join('\n\n'));
      });
      card.appendChild(copy);

      /* Editing: each caption becomes its own field in place, the block
         opens in full, and Request changes opens under it for a note and
         the name. Cancel puts the words back. */
      copy._start = function () {
        if (copy.classList.contains('is-editing')) return;
        copy.classList.add('is-editing', 'is-open');
        Array.prototype.forEach.call(copy.querySelectorAll('[data-cap]'), function (t) {
          var f = t.getAttribute('data-cap');
          var area = document.createElement('textarea');
          area.className = 'textarea copyfield';
          area.setAttribute('data-f', f);
          area.setAttribute('aria-label', f === 'caption_zh' ? '中文文案' : 'Caption');
          area.value = post[f] || '';
          t.hidden = true;
          t.parentNode.insertBefore(area, t.nextSibling);
        });
        var pen = copy.querySelector('.copy-pen');
        if (pen) pen.hidden = true;
        more.hidden = true;
        var first = copy.querySelector('.copyfield');
        if (first) first.focus();
        syncOpenRows();
      };
      copy._stop = function () {
        if (!copy.classList.contains('is-editing')) return;
        copy.classList.remove('is-editing', 'is-open');
        Array.prototype.forEach.call(copy.querySelectorAll('.copyfield'), function (a) { a.remove(); });
        Array.prototype.forEach.call(copy.querySelectorAll('[data-cap]'), function (t) { t.hidden = false; });
        var pen = copy.querySelector('.copy-pen');
        if (pen) pen.hidden = !!(post.review && post.review.decision === 'approved');
        measureCopy(copy);
        syncOpenRows();
      };
      /* An approved post is settled, so its caption offers no pen. */
      var pen0 = copy.querySelector('.copy-pen');
      if (pen0 && post.review && post.review.decision === 'approved') pen0.hidden = true;
    }

    /* A revised post says what it answers: the client's own request on the
       round before. The earlier file and copy stay with the team; the client
       sees the revision alone (the user, 2026-09-30). */
    if (post.round > 1 && post.asked) {
      var rev = document.createElement('div');
      rev.className = 'reask is-revision';
      var askedWhen = fmtDate(post.asked.created_at);
      rev.innerHTML = '<b>Revision ' + post.round + '</b>' +
        (post.asked.note ? '<span>You asked: ' + escapeHtml(post.asked.note) + '</span>' : '') +
        (post.asked.suggested ? '<span>Your caption edit is applied.</span>' : '') +
        '<small>' + (post.asked.reviewer ? escapeHtml(post.asked.reviewer) + ' · ' : '') + askedWhen + '</small>';
      card.appendChild(rev);
    }

    // Something changed since they last approved, so say what before asking again.
    if (post.reset_note) {
      var again = document.createElement('div');
      again.className = 'reask';
      again.innerHTML = '<b>Updated since you approved this</b>' +
        '<span>' + escapeHtml(post.reset_note) + '</span>';
      card.appendChild(again);
    }

    var decision = approvalBlock(post, head.querySelector('.badge'), copy || null);
    card.appendChild(decision);
    var penBtn = copy && copy.querySelector('.copy-pen');
    if (penBtn) penBtn.addEventListener('click', function () {
      copy._start();
      decision._openChanges(true);
    });
    paintDecision(post.review, head.querySelector('.badge'), card.querySelector('.approve'));
    /* The gallery is how a client sees the month; the canvas is how they
       decide on one post. Opening it is the mockup itself, which is the thing
       they are already looking at, plus a named control for a keyboard. */
    stage.setAttribute('role', 'button');
    stage.setAttribute('tabindex', '0');
    stage.setAttribute('aria-label', 'Review ' + MK.label(post));
    stage.addEventListener('click', function (e) {
      /* A control inside the mockup is the mockup's, not the canvas's: its
         play button, and the video's own bar once it plays. */
      if (e.target.closest('button, a, input, textarea, select, video')) return;
      openCanvas(card);
    });
    stage.addEventListener('keydown', function (e) {
      /* Enter on the play button (or the caption's more) is that control's. */
      if (e.target !== stage) return;
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openCanvas(card); }
    });
    return card;
  }

  /* ---- The Review Canvas -----------------------------------------------
     One post at the size it deserves, with everything the decision rests on
     beside it: what it is, the copy in full, what was said last time, where
     it stands and the one place to decide. The blocks are moved out of the
     card and put back on close, so there is one approve control in the page
     and it cannot drift from the one in the gallery. */
  var canvasFor = null, canvasHome = null, canvasOpener = null;

  /* Moving a video element stops it, so one that was playing when its post
     moves in or out of the canvas carries on where it was. */
  function playingIn(root) {
    return Array.prototype.filter.call(root ? root.querySelectorAll('video') : [], function (v) {
      return !v.paused && !v.ended;
    });
  }
  function resume(videos) {
    videos.forEach(function (v) { var p = v.play(); if (p && p.catch) p.catch(function () {}); });
  }

  function galleryCards() {
    return Array.prototype.slice.call(document.querySelectorAll('#content .card'));
  }

  function openCanvas(card) {
    if (canvasFor === card) return;
    if (canvasFor) returnCanvas();
    canvasOpener = canvasOpener || document.activeElement;
    canvasFor = card;
    /* Where each block came from, so it goes back in the order it left. */
    canvasHome = [];
    var head = card.querySelector('.card-head');
    $('canvasTitle').textContent = head.querySelector('.card-title').textContent;
    $('canvasDims').textContent = head.querySelector('.card-dims').textContent;

    var cards = galleryCards();
    var at = cards.indexOf(card);
    $('canvasPos').textContent = (at + 1) + ' of ' + cards.length;
    $('canvasPrev').disabled = at <= 0;
    $('canvasNext').disabled = at >= cards.length - 1;

    var stage = $('canvasStage'), rail = $('canvasRail');
    stage.innerHTML = ''; rail.innerHTML = '';
    /* The badge travels with the rail, because where a post stands is part of
       what the decision is being made against. */
    var badge = head.querySelector('.badge');
    var take = function (el, into) {
      if (!el) return;
      canvasHome.push([el, el.parentNode, el.nextSibling]);
      into.appendChild(el);
    };
    var playing = playingIn(card);
    take(card.querySelector('.card-stage'), stage);
    take(badge, rail);
    take(card.querySelector('.copyblock'), rail);
    take(card.querySelector('.reask'), rail);
    take(card.querySelector('.approve'), rail);
    resume(playing);

    $('canvas').hidden = false;
    document.body.classList.add('is-canvas');
    /* Every post opens at its top: on a phone the canvas is one scroll, and
       the next post must not open where the last one's decision was. */
    stage.scrollTop = 0; rail.scrollTop = 0;
    if (stage.parentNode) stage.parentNode.scrollTop = 0;
    $('canvasClose').focus();
  }

  /* Put every block back where it came from. In reverse, because taking the
     second block out of a card invalidates the sibling the first one recorded;
     and defensively, because a node that is no longer a child of the parent it
     was next to is appended rather than thrown at insertBefore. */
  /* `keep`: on Close, a video playing in the canvas carries on in its card;
     stepping to the next post leaves it stopped. */
  function returnCanvas(keep) {
    var playing = keep ? playingIn($('canvasStage')) : [];
    (canvasHome || []).slice().reverse().forEach(function (h) {
      var el = h[0], parent = h[1], before = h[2];
      if (before && before.parentNode === parent) parent.insertBefore(el, before);
      else parent.appendChild(el);
    });
    resume(playing);
    canvasHome = null;
    canvasFor = null;
  }

  function shutCanvas() {
    if (!canvasFor) return;
    returnCanvas(true);
    $('canvas').hidden = true;
    document.body.classList.remove('is-canvas');
    if (canvasOpener && document.body.contains(canvasOpener)) canvasOpener.focus();
    canvasOpener = null;
  }

  function stepCanvas(by) {
    if (!canvasFor) return;
    var cards = galleryCards();
    var at = cards.indexOf(canvasFor) + by;
    if (at < 0 || at >= cards.length) return;
    var next = cards[at];
    returnCanvas();
    openCanvas(next);
  }

  $('canvasClose').addEventListener('click', shutCanvas);
  $('canvasPrev').addEventListener('click', function () { stepCanvas(-1); });
  $('canvasNext').addEventListener('click', function () { stepCanvas(1); });
  $('canvas').addEventListener('click', function (e) { if (e.target === this) shutCanvas(); });
  document.addEventListener('keydown', function (e) {
    if ($('canvas').hidden) return;
    if (e.key === 'Escape') { shutCanvas(); return; }
    /* Arrows move through the set, unless somebody is typing their name into
       the decision beside it. */
    if (e.target.closest('input, textarea, select')) return;
    if (e.key === 'ArrowLeft') stepCanvas(-1);
    if (e.key === 'ArrowRight') stepCanvas(1);
  });

  function approvalBlock(post, badge, copyBlock) {
    var wrap = document.createElement('div');
    wrap.className = 'approve';
    wrap.innerHTML =
      '<div class="approve-row">' +
        '<button class="btn btn-approve" type="button" aria-pressed="false">Approve</button>' +
        '<button class="btn btn-changes" type="button" aria-pressed="false">Request changes</button>' +
      '</div>' +
      '<div class="changebox">' +
        '<textarea class="textarea" data-f="note" aria-label="Changes required" placeholder="Describe the changes required."></textarea>' +
        /* Only where we do not already hold the name: a client who has
           approved a post before is not asked for it a second time. */
        (window.ADspaceDecide.known() ? '' :
          '<input class="input changebox-who" type="text" autocomplete="name"' +
            ' aria-label="Your name" placeholder="Name">') +
        '<div class="changebox-actions">' +
          '<button class="btn btn-primary" type="button" data-act="send">Send request</button>' +
          '<button class="btn" type="button" data-act="cancel">Cancel</button>' +
        '</div>' +
      '</div>' +
      '<div class="approve-state"></div>';

    var box      = wrap.querySelector('.changebox');
    var textarea = wrap.querySelector('[data-f="note"]');
    /* What the client changed in the caption (edited in place under the
       pen), or null where they changed nothing: an untouched field is not a
       suggestion. */
    function edited(f, was) {
      var el = copyBlock ? copyBlock.querySelector('.copyfield[data-f="' + f + '"]') : null;
      if (!el) return null;
      return el.value !== (was || '') ? el.value : null;
    }
    var who      = wrap.querySelector('.changebox-who');
    var state    = wrap.querySelector('.approve-state');
    function say(text) { state.textContent = text || ''; }

    /* The name is asked inside Approve rather than in a browser dialog: see
       js/decide.js. A name already given opens nothing at all. */
    var approveBtn = wrap.querySelector('.btn-approve');
    var asker = window.ADspaceDecide.nameBox(approveBtn, {
      label: 'Your name', placeholder: 'Name',
      needed: 'A name is required to record this decision.'
    }, say);

    approveBtn.addEventListener('click', function () {
      box.classList.remove('is-open');
      asker.need(function (name) { send(post, 'approved', null, wrap, badge, name); });
    });
    /* Opens the request; from the pen the caption field keeps the caret. */
    wrap._openChanges = function (fromPen) {
      asker.close();
      box.classList.add('is-open');
      if (!fromPen) textarea.focus();
    };
    wrap.querySelector('.btn-changes').addEventListener('click', function () { wrap._openChanges(false); });
    box.querySelector('[data-act="cancel"]').addEventListener('click', function () {
      box.classList.remove('is-open');
      if (copyBlock) copyBlock._stop();
    });
    box.querySelector('[data-act="send"]').addEventListener('click', function () {
      var note = textarea.value.trim();
      var cap = edited('caption', post.caption), capZh = edited('caption_zh', post.caption_zh);
      if (!note && cap === null && capZh === null) {
        say('Describe the changes, or edit the caption.');
        textarea.focus();
        return;
      }
      /* The note box is already open, so the name it may still need is a
         field inside it rather than one growing out of the row behind it. */
      var name = window.ADspaceDecide.known();
      if (!name) {
        name = (who.value || '').trim();
        if (!name) { say('A name is required to record this decision.'); who.focus(); return; }
        window.ADspaceDecide.keep(name);
      }
      box.classList.remove('is-open');
      if (copyBlock) copyBlock._stop();
      send(post, 'changes', note, wrap, badge, name, { caption: cap, caption_zh: capZh });
    });
    return wrap;
  }

  /* An approval with nobody's name on it is worth nothing, so the name is a
     hard stop — but it is settled before this runs, on the page rather than
     in a browser dialog, and arrives here as an argument. */
  function send(post, decision, note, wrap, badge, reviewer, copy) {
    var buttons = wrap.querySelectorAll('.btn');
    Array.prototype.forEach.call(buttons, function (b) { b.disabled = true; });

    API.submitReview({
      token: token, postId: post.id, decision: decision,
      note: note, reviewer: reviewer, passcode: passcode,
      caption: copy && copy.caption, captionZh: copy && copy.caption_zh
    }).then(function (res) {
      Array.prototype.forEach.call(buttons, function (b) { b.disabled = false; });
      if (res && res.error) {
        wrap.querySelector('.approve-state').textContent =
          res.error === 'note_required'
            ? 'Please describe the required changes.'
            : 'Unable to save. Please refresh and try again.';
        return;
      }
      post.review = {
        decision: decision, note: note, reviewer: reviewer,
        created_at: new Date().toISOString(),
        suggested: !!(copy && (copy.caption !== null && copy.caption !== undefined ||
                               copy.caption_zh !== null && copy.caption_zh !== undefined))
      };
      paintDecision(post.review, badge, wrap);
    }).catch(function () {
      Array.prototype.forEach.call(buttons, function (b) { b.disabled = false; });
      wrap.querySelector('.approve-state').textContent = 'Unable to save. Please check your connection.';
    });
  }

  /* Takes the decision block itself rather than the card it usually sits in:
     while the Review Canvas is open that block is in the canvas rail, and
     `card.querySelector('.approve')` came back null there — which threw inside
     a .then and was reported to the client as "Unable to save. Please check
     your connection." over a save that had gone through. */
  function paintDecision(review, badge, wrap) {
    if (wrap && wrap.classList && !wrap.classList.contains('approve')) {
      wrap = wrap.querySelector('.approve');
    }
    if (!wrap) return;
    var state = wrap.querySelector('.approve-state');
    var approveBtn = wrap.querySelector('.btn-approve');
    var changesBtn = wrap.querySelector('.btn-changes');

    badge.className = 'badge status status-pending';
    badge.innerHTML = '<span></span>';
    var badgeWord = badge.querySelector('span');
    approveBtn.setAttribute('aria-pressed', 'false');
    changesBtn.setAttribute('aria-pressed', 'false');
    wrap.querySelector('.approve-row').classList.remove('is-settled');
    changesBtn.hidden = false;
    approveBtn.hidden = false;
    approveBtn.disabled = false;
    approveBtn.textContent = 'Approve';
    var old = wrap.querySelector('.approve-note');
    if (old) old.remove();

    if (!review) { badgeWord.textContent = 'Pending'; state.textContent = ''; return; }

    var who  = review.reviewer ? ' by <b>' + escapeHtml(review.reviewer) + '</b>' : '';
    var when = new Date(review.created_at).toLocaleString('en-GB',
      { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }).replace(/\bSep\b/, 'Sept');

    if (review.decision === 'approved') {
      badgeWord.textContent = 'Approved';
      badge.className = 'badge status status-approved is-ok';
      approveBtn.setAttribute('aria-pressed', 'true');
      // Approved is the end of the road for this post. Hide the other option and
      // let the button fill the row so the state is unmistakable.
      wrap.querySelector('.approve-row').classList.add('is-settled');
      changesBtn.hidden = true;
      approveBtn.textContent = 'Approved';
      approveBtn.disabled = true;
      state.innerHTML = 'Approved' + who + ' on ' + when + '.';
      autoFold(wrap);
    } else {
      badgeWord.textContent = 'Changes requested';
      badge.className = 'badge status status-changes is-changes';
      changesBtn.setAttribute('aria-pressed', 'true');
      state.innerHTML = 'Changes requested' + who + ' on ' + when + '.';
      if (review.note || review.suggested) {
        var n = document.createElement('div');
        n.className = 'approve-note';
        n.textContent = [review.note, review.suggested ? 'Caption edit suggested.' : ''].filter(Boolean).join('\n');
        wrap.appendChild(n);
      }
    }
  }

  // ---- Build ---------------------------------------------------------------
  function build() {
    document.body.classList.remove('is-plain');
    var root = $('content');
    root.innerHTML = '';
    var formats = {};
    restoring = readPlace();

    feed.batches.forEach(function (batch) {
      var section = document.createElement('section');
      section.className = 'batch';
      section.dataset.batch = batch.id;

      var head = document.createElement('button');
      head.type = 'button';
      head.className = 'batch-head';
      head.innerHTML =
        '<span class="fold-caret" aria-hidden="true">&#9662;</span>' +
        '<span class="batch-title">' + escapeHtml(batch.title) + '</span>' +
        '<span class="batch-date">' + fmtDate(batch.created_at) + ' &middot; ' +
        batch.posts.length + ' post' + (batch.posts.length === 1 ? '' : 's') + '</span>' +
        '<span class="batch-progress"></span>';
      section.appendChild(head);

      var body = document.createElement('div');
      body.className = 'batch-body';

      if (batch.note) {
        var note = document.createElement('div');
        note.className = 'batch-note';
        note.textContent = batch.note;
        body.appendChild(note);
      }

      var grid = document.createElement('div');
      grid.className = 'grid';
      batch.posts.forEach(function (post) {
        formats[MK.key(post)] = MK.label(post);
        grid.appendChild(postCard(post, feed.client));
      });
      body.appendChild(grid);
      section.appendChild(body);
      root.appendChild(section);

      head.addEventListener('click', function () {
        // A deliberate click always wins over the automatic folding.
        section.dataset.userSet = '1';
        section.classList.toggle('is-folded');
        head.setAttribute('aria-expanded', section.classList.contains('is-folded') ? 'false' : 'true');
        if (!section.classList.contains('is-folded')) requestAnimationFrame(remeasure);
        savePlace();
      });

      // A set everyone has already signed off starts folded, so the page opens
      // on what still needs attention.
      paintFold(section, true);

      // Unless the reader had already decided otherwise before they left.
      if (restoring) {
        var was = restoring.open.indexOf(batch.id) !== -1 ? 'open'
                : restoring.shut.indexOf(batch.id) !== -1 ? 'shut' : null;
        if (was) {
          section.dataset.userSet = '1';
          section.classList.toggle('is-folded', was === 'shut');
          head.setAttribute('aria-expanded', was === 'shut' ? 'false' : 'true');
        }
      }
    });

    /* Counted once, at load: a decision made now does not move its card. */
    var counts = { pending: 0, changes: 0, approved: 0, all: 0 };
    feed.batches.forEach(function (b) {
      b.posts.forEach(function (p) { counts[stageOf(p.review)]++; counts.all++; });
    });
    var kept = restoring && restoring.stage;
    stage = kept && (kept === 'all' || counts[kept]) ? kept : counts.pending ? 'pending' : 'all';
    paintStages(counts);

    var ff = $('formatFilter');
    Object.keys(formats).sort().forEach(function (k) {
      var opt = document.createElement('option');
      opt.value = k; opt.textContent = formats[k];
      ff.appendChild(opt);
    });

    var bf = $('batchFilter');
    feed.batches.forEach(function (b) {
      var opt = document.createElement('option');
      opt.value = b.id; opt.textContent = b.title;
      bf.appendChild(opt);
    });

    ff.addEventListener('change', applyFilters);
    bf.addEventListener('change', applyFilters);
    $('filterbar').hidden = false;
    $('stageStrip').hidden = false;
    $('qrBtn').hidden = false;
    paintSafeSwitch();
    watchVideos(document);

    if (restoring) {
      // A filter naming a format or a set that has since gone is dropped
      // rather than leaving the reader looking at nothing.
      if (hasOption(ff, restoring.fmt)) ff.value = restoring.fmt;
      if (hasOption(bf, restoring.bat)) bf.value = restoring.bat;
      if (restoring.safe) {
        $('safeToggle').checked = true;
        document.body.classList.add('is-safe');
      }
    }
    applyFilters();

    feedLoaded = true;
    if (restoring && restoring.y) {
      var y = restoring.y;
      requestAnimationFrame(function () {
        window.scrollTo(0, y);
        // Again once the media has sized itself, which is what moves things.
        setTimeout(function () { window.scrollTo(0, y); }, 300);
      });
    }
    restoring = null;
  }

  /* Counts approvals in a set, updates its header, and folds it once nothing is
     left to do. initial=true allows folding a set that arrived fully approved. */
  function paintFold(section, initial) {
    var cards = section.querySelectorAll('.card');
    var total = cards.length;
    var done = section.querySelectorAll('.badge.is-ok').length;
    var changes = section.querySelectorAll('.badge.is-changes').length;

    var label = done + ' of ' + total + ' approved';
    if (changes) label += ' · ' + changes + ' with changes';
    section.querySelector('.batch-progress').textContent = label;
    section.classList.toggle('is-done', done === total && total > 0);

    var settled = total > 0 && done === total;
    if (settled && (initial || !section.dataset.userSet)) {
      section.classList.add('is-folded');
    }
    var head = section.querySelector('.batch-head');
    head.setAttribute('aria-expanded', section.classList.contains('is-folded') ? 'false' : 'true');
  }

  /* The set folds once every post in it is settled. Reached from the decision
     block, which is in the canvas rail while the canvas is open and therefore
     inside no `.batch` at all: there is nothing to fold until it goes home. */
  function autoFold(from) {
    var section = from && from.closest ? from.closest('.batch') : null;
    if (section) paintFold(section, false);
  }

  function applyFilters() {
    var fmt = $('formatFilter').value;
    var bat = $('batchFilter').value;
    var shown = 0;

    document.querySelectorAll('.batch').forEach(function (section) {
      var batchOk = bat === 'all' || section.dataset.batch === bat;
      var visibleHere = 0;
      section.querySelectorAll('.card').forEach(function (card) {
        var ok = batchOk && (fmt === 'all' || card.dataset.format === fmt) &&
          (!stage || stage === 'all' || card.dataset.stage === stage);
        card.hidden = !ok;
        if (ok) visibleHere++;
      });
      section.hidden = visibleHere === 0;
      if (!section.hidden) paintFold(section, false);
      shown += visibleHere;
    });

    $('countLabel').textContent = shown + ' post' + (shown === 1 ? '' : 's') + ' shown';
    $('stageEmpty').hidden = shown > 0;
    requestAnimationFrame(remeasure);
    savePlace();
  }

  // ---- Chrome --------------------------------------------------------------
  $('qrBtn').addEventListener('click', function () {
    var target = $('qrTarget');
    if (!target.hasChildNodes() && window.QRCode) {
      new QRCode(target, { text: location.href, width: 190, height: 190,
        colorDark: '#1a1a1a', colorLight: '#ffffff' });
    }
    $('qrModal').classList.add('is-open');
  });
  $('qrClose').addEventListener('click', function () { $('qrModal').classList.remove('is-open'); });
  $('qrModal').addEventListener('click', function (e) {
    if (e.target === this) this.classList.remove('is-open');
  });

  /* A video is cropped to its placement inside the frame. Once it goes full
     screen that crop is wrong, so drop it for as long as it is expanded. */
  ['fullscreenchange', 'webkitfullscreenchange'].forEach(function (ev) {
    document.addEventListener(ev, function () {
      var active = document.fullscreenElement || document.webkitFullscreenElement || null;
      document.querySelectorAll('.mk-media video').forEach(function (v) {
        v.classList.toggle('is-fullscreen', v === active);
      });
    });
  });

  $('passForm').addEventListener('submit', function (e) {
    e.preventDefault();
    passcode = $('passInput').value.trim();
    sessionStorage.setItem('adspace_pass_' + token, passcode);
    load();
  });

  // ---- Load ----------------------------------------------------------------
  /* This page is English only (no language action in its chrome), so it takes
     the English half of the shared words. The covers say the same thing here
     as on /creators/ and /client/ because they are the same words, not
     because three files were kept in step by hand. */
  var W = window.ADspaceWords.en;

  function load() {
    if (!token && API.configured) {
      showState(W.notFound, W.notFoundText);
      return;
    }
    API.getReviewFeed(token, passcode).then(function (data) {
      if (!data || data.error === 'not_found') {
        showState(W.notFound, W.notFoundText);
        return;
      }
      if (data.error === 'passcode_required') {
        showState(W.passTitle, W.passText, true);
        return;
      }
      feed = data;
      $('cover').hidden = true;
      document.querySelector('.brand-for').hidden = false;
      $('clientName').textContent = feed.client.name;
      // The name goes in front, here and on the tags a crawler would have read
      // had it run this. Written in one place so the two cannot drift apart.
      setPageTitle(feed.client.name + ' Content Review Portal by ADspace');
      if (!feed.batches.length) {
        showState(W.nothing, W.nothingText);
        return;
      }
      build();
    }).catch(function (err) {
      console.error(err);
      showState(W.failTitle, W.failText);
    });
  }

  load();
})();
