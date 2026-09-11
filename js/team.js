/*
 * Team — who may do what.
 *
 * One row per person who can sign in. The role sets defaults, the switches
 * adjust them per person, and the database enforces the result: this page
 * draws the switches, the policies in supabase/schema.sql are the control.
 * Only an admin sees this section.
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

  var ROLES = [
    ['admin',   'Admin'],
    ['account', 'Account'],
    ['sales',   'Sales']
  ];
  /* The switches, in the order they are asked about. Column, label, what it
     lets the person do. */
  var FLAGS = [
    ['can_clients',   'Clients',          'The client list, contacts and the log'],
    ['can_review',    'Content Review',   'Content sets and approvals'],
    ['can_campaigns', 'Creator Campaigns','Creators, proposals and production'],
    ['can_links',     'Short Links',      'Links and QR codes'],
    ['can_billing',   'Billing details',  'See and edit the e-invoice fields'],
    ['can_activity',  'Activity record',  'Read the record of who did what'],
    ['can_remove',    'Can remove',       'Delete campaigns and links, remove clients from Content Review']
  ];

  var state = { rows: [] };

  function load() {
    var box = $('teamList');
    box.innerHTML = '<div class="empty">Loading…</div>';
    db.from('team_members').select('*').order('active', { ascending: false })
      .order('role').order('name').then(function (r) {
        if (r.error) { box.innerHTML = '<div class="empty">' + esc(r.error.message) + '</div>'; return; }
        state.rows = r.data || [];
        paint();
      });
  }

  function paint() {
    var box = $('teamList');
    box.innerHTML = '';
    if (!state.rows.length) {
      box.innerHTML = '<div class="empty">No team members.</div>';
      return;
    }
    var head = document.createElement('div');
    head.className = 'team-head';
    head.innerHTML = '<span>Person</span><span>Role</span>' +
      FLAGS.map(function (f) { return '<span title="' + esc(f[2]) + '">' + esc(f[1]) + '</span>'; }).join('') +
      '<span></span>';
    box.appendChild(head);
    state.rows.forEach(function (m) { box.appendChild(row(m)); });
  }

  function row(m) {
    var self = me() && me().id === m.id;
    var el = document.createElement('div');
    el.className = 'team-row' + (m.active ? '' : ' is-off');
    el.innerHTML =
      '<span class="team-who"><b>' + esc(m.name) + (self ? ' <i>you</i>' : '') + '</b>' +
        '<small>' + esc(m.email || 'no email, cannot sign in') + '</small></span>' +
      '<span><select class="select select-sm" data-f="role">' +
        ROLES.map(function (r) {
          return '<option value="' + r[0] + '"' + (m.role === r[0] ? ' selected' : '') + '>' + esc(r[1]) + '</option>';
        }).join('') + '</select></span>' +
      FLAGS.map(function (f) {
        return '<span class="team-flag" data-label="' + esc(f[1]) + '"><input type="checkbox" data-f="' + f[0] + '"' +
          (m[f[0]] ? ' checked' : '') + (m.role === 'admin' ? ' disabled' : '') +
          ' aria-label="' + esc(f[1]) + '"></span>';
      }).join('') +
      '<span class="team-act">' +
        (m.active && m.email ? '<button class="btn btn-quiet btn-sm" data-a="invite" type="button" title="Email their sign-in link again">Invite</button>' : '') +
        (m.active
          ? '<button class="btn btn-quiet btn-sm' + (self ? '' : ' is-danger') + '" data-a="off" type="button"' +
            (self ? ' disabled title="Ask another admin"' : '') + '>Deactivate</button>'
          : '<button class="btn btn-quiet btn-sm" data-a="on" type="button">Reactivate</button>') +
      '</span>';

    // Any change saves at once and says so. The role change re-fetches so the
    // defaults the database applied are what is on screen.
    el.querySelector('[data-f="role"]').addEventListener('change', function () {
      save(m, { role: this.value }, true);
    });
    Array.prototype.forEach.call(el.querySelectorAll('input[type="checkbox"]'), function (cb) {
      cb.addEventListener('change', function () {
        var patch = {}; patch[cb.getAttribute('data-f')] = cb.checked;
        save(m, patch, false);
      });
    });
    var off = el.querySelector('[data-a="off"]');
    if (off) off.addEventListener('click', function () {
      if (!confirm('Deactivate ' + m.name + '?\n\nAccess is removed until reactivated.')) return;
      save(m, { active: false }, true);
    });
    var on = el.querySelector('[data-a="on"]');
    if (on) on.addEventListener('click', function () { save(m, { active: true }, true); });
    var inv = el.querySelector('[data-a="invite"]');
    if (inv) inv.addEventListener('click', function () { reinvite(m); });
    return el;
  }

  function save(m, patch, reload) {
    db.from('team_members').update(patch).eq('id', m.id).then(function (r) {
      if (r.error) { msg('teamMsg', r.error.message, 'err'); load(); return; }
      Object.keys(patch).forEach(function (k) { m[k] = patch[k]; });
      log('team.changed', m.name, Object.keys(patch).map(function (k) { return k.replace('can_', '') + '=' + patch[k]; }).join(', '));
      msg('teamMsg', 'Saved for ' + m.name + '.', 'ok');
      if (reload) load();
    });
  }

  // ---- Add a person -------------------------------------------------------
  $('teamAdd').addEventListener('click', function () {
    $('teamAddBox').hidden = false;
    $('tmName').value = ''; $('tmEmail').value = ''; $('tmRole').value = 'account';
    msg('tmMsg', '');
    $('tmName').focus();
  });
  $('tmCancel').addEventListener('click', function () { $('teamAddBox').hidden = true; });
  $('tmSave').addEventListener('click', function () {
    var name = ($('tmName').value || '').trim();
    var email = ($('tmEmail').value || '').trim().toLowerCase();
    if (!name) { msg('tmMsg', 'A name is needed.', 'err'); return; }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) { msg('tmMsg', 'Enter the email they sign in with.', 'err'); return; }
    db.from('team_members').insert({ name: name, email: email, role: $('tmRole').value, active: true })
      .then(function (r) {
        if (r.error) {
          msg('tmMsg', /duplicate|unique/i.test(r.error.message)
            ? 'That email is already on the list.' : r.error.message, 'err');
          return;
        }
        log('team.added', name, email + ' · ' + $('tmRole').value);
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

  // For a person added before the function existed, or whose email got lost.
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

  $('tmRole').innerHTML = ROLES.map(function (r) {
    return '<option value="' + r[0] + '">' + esc(r[1]) + '</option>';
  }).join('');
  $('tmRole').value = 'account';

  window.ADspaceTeam = {
    urlState: function () { return {}; },
    enter: function () { load(); }
  };
  if (bridge.teamReady) bridge.teamReady();
})();
