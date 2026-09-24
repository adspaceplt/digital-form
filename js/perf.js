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
  var ROLE_WORD = { visual: 'Visual / Designer', video: 'Video Production Specialist',
                    planner: 'PM / Content Planner / Copywriter', account: 'Account Media / Ads / Account Manager' };
  var ROLE_STD = {
    visual: 'Visual hierarchy, brand consistency, detail accuracy, clean handover. Choices reduce client revision risk.',
    video: 'Shot quality, editing flow, hook strength, retention, export accuracy. Improves watchability and performance.',
    planner: 'Campaign direction, content angles, brief clarity. Identifies weak accounts and proposes improvement.',
    account: 'Client servicing, posting accuracy, budget pacing, escalation. Proactively manages every account.'
  };
  var DEPT_WORD = { creative: 'Creative', marketing: 'Marketing' };
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
    return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
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
    'not-draft': 'A released month keeps its scores. Return it to draft to change them.',
    'incomplete': 'Score all six categories first.',
    'no-staff-code': 'Set their Employee ID on the Team page first. The reference is built from it.',
    'stale': 'Somebody else changed this review. It has been reloaded.',
    'bad-score': 'A score is outside its range.',
    'bad-rate': 'A rate is outside its range.',
    'bad-date': 'That date is not valid.',
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
    'window-closed': 'The 3 days to dispute have passed.',
    'nothing-disputed': 'Tick at least one item.',
    'bad-item': 'That item cannot be disputed.',
    'not-final': 'Only a final record can be reopened.',
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
      if (/^\d{4}-\d{2}$/.test(q.get('m') || '')) st.period = q.get('m') + '-01';
    }
    var canMembers = may('team', 'view'), canPerf = may('team.performance', 'view');
    if (!canPerf) st.tab = 'members';
    if (!canMembers) st.tab = 'performance';
    $('teamTabs').hidden = !(canMembers && canPerf);
    Array.prototype.forEach.call(document.querySelectorAll('#teamTabs .tab'), function (b) {
      var on = b.getAttribute('data-tab') === st.tab;
      b.classList.toggle('is-on', on);
      b.setAttribute('aria-selected', String(on));
    });
    $('teamMembersPane').hidden = st.tab !== 'members';
    $('teamPerfPane').hidden = st.tab !== 'performance';
    if (st.tab === 'members') { if (window.ADspaceTeam) window.ADspaceTeam.enter(); }
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
      loadMonth();
    });
  }

  function showLock(why) {
    $('perfLock').hidden = false;
    $('perfOpen').hidden = true;
    var blocked = why && (why.error === 'no-code' || why.error === 'denied' || why.error === 'db');
    $('perfLockForm').hidden = Boolean(blocked);
    msg('perfLockMsg', why ? said(why) : '', why ? (why.error === 'code-needed' ? 'warn' : 'err') : '');
  }
  /* The database said the unlock has gone. Whatever was open closes, so a
     record is never left on the screen after the database stopped serving it. */
  function lockedOut(d) {
    keepToken(null);
    if (window.ADspaceSheet && window.ADspaceSheet.isOpen($('perfSheet')) && st.mode === 'manage') {
      window.ADspaceSheet.close();
    }
    st.month = null;
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
      loadMonth();
    });
  });

  $('perfLockBtn').addEventListener('click', function () {
    lock(function () { showLock(null); msg('perfLockMsg', 'Locked.', 'ok'); });
  });
  function lock(then) {
    var t = token || readToken();
    keepToken(null);
    st.month = null;
    if (!t) { if (then) then(); return; }
    call('perf_lock', { p_token: t }, function () { if (then) then(); });
  }

  // ---- The month ----------------------------------------------------------------------
  function monthOptions() {
    var sel = $('perfMonth'), out = [], d = new Date();
    d.setDate(1);
    for (var i = 0; i < 13; i++) {
      var k = d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-01';
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
    });
  }
  $('perfMonth').addEventListener('change', function () {
    st.period = this.value;
    st.month = null;
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
    if (!st.month) return;
    var people = st.month.people || [];
    var shown = people.filter(function (p) {
      if (st.find && String(p.name || '').toLowerCase().indexOf(st.find) < 0) return false;
      if (st.filter && stateOf(p) !== st.filter) return false;
      return true;
    });
    var reviewed = shown.filter(function (p) { return p.reviewed; });
    var others = shown.filter(function (p) { return !p.reviewed; });
    var all = people.filter(function (p) { return p.reviewed; }).length;
    $('perfCount').textContent = (st.find || st.filter)
      ? reviewed.length + ' of ' + all : all + (all === 1 ? ' person' : ' people');
    if (!people.length) { UI.emptyLine(box, 'No team members.'); return; }
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
    var sum = res && res.complete ? [num(res.final), res.grade_word, rewardWord(res)].join(' · ') : '';
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
        '<div class="kmenu" data-menu hidden><button class="kmenu-item" data-a="profile" type="button"><b>Review profile</b></button></div>' +
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
    return el;
  }
  function shutRowMenus() {
    Array.prototype.forEach.call(document.querySelectorAll('#perfList .kmenu'), function (m) { m.hidden = true; });
    Array.prototype.forEach.call(document.querySelectorAll('#perfList .kmenu-btn'), function (b) { b.setAttribute('aria-expanded', 'false'); });
  }
  if (window.ADspaceMenu) window.ADspaceMenu.onScroll(shutRowMenus);
  document.addEventListener('click', function (e) {
    if (!e.target.closest || !e.target.closest('#perfList .team-act')) shutRowMenus();
  });

  // ---- The review profile ---------------------------------------------------------------
  var profileFor = null;
  function openProfile(p, opener) {
    profileFor = p;
    $('ppTitle').textContent = p.name;
    $('ppDept').value = p.department || '';
    $('ppRole').value = p.role_family || '';
    $('ppAds').checked = Boolean(p.runs_ads);
    $('ppReviewed').checked = Boolean(p.reviewed);
    msg('ppMsg', '');
    window.ADspaceSheet.show($('perfProfileSheet'), { opener: opener });
  }
  $('ppClose').addEventListener('click', function () { window.ADspaceSheet.close(); });
  $('ppCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
  $('ppSave').addEventListener('click', function () {
    if (!profileFor) return;
    var btn = this; btn.disabled = true;
    call('perf_profile_set', { p_token: token, p_member: profileFor.team_member_id, p_payload: {
      department: $('ppDept').value, role_family: $('ppRole').value,
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
      reopen: manage() && may('team.performance', 'manage') && r.status === 'final'
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
    var title = '', line = '', acts = '';
    var dUntil = r.dispute_until ? timeWord(r.dispute_until) : '';
    var open = r.dispute_open;
    if (st.editing === 'return' || st.editing === 'reopen') {
      var ret = st.editing === 'return';
      return '<section class="qcard qnext">' +
        '<h3 class="qnext-title">' + (ret ? 'Return to draft' : 'Reopen') + '</h3>' +
        '<p class="qnext-line">' + esc(ret
          ? (r.member.name || 'They') + ' stops seeing this month until it is released again.'
          : 'A new version is opened in draft with the same reference. The final version is kept on the record.') + '</p>' +
        '<form class="qform" id="pvReasonForm" autocomplete="off">' +
          '<label class="field-label" for="pvReason">Reason</label>' +
          '<textarea class="input" id="pvReason" rows="2" maxlength="500"></textarea>' +
          '<div class="qform-acts"><button class="btn btn-sm btn-warn" type="submit">' + (ret ? 'Return to draft' : 'Reopen') + '</button>' +
          '<button class="btn btn-sm btn-quiet" type="button" data-a="cancel">Cancel</button></div>' +
        '</form><div class="msg" id="pvMsg"></div></section>';
    }
    if (manage()) {
      var name = (r.member && r.member.name) || 'They';
      if (!r.id || r.status === 'draft') {
        title = r.id ? 'Draft' : 'Not started';
        line = name + ' sees nothing of this month, breaches included, until it is released.';
        if (canWork()) {
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
      '<p class="qnext-line">' + esc(line) + '</p>' + ackNote +
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
      '<dl class="tfacts perf-sums">' +
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
    return card('Rates behind the scores', '<dl class="tfacts">' + rows + '</dl>');
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
      '<label class="field-label" for="pvBWhat">What happened</label><textarea class="input" id="pvBWhat" rows="2" maxlength="1000"></textarea>' +
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
      if (!r.improvement && !r.review_by && !r.reward_step) {
        return manage() || r.status === 'final' ? card('Improvement and review', '<p class="perf-quiet">None set.</p>') : '';
      }
      return card('Improvement and review', '<dl class="tfacts">' +
        (r.improvement ? '<div><dt>Improvement</dt><dd>' + esc(r.improvement) + '</dd></div>' : '') +
        (r.review_by ? '<div><dt>Review by</dt><dd>' + esc(dateWord(r.review_by)) + '</dd></div>' : '') +
        (r.reward_step ? '<div><dt>Step or reward</dt><dd>' + esc(r.reward_step) + '</dd></div>' : '') + '</dl>');
    }
    return card('Improvement and review',
      '<div class="perf-plan"><label class="field-label" for="pvImp">Improvement</label>' +
      '<textarea class="input" id="pvImp" rows="3" maxlength="4000">' + esc(r.improvement || '') + '</textarea>' +
      '<div class="row"><div><label class="field-label" for="pvBy">Review by</label><input class="input" id="pvBy" type="date" value="' + esc(r.review_by || '') + '"></div>' +
      '<div><label class="field-label" for="pvStep">Step or reward to apply</label><input class="input" id="pvStep" maxlength="500" value="' + esc(r.reward_step || '') + '"></div></div>' +
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

  var EVENT_WORD = { started: 'Started', scored: 'Scores saved', released: 'Released', returned: 'Returned to draft',
    disputed: 'Disputed', decided: 'Dispute answered', acknowledged: 'Acknowledged', finalised: 'Finalised',
    reopened: 'Reopened', breach_logged: 'Breach logged', breach_voided: 'Breach voided', printed: 'Printed', profile: 'Profile changed' };
  function historyCard(r) {
    var ev = r.events || [];
    if (!ev.length) return '';
    return card('History', '<ul class="perf-history">' + ev.slice(0, 20).map(function (e) {
      var why = e.detail && e.detail.reason ? ': ' + e.detail.reason : '';
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
    if ($('pvImp')) { p.improvement = $('pvImp').value; p.review_by = $('pvBy').value; p.reward_step = $('pvStep').value; }
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
      busy(b, true);
      save(function (d) {
        if (!d.result || !d.result.complete) { paintSheet(); msg('pvMsg', said({ error: 'incomplete' }), 'err'); return; }
        call('perf_release', { p_token: token, p_review: d.id, p_rev: d.rev }, function (x) {
          if (after(x, 'Released. ' + ((x.member && x.member.name) || 'They') + ' has been told.')) sheetDirty = true;
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
        p_payload: { improvement: $('pvImp').value, review_by: $('pvBy').value, reward_step: $('pvStep').value }, p_rev: null },
        function (d) { busy(b, false); after(d, 'Saved.'); });
    });
    on('pvAck', function (b) {
      busy(b, true);
      call('perf_acknowledge', { p_review: r.id }, function (d) {
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
        function (d) { after(d, ret ? 'Returned to draft.' : 'Reopened as version ' + d.version + '.'); });
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
  function enterMine() {
    if (!st.mine) UI.skeleton($('mineList'), 3);
    call('perf_mine', {}, function (d) {
      if (d.error) { UI.failLine($('mineList'), 'Your reviews', said(d), enterMine); return; }
      st.mine = d.reviews || [];
      paintMine();
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
      '<span class="perf-sum">' + esc(res.complete ? [num(res.final), res.grade_word, rewardWord(res)].join(' · ') : '') + '</span>' +
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
  /* The outcome sheet the team signs at the 1-1, drawn on the letterhead the
     letters use and redrawn from the record every time: no file is stored. */
  function printOne(r, btn) {
    if (!r || !r.id) return;
    draw([r], fileOf(r), btn);
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
    var PDF = window.PDFLib, D = window.ADspaceDocs;
    var fail = function (e) {
      if (btn) msg('pvMsg', 'The file could not be drawn: ' + ((e && e.message) || e), 'err');
      if (then) then(false);
    };
    if (!PDF || !D) { fail(new Error('PDF library not loaded')); return; }
    if (btn) btn.disabled = true;
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
        recs.forEach(function (r) { call('perf_printed', { p_review: r.id, p_token: token }, function () {}); });
        if (btn && document.getElementById('pvMsg')) msg('pvMsg', 'Downloaded.', 'ok');
        if (then) then(true);
      }).catch(function (e) { if (btn) btn.disabled = false; fail(e); });
    } catch (e) { if (btn) btn.disabled = false; fail(e); }
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
      p.text('Confidential, internal use · Version ' + (r.version || 1), M, 32, 7.5, f.font, p.mute);
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
                 ['Role', ROLE_WORD[m.role_family] || m.designation], ['Review month', r.month], ['Reviewed by', r.reviewer]];
    var colW = W / 3;
    [facts.slice(0, 3), facts.slice(3)].forEach(function (row) {
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

    heading('5 · Required improvement and review');
    para(r.improvement || 'None set.', 10, f.font, r.improvement ? p.ink : p.mute);
    var stop = function (x) { x = String(x || '').trim(); return /[.!?]$/.test(x) ? x : x + '.'; };
    para('Review by: ' + stop(r.review_by ? dateWord(r.review_by) : none) + '  Step or reward to apply: ' + stop(r.reward_step || none), 9.5);

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

    heading('7 · Acknowledgement');
    para(r.acknowledged_at ? 'Acknowledged in the portal on ' + timeWord(r.acknowledged_at) + '.' : 'Not acknowledged in the portal.', 9.5);
    need(84);
    y -= 38;
    var half = (W - 24) / 2;
    p.rule(y, M, M + half, true);
    p.rule(y, M + half + 24, R, true);
    p.text('Reviewer signature and date', M, y - 12, 8.5, f.font, p.mute);
    p.text('Team member signature and date', M + half + 24, y - 12, 8.5, f.font, p.mute);
    y -= 28;
    para('Signing confirms this review was discussed and the result was shown. It records acknowledgement, not necessarily agreement with the rating.', 8.5, f.font, p.mute);
  }

  window.ADspacePerf = {
    enterTeam: enterTeam,
    enterMine: enterMine,
    lock: function (then) { lock(then); },
    urlState: function () {
      return st.tab === 'performance'
        ? { tab: 'performance', m: st.period.slice(0, 7) } : {};
    },
    /* The bell: a dispute opens Team > Performance on its month. */
    openTeam: function () { st.tab = 'performance'; if (bridge.show) bridge.show('team'); }
  };
  if (bridge.perfReady) bridge.perfReady();
})();
