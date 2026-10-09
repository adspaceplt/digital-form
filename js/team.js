/*
 * Team — people and the groups they belong to.
 *
 * A person is in one group. The group says which sections its members open,
 * whether they see billing and the activity record, and whether they may
 * remove things. The database enforces it: the switches on a group are
 * copied onto its members by trigger and read by every policy.
 */
(function () {
  var API = window.ADspaceAPI;
  var db  = API && API.client;
  if (!API || !API.configured || !db) return;

  var $ = function (id) { return document.getElementById(id); };
  var bridge = window.ADspaceAdmin || {};
  /* What the database lets this colleague change here: a member and a group
     are written at Team Full Access (`team_admin`), and a colleague's
     invitation is an admin's alone (`invite-member`). A control the database
     would refuse is not drawn (audit, 2026-10-03). */
  function may(key, level) { return Boolean(bridge.may && bridge.may(key, level)); }
  function amAdmin() { var m = bridge.me && bridge.me(); return Boolean(m && (m.is_admin || m.role === 'admin')); }
  var log = bridge.log || function () {};
  var me = bridge.me || function () { return null; };
  /* Department and role standard are said once, in js/words.js; the sheet's
     two selects are filled from there before the segment is drawn. */
  var DEPT = window.ADspaceWords.dept, ROLE_STD = window.ADspaceWords.roleStd;
  [['tmDept', DEPT], ['tmRoleStd', ROLE_STD]].forEach(function (f) {
    var sel = document.getElementById(f[0]);
    if (sel) Object.keys(f[1]).forEach(function (k) { sel.add(new Option(f[1][k], k)); });
  });

  function esc(s) {
    return String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  }
  function msg(id, text, kind) {
    var el = $(id); if (!el) return;
    el.textContent = text || ''; el.className = 'msg' + (kind ? ' ' + kind : '');
  }

  /* ACCESS IS A LEVEL PER SECTION.
     It used to be eight booleans, six of them all-or-nothing section access
     and one — `can_remove` — a single hard-delete authority shared by
     clients, contacts, letters, rate card lines, short links, creators and
     content sets. Granting it so a group could delete one of those granted
     all of them.

     Four levels, ranked, drawn on reversibility rather than on
     add/edit/delete/share: add, edit and publish can all be undone (Unpublish
     exists), a permanent deletion cannot. A matrix of sections against verbs
     would be twenty eight switches per group, about sixteen of which name
     nothing this portal does, and this page already replaced one permission
     matrix for exactly that reason. */
  /* The words the user chose (2026-10-01): No Access, View, Manage, Full
     Access. Only the words moved; the stored keys (none, view, work,
     manage) and what each opens are as they were. */
  var LEVELS = [
    ['none',   'No Access'],
    ['view',   'View'],
    ['work',   'Manage'],
    ['manage', 'Full Access']
  ];
  var LEVEL_WORD = { view: 'View', work: 'Manage', manage: 'Full Access' };
  var SCOPE_WORD = { all: 'All clients', own: 'Own clients only' };
  function readScope() { var el = document.getElementById('grScope'); return el && el.value === 'own' ? 'own' : 'all'; }

  /* Each section offers the levels that mean something in it. The activity
     record is a log, so it is read or not read; administering the team is one
     authority rather than a ladder. */
  /* The rail's order, so a person granting access reads the sections in the
     sequence they will meet them on the screen. */
  var SECTIONS = [
    /* Operations, which the console calls My Work: View works your own
       tasks, Work also creates them, Manage also assigns an owner. The four
       parts under it are the exception to the rule below. */
    ['ops',       'My Work',           ['none', 'view', 'work', 'manage']],
    ['clients',   'Clients',           ['none', 'view', 'work', 'manage']],
    ['review',    'Content Review',    ['none', 'view', 'work', 'manage']],
    /* A shoot's video scripts, approved by the client and ticked on the day
       (2026-10-09). */
    ['scripts',   'Video Scripts',     ['none', 'view', 'work', 'manage']],
    ['campaigns', 'Creator Campaigns', ['none', 'view', 'work', 'manage']],
    /* Client reports are prepared here and published to the client portal.
       Their own section (2026-09-25), so a colleague can prepare reports
       without reading client records; Clients View still reads a client's
       finished reports on the record. */
    ['reports',   'Reports',           ['none', 'view', 'work', 'manage']],
    /* The documents issued and the serials the verify page answers; HR
       letters are a part of it, gated apart, because a colleague's letter is
       read by fewer people than a client's. Named as the nav names it: the
       ladder's key stays `register`, which is an address and not copy, but a
       panel granting "Register" while the rail read Documents made somebody
       check twice which one they had. */
    ['register',  'Documents',         ['none', 'view', 'work', 'manage']],
    ['links',     'Short Links',       ['none', 'view', 'work', 'manage']],
    ['services',  'Services',          ['none', 'view', 'work', 'manage']],
    ['team',      'Team',              ['none', 'manage']],
    ['activity',  'Activity record',   ['none', 'view']]
  ];

  /* A PART IS AN EXCEPTION TO ITS SECTION. Each section is made of the panes
     and lists below, and a part left at Same as section stores nothing: the
     database and the page both read the part's own level where one is set
     and the section's where none is. So the ordinary group is one select per
     section, and the group that may work Clients but not read Billing sets
     that one part and nothing else. Billing was a switch beside the ladder
     until 2026-09-22; it is a part now, with the same four levels. */
  var PARTS = {
    clients:   [['contacts', 'Contacts'], ['billing', 'Billing'], ['services', 'Services'],
                ['documents', 'Documents'], ['requests', 'Requests'], ['calls', 'Calls and visits'],
                /* The lead stages and Past (2026-10-03): No Access, View or
                   Manage on those records, and on everything filed under
                   them in every section (`client_row_seen`). */
                ['leads', 'Leads'], ['past', 'Past clients'],
                /* Request feedback on WhatsApp (2026-10-09): a group may
                   work Clients and still not message a client. */
                ['whatsapp', 'Send on WhatsApp']],
    review:    [['sets', 'Content sets'], ['settings', 'Client settings']],
    campaigns: [['campaigns', 'Campaigns'], ['creators', 'Creators List'], ['finance', 'Finance'],
                /* Send on WhatsApp in a booking's ⋯ (2026-10-09). */
                ['whatsapp', 'Send on WhatsApp']],
    register:  [['documents', 'Client documents'], ['hr', 'HR Letters'], ['types', 'Document types']],
    /* The record is already read a section at a time — the tab strip is its
       own — and its access was one switch over all of them, so opening the
       campaigns log to the team opened every client's billing change and
       every letter with it. Each tab is a part, and the database decides
       which rows arrive: `activity_section()` maps a tag to the section the
       console files it under, and the read policy asks the part. */
    activity:  [['ops', 'My Work'], ['clients', 'Clients'],
                ['review', 'Content Review'], ['scripts', 'Video Scripts'], ['campaigns', 'Creator Campaigns'],
                ['reports', 'Reports'], ['register', 'Documents'], ['links', 'Short Links'],
                ['services', 'Services'], ['team', 'Team'], ['handbook', 'Handbook']],
    /* THESE FOUR ARE THE EXCEPTION. Every other part is a pane *inside* its
       section's job, so it falls back to the section: a group that works
       Clients works its Billing pane unless somebody says otherwise. These
       four are the other direction — seeing every colleague's queue, reading
       the reports, editing the templates and correcting somebody else's
       hours are all *more* than "work my own tasks". So they are granted and
       never inherited, in the page and in `ops_granted()` alike, and their
       unset option reads No access rather than Same as section. */
    /* The three views of a person's own work (2026-09-24, the user asked for
       each view to be granted on its own) follow the section unless set:
       they show or hide a view of the same tasks, so the database's own
       rules on which tasks arrive are unchanged. Workload reads the whole
       team's queue and Report the team's figures, so those two are granted. */
    ops:       [['list', 'List view'], ['board', 'Board view'], ['calendar', 'Calendar view'],
                ['all', 'Workload and the whole team\'s tasks'], ['reports', 'Report view'],
                ['workflows', 'Templates and recurring tasks'], ['time', 'Another person\'s time records'],
                /* What an admin alone did before (2026-10-07): an admin's by
                   itself, any other group's once set. */
                ['numbering', 'Task numbering'], ['override', 'Move anyone\'s task and due date']],
    /* Everybody's monthly performance review: View reads them, Work scores,
       releases and answers disputes, Manage also reopens a final record.
       Granted like the four above, because administering the team is not
       reading its scores, and the master code is asked for on top. */
    team:      [['performance', 'Performance reviews'],
                ['perfadmin', 'Performance company figures, settings and removals'],
                ['settings', 'Business settings'], ['upgrade', 'Upgrade mode'],
                ['invite', 'Send invitation'], ['handbook', 'Handbook files'], ['announce', 'Announcements'],
                /* A notice to all colleagues or to those chosen (2026-10-09). */
                ['notice', 'Notices'],
                /* Every colleague's health check-ins by name (2026-10-07):
                   an admin's by itself, any other group's once set. */
                ['health', 'Health check-ins']],
    /* A report carrying a white-label client's logo, and the White label
       tick on a client's Brand (2026-10-07): granted, an admin's by itself
       and any other group's once set. */
    reports:   [['whitelabel', 'White label'], ['transfer', 'Transfer client'], ['ai', 'AI usage and limits'],
                /* Send on WhatsApp (2026-10-09): follows Reports unless shut. */
                ['whatsapp', 'Send on WhatsApp']]
  };
  /* The parts that are granted rather than inherited: each opens more than
     its section does, so silence means no. The same list the console reads
     (`OPS_GRANTED` in js/admin.js) and the database asks (`ops_granted()`). */
  var GRANTED = { 'ops.all': 1, 'ops.reports': 1, 'ops.workflows': 1, 'ops.time': 1, 'team.performance': 1,
    'reports.whitelabel': 1, 'ops.numbering': 1, 'ops.override': 1, 'team.perfadmin': 1, 'team.settings': 1,
    'team.upgrade': 1, 'team.invite': 1, 'team.handbook': 1, 'reports.transfer': 1, 'reports.ai': 1,
    'team.announce': 1, 'register.types': 1, 'team.health': 1, 'team.notice': 1 };
  function isGranted(key) { return Boolean(GRANTED[key]); }
  var VIEW_PARTS = { 'ops.list': 1, 'ops.board': 1, 'ops.calendar': 1 };

  /* The levels a part is actually asked for, read off the database's own
     checks (2026-09-24, the user found a select offering levels that did
     nothing): the whole team's queue and the reports are only ever read, the
     templates are read and edited, another person's hours are corrected at
     Manage alone, and every Activity record tab is read or not read. A part
     not named here takes all three. The unset option is the first line, so a
     granted part reads No access once and not twice. */
  var PART_LEVELS = {
    'ops.all': ['view'], 'ops.reports': ['view'], 'ops.workflows': ['view', 'work'],
    'ops.list': ['view'], 'ops.board': ['view'], 'ops.calendar': ['view'],
    'ops.time': ['manage'], 'team.performance': ['view', 'work', 'manage'], 'reports.whitelabel': ['work'],
    'ops.numbering': ['work'], 'ops.override': ['work'], 'team.perfadmin': ['work'], 'team.settings': ['work'],
    'team.upgrade': ['work'], 'team.invite': ['work'], 'team.handbook': ['work'], 'reports.transfer': ['work'],
    'reports.ai': ['work'], 'team.announce': ['work'], 'register.types': ['work'], 'team.health': ['work'],
    'team.notice': ['work'], 'clients.whatsapp': ['work'], 'reports.whatsapp': ['work'],
    'campaigns.whatsapp': ['work'],
    /* Leads and Past clients narrow the Clients level and never widen it;
       removing a client stays with Clients Full Access. */
    'clients.leads': ['view', 'work'], 'clients.past': ['view', 'work']
  };
  function partLevels(key) {
    if (PART_LEVELS[key]) return PART_LEVELS[key];
    if (key.indexOf('activity.') === 0) return ['view'];
    return ['view', 'work', 'manage'];
  }
  var RANK = { none: 0, view: 1, work: 2, manage: 3 };
  /* Whether a part's level says something its section does not. A view-only
     part that follows its section (the three My Work views) is the same as
     the section whenever the section opens at all: View on the List view of
     a group that works My Work is not an exception. */
  function adds(key, held, same) {
    if (!held || held === same) return false;
    var only = partLevels(key);
    if (VIEW_PARTS[key] && held !== 'none' && RANK[same] >= RANK[only[0]]) return false;
    return true;
  }
  /* A level stored before the select was narrowed is shown as what it
     grants: `work` on the team's queue grants reading it, which is View; `work`
     on another person's hours grants nothing, because only Manage is asked. */
  function offered(key, v) {
    if (!v || v === 'none') return v;
    var list = partLevels(key);
    if (list.indexOf(v) > -1) return v;
    var best = '';
    list.forEach(function (l) { if (RANK[l] <= RANK[v]) best = l; });
    if (best) return best;
    return isGranted(key) ? '' : 'none';
  }

  /* What a part holds that its section does not. An inherited part falls back
     to its section, so a stored level equal to it changes nothing; a granted
     part falls back to no access, so a stored `none` changes nothing either.
     Either way the answer is the empty string, which is Same as section on
     the panel and the absence of a key in the database. */
  function exceptionOf(acc, key) {
    var held = (acc && acc[key]) || '';
    if (!held) return '';
    var sec = key.split('.')[0];
    var same = isGranted(key) ? 'none' : ((acc && acc[sec]) || 'none');
    return adds(key, held, same) ? held : '';
  }
  var CAPS = [];

  function accessOf(r) {
    var a = r && r.access;
    if (typeof a === 'string') { try { a = JSON.parse(a); } catch (e) { a = null; } }
    return a || {};
  }

  var state = { rows: [], roles: [], editing: null };

  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>';
  function menuItem(action, label, cls, disabled) {
    return '<button class="kmenu-item ' + (cls || '') + '" data-a="' + action + '" type="button"' +
      (disabled ? ' disabled' : '') + '><b>' + esc(label) + '</b></button>';
  }
  function menuBtn(items) {
    return '<span class="team-act">' +
      '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
      '<div class="kmenu" data-menu hidden>' + items + '</div></span>';
  }
  /* A row whose ⋯ would hold nothing keeps its cell and draws no ⋯. */
  function rowMenu(items) { return items ? menuBtn(items) : '<span class="team-act"></span>'; }
  function shutMenus() {
    Array.prototype.forEach.call(document.querySelectorAll('#sectionTeam .kmenu'), function (m) { m.hidden = true; });
    Array.prototype.forEach.call(document.querySelectorAll('#sectionTeam .kmenu-btn'), function (b) { b.setAttribute('aria-expanded', 'false'); });
  }
  function wireMenu(el) {
    var btn = el.querySelector('[data-a="menu"]'), menu = el.querySelector('[data-menu]');
    if (!btn || !menu) return;
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      var open = menu.hidden;
      shutMenus();
      // Placed on the viewport, so the table's overflow cannot clip it.
      menu.hidden = !open;
      btn.setAttribute('aria-expanded', String(open));
      if (open) {
        window.ADspaceMenu.place(btn, menu);
      }
    });
  }
  window.ADspaceMenu.onScroll(shutMenus);
  document.addEventListener('click', function (e) {
    if (!e.target.closest || !e.target.closest('#sectionTeam .team-act')) shutMenus();
  });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') shutMenus(); });

  var pendingEdit = null;
  function openPending() {
    var id = pendingEdit; pendingEdit = null;
    var m = id && (state.rows || []).filter(function (x) { return x.id === id; })[0];
    if (m) openMemberBox(m, null);
  }
  function load() {
    state.loading = true;
    $('teamList').innerHTML = '<div class="softpanel"><div class="skel">' +
      '<div class="skel-row"></div><div class="skel-row"></div><div class="skel-row"></div>' +
      '<div class="skel-row"></div></div></div>';
    db.from('team_roles').select('*').order('position').order('name').then(function (r) {
      if (r.error) {
        state.loading = false;
        $('groupList').innerHTML = '<div class="softpanel"><div class="errline">' +
          '<b>Could not load the groups.</b><span>' + esc(r.error.message) + '</span></div></div>';
        return;
      }
      state.roles = r.data || [];
      paintGroups();
      fillRolePick();
      db.from('team_members').select('*').order('active', { ascending: false })
        .order('role').order('name').then(function (q) {
          if (q.error) {
            state.loading = false;
            $('teamList').innerHTML = '<div class="softpanel"><div class="errline">' +
              '<b>Could not load the team.</b><span>' + esc(q.error.message) + '</span></div></div>';
            return;
          }
          state.rows = q.data || [];
          state.loading = false;
          paintMembers();
          paintGroups();   // member counts and Delete depend on the rows
          if (pendingEdit) openPending();
        });
    });
  }

  function roleName(slug) {
    var r = state.roles.filter(function (x) { return x.slug === slug; })[0];
    return r ? r.name : slug;
  }
  function roleOptions(current) {
    return state.roles.map(function (r) {
      return '<option value="' + esc(r.slug) + '"' + (r.slug === current ? ' selected' : '') + '>' + esc(r.name) + '</option>';
    }).join('');
  }
  function fillRolePick() {
    var keep = $('tmRole').value;
    $('tmRole').innerHTML = roleOptions(keep || 'account');
  }

  // ---- Members ------------------------------------------------------------
  /* People are listed under the group they belong to, the way the rate card
     lists services under a category. A column of identical Group selects said
     the same thing the groups table below already says, three times over, and
     answered "who is in Sales" only by reading every row. The heading answers
     it, and moving somebody is Edit in the ⋯, where a rare action belongs. */
  var teamFind = '';

  function teamMatch(m) {
    if (!teamFind) return true;
    return (String(m.name || '') + ' ' + String(m.email || '') + ' ' + String(m.staff_code || '') + ' ' + whoLine(m))
      .toLowerCase().indexOf(teamFind) > -1;
  }

  function paintMembers() {
    var box = $('teamList');
    box.innerHTML = '';
    var all = state.rows;
    var rows = all.filter(teamMatch);
    var count = $('teamCount');
    if (count) {
      count.textContent = !all.length ? ''
        : rows.length === all.length ? all.length + (all.length === 1 ? ' member' : ' members')
        : rows.length + ' of ' + all.length;
    }

    if (!all.length) {
      box.innerHTML = '<div class="softpanel"><div class="emptyline"><b>No members.</b>' +
        '<button class="btn btn-sm" data-a="first" type="button">Add the first member</button></div></div>';
      box.querySelector('[data-a="first"]').addEventListener('click', function () { openMemberBox(null, this); });
      return;
    }
    if (!rows.length) {
      box.innerHTML = '<div class="softpanel"><div class="emptyline"><b>No matches.</b>' +
        '<button class="btn btn-sm" data-a="clear" type="button">Clear the filters</button></div></div>';
      box.querySelector('[data-a="clear"]').addEventListener('click', function () {
        teamFind = '';
        if ($('teamFind')) $('teamFind').value = '';
        paintMembers();
      });
      return;
    }

    /* A card per user group under its own heading, the shape every directory
       in this console takes; a group nobody is in draws no card, and a person
       whose group was deleted under them still has to be reachable. */
    var GRP = window.ADspaceGroup;
    var filtered = rows.length !== all.length;
    var placed = {};
    var groups = state.roles.map(function (r) {
      var mine = rows.filter(function (m) { return m.role === r.slug; });
      mine.forEach(function (m) { placed[m.id] = true; });
      return [r.slug, r.name, mine];
    });
    groups.push(['none', 'No group', rows.filter(function (m) { return !placed[m.id]; })]);
    groups.forEach(function (g) {
      if (!g[2].length) return;
      box.appendChild(GRP.section({
        route: 'team', key: g[0], name: g[1], count: g[2].length,
        shut: !filtered && GRP.shut('team', g[0], false),
        table: function () {
          var table = GRP.table('team-row', ['Person', 'Sign-in email', '', '']);
          /* The members table keeps its own row grid and header rule. */
          table.className = 'team-table softpanel';
          table.firstChild.className = 'team-head team-row';
          byName(g[2]).forEach(function (m) { table.appendChild(memberRow(m)); });
          return table;
        }
      }));
    });
  }

  if ($('teamFind')) $('teamFind').addEventListener('input', function () {
    teamFind = this.value.trim().toLowerCase(); paintMembers();
  });
  function byName(a) {
    return a.slice().sort(function (x, y) {
      if (Boolean(x.active) !== Boolean(y.active)) return x.active ? -1 : 1;
      return String(x.name || '').localeCompare(String(y.name || ''));
    });
  }
  /* A day as the portal writes it: 31 Dec 2027, 12 Sept 2027. */
  var MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
  function dayWord(iso) {
    var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso || ''));
    return m ? Number(m[3]) + ' ' + MON[Number(m[2]) - 1] + ' ' + m[1] : '';
  }
  function todayMy() { return new Date(Date.now() + 8 * 3600 * 1000).toISOString().slice(0, 10); }
  function nowMyTime() { return new Date(Date.now() + 8 * 3600 * 1000).toISOString().slice(11, 16); }
  /* 18:00 reads 6pm, 18:30 6.30pm, as the campaign schedule writes it. */
  function timeWord(t) {
    var m = /^(\d{2}):(\d{2})/.exec(String(t || ''));
    if (!m) return '';
    var h = Number(m[1]);
    return ((h % 12) || 12) + (m[2] === '00' ? '' : '.' + m[2]) + (h < 12 ? 'am' : 'pm');
  }
  /* A switch as the change log hands it over: records.js reads a boolean
     as Yes or No before the label's own words. */
  function off(v) { return v === false || v === 'No'; }
  function untilWord(day, time) { return dayWord(day) + (day && time ? ', ' + timeWord(time) : ''); }
  /* A moment still ahead in Malaysia: a later day, or today at a later time
     (no time is the day's end). */
  function aheadMy(day, time) {
    var today = todayMy();
    if (!day || day > today) return true;
    if (day < today) return false;
    return !time || String(time).slice(0, 5) > nowMyTime();
  }
  function whoLine(m) {
    var post = [DEPT[m.department], m.designation].filter(Boolean).join(', ');
    /* The day access ends, where one is set (TEAM ACCESS EXPIRY). */
    var until = m.active && m.access_until ? 'Until ' + untilWord(m.access_until, m.access_until_time) : '';
    return [post, until].filter(Boolean).join(' · ');
  }
  /* The database's refusals, in the team's words. */
  function teamSaid(e) {
    var t = String(e && e.message || e || '');
    if (/own-expiry/.test(t)) return 'Your own access date is set by another admin.';
    if (/expired-date/.test(t)) return 'Move the access date first.';
    if (/past-date/.test(t)) return 'Choose today or a later date.';
    if (/system-account/.test(t)) return 'This is a system account.';
    return t;
  }
  function memberRow(m) {
    var self = me() && me().id === m.id;
    /* A system account (2026-10-08) is IT's: shown with its tag, and only the
       account itself may change it (the database refuses anyone else), so
       nobody else is offered a control that would be refused. */
    var sysRow = Boolean(m.system) && !self;
    var manage = may('team', 'manage') && !sysRow;
    var el = document.createElement('div');
    el.className = 'team-row' + (m.active ? '' : ' is-off');
    el.innerHTML =
      /* Everyone on this list is active, so a green Active on every row spends
         the one accent on the ordinary case and leaves the exception looking
         like everything else. The row says nothing when a person is working
         and names it when they are not. */
      /* You is a designation, not a live state, so it is the neutral chip the
         rate card gives Inactive and not a word in the accent green. */
      /* The name with its Employee ID beside it (the user, 2026-10-03), then
         where they sit: "Creative, Production Executive". The HR serial and
         the signature on a letter are built from these, and the department
         is chosen from a list, so the line reads the same on every row
         whoever typed it. */
      '<span class="team-who"><b>' + esc(m.name) +
        (m.staff_code ? ' <span class="team-eid">' + esc(m.staff_code) + '</span>' : '') +
        (self ? ' <span class="tone">You</span>' : '') +
        (m.system ? ' <span class="tone">System</span>' : '') + '</b>' +
        (whoLine(m) ? '<small>' + esc(whoLine(m)) + '</small>' : '') +
      '</span>' +
      '<span class="team-mail">' + esc(m.email || '') + '</span>' +
      /* The exception only: Inactive, Access expired, or a card turned off
         for somebody still working; an ordinary row says nothing. */
      '<span class="team-state">' + (!m.active ? '<span class="tone is-off">' + (m.expired_at ? 'Access expired' : 'Inactive') + '</span>'
        : m.card_on === false ? '<span class="tone is-off">Card off</span>' : '') + '</span>' +
      /* Mail leaves the building and cannot be recalled, so Send invitation
         sits one place from Edit and asks first, as it does on a contact.
         Standing somebody down happens once in a job, so it is here rather
         than a select on every row. A person cannot switch themselves off. */
      rowMenu((manage ? menuItem('edit', 'Edit') : '') +
              (m.active && m.card_key && m.card_on !== false ? menuItem('card', 'Open namecard') : '') +
              (may('team.invite', 'work') && m.active && m.email && !sysRow ? menuItem('invite', 'Send invitation') : '') +
              (self || !manage ? '' : menuItem('state', m.active ? 'Set inactive' : (m.expired_at ? 'Extend access' : 'Set active'))));

    wireMenu(el);
    var nc = el.querySelector('[data-a="card"]');
    if (nc) nc.addEventListener('click', function () {
      shutMenus();
      window.open('/card/?k=' + encodeURIComponent(m.card_key), '_blank', 'noopener');
    });
    var st = el.querySelector('[data-a="state"]');
    if (st) st.addEventListener('click', function () {
      shutMenus();
      /* Setting somebody active again asks nothing: it is the way back from
         this, and the way back never asks. */
      /* Access that ended on its date comes back with a later date (the
         database brings them back as the date moves). */
      if (!m.active && m.expired_at) {
        window.ADspaceConfirm.ask({
          title: 'Extend access',
          body: m.name + '\'s access ended ' + (m.access_until_time ? 'at ' : 'after ') + untilWord(m.access_until, m.access_until_time) +
                '. Choose the new last day and, if it ends sooner, the time. Leave the day empty for no end.',
          go: 'Extend access',
          fields: [{ name: 'day', label: 'Access until', type: 'date', min: todayMy(), required: false },
                   { name: 'time', label: 'Time', type: 'time', required: false }]
        }, function (v) {
          var day = v.day || null, time = day ? (v.time || null) : null;
          if (day && !aheadMy(day, time)) { msg('teamMsg', 'Choose a later time.', 'err'); return; }
          saveMember(m, { access_until: day, access_until_time: time });
        });
        return;
      }
      if (!m.active) { saveMember(m, { active: true }); return; }
      /* Somebody who is stood down may still be the person in charge of
         clients and open campaigns, and a client whose person in charge
         cannot sign in is a client nobody is looking after. So the same sheet
         asks who takes them over, in the same breath, with Keep as the first
         answer because a stand-down can be for a week (the user,
         2026-09-26). A completed campaign keeps who ran it: that is history. */
      ownedBy(m.name, false, function (own) {
        var n = ownWord(own);
        var others = state.rows.filter(function (x) { return x.active && x.id !== m.id && x.name; });
        window.ADspaceConfirm.ask({
          title: 'Set inactive',
          body: m.name + ' loses access to every section until they are set active '
              + 'again here. Their record, their name on past work and everything '
              + 'they signed stay as they are.'
              + (n ? ' They are person in charge of ' + n + '.' : ''),
          go: 'Set inactive',
          tone: 'warn',
          field: n && others.length ? {
            label: 'Person in charge from now on',
            required: false,
            choices: [['', 'Keep with ' + m.name]].concat(others.slice().sort(window.ADspaceForm.byStaff).map(function (x) { return [x.name, window.ADspaceForm.named(x.staff_code, x.name)]; }))
          } : null
        }, function (to) {
          saveMember(m, { active: false }, function () {
            if (typeof to === 'string' && to) handOver(m.name, to, own);
          });
        });
      });
    });
    var ed = el.querySelector('[data-a="edit"]');
    if (ed) ed.addEventListener('click', function () { openMemberBox(m, this); });
    var inv = el.querySelector('[data-a="invite"]');
    if (inv) inv.addEventListener('click', function () { reinvite(m); });
    return el;
  }

  function saveMember(m, patch, then) {
    db.from('team_members').update(patch).eq('id', m.id).select('id').then(function (r) {
      if (r.error) { msg('teamMsg', teamSaid(r.error), 'err'); load(); return; }
      if (!(r.data || []).length) { msg('teamMsg', 'Not saved. The database refused the request.', 'err'); load(); return; }
      log('team.changed', m.name, Object.keys(patch).map(function (k) {
        if (k === 'active') return 'Active: ' + (m.active ? 'Yes' : 'No') + ' → ' + (patch.active ? 'Yes' : 'No');
        if (k === 'role') return 'User group: ' + roleName(m.role) + ' → ' + roleName(patch.role);
        if (k === 'access_until') return 'Access until: ' + (dayWord(m.access_until) || 'not set') + ' → ' + (dayWord(patch.access_until) || 'not set');
        if (k === 'access_until_time') return 'Access time: ' + (timeWord(m.access_until_time) || 'day\'s end') + ' → ' + (timeWord(patch.access_until_time) || 'day\'s end');
        return k + ': ' + (m[k] == null ? 'not set' : m[k]) + ' → ' + (patch[k] == null ? 'not set' : patch[k]);
      }).join('; '));
      msg('teamMsg', 'Saved.', 'ok');
      load();
      if (then) then();
    });
  }

  /* ---- Person in charge ----------------------------------------------------
     `clients.owner` and `campaigns.owner` hold the person's name as text, not
     an id, so the team page is where a stand-down or a rename has to follow
     through to the records that name them. Matched on the trimmed name in any
     case, because the field was typed by hand before it was a select. */
  function ownedBy(name, all, then) {
    var key = String(name || '').trim().toLowerCase();
    var none = { clients: [], campaigns: [] };
    if (!key) { then(none); return; }
    function mine(r) {
      return (r && !r.error ? r.data || [] : []).filter(function (x) {
        return String(x.owner || '').trim().toLowerCase() === key;
      });
    }
    Promise.all([
      db.from('clients').select('id, name, owner'),
      db.from('campaigns').select('id, title, owner, state')
    ]).then(function (res) {
      then({
        clients: mine(res[0]),
        campaigns: mine(res[1]).filter(function (c) { return all || c.state !== 'completed'; })
      });
    }, function () { then(none); });
  }
  function plural(n, one, many) { return n + ' ' + (n === 1 ? one : many); }
  function ownWord(own) {
    return [own.clients.length ? plural(own.clients.length, 'client', 'clients') : '',
            own.campaigns.length ? plural(own.campaigns.length, 'open campaign', 'open campaigns') : '']
      .filter(Boolean).join(' and ');
  }
  /* Each record is written with `.select('id')`, because a refused update is
     answered with no error and no row, and each move is filed under the client
     or the campaign it changed, so it reads on that record's own Activity. */
  function handOver(from, to, own, word) {
    var jobs = [];
    if (own.clients.length) jobs.push(db.from('clients').update({ owner: to })
      .in('id', own.clients.map(function (c) { return c.id; })).select('id'));
    if (own.campaigns.length) jobs.push(db.from('campaigns').update({ owner: to })
      .in('id', own.campaigns.map(function (c) { return c.id; })).select('id'));
    if (!jobs.length) return;
    Promise.all(jobs).then(function (res) {
      var moved = 0, bad = null;
      res.forEach(function (r) {
        if (r.error) bad = r.error.message;
        else moved += (r.data || []).length;
      });
      var want = own.clients.length + own.campaigns.length;
      if (bad || moved < want) {
        msg('teamMsg', 'Saved. The person in charge could not be moved on ' + (want - moved) +
          ' of ' + want + (bad ? ': ' + bad : '. The database refused the request.'), 'err');
        return;
      }
      own.clients.forEach(function (c) { log('client.edited', c.name, 'Person in charge: ' + from + ' to ' + to); });
      own.campaigns.forEach(function (c) { log('campaign.edited', c.title, 'Person in charge: ' + from + ' to ' + to); });
      msg('teamMsg', 'Saved. ' + (word || ownWord(own).replace(/^./, function (x) { return x.toUpperCase(); })) +
        ' now read ' + to + '.', 'ok');
    }, function () { msg('teamMsg', 'Saved. The person in charge could not be moved.', 'err'); });
  }

  // ---- Groups -------------------------------------------------------------
  /* A group is read far more often than it is changed: somebody deciding which
     group a new colleague goes in wants to know what each one opens. Eight
     columns of checkboxes answered that only by counting ticks across a table
     that had to scroll sideways to fit, and every switch added another column.
     So the row states the group in words and the ⋯ opens the switches, which
     is how a service and a contact are already edited. */
  function paintGroups() {
    var box = $('groupList');
    box.innerHTML = '';
    var head = document.createElement('div');
    head.className = 'group-head';
    head.innerHTML = '<span>Group</span><span>Access</span><span></span>';
    box.appendChild(head);
    state.roles.forEach(function (r) { box.appendChild(groupRow(r)); });
    var n = state.roles.length;
    $('groupCount').textContent = n ? n + (n === 1 ? ' group' : ' groups') : '';
  }

  /* What the group opens, in its own words, grouped by level so the strongest
     reads first. An admin group opens everything, and listing every section it
     can reach is a longer way of saying so. A column per switch was tried and
     removed: it is a table that grows every time the product does. */
  /* What an access save changed, section by section and part by part:
     "Clients: View → Work; Clients · Billing: Same as section → No access".
     Keys neither side holds are left out, so a save names only its moves. */
  function accessMoves(before, after) {
    before = before || {}; after = after || {};
    var name = function (k) {
      var bits = k.split('.');
      var sec = SECTIONS.filter(function (x) { return x[0] === bits[0]; })[0];
      var part = bits[1] && (PARTS[bits[0]] || []).filter(function (x) { return x[0] === bits[1]; })[0];
      return (sec ? sec[1] : bits[0]) + (bits[1] ? ' · ' + (part ? part[1] : bits[1]) : '');
    };
    var word = function (k, v) { return v ? (LEVEL_WORD[v] || 'No Access') : (k.indexOf('.') > -1 ? 'Same as section' : 'No Access'); };
    var keys = Object.keys(before).concat(Object.keys(after)).filter(function (k, i, a) { return a.indexOf(k) === i; });
    return keys.filter(function (k) { return (before[k] || '') !== (after[k] || ''); }).map(function (k) {
      return name(k) + ': ' + word(k, before[k]) + ' → ' + word(k, after[k]);
    }).join('; ');
  }
  function grantWord(r) {
    if (r.is_admin) return 'Everything';
    var acc = accessOf(r), parts = [];
    /* A section's exceptions read in brackets after its name
       (`Clients (Billing: No access)`), so the sentence still says what the
       group opens and then what it does not. */
    var word = function (s) {
      var ex = (PARTS[s[0]] || []).map(function (p) {
        var v = offered(s[0] + '.' + p[0], exceptionOf(acc, s[0] + '.' + p[0]));
        return v ? p[1] + ': ' + (LEVEL_WORD[v] || 'No Access') : '';
      }).filter(Boolean);
      return s[1] + (ex.length ? ' (' + ex.join(', ') + ')' : '');
    };
    ['manage', 'work', 'view'].forEach(function (lv) {
      var named = SECTIONS.filter(function (s) { return acc[s[0]] === lv; }).map(word);
      if (named.length) parts.push(LEVEL_WORD[lv] + ': ' + named.join(', '));
    });
    /* A part opened above a section that is shut is an exception too. */
    var only = SECTIONS.filter(function (s) { return (acc[s[0]] || 'none') === 'none'; }).map(function (s) {
      var ex = (PARTS[s[0]] || []).map(function (p) {
        var v = offered(s[0] + '.' + p[0], exceptionOf(acc, s[0] + '.' + p[0]));
        return v && v !== 'none' ? p[1] + ': ' + LEVEL_WORD[v] : '';
      }).filter(Boolean);
      return ex.length ? s[1] + ' (' + ex.join(', ') + ')' : '';
    }).filter(Boolean);
    if (only.length) parts.push('Only: ' + only.join(', '));
    if (r.client_scope === 'own') parts.push('Own clients only');
    return parts.length ? parts.join(' · ') : 'No Access';
  }

  function groupRow(r) {
    var locked = r.slug === 'admin';
    var used = state.rows.some(function (m) { return m.role === r.slug; });
    var el = document.createElement('div');
    el.className = 'group-row';
    var members = state.rows.filter(function (m) { return m.role === r.slug; }).length;
    el.innerHTML =
      '<span class="group-name"><b>' + esc(r.name) + '</b><small>' + members + ' member' + (members === 1 ? '' : 's') + '</small></span>' +
      '<span class="group-grants">' + esc(grantWord(r)) + '</span>' +
      (locked || !may('team', 'manage') ? '<span class="team-act"></span>'
        : menuBtn(menuItem('rename', 'Edit') + (used ? '' : menuItem('del', 'Delete', 'is-danger'))));

    wireMenu(el);
    var ren = el.querySelector('[data-a="rename"]');
    if (ren) ren.addEventListener('click', function () { openGroupBox(r, this); });
    var del = el.querySelector('[data-a="del"]');
    if (del) del.addEventListener('click', function () {
      window.ADspaceConfirm.ask({
        title: 'Delete',
        body: 'The ' + r.name + ' group and the access it carries go. There is no restore.',
        go: 'Delete',
        tone: 'danger'
      }, function () {
        /* PostgREST answers a delete a policy refused with no error and no
           row gone, so ask for the row back: an empty answer is a refusal,
           not a success, and the group stays in the list saying so. */
        db.from('team_roles').delete().eq('slug', r.slug).select('slug').then(function (q) {
          if (q.error) { msg('groupMsg', q.error.message, 'err'); return; }
          if (!q.data || !q.data.length) {
            msg('groupMsg', 'Not deleted. The database refused the request.', 'err');
            load();
            return;
          }
          log('team.group_removed', r.name, '');
          msg('groupMsg', r.name + ' deleted.', 'ok');
          load();
        });
      });
    });
    return el;
  }

  function saveGroup(r, patch) {
    var was = Object.assign({}, r, { access: Object.assign({}, r.access || {}) });
    db.from('team_roles').update(patch).eq('slug', r.slug).select('slug').then(function (q) {
      if (q.error) { msg('groupMsg', q.error.message, 'err'); load(); return; }
      if (!(q.data || []).length) { msg('groupMsg', 'Not saved. The database refused the request.', 'err'); load(); return; }
      Object.keys(patch).forEach(function (k) { r[k] = patch[k]; });
      log('team.group_changed', r.name, Object.keys(patch).map(function (k) {
        if (k === 'access') return accessMoves(was.access, patch.access);
        if (k === 'is_admin') return 'Admin: ' + (was.is_admin ? 'Yes' : 'No') + ' → ' + (patch.is_admin ? 'Yes' : 'No');
        if (k === 'name') return 'Name: ' + (was.name || 'not set') + ' → ' + patch.name;
        if (k === 'client_scope') return 'Clients they see: ' + SCOPE_WORD[was.client_scope || 'all'] + ' → ' + SCOPE_WORD[patch.client_scope];
        return k.replace('can_', '') + ': ' + was[k] + ' → ' + patch[k];
      }).filter(Boolean).join('; '));
      msg('groupMsg', 'Saved.', 'ok');
      // Members carry their group's switches; the console reads them at sign-in.
      load();
    });
  }

  /* What each level allows in each section, said once under its segment so a
     person granting it reads the consequence before saving (2026-09-25, the
     permissions revamp the user approved: "Build the revamp"). Each line is
     what the database's own checks open at that level. */
  var DESC = {
    ops: { none: 'My Work is hidden.', view: 'See and update your own tasks.',
           work: 'Also create tasks and add months.', manage: 'Also reassign and delete tasks.' },
    clients: { none: 'Clients is hidden.', view: 'Read client records.',
               work: 'Add leads, edit records, log calls and issue letters.', manage: 'Also delete clients and void letters.' },
    review: { none: 'Content Review is hidden.', view: 'Read content sets and posts.',
              work: 'Add sets and posts, import from Drive and publish.', manage: 'Also delete content sets.' },
    scripts: { none: 'Video Scripts is hidden.', view: 'Read scripts and download their PDFs.',
               work: 'Write scripts, publish them to the client and record the clips on the day.', manage: 'Also delete scripts.' },
    campaigns: { none: 'Creator Campaigns is hidden.', view: 'Read campaigns and the Creators List.',
                 work: 'Run campaigns, book creators and release drafts.', manage: 'Also delete campaigns and remove creators.' },
    register: { none: 'Documents is hidden.', view: 'Read and download documents.',
                work: 'Issue, reissue and add documents.', manage: 'Also void and delete documents.' },
    reports: { none: 'Reports is hidden.', view: 'Read reports and preview their PDFs.',
               work: 'Start reports, enter figures and submit them for review.', manage: 'Also confirm, publish, unpublish and delete reports.' },
    links: { none: 'Short Links is hidden.', view: 'Read short links.',
             work: 'Add, edit and pause short links.', manage: 'Also delete short links.' },
    services: { none: 'Services is hidden.', view: 'Read the rate card.',
                work: 'Add and edit rate card lines.', manage: 'Also delete rate card lines.' },
    team: { none: 'Team is hidden.', manage: 'Add colleagues, edit user groups and send invitations.' },
    activity: { none: 'The activity record is hidden.', view: 'Read the activity record, tab by tab.' }
  };

  /* A group starts from one of four shapes and is adjusted from there; a
     change that matches none of them reads as Custom. Sensitive parts (HR
     letters, performance reviews, Team) are never in a preset below Admin:
     they are opened deliberately, in Advanced. */
  var PRESETS = {
    manager: { ops: 'manage', clients: 'manage', review: 'manage', scripts: 'manage', campaigns: 'manage', register: 'manage', reports: 'manage',
               links: 'manage', services: 'manage', team: 'none', activity: 'view',
               'ops.all': 'view', 'ops.reports': 'view', 'ops.workflows': 'work', 'ops.time': 'manage',
               'register.hr': 'none' },
    staff:   { ops: 'work', clients: 'work', review: 'work', scripts: 'work', campaigns: 'work', register: 'view', reports: 'work',
               links: 'work', services: 'view', team: 'none', activity: 'none', 'register.hr': 'none' },
    viewer:  { ops: 'view', clients: 'view', review: 'view', scripts: 'view', campaigns: 'view', register: 'view', reports: 'view',
               links: 'view', services: 'view', team: 'none', activity: 'view', 'register.hr': 'none' }
  };

  /* One block per section: its name and the Advanced fold on the head line,
     the four levels as a segment, and one line saying what the chosen level
     allows. The parts sit folded under Advanced, each a select that starts
     at Same as section, and the fold counts only the parts that differ. A part
     is read where its section is, never in a second list (2026-09-22). */
  $('grFlags').innerHTML =
    SECTIONS.map(function (sec) {
      var parts = PARTS[sec[0]] || [];
      return '<div class="permsec" data-sec="' + sec[0] + '">' +
        '<div class="permsec-head"><span class="permsec-name">' + esc(sec[1]) + '</span>' +
          (parts.length
            ? '<button class="permsec-toggle" type="button" aria-expanded="false" aria-controls="grParts-' + sec[0] + '">' +
                '<span>Advanced</span><span class="permsec-n" data-n="' + sec[0] + '"></span>' +
                '<span class="disclosure-caret" aria-hidden="true">&#9656;</span></button>'
            : '') + '</div>' +
        '<select class="select" data-seg data-sec="' + sec[0] + '" aria-label="' + esc(sec[1]) + ' access">' +
          LEVELS.filter(function (l) { return sec[2].indexOf(l[0]) > -1; }).map(function (l) {
            return '<option value="' + l[0] + '">' + esc(l[1]) + '</option>';
          }).join('') + '</select>' +
        '<p class="permsec-desc" id="grDesc-' + sec[0] + '"></p>' +
        (parts.length ? '<div class="permsec-parts" id="grParts-' + sec[0] + '" hidden>' + parts.map(function (p) {
          var key = sec[0] + '.' + p[0], granted = isGranted(key);
          /* A part is a row: its name on the left and its select on one right
             edge, so every choice under the fold reads down one column. */
          return '<label class="permpart"><span class="permpart-name">' + esc(p[1]) + '</span>' +
            '<select class="select select-sm" data-part="' + key + '" aria-label="' + esc(sec[1] + ': ' + p[1]) + ' access">' +
            /* A granted part is not inherited, so its unset state is No
               access, said once; an inherited part starts at Same as
               section and may still be shut on its own. */
            (granted ? '<option value="">No Access</option>'
                     : '<option value="">Same as section</option><option value="none">No Access</option>') +
            /* A My Work view follows its section and has two states. */
            (VIEW_PARTS[key] ? '' :
              partLevels(key).map(function (l) { return '<option value="' + l + '">' + esc(LEVEL_WORD[l]) + '</option>'; }).join('')) +
            '</select></label>';
        }).join('') +
        /* Whose clients the group sees, in every section: all, or the ones
           its colleague is Person in charge of with any lead nobody holds
           (`team_roles.client_scope`). */
        (sec[0] === 'clients' ? '<label class="permpart"><span class="permpart-name">Clients they see</span>' +
          '<select class="select select-sm" id="grScope" aria-label="Clients: clients they see">' +
          '<option value="all">All clients</option><option value="own">Own clients only</option></select></label>' : '') +
        '</div>' : '') +
      '</div>';
    }).join('') +
    /* Admin is chosen from Start from, which already names it (2026-09-26):
       a second tick below the sections said the same thing twice. The box
       stays, unseen, because it is what the save reads. */
    CAPS.map(function (f) {
      return '<label class="perm"><input type="checkbox" data-f="' + f[0] + '"><span>' + esc(f[1]) + '</span></label>';
    }).join('') +
    '<input type="checkbox" data-f="is_admin" hidden tabindex="-1" aria-hidden="true">';
  function flagBoxes() { return Array.prototype.slice.call($('grFlags').querySelectorAll('input')); }
  function levelPicks() { return Array.prototype.slice.call($('grFlags').querySelectorAll('select[data-sec]')); }
  function partPicks() { return Array.prototype.slice.call($('grFlags').querySelectorAll('select[data-part]')); }
  levelPicks().forEach(function (sel) {
    if (window.ADspaceForm) window.ADspaceForm.segment(sel);
    if (sel.__seg) sel.__seg.setAttribute('aria-describedby', 'grDesc-' + sel.getAttribute('data-sec'));
  });
  if (window.ADspaceForm) window.ADspaceForm.segment($('grPreset'));
  function foldSec(sec, open) {
    var box = $('grParts-' + sec), btn = $('grFlags').querySelector('.permsec[data-sec="' + sec + '"] .permsec-toggle');
    if (!box || !btn) return;
    box.hidden = !open;
    btn.setAttribute('aria-expanded', String(open));
  }
  Array.prototype.forEach.call($('grFlags').querySelectorAll('.permsec-toggle'), function (btn) {
    btn.addEventListener('click', function () {
      var sec = btn.closest('.permsec').getAttribute('data-sec');
      foldSec(sec, $('grParts-' + sec).hidden);
    });
  });

  /* The access the panel holds now, as it would be stored: every section,
     and a part only where it says something its section does not. */
  function readAccess() {
    var access = {};
    levelPicks().forEach(function (sel) { access[sel.getAttribute('data-sec')] = sel.value || 'none'; });
    partPicks().forEach(function (sel) {
      var k = sel.getAttribute('data-part');
      var same = isGranted(k) ? 'none' : (access[k.split('.')[0]] || 'none');
      if (sel.value && adds(k, sel.value, same)) access[k] = sel.value;
    });
    return access;
  }
  /* The same access in one comparable shape, whatever was stored before. */
  function canon(acc) {
    var out = {};
    SECTIONS.forEach(function (s) { out[s[0]] = (acc && acc[s[0]]) || 'none'; });
    Object.keys(PARTS).forEach(function (sec) {
      PARTS[sec].forEach(function (p) {
        var k = sec + '.' + p[0], v = offered(k, exceptionOf(acc, k));
        if (v) out[k] = v;
      });
    });
    return JSON.stringify(Object.keys(out).sort().map(function (k) { return k + '=' + out[k]; }));
  }
  function presetOf() {
    var adm = flagBoxes().filter(function (cb) { return cb.getAttribute('data-f') === 'is_admin'; })[0];
    if (adm && adm.checked) return 'admin';
    if (readScope() === 'own') return 'custom';
    var now = canon(readAccess());
    var hit = Object.keys(PRESETS).filter(function (k) { return canon(PRESETS[k]) === now; })[0];
    return hit || 'custom';
  }
  /* "A, B and C" inside a level; the levels themselves are joined with a
     comma before the last ("work A and B, and view C"), so the two kinds of
     "and" are never read as one list. */
  function listWords(xs, sep) {
    if (xs.length < 2) return xs.join('');
    return xs.slice(0, -1).join(', ') + (sep || ' and ') + xs[xs.length - 1];
  }
  /* The group in one sentence, read from the panel as it stands, in the
     panel's own words (Team audit, 2026-10-03: it read "can work Clients"
     and "manage", the stored keys, where the panel says Manage and Full
     Access). */
  function sumText(acc, admin, tuned, scope) {
    if (admin) return 'This group can do everything, in every section.';
    var by = { manage: [], work: [], view: [] };
    SECTIONS.forEach(function (s) { var v = acc[s[0]] || 'none'; if (by[v]) by[v].push(s[1]); });
    var said = ['manage', 'work', 'view'].filter(function (lv) { return by[lv].length; }).map(function (lv) {
      return LEVEL_WORD[lv] + ' on ' + listWords(by[lv]);
    });
    var line = said.length ? 'This group has ' + listWords(said, ', and ') + '.' : 'This group has no access.';
    if (scope === 'own') line += ' Own clients only.';
    if (tuned) line += ' ' + tuned + (tuned === 1 ? ' page is' : ' pages are') + ' set in Advanced.';
    return line;
  }
  /* Everything that follows a change: each section's line and count, the
     preset it matches, and the sentence at the top. */
  function paintPanel() {
    var access = readAccess();
    var adm = flagBoxes().filter(function (cb) { return cb.getAttribute('data-f') === 'is_admin'; })[0];
    var admin = Boolean(adm && adm.checked), locked = Boolean(state.editing && state.editing.slug === 'admin');
    var tuned = 0;
    SECTIONS.forEach(function (s) {
      var d = $('grDesc-' + s[0]);
      if (d) d.textContent = admin ? 'Every level, as an admin.' : (DESC[s[0]][access[s[0]] || 'none'] || '');
      var n = (PARTS[s[0]] || []).filter(function (p) { return (s[0] + '.' + p[0]) in access; }).length +
              (s[0] === 'clients' && readScope() === 'own' ? 1 : 0);
      tuned += n;
      /* The team's figures (the Report view, the Overview's My Work cards)
         are a grant of their own, which a group at Full Access on My Work
         does not hold until it is given (the user found the Overview's My
         Work missing, 2026-10-03). */
      if (d && !admin && s[0] === 'ops' && (access.ops || 'none') !== 'none' && !access['ops.reports']) {
        d.textContent += ' Team figures need Report view in Advanced.';
      }
      var box = $('grFlags').querySelector('[data-n="' + s[0] + '"]');
      if (box) box.textContent = n ? '(' + n + ')' : '';
    });
    /* An admin opens everything, so the levels under it decide nothing and
       are not offered for change while the tick is on. */
    levelPicks().concat(partPicks()).forEach(function (sel) { sel.disabled = locked || admin; });
    $('grScope').disabled = locked || admin;
    $('grPreset').value = presetOf();
    $('grPreset').disabled = locked;
    $('grPresetNote').hidden = $('grPreset').value !== 'custom';
    $('grSum').textContent = sumText(access, admin, tuned, readScope());
  }
  function applyPreset(k) {
    flagBoxes().forEach(function (cb) { if (cb.getAttribute('data-f') === 'is_admin') cb.checked = k === 'admin'; });
    $('grScope').value = 'all';
    if (k !== 'admin') {
      var acc = PRESETS[k];
      levelPicks().forEach(function (sel) { sel.value = acc[sel.getAttribute('data-sec')] || 'none'; });
      partPicks().forEach(function (sel) {
        var key = sel.getAttribute('data-part');
        sel.value = offered(key, exceptionOf(acc, key));
      });
      Object.keys(PARTS).forEach(function (sec) {
        foldSec(sec, PARTS[sec].some(function (p) { return (sec + '.' + p[0]) in acc; }));
      });
    }
    paintPanel();
  }
  $('grPreset').addEventListener('change', function () {
    if (this.value && this.value !== 'custom') applyPreset(this.value);
  });
  $('grFlags').addEventListener('change', paintPanel);

  /* One sheet adds a group or edits one, the same sheet a colleague and a
     creator are edited in. */
  var groupOpener = null;
  function shutGroupBox() {
    window.ADspaceSheet.close();
    state.editing = null;
    groupOpener = null;
  }
  function openGroupBox(r, opener) {
    shutMenus();   // it was chosen from a ⋯, which does not repaint behind it
    state.editing = r || null;
    groupOpener = opener || null;
    $('grTitle').textContent = r ? 'Edit group' : 'New group';
    $('grSave').textContent = r ? 'Save' : 'Add';
    $('grName').value = r ? r.name : '';
    // A new group starts able to work the section everybody needs, and to
    // read nothing else: what it may destroy is always chosen deliberately.
    var acc = r ? accessOf(r) : null;
    levelPicks().forEach(function (sel) {
      var k = sel.getAttribute('data-sec');
      sel.value = acc ? (acc[k] || 'none') : (k === 'clients' ? 'work' : 'none');
      if (!sel.value) sel.value = 'none';
      sel.disabled = Boolean(r && r.slug === 'admin');
    });
    /* A section holding an exception opens on it; the rest stay folded,
       because Same as section on every part is the ordinary case.

       A part that says what its section already says is not an exception.
       The HR move wrote `register.hr` onto every group, `none` included, so
       every group carried a stored level identical to the one it would have
       inherited and Documents was the one section that opened by itself on
       every screen, for a difference nobody had made. A stored level equal to
       the section's reads as Same as section and is not saved again. */
    var opened = {};
    partPicks().forEach(function (sel) {
      var k = sel.getAttribute('data-part');
      sel.value = offered(k, exceptionOf(acc, k));
      if (sel.value) opened[k.split('.')[0]] = true;
      sel.disabled = Boolean(r && r.slug === 'admin');
    });
    $('grScope').value = r && r.client_scope === 'own' ? 'own' : 'all';
    $('grScope').disabled = Boolean(r && r.slug === 'admin');
    if ($('grScope').value === 'own') opened.clients = true;
    Object.keys(PARTS).forEach(function (sec) { foldSec(sec, Boolean(opened[sec])); });
    flagBoxes().forEach(function (cb) {
      var k = cb.getAttribute('data-f');
      cb.checked = r ? Boolean(r[k]) : false;
      cb.disabled = Boolean(r && r.slug === 'admin');
    });
    paintPanel();
    msg('grMsg', '');
    window.ADspaceSheet.show($('groupAddBox'), {
      opener: groupOpener,
      onClose: function () { state.editing = null; groupOpener = null; }
    });
  }
  $('groupAdd').addEventListener('click', function () { openGroupBox(null, this); });
  $('grCancel').addEventListener('click', shutGroupBox);
  $('grClose').addEventListener('click', shutGroupBox);
  $('grSave').addEventListener('click', function () {
    var name = ($('grName').value || '').trim();
    if (!name) { msg('grMsg', 'A name is required.', 'err'); return; }
    var flags = {};
    flagBoxes().forEach(function (cb) { flags[cb.getAttribute('data-f')] = cb.checked; });
    // Only an exception is stored; Same as section is the absence of a key,
    // and so is a part set to exactly what its section already gives.
    var access = readAccess();
    if (state.editing) {
      var r = state.editing;
      var patch = {};
      if (name !== r.name) patch.name = name;
      Object.keys(flags).forEach(function (k) { if (Boolean(r[k]) !== flags[k]) patch[k] = flags[k]; });
      if (JSON.stringify(accessOf(r)) !== JSON.stringify(access)) patch.access = access;
      if ((r.client_scope || 'all') !== readScope()) patch.client_scope = readScope();
      shutGroupBox();
      if (Object.keys(patch).length) saveGroup(r, patch);
      return;
    }
    var slug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
    if (!slug) { msg('grMsg', 'Use letters or numbers in the name.', 'err'); return; }
    if (state.roles.some(function (r) { return r.slug === slug; })) { msg('grMsg', 'That group already exists.', 'err'); return; }
    var row = { slug: slug, name: name, position: state.roles.length, access: access, client_scope: readScope() };
    Object.keys(flags).forEach(function (k) { row[k] = flags[k]; });
    db.from('team_roles').insert(row).then(function (q) {
      if (q.error) { msg('grMsg', q.error.message, 'err'); return; }
      log('team.group_added', name, '');
      shutGroupBox();
      msg('groupMsg', name + ' added.', 'ok');
      load();
    });
  });

  // ---- Add or edit a person -----------------------------------------------
  var editingMember = null;
  /* The form is a sheet over the list, the shape a creator is edited in: on
     a phone it comes up from the floor over the row somebody pressed, rather
     than unfolding a screen above it where pressing Edit looked like nothing
     had happened. The scrim does not throw typed changes away; the close
     mark, Cancel and Escape are the ways out. */
  var memberOpener = null;
  function shutMemberBox() {
    window.ADspaceSheet.close();
    editingMember = null;
    memberOpener = null;
  }
  function openMemberBox(m, opener) {
    shutMenus();
    editingMember = m || null;
    memberOpener = opener || null;
    $('tmTitle').textContent = m ? 'Edit member' : 'New team member';
    $('tmSave').textContent = m ? 'Save' : 'Add';
    $('tmName').value = m ? (m.name || '') : '';
    $('tmEmail').value = m ? (m.email || '') : '';
    $('tmStaff').value = m ? (m.staff_code || '') : '';
    $('tmDesig').value = m ? (m.designation || '') : '';
    $('tmDept').value = m ? (m.department || '') : '';
    $('tmRoleStd').value = m ? (m.role_family || '') : '';
    $('tmCap').value = m && m.capacity_minutes_week ? String(Math.round(m.capacity_minutes_week / 30) / 2) : '';
    /* Nobody sets their own access date; another admin does. */
    var mine = !!(m && me() && me().id === m.id);
    $('tmUntilRow').hidden = mine;
    $('tmUntil').value = m && m.access_until ? m.access_until : '';
    $('tmUntilTime').value = m && m.access_until && m.access_until_time ? String(m.access_until_time).slice(0, 5) : '';
    $('tmUntil').min = todayMy();
    $('tmUntilTimeBox').hidden = !$('tmUntil').value;
    $('tmMobile').value = m ? (m.mobile || '') : '';
    $('tmCardOn').value = m && m.card_on === false ? 'off' : 'on';
    $('tmCardMobile').value = m && m.card_mobile === false ? 'hide' : 'show';
    $('tmCardSlug').value = m ? (m.card_slug || '') : '';
    $('tmSlugPre').textContent = ((window.ADSPACE_CONFIG && window.ADSPACE_CONFIG.linkHost) || 'hi.adspace.me') + '/';
    fillRolePick(); $('tmRole').value = m ? m.role : 'account';
    msg('tmMsg', '');
    window.ADspaceSheet.show($('teamAddBox'), {
      opener: memberOpener,
      onClose: function () { editingMember = null; memberOpener = null; }
    });
  }
  $('teamAdd').addEventListener('click', function () { openMemberBox(null, this); });
  ['input', 'change'].forEach(function (ev) {
    $('tmUntil').addEventListener(ev, function () {
      $('tmUntilTimeBox').hidden = !this.value;
      if (!this.value) $('tmUntilTime').value = '';
    });
  });

  /* The bar's ⋯: one last day for everybody's access but your own (the
     user, 2026-10-01: "set all to expire 31/12/2027 unless extended"). */
  (function () {
    var wrap = $('teamMoreWrap'), btn = $('teamMoreBtn'), menu = $('teamMore');
    if (!wrap || !btn || !menu) return;
    wrap.hidden = false;
    var shut = function () { menu.hidden = true; btn.setAttribute('aria-expanded', 'false'); };
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      var open = menu.hidden;
      menu.hidden = !open;
      btn.setAttribute('aria-expanded', String(open));
      if (open && window.ADspaceMenu) window.ADspaceMenu.place(btn, menu);
    });
    document.addEventListener('click', function (e) { if (!e.target.closest || !e.target.closest('#teamMoreWrap')) shut(); });
    if (window.ADspaceMenu && window.ADspaceMenu.onScroll) window.ADspaceMenu.onScroll(shut);
    menu.addEventListener('click', function (e) {
      var it = e.target.closest('.kmenu-item');
      if (!it) return;
      shut();
      var others = state.rows.filter(function (x) { return x.active && !(me() && me().id === x.id); }).length;
      window.ADspaceConfirm.ask({
        title: 'Set access expiry',
        body: 'Every active colleague but you keeps access up to this day, and the time if one is set (else the day\'s end), unless it is moved for them. Leave the day empty for no end. ' +
              others + (others === 1 ? ' colleague.' : ' colleagues.'),
        go: 'Set for all',
        fields: [{ name: 'day', label: 'Access until', type: 'date', min: todayMy(), required: false },
                 { name: 'time', label: 'Time', type: 'time', required: false }]
      }, function (v) {
        var day = v.day || null, time = day ? (v.time || null) : null;
        if (day && !aheadMy(day, time)) { msg('teamMsg', 'Choose a later time.', 'err'); return; }
        db.rpc('team_set_expiry_at', { p_until: day, p_time: time }).then(function (r) {
          var d = r.data || {};
          if (r.error || d.error) { msg('teamMsg', r.error ? (/function|schema cache/i.test(r.error.message) ? 'This needs a database update.' : teamSaid(r.error)) : teamSaid(d.error === 'denied' ? 'Not allowed.' : d.error), 'err'); return; }
          msg('teamMsg', 'Saved.', 'ok');
          load();
        });
      });
    });
  })();
  $('tmCancel').addEventListener('click', shutMemberBox);
  $('tmClose').addEventListener('click', shutMemberBox);
  $('tmSave').addEventListener('click', function () {
    var name = ($('tmName').value || '').trim();
    var email = ($('tmEmail').value || '').trim().toLowerCase();
    var role = $('tmRole').value;
    var staff = ($('tmStaff').value || '').trim().toUpperCase();
    var desig = ($('tmDesig').value || '').trim();
    var capH = parseFloat($('tmCap').value);
    if (!name) { msg('tmMsg', 'A name is required.', 'err'); return; }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) { msg('tmMsg', 'A valid email is required.', 'err'); return; }
    if (!role) { msg('tmMsg', 'A group is required.', 'err'); return; }
    /* The HR serial is built from it, so it is letters and digits only. */
    if (staff && !/^[A-Z0-9]{3,8}$/.test(staff)) { msg('tmMsg', 'An Employee ID is 3 to 8 letters or digits.', 'err'); $('tmStaff').focus(); return; }
    if ($('tmCap').value && !(capH >= 0 && capH <= 80)) { msg('tmMsg', 'Weekly capacity is 0 to 80 hours.', 'err'); $('tmCap').focus(); return; }
    var mobile = ($('tmMobile').value || '').trim();
    var mobDigits = mobile.replace(/\D/g, '').length;
    if (mobile && (mobDigits < 8 || mobDigits > 15)) { msg('tmMsg', 'Enter a mobile number of 8 to 15 digits.', 'err'); $('tmMobile').focus(); return; }
    var cardSlug = ($('tmCardSlug').value || '').trim().toLowerCase().replace(/^https?:\/\/[^/]*\//, '').replace(/^\/+|\/+$/g, '');
    if (cardSlug && !/^[a-z0-9][a-z0-9._-]{0,79}$/.test(cardSlug)) {
      msg('tmMsg', 'Use lowercase letters, digits, dots, dashes or underscores.', 'err'); $('tmCardSlug').focus(); return;
    }
    var fields = { name: name, email: email, role: role, staff_code: staff || null, designation: desig || null,
                   department: $('tmDept').value || null, role_family: $('tmRoleStd').value || null,
                   capacity_minutes_week: capH >= 0 && $('tmCap').value ? Math.round(capH * 60) : null,
                   mobile: mobile || null, card_on: $('tmCardOn').value !== 'off',
                   card_mobile: $('tmCardMobile').value !== 'hide' };
    /* Empty makes it again from the name; unchanged is not sent. */
    if (!editingMember || cardSlug !== (editingMember.card_slug || '')) fields.card_slug = cardSlug || null;
    if (!$('tmUntilRow').hidden) {
      var until = $('tmUntil').value || null;
      var untilTime = until ? ($('tmUntilTime').value || null) : null;
      var same = editingMember && until === editingMember.access_until &&
                 (untilTime || null) === (editingMember.access_until_time ? String(editingMember.access_until_time).slice(0, 5) : null);
      if (until && !same && !aheadMy(until, untilTime)) {
        msg('tmMsg', until < todayMy() ? 'Choose today or a later date.' : 'Choose a later time.', 'err');
        $(until < todayMy() ? 'tmUntil' : 'tmUntilTime').focus(); return;
      }
      fields.access_until = until;
      fields.access_until_time = untilTime;
    }
    if (editingMember) {
      var m = editingMember;
      /* The row's email is the address the console signs in with, so moving it
         moves the door. The login itself stays where it was until somebody is
         invited at the new address. */
      function write() {
        shutMemberBox();
        db.from('team_members').update(fields).eq('id', m.id).select('id').then(function (r) {
          if (!r.error && !(r.data || []).length) { msg('teamMsg', 'Not saved. The database refused the request.', 'err'); return; }
          if (r.error) {
            msg('teamMsg', /slug-taken/.test(r.error.message) ? 'That short link is already in use.'
              : /staff_code/i.test(r.error.message) ? 'That Employee ID is already on the list.'
              : /duplicate|unique/i.test(r.error.message)
              ? 'That email is already on the list.' : teamSaid(r.error), 'err');
            return;
          }
          /* A save that changed nothing files nothing. */
          /* An emptied short link is made again from the name by the database,
             so it is not filed as "not set"; the next read shows the new one. */
          var filed = fields.card_slug === null ? Object.assign({}, fields, { card_slug: m.card_slug }) : fields;
          var moved = window.ADspaceRecords.changes(m, filed, [
            ['name', 'Name'], ['email', 'Email'], ['role', 'User group', roleName], ['staff_code', 'Employee ID'],
            ['designation', 'Position'], ['department', 'Department', function (v) { return DEPT[v] || v; }],
            ['role_family', 'Role standard', function (v) { return ROLE_STD[v] || v; }],
            ['capacity_minutes_week', 'Weekly capacity', function (v) { return Math.round(Number(v) / 60) + 'h'; }],
            ['access_until', 'Access until', dayWord], ['access_until_time', 'Access time', timeWord],
            ['mobile', 'Mobile'], ['card_mobile', 'Mobile on card', function (v) { return off(v) ? 'Hide' : 'Show'; }],
            ['card_on', 'Namecard', function (v) { return off(v) ? 'Off' : 'On'; }],
            ['card_slug', 'Short link']]);
          if (moved) log('team.edited', name, moved);
          msg('teamMsg', 'Saved.', 'ok');
          load();
          /* A rename is the same person, so the clients and campaigns that
             name them follow the new name without being asked, completed
             campaigns included: they would otherwise name somebody the team
             list no longer has. */
          if (name !== String(m.name || '').trim()) {
            ownedBy(m.name, true, function (own) {
              var n = own.clients.length + own.campaigns.length;
              if (n) handOver(m.name, name, own, [
                own.clients.length ? plural(own.clients.length, 'client', 'clients') : '',
                own.campaigns.length ? plural(own.campaigns.length, 'campaign', 'campaigns') : ''
              ].filter(Boolean).join(' and ').replace(/^./, function (x) { return x.toUpperCase(); }));
            });
          }
        });
      }
      if (email === String(m.email || '').toLowerCase()) { write(); return; }
      window.ADspaceConfirm.ask({
        title: 'Change the sign-in address',
        body: m.name + ' signs in with ' + email + ' from now on. The login itself '
            + 'stays at the old address until they are invited at the new one.',
        go: 'Change address',
        tone: 'warn'
      }, write);
      return;
    }
    db.from('team_members').insert(Object.assign({ active: true }, fields))
      .then(function (r) {
        if (r.error) {
          msg('tmMsg', /slug-taken/.test(r.error.message) ? 'That short link is already in use.'
            : /staff_code/i.test(r.error.message) ? 'That Employee ID is already on the list.'
            : /duplicate|unique/i.test(r.error.message)
            ? 'That email is already on the list.' : r.error.message, 'err');
          return;
        }
        log('team.added', name, email + ' · ' + roleName(role));
        shutMemberBox();
        load();
        // The row is theirs; now the login. The function holds the key the
        // browser must not, and emails them the sign-in link.
        msg('teamMsg', name + ' added. Sending invitation…', 'ok');
        API.invokeFn('invite-member', { email: email, name: name })
          .then(function (r) {
            var d = r.data || {};
            if (r.error) {
              var why = (d.error === 'not_admin') ? 'Only an admin can send invitations.'
                : /not deployed/.test(r.why)
                  ? 'The invite-member function is not deployed. Add the login under Supabase ' +
                    'Authentication, or deploy the function and use Send invitation.'
                  : 'Invitation could not be sent: ' + r.why;
              msg('teamMsg', name + ' added. ' + why, 'warn');
              return;
            }
            msg('teamMsg', d.already
              ? name + ' added. A login already exists.'
              : name + ' added. Invitation sent to ' + email + '.',
              'ok');
          });
      });
  });

  function reinvite(m) {
    // The ⋯ it was chosen from would otherwise sit open over the answer.
    shutMenus();
    if (!m.email) { msg('teamMsg', m.name + ' has no email on record.', 'err'); return; }
    window.ADspaceConfirm.ask({
      title: 'Send an invitation',
      body: 'An email goes to ' + m.email + ' with a sign-in link. '
          + 'It leaves the building and cannot be recalled.',
      go: 'Send'
    }, function () {
      msg('teamMsg', 'Sending an invitation to ' + m.email + '…', 'ok');
      API.invokeFn('invite-member', { email: m.email, name: m.name })
        .then(function (r) {
          var d = r.data || {};
          if (r.error) { msg('teamMsg', 'Could not send: ' + r.why, 'err'); return; }
          log('team.invited', m.name, m.email);
          msg('teamMsg', d.already ? m.name + ' already has a login.'
                                   : 'Invitation sent to ' + m.email + '.', 'ok');
        });
    });
  }

  window.ADspaceTeam = {
    urlState: function () { return {}; },
    enter: function () { load(); },
    /* Opens one colleague's sheet, for the review profile's Edit on Members:
       from the rows already read, or once the list has been. */
    edit: function (id) { pendingEdit = id; if (!state.loading) openPending(); }
  };
  if (bridge.teamReady) bridge.teamReady();
})();
