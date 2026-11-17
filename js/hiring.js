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
    'denied': 'You do not have permission to do this. Please ask an admin.', 'send-off': window.ADspaceWords.line.emailSendOff, 'not-found': 'This candidate no longer exists.',
    'bad-name': 'Enter a name of 2 to 120 characters.', 'bad-email': 'Enter a valid email address.',
    'bad-phone': 'Enter a phone number of 8 to 15 digits, for example 012-345 6789.', 'bad-position': 'Enter the position.',
    'bad-source': 'Choose a source.', 'bad-cv': 'Enter a web address that starts with https://.', 'too-long': 'Shorten the note to 2,000 characters.',
    'stale': 'Not saved. This record was changed by someone else. The latest version is now shown.',
    'bad-role': 'Choose Owner or Interviewer.', 'bad-colleague': 'Choose an active colleague.', 'not-removed': 'Remove the candidate first.',
    'has-contract': 'This candidate holds a signed offer or contract and cannot be deleted. The candidate stays removed.',
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
    'meet-pending': 'Google is still creating the Google Meet link. Press Create Google Meet again shortly.',
    'bad-recommend': 'Choose a recommendation.', 'bad-outcome': 'Please refresh the page and try again.',
    'no-email': 'This decision sends no email.', 'bad-criteria': 'Enter 3 to 8 criteria, each 2 to 60 characters, none twice.',
    'bad-position': 'Enter a position of 2 to 80 characters.', 'standard': 'The Standard scorecard cannot be deleted.'
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
  var PANES = [['overview', 'Overview'], ['interview', 'Interview'], ['scores', 'Scores'], ['offer', 'Offer'], ['people', 'People'], ['activity', 'Activity']];
  /* Offer (step D) is the part's and the Owner's alone. */
  function panesFor(role) { return PANES.filter(function (x) { return x[0] !== 'offer' || role === 'admin' || role === 'owner'; }); }
  function paneOk(k) { return panesFor(state.role).some(function (x) { return x[0] === k; }); }
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
    state.pane = state.open && PANES.some(function (x) { return x[0] === q.get('ctab'); }) ? q.get('ctab') : 'overview';
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
      if (state.admin && !state.swept) sweepFiles();
      $('hirPositions').innerHTML = uniq(state.rows.map(function (c) { return c.position; })).map(function (p) { return '<option value="' + esc(p) + '">'; }).join('');
      if (state.open) openRec(state.open); else paint();
    });
  }
  /* A candidate removed in their time (hiring_retention) leaves their CV file
     queued; SQL cannot take a file out of Storage, so the part's console
     does, once a visit, quietly. */
  function sweepFiles() {
    state.swept = true;
    rpc('hiring_files_gone_list', {}).then(function (r) {
      var paths = ((r.data || {}).paths || []);
      if (!paths.length) return;
      db.storage.from(BUCKET).remove(paths).then(function (x) {
        if (x && x.error) return;
        rpc('hiring_files_gone_done', { p_paths: paths });
      }, function () {});
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
        return Promise.all([rpc('hiring_outcome_of', { p_id: id }), rpc('hiring_sheets_of', { p_id: id })]).then(function (pair) {
          if (state.open !== id) return;
          var o = pair[0], od = o.data || {}, sd = pair[1].data || {};
          state.outcome = o.error || od.error ? null : od;
          /* The interview sheets; a read that fails leaves them out. */
          state.sheets = pair[1].error || sd.error ? [] : (sd.sheets || []);
          if (state.role !== 'admin' && state.role !== 'owner') { state.docs = []; paintRec(); return; }
          return rpc('hiring_docs_of', { p_id: id }).then(function (x) {
            if (state.open !== id) return;
            var xd = x.data || {};
            state.docs = x.error || xd.error ? null : (xd.rows || []);
            /* Make colleague (step E1): whether both documents are confirmed,
               or the colleague the candidate became. A read that fails
               leaves the card out. */
            return rpc('hiring_hire_state', { p_id: id }).then(function (h) {
              if (state.open !== id) return;
              var hd = h.data || {};
              state.hire = h.error || hd.error ? null : hd;
              paintRec();
            });
          });
        });
      });
    });
  }
  function linkOf(key) { return location.origin + '/careers/?k=' + key; }
  function fact(label, value, cls) {
    return '<div><dt>' + esc(label) + '</dt><dd' + (value ? (cls ? ' class="' + cls + '"' : '') : ' class="is-empty"') + '>' + (value || 'Not set') + '</dd></div>';
  }
  function paintRec() {
    var c = state.rec, rec = $('hirRec'), role = state.role, keeps = role === 'admin' || role === 'owner';
    if (!paneOk(state.pane)) state.pane = 'overview';
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
      scores: scoresPane(c, keeps && !removed),
      offer: keeps ? hireCard() + docsPane(c, !removed) : '',
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
      '<nav class="rectabs" id="hirTabs" role="tablist" aria-label="Candidate">' + panesFor(role).map(function (x) {
        var on = x[0] === state.pane;
        return '<button class="tab' + (on ? ' is-on' : '') + '" type="button" role="tab" aria-selected="' + on + '" data-pane="' + x[0] + '">' + esc(x[1]) + '</button>';
      }).join('') + '</nav>' +
      '<div class="msg" id="hirRecMsg"></div>' +
      '<div class="panel hir-body" data-swipe="hirTabs">' + panesFor(role).map(function (x) {
        return '<div class="readgroups hir-pane" data-pane="' + x[0] + '"' + (x[0] === state.pane ? '' : ' hidden') + '>' + panes[x[0]] + '</div>';
      }).join('') + '</div>';
    paintLog();
    if ($('hirScFail')) UI.failLine($('hirScFail'), 'the scores', 'Please try again.', function () { openRec(c.id); });
    if ($('hirIvFail')) UI.failLine($('hirIvFail'), 'the interviews', 'Please try again.', function () { openRec(c.id); });
    if ($('hirDocFail')) UI.failLine($('hirDocFail'), 'the documents', 'Please try again.', function () { openRec(c.id); });
    if (window.ADspaceActs && window.ADspaceActs.scan) window.ADspaceActs.scan(rec);
    if (window.ADspaceMenu && window.ADspaceMenu.tidy) Array.prototype.forEach.call(rec.querySelectorAll('.kmenu'), function (m) { window.ADspaceMenu.tidy(m); });
    /* The strip slides its thumb and fades the edge that has more beyond
       it on a narrow phone, as every record's strip does. */
    if ($('hirTabs') && window.ADspaceForm && window.ADspaceForm.thumb) window.ADspaceForm.thumb($('hirTabs'));
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
  /* ---- Scores and the decision (step C) -------------------------------------
     Everyone on a candidate scores them against the position's scorecard
     (Standard for any other), 1 to 5 a criterion, with a recommendation; the
     part or the Owner decides Proceed, Keep in talent pool or Not proceed,
     Reopen the way back. The decision's note stays with the team. */
  var REC = { proceed: 'Proceed', pool: 'Keep in talent pool', not: 'Not proceed' };
  var OUTCOME = { proceed: ['Proceed', 'is-ok'], pool: ['Talent pool', 'is-off'], not: ['Not proceed', 'is-off'] };
  var POOL = { asked: 'Waiting for the candidate to agree', yes: 'Agreed', no: 'Declined' };
  function scoresPane(c, keeps) {
    var o = state.outcome;
    if (!o) return '<section class="readgroup"><div id="hirScFail"></div></section>';
    var crit = o.scorecard.criteria || [], out = o.outcome || {}, open = c.stage !== 'hired' && c.stage !== 'closed';
    var mine = o.scores.filter(function (x) { return x.mine; })[0];
    var sheets = state.sheets || [], mySheet = sheets.filter(function (x) { return x.mine; })[0], qs = sheetQs(c);
    /* A colleague's scores and their sheet are one card. */
    var people = [];
    o.scores.forEach(function (x) { people.push({ id: x.id, name: x.name, score: x }); });
    sheets.forEach(function (x) {
      var p = people.filter(function (y) { return y.id === x.id; })[0];
      if (p) p.sheet = x; else people.push({ id: x.id, name: x.name, sheet: x });
    });
    var decide = '';
    if (out.outcome) {
      var st = OUTCOME[out.outcome];
      decide = '<dl class="ovfacts">' + fact('Decision', '<span class="chip-state ' + st[1] + '">' + esc(st[0]) + '</span>') +
        fact('Decided by', esc([out.by, out.at ? when(out.at) : ''].filter(Boolean).join(' · '))) +
        (out.note ? fact('Note', esc(out.note), 'is-pre') : '') +
        (out.outcome === 'pool' ? fact('Talent pool', esc(POOL[out.pool_consent] || '') + (out.pool_until ? ' · until ' + esc(day(out.pool_until)) : '')) : '') +
        (out.mail ? fact('Email', esc(MAIL[out.mail] || out.mail) + ' · ' + esc(when(out.mail_at)), out.mail === 'sent' ? '' : 'is-warn') : '') + '</dl>' +
        (keeps ? '<div class="hir-iv-acts">' + ((out.outcome === 'pool' || out.outcome === 'not') && out.mail !== 'sent'
            ? '<button class="btn btn-sm" type="button" data-h="outmail">Email the candidate</button>' : '') +
          (c.stage !== 'hired' ? '<button class="btn btn-sm btn-quiet" type="button" data-h="reopen">Reopen</button>' : '') + '</div>' : '');
    } else if (keeps && open) {
      decide = '<div class="hir-decide"><button class="btn btn-sm" type="button" data-h="decide" data-o="not">Not proceed</button>' +
        '<button class="btn btn-sm" type="button" data-h="decide" data-o="pool">Keep in talent pool</button>' +
        '<button class="btn btn-sm btn-go" type="button" data-h="decide" data-o="proceed">Proceed</button></div>';
    } else decide = '<p class="emptyline">Not decided.</p>';
    /* Each criterion's average over every colleague's scores. */
    var avg = crit.map(function (k) {
      var v = o.scores.map(function (x) { return Number((x.scores || {})[k]); }).filter(function (n) { return n > 0; });
      return [k, v.length ? Math.round(v.reduce(function (a, b) { return a + b; }, 0) / v.length * 10) / 10 : null];
    });
    return '<section class="readgroup"><div class="readgroup-head"><h4 class="fsec-h">Decision</h4></div>' + decide + '</section>' +
      '<section class="readgroup"><div class="readgroup-head"><h4 class="fsec-h">Interviews</h4>' +
        (open ? '<button class="btn btn-sm' + (mine || mySheet ? ' btn-quiet' : '') + '" type="button" data-h="score">Open sheet</button>' : '') + '</div>' +
      '<p class="hir-card-line">' + esc(o.scorecard.standard ? 'Standard scorecard' : o.scorecard.position + ' scorecard') + ' · 1 to 5 per criterion</p>' +
      (people.length ? (o.scores.length ? '<dl class="ovfacts">' + avg.map(function (a) { return fact(a[0], a[1] == null ? '' : a[1].toFixed(1)); }).join('') + '</dl>' : '') +
        '<div class="hir-scores">' + people.map(function (p) {
          var x = p.score, sh = p.sheet || {}, a = sh.answers || {};
          var read = qs.filter(function (q) { return a[q[0]]; });
          return '<div class="hir-score"><div class="hir-iv-head"><b>' + esc(p.name) + '</b><span class="hir-iv-ctl">' +
            (sh.rating ? '<span class="hir-rating">' + esc(sh.rating) + '/10</span>' : '') +
            (x ? '<span class="hir-total">' + esc(Number(x.total).toFixed(1)) + '</span><span class="chip">' + esc(REC[x.recommend] || '') + '</span>' : '') +
            (x && x.mine && open ? '<span class="team-act"><button class="kmenu-btn" type="button" data-h="menu" aria-label="More actions for your scores" aria-expanded="false">' + DOTS + '</button>' +
              '<div class="kmenu" hidden><button class="kmenu-item is-danger" data-g="6" type="button" data-h="unscore" role="menuitem">Remove</button></div></span>' : '') +
            '</span></div>' +
            (x ? '<p class="hir-card-line">' + crit.map(function (k) { return '<span class="nb">' + esc(k) + ' ' + esc((x.scores || {})[k] || '') + '</span>'; }).join(' · ') + '</p>' : '<p class="hir-card-line">Not scored</p>') +
            (x && x.note ? '<p class="hir-note">' + esc(x.note) + '</p>' : '') +
            (a.remarks ? '<p class="hir-note">' + esc(a.remarks) + '</p>' : '') +
            (read.length ? '<details class="iv-read"><summary>Interview sheet</summary><dl class="ovfacts iv-facts">' +
              read.map(function (q) { return fact(q[1], esc(a[q[0]]), 'is-pre'); }).join('') + '</dl></details>' : '') + '</div>';
        }).join('') + '</div>'
        : '<p class="emptyline">No interview sheets.</p>') + '</section>';
  }
  /* ---- The Interviewer's Sheet (2026-11-17) ----------------------------------
     The team's paper sheet, filled during the interview in a panel beside
     the record (the user: "it shouldnt be shown like a card, it should at
     least a slide window or so so the record could stay right"): a rating
     out of 10, internal remarks, MBTI and the sheet's questions, each saved
     as it is left (`hiring_sheet_save`); the scorecard and the
     recommendation at its foot, saved by Save (`hiring_score_save`). The
     keys are the database's `hiring_sheet_keys()` (tests/hiringsql.js). */
  function sheetQs(c) {
    return [['mbti', 'MBTI'], ['why_role', 'Why do you want the ' + (c.position || 'this') + ' role?'],
      ['about', 'About self and family background'], ['academics', 'Academics and languages'], ['experience', 'Experience'],
      ['hobbies', 'Hobbies'], ['strengths', 'Strengths and weaknesses'],
      ['future', 'Where do you see yourself in the next 5 to 10 years?'], ['ambition', 'What is your ambition?'],
      ['company', 'What kind of company are you looking for?'], ['found', 'How did you find out about ADspace?'],
      ['why_us', 'Why have you applied to ADspace?'], ['why_hire', 'Why should ADspace hire you?'],
      ['others', 'Others'], ['general', 'General remarks']];
  }
  var iv = { dirty: false, saving: null, wired: false };
  function ivVals() {
    var a = {}, box = $('hivBody');
    Array.prototype.forEach.call(box.querySelectorAll('[data-q]'), function (el) {
      var v = String(el.value || '').trim();
      if (v) a[el.getAttribute('data-q')] = v;
    });
    var r = $('hivRating').value;
    return { rating: r ? Number(r) : null, answers: a };
  }
  /* The notes go as they are left; one save at a time, the last words
     sent once the one on its way answers. */
  function ivSave() {
    if (!iv.dirty || !state.rec) return iv.saving || Promise.resolve(true);
    if (iv.saving) return iv.saving.then(ivSave);
    iv.dirty = false;
    var v = ivVals(), c = state.rec;
    iv.saving = rpc('hiring_sheet_save', { p_id: c.id, p_rating: v.rating, p_answers: v.answers }).then(function (r) {
      iv.saving = null;
      var d = r.data || {};
      if (r.error || d.error) {
        iv.dirty = true;
        msg('hivMsg', d.error === 'too-long' ? 'Shorten ' + ((sheetQs(c).filter(function (q) { return q[0] === d.field; })[0] || [0, 'the remarks'])[1]) + ' to ' + (d.field === 'mbti' ? '20' : '2,000') + ' characters.'
          : said(r), 'err');
        return false;
      }
      $('hivSaved').textContent = 'Saved ' + window.ADspaceClock.clock(d.updated_at || new Date().toISOString());
      return true;
    });
    return iv.saving;
  }
  function score() {
    var c = state.rec, o = state.outcome, sh = $('hivSheet');
    if (!sh || !o) return;
    var mine = o.scores.filter(function (x) { return x.mine; })[0] || {};
    var ms = (state.sheets || []).filter(function (x) { return x.mine; })[0] || {}, ans = ms.answers || {};
    var crit = o.scorecard.criteria || [];
    var area = function (k, label, rows, note) {
      var id = 'hivQ_' + k;
      return '<div class="field"><label class="field-label" for="' + id + '">' + esc(label) + '</label>' +
        (k === 'mbti' ? '<input class="input" id="' + id + '" data-q="mbti" maxlength="20" autocomplete="off" spellcheck="false" value="' + esc(ans.mbti || '') + '">'
          : '<textarea class="input" id="' + id + '" data-q="' + k + '" rows="' + (rows || 2) + '"' + (note ? ' aria-describedby="' + id + 'N"' : '') + '>' + esc(ans[k] || '') + '</textarea>') +
        (note ? '<p class="iv-note" id="' + id + 'N">' + esc(note) + '</p>' : '') + '</div>';
    };
    var opts = function (n, val, first) {
      var h = '<option value="">' + first + '</option>';
      for (var i = 1; i <= n; i++) h += '<option value="' + i + '"' + (String(val) === String(i) ? ' selected' : '') + '>' + i + '</option>';
      return h;
    };
    $('hivCtx').textContent = [c.name, c.position].filter(Boolean).join(' · ');
    $('hivBody').innerHTML =
      '<section class="qcard"><h3 class="qcard-title">Assessment</h3><div class="iv-fields">' +
        '<div class="field"><label class="field-label" for="hivRating">Rating (out of 10)</label><select class="select" id="hivRating">' + opts(10, ms.rating, 'Choose') + '</select></div>' +
        area('remarks', 'Internal remarks', 3) + '</div></section>' +
      '<section class="qcard"><h3 class="qcard-title">Questions</h3><div class="iv-fields">' +
        sheetQs(c).map(function (q) { return area(q[0], q[1], q[0] === 'general' ? 3 : 2); }).join('') + '</div></section>' +
      (crit.length ? '<section class="qcard"><h3 class="qcard-title">Scores</h3><p class="hir-card-line">' +
        esc((o.scorecard.standard ? 'Standard scorecard' : o.scorecard.position + ' scorecard') + ' · 1 is weak and 5 is strong') + '</p><div class="iv-fields">' +
        crit.map(function (k, n) {
          return '<div class="field"><label class="field-label" for="hivC' + n + '">' + esc(k) + '</label><select class="select" id="hivC' + n + '" data-c="' + esc(k) + '" data-seg>' +
            opts(5, mine.scores ? mine.scores[k] : '', '–') + '</select></div>';
        }).join('') +
        '<div class="field"><label class="field-label" for="hivRec">Recommendation</label><select class="select" id="hivRec" data-seg>' +
          [['proceed', 'Proceed'], ['pool', 'Talent pool'], ['not', 'Not proceed']].map(function (x) {
            return '<option value="' + x[0] + '"' + ((mine.recommend || 'proceed') === x[0] ? ' selected' : '') + '>' + x[1] + '</option>';
          }).join('') + '</select></div></div></section>' : '');
    if (window.ADspaceForm && ADspaceForm.segment) Array.prototype.forEach.call($('hivBody').querySelectorAll('select[data-seg]'), function (el) { ADspaceForm.segment(el); });
    msg('hivMsg', '');
    $('hivSaved').textContent = ms.updated_at ? 'Saved ' + window.ADspaceClock.clock(ms.updated_at) : '';
    iv.dirty = false;
    if (!iv.wired) {
      iv.wired = true;
      var notes = function (e) { if (e.target.closest('[data-q]') || e.target.id === 'hivRating') iv.dirty = true; };
      $('hivBody').addEventListener('input', notes);
      $('hivBody').addEventListener('change', function (e) { notes(e); if (iv.dirty) ivSave(); });
      $('hivCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
      $('hivClose').addEventListener('click', function () { $('hivCancel').click(); });
      $('hivSave').addEventListener('click', ivDone);
    }
    window.ADspaceSheet.show(sh, { opener: document.querySelector('#hirRec [data-h="score"]'), onClose: function () {
      /* Words still being typed are kept as the panel shuts. */
      var reread = iv.dirty || iv.saved, done = iv.saved;
      iv.saved = false;
      ivSave().then(function () {
        if (!reread || !state.rec || state.rec.id !== c.id) return;
        state.pane = 'scores';
        openRec(c.id).then(function () { if (done) msg('hirRecMsg', 'Saved.', 'ok'); });
      });
    } });
  }
  function ivDone() {
    var c = state.rec, o = state.outcome, b = $('hivSave');
    var mine = o.scores.filter(function (x) { return x.mine; })[0] || {};
    var sel = Array.prototype.slice.call($('hivBody').querySelectorAll('select[data-c]'));
    var chosen = sel.filter(function (el) { return el.value; });
    if (chosen.length && chosen.length < sel.length) {
      var gap = sel.filter(function (el) { return !el.value; })[0];
      msg('hivMsg', 'Choose a score for ' + gap.getAttribute('data-c') + '.', 'err');
      return;
    }
    b.disabled = true;
    iv.dirty = true;
    ivSave().then(function (ok) {
      if (!ok) { b.disabled = false; return; }
      if (!chosen.length) { b.disabled = false; iv.saved = true; window.ADspaceSheet.close(); return; }
      var sc = {};
      sel.forEach(function (el) { sc[el.getAttribute('data-c')] = Number(el.value); });
      rpc('hiring_score_save', { p_id: c.id, p_scores: sc, p_recommend: $('hivRec').value, p_note: mine.note || null }).then(function (r) {
        b.disabled = false;
        var d = r.data || {};
        if (d.error === 'incomplete') { msg('hivMsg', 'Choose a score for ' + d.criterion + '.', 'err'); return; }
        if (r.error || d.error) { msg('hivMsg', said(r), 'err'); return; }
        iv.saved = true;
        window.ADspaceSheet.close();
      });
    });
  }
  function outcomeMail() {
    var c = state.rec;
    return fnCall('hiring-mail', { candidateId: c.id, kind: 'outcome' }).then(function (d) {
      if (d.error) { msg('hirRecMsg', SAID[d.error] || said({ data: d }), d.error === 'unknown' ? 'warn' : 'err'); return false; }
      return true;
    });
  }
  function decide(o) {
    var c = state.rec, mails = o !== 'proceed';
    var body = { proceed: c.name + ' moves to Offer. The offer will be prepared in the next step.',
      pool: c.name + ' will be asked on their page to agree to ADspace keeping their application. If they do not agree, their details will be deleted.',
      not: c.name + '\'s application will be closed. Their details will be deleted after the period set in Settings (Closed candidates kept).' }[o];
    var f = [{ name: 'note', label: 'Note', rows: 2, required: false, placeholder: 'Optional', note: 'Seen by the team only.' }];
    if (mails) f.push({ name: 'mail', label: 'Email ' + c.name, tick: true, value: 'on' });
    window.ADspaceConfirm.ask({ title: REC[o] + '?', go: REC[o], tone: o === 'not' ? 'warn' : '', wait: true, body: body, fields: f },
    function (v) {
      return rpc('hiring_decide', { p_id: c.id, p_outcome: o, p_note: String(v.note || '').trim() || null }).then(function (r) {
        var d = r.data || {};
        if (r.error || d.error) return said(r);
        state.pane = 'scores';
        var after = mails && v.mail ? outcomeMail() : Promise.resolve(false);
        after.then(function (sent) {
          load().then(function () {
            msg('hirRecMsg', sent ? 'Decided. The candidate was emailed.' : 'Decided.', 'ok');
            if (bridge.undoHere) bridge.undoHere('Decided: ' + REC[o] + '.', function () {
              return rpc('hiring_decide', { p_id: c.id, p_outcome: 'reopen', p_note: null }).then(function () { openRec(c.id); });
            }, $('hirRecMsg'));
          });
        });
        return '';
      });
    });
  }

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

  /* ---- Offers and contracts (step D; HR-SPEC.md decisions 4, 5, 10) ------
     A document a card: its reference, where it stands and its next step.
     The salary is set, read and drawn only behind the master code and a
     caution step (`hiring_unlock`, the token kept 15 minutes in this page's
     memory alone); never shown in a fact, a line or the history. */
  var DOC_WORD = { offer: 'Employment Offer', contract: 'Employment Contract' };
  var DOC_STATE = { draft: ['Draft', 'is-off'], sent: ['Sent', 'is-warn'], withdrawn: ['Withdrawn', 'is-off'], declined: ['Declined', 'is-off'],
    signed: ['Signed', 'is-warn'], confirmed: ['Confirmed', 'is-ok'], void: ['Void', 'is-off'] };
  var EMP_TYPE = { permanent: 'Permanent', contract: 'Contract', intern: 'Internship', part_time: 'Part-time' };
  var DOC_SAID = {
    'not-offer': 'Choose Proceed on the Scores tab first.', 'offer-first': 'Confirm the Employment Offer first.',
    'exists': 'This candidate already has one. Open it below.', 'not-draft': 'This document has been sent and can no longer be edited.',
    'no-pay': 'Set the salary first.', 'bad-type': 'Choose the employment type.', 'bad-probation': 'Enter a probation of 0 to 12 months.',
    'bad-reply': 'Enter 1 to 14 days to reply.', 'bad-start': 'Enter the commencement date.', 'bad-end': 'Enter an end date after the commencement date.',
    'bad-scope': 'Enter the scope.', 'bad-duties': 'Enter the nature of works.', 'bad-basic': 'Enter the basic salary.',
    'bad-probation-pay': 'Enter the salary during probation, or leave it empty.', 'code-needed': 'Enter the master code again.',
    'wrong-code': 'The master code is incorrect.', 'locked': 'Too many attempts. Please try again in 15 minutes.',
    'no-code': 'The master code is not set up yet. Please contact an admin.', 'not-sent': 'This document is not on the candidate\'s page.',
    'not-signed': 'This document has not been signed.', 'bad-note': 'Enter a reason.', 'bad-date': 'Choose a date from the day it was sent to today.',
    'bad-file': 'Upload the signed copy as a PDF.', 'bad-stamp': 'Enter the stamp certificate number as printed.', 'bad-state': 'This document has changed. Refresh the page.',
    'bad-serial': 'Type the reference exactly as shown.', 'expired': 'The days to reply have passed. Replace the document instead.',
    'replaced': 'The document it replaces can no longer be replaced.', 'gone': 'This document no longer exists.', 'not-confirmed': 'Confirm the document first.',
    'bad-sha': 'The sealed copy could not be saved. Please try again.'
  };
  function docSaid(r) { var k = r && r.data && r.data.error; return DOC_SAID[k] || said(r); }
  function docOf(b) { var id = b.getAttribute('data-id'); return (state.docs || []).filter(function (d) { return d.id === id; })[0] || {}; }
  /* Make colleague (step E1, the mockups approved 2026-11-17): once the
     offer and the contract are both confirmed, the part makes the candidate
     a colleague; then the card names the colleague and opens their record. */
  function hireCard() {
    var h = state.hire;
    if (!h) return '';
    if (h.made && h.member) {
      var m = h.member;
      return '<section class="readgroup hir-hire"><div class="readgroup-head"><h4 class="fsec-h">Colleague</h4>' +
        '<button class="btn btn-sm" type="button" data-h="openmember">Open record' + CHEV.replace('<svg ', '<svg class="ovgo-chev" ') + '</button></div>' +
        '<dl class="ovfacts">' + fact('Name', esc(m.name)) + fact('Employee ID', esc(m.staff_code || '')) + fact('Company email', esc(m.email || '')) +
        fact('First day', esc(day(m.first_day))) + fact('Welcome Kit', esc(m.welcomed_at ? 'Acknowledged ' + day(m.welcomed_at) : 'Not acknowledged')) + '</dl></section>';
    }
    if (!h.ready || !h.may) return '';
    return '<section class="readgroup hir-hire"><div class="readgroup-head"><h4 class="fsec-h">Next step</h4>' +
      '<button class="btn btn-sm btn-primary" type="button" data-h="makecolleague">Make colleague</button></div>' +
      '<p class="hir-hire-line">' + esc(state.rec.name) + ' will become a colleague with a sign-in, a Welcome Kit and an onboarding checklist.</p></section>';
  }
  var HIRE_SAID = {
    'bad-email': 'Enter a valid email address.', 'bad-role': 'Choose a user group.', 'bad-staff': 'Enter an Employee ID of 3 to 8 letters or digits.',
    'bad-department': 'Choose a department.', 'bad-position': 'Enter a position of 2 to 80 characters.', 'bad-day': 'Choose the first day.',
    'bad-dm': 'Choose a direct manager.', 'not-ready': 'Confirm the offer and the contract first.',
    'team-access': 'You do not have permission to add a colleague. Please ask an admin.', 'refused': 'The colleague could not be added. Please ask an admin.',
    taken: { email: 'This email address is used by another colleague. Enter another email address.', staff_code: 'This Employee ID is used by another colleague. Enter another Employee ID.',
      name: 'A colleague already has this name. Change the candidate\'s name on Edit first.' }
  };
  function makeColleague() {
    Promise.all([team(), db.from('team_roles').select('slug, name, is_admin, position').order('position').then(function (r) { if (r.error) throw r.error; return r.data || []; })])
      .then(function (x) { askColleague(x[0], x[1]); })
      .catch(function () { msg('hirRecMsg', 'The colleagues could not be loaded. Please try again.', 'err'); });
  }
  function askColleague(list, groups) {
    var c = state.rec, h = state.hire || {}, t = h.terms || {};
    var A = window.ADspaceAdmin || {}, F = window.ADspaceForm;
    /* An admin group is offered to an admin alone, as Add member does. */
    var roles = groups.filter(function (r) { return !r.is_admin || (A.isAdmin && A.isAdmin()); }).map(function (r) { return [r.slug, r.name]; });
    var depts = (A.depts ? A.depts() : []).filter(function (d) { return d.active !== false; }).map(function (d) { return [d.key, d.name]; });
    var people = list.slice().sort(F && F.sequence ? F.sequence('staff_code') : undefined)
      .map(function (m) { return [m.id, F && F.named ? F.named(m.staff_code, m.name) : m.name]; });
    var invite = may('team.invite', 'work');
    var fields = [
      { name: 'email', label: 'Company email', type: 'email', placeholder: 'email@adspacestudios.com' },
      { name: 'staff', label: 'Employee ID', placeholder: 'AD001', half: true },
      { name: 'role', label: 'User group', choices: [['', 'Choose a group']].concat(roles), value: '' },
      { name: 'dept', label: 'Department', choices: [['', 'Choose a department']].concat(depts), value: '', half: true },
      { name: 'pos', label: 'Position', value: t.position || c.position || '' },
      { name: 'day', label: 'First day', type: 'date', value: t.start || '', half: true },
      { name: 'dm', label: 'Direct manager', choices: [['', 'Choose a colleague']].concat(people), value: '' }];
    if (invite) fields.push({ name: 'invite', label: 'Send invitation email', tick: true });
    window.ADspaceConfirm.ask({ title: 'Make colleague', body: c.name + ' will be added to Team.', go: 'Make colleague', wait: true, fields: fields,
      check: function (v) {
        if (!window.ADspaceWords.emailOk(String(v.email || '').trim())) return 'Enter a valid email address.';
        if (!/^[A-Za-z0-9]{3,8}$/.test(String(v.staff || '').trim())) return HIRE_SAID['bad-staff'];
        if (!v.role) return HIRE_SAID['bad-role'];
        if (!v.dept) return HIRE_SAID['bad-department'];
        if (!v.day) return HIRE_SAID['bad-day'];
        if (!v.dm) return HIRE_SAID['bad-dm'];
        return '';
      } },
    function (v) {
      var email = String(v.email || '').trim().toLowerCase();
      return rpc('hiring_make_colleague', { p_id: c.id, p_values: { email: email, staff_code: String(v.staff || '').trim().toUpperCase(), role: v.role,
        department: v.dept, designation: String(v.pos || '').trim(), first_day: v.day, dm: v.dm } }).then(function (r) {
        var d = r.data || {};
        if (d.error === 'taken') return HIRE_SAID.taken[d.field] || HIRE_SAID.taken.email;
        if (d.error === 'refused') return 'You do not have permission to add a colleague to this group. Please ask an admin.';
        if (r.error || d.error) return HIRE_SAID[d.error] || said(r);
        var after = Promise.resolve('');
        if (v.invite === 'on' && invite) {
          after = API.invokeFn('invite-member', { email: email, name: c.name }).then(function (x) {
            if (x.error) return ' The invitation could not be sent. Send it from their record.';
            return (x.data || {}).sent === false ? '' : ' Invitation sent to ' + email + '.';
          }).catch(function () { return ' The invitation could not be sent. Send it from their record.'; });
        }
        after.then(function (more) {
          state.pane = 'offer';
          load().then(function () { return openRec(c.id); }).then(function () { msg('hirRecMsg', c.name + ' is now a colleague.' + more, more && /could not/.test(more) ? 'warn' : 'ok'); });
        });
        return '';
      });
    });
  }
  function openMember() {
    var h = state.hire || {}, id = h.member && h.member.id;
    if (!id) return;
    state.open = null; state.rec = null; state.pane = 'overview';
    $('hirRec').hidden = true; $('sectionTeam').classList.remove('is-candidate');
    /* Members first: its tab writes the address, which then names the
       colleague, as search opens one. */
    var tab = document.querySelector('#teamTabs .tab[data-tab="members"]');
    if (tab && !tab.classList.contains('is-on')) tab.click();
    history.pushState(null, '', '/admin/?s=team&member=' + encodeURIComponent(id));
    if (window.ADspaceTeam) { window.ADspaceTeam.fromUrl(); window.ADspaceTeam.enter(); }
    window.scrollTo(0, 0);
  }
  function docsPane(c, can) {
    if (state.docs == null) return '<section class="readgroup"><div id="hirDocFail"></div></section>';
    var live = function (k) { return state.docs.some(function (d) { return d.kind === k && ['draft', 'sent', 'signed', 'confirmed'].indexOf(d.state) >= 0; }); };
    var newOffer = can && c.stage === 'offer' && !live('offer');
    var newContract = can && c.stage === 'offer' && !live('contract') && state.docs.some(function (d) { return d.kind === 'offer' && d.state === 'confirmed'; });
    var head = '<section class="readgroup"><div class="readgroup-head"><h4 class="fsec-h">Offer and contract</h4>' +
      (newOffer ? '<button class="btn btn-sm" type="button" data-h="docnew" data-kind="offer">New offer</button>' : '') +
      (newContract ? '<button class="btn btn-sm" type="button" data-h="docnew" data-kind="contract">New contract</button>' : '') + '</div>';
    if (!state.docs.length) return head + '<p class="emptyline">' + (c.stage === 'offer' ? 'No documents.' : 'Choose Proceed on the Scores tab first.') + '</p></section>';
    return head + '<div class="hir-ivs">' + state.docs.map(function (d) { return docCard(d, can); }).join('') + '</div></section>';
  }
  function docCard(d, can) {
    var st = DOC_STATE[d.state] || DOC_STATE.draft, t = d.terms || {}, part = admin(), id = ' data-id="' + esc(d.id) + '"';
    var label = d.state === 'sent' && d.expired ? ['Expired', 'is-off'] : st;
    var acts = '', items = [];
    var item = function (g, h, words, red) { items.push('<button class="kmenu-item' + (red ? ' is-danger' : '') + '" data-g="' + g + '" type="button" data-h="' + h + '"' + id + ' role="menuitem">' + words + '</button>'); };
    if (can) {
      if (d.state === 'draft') {
        if (part) acts += '<button class="btn btn-sm" type="button" data-h="docpay"' + id + '>' + (d.pay_set ? 'Change salary' : 'Set salary') + '</button>';
        if (part) acts += '<button class="btn btn-sm" type="button" data-h="docpreview"' + id + '>Preview PDF</button>';
        acts += '<button class="btn btn-sm btn-go" type="button" data-h="docsend"' + id + '>Send</button>';
        item(2, 'docedit', 'Edit'); item(6, 'docdelete', 'Delete', true);
      }
      if (d.state === 'sent') {
        if (part) acts += '<button class="btn btn-sm" type="button" data-h="docpreview"' + id + '>Preview PDF</button>';
        if (!d.expired && d.mail !== 'sent') acts += '<button class="btn btn-sm" type="button" data-h="docmail"' + id + '>Email candidate</button>';
        item(4, 'docmark', 'Mark signed'); item(2, 'docreplace', 'Replace'); if (!d.expired) item(5, 'docwithdraw', 'Withdraw');
      }
      if (d.state === 'withdrawn') {
        if (!d.expired) acts += '<button class="btn btn-sm" type="button" data-h="docrestore"' + id + '>Restore</button>';
        item(4, 'docmark', 'Mark signed'); item(2, 'docreplace', 'Replace');
      }
      if (d.state === 'declined') item(2, 'docreplace', 'Replace');
      if (d.state === 'signed') {
        acts += '<button class="btn btn-sm" type="button" data-h="docback"' + id + '>Send back</button>';
        if (part) acts += '<button class="btn btn-sm btn-go" type="button" data-h="docconfirm"' + id + '>Confirm</button>';
        item(2, 'docreplace', 'Replace');
      }
      if (d.state === 'confirmed') acts += '<button class="btn btn-sm" type="button" data-h="docseal"' + id + '>Download</button>';
      if (d.signed && d.signed.has_scan) item(1, 'docscan', 'Signed copy');
      if (d.state !== 'draft') item(1, 'docrecord', 'Record');
      if (part && ['sent', 'withdrawn', 'declined', 'signed', 'confirmed'].indexOf(d.state) >= 0) item(6, 'docvoid', 'Void', true);
      if (part && d.state === 'void') item(6, 'docdelete', 'Delete', true);
    }
    var menu = items.length ? '<span class="team-act"><button class="kmenu-btn" type="button" data-h="menu" aria-label="More actions for ' + esc(DOC_WORD[d.kind]) + '" aria-expanded="false">' + DOTS + '</button>' +
      '<div class="kmenu" hidden>' + items.join('') + '</div></span>' : '';
    var signed = d.signed ? (d.signed.via === 'online' ? esc(d.signed.name || '') + ' · ' + esc(when(d.signed_at)) + ' · Code confirmed' :
      (d.signed.via === 'scan' ? 'By scan' : 'On paper') + (d.signed.on ? ' · ' + esc(day(d.signed.on)) : '')) : '';
    return '<div class="hir-iv' + (d.state === 'void' ? ' is-off' : '') + '"><div class="hir-iv-head"><b>' + esc(DOC_WORD[d.kind]) +
        (d.serial ? ' <span class="nb hir-doc-ref">' + esc(d.serial) + '</span>' : '') + '</b>' +
        '<span class="hir-iv-ctl"><span class="chip-state ' + label[1] + '">' + esc(label[0]) + '</span>' + menu + '</span></div>' +
      '<dl class="ovfacts">' +
        fact('Position', esc(t.position || '')) + fact('Employment', esc(EMP_TYPE[t.type] || '')) +
        fact('Commencement', esc(day(t.start))) + (t.end ? fact('End of contract', esc(day(t.end))) : '') +
        fact('Probation', t.probation_months ? esc(t.probation_months) + ' month' + (t.probation_months === 1 ? '' : 's') : 'None') +
        fact('Salary', d.pay_set ? 'Set' : '', d.pay_set ? '' : 'is-warn') +
        (d.state === 'draft' ? fact('Days to reply', esc(t.reply_days || '')) : '') +
        (d.sent_at ? fact('Sent', esc([d.sent_by, when(d.sent_at)].filter(Boolean).join(' · '))) : '') +
        (d.state === 'sent' ? fact(d.expired ? 'Expired' : 'Reply by', esc(when(d.reply_by))) : '') +
        (d.mail ? fact('Email', esc(MAIL[d.mail] || d.mail) + ' · ' + esc(when(d.mail_at)), d.mail === 'sent' ? '' : 'is-warn') : '') +
        (d.returned_note && d.state === 'sent' ? fact('Sent back', esc(d.returned_note), 'is-pre') : '') +
        (signed ? fact(d.kind === 'offer' ? 'Accepted' : 'Signed', signed) : '') +
        (d.state === 'declined' ? fact('Declined', esc(when(d.answered_at)) + (d.decline_note ? ' · ' + esc(d.decline_note) : '')) : '') +
        (d.confirmed_at ? fact('Confirmed', esc([d.confirmed_by, when(d.confirmed_at)].filter(Boolean).join(' · '))) : '') +
        (d.stamp_no ? fact('Stamp certificate', esc(d.stamp_no)) : '') +
        (d.sealed_at ? fact('Sealed', esc(when(d.sealed_at))) : '') +
        (d.void_note ? fact('Void', esc(d.void_note)) : '') +
      '</dl>' + (acts ? '<div class="hir-iv-acts">' + acts + '</div>' : '') + '</div>';
  }
  function docSheet(d, kind) {
    var c = state.rec, k = d ? d.kind : kind, t = (d && d.terms) || {};
    var last = (state.docs || []).filter(function (x) { return x.kind === 'offer' && x.terms; })[0];
    if (!d && k === 'contract' && last) t = Object.assign({}, last.terms, { reply_days: 7 });
    var f = [
      { name: 'position', label: 'Position', value: t.position || c.position || '', required: true },
      { name: 'type', label: 'Employment', choices: [['permanent', 'Permanent'], ['contract', 'Contract'], ['intern', 'Internship'], ['part_time', 'Part-time']], value: t.type || 'permanent' },
      { name: 'start', label: 'Commencement', type: 'date', value: t.start || '', half: true, required: true },
      { name: 'end', label: 'End of contract', type: 'date', value: t.end || '', required: false, note: 'Contract and internship only.' },
      { name: 'probation', label: 'Probation (months)', type: 'number', value: t.probation_months == null ? 3 : t.probation_months, half: true },
      { name: 'reply', label: 'Days to reply', type: 'number', value: t.reply_days || (k === 'offer' ? 3 : 7) }
    ];
    if (k === 'offer') f.push({ name: 'scope', label: 'Scope', value: t.scope || '', required: true });
    else {
      f.push({ name: 'duties', label: 'Nature of works', rows: 3, value: t.duties || '', required: true });
      f.push({ name: 'place', label: 'Place of employment', value: t.place || '', required: false, note: 'Leave empty for the registered office.' });
    }
    window.ADspaceConfirm.ask({ title: (d ? 'Edit ' : 'New ') + (k === 'offer' ? 'offer' : 'contract'), go: d ? 'Save' : 'Create', wait: true, fields: f,
      check: function (v) {
        if (!String(v.position || '').trim()) return DOC_SAID['bad-position'] || 'Enter the position.';
        if (!v.start) return DOC_SAID['bad-start'];
        if ((v.type === 'contract' || v.type === 'intern') && (!v.end || v.end <= v.start)) return DOC_SAID['bad-end'];
        return '';
      } },
    function (v) {
      var terms = { position: String(v.position).trim(), type: v.type, start: v.start, end: v.end || null, probation_months: Number(v.probation) || 0,
        reply_days: Number(v.reply) || 0, scope: v.scope, duties: v.duties, place: v.place };
      return rpc('hiring_doc_save', { p_candidate: c.id, p_doc: d ? d.id : null, p_kind: k, p_terms: terms, p_expected: d ? d.updated_at : null }).then(function (r) {
        var x = r.data || {};
        if (r.error || x.error) return docSaid(r);
        state.pane = 'offer';
        openRec(c.id).then(function () { msg('hirRecMsg', d ? 'Saved.' : 'Draft created. Set the salary, then send it.', 'ok'); });
        return '';
      });
    });
  }
  /* The master code, then the caution step; the token held 15 minutes in
     this page alone (never stored). */
  var unlockAt = 0, unlockTok = '';
  function unlocked() {
    if (unlockTok && Date.now() - unlockAt < 14 * 60000) return Promise.resolve(unlockTok);
    return new Promise(function (resolve) {
      window.ADspaceConfirm.ask({ title: 'Enter the master code', go: 'Unlock', wait: true,
        body: 'Enter the master code to see the salary.',
        field: { name: 'code', label: 'Master code', type: 'password', required: true } },
      function (v) {
        return rpc('hiring_unlock', { p_code: v.code }).then(function (r) {
          var x = r.data || {};
          if (r.error || x.error) return x.error === 'wrong-code' ? 'The master code is incorrect. ' + x.left + ' attempts left.' : docSaid(r);
          unlockTok = x.token; unlockAt = Date.now();
          setTimeout(function () { resolve(unlockTok); }, 0);
          return '';
        });
      });
    }).then(function (tok) {
      return new Promise(function (resolve) {
        window.ADspaceConfirm.ask({ title: 'Sensitive information follows', body: 'Proceed with caution.', go: 'Continue' }, function () { resolve(tok); });
      });
    });
  }
  function payOf(d, tok) {
    return rpc('hiring_doc_pay_get', { p_doc: d.id, p_token: tok }).then(function (r) {
      var x = r.data || {};
      if (r.error || x.error) { if (x.error === 'code-needed') unlockTok = ''; throw new Error(docSaid(r)); }
      unlockAt = Date.now();
      return x;
    });
  }
  function docPay(d, b) {
    unlocked().then(function (tok) {
      return payOf(d, tok).then(function (p) {
        var prob = Number((d.terms || {}).probation_months) || 0;
        var f = [{ name: 'basic', label: 'Basic salary per month (RM)', type: 'number', value: p.basic == null ? '' : p.basic, required: true }];
        if (prob) f.push({ name: 'probation', label: 'During probation per month (RM)', type: 'number', value: p.probation == null ? '' : p.probation, required: false, note: 'Leave empty if it is the same as the basic salary.' });
        window.ADspaceConfirm.ask({ title: 'Salary', go: 'Save', wait: true, fields: f,
          check: function (v) { return Number(v.basic) > 0 ? '' : DOC_SAID['bad-basic']; } },
        function (v) {
          return rpc('hiring_doc_pay_set', { p_doc: d.id, p_basic: Number(v.basic), p_probation: v.probation === '' || v.probation == null ? null : Number(v.probation), p_token: tok }).then(function (r) {
            if (r.error || (r.data || {}).error) return docSaid(r);
            unlockAt = Date.now();
            openRec(state.rec.id).then(function () { msg('hirRecMsg', 'Saved.', 'ok'); });
            return '';
          });
        });
      });
    }).catch(function (e) { msg('hirRecMsg', e && e.message ? e.message : 'The request failed. Please try again.', 'err'); });
  }
  function docInfo(d) {
    var c = state.rec, me = bridge.me ? bridge.me() : {};
    return { kind: d.kind, serial: d.serial, sent_at: d.sent_at, terms: d.terms, name: c.name, signed: null,
      signatory: { name: d.sent_by || (me && me.name) || '', designation: d.sent_role || '' } };
  }
  function docPreview(d, b) {
    var tab = window.ADspaceDocs.previewTab ? window.ADspaceDocs.previewTab() : null;
    unlocked().then(function (tok) { return payOf(d, tok); }).then(function (p) {
      return window.ADspaceHrDocs.bytes(docInfo(d), p, { draft: d.state === 'draft' });
    }).then(function (bytes) {
      return window.ADspaceDocs.save(new Blob([bytes], { type: 'application/pdf' }), window.ADspaceHrDocs.fileName(d), tab);
    }).catch(function (e) { if (tab && tab.close) try { tab.close(); } catch (x) {} msg('hirRecMsg', e && e.message ? e.message : 'The document could not be generated. Please try again.', 'err'); });
  }
  function docMail(d) {
    return fnCall('hiring-mail', { docId: d.id, kind: 'doc' }).then(function (x) {
      if (x.error) { msg('hirRecMsg', SAID[x.error] || said({ data: x }), x.error === 'unknown' ? 'warn' : 'err'); return false; }
      return true;
    });
  }
  function docSend(d, b) {
    var c = state.rec;
    window.ADspaceConfirm.ask({ title: 'Send ' + DOC_WORD[d.kind] + '?', go: 'Send', wait: true,
      body: 'ADspace will email ' + c.name + ' at ' + c.email + '. Their page asks for a code before it shows the document. The email does not include the salary.' },
    function () {
      return rpc('hiring_doc_send', { p_doc: d.id }).then(function (r) {
        var x = r.data || {};
        if (r.error || x.error) return docSaid(r);
        docMail(d).then(function (ok) { openRec(c.id).then(function () { if (ok) msg('hirRecMsg', 'Sent.', 'ok'); }); });
        return '';
      });
    });
  }
  function docWithdraw(d, back) {
    var c = state.rec;
    rpc('hiring_doc_withdraw', { p_doc: d.id, p_restore: back }).then(function (r) {
      if (r.error || (r.data || {}).error) { msg('hirRecMsg', docSaid(r), 'err'); return; }
      openRec(c.id).then(function () {
        if (!back && bridge.undoHere) bridge.undoHere('Withdrawn.', function () {
          return rpc('hiring_doc_withdraw', { p_doc: d.id, p_restore: true }).then(function () { openRec(c.id); });
        }, $('hirRecMsg'));
      });
    });
  }
  /* A PDF picked and stored in the candidate's private folder; answers its
     path. */
  function pickPdf(label) {
    return new Promise(function (resolve, reject) {
      var inp = document.createElement('input');
      inp.type = 'file'; inp.accept = 'application/pdf,.pdf';
      inp.addEventListener('change', function () {
        var f = inp.files && inp.files[0];
        if (!f) { reject(new Error('')); return; }
        if (!/\.pdf$/i.test(f.name) || (f.type && f.type !== 'application/pdf')) { reject(new Error(DOC_SAID['bad-file'])); return; }
        if (f.size > MAX_MB * 1048576) { reject(new Error('Choose a file of ' + MAX_MB + ' MB or less.')); return; }
        var path = state.rec.id + '/' + Date.now() + '-' + label + '.pdf';
        db.storage.from(BUCKET).upload(path, f, { contentType: 'application/pdf', upsert: false }).then(function (x) {
          if (x.error) reject(new Error('The file was not uploaded. Please try again.')); else resolve(path);
        }, function () { reject(new Error('The file was not uploaded. Please try again.')); });
      });
      inp.click();
    });
  }
  function docMark(d) {
    var c = state.rec, today = window.ADspaceClock.today();
    window.ADspaceConfirm.ask({ title: 'Mark signed', go: 'Choose the signed copy', wait: true,
      body: 'Upload the signed copy as a PDF.',
      fields: [{ name: 'route', label: 'Signed', choices: [['scan', 'By scan'], ['paper', 'On paper']], seg: true, value: 'scan' },
        { name: 'on', label: 'Date signed', type: 'date', value: today, required: true }],
      check: function (v) { return !v.on || v.on > today || v.on < window.ADspaceClock.day(d.sent_at) ? DOC_SAID['bad-date'] : ''; } },
    function (v) {
      return pickPdf('signed-' + d.kind).then(function (path) {
        return rpc('hiring_doc_mark', { p_doc: d.id, p_route: v.route, p_on: v.on, p_path: path }).then(function (r) {
          if (r.error || (r.data || {}).error) { db.storage.from(BUCKET).remove([path]).then(function () {}, function () {}); return docSaid(r); }
          openRec(c.id).then(function () { msg('hirRecMsg', 'Marked signed.', 'ok'); });
          return '';
        });
      }).catch(function (e) { return (e && e.message) || ''; });
    });
  }
  function docBack(d) {
    var c = state.rec;
    window.ADspaceConfirm.ask({ title: 'Send back?', go: 'Send back', tone: 'warn', wait: true,
      body: 'The candidate will be asked to ' + (d.kind === 'offer' ? 'reply' : 'sign') + ' again. The signing so far is kept in its record.',
      field: { name: 'note', label: 'Reason', required: true } },
    function (v) {
      return rpc('hiring_doc_send_back', { p_doc: d.id, p_note: String(v.note || '').trim() }).then(function (r) {
        if (r.error || (r.data || {}).error) return docSaid(r);
        docMail(d).then(function () { openRec(c.id); });
        return '';
      });
    });
  }
  function docConfirm(d, b) {
    var c = state.rec;
    window.ADspaceConfirm.ask({ title: 'Confirm ' + DOC_WORD[d.kind] + '?', go: 'Confirm', wait: true,
      body: 'Confirming countersigns it for ' + (window.ADSPACE_ORG && window.ADSPACE_ORG.name || 'ADSPACE PLT') + '. The confirmed copy is then sealed and cannot be changed.',
      fields: [{ name: 'stamp', label: 'Stamp certificate number', value: '', required: false, note: 'Optional. Enter it if the document was stamped.' }] },
    function (v) {
      return rpc('hiring_doc_confirm', { p_doc: d.id, p_stamp_no: String(v.stamp || '').trim() || null, p_stamp_path: null }).then(function (r) {
        if (r.error || (r.data || {}).error) return docSaid(r);
        openRec(c.id).then(function () {
          msg('hirRecMsg', 'Confirmed.', 'ok');
          var now = (state.docs || []).filter(function (x) { return x.id === d.id; })[0];
          if (now) docSealed(now, null);
        });
        return '';
      });
    });
  }
  /* The sealed copy: drawn once behind the master code, with its Record of
     this Document, stored privately and never drawn again; later presses
     open the kept file. */
  function docSealed(d, b) {
    if (d.seal_path) { openPath(d.seal_path, b); return; }
    var c = state.rec, rec;
    rpc('hiring_doc_record', { p_doc: d.id }).then(function (r) {
      if (r.error || (r.data || {}).error) throw new Error(docSaid(r));
      rec = r.data;
      return unlocked();
    }).then(function (tok) { return payOf(d, tok); }).then(function (p) {
      var info = docInfo(d);
      return signedOf(d).then(function (s) { info.signed = s; return window.ADspaceHrDocs.seal(info, p, rec); });
    }).then(function (blob) {
      var path = c.id + '/sealed-' + d.id + '.pdf';
      return db.storage.from(BUCKET).upload(path, blob, { contentType: 'application/pdf', upsert: false }).then(function (x) {
        if (x.error && !/exists|Duplicate/i.test(x.error.message || '')) throw new Error('The sealed copy could not be saved. Please try again.');
        return rpc('hiring_doc_seal', { p_doc: d.id, p_path: path, p_sha: blob.seal.sha, p_pages_sha: blob.seal.pagesSha });
      }).then(function (r) {
        if (r.error || (r.data || {}).error) throw new Error(docSaid(r));
        openRec(c.id).then(function () { msg('hirRecMsg', 'Sealed.', 'ok'); });
      });
    }).catch(function (e) { if (e && e.message) msg('hirRecMsg', e.message, 'err'); });
  }
  /* The candidate's signing as the PDF prints it (the signature drawn and
     the record), read with the salary's unlock. */
  function signedOf(d) {
    return rpc('hiring_doc_signed', { p_doc: d.id, p_token: unlockTok }).then(function (r) {
      var x = r.data || {};
      return x.ok ? x.signed : null;
    });
  }
  function openPath(path, b) {
    if (!path) return;
    var tab = window.open('', '_blank');
    db.storage.from(BUCKET).createSignedUrl(path, SIGN_SECS).then(function (x) {
      if (x.error || !x.data) { if (tab) tab.close(); msg('hirRecMsg', 'The file could not be opened. Please try again.', 'err'); return; }
      if (tab) tab.location.href = x.data.signedUrl; else location.href = x.data.signedUrl;
    }, function () { if (tab) tab.close(); });
  }
  function docRecord(d, b) {
    if (!window.ADspaceSeal) return;
    window.ADspaceSeal.open({ title: 'Record of this Document', sub: DOC_WORD[d.kind] + ' ' + (d.serial || ''), opener: b,
      verifyUrl: 'https://digital.adspace.me/verify/?s=' + encodeURIComponent(d.serial || ''),
      load: function () { return rpc('hiring_doc_record', { p_doc: d.id }).then(function (r) { if (r.error || (r.data || {}).error) throw new Error('x'); return r.data; }); },
      download: d.seal_path ? function () { openPath(d.seal_path); } : null });
  }
  function docReplace(d) {
    var c = state.rec;
    window.ADspaceConfirm.ask({ title: 'Replace ' + DOC_WORD[d.kind] + '?', go: 'Replace', wait: true,
      body: 'A new draft will be created from these terms. Once sent, it takes ' + d.serial + ' and this document becomes void. Set the salary again before sending.' },
    function () {
      return rpc('hiring_doc_replace', { p_doc: d.id }).then(function (r) {
        if (r.error || (r.data || {}).error) return docSaid(r);
        openRec(c.id).then(function () { msg('hirRecMsg', 'Draft created.', 'ok'); });
        return '';
      });
    });
  }
  function docVoid(d) {
    var c = state.rec;
    window.ADspaceConfirm.ask({ title: 'Void ' + d.serial + '?', go: 'Void', tone: 'danger', wait: true,
      body: 'It will be removed from the candidate\'s page. A signed or sealed copy is kept.',
      field: { name: 'note', label: 'Reason', required: true } },
    function (v) {
      return rpc('hiring_doc_void', { p_doc: d.id, p_note: String(v.note || '').trim() }).then(function (r) {
        if (r.error || (r.data || {}).error) return docSaid(r);
        openRec(c.id);
        return '';
      });
    });
  }
  function docDelete(d) {
    var c = state.rec, draft = d.state === 'draft';
    window.ADspaceConfirm.ask({ title: 'Delete', go: 'Delete', tone: 'danger', wait: true,
      body: draft ? 'This draft will be deleted. This cannot be undone.' : d.serial + ', its record and its files will be deleted. This cannot be undone.',
      field: draft ? null : { name: 'serial', label: 'Type the reference', match: d.serial } },
    function (v) {
      return rpc('hiring_doc_delete', { p_doc: d.id, p_serial: draft ? null : v.serial }).then(function (r) {
        if (r.error || (r.data || {}).error) return docSaid(r);
        sweepFiles();
        openRec(c.id);
        return '';
      });
    });
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
      f.push({ line: line || '' });
      f.push({ name: 'minutes', label: 'Length', choices: [['30', '30 minutes'], ['45', '45 minutes'], ['60', '60 minutes'], ['90', '90 minutes']], seg: true, value: '45', head: 'Interview' });
      f.push({ name: 'mode', label: 'Location', choices: [['online', 'Google Meet'], ['office', 'At the office']], seg: true, value: 'online' });
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
    'candidate.email': 'Email to the candidate',
    'candidate.scored': 'Scores changed', 'candidate.decided': 'Decision made', 'candidate.edited': 'Details edited', 'candidate.people': 'People changed',
    'candidate.link': 'Link changed', 'candidate.removed': 'Candidate removed', 'candidate.restored': 'Candidate restored',
    'candidate.hired': 'Made a colleague' };
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
    on('docnew', function (b) { docSheet(null, b.getAttribute('data-kind')); });
    on('makecolleague', function () { makeColleague(); });
    on('openmember', function () { openMember(); });
    on('docedit', function (b) { docSheet(docOf(b), null); });
    on('docpay', function (b) { docPay(docOf(b), b); });
    on('docpreview', function (b) { docPreview(docOf(b), b); });
    on('docsend', function (b) { docSend(docOf(b), b); });
    on('docmail', function (b) { b.disabled = true; docMail(docOf(b)).then(function (ok) { openRec(c.id).then(function () { if (ok) msg('hirRecMsg', 'Sent.', 'ok'); }); }); });
    on('docwithdraw', function (b) { docWithdraw(docOf(b), false); });
    on('docrestore', function (b) { docWithdraw(docOf(b), true); });
    on('docmark', function (b) { docMark(docOf(b)); });
    on('docback', function (b) { docBack(docOf(b)); });
    on('docconfirm', function (b) { docConfirm(docOf(b), b); });
    on('docseal', function (b) { docSealed(docOf(b), b); });
    on('docscan', function (b) { openPath(docOf(b).signed.path, b); });
    on('docrecord', function (b) { docRecord(docOf(b), b); });
    on('docreplace', function (b) { docReplace(docOf(b)); });
    on('docvoid', function (b) { docVoid(docOf(b)); });
    on('docdelete', function (b) { docDelete(docOf(b)); });
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
    on('score', score);
    on('decide', function (b) { decide(b.getAttribute('data-o')); });
    on('outmail', function (b) { b.disabled = true; outcomeMail().then(function (ok) { openRec(c.id).then(function () { if (ok) msg('hirRecMsg', 'Sent.', 'ok'); }); }); });
    on('reopen', function () {
      rpc('hiring_decide', { p_id: c.id, p_outcome: 'reopen', p_note: null }).then(function (r) {
        if (r.error || (r.data || {}).error) { msg('hirRecMsg', said(r), 'err'); return; }
        load();
      });
    });
    on('unscore', function () {
      rpc('hiring_score_remove', { p_id: c.id }).then(function (r) {
        var d = r.data || {};
        if (r.error || d.error) { msg('hirRecMsg', said(r), 'err'); return; }
        openRec(c.id).then(function () {
          if (bridge.undoHere) bridge.undoHere('Your scores were removed.', function () {
            return rpc('hiring_score_save', { p_id: c.id, p_scores: d.scores, p_recommend: d.recommend, p_note: d.note }).then(function () { openRec(c.id); });
          }, $('hirRecMsg'));
        });
      });
    });
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

  /* ---- Interview scorecards (Settings, Hiring; step C) -------------- */
  var PEN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 20h4L19 9l-4-4L4 16v4z"/><path d="m13.5 6.5 4 4"/></svg>';
  var hsc = { rows: null, wired: false };
  function hscMsg(t, k) { msg('hscMsg', t, k); }
  function hscRead() {
    return rpc('hiring_scorecards_list', {}).then(function (r) {
      var d = r.data || {};
      hsc.rows = r.error || d.error ? null : (d.rows || []);
      hsc.err = r.error || d.error ? r : null;
      hscPaint();
    });
  }
  function hscPaint() {
    var box = $('hscList');
    if (!box) return;
    if (hsc.err) { UI.failLine(box, 'the scorecards', said(hsc.err), hscRead); return; }
    if (!hsc.rows) { UI.skeleton(box, 3); return; }
    $('hscCount').textContent = hsc.rows.length + (hsc.rows.length === 1 ? ' scorecard' : ' scorecards');
    box.innerHTML = '<div class="ind-row ind-head is-hsc" aria-hidden="true"><span>Position</span><span>Criteria</span><span></span></div>' +
      hsc.rows.map(function (r) {
        return '<div class="ind-row is-hsc" data-id="' + esc(r.id) + '"><span class="ind-name hsc-pos">' + esc(r.position) + '</span>' +
          '<span class="hsc-crit">' + esc((r.criteria || []).join(' · ')) + '</span>' +
          '<span class="ind-acts"><button class="iconbtn" type="button" data-k="edit" aria-label="Edit ' + esc(r.position) + '" title="Edit">' + PEN + '</button>' +
          (r.standard ? '' : '<span class="team-act"><button class="kmenu-btn" type="button" data-k="menu" aria-label="More actions for ' + esc(r.position) + '" aria-expanded="false">' + DOTS + '</button>' +
            '<div class="kmenu" hidden role="menu"><button class="kmenu-item is-danger" data-g="6" type="button" role="menuitem" data-k="delete">Delete</button></div></span>') +
          '</span></div>';
      }).join('');
  }
  function hscAsk(r) {
    window.ADspaceConfirm.ask({ title: r ? 'Edit ' + r.position : 'Add scorecard', go: r ? 'Save' : 'Add scorecard', wait: true,
      fields: (r && r.standard ? [] : [{ name: 'pos', label: 'Position', value: r ? r.position : '', placeholder: 'Graphic Designer' }]).concat([
               { name: 'crit', label: 'Criteria', rows: 6, value: r ? (r.criteria || []).join('\n') : '', placeholder: 'One per line', note: '3 to 8 criteria, each scored 1 to 5.' }]) },
    function (v) {
      var crit = String(v.crit || '').split('\n').map(function (x) { return x.trim(); }).filter(Boolean);
      return rpc('hiring_scorecard_save', { p_id: r ? r.id : null, p_position: r && r.standard ? r.position : String(v.pos || '').trim(), p_criteria: crit }).then(function (x) {
        var d = x.data || {};
        if (d.error === 'taken') return 'This position already has a scorecard. Edit it instead.';
        if (x.error || d.error) return said(x);
        hscMsg('Saved.', 'ok'); hscRead();
        return '';
      });
    });
  }
  function openScorecards(opener) {
    var sh = $('hscSheet');
    if (!sh) return;
    if (!hsc.wired) {
      hsc.wired = true;
      $('hscCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
      $('hscClose').addEventListener('click', function () { $('hscCancel').click(); });
      $('hscAdd').addEventListener('click', function () { hscMsg(''); hscAsk(null); });
      $('hscList').addEventListener('click', function (e) {
        var b = e.target.closest('[data-k]'), row = b && b.closest('.ind-row');
        if (!row) return;
        var r = (hsc.rows || []).filter(function (x) { return x.id === row.getAttribute('data-id'); })[0];
        if (!r) return;
        var k = b.getAttribute('data-k');
        if (k === 'menu') {
          e.stopPropagation();
          var mn = row.querySelector('.kmenu'), open = mn.hidden;
          Array.prototype.forEach.call(document.querySelectorAll('#hscList .kmenu'), function (m) { m.hidden = true; });
          mn.hidden = !open; b.setAttribute('aria-expanded', String(open));
          if (open) { window.ADspaceMenu.tidy && window.ADspaceMenu.tidy(mn); window.ADspaceMenu.place(b, mn); }
          return;
        }
        if (k === 'edit') { hscMsg(''); hscAsk(r); return; }
        if (k === 'delete') {
          window.ADspaceConfirm.ask({ title: 'Delete', tone: 'danger', go: 'Delete', wait: true,
            body: 'The ' + r.position + ' scorecard will be deleted. Candidates for this position will be scored on the Standard scorecard. Scores already given are kept. This cannot be undone.' },
          function () {
            return rpc('hiring_scorecard_delete', { p_id: r.id }).then(function (x) {
              if (x.error || (x.data || {}).error) return said(x);
              hscMsg('Deleted.', 'ok'); hscRead(); return '';
            });
          });
        }
      });
    }
    hscMsg(''); hsc.rows = null; hsc.err = null; hscPaint();
    window.ADspaceSheet.show(sh, { opener: opener });
    hscRead();
  }

  window.ADspaceHiring = { enter: enter, urlState: urlState, openScorecards: openScorecards };
  /* Team opened on Hiring before this script arrived. */
  if ($('teamHiringPane') && !$('teamHiringPane').hidden) enter();
})();
