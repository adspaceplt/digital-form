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

  var FLAGS = [
    ['can_clients',   'Clients'],
    ['can_review',    'Content Review'],
    ['can_campaigns', 'Creator Campaigns'],
    ['can_links',     'Short Links'],
    ['can_billing',   'Billing'],
    ['can_activity',  'Activity record'],
    ['can_remove',    'Remove']
  ];

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
      menu.hidden = !open;
      btn.setAttribute('aria-expanded', String(open));
      // Placed on the viewport, so the table's overflow cannot clip it.
      if (open) {
        var r = btn.getBoundingClientRect();
        menu.style.position = 'fixed';
        menu.style.top = (r.bottom + 4) + 'px';
        menu.style.right = 'auto';
        menu.style.left = Math.max(8, r.right - menu.offsetWidth) + 'px';
      }
    });
  }
  window.addEventListener('scroll', shutMenus, true);
  document.addEventListener('click', function (e) {
    if (!e.target.closest || !e.target.closest('#sectionTeam .team-act')) shutMenus();
  });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') shutMenus(); });

  function load() {
    $('teamList').innerHTML = '<div class="empty">Loading…</div>';
    db.from('team_roles').select('*').order('position').order('name').then(function (r) {
      if (r.error) { $('groupList').innerHTML = '<div class="empty">' + esc(r.error.message) + '</div>'; return; }
      state.roles = r.data || [];
      paintGroups();
      fillRolePick();
      db.from('team_members').select('*').order('active', { ascending: false })
        .order('role').order('name').then(function (q) {
          if (q.error) { $('teamList').innerHTML = '<div class="empty">' + esc(q.error.message) + '</div>'; return; }
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
  function paintMembers() {
    var box = $('teamList');
    box.innerHTML = '';
    if (!state.rows.length) { box.innerHTML = '<div class="empty">No team members.</div>'; return; }
    var head = document.createElement('div');
    head.className = 'team-head';
    head.innerHTML = '<span>Person</span><span>Group</span><span></span>';
    box.appendChild(head);
    state.rows.forEach(function (m) { box.appendChild(memberRow(m)); });
  }

  function memberRow(m) {
    var self = me() && me().id === m.id;
    var el = document.createElement('div');
    el.className = 'team-row' + (m.active ? '' : ' is-off');
    el.innerHTML =
      '<span class="team-who"><b>' + esc(m.name) + (self ? ' <i>you</i>' : '') + '</b>' +
        '<small>' + esc(m.email || '') + '</small></span>' +
      '<span><select class="select select-sm" data-f="role" aria-label="Group">' + roleOptions(m.role) + '</select></span>' +
      menuBtn(
        (m.active && m.email ? menuItem('invite', 'Invite') : '') +
        (m.active
          ? menuItem('off', 'Deactivate', self ? '' : 'is-danger', self)
          : menuItem('on', 'Reactivate')));

    wireMenu(el);
    el.querySelector('[data-f="role"]').addEventListener('change', function () {
      saveMember(m, { role: this.value });
    });
    var off = el.querySelector('[data-a="off"]');
    if (off) off.addEventListener('click', function () {
      if (!confirm('Deactivate ' + m.name + '?\n\nAccess is removed until reactivated.')) return;
      saveMember(m, { active: false });
    });
    var on = el.querySelector('[data-a="on"]');
    if (on) on.addEventListener('click', function () { saveMember(m, { active: true }); });
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
  function paintGroups() {
    var box = $('groupList');
    box.innerHTML = '';
    var head = document.createElement('div');
    head.className = 'group-head';
    head.innerHTML = '<span>Group</span>' +
      FLAGS.map(function (f) { return '<span>' + esc(f[1]) + '</span>'; }).join('') +
      '<span>Admin</span><span></span>';
    box.appendChild(head);
    state.roles.forEach(function (r) { box.appendChild(groupRow(r)); });
  }

  function groupRow(r) {
    var locked = r.slug === 'admin';
    var used = state.rows.some(function (m) { return m.role === r.slug; });
    var el = document.createElement('div');
    el.className = 'group-row';
    var members = state.rows.filter(function (m) { return m.role === r.slug; }).length;
    el.innerHTML =
      '<span class="group-name"><b>' + esc(r.name) + '</b><small>' + members + ' member' + (members === 1 ? '' : 's') + '</small></span>' +
      FLAGS.map(function (f) {
        return '<span class="team-flag" data-label="' + esc(f[1]) + '"><input type="checkbox" data-f="' + f[0] + '"' +
          (r[f[0]] ? ' checked' : '') + (locked ? ' disabled' : '') + ' aria-label="' + esc(f[1]) + '"></span>';
      }).join('') +
      '<span class="team-flag" data-label="Admin"><input type="checkbox" data-f="is_admin"' +
        (r.is_admin ? ' checked' : '') + (locked ? ' disabled' : '') + ' aria-label="Admin"></span>' +
      (locked ? '<span class="team-act"></span>'
        : menuBtn(menuItem('rename', 'Rename') + (used ? '' : menuItem('del', 'Delete', 'is-danger'))));

    wireMenu(el);
    Array.prototype.forEach.call(el.querySelectorAll('input[type="checkbox"]'), function (cb) {
      cb.addEventListener('change', function () {
        var patch = {}; patch[cb.getAttribute('data-f')] = cb.checked;
        saveGroup(r, patch);
      });
    });
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
        return k.replace('can_', '') + '=' + patch[k];
      }).join(', '));
      msg('groupMsg', 'Saved.', 'ok');
      // Members carry their group's switches; the console reads them at sign-in.
      load();
    });
  }

  // One panel adds a group or renames one.
  function openGroupBox(r) {
    state.editing = r || null;
    $('grTitle').textContent = r ? 'Rename group' : 'New group';
    $('grSave').textContent = r ? 'Save' : 'Add';
    $('groupAddBox').hidden = false;
    $('grName').value = r ? r.name : '';
    msg('grMsg', '');
    $('grName').focus();
  }
  $('groupAdd').addEventListener('click', function () { openGroupBox(null); });
  $('grCancel').addEventListener('click', function () { $('groupAddBox').hidden = true; state.editing = null; });
  $('grSave').addEventListener('click', function () {
    var name = ($('grName').value || '').trim();
    if (!name) { msg('grMsg', 'A name is required.', 'err'); return; }
    if (state.editing) {
      var r = state.editing;
      $('groupAddBox').hidden = true; state.editing = null;
      if (name !== r.name) saveGroup(r, { name: name });
      return;
    }
    var slug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
    if (!slug) { msg('grMsg', 'Use letters or numbers in the name.', 'err'); return; }
    if (state.roles.some(function (r) { return r.slug === slug; })) { msg('grMsg', 'That group already exists.', 'err'); return; }
    db.from('team_roles').insert({
      slug: slug, name: name, position: state.roles.length,
      can_clients: true, can_review: false, can_campaigns: false, can_links: false,
      can_billing: false, can_activity: false, can_remove: false, is_admin: false
    }).then(function (q) {
      if (q.error) { msg('grMsg', q.error.message, 'err'); return; }
      log('team.group_added', name, '');
      $('groupAddBox').hidden = true;
      msg('groupMsg', name + ' added.', 'ok');
      load();
    });
  });

  // ---- Add a person -------------------------------------------------------
  $('teamAdd').addEventListener('click', function () {
    $('teamAddBox').hidden = false;
    $('tmName').value = ''; $('tmEmail').value = '';
    fillRolePick(); $('tmRole').value = 'account';
    msg('tmMsg', '');
    $('tmName').focus();
  });
  $('tmCancel').addEventListener('click', function () { $('teamAddBox').hidden = true; });
  $('tmSave').addEventListener('click', function () {
    var name = ($('tmName').value || '').trim();
    var email = ($('tmEmail').value || '').trim().toLowerCase();
    var role = $('tmRole').value;
    if (!name) { msg('tmMsg', 'A name is required.', 'err'); return; }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) { msg('tmMsg', 'A valid email is required.', 'err'); return; }
    if (!role) { msg('tmMsg', 'A group is required.', 'err'); return; }
    db.from('team_members').insert({ name: name, email: email, role: role, active: true })
      .then(function (r) {
        if (r.error) {
          msg('tmMsg', /duplicate|unique/i.test(r.error.message)
            ? 'That email is already on the list.' : r.error.message, 'err');
          return;
        }
        log('team.added', name, email + ' · ' + roleName(role));
        $('teamAddBox').hidden = true;
        load();
        // The row is theirs; now the login. The function holds the key the
        // browser must not, and emails them the sign-in link.
        msg('teamMsg', name + ' added. Sending invitation…', 'ok');
        db.functions.invoke('invite-member', { body: { email: email, name: name } })
          .then(function (r) {
            var d = r.data || {};
            if (r.error || d.error) {
              var why = (d.error === 'not_admin') ? 'Only an admin can send invitations.'
                : (r.error && /not found|404|Failed to send/i.test(String(r.error.message || r.error)))
                  ? 'The invite-member function is not deployed. Add the login under Supabase ' +
                    'Authentication, or deploy the function and use Invite.'
                  : 'Invitation could not be sent: ' + (d.detail || (r.error && r.error.message) || d.error);
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
    if (!m.email) { msg('teamMsg', m.name + ' has no email on record.', 'err'); return; }
    msg('teamMsg', 'Sending an invitation to ' + m.email + '…', 'ok');
    db.functions.invoke('invite-member', { body: { email: m.email, name: m.name } })
      .then(function (r) {
        var d = r.data || {};
        if (r.error || d.error) { msg('teamMsg', 'Could not send: ' + (d.detail || d.error || (r.error && r.error.message)), 'err'); return; }
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
