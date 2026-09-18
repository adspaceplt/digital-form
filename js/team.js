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
  var SECTIONS = [
    ['clients',   'Clients',           ['none', 'view', 'work', 'manage']],
    ['review',    'Content Review',    ['none', 'view', 'work', 'manage']],
    ['campaigns', 'Creator Campaigns', ['none', 'view', 'work', 'manage']],
    ['links',     'Short Links',       ['none', 'view', 'work', 'manage']],
    /* The Register is the documents issued and the serials the verify page
       answers; HR letters are a part of it, gated apart, because a
       colleague's letter is read by fewer people than a client's. */
    ['register',  'Register',          ['none', 'view', 'work', 'manage']],
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
    register:  [['documents', 'Client documents'], ['hr', 'HR letters']]
  };
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
      box.querySelector('[data-a="first"]').addEventListener('click', function () { openMemberBox(null); });
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
      if (m.active && !confirm('Set ' + m.name + ' inactive?\n\nAccess is removed until they are set active again.')) return;
      saveMember(m, { active: !m.active });
    });
    var ed = el.querySelector('[data-a="edit"]');
    if (ed) ed.addEventListener('click', function () { openMemberBox(m); });
    var inv = el.querySelector('[data-a="invite"]');
    if (inv) inv.addEventListener('click', function () { reinvite(m); });
    return el;
  }

  function saveMember(m, patch) {
    db.from('team_members').update(patch).eq('id', m.id).then(function (r) {
      if (r.error) { msg('teamMsg', r.error.message, 'err'); load(); return; }
      log('team.changed', m.name, Object.keys(patch).map(function (k) {
        return k + '=' + (k === 'role' ? roleName(patch[k]) : patch[k]);
      }).join(', '));
      msg('teamMsg', 'Saved.', 'ok');
      load();
    });
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
      var ex = (PARTS[s[0]] || []).filter(function (p) {
        var v = acc[s[0] + '.' + p[0]];
        return v && v !== acc[s[0]];
      }).map(function (p) {
        var v = acc[s[0] + '.' + p[0]];
        return p[1] + ': ' + (LEVEL_WORD[v] || 'No access');
      });
      return s[1] + (ex.length ? ' (' + ex.join(', ') + ')' : '');
    };
    ['manage', 'work', 'view'].forEach(function (lv) {
      var named = SECTIONS.filter(function (s) { return acc[s[0]] === lv; }).map(word);
      if (named.length) parts.push(LEVEL_WORD[lv] + ': ' + named.join(', '));
    });
    /* A part opened above a section that is shut is an exception too. */
    var only = SECTIONS.filter(function (s) { return (acc[s[0]] || 'none') === 'none'; }).map(function (s) {
      var ex = (PARTS[s[0]] || []).filter(function (p) { return acc[s[0] + '.' + p[0]] && acc[s[0] + '.' + p[0]] !== 'none'; })
        .map(function (p) { return p[1] + ': ' + LEVEL_WORD[acc[s[0] + '.' + p[0]]]; });
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
    if (ren) ren.addEventListener('click', function () { openGroupBox(r); });
    var del = el.querySelector('[data-a="del"]');
    if (del) del.addEventListener('click', function () {
      if (!confirm('Delete the ' + r.name + ' group?')) return;
      db.from('team_roles').delete().eq('slug', r.slug).then(function (q) {
        if (q.error) { msg('groupMsg', q.error.message, 'err'); return; }
        log('team.group_removed', r.name, '');
        msg('groupMsg', r.name + ' deleted.', 'ok');
        load();
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

  /* One select per section, then the two capabilities and Admin as switches.
     Seven selects rather than twenty eight tickboxes, and the row above reads
     back as a sentence. */
  /* One block per section: the section's own select is the main control on
     its head line, and its parts sit directly under it, each a select that
     starts at Same as section. A part is read where its section is, never in
     a second list that names the sections again (the user's own structure,
     2026-09-22). A section with no parts is the head line alone. */
  $('grFlags').innerHTML =
    SECTIONS.map(function (sec) {
      var parts = PARTS[sec[0]] || [];
      /* A section with parts folds them under its head line, the way the
         accounting portal the user showed folds each of its sections: the
         select on the head is the main control and is always in reach, and
         the parts open where an exception is held or where somebody asks. */
      return '<div class="permsec" data-sec="' + sec[0] + '">' +
        '<div class="permsec-main">' +
          (parts.length
            ? '<button class="permsec-toggle" type="button" aria-expanded="false" aria-controls="grParts-' + sec[0] + '">' +
                '<span class="disclosure-caret" aria-hidden="true">&#9656;</span><span class="permsec-name">' + esc(sec[1]) + '</span></button>'
            : '<span class="permsec-name">' + esc(sec[1]) + '</span>') +
          '<select class="select select-sm" data-sec="' + sec[0] + '" aria-label="' + esc(sec[1]) + ' access">' +
          LEVELS.filter(function (l) { return sec[2].indexOf(l[0]) > -1; }).map(function (l) {
            return '<option value="' + l[0] + '">' + esc(l[1]) + '</option>';
          }).join('') + '</select></div>' +
        (parts.length ? '<div class="permgrid permsec-parts" id="grParts-' + sec[0] + '" hidden>' + parts.map(function (p) {
          return '<label class="permlevel"><span class="field-label">' + esc(p[1]) + '</span>' +
            '<select class="select select-sm" data-part="' + sec[0] + '.' + p[0] + '" aria-label="' + esc(sec[1] + ': ' + p[1]) + ' access">' +
            '<option value="">Same as section</option>' +
            LEVELS.map(function (l) { return '<option value="' + l[0] + '">' + esc(l[1]) + '</option>'; }).join('') +
            '</select></label>';
        }).join('') + '</div>' : '') +
      '</div>';
    }).join('') +
    CAPS.concat([['is_admin', 'Admin (everything)']]).map(function (f) {
      return '<label class="perm"><input type="checkbox" data-f="' + f[0] + '"><span>' + esc(f[1]) + '</span></label>';
    }).join('');
  function flagBoxes() { return Array.prototype.slice.call($('grFlags').querySelectorAll('input')); }
  function levelPicks() { return Array.prototype.slice.call($('grFlags').querySelectorAll('select[data-sec]')); }
  function partPicks() { return Array.prototype.slice.call($('grFlags').querySelectorAll('select[data-part]')); }
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

  // One panel adds a group or edits one, as one panel adds a service.
  function openGroupBox(r) {
    shutMenus();   // it was chosen from a ⋯, which does not repaint behind it
    state.editing = r || null;
    $('grTitle').textContent = r ? 'Edit group' : 'New group';
    $('grSave').textContent = r ? 'Save' : 'Add';
    $('groupAddBox').hidden = false;
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
       because Same as section on every part is the ordinary case. */
    var opened = {};
    partPicks().forEach(function (sel) {
      var k = sel.getAttribute('data-part');
      sel.value = acc && acc[k] ? acc[k] : '';
      if (sel.value) opened[k.split('.')[0]] = true;
      sel.disabled = Boolean(r && r.slug === 'admin');
    });
    Object.keys(PARTS).forEach(function (sec) { foldSec(sec, Boolean(opened[sec])); });
    flagBoxes().forEach(function (cb) {
      var k = cb.getAttribute('data-f');
      cb.checked = r ? Boolean(r[k]) : false;
      cb.disabled = Boolean(r && r.slug === 'admin');
    });
    msg('grMsg', '');
    $('grName').focus();
  }
  $('groupAdd').addEventListener('click', function () { openGroupBox(null); });
  $('grCancel').addEventListener('click', function () { $('groupAddBox').hidden = true; state.editing = null; });
  $('grSave').addEventListener('click', function () {
    var name = ($('grName').value || '').trim();
    if (!name) { msg('grMsg', 'A name is required.', 'err'); return; }
    var flags = {};
    flagBoxes().forEach(function (cb) { flags[cb.getAttribute('data-f')] = cb.checked; });
    var access = {};
    levelPicks().forEach(function (sel) { access[sel.getAttribute('data-sec')] = sel.value || 'none'; });
    // Only an exception is stored; Same as section is the absence of a key.
    partPicks().forEach(function (sel) { if (sel.value) access[sel.getAttribute('data-part')] = sel.value; });
    if (state.editing) {
      var r = state.editing;
      var patch = {};
      if (name !== r.name) patch.name = name;
      Object.keys(flags).forEach(function (k) { if (Boolean(r[k]) !== flags[k]) patch[k] = flags[k]; });
      if (JSON.stringify(accessOf(r)) !== JSON.stringify(access)) patch.access = access;
      $('groupAddBox').hidden = true; state.editing = null;
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
      $('groupAddBox').hidden = true;
      msg('groupMsg', name + ' added.', 'ok');
      load();
    });
  });

  // ---- Add or edit a person -----------------------------------------------
  var editingMember = null;
  function openMemberBox(m) {
    shutMenus();
    editingMember = m || null;
    $('tmTitle').textContent = m ? 'Edit member' : 'New team member';
    $('tmSave').textContent = m ? 'Save' : 'Add';
    $('teamAddBox').hidden = false;
    $('tmName').value = m ? (m.name || '') : '';
    $('tmEmail').value = m ? (m.email || '') : '';
    $('tmStaff').value = m ? (m.staff_code || '') : '';
    $('tmDesig').value = m ? (m.designation || '') : '';
    fillRolePick(); $('tmRole').value = m ? m.role : 'account';
    msg('tmMsg', '');
    $('tmName').focus();
  }
  $('teamAdd').addEventListener('click', function () { openMemberBox(null); });
  $('tmCancel').addEventListener('click', function () { $('teamAddBox').hidden = true; editingMember = null; });
  $('tmSave').addEventListener('click', function () {
    var name = ($('tmName').value || '').trim();
    var email = ($('tmEmail').value || '').trim().toLowerCase();
    var role = $('tmRole').value;
    var staff = ($('tmStaff').value || '').trim().toUpperCase();
    var desig = ($('tmDesig').value || '').trim();
    if (!name) { msg('tmMsg', 'A name is required.', 'err'); return; }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) { msg('tmMsg', 'A valid email is required.', 'err'); return; }
    if (!role) { msg('tmMsg', 'A group is required.', 'err'); return; }
    /* The HR serial is built from it, so it is letters and digits only. */
    if (staff && !/^[A-Z0-9]{3,8}$/.test(staff)) { msg('tmMsg', 'An Employee ID is 3 to 8 letters or digits.', 'err'); $('tmStaff').focus(); return; }
    var fields = { name: name, email: email, role: role, staff_code: staff || null, designation: desig || null };
    if (editingMember) {
      var m = editingMember;
      /* The row's email is the address the console signs in with, so moving it
         moves the door. The login itself stays where it was until somebody is
         invited at the new address. */
      if (email !== String(m.email || '').toLowerCase() &&
          !confirm('Change the sign-in address to ' + email + '?\n\n' + m.name +
                   ' signs in with the new address. Send an invitation so the login is made.')) return;
      $('teamAddBox').hidden = true; editingMember = null;
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
      });
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
        $('teamAddBox').hidden = true;
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
    if (!confirm('Send a sign-in invitation to ' + m.email + '?')) return;
    msg('teamMsg', 'Sending an invitation to ' + m.email + '…', 'ok');
    API.invokeFn('invite-member', { email: m.email, name: m.name })
      .then(function (r) {
        var d = r.data || {};
        if (r.error) { msg('teamMsg', 'Could not send: ' + r.why, 'err'); return; }
        log('team.invited', m.name, m.email);
        msg('teamMsg', d.already ? m.name + ' already has a login.'
                                 : 'Invitation sent to ' + m.email + '.', 'ok');
      });
  }

  window.ADspaceTeam = {
    urlState: function () { return {}; },
    enter: function () { load(); }
  };
  if (bridge.teamReady) bridge.teamReady();
})();
