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
  var log = bridge.log || function () {};
  var me = bridge.me || function () { return null; };

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
  var LEVELS = [
    ['none',   'No access'],
    ['view',   'View'],
    ['work',   'Work'],
    ['manage', 'Manage']
  ];
  var LEVEL_WORD = { view: 'View', work: 'Work', manage: 'Manage' };

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
    ['campaigns', 'Creator Campaigns', ['none', 'view', 'work', 'manage']],
    /* The documents issued and the serials the verify page answers; HR
       letters are a part of it, gated apart, because a colleague's letter is
       read by fewer people than a client's. Named as the nav names it: the
       ladder's key stays `register`, which is an address and not copy, but a
       panel granting "Register" while the rail read Documents made somebody
       check twice which one they had. */
    ['register',  'Documents',         ['none', 'view', 'work', 'manage']],
    /* Client reports are prepared here and published to the client portal.
       Their own section (2026-09-25), so a colleague can prepare reports
       without reading client records; Clients View still reads a client's
       finished reports on the record. */
    ['reports',   'Reports',           ['none', 'view', 'work', 'manage']],
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
                ['documents', 'Documents'], ['requests', 'Requests'], ['calls', 'Calls and visits']],
    review:    [['sets', 'Content sets'], ['settings', 'Client settings']],
    campaigns: [['campaigns', 'Campaigns'], ['creators', 'Creators List'], ['finance', 'Finance']],
    register:  [['documents', 'Client documents'], ['hr', 'HR Letters']],
    /* The record is already read a section at a time — the tab strip is its
       own — and its access was one switch over all of them, so opening the
       campaigns log to the team opened every client's billing change and
       every letter with it. Each tab is a part, and the database decides
       which rows arrive: `activity_section()` maps a tag to the section the
       console files it under, and the read policy asks the part. */
    activity:  [['ops', 'My Work'], ['clients', 'Clients'],
                ['review', 'Content Review'], ['campaigns', 'Creator Campaigns'],
                ['register', 'Documents'], ['links', 'Short Links'],
                ['services', 'Services'], ['team', 'Team']],
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
                ['workflows', 'Templates and recurring tasks'], ['time', 'Another person\'s time records']],
    /* Everybody's monthly performance review: View reads them, Work scores,
       releases and answers disputes, Manage also reopens a final record.
       Granted like the four above, because administering the team is not
       reading its scores, and the master code is asked for on top. */
    team:      [['performance', 'Performance reviews']]
  };
  /* The parts that are granted rather than inherited: each opens more than
     its section does, so silence means no. The same list the console reads
     (`OPS_GRANTED` in js/admin.js) and the database asks (`ops_granted()`). */
  var GRANTED = { 'ops.all': 1, 'ops.reports': 1, 'ops.workflows': 1, 'ops.time': 1, 'team.performance': 1 };
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
    'ops.time': ['manage'], 'team.performance': ['view', 'work', 'manage']
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

  function load() {
    $('teamList').innerHTML = '<div class="softpanel"><div class="skel">' +
      '<div class="skel-row"></div><div class="skel-row"></div><div class="skel-row"></div>' +
      '<div class="skel-row"></div></div></div>';
    db.from('team_roles').select('*').order('position').order('name').then(function (r) {
      if (r.error) {
        $('groupList').innerHTML = '<div class="softpanel"><div class="errline">' +
          '<b>Could not load the groups.</b><span>' + esc(r.error.message) + '</span></div></div>';
        return;
      }
      state.roles = r.data || [];
      paintGroups();
      fillRolePick();
      fillGroupPick();
      db.from('team_members').select('*').order('active', { ascending: false })
        .order('role').order('name').then(function (q) {
          if (q.error) {
            $('teamList').innerHTML = '<div class="softpanel"><div class="errline">' +
              '<b>Could not load the team.</b><span>' + esc(q.error.message) + '</span></div></div>';
            return;
          }
          state.rows = q.data || [];
          paintMembers();
          paintGroups();   // member counts and Delete depend on the rows
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
  var teamFind = '', teamGroup = '';

  function fillGroupPick() {
    var sel = $('teamGroupPick');
    if (!sel) return;
    sel.innerHTML = '<option value="">Every group</option>' + state.roles.map(function (r) {
      return '<option value="' + esc(r.slug) + '">' + esc(r.name) + '</option>';
    }).join('');
    sel.value = teamGroup;
  }
  function teamMatch(m) {
    if (teamGroup && m.role !== teamGroup) return false;
    if (!teamFind) return true;
    return (String(m.name || '') + ' ' + String(m.email || '') + ' ' + String(m.staff_code || ''))
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
      box.innerHTML = '<div class="softpanel"><div class="emptyline"><b>Nobody on the team yet.</b>' +
        '<button class="btn btn-sm" data-a="first" type="button">Add the first member</button></div></div>';
      box.querySelector('[data-a="first"]').addEventListener('click', function () { openMemberBox(null, this); });
      return;
    }
    if (!rows.length) {
      box.innerHTML = '<div class="softpanel"><div class="emptyline"><b>No matches.</b>' +
        '<button class="btn btn-sm" data-a="clear" type="button">Clear the filters</button></div></div>';
      box.querySelector('[data-a="clear"]').addEventListener('click', function () {
        teamFind = ''; teamGroup = '';
        if ($('teamFind')) $('teamFind').value = '';
        if ($('teamGroupPick')) $('teamGroupPick').value = '';
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
  if ($('teamGroupPick')) $('teamGroupPick').addEventListener('change', function () {
    teamGroup = this.value; paintMembers();
  });
  function byName(a) {
    return a.slice().sort(function (x, y) {
      if (Boolean(x.active) !== Boolean(y.active)) return x.active ? -1 : 1;
      return String(x.name || '').localeCompare(String(y.name || ''));
    });
  }
  function memberRow(m) {
    var self = me() && me().id === m.id;
    var el = document.createElement('div');
    el.className = 'team-row' + (m.active ? '' : ' is-off');
    el.innerHTML =
      /* Everyone on this list is active, so a green Active on every row spends
         the one accent on the ordinary case and leaves the exception looking
         like everything else. The row says nothing when a person is working
         and names it when they are not. */
      /* You is a designation, not a live state, so it is the neutral chip the
         rate card gives Inactive and not a word in the accent green. */
      '<span class="team-who"><b>' + esc(m.name) + (self ? ' <span class="tone">You</span>' : '') + '</b>' +
        /* The Employee ID and the designation are read off the row because
           the HR serial and the signature on a letter are built from them. */
        (m.staff_code || m.designation
          ? '<small>' + esc([m.staff_code, m.designation].filter(Boolean).join(' · ')) + '</small>' : '') +
      '</span>' +
      '<span class="team-mail">' + esc(m.email || '') + '</span>' +
      '<span class="team-state">' + (m.active ? '' : '<span class="tone">Inactive</span>') + '</span>' +
      /* Mail leaves the building and cannot be recalled, so Send invitation
         sits one place from Edit and asks first, as it does on a contact.
         Standing somebody down happens once in a job, so it is here rather
         than a select on every row. A person cannot switch themselves off. */
      menuBtn(menuItem('edit', 'Edit') +
              (m.active && m.email ? menuItem('invite', 'Send invitation') : '') +
              (self ? '' : menuItem('state', m.active ? 'Set inactive' : 'Set active')));

    wireMenu(el);
    var st = el.querySelector('[data-a="state"]');
    if (st) st.addEventListener('click', function () {
      shutMenus();
      /* Setting somebody active again asks nothing: it is the way back from
         this, and the way back never asks. */
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
            choices: [['', 'Keep with ' + m.name]].concat(byName(others).map(function (x) { return [x.name, x.name]; }))
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
    db.from('team_members').update(patch).eq('id', m.id).then(function (r) {
      if (r.error) { msg('teamMsg', r.error.message, 'err'); load(); return; }
      log('team.changed', m.name, Object.keys(patch).map(function (k) {
        return k + '=' + (k === 'role' ? roleName(patch[k]) : patch[k]);
      }).join(', '));
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
  }

  /* What the group opens, in its own words, grouped by level so the strongest
     reads first. An admin group opens everything, and listing every section it
     can reach is a longer way of saying so. A column per switch was tried and
     removed: it is a table that grows every time the product does. */
  function grantWord(r) {
    if (r.is_admin) return 'Everything';
    var acc = accessOf(r), parts = [];
    /* A section's exceptions read in brackets after its name
       (`Clients (Billing: No access)`), so the sentence still says what the
       group opens and then what it does not. */
    var word = function (s) {
      var ex = (PARTS[s[0]] || []).map(function (p) {
        var v = offered(s[0] + '.' + p[0], exceptionOf(acc, s[0] + '.' + p[0]));
        return v ? p[1] + ': ' + (LEVEL_WORD[v] || 'No access') : '';
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
    return parts.length ? parts.join(' · ') : 'No access';
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
      (locked ? '<span class="team-act"></span>'
        : menuBtn(menuItem('rename', 'Edit') + (used ? '' : menuItem('del', 'Delete', 'is-danger'))));

    wireMenu(el);
    var ren = el.querySelector('[data-a="rename"]');
    if (ren) ren.addEventListener('click', function () { openGroupBox(r, this); });
    var del = el.querySelector('[data-a="del"]');
    if (del) del.addEventListener('click', function () {
      window.ADspaceConfirm.ask({
        title: 'Delete',
        body: 'The ' + r.name + ' group and the access it carries go. There is no '
            + 'restore. Anybody still in it falls under "No group" and opens nothing '
            + 'until they are moved.',
        go: 'Delete',
        tone: 'danger'
      }, function () {
        db.from('team_roles').delete().eq('slug', r.slug).then(function (q) {
          if (q.error) { msg('groupMsg', q.error.message, 'err'); return; }
          log('team.group_removed', r.name, '');
          msg('groupMsg', r.name + ' deleted.', 'ok');
          load();
        });
      });
    });
    return el;
  }

  function saveGroup(r, patch) {
    db.from('team_roles').update(patch).eq('slug', r.slug).then(function (q) {
      if (q.error) { msg('groupMsg', q.error.message, 'err'); load(); return; }
      Object.keys(patch).forEach(function (k) { r[k] = patch[k]; });
      log('team.group_changed', r.name, Object.keys(patch).map(function (k) {
        if (k === 'access') return grantWord({ access: patch.access });
        return k.replace('can_', '') + '=' + patch[k];
      }).join(', '));
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
           work: 'Also create tasks and bulk add a month.', manage: 'Also assign task owners and delete tasks.' },
    clients: { none: 'Clients is hidden.', view: 'Read client records.',
               work: 'Add leads, edit records, log calls and issue letters.', manage: 'Also delete clients and void letters.' },
    review: { none: 'Content Review is hidden.', view: 'Read content sets and posts.',
              work: 'Add sets and posts, import from Drive and publish.', manage: 'Also delete content sets.' },
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
    manager: { ops: 'manage', clients: 'manage', review: 'manage', campaigns: 'manage', register: 'manage', reports: 'manage',
               links: 'manage', services: 'manage', team: 'none', activity: 'view',
               'ops.all': 'view', 'ops.reports': 'view', 'ops.workflows': 'work', 'ops.time': 'manage',
               'register.hr': 'none' },
    staff:   { ops: 'work', clients: 'work', review: 'work', campaigns: 'work', register: 'view', reports: 'work',
               links: 'work', services: 'view', team: 'none', activity: 'none', 'register.hr': 'none' },
    viewer:  { ops: 'view', clients: 'view', review: 'view', campaigns: 'view', register: 'view', reports: 'view',
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
            (granted ? '<option value="">No access</option>'
                     : '<option value="">Same as section</option><option value="none">No access</option>') +
            /* A My Work view follows its section and has two states. */
            (VIEW_PARTS[key] ? '' :
              partLevels(key).map(function (l) { return '<option value="' + l + '">' + esc(LEVEL_WORD[l]) + '</option>'; }).join('')) +
            '</select></label>';
        }).join('') + '</div>' : '') +
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
  /* The group in one sentence, read from the panel as it stands. */
  function sumText(acc, admin, tuned) {
    if (admin) return 'This group can do everything, in every section.';
    var by = { manage: [], work: [], view: [] };
    SECTIONS.forEach(function (s) { var v = acc[s[0]] || 'none'; if (by[v]) by[v].push(s[1]); });
    var said = ['manage', 'work', 'view'].filter(function (lv) { return by[lv].length; }).map(function (lv) {
      return lv + ' ' + listWords(by[lv]);
    });
    var line = said.length ? 'This group can ' + listWords(said, ', and ') + '.' : 'This group has no access.';
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
      var n = (PARTS[s[0]] || []).filter(function (p) { return (s[0] + '.' + p[0]) in access; }).length;
      tuned += n;
      var box = $('grFlags').querySelector('[data-n="' + s[0] + '"]');
      if (box) box.textContent = n ? '(' + n + ')' : '';
    });
    /* An admin opens everything, so the levels under it decide nothing and
       are not offered for change while the tick is on. */
    levelPicks().concat(partPicks()).forEach(function (sel) { sel.disabled = locked || admin; });
    $('grPreset').value = presetOf();
    $('grPreset').disabled = locked;
    $('grPresetNote').hidden = $('grPreset').value !== 'custom';
    $('grSum').textContent = sumText(access, admin, tuned);
  }
  function applyPreset(k) {
    flagBoxes().forEach(function (cb) { if (cb.getAttribute('data-f') === 'is_admin') cb.checked = k === 'admin'; });
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
      shutGroupBox();
      if (Object.keys(patch).length) saveGroup(r, patch);
      return;
    }
    var slug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
    if (!slug) { msg('grMsg', 'Use letters or numbers in the name.', 'err'); return; }
    if (state.roles.some(function (r) { return r.slug === slug; })) { msg('grMsg', 'That group already exists.', 'err'); return; }
    var row = { slug: slug, name: name, position: state.roles.length, access: access };
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
    $('tmCap').value = m && m.capacity_minutes_week ? String(Math.round(m.capacity_minutes_week / 30) / 2) : '';
    fillRolePick(); $('tmRole').value = m ? m.role : 'account';
    msg('tmMsg', '');
    window.ADspaceSheet.show($('teamAddBox'), {
      opener: memberOpener,
      onClose: function () { editingMember = null; memberOpener = null; }
    });
  }
  $('teamAdd').addEventListener('click', function () { openMemberBox(null, this); });
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
    var fields = { name: name, email: email, role: role, staff_code: staff || null, designation: desig || null,
                   capacity_minutes_week: capH >= 0 && $('tmCap').value ? Math.round(capH * 60) : null };
    if (editingMember) {
      var m = editingMember;
      /* The row's email is the address the console signs in with, so moving it
         moves the door. The login itself stays where it was until somebody is
         invited at the new address. */
      function write() {
        shutMemberBox();
        db.from('team_members').update(fields).eq('id', m.id).then(function (r) {
          if (r.error) {
            msg('teamMsg', /staff_code/i.test(r.error.message) ? 'That Employee ID is already on the list.'
              : /duplicate|unique/i.test(r.error.message)
              ? 'That email is already on the list.' : r.error.message, 'err');
            return;
          }
          log('team.edited', name, email + ' · ' + roleName(role));
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
          msg('tmMsg', /staff_code/i.test(r.error.message) ? 'That Employee ID is already on the list.'
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
    enter: function () { load(); }
  };
  if (bridge.teamReady) bridge.teamReady();
})();
