/* One search across the console (the user, 2026-09-27).
 *
 * A control in the console head opens a panel; Cmd / Ctrl + K opens it from
 * anywhere, and so does "/" when no field has the caret. At a desk the panel
 * drops from the head; on a phone it is the sheet every other form is, from
 * the floor, full height. It opens and shuts through js/sheet.js, so Escape,
 * the focus trap and the hand-back are the ones every sheet has.
 *
 * It asks only the sections the person may read (the page's `may()`), and the
 * database asks again (row level security): a read the policy refuses is a
 * section that drops out of the answer, never one that fails the others, and
 * only when every read fails does the panel say so. A failed read is never
 * drawn as "No matches.".
 *
 * Every read is the table the section already reads, through the one client,
 * with `ilike` over the columns a person would type and at most five rows a
 * section. The newest query wins: an answer to an older one that arrives late
 * is thrown away. A result opens the record's own address, written first, the
 * way the bell opens a task.
 */
(function () {
  var API = window.ADspaceAPI;
  var db = API && API.client;
  var UI = window.ADspaceState;
  var SHEET = window.ADspaceSheet;
  var W = (window.ADspaceWords && window.ADspaceWords.en) || {};
  var bridge = window.ADspaceAdmin || {};
  function $(id) { return document.getElementById(id); }
  var btn = $('searchOpen'), box = $('searchSheet'), field = $('searchQ');
  var list = $('searchList'), say = $('searchSay');
  if (!btn || !box || !field || !list || !say || !db || !SHEET) return;

  var LIMIT = 5, WAIT = 200, MIN = 2;
  var esc = UI.esc || function (s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  };
  function may(key, level) { return Boolean(bridge.may && bridge.may(key, level || 'view')); }

  /* ---- The query ---------------------------------------------------------
     What PostgREST is sent. A value inside `or()` is double quoted, because a
     comma, a full stop or a bracket (an email, "Dale & Cecil (SG)") would
     otherwise be read as the filter's own grammar; the quote and the
     backslash cannot be escaped reliably, and `%` and `*` are wildcards, so
     all four are dropped from what is typed. */
  function clean(q) { return String(q || '').replace(/["\\%*]/g, ' ').replace(/\s+/g, ' ').trim(); }
  function any(cols, q) {
    return cols.map(function (c) { return c + '.ilike."%' + q + '%"'; }).join(',');
  }
  /* `#WT01008`, `WT1008` or `1008` is a task's number. */
  function taskNo(q) {
    var m = /^#?(?:wt)?0*(\d{1,9})$/i.exec(q.replace(/\s+/g, ''));
    return m ? Number(m[1]) : null;
  }
  function clientKey(c) { return (c && (c.slug || c.id)) || ''; }
  function stageOf(v) { return (W.stage && W.stage[v]) || ''; }
  var PLATFORM = { xhs: 'rednote', instagram: 'Instagram', tiktok: 'TikTok', facebook: 'Facebook' };
  var MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
  function hostOf(url) { return String(url || '').replace(/^https?:\/\//i, '').replace(/\/$/, ''); }

  /* ---- Opening a result --------------------------------------------------
     The address first, then the section, because every section reads the
     address on entry. A list with no record of its own (the Creators List,
     Documents, Short Links, Services, Team) opens filtered to the row. */
  function go(url, section, filter) {
    history.replaceState(null, '', url);
    /* Filled before the section draws, so the list never paints unfiltered,
       and again after, because entering a section puts its bar back. */
    if (filter) fill(filter[0], filter[1]);
    if (section === 'review' && bridge.restore) bridge.restore();
    else if (bridge.show) bridge.show(section);
    if (filter) fill(filter[0], filter[1]);
  }
  /* The list's own search, so the filter is on the screen and Clear the
     filters takes it off. */
  function fill(id, value) {
    var el = $(id);
    if (!el) return;
    if (el.value !== value) {
      el.value = value;
      el.dispatchEvent(new Event('input', { bubbles: true }));
    }
    var bar = el.closest('.cmdbar');
    if (bar) {
      bar.classList.add('is-searching');
      var mark = bar.querySelector('.cmdbar-search');
      if (mark) mark.setAttribute('aria-expanded', 'true');
    }
  }

  /* ---- The sections ------------------------------------------------------
     In the rail's order (DESIGN.md §7). Each asks whether it may, reads, and
     turns a row into { id, name, code, meta, open }. A read answers
     { rows } or { error }; a section with two reads fails only when both do. */
  function read(builder) {
    return Promise.resolve(builder).then(function (r) {
      return r && r.error ? { error: r.error } : { rows: (r && r.data) || [] };
    }).catch(function (e) { return { error: e || { message: 'Failed' } }; });
  }
  function both(a, b) {
    return Promise.all([a, b]).then(function (r) {
      if (r[0].error && r[1].error) return { error: r[0].error };
      return { rows: (r[0].rows || []).concat(r[1].rows || []) };
    });
  }

  var SOURCES = [
    { key: 'ops', head: 'My Work', can: function () { return may('ops'); },
      read: function (q) {
        var n = taskNo(q), f = any(['code', 'title', 'content_desc'], q);
        if (n != null) f += ',task_no.eq.' + n;
        return read(db.from('ops_tasks').select('id, task_no, code, title, content_desc, scope, client_id, clients(name)')
          .is('archived_at', null).or(f).order('task_no', { ascending: false }).limit(LIMIT));
      },
      row: function (t) {
        return {
          id: 'task-' + t.id, name: t.content_desc || t.title,
          code: t.task_no != null ? '#WT' + String(t.task_no).padStart(5, '0') : '',
          meta: [t.code, (t.clients && t.clients.name) || (t.scope === 'internal' ? 'Internal' : '')],
          open: function () { go('/admin/?s=work&open=' + encodeURIComponent(t.id), 'work'); }
        };
      } },
    { key: 'clients', head: 'Clients', can: function () { return may('clients'); },
      read: function (q) {
        /* The registered name is a Billing column the table withholds
           (2026-09-28), so a client is found by its name and its code. */
        var direct = read(db.from('clients').select('id, slug, name, client_code, stage')
          .or(any(['name', 'client_code'], q)).order('name').limit(LIMIT));
        if (!may('clients.contacts')) return direct;
        var people = read(db.from('client_contacts')
          .select('name, email, phone, client_id, clients(id, slug, name, client_code, stage)')
          .is('archived_at', null).or(any(['name', 'email', 'phone'], q)).order('name').limit(LIMIT));
        /* A client found by its name leads; one found through a contact
           follows, once, saying which contact. */
        return Promise.all([direct, people]).then(function (r) {
          if (r[0].error && r[1].error) return { error: r[0].error };
          var seen = {}, out = [];
          (r[0].rows || []).forEach(function (c) { seen[c.id] = 1; out.push(c); });
          (r[1].rows || []).forEach(function (p) {
            var c = p.clients;
            if (!c || seen[c.id]) return;
            seen[c.id] = 1;
            out.push(Object.assign({}, c, { via: p }));
          });
          return { rows: out.slice(0, LIMIT) };
        });
      },
      row: function (c) {
        var via = c.via;
        return {
          id: 'client-' + c.id, name: c.name, code: c.client_code,
          meta: via ? [via.name, via.email || via.phone] : [stageOf(c.stage)],
          open: function () {
            go('/admin/?client=' + encodeURIComponent(clientKey(c)) + (via ? '&tab=contacts' : ''), 'clients');
          }
        };
      } },
    { key: 'review', head: 'Content Review', can: function () { return may('review.sets'); },
      read: function (q) {
        return read(db.from('batches').select('id, title, published, client_id, clients(id, slug, name)')
          .ilike('title', '%' + q + '%').order('created_at', { ascending: false }).limit(LIMIT));
      },
      row: function (s) {
        var c = s.clients || {};
        return {
          id: 'set-' + s.id, name: s.title, code: '',
          meta: [c.name, s.published ? 'Published' : 'Not published'],
          open: function () {
            go('/admin/?s=review&client=' + encodeURIComponent(clientKey(c) || s.client_id) + '&set=' + encodeURIComponent(s.id), 'review');
          }
        };
      } },
    { key: 'scripts', head: 'Video Scripts', can: function () { return may('scripts'); },
      read: function (q) {
        return read(db.from('video_scripts').select('id, code, title, period, status, client_id, clients(name)')
          .or(any(['code', 'title'], q)).order('created_at', { ascending: false }).limit(LIMIT));
      },
      row: function (v) {
        var m = /^(\d{4})-(\d{2})/.exec(v.period || '');
        return {
          id: 'script-' + v.id, name: v.title || v.code, code: v.title ? v.code : '',
          meta: [(v.clients && v.clients.name), m ? MON[Number(m[2]) - 1] + ' ' + m[1] : '', v.status === 'shared' ? 'Published' : 'Draft'],
          open: function () { go('/admin/?s=scripts&script=' + encodeURIComponent(v.id), 'scripts'); }
        };
      } },
    { key: 'campaigns', head: 'Creator Campaigns', can: function () { return may('campaigns.campaigns'); },
      read: function (q) {
        return read(db.from('campaigns').select('id, title, state, client_id, clients(name)')
          .ilike('title', '%' + q + '%').order('created_at', { ascending: false }).limit(LIMIT));
      },
      row: function (c) {
        return {
          id: 'campaign-' + c.id, name: String(c.title || '').trim() || W.untitled, code: '',
          meta: [(c.clients && c.clients.name), (W.campState && W.campState[c.state])],
          open: function () { go('/admin/?s=campaigns&campaign=' + encodeURIComponent(c.id), 'campaigns'); }
        };
      } },
    { key: 'creators', head: 'Creators List', can: function () { return may('campaigns.creators'); },
      read: function (q) {
        return read(db.from('creators').select('id, name, active, creator_profiles(platform)')
          .ilike('name', '%' + q + '%').order('name').limit(LIMIT));
      },
      row: function (k) {
        var plats = [];
        (k.creator_profiles || []).forEach(function (p) {
          var w = PLATFORM[p.platform];
          if (w && plats.indexOf(w) < 0) plats.push(w);
        });
        return {
          id: 'creator-' + k.id, name: k.name, code: '',
          meta: [k.active === false ? 'Inactive' : '', plats.join(', ')],
          open: function () { go('/admin/?s=campaigns&tab=roster', 'campaigns', ['rosterSearch', k.name]); }
        };
      } },
    { key: 'register', head: 'Documents',
      can: function () { return may('register.documents') || may('register.hr') || may('clients.documents'); },
      read: function (q) {
        var none = Promise.resolve({ error: { message: 'Not read' } });
        var docs = (may('register.documents') || may('register.hr'))
          ? read(db.from('documents').select('id, serial, kind, family, recipient, client_id, created_at, clients(name)')
            .or(any(['serial', 'recipient->>name'], q)).order('created_at', { ascending: false }).limit(LIMIT))
          : none;
        var offers = may('clients.documents')
          ? read(db.from('client_documents').select('id, number, bill_to, client_id, created_at, clients(id, slug, name)')
            .or(any(['number', 'bill_to->>legal_name', 'bill_to->>name'], q)).order('created_at', { ascending: false }).limit(LIMIT))
            .then(function (r) {
              return r.error ? r : { rows: r.rows.map(function (d) { return Object.assign({ offer: true }, d); }) };
            })
          : none;
        return both(docs, offers).then(function (r) {
          if (r.rows) r.rows = r.rows.sort(function (a, b) { return String(b.created_at || '') < String(a.created_at || '') ? -1 : 1; }).slice(0, LIMIT);
          return r;
        });
      },
      row: function (d) {
        if (d.offer) {
          var c = d.clients || {}, to = d.bill_to || {};
          return {
            id: 'offer-' + d.id, name: to.legal_name || to.name || c.name || 'Letter of Offer', code: d.number,
            meta: ['Letter of Offer', c.name],
            open: function () {
              go('/admin/?client=' + encodeURIComponent(clientKey(c) || d.client_id) + '&tab=documents', 'clients');
            }
          };
        }
        var rc = d.recipient || {};
        return {
          id: 'doc-' + d.id, name: rc.name || (d.clients && d.clients.name) || d.kind, code: d.serial,
          meta: [d.family === 'hr' ? 'HR Letter' : d.kind, d.family === 'hr' ? '' : (d.clients && d.clients.name)],
          open: function () { go('/admin/?s=register', 'register', ['regFind', d.serial]); }
        };
      } },
    { key: 'links', head: 'Short Links', can: function () { return may('links'); },
      read: function (q) {
        return read(db.from('links').select('slug, title, target_url, active')
          .ilike('slug', '%' + q + '%').order('slug').limit(LIMIT));
      },
      row: function (l) {
        return {
          id: 'link-' + l.slug, name: l.title || l.slug, code: l.title ? l.slug : '',
          meta: [l.active === false ? 'Paused' : '', hostOf(l.target_url)],
          open: function () { go('/admin/?s=links', 'links', ['linkSearch', l.slug]); }
        };
      } },
    { key: 'services', head: 'Services', can: function () { return may('services'); },
      read: function (q) {
        return read(db.from('services').select('slug, name, category, active')
          .ilike('name', '%' + q + '%').order('position').limit(LIMIT));
      },
      row: function (s) {
        return {
          id: 'service-' + s.slug, name: s.name, code: '',
          meta: [s.category, s.active === false ? 'Inactive' : ''],
          open: function () { go('/admin/?s=services', 'services', ['svcFind', s.name]); }
        };
      } },
    { key: 'team', head: 'Team', can: function () { return may('team'); },
      read: function (q) {
        return read(db.from('team_members').select('id, name, staff_code, designation, email, active')
          .or(any(['name', 'staff_code'], q)).order('name').limit(LIMIT));
      },
      row: function (m) {
        return {
          id: 'member-' + m.id, name: m.name, code: m.staff_code,
          meta: [m.active === false ? 'Inactive' : '', m.designation],
          open: function () {
            go('/admin/?s=team', 'team', ['teamFind', m.name]);
            /* Team opens on the tab last used; a colleague is on Members. */
            var tab = document.querySelector('#teamTabs .tab[data-tab="members"]');
            if (tab && !tab.classList.contains('is-on') && !tab.closest('[hidden]')) tab.click();
          }
        };
      } }
  ];
  function allowed() { return SOURCES.filter(function (s) { return s.can(); }); }

  /* ---- Drawing -----------------------------------------------------------
     The match is marked with weight, never colour. */
  function mark(text, q) {
    var s = String(text == null ? '' : text);
    if (!q) return esc(s);
    var i = s.toLowerCase().indexOf(q.toLowerCase());
    if (i < 0) return esc(s);
    return esc(s.slice(0, i)) + '<b>' + esc(s.slice(i, i + q.length)) + '</b>' + esc(s.slice(i + q.length));
  }
  var shown = [], active = -1, drawn = '';
  function setActive(i) {
    var rows = list.querySelectorAll('.srow');
    if (!rows.length) { active = -1; field.removeAttribute('aria-activedescendant'); return; }
    active = Math.max(0, Math.min(rows.length - 1, i));
    Array.prototype.forEach.call(rows, function (r, n) {
      r.classList.toggle('is-active', n === active);
      r.setAttribute('aria-selected', String(n === active));
    });
    field.setAttribute('aria-activedescendant', rows[active].id);
    rows[active].scrollIntoView({ block: 'nearest' });
  }
  function status(fn) {
    list.hidden = true; list.innerHTML = '';
    shown = []; active = -1; drawn = '';
    field.removeAttribute('aria-activedescendant');
    field.setAttribute('aria-expanded', 'false');
    say.hidden = false;
    fn(say);
  }
  function quiet() {
    list.hidden = true; list.innerHTML = '';
    say.hidden = true; say.innerHTML = '';
    shown = []; active = -1; drawn = '';
    field.removeAttribute('aria-activedescendant');
    field.setAttribute('aria-expanded', 'false');
  }
  function paint(groups, q) {
    shown = []; drawn = q;
    var html = '';
    groups.forEach(function (g) {
      if (!g.rows.length) return;
      html += '<div class="sgroup" role="group" aria-labelledby="sg-' + g.key + '">' +
        '<h4 class="sgroup-h" id="sg-' + g.key + '">' + (bridge.glyph ? bridge.glyph(g.key) : '') + esc(g.head) + '</h4>';
      g.rows.forEach(function (r) {
        var n = shown.length;
        shown.push(r);
        var meta = (r.meta || []).filter(function (x) { return x != null && String(x).trim(); });
        html += '<button class="srow" type="button" role="option" aria-selected="false" tabindex="-1" id="sr-' + n + '" data-n="' + n + '">' +
          '<span class="srow-name">' + mark(r.name, q) + '</span>' +
          (r.code ? '<span class="srow-code">' + mark(r.code, q) + '</span>' : '') +
          (meta.length ? '<span class="srow-meta">' + meta.map(function (m) { return mark(m, q); }).join(' · ') + '</span>' : '') +
          '</button>';
      });
      html += '</div>';
    });
    say.hidden = true; say.innerHTML = '';
    list.innerHTML = html;
    list.hidden = false;
    field.setAttribute('aria-expanded', 'true');
    setActive(0);
  }

  /* ---- Asking ------------------------------------------------------------ */
  var seq = 0, timer = null, last = '';
  function run(raw) {
    var q = clean(raw);
    last = q;
    var my = ++seq;
    if (q.length < MIN) { quiet(); return; }
    var srcs = allowed();
    if (!srcs.length) { status(function (el) { UI.emptyLine(el, 'No matches.'); }); return; }
    /* The answers already drawn stay while the next is read; a first read
       draws the skeleton. */
    if (!shown.length && say.hidden) { UI.skeleton(say, 3); say.hidden = false; }
    box.setAttribute('aria-busy', 'true');
    Promise.all(srcs.map(function (s) {
      var p;
      try { p = s.read(q); } catch (e) { p = Promise.resolve({ error: e }); }
      return p.then(function (r) { return { src: s, r: r }; }, function (e) { return { src: s, r: { error: e } }; });
    })).then(function (answers) {
      /* An answer to an older query is thrown away: the newest one wins. */
      if (my !== seq) return;
      box.removeAttribute('aria-busy');
      var failed = answers.filter(function (a) { return a.r.error; });
      if (failed.length === answers.length) {
        var why = (failed[0].r.error && failed[0].r.error.message) || '';
        status(function (el) { UI.failLine(el, 'Search', why, function () { run(field.value); }); });
        return;
      }
      var groups = answers.filter(function (a) { return !a.r.error; }).map(function (a) {
        return { key: a.src.key, head: a.src.head, rows: (a.r.rows || []).slice(0, LIMIT).map(a.src.row) };
      });
      if (!groups.some(function (g) { return g.rows.length; })) {
        status(function (el) { UI.emptyLine(el, 'No matches.'); });
        return;
      }
      paint(groups, q);
    });
  }
  function later() {
    clearTimeout(timer);
    timer = setTimeout(function () { run(field.value); }, WAIT);
  }

  /* ---- The panel ---------------------------------------------------------- */
  function isOpen() { return SHEET.isOpen(box); }
  function open(from) {
    if (btn.hidden) return;
    if (isOpen()) { field.focus(); field.select(); return; }
    SHEET.show(box, { opener: from || btn, focus: '#searchQ', onClose: function () { btn.setAttribute('aria-expanded', 'false'); } });
    btn.setAttribute('aria-expanded', 'true');
    field.select();
    if (clean(field.value).length >= MIN && clean(field.value) !== last) run(field.value);
  }
  function choose(n) {
    var r = shown[n];
    if (!r) return;
    SHEET.close();
    r.open();
  }

  btn.addEventListener('click', function () { open(btn); });
  $('searchClose').addEventListener('click', function () { SHEET.close(); });
  field.addEventListener('input', function () {
    /* Typing a search is not work to protect: the scrim still closes it. */
    SHEET.clean();
    later();
  });
  field.addEventListener('keydown', function (e) {
    if (e.isComposing) return;
    if (e.key === 'ArrowDown') { e.preventDefault(); setActive(active + 1); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); setActive(active - 1); }
    else if (e.key === 'Home' && shown.length && e.ctrlKey) { e.preventDefault(); setActive(0); }
    else if (e.key === 'End' && shown.length && e.ctrlKey) { e.preventDefault(); setActive(shown.length - 1); }
    else if (e.key === 'Enter') {
      e.preventDefault();
      /* Enter before the pause is up asks now; while an answer is on its
         way it waits for it. It opens only a row drawn for what is typed. */
      var q = clean(field.value);
      if (q !== last) { clearTimeout(timer); run(field.value); return; }
      if (q === drawn && active > -1) choose(active);
    }
  });
  list.addEventListener('click', function (e) {
    var row = e.target.closest('.srow');
    if (row) choose(Number(row.getAttribute('data-n')));
  });
  list.addEventListener('mousemove', function (e) {
    var row = e.target.closest('.srow');
    if (row && Number(row.getAttribute('data-n')) !== active) setActive(Number(row.getAttribute('data-n')));
  });

  /* Cmd / Ctrl + K from anywhere; "/" when the caret is in no field. Neither
     takes over another sheet that is open, which may hold typing. */
  function typing(el) {
    return el && (el.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName));
  }
  document.addEventListener('keydown', function (e) {
    if (e.isComposing || e.defaultPrevented || btn.hidden) return;
    var k = String(e.key || '').toLowerCase();
    var chord = k === 'k' && (e.metaKey || e.ctrlKey) && !e.altKey && !e.shiftKey;
    var slash = e.key === '/' && !e.metaKey && !e.ctrlKey && !e.altKey && !typing(document.activeElement);
    if (!chord && !slash) return;
    if (SHEET.isOpen() && !isOpen()) return;
    if (document.querySelector('#askSheet:not([hidden])')) return;
    e.preventDefault();
    var from = document.activeElement;
    open(from && from !== document.body && from !== box && !box.contains(from) ? from : btn);
  });

  /* Drawn once the team row has said who this is, and only where one section
     can be searched. */
  function access() { btn.hidden = !(bridge.me && bridge.me()) || !allowed().length; }
  access();
  window.ADspaceSearch = { access: access, open: function () { open(btn); } };
})();
