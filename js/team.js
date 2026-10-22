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
    return String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
      .replace(/"/g,'&quot;').replace(/'/g,'&#39;');
  }
  /* A success line goes after 8 seconds, as the Undo bar does, so a later
     act never reads under an earlier one's Saved. (TEAM-11, 2026-10-14);
     a refusal or a warning stays until the next act replaces it. */
  var msgTimers = {};
  function msg(id, text, kind) {
    var el = $(id); if (!el) return;
    el.textContent = text || ''; el.className = 'msg' + (kind ? ' ' + kind : '');
    clearTimeout(msgTimers[id]);
    if (kind === 'ok' && text) msgTimers[id] = setTimeout(function () {
      if (el.textContent === text) { el.textContent = ''; el.className = 'msg'; }
    }, 8000);
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
  var SCOPE_CLASH = 'Own clients only cannot be given with the Activity record, which shows every client. Set the Activity record to No Access, or choose All clients.';
  function scopeClash(access, scope, admin) {
    if (scope !== 'own' || admin) return false;
    return Object.keys(access || {}).some(function (k) {
      return (k === 'activity' || k.indexOf('activity.') === 0) && access[k] && access[k] !== 'none';
    });
  }

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
    /* WhatsApp (2026-10-10): View reads the messages sent, Manage sends,
       Full Access chooses the templates. */
    ['whatsapp',  'WhatsApp',          ['none', 'view', 'work', 'manage']],
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
    ['suppliers', 'Suppliers',         ['none', 'view', 'work', 'manage']],
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
    /* Each tab of a client's record is a part (2026-10-22, the user: "AMV
       quote, AMV Service Lines, AMV Issue documents"): Quotations, Brand and
       Checklists apart from the lines, the letters and the record itself. */
    clients:   [['contacts', 'Contacts'], ['billing', 'Billing'], ['quotes', 'Quotations'], ['services', 'Service lines'],
                ['documents', 'Letters'], ['requests', 'Requests'], ['calls', 'Calls and visits'],
                ['brand', 'Brand'], ['checklists', 'Checklists'],
                /* The lead stages and Past (2026-10-03): No Access, View or
                   Manage on those records, and on everything filed under
                   them in every section (`client_row_seen`). */
                ['leads', 'Leads'], ['past', 'Past clients'],
                /* Mark a client VIC, or remove it (2026-10-15): granted, an
                   admin's by itself. */
                ['vic', 'Mark VIC clients']],
    /* Each send from a record follows WhatsApp or is shut (2026-10-10):
       they replaced the Clients, Reports and Creator Campaigns parts. */
    whatsapp:  [['report', 'Send a published report'], ['feedback', 'Feedback request'], ['booking', 'Booking message'],
                /* A client reminded of what waits on their approval (2026-10-10). */
                ['approval', 'Approval reminder'],
                /* A quotation or a Letter of Offer sent to the client (2026-10-14). */
                ['documents', 'Quotations and letters']],
    review:    [['sets', 'Content sets'], ['settings', 'Client settings']],
    campaigns: [['campaigns', 'Campaigns'], ['creators', 'Creators List'], ['finance', 'Finance'],
                /* A file the client approved, hidden and then deleted for good
                   (audit S6, 2026-10-10): granted, an admin's by itself. */
                ['files_delete', 'Delete approved files']],
    register:  [['documents', 'Client documents'], ['hr', 'HR Letters'], ['types', 'Document types']],
    /* A supplier's NRIC and bank details (2026-10-18): granted, an admin's by
       itself, read at View and written at Work. */
    suppliers: [['pay', 'Supplier bank details']],
    /* The record is already read a section at a time — the tab strip is its
       own — and its access was one switch over all of them, so opening the
       campaigns log to the team opened every client's billing change and
       every letter with it. Each tab is a part, and the database decides
       which rows arrive: `activity_section()` maps a tag to the section the
       console files it under, and the read policy asks the part. */
    activity:  [['ops', 'My Work'], ['clients', 'Clients'], ['whatsapp', 'WhatsApp'],
                ['review', 'Content Review'], ['scripts', 'Video Scripts'], ['campaigns', 'Creator Campaigns'],
                ['reports', 'Reports'], ['register', 'Documents'], ['suppliers', 'Suppliers'], ['links', 'Short Links'],
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
                ['all', 'The whole team\'s tasks'], ['reports', 'Team figures on the Dashboard'],
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
                /* Import from Meta and the audit against Meta (2026-10-10):
                   granted, an admin's by itself, and read only while the
                   Business setting Meta checks is On. */
                ['meta', 'Meta import and audit']]
  };
  /* The parts that are granted rather than inherited: each opens more than
     its section does, so silence means no. The same list the console reads
     (`OPS_GRANTED` in js/admin.js) and the database asks (`ops_granted()`). */
  var GRANTED = { 'ops.all': 1, 'ops.reports': 1, 'ops.workflows': 1, 'ops.time': 1, 'team.performance': 1,
    'reports.whitelabel': 1, 'ops.numbering': 1, 'ops.override': 1, 'team.perfadmin': 1, 'team.settings': 1,
    'team.upgrade': 1, 'team.invite': 1, 'team.handbook': 1, 'reports.transfer': 1, 'reports.ai': 1,
    'team.announce': 1, 'register.types': 1, 'team.health': 1, 'team.notice': 1, 'reports.meta': 1,
    'campaigns.files_delete': 1, 'clients.vic': 1, 'suppliers.pay': 1 };
  function isGranted(key) { return Boolean(GRANTED[key]); }
  /* A part that follows its section or is shut, and nothing between: the
     three My Work views, and each WhatsApp send (2026-10-10), which asks
     the section at Manage as well as itself. */
  /* The Dashboard (2026-10-11, option A the user chose): one row above the
     sections, On or No Access. It is the key `overview` in the access map,
     stored only as `none`: On stores nothing, which is how every group
     stood before, so the page is offered where one of its cards is
     allowed. No Access only hides the page; each card still asks Full
     Access on its own section. */
  var DASH = 'overview';
  var DASH_DESC = { on: 'Shown with the cards of each section the group holds at Full Access.', none: 'The Dashboard is hidden.',
    empty: 'On, but nothing is shown: the group holds no section at Full Access.' };
  var VIEW_PARTS = { 'ops.list': 1, 'ops.board': 1, 'ops.calendar': 1,
    'whatsapp.report': 1, 'whatsapp.feedback': 1, 'whatsapp.booking': 1, 'whatsapp.approval': 1, 'whatsapp.documents': 1 };

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
    'team.notice': ['work'], 'reports.meta': ['work'], 'campaigns.files_delete': ['work'], 'clients.vic': ['work'], 'suppliers.pay': ['view', 'work'], 'whatsapp.report': ['work'], 'whatsapp.feedback': ['work'], 'whatsapp.booking': ['work'], 'whatsapp.approval': ['work'], 'whatsapp.documents': ['work'],
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
    // Its group from the standard's one table (js/menu.js); never greyed.
    return window.ADspaceMenu.item(action, label, '', '', disabled ? 'disabled' : '');
  }
  function menuBtn(items) {
    return '<span class="team-act">' +
      '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
      '<div class="kmenu" data-menu hidden>' + items + '</div></span>';
  }
  /* A row whose ⋯ would hold nothing keeps its cell and draws no ⋯. */
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
  function load(then) {
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
      /* Every column of every colleague is Team's alone (2026-10-18):
         `team_rows()` answers Team at View, the table the rest. */
      db.rpc('team_rows').then(function (q) {
          if (q.error) {
            state.loading = false;
            $('teamList').innerHTML = '<div class="softpanel"><div class="errline">' +
              '<b>Could not load the team.</b><span>' + esc(q.error.message) + '</span></div></div>';
            return;
          }
          state.rows = q.data || [];
          state.read = true;
          state.loading = false;
          paintMembers();
          paintGroups();   // member counts and Delete depend on the rows
          paintRec();
          if (pendingEdit) openPending();
          if (typeof then === 'function') then();
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
    /* Inactive, expired and removed colleagues leave their group's card and
       count for one card after the groups, shut until opened (TEAM-5,
       2026-10-14), as Clients folds Past and Short Links Paused. */
    groups.forEach(function (g) { g[2] = g[2].filter(function (m) { return m.active; }); });
    groups.push(['off', 'Inactive', rows.filter(function (m) { return !m.active; })]);
    groups.forEach(function (g) {
      if (!g[2].length) return;
      box.appendChild(GRP.section({
        route: 'team', key: g[0], name: g[1], count: g[2].length,
        shut: !filtered && GRP.shut('team', g[0], g[0] === 'off'),
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
  var ADMIN_ONLY = 'Only an admin makes a colleague admin or changes an admin.';
  function teamSaid(e) {
    var t = String(e && e.message || e || '');
    if (/own-expiry/.test(t)) return 'Your own access date is set by another admin.';
    if (/expired-date/.test(t)) return 'Move the access date first.';
    if (/past-date/.test(t)) return 'Choose today or a later date.';
    if (/system-account/.test(t)) return 'This is a system account.';
    if (/admin-only/.test(t)) return ADMIN_ONLY;
    if (/last-admin/.test(t)) return 'This is the last admin with access. Make another colleague admin first.';
    return t;
  }
  /* A save refused because a value is another colleague's names the field
     (Team audit, item 10): the database's index says which. A removed
     colleague's values are free again (REMOVED COLLEAGUES FREE THEIR
     DETAILS), so a colleague who returns is added again. */
  function clashSaid(e) {
    var t = String(e && e.message || '') + ' ' + String(e && e.details || '');
    if (/slug-taken|card_slug/.test(t)) return 'That short link is already in use.';
    if (!/duplicate|unique/i.test(t)) return teamSaid(e);
    if (/staff_code/i.test(t)) return 'That Employee ID is already on the list.';
    if (/email/i.test(t)) return 'That email is already on the list.';
    if (/name/i.test(t)) return 'That name is already on the list.';
    return 'That colleague is already on the list.';
  }
  /* In the member sheet the refusal is the sheet's last line, under its
     fields: it is brought into view and the field that clashes takes the
     caret, the way a failed save focuses its first invalid field. */
  function sheetClash(e) {
    msg('tmMsg', clashSaid(e), 'err');
    var t = String(e && e.message || '') + ' ' + String(e && e.details || '');
    var id = !/duplicate|unique/i.test(t) ? null : /staff_code/i.test(t) ? 'tmStaff'
      : /email/i.test(t) ? 'tmEmail' : /name/i.test(t) ? 'tmName' : null;
    var f = id && $(id);
    if (f) { try { f.focus({ preventScroll: true }); } catch (x) { f.focus(); } }
    var m = $('tmMsg');
    if (m && m.scrollIntoView) m.scrollIntoView({ block: 'nearest' });
  }
  function memberRow(m) {
    var self = me() && me().id === m.id;
    /* The row is the colleague, as a client's row is the client (the user,
       2026-10-18: "it should be the same as client"): one button opening
       their record, the initials before the name and the chevron last. What
       is done to a colleague (Edit, Set inactive, Delete) is in the record's
       own ⋯, never on the list. */
    var el = document.createElement('button');
    el.type = 'button';
    el.className = 'crm-row team-row' + (m.active ? '' : ' is-off');
    el.innerHTML =
      /* Everyone on this list is active, so the row says nothing when a
         person is working and names it when they are not. You is a
         designation, the neutral chip. The name with its Employee ID beside
         it (the user, 2026-10-03), then where they sit. */
      '<span class="team-who">' +
        '<span class="cl-mark" aria-hidden="true">' + esc(window.ADspaceState.initials(m.name || '')) + '</span>' +
        '<span class="cl-who"><b>' + esc(m.name) +
          (m.staff_code ? ' <span class="team-eid">' + esc(m.staff_code) + '</span>' : '') +
          (self ? ' <span class="tone">You</span>' : '') +
          (m.system ? ' <span class="tone">System</span>' : '') + '</b>' +
          /* A line of parts wraps between its parts, never inside one, so
             Until and its time are read whole (the user, 2026-10-15). */
          (whoLine(m) ? '<small>' + whoLine(m).split(' · ').map(function (x) { return /^Until /.test(x) ? '<span class="team-part">' + esc(x) + '</span>' : esc(x); }).join(' · ') + '</small>' : '') +
        '</span>' +
      '</span>' +
      '<span class="team-mail">' + esc(m.email || '') + '</span>' +
      /* The exception only: Inactive, Access expired, or a card turned off
         for somebody still working. */
      '<span class="team-state">' + (!m.active ? '<span class="tone is-off">' + (m.removed_at ? 'Removed' : m.expired_at ? 'Access expired' : 'Inactive') + '</span>'
        : m.card_on === false ? '<span class="tone is-off">Card off</span>' : '') + '</span>' +
      '<svg class="crm-c-go team-go" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
        'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
        '<path d="M9 18l6-6-6-6"/></svg>';
    el.addEventListener('click', function () { openRec(m.id); });
    return el;
  }

  /* The acts on a colleague, one list for the row's ⋯ and the record's
     (2026-10-18): the same items, drawn by the same permissions. */
  function memberMenu(m) {
    var self = me() && me().id === m.id;
    var sysRow = Boolean(m.system) && !self;
    var manage = may('team', 'manage') && !sysRow;
    return (manage ? menuItem('edit', 'Edit') : '') +
              (m.active && m.card_key && m.card_on !== false ? menuItem('card', 'Open namecard') : '') +
              (may('team.invite', 'work') && m.active && m.email && !sysRow ? menuItem('invite', 'Send invitation') : '') +
              (self || !manage || m.removed_at ? '' : menuItem('state', m.active ? 'Set inactive' : (m.expired_at ? 'Extend access' : 'Set active'))) +
              /* Work still held by somebody who no longer signs in is handed
                 over from here (TEAM-3, 2026-10-14). */
              (self || !manage || m.active ? '' : menuItem('handover', 'Hand over work')) +
              /* Delete (2026-10-14): their work handed over kind by kind,
                 their data kept or their personal details deleted. */
              (self || !manage || m.erased_at ? '' : menuItem('remove', 'Delete', 'is-danger'));
  }
  function wireActs(el, m) {
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
      if (window.ADspaceGroup) window.ADspaceGroup.keep('team', 'off', false);   // the row moves into Inactive: keep it in sight
      /* Somebody who is stood down may still be the person in charge of
         clients and open campaigns, and a client whose person in charge
         cannot sign in is a client nobody is looking after. So the same sheet
         asks who takes them over, in the same breath, with Keep as the first
         answer because a stand-down can be for a week (the user,
         2026-09-26). A completed campaign keeps who ran it: that is history. */
      /* Their live work is handed over kind by kind (2026-10-14; the user:
         "A person for each kind"), each kept with them unless a colleague
         is chosen, since a stand-down can be for a week. */
      heldBy(m, function (own, held) {
        var fields = handFields(m, own, held);
        window.ADspaceConfirm.ask({
          title: 'Set inactive',
          body: m.name + ' loses access to every section until they are set active '
              + 'again here. Their record, their name on past work and everything '
              + 'they signed stay as they are.'
              + (fields.length ? ' Choose who takes each kind of their work.' : ''),
          go: 'Set inactive',
          tone: 'warn',
          fields: fields.length ? fields : null
        }, function (v) {
          saveMember(m, { active: false }, function () { handTo(m, own, v && typeof v === 'object' ? v : {}); });
        });
      });
    });
    var hov = el.querySelector('[data-a="handover"]');
    if (hov) hov.addEventListener('click', function () {
      shutMenus();
      heldBy(m, function (own, held) {
        var fields = handFields(m, own, held);
        if (!fields.length) { msg('teamMsg', 'Nothing is assigned to ' + m.name + '.', 'ok'); return; }
        window.ADspaceConfirm.ask({
          title: 'Hand over work', go: 'Hand over',
          body: 'Choose who takes each kind of ' + m.name + '\'s work.',
          fields: fields
        }, function (v) {
          v = v && typeof v === 'object' ? v : {};
          var kept = keptWord(own, held, v, m.name);
          msg('teamMsg', '');
          Promise.resolve(handTo(m, own, v)).then(function () {
            if (!kept) return;
            var said = ($('teamMsg').textContent || '').trim();
            msg('teamMsg', (said ? said + ' ' : '') + kept, 'warn');
          });
        });
      });
    });
    var rmv = el.querySelector('[data-a="remove"]');
    if (rmv) rmv.addEventListener('click', function () { shutMenus(); removeMember(m); });
    var ed = el.querySelector('[data-a="edit"]');
    if (ed) ed.addEventListener('click', function () { openMemberBox(m, this); });
    var inv = el.querySelector('[data-a="invite"]');
    if (inv) inv.addEventListener('click', function () { reinvite(m); });
  }

  /* A colleague or a group is written only over the row as it was read
     (2026-10-18, Team audit 9): one somebody changed meanwhile answers no
     row, told apart from a refusal by reading its stamp again. */
  var STALE = 'Not saved. This changed since it was opened, and has been read again.';
  function asRead(q, row) { return row && row.updated_at ? q.eq('updated_at', row.updated_at) : q; }
  function noRow(table, key, row, then) {
    db.from(table).select(key + ', updated_at').eq(key, row[key]).maybeSingle().then(function (r) {
      var now = r && r.data && r.data.updated_at;
      then(row.updated_at && now && now !== row.updated_at ? STALE : 'Not saved. The database refused the request.');
    }).catch(function () { then('Not saved. The database refused the request.'); });
  }
  function saveMember(m, patch, then) {
    asRead(db.from('team_members').update(patch).eq('id', m.id), m).select('id').then(function (r) {
      if (r.error) { msg('teamMsg', teamSaid(r.error), 'err'); load(); return; }
      if (!(r.data || []).length) { noRow('team_members', 'id', m, function (t) { load(function () { msg('teamMsg', t, 'err'); }); }); return; }
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

  /* ---- Hand-over and Delete (2026-10-14) -------------------------------------
     What a colleague holds, read before they are set inactive or removed:
     the clients and open campaigns they are person in charge of (by name),
     and the rest of their live work from `team_work_held`. A database
     without it offers the person in charge alone. */
  var HELD_KINDS = [['tasks', 'Open tasks'], ['months', 'Months they manage'], ['meetings', 'Meetings they lead'],
    ['repeats', 'Repeating tasks'], ['reviews', 'Reports waiting for their review'], ['extensions', 'Extension requests waiting on them'],
    ['templates', 'Templates naming them as default owner']];
  function heldBy(m, then) {
    ownedBy(m.name, false, function (own) {
      db.rpc('team_work_held', { p_member: m.id }).then(function (r) {
        var d = (r && r.data) || {};
        then(own, r.error || d.error ? {} : d);
      }).catch(function () { then(own, {}); });
    });
  }
  function takers(m) {
    return state.rows.filter(function (x) { return x.active && x.id !== m.id && x.name && !x.system; })
      .slice().sort(window.ADspaceForm.byStaff);
  }
  /* A leaver usually hands everything to one person (TEAM-2, 2026-10-14):
     with two kinds or more, All their work to comes first and each kind
     reads Same as above until a colleague, or Keep, is chosen for it, which
     keeps the user's "a person for each kind". */
  var HAND_KEEP = '__keep';
  function handKinds() { return ['clients', 'campaigns'].concat(HELD_KINDS.map(function (k) { return k[0]; })); }
  /* The kinds that are My Work's go only to a colleague who takes tasks
     (`ADspaceAdmin.takesTasks`): a group below My Work Work is offered for
     clients, campaigns and reviews alone (2026-10-15). */
  var TASK_KINDS = ['tasks', 'months', 'meetings', 'repeats', 'extensions', 'templates'];
  function handFields(m, own, held) {
    var A = window.ADspaceAdmin;
    var named = function (x) { return [x.id, window.ADspaceForm.named(x.staff_code, x.name)]; };
    var people = takers(m).map(named);
    var workers = takers(m).filter(function (x) { return !A || !A.takesTasks || A.takesTasks(x); }).map(named);
    if (!people.length) return [];
    var kinds = [];
    var add = function (name, label, n) { if (n > 0) kinds.push({ name: name, label: label + ' (' + n + ')' }); };
    add('clients', 'Clients they are person in charge of', own.clients.length);
    add('campaigns', 'Open campaigns', own.campaigns.length);
    HELD_KINDS.forEach(function (k) { add(k[0], k[1], Number(held[k[0]]) || 0); });
    var keep = ['', 'Keep with ' + m.name];
    var whoFor = function (k) { return TASK_KINDS.indexOf(k) > -1 ? workers : people; };
    if (kinds.length < 2) return kinds.map(function (k) { return { name: k.name, label: k.label, required: false, choices: [keep].concat(whoFor(k.name)) }; });
    /* All their work goes to one person, so where any of it is My Work's it
       offers only those who take tasks. */
    var anyTask = kinds.some(function (k) { return TASK_KINDS.indexOf(k.name) > -1; });
    return [{ name: 'all', label: 'All their work to', required: false, choices: [keep].concat(anyTask ? workers : people) }].concat(kinds.map(function (k) {
      return { name: k.name, label: k.label, required: false, choices: [['', 'Same as above'], [HAND_KEEP, 'Keep with ' + m.name]].concat(whoFor(k.name)) };
    }));
  }
  /* Each kind's colleague as chosen: its own pick, else All their work to;
     Keep is empty. */
  function handChosen(v) {
    var out = {};
    handKinds().forEach(function (k) {
      var x = v[k];
      out[k] = x === HAND_KEEP ? '' : (x || v.all || '');
    });
    return out;
  }
  /* What stays with them, in words: "1 client and 2 open tasks". */
  var HELD_WORD = { clients: ['client', 'clients'], campaigns: ['open campaign', 'open campaigns'], tasks: ['open task', 'open tasks'],
    months: ['month they manage', 'months they manage'], meetings: ['meeting they lead', 'meetings they lead'],
    repeats: ['repeating task', 'repeating tasks'], reviews: ['report waiting for their review', 'reports waiting for their review'],
    extensions: ['extension request', 'extension requests'], templates: ['template', 'templates'] };
  function keptWord(own, held, v, name) {
    var to = handChosen(v || {}), total = 0;
    var parts = handKinds().map(function (k) {
      var n = k === 'clients' ? own.clients.length : k === 'campaigns' ? own.campaigns.length : Number(held[k]) || 0;
      if (n > 0 && !to[k]) { total += n; return plural(n, HELD_WORD[k][0], HELD_WORD[k][1]); }
      return '';
    }).filter(Boolean);
    if (!parts.length) return '';
    var list = parts.length === 1 ? parts[0] : parts.slice(0, -1).join(', ') + ' and ' + parts[parts.length - 1];
    return list.charAt(0).toUpperCase() + list.slice(1) + (total === 1 ? ' stays' : ' stay') + ' with ' + name + '.';
  }
  /* Moves what was chosen: the person in charge by name, the rest through
     `team_hand_over`; one line says what moved and what could not. */
  function handTo(m, own, v) {
    v = handChosen(v || {});
    var nameOf = function (id) { var x = state.rows.filter(function (r) { return r.id === id; })[0]; return x ? x.name : ''; };
    var jobs = [];
    var owned = function (table, list, to) {
      if (!to || !list.length) return;
      jobs.push(db.from(table).update({ owner: to }).in('id', list.map(function (c) { return c.id; })).select('id').then(function (r) {
        if (r.error) return { bad: true };
        /* Each record that moved is filed, even where others were refused (audit, 2026-10-15). */
        var got = (r.data || []).map(function (x) { return x.id; });
        list.filter(function (c) { return got.indexOf(c.id) > -1; }).forEach(function (c) {
          log(table === 'clients' ? 'client.edited' : 'campaign.edited', c.name || c.title, 'Person in charge: ' + m.name + ' to ' + to);
        });
        return got.length < list.length ? { bad: true } : { ok: true };
      }));
    };
    owned('clients', own.clients, nameOf(v.clients));
    owned('campaigns', own.campaigns, nameOf(v.campaigns));
    var to = {};
    HELD_KINDS.forEach(function (k) { if (v[k[0]]) to[k[0]] = v[k[0]]; });
    if (Object.keys(to).length) {
      jobs.push(db.rpc('team_hand_over', { p_member: m.id, p_to: to }).then(function (r) {
        var d = (r && r.data) || {};
        if (r.error || d.error) return { bad: true };
        return { ok: true, skipped: d.skipped && d.skipped.reviews };
      }));
    }
    if (!jobs.length) return Promise.resolve(true);
    return Promise.all(jobs).then(function (res) {
      var bad = res.some(function (x) { return x.bad; });
      var skip = res.reduce(function (n, x) { return n + (Number(x.skipped) || 0); }, 0);
      msg('teamMsg', bad ? 'Saved. Some work could not be handed over; open the colleague\'s ⋯ again to hand it over.'
        : 'Saved. Work handed over.' + (skip ? ' ' + skip + (skip === 1 ? ' report stays' : ' reports stay') +
          ' with them: the colleague chosen submitted it or does not review reports.' : ''), bad ? 'err' : 'ok');
      return !bad;
    }).catch(function () { msg('teamMsg', 'Saved. The work could not be handed over.', 'err'); return false; });
  }
  var REMOVE_SAID = {
    own: 'Your own account is removed by another admin.', 'system-account': 'This is a system account.', 'admin-only': ADMIN_ONLY,
    'bad-name': 'The name does not match.', 'last-admin': 'This is the last admin with access. Make another colleague admin first.',
    denied: 'Team Full Access is required.', 'not-found': 'This colleague is no longer on the team.'
  };
  /* Delete: who takes each kind of their work, then whether their data is
     kept, then their name typed back. Their name on past work, what they
     signed, and their own HR letters and performance records stay either
     way; Delete their data removes their personal details and sign-in. */
  function removeMember(m) {
    heldBy(m, function (own, held) {
      var fields = handFields(m, own, held);
      window.ADspaceConfirm.ask({
        title: 'Delete', tone: 'danger', go: 'Delete', wait: true,
        /* Short enough to read before the fields on a phone (TEAM-10, 2026-10-14). */
        body: m.name + ' loses access for good. There is no restore.' + (fields.length ? ' Choose who takes their work.' : '') +
          ' Past work, HR letters and performance records are kept. Delete their data also removes their mobile, namecard, sign-in and health check-ins.',
        fields: fields.concat([
          { name: 'data', label: 'Their data', choices: [['keep', 'Keep'], ['erase', 'Delete']], seg: true, value: 'keep' },
          { name: 'name', label: 'Type ' + m.name + ' to confirm', match: m.name, required: true }])
      }, function (v) {
        /* A hand-over that failed removes nobody: the question stays open
           saying so (audit I3, 2026-10-15). */
        /* Who may be removed is asked before any work moves: a refusal
           only the removal knew (the last admin) had left the work handed
           over and the colleague in place (audit, 2026-10-15). A database
           without the check goes on as before. */
        return Promise.resolve(db.rpc('team_member_remove_check', { p_member: m.id })).then(function (c) {
          var e = c && !c.error && c.data && c.data.error;
          if (e) return { refused: e };
          return Promise.resolve(handTo(m, own, v)).then(function (moved) { return moved === false ? { held: true } : null; });
        }).then(function (pre) {
          if (pre) return pre;
          return db.rpc('team_member_remove', { p_member: m.id, p_erase: v.data === 'erase', p_name: v.name });
        }).then(function (r) {
          if (r && r.refused) return REMOVE_SAID[r.refused] || r.refused;
          if (r && r.held) return 'Some work could not be handed over, so ' + m.name + ' was not removed. Choose again, or keep it with them.';
          var d = (r && r.data) || {};
          if (r.error) return /does not exist|schema cache/i.test(r.error.message || '') ? 'This needs a database update.' : String(r.error.message || r.error);
          if (d.error) return REMOVE_SAID[d.error] || d.error;
          /* Work left with them is said, with the way to hand it over
             (TEAM-3, 2026-10-14): a removed colleague signs in no more. */
          var kept = keptWord(own, held, v, m.name);
          if (window.ADspaceGroup) window.ADspaceGroup.keep('team', 'off', false);
          msg('teamMsg', (v.data === 'erase' ? 'Removed. Their personal details were deleted.' : 'Removed. Their data is kept.') +
            (kept ? ' ' + kept + ' Hand over work is in their ⋯.' : ''), kept ? 'warn' : 'ok');
          load();
          return '';
        });
      });
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
      db.from('clients').select('id, name, owner, slug, client_code, stage'),
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
      if (k === DASH) return 'Dashboard';
      var bits = k.split('.');
      var sec = SECTIONS.filter(function (x) { return x[0] === bits[0]; })[0];
      var part = bits[1] && (PARTS[bits[0]] || []).filter(function (x) { return x[0] === bits[1]; })[0];
      return (sec ? sec[1] : bits[0]) + (bits[1] ? ' · ' + (part ? part[1] : bits[1]) : '');
    };
    var word = function (k, v) {
      if (k === DASH) return v === 'none' ? 'No Access' : 'On';
      return v ? (LEVEL_WORD[v] || 'No Access') : (k.indexOf('.') > -1 ? 'Same as section' : 'No Access');
    };
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
    if (acc[DASH] === 'none') parts.push('Dashboard: No Access');
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
        /* A group in use has one act, Edit, on its row; a ⋯ only where
           Delete joins it (MENU standard 8, 2026-10-22). */
        : used ? '<span class="team-act"><button class="btn btn-sm" data-a="rename" type="button">' + (window.ADspaceActs ? window.ADspaceActs.glyph('edit') : '') + 'Edit</button></span>'
        : menuBtn(menuItem('rename', 'Edit') + menuItem('del', 'Delete', 'is-danger')));

    wireMenu(el);
    var ren = el.querySelector('[data-a="rename"]');
    if (ren) ren.addEventListener('click', function () { openGroupBox(r, this); });
    var del = el.querySelector('[data-a="del"]');
    if (del) del.addEventListener('click', function () {
      window.ADspaceConfirm.ask({
        title: 'Delete',
        body: 'The ' + r.name + ' group and the access it carries go. There is no restore.',
        go: 'Delete',
        tone: 'danger',
        field: { label: 'Type the group name to confirm', placeholder: r.name, match: r.name, need: 'Type the group name to confirm.', mismatch: 'The group name does not match.' }
      }, function () {
        /* PostgREST answers a delete a policy refused with no error and no
           row gone, so ask for the row back: an empty answer is a refusal,
           not a success, and the group stays in the list saying so. */
        db.from('team_roles').delete().eq('slug', r.slug).select('slug').then(function (q) {
          if (q.error) { msg('groupMsg', teamSaid(q.error), 'err'); return; }
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

  /* The sheet stays open until the write answers (2026-10-20, TEAM-2): a
     refusal is said in it with every change kept, and a group changed
     meanwhile is read again under it, so the next Save goes over the row
     as it stands. */
  function saveGroup(r, patch, btn) {
    var was = Object.assign({}, r, { access: Object.assign({}, r.access || {}) });
    var fail = function (t) {
      if (btn) btn.disabled = false;
      msg('grMsg', t, 'err');
      try { $('grMsg').scrollIntoView({ block: 'nearest' }); } catch (e) {}
    };
    if (btn) btn.disabled = true;
    asRead(db.from('team_roles').update(patch).eq('slug', r.slug), r).select('slug').then(function (q) {
      if (q.error) { fail(/scope-activity/.test(q.error.message || '') ? SCOPE_CLASH : teamSaid(q.error)); return; }
      if (!(q.data || []).length) {
        noRow('team_roles', 'slug', r, function (t) {
          load(function () {
            var now = state.roles.filter(function (x) { return x.slug === r.slug; })[0];
            if (now && state.editing === r) state.editing = now;
            fail(t);
          });
        });
        return;
      }
      if (btn) btn.disabled = false;
      shutGroupBox();
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
     what the database's own checks open at that level, checked line by line
     against may() and the policies (2026-10-20, TEAM-1). */
  var DESC = {
    ops: { none: 'My Work is hidden.', view: 'See your own tasks.',
           work: 'Also update and create tasks, and add months.', manage: 'Also reassign, archive and delete tasks, and delete months.' },
    clients: { none: 'Clients is hidden.', view: 'Read client records.',
               work: 'Add leads, edit records, log calls and issue letters.', manage: 'Also delete clients and letters, void letters and change the person in charge.' },
    whatsapp: { none: 'WhatsApp is hidden, and no record offers it.', view: 'Read every message sent and its status.',
                work: 'Send messages from WhatsApp and from records.', manage: 'Also choose the templates and turn them on or off.' },
    review: { none: 'Content Review is hidden.', view: 'Read content sets and posts.',
              work: 'Add sets and posts, import from Drive and publish.', manage: 'Also delete content sets and posts.' },
    scripts: { none: 'Video Scripts is hidden.', view: 'Read scripts and download their PDFs.',
               work: 'Write scripts, publish them to the client and record the clips on the day.', manage: 'Also delete scripts.' },
    campaigns: { none: 'Creator Campaigns is hidden.', view: 'Read campaigns and the Creators List.',
                 work: 'Run campaigns, book creators and release drafts.', manage: 'Also delete campaigns and remove creators.' },
    register: { none: 'Documents is hidden.', view: 'Read and download documents.',
                work: 'Issue, reissue and add documents.', manage: 'Also void and delete documents.' },
    suppliers: { none: 'Suppliers is hidden.', view: 'Read suppliers and their letters.',
                 work: 'Add suppliers, send their details form and take it in. Approving needs Supplier bank details.', manage: 'Also delete suppliers and edit their email templates.' },
    reports: { none: 'Reports is hidden.', view: 'Read reports and preview their PDFs.',
               work: 'Start reports, enter figures and submit them for review.', manage: 'Also confirm, return, publish, unpublish and delete reports.' },
    links: { none: 'Short Links is hidden.', view: 'Read short links.',
             work: 'Add, edit and pause short links.', manage: 'Also delete short links.' },
    services: { none: 'Services is hidden.', view: 'Read the rate card.',
                work: 'Read the rate card. Changes need Full Access.', manage: 'Add, edit and delete rate card lines, and publish the rate card.' },
    team: { none: 'Team is hidden.', manage: 'Add colleagues and edit user groups. Invitations need Send invitation.' },
    activity: { none: 'The activity record is hidden.', view: 'Read the activity record, tab by tab.' }
  };

  /* A group starts from one of four shapes and is adjusted from there; a
     change that matches none of them reads as Custom. Sensitive parts (HR
     letters, performance reviews, Team) are never in a preset below Admin:
     they are opened deliberately, in Customise. */
  var PRESETS = {
    manager: { ops: 'manage', clients: 'manage', whatsapp: 'work', review: 'manage', scripts: 'manage', campaigns: 'manage', register: 'manage', suppliers: 'manage', reports: 'manage',
               links: 'manage', services: 'manage', team: 'none', activity: 'view',
               'ops.all': 'view', 'ops.reports': 'view', 'ops.workflows': 'work', 'ops.time': 'manage',
               'register.hr': 'none' },
    staff:   { ops: 'work', clients: 'work', whatsapp: 'work', review: 'work', scripts: 'work', campaigns: 'work', register: 'view', suppliers: 'view', reports: 'work',
               links: 'work', services: 'view', team: 'none', activity: 'none', 'register.hr': 'none' },
    viewer:  { ops: 'view', clients: 'view', whatsapp: 'view', review: 'view', scripts: 'view', campaigns: 'view', register: 'view', suppliers: 'view', reports: 'view',
               links: 'view', services: 'view', team: 'none', activity: 'view', 'register.hr': 'none' }
  };

  /* THE PANEL, SIMPLER (2026-10-10, the proposal the user approved). It
     opens on a role and says only what differs from it; the sections are
     read in the rail's two chunks, one row each; a section's own parts open
     under its Customise and, shut, name only the ones that differ; the acts
     an admin alone took are one Admin tools list in the Settings page's
     groups; the three My Work views are not offered, since they follow My
     Work. Only the screen changed: the stored map, `adds()`, `offered()`,
     `PART_LEVELS` and every database check are as they were. */
  var CHUNKS = [
    ['Work', ['ops', 'clients', 'review', 'scripts', 'campaigns', 'reports', 'whatsapp']],
    ['Internal', ['register', 'suppliers', 'links', 'services', 'team', 'activity']]
  ];
  /* Each is on or off, and each is an admin's alone until a group is given
     it. Portal first (what changes the portal for everybody), then each
     under its own section in the rail's order (the user, 2026-10-12: "not
     properly rearranged"). */
  var ADMIN_TOOLS = [
    ['Portal', ['team.upgrade', 'team.announce', 'team.notice', 'team.settings', 'reports.ai']],
    ['My Work', ['ops.numbering', 'ops.override']],
    ['Clients', ['clients.vic']],
    ['Creator Campaigns', ['campaigns.files_delete']],
    ['Reports', ['reports.meta', 'reports.whitelabel', 'reports.transfer']],
    ['Documents', ['register.types']],
    ['Team', ['team.invite', 'team.handbook', 'team.perfadmin']]
  ];
  /* The three My Work views follow My Work and are not offered here, nor
     is Team: Health, an admin's alone (2026-10-18, Team audit 11). */
  var UNDRAWN = { 'ops.list': 1, 'ops.board': 1, 'ops.calendar': 1, 'team.health': 1 };
  var TOOL = {};
  ADMIN_TOOLS.forEach(function (g) { g[1].forEach(function (k) { TOOL[k] = 1; }); });
  function secOf(key) { return SECTIONS.filter(function (s) { return s[0] === key; })[0]; }
  function partName(key) {
    var bits = key.split('.'), p = (PARTS[bits[0]] || []).filter(function (x) { return x[0] === bits[1]; })[0];
    return p ? p[1] : bits[1];
  }
  /* The parts a section's Customise offers: its own, less the admin tools
     and the views that follow My Work. */
  function ownParts(sec) {
    return (PARTS[sec] || []).filter(function (p) { var k = sec + '.' + p[0]; return !TOOL[k] && !UNDRAWN[k]; });
  }
  /* What each part covers, one line under its name (2026-10-22): a part's
     name alone left a group unsure that Service lines held no quotations. */
  var PART_DESC = {
    'clients.contacts': 'The client\'s people and their portal access.',
    'clients.billing': 'Registered name, BRN, billing contact and address.',
    'clients.quotes': 'Build quote and the client\'s quotations.',
    'clients.services': 'The client\'s service lines and their rates.',
    'clients.documents': 'Letters of Offer and client letters: issue, sign and void.',
    'clients.requests': 'Changes the client asks for in the portal.',
    'clients.calls': 'Calls, visits and meetings logged.',
    'clients.brand': 'Brand profile, content brief, Meta accounts and Brand analysis.',
    'clients.checklists': 'The onboarding and pre-advertising checklists.',
    'clients.leads': 'Leads, Contacted and Proposal sent.',
    'clients.past': 'Past clients.',
    'whatsapp.report': 'A published report sent to the client.',
    'whatsapp.feedback': 'A feedback request to the client.',
    'whatsapp.booking': 'A creator\'s booking message.',
    'whatsapp.approval': 'A reminder of what waits on the client\'s approval.',
    'whatsapp.documents': 'A quotation or Letter of Offer sent to the client.',
    'review.sets': 'Content sets, posts and their decisions.',
    'review.settings': 'The review link, access code, handles and logo.',
    'campaigns.campaigns': 'Campaigns, bookings and drafts.',
    'campaigns.creators': 'The Creators List.',
    'campaigns.finance': 'The invoice number and its PDF.',
    'register.documents': 'Client letters and other documents.',
    'register.hr': 'HR letters and downloaded performance records.',
    'suppliers.pay': 'A supplier\'s NRIC and bank details.',
    'ops.all': 'Every colleague\'s tasks, not only one\'s own.',
    'ops.time': 'Correct another colleague\'s time records.',
    'team.performance': 'Monthly performance reviews, behind the master code.'
  };
  var SEG_ICON = '<span class="disclosure-caret" aria-hidden="true">&#9656;</span>';
  function partRow(sec, p) {
    var key = sec[0] + '.' + p[0], granted = isGranted(key);
    return '<label class="permpart"><span class="permpart-name">' + esc(p[1]) +
      (PART_DESC[key] ? '<small>' + esc(PART_DESC[key]) + '</small>' : '') + '</span>' +
      '<select class="select select-sm" data-part="' + key + '" aria-label="' + esc(sec[1] + ': ' + p[1]) + ' access">' +
      /* A granted part is not inherited, so its unset state is No Access,
         said once; an inherited part starts at Same as section and may
         still be shut on its own. */
      (granted ? '<option value="">No Access</option>'
               : '<option value="">Same as section</option><option value="none">No Access</option>') +
      /* A part that follows its section or is shut has those two lines. */
      (VIEW_PARTS[key] ? '' :
        partLevels(key).map(function (l) { return '<option value="' + l + '">' + esc(LEVEL_WORD[l]) + '</option>'; }).join('')) +
      '</select></label>';
  }
  function secBlock(key) {
    var sec = secOf(key), parts = ownParts(key), fold = parts.length || key === 'clients';
    return '<div class="permsec" data-sec="' + key + '">' +
      '<span class="permsec-name">' + esc(sec[1]) + '</span>' +
      '<select class="select select-sm" data-seg data-sec="' + key + '" aria-label="' + esc(sec[1]) + ' access">' +
        LEVELS.filter(function (l) { return sec[2].indexOf(l[0]) > -1; }).map(function (l) {
          return '<option value="' + l[0] + '">' + esc(l[1]) + '</option>';
        }).join('') + '</select>' +
      '<p class="permsec-desc" id="grDesc-' + key + '"></p>' +
      (fold ? '<button class="permsec-toggle" type="button" aria-expanded="false" aria-controls="grParts-' + key + '">' +
          '<span>Customise</span><span class="permsec-n" data-n="' + key + '"></span>' + SEG_ICON + '</button>' : '') +
      '<p class="permsec-diff" id="grDiff-' + key + '" hidden></p>' +
      (fold ? '<div class="permsec-parts" id="grParts-' + key + '" hidden>' + parts.map(function (p) { return partRow(sec, p); }).join('') +
        /* Whose clients the group sees, in every section: all, or the ones
           its colleague is Person in charge of with any lead nobody holds
           (`team_roles.client_scope`). */
        (key === 'clients' ? '<label class="permpart"><span class="permpart-name">Clients they see</span>' +
          '<select class="select select-sm" id="grScope" aria-label="Clients: clients they see">' +
          '<option value="all">All clients</option><option value="own">Own clients only</option></select></label>' : '') +
        '</div>' : '') +
      '</div>';
  }
  $('grFlags').innerHTML =
    '<div class="permchunk permdash"><div class="permsec" data-sec="' + DASH + '">' +
      '<span class="permsec-name">Dashboard</span>' +
      '<select class="select select-sm" data-seg id="grDash" aria-label="Dashboard access">' +
        '<option value="none">No Access</option><option value="on">On</option></select>' +
      '<p class="permsec-desc" id="grDesc-' + DASH + '"></p></div></div>' +
    CHUNKS.map(function (c) {
      return '<div class="permchunk"><h4 class="fsec-h">' + esc(c[0]) + '</h4>' + c[1].map(secBlock).join('') + '</div>';
    }).join('') +
    '<div class="permchunk permtools"><div class="permsec" data-sec="tools">' +
      '<span class="permsec-name"><h4 class="fsec-h">Admin tools</h4></span>' +
      '<button class="permsec-toggle" type="button" aria-expanded="false" aria-controls="grParts-tools">' +
        '<span>Customise</span><span class="permsec-n" data-n="tools"></span>' + SEG_ICON + '</button>' +
      '<p class="permsec-diff" id="grDiff-tools" hidden></p>' +
      '<div class="permsec-parts permtool-list" id="grParts-tools" hidden>' +
        ADMIN_TOOLS.map(function (g) {
          return '<div class="permtool-group"><span class="permtool-h">' + esc(g[0]) + '</span>' + g[1].map(function (k) {
            return '<div class="permpart"><span class="permpart-name" id="grTool-' + k.replace('.', '-') + '">' + esc(partName(k)) + '</span>' +
              '<button class="switch" type="button" role="switch" aria-checked="false" data-tool="' + k + '" aria-labelledby="grTool-' + k.replace('.', '-') + '"></button></div>';
          }).join('') + '</div>';
        }).join('') +
      '</div></div></div>' +
    /* Admin is chosen from Start from, which already names it (2026-09-26).
       The box stays, unseen, because it is what the save reads. */
    '<input type="checkbox" data-f="is_admin" hidden tabindex="-1" aria-hidden="true">';
  function flagBoxes() { return Array.prototype.slice.call($('grFlags').querySelectorAll('input')); }
  function levelPicks() { return Array.prototype.slice.call($('grFlags').querySelectorAll('select[data-sec]')); }
  function partPicks() { return Array.prototype.slice.call($('grFlags').querySelectorAll('select[data-part]')); }
  function toolSwitches() { return Array.prototype.slice.call($('grFlags').querySelectorAll('[data-tool]')); }
  function adminBox() { return flagBoxes().filter(function (cb) { return cb.getAttribute('data-f') === 'is_admin'; })[0]; }
  levelPicks().forEach(function (sel) {
    if (window.ADspaceForm) window.ADspaceForm.segment(sel);
    if (sel.__seg) sel.__seg.setAttribute('aria-describedby', 'grDesc-' + sel.getAttribute('data-sec'));
  });
  if (window.ADspaceForm) window.ADspaceForm.segment($('grPreset'));
  if (window.ADspaceForm) window.ADspaceForm.segment($('grDash'));
  if ($('grDash').__seg) $('grDash').__seg.setAttribute('aria-describedby', 'grDesc-' + DASH);
  function foldSec(sec, open) {
    var box = $('grParts-' + sec), btn = $('grFlags').querySelector('.permsec[data-sec="' + sec + '"] .permsec-toggle');
    if (!box || !btn) return;
    box.hidden = !open;
    btn.setAttribute('aria-expanded', String(open));
  }
  function foldAll() {
    Array.prototype.forEach.call($('grFlags').querySelectorAll('.permsec-toggle'), function (b) {
      foldSec(b.closest('.permsec').getAttribute('data-sec'), false);
    });
  }
  Array.prototype.forEach.call($('grFlags').querySelectorAll('.permsec-toggle'), function (btn) {
    btn.addEventListener('click', function () {
      var sec = btn.closest('.permsec').getAttribute('data-sec');
      foldSec(sec, $('grParts-' + sec).hidden);
      paintPanel();
    });
  });
  toolSwitches().forEach(function (sw) {
    sw.addEventListener('click', function () {
      if (sw.disabled) return;
      sw.setAttribute('aria-checked', sw.getAttribute('aria-checked') === 'true' ? 'false' : 'true');
      paintPanel();
    });
  });

  /* A part the panel does not draw (the three My Work views) keeps what the
     group already stores, so saving never changes it unseen; a preset clears
     it, since a preset is the whole shape. */
  var carried = {};
  /* The access the panel holds now, as it would be stored: every section,
     and a part only where it says something its section does not. */
  function readAccess() {
    var access = {};
    if ($('grDash').value === 'none') access[DASH] = 'none';
    levelPicks().forEach(function (sel) { access[sel.getAttribute('data-sec')] = sel.value || 'none'; });
    partPicks().forEach(function (sel) {
      var k = sel.getAttribute('data-part');
      var same = isGranted(k) ? 'none' : (access[k.split('.')[0]] || 'none');
      if (sel.value && adds(k, sel.value, same)) access[k] = sel.value;
    });
    toolSwitches().forEach(function (sw) {
      if (sw.getAttribute('aria-checked') === 'true') access[sw.getAttribute('data-tool')] = partLevels(sw.getAttribute('data-tool'))[0];
    });
    Object.keys(carried).forEach(function (k) {
      var same = access[k.split('.')[0]] || 'none';
      if (adds(k, carried[k], same)) access[k] = carried[k];
    });
    return access;
  }
  /* The same access in one comparable shape, whatever was stored before:
     every section, and every part that says something of its own. */
  function canonMap(acc) {
    var out = {};
    if (acc && acc[DASH] === 'none') out[DASH] = 'none';
    SECTIONS.forEach(function (s) { out[s[0]] = (acc && acc[s[0]]) || 'none'; });
    Object.keys(PARTS).forEach(function (sec) {
      PARTS[sec].forEach(function (p) {
        var k = sec + '.' + p[0], v = offered(k, exceptionOf(acc, k));
        if (v) out[k] = v;
      });
    });
    return out;
  }
  /* A key's value in the panel's words: a section's level, a part's (Same
     as section where it says nothing of its own), an admin tool On or Off. */
  function valueWord(k, v) {
    if (k === DASH) return v === 'none' ? 'No Access' : 'On';
    if (TOOL[k]) return v ? 'On' : 'Off';
    if (k.indexOf('.') < 0) return LEVEL_WORD[v] || 'No Access';
    if (!v) return isGranted(k) ? 'No Access' : 'Same as section';
    return LEVEL_WORD[v] || 'No Access';
  }
  function keyName(k) {
    if (k === DASH) return 'Dashboard';
    if (TOOL[k]) return partName(k);
    var bits = k.split('.'), sec = secOf(bits[0]);
    return bits[1] ? partName(k) + ' (' + (sec ? sec[1] : bits[0]) + ')' : (sec ? sec[1] : bits[0]);
  }
  /* What separates two shapes, key by key, in the panel's order. */
  function changesFrom(acc, scope, base) {
    var a = canonMap(acc), b = canonMap(base), out = [];
    var keys = Object.keys(a).concat(Object.keys(b)).filter(function (k, i, x) { return x.indexOf(k) === i; });
    var order = function (k) {
      if (k === DASH) return -1;
      var bits = k.split('.'), i = SECTIONS.map(function (s) { return s[0]; }).indexOf(bits[0]);
      var j = bits[1] ? 1 + (PARTS[bits[0]] || []).map(function (p) { return p[0]; }).indexOf(bits[1]) : 0;
      return (TOOL[k] ? 1000 : 0) + i * 50 + j;
    };
    keys.sort(function (x, y) { return order(x) - order(y); }).forEach(function (k) {
      if ((a[k] || '') === (b[k] || '')) return;
      /* A part of a section the group does not open says nothing more. */
      var sec = k.split('.')[0];
      if (k.indexOf('.') > 0 && !TOOL[k] && a[sec] === 'none' && (!a[k] || a[k] === 'none')) return;
      out.push(keyName(k) + ': ' + valueWord(k, a[k]));
    });
    if (scope === 'own') out.splice(0, 0, 'Own clients only');
    return out;
  }
  var PRESET_WORD = { admin: 'Admin', manager: 'Manager', staff: 'Staff', viewer: 'View only' };
  /* The preset the panel matches, else the nearest one and what differs
     from it, so a group reads "Custom: 3 changes from Staff". */
  function shapeOf(acc, admin, scope) {
    if (admin) return { key: 'admin', changes: [] };
    var best = null;
    Object.keys(PRESETS).forEach(function (k) {
      var c = changesFrom(acc, scope, PRESETS[k]);
      if (!best || c.length < best.changes.length) best = { key: k, changes: c };
    });
    return best;
  }
  /* "A, B and C" inside a level; the levels themselves are joined with a
     comma before the last ("work A and B, and view C"), so the two kinds of
     "and" are never read as one list. */
  function listWords(xs, sep) {
    if (xs.length < 2) return xs.join('');
    return xs.slice(0, -1).join(', ') + (sep || ' and ') + xs[xs.length - 1];
  }
  /* The group in one sentence, read from the panel as it stands, in the
     panel's own words (Team audit, 2026-10-03). */
  function sumText(acc, admin, tuned, scope, tools) {
    if (admin) return 'This group can do everything, in every section.';
    var by = { manage: [], work: [], view: [] };
    SECTIONS.forEach(function (s) { var v = acc[s[0]] || 'none'; if (by[v]) by[v].push(s[1]); });
    var said = ['manage', 'work', 'view'].filter(function (lv) { return by[lv].length; }).map(function (lv) {
      return LEVEL_WORD[lv] + ' on ' + listWords(by[lv]);
    });
    var line = said.length ? 'This group has ' + listWords(said, ', and ') + '.' : 'This group has no access.';
    if (scope === 'own') line += ' Own clients only.';
    if (acc[DASH] === 'none') line += ' The Dashboard is hidden.';
    /* What differs is counted once, against the preset, by the Custom note
       (2026-10-20, TEAM-8); the sentence names no count of its own. */
    if (tools) line += ' ' + tools + (tools === 1 ? ' admin tool is' : ' admin tools are') + ' on.';
    return line;
  }
  /* Everything that follows a change: each section's line, what differs
     under it, the shape the panel matches, and the sentence at the top. */
  function paintPanel() {
    var access = readAccess();
    var adm = adminBox();
    var admin = Boolean(adm && adm.checked), locked = Boolean(state.editing && state.editing.slug === 'admin');
    var tuned = 0;
    /* On shows nothing without a section at Full Access (2026-10-20, TEAM-7). */
    $('grDesc-' + DASH).textContent = admin ? 'Every level, as an admin.' : access[DASH] === 'none' ? DASH_DESC.none
      : SECTIONS.some(function (s) { return access[s[0]] === 'manage'; }) ? DASH_DESC.on : DASH_DESC.empty;
    $('grDash').disabled = locked || admin;
    SECTIONS.forEach(function (s) {
      var d = $('grDesc-' + s[0]);
      if (d) d.textContent = admin ? 'Every level, as an admin.' : (DESC[s[0]][access[s[0]] || 'none'] || '');
      /* The team's figures (the Dashboard's My Work tiles and charts)
         are a grant of their own (2026-10-03). */
      if (d && !admin && s[0] === 'ops' && (access.ops || 'none') !== 'none' && !access['ops.reports']) {
        d.textContent += ' Team figures on the Dashboard need their part in Customise.';
      }
      var diff = (PARTS[s[0]] || []).filter(function (p) { var k = s[0] + '.' + p[0]; return !TOOL[k] && (k in access); })
        .map(function (p) { var k = s[0] + '.' + p[0]; return p[1] + ': ' + valueWord(k, access[k]); });
      if (s[0] === 'clients' && readScope() === 'own') diff.push('Own clients only');
      tuned += diff.length;
      var n = $('grFlags').querySelector('[data-n="' + s[0] + '"]');
      if (n) n.textContent = diff.length ? '(' + diff.length + ')' : '';
      /* Shut, a section names only what differs; open, its parts say it. */
      var line = $('grDiff-' + s[0]), parts = $('grParts-' + s[0]);
      if (line) {
        line.textContent = admin ? '' : diff.join(' · ');
        line.hidden = admin || !diff.length || Boolean(parts && !parts.hidden);
      }
    });
    var on = toolSwitches().filter(function (sw) { return sw.getAttribute('aria-checked') === 'true'; });
    var tn = $('grFlags').querySelector('[data-n="tools"]');
    tn.textContent = admin ? '' : '(' + on.length + ' on)';
    var tl = $('grDiff-tools');
    tl.textContent = admin ? '' : on.map(function (sw) { return partName(sw.getAttribute('data-tool')); }).join(' · ');
    tl.hidden = admin || !on.length || !$('grParts-tools').hidden;
    /* An admin opens everything, so the levels under it decide nothing and
       are not offered for change while it is chosen. */
    levelPicks().concat(partPicks()).forEach(function (sel) { sel.disabled = locked || admin; });
    toolSwitches().forEach(function (sw) {
      sw.disabled = locked || admin;
    });
    $('grScope').disabled = locked || admin;
    var shape = shapeOf(access, admin, readScope());
    var n2 = shape.changes.length;
    $('grPreset').value = n2 ? 'custom' : shape.key;
    $('grPreset').disabled = locked;
    /* The changes themselves fold under the note, which the sentence above
       already reads back (TEAM-4, 2026-10-14). */
    $('grPresetNote').hidden = !n2;
    $('grPresetNote').textContent = n2 ? 'Custom: ' + n2 + (n2 === 1 ? ' change' : ' changes') + ' from ' + PRESET_WORD[shape.key] : '';
    if (!n2) $('grPresetNote').setAttribute('aria-expanded', 'false');
    $('grChanges').hidden = !n2 || $('grPresetNote').getAttribute('aria-expanded') !== 'true';
    $('grChanges').textContent = n2 ? shape.changes.join(' · ') : '';
    $('grSum').textContent = sumText(access, admin, tuned, readScope(), on.length);
  }
  function setTools(acc) {
    toolSwitches().forEach(function (sw) {
      var k = sw.getAttribute('data-tool');
      sw.setAttribute('aria-checked', offered(k, exceptionOf(acc, k)) ? 'true' : 'false');
    });
  }
  function applyPreset(k) {
    var adm = adminBox();
    if (adm) adm.checked = k === 'admin';
    $('grScope').value = 'all';
    $('grDash').value = 'on';
    carried = {};
    if (k !== 'admin') {
      var acc = PRESETS[k];
      levelPicks().forEach(function (sel) { sel.value = acc[sel.getAttribute('data-sec')] || 'none'; });
      partPicks().forEach(function (sel) {
        var key = sel.getAttribute('data-part');
        sel.value = offered(key, exceptionOf(acc, key));
      });
      setTools(acc);
    }
    foldAll();
    paintPanel();
  }
  $('grPresetNote').addEventListener('click', function () {
    var open = this.getAttribute('aria-expanded') !== 'true';
    this.setAttribute('aria-expanded', open ? 'true' : 'false');
    $('grChanges').hidden = !open;
  });
  $('grPreset').addEventListener('change', function () {
    if (this.value && this.value !== 'custom') applyPreset(this.value);
  });
  $('grFlags').addEventListener('change', paintPanel);

  /* Compare groups: every group side by side, read only, so which group
     opens what is checked at a glance before a colleague is placed in one. */
  function cmpCell(r, sec) {
    if (r.is_admin) return { word: LEVEL_WORD[secOf(sec)[2][secOf(sec)[2].length - 1]], n: 0 };
    var acc = accessOf(r), lv = acc[sec] || 'none';
    var n = ownParts(sec).filter(function (p) { return Boolean(offered(sec + '.' + p[0], exceptionOf(acc, sec + '.' + p[0]))); }).length +
      (sec === 'clients' && r.client_scope === 'own' ? 1 : 0);
    return { word: LEVEL_WORD[lv] || 'No Access', n: n, off: lv === 'none' };
  }
  function paintCompare() {
    var roles = state.roles, box = $('grCmp');
    var cols = 'style="--cols:' + roles.length + '"';
    var cell = function (g, inner, cls) {
      return '<span class="permcmp-cell' + (cls ? ' ' + cls : '') + '" data-g="' + esc(g) + '">' + inner + '</span>';
    };
    var html = '<div class="permcmp-row permcmp-head" ' + cols + '><span class="permcmp-sec">Section</span>' +
      roles.map(function (r) { return cell(r.name, esc(r.name)); }).join('') + '</div>' +
      '<div class="permcmp-row" ' + cols + '><span class="permcmp-sec">Dashboard</span>' +
      roles.map(function (r) {
        var acc = accessOf(r), off = !r.is_admin && acc[DASH] === 'none';
        var none = !off && !r.is_admin && !SECTIONS.some(function (s) { return acc[s[0]] === 'manage'; });
        return cell(r.name, '<b>' + (off ? 'No Access' : 'On') + '</b>' + (none ? '<small>Nothing shown without Full Access</small>' : ''), off ? 'is-off' : '');
      }).join('') + '</div>';
    CHUNKS.forEach(function (c) {
      html += '<div class="permcmp-chunk">' + esc(c[0]) + '</div>';
      c[1].forEach(function (sec) {
        html += '<div class="permcmp-row" ' + cols + '><span class="permcmp-sec">' + esc(secOf(sec)[1]) + '</span>' +
          roles.map(function (r) {
            var v = cmpCell(r, sec);
            return cell(r.name, '<b>' + esc(v.word) + '</b>' + (v.n ? '<small>' + v.n + ' customised</small>' : ''), v.off ? 'is-off' : '');
          }).join('') + '</div>';
      });
    });
    html += '<div class="permcmp-chunk">Admin tools</div><div class="permcmp-row" ' + cols + '><span class="permcmp-sec">On</span>' +
      roles.map(function (r) {
        var acc = accessOf(r), total = Object.keys(TOOL).length;
        var n = r.is_admin ? total : Object.keys(TOOL).filter(function (k) { return Boolean(offered(k, exceptionOf(acc, k))); }).length;
        return cell(r.name, '<b>' + n + ' of ' + total + '</b>', n ? '' : 'is-off');
      }).join('') + '</div>';
    box.innerHTML = html;
  }
  $('groupCompare').addEventListener('click', function () {
    shutMenus();
    paintCompare();
    window.ADspaceSheet.show($('groupCmpBox'), { opener: this });
  });
  $('grCmpClose').addEventListener('click', function () { window.ADspaceSheet.close(); });

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
    $('grPresetNote').setAttribute('aria-expanded', 'false');
    // A new group starts able to work the section everybody needs, and to
    // read nothing else: what it may destroy is always chosen deliberately.
    var acc = r ? accessOf(r) : null;
    $('grDash').value = acc && acc[DASH] === 'none' ? 'none' : 'on';
    levelPicks().forEach(function (sel) {
      var k = sel.getAttribute('data-sec');
      sel.value = acc ? (acc[k] || 'none') : (k === 'clients' ? 'work' : 'none');
      if (!sel.value) sel.value = 'none';
      sel.disabled = Boolean(r && r.slug === 'admin');
    });
    /* Every fold opens shut: a section names what differs on its own line,
       so the panel reads in one screen and Customise opens the rest.

       A part that says what its section already says is not an exception.
       The HR move wrote `register.hr` onto every group, `none` included, so
       a stored level equal to the one it would have inherited reads as Same
       as section and is not saved again. */
    partPicks().forEach(function (sel) {
      var k = sel.getAttribute('data-part');
      sel.value = offered(k, exceptionOf(acc, k));
      sel.disabled = Boolean(r && r.slug === 'admin');
    });
    setTools(acc);
    carried = {};
    Object.keys(UNDRAWN).forEach(function (k) {
      var v = exceptionOf(acc, k);
      if (v) carried[k] = v;
    });
    $('grScope').value = r && r.client_scope === 'own' ? 'own' : 'all';
    $('grScope').disabled = Boolean(r && r.slug === 'admin');
    foldAll();
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
    /* The Activity record is not scoped, so a group seeing only its own
       clients holds none of it (the database's `team_roles_scope_guard`). */
    var admin = 'is_admin' in flags ? flags.is_admin : Boolean(state.editing && state.editing.is_admin);
    if (scopeClash(access, readScope(), admin)) { msg('grMsg', SCOPE_CLASH, 'err'); return; }
    if (state.editing) {
      var r = state.editing;
      var patch = {};
      if (name !== r.name) patch.name = name;
      Object.keys(flags).forEach(function (k) { if (Boolean(r[k]) !== flags[k]) patch[k] = flags[k]; });
      if (JSON.stringify(accessOf(r)) !== JSON.stringify(access)) patch.access = access;
      if ((r.client_scope || 'all') !== readScope()) patch.client_scope = readScope();
      if (Object.keys(patch).length) saveGroup(r, patch, $('grSave')); else shutGroupBox();
      return;
    }
    var slug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
    if (!slug) { msg('grMsg', 'Use letters or numbers in the name.', 'err'); return; }
    if (state.roles.some(function (r) { return r.slug === slug; })) { msg('grMsg', 'That group already exists.', 'err'); return; }
    var row = { slug: slug, name: name, position: state.roles.length, access: access, client_scope: readScope() };
    Object.keys(flags).forEach(function (k) { row[k] = flags[k]; });
    db.from('team_roles').insert(row).then(function (q) {
      if (q.error) { msg('grMsg', /scope-activity/.test(q.error.message || '') ? SCOPE_CLASH : teamSaid(q.error), 'err'); return; }
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
  function amAdmin() { return Boolean(window.ADspaceAdmin && window.ADspaceAdmin.isAdmin && window.ADspaceAdmin.isAdmin()); }
  function openMemberBox(m, opener) {
    shutMenus();
    editingMember = m || null;
    memberOpener = opener || null;
    $('tmTitle').textContent = m ? 'Edit member' : 'New team member';
    $('tmSave').textContent = m ? 'Save' : 'Add';
    $('tmName').value = m ? (m.name || '') : '';
    $('tmEmail').value = m ? (m.email || '') : '';
    /* A colleague's sign-in email is changed by an admin alone (2026-10-18). */
    $('tmEmail').readOnly = !!(m && !amAdmin());
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
        /* Two plain sentences (TEAM-9, 2026-10-14). */
        body: 'Applies to ' + others + (others === 1 ? ' active colleague' : ' active colleagues') + ', not including you. Leave the date empty for no end.',
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
    if (cardSlug && !/^[a-z0-9][a-z0-9._-]{2,79}$/.test(cardSlug)) {
      msg('tmMsg', 'Use at least three characters: lowercase letters, digits, dots, dashes or underscores.', 'err'); $('tmCardSlug').focus(); return;
    }
    var fields = { name: name, email: email, role: role, staff_code: staff || null, designation: desig || null,
                   department: $('tmDept').value || null, role_family: $('tmRoleStd').value || null,
                   capacity_minutes_week: capH >= 0 && $('tmCap').value ? Math.round(capH * 60) : null,
                   mobile: mobile || null, card_on: $('tmCardOn').value !== 'off',
                   card_mobile: $('tmCardMobile').value !== 'hide' };
    /* Empty makes it again from the name; unchanged is not sent. */
    if (!editingMember || cardSlug !== (editingMember.card_slug || '')) fields.card_slug = cardSlug || null;
    /* An email not changed is not sent: only an admin moves one. */
    if (editingMember && email === String(editingMember.email || '').toLowerCase()) delete fields.email;
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
        asRead(db.from('team_members').update(fields).eq('id', m.id), m).select('id').then(function (r) {
          if (!r.error && !(r.data || []).length) {
            /* Changed meanwhile: the sheet opens again on the colleague as
               saved now, saying so; a refusal is said where it was. */
            noRow('team_members', 'id', m, function (t) {
              if (t !== STALE) { msg('teamMsg', t, 'err'); return; }
              load(function () {
                var fresh = (state.rows || []).filter(function (x) { return x.id === m.id; })[0];
                if (fresh) { openMemberBox(fresh, memberOpener); msg('tmMsg', t, 'err'); } else msg('teamMsg', t, 'err');
              });
            });
            return;
          }
          if (r.error) {
            msg('teamMsg', clashSaid(r.error), 'err');
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
          sheetClash(r.error);
          return;
        }
        log('team.added', name, email + ' · ' + roleName(role));
        shutMemberBox();
        load();
        /* Only a colleague holding Send invitation invites; anyone else adds
           the colleague plainly, as the record's ⋯ offers them no invitation
           (2026-10-20, TEAM-12). */
        if (!may('team.invite', 'work')) { msg('teamMsg', name + ' added.', 'ok'); return; }
        // The row is theirs; now the login. The function holds the key the
        // browser must not, and emails them the sign-in link.
        msg('teamMsg', name + ' added. Sending invitation…', 'ok');
        API.invokeFn('invite-member', { email: email, name: name })
          .then(function (r) {
            var d = r.data || {};
            if (r.error) {
              var why = (d.error === 'not_admin') ? 'Sending an invitation needs Team: Send invitation.'
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
          + 'Once sent, it cannot be withdrawn.',
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


  // ---- A colleague's record (2026-10-18) ------------------------------------
  /* The user, 2026-10-18: a colleague holds as many functions as a client,
     so they are a record of their own as a client is (`member=`): the head
     (the mark, the name, Employee ID and group, the state, the row's own ⋯),
     then a pane at a time (`mtab=`, Overview left out): Overview, Work,
     Documents, Performance, Health, each drawn only where its section is
     readable. The list stays the way in; Back returns to it. */
  var rec = { id: null, pane: 'overview', seq: 0 };
  var BACK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m15 18-6-6 6-6"/></svg>';
  var PANES = [['overview', 'Overview'], ['work', 'Work'], ['documents', 'Documents'], ['performance', 'Performance'], ['health', 'Health']];
  function paneOk(k) {
    if (k === 'work') return may('team', 'manage');
    if (k === 'documents') return may('register.hr', 'view');
    if (k === 'performance') return may('team.performance', 'view');
    if (k === 'health') return Boolean(window.ADspaceAdmin && window.ADspaceAdmin.isAdmin && window.ADspaceAdmin.isAdmin());
    return true;
  }
  (function () {
    var q = new URLSearchParams(location.search);
    rec.id = q.get('member') || null;
    var t = q.get('mtab');
    if (t && PANES.some(function (x) { return x[0] === t; })) rec.pane = t;
  })();
  function recUrl() {
    var o = {};
    if (rec.id) { o.member = rec.id; if (rec.pane !== 'overview') o.mtab = rec.pane; }
    return o;
  }
  function pushUrl() { if (bridge.pushUrl) bridge.pushUrl(); else if (bridge.setUrl) bridge.setUrl(); }
  function openRec(id, pane) {
    rec.id = id; rec.pane = pane || 'overview';
    pushUrl();
    paintRec();
    window.scrollTo(0, 0);
  }
  function closeRec() {
    rec.id = null; rec.pane = 'overview';
    pushUrl();
    paintRec();
  }
  function stateChip(m) {
    if (!m.active) return '<span class="chip-state is-off">' + (m.removed_at ? 'Removed' : m.expired_at ? 'Access expired' : 'Inactive') + '</span>';
    return '<span class="chip-state is-ok">Active</span>';
  }
  function fact(label, value) {
    return '<div><dt>' + esc(label) + '</dt><dd' + (value ? '' : ' class="is-empty"') + '>' + (value ? esc(value) : 'Not set') + '</dd></div>';
  }
  function hoursWord(min) { return min == null ? '' : (Math.round(min / 6) / 10) + ' hours a week'; }
  function paintRec() {
    var box = $('teamRec'), sec = $('sectionTeam');
    if (!box) return;
    var m = rec.id && (state.rows || []).filter(function (x) { return x.id === rec.id; })[0];
    var showing = Boolean(rec.id) && (Boolean(m) || state.loading);
    if (sec) sec.classList.toggle('is-member', showing);
    box.hidden = !showing;
    if (!showing) {
      box.innerHTML = '';
      if (rec.id && !state.loading) { rec.id = null; if (bridge.setUrl) bridge.setUrl(); msg('teamMsg', 'That colleague is no longer on the team.', 'warn'); }
      return;
    }
    if (!m) { box.innerHTML = '<div class="softpanel"><div class="skel"><div class="skel-row"></div><div class="skel-row"></div></div></div>'; return; }
    if (!paneOk(rec.pane)) rec.pane = 'overview';
    var panes = PANES.filter(function (x) { return paneOk(x[0]); });
    var menu = memberMenu(m);
    var meta = [m.staff_code, roleName(m.role), whoLine(m)].filter(Boolean).join(' · ');
    var self = me() && me().id === m.id;
    box.innerHTML =
      '<div class="mrec-back"><button class="btn btn-quiet btn-sm" type="button" data-r="back">' + BACK + 'Team</button></div>' +
      '<section class="panel rec-head mrec-head"><div class="rec-id">' +
        '<span class="rec-mark" aria-hidden="true">' + esc(window.ADspaceState.initials(m.name || '')) + '</span>' +
        '<div class="rec-who"><div class="rec-name"><h2>' + esc(m.name || '') + '</h2>' +
          (self ? ' <span class="tone">You</span>' : '') + (m.system ? ' <span class="tone">System</span>' : '') + '</div>' +
          '<p class="rec-id-meta">' + esc(meta) + '</p></div>' +
        '<div class="rec-ctl">' + stateChip(m) + (menu ? menuBtn(menu) : '') + '</div>' +
      '</div></section>' +
      (panes.length > 1 ? '<nav class="rectabs mrec-tabs" role="tablist" aria-label="Colleague">' + panes.map(function (x) {
        var on = x[0] === rec.pane;
        return '<button class="tab' + (on ? ' is-on' : '') + '" type="button" role="tab" aria-selected="' + on + '" data-pane="' + x[0] + '">' + esc(x[1]) + '</button>';
      }).join('') + '</nav>' : '') +
      '<div class="msg" id="mrecMsg"></div>' +
      '<div class="mrec-pane" id="mrecPane" data-narrow="640"></div>';
    var head = box.querySelector('.rec-ctl');
    wireActs(head, m);
    box.querySelector('[data-r="back"]').addEventListener('click', closeRec);
    Array.prototype.forEach.call(box.querySelectorAll('.mrec-tabs .tab'), function (b) {
      b.addEventListener('click', function () {
        if (b.getAttribute('data-pane') === rec.pane) return;
        rec.pane = b.getAttribute('data-pane');
        pushUrl();
        paintRec();
      });
    });
    if (window.ADspaceForm && window.ADspaceForm.thumb) {
      var strip = box.querySelector('.mrec-tabs');
      if (strip) window.ADspaceForm.thumb(strip);
    }
    if (window.ADspaceState && window.ADspaceState.fit) window.ADspaceState.fit();
    paintPane(m);
  }
  function paintPane(m) {
    var host = $('mrecPane'), seq = ++rec.seq;
    var live = function () { return seq === rec.seq && $('mrecPane') === host; };
    if (rec.pane === 'work') return paneWork(m, host, live);
    if (rec.pane === 'documents') return paneDocs(m, host, live);
    if (rec.pane === 'performance') return panePerf(m, host);
    if (rec.pane === 'health') return paneHealth(m, host, live);
    paneOverview(m, host);
  }
  function group(title, inner, act) {
    return '<section class="readgroup"><div class="readgroup-head"><h4 class="fsec-h">' + esc(title) + '</h4>' + (act || '') + '</div>' + inner + '</section>';
  }
  /* Overview is changed where it is read (the user, 2026-10-18: "why you
     wouldnt just let it edit on each fields"): a word or a date is its pen
     (ADspaceAsk.rename), a choice a select drawn as the value; each saved on
     its own through `patchMember`, filed from and to, put back on a
     refusal. Nobody changes their own access date (`own-expiry`). */
  var PEN_SVG = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>';
  var MEMBER_LOG = [
    ['name', 'Name'], ['email', 'Email'], ['role', 'User group', function (v) { return roleName(v); }], ['staff_code', 'Employee ID'],
    ['designation', 'Position'], ['department', 'Department', function (v) { return DEPT[v] || v; }],
    ['role_family', 'Role standard', function (v) { return ROLE_STD[v] || v; }],
    ['capacity_minutes_week', 'Weekly capacity', function (v) { return Math.round(Number(v) / 60) + 'h'; }],
    ['access_until', 'Access until', dayWord], ['access_until_time', 'Access time', timeWord],
    ['mobile', 'Mobile'], ['card_mobile', 'Mobile on card', function (v) { return off(v) ? 'Hide' : 'Show'; }],
    ['card_on', 'Namecard', function (v) { return off(v) ? 'Off' : 'On'; }],
    ['card_slug', 'Short link']];
  function patchMember(m, fields, back) {
    var write = function () {
      asRead(db.from('team_members').update(fields).eq('id', m.id), m).select('id').then(function (r) {
        if (!r.error && !(r.data || []).length) {
          noRow('team_members', 'id', m, function (t) {
            back(false);
            if (t === STALE) load(function () { msg('mrecMsg', t, 'err'); }); else msg('mrecMsg', t, 'err');
          });
          return;
        }
        if (r.error) {
          msg('mrecMsg', clashSaid(r.error), 'err');
          back(false); return;
        }
        var filed = fields.card_slug === null ? Object.assign({}, fields, { card_slug: m.card_slug }) : fields;
        var moved = window.ADspaceRecords.changes(m, filed, MEMBER_LOG);
        var name = fields.name || m.name;
        if (moved) log('team.edited', name, moved);
        if (fields.name && fields.name !== String(m.name || '').trim()) {
          ownedBy(m.name, true, function (own) {
            if (own.clients.length + own.campaigns.length) handOver(m.name, fields.name, own, [
              own.clients.length ? plural(own.clients.length, 'client', 'clients') : '',
              own.campaigns.length ? plural(own.campaigns.length, 'campaign', 'campaigns') : ''
            ].filter(Boolean).join(' and ').replace(/^./, function (x) { return x.toUpperCase(); }));
          });
        }
        back(true);
        /* Said after the repaint, which empties the line (2026-10-20, TEAM-3). */
        load(function () { msg('mrecMsg', 'Saved.', 'ok'); });
      }).catch(function () { msg('mrecMsg', 'Not saved. Please try again.', 'err'); back(false); });
    };
    if (fields.email != null && fields.email !== String(m.email || '').toLowerCase()) {
      /* The value goes back until the question is answered: Cancel leaves it. */
      back(false);
      window.ADspaceConfirm.ask({
        title: 'Change the sign-in address',
        body: m.name + ' signs in with ' + fields.email + ' from now on. The login itself '
            + 'stays at the old address until they are invited at the new one.',
        go: 'Change address', tone: 'warn'
      }, function () { back = function () {}; write(); });
      return;
    }
    write();
  }
  /* What a typed value must be, in the sheet's own words; null when fine. */
  function badValue(k, v) {
    if (k === 'name' && !v) return 'A name is required.';
    if (k === 'email' && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v)) return 'A valid email is required.';
    if (k === 'staff_code' && v && !/^[A-Z0-9]{3,8}$/.test(v)) return 'An Employee ID is 3 to 8 letters or digits.';
    if (k === 'capacity_minutes_week' && v !== '' && !(parseFloat(v) >= 0 && parseFloat(v) <= 80)) return 'Weekly capacity is 0 to 80 hours.';
    if (k === 'mobile' && v) { var n = v.replace(/\D/g, '').length; if (n < 8 || n > 15) return 'Enter a mobile number of 8 to 15 digits.'; }
    if (k === 'card_slug' && v && !/^[a-z0-9][a-z0-9._-]{2,79}$/.test(v)) return 'Use at least three characters: lowercase letters, digits, dots, dashes or underscores.';
    if (k === 'access_until' && v && v < todayMy()) return 'Choose today or a later date.';
    return null;
  }
  function paneOverview(m, host) {
    var self = me() && me().id === m.id;
    var edit = may('team', 'manage') && !(m.system && !self) && !m.removed_at;
    var link = m.card_slug && window.ADSPACE_CONFIG && window.ADSPACE_CONFIG.linkHost ? window.ADSPACE_CONFIG.linkHost.replace(/^https?:\/\//, '') + '/' + m.card_slug : (m.card_slug || '');
    /* A word: the value, its pen at the facts' right edge. */
    var word = function (k, label, shown, can) {
      var on = edit && can !== false;
      return '<div><dt>' + esc(label) + '</dt><dd class="mfield' + (shown ? '' : ' is-empty') + '"><span class="mval" data-k="' + k + '">' +
        esc(shown || 'Not set') + '</span>' +
        (on ? '<button class="tl-pen" type="button" data-pen="' + k + '" aria-label="Edit ' + esc(label.toLowerCase()) + '">' + PEN_SVG + '</button>' : '') + '</dd></div>';
    };
    /* A choice: a select drawn as the value. */
    var pick = function (k, label, opts, value, shown) {
      if (!edit) return fact(label, shown);
      return '<div><dt>' + esc(label) + '</dt><dd class="mfield"><select class="select select-sm tdetail" data-sel="' + k + '" aria-label="' + esc(label) + '">' +
        opts.map(function (o) { return '<option value="' + esc(o[0]) + '"' + (String(value == null ? '' : value) === o[0] ? ' selected' : '') + '>' + esc(o[1]) + '</option>'; }).join('') +
        '</select></dd></div>';
    };
    var map = function (o, none) { return [['', none || 'Not set']].concat(Object.keys(o).map(function (k) { return [k, o[k]]; })); };
    var roles = state.roles.map(function (r) { return [r.slug, r.name]; });
    host.innerHTML = '<div class="panel mrec-card mrec-ov"><div class="readgroups">' +
      group('Sign-in and access', '<dl class="ovfacts">' +
        word('name', 'Name', m.name) + word('email', 'Sign-in email', m.email, amAdmin()) +
        (edit && !(m.system) ? pick('role', 'User group', roles, m.role, roleName(m.role)) : fact('User group', roleName(m.role))) +
        word('access_until', 'Access until', m.access_until ? untilWord(m.access_until, m.access_until_time) : 'No end', !self) + '</dl>') +
      group('Employment', '<dl class="ovfacts">' +
        word('staff_code', 'Employee ID', m.staff_code) +
        pick('department', 'Department', map(DEPT), m.department || '', DEPT[m.department]) +
        word('designation', 'Position', m.designation) +
        pick('role_family', 'Role standard', map(ROLE_STD), m.role_family || '', ROLE_STD[m.role_family]) +
        word('capacity_minutes_week', 'Weekly capacity', hoursWord(m.capacity_minutes_week)) + '</dl>') +
      group('Namecard', '<dl class="ovfacts">' +
        word('mobile', 'Mobile', m.mobile ? (window.ADspaceCard && window.ADspaceCard.phone ? window.ADspaceCard.phone(m.mobile) : m.mobile) : '') +
        pick('card_mobile', 'Mobile on card', [['show', 'Show'], ['hide', 'Hide']], m.card_mobile === false ? 'hide' : 'show', m.card_mobile === false ? 'Hide' : 'Show') +
        word('card_slug', 'Short link', link) +
        pick('card_on', 'Card', [['on', 'On'], ['off', 'Off']], m.card_on === false ? 'off' : 'on', m.card_on === false ? 'Off' : 'On') + '</dl>') +
      '</div></div>';
    Array.prototype.forEach.call(host.querySelectorAll('[data-pen]'), function (pen) {
      var k = pen.getAttribute('data-pen'), val = host.querySelector('.mval[data-k="' + k + '"]');
      var norm = function (v) {
        v = String(v == null ? '' : v).trim();
        if (k === 'staff_code') v = v.toUpperCase();
        if (k === 'email' || k === 'card_slug') v = v.toLowerCase();
        if (k === 'card_slug') v = v.replace(/^https?:\/\/[^/]*\//, '').replace(/^\/+|\/+$/g, '');
        return v;
      };
      pen.addEventListener('click', function () {
        var raw = k === 'capacity_minutes_week' ? (m[k] == null ? '' : String(Math.round(m[k] / 6) / 10))
          : k === 'access_until' ? (m.access_until || '') : String(m[k] == null ? '' : m[k]);
        val.textContent = raw;
        window.ADspaceAsk.rename(val, pen, {
          value: raw, type: k === 'access_until' ? 'date' : k === 'capacity_minutes_week' ? 'number' : 'text',
          code: k === 'staff_code', label: pen.getAttribute('aria-label').replace(/^Edit /, ''),
          allowEmpty: ['name', 'email'].indexOf(k) < 0,
          /* A value refused keeps its field open, the refusal under it
             (2026-10-20, TEAM-4). */
          check: function (v) { return badValue(k, norm(v)) || ''; },
          save: function (v) {
            v = norm(v);
            var f = {};
            if (k === 'capacity_minutes_week') f[k] = v === '' ? null : Math.round(parseFloat(v) * 60);
            else if (k === 'access_until') { f.access_until = v || null; if (!v) f.access_until_time = null; }
            else f[k] = v || null;
            if (String(f[k] == null ? '' : f[k]) === String(m[k] == null ? '' : m[k])) { paneOverview(m, host); return; }
            patchMember(m, f, function (ok) { if (!ok) paneOverview(m, host); });
          }
        });
      });
    });
    Array.prototype.forEach.call(host.querySelectorAll('select[data-sel]'), function (sel) {
      var was = sel.value;
      sel.addEventListener('change', function () {
        var k = sel.getAttribute('data-sel'), f = {};
        if (k === 'card_mobile') f[k] = sel.value !== 'hide';
        else if (k === 'card_on') f[k] = sel.value !== 'off';
        else f[k] = sel.value || null;
        patchMember(m, f, function (ok) { if (!ok) sel.value = was; else was = sel.value; });
      });
    });
  }
  /* What the colleague holds now, kind by kind, with Hand over (Team Full
     Access): the same reads and the same sheet Set inactive and Delete use. */
  /* Their work as the work itself (the user, 2026-10-18: "the tasks just
     shown its total number"): each open task they own, each client they are
     person in charge of and each open campaign they run, a row a record
     opening it, the latest due first and an overdue one in red. What is not
     a record of its own here (months, meetings, repeats, reviews, extension
     requests, templates) is counted in one line under them. Hand over sits
     at the head. */
  function openTasksOf(m, then) {
    if (!may('ops', 'view')) { then(null); return; }
    db.from('ops_task_assignees').select('task_id').eq('team_member_id', m.id).eq('responsibility', 'owner').is('ended_at', null)
      .then(function (r) {
        if (r.error) { then(null, r.error); return; }
        var ids = (r.data || []).map(function (x) { return x.task_id; });
        if (!ids.length) { then([]); return; }
        return db.from('ops_tasks').select('id, task_no, code, title, content_desc, current_final_due_at, client_id, clients(name)')
          .in('id', ids).is('completed_at', null).is('cancelled_at', null).is('archived_at', null)
          .then(function (t) { if (t.error) then(null, t.error); else then(t.data || []); });
      }).catch(function (e) { then(null, e); });
  }
  var STAGE_WORD = window.ADspaceWords.en.stage, CAMP_WORD = window.ADspaceWords.en.campState;
  var CHEV = '<svg class="crm-c-go" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 18l6-6-6-6"/></svg>';
  function workRow(i, name, meta, end, late) {
    return '<button class="mrec-row" type="button" data-w="' + i + '"><span class="mrec-row-who"><b>' + esc(name) + '</b>' +
      (meta ? '<small>' + esc(meta) + '</small>' : '') + '</span>' +
      '<span class="mrec-row-end' + (late ? ' is-late' : '') + '">' + esc(end || '') + '</span>' + CHEV + '</button>';
  }
  /* As search opens a record: the address written first, then the section. */
  function goTo(url, section) {
    history.replaceState(null, '', url);
    if (bridge.show) bridge.show(section);
  }
  function paneWork(m, host, live) {
    UI().skeleton(host, 3);
    heldBy(m, function (own, held) {
      if (!live()) return;
      openTasksOf(m, function (tasks, err) {
        if (!live()) return;
        var today = window.ADspaceClock.today();
        var opens = [], html = '';
        var self = me() && me().id === m.id;
        var anyHeld = own.clients.length || own.campaigns.length || HELD_KINDS.some(function (k) { return Number(held[k[0]] || 0) > 0; });
        var act = anyHeld && !self && !m.system && may('team', 'manage') ? '<button class="btn btn-sm" type="button" data-r="hand">Hand over</button>' : '';
        /* A long list shows its first rows and the rest behind Show all
           (the user, 2026-10-18: "imaging u need to fit in 100+ tasks"). */
        var FIRST = 10;
        var section = function (title, rows, act2, lead) {
          var more = rows.length > FIRST + 2;
          return group(title, (lead || '') + '<div class="mrec-rows">' + (more ? rows.slice(0, FIRST) : rows).join('') +
            (more ? '<div class="mrec-rest" hidden>' + rows.slice(FIRST).join('') + '</div>' : '') + '</div>' +
            (more ? '<button class="btn btn-sm mrec-all" type="button" data-all>Show all ' + rows.length + '</button>' : ''), act2);
        };
        if (tasks === null && err) {
          html += group('Open tasks', '<p class="msg err">Could not load their tasks.</p>', act); act = '';
        } else if (tasks && tasks.length) {
          var day = function (t) { return t.current_final_due_at ? window.ADspaceClock.day(t.current_final_due_at) : ''; };
          tasks.sort(function (x, y) {
            var a = day(x) || '9999', b2 = day(y) || '9999';
            return a < b2 ? -1 : a > b2 ? 1 : (x.task_no || 0) - (y.task_no || 0);
          });
          var wk = window.ADspaceClock.addDays(today, 7);
          var cnt = { late: 0, week: 0, later: 0, none: 0 };
          tasks.forEach(function (t) { var d = day(t); cnt[!d ? 'none' : d < today ? 'late' : d <= wk ? 'week' : 'later']++; });
          var lead = '<p class="mrec-sum">' + [cnt.late ? '<span class="is-late">' + cnt.late + ' overdue</span>' : '',
            cnt.week ? cnt.week + ' due within 7 days' : '', cnt.later ? cnt.later + ' later' : '', cnt.none ? cnt.none + ' with no due date' : '']
            .filter(Boolean).join(' · ') + '</p>';
          html += section('Open tasks · ' + tasks.length, tasks.map(function (t) {
            opens.push(function () { goTo('/admin/?s=work&open=' + encodeURIComponent(t.id), 'work'); });
            var d = day(t), late = d && d < today;
            var meta = [(t.clients && t.clients.name) || (t.client_id ? '' : 'Internal'), t.code || '', t.task_no ? '#WT' + String(t.task_no).padStart(5, '0') : '']
              .filter(Boolean).join(' · ');
            return workRow(opens.length - 1, t.content_desc || t.title || 'Untitled task', meta,
              d ? (late ? 'Overdue · ' : '') + window.ADspaceClock.date(d) : 'No due date', late);
          }), act, lead);
          act = '';
        }
        if (own.clients.length) {
          html += section('Clients they are person in charge of · ' + own.clients.length, own.clients.slice().sort(function (x, y) {
            return String(x.name || '').localeCompare(String(y.name || ''));
          }).map(function (c) {
            opens.push(function () { goTo('/admin/?client=' + encodeURIComponent(c.slug || c.id), 'clients'); });
            return workRow(opens.length - 1, c.name || '', c.client_code || '', STAGE_WORD[c.stage] || '', false);
          }), act);
          act = '';
        }
        if (own.campaigns.length) {
          html += section('Open campaigns they run · ' + own.campaigns.length, own.campaigns.map(function (c) {
            opens.push(function () { goTo('/admin/?s=campaigns&campaign=' + encodeURIComponent(c.id), 'campaigns'); });
            return workRow(opens.length - 1, c.title || 'Untitled campaign', '', CAMP_WORD[c.state] || '', false);
          }), act);
          act = '';
        }
        /* Tasks are listed above once they could be read; else counted here. */
        var rest = HELD_KINDS.filter(function (k) { return k[0] !== 'tasks' || tasks === null; })
          .map(function (k) { return [k[1], Number(held[k[0]] || 0)]; }).filter(function (x) { return x[1] > 0; });
        if (rest.length) {
          html += group('Also held', '<dl class="ovfacts">' + rest.map(function (x) {
            return '<div><dt>' + esc(x[0]) + '</dt><dd>' + esc(String(x[1])) + '</dd></div>';
          }).join('') + '</dl>', act);
          act = '';
        }
        if (!html) html = group('Their work', '<p class="muted">Nothing is assigned to ' + esc(m.name) + '.</p>');
        host.innerHTML = '<div class="panel mrec-card"><div class="readgroups">' + html + '</div></div>';
        Array.prototype.forEach.call(host.querySelectorAll('[data-all]'), function (b) {
          b.addEventListener('click', function () {
            var rest = b.parentNode.querySelector('.mrec-rest');
            if (rest) rest.hidden = false;
            b.remove();
          });
        });
        Array.prototype.forEach.call(host.querySelectorAll('[data-w]'), function (b) {
          b.addEventListener('click', function () { opens[Number(b.getAttribute('data-w'))](); });
        });
        var h = host.querySelector('[data-r="hand"]');
        if (h) h.addEventListener('click', function () {
          var fields = handFields(m, own, held);
          window.ADspaceConfirm.ask({
            title: 'Hand over work', go: 'Hand over',
            body: 'Choose who takes each kind of ' + m.name + '\'s work.',
            fields: fields
          }, function (v) {
            v = v && typeof v === 'object' ? v : {};
            msg('teamMsg', '');
            Promise.resolve(handTo(m, own, v)).then(function () { if (rec.id === m.id && rec.pane === 'work') paintPane(m); });
          });
        });
      });
    });
  }
  /* Their HR letters (HR Letters at View), newest first: a letter the portal
     issued opens as its PDF, one added by hand its file link; Issue document
     and Add entry open on this colleague. */
  function paneDocs(m, host, live) {
    var R = window.ADspaceRegister;
    var work = may('register.hr', 'work') && R;
    var act = work ? '<span class="mrec-acts"><button class="btn btn-sm" type="button" data-r="add">Add existing document</button>' +
      '<button class="btn btn-sm" type="button" data-r="issue">Issue document</button></span>' : '';
    host.innerHTML = '<div class="panel mrec-card"><div class="readgroups">' + group('HR letters', '<div id="mrecDocs"></div>', act) + '</div></div>';
    var box = host.querySelector('#mrecDocs');
    UI().skeleton(box, 2);
    var again = function () { if (rec.id === m.id && rec.pane === 'documents') paintPane(m); };
    if (R && R.paintForMember) R.paintForMember(m, box, function (rows, err) {
      if (!live()) return;
      var sk = box.querySelector('.skel'); if (sk && sk.parentNode) sk.parentNode.remove();
      if (err) { UI().failLine(box, 'their letters', (err && err.message) || '', function () { paneDocs(m, host, live); }); return; }
      if (!rows.length) box.innerHTML = '<p class="muted">No letters.</p>';
    });
    var is = host.querySelector('[data-r="issue"]');
    if (is) is.addEventListener('click', function () {
      R.openIssue({ member: m, families: ['hr'], msg: 'mrecMsg', onDone: again });
    });
    var ad = host.querySelector('[data-r="add"]');
    if (ad) ad.addEventListener('click', function () {
      R.openAdd({ member: m, msg: 'mrecMsg', onDone: again });
    });
  }
  /* Reviews sit behind Performance's own lock, so the record opens them
     there, the list searched for this colleague. */
  function panePerf(m, host) {
    host.innerHTML = '<div class="panel mrec-card"><div class="readgroups">' + group('Monthly reviews',
      '<p class="muted">Reviews open in Performance, behind its master code.</p>',
      '<button class="btn btn-sm" type="button" data-r="perf">Open reviews</button>') + '</div></div>';
    host.querySelector('[data-r="perf"]').addEventListener('click', function () {
      if (window.ADspacePerf && window.ADspacePerf.openFor) window.ADspacePerf.openFor(m.name || '');
    });
  }
  function paneHealth(m, host, live) {
    if (!window.ADspaceHealth || !window.ADspaceHealth.paintPerson) { host.innerHTML = ''; return; }
    host.innerHTML = '<div class="panel mrec-card"><div id="mrecHealth"></div></div>';
    window.ADspaceHealth.paintPerson(m.id, $('mrecHealth'), live);
  }
  function UI() { return window.ADspaceState; }
  window.addEventListener('popstate', function () {
    var sec = $('sectionTeam');
    if (!sec || sec.hidden || !state.rows) return;
    window.ADspaceTeam.fromUrl();
  });

  window.ADspaceTeam = {
    urlState: function () { return recUrl(); },
    enter: function () { load(); },
    /* Leaves a record without touching the address (Performance writes it). */
    close: function () { rec.id = null; rec.pane = 'overview'; paintRec(); },
    /* Back and Forward on a colleague's record. */
    fromUrl: function () {
      var q = new URLSearchParams(location.search), id = q.get('member') || null, t = q.get('mtab') || 'overview';
      if (id === rec.id && t === rec.pane) return;
      rec.id = id; rec.pane = PANES.some(function (x) { return x[0] === t; }) ? t : 'overview';
      /* Before the colleagues are read (search opening a record from
         another section) the read paints it; painting now would find no
         row and let go of it. */
      if (!state.read && !state.loading) return;
      paintRec();
    },
    /* Opens one colleague's sheet, for the review profile's Edit on Members:
       from the rows already read, or once the list has been. */
    edit: function (id) { pendingEdit = id; if (!state.loading) openPending(); }
  };
  if (bridge.teamReady) bridge.teamReady();
})();
