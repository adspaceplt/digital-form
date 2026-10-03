/*
 * Performance reviews — the monthly score, the breach log, the dispute and
 * the signed record.
 *
 * Two readers, one sheet. Management reads everybody's month from Team >
 * Performance, behind the master code; a colleague reads their own released
 * months from My performance in the account menu. What each is sent is the
 * database's decision (`perf_*` functions, no table readable directly), so
 * nothing here withholds anything: it draws what arrived.
 *
 * The rules — the six categories, the deduction and its cap, the grade caps,
 * the eligibility rule for a second Baseline month, the paths — are stated
 * once, in `perf_calc()`. This page shows the result the database worked
 * out and never works it out again, so the list, the sheet, the member's
 * view and the printed record cannot disagree.
 */
(function () {
  'use strict';
  var API = window.ADspaceAPI;
  var db = API && API.client;
  if (!API || !API.configured || !db) return;

  var $ = function (id) { return document.getElementById(id); };
  var bridge = window.ADspaceAdmin || {};
  var UI = window.ADspaceState;
  function may(k, l) { return bridge.may ? bridge.may(k, l) : false; }
  function me() { return bridge.me ? bridge.me() : null; }
  /* Deleting a month is an admin's alone (2026-09-27); the database asks again. */
  function isAdmin() { var u = me(); return Boolean(u && (u.is_admin || u.role === 'admin')); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function msg(id, text, kind) {
    var el = $(id); if (!el) return;
    el.textContent = text || ''; el.className = 'msg' + (kind ? ' ' + kind : '');
  }

  // ---- The framework's words ---------------------------------------------------
  var CATS = [
    ['output',     'Role output quality',              25],
    ['accuracy',   'Accuracy and compliance',          15],
    ['delivery',   'Delivery and reliability',         15],
    ['client',     'Client ownership',                 20],
    ['comms',      'Communication and collaboration',  15],
    ['initiative', 'Initiative and improvement',       10]
  ];
  var CAT_WORD = {};
  CATS.forEach(function (c) { CAT_WORD[c[0]] = c[1]; });
  var RATES = [
    ['posting',      'On-time posting',        95, 'delivery'],
    ['timeline',     'Timeline adherence',     90, 'delivery'],
    ['satisfaction', 'Client satisfaction',    90, 'client'],
    ['pacing',       'Budget pacing variance', 10, 'client'],
    ['sla',          'Response within SLA',    90, 'comms']
  ];
  var ROLE_WORD = window.ADspaceWords.roleStd;
  var ROLE_STD = {
    visual: 'Visual hierarchy, brand consistency, detail accuracy, clean handover. Choices reduce client revision risk.',
    video: 'Shot quality, editing flow, hook strength, retention, export accuracy. Improves watchability and performance.',
    planner: 'Campaign direction, content angles, brief clarity. Identifies weak accounts and proposes improvement.',
    account: 'Client servicing, posting accuracy, budget pacing, escalation. Proactively manages every account.'
  };
  var DEPT_WORD = window.ADspaceWords.dept;
  var BREACH_CAT = { client: 'Client and account risk', delivery: 'Delivery and execution risk',
                     compliance: 'Compliance and platform risk', asset: 'Asset and financial risk' };
  var SEV_WORD = { 1: 'Level 1 · Minor', 2: 'Level 2 · Moderate', 3: 'Level 3 · Major', 4: 'Level 4 · Critical' };
  var SEV_POINTS = { 1: -3, 2: -7, 3: -15, 4: -30 };
  var STATUS = { none: ['Not started', ''], draft: ['Draft', ''], released: ['Released', 'is-warn'],
                 disputed: ['Disputed', 'is-warn'], resolved: ['Resolved', 'is-warn'],
                 acknowledged: ['Acknowledged', ''], final: ['Final', 'is-ok'] };
  var GRADES = [['A', '90–100', 'Distinction'], ['B', '80–89', 'Strong'], ['C', '70–79', 'Baseline'],
                ['D', '60–69', 'Needs Guidance'], ['E', 'Under 60', 'Performance Review']];
  var GRADE_TONE = { A: 'is-ok', B: 'is-ok', C: '', D: 'is-warn', E: 'is-danger' };
  var ACTION = {
    A: 'Maintain standard and mentor where needed.',
    B: 'Maintain consistency.',
    C: 'Written improvement report or action plan for the next review cycle.',
    D: 'Intensive training, close guidance and a formal improvement plan.',
    E: 'Formal performance review is triggered.'
  };
  var PATH = {
    development: ['Development path', 'A work or skills shortfall with no client harmed. Repeated months move through a documented, staged improvement process.'],
    accountability: ['Accountability path', 'A breach occurred, or performance is critical. Forfeits this month\'s bonus, commission eligibility, trip and reward-linked benefits.']
  };
  var DECISION = { upheld: 'Upheld', partly: 'Partly upheld', not_upheld: 'Not upheld' };

  function dateWord(s) {
    if (!s) return '';
    var d = new Date(String(s).length === 10 ? s + 'T00:00:00' : s);
    if (isNaN(d)) return String(s);
    return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }).replace(/\bSep\b/, 'Sept');
  }
  function timeWord(s) {
    var d = new Date(s);
    if (isNaN(d)) return '';
    return dateWord(s) + ', ' + d.toLocaleTimeString('en-GB', { hour: 'numeric', minute: '2-digit', hour12: true }).replace(' ', '');
  }
  function monthWord(p) {
    var d = new Date(String(p).slice(0, 7) + '-01T00:00:00');
    return isNaN(d) ? String(p) : d.toLocaleDateString('en-GB', { month: 'long', year: 'numeric' });
  }
  function num(v) {
    if (v == null || v === '') return '—';
    var n = Number(v);
    return (Math.round(n * 10) / 10).toString();
  }
  function statusChip(s) {
    var w = STATUS[s || 'none'] || STATUS.none;
    return '<span class="chip ' + w[1] + '">' + esc(w[0]) + '</span>';
  }
  function gradeChip(res) {
    if (!res || !res.complete) return '<span class="perf-dash">—</span>';
    return '<span class="chip ' + (GRADE_TONE[res.grade] || '') + '">' + esc(res.grade + ' · ' + res.grade_word) + '</span>';
  }
  function rewardWord(res) {
    if (!res || !res.complete) return '—';
    return res.eligible ? 'Eligible' : 'Not eligible';
  }

  /* What the database said, in the team's words. */
  var SAID = {
    'no-code': 'No master code is set. Set it in the Supabase SQL editor.',
    'code-needed': 'Locked. Enter the master code again.',
    'denied': 'Your group cannot open performance reviews.',
    'not-team': 'Only a team member can open this.',
    'own-review': 'Your own review is not yours to change.',
    'not-draft': 'A released month keeps its scores. Revert it to draft to change them.',
    'incomplete': 'Score all six categories first.',
    'no-staff-code': 'Set their Employee ID on the Team page first. The reference is built from it.',
    'stale': 'Somebody else changed this review. It has been reloaded.',
    'bad-score': 'A score is outside its range.',
    'bad-rate': 'A rate is outside its range.',
    'bad-date': 'That date is not valid.',
    'bad-eval-date': 'The date of evaluation falls on or after the first day of the month reviewed, and not after today.',
    'bad-payload': 'That could not be saved.',
    'bad-category': 'Pick a category.',
    'bad-severity': 'Pick a lower level than the breach has now.',
    'what-needed': 'Say what happened.',
    'reason-needed': 'A reason is needed.',
    'cannot-return': 'Only a released month with no dispute can go back to draft.',
    'open-dispute': 'Answer the dispute first.',
    'not-released': 'Release it first.',
    'already-decided': 'Already answered.',
    'bad-decision': 'Pick a decision.',
    'dispute-closed': 'This month can no longer be disputed.',
    'window-closed': 'The time to dispute has passed.',
    'nothing-disputed': 'Tick at least one item.',
    'bad-item': 'That item cannot be disputed.',
    'not-final': 'Only a final record can be reopened.',
    'confirm-mismatch': 'The name and month typed do not match.',
    'admin-only': 'Only an admin can delete a record.',
    'not-found': 'Not found.'
  };
  function said(d) {
    if (!d || !d.error) return '';
    if (d.error === 'db') {
      return /Could not find the function|schema cache|PGRST202/i.test(d.message || '')
        ? 'This needs a database update. Ask an admin to run the latest migration.' : (d.message || 'Not saved.');
    }
    if (d.error === 'window-open') return 'The dispute window is open until ' + timeWord(d.until) + '.';
    if (d.error === 'month-released') return (d.month || 'That month') + ' is released. Return it to draft to change its breaches.';
    if (d.error === 'wrong-code') return 'Wrong code. ' + d.left + (d.left === 1 ? ' try' : ' tries') + ' left.';
    if (d.error === 'locked') return 'Too many wrong tries. Try again after ' + timeWord(d.until) + '.';
    if (d.error === 'bad-score' && d.max) return 'A score is 0 to ' + d.max + ', in steps of 0.1.';
    return SAID[d.error] || d.error;
  }

  // ---- The unlock ----------------------------------------------------------------
  /* The token the master code produced, for this tab only and never longer
     than the database keeps it: a reload inside the 15 minutes stays
     unlocked, closing the tab ends it here, and the database ends it after
     15 idle minutes whatever this page holds. */
  var TOKEN_KEY = 'adspace-perf-token';
  var token = null;
  function readToken() {
    try {
      var t = JSON.parse(sessionStorage.getItem(TOKEN_KEY) || 'null');
      if (t && t.until > Date.now()) return t.token;
    } catch (e) {}
    return null;
  }
  function keepToken(t) {
    token = t || null;
    try {
      if (t) sessionStorage.setItem(TOKEN_KEY, JSON.stringify({ token: t, until: Date.now() + 15 * 60 * 1000 }));
      else sessionStorage.removeItem(TOKEN_KEY);
    } catch (e) {}
  }

  function call(fn, args, then) {
    var done = false;
    var back = function (d) { if (done) return; done = true; then(d || {}); };
    try {
      db.rpc(fn, args || {}).then(function (r) {
        if (r.error) { back({ error: 'db', message: r.error.message }); return; }
        var d = r.data || {};
        if (args && args.p_token) {
          if (d.error === 'code-needed' || d.error === 'no-code') { lockedOut(d); back(d); return; }
          if (!d.error) keepToken(args.p_token);
        }
        back(d);
      }, function (e) { back({ error: 'db', message: String((e && e.message) || e) }); });
    } catch (e) { back({ error: 'db', message: String((e && e.message) || e) }); }
  }

  var st = {
    tab: 'members', urlRead: false,
    period: defaultPeriod(), month: null, find: '', filter: '',
    rec: null, mode: null, mine: null, editing: null, gate: null
  };
  /* A month is reviewed after it ends, so the page opens on the month just
     gone. */
  function defaultPeriod() {
    var d = new Date(); d.setDate(1); d.setMonth(d.getMonth() - 1);
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-01';
  }

  // ---- Team: the two tabs -----------------------------------------------------------
  function enterTeam() {
    if (!st.urlRead) {
      st.urlRead = true;
      var q = new URLSearchParams(location.search);
      if (q.get('tab') === 'performance') st.tab = 'performance';
      if (q.get('tab') === 'groups') st.tab = 'groups';
      if (/^\d{4}-\d{2}$/.test(q.get('m') || '')) st.period = q.get('m') + '-01';
      /* The rewards views (2026-09-28) and the quarter or period they show. */
      var pv = q.get('view'), qq = q.get('q');
      if (pv === 'quarters' || pv === 'company' || pv === 'commission') st.pv = pv;
      if (/^\d{4}-(01|04|07|10)$/.test(qq || '') && qq + '-01' >= FIRST_QUARTER) {
        if (st.pv === 'quarters') st.q = qq + '-01';
        if (st.pv === 'company') st.pf = halfOf(qq + '-01');
      }
    }
    var canMembers = may('team', 'view'), canPerf = may('team.performance', 'view');
    if (!canPerf && st.tab === 'performance') st.tab = 'members';
    if (!canMembers) st.tab = 'performance';
    /* Members and Groups are one permission and Performance another; the
       strip draws whenever there is more than one tab to choose. */
    $('teamTabs').hidden = !canMembers;
    $('teamTabMembers').hidden = !canMembers;
    $('teamTabGroups').hidden = !canMembers;
    $('teamTabPerf').hidden = !canPerf;
    Array.prototype.forEach.call(document.querySelectorAll('#teamTabs .tab'), function (b) {
      var on = b.getAttribute('data-tab') === st.tab;
      b.classList.toggle('is-on', on);
      b.setAttribute('aria-selected', String(on));
    });
    $('teamMembersPane').hidden = st.tab !== 'members';
    $('teamGroupsPane').hidden = st.tab !== 'groups';
    $('teamPerfPane').hidden = st.tab !== 'performance';
    $('perfLockBtn').hidden = st.tab !== 'performance';
    if (st.tab === 'members' || st.tab === 'groups') { if (window.ADspaceTeam) window.ADspaceTeam.enter(); }
    else enterPerf();
  }
  Array.prototype.forEach.call(document.querySelectorAll('#teamTabs .tab'), function (b) {
    b.addEventListener('click', function () {
      st.tab = b.getAttribute('data-tab');
      enterTeam();
      if (bridge.setUrl) bridge.setUrl();
    });
  });

  function enterPerf() {
    token = token || readToken();
    call('perf_gate_info', {}, function (g) {
      st.gate = g;
      if (g.error) { showLock(g); return; }
      if (!g.code_set) { showLock({ error: 'no-code' }); return; }
      if (g.locked_until) { showLock({ error: 'locked', until: g.locked_until }); return; }
      if (!token) { showLock(null); return; }
      loadView();
    });
  }

  /* The padlock beside Performance says which state the reviews are in. */
  var PAD_SHUT = '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>';
  var PAD_OPEN = '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 7.6-1.7"/></svg>';
  /* An edit carries its pen, as every Edit in the console does. */
  var PEN_MARK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>';
  function padlock(open) {
    var b = $('perfLockBtn');
    b.innerHTML = open ? PAD_OPEN : PAD_SHUT;
    b.classList.toggle('is-open', open);
    b.setAttribute('aria-label', open ? 'Unlocked. Lock performance reviews' : 'Locked');
    b.title = open ? 'Lock' : 'Locked';
  }
  function showLock(why) {
    padlock(false);
    $('perfLock').hidden = false;
    $('perfOpen').hidden = true;
    var blocked = why && (why.error === 'no-code' || why.error === 'denied' || why.error === 'db');
    $('perfLockForm').hidden = Boolean(blocked);
    msg('perfLockMsg', why ? said(why) : '', why ? (why.error === 'code-needed' || why.error === 'expired' ? '' : 'err') : '');
  }
  /* The database said the unlock has gone. Whatever was open closes, so a
     record is never left on the screen after the database stopped serving it. */
  function lockedOut(d) {
    keepToken(null);
    if (window.ADspaceSheet && window.ADspaceSheet.isOpen($('perfSheet')) && st.mode === 'manage') {
      window.ADspaceSheet.close();
    }
    st.month = null; st.flex = null; st.quarter = null; st.periodData = null; st.com = null;
    if (!$('teamPerfPane').hidden) showLock(d);
  }

  $('perfLockForm').addEventListener('submit', function (e) {
    e.preventDefault();
    var code = $('perfCode').value;
    if (!code) { msg('perfLockMsg', 'Enter the master code.', 'err'); return; }
    $('perfUnlock').disabled = true;
    call('perf_unlock', { p_code: code }, function (d) {
      $('perfUnlock').disabled = false;
      $('perfCode').value = '';
      if (d.error) { msg('perfLockMsg', said(d), 'err'); return; }
      keepToken(d.token);
      msg('perfLockMsg', '');
      loadView();
    });
  });

  $('perfLockBtn').addEventListener('click', function () {
    if (!$('perfLockBtn').classList.contains('is-open')) { if (!$('perfLockForm').hidden) $('perfCode').focus(); return; }
    lock(function () { showLock(null); msg('perfLockMsg', 'Locked.', ''); });
  });
  function lock(then) {
    var t = token || readToken();
    keepToken(null);
    st.month = null; st.flex = null; st.quarter = null; st.periodData = null; st.com = null;
    if (!t) { if (then) then(); return; }
    call('perf_lock', { p_token: t }, function () { if (then) then(); });
  }

  // ---- The month ----------------------------------------------------------------------
  var FIRST_MONTH = '2026-06-01';
  function monthOptions() {
    var sel = $('perfMonth'), out = [], d = new Date();
    d.setDate(1);
    /* Reviews begin with June 2026 (the user, 2026-09-24): no month before
       it is offered. */
    for (var i = 0; i < 13; i++) {
      var k = d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-01';
      if (k < FIRST_MONTH) break;
      out.push('<option value="' + k + '">' + esc(monthWord(k)) + '</option>');
      d.setMonth(d.getMonth() - 1);
    }
    sel.innerHTML = out.join('');
    if (!sel.querySelector('option[value="' + st.period + '"]')) {
      sel.insertAdjacentHTML('beforeend', '<option value="' + esc(st.period) + '">' + esc(monthWord(st.period)) + '</option>');
    }
    sel.value = st.period;
  }
  function loadMonth() {
    padlock(true);
    $('perfLock').hidden = true;
    $('perfOpen').hidden = false;
    monthOptions();
    if (!st.month) UI.skeleton($('perfList'), 4);
    call('perf_month', { p_token: token, p_period: st.period }, function (d) {
      if (d.error) {
        if (d.error === 'code-needed' || d.error === 'no-code') return;
        UI.failLine($('perfList'), 'The month', said(d), loadMonth);
        return;
      }
      st.month = d;
      paintMonth();
      loadFlex();
    });
  }
  $('perfMonth').addEventListener('change', function () {
    st.period = this.value;
    st.month = null; st.flex = null;
    loadMonth();
    if (bridge.setUrl) bridge.setUrl();
  });
  $('perfFind').addEventListener('input', function () {
    var v = this.value.trim().toLowerCase();
    if (v === st.find) return;
    st.find = v; paintMonth();
  });
  $('perfState').addEventListener('change', function () {
    if (this.value === st.filter) return;
    st.filter = this.value; paintMonth();
  });

  function stateOf(p) { return p.review ? p.review.status : 'none'; }
  function paintMonth() {
    var box = $('perfList');
    if (!st.month || st.pv !== 'months') return;
    var people = st.month.people || [];
    var shown = people.filter(function (p) {
      if (st.find && String(p.name || '').toLowerCase().indexOf(st.find) < 0) return false;
      if (st.filter && stateOf(p) !== st.filter) return false;
      return true;
    });
    /* The month is the people management put on the review list, and anybody
       whose review of this month has begun whatever the list now says. */
    var onList = function (p) { return p.reviewed || Boolean(p.review); };
    var reviewed = shown.filter(onList);
    var others = [];
    var all = people.filter(onList).length;
    $('perfCount').textContent = (st.find || st.filter)
      ? reviewed.length + ' of ' + all : all + (all === 1 ? ' person' : ' people');
    if (!all) {
      UI.emptyLine(box, 'Nobody on the review list.', may('team.performance', 'work') ? 'Review list' : '', openRoster);
      return;
    }
    if (!shown.length) {
      UI.emptyLine(box, 'No matches.', 'Clear the filters', function () {
        st.find = ''; st.filter = '';
        $('perfFind').value = ''; $('perfState').value = '';
        paintMonth();
      });
      return;
    }
    box.innerHTML = '';
    var G = window.ADspaceGroup;
    var filtered = Boolean(st.find || st.filter);
    var disputed = reviewed.filter(function (p) { return stateOf(p) === 'disputed'; }).length;
    box.appendChild(G.section({
      route: 'team-perf', key: 'reviewed', name: monthWord(st.period), count: reviewed.length,
      marks: disputed ? '<span class="chip is-warn">' + disputed + ' disputed</span>' : '',
      shut: false,
      table: function () { return perfTable(reviewed); }
    }));
    if (others.length) {
      box.appendChild(G.section({
        route: 'team-perf', key: 'not-reviewed', name: 'Not reviewed', count: others.length,
        shut: filtered ? false : G.shut('team-perf', 'not-reviewed', true),
        table: function () { return perfTable(others); }
      }));
    }
    var fx = flexSection();
    if (fx) box.appendChild(fx);
  }
  function perfTable(list) {
    var t = window.ADspaceGroup.table('perf-row', ['Person', 'Status', 'Score', 'Grade', 'Reward', '']);
    if (!list.length) {
      var e = document.createElement('div');
      e.className = 'emptyline'; e.innerHTML = '<b>Nobody.</b>';
      t.appendChild(e);
      return t;
    }
    window.ADspaceGroup.more(t, list, 30, '', perfRow);
    return t;
  }
  function perfRow(p) {
    var r = p.review, res = r && r.result;
    var el = document.createElement('div');
    el.className = 'crm-row perf-row';
    el.setAttribute('data-member', p.team_member_id);
    var meta = [DEPT_WORD[p.department], ROLE_WORD[p.role_family]].filter(Boolean);
    if (p.breaches) meta.push(p.breaches + (p.breaches === 1 ? ' breach' : ' breaches'));
    var sum = res && res.complete ? [num(res.final), res.grade_word, rewardWord(res)].filter(Boolean).join(' · ') : '';
    el.innerHTML =
      '<button class="perf-open" type="button"><b>' + esc(p.name) + '</b>' +
        (meta.length ? '<small>' + esc(meta.join(' · ')) + '</small>' : '') + '</button>' +
      '<span class="perf-state">' + statusChip(stateOf(p)) + '</span>' +
      '<span class="perf-score">' + (res && res.complete ? esc(num(res.final)) : '<span class="perf-dash">—</span>') + '</span>' +
      '<span class="perf-grade">' + gradeChip(res) + '</span>' +
      '<span class="perf-reward">' + esc(rewardWord(res)) + '</span>' +
      '<span class="perf-sum">' + esc(sum) + '</span>' +
      '<span class="team-act">' +
        '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' +
          '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg></button>' +
        '<div class="kmenu" data-menu hidden><button class="kmenu-item" data-a="profile" type="button"><b>Review profile</b></button>' +
          (r && r.id && isAdmin() ? '<button class="kmenu-item is-danger" data-a="delete" type="button">Delete</button>' : '') + '</div>' +
      '</span>';
    el.querySelector('.perf-open').addEventListener('click', function () { openReview(p.team_member_id, this); });
    var btn = el.querySelector('[data-a="menu"]'), menu = el.querySelector('[data-menu]');
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      var open = menu.hidden;
      shutRowMenus();
      menu.hidden = !open;
      btn.setAttribute('aria-expanded', String(open));
      if (open) window.ADspaceMenu.place(btn, menu);
    });
    el.querySelector('[data-a="profile"]').addEventListener('click', function () {
      shutRowMenus();
      openProfile(p, btn);
    });
    var delBtn = el.querySelector('[data-a="delete"]');
    if (delBtn) delBtn.addEventListener('click', function () {
      shutRowMenus();
      askDelete({ id: r.id, status: r.status, name: p.name, month: st.month && st.month.month }, btn);
    });
    return el;
  }
  /* Delete a member's month (an admin, any state). The name and the month
     are typed back and a reason given; the sheet says what the member has
     already seen, and that a downloaded copy then reads Void on the verify
     page. There is no restore. */
  var SEEN = { released: 'released to them', disputed: 'disputed by them', resolved: 'answered',
               acknowledged: 'acknowledged by them', 'final': 'final' };
  function askDelete(rec, opener) {
    if (!rec.id || !window.ADspaceConfirm) return;
    var typed = (rec.name + ' ' + (rec.month || '')).trim();
    var seen = rec.status && rec.status !== 'draft'
      ? 'This month has been ' + (SEEN[rec.status] || 'released') + '. A downloaded copy will read Void on the verify page. '
      : '';
    /* The ⋯ has shut, so its button holds the focus the sheet hands back. */
    if (opener && opener.focus) opener.focus();
    window.ADspaceConfirm.ask({
      title: 'Delete ' + rec.name + '\u2019s ' + (rec.month || 'month'),
      body: seen + 'The review, its scores and any dispute go, and there is no restore. The history keeps who deleted it and why.',
      go: 'Delete', tone: 'danger',
      fields: [
        { name: 'who', label: 'Type ' + typed + ' to confirm', match: typed, mismatch: 'Type ' + typed + ' to confirm.' },
        { name: 'why', label: 'Reason', need: 'A reason is required.' }
      ]
    }, function (v) {
      call('perf_delete', { p_token: token, p_review: rec.id, p_confirm: v.who, p_reason: v.why }, function (d) {
        var where = rec.sheet ? 'pvMsg' : 'perfMsg';
        if (d.error) { msg(where, said(d), 'err'); return; }
        if (rec.sheet && window.ADspaceSheet) window.ADspaceSheet.close();
        msg('perfMsg', rec.name + '\u2019s ' + (d.month || rec.month || 'month') + ' deleted.', 'ok');
        loadMonth();
      });
    });
  }
  function shutRowMenus() {
    Array.prototype.forEach.call(document.querySelectorAll('#perfList .kmenu'), function (m) { m.hidden = true; });
    Array.prototype.forEach.call(document.querySelectorAll('#perfList .kmenu-btn'), function (b) { b.setAttribute('aria-expanded', 'false'); });
  }
  if (window.ADspaceMenu) window.ADspaceMenu.onScroll(shutRowMenus);
  document.addEventListener('click', function (e) {
    if (!e.target.closest || !e.target.closest('#perfList .team-act')) shutRowMenus();
  });

  // ---- The review list -----------------------------------------------------------------
  /* A tick per colleague, Employee ID first and A to Z. A tick added puts
     them on from this month; one taken off takes them off from the next,
     because a review already begun this month stays where it is. */
  function openRoster() {
    if (!st.month) return;
    var F = window.ADspaceForm;
    var people = (st.month.people || []).slice().sort(F.byStaff);
    $('prList').innerHTML = people.map(function (p) {
      return '<label class="tickline"><input type="checkbox" data-id="' + esc(p.team_member_id) + '"' +
        (p.reviewed ? ' checked' : '') + '> <span>' + esc(F.named(p.staff_code, p.name)) + '</span></label>';
    }).join('');
    msg('prMsg', '');
    window.ADspaceSheet.show($('perfRosterSheet'), { opener: $('perfRosterBtn') });
  }
  $('perfRosterBtn').addEventListener('click', openRoster);
  $('prClose').addEventListener('click', function () { window.ADspaceSheet.close(); });
  $('prCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
  $('prSave').addEventListener('click', function () {
    var btn = this;
    var was = {};
    (st.month.people || []).forEach(function (p) { was[p.team_member_id] = Boolean(p.reviewed); });
    var changes = Array.prototype.filter.call($('prList').querySelectorAll('input[data-id]'), function (c) {
      return c.checked !== was[c.getAttribute('data-id')];
    });
    if (!changes.length) { window.ADspaceSheet.close(); return; }
    btn.disabled = true;
    var left = changes.length, failed = null;
    changes.forEach(function (c) {
      call('perf_profile_set', { p_token: token, p_member: c.getAttribute('data-id'), p_payload: { reviewed: c.checked } }, function (d) {
        if (d.error) failed = failed || d;
        if (--left) return;
        btn.disabled = false;
        if (failed) { msg('prMsg', said(failed), 'err'); return; }
        window.ADspaceSheet.clean();
        window.ADspaceSheet.close();
        loadMonth();
      });
    });
  });

  // ---- The review profile ---------------------------------------------------------------
  var profileFor = null;
  function openProfile(p, opener) {
    profileFor = p;
    $('ppTitle').textContent = p.name;
    /* Department and role standard are set on the Members tab and only read
       here; Edit on Members opens that person's own sheet there. */
    $('ppFacts').innerHTML = [['Department', DEPT_WORD[p.department]], ['Role standard', ROLE_WORD[p.role_family]]]
      .map(function (f) {
        return '<div><dt>' + f[0] + '</dt><dd' + (f[1] ? '' : ' class="is-empty"') + '>' + esc(f[1] || 'Not set') + '</dd></div>';
      }).join('');
    $('ppEditTeam').hidden = !(may('team', 'manage') && window.ADspaceTeam && window.ADspaceTeam.edit);
    $('ppAds').checked = Boolean(p.runs_ads);
    $('ppReviewed').checked = Boolean(p.reviewed);
    msg('ppMsg', '');
    window.ADspaceSheet.show($('perfProfileSheet'), { opener: opener });
  }
  $('ppClose').addEventListener('click', function () { window.ADspaceSheet.close(); });
  $('ppCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
  $('ppEditTeam').addEventListener('click', function () {
    if (!profileFor) return;
    var id = profileFor.team_member_id;
    window.ADspaceSheet.close();
    st.tab = 'members';
    enterTeam();
    if (bridge.setUrl) bridge.setUrl();
    window.ADspaceTeam.edit(id);
  });
  $('ppSave').addEventListener('click', function () {
    if (!profileFor) return;
    var btn = this; btn.disabled = true;
    call('perf_profile_set', { p_token: token, p_member: profileFor.team_member_id, p_payload: {
      runs_ads: $('ppAds').checked, reviewed: $('ppReviewed').checked } }, function (d) {
      btn.disabled = false;
      if (d.error) { msg('ppMsg', said(d), 'err'); return; }
      window.ADspaceSheet.clean();
      window.ADspaceSheet.close();
      msg('perfMsg', 'Saved.', 'ok');
      loadMonth();
    });
  });

  // ---- One review, in the sheet --------------------------------------------------------
  function openReview(memberId, opener) {
    st.mode = 'manage';
    st.editing = null;
    showSheet(opener);
    UI.skeleton($('pvBody'), 4);
    call('perf_open', { p_token: token, p_member: memberId, p_period: st.period }, function (d) {
      if (d.error) {
        if (d.error === 'code-needed' || d.error === 'no-code') return;
        $('pvBody').innerHTML = '';
        UI.failLine($('pvBody'), 'The review', said(d), function () { openReview(memberId); });
        return;
      }
      st.rec = d;
      paintSheet();
    });
  }
  function reread(then) {
    var r = st.rec;
    if (st.mode === 'mine') {
      call('perf_mine', {}, function (d) {
        if (d.error) return;
        st.mine = d.reviews || [];
        var fresh = st.mine.filter(function (x) { return x.id === r.id; })[0];
        if (fresh) { st.rec = fresh; paintSheet(); }
        paintMine();
        if (then) then();
      });
      return;
    }
    call('perf_open', { p_token: token, p_member: r.team_member_id, p_period: r.period }, function (d) {
      if (d.error) return;
      st.rec = d; paintSheet();
      if (then) then();
    });
  }

  var sheetDirty = false;
  function showSheet(opener) {
    sheetDirty = false;
    $('pvTitle').textContent = '';
    $('pvCtx').hidden = true;
    $('pvStatus').textContent = '';
    $('pvStatus').className = 'chip';
    $('pvRef').hidden = true;
    $('pvMenuWrap').hidden = true;
    window.ADspaceSheet.show($('perfSheet'), {
      opener: opener,
      onClose: function () {
        var dirty = sheetDirty;
        st.rec = null; st.editing = null;
        if (dirty && st.mode === 'manage' && token) loadMonth();
      }
    });
    var body = $('pvBody'); if (body) body.scrollTop = 0;
  }
  $('pvClose').addEventListener('click', function () { window.ADspaceSheet.close(); });

  /* The ⋯ answers Escape before the sheet under it does. */
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape' || $('pvMenu').hidden) return;
    e.preventDefault(); e.stopImmediatePropagation();
    shutPvMenu(); $('pvMenuBtn').focus();
  }, true);
  function shutPvMenu() { $('pvMenu').hidden = true; $('pvMenuBtn').setAttribute('aria-expanded', 'false'); }
  $('pvMenuBtn').addEventListener('click', function (e) {
    e.stopPropagation();
    var open = $('pvMenu').hidden;
    $('pvMenu').hidden = !open;
    this.setAttribute('aria-expanded', String(open));
    if (open) window.ADspaceMenu.place(this, $('pvMenu'));
  });
  document.addEventListener('click', function (e) {
    if (!$('pvMenu').hidden && !e.target.closest('#pvMenuWrap')) shutPvMenu();
  });
  Array.prototype.forEach.call($('pvMenu').querySelectorAll('.kmenu-item'), function (b) {
    b.addEventListener('click', function () {
      shutPvMenu();
      var a = b.getAttribute('data-a');
      if (a === 'print') { printOne(st.rec, $('pvMenuBtn')); return; }
      if (a === 'delete') {
        var rr = st.rec || {};
        askDelete({ id: rr.id, status: rr.status, name: (rr.member && rr.member.name) || '', month: rr.month, sheet: true }, $('pvMenuBtn'));
        return;
      }
      st.editing = a;
      paintSheet();
      var f = $('pvReason'); if (f) f.focus();
    });
  });

  function manage() { return st.mode === 'manage'; }
  function canWork() { return manage() && may('team.performance', 'work'); }

  function paintSheet() {
    var r = st.rec;
    if (!r) return;
    var res = r.result || {};
    var m = r.member || {};
    $('pvTitle').textContent = manage() ? (m.name || '') : r.month;
    var ctx = manage()
      ? [r.month, DEPT_WORD[m.department], ROLE_WORD[m.role_family]].filter(Boolean).join(' · ')
      : (r.reviewer ? 'Reviewed by ' + r.reviewer : '');
    $('pvCtx').textContent = ctx;
    $('pvCtx').hidden = !ctx;
    var w = STATUS[r.id ? r.status : 'none'] || STATUS.none;
    $('pvStatus').textContent = w[0];
    $('pvStatus').className = 'chip ' + w[1];
    $('pvRef').hidden = !r.serial;
    $('pvRef').textContent = r.serial || '';
    $('pvRef').setAttribute('aria-label', r.serial ? 'Copy ' + r.serial : '');
    var items = {
      print: Boolean(r.id) && r.status !== 'draft',
      'return': canWork() && r.status === 'released' && !(r.disputes || []).length,
      reopen: manage() && may('team.performance', 'manage') && r.status === 'final',
      'delete': manage() && isAdmin() && Boolean(r.id)
    };
    var any = false;
    Array.prototype.forEach.call($('pvMenu').querySelectorAll('.kmenu-item'), function (b) {
      var on = Boolean(items[b.getAttribute('data-a')]);
      b.hidden = !on; any = any || on;
    });
    $('pvMenuWrap').hidden = !any;

    var draft = manage() && canWork() && r.status === 'draft';
    var html = nextCard(r, res) + resultCard(r, res) +
      (draft ? scoreForm(r, res) : scoreRead(r, res)) +
      (manage() ? (draft ? rateForm(r, res) : rateRead(r)) : '') +
      breachCard(r, draft) + planCard(r) + disputeCard(r, res) +
      (manage() ? historyCard(r) : '');
    $('pvBody').innerHTML = html;
    wireSheet(r);
  }

  function card(title, inner, act, id) {
    return '<section class="qcard"' + (id ? ' id="' + id + '"' : '') + '>' +
      (act ? '<div class="qcard-head"><h3 class="qcard-title">' + esc(title) + '</h3>' + act + '</div>'
           : '<h3 class="qcard-title">' + esc(title) + '</h3>') + inner + '</section>';
  }

  /* One next step, derived from the record, and the action that takes it. */
  function nextCard(r, res) {
    var title = '', line = '', acts = '', tick = '';
    var dUntil = r.dispute_until ? timeWord(r.dispute_until) : '';
    var open = r.dispute_open;
    if (st.editing === 'return' || st.editing === 'reopen') {
      var ret = st.editing === 'return';
      return '<section class="qcard qnext">' +
        '<h3 class="qnext-title">' + (ret ? 'Revert to draft' : 'Reopen') + '</h3>' +
        '<p class="qnext-line">' + esc(ret
          ? (r.member.name || 'They') + ' stops seeing this month until it is released again.'
          : 'A new version is opened in draft with the same reference. The final version is kept on the record.') + '</p>' +
        '<form class="qform" id="pvReasonForm" autocomplete="off">' +
          '<label class="field-label" for="pvReason">Reason</label>' +
          '<textarea class="input" id="pvReason" rows="2" maxlength="500"></textarea>' +
          '<div class="qform-acts"><button class="btn btn-sm btn-warn" type="submit">' + (ret ? 'Revert' : 'Reopen') + '</button>' +
          '<button class="btn btn-sm btn-quiet" type="button" data-a="cancel">Cancel</button></div>' +
        '</form><div class="msg" id="pvMsg"></div></section>';
    }
    if (manage()) {
      var name = (r.member && r.member.name) || 'They';
      if (!r.id || r.status === 'draft') {
        title = r.id ? 'Draft' : 'Not started';
        line = name + ' sees nothing of this month, breaches included, until it is released.';
        if (canWork()) {
          /* Whether the release tells them: ticked unless management says
             otherwise, on every month (2026-09-27). */
          tick = '<label class="tickline perf-notify"><input type="checkbox" id="pvNotify" checked> <span>Notify ' + esc(name) + '</span></label>';
          acts = '<button class="btn btn-sm btn-primary" id="pvSave" type="button">Save</button>' +
                 '<button class="btn btn-sm btn-go" id="pvRelease" type="button">Release to ' + esc(name) + '</button>';
        }
      } else if (r.status === 'released') {
        title = 'Released';
        line = open ? name + ' may dispute it until ' + dUntil + '.' : 'The dispute window has closed. Waiting for acknowledgement.';
        if (canWork()) acts = '<button class="btn btn-sm btn-primary" id="pvFinal" type="button"' + (open ? ' disabled' : '') + '>Finalise</button>';
      } else if (r.status === 'disputed') {
        var n = (r.disputes || []).filter(function (x) { return !x.decision; }).length;
        title = 'Disputed';
        line = n + (n === 1 ? ' item is' : ' items are') + ' waiting for your answer below.';
      } else if (r.status === 'resolved') {
        title = 'Dispute answered';
        line = open ? 'Waiting for acknowledgement.' : 'Waiting for acknowledgement. It may be finalised now.';
        if (canWork()) acts = '<button class="btn btn-sm btn-primary" id="pvFinal" type="button"' + (open ? ' disabled' : '') + '>Finalise</button>';
      } else if (r.status === 'acknowledged') {
        title = 'Acknowledged';
        line = name + ' acknowledged it on ' + timeWord(r.acknowledged_at) + '.';
        if (canWork()) acts = '<button class="btn btn-sm btn-primary" id="pvFinal" type="button">Finalise</button>';
      } else if (r.status === 'final') {
        title = 'Final';
        line = 'Finalised on ' + timeWord(r.finalised_at) + (r.finalised_by ? ' by ' + r.finalised_by : '') + '.';
        acts = '<button class="btn btn-sm" id="pvPrint" type="button">Download PDF</button>';
      }
    } else {
      if (r.status === 'released' && open) {
        title = 'Your review is ready';
        line = 'Acknowledge it, or dispute any part of it by ' + dUntil + '.';
        acts = '<button class="btn btn-sm btn-go" id="pvAck" type="button">Acknowledge</button>' +
               '<button class="btn btn-sm" id="pvDisputeGo" type="button">Dispute</button>';
      } else if (r.status === 'released') {
        title = 'Your review is ready';
        line = 'The time to dispute has passed.';
        acts = '<button class="btn btn-sm btn-go" id="pvAck" type="button">Acknowledge</button>';
      } else if (r.status === 'disputed') {
        title = 'Dispute sent';
        line = 'Waiting for an answer.';
      } else if (r.status === 'resolved') {
        title = 'Your dispute has been answered';
        line = 'Read the answer below, then acknowledge.';
        acts = '<button class="btn btn-sm btn-go" id="pvAck" type="button">Acknowledge</button>';
      } else if (r.status === 'acknowledged') {
        title = 'Acknowledged';
        line = 'You acknowledged it on ' + timeWord(r.acknowledged_at) + '.';
      } else if (r.status === 'final') {
        title = 'Final';
        line = 'This is the record for ' + r.month + '.';
      }
      if (r.status !== 'draft') acts += '<button class="btn btn-sm btn-quiet" id="pvPrint" type="button">Download PDF</button>';
    }
    var ackNote = !manage() && acts.indexOf('pvAck') > -1
      ? '<p class="perf-note">Acknowledging records that the review was discussed and the result was shown. It is not necessarily agreement with the rating.</p>' : '';
    return '<section class="qcard qnext"><h3 class="qnext-title">' + esc(title) + '</h3>' +
      '<p class="qnext-line">' + esc(line) + '</p>' + ackNote + tick +
      (acts ? '<div class="qnext-acts">' + acts + '</div>' : '') +
      '<div class="msg" id="pvMsg"></div></section>';
  }

  function resultCard(r, res) {
    if (!res.complete) {
      return card('Result', '<p class="perf-quiet">Scored ' + num(res.base) + ' of 100 so far. The grade is worked out once all six categories are scored.</p>');
    }
    var lines = [];
    if (res.capped) lines.push('Grade capped at ' + res.capped + ' by a Level ' + (res.capped === 'D' ? '4' : '3') + ' breach.');
    if (res.review) lines.push('Management review is triggered.');
    if (res.grade === 'C' && res.previous_grade === 'C') lines.push('Baseline again after a Baseline month, so not reward eligible.');
    var path = res.path && PATH[res.path];
    return card('Result',
      '<div class="perf-result">' +
        '<span class="perf-grade-big ' + (GRADE_TONE[res.grade] || '') + '">' + esc(res.grade) + '</span>' +
        '<span class="perf-grade-words"><b>' + esc(res.grade_word) + '</b><small>' + esc(num(res.final)) + ' of 100 · ' + esc(rewardWord(res)) + '</small></span>' +
      '</div>' +
      '<dl class="tfacts perf-facts perf-sums">' +
        '<div><dt>Base score</dt><dd>' + esc(num(res.base)) + '</dd></div>' +
        '<div><dt>Breaches</dt><dd>' + esc(res.deduction ? num(res.deduction) : '0') + (res.deduction_raw < res.deduction ? '<small>Capped at 35 from ' + esc(num(-res.deduction_raw)) + '</small>' : '') + '</dd></div>' +
        '<div><dt>Final score</dt><dd>' + esc(num(res.final)) + '</dd></div>' +
        '<div><dt>What it asks</dt><dd>' + esc(ACTION[res.grade] || '') + '</dd></div>' +
        (path ? '<div><dt>If it repeats</dt><dd>' + esc(path[0]) + '<small>' + esc(path[1]) + '</small></dd></div>' : '') +
      '</dl>' +
      (lines.length ? '<p class="perf-note">' + esc(lines.join(' ')) + '</p>' : '') +
      '');
  }

  function roleLine(r) {
    var fam = r.member && r.member.role_family;
    return fam ? '<small class="perf-std">' + esc(ROLE_WORD[fam] + ': ' + ROLE_STD[fam]) + '</small>' : '';
  }
  function scoreRead(r) {
    var rows = CATS.map(function (c) {
      var note = (r.notes || {})[c[0]];
      return '<div class="perf-cat"><span class="perf-cat-name">' + esc(c[1]) +
        (c[0] === 'output' ? roleLine(r) : '') +
        (note ? '<small class="perf-cat-note">' + esc(note) + '</small>' : '') + '</span>' +
        '<span class="perf-cat-val">' + esc(num((r.scores || {})[c[0]])) + '<small> / ' + c[2] + '</small></span></div>';
    }).join('');
    return card('Scores', '<div class="perf-cats">' + rows + '</div>');
  }
  function scoreForm(r, res) {
    var sug = res.suggested || {};
    var rows = CATS.map(function (c) {
      var k = c[0], v = (r.scores || {})[k], s = sug[k];
      return '<div class="perf-cat is-edit">' +
        '<span class="perf-cat-name"><label for="pvS_' + k + '">' + esc(c[1]) + '</label>' +
          (k === 'output' ? roleLine(r) : '') +
          (s != null ? '<button class="linkbtn perf-use" type="button" data-use="' + k + '" data-v="' + s + '">Suggested ' + esc(num(s)) + ' from the rates</button>' : '') +
        '</span>' +
        '<span class="perf-cat-val"><input class="input input-sm perf-num" id="pvS_' + k + '" type="number" inputmode="decimal" min="0" max="' + c[2] + '" step="0.5" value="' + (v == null ? '' : esc(v)) + '"><small> / ' + c[2] + '</small></span>' +
        '<textarea class="input perf-evidence" id="pvN_' + k + '" rows="1" maxlength="2000" placeholder="Evidence" aria-label="' + esc(c[1]) + ' evidence">' + esc((r.notes || {})[k] || '') + '</textarea>' +
      '</div>';
    }).join('');
    return card('Scores', '<div class="perf-cats">' + rows + '</div>');
  }
  function rateLabel(x, ads) {
    return x[0] === 'pacing' ? x[1] + ', target ' + x[2] + '% or under' : x[1] + ', target ' + x[2] + '%';
  }
  function rateForm(r) {
    var ads = r.member && r.member.runs_ads;
    var ops = r.ops;
    var rows = RATES.filter(function (x) { return x[0] !== 'pacing' || ads; }).map(function (x) {
      var v = (r.rates || {})[x[0]];
      return '<div class="perf-rate"><label class="field-label" for="pvR_' + x[0] + '">' + esc(rateLabel(x)) + '</label>' +
        '<span class="perf-pct"><input class="input input-sm perf-num" id="pvR_' + x[0] + '" type="number" inputmode="decimal" min="0" max="' + (x[0] === 'pacing' ? 1000 : 100) + '" step="0.1" value="' + (v == null ? '' : esc(v)) + '"><small>%</small></span>' +
        (x[0] === 'posting' && ops && ops.done
          ? '<button class="linkbtn perf-use" type="button" data-rate="posting" data-v="' + Math.round(ops.on_time / ops.done * 1000) / 10 + '">My Work: ' + ops.on_time + ' of ' + ops.done + ' tasks finished on time</button>' : '') +
        '</div>';
    }).join('');
    return card('Rates behind the scores', '<div class="perf-rates">' + rows + '</div>');
  }
  function rateRead(r) {
    var ads = r.member && r.member.runs_ads;
    var rows = RATES.filter(function (x) { return x[0] !== 'pacing' || ads; }).map(function (x) {
      var v = (r.rates || {})[x[0]];
      return '<div><dt>' + esc(x[1]) + '</dt><dd>' + (v == null ? '—' : esc(num(v)) + '%') + '</dd></div>';
    }).join('');
    return card('Rates behind the scores', '<dl class="tfacts perf-facts">' + rows + '</dl>');
  }

  function breachCard(r, draft) {
    var list = r.breaches || [];
    var rows = list.map(function (b) {
      var flags = [];
      if (b.repeated) flags.push('Repeated in the quarter');
      if (b.late) flags.push('Late disclosure');
      var voiding = st.editing === 'void:' + b.id;
      return '<div class="perf-breach" data-breach="' + esc(b.id) + '">' +
        '<div class="perf-breach-top"><b>' + esc(SEV_WORD[b.severity]) + '</b><span class="perf-breach-pts">' + esc(num(b.deduction)) + '</span></div>' +
        '<p class="perf-breach-what">' + esc(b.what) + '</p>' +
        '<small>' + esc([dateWord(b.occurred_on), BREACH_CAT[b.category]].concat(flags).join(' · ')) + '</small>' +
        (b.evidence && manage() ? '<small class="perf-breach-ev">' + esc(b.evidence) + '</small>' : '') +
        (draft && !voiding ? '<button class="btn btn-quiet btn-sm perf-void" type="button" data-void="' + esc(b.id) + '">Void</button>' : '') +
        (voiding ? '<form class="qform" id="pvVoidForm" autocomplete="off"><label class="field-label" for="pvVoidWhy">Why is it void?</label>' +
          '<input class="input" id="pvVoidWhy" maxlength="300"><div class="qform-acts">' +
          '<button class="btn btn-sm btn-warn" type="submit">Void</button><button class="btn btn-sm btn-quiet" type="button" data-a="cancel">Cancel</button></div></form>' : '') +
      '</div>';
    }).join('');
    var empty = list.length ? '' : '<p class="perf-quiet">None recorded.</p>';
    var act = draft && r.id !== undefined && st.editing !== 'breach'
      ? '<button class="btn btn-quiet btn-sm qcard-act" id="pvBreachAdd" type="button"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>Log breach</button>' : '';
    var form = draft && st.editing === 'breach' ? breachForm(r) : '';
    return card('Breaches this month', empty + rows + form, act, 'pvBreaches');
  }
  function breachForm(r) {
    var today = new Date(), p = new Date(r.period + 'T00:00:00');
    var last = new Date(p.getFullYear(), p.getMonth() + 1, 0);
    var day = today < last ? today : last;
    var iso = day.getFullYear() + '-' + String(day.getMonth() + 1).padStart(2, '0') + '-' + String(day.getDate()).padStart(2, '0');
    var opt = function (o) { return Object.keys(o).map(function (k) { return '<option value="' + k + '">' + esc(o[k]) + '</option>'; }).join(''); };
    return '<form class="qform" id="pvBreachForm" autocomplete="off">' +
      '<div class="row"><div><label class="field-label" for="pvBDate">Date</label><input class="input" id="pvBDate" type="date" value="' + iso + '" min="' + r.period + '" max="' + iso + '"></div>' +
      '<div><label class="field-label" for="pvBSev">Severity</label><select class="select" id="pvBSev">' +
        Object.keys(SEV_WORD).map(function (k) { return '<option value="' + k + '">' + esc(SEV_WORD[k] + ' (' + SEV_POINTS[k] + ')') + '</option>'; }).join('') + '</select></div></div>' +
      '<div class="row"><div><label class="field-label" for="pvBCat">Category</label><select class="select" id="pvBCat">' + opt(BREACH_CAT) + '</select></div>' +
      '<div><label class="field-label" for="pvBRep">Repeated in the quarter</label><select class="select" id="pvBRep"><option value="">Work it out</option><option value="yes">Yes (−5)</option><option value="no">No</option></select></div></div>' +
      '<label class="field-label" for="pvBWhat">Breach description</label><textarea class="input" id="pvBWhat" rows="2" maxlength="1000"></textarea>' +
      '<label class="field-label" for="pvBEv">Evidence</label><input class="input" id="pvBEv" maxlength="500" placeholder="Link or reference">' +
      '<label class="tickline"><input type="checkbox" id="pvBLate"> <span>Hidden or reported late (−5)</span></label>' +
      '<div class="qform-acts"><button class="btn btn-sm btn-primary" type="submit">Log breach</button>' +
      '<button class="btn btn-sm btn-quiet" type="button" data-a="cancel">Cancel</button></div></form>';
  }

  /* What the month asks of the person next: written at the 1-1, so it stays
     editable until the record is final. */
  function planCard(r) {
    var edit = canWork() && r.status !== 'final';
    if (!edit) {
      if (!r.improvement && !r.review_by && !r.reward_step && !r.evaluated_on) {
        return manage() || r.status === 'final' ? card('Evaluation and follow-up', '<p class="perf-quiet">None set.</p>') : '';
      }
      return card('Evaluation and follow-up', '<dl class="tfacts perf-facts">' +
        (r.evaluated_on ? '<div><dt>Date of evaluation</dt><dd>' + esc(dateWord(r.evaluated_on)) + '</dd></div>' : '') +
        (r.improvement ? '<div><dt>Improvement</dt><dd>' + esc(r.improvement) + '</dd></div>' : '') +
        (r.review_by ? '<div><dt>Follow-up date</dt><dd>' + esc(dateWord(r.review_by)) + '</dd></div>' : '') +
        (r.reward_step ? '<div><dt>Step or reward</dt><dd>' + esc(r.reward_step) + '</dd></div>' : '') + '</dl>');
    }
    /* The day of the 1-1: in or after the month reviewed, never ahead of
       today in Malaysia, so a month keyed in later keeps its real date. */
    var today = new Date(Date.now() + 8 * 3600000).toISOString().slice(0, 10);
    return card('Evaluation and follow-up',
      '<div class="perf-plan"><div class="row fgrid"><div><label class="field-label" for="pvEval">Date of evaluation</label><input class="input" id="pvEval" type="date" min="' + esc(r.period) + '" max="' + today + '" value="' + esc(r.evaluated_on || '') + '"></div>' +
      '<div><label class="field-label" for="pvBy">Follow-up date</label><input class="input" id="pvBy" type="date" value="' + esc(r.review_by || '') + '"></div></div>' +
      '<div><label class="field-label" for="pvImp">Improvement</label>' +
      '<textarea class="input" id="pvImp" rows="3" maxlength="4000">' + esc(r.improvement || '') + '</textarea></div>' +
      '<div><label class="field-label" for="pvStep">Step or reward to apply</label><input class="input" id="pvStep" maxlength="500" value="' + esc(r.reward_step || '') + '"></div>' +
      (r.status !== 'draft' ? '<div class="qform-acts"><button class="btn btn-sm btn-primary" id="pvPlanSave" type="button">Save</button></div>' : '') +
      '</div>');
  }

  function itemWord(d) {
    if (d.item === 'breach') return 'Breach' + (d.breach_what ? ': ' + d.breach_what : '');
    return CAT_WORD[d.item] || d.item;
  }
  function disputeCard(r, res) {
    var list = r.disputes || [];
    var mineForm = !manage() && r.dispute_open && st.editing === 'dispute';
    if (!list.length && !mineForm) return '';
    var rows = list.map(function (d) {
      var dec = d.decision;
      var decide = manage() && canWork() && r.status === 'disputed' && !dec;
      var change = '';
      if (dec && dec !== 'not_upheld') {
        change = d.item === 'breach'
          ? (dec === 'upheld' ? 'Breach removed.' : 'Lowered to ' + SEV_WORD[d.after_value] + '.')
          : 'Score ' + num(d.before_value) + ' to ' + num(d.after_value) + '.';
      }
      return '<div class="perf-dispute">' +
        '<div class="perf-breach-top"><b>' + esc(itemWord(d)) + '</b>' +
          (dec ? '<span class="chip ' + (dec === 'not_upheld' ? '' : 'is-ok') + '">' + esc(DECISION[dec]) + '</span>' : '<span class="chip is-warn">Waiting</span>') + '</div>' +
        '<p class="perf-breach-what">' + esc(d.reason) + '</p>' +
        (dec ? '<p class="perf-answer"><small>' + esc((d.decided_by || 'Answered') + ', ' + timeWord(d.decided_at)) + '</small>' + esc(d.response) + (change ? ' ' + esc(change) : '') + '</p>' : '') +
        (decide ? decideForm(d, r) : '') +
      '</div>';
    }).join('');
    return card('Dispute', rows + (mineForm ? disputeForm(r) : ''), '', 'pvDispute');
  }
  function decideForm(d, r) {
    var max = (CATS.filter(function (c) { return c[0] === d.item; })[0] || [0, 0, 0])[2];
    var cur = d.item === 'breach' ? null : (r.scores || {})[d.item];
    var sev = d.item === 'breach' ? ((r.breaches || []).filter(function (b) { return b.id === d.breach_id; })[0] || {}).severity : null;
    return '<form class="qform perf-decide" data-dispute="' + esc(d.id) + '" autocomplete="off">' +
      '<div class="row"><div><label class="field-label" for="pvDec_' + d.id + '">Decision</label>' +
        '<select class="select" id="pvDec_' + d.id + '" data-f="decision"><option value="">Choose</option>' +
        '<option value="upheld">Upheld</option><option value="partly">Partly upheld</option><option value="not_upheld">Not upheld</option></select></div>' +
      (d.item === 'breach'
        ? '<div data-show="partly" hidden><label class="field-label" for="pvVal_' + d.id + '">Lower it to</label><select class="select" id="pvVal_' + d.id + '" data-f="value">' +
            [1, 2, 3].filter(function (k) { return !sev || k < sev; }).map(function (k) { return '<option value="' + k + '">' + esc(SEV_WORD[k]) + '</option>'; }).join('') + '</select></div>'
        : '<div data-show="change" hidden><label class="field-label" for="pvVal_' + d.id + '">New score, out of ' + max + '</label>' +
            '<input class="input perf-num" id="pvVal_' + d.id + '" data-f="value" type="number" inputmode="decimal" min="0" max="' + max + '" step="0.5" value="' + (cur == null ? '' : esc(cur)) + '"></div>') +
      '</div>' +
      '<label class="field-label" for="pvResp_' + d.id + '">Answer</label><textarea class="input" id="pvResp_' + d.id + '" data-f="response" rows="2" maxlength="1000"></textarea>' +
      '<div class="qform-acts"><button class="btn btn-sm btn-primary" type="submit">Save answer</button></div></form>';
  }
  function disputeForm(r) {
    var opts = CATS.map(function (c) { return { key: c[0], label: c[1], breach: null }; })
      .concat((r.breaches || []).map(function (b) { return { key: 'breach', label: 'Breach: ' + b.what, breach: b.id }; }));
    return '<form class="qform" id="pvDisputeForm" autocomplete="off">' +
      '<p class="perf-quiet">Tick what you dispute and say why. You can send one dispute for this month, until ' + esc(timeWord(r.dispute_until)) + '.</p>' +
      opts.map(function (o, i) {
        return '<div class="perf-dpick"><label class="tickline"><input type="checkbox" data-i="' + i + '" data-item="' + o.key + '"' +
          (o.breach ? ' data-breach="' + esc(o.breach) + '"' : '') + '> <span>' + esc(o.label) + '</span></label>' +
          '<textarea class="input" rows="2" maxlength="1000" data-why="' + i + '" aria-label="Why, ' + esc(o.label) + '" hidden></textarea></div>';
      }).join('') +
      '<div class="qform-acts"><button class="btn btn-sm btn-go" type="submit">Send dispute</button>' +
      '<button class="btn btn-sm btn-quiet" type="button" data-a="cancel">Cancel</button></div></form>';
  }

  var EVENT_WORD = { started: 'Started', scored: 'Scores saved', released: 'Released', returned: 'Reverted to draft',
    disputed: 'Disputed', decided: 'Dispute answered', acknowledged: 'Acknowledged', finalised: 'Finalised',
    reopened: 'Reopened', breach_logged: 'Breach logged', breach_voided: 'Breach voided', printed: 'Downloaded', profile: 'Profile changed' };
  /* What a save changed, named (the user, 2026-09-26: "scores saved should
     show which score"): each scorecard and rate from and to, then the notes
     or the plan. An older save named nothing and still reads Scores saved. */
  var RATE_WORD = {};
  RATES.forEach(function (x) { RATE_WORD[x[0]] = x[1]; });
  function savedWord(d) {
    var ch = d && d.changed;
    if (!ch || !ch.length) return '';
    return ': ' + ch.map(function (c) {
      if (c.key === 'notes') return 'notes';
      if (c.key === 'plan') return 'improvement and follow-up';
      if (c.key === 'evaluated_on') return 'date of evaluation ' + (c.from ? dateWord(c.from) : 'not set') + ' to ' + (c.to ? dateWord(c.to) : 'not set');
      var rate = RATE_WORD[c.key], name = CAT_WORD[c.key] || rate || c.key;
      var v = function (x) { return x == null ? 'not set' : num(x) + (rate ? '%' : ''); };
      return name + ' ' + v(c.from) + ' to ' + v(c.to);
    }).join(', ');
  }
  function historyCard(r) {
    var ev = r.events || [];
    if (!ev.length) return '';
    return card('History', '<ul class="perf-history">' + ev.slice(0, 20).map(function (e) {
      var why = e.kind === 'scored' ? savedWord(e.detail) : e.detail && e.detail.reason ? ': ' + e.detail.reason : '';
      return '<li><b>' + esc((EVENT_WORD[e.kind] || e.kind) + why) + '</b><small>' + esc([e.by, timeWord(e.at)].filter(Boolean).join(', ')) + '</small></li>';
    }).join('') + '</ul>');
  }

  // ---- Wiring the sheet ----------------------------------------------------------------
  function gather() {
    var p = { scores: {}, rates: {}, notes: {} };
    CATS.forEach(function (c) {
      var el = $('pvS_' + c[0]); if (!el) return;
      p.scores[c[0]] = el.value === '' ? null : Number(el.value);
      var n = $('pvN_' + c[0]);
      if (n && n.value.trim()) p.notes[c[0]] = n.value.trim();
    });
    RATES.forEach(function (x) {
      var el = $('pvR_' + x[0]); if (!el) return;
      p.rates[x[0]] = el.value === '' ? null : Number(el.value);
    });
    if ($('pvImp')) { p.improvement = $('pvImp').value; p.review_by = $('pvBy').value; p.reward_step = $('pvStep').value; p.evaluated_on = $('pvEval').value; }
    return p;
  }
  /* A pressed button waits for its answer; a refusal gives it back, so a
     person can correct the value and press again. */
  function busy(btn, on) {
    if (!btn) return;
    btn.disabled = on;
    if (on) btn.setAttribute('data-busy', '1'); else btn.removeAttribute('data-busy');
  }
  function freeButtons() {
    Array.prototype.forEach.call($('pvBody').querySelectorAll('[data-busy]'), function (b) { busy(b, false); });
  }
  function after(d, okText, keep) {
    if (d.error) {
      freeButtons();
      if (d.error === 'stale' && d.record) { st.rec = d.record; paintSheet(); msg('pvMsg', said(d), 'warn'); return false; }
      msg('pvMsg', said(d), 'err');
      return false;
    }
    sheetDirty = true;
    if (!keep) st.editing = null;
    st.rec = d;
    window.ADspaceSheet.clean();
    paintSheet();
    if (okText) msg('pvMsg', okText, 'ok');
    return true;
  }
  function save(then) {
    var r = st.rec;
    call('perf_save', { p_token: token, p_member: r.team_member_id, p_period: r.period,
                        p_payload: gather(), p_rev: r.id ? r.rev : null }, function (d) {
      if (then) { if (d.error) after(d); else { st.rec = d; then(d); } return; }
      after(d, 'Saved.');
    });
  }

  function wireSheet(r) {
    var on = function (id, fn) { var el = $(id); if (el) el.addEventListener('click', function () { fn(el); }); };
    on('pvSave', function (b) { busy(b, true); save(); });
    on('pvRelease', function (b) {
      var tell = !$('pvNotify') || $('pvNotify').checked;   // read before the save repaints anything
      busy(b, true);
      save(function (d) {
        if (!d.result || !d.result.complete) { paintSheet(); msg('pvMsg', said({ error: 'incomplete' }), 'err'); return; }
        call('perf_release', { p_token: token, p_review: d.id, p_rev: d.rev, p_notify: tell }, function (x) {
          var who = (x.member && x.member.name) || 'They';
          if (after(x, tell ? 'Released. ' + who + ' has been told.' : 'Released. ' + who + ' was not notified.')) sheetDirty = true;
        });
      });
    });
    on('pvFinal', function (b) {
      busy(b, true);
      call('perf_finalise', { p_token: token, p_review: r.id }, function (d) { after(d, 'Final.'); });
    });
    on('pvPrint', function (b) { printOne(st.rec, b); });
    on('pvPlanSave', function (b) {
      busy(b, true);
      call('perf_save', { p_token: token, p_member: r.team_member_id, p_period: r.period,
        p_payload: { improvement: $('pvImp').value, review_by: $('pvBy').value, reward_step: $('pvStep').value, evaluated_on: $('pvEval').value }, p_rev: null },
        function (d) { busy(b, false); after(d, 'Saved.'); });
    });
    on('pvAck', function (b) {
      busy(b, true);
      call('perf_acknowledge', { p_review: r.id }, function (d) {
        if (d.error === 'code-needed') { busy(b, false); msg('pvMsg', 'Your email code has expired. Close this and enter a new one.', 'err'); return; }
        if (d.error) { busy(b, false); msg('pvMsg', said(d), 'err'); return; }
        st.rec = d; st.editing = null; paintSheet(); msg('pvMsg', 'Acknowledged.', 'ok'); paintMineRow(d);
      });
    });
    on('pvDisputeGo', function () {
      st.editing = 'dispute'; paintSheet();
      var f = $('pvDisputeForm'); if (f) f.scrollIntoView({ block: 'nearest' });
    });
    on('pvBreachAdd', function () { st.editing = 'breach'; paintSheet(); });

    Array.prototype.forEach.call($('pvBody').querySelectorAll('[data-a="cancel"]'), function (b) {
      b.addEventListener('click', function () { st.editing = null; paintSheet(); });
    });
    Array.prototype.forEach.call($('pvBody').querySelectorAll('.perf-use'), function (b) {
      b.addEventListener('click', function () {
        var k = b.getAttribute('data-use'), rk = b.getAttribute('data-rate');
        var el = $(k ? 'pvS_' + k : 'pvR_' + rk);
        if (el) { el.value = b.getAttribute('data-v'); el.dispatchEvent(new Event('input', { bubbles: true })); el.focus(); }
      });
    });
    Array.prototype.forEach.call($('pvBody').querySelectorAll('[data-void]'), function (b) {
      b.addEventListener('click', function () { st.editing = 'void:' + b.getAttribute('data-void'); paintSheet(); var f = $('pvVoidWhy'); if (f) f.focus(); });
    });

    var rf = $('pvReasonForm');
    if (rf) rf.addEventListener('submit', function (e) {
      e.preventDefault();
      var why = $('pvReason').value.trim();
      if (!why) { msg('pvMsg', said({ error: 'reason-needed' }), 'err'); $('pvReason').focus(); return; }
      var ret = st.editing === 'return';
      call(ret ? 'perf_unrelease' : 'perf_reopen', { p_token: token, p_review: r.id, p_reason: why },
        function (d) { after(d, ret ? 'Reverted to draft.' : 'Reopened as version ' + d.version + '.'); });
    });
    var vf = $('pvVoidForm');
    if (vf) vf.addEventListener('submit', function (e) {
      e.preventDefault();
      var id = st.editing.slice(5), why = $('pvVoidWhy').value.trim();
      if (!why) { msg('pvMsg', said({ error: 'reason-needed' }), 'err'); return; }
      call('perf_breach_void', { p_token: token, p_breach: id, p_reason: why }, function (d) {
        if (d.error) { msg('pvMsg', said(d), 'err'); return; }
        st.editing = null; sheetDirty = true; reread(function () { msg('pvMsg', 'Voided.', 'ok'); });
      });
    });
    var bf = $('pvBreachForm');
    if (bf) bf.addEventListener('submit', function (e) {
      e.preventDefault();
      var what = $('pvBWhat').value.trim();
      if (!what) { msg('pvMsg', said({ error: 'what-needed' }), 'err'); $('pvBWhat').focus(); return; }
      var pay = { occurred_on: $('pvBDate').value, category: $('pvBCat').value, severity: Number($('pvBSev').value),
                  what: what, evidence: $('pvBEv').value.trim(), late: $('pvBLate').checked };
      if ($('pvBRep').value) pay.repeated = $('pvBRep').value === 'yes';
      var go = function () {
        call('perf_breach_log', { p_token: token, p_member: r.team_member_id, p_payload: pay }, function (d) {
          if (d.error) { msg('pvMsg', said(d), 'err'); return; }
          st.editing = null; sheetDirty = true;
          reread(function () { msg('pvMsg', 'Logged. ' + num(d.deduction) + ' this month' + (d.repeated ? ', as a repeat' : '') + '.', 'ok'); });
        });
      };
      /* A breach against a month nobody has started starts it, so the
         breach has a record to sit in. */
      if (!r.id) save(function () { go(); }); else go();
    });
    Array.prototype.forEach.call($('pvBody').querySelectorAll('.perf-decide'), function (f) {
      var dec = f.querySelector('[data-f="decision"]');
      var show = function () {
        var v = dec.value;
        Array.prototype.forEach.call(f.querySelectorAll('[data-show]'), function (x) {
          var w = x.getAttribute('data-show');
          x.hidden = !(w === 'change' ? (v === 'upheld' || v === 'partly') : v === w);
        });
      };
      dec.addEventListener('change', show);
      f.addEventListener('submit', function (e) {
        e.preventDefault();
        var v = dec.value, val = f.querySelector('[data-f="value"]'), resp = f.querySelector('[data-f="response"]').value.trim();
        if (!v) { msg('pvMsg', said({ error: 'bad-decision' }), 'err'); return; }
        if (!resp) { msg('pvMsg', said({ error: 'reason-needed' }), 'err'); return; }
        var value = val && val.value !== '' && !val.closest('[hidden]') ? Number(val.value) : null;
        call('perf_decide', { p_token: token, p_dispute: f.getAttribute('data-dispute'), p_decision: v,
                              p_response: resp, p_value: value }, function (d) { after(d, 'Answered.'); });
      });
    });
    var df = $('pvDisputeForm');
    if (df) {
      Array.prototype.forEach.call(df.querySelectorAll('input[type="checkbox"]'), function (c) {
        c.addEventListener('change', function () {
          var t = df.querySelector('[data-why="' + c.getAttribute('data-i') + '"]');
          t.hidden = !c.checked;
          if (c.checked) t.focus();
        });
      });
      df.addEventListener('submit', function (e) {
        e.preventDefault();
        var items = [], missing = null;
        Array.prototype.forEach.call(df.querySelectorAll('input[type="checkbox"]:checked'), function (c) {
          var why = df.querySelector('[data-why="' + c.getAttribute('data-i') + '"]');
          if (!why.value.trim() && !missing) missing = why;
          var it = { item: c.getAttribute('data-item'), reason: why.value.trim() };
          if (c.getAttribute('data-breach')) it.breach_id = c.getAttribute('data-breach');
          items.push(it);
        });
        if (!items.length) { msg('pvMsg', said({ error: 'nothing-disputed' }), 'err'); return; }
        if (missing) { msg('pvMsg', 'Say why for every item you dispute.', 'err'); missing.focus(); return; }
        call('perf_dispute', { p_review: r.id, p_items: items }, function (d) {
          if (d.error === 'code-needed') { msg('pvMsg', 'Your email code has expired. Close this and enter a new one.', 'err'); return; }
          if (d.error) { msg('pvMsg', said(d), 'err'); return; }
          st.rec = d; st.editing = null; paintSheet(); msg('pvMsg', 'Sent. You will be told when it is answered.', 'ok'); paintMineRow(d);
        });
      });
    }
    Array.prototype.forEach.call($('pvBody').querySelectorAll('.perf-evidence'), grow);
  }
  /* Evidence starts one line tall and grows with what is written. */
  function grow(t) { t.style.height = 'auto'; t.style.height = Math.min(t.scrollHeight + 2, 200) + 'px'; }
  $('pvBody').addEventListener('input', function (e) {
    if (e.target.classList && e.target.classList.contains('perf-evidence')) grow(e.target);
  });

  // ---- My performance --------------------------------------------------------------------
  /* THE EMAIL-CODE LOCK. A member's own reviews open only for a session
     verified by a code emailed to them in the last 15 minutes; the proof is
     the signed token's own claim, so nothing here can fake it. It was a
     switch each member set (2026-09-24) and is always on since the same day:
     the user found the switch useless on a page that always asks. The page
     only needs the address the code goes to. */
  var guard = { email: '' };
  function guardInfo(then) {
    call('perf_guard_info', {}, function (d) {
      if (!d.error) guard.email = d.email || '';
      then();
    });
  }
  function showMineLock(on, why) {
    $('mineLock').hidden = !on;
    $('sectionMine').classList.toggle('is-locked', Boolean(on));
    if (!on) return;
    $('mineList').innerHTML = '';
    $('mineRewards').innerHTML = '';
    $('mineLockTitle').textContent = 'Your reviews are locked';
    /* A passkey (Face ID, Touch ID, the device password) unlocks them in one
       touch where this browser can use one; the emailed code stays beside it
       for a new device (the user, 2026-09-26). The server reads either proof
       in the signed session, within 15 minutes. */
    /* Offered only to a person who holds a passkey of their own: the
       browser offers every passkey on the device, whoever it belongs to, so
       an account with none would only ever be offered somebody else's
       (2026-09-27). The emailed code is drawn at once; the passkey joins it
       once the list has answered, and only while the lock is still asking. */
    lockCopy(false, why);
    $('mineCode').hidden = true; $('mineVerify').hidden = true;
    $('mineSend').hidden = false;
    msg('mineLockMsg', '');
    var PK = window.ADspacePasskey;
    if (PK && PK.on && PK.mine) PK.mine(function (n) {
      if (n > 0 && !$('mineLock').hidden && $('mineCode').hidden) lockCopy(true, why);
    });
  }
  function lockCopy(pk, why) {
    $('minePasskey').hidden = !pk;
    $('mineLockLine').textContent = why || (pk ? 'Use a passkey, or an emailed code sent to ' + guard.email + '.'
                                              : 'An emailed code is sent to ' + guard.email + '.');
    $('mineSend').textContent = pk ? 'Email a code' : 'Send code';
    $('mineSend').className = pk ? 'btn' : 'btn btn-primary';
  }
  function sendCode() {
    var b = $('mineSend');
    b.disabled = true;
    var opts = { shouldCreateUser: false };
    var go = window.ADspaceCaptcha ? window.ADspaceCaptcha.options(b, opts) : Promise.resolve(opts);
    go.then(function (o) { return db.auth.signInWithOtp({ email: guard.email, options: o }); }).then(function (r) {
      b.disabled = false;
      if (r && r.error) { msg('mineLockMsg', 'Not sent. Please try again in a minute.', 'err'); return; }
      $('mineCode').hidden = false; $('mineVerify').hidden = false;
      b.textContent = 'Send again'; b.className = 'btn btn-quiet';
      $('minePasskey').hidden = true;
      $('mineLockTitle').textContent = 'Enter your email code';
      $('mineCode').value = '';
      $('mineCode').focus();
      $('mineLockLine').textContent = 'Code sent to ' + guard.email + '.';
      msg('mineLockMsg', '');
    }, function () { b.disabled = false; msg('mineLockMsg', 'Not sent. Please try again in a minute.', 'err'); });
  }
  function verifyCode() {
    var code = ($('mineCode').value || '').replace(/\D/g, '');
    /* Supabase sends 6 digits unless the project's Email OTP length says
       otherwise (6 to 10), so the field takes whatever length arrived. */
    if (code.length < 6 || code.length > 10) { msg('mineLockMsg', 'Enter the code from the email.', 'err'); $('mineCode').focus(); return; }
    var b = $('mineVerify');
    b.disabled = true;
    db.auth.verifyOtp({ email: guard.email, token: code, type: 'email' }).then(function (r) {
      b.disabled = false;
      if (r && r.error) { msg('mineLockMsg', 'That code is wrong or has expired. Send a new one.', 'err'); return; }
      showMineLock(false);
      enterMine();
    }, function () { b.disabled = false; msg('mineLockMsg', 'Not verified. Please try again.', 'err'); });
  }
  /* The proof is the passkey module's: it proves the person signed in and
     never signs anybody else in (2026-09-27). */
  function unlockPasskey() {
    var b = $('minePasskey');
    b.disabled = true;
    msg('mineLockMsg', '');
    window.ADspacePasskey.prove({
      button: b,
      done: function () { b.disabled = false; showMineLock(false); enterMine(); },
      refused: function (text) { b.disabled = false; msg('mineLockMsg', text, 'err'); },
      failed: function (err, quiet) {
        b.disabled = false;
        if (!quiet) msg('mineLockMsg', 'Not unlocked. Use an emailed code.', 'err');
      }
    });
  }
  $('minePasskey').addEventListener('click', unlockPasskey);
  $('mineSend').addEventListener('click', sendCode);
  $('mineVerify').addEventListener('click', verifyCode);
  $('mineCode').addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); verifyCode(); }
  });

  function enterMine() {
    if (!st.mine) UI.skeleton($('mineList'), 3);
    guardInfo(function () {
      call('perf_mine', {}, function (d) {
        if (d.error === 'code-needed') { st.mine = null; showMineLock(true); return; }
        showMineLock(false);
        if (d.error) { UI.failLine($('mineList'), 'Your reviews', said(d), enterMine); return; }
        st.mine = d.reviews || [];
        paintMine();
        loadMineRewards();
      });
    });
  }
  function paintMine() {
    var box = $('mineList');
    if (!box || !st.mine) return;
    if (!st.mine.length) { UI.emptyLine(box, 'No reviews released yet.'); return; }
    box.innerHTML = '';
    var G = window.ADspaceGroup;
    box.appendChild(G.section({
      route: 'mine', key: 'reviews', name: 'Reviews', count: st.mine.length, shut: false,
      table: function () {
        var t = G.table('mine-row', ['Month', 'Status', 'Score', 'Grade', 'Reward', '']);
        G.more(t, st.mine, 30, '', mineRow);
        return t;
      }
    }));
  }
  function mineRow(r) {
    var res = r.result || {};
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'crm-row mine-row';
    b.setAttribute('data-review', r.id);
    b.innerHTML = '<span class="mine-month"><b>' + esc(r.month) + '</b>' +
        (r.dispute_open ? '<small>Dispute by ' + esc(dateWord(r.dispute_until)) + '</small>' : '') + '</span>' +
      '<span class="perf-state">' + statusChip(r.status) + '</span>' +
      '<span class="perf-score">' + esc(res.complete ? num(res.final) : '—') + '</span>' +
      '<span class="perf-grade">' + gradeChip(res) + '</span>' +
      '<span class="perf-reward">' + esc(rewardWord(res)) + '</span>' +
      '<span class="perf-sum">' + esc(res.complete ? [num(res.final), res.grade_word, rewardWord(res)].filter(Boolean).join(' · ') : '') + '</span>' +
      '<span class="perf-chev" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 6 6 6-6 6"/></svg></span>';
    b.addEventListener('click', function () {
      st.mode = 'mine'; st.editing = null; st.rec = r;
      showSheet(b);
      paintSheet();
    });
    return b;
  }
  function paintMineRow(d) {
    if (!st.mine) return;
    st.mine = st.mine.map(function (x) { return x.id === d.id ? d : x; });
    paintMine();
  }

  // ---- The printed record --------------------------------------------------------------
  /* The record of the month, for keeping and for reading at the 1-1, drawn
     on the letterhead the letters use. No signature lines and no version
     (the user, 2026-09-26): a member acknowledges in the portal, never on
     paper. Redrawn from the record every time: no file is stored. */
  function printOne(r, btn) {
    if (!r || !r.id) return;
    /* The sheet is read again once the file is made, so its History shows
       the download it has just filed. */
    draw([r], fileOf(r), btn, function (ok) {
      if (ok && st.rec && st.rec.id === r.id) reread(function () { msg('pvMsg', 'Downloaded.', 'ok'); });
    });
  }
  $('perfPrintMonth').addEventListener('click', function () {
    var btn = this;
    var people = ((st.month && st.month.people) || []).filter(function (p) {
      return p.review && p.review.status !== 'draft';
    });
    if (!people.length) { msg('perfMsg', 'Nothing released for ' + monthWord(st.period) + ' yet.', 'warn'); return; }
    btn.disabled = true;
    msg('perfMsg', 'Drawing ' + people.length + (people.length === 1 ? ' record…' : ' records…'));
    var recs = [], left = people.length;
    people.forEach(function (p, i) {
      call('perf_open', { p_token: token, p_member: p.team_member_id, p_period: st.period }, function (d) {
        if (!d.error) recs[i] = d;
        if (--left) return;
        btn.disabled = false;
        recs = recs.filter(Boolean);
        if (!recs.length) { msg('perfMsg', 'The records could not be read.', 'err'); return; }
        draw(recs, 'Performance-' + st.period.slice(0, 7) + '.pdf', null, function (ok) {
          msg('perfMsg', ok ? recs.length + (recs.length === 1 ? ' record' : ' records') + ' downloaded.' : 'The file could not be drawn.', ok ? 'ok' : 'err');
        });
      });
    });
  });
  function fileOf(r) { return String(r.serial || ('Performance-' + r.period.slice(0, 7))).replace(/\//g, '-') + '.pdf'; }

  function draw(recs, name, btn, then) {
    var D = window.ADspaceDocs;
    if (!D || !D.lib) { drawNow(recs, name, btn, then); return; }
    D.lib().then(function () { drawNow(recs, name, btn, then); }).catch(function (e) {
      if (btn) msg('pvMsg', 'The file could not be drawn: ' + ((e && e.message) || e), 'err');
      if (then) then(false);
    });
  }
  function drawNow(recs, name, btn, then) {
    var PDF = window.PDFLib, D = window.ADspaceDocs;
    var fail = function (e) {
      if (btn) msg('pvMsg', 'The file could not be drawn: ' + ((e && e.message) || e), 'err');
      if (then) then(false);
    };
    if (!PDF || !D) { fail(new Error('PDF library not loaded')); return; }
    if (btn) btn.disabled = true;
    /* The download is filed before anything is drawn, and the file prints
       the filing: the server's time and who took it, so a copy found later
       says whose it was. A filing refused is a file never made (the user,
       2026-09-26: a legitimate timestamp, as a legal document carries). */
    var left = recs.length, refused = null;
    recs.forEach(function (r) {
      call('perf_printed', { p_review: r.id, p_token: token }, function (d) {
        /* An older database files the download and answers ok with no
           stamp: the file is made, without the stamp it could not print. */
        if (d.error || (!d.at && !d.ok)) refused = refused || d;
        else if (d.at) r.__stamp = d;
        if (--left) return;
        if (refused) {
          if (btn) btn.disabled = false;
          fail(new Error('the download could not be recorded, so no file was made'));
          return;
        }
        make();
      });
    });
    function make() {
    var pdf;
    try {
      PDF.PDFDocument.create().then(function (doc) {
        pdf = doc;
        return Promise.all([D.embedFonts(pdf, PDF), D.embedLogo(pdf)]);
      }).then(function (a) {
        var p = D.pen(PDF, a[0], a[1]);
        recs.forEach(function (r) { drawRecord(pdf, p, r); });
        var pages = pdf.getPages();
        pages.forEach(function (pg, i) { p.page = pg; p.footMark(i, pages.length); });
        return pdf.save();
      }).then(function (bytes) {
        var blob = new Blob([bytes], { type: 'application/pdf' });
        var a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = name;
        document.body.appendChild(a);
        a.click();
        setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 2000);
        if (btn) btn.disabled = false;
        if (btn && document.getElementById('pvMsg')) msg('pvMsg', 'Downloaded.', 'ok');
        if (then) then(true);
      }).catch(function (e) { if (btn) btn.disabled = false; fail(e); });
    } catch (e) { if (btn) btn.disabled = false; fail(e); }
    }
  }
  /* A stamp's time, as a record states it: the day, the time to the second
     and the zone, in Malaysia's time whatever the reader's clock says. */
  function stampTime(s) {
    var d = new Date(s);
    if (isNaN(d)) return '';
    var o = { timeZone: 'Asia/Kuala_Lumpur' };
    var day = d.toLocaleDateString('en-GB', { timeZone: o.timeZone, day: 'numeric', month: 'short', year: 'numeric' }).replace(/\bSep\b/, 'Sept');
    var at = d.toLocaleTimeString('en-GB', { timeZone: o.timeZone, hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });
    return day + ', ' + at + ' MYT';
  }

  function drawRecord(pdf, p, r) {
    var res = r.result || {}, m = r.member || {};
    var f = p.fonts, M = p.M, R = p.R, W = R - M;
    var y;
    var page = function (first) {
      p.page = pdf.addPage([p.W, p.H]);
      y = first ? p.head() : p.H - 60;
      /* Every page names the record it belongs to, so a page lifted out still
         says whose month it was. */
      p.text((r.serial ? 'Ref ' + r.serial + ' · ' : '') + r.month, M, 42, 7.5, f.font, p.mute);
      var st0 = r.__stamp;
      p.text('Confidential, internal use' + (st0 ? ' · Downloaded by ' + (st0.by || st0.email) + ', ' + stampTime(st0.at) : ''),
        M, 32, 7.5, f.font, p.mute);
    };
    var need = function (h) { if (y - h < 78) page(false); };
    /* A heading never ends a page: it takes its first lines with it. */
    var heading = function (s) {
      need(76);
      y -= 18;
      p.text(s.toUpperCase(), M, y, 9, f.bold, p.mute);
      y -= 6;
      p.rule(y);
      y -= 14;
    };
    var para = function (s, size, font, color, x, max) {
      (p.wrap(s || '', max || W, size || 10, font || f.font)).forEach(function (ln) {
        need(14); p.text(ln, x || M, y, size || 10, font || f.font, color || p.ink); y -= (size || 10) + 4;
      });
    };
    page(true);
    p.text('PRIVATE & CONFIDENTIAL', M, y, 9, f.bold);
    y -= 22;
    p.text('MONTHLY PERFORMANCE RECORD', M, y, 13, f.med || f.bold);
    if (r.serial) p.right('Ref ' + r.serial, R, y, 9.5, f.font, p.mute);
    y -= 22;
    var none = 'Not set';
    var pnum = function (v) { return v == null || v === '' ? none : num(v); };
    var facts = [['Team member', m.name], ['Employee ID', m.staff_code], ['Department', DEPT_WORD[m.department]],
                 ['Role', ROLE_WORD[m.role_family] || m.designation], ['Review month', r.month],
                 ['Date of evaluation', r.evaluated_on ? dateWord(r.evaluated_on) : ''],
                 ['Dispute until', r.dispute_until ? timeWord(r.dispute_until) : ''], ['Reviewed by', r.reviewer]];
    var colW = W / 4;
    [facts.slice(0, 4), facts.slice(4)].forEach(function (row) {
      var most = 1;
      row.forEach(function (fc, i) {
        var cx = M + i * colW;
        var lines = p.wrap(fc[1] || none, colW - 12, 10, f.bold).slice(0, 2);
        most = Math.max(most, lines.length);
        p.text(fc[0], cx, y, 8, f.font, p.mute);
        lines.forEach(function (ln, k) { p.text(ln, cx, y - 12 - k * 12, 10, f.bold); });
      });
      y -= 18 + most * 12;
    });
    y += 4;

    heading('1 · Result this month');
    var gw = W / 5, gy = y;
    need(56);
    var RANGE = { A: '90 to 100', B: '80 to 89', C: '70 to 79', D: '60 to 69', E: 'under 60' };
    GRADES.forEach(function (g, i) {
      var gx = M + i * gw, on = g[0] === res.grade;
      p.page.drawRectangle({ x: gx + 2, y: gy - 40, width: gw - 4, height: 46,
        color: on ? p.ink : undefined, borderColor: on ? p.ink : p.line, borderWidth: on ? 1 : 0.8 });
      var tc = on ? window.PDFLib.rgb(1, 1, 1) : p.ink;
      p.text(g[0], gx + 10, gy - 16, 16, f.bold, tc);
      p.text(RANGE[g[0]], gx + 30, gy - 14, 8, f.font, on ? tc : p.mute);
      p.text(g[2], gx + 10, gy - 32, 8.5, f.font, on ? tc : p.mute);
    });
    y = gy - 58;
    var cells = [['Base score', pnum(res.base) + ' / 100'], ['Breach deduction', res.deduction ? num(res.deduction) : '0'],
                 ['Final score', pnum(res.final) + ' / 100'], ['Grade', res.grade ? res.grade + ' · ' + res.grade_word : none],
                 ['Reward eligible', res.complete ? (res.eligible ? 'Yes' : 'No') : none]];
    cells.forEach(function (c, i) {
      var cx = M + i * gw;
      p.text(c[0], cx + 2, y, 8, f.font, p.mute);
      p.text(c[1], cx + 2, y - 13, 10.5, f.bold);
    });
    y -= 34;
    var notes = [];
    if (res.capped) notes.push('Grade capped at ' + res.capped + ' by a Level ' + (res.capped === 'D' ? '4' : '3') + ' breach.');
    if (res.review) notes.push('Management review is triggered.');
    if (res.grade === 'C' && res.previous_grade === 'C') notes.push('Baseline after a Baseline month, so not reward eligible.');
    if (notes.length) { para(notes.join(' '), 9, f.font, p.mute); y -= 4; }

    need(20);
    p.text('Category', M, y, 8, f.bold, p.mute);
    p.right('Score', M + 190, y, 8, f.bold, p.mute);
    p.text('Evidence', M + 206, y, 8, f.bold, p.mute);
    y -= 6; p.rule(y); y -= 13;
    CATS.forEach(function (c) {
      var note = (r.notes || {})[c[0]] || '';
      var lines = note ? p.wrap(note, W - 206, 9, f.font) : [];
      need(Math.max(1, lines.length) * 12 + 6);
      p.text(c[1], M, y, 9.5, f.font);
      p.right(pnum((r.scores || {})[c[0]]) + ' / ' + c[2], M + 190, y, 9.5, f.bold);
      if (lines.length) lines.forEach(function (ln, i) { p.text(ln, M + 206, y - i * 12, 9, f.font, p.mute); });
      y -= Math.max(1, lines.length) * 12 + 5;
    });

    heading('2 · What this grade means');
    para(res.grade ? ACTION[res.grade] : 'Not graded.', 10);
    para('Reward eligible: ' + (res.eligible ? 'Yes.' : 'No.'), 10);

    heading('3 · Breach record this month');
    var br = r.breaches || [];
    if (!br.length) para('None recorded.', 10, f.font, p.mute);
    br.forEach(function (b) {
      var flags = [];
      if (b.repeated) flags.push('repeated in the quarter (-5)');
      if (b.late) flags.push('late disclosure (-5)');
      need(40);
      p.text(SEV_WORD[b.severity] + ' · ' + BREACH_CAT[b.category], M, y, 9.5, f.bold);
      p.right(num(b.deduction), R, y, 9.5, f.bold);
      y -= 13;
      para(dateWord(b.occurred_on) + (flags.length ? ' · ' + flags.join(', ') : '') , 8.5, f.font, p.mute);
      para(b.what, 9.5);
      y -= 3;
    });
    if (br.length) para('Each incident is logged once under its highest-impact category. No points are added for fixing a mistake; recovery may prevent escalation, but the breach remains recorded.', 8.5, f.font, p.mute);

    heading('4 · If this result repeats');
    var path = res.path && PATH[res.path];
    if (path) { need(14); p.text(path[0], M, y, 10, f.bold); y -= 14; para(path[1], 9.5); }
    else para('No development or accountability path applies this month.', 9.5, f.font, p.mute);
    para('A clean month resets the process. Consequences use privileges, training and discretionary rewards, never salary.', 8.5, f.font, p.mute);

    heading('5 · Required improvement and follow-up');
    para(r.improvement || 'None set.', 10, f.font, r.improvement ? p.ink : p.mute);
    var stop = function (x) { x = String(x || '').trim(); return /[.!?]$/.test(x) ? x : x + '.'; };
    para('Follow-up date: ' + stop(r.review_by ? dateWord(r.review_by) : none) + '  Step or reward to apply: ' + stop(r.reward_step || none), 9.5);

    heading('6 · Dispute');
    var ds = r.disputes || [];
    if (!ds.length) para(r.dispute_until ? 'No dispute was raised by ' + timeWord(r.dispute_until) + '.' : 'No dispute raised.', 9.5, f.font, p.mute);
    ds.forEach(function (d) {
      need(44);
      p.text(itemWord(d), M, y, 9.5, f.bold);
      if (d.decision) p.right(DECISION[d.decision], R, y, 9.5, f.bold);
      y -= 13;
      para('Raised: ' + d.reason, 9);
      if (d.decision) {
        var change = d.decision === 'not_upheld' ? '' : d.item === 'breach'
          ? (d.decision === 'upheld' ? ' Breach removed.' : ' Lowered to ' + SEV_WORD[d.after_value] + '.')
          : ' Score ' + num(d.before_value) + ' to ' + num(d.after_value) + '.';
        para('Answer (' + (d.decided_by || '') + ', ' + dateWord(d.decided_at) + '): ' + d.response + change, 9);
      }
      y -= 3;
    });

    /* The record of this copy: every step the portal's server stamped, by
       name, address and time, the download included. Acknowledgement is
       given in the portal and stated here, never signed on paper. */
    var stamp = r.__stamp;
    if (!stamp) return;
    heading('7 · Record of this document');
    var STEP = { released: 'Released', acknowledged: 'Acknowledged', finalised: 'Finalised' };
    var rows = (stamp.trail || []).filter(function (t) { return STEP[t.kind]; }).map(function (t) {
      return [STEP[t.kind], t.by || '', t.email || '', stampTime(t.at)];
    });
    rows.push(['Downloaded', stamp.by || '', stamp.email || '', stampTime(stamp.at)]);
    var cols = [M, M + 84, M + 84 + 118, M + 84 + 118 + 168];
    var head = ['Step', 'Name', 'Email', 'Date and time'];
    need(22 + rows.length * 16);
    head.forEach(function (h, i) { p.text(h, cols[i], y, 8.5, f.bold, p.mute); });
    y -= 6; p.rule(y); y -= 12;
    rows.forEach(function (row) {
      need(16);
      row.forEach(function (c, i) {
        var max = (i < 3 ? cols[i + 1] : R) - cols[i] - 8;
        var txt = p.wrap(c, max, 8.5, i === 0 ? f.bold : f.font)[0] || '';
        p.text(txt, cols[i], y, 8.5, i === 0 ? f.bold : f.font);
      });
      y -= 16;
    });
    y -= 2;
    para('Document ID ' + stamp.id + '. Times are the portal server\'s, in Malaysia time (UTC+8). ' +
      (r.serial ? 'Verify the reference ' + r.serial + ' at go.adspace.me/verify.' : ''), 8, f.font, p.mute);
  }

  // ---- Performance rewards (2026-09-28) ------------------------------------------------
  /* The quarter and its two prizes, flexible hours, the bonus pool and the
     trip over two quarters, and growth commission. Every figure is worked out
     by the database from finalised months (perf_quarter_calc, perf_flex_calc,
     perf_period_calc, perf_commission_json) and drawn here as it arrived:
     nothing is worked out again, so the ranking, the member's page and a
     confirmed snapshot cannot disagree. Revenue and profit arrive only for an
     admin; the caller's own row arrives with its name alone. */
  var MONEY = window.ADspaceMoney;
  function rm(n) { return MONEY ? MONEY.money2(n, 'MY') : 'RM ' + Number(n || 0).toFixed(2); }
  var FIRST_QUARTER = '2026-07-01';
  var DEPT_CRIT = {
    creative: [['On-time creative delivery', 25], ['Creative quality and revision', 25], ['Client performance support', 20],
               ['Asset organisation', 15], ['Cross-functional responsiveness', 15]],
    marketing: [['Client account health', 25], ['Campaign planning and execution', 25], ['Posting and servicing accuracy', 20],
                ['Reporting and proactive improvement', 15], ['Brief and handover quality', 15]]
  };
  var WHY = { 'no-final-month': 'No final month', 'below-c': 'Average under 70', 'e-month': 'An E month',
    'critical-breach': 'Level 4 breach', inactive: 'Inactive', 'not-reviewed': 'Not on the review list',
    'few-b-months': 'Under 3 months at B' };
  var NOPAY = { 'nobody-eligible': 'Nobody eligible', 'scores-needed': 'Scores needed', 'below-b': 'Under 80',
    'critical-issue': 'Critical issue', 'figures-needed': 'Figures needed', 'below-gate': 'Revenue under the gate',
    'no-pool': 'No pool set', 'no-budget': 'No budget set' };
  var COM_STATE = { payable: ['Payable', 'is-ok'], 'not-payable': ['Not payable', ''], pending: ['Pending', 'is-warn'] };
  var COM_WHY = { 'month-not-final': 'Month not final', 'below-c': 'Month under 70', breach: 'Level 3 or 4 breach' };
  var RW_SAID = {
    'before-first': 'Quarters begin with Q3 2026.',
    'quarter-open': 'The quarter has not ended.',
    'period-open': 'The period has not ended.',
    'dept-scores-needed': 'Enter both departments’ scores first.',
    'confirmed': 'Confirmed. Reopen it to change it.',
    'not-confirmed': 'Not confirmed.',
    'admin-only': 'Revenue and profit are for an admin only.',
    'pool-closed': 'The bonus pool opens at RM 500,000 revenue.',
    'trip-closed': 'The trip opens at RM 1,000,000 revenue.',
    'bad-amount': 'Enter each amount in RM, to the cent.',
    'bad-pct': 'The rate is above 0 and at most 100, to two decimals.',
    'bad-month': 'Pick a month from June 2026 to this month.',
    'bad-member': 'Pick a team member.',
    'bad-client': 'Pick a client.',
    'description-needed': 'Describe the deal.',
    'bad-department': 'Pick a department.',
    'figures-needed': 'Enter the company figures first.'
  };
  function monthsWord(n) { return n + (n === 1 ? ' month' : ' months'); }
  function rwSaid(d) {
    if (d && d.error === 'pool-over') return 'The pool is at most ' + rm(d.max) + ', 10% of profit.';
    if (d && d.error === 'months-open') return monthsWord(d.count) + ' in the quarter ' + (d.count === 1 ? 'is' : 'are') + ' not final. Finalise ' + (d.count === 1 ? 'it' : 'them') + ' first.';
    if (d && RW_SAID[d.error]) return RW_SAID[d.error];
    return said(d);
  }
  function addMonths(p, n) {
    var y = Number(p.slice(0, 4)), mo = Number(p.slice(5, 7)) - 1 + n;
    y += Math.floor(mo / 12); mo = ((mo % 12) + 12) % 12;
    return y + '-' + String(mo + 1).padStart(2, '0') + '-01';
  }
  function quarterOf(p) {
    var mo = Number(String(p).slice(5, 7));
    return String(p).slice(0, 4) + '-' + String(Math.floor((mo - 1) / 3) * 3 + 1).padStart(2, '0') + '-01';
  }
  function thisMonth() { var d = new Date(); return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-01'; }
  function qWord(q) { return 'Q' + Math.ceil(Number(q.slice(5, 7)) / 3) + ' ' + q.slice(0, 4); }
  function pWord(f) {
    var s = addMonths(f, 3);
    return f.slice(0, 4) === s.slice(0, 4)
      ? 'Q' + Math.ceil(Number(f.slice(5, 7)) / 3) + ' and Q' + Math.ceil(Number(s.slice(5, 7)) / 3) + ' ' + f.slice(0, 4)
      : qWord(f) + ' and ' + qWord(s);
  }
  /* The quarters offered: from Q3 2026 to the one running now, newest
     first, and the page opens on the newest that has ended. The bonus pool's
     periods are halves of the year (Q1 and Q2, Q3 and Q4), so two never
     share a quarter (perf_half, 2026-10-01). */
  function quarterList() {
    var out = [], q = FIRST_QUARTER, now = quarterOf(thisMonth());
    while (q <= now) { out.unshift(q); q = addMonths(q, 3); }
    return out;
  }
  function halfOf(p) { return String(p).slice(0, 4) + (Number(String(p).slice(5, 7)) >= 7 ? '-07-01' : '-01-01'); }
  function halfList() {
    var out = [], f = FIRST_QUARTER, now = halfOf(thisMonth());
    while (f <= now) { out.unshift(f); f = addMonths(f, 6); }
    return out;
  }
  function defaultQuarter() {
    var list = quarterList(), done = list.filter(function (q) { return addMonths(q, 3) <= thisMonth(); });
    return done[0] || list[0];
  }
  function defaultPeriod2() {
    var list = halfList(), done = list.filter(function (f) { return addMonths(f, 6) <= thisMonth(); });
    return done[0] || list[0];
  }
  st.pv = 'months'; st.q = defaultQuarter(); st.pf = defaultPeriod2();
  st.quarter = null; st.periodData = null; st.com = null; st.flex = null; st.cfind = '';

  function fillSelect(sel, list, cur, word) {
    if (list.indexOf(cur) < 0) list = [cur].concat(list);
    sel.innerHTML = list.map(function (k) { return '<option value="' + k + '">' + esc(word(k)) + '</option>'; }).join('');
    sel.value = cur;
  }
  function chip(text, tone) { return '<span class="chip' + (tone ? ' ' + tone : '') + '">' + esc(text) + '</span>'; }
  function gradeWord(g) { var x = GRADES.filter(function (k) { return k[0] === g; })[0]; return x ? g + ' · ' + x[2] : ''; }
  function gradeCell(g) { return g ? chip(gradeWord(g), GRADE_TONE[g] || '') : '<span class="perf-dash">—</span>'; }
  function dash() { return '<span class="perf-dash">—</span>'; }
  function whoCell(p, sub) {
    return '<span class="rw-who"><b>' + esc(p.name || '') + '</b>' + (sub ? '<small>' + esc(sub) + '</small>' : '') + '</span>';
  }
  function youRow(cls, p, cells, lead) {
    var el = document.createElement('div');
    el.className = 'crm-row rw-row ' + cls + ' is-own';
    el.innerHTML = (lead ? Array(lead + 1).join('<span class="rw-c">' + dash() + '</span>') : '') +
      whoCell(p, 'Your own is in My performance') +
      Array(cells).join('x').split('x').map(function () { return '<span class="rw-c">' + dash() + '</span>'; }).join('') +
      '<span class="rw-sum"></span>';
    var cs = el.querySelectorAll('.rw-c'), last = cs[cs.length - 1];
    last.classList.add('rw-key');
    last.innerHTML = chip('You');
    return el;
  }
  function row(cls, cells, sum) {
    var el = document.createElement('div');
    el.className = 'crm-row rw-row ' + cls;
    /* A line of parts wraps between its parts, never inside one. */
    el.innerHTML = cells.join('') + '<span class="rw-sum">' + esc((sum || []).filter(Boolean).map(function (x) { return String(x).replace(/ /g, '\u00a0'); }).join(' · ')) + '</span>';
    return el;
  }
  function cell(html, key) { return '<span class="rw-c' + (key ? ' rw-key' : '') + '">' + html + '</span>'; }
  function money0(n) { return Number(n) > 0 ? esc(rm(n)) : dash(); }

  /* The history of a quarter, a period or the commissions. */
  var RW_EVENT = { dept_scored: 'Department scores saved', quarter_confirmed: 'Confirmed', quarter_reopened: 'Reopened',
    company_set: 'Company figures saved', period_confirmed: 'Confirmed', period_reopened: 'Reopened',
    commission_added: 'Commission added', commission_removed: 'Commission removed', commission_restored: 'Commission restored' };
  function eventWord(e) {
    var d = e.detail || {}, w = RW_EVENT[e.kind] || e.kind;
    if (e.kind === 'dept_scored') {
      var crit = DEPT_CRIT[d.department] || [];
      return w + ': ' + (DEPT_WORD[d.department] || '') + ', ' + (d.changed || []).map(function (c) {
        if (c.key === 'critical') return 'critical issue ' + (c.to ? 'ticked' : 'cleared');
        var i = Number(String(c.key).slice(1)) - 1;
        return ((crit[i] || [c.key])[0]).toLowerCase() + ' ' + (c.from == null ? 'not set' : num(c.from)) + ' to ' + num(c.to);
      }).join(', ');
    }
    if (e.kind === 'company_set') {
      var NAME = { revenue: 'revenue', profit: 'profit', pool: 'bonus pool', trip_budget: 'trip budget' };
      return w + ': ' + (d.changed || []).map(function (c) {
        return NAME[c.key] + (c.key === 'pool' || c.key === 'trip_budget' ? ' ' + (c.from == null ? 'not set' : rm(c.from)) + ' to ' + rm(c.to) : '');
      }).join(', ');
    }
    return w;
  }
  function historySection(route, events) {
    if (!events || !events.length) return null;
    var G = window.ADspaceGroup;
    return G.section({
      route: route, key: 'history', name: 'History', count: events.length,
      shut: G.shut(route, 'history', true),
      table: function () {
        var t = document.createElement('div');
        t.className = 'crm-table softpanel rw-history';
        t.innerHTML = '<ul class="perf-history">' + events.map(function (e) {
          return '<li><b>' + esc(eventWord(e)) + '</b><small>' + esc([e.by, timeWord(e.at)].filter(Boolean).join(', ')) + '</small></li>';
        }).join('') + '</ul>';
        return t;
      }
    });
  }

  // The views -------------------------------------------------------------------------
  var PANE = { months: 'perfMonths', quarters: 'perfQuarters', company: 'perfCompany', commission: 'perfCommission' };
  function setPv(v, quiet) {
    if (!PANE[v]) v = 'months';
    st.pv = v;
    Array.prototype.forEach.call(document.querySelectorAll('#perfViews .acttab'), function (b) {
      var on = b.getAttribute('data-pv') === v;
      b.classList.toggle('is-on', on);
      b.setAttribute('aria-pressed', String(on));
    });
    Object.keys(PANE).forEach(function (k) { $(PANE[k]).hidden = k !== v; });
    if (window.ADspaceCmdbar) window.ADspaceCmdbar.refresh();
    if (!quiet && bridge.setUrl) bridge.setUrl();
  }
  $('perfViews').addEventListener('click', function (e) {
    var b = e.target.closest('.acttab');
    if (!b || b.getAttribute('data-pv') === st.pv) return;
    setPv(b.getAttribute('data-pv'));
    loadView();
  });
  function opened() {
    padlock(true);
    $('perfLock').hidden = true;
    $('perfOpen').hidden = false;
  }
  function loadView() {
    setPv(st.pv, true);
    if (st.pv === 'quarters') loadQuarter();
    else if (st.pv === 'company') loadPeriod();
    else if (st.pv === 'commission') loadCommission();
    else loadMonth();
  }

  // Flexible hours, under the month -----------------------------------------------------
  function loadFlex() {
    var asked = st.period;
    call('perf_flex', { p_token: token, p_period: st.period }, function (d) {
      if (asked !== st.period) return;
      if (d.error === 'code-needed' || d.error === 'no-code') return;
      st.flex = d;
      paintMonth();
    });
  }
  function flexSection() {
    var f = st.flex, G = window.ADspaceGroup;
    if (!f) return null;
    if (f.error) {
      var fail = document.createElement('div');
      UI.failLine(fail, 'Flexible hours', said(f), loadFlex);
      return fail;
    }
    var marks = !f.members ? '' : f.decided
      ? chip(f.unlocked ? 'Unlocked' : 'Not unlocked', f.unlocked ? 'is-ok' : '')
      : chip((f.members - f.finals) + ' not final', 'is-warn');
    return G.section({
      route: 'team-perf', key: 'flex', name: 'Flexible hours in ' + f.next_month, count: f.members, marks: marks,
      shut: G.shut('team-perf', 'flex', true),
      table: function () {
        var t = G.table('rw-row rwf-row', ['Person', 'Score', 'Grade', 'Flexible hours']);
        if (!f.people.length) { var e = document.createElement('div'); e.className = 'emptyline'; e.innerHTML = '<b>Nobody.</b>'; t.appendChild(e); return t; }
        G.more(t, f.people, 30, '', function (p) {
          if (p.own) return youRow('rwf-row', p, 3);
          var has = p.final != null;
          var el = row('rwf-row', [
            whoCell(p, p.breach ? 'Level 3 or 4 breach' : ''),
            cell(has ? esc(num(p.final)) : dash()),
            cell(gradeCell(p.grade)),
            cell(has ? chip(p.eligible ? 'Eligible' : 'Not eligible', p.eligible ? 'is-ok' : '') : dash(), true)
          ], [has ? num(p.final) : 'Not final', p.grade ? gradeWord(p.grade) : '']);
          return el;
        });
        return t;
      }
    });
  }

  // The quarter --------------------------------------------------------------------------
  function loadQuarter() {
    opened();
    fillSelect($('perfQuarter'), quarterList(), st.q, qWord);
    if (!st.quarter || st.quarter.quarter !== st.q) UI.skeleton($('rwQList'), 4);
    var asked = st.q;
    call('perf_quarter', { p_token: token, p_quarter: st.q }, function (d) {
      if (asked !== st.q) return;
      if (d.error) {
        if (d.error === 'code-needed' || d.error === 'no-code') return;
        UI.failLine($('rwQList'), 'The quarter', rwSaid(d), loadQuarter);
        return;
      }
      st.quarter = d;
      paintQuarter();
    });
  }
  $('perfQuarter').addEventListener('change', function () {
    if (this.value === st.q) return;
    st.q = this.value; st.quarter = null; msg('rwQMsg', '');
    loadQuarter();
    if (bridge.setUrl) bridge.setUrl();
  });
  function confirmedChip(d) {
    return d.confirmed ? chip('Confirmed', 'is-ok') : d.ended ? chip('Not confirmed', 'is-warn') : chip('Running');
  }
  function paintQuarter() {
    var d = st.quarter, box = $('rwQList'), G = window.ADspaceGroup;
    if (!d || st.pv !== 'quarters') return;
    var ppl = d.people || [], ind = d.individual || {}, dp = d.department_prize || {};
    $('rwQCount').textContent = ppl.length + (ppl.length === 1 ? ' person' : ' people');
    /* Confirm is drawn only once it can be pressed: the quarter ended and
       every month in it final (the chip names what is still open). */
    $('rwQConfirm').hidden = !(may('team.performance', 'work') && !d.confirmed && d.ended && !(Number(d.open_months) > 0));
    $('rwQReopen').hidden = !(may('team.performance', 'manage') && d.confirmed);
    box.innerHTML = '';
    if (d.confirmed) {
      var line = document.createElement('p');
      line.className = 'routenote rw-note';
      line.textContent = 'Confirmed ' + timeWord(d.confirmed_at) + (d.confirmed_by ? ' by ' + d.confirmed_by : '') + '.';
      box.appendChild(line);
    }
    var won = ind.winners
      ? (ind.winners === 1 ? rm(ind.each) : ind.winners + ' ways · ' + rm(ind.each) + ' each') +
        (Number(ind.remainder) > 0 ? ' · ' + rm(ind.remainder) + ' left' : '')
      : 'No payout · ' + (NOPAY[ind.reason] || '');
    /* What still stands between the quarter and its confirmation: months
       not final refuse it; months nobody entered are asked about. */
    var waits = d.confirmed ? '' :
      (Number(d.open_months) > 0 ? chip(monthsWord(Number(d.open_months)) + ' not final', 'is-warn') : '') +
      (d.ended && Number(d.missing_months) > 0 ? chip(monthsWord(Number(d.missing_months)) + ' not entered', 'is-warn') : '');
    /* Best to worst by average, with the individual prize. A rank is
       shared by equal averages. The department prize is the department's,
       its team leader deciding the split (the user, 2026-10-01). */
    box.appendChild(G.section({
      route: 'team-rw', key: 'individual', name: 'Ranking and rewards', count: ppl.length,
      marks: confirmedChip(d) + waits + chip('Individual prize · ' + won),
      shut: false,
      table: function () {
        var t = G.table('rw-row rwq-row', ['Rank', 'Person', 'Average', 'Grade', 'Eligibility', 'Prize']);
        if (!ppl.length) { UI.emptyLine(t, 'Nobody on the review list.'); return t; }
        G.more(t, ppl, 30, '', function (p) {
          if (p.own) return youRow('rwq-row', p, 4, 1);
          var elig = p.eligible ? 'Eligible' : WHY[(p.reasons || [])[0]] || 'Not eligible';
          var months = Number(p.months || 0), open = Number(p.open || 0);
          /* The months sit under the average they make, and only when the
             quarter is not whole for them; the name keeps its department. */
          var sub = DEPT_WORD[p.department] || '';
          var short = p.average != null && months < 3 ? months + ' of 3' : '';
          return row('rwq-row', [
            cell(p.rank == null ? dash() : esc(String(p.rank))),
            whoCell(p, sub),
            cell(p.average == null ? dash() : esc(num(p.average)) + (short ? '<small class="rw-why">' + esc(short) + '</small>' : '')),
            cell(gradeCell(p.grade)),
            cell(esc(elig)),
            cell(money0(p.prize), true)
          ], [p.rank == null ? '' : 'Rank ' + p.rank, p.average == null ? '' : num(p.average) + (short ? ' over ' + months + ' of 3 months' : ''),
              open ? open + ' not final' : '', p.grade ? gradeWord(p.grade) : '', elig]);
        });
        return t;
      }
    }));
    var dwon = (d.departments || []).filter(function (x) { return x.won; });
    var dmark = dwon.length
      ? dwon.map(function (x) { return DEPT_WORD[x.department]; }).join(' and ') + ' won · ' + rm(dwon[0].share) + (dwon.length > 1 ? ' each' : '')
      : 'No payout · ' + (NOPAY[dp.reason] || '');
    var edit = may('team.performance', 'work') && !d.confirmed;
    box.appendChild(G.section({
      route: 'team-rw', key: 'department', name: 'Department prize', count: (d.departments || []).length,
      marks: chip(dmark), shut: false,
      table: function () {
        var t = G.table('rw-row rwd-row', ['Department', 'Total', 'Grade', 'Critical issue', 'Prize']);
        (d.departments || []).forEach(function (x) {
          var sub = x.entered ? (x.won ? 'Won' : '') : 'Not entered';
          var name = edit
            ? '<button class="rw-who rw-open" type="button" data-dept="' + x.department + '"><b>' + esc(DEPT_WORD[x.department]) + '</b><small>' + esc(sub) + '</small></button>'
            : whoCell({ name: DEPT_WORD[x.department] }, sub);
          var el = row('rwd-row', [
            name,
            cell(x.entered ? esc(num(x.total)) : dash()),
            cell(gradeCell(x.grade)),
            cell(x.entered ? esc(x.critical ? 'Yes' : 'No') : dash()),
            cell(money0(x.share), true)
          ], [x.entered ? num(x.total) + ' of 100' : '', x.grade ? gradeWord(x.grade) : '', x.critical ? 'Critical issue' : '']);
          var ob = el.querySelector('.rw-open');
          if (ob) ob.addEventListener('click', function () { openDept(x.department, ob); });
          t.appendChild(el);
        });
        return t;
      }
    }));
    var h = historySection('team-rw-q', d.events);
    if (h) box.appendChild(h);
  }
  $('rwQConfirm').addEventListener('click', function () {
    var b = this, d0 = st.quarter || {}, missing = Number(d0.missing_months) || 0;
    var go = function () {
      b.disabled = true;
      call('perf_quarter_confirm', { p_token: token, p_quarter: st.q }, function (d) {
        b.disabled = false;
        if (d.error) { msg('rwQMsg', rwSaid(d), 'err'); return; }
        st.quarter = d; paintQuarter(); msg('rwQMsg', 'Confirmed. The team has been told.', 'ok');
      });
    };
    /* A month nobody entered is left out of that person's average; the
       confirmation names it before the outcome is kept. */
    if (!missing) { go(); return; }
    window.ADspaceConfirm.ask({
      title: 'Confirm ' + (d0.word || qWord(st.q)),
      body: monthsWord(missing) + ' on the review list ' + (missing === 1 ? 'has' : 'have') + ' no review and ' + (missing === 1 ? 'is' : 'are') + ' left out of the averages.',
      go: 'Confirm quarter'
    }, go);
  });
  /* The way back never asks. */
  $('rwQReopen').addEventListener('click', function () {
    var b = this; b.disabled = true;
    call('perf_quarter_reopen', { p_token: token, p_quarter: st.q }, function (d) {
      b.disabled = false;
      if (d.error) { msg('rwQMsg', rwSaid(d), 'err'); return; }
      st.quarter = d; paintQuarter(); msg('rwQMsg', 'Reopened.', 'ok');
    });
  });

  // The department sheet -----------------------------------------------------------------
  function deptFields(dep, vals) {
    $('rwDFields').innerHTML = '<div class="row fgrid">' + DEPT_CRIT[dep].map(function (c, i) {
      var v = vals ? vals[i] : null;
      return '<div' + (i === 4 ? ' class="span-all"' : '') + '><label class="field-label is-req" for="rwDC' + i + '">' + esc(c[0]) + ', out of ' + c[1] + '</label>' +
        '<input class="input rw-crit" id="rwDC' + i + '" type="number" inputmode="decimal" min="0" max="' + c[1] + '" step="0.5" aria-required="true" value="' + (v == null ? '' : esc(v)) + '"></div>';
    }).join('') + '</div>';
    deptTotal();
  }
  function deptTotal() {
    var dep = $('rwDDept').value, sum = 0, all = true;
    DEPT_CRIT[dep].forEach(function (c, i) { var v = $('rwDC' + i).value; if (v === '') all = false; else sum += Number(v); });
    sum = Math.round(sum * 10) / 10;
    $('rwDTotal').textContent = all ? 'Total ' + num(sum) + ' of 100 · ' + gradeWord(sum >= 90 ? 'A' : sum >= 80 ? 'B' : sum >= 70 ? 'C' : sum >= 60 ? 'D' : 'E') : 'Total ' + num(sum) + ' of 100 so far';
  }
  function deptOf(dep) { return ((st.quarter && st.quarter.departments) || []).filter(function (x) { return x.department === dep; })[0] || {}; }
  function openDept(dep, opener) {
    var x = deptOf(dep);
    $('rwDDept').value = dep;
    if (window.ADspaceForm && window.ADspaceForm.thumb) $('rwDDept').dispatchEvent(new Event('change'));
    deptFields(dep, x.criteria);
    $('rwDCrit').checked = Boolean(x.critical);
    $('rwDTitle').textContent = 'Department scores · ' + qWord(st.q);
    msg('rwDMsg', '');
    window.ADspaceSheet.show($('rwDeptSheet'), { opener: opener });
  }
  $('rwDDept').addEventListener('change', function () {
    var x = deptOf(this.value);
    deptFields(this.value, x.criteria);
    $('rwDCrit').checked = Boolean(x.critical);
  });
  $('rwDFields').addEventListener('input', deptTotal);
  $('rwDClose').addEventListener('click', function () { window.ADspaceSheet.close(); });
  $('rwDCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
  $('rwDSave').addEventListener('click', function () {
    var dep = $('rwDDept').value, vals = [], bad = null;
    DEPT_CRIT[dep].forEach(function (c, i) {
      var el = $('rwDC' + i), v = el.value;
      if (v === '' || isNaN(Number(v)) || Number(v) < 0 || Number(v) > c[1]) { bad = bad || el; return; }
      vals.push(Number(v));
    });
    if (bad) { msg('rwDMsg', 'Each criterion is 0 to its maximum.', 'err'); bad.focus(); return; }
    var b = this; b.disabled = true;
    call('perf_dept_save', { p_token: token, p_quarter: st.q, p_department: dep,
                             p_payload: { criteria: vals, critical: $('rwDCrit').checked } }, function (d) {
      b.disabled = false;
      if (d.error) {
        msg('rwDMsg', rwSaid(d), 'err');
        if (d.error === 'bad-score' && d.index && $('rwDC' + (d.index - 1))) $('rwDC' + (d.index - 1)).focus();
        return;
      }
      st.quarter = d;
      window.ADspaceSheet.clean();
      window.ADspaceSheet.close();
      paintQuarter();
      msg('rwQMsg', 'Saved.', 'ok');
    });
  });

  // The bonus pool and the trip ------------------------------------------------------------
  function loadPeriod() {
    opened();
    fillSelect($('perfPeriod'), halfList(), st.pf, pWord);
    if (!st.periodData || st.periodData.period !== st.pf) UI.skeleton($('rwPList'), 4);
    var asked = st.pf;
    call('perf_period', { p_token: token, p_from: st.pf }, function (d) {
      if (asked !== st.pf) return;
      if (d.error) {
        if (d.error === 'code-needed' || d.error === 'no-code') return;
        UI.failLine($('rwPList'), 'The period', rwSaid(d), loadPeriod);
        return;
      }
      st.periodData = d;
      paintPeriod();
    });
  }
  $('perfPeriod').addEventListener('change', function () {
    if (this.value === st.pf) return;
    st.pf = this.value; st.periodData = null; msg('rwPMsg', '');
    loadPeriod();
    if (bridge.setUrl) bridge.setUrl();
  });
  function paintPeriod() {
    var d = st.periodData, box = $('rwPList'), G = window.ADspaceGroup;
    if (!d || st.pv !== 'company') return;
    var ppl = d.people || [], bo = d.bonus || {}, tr = d.trip || {}, co = d.company;
    $('rwPCount').textContent = ppl.length + (ppl.length === 1 ? ' person' : ' people');
    $('rwPConfirm').hidden = !(may('team.performance', 'work') && !d.confirmed && d.ended && d.figures);
    $('rwPReopen').hidden = !(may('team.performance', 'manage') && d.confirmed);
    box.innerHTML = '';
    if (d.confirmed) {
      var line = document.createElement('p');
      line.className = 'routenote rw-note';
      line.textContent = 'Confirmed ' + timeWord(d.confirmed_at) + (d.confirmed_by ? ' by ' + d.confirmed_by : '') + '.';
      box.appendChild(line);
    }
    /* The figures: revenue and profit for an admin, and for everybody who
       reads the period the two amounts, what they pay out and what the
       rounding leaves. One block, never folded: it is what the table under
       it divides. */
    var fig = document.createElement('section');
    fig.className = 'crm-group rw-figs';
    fig.innerHTML = '<div class="crm-group-head"><h3>Company figures</h3>' + confirmedChip(d) + '</div>';
    var t = document.createElement('div');
    t.className = 'crm-table softpanel rw-facts';
    var outcome = function (x, amount, open) {
      if (!open) return 'Not open';
      if (x.reason) return rm(amount) + ' · No payout, ' + (NOPAY[x.reason] || '').toLowerCase();
      return rm(amount) + (Number(x.remainder) > 0 ? ' · ' + rm(x.remainder) + ' left' : '');
    };
    if (!d.figures) {
      UI.emptyLine(t, 'No figures.', d.admin && !d.confirmed ? 'Enter figures' : '', function () { openFigures(); });
    } else {
      var facts = co ? [['Revenue', rm(co.revenue)], ['Profit', rm(co.profit)], ['Bonus pool ceiling', rm(co.max_pool)]] : [];
      facts.push(['Bonus pool', outcome(bo, bo.pool, bo.open)]);
      facts.push(['Trip budget', outcome(tr, tr.budget, tr.open)]);
      t.innerHTML = '<dl class="facts rw-dl">' + facts.map(function (f) {
        return '<div><dt>' + esc(f[0]) + '</dt><dd>' + esc(f[1]) + '</dd></div>';
      }).join('') + '</dl>' +
        (d.admin && !d.confirmed ? '<div class="rw-facts-acts"><button class="btn btn-sm" id="rwFEdit" type="button">' + PEN_MARK + 'Edit</button></div>' : '');
      var eb = t.querySelector('#rwFEdit');
      if (eb) eb.addEventListener('click', function () { openFigures(eb); });
    }
    fig.appendChild(t);
    box.appendChild(fig);
    box.appendChild(G.section({
      route: 'team-rw', key: 'units', name: 'Bonus pool and trip', count: ppl.length,
      shut: false,
      table: function () {
        var t = G.table('rw-row rwp-row', ['Person', 'Months at B', 'Average', 'Grade', 'Units', 'Bonus', 'Trip']);
        if (!ppl.length) { UI.emptyLine(t, 'Nobody on the review list.'); return t; }
        G.more(t, ppl, 30, '', function (p) {
          if (p.own) return youRow('rwp-row', p, 6);
          var elig = p.eligible ? '' : WHY[(p.reasons || [])[0]] || 'Not eligible';
          return row('rwp-row', [
            whoCell(p, elig),
            cell(esc(String(p.months_b || 0)) + '<small> of ' + esc(String(p.months || 0)) + '</small>'),
            cell(p.average == null ? dash() : esc(num(p.average))),
            cell(gradeCell(p.grade)),
            cell(p.units ? esc(num(p.units)) : dash()),
            cell(money0(p.bonus), true),
            cell(money0(p.trip))
          ], [p.average == null ? '' : num(p.average), p.grade ? gradeWord(p.grade) : '', p.units ? num(p.units) + ' units' : '', Number(p.trip) > 0 ? 'Trip ' + rm(p.trip) : '']);
        });
        return t;
      }
    }));
    var h = historySection('team-rw-p', d.events);
    if (h) box.appendChild(h);
  }
  $('rwPConfirm').addEventListener('click', function () {
    var b = this; b.disabled = true;
    call('perf_period_confirm', { p_token: token, p_from: st.pf }, function (d) {
      b.disabled = false;
      if (d.error) { msg('rwPMsg', rwSaid(d), 'err'); return; }
      st.periodData = d; paintPeriod(); msg('rwPMsg', 'Confirmed. The team has been told.', 'ok');
    });
  });
  $('rwPReopen').addEventListener('click', function () {
    var b = this; b.disabled = true;
    call('perf_period_reopen', { p_token: token, p_from: st.pf }, function (d) {
      b.disabled = false;
      if (d.error) { msg('rwPMsg', rwSaid(d), 'err'); return; }
      st.periodData = d; paintPeriod(); msg('rwPMsg', 'Reopened.', 'ok');
    });
  });

  /* Amounts are typed as RM with or without separators, and read back to
     the cent; anything else is not a number. */
  function amountIn(el) {
    var v = String(el.value || '').replace(/[,\s]/g, '').replace(/^RM/i, '');
    if (v === '') return null;
    return /^-?\d+(\.\d{1,2})?$/.test(v) ? Number(v) : NaN;
  }
  function figuresMax() {
    var p = amountIn($('rwFPro'));
    $('rwFMax').textContent = p != null && !isNaN(p) ? 'At most ' + rm(Math.max(0, Math.floor(p * 10 + 1e-7) / 100)) : '';
  }
  function openFigures(opener) {
    var co = (st.periodData && st.periodData.company) || {};
    var put = function (id, v) { $(id).value = v == null ? '' : Number(v).toFixed(2); };
    put('rwFRev', co.revenue); put('rwFPro', co.profit); put('rwFPool', co.pool); put('rwFTrip', co.trip_budget);
    $('rwFTitle').textContent = 'Company figures · ' + pWord(st.pf);
    figuresMax();
    msg('rwFMsg', '');
    window.ADspaceSheet.show($('rwCoSheet'), { opener: opener });
  }
  $('rwFPro').addEventListener('input', figuresMax);
  $('rwFClose').addEventListener('click', function () { window.ADspaceSheet.close(); });
  $('rwFCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
  $('rwFSave').addEventListener('click', function () {
    var ids = ['rwFRev', 'rwFPro', 'rwFPool', 'rwFTrip'], v = ids.map(function (id) { return amountIn($(id)); });
    var bad = ids.filter(function (id, i) { return (i < 2 && v[i] == null) || (v[i] != null && isNaN(v[i])); })[0];
    if (bad) { msg('rwFMsg', i18nNeed(bad), 'err'); $(bad).focus(); return; }
    var b = this; b.disabled = true;
    call('perf_company_set', { p_token: token, p_from: st.pf, p_payload: {
      revenue: v[0], profit: v[1], pool: v[2] || 0, trip_budget: v[3] || 0 } }, function (d) {
      b.disabled = false;
      if (d.error) {
        msg('rwFMsg', rwSaid(d), 'err');
        var at = { 'pool-over': 'rwFPool', 'pool-closed': 'rwFPool', 'trip-closed': 'rwFTrip' }[d.error];
        if (at) $(at).focus();
        return;
      }
      st.periodData = d;
      window.ADspaceSheet.clean();
      window.ADspaceSheet.close();
      paintPeriod();
      msg('rwPMsg', 'Saved.', 'ok');
    });
  });
  function i18nNeed(id) {
    return { rwFRev: 'Enter the revenue in RM.', rwFPro: 'Enter the profit in RM.', rwFPool: 'Enter the bonus pool in RM.',
             rwFTrip: 'Enter the trip budget in RM.', rwMNet: 'Enter the net profit in RM.' }[id] || RW_SAID['bad-amount'];
  }

  // Growth commission ------------------------------------------------------------------------
  function loadCommission() {
    opened();
    if (!st.com) UI.skeleton($('rwCList'), 4);
    call('perf_commissions', { p_token: token }, function (d) {
      if (d.error) {
        if (d.error === 'code-needed' || d.error === 'no-code') return;
        UI.failLine($('rwCList'), 'Commission', rwSaid(d), loadCommission);
        return;
      }
      st.com = d;
      paintCommission();
    });
  }
  $('rwCFind').addEventListener('input', function () {
    var v = this.value.trim().toLowerCase();
    if (v === st.cfind) return;
    st.cfind = v; paintCommission();
  });
  function paintCommission() {
    var d = st.com, box = $('rwCList'), G = window.ADspaceGroup;
    if (!d || st.pv !== 'commission') return;
    var all = d.rows || [];
    var shown = all.filter(function (c) {
      return !st.cfind || [c.name, c.client, c.client_code, c.description].join(' ').toLowerCase().indexOf(st.cfind) > -1;
    });
    $('rwCCount').textContent = st.cfind ? shown.length + ' of ' + all.length : all.length + (all.length === 1 ? ' entry' : ' entries');
    $('rwCAdd').hidden = !may('team.performance', 'work');
    box.innerHTML = '';
    if (!all.length) {
      UI.emptyLine(box, 'No entries.', may('team.performance', 'work') ? 'Add entry' : '', function () { openCommission($('rwCAdd')); });
    } else if (!shown.length) {
      UI.emptyLine(box, 'No matches.', 'Clear the search', function () { st.cfind = ''; $('rwCFind').value = ''; paintCommission(); });
    } else {
      var payable = shown.filter(function (c) { return c.state === 'payable'; }).reduce(function (a, c) { return a + Number(c.amount); }, 0);
      box.appendChild(G.section({
        route: 'team-rw', key: 'commission', name: 'Growth commission', count: shown.length,
        marks: chip('Payable ' + rm(Math.round(payable * 100) / 100)), shut: false,
        table: function () {
          var t = G.table('rw-row rwc-row', ['Deal', 'Month', 'Net profit', 'Rate', 'Commission', 'State', '']);
          G.more(t, shown, 30, '', comRow);
          return t;
        }
      }));
    }
    var h = historySection('team-rw-c', d.events);
    if (h) box.appendChild(h);
  }
  function comRow(c) {
    var s = COM_STATE[c.state] || COM_STATE.pending;
    var sub = [c.description, c.client_code ? c.client_code + ' · ' + c.client : c.client].filter(Boolean).join(' · ');
    var el = row('rwc-row has-act', [
      whoCell(c, sub),
      cell(esc(dateWord(c.month).replace(/^\d+ /, ''))),
      cell(esc(rm(c.net_profit))),
      cell(esc(num(c.pct)) + '%'),
      cell(esc(rm(c.amount))),
      cell(chip(s[0], s[1]) + (c.reason ? '<small class="rw-why">' + esc(COM_WHY[c.reason] || '') + '</small>' : ''), true)
    ], [dateWord(c.month).replace(/^\d+ /, ''), rm(c.amount)]);
    if (may('team.performance', 'work')) {
      el.insertAdjacentHTML('beforeend', '<span class="team-act">' +
        '<button class="kmenu-btn" data-a="menu" type="button" aria-label="More actions" aria-expanded="false">' +
        '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg></button>' +
        '<div class="kmenu" data-menu hidden><button class="kmenu-item is-danger" data-a="remove" type="button">Remove</button></div></span>');
      var btn = el.querySelector('[data-a="menu"]'), menu = el.querySelector('[data-menu]');
      btn.addEventListener('click', function (e) {
        e.stopPropagation();
        var open = menu.hidden;
        shutComMenus();
        menu.hidden = !open;
        btn.setAttribute('aria-expanded', String(open));
        if (open) window.ADspaceMenu.place(btn, menu);
      });
      el.querySelector('[data-a="remove"]').addEventListener('click', function () {
        shutComMenus();
        call('perf_commission_remove', { p_token: token, p_id: c.id }, function (d) {
          if (d.error) { msg('rwCMsg', rwSaid(d), 'err'); return; }
          st.com.rows = st.com.rows.filter(function (x) { return x.id !== c.id; });
          paintCommission();
          comUndo(c);
        });
      });
    } else {
      el.insertAdjacentHTML('beforeend', '<span class="team-act"></span>');
    }
    return el;
  }
  function shutComMenus() {
    Array.prototype.forEach.call(document.querySelectorAll('#rwCList .kmenu'), function (m) { m.hidden = true; });
    Array.prototype.forEach.call(document.querySelectorAll('#rwCList .kmenu-btn'), function (b) { b.setAttribute('aria-expanded', 'false'); });
  }
  if (window.ADspaceMenu) window.ADspaceMenu.onScroll(shutComMenus);
  document.addEventListener('click', function (e) {
    if (!e.target.closest || !e.target.closest('#rwCList .team-act')) shutComMenus();
  });
  /* The way back, drawn where the entry was, for 8 seconds. */
  var comUndoTimer = null;
  function comUndo(c) {
    var host = $('rwCList'), bar = host.parentNode.querySelector(':scope > .undobar-here');
    if (!bar) {
      bar = document.createElement('div');
      bar.className = 'undobar undobar-here';
      host.parentNode.insertBefore(bar, host);
    }
    bar.hidden = false;
    bar.innerHTML = '<span>' + esc((c.name ? c.name + ': ' : '') + c.description + ' removed.') + '</span><button class="btn btn-sm" type="button">Undo</button>';
    var shut = function () { if (bar.parentNode) bar.parentNode.removeChild(bar); };
    bar.querySelector('button').addEventListener('click', function () {
      shut();
      call('perf_commission_restore', { p_token: token, p_id: c.id }, function (d) {
        if (d.error) { msg('rwCMsg', rwSaid(d), 'err'); return; }
        loadCommission();
      });
    });
    clearTimeout(comUndoTimer);
    comUndoTimer = setTimeout(shut, 8000);
  }
  function openCommission(opener) {
    var d = st.com || {}, F = window.ADspaceForm;
    var members = (d.members || []).slice().sort(F.byStaff);
    $('rwMWho').innerHTML = '<option value="">Choose</option>' + members.map(function (m) {
      return '<option value="' + esc(m.id) + '">' + esc(F.named(m.staff_code, m.name)) + '</option>';
    }).join('');
    var clients = (d.clients || []).slice().sort(F.byClient);
    $('rwMClient').innerHTML = '<option value="">No client</option>' + clients.map(function (c) {
      return '<option value="' + esc(c.id) + '">' + esc(F.named(c.client_code, c.name)) + '</option>';
    }).join('');
    $('rwMDesc').value = ''; $('rwMNet').value = ''; $('rwMPct').value = '';
    var last = addMonths(thisMonth(), -1);
    $('rwMMonth').value = (last < '2026-06-01' ? thisMonth() : last).slice(0, 7);
    $('rwMMonth').max = thisMonth().slice(0, 7);
    comAmount();
    msg('rwMMsg', '');
    window.ADspaceSheet.show($('rwComSheet'), { opener: opener });
  }
  function comAmount() {
    var n = amountIn($('rwMNet')), p = Number(String($('rwMPct').value).replace(/[%\s]/g, ''));
    $('rwMAmount').textContent = n != null && !isNaN(n) && p > 0 ? 'Commission ' + rm(Math.round(n * p) / 100) : '';
  }
  $('rwMNet').addEventListener('input', comAmount);
  $('rwMPct').addEventListener('input', comAmount);
  $('rwCAdd').addEventListener('click', function () {
    var b = this;
    if (st.com) { openCommission(b); return; }
    call('perf_commissions', { p_token: token }, function (d) { if (!d.error) { st.com = d; openCommission(b); } });
  });
  $('rwMClose').addEventListener('click', function () { window.ADspaceSheet.close(); });
  $('rwMCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
  $('rwMSave').addEventListener('click', function () {
    var need = function (id, text) { msg('rwMMsg', text, 'err'); $(id).focus(); };
    if (!$('rwMWho').value) { need('rwMWho', RW_SAID['bad-member']); return; }
    if (!$('rwMDesc').value.trim()) { need('rwMDesc', RW_SAID['description-needed']); return; }
    if (!/^\d{4}-\d{2}$/.test($('rwMMonth').value)) { need('rwMMonth', RW_SAID['bad-month']); return; }
    var net = amountIn($('rwMNet'));
    if (net == null || isNaN(net) || net < 0) { need('rwMNet', i18nNeed('rwMNet')); return; }
    var pct = String($('rwMPct').value).replace(/[%\s]/g, '');
    if (!/^\d+(\.\d{1,2})?$/.test(pct) || Number(pct) <= 0 || Number(pct) > 100) { need('rwMPct', RW_SAID['bad-pct']); return; }
    var b = this; b.disabled = true;
    call('perf_commission_add', { p_token: token, p_payload: { team_member_id: $('rwMWho').value,
      client_id: $('rwMClient').value || null, description: $('rwMDesc').value.trim(),
      month: $('rwMMonth').value + '-01', net_profit: net, pct: Number(pct) } }, function (d) {
      b.disabled = false;
      if (d.error) {
        msg('rwMMsg', rwSaid(d), 'err');
        var at = { 'bad-month': 'rwMMonth', 'bad-amount': 'rwMNet', 'bad-pct': 'rwMPct', 'bad-member': 'rwMWho', 'own-review': 'rwMWho' }[d.error];
        if (at) $(at).focus();
        return;
      }
      window.ADspaceSheet.clean();
      window.ADspaceSheet.close();
      msg('rwCMsg', 'Added.', 'ok');
      loadCommission();
    });
  });

  // My performance: the member's own rewards -------------------------------------------------
  function loadMineRewards() {
    call('perf_rewards_mine', {}, function (d) {
      if (d.error === 'code-needed') { $('mineRewards').innerHTML = ''; return; }
      if (d.error) { UI.failLine($('mineRewards'), 'Your rewards', rwSaid(d), loadMineRewards); return; }
      st.mineRw = d;
      paintMineRewards();
    });
  }
  function paintMineRewards() {
    var d = st.mineRw, box = $('mineRewards'), G = window.ADspaceGroup;
    if (!d || !box) return;
    box.innerHTML = '';
    var add = function (key, name, list, heads, cls, rowOf) {
      if (!list || !list.length) return;
      box.appendChild(G.section({
        route: 'mine', key: key, name: name, count: list.length, shut: false,
        table: function () { var t = G.table('rw-row ' + cls, heads); G.more(t, list, 30, '', rowOf); return t; }
      }));
    };
    add('quarters', 'Quarters', d.quarters, ['Quarter', 'Average', 'Grade', 'Individual prize', 'Department prize'], 'rwmq-row', function (x) {
      var me = x.me || {}, dp = x.department;
      var ind = Number(me.prize) > 0 ? rm(me.prize) : me.eligible ? 'Not the highest' : WHY[(me.reasons || [])[0]] || 'Not eligible';
      /* The department prize is the department's; its team leader shares it. */
      var dshare = dp ? (dp.share != null ? dp.share : dp.each) : null;
      var dep = dp ? (dp.won ? (DEPT_WORD[dp.department] || '') + ' won' + (Number(dshare) > 0 ? ' · ' + rm(dshare) : '') : (DEPT_WORD[dp.department] || '') + ' did not win') : '—';
      return row('rwmq-row', [
        whoCell({ name: x.word }, me.months ? me.months + (me.months === 1 ? ' final month' : ' final months') : ''),
        cell(me.average == null ? dash() : esc(num(me.average))),
        cell(gradeCell(me.grade)),
        cell(esc(ind), true),
        cell(esc(dep))
      ], [me.average == null ? '' : num(me.average), me.grade ? gradeWord(me.grade) : '', dp && dp.won ? dep : '']);
    });
    add('periods', 'Bonus and trip', d.periods, ['Period', 'Months at B', 'Units', 'Bonus', 'Trip'], 'rwmp-row', function (x) {
      var me = x.me || {};
      var elig = me.eligible ? '' : WHY[(me.reasons || [])[0]] || 'Not eligible';
      return row('rwmp-row', [
        whoCell({ name: x.word }, elig),
        cell(esc(String(me.months_b || 0)) + '<small> of ' + esc(String(me.months || 0)) + '</small>'),
        cell(me.units ? esc(num(me.units)) : dash()),
        cell(money0(me.bonus), true),
        cell(x.trip_open ? money0(me.trip) : esc('Not open'))
      ], [me.units ? num(me.units) + ' units' : '', x.trip_open && Number(me.trip) > 0 ? 'Trip ' + rm(me.trip) : '']);
    });
    add('flex', 'Flexible hours', d.flex, ['Month', 'Team', 'You'], 'rwmf-row', function (x) {
      return row('rwmf-row', [
        whoCell({ name: x.next_month }, 'From ' + x.month),
        cell(chip(x.unlocked ? 'Unlocked' : 'Not unlocked', x.unlocked ? 'is-ok' : '')),
        cell(x.unlocked ? chip(x.eligible ? 'Eligible' : 'Not eligible', x.eligible ? 'is-ok' : '') : dash(), true)
      ], [x.unlocked ? 'Unlocked' : 'Not unlocked']);
    });
    add('commission', 'Growth commission', d.commissions, ['Deal', 'Net profit', 'Rate', 'Commission', 'State'], 'rwmc-row', function (c) {
      var s = COM_STATE[c.state] || COM_STATE.pending;
      var sub = [dateWord(c.month).replace(/^\d+ /, ''), c.client].filter(Boolean).join(' · ');
      return row('rwmc-row', [
        whoCell({ name: c.description }, sub),
        cell(esc(rm(c.net_profit))),
        cell(esc(num(c.pct)) + '%'),
        cell(esc(rm(c.amount))),
        cell(chip(s[0], s[1]) + (c.reason ? '<small class="rw-why">' + esc(COM_WHY[c.reason] || '') + '</small>' : ''), true)
      ], [rm(c.amount)]);
    });
  }
  // ---- End of performance rewards ------------------------------------------------------

  window.ADspacePerf = {
    /* A step's word and tone, for the Overview's review card. */
    status: STATUS,
    enterTeam: enterTeam,
    enterMine: enterMine,
    lock: function (then) { lock(then); },
    urlState: function () {
      if (st.tab === 'groups') return { tab: 'groups' };
      if (st.tab !== 'performance') return {};
      if (st.pv === 'quarters') return { tab: 'performance', view: 'quarters', q: st.q.slice(0, 7) };
      if (st.pv === 'company') return { tab: 'performance', view: 'company', q: st.pf.slice(0, 7) };
      if (st.pv === 'commission') return { tab: 'performance', view: 'commission' };
      return { tab: 'performance', m: st.period.slice(0, 7) };
    },
    /* The bell: a dispute opens Team > Performance on its month. */
    openTeam: function () { st.tab = 'performance'; if (bridge.show) bridge.show('team'); }
  };
  if (bridge.perfReady) bridge.perfReady();
})();
