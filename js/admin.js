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
    logo.onerror = function () {
      logo.hidden = true;
      $('agencyWordmark').hidden = false;
    };
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
    ['facebook:story',     'Facebook Story'],
    ['tiktok:reel',        'TikTok video'],
    ['xhs:note',           'XiaoHongShu note']
  ];

  var state = { client: null, batch: null, drafts: [], lastDropCount: 0 };

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
      msg('authMsg', r.error ? r.error.message : 'Check your inbox for the sign in link.',
          r.error ? 'err' : 'ok');
    });
  });
  $('signOut').addEventListener('click', function () {
    db.auth.signOut().then(function () { location.reload(); });
  });
  db.auth.getSession().then(function (r) { gate(r.data.session); });
  db.auth.onAuthStateChange(function (_e, session) { gate(session); });

  function gate(session) {
    var inApp = Boolean(session);
    $('authPanel').hidden = inApp;
    $('signOut').hidden = !inApp;
    $('whoami').textContent = inApp ? session.user.email : '';
    if (inApp) showClients(); else { $('clientsView').hidden = true; $('workspace').hidden = true; }
  }

  // ---- Clients ------------------------------------------------------------
  function showClients() {
    $('clientsView').hidden = false;
    $('workspace').hidden = true;
    state.client = null; state.batch = null;
    loadClients();
  }

  function loadClients() {
    db.from('clients').select('*').order('name').then(function (r) {
      var box = $('clientCards');
      box.innerHTML = '';
      if (r.error) { msg('clientMsg', r.error.message, 'err'); return; }
      if (!r.data.length) {
        box.innerHTML = '<div class="empty">No clients yet. Add your first one above.</div>';
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
          if (b.error || !b.data.length) { sub.textContent = 'No content sets yet'; return; }
          var live = b.data.filter(function (x) { return x.published; }).length;
          sub.textContent = b.data.length + ' set' + (b.data.length === 1 ? '' : 's') +
            ' · ' + live + ' sent to client';
        });
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
    if (!name) { msg('clientMsg', 'Please enter the client name.', 'err'); return; }
    db.from('clients').insert({
      name: name,
      logo_url: $('newClientLogo').value.trim() || null,
      passcode: $('newClientPass').value.trim() || null,
      access_token: makeToken()
    }).select().single().then(function (r) {
      if (r.error) { msg('clientMsg', r.error.message, 'err'); return; }
      ['newClientName','newClientLogo','newClientPass'].forEach(function (i) { $(i).value = ''; });
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
    $('waShare').href = 'https://wa.me/?text=' + encodeURIComponent(
      'Hi ' + c.name + ', your content is ready for review. You can approve each post or ' +
      'tell us what to change here: ' + url);
    loadBatches();
    window.scrollTo(0, 0);
  }

  $('backToClients').addEventListener('click', showClients);

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
              (b.published ? 'Sent to client' : 'Draft, client cannot see it') + '</span>';
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
    var title = (window.prompt('Name this content set:', thisMonth()) || '').trim();
    if (!title) return;
    db.from('batches').insert({
      client_id: state.client.id, title: title, published: false
    }).select().single().then(function (r) {
      if (r.error) return;
      loadBatches();
      openBatch(r.data);
    });
  });

  function openBatch(b) {
    state.batch = b;
    clearDrafts();
    $('setPanel').hidden = false;
    paintSetHeader();
    loadBatches();
    loadPosts();
    $('setPanel').scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  function paintSetHeader() {
    $('setTitle').textContent = state.batch.title;
    $('publishSet').textContent = state.batch.published ? 'Hide from client' : 'Send to client';
    $('publishSet').className = state.batch.published ? 'btn' : 'btn btn-primary';
    msg('setMsg', state.batch.published
      ? 'This set is live. The client sees it on their link.'
      : 'Draft. Nothing here is visible to the client yet.',
      state.batch.published ? 'ok' : '');
  }

  $('publishSet').addEventListener('click', function () {
    var next = !state.batch.published;
    if (!next) { setPublished(false); return; }

    // Sending is the commitment, so this is where a missing caption is worth flagging.
    db.from('posts').select('caption, caption_zh').eq('batch_id', state.batch.id).then(function (r) {
      var posts = r.data || [];
      if (!posts.length) { msg('setMsg', 'Add at least one post before sending.', 'err'); return; }
      var blank = posts.filter(function (p) { return !p.caption && !p.caption_zh; }).length;
      var warn = blank
        ? '\n\n' + blank + ' of ' + posts.length + ' posts ' + (blank === 1 ? 'has' : 'have') +
          ' no caption yet.'
        : '';
      if (!confirm('Send ' + posts.length + ' post' + (posts.length === 1 ? '' : 's') + ' to ' +
                   state.client.name + '? They will see it immediately.' + warn)) return;
      setPublished(true);
    });
  });

  function setPublished(next) {
    db.from('batches').update({ published: next }).eq('id', state.batch.id).then(function (r) {
      if (r.error) { msg('setMsg', r.error.message, 'err'); return; }
      state.batch.published = next;
      paintSetHeader();
      loadBatches();
    });
  }

  $('renameSet').addEventListener('click', function () {
    var title = (window.prompt('Rename this set:', state.batch.title) || '').trim();
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
    return new Promise(function (resolve) {
      var url = URL.createObjectURL(file);
      var isVideo = file.type.indexOf('video') === 0;
      var node = document.createElement(isVideo ? 'video' : 'img');
      var done = function (w, h) {
        URL.revokeObjectURL(url);
        resolve({ width: w || 0, height: h || 0, isVideo: isVideo });
      };
      if (isVideo) {
        node.preload = 'metadata';
        node.onloadedmetadata = function () { done(node.videoWidth, node.videoHeight); };
      } else {
        node.onload = function () { done(node.naturalWidth, node.naturalHeight); };
      }
      node.onerror = function () { done(0, 0); };
      node.src = url;
    });
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
    if (!state.batch) { msg('setMsg', 'Open a content set first.', 'err'); return; }

    var cap = (cfg.maxUploadMB || 50) * 1024 * 1024;
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
    var done = 0;
    if (!toobig.length) {
      msg('setMsg', 'Uploading ' + queue.length + ' file' + (queue.length === 1 ? '' : 's') + '…');
    }

    queue.reduce(function (chain, file) {
      return chain.then(function () {
        return probe(file).then(function (info) {
          var ext  = (file.name.split('.').pop() || 'bin').toLowerCase();
          var path = state.client.id + '/' + crypto.randomUUID() + '.' + ext;
          return db.storage.from(cfg.storageBucket)
            .upload(path, file, { cacheControl: '31536000' })
            .then(function (r) {
              if (r.error) throw r.error;
              var pub = db.storage.from(cfg.storageBucket).getPublicUrl(path).data.publicUrl;
              pushDraft(pub, info);
              done++;
              if (!toobig.length) msg('setMsg', 'Uploaded ' + done + ' of ' + queue.length + '…');
            });
        });
      });
    }, Promise.resolve())
      .then(function () {
        if (!toobig.length) {
          msg('setMsg', 'Ready. Add captions below, then click "Add to this set".', 'ok');
        }
        renderDrafts();
      })
      .catch(function (e) {
        var text = e.message || 'Upload failed.';
        if (/payload|too large|exceeded/i.test(text)) {
          text = 'That file is over the ' + (cfg.maxUploadMB || 50) +
            ' MB storage limit. Export a smaller review copy, or paste a link instead.';
        }
        msg('setMsg', text, 'err');
      });
  }

  function mb(bytes) { return (bytes / 1024 / 1024).toFixed(0); }

  function pushDraft(url, info) {
    state.drafts.push({
      placement: guessPlacement(info),
      media: [{ url: url, type: info.isVideo ? 'video' : 'image' }],
      caption: '', caption_zh: '', title: '', showZh: false
    });
    renderDrafts();
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
        finish({ width: v.videoWidth, height: v.videoHeight, isVideo: true, ok: v.videoWidth > 0 });
      };
      v.onerror = function () {
        var i = new Image();
        i.onload = function () {
          finish({ width: i.naturalWidth, height: i.naturalHeight, isVideo: false, ok: true });
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
    if (!state.batch) { msg('setMsg', 'Open a content set first.', 'err'); return; }
    if (!/^https:\/\//i.test(url)) {
      msg('setMsg', 'The link needs to start with https://', 'err');
      return;
    }
    msg('setMsg', 'Checking the link…');
    probeUrl(url).then(function (info) {
      if (!info.ok) {
        msg('setMsg', 'We could not load that link. It has to point straight at the file, ' +
          'the way https://mycdn.adspace.me/reel.mp4 does. A Google Drive or Dropbox ' +
          'share page will not work because it returns a web page, not the video.', 'err');
        return;
      }
      pushDraft(url, info);
      $('mediaUrl').value = '';
      msg('setMsg', 'Added. Write the caption below, then click "Add to this set".', 'ok');
    });
  });

  // ---- Drafts -------------------------------------------------------------
  function renderDrafts() {
    var box = $('drafts');
    box.innerHTML = '';
    $('draftActions').hidden = state.drafts.length === 0;

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
            '<span class="muted">Detected automatically, change it if we guessed wrong</span>' +
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

      row.querySelector('[data-f="placement"]').addEventListener('change', function (e) {
        d.placement = e.target.value; renderDrafts();
      });
      row.querySelector('[data-f="remove"]').addEventListener('click', function () {
        state.drafts.splice(i, 1); renderDrafts();
      });
      var cap = row.querySelector('[data-f="caption"]');
      cap.addEventListener('input', function (e) { d.caption = e.target.value; });
      var zh = row.querySelector('[data-f="caption_zh"]');
      if (zh) zh.addEventListener('input', function (e) { d.caption_zh = e.target.value; });
      var addzh = row.querySelector('[data-f="addzh"]');
      if (addzh) addzh.addEventListener('click', function () { d.showZh = true; renderDrafts(); });
      var title = row.querySelector('[data-f="title"]');
      if (title) title.addEventListener('input', function (e) { d.title = e.target.value; });

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

  function clearDrafts() {
    state.drafts = [];
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
            handle: state.client.name,
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
  function loadPosts() {
    db.from('posts').select('*').eq('batch_id', state.batch.id).order('position')
      .then(function (r) {
        var box = $('postList');
        box.innerHTML = '';
        $('savedLabel').hidden = !(r.data && r.data.length);
        if (r.error || !r.data.length) return;

        var ids = r.data.map(function (p) { return p.id; });
        db.from('reviews').select('post_id, decision, note, reviewer, created_at')
          .in('post_id', ids).order('created_at', { ascending: false })
          .then(function (rev) {
            var latest = {};
            (rev.data || []).forEach(function (x) { if (!latest[x.post_id]) latest[x.post_id] = x; });

            r.data.forEach(function (p) {
              var review = latest[p.id];
              var row = document.createElement('div');
              row.className = 'saved';
              var m = (p.media || [])[0] || {};
              row.innerHTML =
                '<div class="saved-thumb">' +
                  (m.type === 'video'
                    ? '<video src="' + m.url + '" muted></video>'
                    : '<img src="' + (m.url || '') + '" alt="">') + '</div>' +
                '<div class="saved-body">' +
                  '<b>' + MK.label(p) + '</b>' +
                  '<span class="muted">' + esc((p.caption || p.caption_zh || 'No caption').slice(0, 90)) + '</span>' +
                  (review && review.decision === 'changes' && review.note
                    ? '<span class="saved-note">' + esc(review.note) + '</span>' : '') +
                '</div>' +
                '<span class="badge ' + (review
                    ? (review.decision === 'approved' ? 'is-ok' : 'is-changes') : '') + '">' +
                  (review ? (review.decision === 'approved' ? 'Approved' : 'Changes') : 'Pending') +
                '</span>' +
                '<button class="linkbtn" type="button">Delete</button>';
              row.querySelector('button').addEventListener('click', function () {
                if (!confirm('Delete this post? The client will no longer see it.')) return;
                db.from('posts').delete().eq('id', p.id).then(function () {
                  loadPosts(); loadBatches();
                });
              });
              box.appendChild(row);
            });
          });
      });
  }
})();
