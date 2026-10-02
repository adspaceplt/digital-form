/* The Handbook: the company's internal files in one section.
 *
 * The Employee Handbook, SOPs, policies, templates and forms, a card per
 * category (`js/group.js`). Every colleague reads them; only an admin adds a
 * file, edits its details, uploads a new version, archives or deletes it (the
 * user, 2026-10-01: "Admins only"; no read-and-accept step).
 *
 * The files are private. They sit in the Supabase Storage bucket `handbook`,
 * which is never public and never behind the CDN, and they are opened only
 * through a signed link that lasts 60 seconds, made at the press: a link
 * copied out of the address bar stops working a minute later, and nobody who
 * is not a signed-in colleague can make one (the bucket's read policy asks
 * `is_team()`). A document can be an outside link instead (a Google Doc kept
 * as the working copy), opened as it is.
 *
 * A file is never overwritten. New version uploads a new object and a new
 * row, and every earlier version stays readable under Versions. Archive hides
 * a file from everybody but an admin and Restore brings it back; Delete takes
 * the title typed back, removes the rows and then the files.
 */
(function () {
  'use strict';
  var API = window.ADspaceAPI;
  var db = API && API.client;
  if (!API || !API.configured || !db) return;
  var bridge = window.ADspaceAdmin || {};
  var $ = function (id) { return document.getElementById(id); };

  var BUCKET = 'handbook';
  var SIGN_SECS = 60;
  var MAX_BYTES = 50 * 1024 * 1024;
  var CATS = [['handbook', 'Employee Handbook'], ['sop', 'SOPs'], ['policy', 'Policies'],
              ['template', 'Templates and forms'], ['other', 'Other']];
  var CAT_WORD = {};
  CATS.forEach(function (c) { CAT_WORD[c[0]] = c[1]; });
  var MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
  var DOTS = '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="5" cy="12" r="1.6" fill="currentColor"/><circle cx="12" cy="12" r="1.6" fill="currentColor"/><circle cx="19" cy="12" r="1.6" fill="currentColor"/></svg>';
  var OUT = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 4h6v6"/><path d="M20 4 11 13"/><path d="M19 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1h5"/></svg>';

  var st = { docs: [], vers: {}, loaded: false, editing: null, verFor: null };

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function day(iso) {
    if (!iso) return '';
    var d = new Date(iso);
    return isNaN(d) ? '' : d.getDate() + ' ' + MON[d.getMonth()] + ' ' + d.getFullYear();
  }
  function size(n) {
    n = Number(n) || 0;
    if (n >= 1048576) return (n / 1048576).toFixed(1) + ' MB';
    if (n >= 1024) return Math.round(n / 1024) + ' KB';
    return n ? n + ' bytes' : '';
  }
  function isAdmin() {
    var m = bridge.me && bridge.me();
    return Boolean(m && (m.is_admin || m.role === 'admin'));
  }
  function say(el, text, tone) {
    if (!el) return;
    el.textContent = text || '';
    el.className = 'msg' + (text ? ' ' + (tone || 'err') : '');
  }
  function uuid() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    var b = new Uint8Array(16);
    crypto.getRandomValues(b);
    b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128;
    var h = Array.prototype.map.call(b, function (x) { return (x + 256).toString(16).slice(1); }).join('');
    return h.slice(0, 8) + '-' + h.slice(8, 12) + '-' + h.slice(12, 16) + '-' + h.slice(16, 20) + '-' + h.slice(20);
  }
  function whoName(email) { return bridge.whoName ? bridge.whoName(email) : (email || ''); }

  /* A refusal in the team's words. */
  var SAID = {
    denied: 'Only an admin changes the Handbook.',
    'no-title': 'A title is required.',
    'bad-category': 'Choose a category.',
    'bad-link': 'A link starts with https://.',
    'bad-path': 'The file was not stored where the Handbook keeps it.',
    'no-file': 'Choose a file.',
    'not-found': 'This file is no longer in the Handbook.',
    mismatch: 'The title does not match.'
  };
  function said(e) {
    var m = String((e && (e.message || e.error)) || e || '');
    if (SAID[m]) return SAID[m];
    if (/function .* does not exist|schema cache|relation .*handbook/i.test(m)) return 'This needs a database update.';
    if (/bucket not found/i.test(m)) return 'This needs a database update.';
    if (/payload too large|exceeded the maximum allowed size|413/i.test(m)) return 'A file is 50 MB at most.';
    if (/row-level security|new row violates/i.test(m)) return SAID.denied;
    return m || 'Not saved. Try again.';
  }
  function rpc(name, args) {
    return db.rpc(name, args).then(function (r) {
      if (r.error) throw r.error;
      var d = r.data || {};
      if (d.error) throw new Error(d.error);
      return d;
    });
  }

  /* ---- Reading ------------------------------------------------------------ */
  function load() {
    var box = $('hbList');
    if (!st.loaded && window.ADspaceState) window.ADspaceState.skeleton(box, 4);
    return Promise.all([
      db.from('handbook_docs').select('id, title, category, summary, link_url, current_version, archived_at, created_at, updated_at').order('title'),
      db.from('handbook_versions').select('id, doc_id, version_no, file_path, file_name, file_size, mime, note, created_at, created_by').order('version_no', { ascending: false })
    ]).then(function (res) {
      if (res[0].error) throw res[0].error;
      if (res[1].error) throw res[1].error;
      st.docs = res[0].data || [];
      st.vers = {};
      (res[1].data || []).forEach(function (v) { (st.vers[v.doc_id] = st.vers[v.doc_id] || []).push(v); });
      st.loaded = true;
      paint();
    }).catch(function (e) {
      if (window.ADspaceState) window.ADspaceState.failLine(box, 'The Handbook', said(e), load);
    });
  }

  function shown() {
    var q = ($('hbFind').value || '').trim().toLowerCase();
    var cat = $('hbCat').value || '';
    return st.docs.filter(function (d) {
      if (cat && d.category !== cat) return false;
      if (!q) return true;
      var v = (st.vers[d.id] || [])[0];
      return (d.title + ' ' + (d.summary || '') + ' ' + (v ? v.file_name : '')).toLowerCase().indexOf(q) > -1;
    });
  }

  /* ---- Drawing ------------------------------------------------------------ */
  function paint() {
    var box = $('hbList');
    var admin = isAdmin();
    $('hbAdd').hidden = !admin;
    var live = st.docs.filter(function (d) { return admin || !d.archived_at; });
    var list = shown().filter(function (d) { return admin || !d.archived_at; });
    var filtered = list.length !== live.length;
    var nLive = live.filter(function (d) { return !d.archived_at; }).length;
    $('hbCount').textContent = !live.length ? '' :
      filtered ? list.length + ' of ' + live.length : nLive + (nLive === 1 ? ' file' : ' files');
    box.innerHTML = '';
    if (!live.length) {
      window.ADspaceState.emptyLine(box, 'No files.', admin ? 'Add file' : '', function () { openSheet(null, $('hbAdd')); });
      return;
    }
    if (!list.length) {
      window.ADspaceState.emptyLine(box, 'No matches.', 'Clear the filters', function () {
        $('hbFind').value = ''; $('hbCat').value = '';
        $('hbCat').dispatchEvent(new Event('change', { bubbles: true }));
        paint();
      });
      return;
    }
    var GRP = window.ADspaceGroup;
    var groups = CATS.map(function (c) {
      return [c[0], c[1], list.filter(function (d) { return !d.archived_at && d.category === c[0]; }), false];
    });
    groups.push(['archived', 'Archived', list.filter(function (d) { return d.archived_at; }), true]);
    groups.forEach(function (g) {
      if (!g[2].length) return;
      box.appendChild(GRP.section({
        route: 'handbook', key: g[0], name: g[1], count: g[2].length,
        shut: !filtered && GRP.shut('handbook', g[0], g[3], g[2].length === list.length),
        table: function () {
          var table = GRP.table('hb-row', ['File', 'Version', 'Updated', '']);
          GRP.more(table, g[2], 30, 'files', rowOf);
          return table;
        }
      }));
    });
  }

  function rowOf(d) {
    var admin = isAdmin();
    var vers = st.vers[d.id] || [];
    var v = vers[0];
    var row = document.createElement('div');
    row.className = 'hb-row' + (d.archived_at ? ' is-off' : '');
    row.setAttribute('data-doc', d.id);
    var meta = d.link_url ? 'Link' : v ? v.file_name + (v.file_size ? ' · ' + size(v.file_size) : '') : 'No file yet';
    var items = '';
    if (vers.length) items += '<button class="kmenu-item" data-a="vers" type="button"><b>Versions</b></button>';
    if (admin) {
      items += '<button class="kmenu-item" data-a="edit" type="button"><b>Edit</b></button>';
      if (!d.link_url) items += '<button class="kmenu-item" data-a="newver" type="button"><b>New version</b></button>';
      items += d.archived_at
        ? '<button class="kmenu-item" data-a="restore" type="button"><b>Restore</b></button>'
        : '<button class="kmenu-item" data-a="archive" type="button"><b>Archive</b></button>';
      items += '<button class="kmenu-item is-danger" data-a="del" type="button"><b>Delete</b></button>';
    }
    var canOpen = Boolean(d.link_url || v);
    row.innerHTML =
      '<span class="hb-name"><b>' + esc(d.title) + '</b>' +
        '<small>' + esc(d.summary ? d.summary : meta) + '</small></span>' +
      '<span class="hb-ver">' + (d.link_url ? 'Link' : v ? 'v' + v.version_no : '<span class="mute">—</span>') + '</span>' +
      '<span class="hb-when">' + esc(day(d.updated_at)) + '</span>' +
      '<span class="hb-act">' +
        (canOpen ? '<button class="btn btn-sm btn-icon" data-a="open" type="button" aria-label="Open ' + esc(d.title) + '">Open ' + OUT + '</button>' : '') +
        (items ? '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
          '<div class="kmenu" data-menu hidden>' + items + '</div>' : '') +
      '</span>';
    var on = function (a, fn) { var b = row.querySelector('[data-a="' + a + '"]'); if (b) b.addEventListener('click', fn); };
    on('open', function (e) { openDoc(d, e.currentTarget); });
    on('vers', function () { shutMenus(); openVersions(d); });
    on('edit', function () { shutMenus(); openSheet(d, row.querySelector('[data-a="menu"]')); });
    on('newver', function () { shutMenus(); openVersion(d, row.querySelector('[data-a="menu"]')); });
    on('archive', function () { shutMenus(); archive(d, true); });
    on('restore', function () { shutMenus(); archive(d, false); });
    on('del', function () { shutMenus(); remove(d); });
    var mb = row.querySelector('[data-a="menu"]');
    if (mb) {
      var menu = row.querySelector('[data-menu]');
      mb.addEventListener('click', function (e) {
        e.stopPropagation();
        var open = menu.hidden;
        shutMenus();
        menu.hidden = !open;
        mb.setAttribute('aria-expanded', String(open));
        if (open) window.ADspaceMenu.place(mb, menu);
      });
    }
    return row;
  }
  function shutMenus() {
    Array.prototype.forEach.call(document.querySelectorAll('#hbList .kmenu'), function (m) { m.hidden = true; });
    Array.prototype.forEach.call(document.querySelectorAll('#hbList .kmenu-btn'), function (b) { b.setAttribute('aria-expanded', 'false'); });
  }
  document.addEventListener('click', function (e) {
    if (!e.target.closest || !e.target.closest('#hbList .kmenu, #hbList .kmenu-btn')) shutMenus();
  });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') shutMenus(); });
  if (window.ADspaceMenu) window.ADspaceMenu.onScroll(shutMenus);

  /* ---- Opening: a signed link of a minute, made at the press -------------- */
  function openDoc(d, btn) {
    if (d.link_url) { window.open(d.link_url, '_blank', 'noopener'); return; }
    var v = (st.vers[d.id] || [])[0];
    if (v) openFile(v, btn, $('hbListMsg'));
  }
  function openFile(v, btn, m) {
    /* The tab is opened now, while the press still counts as the person's,
       or a browser blocks a window opened after the link comes back. */
    var w = window.open('', '_blank');
    if (btn) btn.disabled = true;
    say(m, '');
    db.storage.from(BUCKET).createSignedUrl(v.file_path, SIGN_SECS).then(function (r) {
      if (btn) btn.disabled = false;
      var url = r && r.data && (r.data.signedUrl || r.data.signedURL);
      if (r.error || !url) throw r.error || new Error('The file could not be opened.');
      if (w) { try { w.opener = null; } catch (e) { /* cross-origin */ } w.location.href = url; }
      else location.href = url;
    }).catch(function (e) {
      if (btn) btn.disabled = false;
      if (w) w.close();
      say(m, 'Not opened. ' + said(e), 'err');
    });
  }

  /* ---- Versions ------------------------------------------------------------ */
  function openVersions(d) {
    var vers = st.vers[d.id] || [];
    $('hbHistTitle').textContent = d.title;
    var box = $('hbHistList');
    box.innerHTML = '<div class="msg" id="hbHistMsg"></div>' + vers.map(function (v, i) {
      return '<div class="hb-verrow">' +
        '<span class="hb-name"><b>Version ' + v.version_no + (i === 0 ? ' <span class="tone">Current</span>' : '') + '</b>' +
          '<small>' + esc([day(v.created_at), whoName(v.created_by), v.file_name, size(v.file_size)].filter(Boolean).join(' · ')) + '</small>' +
          (v.note ? '<small class="hb-note">' + esc(v.note) + '</small>' : '') + '</span>' +
        '<button class="btn btn-sm btn-icon" data-v="' + esc(v.id) + '" type="button" aria-label="Open version ' + v.version_no + '">Open ' + OUT + '</button>' +
      '</div>';
    }).join('');
    Array.prototype.forEach.call(box.querySelectorAll('[data-v]'), function (b) {
      b.addEventListener('click', function () {
        var v = vers.filter(function (x) { return x.id === b.getAttribute('data-v'); })[0];
        if (v) openFile(v, b, $('hbHistMsg'));
      });
    });
    window.ADspaceSheet.show($('hbHistSheet'), {});
  }
  $('hbHistClose').addEventListener('click', function () { window.ADspaceSheet.close(); });

  /* ---- Storing a file ------------------------------------------------------ */
  function fileOk(f, m) {
    if (!f) { say(m, SAID['no-file']); return false; }
    if (f.size > MAX_BYTES) { say(m, 'A file is 50 MB at most.'); return false; }
    return true;
  }
  function upload(docId, f) {
    var safe = String(f.name || 'file').replace(/[^\w.\-]+/g, '_').slice(-120);
    var path = docId + '/' + Date.now() + '-' + safe;
    return db.storage.from(BUCKET).upload(path, f, { contentType: f.type || 'application/octet-stream', upsert: false })
      .then(function (r) { if (r.error) throw r.error; return path; });
  }

  /* ---- Add and edit -------------------------------------------------------- */
  function kindPaint() {
    var link = $('hbKind').value === 'link';
    $('hbFileRow').hidden = link;
    $('hbLinkRow').hidden = !link;
  }
  $('hbKind').addEventListener('change', kindPaint);

  function openSheet(d, opener) {
    st.editing = d || null;
    say($('hbMsg'), '');
    $('hbSheetTitle').textContent = d ? 'Edit file' : 'Add file';
    $('hbSave').textContent = d ? 'Save' : 'Add';
    $('hbTitle').value = d ? d.title : '';
    $('hbCatPick').value = d ? d.category : ($('hbCat').value || 'handbook');
    $('hbSummary').value = d ? (d.summary || '') : '';
    $('hbFile').value = '';
    $('hbLink').value = d ? (d.link_url || '') : '';
    /* An added file chooses File or Link; an edit changes the details, and
       a file's contents change only through New version. */
    $('hbKind').value = d && d.link_url ? 'link' : 'file';
    $('hbKind').dispatchEvent(new Event('change', { bubbles: true }));
    $('hbKindRow').hidden = Boolean(d);
    $('hbSourceSec').hidden = Boolean(d && !d.link_url);
    window.ADspaceSheet.show($('hbSheet'), { opener: opener || null });
  }
  function shutSheet() { window.ADspaceSheet.close(); st.editing = null; }
  $('hbAdd').addEventListener('click', function () { openSheet(null, $('hbAdd')); });
  $('hbCancel').addEventListener('click', shutSheet);
  $('hbClose').addEventListener('click', function () { $('hbCancel').click(); });

  $('hbSave').addEventListener('click', function () {
    var m = $('hbMsg'), btn = $('hbSave'), d = st.editing;
    var title = $('hbTitle').value.trim();
    if (!title) { say(m, SAID['no-title']); $('hbTitle').focus(); return; }
    var cat = $('hbCatPick').value;
    var summary = $('hbSummary').value.trim();
    var isLink = $('hbKind').value === 'link';
    var link = isLink ? $('hbLink').value.trim() : '';
    if (isLink && !/^https:\/\//i.test(link)) { say(m, SAID['bad-link']); $('hbLink').focus(); return; }
    var f = (!d && !isLink) ? $('hbFile').files[0] : null;
    if (!d && !isLink && !fileOk(f, m)) { $('hbFile').focus(); return; }
    var id = d ? d.id : uuid();
    var was = btn.textContent;
    btn.disabled = true; btn.textContent = f ? 'Uploading' : 'Saving';
    say(m, '');
    var stored = f ? upload(id, f) : Promise.resolve(null);
    stored.then(function (path) {
      return rpc('handbook_save', { p_id: id, p_title: title, p_category: cat, p_summary: summary || null,
                                    p_link: isLink ? link : (d ? d.link_url : null) })
        .then(function () {
          if (!path) return null;
          return rpc('handbook_add_version', { p_doc: id, p_path: path, p_name: f.name, p_size: f.size,
                                               p_mime: f.type || null, p_note: null });
        });
    }).then(function () {
      btn.disabled = false; btn.textContent = was;
      window.ADspaceSheet.clean();
      shutSheet();
      say($('hbListMsg'), d ? 'Saved.' : 'Added.', 'ok');
      return load();
    }).catch(function (e) {
      btn.disabled = false; btn.textContent = was;
      say(m, said(e));
    });
  });

  /* ---- New version --------------------------------------------------------- */
  function openVersion(d, opener) {
    st.verFor = d;
    say($('hbVerMsg'), '');
    $('hbVerTitle').textContent = 'New version';
    $('hbVerFile').value = '';
    $('hbVerNote').value = '';
    window.ADspaceSheet.show($('hbVerSheet'), { opener: opener || null });
  }
  $('hbVerCancel').addEventListener('click', function () { window.ADspaceSheet.close(); st.verFor = null; });
  $('hbVerClose').addEventListener('click', function () { $('hbVerCancel').click(); });
  $('hbVerSave').addEventListener('click', function () {
    var m = $('hbVerMsg'), btn = $('hbVerSave'), d = st.verFor;
    if (!d) return;
    var f = $('hbVerFile').files[0];
    if (!fileOk(f, m)) { $('hbVerFile').focus(); return; }
    btn.disabled = true; btn.textContent = 'Uploading';
    say(m, '');
    upload(d.id, f).then(function (path) {
      return rpc('handbook_add_version', { p_doc: d.id, p_path: path, p_name: f.name, p_size: f.size,
                                           p_mime: f.type || null, p_note: $('hbVerNote').value.trim() || null });
    }).then(function (r) {
      btn.disabled = false; btn.textContent = 'Save';
      window.ADspaceSheet.clean();
      window.ADspaceSheet.close();
      st.verFor = null;
      say($('hbListMsg'), 'Version ' + r.version + ' saved.', 'ok');
      return load();
    }).catch(function (e) {
      btn.disabled = false; btn.textContent = 'Save';
      say(m, said(e));
    });
  });

  /* ---- Archive, restore, delete ------------------------------------------- */
  function archive(d, on) {
    var go = function () {
      rpc('handbook_archive', { p_id: d.id, p_on: on }).then(function () {
        say($('hbListMsg'), on ? 'Archived.' : 'Restored.', 'ok');
        return load();
      }).catch(function (e) { say($('hbListMsg'), said(e)); });
    };
    /* The way back never asks. */
    if (!on) { go(); return; }
    window.ADspaceConfirm.ask({ title: 'Archive?', body: 'Colleagues no longer see it. An admin can restore it.',
                                go: 'Archive', tone: 'warn' }, go);
  }
  function remove(d) {
    var n = (st.vers[d.id] || []).length;
    window.ADspaceConfirm.ask({
      title: 'Delete',
      body: '"' + d.title + '"' + (n ? ' and its ' + n + (n === 1 ? ' version' : ' versions') : '') + ' will be deleted. There is no restore.',
      go: 'Delete', tone: 'danger',
      field: { label: 'Type the title to confirm', match: d.title, mismatch: 'The title does not match.' }
    }, function (typed) {
      rpc('handbook_delete', { p_id: d.id, p_title: typed }).then(function (r) {
        var paths = r.paths || [];
        /* The rows are gone; the files follow. A file that will not go is
           left behind unreachable, which costs storage and nothing else. */
        var gone = paths.length ? db.storage.from(BUCKET).remove(paths).catch(function () {}) : Promise.resolve();
        return gone.then(function () {
          say($('hbListMsg'), 'Deleted.', 'ok');
          return load();
        });
      }).catch(function (e) { say($('hbListMsg'), said(e)); });
    });
  }

  /* ---- Filters ------------------------------------------------------------- */
  var lastFind = '', lastCat = '';
  function filtered() {
    var f = $('hbFind').value, c = $('hbCat').value;
    if (f === lastFind && c === lastCat) return;
    lastFind = f; lastCat = c;
    if (st.loaded) paint();
  }
  ['input', 'change'].forEach(function (ev) {
    $('hbFind').addEventListener(ev, filtered);
    $('hbCat').addEventListener(ev, filtered);
  });

  function enter() {
    say($('hbListMsg'), '');
    load();
  }

  window.ADspaceHandbook = { enter: enter, reload: load };
  if (bridge.handbookReady) bridge.handbookReady();
})();
