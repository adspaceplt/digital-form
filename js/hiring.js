/*
 * Hiring (2026-11-16, release H2 step A; the user's HR-SPEC.md decisions 1
 * and 3), Team's Hiring tab since the same day (`?s=team&tab=hiring`). Candidates for a position, the colleagues on each, and each
 * candidate's own page (`/careers/?k=`). A candidate never holds an account.
 *
 * Every candidate is read and added at the granted part `team.hiring` (an
 * admin's by itself). On a candidate the part adds colleagues as Owner
 * (decides and sends) or Interviewer (sees that candidate and scores); such a
 * colleague sees that candidate alone. Nothing about a candidate goes to the
 * Activity record or to an AI service: its history is its own
 * (`hiring_events`), drawn on its Activity pane.
 */
(function () {
  var API = window.ADspaceAPI;
  var db = API && API.client;
  var UI = window.ADspaceState;
  var bridge = window.ADspaceAdmin || {};
  if (!API || !API.configured || !db || !UI) return;

  function $(id) { return document.getElementById(id); }
  var esc = window.ADspaceWords.esc;
  function may(k, l) { return Boolean(bridge.may && bridge.may(k, l)); }
  function admin() { return may('team.hiring', 'work'); }
  function day(iso) { return iso ? window.ADspaceClock.date(iso) : ''; }
  function msg(id, text, kind) { var m = $(id); if (!m) return; m.textContent = text || ''; m.className = 'msg' + (kind && text ? ' ' + kind : ''); }

  var BUCKET = 'hiring', SIGN_SECS = 60, MAX_MB = 20;
  var SOURCE = { jobstreet: 'JobStreet', linkedin: 'LinkedIn', indeed: 'Indeed', referral: 'Referral', website: 'Website', walk_in: 'Walk-in', other: 'Other' };
  /* Where a candidate stands; the steps after New arrive with the later
     releases (invitations, scorecards, offer, Make colleague). */
  var STAGE = { new: ['New', 'is-off'], invited: ['Invited', 'is-warn'], interview: ['Interview', 'is-warn'], offer: ['Offer', 'is-warn'],
    hired: ['Hired', 'is-ok'], pool: ['Talent pool', 'is-off'], closed: ['Closed', 'is-off'] };
  var ROLE = { admin: 'Hiring', owner: 'Owner', interviews: 'Interviewer' };
  var SAID = {
    'denied': 'You do not have permission to do this. Please ask an admin.', 'not-found': 'This candidate no longer exists.',
    'bad-name': 'Enter a name of 2 to 120 characters.', 'bad-email': 'Enter a valid email address.',
    'bad-phone': 'Enter a phone number of 8 to 15 digits, for example 012-345 6789.', 'bad-position': 'Enter the position.',
    'bad-source': 'Choose a source.', 'bad-cv': 'Enter a web address that starts with https://.', 'too-long': 'Shorten the note to 2,000 characters.',
    'stale': 'Not saved. This record was changed by someone else. The latest version is now shown.',
    'bad-role': 'Choose Owner or Interviewer.', 'bad-colleague': 'Choose an active colleague.', 'not-removed': 'Remove the candidate first.',
    'bad-request': 'Please refresh the page and try again.',
    'bad-slots': 'Enter one to three times.', 'slot-past': 'Choose a time at least an hour from now.',
    'slot-far': 'Choose times within the next 60 days.', 'bad-minutes': 'Choose the length.', 'bad-mode': 'Choose Google Meet or At the office.',
    'closed': 'This application has been closed.', 'not-picked': 'The candidate has not chosen a time yet.',
    'not-confirmed': 'Approve the interview first.', 'no-meet': 'Create the Google Meet first.',
    'mail-not-set-up': (window.ADspaceWords.line || {}).mailOff || '', 'not-sent': 'The email was not sent. Please try again.',
    'unknown': 'The email may not have been sent. Check with the candidate before sending it again.',
    'slot-taken': 'Another online meeting is booked at this time. Send the candidate new times.',
    'meet-not-set-up': 'Google Meet is not set up yet. Please contact an admin.',
    'google-token': 'Google Meet is not available at the moment. Please contact an admin.',
    'google-refused': 'Google Meet is not available at the moment. Please try again.',
    'meet-pending': 'Google is still creating the Meet. Press Create Google Meet again in a moment.'
  };
  function said(r) {
    var m = r && r.error && (r.error.message || '');
    if (m && /could not find|does not exist|schema cache/i.test(m)) return 'This feature is not available yet. Please contact an admin.';
    var k = (r && r.data && r.data.error) || m;
    if (k === 'taken') return r.data && r.data.name ? r.data.name + ' has already been added with this email address. Enter another email address.' : 'A candidate has already been added with this email address. Enter another email address.';
    if (k === 'bad-name' && state.deleting) return 'Type the candidate\'s name exactly as shown.';
    return SAID[k] || k || 'The request failed. Please try again.';
  }
  function rpc(fn, args) {
    return db.rpc(fn, args).then(function (r) { return r; }).catch(function (e) { return { error: e }; });
  }
  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>';
  var CHEV = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>';
  var BACK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M19 12H5"/><path d="m11 6-6 6 6 6"/></svg>';
  var COPY = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15H4.5A1.5 1.5 0 0 1 3 13.5v-9A1.5 1.5 0 0 1 4.5 3h9A1.5 1.5 0 0 1 15 4.5V5"/></svg>';
  var OUT = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 4h6v6"/><path d="M20 4 11 13"/><path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg>';
  var FILE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/></svg>';

  var state = { rows: null, admin: false, find: '', open: null, rec: null, pane: 'overview', wired: false, editing: null, deleting: false, team: null };
  var PANES = [['overview', 'Overview'], ['interview', 'Interview'], ['people', 'People'], ['activity', 'Activity']];
  function paneOk(k) { return PANES.some(function (x) { return x[0] === k; }); }
  /* Team's tab (`tab=hiring`): a candidate rides as `candidate=`, its pane as
     `ctab=` (Overview left out), as a colleague's does as `member=` and `mtab=`. */
  function urlState() { return { candidate: state.open || '', ctab: state.open && state.pane !== 'overview' ? state.pane : '' }; }
  function setUrl() { if (bridge.setUrl) bridge.setUrl(); }

  function wire() {
    if (state.wired) return;
    state.wired = true;
    $('hirFind').addEventListener('input', function () {
      var v = this.value.trim().toLowerCase();
      if (v === state.find) return;
      state.find = v; paint();
    });
    $('hirAdd').addEventListener('click', function () { openSheet(null); });
    $('hirSheetCancel').addEventListener('click', shutSheet);
    $('hirSheetClose').addEventListener('click', shutSheet);
    $('hirSheetGo').addEventListener('click', saveSheet);
    window.addEventListener('popstate', function () {
      if ($('teamHiringPane') && !$('teamHiringPane').hidden) enter();
    });
    document.addEventListener('click', function (e) { if (!e.target.closest || !e.target.closest('#hirRec .team-act')) shutMenus(); });
  }
  function enter() {
    wire();
    var q = new URLSearchParams(location.search);
    state.open = q.get('candidate') || null;
    state.pane = state.open && paneOk(q.get('ctab')) ? q.get('ctab') : 'overview';
    $('hirAdd').hidden = !admin();
    load();
  }

  // ---- The list -------------------------------------------------------------
  function load() {
    var box = $('hirList');
    if (!state.rows) UI.skeleton(box, 4);
    return rpc('hiring_list', {}).then(function (r) {
      var d = r.data || {};
      if (r.error || d.error) { state.rows = null; UI.failLine(box, 'the candidates', said(r), load); return; }
      state.rows = d.rows || []; state.admin = Boolean(d.admin);
      $('hirPositions').innerHTML = uniq(state.rows.map(function (c) { return c.position; })).map(function (p) { return '<option value="' + esc(p) + '">'; }).join('');
      if (state.open) openRec(state.open); else paint();
    });
  }
  function uniq(a) { var o = []; a.forEach(function (x) { if (x && o.indexOf(x) < 0) o.push(x); }); return o.sort(); }
  function matches(c) {
    if (!state.find) return true;
    return [c.name, c.position, SOURCE[c.source] || ''].join(' ').toLowerCase().indexOf(state.find) > -1;
  }
  function chip(c) {
    var st = c.removed_at ? ['Removed', 'is-off'] : STAGE[c.stage] || STAGE.new;
    return '<span class="chip-state ' + st[1] + '">' + esc(st[0]) + '</span>';
  }
  function paint() {
    var box = $('hirList');
    $('hirRec').hidden = true; box.hidden = false; $('hirBar').hidden = false;
    $('sectionTeam').classList.remove('is-candidate');
    if (!state.rows) return;
    var all = state.rows, rows = all.filter(matches);
    $('hirCount').textContent = !all.length ? '' : rows.length === all.length
      ? all.length + (all.length === 1 ? ' candidate' : ' candidates') : rows.length + ' of ' + all.length;
    if (!all.length) { UI.emptyLine(box, 'No candidates.', admin() ? 'Add candidate' : '', function () { openSheet(null); }); return; }
    if (!rows.length) {
      UI.emptyLine(box, 'No matches.', 'Clear filters', function () { state.find = ''; $('hirFind').value = ''; paint(); });
      return;
    }
    box.innerHTML = '';
    var GRP = window.ADspaceGroup, filtered = rows.length !== all.length;
    /* A card a stage, what needs acting on first and what is finished last;
       a removed candidate in its own card, shut. */
    [['new', 'New'], ['invited', 'Invited'], ['interview', 'Interview'], ['offer', 'Offer'], ['pool', 'Talent pool'], ['hired', 'Hired'], ['closed', 'Closed'], ['removed', 'Removed']].forEach(function (g) {
      var mine = rows.filter(function (c) { return g[0] === 'removed' ? !!c.removed_at : !c.removed_at && c.stage === g[0]; });
      if (!mine.length) return;
      box.appendChild(GRP.section({
        route: 'hiring', key: g[0], name: g[1], count: mine.length,
        shut: !filtered && GRP.shut('hiring', g[0], g[0] === 'removed' || g[0] === 'closed'),
        table: function () {
          var table = GRP.table('svc-row hir-row', ['Candidate', 'Source', 'Owner', 'Added', 'State', '']);
          GRP.more(table, mine, 30, 'hiring', row);
          return table;
        }
      }));
    });
  }
  function row(c) {
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'svc-row hir-row' + (c.removed_at ? ' is-off' : '');
    var owners = (c.owners || []).join(', ');
    b.innerHTML = '<span class="svc-name"><b>' + esc(c.name) + '</b><small>' + esc(c.position) + '</small></span>' +
      '<span class="hir-src">' + esc(SOURCE[c.source] || '') + '</span>' +
      '<span class="hir-own' + (owners ? '' : ' is-none') + '">' + (owners ? esc(owners) : '<span class="muted">—</span>') + '</span>' +
      '<span class="hir-day">' + esc(day(c.created_at)) + '</span>' +
      '<span class="hir-state">' + chip(c) + '</span>' +
      /* A phone's second line: the position, then the source, each kept whole. */
      '<span class="hir-line">' + [c.position, SOURCE[c.source]].filter(Boolean).map(function (x) { return '<span class="nb">' + esc(x) + '</span>'; }).join(' · ') + '</span>' +
      '<span class="hir-go">' + CHEV + '</span>';
    b.addEventListener('click', function () { state.open = c.id; state.pane = 'overview'; setUrl(); openRec(c.id); });
    return b;
  }

  // ---- The record -----------------------------------------------------------
  function openRec(id) {
    var rec = $('hirRec');
    $('hirList').hidden = true; $('hirBar').hidden = true; rec.hidden = false;
    /* Team's strip steps away while a candidate is open, as for a colleague. */
    $('sectionTeam').classList.add('is-candidate');
    if (!state.rec || state.rec.id !== id) UI.skeleton(rec, 4);
    return rpc('hiring_get', { p_id: id }).then(function (r) {
      if (state.open !== id) return;
      var d = r.data || {};
      if (r.error || d.error) {
        if (d.error === 'not-found') { state.open = null; state.rec = null; setUrl(); paint(); msg('hirMsg', 'This candidate no longer exists.', 'err'); return; }
        UI.failLine(rec, 'the candidate', said(r), function () { openRec(id); });
        return;
      }
      state.rec = d.candidate; state.role = d.role; state.people = d.people || []; state.events = d.events || [];
      /* The candidate's interviews, read beside the record; a refused read is
         said in its pane alone. */
      return rpc('hiring_interviews_of', { p_id: id }).then(function (q) {
        if (state.open !== id) return;
        var e = q.data || {};
        state.interviews = q.error || e.error ? null : (e.rows || []);
        paintRec();
      });
    });
  }
  function linkOf(key) { return location.origin + '/careers/?k=' + key; }
  function fact(label, value, cls) {
    return '<div><dt>' + esc(label) + '</dt><dd' + (value ? (cls ? ' class="' + cls + '"' : '') : ' class="is-empty"') + '>' + (value || 'Not set') + '</dd></div>';
  }
  function paintRec() {
    var c = state.rec, rec = $('hirRec'), role = state.role, keeps = role === 'admin' || role === 'owner';
    var removed = !!c.removed_at;
    var menu = (keeps && !removed ? '<button class="kmenu-item" data-g="2" type="button" data-h="edit" role="menuitem">Edit</button>' +
        '<button class="kmenu-item" data-g="5" type="button" data-h="reset" role="menuitem">Reset link</button>' : '') +
      (role === 'admin' ? (removed ? '<button class="kmenu-item" data-g="5" type="button" data-h="restore" role="menuitem">Restore</button>' +
          '<button class="kmenu-item is-danger" data-g="6" type="button" data-h="delete" role="menuitem">Delete</button>'
        : '<button class="kmenu-item is-danger" data-g="6" type="button" data-h="remove" role="menuitem">Remove</button>') : '');
    var cv = c.cv_path ? '<button class="linkbtn" type="button" data-h="cvfile">' + esc(c.cv_name || 'CV') + CHEV.replace('<svg ', '<svg class="ovgo-chev" ') + '</button>'
      : c.cv_url ? '<a class="plink" href="' + esc(window.ADspaceWords.absUrl(c.cv_url) || '#') + '" target="_blank" rel="noopener">' + FILE + '<span>Open CV</span></a>' : '';
    var url = c.link_key ? linkOf(c.link_key) : '';
    var ended = c.link_ends && Date.parse(c.link_ends) <= Date.now();
    var panes = {
      overview: '<section class="readgroup"><div class="readgroup-head"><h4 class="fsec-h">Details</h4></div><dl class="ovfacts">' +
          fact('Email', esc(c.email)) + fact('Phone', c.phone ? esc(c.phone) : '') + fact('Position', esc(c.position)) +
          fact('Source', esc(SOURCE[c.source] || '')) + fact('Added', esc(day(c.created_at))) + fact('CV', cv) +
          fact('Note', c.note ? esc(c.note) : '', 'is-pre') + '</dl></section>' +
        (keeps && !removed ? '<section class="readgroup"><div class="readgroup-head"><h4 class="fsec-h">Candidate page</h4></div>' +
          '<dl class="ovfacts"><div><dt>State</dt><dd>' + (ended ? 'Link ended ' + esc(day(c.link_ends)) : 'Open until ' + esc(day(c.link_ends))) + '</dd></div></dl>' +
          (url && !ended ? '<div class="rec-linktools"><div class="linkbox">' +
            '<input class="input readfield" id="hirLink" readonly aria-label="Candidate page link" value="' + esc(url) + '">' +
            '<button class="btn btn-icon" type="button" data-h="copy">' + COPY + '<span>Copy link</span></button>' +
            '<a class="btn btn-icon" href="' + esc(url) + '" target="_blank" rel="noopener">Preview ' + OUT + '</a>' +
            '</div></div>' : '') + '</section>' : ''),
      interview: interviewPane(c, keeps && !removed && c.stage !== 'hired' && c.stage !== 'closed'),
      people: '<section class="readgroup"><div class="readgroup-head"><h4 class="fsec-h">People</h4>' +
          (role === 'admin' && !removed ? '<button class="btn btn-sm" type="button" data-h="addperson">Add colleague</button>' : '') + '</div>' +
          (state.people.length ? '<div class="hir-people">' + state.people.map(personRow).join('') + '</div>' : '<p class="emptyline">No colleagues.</p>') + '</section>',
      activity: '<section class="readgroup"><div class="readgroup-head"><h4 class="fsec-h">Activity</h4></div><div id="hirLog"></div></section>'
    };
    rec.innerHTML =
      '<button class="backlink" type="button" data-h="back">' + BACK + 'Back</button>' +
      '<div class="panel hir-headcard">' +
        '<div class="rec-id is-nomark hir-head">' +
          '<div class="rec-who"><div class="rec-name"><h2>' + esc(c.name) + '</h2></div><p class="rec-id-meta">' +
            [c.position, SOURCE[c.source]].filter(Boolean).map(function (x) { return '<span class="nb">' + esc(x) + '</span>'; }).join(' · ') +
            (role !== 'admin' ? ' · <span class="nb">' + esc(ROLE[role] || '') + '</span>' : '') + '</p></div>' +
          '<div class="rec-ctl">' + chip(c) +
            (menu ? '<span class="team-act"><button class="kmenu-btn" type="button" data-h="menu" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
              '<div class="kmenu" hidden>' + menu + '</div></span>' : '') +
          '</div></div></div>' +
      '<nav class="rectabs" id="hirTabs" role="tablist" aria-label="Candidate">' + PANES.map(function (x) {
        var on = x[0] === state.pane;
        return '<button class="tab' + (on ? ' is-on' : '') + '" type="button" role="tab" aria-selected="' + on + '" data-pane="' + x[0] + '">' + esc(x[1]) + '</button>';
      }).join('') + '</nav>' +
      '<div class="msg" id="hirRecMsg"></div>' +
      '<div class="panel hir-body" data-swipe="hirTabs">' + PANES.map(function (x) {
        return '<div class="readgroups hir-pane" data-pane="' + x[0] + '"' + (x[0] === state.pane ? '' : ' hidden') + '>' + panes[x[0]] + '</div>';
      }).join('') + '</div>';
    paintLog();
    if ($('hirIvFail')) UI.failLine($('hirIvFail'), 'the interviews', 'Please try again.', function () { openRec(c.id); });
    if (window.ADspaceActs && window.ADspaceActs.scan) window.ADspaceActs.scan(rec);
    if (window.ADspaceMenu && window.ADspaceMenu.tidy) Array.prototype.forEach.call(rec.querySelectorAll('.kmenu'), function (m) { window.ADspaceMenu.tidy(m); });
    wireRec();
  }
  function personRow(p) {
    var acts = state.role === 'admin' && !state.rec.removed_at;
    return '<div class="hir-person" data-id="' + esc(p.id) + '"><span class="hir-person-who"><b>' + esc(p.name) + '</b>' +
      (p.designation ? '<small>' + esc(p.designation) + '</small>' : '') + '</span>' +
      '<span class="chip">' + esc(ROLE[p.role] || '') + '</span>' +
      (acts ? '<span class="team-act"><button class="kmenu-btn" type="button" data-h="menu" aria-label="More actions for ' + esc(p.name) + '" aria-expanded="false">' + DOTS + '</button>' +
        '<div class="kmenu" hidden><button class="kmenu-item" data-g="2" type="button" data-h="role" data-id="' + esc(p.id) + '" role="menuitem">' +
          (p.role === 'owner' ? 'Make interviewer' : 'Make owner') + '</button>' +
        '<button class="kmenu-item is-danger" data-g="6" type="button" data-h="unperson" data-id="' + esc(p.id) + '" role="menuitem">Remove</button></div></span>' : '') +
      '</div>';
  }
  /* ---- Interviews ---------------------------------------------------------
     An invitation of up to three times, all within the window setting (3
     days); the candidate chooses one on their page, or asks for others; the
     part or the Owner approves, a Google Meet booked on the shared calendar
     where it is online, and the candidate is emailed each step (HR-SPEC.md
     decision 2). */
  var IV_STATE = { invited: ['Waiting for the candidate', 'is-warn'], picked: ['Time chosen', 'is-warn'], none: ['Other times asked for', 'is-danger'],
    confirmed: ['Confirmed', 'is-ok'], cancelled: ['Cancelled', 'is-off'] };
  var MAIL = { sent: 'Emailed', unknown: 'Not confirmed', failed: 'Not emailed' };
  function when(iso) { return window.ADspaceClock.date(iso) + ', ' + window.ADspaceClock.clock(iso); }
  function interviewPane(c, can) {
    if (state.interviews == null) return '<section class="readgroup"><div id="hirIvFail"></div></section>';
    var open = state.interviews.filter(function (i) { return i.state !== 'cancelled'; })[0];
    var invite = can && (!open || open.state === 'none' || open.state === 'confirmed');
    return '<section class="readgroup"><div class="readgroup-head"><h4 class="fsec-h">Interviews</h4>' +
      (invite ? '<button class="btn btn-sm' + (open ? ' btn-quiet' : '') + '" type="button" data-h="invite">' + (open ? 'Send new times' : 'Invite') + '</button>' : '') + '</div>' +
      (state.interviews.length ? '<div class="hir-ivs">' + state.interviews.map(function (i) { return ivCard(i, can); }).join('') + '</div>'
        : '<p class="emptyline">No interviews.</p>') + '</section>';
  }
  function ivCard(i, can) {
    var st = IV_STATE[i.state] || IV_STATE.invited, live = can && i.state !== 'cancelled';
    var times = (i.slots || []).map(function (t, n) {
      var chosen = i.picked === n + 1;
      return '<li' + (chosen ? ' class="is-on"' : '') + '><span class="nb">' + esc(when(t)) + '</span>' + (chosen ? ' <span class="chip">Chosen</span>' : '') + '</li>';
    }).join('');
    var mail = function (k, label) { var v = i[k + '_mail']; return v ? fact(label, esc(MAIL[v] || v) + ' · ' + esc(when(i[k + '_mail_at'])), v === 'sent' ? '' : 'is-warn') : ''; };
    var acts = '';
    if (live && i.state === 'picked') acts += '<button class="btn btn-sm btn-go" type="button" data-h="ivapprove" data-id="' + esc(i.id) + '">Approve</button>';
    if (live && i.state === 'confirmed' && i.mode === 'online' && !i.meeting_link) acts += '<button class="btn btn-sm btn-go" type="button" data-h="ivmeet" data-id="' + esc(i.id) + '">Create Google Meet</button>';
    if (live && i.state === 'confirmed' && (i.meeting_link || i.mode === 'office') && i.confirm_mail !== 'sent')
      acts += '<button class="btn btn-sm" type="button" data-h="ivmail" data-kind="confirm" data-id="' + esc(i.id) + '">Email confirmation</button>';
    if (live && i.state === 'invited' && i.invite_mail !== 'sent')
      acts += '<button class="btn btn-sm" type="button" data-h="ivmail" data-kind="invite" data-id="' + esc(i.id) + '">Email invitation</button>';
    var menu = live ? '<span class="team-act"><button class="kmenu-btn" type="button" data-h="menu" aria-label="More actions for interview ' + i.round + '" aria-expanded="false">' + DOTS + '</button>' +
      '<div class="kmenu" hidden><button class="kmenu-item" data-g="5" type="button" data-h="ivcancel" data-id="' + esc(i.id) + '" role="menuitem">Cancel</button></div></span>' : '';
    return '<div class="hir-iv' + (i.state === 'cancelled' ? ' is-off' : '') + '"><div class="hir-iv-head"><b>Interview ' + esc(i.round) + '</b>' +
        '<span class="hir-iv-ctl"><span class="chip-state ' + st[1] + '">' + esc(st[0]) + '</span>' + menu + '</span></div>' +
      '<dl class="ovfacts">' +
        fact(i.picked ? 'Times offered' : 'Times', '<ul class="hir-times">' + times + '</ul>') +
        fact('Length', esc(i.minutes) + ' minutes') +
        fact('Where', i.mode === 'online' ? (i.meeting_link ? '<a class="plink" href="' + esc(i.meeting_link) + '" target="_blank" rel="noopener"><span>Google Meet</span></a>' : 'Google Meet') : 'At the office') +
        (i.note ? fact('Note to the candidate', esc(i.note), 'is-pre') : '') +
        (i.candidate_note ? fact('Candidate\'s note', esc(i.candidate_note), 'is-pre') : '') +
        fact('Invited by', esc([i.invited_by, when(i.invited_at)].filter(Boolean).join(' · '))) +
        (i.approved_at ? fact('Approved by', esc([i.approved_by, when(i.approved_at)].filter(Boolean).join(' · '))) : '') +
        mail('invite', 'Invitation') + mail('confirm', 'Confirmation') +
      '</dl>' + (acts ? '<div class="hir-iv-acts">' + acts + '</div>' : '') + '</div>';
  }
  function fnCall(name, body) {
    return db.functions.invoke(name, { body: body }).then(function (r) {
      if (r.error) return { error: 'not-sent' };
      return r.data || {};
    }).catch(function () { return { error: 'not-sent' }; });
  }
  function sendMail(id, kind) {
    return fnCall('hiring-mail', { interviewId: id, kind: kind }).then(function (d) {
      if (d.error) { msg('hirRecMsg', SAID[d.error] || said({ data: d }), d.error === 'unknown' ? 'warn' : 'err'); return false; }
      return true;
    });
  }
  function busyLine() {
    /* The online meetings already on the shared calendar over the next two
       weeks, named first so the times keyed avoid them. */
    var C = window.ADspaceClock, from = new Date(), to = new Date(Date.now() + 14 * 86400000);
    return fnCall('meet-create', { action: 'busy', from: from.toISOString(), to: to.toISOString() }).then(function (d) {
      if (d.error || !d.busy) return 'The shared calendar could not be read. Check it before choosing times.';
      if (!d.busy.length) return 'No online meetings are booked in the next two weeks.';
      return 'Online meetings already booked: ' + d.busy.slice(0, 12).map(function (b) {
        return C.date(b.start) + ', ' + C.clock(b.start) + (b.end ? ' to ' + C.clock(b.end) : '');
      }).join('; ') + (d.busy.length > 12 ? '; and ' + (d.busy.length - 12) + ' more.' : '.');
    });
  }
  function invite(btn) {
    var c = state.rec, C = window.ADspaceClock, today = C.today(), key = newKey();
    if (btn) btn.disabled = true;
    busyLine().then(function (line) {
      if (btn) btn.disabled = false;
      var f = [];
      [1, 2, 3].forEach(function (n) {
        f.push({ name: 'd' + n, label: 'Time ' + n + ' date', type: 'date', min: today, half: true, required: n === 1, hint: n === 1 ? '' : 'Optional', head: n === 1 ? 'Times' : '' });
        f.push({ name: 't' + n, label: 'Time ' + n, type: 'time', half: true, required: n === 1, hint: n === 1 ? '' : 'Optional' });
      });
      f[0].note = line;
      f.push({ name: 'minutes', label: 'Length', choices: [['30', '30 minutes'], ['45', '45 minutes'], ['60', '60 minutes'], ['90', '90 minutes']], seg: true, value: '45', head: 'Interview' });
      f.push({ name: 'mode', label: 'Where', choices: [['online', 'Google Meet'], ['office', 'At the office']], seg: true, value: 'online' });
      f.push({ name: 'note', label: 'Note to the candidate', rows: 2, required: false, placeholder: 'Optional' });
      var slots = function (v) {
        var out = [];
        [1, 2, 3].forEach(function (n) { if (v['d' + n] && v['t' + n]) out.push(C.at(v['d' + n], v['t' + n])); });
        return out;
      };
      window.ADspaceConfirm.ask({ title: 'Invite ' + c.name, go: 'Send invitation', wait: true, fields: f,
        body: 'The candidate will choose one of these times on their page.',
        check: function (v) {
          var s = slots(v);
          if (!s.length) return SAID['bad-slots'];
          if ([2, 3].some(function (n) { return Boolean(v['d' + n]) !== Boolean(v['t' + n]); })) return 'Enter a date and a time for each interview time.';
          if (s.some(function (t) { return t.getTime() < Date.now() + 3600000; })) return SAID['slot-past'];
          if (String(v.note || '').trim().length > 500) return 'Shorten the note to 500 characters.';
          return '';
        } },
      function (v) {
        return rpc('hiring_invite', { p_id: c.id, p_slots: slots(v).map(function (t) { return t.toISOString(); }), p_minutes: Number(v.minutes),
          p_mode: v.mode, p_note: String(v.note || '').trim() || null, p_idem: key }).then(function (r) {
          var d = r.data || {};
          if (d.error === 'slot-window') return 'Choose times within ' + d.days + ' days of each other.';
          if (r.error || d.error) return said(r);
          state.pane = 'interview';
          sendMail(d.id, 'invite').then(function (ok) { openRec(c.id).then(function () { if (ok) msg('hirRecMsg', 'Invitation sent.', 'ok'); }); });
          return '';
        });
      });
    });
  }
  function approve(id) {
    var i = state.interviews.filter(function (x) { return x.id === id; })[0], c = state.rec;
    if (!i) return;
    var t = i.slots[i.picked - 1];
    window.ADspaceConfirm.ask({ title: 'Approve interview?', go: 'Approve', wait: true,
      body: when(t) + ', ' + i.minutes + ' minutes, ' + (i.mode === 'online' ? 'by Google Meet. A Google Meet will be created on the shared calendar' : 'at the office. ' + c.name + ' will be emailed the confirmation') +
        (i.mode === 'online' ? ', and ' + c.name + ' will be emailed the confirmation.' : '.') },
    function () {
      return rpc('hiring_interview_approve', { p_interview: id }).then(function (r) {
        if (r.error || (r.data || {}).error) return said(r);
        meetThenMail(id, i.mode);
        return '';
      });
    });
  }
  function meetThenMail(id, mode) {
    var c = state.rec;
    var step = mode === 'online' ? fnCall('meet-create', { interviewId: id, action: 'create' }) : Promise.resolve({});
    step.then(function (m) {
      if (m.error) {
        openRec(c.id).then(function () {
          msg('hirRecMsg', m.error === 'slot-taken' && m.start ? 'Another online meeting is booked from ' + window.ADspaceClock.clock(m.start) +
            (m.end ? ' to ' + window.ADspaceClock.clock(m.end) : '') + '. Cancel this interview and send the candidate new times.' : (SAID[m.error] || SAID['google-refused']), 'err');
        });
        return;
      }
      sendMail(id, 'confirm').then(function (ok) { openRec(c.id).then(function () { if (ok) msg('hirRecMsg', 'Confirmation sent.', 'ok'); }); });
    });
  }
  function cancelIv(id) {
    var i = state.interviews.filter(function (x) { return x.id === id; })[0], c = state.rec;
    if (!i) return;
    window.ADspaceConfirm.ask({ title: 'Cancel interview?', go: 'Cancel interview', tone: 'warn', wait: true,
      body: (i.meeting_link ? 'Its Google Meet will be removed from the shared calendar. ' : '') + 'The candidate will not be emailed. Tell the candidate, or send new times.' },
    function () {
      var off = i.meeting_link ? fnCall('meet-create', { interviewId: id, action: 'delete' }) : Promise.resolve({});
      return off.then(function (m) {
        if (m.error) return SAID[m.error] || SAID['google-refused'];
        return rpc('hiring_interview_cancel', { p_interview: id }).then(function (r) {
          if (r.error || (r.data || {}).error) return said(r);
          openRec(c.id); return '';
        });
      });
    });
  }

  var WORD = { 'candidate.added': 'Candidate added', 'candidate.invited': 'Invitation sent', 'candidate.interview': 'Interview updated',
    'candidate.email': 'Email to the candidate', 'candidate.edited': 'Details edited', 'candidate.people': 'People changed',
    'candidate.link': 'Link changed', 'candidate.removed': 'Candidate removed', 'candidate.restored': 'Candidate restored' };
  function paintLog() {
    var host = $('hirLog');
    if (!host || !window.ADspaceRecords) return;
    window.ADspaceRecords.paint(host, state.events.map(function (e) {
      return { at: e.created_at, who: e.actor, what: WORD[e.action] || 'Changed', key: state.rec.id, detail: e.detail || '',
        tone: e.action === 'candidate.removed' ? 'is-danger' : '' };
    }), { empty: 'No entries.' });
  }
  function showPane(k, push) {
    if (!paneOk(k) || k === state.pane) return;
    state.pane = k;
    Array.prototype.forEach.call(document.querySelectorAll('#hirTabs .tab'), function (t) {
      var on = t.getAttribute('data-pane') === k;
      t.classList.toggle('is-on', on); t.setAttribute('aria-selected', String(on));
    });
    Array.prototype.forEach.call(document.querySelectorAll('#hirRec .hir-pane'), function (p) { p.hidden = p.getAttribute('data-pane') !== k; });
    if (push && bridge.pushUrl) bridge.pushUrl(); else setUrl();
  }
  function shutMenus() {
    Array.prototype.forEach.call(document.querySelectorAll('#hirRec .kmenu'), function (m) { m.hidden = true; });
    Array.prototype.forEach.call(document.querySelectorAll('#hirRec .kmenu-btn'), function (b) { b.setAttribute('aria-expanded', 'false'); });
  }
  function wireRec() {
    var rec = $('hirRec'), c = state.rec;
    var on = function (a, fn) { Array.prototype.forEach.call(rec.querySelectorAll('[data-h="' + a + '"]'), function (b) { b.addEventListener('click', function (e) { e.stopPropagation(); shutMenus(); fn(b); }); }); };
    Array.prototype.forEach.call(rec.querySelectorAll('#hirTabs .tab'), function (t) {
      t.addEventListener('click', function () { showPane(t.getAttribute('data-pane'), true); });
    });
    Array.prototype.forEach.call(rec.querySelectorAll('[data-h="menu"]'), function (b) {
      b.addEventListener('click', function (e) {
        e.stopPropagation();
        var m = b.parentNode.querySelector('.kmenu'), open = m.hidden;
        shutMenus(); m.hidden = !open; b.setAttribute('aria-expanded', String(open));
        if (open) window.ADspaceMenu.place(b, m);
      });
    });
    on('back', function () { state.open = null; state.rec = null; state.pane = 'overview'; setUrl(); paint(); });
    on('edit', function () { openSheet(c); });
    on('copy', function (b) { if (window.ADspaceCopy) window.ADspaceCopy.to(b, $('hirLink').value); });
    on('cvfile', function (b) { openCv(b); });
    on('reset', function () {
      window.ADspaceConfirm.ask({ title: 'Reset link?', body: 'The link sent before will stop working. A new link will be created.', go: 'Reset link', tone: 'warn', wait: true },
        function () {
          return rpc('hiring_link', { p_id: c.id, p_reset: true }).then(function (r) {
            if (r.error || (r.data || {}).error) return said(r);
            openRec(c.id); return '';
          });
        });
    });
    on('remove', function () {
      rpc('hiring_remove', { p_id: c.id, p_restore: false }).then(function (r) {
        if (r.error || (r.data || {}).error) { msg('hirRecMsg', said(r), 'err'); return; }
        state.open = null; state.rec = null; setUrl();
        load().then(function () {
          if (bridge.undoHere) bridge.undoHere('Candidate removed.', function () {
            return rpc('hiring_remove', { p_id: c.id, p_restore: true }).then(function () { load(); });
          }, $('hirMsg'));
        });
      });
    });
    on('restore', function () {
      rpc('hiring_remove', { p_id: c.id, p_restore: true }).then(function (r) {
        if (r.error || (r.data || {}).error) { msg('hirRecMsg', said(r), 'err'); return; }
        state.rows = null; load();
      });
    });
    on('delete', function () {
      state.deleting = true;
      window.ADspaceConfirm.ask({ title: 'Delete', tone: 'danger', go: 'Delete', wait: true,
        body: c.name + ', their details, CV and history will be deleted. This cannot be undone.',
        field: { name: 'name', label: 'Type the candidate\'s name', match: c.name } },
      function (v) {
        return rpc('hiring_delete', { p_id: c.id, p_name: v.name }).then(function (r) {
          state.deleting = false;
          var d = r.data || {};
          if (r.error || d.error) return said(r);
          if (d.cv_path) db.storage.from(BUCKET).remove([d.cv_path]).then(function () {}, function () {});
          state.open = null; state.rec = null; setUrl(); load();
          return '';
        });
      });
    });
    on('addperson', addPerson);
    on('invite', invite);
    on('ivapprove', function (b) { approve(b.getAttribute('data-id')); });
    on('ivmeet', function (b) { b.disabled = true; meetThenMail(b.getAttribute('data-id'), 'online'); });
    on('ivmail', function (b) {
      b.disabled = true;
      sendMail(b.getAttribute('data-id'), b.getAttribute('data-kind')).then(function (ok) {
        openRec(c.id).then(function () { if (ok) msg('hirRecMsg', 'Sent.', 'ok'); });
      });
    });
    on('ivcancel', function (b) { cancelIv(b.getAttribute('data-id')); });
    on('role', function (b) {
      var p = state.people.filter(function (x) { return x.id === b.getAttribute('data-id'); })[0];
      if (!p) return;
      rpc('hiring_person_set', { p_id: c.id, p_member: p.id, p_role: p.role === 'owner' ? 'interviews' : 'owner' }).then(function (r) {
        if (r.error || (r.data || {}).error) { msg('hirRecMsg', said(r), 'err'); return; }
        openRec(c.id);
      });
    });
    on('unperson', function (b) {
      var p = state.people.filter(function (x) { return x.id === b.getAttribute('data-id'); })[0];
      if (!p) return;
      rpc('hiring_person_remove', { p_id: c.id, p_member: p.id }).then(function (r) {
        var d = r.data || {};
        if (r.error || d.error) { msg('hirRecMsg', said(r), 'err'); return; }
        openRec(c.id).then(function () {
          if (bridge.undoHere) bridge.undoHere(p.name + ' removed.', function () {
            return rpc('hiring_person_set', { p_id: c.id, p_member: p.id, p_role: d.role }).then(function () { openRec(c.id); });
          }, $('hirRecMsg'));
        });
      });
    });
  }
  /* The tab is opened at the press, or a browser blocks a window opened
     after the signed link comes back (as the Handbook opens a file). */
  function openCv(btn) {
    var w = window.open('', '_blank');
    btn.disabled = true;
    db.storage.from(BUCKET).createSignedUrl(state.rec.cv_path, SIGN_SECS).then(function (r) {
      btn.disabled = false;
      var url = r && r.data && (r.data.signedUrl || r.data.signedURL);
      if (r.error || !url) throw r.error || new Error('no-url');
      if (w) { try { w.opener = null; } catch (e) { /* cross-origin */ } w.location.href = url; }
      else location.href = url;
    }).catch(function () {
      btn.disabled = false;
      if (w) w.close();
      msg('hirRecMsg', 'The CV could not be opened. Please try again.', 'err');
    });
  }
  /* The colleagues offered: active, code first, never a system account, and
     never one already on the candidate. */
  function team() {
    if (state.team) return Promise.resolve(state.team);
    return db.from('team_members').select('id, name, staff_code, active').eq('active', true).then(function (r) {
      if (r.error) throw r.error;
      state.team = (r.data || []).filter(function (m) { return !(bridge.isSystem && bridge.isSystem(m.id)); });
      return state.team;
    });
  }
  function addPerson() {
    var c = state.rec;
    team().then(function (list) {
      var held = state.people.map(function (p) { return p.id; });
      var free = list.filter(function (m) { return held.indexOf(m.id) < 0; });
      var F = window.ADspaceForm, named = F && F.named ? F.named : null;
      var opts = free.slice().sort(F && F.sequence ? F.sequence('staff_code') : undefined).map(function (m) {
        return [m.id, named ? named(m.staff_code, m.name) : m.name];
      });
      if (!opts.length) { msg('hirRecMsg', 'Every active colleague has already been added to this candidate.', 'warn'); return; }
      window.ADspaceConfirm.ask({ title: 'Add colleague', go: 'Add', wait: true,
        fields: [{ name: 'member', label: 'Colleague', choices: [['', 'Choose a colleague']].concat(opts), required: true },
                 { name: 'role', label: 'Role', choices: [['interviews', 'Interviewer'], ['owner', 'Owner']], seg: true, value: 'interviews',
                   note: 'The owner decides on the candidate and sends the messages. An interviewer sees the candidate and enters scores.' }] },
      function (v) {
        if (!v.member) return 'Choose a colleague.';
        return rpc('hiring_person_set', { p_id: c.id, p_member: v.member, p_role: v.role }).then(function (r) {
          if (r.error || (r.data || {}).error) return said(r);
          openRec(c.id); return '';
        });
      });
    }).catch(function () { msg('hirRecMsg', 'The colleagues could not be loaded. Please try again.', 'err'); });
  }

  // ---- Add candidate and Edit -----------------------------------------------
  var FIELDS = [['name', 'hirName'], ['email', 'hirEmail'], ['phone', 'hirPhone'], ['position', 'hirPosition'],
    ['source', 'hirSource'], ['cv_url', 'hirCvUrl'], ['note', 'hirNote']];
  function openSheet(c) {
    state.editing = c ? { id: c.id, updated_at: c.updated_at } : { idem: newKey() };
    FIELDS.forEach(function (x) { $(x[1]).value = c && c[x[0]] != null ? c[x[0]] : ''; });
    $('hirCvFile').value = '';
    $('hirCvHeld').hidden = !(c && c.cv_path);
    $('hirCvHeld').textContent = c && c.cv_path ? 'Held: ' + (c.cv_name || 'CV') + '. A file chosen replaces it.' : '';
    $('hirSheetTitle').textContent = c ? 'Edit candidate' : 'Add candidate';
    $('hirSheetGo').textContent = c ? 'Save' : 'Add candidate';
    msg('hirSheetMsg', '');
    $('hirSheet').hidden = false;
  }
  function shutSheet() { $('hirSheet').hidden = true; state.editing = null; }
  function newKey() {
    var a = new Uint8Array(12), s = '';
    (window.crypto || window.msCrypto).getRandomValues(a);
    for (var i = 0; i < a.length; i++) s += ('0' + a[i].toString(16)).slice(-2);
    return 'hir-' + s;
  }
  function saveSheet() {
    var ed = state.editing;
    if (!ed) return;
    var v = {};
    FIELDS.forEach(function (x) { v[x[0]] = $(x[1]).value.trim(); });
    var need = [['name', 'Enter the candidate\'s name.'], ['email', 'Enter a valid email address.'], ['position', 'Enter the position.'], ['source', 'Choose a source.']]
      .filter(function (x) { return !v[x[0]]; })[0];
    if (need) { msg('hirSheetMsg', need[1], 'err'); $(FIELDS.filter(function (x) { return x[0] === need[0]; })[0][1]).focus(); return; }
    if (!window.ADspaceWords.emailOk(v.email)) { msg('hirSheetMsg', 'Enter a valid email address.', 'err'); $('hirEmail').focus(); return; }
    if (v.cv_url && !window.ADspaceWords.absUrl(v.cv_url)) { msg('hirSheetMsg', 'Enter a web address that starts with https://.', 'err'); $('hirCvUrl').focus(); return; }
    var file = $('hirCvFile').files && $('hirCvFile').files[0];
    if (file && !/\.(pdf|docx?)$/i.test(file.name)) { msg('hirSheetMsg', 'Choose a PDF or Word file.', 'err'); return; }
    if (file && file.size > MAX_MB * 1024 * 1024) { msg('hirSheetMsg', 'Choose a file of ' + MAX_MB + ' MB or less.', 'err'); return; }
    var go = $('hirSheetGo');
    go.disabled = true;
    var write = ed.id ? rpc('hiring_save', { p_id: ed.id, p_values: v, p_expected: ed.updated_at || null })
      : rpc('hiring_add', { p_values: v, p_idem: ed.idem });
    write.then(function (r) {
      var d = r.data || {};
      if (r.error || d.error) {
        go.disabled = false;
        msg('hirSheetMsg', said(r), 'err');
        if (d.error === 'stale' && ed.id) { openRec(ed.id); shutSheet(); }
        var k = { 'bad-name': 'hirName', 'bad-email': 'hirEmail', 'taken': 'hirEmail', 'bad-phone': 'hirPhone', 'bad-position': 'hirPosition', 'bad-source': 'hirSource', 'bad-cv': 'hirCvUrl', 'too-long': 'hirNote' }[d.error];
        if (k) $(k).focus();
        return;
      }
      var id = ed.id || d.id;
      var then = function (warn) {
        go.disabled = false;
        shutSheet();
        state.open = id; setUrl();
        load().then(function () { if (warn) msg('hirRecMsg', warn, 'warn'); });
      };
      if (!file) { then(); return; }
      uploadCv(id, file).then(function () { then(); }, function () {
        then('The candidate was saved, but the CV file was not uploaded. Choose it again in Edit.');
      });
    });
  }
  /* A CV file is kept in the private bucket under the candidate's own
     folder, then named on the candidate; the file it replaces is removed. */
  function uploadCv(id, file) {
    var safe = file.name.replace(/[^A-Za-z0-9._-]+/g, '-').replace(/^-+|-+$/g, '').slice(-120) || 'cv.pdf';
    var path = id + '/' + Date.now() + '-' + safe;
    var was = state.rec && state.rec.id === id ? state.rec.cv_path : null;
    return db.storage.from(BUCKET).upload(path, file, { contentType: file.type || undefined, upsert: false }).then(function (r) {
      if (r.error) throw r.error;
      return rpc('hiring_save', { p_id: id, p_values: { cv_path: path, cv_name: file.name.slice(0, 200) }, p_expected: null });
    }).then(function (r) {
      if (r.error || (r.data || {}).error) throw new Error('not-saved');
      if (was && was !== path) db.storage.from(BUCKET).remove([was]).then(function () {}, function () {});
    });
  }

  window.ADspaceHiring = { enter: enter, urlState: urlState };
  /* Team opened on Hiring before this script arrived. */
  if ($('teamHiringPane') && !$('teamHiringPane').hidden) enter();
})();
