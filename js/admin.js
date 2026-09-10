/*
 * Team admin. Built for people who are not technical:
 * drop files, we work out the placement, you write the caption, you send the link.
 */
(function () {
  var cfg = window.ADSPACE_CONFIG;
  var API = window.ADspaceAPI;
  var MK  = window.ADspaceMockups;
  var db  = API.client;
  var $   = function (id) { return document.getElementById(id); };

  (function () {
    var logo = $('agencyLogo');
    logo.onerror = function () { logo.hidden = true; $('agencyWordmark').hidden = false; };
    logo.src = cfg.brandLogo;
  })();
  if (!API.configured || !db) { $('notConfigured').hidden = false; return; }

  /* One dropdown in plain language beats two dropdowns of jargon. */
  var PLACEMENTS = [
    ['instagram:feed',     'Instagram feed post'],
    ['instagram:carousel', 'Instagram carousel'],
    ['instagram:reel',     'Instagram Reels'],
    ['instagram:story',    'Instagram Story'],
    ['facebook:feed',      'Facebook post'],
    ['facebook:multi',     'Facebook multi-photo post'],
    ['facebook:carousel',  'Facebook carousel ad'],
    ['facebook:reel',      'Facebook Reels'],
    ['facebook:story',     'Facebook Story'],
    ['tiktok:reel',        'TikTok video'],
    ['xhs:note',           'RedNote post'],
    ['cover:image',        'Cover image']
  ];

  var state = { client: null, batch: null, drafts: [], lastDropCount: 0, uploading: false,
               storageCheck: null };

  // Switching tabs is safe. Closing one mid upload is not, so only warn then.
  window.addEventListener('beforeunload', function (e) {
    if (!state.uploading) return;
    e.preventDefault();
    e.returnValue = '';
  });

  function msg(id, text, kind) {
    var n = $(id); n.textContent = text || ''; n.className = 'msg' + (kind ? ' ' + kind : '');
  }
  function esc(s) {
    return String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  }
  function makeToken() {
    var a = new Uint8Array(12);
    crypto.getRandomValues(a);
    return Array.from(a, function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
  }
  function reviewUrl(c) { return location.origin + '/review/?k=' + c.access_token; }

  /* Records the handful of actions that destroy data or change what a client
     can see. Deliberately fire and forget: a failure to log must never stop
     the action itself, and this is not a click tracker. */
  var actor = '';
  function logAction(action, subject, detail) {
    db.from('activity_log').insert({
      actor: actor || 'unknown',
      action: action,
      subject: subject || null,
      detail: detail || null
    }).then(function () {}, function () {});
  }

  function thisMonth() {
    return new Date().toLocaleDateString('en-GB', { month: 'long', year: 'numeric' }) + ' Content';
  }

  // ---- Auth ---------------------------------------------------------------
  $('authSend').addEventListener('click', function () {
    var email = $('authEmail').value.trim();
    if (!email) return;
    // A fixed URL, not location.href, so it matches the Supabase allow list exactly.
    // Supabase silently falls back to its Site URL for anything not on that list.
    db.auth.signInWithOtp({
      email: email,
      options: { emailRedirectTo: location.origin + '/admin/' }
    }).then(function (r) {
      msg('authMsg', r.error ? r.error.message : 'A sign in link has been sent to that address.',
          r.error ? 'err' : 'ok');
    });
  });
  $('authEmail').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') $('authSend').click();
  });

  $('signOut').addEventListener('click', function () {
    db.auth.signOut().then(function () { location.reload(); });
  });
  db.auth.getSession().then(function (r) { gate(r.data.session); });
  db.auth.onAuthStateChange(function (_e, session) { gate(session); });

  /* Supabase refreshes the token when you come back to the tab, which fires an
     auth event. Only the first one should decide what is on screen, otherwise
     switching tabs throws away whatever you were in the middle of. */
  var entered = false;

  function gate(session) {
    var inApp = Boolean(session);
    $('authPanel').hidden = inApp;
    $('signOut').hidden = !inApp;
    $('whoami').textContent = inApp ? session.user.email : '';
    actor = inApp ? session.user.email : '';

    if (!inApp) {
      entered = false;
      $('clientsView').hidden = true;
      $('workspace').hidden = true;
      return;
    }
    if (entered) return;
    entered = true;
    restoreView();
  }

  /* A tab that has been in the background long enough is thrown away by the
     browser and rebuilt from scratch when you return. The address bar already
     carries the client and the set; this carries how far down the page you
     were, so coming back lands where you left rather than at the top. */
  var PLACE = 'adspace.place';
  var pendingScroll = 0;

  if ('scrollRestoration' in history) history.scrollRestoration = 'manual';

  var scrollTimer = null;
  window.addEventListener('scroll', function () {
    clearTimeout(scrollTimer);
    scrollTimer = setTimeout(function () {
      if (!state.client) return;
      try {
        sessionStorage.setItem(PLACE, JSON.stringify({
          client: state.client.id,
          set: state.batch ? state.batch.id : null,
          y: Math.round(window.scrollY),
          drawer: !$('advancedBody').hidden
        }));
      } catch (e) { /* private browsing */ }
    }, 180);
  }, { passive: true });

  function readPlace() {
    try { return JSON.parse(sessionStorage.getItem(PLACE) || 'null'); }
    catch (e) { return null; }
  }

  /* Called once the lists that make the page tall have rendered, so the
     position it scrolls to actually exists. */
  function settleScroll() {
    if (!pendingScroll) return;
    var y = pendingScroll;
    requestAnimationFrame(function () {
      window.scrollTo(0, y);
      // A second pass after images size themselves, which is what moves things.
      setTimeout(function () { if (pendingScroll) { window.scrollTo(0, y); pendingScroll = 0; } }, 260);
    });
  }

  // 2. The address bar remembers the client and set you are working on, so a
  //    reload or a reopened tab lands back in the same place.
  function setUrl() {
    var q = [];
    if (state.client) q.push('client=' + state.client.id);
    if (state.batch)  q.push('set=' + state.batch.id);
    history.replaceState(null, '', '/admin/' + (q.length ? '?' + q.join('&') : ''));
  }

  function restoreView() {
    var params = new URLSearchParams(location.search);
    var clientId = params.get('client');
    var setId = params.get('set');
    if (!clientId) { showClients(); return; }

    var place = readPlace();
    var samePlace = place && place.client === clientId;
    if (samePlace) pendingScroll = place.y || 0;

    db.from('clients').select('*').eq('id', clientId).single().then(function (r) {
      if (r.error || !r.data) { showClients(); return; }
      openClient(r.data);
      if (samePlace && place.drawer) openDrawer(true);
      if (!setId) return;
      db.from('batches').select('*').eq('id', setId).single().then(function (bt) {
        if (!bt.error && bt.data) openBatch(bt.data, true);
      });
    });
  }

  // ---- Clients ------------------------------------------------------------
  function showClients() {
    $('clientsView').hidden = false;
    $('workspace').hidden = true;
    state.client = null; state.batch = null;
    setUrl();
    loadClients();
    gateActivity();
  }

  function loadClients() {
    db.from('clients').select('*').order('name').then(function (r) {
      var box = $('clientCards');
      box.innerHTML = '';
      if (r.error) { msg('clientMsg', r.error.message, 'err'); return; }
      if (!r.data.length) {
        box.innerHTML = '<div class="empty">No clients yet. Add your first one above.</div>';
        settleScroll();
        return;
      }
      r.data.forEach(function (c) {
        var card = document.createElement('button');
        card.className = 'bigcard';
        card.type = 'button';
        card.innerHTML =
          '<span class="bigcard-name">' + esc(c.name) + '</span>' +
          '<span class="bigcard-sub" data-role="sub">Loading…</span>' +
          (c.passcode ? '<span class="bigcard-tag">Access code on</span>' : '');
        card.addEventListener('click', function () { openClient(c); });
        box.appendChild(card);

        // A one line answer to "where does this client stand?"
        db.from('batches').select('id, published').eq('client_id', c.id).then(function (b) {
          var sub = card.querySelector('[data-role="sub"]');
          if (b.error || !b.data.length) { sub.textContent = 'No content sets'; return; }
          var live = b.data.filter(function (x) { return x.published; }).length;
          sub.textContent = b.data.length + ' set' + (b.data.length === 1 ? '' : 's') +
            ' · ' + live + ' published';
        });
      });
      settleScroll();
    });
  }

  var ACTION_LABEL = {
    'client.removed':        ['Client removed', 'is-danger'],
    'set.deleted':           ['Content set deleted', 'is-danger'],
    'post.deleted':          ['Post deleted', 'is-danger'],
    'set.published':         ['Published to client', 'is-ok'],
    'set.withdrawn':         ['Withdrawn from client', 'is-warn'],
    'link.reset':            ['Access link reset', 'is-warn'],
    'reapproval.requested':  ['Re-approval requested', 'is-warn']
  };

  /* The section only appears for people on the viewer list. The database
     enforces this too, so hiding it here is convenience rather than the
     control itself. */
  function gateActivity() {
    var panel = $('activityToggle').closest('.panel');
    panel.hidden = true;
    if (!actor) return;
    db.from('activity_viewers').select('email').ilike('email', actor).limit(1)
      .then(function (r) {
        panel.hidden = !(r.data && r.data.length);
      }, function () { panel.hidden = true; });
  }

  $('activityToggle').addEventListener('click', function () {
    var open = $('activityBody').hidden;
    $('activityBody').hidden = !open;
    $('activityToggle').setAttribute('aria-expanded', String(open));
    $('activityToggle').classList.toggle('is-open', open);
    if (open) loadActivity();
  });

  function loadActivity() {
    var box = $('activityList');
    box.innerHTML = '<div class="empty">Loading…</div>';
    db.from('activity_log').select('*')
      .order('created_at', { ascending: false }).limit(60)
      .then(function (r) {
        if (r.error) {
          box.innerHTML = '<div class="empty">You do not have access to the activity record.</div>';
          return;
        }
        if (!r.data.length) { box.innerHTML = '<div class="empty">No recorded activity.</div>'; return; }
        box.innerHTML = '';
        r.data.forEach(function (a) {
          var meta = ACTION_LABEL[a.action] || [a.action, ''];
          var row = document.createElement('div');
          row.className = 'act';
          row.innerHTML =
            '<span class="act-tag ' + meta[1] + '">' + esc(meta[0]) + '</span>' +
            '<span class="act-subject">' + esc(a.subject || '') + '</span>' +
            '<span class="muted act-detail">' + esc(a.detail || '') + '</span>' +
            '<span class="muted act-who">' + esc(a.actor || '') + '</span>' +
            '<span class="muted act-when">' +
              new Date(a.created_at).toLocaleString('en-GB',
                { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) +
            '</span>';
          box.appendChild(row);
        });
      });
  }

  $('showAddClient').addEventListener('click', function () {
    $('addClientBox').hidden = false;
    $('newClientName').focus();
  });
  $('cancelAddClient').addEventListener('click', function () { $('addClientBox').hidden = true; });

  $('addClient').addEventListener('click', function () {
    var name = $('newClientName').value.trim();
    if (!name) { msg('clientMsg', 'A client name is required.', 'err'); return; }
    db.from('clients').insert({
      name: name,
      logo_url: $('newClientLogo').value.trim() || null,
      passcode: $('newClientPass').value.trim() || null,
      access_token: makeToken()
    }).select().single().then(function (r) {
      if (r.error) { msg('clientMsg', r.error.message, 'err'); return; }
      ['newClientName','newClientLogo','newClientPass']
        .forEach(function (i) { $(i).value = ''; });
      $('addClientBox').hidden = true;
      msg('clientMsg', '');
      openClient(r.data);
    });
  });

  function openClient(c) {
    state.client = c;
    state.batch = null;
    $('clientsView').hidden = true;
    $('workspace').hidden = false;
    $('setPanel').hidden = true;
    $('wsClientName').textContent = c.name;

    var url = reviewUrl(c);
    $('clientLink').value = url;
    $('openLink').href = url;
    openDrawer(false);
    $('eIg').value  = c.handle_ig || '';
    $('eFb').value  = c.handle_fb || '';
    $('eTt').value  = c.handle_tiktok || '';
    $('eXhs').value = c.handle_xhs || '';
    $('eLogo').value = c.logo_url || '';
    $('ePass').value = c.passcode || '';
    paintLock();
    msg('handleMsg', '');
    msg('profileMsg', '');
    setUrl();
    loadBatches();
    if (!pendingScroll) window.scrollTo(0, 0);
  }

  $('backToClients').addEventListener('click', showClients);

  function openDrawer(open) {
    $('advancedBody').hidden = !open;
    $('advancedToggle').setAttribute('aria-expanded', String(open));
    $('advancedToggle').classList.toggle('is-open', open);
  }

  $('advancedToggle').addEventListener('click', function () {
    openDrawer($('advancedBody').hidden);
  });

  $('saveHandles').addEventListener('click', function () {
    db.from('clients').update({
      handle_ig:     $('eIg').value.trim() || null,
      handle_fb:     $('eFb').value.trim() || null,
      handle_tiktok: $('eTt').value.trim() || null,
      handle_xhs:    $('eXhs').value.trim() || null
    }).eq('id', state.client.id).then(function (r) {
      if (r.error) { msg('handleMsg', r.error.message, 'err'); return; }
      state.client.handle_ig = $('eIg').value.trim() || null;
      state.client.handle_fb = $('eFb').value.trim() || null;
      state.client.handle_tiktok = $('eTt').value.trim() || null;
      state.client.handle_xhs = $('eXhs').value.trim() || null;
      msg('handleMsg', 'Saved. Applied to every preview.', 'ok');
    });
  });

  /* Whether the link needs a code is worth seeing without opening the drawer. */
  function paintLock() {
    $('wsLock').hidden = !state.client.passcode;
  }

  /* Logo and access code were set once at creation and then stuck. Both are
     editable here, and clearing either field removes it. */
  $('saveProfile').addEventListener('click', function () {
    var logo = $('eLogo').value.trim();
    var pass = $('ePass').value.trim();
    if (logo && !/^https:\/\//i.test(logo)) {
      msg('profileMsg', 'The logo address needs to start with https://', 'err');
      return;
    }
    var had = Boolean(state.client.passcode);
    db.from('clients').update({ logo_url: logo || null, passcode: pass || null })
      .eq('id', state.client.id).then(function (r) {
        if (r.error) { msg('profileMsg', r.error.message, 'err'); return; }
        state.client.logo_url = logo || null;
        state.client.passcode = pass || null;
        paintLock();
        var note = !had && pass ? 'Access code added. The client will be asked for it.'
                 : had && !pass ? 'Access code removed. The link now opens on its own.'
                 : had && pass  ? 'Access code updated. The previous one no longer works.'
                 : 'Saved.';
        msg('profileMsg', note, 'ok');
        if (!had && !pass) msg('profileMsg', logo ? 'Logo saved.' : 'Saved.', 'ok');
      });
  });

  $('resetLink').addEventListener('click', function () {
    if (!confirm('Reset the review link for ' + state.client.name + '?\n\n' +
      'The current link will be invalidated immediately and anyone holding it will lose ' +
      'access. The replacement link must be reissued to the client.')) return;

    var next = makeToken();
    db.from('clients').update({ access_token: next }).eq('id', state.client.id)
      .then(function (r) {
        if (r.error) { msg('handleMsg', r.error.message, 'err'); return; }
        logAction('link.reset', state.client.name, 'Previous link invalidated');
        state.client.access_token = next;
        var fresh = reviewUrl(state.client);
        $('clientLink').value = fresh;
        $('openLink').href = fresh;
        msg('handleMsg', 'New link issued. The previous link is no longer valid.', 'ok');
      });
  });

  /* Deleting a client takes every set, post and approval with it, and two
     confirm boxes are two reflexes. It takes something typed instead.

     The code itself is never in this file. Anything here is served to the
     browser and readable by anyone who opens the page, so a code kept here
     would not be a code at all. It lives in the database, behind a table the
     browser cannot read, and the deletion runs as a function on the server
     that compares it there. This side only asks the question and passes the
     answer along; it never learns whether the answer was right until the
     server says so, and a browser that skipped the question outright would be
     refused all the same. */
  $('deleteClient').addEventListener('click', function () {
    var c = state.client;
    db.from('batches').select('id').eq('client_id', c.id).then(function (r) {
      var sets = (r.data || []).length;
      if (!confirm('Delete ' + c.name + '?\n\n' +
        'This removes their review link and ' + sets + ' content set' +
        (sets === 1 ? '' : 's') + ', including every post and approval record.\n\n' +
        'This cannot be reversed.')) return;

      db.rpc('delete_code_set').then(function (q) {
        // The function is missing until the current schema has been applied.
        if (q.error) { legacyDelete(c, sets, q.error); return; }
        askAndDelete(c, sets, q.data === true);
      });
    });
  });

  function askAndDelete(c, sets, coded) {
    var answer = window.prompt(
      'Deleting ' + c.name + ' cannot be undone.\n\n' +
      (coded ? 'Enter the deletion code to continue:'
             : 'Type the client name exactly to confirm:'), '');
    if (answer === null) return;
    answer = answer.trim();

    if (!coded && answer !== c.name) {
      msg('profileMsg', 'That does not match the client name. Nothing has been deleted.', 'err');
      return;
    }

    db.rpc('delete_client', { p_client: c.id, p_code: coded ? answer : null })
      .then(function (res) {
        if (res.error) { msg('profileMsg', res.error.message, 'err'); return; }
        if (res.data === 'wrong-code') {
          msg('profileMsg', 'That deletion code is not correct. Nothing has been deleted.', 'err');
          return;
        }
        if (res.data === 'not-found') {
          msg('profileMsg', 'That client no longer exists.', 'err');
          showClients();
          return;
        }
        logAction('client.removed', c.name,
          sets + ' content set' + (sets === 1 ? '' : 's') + ' removed with it');
        showClients();
      });
  }

  /* A database that has not had the current schema applied yet. Deleting still
     works, and still asks, but the check is only the one in this browser. Say
     so rather than implying a protection that is not there. */
  function legacyDelete(c, sets, why) {
    if (!/function|does not exist|schema|404/i.test(why.message || '')) {
      msg('profileMsg', why.message, 'err');
      return;
    }
    var typed = window.prompt(
      'Deleting ' + c.name + ' cannot be undone.\n\n' +
      'Type the client name exactly to confirm:', '');
    if (typed === null) return;
    if (typed.trim() !== c.name) {
      msg('profileMsg', 'That does not match the client name. Nothing has been deleted.', 'err');
      return;
    }
    db.from('clients').delete().eq('id', c.id).then(function (res) {
      if (res.error) { msg('profileMsg', res.error.message, 'err'); return; }
      logAction('client.removed', c.name,
        sets + ' content set' + (sets === 1 ? '' : 's') + ' removed with it');
      showClients();
      msg('clientMsg', 'Deleted. Run the current supabase/schema.sql to move the ' +
        'deletion code onto the server, where a browser cannot read it.', 'err');
    });
  }

  $('copyLink').addEventListener('click', function () {
    navigator.clipboard.writeText($('clientLink').value).then(function () {
      $('copyLink').textContent = 'Copied';
      setTimeout(function () { $('copyLink').textContent = 'Copy link'; }, 1600);
    });
  });

  // ---- Content sets -------------------------------------------------------
  function loadBatches() {
    db.from('batches').select('*').eq('client_id', state.client.id)
      .order('created_at', { ascending: false }).then(function (r) {
        var box = $('batchCards');
        box.innerHTML = '';
        if (r.error || !r.data.length) {
          box.innerHTML = '<div class="empty">No content sets yet. Create one to start uploading.</div>';
          return;
        }
        r.data.forEach(function (b) {
          var card = document.createElement('button');
          card.className = 'bigcard' + (state.batch && state.batch.id === b.id ? ' is-on' : '');
          card.type = 'button';
          card.innerHTML =
            '<span class="bigcard-name">' + esc(b.title) + '</span>' +
            '<span class="bigcard-sub" data-role="sub">Loading…</span>' +
            '<span class="bigcard-tag ' + (b.published ? 'is-live' : '') + '">' +
              (b.published ? 'Published' : 'Draft') + '</span>';
          card.addEventListener('click', function () { openBatch(b); });
          box.appendChild(card);

          db.from('posts').select('id').eq('batch_id', b.id).then(function (p) {
            var n = (p.data || []).length;
            card.querySelector('[data-role="sub"]').textContent =
              n + ' post' + (n === 1 ? '' : 's');
          });
        });
      });
  }

  $('addBatch').addEventListener('click', function () {
    var title = (window.prompt('Name for this content set:', thisMonth()) || '').trim();
    if (!title) return;
    db.from('batches').insert({
      client_id: state.client.id, title: title, published: false
    }).select().single().then(function (r) {
      if (r.error) return;
      loadBatches();
      openBatch(r.data);
    });
  });

  function openBatch(b, quiet) {
    state.batch = b;
    setUrl();
    state.drafts = readStoredDrafts();
    $('setPanel').hidden = false;
    $('driveUrl').value = state.client.drive_folder || '';
    $('mediaUrl').value = '';
    $('drivePicker').hidden = true;
    msg('driveMsg', '');
    paintSetHeader();
    renderDrafts();
    loadBatches();
    loadPosts();

    if (state.drafts.length) {
      msg('setMsg', state.drafts.length + ' unsaved upload' +
        (state.drafts.length === 1 ? '' : 's') +
        ' still waiting to be added to this set.', 'ok');
    }
    if (!quiet) $('setPanel').scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  function paintSetHeader() {
    var live = state.batch.published;
    $('setTitle').textContent = state.batch.title;

    var chip = $('setState');
    chip.textContent = live ? 'Published' : 'Draft';
    chip.className = 'chip' + (live ? ' is-live' : '');

    // Publishing is the positive action, taking it back is a step in reverse,
    // so they should not look the same.
    $('publishLabel').textContent = live ? 'Unpublish' : 'Publish';
    // A paper plane to send it out, an eye struck through to take it back.
    $('publishIcon').innerHTML = live
      ? '<path d="m3 3 18 18"/><path d="M10.6 5.1A9.6 9.6 0 0 1 12 5c5 0 9 4.5 9 7a12 12 0 0 1-2.4 3.4"/>' +
        '<path d="M6.5 7.6C4.3 9.1 3 11.2 3 12c0 2.5 4 7 9 7a9.7 9.7 0 0 0 4.2-1"/>' +
        '<path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/>'
      : '<path d="M21 3 10.5 13.5"/><path d="M21 3l-6.8 18-3.7-7.5L3 9.8z"/>';
    $('publishSet').className = 'btn btn-icon ' + (live ? 'btn-warn' : 'btn-go');

    // The standing state belongs beside the title. #setMsg is kept free for
    // things that just happened, so one does not overwrite the other.
    $('setNote').textContent = live
      ? 'Visible to the client on their review link.'
      : 'Not visible to the client yet.';
    msg('setMsg', '');
  }

  $('publishSet').addEventListener('click', function () {
    var next = !state.batch.published;
    if (!next) { setPublished(false); return; }

    // Sending is the commitment, so this is where a missing caption is worth flagging.
    db.from('posts').select('caption, caption_zh').eq('batch_id', state.batch.id).then(function (r) {
      var posts = r.data || [];
      if (!posts.length) { msg('setMsg', 'Add at least one post before publishing.', 'err'); return; }
      var blank = posts.filter(function (p) { return !p.caption && !p.caption_zh; }).length;
      var warn = blank
        ? '\n\n' + blank + ' of ' + posts.length + ' posts ' + (blank === 1 ? 'has' : 'have') +
          ' no copy assigned.'
        : '';
      if (!confirm('Publish ' + posts.length + ' post' + (posts.length === 1 ? '' : 's') +
                   ' to ' + state.client.name + '? The set becomes visible immediately.' +
                   warn)) return;
      setPublished(true);
    });
  });

  function setPublished(next) {
    db.from('batches').update({ published: next }).eq('id', state.batch.id).then(function (r) {
      if (r.error) { msg('setMsg', r.error.message, 'err'); return; }
      logAction(next ? 'set.published' : 'set.withdrawn',
        state.client.name + ' — ' + state.batch.title);
      state.batch.published = next;
      paintSetHeader();
      msg('setMsg', next
        ? 'Published. The client can now see this set on their review link.'
        : 'Withdrawn. This set is no longer visible to the client.', next ? 'ok' : '');
      loadBatches();
    });
  }

  $('deleteSet').addEventListener('click', function () {
    var b = state.batch;
    db.from('posts').select('id').eq('batch_id', b.id).then(function (r) {
      var n = (r.data || []).length;
      var warning = 'Delete "' + b.title + '"?\n\n' +
        'This removes ' + n + ' post' + (n === 1 ? '' : 's') + ' and their approval records.' +
        (b.published ? '\n\nThis set is currently published to the client.' : '') +
        '\n\nThis action cannot be reversed.';
      if (!confirm(warning)) return;

      db.from('batches').delete().eq('id', b.id).then(function (res) {
        if (res.error) { msg('setMsg', res.error.message, 'err'); return; }
        logAction('set.deleted', state.client.name + ' — ' + b.title,
          n + ' post' + (n === 1 ? '' : 's') + (b.published ? ', was published' : ', was draft'));
        state.batch = null;
        clearDrafts();
        $('setPanel').hidden = true;
        loadBatches();
      });
    });
  });

  $('renameSet').addEventListener('click', function () {
    var title = (window.prompt('Rename this content set:', state.batch.title) || '').trim();
    if (!title) return;
    db.from('batches').update({ title: title }).eq('id', state.batch.id).then(function () {
      state.batch.title = title;
      paintSetHeader();
      loadBatches();
    });
  });

  // ---- Uploading ----------------------------------------------------------
  var drop = $('drop'), fileInput = $('fileInput');
  drop.addEventListener('click', function () { fileInput.click(); });
  drop.addEventListener('dragover', function (e) { e.preventDefault(); drop.classList.add('is-over'); });
  drop.addEventListener('dragleave', function () { drop.classList.remove('is-over'); });
  drop.addEventListener('drop', function (e) {
    e.preventDefault(); drop.classList.remove('is-over');
    handleFiles(e.dataTransfer.files);
  });
  fileInput.addEventListener('change', function () { handleFiles(fileInput.files); fileInput.value = ''; });

  /* Reads the real pixel size so we can guess the placement instead of asking. */
  function probe(file) {
    return probeBlob(file, file.type || '');
  }

  /* Reads the real pixel size, and for a video grabs a still as well. The still
     becomes the poster, so the client sees the frame straight away and the
     video itself is not fetched until they press play. */
  function probeBlob(blob, mime) {
    return new Promise(function (resolve) {
      var url = URL.createObjectURL(blob);
      var isVideo = String(mime).indexOf('video') === 0;
      var node = document.createElement(isVideo ? 'video' : 'img');
      var settled = false;
      var done = function (w, h, poster) {
        if (settled) return;
        settled = true;
        URL.revokeObjectURL(url);
        resolve({ width: w || 0, height: h || 0, isVideo: isVideo,
                  mime: mime || null, poster: poster || null });
      };
      // A file the browser cannot decode must not hold the batch up.
      setTimeout(function () { done(node.videoWidth || 0, node.videoHeight || 0); }, 15000);

      if (isVideo) {
        node.preload = 'metadata';
        node.muted = true;
        node.playsInline = true;
        node.onloadedmetadata = function () {
          var w = node.videoWidth, h = node.videoHeight;
          node.onseeked = function () {
            grabFrame(node, w, h).then(function (poster) { done(w, h, poster); },
                                       function () { done(w, h); });
          };
          // A little way in, so the still is not the black frame most edits open on.
          try { node.currentTime = Math.min(1, (node.duration || 2) / 3); }
          catch (e) { done(w, h); }
        };
      } else {
        node.onload = function () { done(node.naturalWidth, node.naturalHeight); };
      }
      node.onerror = function () { done(0, 0); };
      node.src = url;
    });
  }

  /* One frame as a small JPEG. Capped at 720 across, which is plenty for a
     poster and keeps it to a few tens of kilobytes. */
  function grabFrame(video, w, h) {
    return new Promise(function (resolve, reject) {
      if (!w || !h) { reject(); return; }
      var scale = Math.min(1, 720 / Math.max(w, h));
      var canvas = document.createElement('canvas');
      canvas.width = Math.round(w * scale);
      canvas.height = Math.round(h * scale);
      try {
        canvas.getContext('2d').drawImage(video, 0, 0, canvas.width, canvas.height);
      } catch (e) { reject(); return; }
      canvas.toBlob(function (b) { b ? resolve(b) : reject(); }, 'image/jpeg', 0.72);
    });
  }

  /* An MP4 only starts playing once the player has read its moov atom. Most
     exports leave it at the end of the file, which means the whole video has to
     arrive before the first frame does. Reading the box order tells us which
     kind we have, so the team can re-export rather than hand a client a video
     that takes a minute to start. */
  function hasFastStart(file) {
    if (!/mp4|quicktime|m4v/i.test(file.type || '')) return Promise.resolve(true);
    var offset = 0;
    var steps = 0;
    function readBox() {
      if (steps++ > 12 || offset + 8 > file.size) return Promise.resolve(true);
      return file.slice(offset, offset + 16).arrayBuffer().then(function (buf) {
        var view = new DataView(buf);
        if (buf.byteLength < 8) return true;
        var size = view.getUint32(0);
        var type = String.fromCharCode(view.getUint8(4), view.getUint8(5),
                                       view.getUint8(6), view.getUint8(7));
        if (type === 'moov') return true;
        if (type === 'mdat') return false;
        if (size === 1) {                       // 64-bit size follows the type
          if (buf.byteLength < 16) return true;
          size = Number(view.getBigUint64(8));
        }
        if (!size || size < 8) return true;
        offset += size;
        return readBox();
      }, function () { return true; });         // unreadable is not a verdict
    }
    return readBox();
  }

  function guessPlacement(info) {
    if (!info.width || !info.height) return 'instagram:feed';
    var ratio = info.width / info.height;
    if (ratio < 0.62) return info.isVideo ? 'instagram:reel' : 'instagram:story';  // 9:16
    if (info.isVideo) return 'instagram:reel';
    return 'instagram:feed';                                                       // 4:5, 1:1, landscape
  }

  function handleFiles(files) {
    if (!files || !files.length) return;
    if (!state.batch) { msg('setMsg', 'Select a content set first.', 'err'); return; }

    // The size limit belongs to Supabase storage. S3 has no such ceiling.
    var cap = usingS3() ? Infinity : (cfg.maxUploadMB || 50) * 1024 * 1024;
    var all = Array.prototype.slice.call(files);
    var queue = all.filter(function (f) { return f.size <= cap; });
    var toobig = all.filter(function (f) { return f.size > cap; });

    if (toobig.length) {
      msg('setMsg',
        toobig.map(function (f) { return f.name + ' (' + mb(f.size) + ' MB)'; }).join(', ') +
        ' — too big to upload. The limit is ' + (cfg.maxUploadMB || 50) + ' MB. ' +
        'Export a review copy at 1080p and around 5 Mbps, which is plenty for approval, ' +
        'or put the file on your own CDN and paste the link below.', 'err');
      if (!queue.length) return;
    }

    state.lastDropCount = queue.length;
    state.uploading = true;
    var done = 0;
    var total = queue.reduce(function (n, f) { return n + f.size; }, 0);
    var sent = queue.map(function () { return 0; });
    var word = queue.length === 1 ? 'file' : 'files';
    if (!toobig.length) msg('setMsg', '');
    showProgress('Uploading ' + queue.length + ' ' + word + '…', 0);

    function tick() {
      var n = sent.reduce(function (a, b) { return a + b; }, 0);
      showProgress('Uploading ' + queue.length + ' ' + word + ' · ' +
        done + ' of ' + queue.length + ' complete', total ? n / total : 0);
    }

    var slow = [];
    runPool(queue, function (file, i) {
      return probe(file).then(function (info) {
        return storeFile(file, function (frac) {
          sent[i] = frac * file.size;
          tick();
        }).then(function (publicUrl) {
          sent[i] = file.size;
          done++;
          tick();
          return hasFastStart(file).then(function (fast) {
            if (!fast) slow.push(file.name);
            return storePoster(info.poster).then(function (posterUrl) {
              info.posterUrl = posterUrl;
              return { url: publicUrl, info: info };
            });
          });
        });
      });
    }, 3)
      .then(function (results) {
        state.uploading = false;
        showProgress(null);
        // Added in the order they were chosen, not the order they happened to
        // finish, so the running order of a set is never a lottery.
        results.forEach(function (r) { pushDraft(r.url, r.info, true); });
        if (slow.length) {
          msg('setMsg', slow.join(', ') + ' — ' + (slow.length === 1 ? 'this file has' : 'these files have') +
            ' its index at the end, so a viewer waits for the whole download before ' +
            'the first frame appears. Re-export with Fast Start or Web Optimised ' +
            'for instant playback. The upload itself is fine.', 'err');
        } else if (!toobig.length) {
          msg('setMsg', 'Upload complete. Add copy below, then select Add to set.', 'ok');
        }
        renderDrafts();
      })
      .catch(function (e) {
        state.uploading = false;
        showProgress(null);
        var text = e.message || 'Upload failed.';
        if (/payload|too large|exceeded/i.test(text)) {
          text = 'That file is over the ' + (cfg.maxUploadMB || 50) +
            ' MB storage limit. Export a smaller review copy, or paste a link instead.';
        }
        msg('setMsg', text, 'err');
      });
  }

  function mb(bytes) {
    var v = bytes / 1024 / 1024;
    return v < 1 ? v.toFixed(1) : v.toFixed(0);   // 0.4 MB should not read as 0 MB
  }

  function usingS3() { return Boolean(cfg.s3 && cfg.s3.enabled); }

  function clientHandles() {
    var c = state.client || {};
    return {
      instagram: c.handle_ig, facebook: c.handle_fb,
      tiktok: c.handle_tiktok, xhs: c.handle_xhs
    };
  }

  /* "MP4 · 1080 x 1920", so it is obvious what was actually imported. */
  /* Carousel order decides which slide Instagram shows first and sizes the
     whole post, so it has to be changeable when the guess is wrong. */
  function slidesNode(media, onChange) {
    var wrap = el2('div', 'slides');
    media.forEach(function (m, i) {
      var chip = el2('div', 'slide-chip');
      chip.innerHTML =
        (m.type === 'video'
          ? '<video src="' + m.url + '" muted></video>'
          : '<img src="' + m.url + '" alt="">') +
        '<i>' + (i + 1) + '</i>' +
        '<span class="slide-move">' +
          '<button type="button" data-d="-1"' + (i === 0 ? ' disabled' : '') + '>&#8249;</button>' +
          '<button type="button" data-d="1"' + (i === media.length - 1 ? ' disabled' : '') + '>&#8250;</button>' +
        '</span>';
      chip.querySelectorAll('button').forEach(function (btn) {
        btn.addEventListener('click', function () {
          var to = i + Number(btn.dataset.d);
          if (to < 0 || to >= media.length) return;
          var moved = media.splice(i, 1)[0];
          media.splice(to, 0, moved);
          onChange();
        });
      });
      wrap.appendChild(chip);
    });
    return wrap;
  }

  /* Runs `work` over `items` a few at a time. One upload rarely fills the
     office line on its own, so several in flight finish the batch far sooner
     than one after another. Results come back in the original order. */
  function runPool(items, work, limit) {
    var out = new Array(items.length);
    var next = 0;
    function lane() {
      if (next >= items.length) return Promise.resolve();
      var i = next++;
      return Promise.resolve(work(items[i], i)).then(function (r) {
        out[i] = r;
        return lane();
      });
    }
    var lanes = [];
    for (var i = 0; i < Math.min(limit || 3, items.length); i++) lanes.push(lane());
    return Promise.all(lanes).then(function () { return out; });
  }

  function el2(tag, cls) {
    var n = document.createElement(tag);
    n.className = cls;
    return n;
  }

  function fileLabel(m) {
    if (!m) return '';
    var ext = extFor(m.mime, m.url || '').toUpperCase();
    var size = m.width && m.height ? m.width + ' x ' + m.height : '';
    return [ext, size].filter(Boolean).join(' · ');
  }

  /* Files are already in storage by the time they become drafts, so keeping the
     draft list locally means a reload never costs you an upload. */
  function draftKey() { return 'adspace_drafts_' + (state.batch ? state.batch.id : 'none'); }

  function saveDrafts() {
    try {
      if (state.drafts.length) localStorage.setItem(draftKey(), JSON.stringify(state.drafts));
      else localStorage.removeItem(draftKey());
    } catch (e) { /* private mode, carry on without it */ }
  }

  function readStoredDrafts() {
    try {
      var raw = localStorage.getItem(draftKey());
      var list = raw ? JSON.parse(raw) : [];
      return Array.isArray(list) ? list : [];
    } catch (e) { return []; }
  }

  /* One place that knows where files live. S3 behind CloudFront when it is set
     up, Supabase storage otherwise. Returns the URL to save on the post. */
  /* The content type is authoritative, the filename is not. A video named
     .jpg, or a Drive file with no extension at all, must not decide how the
     file is stored or how the client's browser is told to play it. */
  var MIME_EXT = {
    'video/mp4': 'mp4', 'video/quicktime': 'mov', 'video/webm': 'webm',
    'video/x-m4v': 'm4v', 'video/mpeg': 'mpg', 'video/x-matroska': 'mkv',
    'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp',
    'image/gif': 'gif', 'image/heic': 'heic', 'image/avif': 'avif'
  };

  function extFor(mimeType, name) {
    var byMime = MIME_EXT[String(mimeType || '').toLowerCase().split(';')[0].trim()];
    if (byMime) return byMime;

    var fromName = String(name || '').split('.').pop().toLowerCase().replace(/[^a-z0-9]/g, '');
    if (fromName && fromName.length <= 5 && /\./.test(String(name || ''))) return fromName;

    // Last resort: at least keep video and image apart.
    return String(mimeType || '').indexOf('video') === 0 ? 'mp4' : 'jpg';
  }

  function storePoster(blob) {
    if (!blob) return Promise.resolve(null);
    return storeBlob(blob, 'jpg', 'image/jpeg').then(function (url) { return url; },
                                                     function () { return null; });
  }

  function storeFile(file, onProgress) {
    return storeBlob(file, extFor(file.type, file.name), file.type, onProgress);
  }

  /* fetch() cannot report how much of a body has gone out, so a 40 MB video
     looks frozen until it lands. XHR can, and it is the same request. */
  function putToS3(url, blob, contentType, onProgress) {
    return new Promise(function (resolve, reject) {
      var xhr = new XMLHttpRequest();
      xhr.open('PUT', url, true);
      xhr.setRequestHeader('Content-Type', contentType || 'application/octet-stream');
      // filenames are random and never reused, so this is safe to cache hard
      xhr.setRequestHeader('Cache-Control', 'public, max-age=31536000, immutable');
      if (onProgress) {
        xhr.upload.onprogress = function (e) {
          if (e.lengthComputable) onProgress(e.loaded / e.total);
        };
      }
      xhr.onload = function () {
        if (xhr.status >= 200 && xhr.status < 300) { if (onProgress) onProgress(1); resolve(); }
        else reject(new Error('S3 rejected the upload (HTTP ' + xhr.status + ').'));
      };
      xhr.onerror = function () {
        reject(new Error('The connection to storage dropped part way through the upload.'));
      };
      xhr.send(blob);
    });
  }

  function storeBlob(blob, ext, contentType, onProgress) {
    if (!usingS3()) {
      var path = state.client.id + '/' + crypto.randomUUID() + '.' + (ext || 'bin');
      return db.storage.from(cfg.storageBucket)
        .upload(path, blob, { cacheControl: '31536000', contentType: contentType || undefined })
        .then(function (r) {
          if (r.error) throw r.error;
          return db.storage.from(cfg.storageBucket).getPublicUrl(path).data.publicUrl;
        });
    }

    // Ask our own function to sign one upload, then send the file straight to
    // S3. The file never passes through Supabase, so there is no size ceiling.
    return db.functions.invoke(cfg.s3.functionName || 'sign-upload', {
      body: { ext: ext || 'bin', clientId: state.client.id, size: blob.size }
    }).then(function (r) {
      if (r.error) {
        var hint = /failed to send|fetch/i.test(r.error.message || '')
          ? ' The browser could not reach it. In the Supabase dashboard, open Edge ' +
            'Functions, check a function named "' + (cfg.s3.functionName || 'sign-upload') +
            '" exists, and turn OFF its "Verify JWT" setting.'
          : '';
        throw new Error('Could not start the upload. ' + r.error.message + hint);
      }
      if (!r.data || !r.data.uploadUrl) throw new Error(
        'Upload was refused: ' + ((r.data && r.data.error) || 'unknown reason'));

      return putToS3(r.data.uploadUrl, blob, contentType, onProgress).then(function () {
        // The file is in the bucket, but that does not prove CloudFront serves it
        // at the URL we are about to save. What this catches is a misconfigured
        // distribution, which is the same for every file, so one check a session
        // is enough. Reading every upload back meant downloading it a second
        // time. Held as a promise rather than a flag so uploads running side by
        // side share the one check instead of each starting their own.
        if (!state.storageCheck) {
          state.storageCheck = probeUrl(r.data.publicUrl).then(function (info) {
            if (info.ok) return true;
            state.storageCheck = null;   // a later upload may be worth retrying
            throw new Error(
              'Uploaded to S3, but nothing is served at ' + r.data.publicUrl + ' — so the ' +
              'client would see a broken post. Usually the CloudFront distribution has an ' +
              'Origin path set, which shifts where files appear. Open that URL in a tab to ' +
              'confirm, then see docs/S3-UPLOAD-SETUP.md.');
          });
        }
        return state.storageCheck.then(function () { return r.data.publicUrl; });
      });
    });
  }

  window.__hasFastStart = hasFastStart;   // used by the test harness

  function pushDraft(url, info, quiet) {
    // Store the real pixel size so the client's preview frame matches the file
    // before it has finished loading.
    state.drafts.push({
      placement: guessPlacement(info),
      media: [{
        url: url,
        type: info.isVideo ? 'video' : 'image',
        width: info.width || null,
        height: info.height || null,
        mime: info.mime || null,
        poster: info.posterUrl || null
      }],
      caption: '', caption_zh: '', title: '', showZh: false
    });
    if (!quiet) renderDrafts();
  }

  /* Large videos can live anywhere that serves the file directly, such as
     mycdn.adspace.me. We read the dimensions off the URL the same way. */
  function probeUrl(url) {
    return new Promise(function (resolve) {
      var settled = false;
      var finish = function (r) { if (!settled) { settled = true; resolve(r); } };
      setTimeout(function () { finish({ ok: false }); }, 12000);

      var v = document.createElement('video');
      v.preload = 'metadata';
      v.onloadedmetadata = function () {
        finish({ width: v.videoWidth, height: v.videoHeight, isVideo: true,
                 mime: null, ok: v.videoWidth > 0 });
      };
      v.onerror = function () {
        var i = new Image();
        i.onload = function () {
          finish({ width: i.naturalWidth, height: i.naturalHeight, isVideo: false,
                   mime: null, ok: true });
        };
        i.onerror = function () { finish({ ok: false }); };
        i.src = url;
      };
      v.src = url;
    });
  }

  $('addMediaUrl').addEventListener('click', function () {
    var url = $('mediaUrl').value.trim();
    if (!url) return;
    if (!state.batch) { msg('setMsg', 'Select a content set first.', 'err'); return; }

    // A Drive link is a normal thing to paste here, so handle it rather than refuse it.
    if (isDriveLink(url)) { handleDriveLink(url); return; }

    if (!/^https:\/\//i.test(url)) {
      msg('setMsg', 'The link needs to start with https://', 'err');
      return;
    }
    msg('setMsg', 'Verifying the link…');
    probeUrl(url).then(function (info) {
      if (!info.ok) {
        msg('setMsg', 'We could not load that link. It has to point straight at the file, ' +
          'the way https://mycdn.adspace.me/reel.mp4 does. A Dropbox share page will not ' +
          'work because it returns a web page, not the video.', 'err');
        return;
      }
      pushDraft(url, info);
      $('mediaUrl').value = '';
      msg('setMsg', 'Asset added. Add copy below, then select Add to set.', 'ok');
    });
  });

  function handleDriveLink(url) {
    if (!driveKey()) {
      msg('setMsg', 'That is a Google Drive link. To pull files straight from Drive we need ' +
        'a Google API key in js/config.js first. See docs/DRIVE-IMPORT-CHECK.md.', 'err');
      return;
    }

    // A folder belongs in the Drive section, so send it there and load it.
    var folder = driveFolderId(url);
    if (folder) {
      $('mediaUrl').value = '';
      $('driveUrl').value = url;
      msg('setMsg', '');
      $('driveLoad').click();
      return;
    }

    var fileId = driveFileId(url);
    if (!fileId) {
      msg('setMsg', 'That looks like a Drive link but we could not find a file id in it. ' +
        'Use the Share button in Drive and copy the link it gives you.', 'err');
      return;
    }

    msg('setMsg', 'Retrieving file details from Drive…');
    driveMeta(fileId).then(function (f) {
      if (!/^(image|video)\//.test(f.mimeType)) {
        msg('setMsg', f.name + ' is not an image or a video.', 'err');
        return;
      }
      var cap = usingS3() ? Infinity : (cfg.maxUploadMB || 50) * 1024 * 1024;
      if (f.size > cap) {
        msg('setMsg', f.name + ' is ' + mb(f.size) + ' MB, over the ' +
          (cfg.maxUploadMB || 50) + ' MB limit. Turning on S3 storage removes this limit.', 'err');
        return;
      }
      msg('setMsg', 'Copying ' + f.name + ' from Drive…');
      state.uploading = true;
      return copyDriveFile(f).then(function (res) {
        state.drafts.push(res.draft);
        renderDrafts();
        state.uploading = false;
        $('mediaUrl').value = '';
        msg('setMsg', f.name + ' imported. Add copy below, then select Add to set.', 'ok');
      });
    }).catch(function (e) {
      state.uploading = false;
      if (e.name === 'AbortError') {
        msg('setMsg', 'Timed out reading that file from Drive.', 'err');
      } else if (/uploaded to s3|s3 rejected|could not start/i.test(e.message || '')) {
        // A storage problem, not a Drive one. Do not muddy it with sharing advice.
        msg('setMsg', e.message, 'err');
      } else {
        msg('setMsg', 'Could not read that file from Drive. ' + e.message +
          ' Check it is shared as Anyone with the link.', 'err');
      }
    });
  }

  // ---- Google Drive import -------------------------------------------------
  // Creative uploads to Drive, so the portal reads that folder directly rather
  // than making anyone download and re-upload. Files are copied into our own
  // storage once, so a client link never depends on a Drive folder staying put.
  var DRIVE_API = 'https://www.googleapis.com/drive/v3/files';
  var driveFiles = [];

  function driveKey() { return (cfg.googleApiKey || '').trim(); }

  function driveFileId(url) {
    var m = String(url).match(/\/file\/d\/([A-Za-z0-9_-]{10,})/) ||
            String(url).match(/[?&]id=([A-Za-z0-9_-]{10,})/);
    return m ? m[1] : null;
  }

  function isDriveLink(url) {
    return /^https?:\/\/(?:[a-z0-9-]+\.)*drive\.google\.com\//i.test(String(url).trim());
  }

  /* Reads bytes with progress, so a large video does not look like it has hung. */
  function fetchWithProgress(url, onProgress) {
    return driveFetch(url, 600000).then(function (r) {
      if (!r.ok) throw new Error('Drive refused the file (HTTP ' + r.status + ')');
      var total = Number(r.headers.get('content-length')) || 0;
      if (!r.body || !total) return r.blob();

      var reader = r.body.getReader();
      var chunks = [];
      var got = 0;
      return (function pump() {
        return reader.read().then(function (res) {
          if (res.done) return new Blob(chunks);
          chunks.push(res.value);
          got += res.value.length;
          if (onProgress) onProgress(got / total);
          return pump();
        });
      })();
    });
  }

  /* Pulls a Drive file into our own storage. If we have copied this Drive file
     before, reuse it: re-importing after a mistake should not upload again and
     pay for a second copy in S3. */
  function copyDriveFile(f, onProgress) {
    return db.from('drive_assets')
      .select('url, poster_url').eq('client_id', state.client.id).eq('drive_id', f.id).limit(1)
      .then(function (r) {
        var hit = (r.data || [])[0];
        if (hit && hit.url) {
          if (onProgress) onProgress(1);
          return { url: hit.url, reused: true, poster: hit.poster_url || null };
        }
        // A Drive import is two transfers, down from Google and up to storage,
        // so each leg gets half the bar rather than the bar sticking at full
        // while the upload is still running.
        var leg = function (base) {
          return onProgress ? function (frac) { onProgress(base + frac / 2); } : null;
        };
        return fetchWithProgress(
          DRIVE_API + '/' + f.id + '?alt=media&key=' + encodeURIComponent(driveKey()), leg(0))
          .then(function (blob) {
            // The bytes are already here, so the poster costs nothing extra.
            return probeBlob(blob, f.mimeType).then(function (shot) {
              f.poster = shot.poster;
              if (!f.width)  f.width = shot.width;
              if (!f.height) f.height = shot.height;
              return blob;
            });
          })
          .then(function (blob) {
            return storeBlob(blob, extFor(f.mimeType, f.name), f.mimeType, leg(0.5))
              .then(function (url) {
                // Remember it even if the post is later deleted.
                return storePoster(f.poster).then(function (posterUrl) {
                  db.from('drive_assets').insert({
                    client_id: state.client.id, drive_id: f.id, url: url,
                    mime_type: f.mimeType, width: f.width || null, height: f.height || null,
                    bytes: f.size || null, poster_url: posterUrl || null
                  }).then(function () {}, function () {});
                  return { url: url, reused: false, poster: posterUrl };
                });
              });
          });
      })
      .then(function (res) {
        // The caller adds it, so a batch import can keep the chosen order even
        // though the copies finish out of order.
        res.draft = {
          placement: guessPlacement({ width: f.width, height: f.height, isVideo: f.isVideo }),
          media: [{
            url: res.url,
            type: f.isVideo ? 'video' : 'image',
            width: f.width || null,
            height: f.height || null,
            mime: f.mimeType || null,
            poster: res.poster || null,
            driveId: f.id
          }],
          caption: '', caption_zh: '', title: '', showZh: false
        };
        return res;
      });
  }

  function driveMeta(id) {
    var fields = 'id,name,mimeType,size,imageMediaMetadata(width,height),' +
                 'videoMediaMetadata(width,height)';
    return driveFetch(DRIVE_API + '/' + id + '?key=' + encodeURIComponent(driveKey()) +
                      '&fields=' + encodeURIComponent(fields) + '&supportsAllDrives=true')
      .then(function (r) {
        return r.json().then(function (body) {
          if (r.status !== 200) {
            throw new Error((body.error && body.error.message) || ('Google returned ' + r.status));
          }
          var m = body.imageMediaMetadata || body.videoMediaMetadata || {};
          return {
            id: body.id, name: body.name || 'file', mimeType: body.mimeType || '',
            size: Number(body.size) || 0,
            width: m.width || 0, height: m.height || 0,
            isVideo: String(body.mimeType || '').indexOf('video') === 0
          };
        });
      });
  }

  function driveFolderId(url) {
    var m = String(url).match(/\/folders\/([A-Za-z0-9_-]{10,})/) ||
            String(url).match(/[?&]id=([A-Za-z0-9_-]{10,})/);
    return m ? m[1] : null;
  }

  function driveFetch(url, ms) {
    var ctrl = new AbortController();
    var timer = setTimeout(function () { ctrl.abort(); }, ms || 30000);
    return fetch(url, { signal: ctrl.signal }).finally(function () { clearTimeout(timer); });
  }

  /* Drive ids already used by this client, so last month's files are not
     imported a second time by accident. */
  function alreadyImported() {
    return db.from('batches').select('id').eq('client_id', state.client.id)
      .then(function (r) {
        var ids = (r.data || []).map(function (b) { return b.id; });
        if (!ids.length) return {};
        return db.from('posts').select('media').in('batch_id', ids).then(function (p) {
          var seen = {};
          (p.data || []).forEach(function (post) {
            (post.media || []).forEach(function (m) { if (m.driveId) seen[m.driveId] = true; });
          });
          return seen;
        });
      }).catch(function () { return {}; });
  }

  $('driveLoad').addEventListener('click', function () {
    var url = $('driveUrl').value.trim();
    var id = driveFolderId(url);
    if (!id) {
      msg('driveMsg', 'That does not look like a Drive folder link. It should have ' +
        '/folders/ followed by a long id.', 'err');
      return;
    }
    msg('driveMsg', 'Reading folder contents…');
    $('drivePicker').hidden = true;

    var fields = 'files(id,name,mimeType,size,imageMediaMetadata(width,height),' +
                 'videoMediaMetadata(width,height))';
    var q = encodeURIComponent("'" + id + "' in parents and trashed=false");
    var listUrl = DRIVE_API + '?q=' + q + '&key=' + encodeURIComponent(driveKey()) +
      '&fields=' + encodeURIComponent(fields) +
      '&pageSize=200&supportsAllDrives=true&includeItemsFromAllDrives=true';

    driveFetch(listUrl).then(function (r) {
      return r.json().then(function (body) { return { status: r.status, body: body }; });
    }).then(function (res) {
      if (res.status !== 200) {
        msg('driveMsg', (res.body.error && res.body.error.message) ||
          ('Google returned ' + res.status) +
          '. Check the folder is shared as Anyone with the link.', 'err');
        return;
      }
      var files = (res.body.files || []).filter(function (f) {
        return /^(image|video)\//.test(f.mimeType);
      });
      if (!files.length) {
        msg('driveMsg', 'That folder contains no images or videos.', 'err');
        return;
      }

      // remember the folder so next month is one click
      db.from('clients').update({ drive_folder: url }).eq('id', state.client.id)
        .then(function () { state.client.drive_folder = url; });

      return alreadyImported().then(function (seen) {
        driveFiles = files.map(function (f) {
          var m = f.imageMediaMetadata || f.videoMediaMetadata || {};
          return {
            id: f.id, name: f.name, mimeType: f.mimeType,
            size: Number(f.size) || 0,
            width: m.width || 0, height: m.height || 0,
            isVideo: f.mimeType.indexOf('video') === 0,
            done: Boolean(seen[f.id]),
            pick: !seen[f.id]
          };
        });
        renderDriveFiles();
        var fresh = driveFiles.filter(function (f) { return !f.done; }).length;
        msg('driveMsg', files.length + ' file' + (files.length === 1 ? '' : 's') + ' found, ' +
          fresh + ' not imported yet.', 'ok');
      });
    }).catch(function (e) {
      msg('driveMsg', e.name === 'AbortError'
        ? 'Timed out reading the folder.'
        : 'Could not reach Google. ' + e.message, 'err');
    });
  });

  function renderDriveFiles() {
    var box = $('driveFiles');
    box.innerHTML = '';
    $('drivePicker').hidden = false;

    driveFiles.forEach(function (f, i) {
      var card = document.createElement('label');
      card.className = 'dfile' + (f.done ? ' is-done' : '');
      card.innerHTML =
        '<input type="checkbox"' + (f.pick ? ' checked' : '') + (f.done ? ' disabled' : '') + '>' +
        '<span class="dfile-img"><img loading="lazy" alt=""></span>' +
        '<span class="dfile-meta"><b>' + esc(f.name) + '</b>' +
        '<span class="muted">' + (f.width ? f.width + ' x ' + f.height : 'size unknown') +
        (f.size ? ' · ' + mb(f.size) + ' MB' : '') +
        (f.done ? ' · already imported' : '') + '</span></span>';
      card.querySelector('img').src =
        'https://drive.google.com/thumbnail?id=' + f.id + '&sz=w400';
      card.querySelector('input').addEventListener('change', function (e) {
        driveFiles[i].pick = e.target.checked;
      });
      box.appendChild(card);
    });
  }

  $('driveAll').addEventListener('click', function () {
    driveFiles.forEach(function (f) { if (!f.done) f.pick = true; });
    renderDriveFiles();
  });
  $('driveNone').addEventListener('click', function () {
    driveFiles.forEach(function (f) { f.pick = false; });
    renderDriveFiles();
  });

  function showProgress(label, fraction) {
    var box = $('driveProgress');
    if (label === null) { box.hidden = true; return; }
    box.hidden = false;
    $('progressLabel').textContent = label;
    var pct = Math.max(0, Math.min(100, Math.round(fraction * 100)));
    $('progressPct').textContent = pct + '%';
    $('progressFill').style.width = pct + '%';
  }

  $('driveImport').addEventListener('click', function () {
    if (!state.batch) { msg('driveMsg', 'Select a content set first.', 'err'); return; }
    var picked = driveFiles.filter(function (f) { return f.pick && !f.done; });
    if (!picked.length) { msg('driveMsg', 'No assets selected.', 'err'); return; }

    var cap = usingS3() ? Infinity : (cfg.maxUploadMB || 50) * 1024 * 1024;
    var toobig = picked.filter(function (f) { return f.size > cap; });
    var queue = picked.filter(function (f) { return f.size <= cap; });

    if (toobig.length) {
      msg('driveMsg', toobig.length + ' file' + (toobig.length === 1 ? ' is' : 's are') +
        ' over the ' + (cfg.maxUploadMB || 50) + ' MB limit and were skipped: ' +
        toobig.map(function (f) { return f.name; }).join(', ') +
        '. Turning on S3 storage removes this limit.', 'err');
      if (!queue.length) return;
    }

    state.uploading = true;
    var done = 0;
    var reused = 0;
    var total = queue.reduce(function (n, f) { return n + (f.size || 0); }, 0);
    var moved = queue.map(function () { return 0; });
    showProgress('Preparing…', 0);

    function tick() {
      var n = moved.reduce(function (a, b) { return a + b; }, 0);
      showProgress('Importing ' + queue.length + ' file' + (queue.length === 1 ? '' : 's') +
        ' · ' + done + ' of ' + queue.length + ' complete', total ? n / total : 0);
    }

    runPool(queue, function (f, i) {
      return copyDriveFile(f, function (frac) {
        moved[i] = frac * (f.size || 0);
        tick();
      }).then(function (res) {
        if (res.reused) reused++;
        f.done = true; f.pick = false;
        moved[i] = f.size || 0;
        done++;
        tick();
        return res;
      });
    }, 3)
      .then(function (results) {
        state.uploading = false;
        showProgress(null);
        results.forEach(function (r) { state.drafts.push(r.draft); });
        renderDrafts();
        renderDriveFiles();
        if (!toobig.length) {
          msg('driveMsg', done + ' file' + (done === 1 ? '' : 's') + ' imported' +
            (reused ? ', ' + reused + ' reused from storage at no additional cost' : '') +
            '. Add copy below, then select Add to set.', 'ok');
        }
      })
      .catch(function (e) {
        state.uploading = false;
        showProgress(null);
        msg('driveMsg', e.name === 'AbortError'
          ? 'Timed out copying a file. Large videos can take a while, try fewer at a time.'
          : e.message, 'err');
      });
  });

  function renderDrafts() {
    saveDrafts();
    var box = $('drafts');
    box.innerHTML = '';
    $('draftActions').hidden = state.drafts.length === 0;
    $('draftZone').hidden = state.drafts.length === 0;

    var images = state.drafts.filter(function (d) { return d.media[0].type === 'image'; });
    var canCombine = state.drafts.length > 1 && images.length === state.drafts.length;
    $('combineBar').hidden = !canCombine;
    if (canCombine) {
      $('combineText').textContent =
        state.drafts.length + ' images uploaded. Are these separate posts, or slides of one carousel?';
    }

    state.drafts.forEach(function (d, i) {
      var isXhs = d.placement.indexOf('xhs') === 0;
      var row = document.createElement('div');
      row.className = 'draft';

      var opts = PLACEMENTS.map(function (p) {
        return '<option value="' + p[0] + '"' + (p[0] === d.placement ? ' selected' : '') + '>' +
          p[1] + '</option>';
      }).join('');

      row.innerHTML =
        '<div class="draft-media">' +
          d.media.map(function (m) {
            return m.type === 'video'
              ? '<video src="' + m.url + '" muted></video>'
              : '<img src="' + m.url + '" alt="">';
          }).join('') +
          (d.media.length > 1 ? '<i>' + d.media.length + ' slides</i>' : '') +
        '</div>' +
        '<div class="draft-body">' +
          '<div class="draft-top">' +
            '<select class="select" data-f="placement">' + opts + '</select>' +
            '<span class="filetag">' + esc(fileLabel(d.media[0])) + '</span>' +
            '<span class="muted">Change if wrong</span>' +
            '<button class="linkbtn" data-f="remove" type="button">Remove</button>' +
          '</div>' +
          (isXhs ? '<input class="input" data-f="title" placeholder="Note title 标题" value="' +
                   esc(d.title) + '">' : '') +
          '<textarea class="textarea" data-f="caption" placeholder="Caption. Lead with what the customer gains.">' +
            esc(d.caption) + '</textarea>' +
          (d.showZh
            ? '<textarea class="textarea" data-f="caption_zh" placeholder="中文文案">' + esc(d.caption_zh) + '</textarea>'
            : '<button class="linkbtn" data-f="addzh" type="button">+ Add Chinese caption</button>') +
        '</div>';

      if (d.media.length > 1) {
        var body = row.querySelector('.draft-body');
        var strip = slidesNode(d.media, function () { saveDrafts(); renderDrafts(); });
        var hint = el2('div', 'slide-hint');
        hint.textContent = d.placement === 'facebook:multi'
          ? 'Photo 1 takes the largest tile in the grid.'
          : 'Slide 1 is the cover and sets the shape of the whole carousel.';
        body.insertBefore(strip, body.children[1] || null);
        body.insertBefore(hint, strip.nextSibling);
      }

      row.querySelector('[data-f="placement"]').addEventListener('change', function (e) {
        d.placement = e.target.value; renderDrafts();
      });
      row.querySelector('[data-f="remove"]').addEventListener('click', function () {
        state.drafts.splice(i, 1); renderDrafts();
      });
      var cap = row.querySelector('[data-f="caption"]');
      cap.addEventListener('input', function (e) { d.caption = e.target.value; queueSave(); });
      var zh = row.querySelector('[data-f="caption_zh"]');
      if (zh) zh.addEventListener('input', function (e) { d.caption_zh = e.target.value; queueSave(); });
      var addzh = row.querySelector('[data-f="addzh"]');
      if (addzh) addzh.addEventListener('click', function () { d.showZh = true; renderDrafts(); });
      var title = row.querySelector('[data-f="title"]');
      if (title) title.addEventListener('input', function (e) { d.title = e.target.value; queueSave(); });

      box.appendChild(row);
    });
  }

  $('combineBtn').addEventListener('click', function () {
    var merged = {
      placement: 'instagram:carousel',
      media: state.drafts.reduce(function (all, d) { return all.concat(d.media); }, []),
      caption: state.drafts.map(function (d) { return d.caption; }).filter(Boolean)[0] || '',
      caption_zh: '', title: '', showZh: false
    };
    state.drafts = [merged];
    renderDrafts();
  });

  $('clearDrafts').addEventListener('click', function () {
    if (state.drafts.length && !confirm('Discard these uploads?')) return;
    clearDrafts();
  });

  var saveTimer = null;
  function queueSave() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(saveDrafts, 400);   // typing should not hit storage on every key
  }

  function clearDrafts() {
    state.drafts = [];
    try { localStorage.removeItem(draftKey()); } catch (e) {}
    renderDrafts();
    msg('setMsg', '');
    if (state.batch) paintSetHeader();
  }

  $('saveDrafts').addEventListener('click', function () {
    if (!state.drafts.length) return;

    db.from('posts').select('position').eq('batch_id', state.batch.id)
      .order('position', { ascending: false }).limit(1).then(function (r) {
        var next = (r.data && r.data.length ? r.data[0].position : -1) + 1;
        var rows = state.drafts.map(function (d, i) {
          var parts = d.placement.split(':');
          return {
            batch_id: state.batch.id,
            platform: parts[0], format: parts[1],
            handle: null,   // the client's per platform account name is used instead
            title: d.title || null,
            caption: d.caption || null,
            caption_zh: d.caption_zh || null,
            media: d.media,
            position: next + i
          };
        });
        db.from('posts').insert(rows).then(function (res) {
          if (res.error) { msg('setMsg', res.error.message, 'err'); return; }
          clearDrafts();
          msg('setMsg', rows.length + ' post' + (rows.length === 1 ? '' : 's') + ' added.', 'ok');
          loadPosts();
          loadBatches();
        });
      });
  });

  // ---- Saved posts --------------------------------------------------------
  /* Once a post is in the set it is shown as settled rather than as a form.
     Editing is deliberate, so a stray click cannot change what a client sees. */
  function loadPosts() {
    db.from('posts').select('*').eq('batch_id', state.batch.id).order('position')
      .then(function (r) {
        var box = $('postList');
        box.innerHTML = '';
        var n = (r.data || []).length;
        $('savedCount').textContent = n
          ? n + ' post' + (n === 1 ? '' : 's') + ' in this set.'
          : 'Nothing added yet.';
        if (r.error || !n) { settleScroll(); return; }

        var ids = r.data.map(function (p) { return p.id; });
        db.from('reviews').select('post_id, decision, note, reviewer, created_at')
          .in('post_id', ids).order('created_at', { ascending: false })
          .then(function (rev) {
            var latest = {};
            (rev.data || []).forEach(function (x) { if (!latest[x.post_id]) latest[x.post_id] = x; });
            r.data.forEach(function (p) { box.appendChild(savedRow(p, latest[p.id])); });
            settleScroll();
          });
      });
  }

  function savedRow(p, review) {
    var row = document.createElement('div');
    row.className = 'saved';
    var m = (p.media || [])[0] || {};

    function paintRead() {
      row.classList.remove('is-editing');
      row.innerHTML =
        '<div class="saved-thumb">' +
          (m.type === 'video'
            ? '<video src="' + m.url + '" muted></video>'
            : '<img src="' + (m.url || '') + '" alt="">') + '</div>' +
        '<div class="saved-body">' +
          '<b>' + MK.label(p) + '</b>' +
          '<span class="filetag">' + esc(fileLabel(m)) + '</span>' +
          '<span class="muted">' + esc((p.caption || p.caption_zh || 'No caption').slice(0, 90)) + '</span>' +
          (review && review.decision === 'changes' && review.note
            ? '<span class="saved-note">' + esc(review.note) + '</span>' : '') +
        '</div>' +
        '<span class="badge ' + (review
            ? (review.decision === 'approved' ? 'is-ok' : 'is-changes') : '') + '">' +
          (review ? (review.decision === 'approved' ? 'Approved' : 'Changes') : 'Pending') +
        '</span>' +
        (p.review_reset_note
          ? '<span class="saved-note is-warn">Sent back: ' + esc(p.review_reset_note) + '</span>'
          : '') +
        (review && review.decision === 'approved'
          ? '<button class="btn btn-warn btn-sm" data-a="reask" type="button">Request re-approval</button>'
          : '') +
        '<button class="btn btn-sm" data-a="edit" type="button">Edit</button>' +
        '<button class="btn btn-quiet btn-sm is-danger" data-a="del" type="button">Delete</button>';

      row.querySelector('[data-a="edit"]').addEventListener('click', paintEdit);

      var reask = row.querySelector('[data-a="reask"]');
      if (reask) reask.addEventListener('click', function () {
        var why = (window.prompt(
          'Reason for requesting re-approval. This note will be shown to the client.\n\n' +
          'For example: pricing corrected, logo updated, copy revised.') || '').trim();
        if (!why) return;
        db.from('posts').update({
          review_reset_at: new Date().toISOString(),
          review_reset_note: why
        }).eq('id', p.id).then(function (r) {
          if (r.error) { msg('setMsg', r.error.message, 'err'); return; }
          logAction('reapproval.requested',
            state.client.name + ' — ' + MK.label(p), why);
          msg('setMsg', 'Re-approval requested. The client now sees this post as pending, ' +
            'together with your note.', 'ok');
          loadPosts();
        });
      });
      row.querySelector('[data-a="del"]').addEventListener('click', function () {
        if (!confirm('Delete this post? It will be removed from the client view.\n\n' +
          'The file remains in storage, so re-importing it from Drive will not upload again.')) return;
        db.from('posts').delete().eq('id', p.id).then(function () {
          logAction('post.deleted',
            state.client.name + ' — ' + state.batch.title, MK.label(p));
          loadPosts(); loadBatches();
        });
      });
    }

    var editMedia = null;

    function paintEdit() {
      row.classList.add('is-editing');
      var current = (p.platform || 'instagram') + ':' + (p.format || 'feed');
      var opts = PLACEMENTS.map(function (o) {
        return '<option value="' + o[0] + '"' + (o[0] === current ? ' selected' : '') + '>' +
          o[1] + '</option>';
      }).join('');

      row.innerHTML =
        '<div class="saved-thumb">' +
          (m.type === 'video'
            ? '<video src="' + m.url + '" muted></video>'
            : '<img src="' + (m.url || '') + '" alt="">') + '</div>' +
        '<div class="saved-body">' +
          '<div class="draft-top">' +
            '<select class="select" data-f="placement">' + opts + '</select>' +
            '<span class="filetag">' + esc(fileLabel(m)) + '</span>' +
          '</div>' +
          (current.indexOf('xhs') === 0
            ? '<input class="input" data-f="title" placeholder="Note title 标题" value="' +
              esc(p.title || '') + '">' : '') +
          '<textarea class="textarea" data-f="caption" placeholder="Caption">' +
            esc(p.caption || '') + '</textarea>' +
          '<textarea class="textarea" data-f="caption_zh" placeholder="中文文案">' +
            esc(p.caption_zh || '') + '</textarea>' +
          '<div class="changebox-actions">' +
            '<button class="btn btn-sm" data-a="cancel" type="button">Cancel</button>' +
            '<button class="btn btn-primary btn-sm" data-a="save" type="button">Save changes</button>' +
          '</div>' +
        '</div>';

      var mediaCopy = editMedia || JSON.parse(JSON.stringify(p.media || []));
      editMedia = mediaCopy;
      if (mediaCopy.length > 1) {
        var sbody = row.querySelector('.saved-body');
        var sstrip = slidesNode(mediaCopy, function () { paintEdit(); });
        sbody.insertBefore(sstrip, sbody.children[1] || null);
      }

      row.querySelector('[data-a="cancel"]').addEventListener('click', function () {
        editMedia = null;
        paintRead();
      });
      row.querySelector('[data-a="save"]').addEventListener('click', function () {
        var parts = row.querySelector('[data-f="placement"]').value.split(':');
        var titleEl = row.querySelector('[data-f="title"]');
        var patch = {
          platform: parts[0],
          format: parts[1],
          title: titleEl ? (titleEl.value.trim() || null) : p.title,
          caption: row.querySelector('[data-f="caption"]').value || null,
          caption_zh: row.querySelector('[data-f="caption_zh"]').value || null,
          media: mediaCopy
        };
        db.from('posts').update(patch).eq('id', p.id).then(function (res) {
          if (res.error) { msg('setMsg', res.error.message, 'err'); return; }
          Object.keys(patch).forEach(function (k) { p[k] = patch[k]; });
          m = (p.media || [])[0] || {};
          editMedia = null;
          paintRead();
          msg('setMsg', 'Post updated.', 'ok');
        });
      });
    }

    paintRead();
    return row;
  }
})();
