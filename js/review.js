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
      { day: 'numeric', month: 'short', year: 'numeric' });
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
      if (post.caption)    html += '<div class="copytext">' + escapeHtml(post.caption) + '</div>';
      if (post.caption_zh) html += '<h5>中文文案</h5><div class="copytext">' + escapeHtml(post.caption_zh) + '</div>';
      // Copy text sits in the heading so it stays where the reader left it.
      // Below the words it moved every time the block was expanded, and sat
      // right beside Show full copy, which is a different kind of action.
      copy.innerHTML =
        '<div class="copyhead">' +
          '<h5>Copywriting</h5>' +
          '<button class="copy-btn" type="button">Copy text</button>' +
        '</div>' +
        html +
        '<button class="copy-more" type="button" hidden>Show full copy</button>';

      // Long captions are clamped so cards in a row finish at the same height.
      var more = copy.querySelector('.copy-more');
      more.addEventListener('click', function () {
        var open = copy.classList.toggle('is-open');
        more.textContent = open ? 'Show less' : 'Show full copy';
        measureCopy(copy);
        syncOpenRows();
      });
      requestAnimationFrame(function () { measureCopy(copy); });
      copy.querySelector('.copy-btn').addEventListener('click', function (e) {
        navigator.clipboard.writeText([post.title, post.caption, post.caption_zh]
          .filter(Boolean).join('\n\n')).then(function () {
            e.target.textContent = 'Copied';
            setTimeout(function () { e.target.textContent = 'Copy text'; }, 1600);
          });
      });
      card.appendChild(copy);
    }

    // Something changed since they last approved, so say what before asking again.
    if (post.reset_note) {
      var again = document.createElement('div');
      again.className = 'reask';
      again.innerHTML = '<b>Updated since you approved this</b>' +
        '<span>' + escapeHtml(post.reset_note) + '</span>';
      card.appendChild(again);
    }

    card.appendChild(approvalBlock(post, head.querySelector('.badge')));
    paintDecision(post.review, head.querySelector('.badge'), card);
    return card;
  }

  function approvalBlock(post, badge) {
    var wrap = document.createElement('div');
    wrap.className = 'approve';
    wrap.innerHTML =
      '<div class="approve-row">' +
        '<button class="btn btn-approve" type="button" aria-pressed="false">Approve</button>' +
        '<button class="btn btn-changes" type="button" aria-pressed="false">Request changes</button>' +
      '</div>' +
      '<div class="changebox">' +
        '<textarea class="textarea" placeholder="Describe the changes required."></textarea>' +
        '<div class="changebox-actions">' +
          '<button class="btn" type="button" data-act="cancel">Cancel</button>' +
          '<button class="btn btn-primary" type="button" data-act="send">Send request</button>' +
        '</div>' +
      '</div>' +
      '<div class="approve-state"></div>';

    var box      = wrap.querySelector('.changebox');
    var textarea = wrap.querySelector('.textarea');

    wrap.querySelector('.btn-approve').addEventListener('click', function () {
      box.classList.remove('is-open');
      send(post, 'approved', null, wrap, badge);
    });
    wrap.querySelector('.btn-changes').addEventListener('click', function () {
      box.classList.add('is-open');
      textarea.focus();
    });
    box.querySelector('[data-act="cancel"]').addEventListener('click', function () {
      box.classList.remove('is-open');
    });
    box.querySelector('[data-act="send"]').addEventListener('click', function () {
      var note = textarea.value.trim();
      if (!note) { textarea.focus(); return; }
      box.classList.remove('is-open');
      send(post, 'changes', note, wrap, badge);
    });
    return wrap;
  }

  function send(post, decision, note, wrap, badge) {
    var buttons = wrap.querySelectorAll('.btn');
    Array.prototype.forEach.call(buttons, function (b) { b.disabled = true; });

    // An approval with nobody's name on it is worth nothing, so this is a hard
    // stop rather than a prompt that can be dismissed past.
    var reviewer = localStorage.getItem('adspace_reviewer') || '';
    if (!reviewer) {
      reviewer = (window.prompt('Please enter your name to record this decision:') || '').trim();
      if (!reviewer) {
        Array.prototype.forEach.call(buttons, function (b) { b.disabled = false; });
        wrap.querySelector('.approve-state').textContent =
          'A name is required to record this decision.';
        return;
      }
      localStorage.setItem('adspace_reviewer', reviewer);
    }

    API.submitReview({
      token: token, postId: post.id, decision: decision,
      note: note, reviewer: reviewer, passcode: passcode
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
        created_at: new Date().toISOString()
      };
      paintDecision(post.review, badge, wrap.closest('.card'));
    }).catch(function () {
      Array.prototype.forEach.call(buttons, function (b) { b.disabled = false; });
      wrap.querySelector('.approve-state').textContent = 'Unable to save. Please check your connection.';
    });
  }

  function paintDecision(review, badge, card) {
    var wrap  = card.querySelector('.approve');
    var state = wrap.querySelector('.approve-state');
    var approveBtn = wrap.querySelector('.btn-approve');
    var changesBtn = wrap.querySelector('.btn-changes');

    badge.className = 'badge status status-pending';
    badge.innerHTML = '<i class="status-dot"></i><span></span>';
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
      { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });

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
      autoFold(card);
    } else {
      badgeWord.textContent = 'Changes requested';
      badge.className = 'badge status status-changes is-changes';
      changesBtn.setAttribute('aria-pressed', 'true');
      state.innerHTML = 'Changes requested' + who + ' on ' + when + '.';
      if (review.note) {
        var n = document.createElement('div');
        n.className = 'approve-note';
        n.textContent = review.note;
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

  function autoFold(card) {
    var section = card.closest('.batch');
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
        var ok = batchOk && (fmt === 'all' || card.dataset.format === fmt);
        card.hidden = !ok;
        if (ok) visibleHere++;
      });
      section.hidden = visibleHere === 0;
      if (!section.hidden) paintFold(section, false);
      shown += visibleHere;
    });

    $('countLabel').textContent = shown + ' post' + (shown === 1 ? '' : 's') + ' shown';
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
  function load() {
    if (!token && API.configured) {
      showState('Content Review',
        'Please access using your unique link provided by ' + cfg.agencyName + '.');
      return;
    }
    API.getReviewFeed(token, passcode).then(function (data) {
      if (!data || data.error === 'not_found') {
        showState('This link is no longer active',
          'Please contact your ' + cfg.agencyName + ' account manager for a new link.');
        return;
      }
      if (data.error === 'passcode_required') {
        showState('Access code required', 'Please enter the access code issued alongside this link.', true);
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
        showState('No content pending review',
          'The next content set will appear here when it is ready for review.');
        return;
      }
      build();
    }).catch(function (err) {
      console.error(err);
      showState('Unable to load this page', 'Please refresh the page. If the problem continues, contact ' + cfg.supportEmail + '.');
    });
  }

  load();
})();
