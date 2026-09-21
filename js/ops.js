/*
 * My Work — the operations queue, and one task open.
 *
 * Phase 1 put the whole model behind security-definer functions: a browser
 * cannot set a stage, move a commitment, assign a person, stamp a completion
 * or file an event, whatever it sends. This page is therefore two things and
 * nothing else — a read of tables whose policies already decide what arrives,
 * and a caller of those functions. Every refusal it can meet is named on the
 * screen in the team's own words rather than in the database's.
 *
 * The queue is banded by when the work is owed, because that is what orders a
 * day: overdue first, then today, this week, later, and the ones nobody has
 * dated. It is `ADspaceGroup`, the same card per group every other console
 * directory uses.
 *
 * Whose work arrives is not this page's decision. `ops_may_see_task` answers
 * with your own always and the team's only where `ops.all` is granted, so the
 * scope select is offered only where that part is held and hiding it would
 * change nothing the database does.
 */
(function () {
  var API = window.ADspaceAPI;
  var db  = API && API.client;
  var UI  = window.ADspaceState;
  var GRP = window.ADspaceGroup;
  var bridge = window.ADspaceAdmin || {};
  if (!API || !API.configured || !db || !UI || !GRP) return;

  function $(id) { return document.getElementById(id); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function msg(id, text, kind) {
    var el = $(id); if (!el) return;
    el.textContent = text || '';
    el.className = 'msg' + (kind && text ? ' ' + kind : '');
  }
  function may(key, level) { return Boolean(bridge.may && bridge.may(key, level)); }
  /* A link is typed by a colleague and opened by another one, so the page
     opens only what a browser should follow. `javascript:` in an href is a
     script that runs with this console's session behind it, and the fact that
     both ends are the team is not a reason to hand one of them that. */
  function safeUrl(u) { return /^https?:\/\//i.test(String(u || '')) ? String(u) : ''; }

  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>';
  var CHEV = '<svg class="crm-chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 18l6-6-6-6"/></svg>';

  // ---- Dates ---------------------------------------------------------------
  /* One reading of "when", because a queue that calls the same day two
     different things in two places is a queue nobody trusts. */
  function dayOf(v) {
    if (!v) return null;
    var d = new Date(v);
    if (isNaN(d.getTime())) return null;
    d.setHours(0, 0, 0, 0);
    return d;
  }
  function todayStart() { var d = new Date(); d.setHours(0, 0, 0, 0); return d; }
  function daysAway(v) {
    var d = dayOf(v);
    if (!d) return null;
    return Math.round((d - todayStart()) / 86400000);
  }
  function niceDate(v) {
    var d = dayOf(v);
    if (!d) return '';
    return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
  }
  function shortDate(v) {
    var d = dayOf(v);
    if (!d) return '';
    return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
  }
  function niceTime(v) {
    if (!v) return '';
    var d = new Date(v);
    if (isNaN(d.getTime())) return '';
    return d.toLocaleString('en-GB', { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });
  }
  function dateValue(v) {
    var d = dayOf(v);
    if (!d) return '';
    return [d.getFullYear(), String(d.getMonth() + 1).padStart(2, '0'),
            String(d.getDate()).padStart(2, '0')].join('-');
  }
  /* The ceiling a first draft date may reach: the calendar day before the
     commitment, which is what `ops_due_order_ok` compares against. Built off
     `dayOf`, so the page and the database mean the same day. */
  function dayBefore(v) {
    var d = dayOf(v);
    if (!d) return '';
    d = new Date(d.getTime());
    d.setDate(d.getDate() - 1);
    return dateValue(d);
  }
  /* "In 3 days" is what a person says; "2026-10-02T00:00:00Z" is what the row
     holds. Overdue carries the word as well as the colour, so the mark
     survives greyscale and a reader who cannot tell warn from mute. */
  function dueWord(v) {
    var n = daysAway(v);
    if (n === null) return 'No date set';
    if (n < -1) return shortDate(v) + ' · ' + (-n) + ' days over';
    if (n === -1) return shortDate(v) + ' · 1 day over';
    if (n === 0) return 'Today';
    if (n === 1) return 'Tomorrow';
    if (n <= 7) return shortDate(v) + ' · in ' + n + ' days';
    return shortDate(v);
  }
  function minutesWord(m) {
    m = Math.max(0, Math.round(Number(m) || 0));
    if (m < 60) return m + ' min';
    var h = Math.floor(m / 60), r = m % 60;
    return h + 'h' + (r ? ' ' + r + 'm' : '');
  }

  // ---- What the database said, in the team's words -------------------------
  /* Every one of these is a refusal a person can act on, so it is said in the
     words of the thing they were trying to do. A page that prints
     `ready-needs-owner-and-due` has made the database's vocabulary the
     reader's problem. */
  var SAID = {
    'not-team': 'Your team record could not be read. Ask an admin to check it.',
    'denied': 'You do not have access to do that.',
    'not-found': 'That task is no longer there.',
    'stale': 'Somebody changed this task while it was open. It has been reloaded.',
    'not-yours': 'That extension is somebody else\'s to decide.',
    'decided': 'That extension has already been answered.',
    'no-date': 'A date is required.',
    /* The team's own milestone has to land before the commitment it feeds,
       and the latest it may fall is the day before. Named here rather than
       left as the database's own word, like every other refusal. */
    'draft-not-before-final': 'The first draft is due at the latest one day before the final due date.',
    'bad-transition': 'That is not a move this workflow offers from here.',
    'no-such-stage': 'That is not a stage in this workflow.',
    'ready-needs-owner-and-due': 'Ready needs an owner and a final due date.',
    'footage-not-ready': 'Editing is refused while the footage is marked not ready.',
    'needs-draft': 'Client review needs a draft or review link.',
    'needs-final-link': 'Delivered needs a final link.',
    'needs-delivery-or-reason': 'Done needs a delivery, or a reason for closing without one.',
    'checklist-incomplete': 'A required checklist item is still open.',
    'reason-required': 'A reason is required.',
    'category-required': 'Say what it is waiting on.',
    'title-required': 'A title is required.',
    'client-required': 'A client is required.',
    'workflow-required': 'No workflow is set up. Ask an admin.',
    'bad-kind': 'That is not a kind of link this portal keeps.',
    'url-required': 'An address is required.',
    'ends-before-it-starts': 'That ends before it starts.',
    'not-blocked': 'This task is not blocked.',
    'confirm-required': 'Type the task number exactly as it is shown.'
  };
  function said(err) { return SAID[err] || ('Refused: ' + err + '.'); }

  // ---- State ---------------------------------------------------------------
  var state = {
    tasks: null, stages: {}, workflows: [], templates: [], members: [], clients: [],
    owners: {}, ownerIds: {},   // task id → the live owner's name, and their id
    find: '', scope: 'mine', filter: 'open', group: 'due', period: 'month', err: null,
    view: 'list',          // list | board | calendar: three readings of one set of rows
    wf: null,              // the workflow the board lays out
    month: null,           // the first day of the month the calendar shows
    week: [],              // this week's work sessions, for the capacity strip
    notifs: [],            // my unread notifications
    task: null,            // the open task, as ops_task_json returned it
    pane: 'overview',
    session: null,         // my one open work session, whichever task it is on
    detail: { checklist: [], links: [], sessions: [], events: [], video: null },
    moved: null,           // the last stage move, named on the row the repaint draws
    tick: null
  };

  /* Every stage in every workflow, keyed workflow id + '|' + key, so a row
     can name its own stage without a second read per task. */
  function stageOf(t) {
    if (!t) return null;
    return state.stages[t.workflow_id + '|' + t.stage_key] || null;
  }
  function stageLabel(t) {
    var s = stageOf(t);
    return (s && s.label) || String(t.stage_key || '').replace(/_/g, ' ');
  }
  /* The colour a stage carries is the portal's one vocabulary: amber while
     something waits, green once it is a fact, neutral otherwise. Blocked is
     red, because it is a refusal and not a caution. */
  /* Four families and no more, so a column of stages can be read down without
     becoming a rainbow: not started is mute, the work in hand is the ordinary
     case and carries no paint at all, anything waiting on a person is warn,
     anything cleared is green, and blocked is red because it is a refusal.
     Terminal-or-waiting was the whole of this rule before, so Intake, Ready,
     In progress, Shooting, Editing, Revision, Approved and Delivered all drew
     the same neutral control and nothing on the row said where the task had
     got to — which is the one thing the control exists to say. It keys on
     `stage_group`, which the workflow already carries, so a stage added to a
     workflow next year is toned by its own data and not by a list kept here. */
  /* A stored key is not a word on a screen. Details printed `reel` under a
     template named Reel and `simple` under a field offering Simple, so the
     record contradicted the form that filled it one tab away. The key stays
     what it is; what a person reads is named here, and anything a workflow of
     somebody's own adds falls through to sentence case rather than to the raw
     key. */
  var DELIVER_WORD = {
    static: 'Static post', carousel: 'Carousel', reel: 'Reel', video: 'Video',
    story: 'Story', report: 'Report', copywriting: 'Copywriting',
    design: 'Design', adhoc: 'Ad-hoc request'
  };
  var COMPLEX_WORD = { simple: 'Simple', standard: 'Standard', complex: 'Complex' };
  var PRIORITY_WORD = { '1': '1 highest', '2': '2', '3': '3 normal', '4': '4', '5': '5 lowest' };
  function sentence(s) {
    s = String(s || '').replace(/_/g, ' ');
    return s ? s.charAt(0).toUpperCase() + s.slice(1) : '';
  }

  var STAGE_TONE = {
    intake: 'is-off', kiv: 'is-off', cancelled: 'is-off',
    internal_review: 'is-warn', client_review: 'is-warn', waiting: 'is-warn',
    approved: 'is-ok', delivered: 'is-ok', done: 'is-ok',
    blocked: 'is-danger'
  };
  function stageTone(t) {
    var s = stageOf(t);
    if (!s) return '';
    if (STAGE_TONE[s.stage_group]) return STAGE_TONE[s.stage_group];
    /* A workflow of somebody's own making need not use the seeded groups, so
       the old test is the fallback and never the rule. */
    if (s.is_terminal) return 'is-ok';
    if (s.is_waiting || s.is_review) return 'is-warn';
    return '';
  }
  function isFinished(t) { return Boolean(t.completed_at || t.cancelled_at); }

  // ---- Reading -------------------------------------------------------------
  function loadCatalogue(then) {
    Promise.all([
      db.from('ops_workflows').select('id, key, name, active').order('key'),
      db.from('ops_workflow_stages').select('*').order('position'),
      db.from('ops_task_templates').select('*').eq('active', true).order('name'),
      db.from('team_members').select('id, name, email, active, capacity_minutes_week').eq('active', true).order('name'),
      db.from('clients').select('id, name').order('name')
    ]).then(function (r) {
      state.workflows = (r[0] && r[0].data) || [];
      state.stages = {};
      ((r[1] && r[1].data) || []).forEach(function (s) {
        state.stages[s.workflow_id + '|' + s.key] = s;
      });
      state.templates = (r[2] && r[2].data) || [];
      state.members = (r[3] && r[3].data) || [];
      state.clients = (r[4] && r[4].data) || [];
      then();
    }, function () { then(); });
  }

  function load() {
    var box = $('workQueue');
    if (!box) return;
    if (!box.querySelector('.crm-table')) UI.skeleton(box, 5);
    state.err = null;
    loadCatalogue(function () {
      /* The client's name comes off the join the policy already allows, and
         the owner off the live assignee rows. Neither is a second store: a
         task holds an id and the name is read where it lives.

         THE READ IS BOUNDED, AND OPEN WORK IS NOT PART OF THE BOUND. At eight
         contents a week across thirty clients this table gains about three
         hundred rows a month, so a single `.limit(500)` over everything
         stopped showing older work in week seven and said nothing at all
         about it. What grows without limit is *finished* work; what a person
         has to see is open work, however old, because a task overdue since
         August is the first thing the queue exists to show. So open work is
         read in full and closed work is read from the chosen period onward.
         Three reads rather than one `.or()`, because each is a plain filter
         and a cancelled task carries `cancelled_at` where a completed one
         carries `completed_at`. */
      var since = periodStart().toISOString();
      var base = function () {
        return db.from('ops_tasks').select('*, clients(name)').is('archived_at', null)
          .order('current_final_due_at', { ascending: true, nullsFirst: false });
      };
      Promise.all([
        base().is('completed_at', null).is('cancelled_at', null),
        base().gte('completed_at', since).limit(500),
        base().gte('cancelled_at', since).limit(500),
        /* The foreign key is named, because `ops_task_assignees` points at
           `team_members` twice (the person assigned and the person who did the
           assigning) and PostgREST refuses an embed it cannot resolve. Left
           bare, this read failed outright: every owner in the console was
           blank, Mine matched nothing, and the record's own owner select fell
           back to Nobody a moment after a save that had worked. */
        db.from('ops_task_assignees')
          .select('task_id, responsibility, team_member_id,' +
                  ' team_members!ops_task_assignees_team_member_id_fkey(name)')
          .is('ended_at', null)
      ]).then(function (r) {
        /* A refused read of who owns what is not an empty owner column: the
           scope, the grouping and the capacity strip all hang off it, and a
           queue that quietly says nobody owns anything is worse than one that
           says it could not be read. */
        var bad = (r[0] && r[0].error) || (r[3] && r[3].error);
        if (bad) {
          state.err = bad;
          UI.failLine(box, 'Your tasks', bad.message, load);
          return;
        }
        /* One row can only be in one of the three, but a merge that trusted
           that would be a merge nobody had checked. */
        var seen = {};
        state.tasks = [].concat((r[0] && r[0].data) || [], (r[1] && r[1].data) || [],
                                (r[2] && r[2].data) || [])
          .filter(function (t) {
            if (seen[t.id]) return false;
            seen[t.id] = 1;
            return true;
          });
        state.owners = {};
        state.ownerIds = {};
        ((r[3] && r[3].data) || []).forEach(function (a) {
          if (a.responsibility !== 'owner') return;
          state.owners[a.task_id] = (a.team_members && a.team_members.name) || '';
          state.ownerIds[a.task_id] = a.team_member_id;
        });
        paint();
      }, function (e) {
        state.err = e;
        UI.failLine(box, 'Your tasks', (e && e.message) || String(e), load);
      });
    });
  }

  /* My own open session, whichever task it is on: one a person, across every
     task, which is a partial unique index in the database and not a hope. */
  function loadSession(then) {
    var me = bridge.me && bridge.me();
    if (!me || !me.id) { state.session = null; if (then) then(); return; }
    db.from('ops_work_sessions').select('*').eq('team_member_id', me.id)
      .is('ended_at', null).limit(1)
      .then(function (r) {
        state.session = (!r.error && r.data && r.data[0]) || null;
        if (then) then();
      }, function () { state.session = null; if (then) then(); });
  }

  // ---- The queue -----------------------------------------------------------
  /* How far back finished work is read. Never applied to open work. */
  function periodStart() {
    var d = new Date();
    if (state.period === 'q') return new Date(d.getFullYear(), d.getMonth() - 2, 1);
    if (state.period === 'year') return new Date(d.getFullYear(), 0, 1);
    return new Date(d.getFullYear(), d.getMonth(), 1);
  }

  var BANDS = [
    { key: 'overdue', name: 'Overdue' },
    { key: 'today',   name: 'Due today' },
    { key: 'week',    name: 'Due this week' },
    { key: 'later',   name: 'Later' },
    { key: 'nodate',  name: 'No date set' },
    { key: 'done',    name: 'Finished' }
  ];
  function bandOf(t) {
    if (isFinished(t)) return 'done';
    var n = daysAway(t.current_final_due_at);
    if (n === null) return 'nodate';
    if (n < 0) return 'overdue';
    if (n === 0) return 'today';
    if (n <= 7) return 'week';
    return 'later';
  }

  /* THE AXIS. The same rows and the same card, asked a different question.
     By due date is what orders a day. By client is how the work is sold and
     how the team has always counted it — thirty headings with a count each,
     rather than two hundred and ninety rows. By stage is where the work is
     piling up. By owner is who is carrying it.

     Only the due bands have a fixed order and a fixed set; the other three
     are drawn from the rows that are actually there, so a client with no
     work this month costs no heading. */
  function groupsOf(rows) {
    var mode = state.group, out = [], by = {};
    function put(key, name, sort) {
      if (!by[key]) { by[key] = { key: key, name: name, sort: sort, rows: [] }; out.push(by[key]); }
      return by[key];
    }
    rows.forEach(function (t) {
      if (mode === 'client') {
        var c = (t.clients && t.clients.name) || (t.scope === 'internal' ? 'Internal' : 'No client');
        put('c-' + c, c, c).rows.push(t);
      } else if (mode === 'stage') {
        var s = stageOf(t);
        put('s-' + t.stage_key, stageLabel(t), String(1000 + (s ? s.position : 99))).rows.push(t);
      } else if (mode === 'owner') {
        var o = state.owners[t.id] || '';
        /* Nobody yet sorts last, because it is the exception and not a name. */
        put('o-' + (o || 'none'), o || 'Nobody yet', o ? '1' + o : '2').rows.push(t);
      } else {
        var b = bandOf(t);
        put(b, (BANDS.filter(function (x) { return x.key === b; })[0] || {}).name || b,
            String(BANDS.map(function (x) { return x.key; }).indexOf(b))).rows.push(t);
      }
    });
    if (mode === 'due') {
      var order = BANDS.map(function (x) { return x.key; });
      out.sort(function (a, b) { return order.indexOf(a.key) - order.indexOf(b.key); });
    } else {
      out.sort(function (a, b) { return String(a.sort).localeCompare(String(b.sort)); });
    }
    return out;
  }
  /* On the due axis the bands are few and mostly worth opening, so only the
     two nobody opens a queue to read are shut. On every other axis the whole
     point is the headings: thirty client cards, each with its count, is the
     page somebody can scan — thirty open cards is the two hundred and ninety
     rows we were trying to get away from. */
  function shutByDefault(g) {
    if (state.group !== 'due') return true;
    return g.key === 'done' || g.key === 'later';
  }
  function marksOf(g) {
    if (g.key === 'overdue') return '<span class="tone is-warn">Overdue</span>';
    if (state.group === 'due') return '';
    /* Off the due axis, overdue is the fact a heading has to carry or it is
       hidden inside a shut card. */
    var late = g.rows.filter(function (t) {
      return !isFinished(t) && daysAway(t.current_final_due_at) < 0;
    }).length;
    return late ? '<span class="tone is-warn">' + late + ' overdue</span>' : '';
  }

  function inFilter(t) {
    var f = state.filter;
    if (!f) return true;
    var s = stageOf(t);
    if (f === 'open') return !isFinished(t);
    if (f === 'done') return isFinished(t);
    if (f === 'active') return Boolean(s && s.is_active_work);
    if (f === 'review') return Boolean(s && s.is_review);
    if (f === 'waiting') return Boolean(s && s.is_waiting) || t.stage_key === 'blocked';
    return true;
  }
  function inScope(t) {
    if (state.scope !== 'mine') return true;
    var me = bridge.me && bridge.me();
    if (!me || !me.id) return true;
    /* The whole team's queue arrives where `ops.all` is granted, so "my work"
       is a filter over what came back and never a second read. Keyed on the
       id and not the name: two colleagues can share a first name, and a rename
       would quietly empty somebody's queue. */
    return state.ownerIds[t.id] === me.id;
  }
  function matches(t) {
    if (!state.find) return true;
    var hay = [t.title, t.description, t.remarks, t.deliverable_type,
               (t.clients && t.clients.name), state.owners[t.id],
               'T' + t.task_no].join(' ').toLowerCase();
    return hay.indexOf(state.find) > -1;
  }

  /* Which container the view draws in. The other two are hidden, and the
     capacity strip draws only with the board, where the question it answers
     (who has room this week) is the question being asked. */
  function viewBox() {
    var list = $('workQueue'), board = $('workBoard'), cal = $('workCal'), cap = $('workCap');
    if (list) list.hidden = state.view !== 'list';
    if (board) board.hidden = state.view !== 'board';
    if (cal) cal.hidden = state.view !== 'calendar';
    if (cap) cap.hidden = state.view !== 'board';
    return state.view === 'board' ? board : state.view === 'calendar' ? cal : list;
  }

  function paint() {
    var box = viewBox();
    if (!box || !state.tasks) return;
    /* The count is read against the view somebody chose, not against every
       row the database sent: "Open work, mine" is where this route opens, so
       counting it as `5 of 6` would print a fraction on a screen nobody has
       filtered. The search is the narrowing, and it is what puts "of" on. */
    var all = state.tasks.filter(function (t) { return inFilter(t) && inScope(t); });
    var rows = all.filter(matches);
    /* The board's workflow select is filled from the catalogue whether or not
       there is anything to draw: with no tasks the paint stopped at the empty
       line below and the select stood where Group by had been with nothing in
       it, which the user reported as an empty record on 2026-09-22. */
    if (state.view === 'board') boardWorkflow(all);
    var count = $('workCount');
    if (count) {
      count.textContent = !all.length ? ''
        : rows.length === all.length ? all.length + (all.length === 1 ? ' task' : ' tasks')
        : rows.length + ' of ' + all.length;
    }
    if (!all.length) {
      UI.emptyLine(box, 'No tasks.', may('ops', 'work') ? 'Create the first task' : '', openNew);
      return;
    }
    if (!rows.length) {
      /* Back to the view this route opens on, and no further: whose queue you
         are looking at is not a filter, so clearing the filters does not put
         somebody back on their own work without being asked. */
      UI.emptyLine(box, 'No matches.', 'Clear the filters', function () {
        state.find = ''; state.filter = 'open'; state.group = 'due';
        if ($('workFind')) $('workFind').value = '';
        if ($('workStage')) $('workStage').value = 'open';
        if ($('workGroup')) $('workGroup').value = 'due';
        showPeriod();
        paint();
      });
      return;
    }
    box.innerHTML = '';
    if (state.view === 'board') { paintBoard(all, rows); paintMoved(); return; }
    if (state.view === 'calendar') { paintCalendar(rows); return; }
    /* A *search* opens every card, because somebody who typed a title wants
       the row wherever it is and a shut card would hide the one match and say
       nothing. Choosing a stage in the bar is not that: it picks which work is
       on the page, and a card of four hundred finished tasks forced open by
       it is the opposite of help. */
    var filtered = Boolean(state.find);
    groupsOf(rows).forEach(function (g) {
      box.appendChild(GRP.section({
        route: 'work', key: g.key, name: g.name, count: g.rows.length,
        /* The fold is remembered per axis, while the card keeps its own name
           on the page: a client card shut under By client has nothing to say
           about a stage card under By stage, and one key for both would carry
           the answer across. */
        memo: state.group + ':' + g.key,
        marks: marksOf(g),
        /* A card that holds everything on the page never shuts by default, or
           a person whose work is all weeks away opens My Work on a heading
           over nothing. */
        shut: !filtered && GRP.shut('work', state.group + ':' + g.key,
                                    shutByDefault(g), g.rows.length === rows.length),
        table: function () {
          var table = GRP.table('svc-row task-row', ['Task', 'Stage', 'Owner', 'Due']);
          GRP.more(table, g.rows, 30, 'tasks', rowOf);
          return table;
        }
      }));
    });
    paintMoved();
  }

  // ---- The board -----------------------------------------------------------
  /* ONE WORKFLOW'S STAGES, SIDE BY SIDE. The columns and the work-in-progress
     guidance on them are the workflow's own, so the board is one workflow at
     a time and the select names which; it draws where Group by would,
     because the board has fixed the axis Group by chooses. The lanes beside
     the line (blocked, waiting, KIV) are one column at the end: a board is
     where the flow is read, and a task that has stepped out of the flow is
     in one place, not three. A terminal stage draws only while the filter
     lets finished work onto the page. */
  function boardWorkflow(all) {
    var counts = {};
    all.forEach(function (t) { counts[t.workflow_id] = (counts[t.workflow_id] || 0) + 1; });
    var wfs = state.workflows.filter(function (w) { return w.active !== false; });
    if (!state.wf || !wfs.some(function (w) { return w.id === state.wf; })) {
      var best = wfs.slice().sort(function (a, b) { return (counts[b.id] || 0) - (counts[a.id] || 0); })[0];
      state.wf = best ? best.id : null;
    }
    var sel = $('workWf');
    if (sel) {
      sel.innerHTML = wfs.map(function (w) {
        return '<option value="' + esc(w.id) + '"' + (w.id === state.wf ? ' selected' : '') + '>' +
          esc(w.name) + (counts[w.id] ? ' (' + counts[w.id] + ')' : '') + '</option>';
      }).join('');
    }
    return state.wf;
  }
  function stagesOf(wf) {
    return Object.keys(state.stages).map(function (k) { return state.stages[k]; })
      .filter(function (s) { return s.workflow_id === wf; })
      .sort(function (a, b) { return a.position - b.position; });
  }
  function paintBoard(all, rows) {
    var box = $('workBoard');
    var wf = boardWorkflow(all);
    var mine = rows.filter(function (t) { return t.workflow_id === wf; });
    var stages = stagesOf(wf);
    /* A board of nine columns is wider than any screen, and most of them are
       empty most of the time: the video workflow draws Intake, Ready,
       Shooting, Editing, Client review, Revision, Approved and Delivered
       whether or not anything is in them, so reading it means scrolling past
       columns that say None. An empty column is drawn only where it is still
       somewhere the work can go — the stage a task on this board could be
       moved into next, which is what a column is *for* — or where it is the
       workflow's own entry, because a board with nowhere to start reads as a
       board missing its first step. Everything else leaves, and comes back by
       itself the moment a task can reach it. */
    var reach = {};
    stages.forEach(function (s) {
      if (!mine.some(function (t) { return t.stage_key === s.key; })) return;
      (s.next_stage_keys || []).forEach(function (k) { reach[k] = 1; });
    });
    var entry = stages.length ? stages[0].key : null;
    var keep = function (s, n) { return n > 0 || reach[s.key] || s.key === entry; };
    var cols = stages.filter(function (s) { return !SIDE[s.stage_group] && !s.is_terminal; })
      .filter(function (s) {
        return keep(s, mine.filter(function (t) { return t.stage_key === s.key; }).length);
      })
      .map(function (s) { return { key: s.key, name: s.label, wip: s.wip_guidance, keys: [s.key] }; });
    /* On hold gathers the lanes beside the line, and is drawn only while it
       holds something: it is where work steps *out* of the flow, so an empty
       one is a column for a thing that has not happened. It is deliberately
       not a drop target either — Blocked needs a category before it means
       anything, and that is asked for on the record. */
    var held = stages.filter(function (s) { return SIDE[s.stage_group] && !s.is_terminal; });
    var heldKeys = held.map(function (s) { return s.key; });
    if (held.length && mine.some(function (t) { return heldKeys.indexOf(t.stage_key) > -1; })) {
      cols.push({ key: 'held', name: 'On hold', wip: null, keys: heldKeys, noDrop: true });
    }
    stages.filter(function (s) { return s.is_terminal; }).forEach(function (s) {
      if (mine.some(function (t) { return t.stage_key === s.key; })) {
        cols.push({ key: s.key, name: s.label, wip: null, keys: [s.key] });
      }
    });
    paintCapacity();
    box.innerHTML = '';
    if (!mine.length) {
      UI.emptyLine(box, 'No tasks in this workflow.', '', null);
      return;
    }
    var board = document.createElement('div');
    board.className = 'board';
    cols.forEach(function (c) {
      var cards = mine.filter(function (t) { return c.keys.indexOf(t.stage_key) > -1; });
      var col = document.createElement('div');
      col.className = 'bcol' + (!cards.length ? ' is-empty' : '') +
        (c.wip && cards.length > c.wip ? ' is-over' : '');
      col.setAttribute('data-col', c.key);
      col.innerHTML = '<div class="bcol-head"><h3>' + esc(c.name) + '</h3>' +
        '<span class="bcol-n">' + cards.length + (c.wip ? ' / ' + c.wip : '') + '</span></div>' +
        '<div class="bcards"></div>';
      var list = col.querySelector('.bcards');
      if (!cards.length) list.innerHTML = '<p class="bcol-empty">None.</p>';
      cards.forEach(function (t) { list.appendChild(cardOf(t)); });
      if (!c.noDrop) dropInto(col, c.keys[0]);
      board.appendChild(col);
    });
    box.appendChild(board);
  }

  /* Dragging a card is the one thing a board is expected to do, and it was the
     first thing the user reached for. It is the same move as the select on the
     card: the same function, the same gates, the same refusal named in the
     team's words on the card it was made on. What it adds is that the board
     says where a card may go *before* it is dropped, which is this portal's
     rule about constraining an invalid choice rather than reporting it: while
     a card is in hand every column the workflow allows is marked and every
     other is dimmed, so a refusal is rare and never a surprise.

     It is deliberately a pointer affordance only. Dragging cannot be done from
     a keyboard and HTML5 drag events do not fire under a finger, so the select
     on every card stays exactly where it was and is the path for both — this
     is an addition, never a replacement, and no screen loses a way to move a
     stage. */
  var drag = null;

  function dragAllowed(next) {
    if (!drag || !next) return false;
    if (drag.task.stage_key === next) return false;
    var s = stageOf(drag.task);
    return Boolean(s && (s.next_stage_keys || []).indexOf(next) > -1);
  }

  /* A column that will take a drop says so on itself, and the pointer drag
     below reads that rather than each column carrying its own listeners: one
     place decides what a drop means, whichever input made it. */
  function dropInto(col, next) {
    if (!may('ops', 'work')) return;
    col.setAttribute('data-drop', next);
  }

  function startDrag(t, el) {
    drag.task = t;
    drag.el = el;
    el.classList.add('is-dragging');
    var board = el.closest('.board');
    if (!board) return;
    drag.board = board;
    board.classList.add('is-dragging');
    /* Every column says whether this card may land in it, so the answer is on
       the screen while the hand is still moving: error prevention rather than
       an error message afterwards. */
    Array.prototype.forEach.call(board.querySelectorAll('.bcol'), function (c) {
      c.classList.toggle('is-shut-out', !dragAllowed(c.getAttribute('data-drop')));
    });
  }

  function endDrag() {
    if (drag && drag.el) drag.el.classList.remove('is-dragging');
    var g = drag && drag.ghost && drag.ghost.el;
    if (g && g.parentNode) g.parentNode.removeChild(g);
    var board = (drag && drag.board) || document.querySelector('.board');
    if (board) {
      board.classList.remove('is-dragging');
      Array.prototype.forEach.call(board.querySelectorAll('.bcol'), function (c) {
        c.classList.remove('is-shut-out', 'is-drop');
      });
    }
    drag = null;
  }

  /* **A card is dragged by a finger as well as by a pointer.**
     It was HTML5 drag and drop, set under `(pointer: fine)` alone, because
     those events do not fire under a finger - which meant the board could not
     be rearranged on the device most of this portal is read on, and the user
     asked for exactly that. Pointer events are one API for both, so this is
     one path rather than two.

     **A finger drags from a grip, a pointer from anywhere on the card.** A
     press and hold was tried first and cannot work: a phone decides whether a
     touch is a scroll at the moment it lands, before any class this page sets
     can say otherwise, so the board claimed the gesture and cancelled the drag
     the instant the finger moved. A grip declares `touch-action: none` on
     itself, so the browser never claims a gesture that starts there, the rest
     of the card still scrolls the board, and there is no hold to wait out. It
     is drawn at every width, because a handle that appears only on a phone is
     a control somebody has to discover twice; at a desk the whole card is a
     handle as well, since a mouse has no scroll to lose.

     The card that lifts is a clone under the hand, never the card itself:
     moving the real one out of its column reflows the board mid gesture. */
  var SLOP = 8;

  function ghostOf(el, x, y) {
    var r = el.getBoundingClientRect();
    var g = el.cloneNode(true);
    g.className = el.className.replace(/\bis-dragging\b/, '') + ' bcard-ghost';
    g.style.width = r.width + 'px';
    g.style.left = r.left + 'px';
    g.style.top = r.top + 'px';
    g.setAttribute('aria-hidden', 'true');
    document.body.appendChild(g);
    return { el: g, dx: x - r.left, dy: y - r.top,
             move: function (nx, ny) {
               g.style.transform = 'translate(' + (nx - x) + 'px,' + (ny - y) + 'px)';
             } };
  }

  /* The column under the pointer, found by what is actually on the screen
     there, because the clone is `pointer-events: none` and a finger has no
     hover to read. */
  function colAt(x, y) {
    var el = document.elementFromPoint(x, y);
    return el ? el.closest('.bcol') : null;
  }

  function wireDrag(el, t) {
    el.addEventListener('pointerdown', function (e) {
      if (e.button !== 0 && e.pointerType === 'mouse') return;
      /* The title opens the task and the select moves the stage; neither is a
         handle, or a press on them would never reach its own control. */
      var touch = e.pointerType !== 'mouse';
      var grip = Boolean(e.target.closest('.bcard-grip'));
      /* A finger starts a drag from the grip and nowhere else, so the rest of
         the card is still the board's to scroll. */
      if (touch && !grip) return;
      if (!grip && e.target.closest('.bcard-title, .state-select, select, button, a')) return;
      var sx = e.clientX, sy = e.clientY, id = e.pointerId;
      var lifted = false;

      function lift(x, y) {
        lifted = true;
        drag = { task: null, el: null, ghost: null, board: null };
        drag.ghost = ghostOf(el, x, y);
        startDrag(t, el);
        try { el.setPointerCapture(id); } catch (err) {}
      }
      function move(ev) {
        if (ev.pointerId !== id) return;
        if (!lifted) {
          if (Math.abs(ev.clientX - sx) <= SLOP && Math.abs(ev.clientY - sy) <= SLOP) return;
          lift(sx, sy);
        }
        ev.preventDefault();
        drag.ghost.move(ev.clientX, ev.clientY);
        var col = colAt(ev.clientX, ev.clientY);
        Array.prototype.forEach.call(drag.board.querySelectorAll('.bcol'), function (c) {
          c.classList.toggle('is-drop', c === col && dragAllowed(c.getAttribute('data-drop')));
        });
      }
      function up(ev) {
        if (ev.pointerId !== id) return;
        if (!lifted) { done(); return; }
        var col = colAt(ev.clientX, ev.clientY);
        var next = col && col.getAttribute('data-drop');
        var ok = next && dragAllowed(next);
        var task = drag.task, card = drag.el;
        done();
        /* The same path the select on the card takes, so the gates, the
           refusal and where it is named are all one thing. */
        if (ok) moveTo(task, card, next);
      }
      function done() {
        document.removeEventListener('pointermove', move, true);
        document.removeEventListener('pointerup', up, true);
        document.removeEventListener('pointercancel', up, true);
        try { el.releasePointerCapture(id); } catch (err) {}
        if (lifted) endDrag();
        lifted = false;
      }
      document.addEventListener('pointermove', move, true);
      document.addEventListener('pointerup', up, true);
      document.addEventListener('pointercancel', up, true);
    });
  }
  /* A card is the row, stood up, and read in the order somebody scans a board:
     what it is, whose it is, when it is owed. The title is the heaviest thing
     on it and is what opens the task; the serial is demoted into the mute line
     above it beside the client, because a number is how a card is quoted in a
     message and never why anybody is looking at it; the owner is a disc and a
     name on the foot, which is the fact a board is read for and which this
     card did not carry at all; the due date ends that same line, warn once it
     has passed. The stage select sits between them, through the same function
     and the same gates as the list, with a refusal named on the card. */
  function cardOf(t) {
    var el = document.createElement('div');
    el.className = 'bcard' + (isFinished(t) ? ' is-off' : '');
    el.setAttribute('data-task', t.id);
    var over = !isFinished(t) && daysAway(t.current_final_due_at) < 0;
    var top = ['T' + t.task_no,
               (t.clients && t.clients.name) || (t.scope === 'internal' ? 'Internal' : '')]
      .filter(Boolean);
    var who = state.owners[t.id] || '';
    el.innerHTML =
      '<div class="bcard-top"><span class="bcard-no">' + esc(top[0]) + '</span>' +
        (top[1] ? '<span class="bcard-client">' + esc(top[1]) + '</span>' : '') +
        /* The grip a finger drags from. It carries its own name, because an
           icon-only control that says nothing is one a screen reader cannot
           offer; and it is not a keyboard path — a keyboard moves a stage
           with the select below it, which every card carries. */
        (may('ops', 'work') && !isFinished(t)
          ? '<span class="bcard-grip" aria-hidden="true" title="Drag to move stage">' +
            '<svg viewBox="0 0 24 24" fill="currentColor"><circle cx="9" cy="6" r="1.6"/>' +
            '<circle cx="15" cy="6" r="1.6"/><circle cx="9" cy="12" r="1.6"/>' +
            '<circle cx="15" cy="12" r="1.6"/><circle cx="9" cy="18" r="1.6"/>' +
            '<circle cx="15" cy="18" r="1.6"/></svg></span>'
          : '') + '</div>' +
      '<button class="bcard-title" type="button">' + esc(t.title) + '</button>' +
      '<div class="bcard-stage">' + stageCell(t) + '</div>' +
      '<div class="bcard-foot">' +
        '<span class="bcard-who">' +
          (who ? '<span class="bcard-face" aria-hidden="true">' + esc(UI.initials(who)) + '</span>' +
                 '<span class="bcard-name">' + esc(who) + '</span>'
               : '<span class="bcard-face is-none" aria-hidden="true"></span>' +
                 '<span class="bcard-name mute">Unassigned</span>') + '</span>' +
        (t.current_final_due_at
          ? '<span class="bcard-due' + (over ? ' is-over' : '') + '">' +
              esc(shortDate(t.current_final_due_at)) + '</span>'
          : '') +
      '</div>';
    el.querySelector('.bcard-title').addEventListener('click', function () { openTask(t.id, true); });
    var sel = el.querySelector('.state-select');
    if (sel) sel.addEventListener('change', function () { rowMove(t, el, sel); });
    /* Wherever the move is allowed at all, under a finger as under a pointer.
       A keyboard still has no drag, so the select on every card stays and is
       the path both share: this is an addition, never a replacement. */
    if (may('ops', 'work') && !isFinished(t)) wireDrag(el, t);
    return el;
  }

  // ---- The calendar --------------------------------------------------------
  /* The commitments on the days they fall. One date a task, the final due
     date, because that is the promise the queue is ordered by and the rail
     states the rest; a chip is the task at the size a cell can hold and a
     press opens it. */
  function monthStart(d) { return new Date(d.getFullYear(), d.getMonth(), 1); }
  function sameDay(a, b) { return a && b && a.getTime() === b.getTime(); }
  function paintCalendar(rows) {
    var box = $('workCal');
    if (!state.month) state.month = monthStart(new Date());
    var m = state.month, today = todayStart();
    var byDay = {};
    rows.forEach(function (t) {
      var d = dayOf(t.current_final_due_at);
      if (!d) return;
      (byDay[d.getTime()] = byDay[d.getTime()] || []).push(t);
    });
    var title = m.toLocaleDateString('en-GB', { month: 'long', year: 'numeric' });
    /* The short month draws under 360px, where "September 2026" with its two
       arrows and Today ran past the gutter; the day labels already say Sept. */
    var short = m.toLocaleDateString('en-GB', { month: 'short', year: 'numeric' }).replace(/^Sep /, 'Sept ');
    var chev = function (path) {
      return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="' + path + '"/></svg>';
    };
    var html = '<div class="calbar">' +
      '<button class="btn btn-sm iconbtn" data-cal="prev" type="button" aria-label="Previous month">' + chev('M15 18l-6-6 6-6') + '</button>' +
      '<h3><span class="cal-mlong">' + esc(title) + '</span><span class="cal-mshort">' + esc(short) + '</span></h3>' +
      '<button class="btn btn-sm iconbtn" data-cal="next" type="button" aria-label="Next month">' + chev('M9 18l6-6-6-6') + '</button>' +
      '<button class="btn btn-sm btn-quiet" data-cal="today" type="button">Today</button>' +
      '</div>';
    var first = new Date(m), start = new Date(m);
    /* Monday first, as this team's week is. */
    start.setDate(first.getDate() - ((first.getDay() + 6) % 7));
    var end = new Date(m.getFullYear(), m.getMonth() + 1, 0);
    end.setDate(end.getDate() + (7 - ((end.getDay() + 6) % 7) - 1));
    var cells = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map(function (d) {
      return '<div class="cal-dow">' + d + '</div>';
    }).join('');
    for (var d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
      var k = d.getTime(), list = byDay[k] || [];
      var out = d.getMonth() !== m.getMonth();
      var cls = 'cal-day' + (out ? ' is-out' : '') + (sameDay(d, today) ? ' is-today' : '') +
        ((d.getDay() === 0 || d.getDay() === 6) ? ' is-weekend' : '') + (!list.length ? ' is-empty' : '');
      var chips = list.slice(0, 3).map(function (t) {
        var late = !isFinished(t) && d < today;
        return '<button class="cal-chip btn-sm ' + stageTone(t) + (late ? ' is-late' : '') + '" type="button" data-task="' + esc(t.id) + '">' +
          esc(t.title) + '</button>';
      }).join('') + (list.length > 3 ? '<span class="cal-more">+' + (list.length - 3) + ' more</span>' : '');
      cells += '<div class="' + cls + '" data-day="' + esc(d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2)) + '">' +
        '<span class="cal-num"><small>' + esc(d.toLocaleDateString('en-GB', { weekday: 'short' })) + '</small>' +
          '<b>' + d.getDate() + '</b><small>' + esc(d.toLocaleDateString('en-GB', { month: 'short' })) + '</small></span>' +
        chips + '</div>';
    }
    box.innerHTML = html + '<div class="cal">' + cells + '</div>';
    box.querySelector('[data-cal="prev"]').addEventListener('click', function () {
      state.month = new Date(m.getFullYear(), m.getMonth() - 1, 1); paintCalendar(rows);
    });
    box.querySelector('[data-cal="next"]').addEventListener('click', function () {
      state.month = new Date(m.getFullYear(), m.getMonth() + 1, 1); paintCalendar(rows);
    });
    box.querySelector('[data-cal="today"]').addEventListener('click', function () {
      state.month = monthStart(new Date()); paintCalendar(rows);
    });
    Array.prototype.forEach.call(box.querySelectorAll('.cal-chip'), function (b) {
      b.addEventListener('click', function () { openTask(b.getAttribute('data-task'), true); });
    });
  }

  // ---- Capacity ------------------------------------------------------------
  /* The week's recorded hours against each person's capacity. A planning
     figure beside the record of what was pressed: nothing here measures
     attention, and a week with no sessions is a week nobody pressed Start.
     Own week alone without `ops.all`; the team's with it. */
  function weekStart() {
    var d = todayStart();
    d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
    return d;
  }
  function loadCapacity() {
    db.from('ops_work_sessions').select('team_member_id, minutes, started_at, ended_at')
      .gte('started_at', weekStart().toISOString())
      .then(function (r) {
        state.week = (r && r.data) || [];
        paintCapacity();
      }, function () { state.week = []; paintCapacity(); });
  }
  function paintCapacity() {
    var box = $('workCap');
    if (!box || state.view !== 'board') return;
    var me = bridge.me && bridge.me();
    var team = may('ops.all', 'view');
    var mins = {};
    state.week.forEach(function (s) {
      var n = Number(s.minutes) || (s.started_at && !s.ended_at ? Math.max(0, (Date.now() - new Date(s.started_at)) / 60000) : 0);
      mins[s.team_member_id] = (mins[s.team_member_id] || 0) + n;
    });
    var open = {};
    (state.tasks || []).forEach(function (t) {
      if (isFinished(t) || !state.ownerIds[t.id]) return;
      open[state.ownerIds[t.id]] = (open[state.ownerIds[t.id]] || 0) + 1;
    });
    var people = state.members.filter(function (m) {
      if (!team) return me && m.id === me.id;
      return m.capacity_minutes_week || mins[m.id] || open[m.id];
    });
    if (!people.length) { box.innerHTML = ''; return; }
    var hours = function (n) { return (Math.round(n / 30) / 2) + 'h'; };
    box.innerHTML = '<div class="capstrip">' + people.map(function (m) {
      var used = mins[m.id] || 0, cap = m.capacity_minutes_week || 0;
      var pct = cap ? Math.min(100, Math.round(used / cap * 100)) : 0;
      return '<div class="caprow' + (cap && used > cap ? ' is-over' : '') + '">' +
        '<span class="caprow-name">' + esc(m.name) + '</span>' +
        '<span class="caprow-fig">' + hours(used) + (cap ? ' of ' + hours(cap) : ' · no capacity set') +
          (open[m.id] ? ' · ' + open[m.id] + ' open' : '') + '</span>' +
        '<span class="capbar"><i style="width:' + pct + '%"></i></span></div>';
    }).join('') + '</div>';
  }

  // ---- The view ------------------------------------------------------------
  /* The segment and the bar's controls follow the view: Group by is the
     list's axis and the workflow select is the board's, so each draws only
     with its view. */
  function applyView(v) {
    state.view = v === 'board' || v === 'calendar' ? v : 'list';
    var seg = $('workViews');
    if (seg) Array.prototype.forEach.call(seg.querySelectorAll('.acttab'), function (b) {
      var on = b.getAttribute('data-view') === state.view;
      b.classList.toggle('is-on', on);
      b.setAttribute('aria-pressed', String(on));
    });
    if ($('workGroup')) $('workGroup').hidden = state.view !== 'list';
    if ($('workWf')) $('workWf').hidden = state.view !== 'board';
    if (state.view === 'board') loadCapacity();
  }
  function setView(v) {
    applyView(v);
    paint();
    if (bridge.setUrl) bridge.setUrl();
  }

  /* THE COMMONEST ACT ON THIS LIST IS MOVING A STAGE, so the stage cell is
     the portal's own tinted state select and not a chip somebody has to open
     the record to change. It goes through `ops_transition_task` like every
     other move, so the gates are the same and a refusal is named in the same
     words — under the row, where the act was.

     The row is therefore no longer a single `<button>`. A control inside a
     control is one a screen reader trips over, so what opens the task is the
     name cell: the widest cell, full row height, where the eye already is.
     The chevron went with the button, because a mark that is no longer a
     target is furniture. */
  function rowOf(t) {
    var el = document.createElement('div');
    el.className = 'svc-row task-row' + (isFinished(t) ? ' is-off' : '');
    el.setAttribute('data-task', t.id);
    var over = !isFinished(t) && daysAway(t.current_final_due_at) < 0;
    var meta = [(t.clients && t.clients.name) || (t.scope === 'internal' ? 'Internal' : ''),
                DELIVER_WORD[t.deliverable_type] || sentence(t.deliverable_type)]
      .filter(Boolean).join(' · ');
    el.innerHTML =
      '<button class="task-open" type="button"><b>' + esc(t.title) + '</b>' +
        '<small>' + esc(meta) + '</small></button>' +
      '<span class="task-stage">' + stageCell(t) + '</span>' +
      '<span class="task-owner">' + (state.owners[t.id] ? esc(state.owners[t.id]) : '<span class="mute">—</span>') + '</span>' +
      '<span class="task-due' + (over ? ' is-over' : '') + '">' + esc(dueWord(t.current_final_due_at)) + '</span>';
    el.querySelector('.task-open').addEventListener('click', function () { openTask(t.id, true); });
    var sel = el.querySelector('.state-select');
    if (sel) sel.addEventListener('change', function () { rowMove(t, el, sel); });
    return el;
  }

  /* A select where the person may work the task and the stage can still move,
     the read-only chip everywhere else: a control that cannot do anything is
     a control that should not be drawn. */
  function stageCell(t) {
    var s = stageOf(t);
    /* Blocked needs a category before it means anything, so it is asked for
       on the record and never set from a list. */
    var nexts = ((s && s.next_stage_keys) || []).filter(function (k) { return k !== 'blocked'; });
    if (!may('ops', 'work') || isFinished(t) || !nexts.length) {
      return '<span class="tone ' + stageTone(t) + '">' + esc(stageLabel(t)) + '</span>';
    }
    return '<select class="select select-sm state-select ' + stageTone(t) + '" ' +
      'aria-label="Stage of ' + esc(t.title) + '">' +
      '<option value="">' + esc(stageLabel(t)) + '</option>' +
      nexts.map(function (k) {
        return '<option value="' + esc(k) + '">' + esc(labelOfStage(t, k)) + '</option>';
      }).join('') + '</select>';
  }
  function labelOfStage(t, k) {
    var s = state.stages[t.workflow_id + '|' + k];
    return (s && s.label) || String(k || '').replace(/_/g, ' ');
  }

  /* The move the row asked for. A refusal puts the select back where it was
     and says why under the row, because the row is where the act happened and
     the command bar is a screen away from it on a long list. */
  function rowMove(t, el, sel) {
    moveTo(t, el, sel.value, function () { sel.value = ''; });
  }
  /* One path for every way a stage is moved on this page — the select on a
     list row, the select on a board card, and a card dragged into a column.
     All three go through `ops_transition_task` and therefore through the same
     gates, and all three name the refusal on the thing that was moved rather
     than in a bar a screen away. */
  function moveTo(t, el, next, back) {
    if (!next) return;
    back = back || function () {};
    rowNote(el, '');
    db.rpc('ops_transition_task',
      { p_task: t.id, p_next: next, p_version: t.version, p_note: null })
      .then(function (r) {
        if (r.error) { back(); rowNote(el, r.error.message); return; }
        var d = r.data;
        if (d && d.error) { back(); rowNote(el, said(d.error)); return; }
        /* A move that repaints the list and says nothing is a move nobody can
           tell they made: the row is rebuilt somewhere else in the band order
           and the select they pressed is gone. What happened is named under
           the row it happened on, once the repaint has drawn it. */
        state.moved = { id: t.id, word: labelOfStage(t, next) };
        /* The band a row belongs to can change with its stage, so the queue is
           repainted rather than the cell patched. */
        load();
      }, function (e) { back(); rowNote(el, (e && e.message) || String(e)); });
  }
  /* The note the last move left, drawn on the row the repaint has just made. */
  function paintMoved() {
    var m = state.moved;
    if (!m) return;
    state.moved = null;
    var row = document.querySelector('[data-task="' + m.id + '"]');
    if (row) rowNote(row, 'Moved to ' + m.word + '.', 'ok');
  }
  function rowNote(el, text, tone) {
    var was = el.nextSibling;
    if (was && was.classList && was.classList.contains('task-note')) was.remove();
    if (!text) return;
    var note = document.createElement('div');
    note.className = 'msg ' + (tone || 'err') + ' task-note';
    note.textContent = text;
    el.parentNode.insertBefore(note, el.nextSibling);
    if (tone === 'ok') setTimeout(function () { if (note.parentNode) note.remove(); }, 6000);
  }

  // ---- One task ------------------------------------------------------------
  function showList() {
    state.task = null;
    state.openId = null;
    $('workList').hidden = false;
    $('workRec').hidden = true;
    if (bridge.setUrl) bridge.setUrl();
    load();
  }

  function openTask(id, push) {
    $('workList').hidden = true;
    $('workRec').hidden = false;
    msg('taskMsg', '');
    /* The address is written before the read comes back, or it is written
       from a state that does not yet hold the task somebody just opened: a
       reload would land on the queue rather than on the row they pressed. */
    state.openId = id;
    if (push && bridge.pushUrl) bridge.pushUrl();
    readTask(id);
  }

  /* One read of the task and everything hanging off it. The row itself comes
     back from `ops_task_json` after every write, so the panes are repainted
     from the answer the write gave rather than from a second request that can
     disagree with it. */
  function readTask(id, after) {
    Promise.all([
      db.from('ops_tasks').select('*, clients(name)').eq('id', id).single(),
      db.from('ops_task_checklist_items').select('*').eq('task_id', id).order('position'),
      db.from('ops_task_links').select('*').eq('task_id', id).order('created_at'),
      db.from('ops_work_sessions')
        .select('*, team_members!ops_work_sessions_team_member_id_fkey(name)')
        .eq('task_id', id).order('started_at', { ascending: false }),
      db.from('ops_task_events').select('*').eq('task_id', id).order('created_at', { ascending: false }).limit(60),
      db.from('ops_task_assignees')
        .select('*, team_members!ops_task_assignees_team_member_id_fkey(name)')
        .eq('task_id', id).is('ended_at', null),
      db.from('ops_video_details').select('*').eq('task_id', id),
      /* The extension nobody has answered yet. Read with the task, because
         it is part of where the task stands and a second round trip would
         paint the rail twice. A refused read leaves no block rather than
         failing the record: the dates themselves are still true. */
      db.from('ops_due_requests').select('*').eq('task_id', id).eq('state', 'asked')
    ]).then(function (r) {
      /* Who owns it is part of the record, so a refused read of the
         assignments is named rather than drawn as an unowned task. */
      var bad = r[0].error || (r[5] && r[5].error);
      if (bad || !r[0].data) {
        msg('taskMsg', (bad && bad.message) || 'That task could not be read.', 'err');
        return;
      }
      var t = r[0].data;
      state.due = (((r[7] && r[7].data) || [])[0]) || null;
      t.assignees = ((r[5] && r[5].data) || []).map(function (a) {
        return { team_member_id: a.team_member_id, responsibility: a.responsibility,
                 name: (a.team_members && a.team_members.name) || '' };
      });
      state.task = t;
      state.detail = {
        checklist: (r[1] && r[1].data) || [],
        links: (r[2] && r[2].data) || [],
        sessions: (r[3] && r[3].data) || [],
        events: (r[4] && r[4].data) || [],
        video: (r[6] && r[6].data && r[6].data[0]) || null
      };
      loadSession(function () { paintTask(); if (after) after(); });
    }, function (e) {
      msg('taskMsg', (e && e.message) || String(e), 'err');
    });
  }

  /* A write answers with the task, so the record repaints from that answer and
     the lists that hang off it are re-read only where the write could have
     changed them. */
  function applyTask(t) {
    if (!t) return;
    if (t.clients === undefined && state.task) t.clients = state.task.clients;
    state.task = t;
  }

  function paintTask() {
    var t = state.task;
    if (!t) return;
    paintIdentity(t);
    paintOverview(t);
    paintChecklist();
    paintLinks();
    paintTime();
    paintLog();
    paintRail(t);
    if (UI.fit) UI.fit();
  }

  function paintIdentity(t) {
    var mark = $('taskMark');
    /* The task number is what an invoice, a message and a spreadsheet row all
       name it by, so it heads the record in the token face and copies on a
       press, the way a serial does on the Register. It was a 46px disc, which
       is a shape for a logo or a monogram; five characters pressed into it
       read as a badly fitted logo. */
    if (mark) {
      mark.textContent = 'T' + t.task_no;
      mark.setAttribute('aria-label', 'Copy T' + t.task_no);
    }
    $('taskName').textContent = t.title || 'Untitled task';
    var who = state.owners[t.id] ||
      (t.assignees || []).filter(function (a) { return a.responsibility === 'owner'; })
        .map(function (a) { return a.name; })[0] || '';
    $('taskMeta').textContent = [
      (t.clients && t.clients.name) || (t.scope === 'internal' ? 'Internal' : ''),
      DELIVER_WORD[t.deliverable_type] || sentence(t.deliverable_type),
      who ? 'Owner ' + who : ''
    ].filter(Boolean).join(' · ');
    var chip = $('taskStage');
    chip.className = 'chip ' + stageTone(t);
    chip.textContent = stageLabel(t);

    var menu = $('taskMenu');
    menu.querySelector('[data-a="block"]').hidden = t.stage_key === 'blocked' || isFinished(t);
    menu.querySelector('[data-a="reopen"]').hidden = !t.completed_at;
    var arch = menu.querySelector('[data-a="archive"]');
    arch.textContent = t.archived_at ? 'Restore' : 'Archive';

    paintNext(t);
  }

  /* What this task is waiting on, derived on every repaint and never stored:
     a line written once by the action that caused it goes stale the moment
     somebody reverts. */
  function paintNext(t) {
    var line = $('taskNext');
    var s = stageOf(t), words = [];
    if (t.stage_key === 'blocked') {
      words.push('Blocked on ' + (t.blocked_category || 'something') +
        (t.blocked_note ? ': ' + t.blocked_note : '') + '.');
    } else if (isFinished(t)) {
      words = [];
    } else if (t.stage_key === 'intake') {
      var needs = [];
      if (!ownerId(t)) needs.push('an owner');
      if (!t.current_final_due_at) needs.push('a final due date');
      words.push(needs.length ? 'Ready needs ' + needs.join(' and ') + '.'
                              : 'Ready to move to Ready.');
    } else if (t.stage_key === 'internal_review' && !hasLink('draft') && !hasLink('review')) {
      words.push('Client review needs a draft or review link.');
    } else if (t.stage_key === 'approved' && !hasLink('final')) {
      words.push('Delivered needs a final link.');
    } else if (s && s.is_waiting) {
      words.push('Waiting. Nothing here moves until that changes.');
    }
    var over = !isFinished(t) && daysAway(t.current_final_due_at) < 0;
    if (over) words.push('The final date passed ' + Math.abs(daysAway(t.current_final_due_at)) + ' days ago.');
    line.textContent = words.join(' ');
    line.hidden = !words.length;
  }
  function ownerId(t) {
    var a = (t.assignees || []).filter(function (x) { return x.responsibility === 'owner'; })[0];
    return (a && a.team_member_id) || null;
  }
  function hasLink(kind) {
    return state.detail.links.some(function (l) { return l.kind === kind && !l.archived_at; });
  }

  // ---- Overview ------------------------------------------------------------
  function ovSection(title, action, body) {
    return '<section class="ovsec">' +
      '<div class="ovsec-head"><h3>' + esc(title) + '</h3>' + (action || '') + '</div>' +
      body + '</section>';
  }
  function factRows(pairs) {
    var out = pairs.filter(function (p) { return p[1]; }).map(function (p) {
      return '<div class="ovfact"><dt>' + esc(p[0]) + '</dt><dd>' + p[1] + '</dd></div>';
    }).join('');
    return '<dl class="ovfacts">' + (out || '<div class="ovfact"><dd class="mute">Nothing recorded.</dd></div>') + '</dl>';
  }

  function paintOverview(t) {
    var box = $('taskOv');
    if (!box) return;
    var v = state.detail.video;
    var done = state.detail.checklist.filter(function (c) { return c.completed_at; }).length;
    var mins = state.detail.sessions.reduce(function (a, s) { return a + (Number(s.minutes) || 0); }, 0);
    var live = state.detail.links.filter(function (l) { return !l.archived_at; });

    var brief = (t.description || t.remarks)
      ? '<p class="ovnote">' + esc(t.description || '') + '</p>' +
        (t.remarks ? '<p class="ovnote mute">' + esc(t.remarks) + '</p>' : '')
      : '<p class="ovnote mute">No brief was written.</p>';

    /* Editing is refused while footage is marked not ready, so the mark is a
       control here rather than a fact somebody has to go and find. */
    var video = v ? factRows([
      ['Script', v.script_ready === null ? '<span class="mute">Not said</span>'
        : v.script_ready ? '<span class="tone is-ok">Ready</span>' : '<span class="tone is-warn">Not ready</span>'],
      ['Footage', v.footage_ready === null ? '<span class="mute">Not said</span>'
        : v.footage_ready ? '<span class="tone is-ok">Ready</span>' : '<span class="tone is-warn">Not ready</span>'],
      ['Shoot', esc(niceTime(v.shoot_at))],
      ['Output', v.output_duration_seconds ? esc(v.output_duration_seconds + ' seconds') : ''],
      ['Subtitles', v.subtitle_required ? 'Required' : '']
    ]) : '';

    /* The links, as the client record's Overview lists letters: concise real
       rows and the one control that opens the pane. `.ovgo` is a modifier, not
       a button: the shape and the control floor come from `.btn .btn-quiet
       .btn-sm`, or the control is 26px tall under a 44px finger. */
    var links = live.length
      ? '<ul class="ovlinks">' + live.slice(0, 5).map(function (l) {
          var href = safeUrl(l.url);
          return '<li><span class="tone">' + esc(l.kind) + '</span>' +
            (href ? '<a href="' + esc(href) + '" target="_blank" rel="noopener">' + esc(l.label) + '</a>'
                  : '<span>' + esc(l.label) + '</span>') + '</li>';
        }).join('') + '</ul>'
      : '<p class="ovnote mute">None yet.</p>';
    var goLinks = '<button class="btn btn-quiet btn-sm ovgo" data-a="links" type="button">' +
      (live.length ? 'Manage links' : 'Add a link') +
      '<svg class="ovgo-chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 18l6-6-6-6"/></svg></button>';

    box.innerHTML = '<div class="ovcard">' +
      ovSection('Brief', '', brief) +
      (v ? ovSection('Video', may('ops', 'work')
        ? '<button class="btn btn-sm" data-a="footage" type="button">' +
          (v.footage_ready ? 'Mark footage not ready' : 'Mark footage ready') + '</button>' : '', video) : '') +
      ovSection('Progress', '', factRows([
        ['Checklist', state.detail.checklist.length ? esc(done + ' of ' + state.detail.checklist.length + ' done') : ''],
        ['Recorded work', mins ? esc(minutesWord(mins)) : '<span class="mute">None yet</span>'],
        ['Estimate', t.estimate_minutes ? esc(minutesWord(t.estimate_minutes)) : '']
      ])) +
      ovSection('Links', goLinks, links) +
      '</div>';

    var gl = box.querySelector('[data-a="links"]');
    if (gl) gl.addEventListener('click', function () { showPane('links'); });
    var ft = box.querySelector('[data-a="footage"]');
    if (ft) ft.addEventListener('click', function () {
      call('ops_set_video', { p_task: t.id, p_payload: { footage_ready: !v.footage_ready } },
        'taskMsg', function () { readTask(t.id); });
    });
  }

  // ---- Checklist -----------------------------------------------------------
  function paintChecklist() {
    var box = $('taskCheck');
    if (!box) return;
    var items = state.detail.checklist;
    if (!items.length) {
      UI.emptyLine(box, 'No checklist.');
      return;
    }
    var can = may('ops', 'work');
    box.innerHTML = '<div class="softpanel">' + items.map(function (c) {
      return '<label class="checkrow' + (c.completed_at ? ' is-done' : '') + '">' +
        '<input type="checkbox" data-item="' + esc(c.id) + '"' +
          (c.completed_at ? ' checked' : '') + (can ? '' : ' disabled') + '>' +
        '<span class="checkrow-label">' + esc(c.label) +
          (c.required ? ' <span class="tone is-warn">Required</span>' : '') + '</span>' +
        '<span class="checkrow-when">' + esc(c.completed_at ? niceTime(c.completed_at) : '') + '</span>' +
        '</label>';
    }).join('') + '</div>';
    /* The row it ticked is updated where it sits, never by repainting the
       list: a list that redraws under the pointer takes the focus away from
       somebody working down it with a keyboard, and the tick they just made
       is the one thing that must not move. */
    Array.prototype.forEach.call(box.querySelectorAll('[data-item]'), function (cb) {
      cb.addEventListener('change', function () {
        var want = cb.checked;
        var line = cb.closest('.checkrow');
        call('ops_set_checklist', { p_item: cb.getAttribute('data-item'), p_done: want },
          'taskMsg', function (row) {
            if (!row) { cb.checked = !want; return; }
            state.detail.checklist = state.detail.checklist.map(function (c) {
              return c.id === row.id ? row : c;
            });
            if (line) {
              line.classList.toggle('is-done', Boolean(row.completed_at));
              var when = line.querySelector('.checkrow-when');
              if (when) when.textContent = row.completed_at ? niceTime(row.completed_at) : '';
            }
            paintOverview(state.task);
          }, function () { cb.checked = !want; });
      });
    });
  }

  // ---- Links ---------------------------------------------------------------
  function paintLinks() {
    var box = $('taskLinks');
    if (!box) return;
    var live = state.detail.links.filter(function (l) { return !l.archived_at; });
    if (!live.length) {
      UI.emptyLine(box, 'No links.', may('ops', 'work') ? 'Add the first link' : '', openLinkForm);
      return;
    }
    var can = may('ops', 'work');
    box.innerHTML = '';
    var table = GRP.table('svc-row tlink-row', ['Link', 'Kind', '']);
    live.forEach(function (l) {
      var row = document.createElement('div');
      var href = safeUrl(l.url);
      row.className = 'svc-row tlink-row';
      row.innerHTML =
        '<span class="svc-name"><b>' + esc(l.label) + '</b><small>' + esc(l.url) + '</small></span>' +
        '<span class="tlink-kind"><span class="tone">' + esc(l.kind) + '</span></span>' +
        '<span class="team-act">' +
          (href ? '<a class="btn btn-sm" href="' + esc(href) + '" target="_blank" rel="noopener">Open</a>' : '') +
          (can ? '<button class="iconbtn" data-off="' + esc(l.id) + '" type="button" aria-label="Remove ' + esc(l.label) + '">' +
            '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg></button>' : '') +
        '</span>';
      table.appendChild(row);
    });
    box.appendChild(table);
    Array.prototype.forEach.call(box.querySelectorAll('[data-off]'), function (b) {
      b.addEventListener('click', function () { removeLink(b.getAttribute('data-off')); });
    });
  }

  /* Taking a link off is a soft remove with the way back drawn where the act
     happened, not at the top of the record: a safeguard nobody can see is not
     one. Removing a draft link shuts the Client review gate again, which is
     the reason it is worth undoing. */
  function removeLink(id) {
    var l = state.detail.links.filter(function (x) { return x.id === id; })[0];
    call('ops_set_link_archived', { p_link: id, p_on: true }, 'taskMsg', function (res) {
      if (res && res.task) applyTask(res.task);
      state.detail.links = state.detail.links.map(function (x) {
        return x.id === id ? Object.assign({}, x, { archived_at: new Date().toISOString() }) : x;
      });
      paintLinks();
      paintTask();
      undoBar((l ? l.label : 'The link') + ' removed.', function () {
        call('ops_set_link_archived', { p_link: id, p_on: false }, 'taskMsg', function () {
          readTask(state.task.id);
        });
      }, $('taskLinks'));
    });
  }

  function openLinkForm() {
    $('taskLinkForm').hidden = false;
    $('taskLinkUrl').value = '';
    $('taskLinkLabel').value = '';
    msg('taskLinkMsg', '');
    $('taskLinkUrl').focus();
  }

  // ---- Time ----------------------------------------------------------------
  function paintTime() {
    var box = $('taskTime');
    if (!box) return;
    var rows = state.detail.sessions;
    var mins = rows.reduce(function (a, s) { return a + (Number(s.minutes) || 0); }, 0);
    if (!rows.length) {
      UI.emptyLine(box, 'No recorded work.');
      return;
    }
    box.innerHTML = '';
    var table = GRP.table('svc-row tsess-row', ['Session', 'Who', 'Minutes']);
    rows.forEach(function (s) {
      var row = document.createElement('div');
      row.className = 'svc-row tsess-row';
      row.innerHTML =
        '<span class="svc-name"><b>' + esc(niceTime(s.started_at)) + '</b>' +
          '<small>' + esc(s.ended_at ? 'to ' + niceTime(s.ended_at) : 'running') +
          (s.corrected_at ? ' · corrected' : '') +
          (s.note ? ' · ' + s.note : '') + '</small></span>' +
        '<span class="tsess-who">' + esc((s.team_members && s.team_members.name) || '') + '</span>' +
        '<span class="tsess-mins">' + esc(s.minutes == null ? '—' : minutesWord(s.minutes)) + '</span>';
      table.appendChild(row);
    });
    var total = document.createElement('div');
    total.className = 'svc-row tsess-row is-total';
    total.innerHTML = '<span class="svc-name"><b>Total recorded</b></span>' +
      '<span class="tsess-who"></span><span class="tsess-mins">' + esc(minutesWord(mins)) + '</span>';
    table.appendChild(total);
    box.appendChild(table);
  }

  // ---- Activity ------------------------------------------------------------
  var EVENT_WORD = {
    task_created: 'Created', stage_changed: 'Stage moved', due_changed: 'Date moved',
    assignment_changed: 'Owner changed', contributor_changed: 'Contributors changed',
    reviewer_changed: 'Reviewer changed', blocked: 'Blocked', unblocked: 'Unblocked',
    work_started: 'Work started', work_stopped: 'Work stopped', work_corrected: 'Hours corrected',
    revision_requested: 'Revision requested', revision_completed: 'Revision done',
    review_decision: 'Review decided', file_added: 'Link added', file_removed: 'Link removed',
    file_restored: 'Link restored', checklist_changed: 'Checklist changed',
    video_changed: 'Video details changed', delivered: 'Delivered', completed: 'Completed',
    reopened: 'Reopened', cancelled: 'Cancelled', archived: 'Archived', restored: 'Restored',
    /* An extension is asked for, answered, or taken back; the date moving
       is still `due_changed`, so a report reads replanning the same way
       whether or not an approval was needed. */
    due_requested: 'Extension requested', due_approved: 'Extension approved',
    due_declined: 'Extension declined'
  };
  /* The reason a date moved is a stored key and the sheet offers a word for
     it; the record printed the key. Named once, with sentence case as the
     fallback so a category added next year is still a word. */
  var REASON_WORD = {
    client_request: 'Client request', scope_change: 'Scope change',
    capacity: 'Internal capacity', pending_assets: 'Pending assets',
    pending_confirmation: 'Pending confirmation', correction: 'Incorrect date listed'
  };
  function reasonWord(k) {
    if (!k) return '';
    if (REASON_WORD[k]) return REASON_WORD[k];
    var w = String(k).replace(/_/g, ' ');
    return w.charAt(0).toUpperCase() + w.slice(1);
  }

  function eventDetail(e) {
    var d = e.detail || {}, to = e.to_value || {}, from = e.from_value || {};
    /* An extension asked for, answered or taken back reads like the move it
       is about, so the two sit together in the log rather than in two
       vocabularies. */
    if (e.event_type === 'due_requested' || e.event_type === 'due_approved' ||
        e.event_type === 'due_declined') {
      return (to.kind === 'final' ? 'Final due' : 'First draft due') + ' ' +
        (from.value ? niceDate(from.value) + ' to ' : '') + niceDate(to.value) +
        (d.reason ? ' · ' + reasonWord(d.reason) : '');
    }
    if (e.event_type === 'stage_changed') {
      return (from.stage_key ? labelForKey(from.stage_key) + ' to ' : '') + labelForKey(to.stage_key);
    }
    if (e.event_type === 'due_changed') {
      return (to.kind === 'final' ? 'Final due' : 'First draft due') + ' ' +
        (from.value ? niceDate(from.value) + ' to ' : '') + niceDate(to.value) +
        (d.reason ? ' · ' + reasonWord(d.reason) : '');
    }
    if (e.event_type === 'work_stopped') return minutesWord(to.minutes);
    if (e.event_type === 'checklist_changed') return to.label + (to.done ? ' ticked' : ' cleared');
    if (e.event_type === 'blocked') return d.category ? String(d.category).replace(/_/g, ' ') : '';
    if (e.event_type === 'file_added' || e.event_type === 'file_removed' || e.event_type === 'file_restored') {
      return to.label || to.kind || '';
    }
    return d.note || reasonWord(d.reason) || '';
  }
  function labelForKey(k) {
    var t = state.task;
    var s = t && state.stages[t.workflow_id + '|' + k];
    return (s && s.label) || String(k || '').replace(/_/g, ' ');
  }

  function paintLog() {
    var box = $('taskLog');
    if (!box) return;
    var rows = state.detail.events;
    if (!rows.length) { UI.emptyLine(box, 'No activity.'); return; }
    box.innerHTML = '';
    var table = GRP.table('svc-row tact-row', ['When', 'Event', 'Who']);
    rows.forEach(function (e) {
      var row = document.createElement('div');
      row.className = 'svc-row tact-row';
      row.innerHTML =
        '<span class="tact-when">' + esc(niceTime(e.created_at)) + '</span>' +
        '<span class="svc-name"><b>' + esc(EVENT_WORD[e.event_type] || e.event_type.replace(/_/g, ' ')) + '</b>' +
          '<small>' + esc(eventDetail(e)) + '</small></span>' +
        '<span class="tact-who">' + esc(whoName(e)) + '</span>';
      table.appendChild(row);
    });
    box.appendChild(table);
  }
  function whoName(e) {
    var m = state.members.filter(function (x) { return x.id === e.actor_id; })[0];
    if (m) return m.name;
    return bridge.whoName ? bridge.whoName(e.actor_email) : (e.actor_email || '');
  }

  // ---- The rail ------------------------------------------------------------
  function paintRail(t) {
    paintStageBox(t);
    paintTimer(t);

    var dates = $('taskDates');
    /* Only a commitment can be overdue. A publish date that has passed is a
       fact about the client's calendar, not a failure of ours, and marking
       all three red made the one date anybody scans for indistinguishable
       from the two beside it. */
    /* A commitment that moved says where it moved from, because the original
       is written once so a report can see replanning, and the one place the
       dates are stated is where that has to be read. The three timestamps
       that end a task (draft in, delivered, completed) sit under them once
       they exist. */
    var rows = [
      ['First draft', t.current_first_draft_due_at, true, t.original_first_draft_due_at],
      ['Final', t.current_final_due_at, true, t.original_final_due_at],
      ['Publish', t.publish_at, false, null],
      ['Draft in', t.first_draft_submitted_at, false, null],
      ['Delivered', t.delivered_at, false, null],
      ['Completed', t.completed_at, false, null]
    ].filter(function (p) { return p[1]; });
    dates.innerHTML = rows.map(function (p) {
      var over = p[2] && !isFinished(t) && daysAway(p[1]) < 0;
      var moved = p[3] && p[3] !== p[1];
      return '<div class="raildate' + (moved ? ' has-from' : '') + '"><dt>' + esc(p[0]) + '</dt>' +
        '<dd' + (over ? ' class="is-over"' : '') + '>' + esc(niceDate(p[1])) +
        (moved ? '<small>moved from ' + esc(niceDate(p[3])) + '</small>' : '') + '</dd></div>';
    }).join('');
    $('taskDateEdit').hidden = !may('ops', 'work');
    paintDue(t);
    $('taskDatesBlock').hidden = !rows.length && !may('ops', 'work') && !state.due;

    /* The owner is on the identity line and in the select below; the rail
       names only the people the line does not. */
    var people = (t.assignees || []);
    $('taskPeople').innerHTML = [
      ['Reviewer', people.filter(function (a) { return a.responsibility === 'reviewer'; }).map(function (a) { return a.name; }).join(', ')],
      ['Contributors', people.filter(function (a) { return a.responsibility === 'contributor'; }).map(function (a) { return a.name; }).join(', ')]
    ].filter(function (p) { return p[1]; }).map(function (p) {
      return '<div><dt>' + esc(p[0]) + '</dt><dd>' + esc(p[1]) + '</dd></div>';
    }).join('');
    $('taskPeopleBlock').hidden = !$('taskPeople').innerHTML && !may('ops', 'manage');

    var sel = $('taskOwner');
    sel.innerHTML = '<option value="">Nobody</option>' + state.members.map(function (m) {
      return '<option value="' + esc(m.id) + '"' + (ownerId(t) === m.id ? ' selected' : '') + '>' + esc(m.name) + '</option>';
    }).join('');

    var wf = state.workflows.filter(function (w) { return w.id === t.workflow_id; })[0];
    $('taskFacts').innerHTML = [
      ['Workflow', (wf && wf.name) || ''],
      ['Deliverable', DELIVER_WORD[t.deliverable_type] || sentence(t.deliverable_type)],
      ['Languages', (t.language_codes || []).join(', ')],
      ['Priority', PRIORITY_WORD[String(t.priority_level)] || String(t.priority_level)],
      ['Complexity', COMPLEX_WORD[t.complexity] || sentence(t.complexity)],
      ['Added', niceDate(t.created_at)]
    ].filter(function (p) { return p[1]; }).map(function (p) {
      return '<div><dt>' + esc(p[0]) + '</dt><dd>' + esc(p[1]) + '</dd></div>';
    }).join('');

    /* The last three events, as the client record's rail excerpts its
       Activity pane: read once with the task, so the block costs nothing. */
    var recent = state.detail.events.slice(0, 3);
    var rb = $('taskRecentBlock');
    if (rb) {
      rb.hidden = !recent.length;
      $('taskRecent').innerHTML = '<ul class="raillog raillog-plain">' + recent.map(function (e) {
        var d = eventDetail(e);
        return '<li><span class="raillog-what">' + esc(EVENT_WORD[e.event_type] || e.event_type.replace(/_/g, ' ')) + '</span>' +
          (d ? '<span class="raillog-detail">' + esc(d) + '</span>' : '') +
          '<span class="raillog-when">' + esc(niceTime(e.created_at)) + (whoName(e) ? ' · ' + esc(whoName(e)) : '') + '</span></li>';
      }).join('') + '</ul>';
    }
  }

  /* One forward move drawn as the action, and every other move the workflow
     allows in the select beside it. Eight buttons in a rail is eight things
     to read before doing the one that matters, and this portal spends one
     blue action a view.
     Which move is forward is the workflow's own to say, never a list kept
     here: the next stage is the one nearest ahead of where the task stands
     by position. A hand-written preference put Ready in front of Internal
     review on a task already In progress, because Ready is earlier in the
     workflow and the list did not know where the task was. */
  /* The lanes beside the main line. A review stage is marked waiting because
     it waits on a reviewer, so "not waiting" is the wrong test for forward:
     it put Revision in front of Client review. What is beside the line is its
     own stage group, which is data the workflow already carries. */
  var SIDE = { blocked: 1, waiting: 1, kiv: 1, cancelled: 1 };
  function forwardOf(t, nexts) {
    var here = stageOf(t);
    var pos = here ? here.position : 0;
    var ahead = nexts.map(function (k) {
      return state.stages[t.workflow_id + '|' + k];
    }).filter(function (s) { return s && s.position > pos && !SIDE[s.stage_group]; })
      .sort(function (a, b) { return a.position - b.position; });
    return ahead.length ? ahead[0].key : nexts[0];
  }
  /* Where the task came from: the last stage change in its own events, which
     the record has already read. Nothing is stored for this, because a stored
     "previous stage" is a fact written once by the move that caused it and is
     wrong the moment somebody moves again. */
  function cameFrom(t) {
    var ev = (state.detail.events || []).filter(function (e) {
      return e.event_type === 'stage_changed' && e.from_value && e.from_value.stage_key;
    })[0];
    var k = ev && ev.from_value.stage_key;
    return k && k !== t.stage_key ? k : null;
  }
  /* WHOSE DATE IT IS.
     A commitment is the promise the person who created the task made, so
     moving it is theirs to allow: the control is named for what pressing it
     will actually do, and while an ask is open the rail says so with the one
     action the reader has. Nobody is shown a button that is not theirs. */
  function whoDecides(t) { return (t && t.created_by) || null; }
  function myId() { var m = bridge.me && bridge.me(); return (m && m.id) || null; }
  function needsAsking(t) {
    var d = whoDecides(t);
    return Boolean(d && myId() && d !== myId());
  }

  function paintDue(t) {
    /* The first draft date is the team's own milestone, set against a schedule
       that is already agreed, so it is theirs to adjust and goes through no
       round. Named for whether there is one yet. */
    var dd = $('taskDraftDate');
    if (dd) dd.textContent = t.current_first_draft_due_at ? 'Change draft date' : 'Set draft date';
    var mv = $('taskDateMove');
    if (mv) {
      /* The final date is the commitment a client is owed. The control is
         named for what pressing it will do: a person who created the task
         moves it, everybody else is asking the person who set it. */
      mv.textContent = needsAsking(t) ? 'Request extension' : 'Change due date';
      mv.hidden = Boolean(state.due);
    }
    var box = $('dueAsk');
    if (!box) return;
    msg('dueAskMsg', state.said || '', state.said ? 'ok' : '');
    state.said = '';
    var q = state.due;
    if (!q) { box.hidden = true; box.innerHTML = ''; return; }
    var mine = myId() && q.asked_by === myId();
    var yours = myId() && q.decider_id === myId();
    var who = nameOf(q.asked_by) || 'Somebody';
    var to = nameOf(q.decider_id) || 'the task owner';
    box.hidden = false;
    box.innerHTML =
      '<p class="dueask-line">' +
        esc((q.kind === 'final' ? 'Due date' : 'First draft date') + ' to ' + niceDate(q.wants_at)) +
        '<small>' + esc(mine ? 'Waiting on ' + to : who + ' asked') +
        (q.note ? ' · ' + esc(q.note) : '') + '</small></p>' +
      '<div class="dueask-acts">' +
        (yours
          ? '<button class="btn btn-sm btn-go" data-due="yes" type="button">Approve</button>' +
            '<button class="btn btn-sm" data-due="no" type="button">Decline</button>'
          : mine
            ? '<button class="btn btn-sm" data-due="withdraw" type="button">Withdraw</button>'
            : '') +
      '</div>';
  }

  function nameOf(id) {
    if (!id) return '';
    var m = (state.members || []).filter(function (x) { return x.id === id; })[0];
    return (m && m.name) || '';
  }

  function paintStageBox(t) {
    var box = $('taskStageBox');
    var s = stageOf(t);
    var nexts = (s && s.next_stage_keys) || [];
    var can = may('ops', 'work');

    if (!nexts.length) {
      box.innerHTML = '<p class="mute">' + esc(stageLabel(t)) + ' is where this ends.</p>';
      return;
    }
    var first = forwardOf(t, nexts);
    /* Revert undoes a state, and this portal's rule is that every forward move
       has one. Which stage to go back to is not a guess: it is the one the
       task came from, read off the last stage change in its own events, and it
       is offered only where the workflow still allows that move — so a revert
       goes through the same function and the same gates as everything else. */
    var back = cameFrom(t);
    if (back && nexts.indexOf(back) < 0) back = null;
    var rest = nexts.filter(function (k) { return k !== first && k !== back; });
    /* The head already carries the stage as its chip, so the rail does not say
       it again; and the move is a button at its own width, never a slab across
       the rail: full width it was the loudest thing on the page, louder than
       the overdue line above it, and on a phone it was the banner this
       portal's section heads have refused for months. */
    box.innerHTML =
      (can ? '<div class="railmoves">' +
               '<button class="btn btn-go railmove" data-go="' + esc(first) + '" type="button">Move to ' + esc(labelForKey(first)) + '</button>' +
               (back ? '<button class="btn btn-sm railback" data-back="' + esc(back) + '" type="button">Revert to ' + esc(labelForKey(back)) + '</button>' : '') +
             '</div>'
           : '<p class="mute">' + esc(stageLabel(t)) + '</p>') +
      (can && rest.length
        ? '<div class="railother"><label class="field-label" for="taskOther">Or move to</label>' +
          '<select class="select select-sm" id="taskOther">' +
            '<option value="">Choose a stage</option>' +
            rest.map(function (k) { return '<option value="' + esc(k) + '">' + esc(labelForKey(k)) + '</option>'; }).join('') +
          '</select></div>'
        : '');

    var go = box.querySelector('[data-go]');
    if (go) go.addEventListener('click', function () { move(first); });
    var rv = box.querySelector('[data-back]');
    if (rv) rv.addEventListener('click', function () { move(back); });
    var other = box.querySelector('#taskOther');
    if (other) other.addEventListener('change', function () {
      if (!other.value) return;
      var want = other.value;
      other.value = '';
      move(want);
    });
  }

  function move(next) {
    var t = state.task;
    if (!t) return;
    if (next === 'blocked') { openBlock(); return; }
    var fn = t.stage_key === 'blocked' ? 'ops_clear_blocked' : 'ops_transition_task';
    var args = t.stage_key === 'blocked'
      ? { p_task: t.id, p_next: next, p_version: t.version }
      : { p_task: t.id, p_next: next, p_version: t.version, p_note: null };
    call(fn, args, 'taskMsg', function () { readTask(t.id); });
  }

  /* The timer is one press and the page says which task it is running on,
     because one open session a person across every task means starting here
     stops it somewhere else. */
  function paintTimer(t) {
    var box = $('taskTimer');
    if (!box) return;
    var mine = state.session;
    var here = mine && mine.task_id === t.id;
    var other = mine && !here
      ? (state.tasks || []).filter(function (x) { return x.id === mine.task_id; })[0]
      : null;
    var run = here ? Math.round((Date.now() - new Date(mine.started_at)) / 60000) : 0;

    box.innerHTML =
      (here
        ? '<p class="railnow"><b class="timer-run">' + esc(minutesWord(run)) + '</b> on this task</p>' +
          '<button class="btn btn-warn" data-a="stop" type="button">Stop</button>'
        : '<button class="btn" data-a="start" type="button">Start work</button>' +
          (other ? '<p class="hint">Running on ' + esc(other.title) + '. Starting here stops that one.</p>' : '')) ;

    var st = box.querySelector('[data-a="start"]');
    if (st) st.addEventListener('click', function () {
      call('ops_start_work', { p_task: t.id }, 'taskMsg', function () {
        loadSession(function () { paintTimer(t); startTick(); });
      });
    });
    var sp = box.querySelector('[data-a="stop"]');
    if (sp) sp.addEventListener('click', function () {
      call('ops_stop_work', { p_session: mine.id, p_note: null }, 'taskMsg', function () {
        stopTick();
        readTask(t.id);
      });
    });
    here ? startTick() : stopTick();
  }
  /* A minute, not a second: the number is how long somebody has been at this,
     and a second hand on a page somebody is working in is a distraction with
     no answer in it. */
  function startTick() {
    if (state.tick) return;
    state.tick = setInterval(function () {
      if (!state.task || !state.session) { stopTick(); return; }
      paintTimer(state.task);
    }, 60000);
  }
  function stopTick() {
    if (!state.tick) return;
    clearInterval(state.tick);
    state.tick = null;
  }

  /* Reopening needs a reason somebody else will read, so it is the textarea
     `js/ask.js` draws under the control that sends it rather than a browser
     dialog, which this portal does not have. It is built once and reopened,
     because the ⋯ it is launched from closes itself. */
  var reopen = null;
  function reopenBox() {
    if (reopen) return reopen;
    reopen = window.ADspaceAsk.note($('taskMsg'), {
      label: 'Why it is being reopened',
      placeholder: 'Why it is being reopened',
      send: 'Reopen',
      save: function (text) {
        var t = state.task;
        if (!t) return;
        call('ops_reopen_task', { p_task: t.id, p_reason: text, p_version: t.version },
          'taskMsg', function () { readTask(t.id); });
      }
    });
    return reopen;
  }

  // ---- The way back, drawn where the act happened --------------------------
  function undoBar(text, undo, host) {
    if (!host || !host.parentNode) return;
    /* One bar at a time: two removals in a row would otherwise stack two
       offers of a way back and neither would say which. */
    var old = host.parentNode.querySelector(':scope > .undobar-here');
    if (old) old.remove();
    var bar = document.createElement('div');
    bar.className = 'undobar undobar-here';
    bar.innerHTML = '<span></span><button class="btn btn-sm" type="button">Undo</button>';
    bar.querySelector('span').textContent = text;
    var timer = setTimeout(function () { bar.remove(); }, 8000);
    bar.querySelector('button').addEventListener('click', function () {
      clearTimeout(timer);
      bar.remove();
      undo();
    });
    host.parentNode.insertBefore(bar, host.nextSibling);
  }

  // ---- Calling the database ------------------------------------------------
  /* Every write goes through one place, so a refusal is named the same way
     whichever control asked for it, and a stale write — the one a page cannot
     see coming — repaints from the row the database handed back rather than
     leaving the screen claiming something that is no longer true. */
  function call(fn, args, msgId, then, onFail) {
    db.rpc(fn, args).then(function (r) {
      if (r.error) {
        msg(msgId, r.error.message, 'err');
        if (onFail) onFail();
        return;
      }
      var d = r.data;
      if (d && d.error) {
        msg(msgId, said(d.error), 'err');
        if (d.error === 'stale' && d.task) { applyTask(d.task); paintTask(); }
        if (onFail) onFail();
        return;
      }
      msg(msgId, '');
      if (then) then(d);
    }, function (e) {
      msg(msgId, (e && e.message) || String(e), 'err');
      if (onFail) onFail();
    });
  }

  // ---- Sheets --------------------------------------------------------------
  /* What goes with it, counted from the record already on the screen, so the
     sheet states the consequence before it asks rather than after. */
  function openDelete() {
    var t = state.task;
    if (!t) return;
    var goes = [
      state.detail.events.length + (state.detail.events.length === 1 ? ' event' : ' events'),
      state.detail.sessions.length ? state.detail.sessions.length +
        (state.detail.sessions.length === 1 ? ' time session' : ' time sessions') : '',
      state.detail.links.length ? state.detail.links.length +
        (state.detail.links.length === 1 ? ' link' : ' links') : '',
      state.detail.checklist.length ? state.detail.checklist.length + ' checklist items' : ''
    ].filter(Boolean);
    $('tdelWhat').textContent = 'T' + t.task_no + ' · ' + (t.title || 'Untitled task') +
      ' goes, with its ' + goes.join(', ') + '. There is no restore.';
    $('tdelConfirm').value = '';
    $('tdelReason').value = '';
    $('tdelConfirm').setAttribute('placeholder', 'T' + t.task_no);
    msg('tdelMsg', '');
    sheet('tdelSheet', true);
    $('tdelConfirm').focus();
  }

  var dueKind = 'final';
  function openDue(kind) {
    var t = state.task;
    if (!t) return;
    dueKind = kind || 'final';
    var draft = dueKind === 'first_draft';
    var was = draft ? t.current_first_draft_due_at : t.current_final_due_at;
    /* Each date says what it is and what governs it. The commitment keeps the
       original-promise line, because that is the fact a replan report reads;
       the team's own milestone says instead where its ceiling is, which is
       the only thing that can refuse it. */
    $('dueWhat').textContent = (draft ? 'First draft due date' : 'Final due date') +
      (was ? ', now ' + niceDate(was) + '.' : ', not set.') +
      (draft
        ? (t.current_final_due_at
            ? ' The latest it may fall is one day before the final due date, ' +
              niceDate(t.current_final_due_at) + '.'
            : '')
        : ' The promise first made is kept either way.');
    /* Error prevention rather than an error message: the picker will not open
       past the day before the commitment. The database refuses it as well,
       because a ceiling only the page knows is not a rule. */
    /* The sheet is titled for the act, the way the control that opened it is
       named: setting the team's own milestone, or asking for the client's
       commitment to move. */
    $('dueTitle').textContent = draft
      ? (was ? 'Change draft date' : 'Set draft date')
      : (needsAsking(t) ? 'Request extension' : 'Change due date');
    var cap = draft && t.current_final_due_at ? dayBefore(t.current_final_due_at) : '';
    if (cap) $('dueDate').setAttribute('max', cap); else $('dueDate').removeAttribute('max');
    $('dueDate').value = dateValue(was);
    $('dueNote').value = '';
    msg('dueMsg', '');
    sheet('dueSheet', true);
  }
  function openBlock() {
    $('blockNote').value = '';
    msg('blockMsg', '');
    sheet('blockSheet', true);
  }
  function sheet(id, on) {
    var el = $(id);
    if (!el) return;
    el.hidden = !on;
    document.body.classList.toggle('sheet-open', !!on);
    if (on) {
      var f = el.querySelector('input, select, textarea, button');
      if (f) f.focus();
    }
  }

  // ---- New task ------------------------------------------------------------
  function openNew() {
    if (!may('ops', 'work')) return;
    var cl = $('ntClient');
    cl.innerHTML = '<option value="">Choose a client</option>' + state.clients.map(function (c) {
      return '<option value="' + esc(c.id) + '">' + esc(c.name) + '</option>';
    }).join('');
    var tp = $('ntTemplate');
    tp.innerHTML = '<option value="">No template</option>' + state.templates.map(function (x) {
      return '<option value="' + esc(x.id) + '">' + esc(x.name) + '</option>';
    }).join('');
    var ow = $('ntOwner');
    var me = bridge.me && bridge.me();
    ow.innerHTML = '<option value="">Nobody yet</option>' + state.members.map(function (m) {
      return '<option value="' + esc(m.id) + '"' + (me && me.id === m.id ? ' selected' : '') + '>' + esc(m.name) + '</option>';
    }).join('');
    $('ntTitle').value = '';
    $('ntDesc').value = '';
    $('ntPublish').value = '';
    $('ntFinal').value = '';
    $('ntScope').value = 'client';
    $('ntPriority').value = '3';
    $('ntComplex').value = '';
    ntScopeChanged();
    ntHint();
    msg('ntMsg', '');
    sheet('taskSheet', true);
  }
  function ntScopeChanged() {
    $('ntClientField').hidden = $('ntScope').value !== 'client';
  }
  function ntHint() {
    var tpl = state.templates.filter(function (x) { return x.id === $('ntTemplate').value; })[0];
    var line = $('ntHint');
    if (!tpl) { line.textContent = ''; line.hidden = true; return; }
    var bits = [];
    if (tpl.first_draft_offset_business_days) bits.push('first draft ' + tpl.first_draft_offset_business_days + ' working days before publishing');
    if (tpl.final_offset_business_days) bits.push('final ' + tpl.final_offset_business_days + ' working days before');
    line.textContent = bits.length
      ? 'With a publish date, this template dates the work back from it: ' + bits.join(', ') + '.'
      : '';
    line.hidden = !line.textContent;
  }
  /* The same press twice is one task. The key is what makes the two presses
     the same act, so it is built from what was typed and not from a counter. */
  var ntKey = '';
  function createTask() {
    var scope = $('ntScope').value;
    var title = String($('ntTitle').value || '').trim();
    if (!title) { msg('ntMsg', 'A title is required.', 'err'); $('ntTitle').focus(); return; }
    if (scope === 'client' && !$('ntClient').value) {
      msg('ntMsg', 'A client is required.', 'err'); $('ntClient').focus(); return;
    }
    var payload = {
      scope: scope,
      client_id: scope === 'client' ? $('ntClient').value : null,
      template_id: $('ntTemplate').value || null,
      owner_id: $('ntOwner').value || null,
      title: title,
      description: String($('ntDesc').value || '').trim() || null,
      priority_level: Number($('ntPriority').value) || 3,
      complexity: $('ntComplex').value || null,
      publish_at: $('ntPublish').value ? $('ntPublish').value + 'T00:00:00Z' : null,
      final_due_at: $('ntFinal').value ? $('ntFinal').value + 'T00:00:00Z' : null
    };
    if (!ntKey) ntKey = 'nt-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8);
    var btn = $('ntGo');
    btn.disabled = true;
    call('ops_create_task', { p_payload: payload, p_idem: ntKey }, 'ntMsg', function (t) {
      btn.disabled = false;
      ntKey = '';
      sheet('taskSheet', false);
      openTask(t.id, true);
    }, function () { btn.disabled = false; });
  }

  // ---- Wiring --------------------------------------------------------------
  function wire() {
    var find = $('workFind');
    if (find) {
      /* One control, one listener: `input` and `change` both fire for a
         keystroke and the second arrives on blur, which is how a Clear button
         once detached itself between mousedown and click. */
      find.addEventListener('input', function () {
        var v = String(find.value || '').trim().toLowerCase();
        if (v === state.find) return;
        state.find = v;
        paint();
      });
    }
    var st = $('workStage');
    if (st) st.addEventListener('change', function () {
      state.filter = st.value;
      /* The period governs finished work and nothing else, so it appears
         exactly when finished work is being asked for. A control that is on
         the screen while it decides nothing is a control somebody has to
         work out. Changing the filter into finished work needs the read
         again, because finished work was bounded by the period all along. */
      var was = showPeriod();
      if (was) load(); else paint();
    });
    var gp = $('workGroup');
    if (gp) gp.addEventListener('change', function () { state.group = gp.value; paint(); });
    var pd = $('workPeriod');
    if (pd) pd.addEventListener('change', function () { state.period = pd.value; load(); });
    var sc = $('workScope');
    if (sc) sc.addEventListener('change', function () { state.scope = sc.value; paint(); });
    var vw = $('workViews');
    if (vw) vw.addEventListener('click', function (e) {
      var b = e.target.closest('.acttab');
      if (b) setView(b.getAttribute('data-view'));
    });
    var wfs = $('workWf');
    if (wfs) wfs.addEventListener('change', function () { state.wf = wfs.value; paint(); });
    wireBell();
    var nw = $('workNew');
    if (nw) nw.addEventListener('click', openNew);
    var back = $('workBack');
    if (back) back.addEventListener('click', showList);
    var mk = $('taskMark');
    if (mk) mk.addEventListener('click', function () {
      if (window.ADspaceCopy) window.ADspaceCopy.to(mk, mk.textContent);
    });

    // Panes
    var tabs = $('taskTabs');
    if (tabs) tabs.addEventListener('click', function (e) {
      var tab = e.target.closest('.tab');
      if (!tab) return;
      showPane(tab.getAttribute('data-pane'), true);
    });

    // The record's ⋯
    var mb = $('taskMenuBtn'), menu = $('taskMenu');
    if (mb && menu) {
      mb.addEventListener('click', function (e) {
        e.stopPropagation();
        var open = menu.hidden;
        menu.hidden = !open;
        mb.setAttribute('aria-expanded', String(open));
        if (open) window.ADspaceMenu.place(mb, menu);
      });
      window.ADspaceMenu.onScroll(function () { menu.hidden = true; mb.setAttribute('aria-expanded', 'false'); });
      document.addEventListener('click', function (e) {
        if (!e.target.closest || !e.target.closest('#taskMenuWrap')) {
          menu.hidden = true;
          mb.setAttribute('aria-expanded', 'false');
        }
      });
      menu.addEventListener('click', function (e) {
        var it = e.target.closest('.kmenu-item');
        if (!it) return;
        menu.hidden = true;
        mb.setAttribute('aria-expanded', 'false');
        var a = it.getAttribute('data-a'), t = state.task;
        if (!t) return;
        if (a === 'block') openBlock();
        if (a === 'archive') {
          call('ops_archive_task', { p_task: t.id, p_on: !t.archived_at }, 'taskMsg', function () {
            showList();
          });
        }
        if (a === 'reopen') reopenBox().open();
        if (a === 'delete') openDelete();
      });
    }

    // Deleting the task keyed in twice
    ['tdelClose', 'tdelCancel'].forEach(function (id) {
      var b = $(id); if (b) b.addEventListener('click', function () { sheet('tdelSheet', false); });
    });
    var tdg = $('tdelGo');
    if (tdg) tdg.addEventListener('click', function () {
      var t = state.task;
      if (!t) return;
      call('ops_delete_task', {
        p_task: t.id,
        p_confirm: String($('tdelConfirm').value || '').trim().toUpperCase(),
        p_reason: String($('tdelReason').value || '').trim() || null
      }, 'tdelMsg', function () {
        sheet('tdelSheet', false);
        /* The record is gone, so there is nothing to repaint it from: back to
           the queue, which re-reads. */
        showList();
        load();
      });
    });

    // Links
    var la = $('taskLinkAdd');
    if (la) la.addEventListener('click', openLinkForm);
    var lc = $('taskLinkCancel');
    if (lc) lc.addEventListener('click', function () { $('taskLinkForm').hidden = true; });
    var ls = $('taskLinkSave');
    if (ls) ls.addEventListener('click', function () {
      var t = state.task;
      if (!t) return;
      var url = String($('taskLinkUrl').value || '').trim();
      if (!url) { msg('taskLinkMsg', 'An address is required.', 'err'); $('taskLinkUrl').focus(); return; }
      call('ops_add_link', {
        p_task: t.id, p_kind: $('taskLinkKind').value,
        p_label: String($('taskLinkLabel').value || '').trim(),
        p_url: url, p_version: t.version
      }, 'taskLinkMsg', function () {
        $('taskLinkForm').hidden = true;
        readTask(t.id);
      });
    });

    // Owner
    var os = $('taskOwnerSave');
    if (os) os.addEventListener('click', function () {
      var t = state.task;
      if (!t) return;
      var sel = $('taskOwner');
      var pick = sel.value || null;
      if (pick === ownerId(t)) { msg('taskOwnerMsg', 'No change.', ''); return; }
      /* The select already shows the new name before anything is saved, so a
         refused save left the screen claiming a change the database had not
         made, and a successful one changed nothing near the control: the line
         that says Saved is here, and a refusal puts the select back. */
      call('ops_assign_task', { p_task: t.id, p_owner: pick, p_version: t.version },
        'taskOwnerMsg', function (d) {
          applyTask(d);
          var m = state.members.filter(function (x) { return x.id === pick; })[0];
          state.owners[t.id] = (m && m.name) || '';
          state.ownerIds[t.id] = pick;
          readTask(t.id, function () { msg('taskOwnerMsg', 'Saved.', 'ok'); });
        }, function () { sel.value = ownerId(t) || ''; });
    });

    var dm = $('taskDateMove');
    if (dm) dm.addEventListener('click', function () { openDue('final'); });
    var dd2 = $('taskDraftDate');
    if (dd2) dd2.addEventListener('click', function () { openDue('first_draft'); });
    /* Approve, decline or take back an open extension, where the rail drew
       one. The buttons are painted by paintDue and wired here once. */
    var da = $('dueAsk');
    if (da) da.addEventListener('click', function (e) {
      var b = e.target.closest('[data-due]');
      if (!b || !state.task || !state.due) return;
      var act = b.getAttribute('data-due');
      var fn = act === 'withdraw' ? 'ops_withdraw_due_change' : 'ops_decide_due_change';
      var args = act === 'withdraw'
        ? { p_request: state.due.id }
        : { p_request: state.due.id, p_approve: act === 'yes', p_note: null };
      call(fn, args, 'dueAskMsg', function () { readTask(state.task.id); });
    });

    // Sheets
    ['dueClose', 'dueCancel'].forEach(function (id) {
      var b = $(id); if (b) b.addEventListener('click', function () { sheet('dueSheet', false); });
    });
    var dg = $('dueGo');
    if (dg) dg.addEventListener('click', function () {
      var t = state.task;
      if (!t) return;
      if (!$('dueDate').value) { msg('dueMsg', 'A date is required.', 'err'); return; }
      /* One call, and the database decides whether this is a move or an ask:
         a person moving a date on a task they created themselves needs
         nobody, and everybody else is asking the person who set it. Deciding
         that here would put the rule in two places. */
      call('ops_request_due_change', {
        p_task: t.id, p_kind: dueKind === 'final' ? 'final' : 'first_draft',
        p_value: $('dueDate').value + 'T00:00:00Z',
        p_reason: $('dueReason').value,
        p_note: String($('dueNote').value || '').trim() || null,
        p_version: t.version
      }, 'dueMsg', function (out) {
        sheet('dueSheet', false);
        state.said = out && out.asked
          ? (out.repeat ? 'That extension is already with them.' : 'Extension requested.')
          : '';
        readTask(t.id);
      });
    });

    ['blockClose', 'blockCancel'].forEach(function (id) {
      var b = $(id); if (b) b.addEventListener('click', function () { sheet('blockSheet', false); });
    });
    var bg = $('blockGo');
    if (bg) bg.addEventListener('click', function () {
      var t = state.task;
      if (!t) return;
      call('ops_set_blocked', {
        p_task: t.id, p_category: $('blockCat').value,
        p_note: String($('blockNote').value || '').trim() || null,
        p_version: t.version
      }, 'blockMsg', function () { sheet('blockSheet', false); readTask(t.id); });
    });

    ['taskSheetClose', 'ntCancel'].forEach(function (id) {
      var b = $(id); if (b) b.addEventListener('click', function () { sheet('taskSheet', false); });
    });
    var ns = $('ntScope');
    if (ns) ns.addEventListener('change', ntScopeChanged);
    var nt = $('ntTemplate');
    if (nt) nt.addEventListener('change', ntHint);
    var ng = $('ntGo');
    if (ng) ng.addEventListener('click', createTask);

    document.addEventListener('keydown', function (e) {
      if (e.key !== 'Escape') return;
      ['dueSheet', 'blockSheet', 'taskSheet'].forEach(function (id) {
        if ($(id) && !$(id).hidden) sheet(id, false);
      });
    });
  }

  function showPane(name, push) {
    state.pane = name || 'overview';
    Array.prototype.forEach.call($('taskTabs').querySelectorAll('.tab'), function (b) {
      var on = b.getAttribute('data-pane') === state.pane;
      b.classList.toggle('is-on', on);
      b.setAttribute('aria-selected', String(on));
    });
    Array.prototype.forEach.call($('workRec').querySelectorAll('.rec-pane'), function (p) {
      p.hidden = p.getAttribute('data-pane') !== state.pane;
    });
    if (push && bridge.pushUrl) bridge.pushUrl();
    if (UI.fit) UI.fit();
  }

  // ---- The address ---------------------------------------------------------
  function urlState() {
    var q = {};
    if (state.openId) q.task = state.openId;
    if (state.openId && state.pane !== 'overview') q.pane = state.pane;
    if (!state.openId && state.view !== 'list') q.view = state.view;
    return q;
  }

  /* Finished work is the only thing the period bounds, so the select draws
     only while finished work can be on the page. Returns whether it is now
     showing, so a caller knows whether the read has to run again. */
  function showPeriod() {
    var pd = $('workPeriod');
    var on = state.filter === 'done' || state.filter === '';
    if (pd) pd.hidden = !on;
    return on;
  }

  function enter() {
    var nw = $('workNew');
    if (nw) nw.hidden = !may('ops', 'work');
    var sc = $('workScope');
    /* The select is offered only where the whole team's queue can arrive.
       Hiding it changes nothing the database does; showing it where it cannot
       work would offer a view that comes back empty and say nothing. */
    if (sc) sc.hidden = !may('ops.all', 'view');
    if (sc && sc.hidden) state.scope = 'mine';
    showPeriod();

    var params = new URLSearchParams(location.search);
    var want = params.get('task');
    var pane = params.get('pane') || 'overview';
    applyView(params.get('view') || 'list');
    load();
    if (!want) { $('workList').hidden = false; $('workRec').hidden = true; if (bridge.setUrl) bridge.setUrl(); return; }
    loadCatalogue(function () {
      showPane(pane, false);
      openTask(want, false);
    });
  }

  // ---- The bell --------------------------------------------------------------
  /* A change somebody else made to a task you own, written by the database
     beside the event that caused it. Drawn on every route for anybody who can
     read My Work; the count is the unread rows and nothing else. Pressing one
     opens the task and marks the row read, which is the one write a browser
     makes to this table directly. */
  function signedIn() {
    var wrap = $('notifWrap');
    if (!wrap) return;
    wrap.hidden = !may('ops', 'view');
    if (!wrap.hidden) loadNotifs();
  }
  function loadNotifs() {
    var me = bridge.me && bridge.me();
    if (!me || !me.id) return;
    db.from('ops_notifications').select('*').eq('team_member_id', me.id)
      .is('read_at', null).order('created_at', { ascending: false }).limit(30)
      .then(function (r) {
        state.notifs = (r && !r.error && r.data) || [];
        paintNotifs();
      }, function () {});
  }
  function paintNotifs() {
    var n = state.notifs.length, count = $('notifCount'), list = $('notifList');
    if (count) { count.hidden = !n; count.textContent = n > 30 ? '30+' : String(n); }
    var btn = $('notifBtn');
    if (btn) btn.setAttribute('aria-label', n ? 'Notifications, ' + n + ' unread' : 'Notifications');
    if ($('notifAll')) $('notifAll').hidden = !n;
    if (!list) return;
    list.innerHTML = n ? state.notifs.map(function (x) {
      return '<button class="notif-item" type="button" data-id="' + esc(x.id) + '">' +
        '<b>' + esc(x.title || '') + '</b>' +
        (x.body ? '<span>' + esc(x.body) + '</span>' : '') +
        '<small>' + esc(niceTime(x.created_at)) + '</small></button>';
    }).join('') : '<p class="notif-empty">Nothing unread.</p>';
    Array.prototype.forEach.call(list.querySelectorAll('.notif-item'), function (b) {
      b.addEventListener('click', function () { openNotif(b.getAttribute('data-id')); });
    });
  }
  function markRead(ids) {
    var now = new Date().toISOString();
    state.notifs = state.notifs.filter(function (x) { return ids.indexOf(x.id) < 0; });
    paintNotifs();
    ids.forEach(function (id) {
      db.from('ops_notifications').update({ read_at: now }).eq('id', id).then(function () {}, function () {});
    });
  }
  function openNotif(id) {
    var x = state.notifs.filter(function (n) { return n.id === id; })[0];
    if (!x) return;
    shutBell();
    markRead([id]);
    if (!x.task_id) return;
    /* The address first, because My Work reads it on entry. */
    history.replaceState(null, '', '/admin/?s=work&task=' + encodeURIComponent(x.task_id));
    if (bridge.show) bridge.show('work');
  }
  function shutBell() {
    var menu = $('notifMenu'), btn = $('notifBtn');
    if (menu) menu.hidden = true;
    if (btn) btn.setAttribute('aria-expanded', 'false');
  }
  function wireBell() {
    var btn = $('notifBtn'), menu = $('notifMenu');
    if (!btn || !menu) return;
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      var open = menu.hidden;
      if (open) loadNotifs();
      menu.hidden = !open;
      btn.setAttribute('aria-expanded', String(open));
      if (open) { var first = menu.querySelector('.notif-item, #notifAll'); if (first) first.focus(); }
    });
    document.addEventListener('click', function (e) {
      if (!menu.hidden && !e.target.closest('#notifWrap')) shutBell();
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && !menu.hidden) { shutBell(); btn.focus(); }
    });
    var all = $('notifAll');
    if (all) all.addEventListener('click', function () {
      markRead(state.notifs.map(function (x) { return x.id; }));
    });
  }

  wire();
  showPane('overview', false);
  window.ADspaceOps = {
    enter: enter, urlState: urlState, signedIn: signedIn,
    /* Which task is open, and a re-read of it. The record is otherwise only
       reachable through a press, so a change made to the row underneath it
       has no way to reach the screen. */
    openId: function () { return (state.task && state.task.id) || null; },
    reload: function () { if (state.task) readTask(state.task.id); }
  };
  if (bridge.opsReady) bridge.opsReady();
  if (bridge.me && bridge.me()) signedIn();
})();
