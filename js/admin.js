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

  /* The signed out bar is the shared chrome's, which handles its own mark.
     The console rail is this page's, so it asks the chrome to wire that one
     the same way rather than repeating the fallback here. */
  if (window.ADspaceChrome) window.ADspaceChrome.mark('sideLogo', 'sideWordmark');
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
    ['xhs:note',           'rednote post'],
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

  /* The activity record stores who by the address they signed in with, which
     is the stable identity: two colleagues can share a display name, nobody
     shares a login, and the nine security definer functions that write the log
     have `auth.jwt() ->> 'email'` and nothing else to hand.

     A person reading the record wants the person, so the address is resolved
     to a name here rather than stored as one. That way every entry ever
     written reads as a name from the moment this ships, with no migration and
     no audit row rewritten, and somebody who changes their name is recognised
     in their old entries too.

     Stood down colleagues are included deliberately: they still wrote what
     they wrote. An address with no team row at all — a legacy entry, a
     colleague whose row was deleted, `unknown` — keeps the address, because
     the point is to say who and not to hide that we cannot. */
  var whoBy = null;
  function loadWho(then) {
    db.from('team_members').select('email, name').then(function (r) {
      var by = {};
      (r.data || []).forEach(function (t) {
        var e = String(t.email || '').trim().toLowerCase();
        if (e && t.name) by[e] = t.name;
      });
      whoBy = by;
      if (then) then();
    }, function () { whoBy = whoBy || {}; if (then) then(); });
  }
  /* Never throws and never blanks a row: a failed read leaves every entry
     reading exactly as it does today. */
  function whoName(email) {
    var e = String(email == null ? '' : email).trim();
    if (!e || !whoBy) return e;
    return whoBy[e.toLowerCase()] || e;
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
      msg('authMsg', r.error ? r.error.message : 'A sign-in link has been sent.',
          r.error ? 'err' : 'ok');
    });
  });
  $('authEmail').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') $('authSend').click();
  });

  /* Dark is the console's and this browser's: chosen here, remembered here,
     and never taken from the system. The head script has already applied it
     before first paint; this only flips it and writes the choice down. The
     button names the theme it switches to, as a light switch does. */
  function paintTheme() {
    var dark = document.documentElement.getAttribute('data-theme') === 'dark';
    $('themeWord').textContent = dark ? 'light' : 'dark';
    $('themeToggle').setAttribute('aria-pressed', String(dark));
  }
  $('themeToggle').addEventListener('click', function () {
    var dark = document.documentElement.getAttribute('data-theme') !== 'dark';
    if (dark) document.documentElement.setAttribute('data-theme', 'dark');
    else document.documentElement.removeAttribute('data-theme');
    try { localStorage.setItem('adspace-theme', dark ? 'dark' : 'light'); } catch (e) {}
    paintTheme();
    shutAcct();
  });
  paintTheme();

  /* The account control. Who you are, the register you read in and the way
     out are three things touched a few times a year, so they sit behind one
     control at the end of the bar rather than in a block at the foot of the
     sidebar that every screen had to carry. */
  function shutAcct() {
    $('acctMenu').hidden = true;
    $('acctBtn').setAttribute('aria-expanded', 'false');
  }
  $('acctBtn').addEventListener('click', function (e) {
    e.stopPropagation();
    var open = $('acctMenu').hidden;
    $('acctMenu').hidden = !open;
    this.setAttribute('aria-expanded', String(open));
    if (open) $('acctMenu').querySelector('.kmenu-item').focus();
  });
  document.addEventListener('click', function (e) {
    if (!$('acctMenu').hidden && !e.target.closest('#acctWrap')) shutAcct();
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && !$('acctMenu').hidden) { shutAcct(); $('acctBtn').focus(); }
  });

  $('signOut').addEventListener('click', function () {
    db.auth.signOut().then(function () { location.reload(); });
  });
  $('noTeamOut').addEventListener('click', function () {
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
    // Signed out is a plain page, white to the edges. Signed in is the console,
    // which brings its own chrome and does not want the page header as well.
    /* Signed in is not the same as allowed in. Until the database has said
       who this is, the console stays hidden: its chrome names every section
       of the tool, and somebody with no team row was seeing that shape for as
       long as the me() call took before it was swapped for the cover. So the
       in-between looks like the plain page, and the console appears once, to
       the person it belongs to. */
    document.body.classList.toggle('is-plain', !inApp || !meLoaded);
    $('topbar').hidden = inApp && meLoaded;
    $('publicShell').hidden = inApp;
    $('console').hidden = true;
    $('authPanel').hidden = inApp;
    $('acctWrap').hidden = !inApp;
    if (!inApp) shutAcct();
    $('whoami').textContent = inApp ? session.user.email : '';
    /* One letter, not an avatar nobody uploaded. */
    $('acctMark').textContent = inApp ? (session.user.email || '?').charAt(0).toUpperCase() : '';
    actor = inApp ? session.user.email : '';

    if (!inApp) {
      entered = false;
      meLoaded = false;
      $('noTeamShell').hidden = true;
      $('clientsView').hidden = true;
      $('workspace').hidden = true;
      return;
    }
    // Already decided: a token refresh must not blank the console.
    if (meLoaded) { $('console').hidden = Boolean(!me); return; }
    if (entered) return;
    entered = true;
    /* Who this person is on the team decides what the console draws. The
       database enforces the same row on every query; this only keeps the
       screen honest about it. Fetched once, before anything is shown. */
    loadMe(function () {
      applyAccess();
      gateActivity();
      // Who wrote what, by address. Fire and forget: the record reads as
      // addresses until it lands, which is what it read as before.
      if (me) loadWho(function () { if (!$('activitySheet').hidden) paintActivity(); });
      if (!me) {
        // A plain page like sign-in: the page header, white to the edges.
        $('console').hidden = true;
        $('topbar').hidden = false;
        document.body.classList.add('is-plain');
        $('noTeamShell').hidden = false;
        $('noTeamWho').textContent = actor;
        return;
      }
      $('console').hidden = false;
      $('topbar').hidden = true;
      document.body.classList.remove('is-plain');
      // A session kept in local storage answers before the scripts below this
      // one have run. Restoring then would write the address with nothing
      // open and lose the tab or campaign it named, so wait for the page.
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', restoreView, { once: true });
      } else {
        restoreView();
      }
    });
  }

  /* The signed-in person's team row, or null if they have a login but no row.
     A missing me() function (schema not yet applied) is treated as "everyone
     may do everything", so an older database keeps working. */
  var me = null;
  var meLoaded = false;
  function loadMe(then) {
    db.rpc('me').then(function (r) {
      if (r.error) {
        me = { role: 'admin', is_admin: true, legacy: true };
      } else {
        me = r.data && r.data.id ? r.data : null;
      }
      meLoaded = true;
      then();
    }, function () { me = null; meLoaded = true; then(); });
  }

  /* Access is a level per section, the same four the database ranks.
     `view` reads, `work` adds, edits and publishes, `manage` also destroys.
     The line is reversibility: Unpublish exists, so publishing is `work`;
     a permanent deletion has no way back, so it is `manage`. */
  var SECTIONS = ['clients', 'review', 'campaigns', 'links', 'register', 'services', 'team', 'activity'];
  /* A part is a pane or a list inside a section, keyed `section.part`. It
     takes its own level where the group set one and its section's where it
     did not, in the page exactly as in `allowed()`, so a group that never
     opened the Parts fold is where it always was. HR letters were a section
     and are `register.hr` now. */
  var PARTS = {
    clients:   ['contacts', 'billing', 'services', 'documents', 'requests', 'calls'],
    review:    ['sets', 'settings'],
    campaigns: ['campaigns', 'creators', 'finance'],
    register:  ['documents', 'hr']
  };
  var RANK = { none: 0, view: 1, work: 2, manage: 3 };
  function level(key) {
    if (!me) return 0;
    if (me.is_admin || me.role === 'admin') return 3;
    var acc = me.access || {};
    var lv = acc[key];
    if (lv == null && key.indexOf('.') > 0) lv = acc[key.split('.')[0]];
    return RANK[lv] || 0;
  }
  /* `may('clients')` still reads as it always did and still means the
     everyday level, so nothing that asked the old question has changed its
     meaning; a second argument asks for one of the other three. */
  function may(section, want) {
    return level(section) >= (RANK[want || 'work'] || 2);
  }
  /* The Register is one page over two parts of the ladder: the documents
     themselves and the HR letters, which are gated apart. Either opens it,
     and the database's own policy decides which rows arrive. */
  function sectionAllowed(name) {
    if (name === 'register') return may('register.documents', 'view') || may('register.hr', 'view');
    return may(name, 'view');
  }

  /* Hide what the person may not use. Nothing here is the control; the
     policies are. This keeps the screen from offering what will be refused.
     One class per section and per part rather than one global `no-remove`,
     because the authority to destroy is per section now: a group can manage
     Content Review without being able to delete a client. A part's class
     hyphenates the key (`no-work-clients-billing`), since a dot is not a
     class token. */
  function applyAccess() {
    navItems().forEach(function (b) {
      b.hidden = !sectionAllowed(b.getAttribute('data-section'));
    });
    var keys = SECTIONS.slice();
    Object.keys(PARTS).forEach(function (s) {
      PARTS[s].forEach(function (p) { keys.push(s + '.' + p); });
    });
    keys.forEach(function (k) {
      var cls = k.replace('.', '-');
      document.body.classList.toggle('no-manage-' + cls, !may(k, 'manage'));
      document.body.classList.toggle('no-work-' + cls, !may(k, 'work'));
      document.body.classList.toggle('no-view-' + cls, !may(k, 'view'));
    });
  }

  /* On a phone the rail is a drawer. It closes on a pick, on the scrim, and on
     escape, so it can never be left covering the work. */
  (function () {
    var bar = $('sidebar');
    var scrim = null;

    function shut() {
      bar.classList.remove('is-open');
      if (scrim) { scrim.remove(); scrim = null; }
    }
    function open() {
      bar.classList.add('is-open');
      scrim = document.createElement('button');
      scrim.className = 'scrim';
      scrim.type = 'button';
      scrim.setAttribute('aria-label', 'Close sections');
      scrim.addEventListener('click', shut);
      document.body.appendChild(scrim);
    }

    $('navToggle').addEventListener('click', function () {
      bar.classList.contains('is-open') ? shut() : open();
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') shut();
    });
    bar.addEventListener('click', function (e) {
      if (e.target.closest('.navitem')) shut();
    });
  })();

  /* Which section of the console is on screen. The rail decides; neither
     section knows the other exists, which is the point of the shell. */
  /* Clients is the root of the model: a content set and a campaign both hang
     off one, so the console opens on the list rather than on work whose owner
     has not been established yet. */
  var section = 'clients';
  var SECTION_TITLE = {
    clients: 'Clients',
    review: 'Content Review',
    campaigns: 'Creator Campaigns',
    links: 'Short Links',
    register: 'Register',
    services: 'Services',
    team: 'Team'
  };
  /* WHAT EACH SECTION IS FOR, in one line, while the team is new to it.
     This portal carries no explanatory copy, and the user asked for exactly
     this on 2026-09-22: the portal is opening to the whole team and most of
     them do not yet know what the sections are. So it is the instruction
     pattern the creator page and the draft step already use: the line opens
     by itself the first three times a section is entered and then retires
     behind its `?` in the command bar, where anybody can open it again. Not
     a `title`, because a tooltip is unreachable on a phone. */
  var INTRO = {
    clients:   'Every client starts here as a lead. The record holds contacts, billing, services, letters and calls, and an active client is what Content Review and Creator Campaigns hang off.',
    review:    'Post mockups for the client to approve online. Build a content set, publish it and send the client the link.',
    campaigns: 'Creator bookings from selection to posting. The client picks creators on their link; the steps, the schedule and the invoice are run here.',
    links:     'Short links for slides, print and QR codes, redirecting from ' + ((window.ADSPACE_CONFIG && window.ADSPACE_CONFIG.linkHost) || 'hi.adspace.me') + '. A destination can be corrected or paused after it is printed.',
    register:  'Every document the portal has issued and every reference added by hand. A reference is checked at ' + location.host + '/verify.',
    services:  'The rate card every quotation reads from. A price here seeds a client\'s service line and stays editable there.',
    team:      'Who can sign in, and what each group may open. Access is set per section, with exceptions per part.'
  };
  var INTRO_SHOWS = 3;
  function introSeen(name) {
    try { return Number(localStorage.getItem('adspace-hint-intro-' + name) || 0); } catch (e) { return INTRO_SHOWS; }
  }
  function paintIntro(name) {
    var host = $('section' + name.charAt(0).toUpperCase() + name.slice(1));
    if (!host || !INTRO[name]) return;
    var bar = host.querySelector('.cmdbar');
    if (!bar) return;
    var line = host.querySelector('.routeintro');
    var seen = introSeen(name);
    if (!line) {
      line = document.createElement('div');
      line.className = 'hintline routeintro';
      line.innerHTML = '<button class="hintbtn" type="button" aria-expanded="false" aria-label="What this section is for">?</button>' +
        '<p class="hinttext" hidden></p>';
      line.querySelector('.hinttext').textContent = INTRO[name];
      bar.parentNode.insertBefore(line, bar.nextSibling);
      line.querySelector('.hintbtn').addEventListener('click', function () {
        var t = line.querySelector('.hinttext');
        t.hidden = !t.hidden;
        this.setAttribute('aria-expanded', String(!t.hidden));
      });
      // Counted once per visit, not once per repaint.
      try { localStorage.setItem('adspace-hint-intro-' + name, String(seen + 1)); } catch (e) {}
    }
    var open = seen < INTRO_SHOWS;
    line.querySelector('.hinttext').hidden = !open;
    line.querySelector('.hintbtn').setAttribute('aria-expanded', String(open));
  }
  // The first section this person is allowed, for when the one asked for is not.
  function firstAllowed() {
    var order = ['clients', 'review', 'campaigns', 'links', 'register', 'services', 'team'];
    for (var i = 0; i < order.length; i++) if (sectionAllowed(order[i])) return order[i];
    return 'clients';
  }

  var enterLater = '';

  function showSection(name) {
    if (!SECTION_TITLE[name]) name = 'clients';
    if (meLoaded && !sectionAllowed(name)) name = firstAllowed();
    section = name;
    $('sectionClients').hidden   = name !== 'clients';
    $('sectionReview').hidden    = name !== 'review';
    $('sectionCampaigns').hidden = name !== 'campaigns';
    $('sectionLinks').hidden     = name !== 'links';
    $('sectionRegister').hidden  = name !== 'register';
    $('sectionServices').hidden  = name !== 'services';
    $('sectionTeam').hidden      = name !== 'team';
    $('sectionTitle').textContent = SECTION_TITLE[name];
    paintIntro(name);
    // The tab said Content Review Internal whichever section you were in.
    document.title = SECTION_TITLE[name] + ' · ADspace Digital Portal';
    navItems().forEach(function (b) {
      b.classList.toggle('is-on', b.getAttribute('data-section') === name);
    });
    showActivityLink();
    // Campaigns reads the address before it writes it, because on a reload the
    // address is the only record of which campaign or tab was open. Writing
    // first, with nothing open yet, blanked exactly the part it needed.
    if (name === 'campaigns') {
      // Not loaded yet: leave the address alone and enter once it is.
      if (!window.ADspaceCampaigns) { enterLater = 'campaigns'; return; }
      window.ADspaceCampaigns.enter();
      return;
    }
    if (name === 'clients') {
      if (!window.ADspaceCRM) { enterLater = 'clients'; return; }
      window.ADspaceCRM.enter();
      return;
    }
    if (name === 'team') {
      if (!window.ADspaceTeam) { enterLater = 'team'; return; }
      window.ADspaceTeam.enter();
      setUrl();
      return;
    }
    if (name === 'register') {
      if (!window.ADspaceRegister) { enterLater = 'register'; return; }
      window.ADspaceRegister.enter();
      setUrl();
      return;
    }
    if (name === 'services') {
      if (!window.ADspaceCRM) { enterLater = 'services'; return; }
      window.ADspaceCRM.enterServices();
      setUrl();
      return;
    }
    setUrl();
    if (name === 'links') { loadLinks(); restoreScroll(); }
  }

  function navItems() {
    return Array.prototype.slice.call(document.querySelectorAll('.navitem'));
  }
  navItems().forEach(function (b) {
    b.addEventListener('click', function () { showSection(b.getAttribute('data-section')); });
  });

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
          client: clientKey(state.client),
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
  /* The address bar is where you are: the section, and whatever is open
     inside it. A refresh, a reopened tab or a pasted link all land there.
     What you were typing is not here; that is the form's own memory. */
  /* A client's address is its slug, the readable one the Clients section
     writes. Older links carrying a UUID still resolve, so nothing shared
     before this stops working. Both live in js/crm.js, which owns clients. */
  function clientKey(c) {
    var CRM = window.ADspaceCRM;
    return (CRM && CRM.keyOf ? CRM.keyOf(c) : '') || (c && c.id) || '';
  }
  function clientByKey(key, then) {
    var CRM = window.ADspaceCRM;
    if (CRM && CRM.byKey) { CRM.byKey(key, then); return; }
    db.from('clients').select('*').eq('id', key).single()
      .then(function (r) { then(r.error ? null : (r.data || null)); }, function () { then(null); });
  }

  function setUrl() { history.replaceState(null, '', urlOf(queryNow())); }

  function queryNow() {
    var q = [];
    if (section !== 'clients') q.push('s=' + section);
    if (section === 'review') {
      // The same readable address the Clients section uses.
      if (state.client) q.push('client=' + encodeURIComponent(clientKey(state.client)));
      if (state.batch)  q.push('set=' + state.batch.id);
    } else if (section === 'campaigns' && window.ADspaceCampaigns) {
      var sub = window.ADspaceCampaigns.urlState();
      Object.keys(sub).forEach(function (k) { if (sub[k]) q.push(k + '=' + encodeURIComponent(sub[k])); });
    } else if (section === 'clients' && window.ADspaceCRM) {
      var crm = window.ADspaceCRM.urlState();
      Object.keys(crm).forEach(function (k) { if (crm[k]) q.push(k + '=' + encodeURIComponent(crm[k])); });
    }
    return q;
  }

  /* Most of the address is a note of where you are: it is replaced, so the
     browser's Back button still leaves the console rather than walking every
     repaint. A local navigation inside a record is different — it is a move a
     person made, so it pushes an entry and Back and Forward walk the panes. */
  function pushUrl() {
    var before = location.pathname + location.search;
    var after = urlOf(queryNow());
    if (after !== before) history.pushState(null, '', after);
  }
  function urlOf(q) { return '/admin/' + (q.length ? '?' + q.join('&') : ''); }

  /* Scroll, per address. Review has its own richer memory tied to the client;
     this is the plain one the other sections use. */
  var SCROLL = 'adspace.admin.scroll:';
  var scrollSaveTimer = null;
  window.addEventListener('scroll', function () {
    if (section === 'review') return;
    clearTimeout(scrollSaveTimer);
    scrollSaveTimer = setTimeout(function () {
      try { sessionStorage.setItem(SCROLL + location.search, String(window.scrollY)); } catch (e) {}
    }, 200);
  });
  function restoreScroll() {
    var y = 0;
    try { y = Number(sessionStorage.getItem(SCROLL + location.search) || 0); } catch (e) {}
    if (!y) return;
    // The content arrives after the call, so try now and again once it has.
    window.scrollTo(0, y);
    setTimeout(function () { window.scrollTo(0, y); }, 260);
  }

  function restoreView() {
    var params = new URLSearchParams(location.search);
    // Read the address before anything writes to it: showSection rewrites the
    // address from state, and state does not know about these yet.
    var clientId = params.get('client');
    var setId = params.get('set');
    var where = params.get('s') || firstAllowed();
    if (!SECTION_TITLE[where]) where = firstAllowed();

    if (where !== 'review') {
      // Content Review still needs its list painted for when they come back.
      $('clientsView').hidden = false;
      loadClients();
      showSection(where);
      return;
    }

    showSection('review');
    if (!clientId) { showClients(); return; }

    var place = readPlace();
    var samePlace = place && place.client === clientId;
    if (samePlace) pendingScroll = place.y || 0;

    clientByKey(clientId, function (c) {
      if (!c) { showClients(); return; }
      openClient(c);
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
  }

  /* Only active clients belong here. The CRM also holds leads and past
     clients, and none of those have content to review. A client removed from
     this section stays a client; they are simply not listed here. */
  /* Loading, empty and failed are said one way across the console. */
  var UI = window.ADspaceState;
  var skeleton = UI.skeleton, failLine = UI.failLine;

  var crFind = '';
  function loadClients() {
    var box = $('clientCards');
    if (!state.reviewClients) skeleton(box, 3);
    db.from('clients').select('*').eq('stage', 'active').eq('review_hidden', false)
      .order('name').then(function (r) {
      if (r.error) {
        state.reviewClients = null;
        failLine(box, 'Clients', r.error.message, loadClients);
        settleScroll();
        return;
      }
      state.reviewClients = r.data || [];
      paintReviewClients();
      settleScroll();
    });
  }

  function paintReviewClients() {
    var box = $('clientCards');
    var all = state.reviewClients || [];
    var rows = !crFind ? all : all.filter(function (c) {
      return String(c.name || '').toLowerCase().indexOf(crFind) >= 0;
    });
    var count = $('crCount');
    if (count) {
      count.textContent = !all.length ? ''
        : rows.length === all.length ? all.length + (all.length === 1 ? ' client' : ' clients')
        : rows.length + ' of ' + all.length;
    }
    box.innerHTML = '';
    if (!all.length) { UI.emptyLine(box, 'No active clients.'); return; }
    if (!rows.length) {
      UI.emptyLine(box, 'No matches.', 'Clear the search', function () {
        crFind = ''; if ($('crFind')) $('crFind').value = ''; paintReviewClients();
      });
      return;
    }
    /* One register, not a grid of tiles. A card per client answered "which
       clients are there" and nothing else: how many sets each has, how many
       are live and whether an access code is on all needed reading the tile,
       and a tile cannot be read down a column. The same surface the clients
       directory and the campaign register are. */
    var table = document.createElement('div');
    table.className = 'crm-table softpanel crm-register';
    var head = document.createElement('div');
    head.className = 'crm-head cr-client-row';
    head.innerHTML = '<span>Client</span><span>Content sets</span><span>Access</span><span></span>';
    table.appendChild(head);

    rows.forEach(function (c) {
      var row = document.createElement('button');
      row.type = 'button';
      row.className = 'crm-row cr-client-row';
      row.innerHTML =
        '<span class="crm-c crm-c-name">' + esc(c.name) + '</span>' +
        '<span class="crm-c crm-c-sets" data-role="sub"><span class="muted">Loading\u2026</span></span>' +
        /* An access code is the exception, so the row says nothing where there
           is none rather than printing "Open" on almost every line. */
        '<span class="crm-c crm-c-code">' + (c.passcode
          ? '<span class="tone">Access code</span>' : '<span class="muted">\u2014</span>') + '</span>' +
        '<span class="crm-c crm-c-go" aria-hidden="true">' + GO_CHEV + '</span>';
      row.addEventListener('click', function () { openClient(c); });
      table.appendChild(row);

      /* A one line answer to "where does this client stand?" A read that
         failed is not a client with nothing on it: "No content sets" over a
         fault sends somebody to build a set that is already there. */
      db.from('batches').select('id, published').eq('client_id', c.id).then(function (b) {
        var sub = row.querySelector('[data-role="sub"]');
        if (!sub) return;
        if (b.error) { sub.innerHTML = '<span class="is-warn">Sets unavailable</span>'; return; }
        if (!b.data.length) { sub.innerHTML = '<span class="muted">None yet</span>'; return; }
        var live = b.data.filter(function (x) { return x.published; }).length;
        sub.textContent = b.data.length + ' set' + (b.data.length === 1 ? '' : 's') +
          ' \u00b7 ' + live + ' published';
      });
    });
    box.appendChild(table);
  }

  var GO_CHEV = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' +
    'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 18l6-6-6-6"/></svg>';

  if ($('crFind')) $('crFind').addEventListener('input', function () {
    crFind = this.value.trim().toLowerCase();
    paintReviewClients();
  });

  /* Label, tone, and which section of the portal the action belongs to, so the
     record can be filtered the way the sidebar is. */
  var ACTION_LABEL = {
    'client.added':          ['Client added', 'is-ok', 'clients'],
    'team.added':            ['Team member added', 'is-ok', 'team'],
    'team.changed':          ['Access changed', 'is-warn', 'team'],
    'team.edited':           ['Team member edited', '', 'team'],
    'team.invited':          ['Sign-in invitation sent', '', 'team'],
    'team.group_added':      ['User group added', 'is-ok', 'team'],
    'team.group_changed':    ['User group changed', 'is-warn', 'team'],
    'team.group_removed':    ['User group removed', 'is-danger', 'team'],
    'client.removed':        ['Client removed', 'is-danger', 'review'],
    'review.removed':        ['Removed from Content Review', 'is-danger', 'review'],
    'client.edited':         ['Client edited', '', 'clients'],
    'client.stage':          ['Stage moved', '', 'clients'],
    'client.billing':        ['Billing details saved', '', 'clients'],
    'client.brand':          ['Brand profile saved', '', 'clients'],
    'client.service':        ['Service line added', 'is-ok', 'clients'],
    'client.service_changed': ['Service line changed', '', 'clients'],
    'client.service_removed': ['Service line removed', 'is-danger', 'clients'],
    'document.issued':       ['Document issued', 'is-ok', 'clients'],
    'document.voided':       ['Document voided', 'is-danger', 'clients'],
    'document.restored':     ['Document restored', 'is-ok', 'clients'],
    'document.deleted':      ['Document deleted', 'is-danger', 'clients'],
    'document.reissued':     ['Document reissued', '', 'clients'],
    'register.added':        ['Register entry added', 'is-ok', 'clients'],
    'register.edited':       ['Register entry edited', '', 'clients'],
    'service.added':         ['Rate card line added', 'is-ok', 'services'],
    'service.changed':       ['Rate card line changed', '', 'services'],
    'service.off':           ['Rate card line set inactive', 'is-warn', 'services'],
    'service.on':            ['Rate card line set active', 'is-ok', 'services'],
    'service.deleted':       ['Rate card line deleted', 'is-danger', 'services'],
    'client.touch':          ['Call or visit logged', '', 'clients'],
    'client.review_on':      ['Added to Content Review', 'is-ok', 'clients'],
    'contact.portal_on':     ['Portal access granted', 'is-ok', 'clients'],
    'contact.portal_off':    ['Portal access revoked', 'is-warn', 'clients'],
    'contact.portal_invite': ['Invitation sent', '', 'clients'],
    'contact.deleted':       ['Contact deleted', 'is-danger', 'clients'],
    'request.raised':        ['Request raised', 'is-warn', 'clients'],
    'request.changed':       ['Request changed', '', 'clients'],
    'request.replied':       ['Request replied', '', 'clients'],
    'contact.added':         ['Contact added', 'is-ok', 'clients'],
    'contact.edited':        ['Contact edited', '', 'clients'],
    'contact.restored':      ['Contact put back', 'is-ok', 'clients'],
    'client.touch_edited':   ['Log entry edited', '', 'clients'],
    'client.touch_removed':  ['Log entry removed', 'is-warn', 'clients'],
    'client.touch_restored': ['Log entry put back', 'is-ok', 'clients'],
    'client.action_done':    ['Next action done', 'is-ok', 'clients'],
    'client.action_reopened':['Next action reopened', 'is-warn', 'clients'],
    'contact.primary':       ['Main contact changed', '', 'clients'],
    'contact.removed':       ['Contact removed', 'is-danger', 'clients'],
    'set.deleted':           ['Content set deleted', 'is-danger', 'review'],
    'post.deleted':          ['Post deleted', 'is-danger', 'review'],
    'set.published':         ['Published to client', 'is-ok', 'review'],
    'set.withdrawn':         ['Withdrawn from client', 'is-warn', 'review'],
    'link.reset':            ['Access link reset', 'is-warn', 'review'],
    'reapproval.requested':  ['Re-approval requested', 'is-warn', 'review'],
    /* What a client and a creator did, not only what we did. The record is
       what answers a dispute, and it held one side of every conversation:
       a client approved a post and the portal kept the verdict in `reviews`
       alone, which no screen reads as a history. These carry the name the
       person typed as the actor, so the row says who, what and when. */
    'review.approved':       ['Approved by client', 'is-ok', 'review'],
    'review.changes':        ['Changes requested by client', 'is-warn', 'review'],
    'request.withdrawn':     ['Request withdrawn by client', 'is-warn', 'clients'],
    'request.reinstated':    ['Request reinstated by client', '', 'clients'],
    // Short links. Named apart from link.reset above, which is the client's
    // access link and a different thing entirely.
    'shortlink.created':     ['Short link created', 'is-ok', 'links'],
    'shortlink.updated':     ['Short link changed', 'is-warn', 'links'],
    'shortlink.deleted':     ['Short link deleted', 'is-danger', 'links'],
    'shortlink.imported':    ['Short links imported', 'is-ok', 'links'],
    // Creator campaigns and the creators list behind them.
    'campaign.created':      ['Campaign created', 'is-ok', 'campaigns'],
    'campaign.edited':       ['Campaign edited', '', 'campaigns'],
    'campaign.opened':       ['Sent to client', 'is-ok', 'campaigns'],
    'campaign.closed':       ['Withdrawn from client', 'is-warn', 'campaigns'],
    'campaign.deleted':      ['Campaign deleted', 'is-danger', 'campaigns'],
    'campaign.locked':       ['Selection accepted', 'is-ok', 'campaigns'],
    'campaign.keyed':        ['Chosen for the client', '', 'campaigns'],
    'campaign.unkeyed':      ['Selection undone', 'is-warn', 'campaigns'],
    'campaign.rate':         ['Rate changed', 'is-warn', 'campaigns'],
    'campaign.stage':        ['Stage moved', '', 'campaigns'],
    'campaign.unbooked':     ['Returned to options', 'is-warn', 'campaigns'],
    'campaign.withdrawn':    ['Creator withdrew', 'is-danger', 'campaigns'],
    'campaign.confirmed':    ['Selection confirmed by client', 'is-ok', 'campaigns'],
    'campaign.submitted':    ['Draft handed in by creator', '', 'campaigns'],
    'campaign.rated':        ['Creator rated the booking', '', 'campaigns'],
    'campaign.replaced':     ['Creator replaced', 'is-danger', 'campaigns'],
    'campaign.reinstated':   ['Put back in production', 'is-ok', 'campaigns'],
    'campaign.invoice':      ['Invoice number set', '', 'campaigns'],
    'campaign.invoice_file': ['Invoice uploaded', 'is-ok', 'campaigns'],
    'campaign.invoice_removed': ['Invoice PDF removed', 'is-warn', 'campaigns'],
    'campaign.bulk':         ['Shoot dates applied', '', 'campaigns'],
    'creator.added':         ['Creator added', 'is-ok', 'campaigns'],
    'creator.updated':       ['Creator edited', '', 'campaigns'],
    'creator.removed':       ['Creator removed', 'is-danger', 'campaigns'],
    'creator.off':           ['Creator set inactive', 'is-warn', 'campaigns'],
    'creator.on':            ['Creator set active', 'is-ok', 'campaigns']
  };
  var ACT_SECTION = { all: 'Everything', clients: 'Clients', team: 'Team', review: 'Content Review',
                      campaigns: 'Creator Campaigns', links: 'Short Links', services: 'Services' };

  /* The section only appears for people on the viewer list. The database
     enforces this too, so hiding it here is convenience rather than the
     control itself. */
  var maySeeActivity = false;

  function gateActivity() {
    maySeeActivity = may('activity', 'view');
    showActivityLink();
    // An older database without me() still has the viewers list; honour it.
    if (me && me.legacy && actor) {
      db.from('activity_viewers').select('email').ilike('email', actor).limit(1)
        .then(function (r) {
          maySeeActivity = Boolean(r.data && r.data.length);
          showActivityLink();
        }, function () {});
    }
  }

  /* The record covers the whole portal, not one section of it, so it is
     offered wherever you are. Hiding it is convenience; the database is what
     actually refuses. */
  function showActivityLink() {
    $('activityOpen').hidden = !maySeeActivity;
  }

  function shutActivity() { $('activitySheet').hidden = true; }

  $('activityOpen').addEventListener('click', function () {
    $('activitySheet').hidden = false;
    loadActivity();
  });
  $('activityClose').addEventListener('click', shutActivity);
  $('activitySheet').addEventListener('click', function (e) {
    if (e.target === $('activitySheet')) shutActivity();
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') shutActivity();
  });

  /* Filtered by section and grouped by day. Sixty rows in one unbroken column
     was a scroll with no landmarks in it; a date heading gives the eye
     somewhere to stop, and the tabs answer "what happened in campaigns" without
     reading past everything else. */
  var actFilter = 'all';
  var actRows = [];

  function dayLabel(iso) {
    var d = new Date(iso);
    // A row with no usable timestamp gets its own group rather than a heading
    // reading "Invalid Date".
    if (!iso || isNaN(d.getTime())) return 'Undated';
    var today = new Date();
    var same = function (a, b) { return a.toDateString() === b.toDateString(); };
    var yest = new Date(today.getTime() - 864e5);
    if (same(d, today)) return 'Today';
    if (same(d, yest)) return 'Yesterday';
    return d.toLocaleDateString('en-GB',
      { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });
  }

  function sectionOf(action) { return (ACTION_LABEL[action] || [])[2] || 'other'; }

  function clockOf(iso) {
    var d = new Date(iso);
    if (!iso || isNaN(d.getTime())) return '';
    return d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
  }

  function paintActivity() {
    var box = $('activityList');
    var rows = actRows.filter(function (a) {
      return actFilter === 'all' || sectionOf(a.action) === actFilter;
    });
    Array.prototype.forEach.call($('activityTabs').children, function (b) {
      b.classList.toggle('is-on', b.getAttribute('data-af') === actFilter);
    });
    if (!rows.length) {
      box.innerHTML = '<div class="empty">Nothing recorded' +
        (actFilter === 'all' ? '' : ' in ' + ACT_SECTION[actFilter]) + '.</div>';
      return;
    }
    box.innerHTML = '';
    var day = '';
    rows.forEach(function (a) {
      var label = dayLabel(a.created_at);
      if (label !== day) {
        day = label;
        var h = document.createElement('div');
        h.className = 'act-day';
        h.textContent = day;
        box.appendChild(h);
        var th = document.createElement('div');
        th.className = 'act act-head';
        th.innerHTML = ['Time', 'Action', 'On', 'Detail', 'By']
          .map(function (c) { return '<span>' + c + '</span>'; }).join('');
        box.appendChild(th);
      }
      var meta = ACTION_LABEL[a.action] || [a.action, ''];
      var row = document.createElement('div');
      row.className = 'act';
      // Four columns, so the eye reads down a column instead of hunting
      // across each line for where the detail happens to have landed.
      row.innerHTML =
        '<span class="act-when">' + esc(clockOf(a.created_at)) + '</span>' +
        '<span class="act-tagcell"><span class="act-tag ' + meta[1] + '">' + esc(meta[0]) + '</span></span>' +
        '<span class="act-subject">' + esc(a.subject || '') + '</span>' +
        '<span class="act-detail">' + esc(a.detail || '') + '</span>' +
        '<span class="act-who">' + esc(whoName(a.actor)) + '</span>';
      box.appendChild(row);
    });
  }

  Array.prototype.forEach.call($('activityTabs').children, function (b) {
    b.addEventListener('click', function () {
      actFilter = b.getAttribute('data-af');
      paintActivity();
    });
  });

  function loadActivity() {
    var box = $('activityList');
    box.innerHTML = '<div class="empty">Loading…</div>';
    // Opening it from a section starts on that section, since that is almost
    // always what the question was about.
    actFilter = ACT_SECTION[section] ? section : 'all';
    db.from('activity_log').select('*')
      .order('created_at', { ascending: false }).limit(200)
      .then(function (r) {
        if (r.error) {
          box.innerHTML = '<div class="empty">Access denied.</div>';
          return;
        }
        actRows = r.data || [];
        paintActivity();
      });
  }

  /* Creating a client used to happen here, and separately inside Creator
     Campaigns, so the same company could be entered twice with neither place
     owning the record. A client is a company and belongs to the CRM; this
     section publishes their deliverables. */
  $('goToCrm').addEventListener('click', function () { showSection('clients'); });

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
    paintLogo();
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
      msg('handleMsg', 'Saved.', 'ok');
    });
  });

  /* Shows the address as a circle, the way every platform will, and says so
     when the file is not square. Nothing is ever skewed: a wide mark either
     loses its ends to a crop or sits small inside the circle, and neither is
     what the client's real profile looks like. The fix is a square file, so
     the tool asks for one here rather than letting a mockup deliver the news. */
  var logoTimer = null;
  function paintLogo() {
    var url = $('eLogo').value.trim();
    var box = $('logoPreview');
    var img = $('logoPreviewImg');
    box.classList.toggle('is-empty', !url);
    if (!url) { img.hidden = true; img.removeAttribute('src'); msg('logoNote', ''); return; }
    if (!/^https:\/\//i.test(url)) { img.hidden = true; msg('logoNote', ''); return; }

    var probe = new Image();
    probe.onload = function () {
      img.src = url;
      img.hidden = false;
      var w = probe.naturalWidth, h = probe.naturalHeight;
      var square = w && h && Math.abs(w - h) / Math.max(w, h) < 0.02;
      if (square) {
        msg('logoNote', w + ' x ' + h + '. Square, so it fills the circle exactly.', 'ok');
      } else {
        msg('logoNote', w + ' x ' + h + '. Not square; it will appear small inside the circle. Use a square version.', 'warn');
      }
    };
    probe.onerror = function () {
      img.hidden = true;
      msg('logoNote', 'No image could be loaded from that address.', 'err');
    };
    probe.src = url;
  }

  $('eLogo').addEventListener('input', function () {
    clearTimeout(logoTimer);
    logoTimer = setTimeout(paintLogo, 400);
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
        var note = !had && pass ? 'Access code added.'
                 : had && !pass ? 'Access code removed.'
                 : had && pass  ? 'Access code updated.'
                 : 'Saved.';
        msg('profileMsg', note, 'ok');
        if (!had && !pass) msg('profileMsg', logo ? 'Logo saved.' : 'Saved.', 'ok');
      });
  });

  $('resetLink').addEventListener('click', function () {
    if (!confirm('Reset the review link for ' + state.client.name + '?\n\n' +
      'The current link stops working immediately. The new link must be reissued to the client.')) return;

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
  /* "Delete" here used to delete the company. It now removes what Content
     Review holds for them, their content sets, and takes them off this list.
     The company, its contacts and its log stay in Clients, where they belong. */
  $('deleteClient').addEventListener('click', function () {
    var c = state.client;
    db.from('batches').select('id').eq('client_id', c.id).then(function (r) {
      var sets = (r.data || []).length;
      if (!confirm('Remove ' + c.name + ' from Content Review?\n\n' +
        'Deletes ' + sets + ' content set' + (sets === 1 ? '' : 's') +
        ' with all posts and approval records. The client record is kept.')) return;
      var typed = prompt('Type the client name exactly to confirm:', '');
      if (typed === null) return;
      if (typed.trim() !== c.name) {
        msg('profileMsg', 'Name does not match. Nothing removed.', 'err');
        return;
      }
      db.from('batches').delete().eq('client_id', c.id).then(function (d) {
        if (d.error) { msg('profileMsg', d.error.message, 'err'); return; }
        db.from('clients').update({ review_hidden: true }).eq('id', c.id).then(function (u) {
          if (u.error) { msg('profileMsg', u.error.message, 'err'); return; }
          logAction('review.removed', c.name,
            sets + ' content set' + (sets === 1 ? '' : 's') + ' removed');
          showClients();
        });
      });
    });
  });

  $('copyLink').addEventListener('click', function () {
    window.ADspaceCopy.to(this, $('clientLink').value);
  });

  // ---- Content sets -------------------------------------------------------
  function loadBatches() {
    db.from('batches').select('*').eq('client_id', state.client.id)
      .order('created_at', { ascending: false }).then(function (r) {
        var box = $('batchCards');
        box.innerHTML = '';
        if (r.error) { failLine(box, 'Content sets', r.error.message, loadBatches); return; }
        if (!r.data.length) {
          box.innerHTML = '<div class="empty">No content sets.</div>';
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

          /* A count that could not be read is not a count of nothing: it
             said "0 posts" over a failed request and the set looked empty. */
          db.from('posts').select('id').eq('batch_id', b.id).then(function (p) {
            var sub = card.querySelector('[data-role="sub"]');
            if (p.error) { sub.textContent = 'Posts unavailable'; sub.className = 'bigcard-sub is-warn'; return; }
            var n = (p.data || []).length;
            sub.textContent = n + ' post' + (n === 1 ? '' : 's');
          });
        });
      });
  }

  /* The name a new set needs is not on the screen yet, so the field grows out
     of the button that needs it and that button confirms it. Seeded with the
     month, which is what nearly every set is called. */
  var addSetAsk = window.ADspaceAsk.inline($('addBatch'), {
    label: 'Content set name', placeholder: 'Content set name',
    value: function () { return thisMonth(); },
    save: function (title) { makeBatch(title); }
  });
  $('addBatch').addEventListener('click', function () {
    addSetAsk.press();
  });
  function makeBatch(title) {
    db.from('batches').insert({
      client_id: state.client.id, title: title, published: false
    }).select().single().then(function (r) {
      if (r.error) { msg('setsMsg', r.error.message, 'err'); return; }
      loadBatches();
      openBatch(r.data);
    });
  }

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

      /* `.select()` so the answer says what was removed. A delete the database
         refuses returns no error at all — PostgREST answers 204 and the row
         simply stays — so without this the panel closed, nothing was said, and
         the set was still in the list underneath. A refusal is a sentence on
         the screen, never a success nobody can tell from one. */
      db.from('batches').delete().eq('id', b.id).select('id').then(function (res) {
        if (res.error) { msg('setMsg', res.error.message, 'err'); return; }
        if (!(res.data || []).length) {
          msg('setMsg', 'Not deleted. The database refused the request.', 'err');
          return;
        }
        logAction('set.deleted', state.client.name + ' — ' + b.title,
          n + ' post' + (n === 1 ? '' : 's') + (b.published ? ', was published' : ', was draft'));
        state.batch = null;
        clearDrafts();
        $('setPanel').hidden = true;
        loadBatches();
      });
    });
  });

  /* The title is already on the screen, so the pen edits it where it sits and
     becomes the tick that saves it. It used to open a browser prompt, which is
     a window over the page asking for a value the page was already showing. */
  $('renameSet').addEventListener('click', function () {
    var btn = this;
    window.ADspaceAsk.rename($('setTitle'), btn, {
      label: 'Content set name', max: 120,
      saveLabel: 'Save name',
      save: function (title) {
        db.from('batches').update({ title: title }).eq('id', state.batch.id).then(function (r) {
          if (r.error) { msg('setMsg', r.error.message, 'err'); return; }
          state.batch.title = title;
          paintSetHeader();
          loadBatches();
        });
      }
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
        ' exceeds the ' + (cfg.maxUploadMB || 50) + ' MB limit. Export a smaller review copy or paste a link.', 'err');
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
          msg('setMsg', slow.join(', ') + ': not web-optimised, so playback waits for the full download. ' +
            'Re-export with Fast Start.', 'err');
        } else if (!toobig.length) {
          msg('setMsg', 'Upload complete.', 'ok');
        }
        renderDrafts();
      })
      .catch(function (e) {
        state.uploading = false;
        showProgress(null);
        var text = e.message || 'Upload failed.';
        if (/payload|too large|exceeded/i.test(text)) {
          text = 'File exceeds the ' + (cfg.maxUploadMB || 50) +
            ' MB limit. Export a smaller review copy or paste a link.';
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
        msg('setMsg', 'Link could not be loaded. It must point directly to the file.', 'err');
        return;
      }
      pushDraft(url, info);
      $('mediaUrl').value = '';
      msg('setMsg', 'Asset added.', 'ok');
    });
  });

  function handleDriveLink(url) {
    if (!driveKey()) {
      msg('setMsg', 'Drive import requires a Google API key in js/config.js. See docs/DRIVE-IMPORT-CHECK.md.', 'err');
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
      msg('setMsg', 'No file id found in that Drive link. Use Share in Drive and copy the link.', 'err');
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
        // Neutral: nothing has happened yet. Green is kept for the import
        // actually finishing, so it means the same thing everywhere.
        msg('driveMsg', files.length + ' file' + (files.length === 1 ? '' : 's') + ' found' +
          (fresh ? ', ' + fresh + ' not imported yet.' : '. All of them are already in storage.'));
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
      // Drive knows the pixel size of an image but often not of a video, and
      // "size unknown" beside a figure in megabytes read as a contradiction.
      var spec = [f.width ? f.width + ' x ' + f.height : '', f.size ? mb(f.size) + ' MB' : '']
        .filter(Boolean).join(' \u00b7 ');
      card.innerHTML =
        '<input type="checkbox"' + (f.pick ? ' checked' : '') + (f.done ? ' disabled' : '') + '>' +
        '<span class="dfile-img"><img loading="lazy" alt="">' +
          '<i>' + esc(extFor(f.mimeType, f.name).toUpperCase()) + '</i></span>' +
        '<span class="dfile-meta"><b>' + esc(f.name) + '</b>' +
          '<span class="dfile-status status ' +
            (f.done ? 'status-approved' : 'status-pending') + '">' +
            (f.done ? 'Imported' : 'Not imported') + '</span>' +
          (spec ? '<span class="muted">' + spec + '</span>' : '') +
        '</span>';
      // Drive has no thumbnail for every file. Fall back to the file type
      // rather than leaving a browser's broken image icon on screen.
      var thumb = card.querySelector('img');
      thumb.addEventListener('error', function () {
        card.querySelector('.dfile-img').classList.add('is-blank');
      });
      thumb.src = 'https://drive.google.com/thumbnail?id=' + f.id + '&sz=w400';
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
        state.drafts.length + ' images uploaded. Separate posts, or one carousel?';
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
          '<textarea class="textarea" data-f="caption" placeholder="Caption">' +
            esc(d.caption) + '</textarea>' +
          (d.showZh
            ? '<textarea class="textarea" data-f="caption_zh" placeholder="中文文案">' + esc(d.caption_zh) + '</textarea>'
            : '<button class="linkbtn" data-f="addzh" type="button">Add Chinese caption</button>') +
        '</div>';

      if (d.media.length > 1) {
        var body = row.querySelector('.draft-body');
        var strip = slidesNode(d.media, function () { saveDrafts(); renderDrafts(); });
        var hint = el2('div', 'slide-hint');
        hint.textContent = d.placement === 'facebook:multi'
          ? 'Photo 1 takes the largest tile.'
          : 'Slide 1 is the cover and sets the carousel shape.';
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
        /* A failed read used to print "Nothing added yet." over a set that
           was full, which is the one message that makes somebody add a post
           twice. */
        if (r.error) {
          $('savedCount').textContent = '';
          failLine(box, 'Posts', r.error.message, loadPosts);
          settleScroll();
          return;
        }
        var n = (r.data || []).length;
        $('savedCount').textContent = n
          ? n + ' post' + (n === 1 ? '' : 's') + ' in this set.'
          : 'Nothing added yet.';
        if (!n) { settleScroll(); return; }

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

  // The ⋯ this portal draws everywhere a row hides its rarer actions.
  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">' +
    '<circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>';

  var ICON = {
    pencil: '<path d="M4 20h4L19.5 8.5a2.1 2.1 0 0 0-3-3L5 17z"/><path d="M14.5 6.5l3 3"/>',
    trash:  '<path d="M4 7h16"/><path d="M9 7V5.5A1.5 1.5 0 0 1 10.5 4h3A1.5 1.5 0 0 1 15 5.5V7"/>' +
            '<path d="M6.5 7 7.4 19a1.6 1.6 0 0 0 1.6 1.5h6a1.6 1.6 0 0 0 1.6-1.5L17.5 7"/>',
    redo:   '<path d="M21 12a9 9 0 1 1-2.6-6.4"/><path d="M21 4v4h-4"/>',
    copy:   '<rect x="9" y="9" width="11" height="11" rx="2"/>' +
            '<path d="M5 15H4.5A1.5 1.5 0 0 1 3 13.5v-9A1.5 1.5 0 0 1 4.5 3h9A1.5 1.5 0 0 1 15 4.5V5"/>',
    tick:   '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
    qr:     '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/>' +
            '<rect x="3" y="14" width="7" height="7" rx="1"/><path d="M14 14h3v3h-3z"/>' +
            '<path d="M20 14v3M14 20h3M20 20h.01"/>'
  };

  /* A round mark with the action named for anyone who cannot see the shape. */
  function iconBtn(name, action, label, tone) {
    return '<button class="iconbtn' + (tone ? ' ' + tone : '') + '" data-a="' + action +
      '" type="button" title="' + label + '" aria-label="' + label + '">' +
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" ' +
      'stroke-linejoin="round" aria-hidden="true">' + ICON[name] + '</svg></button>';
  }

  /* Creator Campaigns lives in its own file, because this one is long enough.
     It needs the same marks, the same activity record and the same idea of who
     is signed in, so those are lent rather than written twice. */
  window.ADspaceAdmin = {
    ICON: ICON,
    iconBtn: iconBtn,
    /* The one list of what each logged action is called. The client record's
       Activity pane reads it rather than keeping a second copy that would
       drift from the activity record's own. */
    actionLabel: ACTION_LABEL,
    log: logAction,
    actor: function () { return actor; },
    actorName: function () { return (me && me.name) || actor; },
    /* The client record and a campaign draw their own activity excerpt, so
       they resolve a logged address through the same map rather than keeping
       a second one that would answer differently. */
    whoName: whoName,
    // The signed PUT to S3, so an invoice PDF travels the same road as media.
    putToS3: putToS3,
    // Where you are, and how far down. The address bar is shared property.
    setUrl: setUrl,
    pushUrl: pushUrl,
    restoreScroll: restoreScroll,
    // Campaigns announces itself once its script has run; if the rail asked
    // for it before then, enter now.
    campaignsReady: function () {
      if (enterLater !== 'campaigns' || section !== 'campaigns') return;
      enterLater = '';
      window.ADspaceCampaigns.enter();
    },
    crmReady: function () {
      if (enterLater === 'services' && section === 'services') {
        enterLater = '';
        window.ADspaceCRM.enterServices();
        return;
      }
      if (enterLater !== 'clients' || section !== 'clients') return;
      enterLater = '';
      window.ADspaceCRM.enter();
    },
    teamReady: function () {
      if (enterLater !== 'team' || section !== 'team') return;
      enterLater = '';
      window.ADspaceTeam.enter();
    },
    // The signed-in person's team row, for sections that gate on it.
    me: function () { return me; },
    may: may,
    parts: PARTS
  };

  /* Pending, approved, changes requested. The dot is what you scan for; the
     word is what makes it mean something. */
  function statusMark(review) {
    var kind = !review ? 'pending'
             : review.decision === 'approved' ? 'approved' : 'changes';
    var word = kind === 'pending' ? 'Pending'
             : kind === 'approved' ? 'Approved' : 'Changes requested';
    return '<span class="status status-' + kind + '">' + word + '</span>';
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
          '<span class="saved-meta">' + statusMark(review) +
            '<span class="sep">&middot;</span>' +
            '<span class="spec">' + esc(fileLabel(m)) + '</span>' +
          '</span>' +
          // A post with no copy yet says nothing rather than saying "No caption".
          ((p.caption || p.caption_zh)
            ? '<span class="muted">' + esc((p.caption || p.caption_zh).slice(0, 90)) + '</span>'
            : '') +
          (review && review.decision === 'changes' && review.note
            ? '<span class="saved-note">' + esc(review.note) + '</span>' : '') +
          (p.review_reset_note
            ? '<span class="saved-note is-warn">Sent back: ' + esc(p.review_reset_note) + '</span>'
            : '') +
        '</div>' +
        // Two marks, not two words. Secondary actions should not outweigh the
        // name of the placement they belong to.
        '<div class="saved-actions">' +
          (review && review.decision === 'approved'
            ? iconBtn('redo', 'reask', 'Request re-approval', 'is-warn') : '') +
          iconBtn('pencil', 'edit', 'Edit post') +
          iconBtn('trash', 'del', 'Delete post', 'is-danger') +
        '</div>';

      row.querySelector('[data-a="edit"]').addEventListener('click', paintEdit);

      /* The client reads this, so it is a note and not a value: it opens under
         the control that sends it rather than in a browser window over the
         post it is about. */
      var reask = row.querySelector('[data-a="reask"]');
      if (reask) reask.addEventListener('click', function () {
        if (reask._ask) { reask._ask.open(); return; }
        reask._ask = window.ADspaceAsk.note(reask, {
          label: 'Reason for re-approval', send: 'Request re-approval',
          placeholder: 'Why the client is being asked again. They read this.',
          save: function (why) {
            db.from('posts').update({
              review_reset_at: new Date().toISOString(),
              review_reset_note: why
            }).eq('id', p.id).then(function (r) {
              if (r.error) { msg('setMsg', r.error.message, 'err'); return; }
              logAction('reapproval.requested',
                state.client.name + ' — ' + MK.label(p), why);
              msg('setMsg', 'Re-approval requested.', 'ok');
              loadPosts();
            });
          }
        });
        reask._ask.open();
      });
      row.querySelector('[data-a="del"]').addEventListener('click', function () {
        if (!confirm('Delete this post?\n\nIt will be removed from the client view.')) return;
        // Same as the set above: the answer was thrown away entirely here, so a
        // refused delete repainted the list with the post still in it.
        db.from('posts').delete().eq('id', p.id).select('id').then(function (r) {
          if (r.error) { msg('setMsg', r.error.message, 'err'); return; }
          if (!(r.data || []).length) {
            msg('setMsg', 'Not deleted. The database refused the request.', 'err');
            return;
          }
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
            '<button class="btn btn-primary btn-sm" data-a="save" type="button">Save</button>' +
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

  /* ---- Short Links -------------------------------------------------------
     This list is live: hi.adspace.me is a Cloudflare Worker (workers/links/)
     that reads it one slug at a time through link_resolve, so a row saved here
     redirects as soon as it is saved and a row paused here stops redirecting.
     The page used to carry a "Not live yet." line under the table; the Worker
     is deployed, so that line would now be a standing fact that is false.

     The host is one value in js/config.js, read here and written into the
     field's prefix, because it was typed into this file and into the console's
     markup and the two could disagree. `go.adspace.me` is deliberately not
     retired and is not served by that Worker: a QR code encodes the whole
     address, so the ones already printed on slides keep working for as long as
     that host redirects. This value decides what the next link is built with. */
  var LINK_HOST = (window.ADSPACE_CONFIG && window.ADSPACE_CONFIG.linkHost) || 'go.adspace.me';
  if ($('slugPrefix')) $('slugPrefix').textContent = LINK_HOST + '/';
  /* The host a link redirects from is a standing fact about the route, so it
     is the quiet line under the register: the team asked where these links
     live, and the field's prefix is only on screen while one is being added.
     go.adspace.me is named because the QR codes printed before this portal
     encode it whole and keep working. */
  if ($('linkNote')) $('linkNote').innerHTML = 'Short links redirect from <b>' + LINK_HOST + '</b>. ' +
    'Codes printed with <b>go.adspace.me</b> keep working.';
  var links = [];
  var editingSlug = null;

  // What a slug may be: the part after the slash, and safe in a URL as typed.
  function slugOk(s) { return /^[a-z0-9][a-z0-9._-]{0,79}$/.test(s); }

  // People paste the whole short link as often as they type the slug alone.
  function cleanSlug(s) {
    return String(s == null ? '' : s).trim()
      .replace(/^https?:\/\//i, '').replace(/^[^/]*\//, '')
      .replace(/^\/+|\/+$/g, '').toLowerCase();
  }
  /* Returns '' for anything that is not plausibly a destination. Without the
     hostname check, a stray line like "BROKEN LINE ONLY" in a pasted export
     parses as the slug "broken" pointing at "https://LINE", and a bad row
     imports silently instead of being reported. */
  function cleanTarget(u) {
    var v = String(u == null ? '' : u).trim();
    if (!v) return '';
    if (/^https?:\/\//i.test(v)) return v;
    return /^[a-z0-9-]+(\.[a-z0-9-]+)+([:/?#]|$)/i.test(v) ? 'https://' + v : '';
  }
  function shortUrl(slug) { return 'https://' + LINK_HOST + '/' + slug; }

  function loadLinks() {
    var box = $('linkList');
    box.innerHTML = '<div class="empty">Loading…</div>';
    db.from('links').select('*').order('slug').then(function (r) {
      if (r.error) {
        links = [];
        box.innerHTML = '<div class="softpanel"><div class="errline">' +
          '<b>Could not load the links.</b><span>' + esc(r.error.message) + '</span>' +
          '<button class="btn btn-sm" data-a="retry" type="button">Try again</button>' +
          '</div></div>';
        box.querySelector('[data-a="retry"]').addEventListener('click', loadLinks);
        $('linkCount').textContent = '';
        return;
      }
      links = r.data || [];
      paintLinks();
    });
  }

  /* A slug is looked at far more often than it is changed, so the list is a
     table with columns rather than fifty bordered cards each holding the same
     four icons. Copy is the everyday action and stays on the row; the rest
     move into the ⋯, where this portal already puts a rare or destructive
     one. */
  function linkShown() {
    var q = $('linkSearch').value.trim().toLowerCase();
    var st = $('linkState') ? $('linkState').value : '';
    return links.filter(function (l) {
      var live = l.active !== false;
      if (st === 'live' && !live) return false;
      if (st === 'paused' && live) return false;
      if (!q) return true;
      return (l.slug + ' ' + (l.target_url || '') + ' ' + (l.title || ''))
        .toLowerCase().indexOf(q) > -1;
    });
  }

  function paintLinks() {
    var box = $('linkList');
    var shown = linkShown();
    var filtered = shown.length !== links.length;

    $('linkCount').textContent = !links.length ? '' :
      (filtered ? shown.length + ' of ' + links.length
                : links.length + (links.length === 1 ? ' link' : ' links'));

    box.innerHTML = '';
    if (!links.length) {
      box.innerHTML = '<div class="softpanel"><div class="emptyline">' +
        '<b>No short links yet.</b>' +
        '<button class="btn btn-sm" data-a="first" type="button">Add the first link</button>' +
        '</div></div>';
      box.querySelector('[data-a="first"]').addEventListener('click', function () { openLinkForm(null); });
      return;
    }
    if (!shown.length) {
      box.innerHTML = '<div class="softpanel"><div class="emptyline">' +
        '<b>No matches.</b><button class="btn btn-sm" data-a="clear" type="button">Clear the filters</button>' +
        '</div></div>';
      box.querySelector('[data-a="clear"]').addEventListener('click', function () {
        $('linkSearch').value = '';
        if ($('linkState')) $('linkState').value = '';
        paintLinks();
      });
      return;
    }

    var table = document.createElement('div');
    table.className = 'crm-table softpanel';
    /* No Status column: Live is true of nearly every row, so the heading stood
       over a cell that was empty almost always and read as something broken.
       The exception is named beside the slug instead, the way the rate card
       names an inactive service. The last cell stays empty over the actions,
       the way every other table in this console does. */
    table.innerHTML = '<div class="crm-head link-row"><span>Short link</span>' +
      '<span>Destination</span><span>Label</span><span></span></div>';

    shown.forEach(function (l) {
      var off = l.active === false;
      var row = document.createElement('div');
      row.className = 'link-row' + (off ? ' is-off' : '');
      row.innerHTML =
        // Live is true of nearly every row, so only the exception is named,
        // and it is named beside the thing it is true of.
        '<span class="link-slug">/' + esc(l.slug) +
          (off ? ' <span class="tone is-warn">Paused</span>' : '') + '</span>' +
        '<span class="link-target">' + esc(l.target_url || '') + '</span>' +
        '<span class="link-label">' + esc(l.title || '') + '</span>' +
        '<span class="link-act">' +
          iconBtn('copy', 'copy', 'Copy short link') +
          iconBtn('qr',   'qr',   'QR codes') +
          '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
          '<div class="kmenu" data-menu hidden>' +
            '<button class="kmenu-item" data-a="edit" type="button"><b>Edit</b></button>' +
            '<button class="kmenu-item is-danger" data-a="del" data-need="links:manage" type="button"><b>Delete link</b></button>' +
          '</div>' +
        '</span>';

      row.querySelector('[data-a="copy"]').addEventListener('click', function (e) {
        window.ADspaceCopy.to(e.currentTarget, shortUrl(l.slug));
      });
      row.querySelector('[data-a="qr"]').addEventListener('click', function () { openQr(l); });
      row.querySelector('[data-a="edit"]').addEventListener('click', function () {
        shutLinkMenus(); editLink(l);
      });
      row.querySelector('[data-a="del"]').addEventListener('click', function () {
        shutLinkMenus(); removeLink(l);
      });
      wireLinkMenu(row);
      table.appendChild(row);
    });
    box.appendChild(table);
  }

  function shutLinkMenus() {
    Array.prototype.forEach.call(document.querySelectorAll('#linkList .kmenu'), function (m) { m.hidden = true; });
    Array.prototype.forEach.call(document.querySelectorAll('#linkList .kmenu-btn'), function (b) {
      b.setAttribute('aria-expanded', 'false');
    });
  }
  function wireLinkMenu(row) {
    var btn = row.querySelector('[data-a="menu"]');
    var menu = row.querySelector('[data-menu]');
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      var open = menu.hidden;
      shutLinkMenus();
      menu.hidden = !open;
      btn.setAttribute('aria-expanded', String(open));
      if (open) window.ADspaceMenu.place(btn, menu);
    });
  }
  document.addEventListener('click', function (e) {
    if (!e.target.closest || !e.target.closest('#linkList .kmenu, #linkList .kmenu-btn')) shutLinkMenus();
  });
  window.ADspaceMenu.onScroll(shutLinkMenus);
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') shutLinkMenus(); });

  if ($('linkState')) $('linkState').addEventListener('change', paintLinks);

  function openLinkForm(link) {
    editingSlug = link ? link.slug : null;
    $('linkFormTitle').textContent = link ? 'Edit short link' : 'New short link';
    $('saveLink').textContent = link ? 'Save' : 'Create';
    $('newSlug').value = link ? link.slug : '';
    $('newTarget').value = link ? (link.target_url || '') : '';
    $('newLinkLabel').value = link ? (link.title || '') : '';
    $('addLinkBox').hidden = false;
    $('importBox').hidden = true;
    msg('linkMsg', '');
    $('newSlug').focus();
  }
  function shutLinkForm() { $('addLinkBox').hidden = true; editingSlug = null; msg('linkMsg', ''); }

  function editLink(l) { openLinkForm(l); }

  function removeLink(l) {
    if (!confirm('Delete /' + l.slug + '?\n\nAnywhere this link is already printed or posted will stop working.')) return;
    db.from('links').delete().eq('slug', l.slug).then(function (r) {
      if (r.error) { msg('linkMsg', r.error.message, 'err'); return; }
      logAction('shortlink.deleted', '/' + l.slug, l.target_url || '');
      loadLinks();
    });
  }

  $('showAddLink').addEventListener('click', function () { openLinkForm(null); });
  $('cancelAddLink').addEventListener('click', shutLinkForm);
  $('linkSearch').addEventListener('input', paintLinks);

  $('saveLink').addEventListener('click', function () {
    var slug = cleanSlug($('newSlug').value);
    var target = cleanTarget($('newTarget').value);
    if (!slug)       { msg('linkMsg', 'A short link needs a slug.', 'err'); return; }
    if (!slugOk(slug)) {
      msg('linkMsg', 'Use lowercase letters, digits, dots, dashes or underscores.', 'err');
      return;
    }
    if (!target) {
      msg('linkMsg', $('newTarget').value.trim()
        ? 'That destination does not look like a web address.'
        : 'A destination is required.', 'err');
      return;
    }

    // Renaming a slug is a new row plus a delete, so catch the collision first.
    var clash = links.filter(function (l) { return l.slug === slug && l.slug !== editingSlug; });
    if (clash.length) { msg('linkMsg', '/' + slug + ' is already in use.', 'err'); return; }

    var body = {
      slug: slug, target_url: target,
      title: $('newLinkLabel').value.trim() || null,
      created_by: actor || null
    };
    var was = editingSlug;

    db.from('links').upsert(body, { onConflict: 'slug' }).then(function (r) {
      if (r.error) { msg('linkMsg', r.error.message, 'err'); return; }
      if (was && was !== slug) {
        db.from('links').delete().eq('slug', was).then(function () { loadLinks(); });
      } else {
        loadLinks();
      }
      logAction(was ? 'shortlink.updated' : 'shortlink.created', '/' + slug, target);
      shutLinkForm();
    });
  });

  /* ---- QR codes ----------------------------------------------------------
     A QR is a picture of a URL. Once printed it decodes to that URL forever,
     so there is no revoking the image. Each code therefore carries its own
     identity and the redirector is what turns a revoked one away:

         https://go.adspace.me/<slug>?q=<code>

     One slug can hold several, so a single placement can be pulled without
     taking the rest of the campaign down with it. The encoded text never
     changes for a given code, which is what makes the picture permanent. */
  var qrLink = null;
  var qrCodes = [];

  function qrUrl(slug, code) { return shortUrl(slug) + '?q=' + code; }

  function makeCode() {
    var a = new Uint8Array(5);
    crypto.getRandomValues(a);
    return Array.from(a, function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
  }

  /* Draws into a fresh element every time. qrcodejs appends rather than
     replaces, so reusing a node stacks images on top of each other. */
  function drawQr(box, text, size) {
    box.innerHTML = '';
    if (!window.QRCode) {
      box.innerHTML = '<span class="muted">QR library did not load.</span>';
      return;
    }
    new window.QRCode(box, {
      text: text, width: size, height: size,
      correctLevel: window.QRCode.CorrectLevel.H
    });
  }

  /* Print wants far more than the screen does, so the file is rendered at a
     size nobody has to look at, off screen, and thrown away after. */
  function downloadQr(slug, code, label) {
    var tmp = document.createElement('div');
    tmp.style.cssText = 'position:fixed;left:-9999px;top:0';
    document.body.appendChild(tmp);
    drawQr(tmp, qrUrl(slug, code), 1024);
    setTimeout(function () {
      var canvas = tmp.querySelector('canvas');
      var img = tmp.querySelector('img');
      var data = canvas ? canvas.toDataURL('image/png') : (img && img.src);
      if (data) {
        var a = document.createElement('a');
        a.href = data;
        a.download = 'qr-' + slug + (label ? '-' + label.toLowerCase().replace(/[^a-z0-9]+/g, '-') : '') + '.png';
        document.body.appendChild(a);
        a.click();
        a.remove();
      }
      tmp.remove();
    }, 120);
  }

  function openQr(l) {
    qrLink = l;
    $('qrHeading').textContent = 'QR codes for /' + l.slug;
    $('qrLabel').value = '';
    msg('qrMsg', '');
    $('qrSheet').hidden = false;
    loadQrs();
  }
  function shutQr() { $('qrSheet').hidden = true; qrLink = null; }
  $('qrSheetClose').addEventListener('click', shutQr);
  $('qrSheet').addEventListener('click', function (e) {
    if (e.target === $('qrSheet')) shutQr();
  });

  function loadQrs() {
    var box = $('qrList');
    box.innerHTML = '<div class="empty">Loading…</div>';
    db.from('link_qrs').select('*').eq('slug', qrLink.slug)
      .order('created_at').then(function (r) {
        if (r.error) {
          box.innerHTML = '<div class="empty">Could not load the codes. ' + esc(r.error.message) + '</div>';
          return;
        }
        qrCodes = r.data || [];
        paintQrs();
      });
  }

  /* The timestamp is the database's to set, so a row that has not been read
     back yet simply has none. Saying nothing beats saying "Invalid Date". */
  function made(value, prefix) {
    if (!value) return '';
    var d = new Date(value);
    if (isNaN(d.getTime())) return '';
    return prefix + d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
  }

  function paintQrs() {
    var box = $('qrList');
    box.innerHTML = '';
    if (!qrCodes.length) {
      box.innerHTML = '<div class="empty">No codes.</div>';
      return;
    }
    qrCodes.forEach(function (q) {
      var card = document.createElement('div');
      card.className = 'qrrow' + (q.active ? '' : ' is-off');
      card.innerHTML =
        '<div class="qrrow-img"></div>' +
        '<div class="qrrow-body">' +
          '<b>' + esc(q.label || 'Untitled code') + '</b>' +
          (q.active ? '' : '<span class="act-tag is-danger" style="margin-left:8px">Revoked</span>') +
          '<span class="qrrow-url">' + esc(qrUrl(q.slug, q.code)) + '</span>' +
          '<span class="muted">' +
            [made(q.created_at, 'Created '), made(q.revoked_at, 'revoked ')]
              .filter(Boolean).join(' · ') +
          '</span>' +
          '<div class="qrrow-acts">' +
            '<button class="btn btn-sm" data-q="dl" type="button">Download PNG</button>' +
            '<button class="btn btn-sm btn-quiet" data-q="copy" type="button">Copy URL</button>' +
            '<button class="btn btn-sm btn-quiet' + (q.active ? ' is-danger' : '') +
              '" data-q="toggle" type="button">' + (q.active ? 'Revoke' : 'Restore') + '</button>' +
          '</div>' +
        '</div>';
      drawQr(card.querySelector('.qrrow-img'), qrUrl(q.slug, q.code), 132);
      card.querySelector('[data-q="dl"]').addEventListener('click', function () {
        downloadQr(q.slug, q.code, q.label);
      });
      card.querySelector('[data-q="copy"]').addEventListener('click', function (e) {
        var b = e.currentTarget;
        navigator.clipboard.writeText(qrUrl(q.slug, q.code)).then(function () {
          b.textContent = 'Copied';
          setTimeout(function () { b.textContent = 'Copy URL'; }, 1500);
        });
      });
      card.querySelector('[data-q="toggle"]').addEventListener('click', function () { toggleQr(q); });
      box.appendChild(card);
    });
  }

  function toggleQr(q) {
    var next = !q.active;
    if (!next && !confirm('Revoke "' + (q.label || 'this code') + '"?\n\n' +
        'Scans of this code will be turned away. /' + q.slug + ' keeps working.')) return;
    db.from('link_qrs').update({ active: next, revoked_at: next ? null : new Date().toISOString() })
      .eq('code', q.code).then(function (r) {
        if (r.error) { msg('qrMsg', r.error.message, 'err'); return; }
        logAction(next ? 'qr.restored' : 'qr.revoked', '/' + q.slug, q.label || q.code);
        loadQrs();
      });
  }

  $('qrNew').addEventListener('click', function () {
    if (!qrLink) return;
    var row = {
      code: makeCode(), slug: qrLink.slug,
      label: ($('qrLabel').value || '').trim() || null,
      active: true,
      created_by: actor || null
    };
    db.from('link_qrs').insert(row).then(function (r) {
      if (r.error) { msg('qrMsg', r.error.message, 'err'); return; }
      logAction('qr.created', '/' + qrLink.slug, row.label || row.code);
      $('qrLabel').value = '';
      msg('qrMsg', '');
      loadQrs();
    });
  });

  $('showImport').addEventListener('click', function () {
    $('importBox').hidden = false;
    $('addLinkBox').hidden = true;
    msg('importMsg', '');
    $('importText').focus();
  });
  $('cancelImport').addEventListener('click', function () { $('importBox').hidden = true; });

  /* A paste from Rebrandly is a slug, a destination, and sometimes a name.
     Splitting on tab, comma or a run of spaces covers every export shape
     without asking anyone to reformat fifty rows by hand. */
  function parseImport(text) {
    var rows = [], bad = [];
    String(text || '').split(/\r?\n/).forEach(function (line, i) {
      var raw = line.trim();
      if (!raw) return;
      var parts = raw.split(/\t|\s*,\s*|\s{2,}|\s+/);
      var slug = cleanSlug(parts.shift());
      var target = cleanTarget(parts.shift());
      var title = parts.join(' ').trim();
      if (!slug || !slugOk(slug) || !target) { bad.push(i + 1); return; }
      rows.push({ slug: slug, target_url: target, title: title || null, created_by: actor || null });
    });
    return { rows: rows, bad: bad };
  }

  $('runImport').addEventListener('click', function () {
    var parsed = parseImport($('importText').value);
    if (!parsed.rows.length) {
      msg('importMsg', 'Nothing to import. Each line needs a slug and a destination.', 'err');
      return;
    }
    // Last one wins, so a list with a repeated slug still imports cleanly.
    var seen = {};
    parsed.rows.forEach(function (r) { seen[r.slug] = r; });
    var rows = Object.keys(seen).map(function (k) { return seen[k]; });

    msg('importMsg', 'Importing ' + rows.length + '…');
    db.from('links').upsert(rows, { onConflict: 'slug' }).then(function (r) {
      if (r.error) { msg('importMsg', r.error.message, 'err'); return; }
      logAction('shortlink.imported', rows.length + ' links', '');
      var note = 'Imported ' + rows.length + (rows.length === 1 ? ' link.' : ' links.');
      if (parsed.bad.length) {
        note += ' Skipped line' + (parsed.bad.length === 1 ? ' ' : 's ') +
                parsed.bad.join(', ') + ' — could not read a slug and destination.';
      }
      msg('importMsg', note, parsed.bad.length ? 'warn' : 'ok');
      $('importText').value = '';
      loadLinks();
    });
  });
})();
