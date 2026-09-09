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

  (function () {
    var logo = $('agencyLogo');
    logo.onerror = function () {
      logo.hidden = true;
      $('agencyWordmark').hidden = false;
    };
    logo.src = cfg.brandLogo;
  })();
  if (!API.configured) $('demoStrip').hidden = false;

  function showState(title, body, wantsPass) {
    $('content').innerHTML = '';
    $('filterbar').hidden = true;
    $('state').hidden = false;
    $('stateTitle').textContent = title;
    $('stateBody').textContent = body;
    $('passForm').hidden = !wantsPass;
    if (wantsPass) $('passInput').focus();
  }

  function fmtDate(iso) {
    if (!iso) return '';
    return new Date(iso).toLocaleDateString('en-GB',
      { day: 'numeric', month: 'short', year: 'numeric' });
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
    card.appendChild(stage);

    // The mockup truncates like the real feed. This shows the caption in full.
    if (post.caption || post.caption_zh || post.title) {
      var copy = document.createElement('div');
      copy.className = 'copyblock';
      var html = '';
      if (post.title)      html += '<h5>Title</h5><div class="copytext">' + escapeHtml(post.title) + '</div>';
      if (post.caption)    html += '<h5>Caption</h5><div class="copytext">' + escapeHtml(post.caption) + '</div>';
      if (post.caption_zh) html += '<h5>中文文案</h5><div class="copytext">' + escapeHtml(post.caption_zh) + '</div>';
      copy.innerHTML = html + '<button class="copy-btn" type="button">Copy caption</button>';
      copy.querySelector('.copy-btn').addEventListener('click', function (e) {
        navigator.clipboard.writeText([post.title, post.caption, post.caption_zh]
          .filter(Boolean).join('\n\n')).then(function () {
            e.target.textContent = 'Copied';
            setTimeout(function () { e.target.textContent = 'Copy caption'; }, 1600);
          });
      });
      card.appendChild(copy);
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
        '<textarea class="textarea" placeholder="What needs to change? Be specific so we can action it in one round."></textarea>' +
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

    var reviewer = localStorage.getItem('adspace_reviewer') || '';
    if (!reviewer) {
      reviewer = (window.prompt('Your name, so we know who signed off:') || '').trim();
      if (reviewer) localStorage.setItem('adspace_reviewer', reviewer);
    }

    API.submitReview({
      token: token, postId: post.id, decision: decision,
      note: note, reviewer: reviewer, passcode: passcode
    }).then(function (res) {
      Array.prototype.forEach.call(buttons, function (b) { b.disabled = false; });
      if (res && res.error) {
        wrap.querySelector('.approve-state').textContent =
          res.error === 'note_required'
            ? 'Please tell us what needs changing.'
            : 'Could not save. Refresh and try again.';
        return;
      }
      post.review = {
        decision: decision, note: note, reviewer: reviewer,
        created_at: new Date().toISOString()
      };
      paintDecision(post.review, badge, wrap.closest('.card'));
    }).catch(function () {
      Array.prototype.forEach.call(buttons, function (b) { b.disabled = false; });
      wrap.querySelector('.approve-state').textContent = 'Could not save. Check your connection.';
    });
  }

  function paintDecision(review, badge, card) {
    var wrap  = card.querySelector('.approve');
    var state = wrap.querySelector('.approve-state');
    var approveBtn = wrap.querySelector('.btn-approve');
    var changesBtn = wrap.querySelector('.btn-changes');

    badge.className = 'badge';
    approveBtn.setAttribute('aria-pressed', 'false');
    changesBtn.setAttribute('aria-pressed', 'false');
    var old = wrap.querySelector('.approve-note');
    if (old) old.remove();

    if (!review) { badge.textContent = 'Pending'; state.textContent = ''; return; }

    var who  = review.reviewer ? ' by <b>' + escapeHtml(review.reviewer) + '</b>' : '';
    var when = new Date(review.created_at).toLocaleString('en-GB',
      { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });

    if (review.decision === 'approved') {
      badge.textContent = 'Approved';
      badge.classList.add('is-ok');
      approveBtn.setAttribute('aria-pressed', 'true');
      state.innerHTML = 'Approved' + who + ' on ' + when + '.';
    } else {
      badge.textContent = 'Changes';
      badge.classList.add('is-changes');
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
    var root = $('content');
    root.innerHTML = '';
    var formats = {};

    feed.batches.forEach(function (batch) {
      var section = document.createElement('section');
      section.className = 'batch';
      section.dataset.batch = batch.id;

      var head = document.createElement('div');
      head.className = 'batch-head';
      head.innerHTML =
        '<span class="batch-title">' + escapeHtml(batch.title) + '</span>' +
        '<span class="batch-date">' + fmtDate(batch.created_at) + ' &middot; ' +
        batch.posts.length + ' post' + (batch.posts.length === 1 ? '' : 's') + '</span>';
      section.appendChild(head);

      if (batch.note) {
        var note = document.createElement('div');
        note.className = 'batch-note';
        note.textContent = batch.note;
        section.appendChild(note);
      }

      var grid = document.createElement('div');
      grid.className = 'grid';
      batch.posts.forEach(function (post) {
        formats[MK.key(post)] = MK.label(post);
        grid.appendChild(postCard(post, feed.client));
      });
      section.appendChild(grid);
      root.appendChild(section);
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
    $('printBtn').hidden = false;
    applyFilters();
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
      shown += visibleHere;
    });

    $('countLabel').textContent = shown + ' post' + (shown === 1 ? '' : 's') + ' shown';
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
  $('printBtn').addEventListener('click', function () { window.print(); });

  $('passForm').addEventListener('submit', function (e) {
    e.preventDefault();
    passcode = $('passInput').value.trim();
    sessionStorage.setItem('adspace_pass_' + token, passcode);
    load();
  });

  // ---- Load ----------------------------------------------------------------
  function load() {
    if (!token && API.configured) {
      showState('No review link',
        'This page needs your personal review link. Please use the link ' + cfg.agencyName + ' sent you.');
      return;
    }
    API.getReviewFeed(token, passcode).then(function (data) {
      if (!data || data.error === 'not_found') {
        showState('Link not found',
          'This review link is no longer active. Contact your ' + cfg.agencyName + ' account manager for a new one.');
        return;
      }
      if (data.error === 'passcode_required') {
        showState('Access code required', 'Enter the access code we sent alongside this link.', true);
        return;
      }
      feed = data;
      $('state').hidden = true;
      $('clientName').textContent = feed.client.name;
      document.title = feed.client.name + ' — ADspace Content Review';
      if (!feed.batches.length) {
        showState('Nothing to review yet',
          'Your next content set will appear here. We will let you know when it is ready.');
        return;
      }
      build();
    }).catch(function (err) {
      console.error(err);
      showState('Something went wrong', 'Please refresh the page, or contact ' + cfg.supportEmail + '.');
    });
  }

  load();
})();
