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
  function plusDays(v, n) {
    var d = dayOf(v);
    if (!d) return null;
    d = new Date(d.getTime());
    d.setDate(d.getDate() + n);
    return d.toISOString();
  }
  /* THE NUMBER A TASK IS QUOTED BY. `#WT` and five figures, the same words
     `ops_serial` gives the database, so a number read off the screen is the
     number the activity record and a search both know. */
  function serialOf(t) {
    return t && t.task_no != null ? '#WT' + String(t.task_no).padStart(5, '0') : '';
  }
  function isAdmin() {
    var m = bridge.me && bridge.me();
    return Boolean(m && (m.is_admin || m.role === 'admin'));
  }

  // ---- What the database said, in the team's words -------------------------
  /* Every one of these is a refusal a person can act on, so it is said in the
     words of the thing they were trying to do. A page that prints
     `ready-needs-owner-and-due` has made the database's vocabulary the
     reader's problem. */
  var SAID = {
    'not-team': 'Team record not found. Contact an admin.',
    'denied': 'You do not have access to do that.',
    'not-found': 'That task is no longer there.',
    'stale': 'Updated by someone else. Reloaded.',
    'not-yours': 'Not yours to decide.',
    'decided': 'Already decided.',
    'no-date': 'A date is required.',
    /* The team's own milestone has to land before the commitment it feeds,
       and the latest it may fall is the day before. Named here rather than
       left as the database's own word, like every other refusal. */
    'draft-not-before-final': 'Draft due must be before the final due date.',
    'bad-transition': 'Move not allowed from this stage.',
    'no-such-stage': 'Stage not in this workflow.',
    'ready-needs-owner-and-due': 'Ready needs an owner and a final due date.',
    'footage-not-ready': 'Footage not ready for editing.',
    'needs-draft': 'Add the draft link, or say how it was sent.',
    'needs-final-link': 'Delivered needs a final link.',
    'needs-delivery-or-reason': 'Add a delivery or a closing reason.',
    'checklist-incomplete': 'Required checklist items are open.',
    'reason-required': 'A reason is required.',
    'category-required': 'Select what it is waiting on.',
    'title-required': 'A description is required.',
    'client-required': 'A client is required.',
    'client-not-active': 'Client not active. Choose an active client or Lead.',
    'not-a-lead': 'Already a client. Choose Client.',
    'bad-scope': 'Choose Client, Lead or Internal.',
    'bad-task-type': 'Choose a task type.',
    'bad-period': 'Invalid content month.',
    'bad-week': 'Week must be 1 to 5.',
    'skip-reason-required': 'Skipping a step needs a reason.',
    'planning-incomplete': 'Planning not complete for this month.',
    'meeting-required': 'Content meeting not held or marked N/A.',
    'needs-final-or-reason': 'Add a final link or a note.',
    'no-such-person': 'Not a team member.',
    'bad-count': 'Task count must be 1 to 60.',
    'bad-weeks': 'Enter up to five weekly figures.',
    'weeks-do-not-add-up': 'Weekly figures must match the total.',
    'already-generated': 'Already generated from this sheet.',
    'bad-frequency': 'Choose weekly, monthly or every N days.',
    'interval-required': 'Enter the number of days.',
    'bad-state': 'Invalid status.',
    'no-such-check': 'Check not found.',
    'meeting-in-past': 'Meeting date must be today or later.',
    'bad-minutes': 'A meeting runs 15 minutes to 4 hours.',
    'bad-meeting-link': 'Paste a Google Meet, Zoom or Teams link.',
    'bad-channel': 'Choose where the meeting is held.',
    'checklist-open': 'Tick both checklists, or mark one not needed, first.',
    'workflow-required': 'No workflow set up. Contact an admin.',
    'bad-kind': 'Invalid link type.',
    'url-required': 'A link is required.',
    'ends-before-it-starts': 'End date is before the start.',
    'not-blocked': 'This task is not blocked.',
    'confirm-required': 'Type the task number as shown.',
    'needs-aqc': 'AQC review comes before client review.',
    'note-required': 'A note is required for this step.',
    'needs-schedule': 'Set the publish date first.',
    'needs-live-date': 'Confirm the date it went live.',
    'live-in-future': 'A post cannot go live after today.',
    'live-reason-required': 'Say why it went live on a different date.',
    'not-finished': 'Only a finished task can be rated.',
    'bad-rating': 'Choose one to five.',
    'none-selected': 'No tasks selected.',
    'too-many': 'Select up to 500 tasks at a time.',
    'number-taken': 'That number is already used.',
    'bad-number': 'Enter a number from 1.'
  };
  /* The database refuses Ready with one key for two causes, so the words
     are built from the task it refused: naming an owner beside the owner
     the rail shows is how the page contradicted itself. */
  function said(err, t) {
    if (err === 'ready-needs-owner-and-due' && t) {
      var need = [];
      /* A queue row carries no assignees; the queue's own read of the owner
         is what it knows. */
      if (!ownerId(t) && !(state.ownerIds && state.ownerIds[t.id])) need.push('an owner');
      if (!t.current_final_due_at) need.push('a final due date');
      if (need.length) return 'Ready needs ' + need.join(' and ') + '.';
    }
    return SAID[err] || ('Refused: ' + err + '.');
  }

  // ---- State ---------------------------------------------------------------
  var state = {
    tasks: null, stages: {}, workflows: [], templates: [], members: [], clients: [],
    owners: {}, ownerIds: {},   // task id → the live owner's name, and their id
    find: '', scope: 'mine', filter: 'day', group: 'due', period: 'month', err: null,
    view: 'list',          // list | board | calendar: three readings of one set of rows
    wf: null,              // the workflow the board lays out
    month: null,           // the first day of the month the calendar shows
    week: [],              // this week's work sessions, for the capacity strip
    notifs: [],            // my unread notifications
    task: null,            // the open task, as ops_task_json returned it
    pane: 'work',
    session: null,         // my one open work session, whichever task it is on
    detail: { checklist: [], links: [], sessions: [], events: [], video: null },
    moved: null,           // the last stage move, named on the row the repaint draws
    tick: null,
    selecting: false,      // the list's ticks are showing
    picked: {},            // task id -> 1, for the ticked rows
    shown: []              // the rows the list last drew, which Select all means
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
  /* WHAT THE FINAL DATE ACTUALLY PROMISES.
     It is the day the work is owed *at client review*, not a square on a
     calendar: a task still short of that stage when the date passes is late
     whatever its own stage says, and that is what an admin is shown. Asked
     for by the user on 2026-09-21.

     Where client review begins is the workflow's own to say, read off
     `stage_group` and not off a stage key, because the two seeded workflows
     name that stage differently and one somebody adds next year will again.
     Derived on every read and never stored: a flag written once by the move
     that caused it is wrong the moment somebody reverts. */
  function reviewFloor(wf) {
    var at = null;
    Object.keys(state.stages).forEach(function (k) {
      var s = state.stages[k];
      if (!s || s.workflow_id !== wf || s.stage_group !== 'client_review') return;
      if (at === null || s.position < at) at = s.position;
    });
    return at;
  }
  function isLate(t) {
    if (!t || !t.current_final_due_at) return false;
    /* A task that is finished was not late for being finished: whether it
       arrived on time is the record's question, not the queue's. */
    if (t.completed_at || t.cancelled_at) return false;
    var due = dayOf(t.current_final_due_at);
    if (!due || due.getTime() >= todayStart().getTime()) return false;
    var here = stageOf(t);
    var floor = reviewFloor(t.workflow_id);
    /* A workflow with no client review stage falls back to the plain reading
       of the date, which is what it meant before this rule existed. */
    if (floor === null || !here) return true;
    return here.position < floor;
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
  /* The deliverable format, in the words the rate card sells it by. The older
     keys stay named, because a task created before the list changed still
     carries one. */
  var DELIVER_WORD = {
    ad_campaign: 'Ad Campaign', static: 'Graphic: Static', gif: 'Graphic: GIF',
    carousel: 'Graphic: Carousel', reels_30: 'Reels: up to 30s',
    reels_60: 'Reels: up to 60s', reels_120: 'Reels: up to 120s', report: 'Report',
    account_mgmt: 'Account Management', koc: 'KOC', kol: 'KOL', other: 'Other',
    reel: 'Reel', video: 'Video', story: 'Story', copywriting: 'Copywriting',
    design: 'Design', adhoc: 'Ad-hoc request', graphic: 'Graphic'
  };
  /* What a task is for: engagement work is what a contract pays for, ad hoc
     is asked for outside it, goodwill is given, special is anything else the
     team names. */
  var TASK_TYPE_WORD = { engagement: 'Engagement', adhoc: 'Ad hoc', goodwill: 'Goodwill', special: 'Special' };
  /* `simple` is the stored key and Light is the word the team uses for it. */
  var COMPLEX_WORD = { simple: 'Light', standard: 'Standard', complex: 'Complex' };
  /* Priority is how soon, on four words; the fifth level a row written before
     this list can still carry reads as Low. */
  var PRIORITY_WORD = { '1': 'Urgent', '2': 'High', '3': 'Normal', '4': 'Low', '5': 'Low' };
  function formatWord(t) {
    if (!t || !t.deliverable_type) return '';
    return DELIVER_WORD[t.deliverable_type] || sentence(t.deliverable_type);
  }
  /* The format as a line under a name says it: once. A task made in bulk is
     named for its format, so "Graphic: Static" under "2609W101 Graphic:
     Static" is the same fact twice. */
  function metaFormat(t) {
    var f = formatWord(t);
    if (!f) return '';
    return String(t.title || '').toLowerCase().indexOf(f.toLowerCase()) > -1 ? '' : f;
  }
  /* Whose it is, as the row and the head say it: the client's name, the
     lead's name marked as a lead, or Internal. */
  function whoseWord(t) {
    var name = t.clients && t.clients.name;
    if (t.scope === 'internal') return 'Internal';
    if (t.scope === 'lead') return name ? 'Lead · ' + name : 'Lead';
    return name || '';
  }
  /* Urgent and High carry a chip because they are the exception; Normal and
     Low are the ordinary case and say nothing, which is the accent rule. */
  function priorityChip(t) {
    var p = Number(t.priority_level);
    if (p === 1) return '<span class="tone is-warn task-pri">Urgent</span>';
    if (p === 2) return '<span class="tone task-pri">High</span>';
    return '';
  }
  function sentence(s) {
    s = String(s || '').replace(/_/g, ' ');
    return s ? s.charAt(0).toUpperCase() + s.slice(1) : '';
  }

  /* After approval the post is a fact and then a live one, so Scheduled and
     Live are green; the performance review waits on a person, so it is warn;
     a post taken down is an outcome and reads mute. */
  var STAGE_TONE = {
    intake: 'is-off', kiv: 'is-off', cancelled: 'is-off', taken_down: 'is-off',
    internal_review: 'is-warn', client_review: 'is-warn', waiting: 'is-warn', performance: 'is-warn',
    approved: 'is-ok', delivered: 'is-ok', done: 'is-ok', scheduled: 'is-ok', live: 'is-ok',
    blocked: 'is-danger'
  };
  /* WHEN A TASK IS NEXT OWED. Up to client review it is the final due date,
     the commitment. After approval the date that matters is the one the post
     goes out, and once it is live, the day its performance is reviewed —
     three days on. A post live since Monday is not "overdue" because its
     client review date has passed; it is due for review on Thursday. */
  var REVIEW_AFTER_DAYS = 3;
  function dueOf(t) {
    var s = stageOf(t), g = s ? s.stage_group : '';
    if (!isFinished(t) && (g === 'approved' || g === 'scheduled') && t.publish_at) return t.publish_at;
    if (!isFinished(t) && (g === 'live' || g === 'performance') && t.live_at) return plusDays(t.live_at, REVIEW_AFTER_DAYS);
    return t.current_final_due_at;
  }
  /* The word the due column puts before a date that is not the final due. */
  function dueLead(t) {
    var s = stageOf(t), g = s ? s.stage_group : '';
    if (isFinished(t)) return '';
    if ((g === 'approved' || g === 'scheduled') && t.publish_at) return 'Publish';
    if ((g === 'live' || g === 'performance') && t.live_at) return 'Review';
    return '';
  }
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
      /* The stage decides which list a client is offered on: Client is the
         clients engaged now, Lead the records not yet one. */
      db.from('clients').select('id, name, stage').order('name')
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
      /* The week is always read, because Completed today, the workload's
         Done this week and the undo after a completion all need it. */
      var since = new Date(Math.min(periodStart().getTime(), weekStart().getTime())).toISOString();
      var base = function () {
        return db.from('ops_tasks').select('*, clients(name)').is('archived_at', null)
          .order('current_final_due_at', { ascending: true, nullsFirst: false });
      };
      Promise.all([
        base().is('completed_at', null).is('cancelled_at', null),
        base().gte('completed_at', since).limit(500),
        base().gte('cancelled_at', since).limit(500),
        /* SEARCHING COMPLETED WORK asks the database, across every month:
           history is too long to hold in the browser, and a search that
           looked only at what happened to be loaded would say "no matches"
           about a task that exists. */
        (state.filter === 'done' || state.filter === 'all') && state.find
          ? base().not('completed_at', 'is', null).ilike('title', '%' + state.find.replace(/[%_]/g, '') + '%').limit(200)
          : Promise.resolve({ data: [] }),
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
        var bad = (r[0] && r[0].error) || (r[4] && r[4].error);
        if (bad) {
          state.err = bad;
          UI.failLine(box, 'Your tasks', bad.message, load);
          return;
        }
        /* One row can only be in one of the three, but a merge that trusted
           that would be a merge nobody had checked. */
        var seen = {};
        state.tasks = [].concat((r[0] && r[0].data) || [], (r[1] && r[1].data) || [],
                                (r[2] && r[2].data) || [], (r[3] && r[3].data) || [])
          .filter(function (t) {
            if (seen[t.id]) return false;
            seen[t.id] = 1;
            return true;
          });
        state.owners = {};
        state.ownerIds = {};
        state.onTask = {};
        ((r[4] && r[4].data) || []).forEach(function (a) {
          /* Following is being on the task in any other capacity than owning
             it: a reviewer or a contributor is somebody the task's changes
             concern without the task being theirs to carry. */
          (state.onTask[a.task_id] = state.onTask[a.task_id] || {})[a.team_member_id] = a.responsibility;
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

  // ---- Everyday tasks, and the plain status every task is read by -------------
  /* A task is one finishable action. Most of them are on the everyday
     workflow, whose five states are the ones a person uses to talk about
     their day; a content deliverable keeps its detailed workflow, and the
     list reads it through the same five words, with the next step it needs
     said in the drawer. */
  function wfKey(t) {
    var w = (state.workflows || []).filter(function (x) { return x.id === t.workflow_id; })[0];
    return w ? w.key : '';
  }
  function isEveryday(t) { return wfKey(t) === 'task'; }
  var PLAIN = {
    todo: { word: 'To do', tone: 'is-off' },
    doing: { word: 'In progress', tone: '' },
    waiting: { word: 'Waiting', tone: 'is-warn' },
    review: { word: 'Review', tone: '' },
    done: { word: 'Done', tone: 'is-ok' },
    cancelled: { word: 'Cancelled', tone: 'is-off' }
  };
  /* The everyday stage each plain status is. */
  var PLAIN_KEY = { todo: 'todo', doing: 'doing', waiting: 'waiting', review: 'review', done: 'complete' };
  function plainOf(t) {
    if (t.cancelled_at) return 'cancelled';
    if (t.completed_at) return 'done';
    if (t.stage_key === 'blocked') return 'waiting';
    if (isEveryday(t)) return t.stage_key === 'complete' ? 'done' : (PLAIN[t.stage_key] ? t.stage_key : 'todo');
    var s = stageOf(t);
    var g = s ? s.stage_group : '';
    /* Scheduled and live wait on a date rather than on anybody's hands, so
       they read with the waiting work; a performance review is a review. */
    if (g === 'waiting' || g === 'kiv' || g === 'scheduled' || g === 'live') return 'waiting';
    if (g === 'internal_review' || g === 'client_review' || g === 'performance') return 'review';
    if (isWork(g) || g === 'revision' || g === 'approved' || g === 'delivered') return 'doing';
    if (g === 'done' || g === 'taken_down') return 'done';
    return 'todo';
  }
  function doneToday(t) {
    var d = dayOf(t.completed_at || t.cancelled_at);
    return Boolean(d && d.getTime() === todayStart().getTime());
  }
  /* Where the msg for an act goes: the drawer's own line while it is open. */
  function msgHere(fallback) { return state.drawer ? 'dwMsg' : (fallback || 'taskNextMsg'); }

  // ---- The queue -----------------------------------------------------------
  /* How far back finished work is read. Never applied to open work. */
  function periodStart() {
    var d = new Date();
    if (state.period === 'week') return weekStart();
    if (state.period === 'q') return new Date(d.getFullYear(), d.getMonth() - 2, 1);
    if (state.period === 'year') return new Date(d.getFullYear(), 0, 1);
    return new Date(d.getFullYear(), d.getMonth(), 1);
  }

  /* THE DAY, IN THE ORDER IT IS WORKED. What is overdue, what is due today,
     what is in hand, what is ready for review, what is coming, what is waiting
     on somebody else, and what was finished today. Nobody has to sort a list
     before they can read their day. */
  var BANDS = [
    { key: 'overdue',   name: 'Overdue' },
    { key: 'today',     name: 'Due today' },
    { key: 'doing',     name: 'In progress' },
    { key: 'review',    name: 'Ready for review' },
    { key: 'upcoming',  name: 'Upcoming' },
    { key: 'nodate',    name: 'No due date' },
    { key: 'waiting',   name: 'Waiting' },
    { key: 'donetoday', name: 'Completed today' },
    { key: 'done',      name: 'Completed' }
  ];
  function bandOf(t) {
    if (isFinished(t)) return doneToday(t) ? 'donetoday' : 'done';
    var n = daysAway(dueOf(t)), p = plainOf(t);
    if (n !== null && n < 0) return 'overdue';
    if (n === 0) return 'today';
    if (p === 'waiting') return 'waiting';
    if (p === 'doing') return 'doing';
    if (p === 'review') return 'review';
    return n === null ? 'nodate' : 'upcoming';
  }
  var PLAIN_ORDER = ['todo', 'doing', 'review', 'waiting', 'done', 'cancelled'];
  /* One line that places a task: whose it is, and the month's content it
     belongs to where it belongs to one. */
  function engName(t) {
    var c = (t.clients && t.clients.name) || '';
    var m = t.engagement_id && t.code_period ? monthWord(t.code_period) + ' content' : '';
    return [c, m].filter(Boolean).join(' · ');
  }

  /* THE AXIS. The same rows asked a different question: by day is what
     orders a day, by stage is where each piece of work has got to, by status
     is the same in five words across every workflow, by task owner is who is
     carrying it, by client is how the work is sold, by engagement is the
     month it belongs to. */
  /* Completed work is read by the month it was finished in, newest first:
     a year of it under one heading is a card nobody opens. */
  function doneMonth(t) {
    var d = new Date(t.completed_at || t.cancelled_at || t.updated_at || Date.now());
    return monthKey(d);
  }
  function groupsOf(rows) {
    var mode = state.group, out = [], by = {};
    function put(key, name, sort) {
      if (!by[key]) { by[key] = { key: key, name: name, sort: sort, rows: [] }; out.push(by[key]); }
      return by[key];
    }
    /* Completed, read by day, is read by month instead: every row in it is
       finished, so the bands of a day would put them all under one. */
    var byMonth = mode === 'due' && state.filter === 'done';
    var wfPos = {};
    (state.workflows || []).forEach(function (w, i) { wfPos[w.id] = i; });
    rows.forEach(function (t) {
      if (byMonth) {
        var mk = doneMonth(t);
        put('m-' + mk, monthWord(mk), mk).rows.push(t);
      } else if (mode === 'client') {
        var c = (t.clients && t.clients.name) || (t.scope === 'internal' ? 'Internal' : 'No client');
        put('c-' + c, c, c).rows.push(t);
      } else if (mode === 'status') {
        var p = plainOf(t);
        put('s-' + p, PLAIN[p].word, String(PLAIN_ORDER.indexOf(p))).rows.push(t);
      } else if (mode === 'stage') {
        /* The stage itself, named as the workflow names it. Two workflows
           that call a stage the same thing share one card, ordered where the
           first of them puts it. */
        var s = stageOf(t);
        var lab = isFinished(t) && !s ? 'Finished' : stageLabel(t);
        var pos = s ? String(wfPos[s.workflow_id] || 0).padStart(2, '0') + String(s.position).padStart(3, '0') : '99999';
        var g = put('g-' + lab.toLowerCase(), lab, pos);
        if (pos < g.sort) g.sort = pos;
        g.rows.push(t);
      } else if (mode === 'owner') {
        var o = state.owners[t.id] || '';
        put('o-' + (o || 'none'), o || 'No task owner', o ? '1' + o : '2').rows.push(t);
      } else if (mode === 'engagement') {
        var e = t.engagement_id ? engName(t) || 'Engagement' : '';
        put('e-' + (t.engagement_id || 'none'), e || 'No engagement', e ? '1' + e : '2').rows.push(t);
      } else {
        var b = bandOf(t);
        put(b, (BANDS.filter(function (x) { return x.key === b; })[0] || {}).name || b,
            String(BANDS.map(function (x) { return x.key; }).indexOf(b))).rows.push(t);
      }
    });
    if (byMonth) {
      out.sort(function (a, b) { return String(b.sort).localeCompare(String(a.sort)); });
    } else if (mode === 'due') {
      var order = BANDS.map(function (x) { return x.key; });
      out.sort(function (a, b) { return order.indexOf(a.key) - order.indexOf(b.key); });
    } else {
      out.sort(function (a, b) { return String(a.sort).localeCompare(String(b.sort)); });
    }
    return out;
  }
  /* By day every band is worth reading except what is finished: Completed
     today and the older Completed card stay shut until they are opened, so
     finished work is one press away and never in the way. Completed, read by
     month, opens this month and shuts the rest. Off the day axis the
     headings are the page: thirty client cards with a count each are
     scanned, thirty open ones are not. */
  function shutByDefault(g) {
    if (state.group === 'due' && state.filter === 'done') return g.key !== 'm-' + monthKey(new Date());
    if (state.group !== 'due') return true;
    return g.key === 'done' || g.key === 'donetoday';
  }
  function marksOf(g) {
    if (g.key === 'overdue') return '<span class="tone is-warn">Overdue</span>';
    if (state.group === 'due') return '';
    var late = g.rows.filter(function (t) {
      return !isFinished(t) && daysAway(dueOf(t)) < 0;
    }).length;
    return late ? '<span class="tone is-warn">' + late + ' overdue</span>' : '';
  }

  /* THE VIEW: the question a person is asking of their work. My day is the
     whole of it in the order above; the day views narrow it by date, and the
     stage views are the ones My Work was published with, keyed on the stage
     group the workflow carries, because two workflows name the same stage
     differently. */
  function inFilter(t) {
    var f = state.filter || 'day';
    var fin = isFinished(t), n = daysAway(dueOf(t)), p = plainOf(t);
    var s = stageOf(t), g = s ? s.stage_group : '';
    if (f === 'all') return true;
    if (f === 'done') return fin;
    if (f === 'day') return fin ? doneToday(t) : true;
    if (fin) return false;
    if (f === 'today') return n !== null && n <= 0;
    if (f === 'overdue') return n !== null && n < 0;
    /* Owed within the week and not already over: overdue is its own answer. */
    if (f === 'soon') return n !== null && n >= 0 && n <= 7;
    if (f === 'upcoming') return n === null || n > 0;
    /* The work in hand, on either word a workflow uses for it: the stage's
       own flag, or its group. */
    if (f === 'active') return Boolean(s && (s.is_active_work || isWork(g)));
    if (f === 'internal_review') return g === 'internal_review';
    if (f === 'client_review') return g === 'client_review';
    /* With the client for a decision, or held because they have not
       answered. */
    if (f === 'waiting_client') return g === 'client_review' || (t.stage_key === 'blocked' && t.blocked_category === 'client');
    /* Everything after the client said yes: approved, scheduled, live and
       under review for how it performed. */
    if (f === 'after') return g === 'approved' || g === 'scheduled' || g === 'live' || g === 'performance';
    if (f === 'waiting') return g === 'waiting' || g === 'kiv' || t.stage_key === 'blocked';
    if (f === 'review') return p === 'review';
    if (f === 'late') return isLate(t);
    return true;
  }
  function inScope(t) {
    if (state.scope === 'all') return true;
    var me = bridge.me && bridge.me();
    if (!me || !me.id) return true;
    /* The whole team's queue arrives where `ops.all` is granted, so every
       view here is a filter over what came back and never a second read.
       Keyed on the id and not the name: two colleagues can share a first
       name, and a rename would quietly empty somebody's queue. */
    if (state.scope === 'created') return t.created_by === me.id;
    /* Following is being on the task as its reviewer or a contributor: the
       work is not yours to carry, and its changes still concern you. */
    if (state.scope === 'following') {
      var role = state.onTask && state.onTask[t.id] && state.onTask[t.id][me.id];
      return Boolean(role && role !== 'owner');
    }
    return state.ownerIds[t.id] === me.id;
  }
  function matches(t) {
    if (!state.find) return true;
    var hay = [t.title, t.code, t.content_desc, t.description, t.remarks,
               formatWord(t), TASK_TYPE_WORD[t.task_type] || t.task_type,
               (t.clients && t.clients.name), state.owners[t.id],
               serialOf(t), stageLabel(t)].join(' ').toLowerCase();
    /* A number is found whether it is typed with the hash or without it. */
    return hay.indexOf(state.find) > -1 || hay.indexOf('#' + state.find) > -1;
  }
  /* Inside a band the rows read by how soon, then by when: an Urgent task
     owed on Friday sits above a Normal one owed on Thursday, because the band
     has already said which week it is. */
  function byPriority(a, b) {
    var pa = Number(a.priority_level) || 3, pb = Number(b.priority_level) || 3;
    if (pa !== pb) return pa - pb;
    var da = a.current_final_due_at || '9999', dbb = b.current_final_due_at || '9999';
    return da < dbb ? -1 : da > dbb ? 1 : 0;
  }

  /* Which container the view draws in. The other two are hidden, and the
     capacity strip draws only with the board, where the question it answers
     (who has room this week) is the question being asked. */
  function viewBox() {
    var list = $('workQueue'), board = $('workBoard'), cal = $('workCal'), cap = $('workCap');
    var rep = $('workReport'), wl = $('workLoad');
    if (wl) wl.hidden = state.view !== 'load';
    if (list) list.hidden = state.view !== 'list';
    if (board) board.hidden = state.view !== 'board';
    if (cal) cal.hidden = state.view !== 'calendar';
    if (cap) cap.hidden = state.view !== 'board';
    if (rep) rep.hidden = state.view !== 'report';
    return state.view === 'board' ? board
         : state.view === 'load' ? wl
         : state.view === 'calendar' ? cal
         : state.view === 'report' ? rep : list;
  }

  function paint() {
    var box = viewBox();
    if (!box) return;
    /* The report is the same work asked an aggregate question, so it reads
       its own figures and none of the row filtering below applies to it:
       "how long does Editing take" is a question about every task there has
       ever been and not about the rows on this page. */
    if (state.view === 'report') { paintReport(); return; }
    if (!state.tasks) return;
    if (state.view === 'load') { paintLoad(); return; }
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
      UI.emptyLine(box, state.filter === 'day' ? 'Nothing on your list.' : 'No tasks.', may('ops', 'work') ? 'Add a task' : '', function () { openQuick(); });
      state.shown = [];
      paintUndone();
      paintBulk();
      return;
    }
    if (!rows.length) {
      /* Back to the view this route opens on, and no further: whose queue you
         are looking at is not a filter, so clearing the filters does not put
         somebody back on their own work without being asked. */
      UI.emptyLine(box, 'No matches.', 'Clear the filters', function () {
        state.find = ''; state.filter = 'day'; state.group = 'due';
        if ($('workFind')) $('workFind').value = '';
        if ($('workStage')) $('workStage').value = 'day';
        if ($('workGroup')) $('workGroup').value = 'due';
        showPeriod();
        paint();
      });
      state.shown = [];
      state.picked = {};
      paintBulk();
      return;
    }
    box.innerHTML = '';
    box.classList.toggle('is-mine', state.scope === 'mine');
    if (state.view === 'board') { paintBoard(all, rows); paintMoved(); return; }
    if (state.view === 'calendar') { paintCalendar(rows); return; }
    /* The ticks are over the rows on the page, so a pick that the view no
       longer shows is let go rather than deleted out of sight. */
    if (state.selecting) {
      var shown = {};
      rows.forEach(function (t) { shown[t.id] = 1; });
      Object.keys(state.picked).forEach(function (id) { if (!shown[id]) delete state.picked[id]; });
    }
    state.shown = rows;
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
          var table = GRP.table('svc-row task-row', ['', 'Task', 'Task Owner', 'Due', 'Stage', '']);
          GRP.more(table, g.rows.slice().sort(byPriority), 30, 'tasks', function (t) { return rowOf(t); });
          return table;
        }
      }));
    });
    paintMoved();
    paintRowSaid();
    paintUndone();
    paintBulk();
  }

  // ---- Several tasks at once ------------------------------------------------
  /* A year of tasks is hundreds a month, and a list that can only be cleared
     one row at a time is a list nobody clears. Select turns the first cell of
     every row into a tick; the bar under the command bar counts them and
     offers the two acts that make sense for many at once. Both are Manage,
     both are asked again by the database, and a deletion states its count and
     takes a reason, because there is no restore. */
  function setSelecting(on) {
    state.selecting = Boolean(on) && may('ops', 'manage');
    state.picked = {};
    if (state.selecting && state.view !== 'list') applyView('list');
    paint();
    var bar = $('workBulk');
    if (bar && state.selecting) { var all = $('workBulkAll'); if (all) try { all.focus(); } catch (e) {} }
  }
  function pickedIds() { return Object.keys(state.picked || {}); }
  function paintBulk() {
    var bar = $('workBulk');
    if (!bar) return;
    bar.hidden = !state.selecting || state.view !== 'list';
    if (bar.hidden) return;
    var n = pickedIds().length;
    var shown = (state.shown || []).length;
    $('workBulkCount').textContent = n + ' selected';
    var all = $('workBulkAll');
    all.checked = n > 0 && n === shown;
    all.indeterminate = n > 0 && n < shown;
    all.setAttribute('aria-label', n === shown && n ? 'Clear the selection' : 'Select every task shown');
    $('workBulkOwner').disabled = !n;
    $('workBulkDelete').disabled = !n;
  }
  function pickRow(id, on) {
    if (on) state.picked[id] = 1; else delete state.picked[id];
    var row = document.querySelector('#workQueue [data-task="' + id + '"]');
    if (row) row.classList.toggle('is-picked', Boolean(on));
    paintBulk();
  }
  function bulkDelete() {
    var ids = pickedIds();
    if (!ids.length) return;
    var n = ids.length;
    ADspaceConfirm.ask({
      title: 'Delete ' + n + (n === 1 ? ' task' : ' tasks'),
      body: (n === 1 ? 'It goes' : 'They go') + ' with every stage move, comment, link, checklist item and time entry. There is no restore.',
      go: 'Delete', tone: 'danger',
      fields: [
        { name: 'n', label: 'Type ' + n + ' to confirm', match: String(n), mismatch: 'Type ' + n + ' to confirm.' },
        { name: 'why', label: 'Reason', need: 'A reason is required.' }
      ]
    }, function (v) {
      db.rpc('ops_delete_tasks', { p_tasks: ids, p_confirm: v.n, p_reason: v.why }).then(function (r) {
        var d = r.data;
        if (r.error || (d && d.error)) { msg('workMsg', r.error ? r.error.message : said(d.error), 'err'); return; }
        var gone = (d && d.deleted) || 0;
        state.picked = {};
        msg('workMsg', gone + (gone === 1 ? ' task deleted.' : ' tasks deleted.'), 'ok');
        load();
      }, function (e) { msg('workMsg', (e && e.message) || String(e), 'err'); });
    });
  }
  function bulkOwner() {
    var ids = pickedIds();
    if (!ids.length) return;
    ADspaceConfirm.ask({
      title: 'Assign task owner',
      body: 'The ' + (ids.length === 1 ? 'task goes' : ids.length + ' tasks go') + ' to one person, with the change on each task\'s record.',
      go: 'Assign',
      field: { label: 'Task Owner', choices: [['', 'Choose a person']].concat(state.members.map(function (m) { return [m.id, m.name]; })),
               need: 'Choose a person.' }
    }, function (who) {
      var done = 0, bad = null, i = 0;
      var next = function () {
        if (i >= ids.length) {
          if (bad) msg('workMsg', done + ' of ' + ids.length + ' assigned. ' + bad, 'err');
          else msg('workMsg', (done === 1 ? '1 task' : done + ' tasks') + ' assigned to ' + nameOf(who) + '.', 'ok');
          state.picked = {};
          load();
          return;
        }
        var id = ids[i++];
        var t = (state.tasks || []).filter(function (x) { return x.id === id; })[0];
        db.rpc('ops_assign_task', { p_task: id, p_owner: who, p_version: t ? t.version : null }).then(function (r) {
          var d = r.data;
          if (r.error || (d && d.error)) { bad = bad || (r.error ? r.error.message : said(d.error, t)); }
          else done++;
          next();
        }, function (e) { bad = bad || ((e && e.message) || String(e)); next(); });
      };
      next();
    });
  }

  /* THE NEXT NUMBER. What the next task will be called, and the place to set
     it, for an admin: the database refuses a number already used and files
     the change in the activity record. */
  function openNumbering() {
    if (!isAdmin()) return;
    db.rpc('ops_next_task_no').then(function (r) {
      var d = r.data;
      if (r.error || (d && d.error)) { msg('workMsg', r.error ? r.error.message : said(d.error), 'err'); return; }
      ADspaceConfirm.ask({
        title: 'Task numbering',
        body: 'The next task is ' + d.serial + '.' + (d.highest_serial ? ' The highest in use is ' + d.highest_serial + '.' : ' No task holds a number yet.'),
        go: 'Save',
        field: { label: 'Next number', value: String(d.next), need: 'Enter a number.' }
      }, function (v) {
        var want = Math.floor(Number(String(v).replace(/[^0-9]/g, '')));
        if (!want) { msg('workMsg', said('bad-number'), 'err'); return; }
        db.rpc('ops_set_next_task_no', { p_next: want }).then(function (q) {
          var e = q.data;
          if (q.error || (e && e.error)) {
            msg('workMsg', q.error ? q.error.message : said(e.error) + (e.highest ? ' The highest in use is ' + e.highest + '.' : ''), 'err');
            return;
          }
          msg('workMsg', 'The next task is ' + e.serial + '.', 'ok');
        });
      });
    });
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
    /* A retired workflow is still the workflow of every task already on it,
       so it is offered while any of them is in view; a workflow with nothing
       on it is offered only while it is live. */
    var wfs = state.workflows.filter(function (w) { return w.active !== false || counts[w.id]; });
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
        if (ok) stepFromRow(task, card, next);
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
    /* Late, not merely past: the same rule the queue row draws. */
    var over = isLate(t);
    var top = [serialOf(t),
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
          (who ? '<span class="bcard-name">' + esc(who) + '</span>'
               : '<span class="bcard-name mute">No task owner</span>') + '</span>' +
        (dueOf(t)
          ? '<span class="bcard-due' + (over ? ' is-over' : '') + '">' +
              esc((dueLead(t) ? dueLead(t) + ' ' : '') + shortDate(dueOf(t))) + '</span>'
          : '') +
      '</div>';
    /* A card opens the task beside the board, as a row does beside the list. */
    el.querySelector('.bcard-title').addEventListener('click', function () { openDrawer(t.id); });
    var sel = el.querySelector('.state-select');
    if (sel) sel.addEventListener('change', function () {
      var want = sel.value;
      sel.value = '';
      if (want) stepFromRow(t, el, want);
    });
    /* Wherever the move is allowed at all, under a finger as under a pointer.
       A keyboard still has no drag, so the select on every card stays and is
       the path both share: this is an addition, never a replacement. */
    if (may('ops', 'work') && !isFinished(t)) wireDrag(el, t);
    return el;
  }

  // ---- The calendar --------------------------------------------------------
  // ---- The report ----------------------------------------------------------
  /* THE SAME WORK, ASKED AN AGGREGATE QUESTION.
     What is running, what is late, how long each stage takes, whether it was
     there on time, and the same per person. Every figure comes from one call
     to `ops_report`, which derives them from rows the system has written since
     phase 1; the page computes nothing of its own, because a report a page
     works out for itself is a second definition of the thing.

     Read on arrival and again when the period changes, and kept, so switching
     to Board and back does not go to the database for numbers that have not
     moved. */
  function loadReport(again) {
    var want = state.period || 'month';
    if (!again && state.report && state.reportFor === want) { paintReport(); return; }
    state.reportBusy = true;
    state.reportFor = want;
    /* Through `paint` and never straight to `paintReport`: `viewBox` is what
       hides the queue, the board and the calendar, so a report drawn without
       it left the list on the screen underneath. */
    paint();
    db.rpc('ops_report', { p_from: periodStart().toISOString(), p_to: new Date().toISOString() })
      .then(function (r) {
        state.reportBusy = false;
        if (r.error) { state.report = null; state.reportErr = r.error.message || 'denied'; }
        else if (r.data && r.data.error) { state.report = null; state.reportErr = SAID[r.data.error] || r.data.error; }
        else { state.report = r.data; state.reportErr = ''; }
        paint();
      })
      .catch(function (e) {
        state.reportBusy = false; state.report = null;
        state.reportErr = String((e && e.message) || e);
        paint();
      });
  }

  /* Hours where a figure is hours and days where it is days: "2,880 min" is a
     number somebody has to divide before it means anything, and the question
     being asked of a stage is measured in days. */
  function spanWord(mins) {
    var m = Math.max(0, Math.round(Number(mins) || 0));
    if (m < 90) return m + ' min';
    if (m < 60 * 36) return Math.round(m / 60) + 'h';
    var d = m / 1440;
    return (d < 10 ? Math.round(d * 10) / 10 : Math.round(d)) + (d < 1.05 && d >= 0.95 ? ' day' : ' days');
  }

  /* A column heading is not on the screen on a phone, so a cell that holds a
     bare number has nothing saying what the number is. The middle cell carries
     its own word, drawn only where the header is hidden. */
  function repLab(word) {
    return '<span class="rep-lab">' + esc(word) + ' </span>';
  }
  function dayCount(n) {
    return n + (Math.abs(n) === 1 ? ' day' : ' days');
  }

  function repTable(host, title, heads, rowClass, rows, note) {
    var h = document.createElement('h3');
    h.className = 'ovsec-title';
    h.textContent = title;
    host.appendChild(h);
    if (!rows.length) {
      /* `emptyLine` fills the box it is handed, so the wrapper is what the
         next heading's gap keys on: the empty card is a block in the stack
         like the table it stands in for, and both are the same distance from
         the heading that follows. */
      var sub = document.createElement('div');
      sub.className = 'repempty';
      host.appendChild(sub);
      UI.emptyLine(sub, note || 'Nothing yet.');
      return;
    }
    var t = GRP.table(rowClass, heads);
    rows.forEach(function (cells) {
      var row = document.createElement('div');
      row.className = rowClass + (cells.cls ? ' ' + cells.cls : '');
      row.innerHTML = cells.html;
      if (cells.open) {
        var b = row.querySelector('[data-open]');
        if (b) b.addEventListener('click', function () { openTask(cells.open, true); });
      }
      t.appendChild(row);
    });
    host.appendChild(t);
  }

  function paintReport() {
    var box = $('workReport');
    if (!box) return;
    if (state.reportBusy && !state.report) { UI.skeleton(box, 4); return; }
    if (state.reportErr) {
      UI.failLine(box, 'the report', state.reportErr, function () { loadReport(true); });
      return;
    }
    var r = state.report;
    if (!r) { UI.emptyLine(box, 'No report.'); return; }
    box.innerHTML = '';

    /* Every figure below but the first is taken over a window, and on a phone
       the select that sets it is inside the filters sheet — so the window is
       stated on the report itself rather than left to a control that is not
       on the screen. */
    var win = document.createElement('p');
    win.className = 'routenote repwin';
    win.textContent = niceDate(r.from) + ' to ' + niceDate(r.to);
    box.appendChild(win);

    /* 1. What is running. The first question a manager asks, answered in the
          words on the stage itself, so "what is on shooting" reads as a row
          rather than as a group somebody has to translate. */
    repTable(box, 'What is running', ['Stage', '', 'Tasks'], 'svc-row rep-row',
      (r.running || []).map(function (s) {
        return { html: '<span class="svc-name"><b>' + esc(s.label) + '</b></span>' +
                       '<span class="rep-mid"></span>' +
                       '<span class="rep-num">' + esc(String(s.count)) + '</span>' };
      }), 'Nothing open.');

    /* 2. What is late, which is the flag the user asked be put in front of a
          manager: past the commitment and still short of client review. The
          title opens the task, because a list of problems nobody can act on
          from is a list nobody reads twice. */
    repTable(box, 'Late', ['Task', 'Owner', 'Over by'], 'svc-row rep-row',
      (r.late || []).map(function (t) {
        return {
          open: t.task_id,
          cls: 'is-late',
          html: '<span class="svc-name"><button class="task-open rep-open" data-open type="button">' +
                  '<b>' + esc(t.title || 'Untitled') + '</b>' +
                  '<small>' + esc([t.client, t.stage].filter(Boolean).join(' · ')) + '</small>' +
                '</button></span>' +
                '<span class="rep-mid">' + repLab('Owner') +
                  (t.owner ? esc(t.owner) : '<span class="mute">—</span>') + '</span>' +
                '<span class="rep-num is-over">' + esc(dayCount(Number(t.days_over))) + '</span>'
        };
      }), 'Nothing is late.');

    /* 3. How long each stage takes. A median, its 90th percentile and the
          count it was taken over, never a bare figure: a median over two
          tasks is not a measurement, and the tail is what a person is
          actually trying to find. */
    repTable(box, 'Time in each stage', ['Stage', 'Slowest tenth', 'Typical'], 'svc-row rep-row',
      (r.stage_time || []).map(function (s) {
        return { html: '<span class="svc-name"><b>' + esc(s.label) + '</b>' +
                         '<small>' + esc(s.n + (s.n === 1 ? ' time' : ' times')) + '</small></span>' +
                       '<span class="rep-mid">' + repLab('Slowest tenth') +
                         esc(spanWord(s.p90_minutes)) + '</span>' +
                       '<span class="rep-num">' + esc(spanWord(s.median_minutes)) + '</span>' };
      }), 'No stage moves in this period.');

    /* 4. Was it there on time. Replanning sits beside the rate and never
          inside it: an extension would otherwise erase the miss it was
          granted for, and a rate that cannot be missed measures nothing. */
    var ot = r.on_time || {};
    var reached = Number(ot.reached || 0);
    repTable(box, 'At client review on time', ['', '', ''], 'svc-row rep-row',
      !reached ? [] : [
        { html: '<span class="svc-name"><b>On time</b></span><span class="rep-mid">' +
                esc(Math.round((Number(ot.met) / reached) * 100) + '%') +
                '</span><span class="rep-num">' + esc(String(ot.met)) + '</span>' },
        { html: '<span class="svc-name"><b>Late</b></span><span class="rep-mid"></span>' +
                '<span class="rep-num' + (Number(ot.missed) ? ' is-over' : '') + '">' +
                esc(String(ot.missed)) + '</span>' },
        { html: '<span class="svc-name"><b>Date was moved</b>' +
                '<small>counted beside the rate, never inside it</small></span>' +
                '<span class="rep-mid"></span><span class="rep-num">' +
                esc(String(ot.replanned || 0)) + '</span>' }
      ], 'Nothing reached client review.');

    /* 5. By person. The foundation of a KPI and not a KPI: what somebody
          finished, how much of it was on time, and how long their work took
          end to end. No score and no ranking — a number a person can check is
          worth more than a league table nobody trusts. */
    repTable(box, 'By person', ['Person', 'On time', 'Typical'], 'svc-row rep-row',
      (r.by_person || []).map(function (m) {
        return { html: '<span class="svc-name"><b>' + esc(m.name) + '</b>' +
                         '<small>' + esc(m.completed + ' finished') + '</small></span>' +
                       '<span class="rep-mid">' + repLab('On time') +
                         esc(m.on_time + ' of ' + m.completed) + '</span>' +
                       '<span class="rep-num">' + esc(spanWord(m.median_cycle_minutes)) + '</span>' };
      }), 'Nothing finished.');
  }

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
    /* Each task on the day it is next owed: the commitment until client
       review, the publish date once it is approved, and the review date once
       it is live — which makes the calendar the month's content calendar. */
    rows.forEach(function (t) {
      var d = dayOf(dueOf(t));
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
      b.addEventListener('click', function () { openDrawer(b.getAttribute('data-task')); });
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
    /* The report is refused to anybody the part is not granted to, even from
       the address: `view=report` in a link somebody was sent must not open a
       view the database would only deny. */
    if (v === 'report' && !may('ops.reports', 'view')) v = 'list';
    if (v === 'load' && !may('ops.all', 'view')) v = 'list';
    state.view = v === 'board' || v === 'calendar' || v === 'report' || v === 'load' ? v : 'list';
    /* The workload is the team's, so it reads the team's queue. */
    if (state.view === 'load' && state.scope !== 'all' && $('workScope')) { state.scope = 'all'; $('workScope').value = 'all'; }
    var seg = $('workViews');
    if (seg) Array.prototype.forEach.call(seg.querySelectorAll('.acttab'), function (b) {
      var on = b.getAttribute('data-view') === state.view;
      b.classList.toggle('is-on', on);
      b.setAttribute('aria-pressed', String(on));
    });
    if ($('workGroup')) $('workGroup').hidden = state.view !== 'list';
    if ($('workScope')) $('workScope').hidden = state.view === 'load' || state.view === 'report';
    if ($('workWf')) $('workWf').hidden = state.view !== 'board';
    /* The report is not a filtered list, so the list's own controls say
       nothing about it: a search box over an aggregate filters nothing, and
       a stage filter over "what is running" is the question being asked. */
    var find = $('workFind'), stg = $('workStage'), cnt = $('workCount');
    if (find && find.parentElement) find.parentElement.hidden = state.view === 'report' || state.view === 'load';
    if (stg) stg.hidden = state.view === 'report' || state.view === 'load';
    if (cnt && state.view === 'report') cnt.textContent = '';
    showPeriod();
    if (state.view === 'board') loadCapacity();
  }
  function setView(v) {
    applyView(v);
    /* The report reads its own figures, so entering it is what asks for
       them. Kept between views, so Board and back does not go to the
       database for numbers that have not moved. */
    if (v === 'report') loadReport(false); else paint();
    if (bridge.setUrl) bridge.setUrl();
  }

  /* THE ROW IS THE WORKSPACE. A routine change never needs the task opened:
     the circle completes an everyday task, the owner and the due date are
     changed where they are printed, the stage is a select, and the ⋯ holds the
     rest. What opens the task is the title, into the sheet beside the list.
     Nothing here repeats the engagement's own facts: the line under the title
     is the one piece of context that places the task. */
  /* A content task is not ticked off from the list: its workflow moves it.
     Where the checkbox stands on an everyday task, the ring says how far
     along its own line it has come, which is what a list is scanned for. */
  function wfRing(t, fin) {
    var line = lineOf(t);
    var at = line.map(function (s) { return s.key; }).indexOf(t.stage_key);
    var n = line.length;
    /* A cancelled task ended without being finished, so its ring is empty
       and never the green of work that was done. */
    var cancelled = Boolean(t.cancelled_at);
    var done = cancelled ? 0 : fin ? n : Math.max(0, at);
    var r = 7, len = 2 * Math.PI * r, off = len * (1 - (n ? done / n : 0));
    var said = cancelled ? 'Cancelled' : fin ? 'Finished' : n && at > -1 ? 'Step ' + (at + 1) + ' of ' + n : stageLabel(t);
    return '<svg class="ring tring' + (fin && !cancelled ? ' is-ok' : '') + '" viewBox="0 0 20 20" role="img" aria-label="' + esc(said) + '">' +
      '<circle class="ring-track" cx="10" cy="10" r="' + r + '"/>' +
      '<circle class="ring-arc" cx="10" cy="10" r="' + r + '" stroke-dasharray="' + len.toFixed(2) + '" stroke-dashoffset="' + off.toFixed(2) + '"/></svg>';
  }
  /* The due cell's words: the date and how far off it is, with what the date
     is for where it is not the final due (a publish date, a review date). */
  function dueCell(t) {
    var v = dueOf(t), kind = dueLead(t);
    if (!v) return { long: 'No date', short: 'No date', label: 'No due date' };
    var w = dueWord(v);
    if (kind) w = kind + ' ' + (w === 'Today' || w === 'Tomorrow' ? w.toLowerCase() : w);
    /* The phone's shorter words say the same thing the desk's do: a task
       due today reads Today on both, not a bare date. */
    var n = daysAway(v);
    var near = n === 0 ? 'Today' : n === 1 ? 'Tomorrow' : '';
    var sh = near || shortDate(v) + (n < 0 ? ' · late' : '');
    if (kind) sh = kind + ' ' + (near ? near.toLowerCase() : shortDate(v));
    return { long: w, short: sh, label: (kind ? kind + ' ' : 'Due ') + niceDate(v) };
  }
  function rowOf(t, elsewhere) {
    var owners = elsewhere ? cw.owners : state.owners;
    var ownerIds = elsewhere ? (cw.ownerIds || {}) : state.ownerIds;
    var el = document.createElement('div');
    var fin = isFinished(t);
    var picking = !elsewhere && state.selecting;
    var picked = picking && state.picked[t.id];
    el.className = 'svc-row task-row' + (fin ? ' is-off' : '') + (picked ? ' is-picked' : '');
    el.setAttribute('data-task', t.id);
    var over = isLate(t) || (!fin && dueLead(t) && daysAway(dueOf(t)) < 0);
    var work = may('ops', 'work');
    var every = isEveryday(t);
    var p = plainOf(t);
    var ctx = engName(t) || whoseWord(t);
    var mine = state.session && state.session.task_id === t.id;
    var check = picking
      ? '<input type="checkbox" class="trow-pick" data-a="pick"' + (picked ? ' checked' : '') + ' aria-label="Select ' + esc(t.title || serialOf(t)) + '">'
      : every && work && p !== 'cancelled'
        ? '<button class="tcheck' + (p === 'done' ? ' is-done' : '') + '" type="button" data-a="check" aria-pressed="' + (p === 'done') + '" aria-label="' +
            esc((p === 'done' ? 'Reopen ' : 'Mark complete: ') + (t.title || 'task')) + '"></button>'
        : wfRing(t, fin);
    var who = owners[t.id] || '';
    var canOwn = may('ops', 'manage') && !fin;
    var dc = dueCell(t);
    /* The final due is the one a row edits; a publish or review date is the
       step's, and is changed where the step is. */
    var dueEdit = work && !fin && !dueLead(t);
    var dueHtml = '<span class="due-long">' + esc(dc.long) + '</span><span class="due-short">' + esc(dc.short) + '</span>';
    el.innerHTML =
      '<span class="trow-check">' + check + '</span>' +
      '<button class="task-open" type="button"><b>' + esc(t.title) + '</b>' +
        '<small>' + (priorityChip(t) ? priorityChip(t) + ' ' : '') +
          (mine ? '<span class="trun" aria-label="Your timer is running">Timing</span> ' : '') +
          esc(ctx) + '</small></button>' +
      '<span class="trow-meta">' +
      '<span class="task-owner">' + (canOwn
        ? '<button class="tinline" type="button" data-a="owner" aria-label="Task Owner of ' + esc(t.title) + ': ' + esc(who || 'nobody') + '. Change">' +
            (who ? esc(who) : '<span class="mute">Assign</span>') + '</button>'
        : (who ? esc(who) : '<span class="mute">—</span>')) + '</span>' +
      '<span class="task-due' + (over ? ' is-over' : '') + '">' + (dueEdit
        ? '<button class="tinline" type="button" data-a="due" aria-label="' + esc(dc.label) + '. Change">' + dueHtml + '</button>'
        : '<span aria-label="' + esc(fin ? 'Finished ' + niceDate(t.completed_at || t.cancelled_at) : dc.label) + '">' +
            (fin ? esc(niceDate(t.completed_at || t.cancelled_at)) : dueHtml) + '</span>') + '</span>' +
      '<span class="task-stage">' + statusCell(t) + '</span>' +
      '</span>' +
      '<span class="team-act">' + (work ? rowMenu(t) : '') + '</span>';
    el.querySelector('.task-open').addEventListener('click', function () {
      if (elsewhere) openDrawer(t.id, { from: 'client' }); else openDrawer(t.id);
    });
    var done = function () { if (elsewhere) readClientWork(); else load(); };
    var pk = el.querySelector('[data-a="pick"]');
    if (pk) pk.addEventListener('change', function () { pickRow(t.id, pk.checked); });
    var ck = el.querySelector('[data-a="check"]');
    if (ck) ck.addEventListener('click', function () { toggleDone(t, el, done); });
    var ow = el.querySelector('[data-a="owner"]');
    if (ow) ow.addEventListener('click', function () { inlineOwner(t, el, ow, ownerIds[t.id], done); });
    var du = el.querySelector('[data-a="due"]');
    if (du) du.addEventListener('click', function () { inlineDue(t, el, du, done); });
    var sel = el.querySelector('.state-select');
    if (sel) sel.addEventListener('change', function () {
      var want = sel.value;
      sel.value = '';
      if (!want) return;
      stepFromRow(t, el, want, done);
    });
    wireRowMenu(el, t, done);
    return el;
  }

  /* An everyday task's status is a select of five words. A content
     deliverable shows its own stage — the step it is actually at, named as
     its workflow names it — with the steps it may move to, which is how My
     Work was published: five words over thirteen stages hid where the work
     was, and that is the one thing the column is for. */
  function statusCell(t) {
    if (!isEveryday(t)) return stageCell(t);
    var p = plainOf(t);
    if (!may('ops', 'work') || p === 'cancelled') {
      return '<span class="tone ' + PLAIN[p].tone + '">' + esc(PLAIN[p].word) + '</span>';
    }
    return '<select class="select select-sm state-select ' + PLAIN[p].tone + '" aria-label="Status of ' + esc(t.title) + '">' +
      '<option value="">' + esc(PLAIN[p].word) + '</option>' +
      ['todo', 'doing', 'waiting', 'review', 'done'].filter(function (k) { return k !== p; }).map(function (k) {
        return '<option value="' + PLAIN_KEY[k] + '">' + esc(PLAIN[k].word) + '</option>';
      }).join('') + '</select>';
  }
  /* The stage and the steps it may move to: a select where the person may
     work the task and the stage can still move, the read-only chip
     everywhere else. Blocked needs a category first, so it is asked for on
     the task. A step that needs something said (a note, a date, a link) asks
     for it in the step sheet; the rest move on the pick. */
  function stageCell(t) {
    var s = stageOf(t);
    var nexts = ((s && s.next_stage_keys) || []).filter(function (k) { return k !== 'blocked'; });
    var word = function (k) {
      return stepWord(state.stages[t.workflow_id + '|' + k], t.engagement_id) || labelOfStage(t, k);
    };
    if (!may('ops', 'work') || isFinished(t) || !nexts.length) {
      return '<span class="tone ' + stageTone(t) + '">' + esc(word(t.stage_key)) + '</span>';
    }
    return '<select class="select select-sm state-select ' + stageTone(t) + '" ' +
      'aria-label="Stage of ' + esc(t.title) + '">' +
      '<option value="">' + esc(word(t.stage_key)) + '</option>' +
      nexts.map(function (k) {
        return '<option value="' + esc(k) + '">' + esc(word(k)) + '</option>';
      }).join('') + '</select>';
  }
  /* The meeting stage is named for the meeting, not for a claim about it:
     whether it is in the diary is the month's to say, and the head says it.
     One word for the row and the stepper; a band or a board column keeps the
     name the workflow gives the stage. */
  function stepWord(s, inMonth) {
    if (!s) return '';
    return s.key === 'meeting_scheduled' && inMonth ? 'Content meeting' : s.label;
  }

  function rowMenu(t) {
    var fin = isFinished(t);
    var s = stageOf(t);
    var canCancel = !fin && s && (s.next_stage_keys || []).indexOf('cancelled') > -1;
    return '<span class="kmenu-wrap">' +
      '<button class="kmenu-btn" type="button" aria-haspopup="true" aria-expanded="false" aria-label="More for ' + esc(t.title) + '">' +
        '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="19" cy="12" r="1.8"/></svg></button>' +
      '<span class="kmenu" hidden role="menu">' +
        '<button class="kmenu-item" data-m="open" type="button" role="menuitem">Open</button>' +
        '<button class="kmenu-item" data-m="full" type="button" role="menuitem">Open full record</button>' +
        (canCancel ? '<button class="kmenu-item" data-m="cancel" type="button" role="menuitem">Cancel task</button>' : '') +
      '</span></span>';
  }
  function wireRowMenu(el, t, done) {
    var btn = el.querySelector('.team-act .kmenu-btn'), menu = el.querySelector('.team-act .kmenu');
    if (!btn || !menu) return;
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      Array.prototype.forEach.call(document.querySelectorAll('#workQueue .kmenu, #cwList .kmenu'), function (m) {
        if (m !== menu) m.hidden = true;
      });
      var open = menu.hidden;
      menu.hidden = !open;
      btn.setAttribute('aria-expanded', String(open));
      if (open && window.ADspaceMenu) window.ADspaceMenu.place(btn, menu);
    });
    menu.addEventListener('click', function (e) {
      var it = e.target.closest('[data-m]');
      if (!it) return;
      menu.hidden = true;
      btn.setAttribute('aria-expanded', 'false');
      var a = it.getAttribute('data-m');
      var from = el.closest('#cwList') ? { from: 'client' } : null;
      if (a === 'open') openDrawer(t.id, from);
      if (a === 'full') openFull(t.id);
      if (a === 'cancel') {
        ADspaceConfirm.ask({
          title: 'Cancel task', body: 'Removes it from open work. It can be reopened.',
          go: 'Cancel task', tone: 'danger', cancel: 'Keep task',
          field: { label: 'Reason', rows: 2, need: 'A reason is required.' }
        }, function (why) {
          db.rpc('ops_transition_task', { p_task: t.id, p_next: 'cancelled', p_version: t.version, p_note: why })
            .then(function (r) {
              var d = r.data;
              if (r.error || (d && d.error)) { rowNote(el, r.error ? r.error.message : said(d.error, t)); return; }
              done();
            });
        });
      }
    });
  }
  document.addEventListener('click', function (e) {
    if (e.target.closest && e.target.closest('.team-act .kmenu-wrap')) return;
    Array.prototype.forEach.call(document.querySelectorAll('#workQueue .team-act .kmenu, #cwList .team-act .kmenu'), function (m) { m.hidden = true; });
  });

  /* ONE PRESS COMPLETES IT, and the way back is drawn at once. Completing
     stops any timer on the task (the database does that) and moves it out of
     the open bands; it stays in Completed with everything it had. */
  function toggleDone(t, el, done) {
    var p = plainOf(t);
    var from = t.stage_key;
    var next = p === 'done' ? 'todo' : 'complete';
    var ck = el.querySelector('[data-a="check"]');
    if (ck) { ck.disabled = true; ck.classList.toggle('is-done', next === 'complete'); }
    db.rpc('ops_transition_task', { p_task: t.id, p_next: next, p_version: t.version, p_note: null })
      .then(function (r) {
        var d = r.data;
        if (r.error || (d && d.error)) {
          if (ck) { ck.disabled = false; ck.classList.toggle('is-done', p === 'done'); }
          rowNote(el, r.error ? r.error.message : said(d.error, t));
          return;
        }
        if (next === 'complete') {
          state.undone = { id: t.id, back: from === 'complete' ? 'todo' : from, title: t.title };
        } else state.undone = null;
        if (state.session && state.session.task_id === t.id && next === 'complete') { state.session = null; stopTick(); }
        done();
      }, function (e) { if (ck) ck.disabled = false; rowNote(el, (e && e.message) || String(e)); });
  }
  /* The way back from a completion, drawn above the list once it repaints. */
  function paintUndone() {
    var u = state.undone;
    if (!u) return;
    state.undone = null;
    undoBar('Completed ' + (u.title || 'the task') + '.', function () {
      var t = (state.tasks || []).filter(function (x) { return x.id === u.id; })[0];
      db.rpc('ops_transition_task', { p_task: u.id, p_next: u.back, p_version: t ? t.version : null, p_note: null })
        .then(function () { load(); });
    }, $('workMsg'));
  }

  /* OWNER, IN TWO PRESSES: the name, then the person. It saves on the pick;
     a refusal puts the name back and says why under the row. */
  function inlineOwner(t, el, btn, was, done) {
    var sel = document.createElement('select');
    sel.className = 'select select-sm tinline-pick';
    sel.setAttribute('aria-label', 'Task Owner of ' + (t.title || 'task'));
    sel.innerHTML = (was ? '' : '<option value="">Choose a person</option>') + state.members.map(function (m) {
      return '<option value="' + esc(m.id) + '"' + (m.id === was ? ' selected' : '') + '>' + esc(m.name) + '</option>';
    }).join('');
    btn.hidden = true;
    btn.parentNode.appendChild(sel);
    sel.focus();
    var put = function () { if (sel.parentNode) sel.remove(); btn.hidden = false; };
    sel.addEventListener('blur', function () { if (!sel.disabled) setTimeout(put, 120); });
    sel.addEventListener('keydown', function (e) { if (e.key === 'Escape') { e.stopPropagation(); put(); btn.focus(); } });
    sel.addEventListener('change', function () {
      var pick = sel.value;
      if (!pick || pick === was) { put(); return; }
      sel.disabled = true;
      db.rpc('ops_assign_task', { p_task: t.id, p_owner: pick, p_version: t.version }).then(function (r) {
        var d = r.data;
        if (r.error || (d && d.error)) { sel.disabled = false; put(); rowNote(el, r.error ? r.error.message : said(d.error, t)); return; }
        state.owners[t.id] = nameOf(pick); state.ownerIds[t.id] = pick;
        state.rowSaid = { id: t.id, word: 'Task Owner changed to ' + nameOf(pick) + '.' };
        done();
      }, function (e) { sel.disabled = false; put(); rowNote(el, (e && e.message) || String(e)); });
    });
  }

  /* DUE DATE, WHERE IT IS PRINTED. A first date is set; a date already set
     is rescheduled, and the database still decides whether this person may
     move it or is asking whoever set it. */
  function inlineDue(t, el, btn, done) {
    var inp = document.createElement('input');
    inp.type = 'date';
    inp.className = 'input input-sm tinline-pick';
    inp.setAttribute('aria-label', 'Due date of ' + (t.title || 'task'));
    inp.value = dateValue(t.current_final_due_at);
    if (t.current_first_draft_due_at) inp.min = dateValue(t.current_first_draft_due_at);
    btn.hidden = true;
    btn.parentNode.appendChild(inp);
    inp.focus();
    if (inp.showPicker) { try { inp.showPicker(); } catch (e) {} }
    var put = function () { if (inp.parentNode) inp.remove(); btn.hidden = false; };
    inp.addEventListener('blur', function () { if (!inp.disabled) setTimeout(put, 150); });
    inp.addEventListener('keydown', function (e) { if (e.key === 'Escape') { e.stopPropagation(); put(); btn.focus(); } });
    inp.addEventListener('change', function () {
      if (!inp.value || inp.value === dateValue(t.current_final_due_at)) return;
      inp.disabled = true;
      saveDue(t, inp.value, function (out) {
        state.rowSaid = { id: t.id, word: out && out.asked ? 'Asked ' + (nameOf(t.created_by) || 'the person who set it') + ' to move it.' : 'Due ' + niceDate(inp.value + 'T00:00:00Z') + '.' };
        done();
      }, function (why) { inp.disabled = false; put(); rowNote(el, why); });
    });
  }
  function saveDue(t, day, ok, bad) {
    db.rpc('ops_request_due_change', {
      p_task: t.id, p_kind: 'final', p_value: day + 'T00:00:00Z',
      p_reason: t.current_final_due_at ? 'rescheduled' : 'initial', p_note: null, p_version: t.version
    }).then(function (r) {
      var d = r.data;
      if (r.error) { bad(r.error.message); return; }
      if (d && d.error) { bad(said(d.error, t)); return; }
      ok(d);
    }, function (e) { bad((e && e.message) || String(e)); });
  }

  /* The note an inline change left, on the row the repaint drew. */
  function paintRowSaid() {
    var m = state.rowSaid;
    if (!m) return;
    state.rowSaid = null;
    var row = document.querySelector('[data-task="' + m.id + '"]');
    if (row) rowNote(row, m.word, 'ok');
  }
  function labelOfStage(t, k) {
    var s = state.stages[t.workflow_id + '|' + k];
    return (s && s.label) || String(k || '').replace(/_/g, ' ');
  }

  /* The move the row asked for. A refusal puts the select back where it was
     and says why under the row, because the row is where the act happened and
     the command bar is a screen away from it on a long list. */
  function rowMove(t, el, sel) {
    stepFromRow(t, el, sel.value);
    sel.value = '';
  }
  function plainOfKey(k) { return k === 'complete' ? 'done' : k; }
  /* A step from a row, a card or a drop. Where the database needs something
     said before it will allow the move — what has to change, why a post came
     down, the date it is scheduled for or went live — the step sheet asks
     for it; every other move is made on the pick. */
  function stepFromRow(t, el, next, after) {
    if (!next) return;
    if (needsSay(t, next)) { openStep(t, next, { el: el, after: after }); return; }
    moveTo(t, el, next, null, after);
  }
  /* One path for every way a stage is moved on this page — the select on a
     list row, the select on a board card, and a card dragged into a column.
     All three go through `ops_transition_task` and therefore through the same
     gates, and all three name the refusal on the thing that was moved rather
     than in a bar a screen away. */
  function moveTo(t, el, next, back, after) {
    if (!next) return;
    back = back || function () {};
    rowNote(el, '');
    db.rpc('ops_transition_task',
      { p_task: t.id, p_next: next, p_version: t.version, p_note: null })
      .then(function (r) {
        if (r.error) { back(); rowNote(el, dbWord(r.error.message)); return; }
        var d = r.data;
        /* No draft link on the task: the step asks how it was sent, with
           WhatsApp already written in, rather than refusing the move. */
        if (d && d.error === 'needs-draft') { back(); openStep(t, next, { el: el, after: after, note: WA_NOTE }); return; }
        if (d && d.error) { back(); rowNote(el, said(d.error, t)); return; }
        /* A move that repaints the list and says nothing is a move nobody can
           tell they made: the row is rebuilt somewhere else in the band order
           and the select they pressed is gone. What happened is named under
           the row it happened on, once the repaint has drawn it. */
        state.moved = { id: t.id, word: isEveryday(t) ? (PLAIN[plainOfKey(next)] || {}).word || labelOfStage(t, next) : labelOfStage(t, next),
                        /* The page stays where the reader was: the repaint
                           rebuilds every band, and a phone that had scrolled
                           to keep the focused select in view jumped with it. */
                        y: window.scrollY };
        /* The band a row belongs to can change with its stage, so the queue is
           repainted rather than the cell patched. */
        if (after) after(); else load();
      }, function (e) { back(); rowNote(el, (e && e.message) || String(e)); });
  }
  /* The note the last move left, drawn on the row the repaint has just made. */
  function paintMoved() {
    var m = state.moved;
    if (!m) return;
    state.moved = null;
    if (typeof m.y === 'number') {
      try { if (document.activeElement && document.activeElement.blur) document.activeElement.blur(); } catch (e) {}
      window.scrollTo(0, m.y);
    }
    var row = document.querySelector('[data-task="' + m.id + '"]');
    if (row) rowNote(row, 'Moved to ' + m.word + '.', 'ok');
  }
  function rowNote(el, text, tone) {
    if (!el || !el.parentNode) { if (text) msg('workMsg', text, tone || 'err'); return; }
    var was = el.nextSibling;
    if (was && was.classList && was.classList.contains('task-note')) was.remove();
    if (!text) return;
    var note = document.createElement('div');
    note.className = 'msg ' + (tone || 'err') + ' task-note';
    note.textContent = text;
    el.parentNode.insertBefore(note, el.nextSibling);
    if (tone === 'ok') setTimeout(function () { if (note.parentNode) note.remove(); }, 6000);
  }

  // ---- The task, opened from a list -----------------------------------------
  /* A task opened from the list, the board, the calendar, the bell or a
     client's Work pane opens here, in the portal's own sheet docked beside
     the list: what it is and where it stands, the one thing to do next, then
     the facts, the brief, the checklist, the files, the talk, the time and
     what happened lately, each in its own card. The list stays where it was.
     The full record is one press further, for the rare task that needs it,
     and its address is still what a link to a task opens. */
  function openDrawer(id, o) {
    var d = $('taskDrawer');
    if (!d || !id) return;
    o = o || {};
    if (!d.hidden && state.drawer === id) return;
    state.drawer = id;
    state.drawerFrom = o.from || 'work';
    state.drawerDirty = false;
    if (d.hidden) state.drawerOpener = document.activeElement;
    var row = (state.tasks || []).concat(cw.tasks || []).filter(function (x) { return x.id === id; })[0];
    $('dwTitle').textContent = row ? row.title : '';
    $('dwNo').textContent = row ? serialOf(row) : '';
    $('dwStatus').textContent = '';
    $('dwCtx').textContent = '';
    $('dwCtx').hidden = true;
    $('dwFacts').innerHTML = '';
    $('dwNextTitle').textContent = '';
    $('dwNextLine').textContent = '';
    $('dwActs').innerHTML = '';
    $('dwHand').hidden = true;
    $('dwHand').removeAttribute('data-key');
    $('dwRate').hidden = true;
    CARD_FORMS.forEach(closeCardForm);
    ['dwTimeMore', 'dwLogMore'].forEach(function (x) { if ($(x)) $(x).open = false; });
    UI.skeleton($('dwChecks'), 2);
    msg('dwMsg', '');
    d.hidden = false;
    var card = d.querySelector('.sheet-card');
    if (card) { try { card.focus(); } catch (e) {} }
    var body = $('dwBody');
    if (body) body.scrollTop = 0;
    if (state.drawerFrom === 'work' && bridge.setUrl) bridge.setUrl();
    readTask(id);
  }
  function closeDrawer(noReload) {
    var d = $('taskDrawer');
    if (!d || d.hidden) return;
    d.hidden = true;
    var dirty = state.drawerDirty, id = state.drawer, from = state.drawerFrom;
    state.drawer = null;
    state.drawerFrom = null;
    if (!state.openId) state.task = null;
    if (!noReload && dirty) { if (from === 'client') readClientWork(); else load(); }
    if (from === 'work' && bridge.setUrl) bridge.setUrl();
    var opener = state.drawerOpener;
    state.drawerOpener = null;
    var row = id && document.querySelector('[data-task="' + id + '"] .task-open, [data-task="' + id + '"] .bcard-title');
    var back = opener && document.body.contains(opener) && opener.offsetParent !== null ? opener : row;
    if (back) { try { back.focus(); } catch (e) {} }
  }
  /* Typed words in the card are the reader's; a stray click beside it does
     not throw them away. */
  function drawerTyped() {
    return ['dwCheckAdd', 'dwLinkUrl', 'dwLinkLabel', 'dwComment', 'dwDescText'].some(function (x) {
      return $(x) && String($(x).value || '').trim();
    });
  }
  function openFull(id) {
    var from = state.drawerFrom;
    closeDrawer(true);
    /* From a client's record the full record is My Work's, so the address
       comes first, the way the bell opens a task. */
    if (from === 'client' || !$('sectionWork') || $('sectionWork').hidden) {
      history.replaceState(null, '', '/admin/?s=work&task=' + encodeURIComponent(id));
      if (bridge.show) bridge.show('work');
      return;
    }
    openTask(id, true);
  }

  function paintDrawer(t) {
    if (!state.drawer || !t || t.id !== state.drawer) return;
    var p = plainOf(t), every = isEveryday(t), work = may('ops', 'work');
    var fin = isFinished(t);
    var n = derive(t);
    $('dwNo').textContent = serialOf(t);
    $('dwNo').setAttribute('aria-label', 'Copy ' + serialOf(t));
    var ck = $('dwCheck');
    ck.hidden = !(every && work);
    ck.className = 'tcheck' + (p === 'done' ? ' is-done' : '');
    ck.setAttribute('aria-pressed', String(p === 'done'));
    ck.setAttribute('aria-label', p === 'done' ? 'Reopen' : 'Mark complete');
    var chip = $('dwStatus');
    chip.className = 'chip ' + n.tone;
    chip.textContent = n.status;
    $('dwTitle').textContent = t.title || 'Untitled task';
    /* One line that places it, and the way to where the rest of it lives:
       the month or the client is its own record, not this sheet's. */
    var ctx = [engName(t) || whoseWord(t), metaFormat(t)].filter(Boolean).join(' · ');
    var ml = t.engagement_id ? monthLink(t) : null;
    var cl = !ml && t.clients && t.clients.slug
      ? { label: t.scope === 'lead' ? 'View lead' : 'View client', href: '/admin/?s=clients&client=' + encodeURIComponent(t.clients.slug) } : null;
    var link = ml ? { label: 'View engagement', href: ml.href } : cl;
    $('dwCtx').innerHTML = esc(ctx) + (link ? (ctx ? ' · ' : '') + '<a class="tlink" href="' + esc(link.href) + '">' + esc(link.label) + '</a>' : '');
    $('dwCtx').hidden = !ctx && !link;

    paintNext(NEXT_DW(), t, n);

    // The facts a day's work turns on.
    var who = ownerName(t);
    var canOwn = may('ops', 'manage') && !fin;
    var dueTxt = t.current_final_due_at ? niceDate(t.current_final_due_at) : 'Not set';
    var over = isLate(t);
    var pen = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>';
    var facts =
      frow('Task Owner', '<span id="dwOwnerName">' + (who ? esc(who) : '<span class="mute">Nobody</span>') + '</span>',
        canOwn ? '<button class="linkbtn" id="dwOwnerChange" type="button">' + (who ? 'Change' : 'Assign') + '</button>' : '') +
      frow('Due', work && !fin
        ? '<button class="tdate' + (over ? ' is-over' : '') + '" id="dwDue" type="button" aria-label="Due ' + esc(dueTxt) + '. Change">' + esc(dueTxt) + pen + '</button>'
        : '<span class="tdate-read' + (over ? ' is-over' : '') + '">' + esc(dueTxt) + '</span>');
    /* After approval the dates the step runs on: when it goes out, and when
       it went live. */
    var sg = (stageOf(t) || {}).stage_group;
    var after = sg === 'approved' || sg === 'scheduled' || sg === 'live' || sg === 'performance' || sg === 'taken_down' || t.stage_key === 'completed';
    if (!every && (t.publish_at || after)) {
      var pubTxt = t.publish_at ? niceDate(t.publish_at) : 'Not set';
      facts += frow('Publish', work && !fin && (sg === 'approved' || sg === 'scheduled' || !after)
        ? '<button class="tdate" id="dwPublish" type="button" aria-label="Scheduled publish ' + esc(pubTxt) + '. Change">' + esc(pubTxt) + pen + '</button>'
        : '<span class="tdate-read">' + esc(pubTxt) + '</span>');
    }
    if (t.live_at) facts += frow('Live', esc(niceDate(t.live_at)));
    facts += frow('Created by', esc(nameOf(t.created_by) || '—'));
    /* How soon, on four words; a select where the reader may change it. */
    facts += frow('Priority', work && !fin
      ? '<select class="select select-sm qpri" id="dwPriority" aria-label="Priority">' +
          [['1', 'Urgent'], ['2', 'High'], ['3', 'Normal'], ['4', 'Low']].map(function (o) {
            return '<option value="' + o[0] + '"' + (String(Math.min(4, Number(t.priority_level) || 3)) === o[0] ? ' selected' : '') + '>' + o[1] + '</option>';
          }).join('') + '</select>'
      : esc(PRIORITY_WORD[String(t.priority_level)] || 'Normal'));
    $('dwFacts').innerHTML = facts;
    var oc = $('dwOwnerChange');
    if (oc) oc.addEventListener('click', function () {
      inlineOwner(t, $('dwFacts'), oc, ownerId(t), function () {
        state.drawerDirty = true;
        readTask(t.id, function () { msg('dwMsg', 'Task Owner changed.', 'ok'); });
      });
    });
    var dd = $('dwDue');
    if (dd) dd.addEventListener('click', function () {
      if (t.current_final_due_at) { openDue('final'); return; }
      inlineDue(t, $('dwFacts'), dd, function () {
        state.drawerDirty = true;
        readTask(t.id, function () { msg('dwMsg', state.rowSaid ? state.rowSaid.word : 'Saved.', 'ok'); state.rowSaid = null; });
      });
    });
    var dp = $('dwPublish');
    if (dp) dp.addEventListener('click', function () { inlinePublish(t, dp); });
    var dpr = $('dwPriority');
    if (dpr) dpr.addEventListener('change', function () {
      var was = String(Math.min(4, Number(t.priority_level) || 3));
      call('ops_update_task', { p_task: t.id, p_payload: { priority_level: Number(dpr.value) }, p_version: t.version }, 'dwMsg', function () {
        readTask(t.id, function () { msg('dwMsg', 'Priority saved.', 'ok'); });
      }, function () { dpr.value = was; });
    });
    $('dwTitleEdit').hidden = !work || fin;

    // The brief
    var desc = String(t.description || '').trim();
    $('dwDesc').innerHTML = desc ? '<p class="ovnote">' + esc(desc) + '</p>' : '<p class="qempty">No brief.</p>';
    $('dwDescEdit').hidden = !work || fin;
    /* The card's quiet action carries its glyph like the others do. */
    $('dwDescEdit').innerHTML = (desc
      ? '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>Edit'
      : '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>Add');
    $('dwDescSec').hidden = !desc && (!work || fin);

    // Checklist
    var items = state.detail.checklist;
    var cbox = $('dwChecks');
    cbox.innerHTML = items.map(function (c) {
      var menu = work && !fin && !c.required
        ? itemMenu(c.label, [['rename', 'Rename'], ['remove', 'Remove', true]]) : '';
      return '<div class="qitem qitem-mid" data-row="' + esc(c.id) + '"><label class="checkrow' + (c.completed_at ? ' is-done' : '') + '">' +
        '<input type="checkbox" data-item="' + esc(c.id) + '"' + (c.completed_at ? ' checked' : '') + (work ? '' : ' disabled') + '>' +
        '<span class="checkrow-label">' + esc(c.label) + (c.required ? ' <span class="tone is-warn">Required</span>' : '') + '</span></label>' +
        menu + '</div>';
    }).join('') || (work && !fin ? '<p class="qempty">No items.</p>' : '');
    var doneN = items.filter(function (c) { return c.completed_at; }).length;
    $('dwCheckCount').textContent = items.length ? doneN + ' of ' + items.length : '';
    Array.prototype.forEach.call(cbox.querySelectorAll('[data-item]'), function (cb) {
      cb.addEventListener('change', function () {
        var want = cb.checked, line = cb.closest('.checkrow');
        call('ops_set_checklist', { p_item: cb.getAttribute('data-item'), p_done: want }, 'dwMsg', function (row) {
          if (!row || !row.id) { cb.checked = !want; return; }
          state.detail.checklist = state.detail.checklist.map(function (c) { return c.id === row.id ? row : c; });
          if (line) line.classList.toggle('is-done', Boolean(row.completed_at));
          var dn = state.detail.checklist.filter(function (c) { return c.completed_at; }).length;
          $('dwCheckCount').textContent = dn + ' of ' + state.detail.checklist.length;
          state.drawerDirty = true;
          /* A performance review is completed once its checks are done, so
             the step card says so the moment the last one is ticked. */
          if (state.task && state.task.id === t.id) paintNext(NEXT_DW(), state.task, derive(state.task));
        }, function () { cb.checked = !want; });
      });
    });
    Array.prototype.forEach.call(cbox.querySelectorAll('.qitem'), function (row) {
      var c = items.filter(function (x) { return x.id === row.getAttribute('data-row'); })[0];
      wireItemMenu(row, function (a) {
        if (a === 'rename') renameItem(t, c);
        if (a === 'remove') removeItem(t, c, $('dwChecks'), 'dwMsg');
      });
    });
    $('dwCheckOpen').hidden = !work || fin;
    $('dwCheckSec').hidden = !items.length && (!work || fin);

    // Files and links
    var live = state.detail.links.filter(function (l) { return !l.archived_at; });
    $('dwLinks').innerHTML = live.length ? '<ul class="qlinks">' + live.map(function (l) {
      var href = safeUrl(l.url);
      var menu = work && !fin ? itemMenu(l.label || l.url, [['edit', 'Edit'], ['remove', 'Remove', true]]) : '';
      return '<li class="qitem" data-link="' + esc(l.id) + '"><span class="qlink-main"><span class="tone">' + esc(LINK_WORD[l.kind] || sentence(l.kind)) + '</span>' +
        (href ? '<a href="' + esc(href) + '" target="_blank" rel="noopener">' + esc(l.label || l.url) + '</a>' : '<span class="qlink-name">' + esc(l.label) + '</span>') +
        '</span>' + menu + '</li>';
    }).join('') + '</ul>' : '<p class="qempty">No files or links.</p>';
    Array.prototype.forEach.call($('dwLinks').querySelectorAll('.qitem'), function (row) {
      var l = live.filter(function (x) { return x.id === row.getAttribute('data-link'); })[0];
      wireItemMenu(row, function (a) {
        if (a === 'edit') openLinkEdit(l);
        if (a === 'remove') removeLinkIn(t, l, $('dwLinks'), 'dwMsg');
      });
    });
    $('dwLinkOpen').hidden = !work || fin;
    $('dwLinkSec').hidden = !live.length && (!work || fin);

    // Comments, oldest first, as a conversation reads, each as it now stands.
    var comments = commentsOf(state.detail.events);
    var me = myId();
    $('dwComments').innerHTML = comments.length ? '<ul class="qcomments">' + comments.map(function (c) {
      var mine = work && (c.actor_id === me || may('ops', 'manage'));
      var menu = mine ? itemMenu('comment', [['edit', 'Edit'], ['remove', 'Delete', true]]) : '';
      return '<li class="qitem" data-comment="' + esc(c.id) + '"><div><p>' + esc(c.body) + '</p>' +
        '<small>' + esc(whoName(c.e)) + ' · ' + esc(niceTime(c.at)) + (c.edited ? ' · edited' : '') + '</small></div>' + menu + '</li>';
    }).join('') + '</ul>' : (work ? '<p class="qempty">No comments.</p>' : '');
    Array.prototype.forEach.call($('dwComments').querySelectorAll('.qitem'), function (row) {
      var c = comments.filter(function (x) { return x.id === row.getAttribute('data-comment'); })[0];
      wireItemMenu(row, function (a) {
        if (a === 'edit') editComment(t, c);
        if (a === 'remove') removeComment(t, c, $('dwComments'));
      });
    });
    $('dwCommentOpen').hidden = !work;
    $('dwCommentSec').hidden = !comments.length && !work;

    paintDrawerTime(t);

    // Recent activity, and the whole of it on request.
    /* The talk is the Comments card's; what happened to the task is here. */
    var rest = state.detail.events.filter(function (e) { return !/^comment/.test(e.event_type); });
    var line = function (e) {
      var dt = eventDetail(e);
      return '<li><span class="raillog-what">' + esc(EVENT_WORD[e.event_type] || e.event_type.replace(/_/g, ' ')) + '</span>' +
        (dt ? '<span class="raillog-detail">' + esc(dt) + '</span>' : '') +
        '<span class="raillog-when">' + esc(niceTime(e.created_at)) + (whoName(e) ? ' · ' + esc(whoName(e)) : '') + '</span></li>';
    };
    $('dwLog').innerHTML = rest.length ? '<ul class="raillog raillog-plain">' + rest.slice(0, 3).map(line).join('') + '</ul>' : '';
    $('dwLogMore').hidden = rest.length <= 3;
    $('dwLogAll').innerHTML = rest.length > 3 ? '<ul class="raillog raillog-plain">' + rest.slice(3).map(line).join('') + '</ul>' : '';
    $('dwLogSec').hidden = !rest.length;

    $('dwFull').href = '/admin/?s=work&task=' + encodeURIComponent(t.id);

    // The ⋯
    var menu = $('dwMenu');
    var s = stageOf(t);
    var nexts = (s && s.next_stage_keys) || [];
    /* The way back is the move a person makes most after a mistake, so it
       leads the ⋯ wherever the workflow still allows it. */
    var back = cameFrom(t);
    var rv = menu.querySelector('[data-a="revert"]');
    var canBack = work && back && nexts.indexOf(back) > -1 && !fin && t.stage_key !== 'blocked';
    rv.hidden = !canBack;
    if (canBack) rv.textContent = 'Revert to ' + labelForKey(back);
    menu.querySelector('[data-a="move"]').hidden = !work || fin || !nexts.length;
    menu.querySelector('[data-a="block"]').hidden = !work || fin || t.stage_key === 'blocked' || every;
    menu.querySelector('[data-a="repeat"]').hidden = !work;
    menu.querySelector('[data-a="duplicate"]').hidden = !work;
    menu.querySelector('[data-a="reopen"]').hidden = !work || !canReopen(t);
    menu.querySelector('[data-a="cancel"]').hidden = !work || fin || nexts.indexOf('cancelled') < 0;
    menu.querySelector('[data-a="handover"]').hidden = fin;
  }
  // ---- Changing and taking back what was added --------------------------------
  /* A row the reader may change carries a ⋯ at its end, holding the acts for
     that one thing. It is the row menu every list in this console has. */
  function itemMenu(label, items) {
    return '<span class="kmenu-wrap">' +
      '<button class="kmenu-btn" type="button" aria-haspopup="true" aria-expanded="false" aria-label="More for ' + esc(label) + '">' +
        '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="19" cy="12" r="1.8"/></svg></button>' +
      '<span class="kmenu" hidden role="menu">' + items.map(function (x) {
        return '<button class="kmenu-item' + (x[2] ? ' is-danger' : '') + '" data-i="' + x[0] + '" type="button" role="menuitem">' + esc(x[1]) + '</button>';
      }).join('') + '</span></span>';
  }
  function shutItemMenus(except) {
    Array.prototype.forEach.call(document.querySelectorAll('.qitem .kmenu, .tlink-row .kmenu, .eng-ctl .kmenu'), function (m) {
      if (m === except) return;
      m.hidden = true;
      var b = m.parentNode && m.parentNode.querySelector('.kmenu-btn');
      if (b) b.setAttribute('aria-expanded', 'false');
    });
  }
  function wireItemMenu(row, onPick) {
    var btn = row.querySelector('.kmenu-btn'), menu = row.querySelector('.kmenu');
    if (!btn || !menu) return;
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      shutItemMenus(menu);
      var open = menu.hidden;
      menu.hidden = !open;
      btn.setAttribute('aria-expanded', String(open));
      if (open && window.ADspaceMenu) window.ADspaceMenu.place(btn, menu);
    });
    menu.addEventListener('click', function (e) {
      var it = e.target.closest('[data-i]');
      if (!it) return;
      menu.hidden = true;
      btn.setAttribute('aria-expanded', 'false');
      onPick(it.getAttribute('data-i'));
    });
  }
  document.addEventListener('click', function (e) {
    if (e.target.closest && e.target.closest('.qitem .kmenu-wrap, .tlink-row .kmenu-wrap, .eng-ctl .kmenu-wrap')) return;
    shutItemMenus(null);
  });

  /* A checklist item is renamed in place of the words it had, and removed
     with the way back drawn under the list. A required check is the review's
     own gate, so it carries no ⋯ at all. */
  function renameItem(t, c) {
    if (!c) return;
    ADspaceConfirm.ask({
      title: 'Rename item', go: 'Save',
      field: { label: 'Item', value: c.label, need: 'Say what needs doing.' }
    }, function (v) {
      call('ops_edit_checklist_item', { p_item: c.id, p_label: v }, msgHere('taskMsg'), function () {
        readTask(t.id, function () { msg(msgHere('taskMsg'), 'Item renamed.', 'ok'); });
      });
    });
  }
  function removeItem(t, c, host, where) {
    if (!c) return;
    call('ops_remove_checklist_item', { p_item: c.id }, where, function (d) {
      var gone = (d && d.removed) || c;
      readTask(t.id, function () {
        undoBar('Removed ' + gone.label + '.', function () {
          call('ops_add_checklist_item', { p_task: t.id, p_label: gone.label }, where, function (row) {
            var back = function () { readTask(t.id); };
            if (gone.completed_at && row && row.id) {
              call('ops_set_checklist', { p_item: row.id, p_done: true }, where, back, back);
            } else back();
          });
        }, host);
      });
    });
  }

  /* A link is corrected in the card's own form, and removed with its Undo. */
  var linkEditing = null;
  function openLinkEdit(l) {
    if (!l) return;
    linkEditing = l.id;
    openCardForm('dwLinkForm');
    $('dwLinkUrl').value = l.url || '';
    $('dwLinkKind').value = l.kind || 'other';
    $('dwLinkLabel').value = l.label || '';
    $('dwLinkSave').textContent = 'Save';
    $('dwLinkUrl').focus();
  }
  function removeLinkIn(t, l, host, where) {
    if (!l) return;
    call('ops_set_link_archived', { p_link: l.id, p_on: true }, where, function () {
      readTask(t.id, function () {
        undoBar((l.label || 'The link') + ' removed.', function () {
          call('ops_set_link_archived', { p_link: l.id, p_on: false }, where, function () { readTask(t.id); });
        }, host);
      });
    });
  }

  /* COMMENTS, AS THEY NOW STAND. A comment is never rewritten: a correction
     and a removal are later events that name it, so the thread is read by
     folding them in, oldest first, and the history keeps every word. */
  function commentsOf(events) {
    var by = {}, out = [];
    (events || []).slice().reverse().forEach(function (e) {
      if (e.event_type === 'commented') {
        var c = { id: e.id, body: (e.detail && e.detail.note) || '', actor_id: e.actor_id, at: e.created_at, edited: null, gone: false, e: e };
        by[e.id] = c;
        out.push(c);
        return;
      }
      if (e.event_type !== 'comment_edited' && e.event_type !== 'comment_removed' && e.event_type !== 'comment_restored') return;
      var ref = (e.to_value && e.to_value.event_id) || (e.from_value && e.from_value.event_id);
      var hit = by[ref];
      if (!hit) return;
      if (e.event_type === 'comment_edited') { hit.body = (e.detail && e.detail.note) || hit.body; hit.edited = e.created_at; }
      else hit.gone = e.event_type === 'comment_removed';
    });
    return out.filter(function (c) { return !c.gone; });
  }
  function editComment(t, c) {
    if (!c) return;
    ADspaceConfirm.ask({
      title: 'Edit comment', go: 'Save',
      field: { label: 'Comment', rows: 3, value: c.body, need: 'A comment cannot be empty.' }
    }, function (v) {
      call('ops_edit_comment', { p_event: c.id, p_body: v }, msgHere('taskMsg'), function () {
        readTask(t.id, function () { msg(msgHere('taskMsg'), 'Comment edited.', 'ok'); });
      });
    });
  }
  function removeComment(t, c, host) {
    if (!c) return;
    call('ops_remove_comment', { p_event: c.id, p_on: true }, msgHere('taskMsg'), function () {
      readTask(t.id, function () {
        undoBar('Comment deleted.', function () {
          call('ops_remove_comment', { p_event: c.id, p_on: false }, msgHere('taskMsg'), function () { readTask(t.id); });
        }, host);
      });
    });
  }

  /* One small form open in the sheet at a time, so there is one filled
     action beside the step's own, never three. */
  var CARD_FORMS = ['dwDescForm', 'dwCheckForm', 'dwLinkForm', 'dwCommentForm'];
  function openCardForm(id) {
    CARD_FORMS.forEach(function (f) { if (f !== id && $(f)) closeCardForm(f); });
    var form = $(id);
    if (!form) return;
    form.hidden = false;
    var opener = { dwDescForm: 'dwDescEdit', dwCheckForm: 'dwCheckOpen', dwLinkForm: 'dwLinkOpen', dwCommentForm: 'dwCommentOpen' }[id];
    if ($(opener)) $(opener).setAttribute('aria-expanded', 'true');
  }
  function closeCardForm(id) {
    var form = $(id);
    if (!form) return;
    form.hidden = true;
    Array.prototype.forEach.call(form.querySelectorAll('input, textarea'), function (x) { x.value = ''; });
    if (id === 'dwLinkForm') { linkEditing = null; $('dwLinkKind').value = 'other'; $('dwLinkSave').textContent = 'Add'; }
    var opener = { dwDescForm: 'dwDescEdit', dwCheckForm: 'dwCheckOpen', dwLinkForm: 'dwLinkOpen', dwCommentForm: 'dwCommentOpen' }[id];
    if ($(opener)) $(opener).setAttribute('aria-expanded', 'false');
  }
  /* The title is edited where it sits, the pen becoming the tick. A task with
     a code keeps its code; what is edited is the words after it. */
  function editSheetTitle() {
    var t = state.task;
    if (!t || !window.ADspaceAsk) return;
    var was = t.code ? (t.content_desc || '') : (t.content_desc || t.title || '');
    window.ADspaceAsk.rename($('dwTitle'), $('dwTitleEdit'), {
      label: 'Title', saveLabel: 'Save title', value: was,
      allowEmpty: Boolean(t.code), max: 160,
      save: function (v) {
        call('ops_set_content_desc', { p_task: t.id, p_desc: v, p_version: t.version }, 'dwMsg', function (d) {
          applyTask(d);
          readTask(t.id, function () { msg('dwMsg', 'Title saved.', 'ok'); });
        });
      }
    });
  }

  /* The words a stored link kind is read by. */
  var LINK_WORD = { draft: 'Draft', review: 'Review', final: 'Final', brief: 'Brief', asset: 'File', other: 'Link' };

  /* TIME, SAID ONCE AND BRIEFLY: how long it has been at this stage, how
     long since it was made, and the hours somebody recorded where there are
     any. The stage by stage table is the detail, opened on request. */
  function paintDrawerTime(t) {
    var spans = stageSpans();
    var here = spans.filter(function (x) { return x.running; })[0];
    var since = spans.reduce(function (a, x) { return a + x.mins; }, 0);
    var rec = (state.detail.sessions || []).reduce(function (a, x) { return a + (Number(x.minutes) || 0); }, 0);
    var rows = '';
    if (here && !isFinished(t)) rows += frow('In this stage', esc(spanWord(here.mins)));
    if (spans.length) rows += frow(isFinished(t) ? 'Start to finish' : 'Since created', esc(spanWord(since)));
    if (rec) rows += frow('Recorded', esc(minutesWord(rec)));
    $('dwTime').innerHTML = rows;
    var box = $('dwTimeList');
    box.innerHTML = '';
    if (spans.length) box.appendChild(stageTable(spans));
    $('dwTimeMore').hidden = spans.length < 2;
    $('dwTimeSec').hidden = !rows;
  }

  /* THE NEXT STEP, IN THE SHEET AND ON THE FULL RECORD ALIKE. One derived
     state, drawn by one function into either place, so the two can never
     say different things about the same task. */
  function NEXT_DW() {
    return { box: $('dwNext'), title: $('dwNextTitle'), line: $('dwNextLine'), list: $('dwNextList'),
             late: $('dwNextLate'), hand: $('dwHand'), tick: $('dwHandTick'), tickWrap: $('dwHandTickWrap'),
             lab: $('dwHandLab'), to: $('dwHandTo'), acts: $('dwActs'), rate: $('dwRate'), msg: 'dwMsg', ids: 'dw' };
  }
  function NEXT_REC() {
    return { box: $('taskNextStep'), title: $('taskNextTitle'), line: $('taskNextLine'), list: $('taskNextList'),
             late: $('taskNextLate'), hand: $('taskHand'), tick: $('taskHandTick'), tickWrap: $('taskHandTickWrap'),
             lab: $('taskHandLab'), to: $('taskHandTo'), acts: $('taskNextActs'), rate: $('taskRate'), msg: 'taskNextMsg', ids: 'task' };
  }
  function paintNext(b, t, n) {
    if (!b.box) return;
    b.box.classList.toggle('is-blocked', Boolean(n.blocked));
    b.title.textContent = n.title;
    b.line.textContent = n.line || '';
    b.line.hidden = !n.line;
    b.list.innerHTML = (n.list || []).map(function (w) { return '<li>' + esc(w) + '</li>'; }).join('');
    b.list.hidden = !(n.list || []).length;
    paintMonth(b, t, n);
    /* The final date is the day the work is owed AT CLIENT REVIEW, so the
       line says which of the two has happened. */
    var over = daysAway(t.current_final_due_at);
    b.late.hidden = !isLate(t);
    b.late.textContent = isLate(t)
      ? 'Late: ' + Math.abs(over) + (Math.abs(over) === 1 ? ' day' : ' days') + ' past final due, not yet at client review.'
      : '';
    paintHand(b, t, n);
    b.acts.innerHTML = '';
    if (n.go) b.acts.appendChild(actButton(n.go, true, b));
    if (n.alt) b.acts.appendChild(actButton(n.alt, false, b));
    b.acts.hidden = !n.go && !n.alt;
    paintRate(b, t, n);
  }
  /* WHO TAKES IT NEXT. A step is where work changes hands, so the step is
     where the Task Owner can change — optionally, with a tick, because most
     steps stay with the person who made them. A performance review goes back
     to whoever created the task unless somebody else is named, so that one
     names its reviewer rather than asking. */
  function paintHand(b, t, n) {
    if (!b.hand) return;
    var mv = n.go && n.go.move;
    var show = Boolean(mv) && may('ops', 'work');
    b.hand.hidden = !show;
    if (!show) return;
    var key = t.id + '|' + mv;
    var perf = mv === 'performance_review';
    if (b.hand.getAttribute('data-key') === key) return;
    b.hand.setAttribute('data-key', key);
    var cur = ownerId(t);
    b.to.innerHTML = '<option value="">Choose a person</option>' + state.members.filter(function (m) {
      return perf || m.id !== cur;
    }).map(function (m) {
      return '<option value="' + esc(m.id) + '">' + esc(m.name) + (m.id === t.created_by ? ' (created it)' : '') + '</option>';
    }).join('');
    var def = perf ? t.created_by : (mv === 'internal_review' && t.created_by !== cur ? t.created_by : '');
    b.to.value = def && b.to.querySelector('option[value="' + def + '"]') ? def : '';
    b.tick.checked = false;
    b.tickWrap.hidden = perf;
    b.lab.hidden = !perf;
    b.to.hidden = !perf;
  }
  function handOf(b) {
    if (!b || !b.hand || b.hand.hidden) return { who: null };
    if (!b.lab.hidden) return { who: b.to.value || null };
    if (!b.tick.checked) return { who: null };
    if (!b.to.value) return { missing: true };
    return { who: b.to.value };
  }
  /* A finished task is rated on the card that says it is finished: one to
     five, changeable, each rating a line in its history. */
  var STAR = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 3.2l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17.2l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z"/></svg>';
  function paintRate(b, t, n) {
    if (!b.rate) return;
    var show = Boolean(n.rate) && Boolean(t.completed_at);
    b.rate.hidden = !show;
    if (!show) return;
    var r = Number(t.rating) || 0;
    var can = may('ops', 'work');
    b.rate.innerHTML = '<p class="qrate-lab">' + (r ? 'Rated ' + r + ' of 5' + (t.rated_by ? ' by ' + esc(nameOf(t.rated_by) || '') : '') : 'How did it go?') + '</p>' +
      '<div class="qstars" role="group" aria-label="Rating">' + [1, 2, 3, 4, 5].map(function (k) {
        return '<button class="qstar' + (k <= r ? ' is-on' : '') + '" type="button" data-star="' + k + '" aria-pressed="' + (k === r) + '"' +
          (can ? '' : ' disabled') + ' aria-label="' + k + (k === 1 ? ' star' : ' stars') + '">' + STAR + '</button>';
      }).join('') + '</div>' +
      (t.rating_note ? '<p class="qrate-note">' + esc(t.rating_note) + '</p>' : '');
    Array.prototype.forEach.call(b.rate.querySelectorAll('[data-star]'), function (btn) {
      btn.addEventListener('click', function () {
        var k = Number(btn.getAttribute('data-star'));
        call('ops_rate_task', { p_task: t.id, p_rating: k, p_note: null }, b.msg, function () {
          readTask(t.id, function () { msg(b.msg, 'Rated ' + k + ' of 5.', 'ok'); });
        });
      });
    });
  }

  /* THE PUBLISH DATE, where the sheet prints it. */
  function inlinePublish(t, btn) {
    var inp = document.createElement('input');
    inp.type = 'date';
    inp.className = 'input input-sm tinline-pick';
    inp.setAttribute('aria-label', 'Scheduled publish date');
    inp.value = dateValue(t.publish_at);
    btn.hidden = true;
    btn.parentNode.appendChild(inp);
    inp.focus();
    if (inp.showPicker) { try { inp.showPicker(); } catch (e) {} }
    var put = function () { if (inp.parentNode) inp.remove(); btn.hidden = false; };
    inp.addEventListener('blur', function () { if (!inp.disabled) setTimeout(put, 150); });
    inp.addEventListener('keydown', function (e) { if (e.key === 'Escape') { e.stopPropagation(); put(); btn.focus(); } });
    inp.addEventListener('change', function () {
      if (inp.value === dateValue(t.publish_at)) return;
      inp.disabled = true;
      call('ops_set_publish_date', { p_task: t.id, p_at: inp.value ? inp.value + 'T00:00:00Z' : null, p_version: t.version }, 'dwMsg', function () {
        state.drawerDirty = true;
        readTask(t.id, function () { msg('dwMsg', 'Publish date saved.', 'ok'); });
      }, function () { inp.disabled = false; put(); });
    });
  }

  // ---- A step that needs something said ------------------------------------
  /* The moves the database will not make without a word or a date: a
     revision says what has to change, taking a post down says why, a
     schedule needs its date and going live is confirmed with the day it
     happened. Every other move is made on the press. */
  function needsSay(t, key) {
    var s = state.stages[t.workflow_id + '|' + key];
    if (!s) return false;
    if (s.stage_group === 'revision' && key !== 'changes_requested') return true;
    if (key === 'taken_down' || key === 'live') return true;
    if (key === 'scheduled' && !t.publish_at) return true;
    return false;
  }
  /* The moves that hand the work to somebody else carry the action colour;
     the ones that record the team's own progress are the ink primary. */
  function handsOff(key, t) {
    var s = state.stages[t.workflow_id + '|' + key];
    var g = s && s.stage_group;
    return g === 'internal_review' || g === 'client_review' || g === 'performance';
  }
  var stepCtx = null;
  function openStep(t, key, o) {
    o = o || {};
    var s = state.stages[t.workflow_id + '|' + key];
    var g = s && s.stage_group;
    stepCtx = { t: t, key: key, o: o };
    var verb = verbFor(key, t);
    $('stepTitle').textContent = verb;
    $('stepWhat').textContent = stageLabel(t) + ' to ' + labelOfStage(t, key) + '.';
    var live = key === 'live', sched = key === 'scheduled';
    $('stepDateRow').hidden = !(live || sched);
    $('stepDateLabel').textContent = live ? 'Date it went live' : 'Publish date';
    $('stepDate').value = live ? dateValue(new Date()) : dateValue(t.publish_at);
    if (live) $('stepDate').setAttribute('max', dateValue(new Date())); else $('stepDate').removeAttribute('max');
    $('stepWhy').value = '';
    $('stepLink').value = '';
    $('stepLinkRow').hidden = !live;
    stepDateChanged();
    var toClient = key === 'client_review' && o.note != null;
    var needNote = (g === 'revision' && key !== 'changes_requested') || key === 'taken_down' || toClient;
    $('stepNoteLabel').textContent = g === 'revision' ? 'What needs to change'
      : key === 'taken_down' ? 'Why it is taken down'
      : toClient ? 'How the draft was sent'
      : live ? 'Note (where it is posted, if there is no link)' : 'Note';
    $('stepNote').placeholder = needNote ? 'Required' : 'Optional';
    $('stepNote').value = toClient ? o.note : '';
    var perf = key === 'performance_review';
    var cur = state.ownerIds[t.id] || ownerId(t);
    $('stepHandTickWrap').hidden = perf;
    $('stepHandTick').checked = perf || Boolean(o.assignee);
    $('stepHandRow').hidden = !$('stepHandTick').checked;
    $('stepHandLabel').textContent = perf ? 'Performance review by' : 'New Task Owner';
    $('stepHandTo').innerHTML = '<option value="">Choose a person</option>' + state.members.filter(function (m) {
      return perf || m.id !== cur;
    }).map(function (m) {
      return '<option value="' + esc(m.id) + '">' + esc(m.name) + (m.id === t.created_by ? ' (created it)' : '') + '</option>';
    }).join('');
    $('stepHandTo').value = o.assignee || (perf ? t.created_by || '' : '');
    $('stepHand').hidden = !may('ops', 'work');
    var go = $('stepGo');
    go.textContent = verb;
    go.className = 'btn ' + (handsOff(key, t) ? 'btn-go' : 'btn-primary');
    go.disabled = false;
    msg('stepMsg', '');
    sheet('stepSheet', true);
  }
  /* Going live on a day other than the one it was scheduled for is allowed,
     and asks why, because a report that cannot see why a date moved cannot
     see replanning. */
  function stepDateChanged() {
    var c = stepCtx;
    var show = Boolean(c && c.key === 'live' && c.t.publish_at && $('stepDate').value &&
      $('stepDate').value !== dateValue(c.t.publish_at));
    $('stepWhyRow').hidden = !show;
    if (show) $('stepWhyLabel').textContent = 'Why not on ' + niceDate(c.t.publish_at) + ', the scheduled date';
  }
  function doStep() {
    var c = stepCtx;
    if (!c) return;
    var t = c.t, key = c.key;
    var s = state.stages[t.workflow_id + '|' + key];
    var g = s && s.stage_group;
    var note = String($('stepNote').value || '').trim();
    var toClient = key === 'client_review' && c.o.note != null;
    var needNote = (g === 'revision' && key !== 'changes_requested') || key === 'taken_down' || toClient;
    if (needNote && !note) {
      msg('stepMsg', g === 'revision' ? 'Say what needs to change.' : toClient ? 'Say how the draft was sent.' : 'Say why it is taken down.', 'err');
      $('stepNote').focus();
      return;
    }
    var who = null;
    if (key === 'performance_review' || $('stepHandTick').checked) {
      who = $('stepHandTo').value || null;
      if (!who && key !== 'performance_review') { msg('stepMsg', 'Choose the new Task Owner.', 'err'); $('stepHandTo').focus(); return; }
    }
    var btn = $('stepGo');
    btn.disabled = true;
    var fail = function (text) { btn.disabled = false; msg('stepMsg', text, 'err'); };
    var ok = function (d) { btn.disabled = false; sheet('stepSheet', false); stepDone(c, d, who); };
    var rpc = function (fn, args, then) {
      db.rpc(fn, args).then(function (r) {
        var d = r.data;
        if (r.error) { fail(r.error.message); return; }
        if (d && d.error) { fail(said(d.error, t)); return; }
        then(d);
      }, function (e) { fail((e && e.message) || String(e)); });
    };
    if (key === 'scheduled') {
      var day = $('stepDate').value;
      if (!day) { fail('Set the publish date.'); $('stepDate').focus(); return; }
      rpc('ops_set_publish_date', { p_task: t.id, p_at: day + 'T00:00:00Z', p_version: t.version }, function (d) {
        rpc('ops_transition_task', {
          p_task: t.id, p_next: key, p_version: d && d.version != null ? d.version : null,
          p_note: note || null, p_assignee: who
        }, ok);
      });
      return;
    }
    if (key === 'live') {
      var liveDay = $('stepDate').value;
      if (!liveDay) { fail('Confirm the date it went live.'); $('stepDate').focus(); return; }
      var why = String($('stepWhy').value || '').trim();
      if (t.publish_at && liveDay !== dateValue(t.publish_at) && !why) { fail(said('live-reason-required')); $('stepWhy').focus(); return; }
      var url = String($('stepLink').value || '').trim();
      if (url && !/^https?:\/\//i.test(url)) { fail('A link starts with https://'); $('stepLink').focus(); return; }
      var goLive = function (ver) {
        rpc('ops_mark_live', {
          p_task: t.id, p_live_at: liveDay + 'T00:00:00Z', p_reason: why || null,
          p_version: ver, p_assignee: who, p_note: note || null
        }, ok);
      };
      if (url) {
        rpc('ops_add_link', { p_task: t.id, p_kind: 'final', p_label: 'Live post', p_url: url, p_version: t.version }, function (d) {
          goLive(d && d.task && d.task.version != null ? d.task.version : null);
        });
      } else goLive(t.version);
      return;
    }
    rpc('ops_transition_task', { p_task: t.id, p_next: key, p_version: t.version, p_note: note || null, p_assignee: who }, ok);
  }
  function stepDone(c, d, who) {
    var t = c.t;
    if (who) { state.owners[t.id] = nameOf(who); state.ownerIds[t.id] = who; }
    if (state.task && state.task.id === t.id) {
      if (d && d.id) applyTask(d);
      if (state.drawer) state.drawerDirty = true;
      readTask(t.id, function () { msg(state.drawer ? 'dwMsg' : 'taskNextMsg', 'Moved to ' + labelOfStage(t, c.key) + '.', 'ok'); });
      return;
    }
    state.moved = { id: t.id, word: labelOfStage(t, c.key) };
    if (c.o.after) c.o.after(); else load();
  }

  // ---- Add task ------------------------------------------------------------
  /* WHAT, WHO AND WHEN, and it is made. Enter makes it and leaves the title
     field ready for the next, so a list of the week's tasks is typed in one
     go; the client and the month are named once, in More options, and the
     task takes them from there. */
  var qkKey = '', qkMade = 0;
  function linkOptions(sel, chosen) {
    var engs = (state.engList || []).slice().sort(function (a, b) {
      return String((a.clients && a.clients.name) || '').localeCompare(String((b.clients && b.clients.name) || '')) ||
        String(b.period).localeCompare(String(a.period));
    });
    var clients = state.clients.filter(function (c) { return c.stage === 'active' || c.stage === 'paused'; });
    sel.innerHTML = '<option value="">No client (internal)</option>' +
      (engs.length ? '<optgroup label="Engagements">' + engs.map(function (e) {
        var v = 'e:' + e.id;
        return '<option value="' + v + '"' + (v === chosen ? ' selected' : '') + '>' +
          esc(((e.clients && e.clients.name) || 'Client') + ' · ' + monthWord(e.period)) + '</option>';
      }).join('') + '</optgroup>' : '') +
      (clients.length ? '<optgroup label="Clients">' + clients.map(function (c) {
        var v = 'c:' + c.id;
        return '<option value="' + v + '"' + (v === chosen ? ' selected' : '') + '>' + esc(c.name) + '</option>';
      }).join('') + '</optgroup>' : '');
  }
  /* The engagements a task is most often made for: this month's, last
     month's and next month's. Read once and kept. */
  function loadEngs(then) {
    if (state.engList) { then(); return; }
    var d = new Date();
    var ks = [-1, 0, 1].map(function (k) { return monthKey(new Date(d.getFullYear(), d.getMonth() + k, 1)); });
    db.from('ops_engagements').select('id, client_id, period, status, clients(name, slug)').in('period', ks)
      .then(function (r) { state.engList = (!r.error && r.data) || []; then(); }, function () { state.engList = []; then(); });
  }
  function openQuick(pre, from) {
    if (!may('ops', 'work')) return;
    loadEngs(function () {
      var me = bridge.me && bridge.me();
      $('qkOwner').innerHTML = state.members.map(function (m) {
        return '<option value="' + esc(m.id) + '"' + (me && me.id === m.id ? ' selected' : '') + '>' + esc(m.name) + '</option>';
      }).join('');
      $('qkDue').value = dateValue(new Date());
      linkOptions($('qkLink'), pre && pre.link || '');
      $('qkMore').open = Boolean(pre && pre.link);
      $('qkTitle').value = ''; $('qkDesc').value = ''; $('qkCheck').value = ''; $('qkPri').value = '3';
      $('qkMade').innerHTML = '';
      qkMade = 0; qkKey = '';
      msg('qkMsg', '');
      /* Switched to from the content form, which stayed on the screen while
         the months were read: the two change places in one frame, so there
         is never a moment with no sheet and the page showing through. */
      if (from) { sheet(from, false); from = null; sheet('quickSheet', true, true); }
      else sheet('quickSheet', true);
      $('qkTitle').focus();
    });
  }
  function quickAdd() {
    var title = String($('qkTitle').value || '').trim();
    if (!title) { msg('qkMsg', 'Say what the task is.', 'err'); $('qkTitle').focus(); return; }
    if (!$('qkDue').value) { msg('qkMsg', 'A due date is required.', 'err'); $('qkDue').focus(); return; }
    var link = $('qkLink').value || '';
    var payload = {
      title: title, workflow_key: 'task',
      scope: link ? 'client' : 'internal',
      client_id: link.indexOf('c:') === 0 ? link.slice(2) : null,
      engagement_id: link.indexOf('e:') === 0 ? link.slice(2) : null,
      task_type: link.indexOf('e:') === 0 ? 'engagement' : 'adhoc',
      owner_id: $('qkOwner').value || null,
      final_due_at: $('qkDue').value + 'T00:00:00Z',
      description: String($('qkDesc').value || '').trim() || null,
      priority_level: Number($('qkPri').value) || 3,
      checklist: String($('qkCheck').value || '').split(/\n/).map(function (x) { return x.trim(); }).filter(Boolean)
    };
    if (!qkKey) qkKey = 'qk-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8);
    var btn = $('qkGo');
    btn.disabled = true;
    call('ops_create_task', { p_payload: payload, p_idem: qkKey }, 'qkMsg', function (t) {
      btn.disabled = false;
      qkKey = '';
      qkMade++;
      var li = document.createElement('li');
      li.innerHTML = '<span>Added</span> <b></b> <span class="mute"></span>';
      li.querySelector('b').textContent = t.title;
      li.querySelector('.mute').textContent = '· ' + (nameOf(payload.owner_id) || 'nobody') + ' · ' + shortDate(payload.final_due_at);
      $('qkMade').insertBefore(li, $('qkMade').firstChild);
      $('qkTitle').value = ''; $('qkDesc').value = ''; $('qkCheck').value = '';
      msg('qkMsg', '');
      $('qkTitle').focus();
    }, function () { btn.disabled = false; });
  }
  function closeQuick() {
    sheet('quickSheet', false);
    if (qkMade) load();
    qkMade = 0;
  }

  // ---- From template -------------------------------------------------------
  /* The tasks a month always needs, made at once and linked once. Each is a
     new task, so a template made a hundred times has a hundred histories. */
  var tplRows = [];
  function openTpl(pre) {
    if (!may('ops', 'work')) return;
    loadEngs(function () {
      db.from('ops_task_templates').select('*').order('name').then(function (r) {
        tplRows = (!r.error && r.data) || [];
        linkOptions($('tplLink'), pre && pre.link || '');
        $('tplBase').value = pre && pre.base ? pre.base : dateValue(new Date());
        $('tplNew').hidden = !may('ops.workflows', 'work');
        paintTplList();
        msg('tplMsg', r.error ? r.error.message : '', r.error ? 'err' : '');
        sheet('tplSheet', true);
      });
    });
  }
  function paintTplList() {
    var edit = may('ops.workflows', 'work');
    var rows = tplRows.filter(function (x) { return x.active || edit; });
    $('tplList').innerHTML = rows.length ? rows.map(function (x) {
      var bits = [
        x.due_offset_days != null ? 'Due ' + (Number(x.due_offset_days) === 0 ? 'the same day' : x.due_offset_days + (Number(x.due_offset_days) === 1 ? ' day' : ' days') + ' after') : '',
        x.default_owner_id ? nameOf(x.default_owner_id) : '',
        (x.checklist || []).length ? (x.checklist || []).length + ((x.checklist || []).length === 1 ? ' item' : ' items') : '',
        x.active ? '' : 'Not offered'
      ].filter(Boolean).join(' · ');
      return '<div class="tplrow">' +
        '<label class="tickline"><input type="checkbox" data-tpl="' + esc(x.id) + '"' + (x.active ? '' : ' disabled') + '> ' +
          '<span><b>' + esc(x.name) + '</b>' + (bits ? '<small>' + esc(bits) + '</small>' : '') + '</span></label>' +
        (edit ? '<button class="btn btn-quiet btn-sm" data-edit="' + esc(x.id) + '" type="button">Edit</button>' : '') +
        '</div>';
    }).join('') : '<p class="ovnote mute">No templates yet.</p>';
    Array.prototype.forEach.call($('tplList').querySelectorAll('[data-edit]'), function (b) {
      b.addEventListener('click', function () {
        openTplEdit(tplRows.filter(function (x) { return x.id === b.getAttribute('data-edit'); })[0]);
      });
    });
  }
  function tplCreate() {
    var picks = Array.prototype.map.call($('tplList').querySelectorAll('[data-tpl]:checked'), function (c) {
      return c.getAttribute('data-tpl');
    });
    if (!picks.length) { msg('tplMsg', 'Tick the templates to make.', 'err'); return; }
    var link = $('tplLink').value || '';
    var base = $('tplBase').value || dateValue(new Date());
    var btn = $('tplGo');
    btn.disabled = true;
    var made = 0, i = 0;
    var next = function () {
      if (i >= picks.length) {
        btn.disabled = false;
        sheet('tplSheet', false);
        msg('workMsg', made + (made === 1 ? ' task added.' : ' tasks added.'), 'ok');
        load();
        return;
      }
      var id = picks[i++];
      /* The key is what makes two presses the same act: this template, for
         this client or month, for this day. A second press makes nothing. */
      call('ops_create_task', {
        p_payload: {
          template_id: id,
          scope: link ? 'client' : 'internal',
          client_id: link.indexOf('c:') === 0 ? link.slice(2) : null,
          engagement_id: link.indexOf('e:') === 0 ? link.slice(2) : null,
          task_type: link.indexOf('e:') === 0 ? 'engagement' : 'adhoc',
          base_date: base + 'T00:00:00Z'
        },
        p_idem: 'tpl:' + id + ':' + (link || 'internal') + ':' + base
      }, 'tplMsg', function () { made++; next(); }, function () { btn.disabled = false; });
    };
    next();
  }
  var tplEditing = null;
  function openTplEdit(row) {
    tplEditing = row || null;
    var x = row || {};
    $('teHead').textContent = row ? 'Edit template' : 'New template';
    $('teName').value = x.name || '';
    $('teTitle').value = x.default_title || '';
    $('teOwner').innerHTML = '<option value="">Whoever makes it</option>' + state.members.map(function (m) {
      return '<option value="' + esc(m.id) + '"' + (m.id === x.default_owner_id ? ' selected' : '') + '>' + esc(m.name) + '</option>';
    }).join('');
    $('teDue').value = x.due_offset_days == null ? '' : String(x.due_offset_days);
    $('teEst').value = x.default_estimate_minutes == null ? '' : String(x.default_estimate_minutes);
    var w = (state.workflows || []).filter(function (f) { return f.id === x.workflow_id; })[0];
    $('teKind').value = w && w.key === 'content' ? 'content' : 'task';
    $('teCheck').value = (x.checklist || []).join('\n');
    $('teActive').checked = row ? Boolean(x.active) : true;
    msg('teMsg', '');
    sheet('tplEditSheet', true);
  }
  function tplSave() {
    var name = String($('teName').value || '').trim();
    if (!name) { msg('teMsg', 'A name is required.', 'err'); $('teName').focus(); return; }
    var btn = $('teGo');
    btn.disabled = true;
    call('ops_save_template', {
      p_id: tplEditing ? tplEditing.id : null,
      p_payload: {
        name: name,
        default_title: String($('teTitle').value || '').trim() || null,
        default_owner_id: $('teOwner').value || null,
        due_offset_days: $('teDue').value === '' ? null : Number($('teDue').value),
        default_estimate_minutes: $('teEst').value === '' ? null : Number($('teEst').value),
        workflow_key: $('teKind').value,
        checklist: String($('teCheck').value || '').split(/\n/).map(function (s) { return s.trim(); }).filter(Boolean),
        active: $('teActive').checked
      }
    }, 'teMsg', function (row) {
      btn.disabled = false;
      sheet('tplEditSheet', false);
      tplRows = tplRows.filter(function (x) { return x.id !== row.id; }).concat([row])
        .sort(function (a, b) { return String(a.name).localeCompare(String(b.name)); });
      paintTplList();
      sheet('tplSheet', true);
      msg('tplMsg', 'Template saved.', 'ok');
    }, function () { btn.disabled = false; });
  }

  // ---- Workload -------------------------------------------------------------
  /* Who is carrying what: one row a person, the counts a manager reads on a
     Monday. It is the team's queue, so it reads whatever the team's queue
     reads, and it adds nothing to any task's own row. */
  function paintLoad() {
    var box = $('workLoad');
    if (!box) return;
    box.innerHTML = '';
    var ws = weekStart().getTime();
    var by = {}, order = [];
    (state.tasks || []).forEach(function (t) {
      var id = state.ownerIds[t.id] || '';
      if (!by[id]) { by[id] = { name: state.owners[t.id] || 'No task owner', overdue: 0, today: 0, doing: 0, waiting: 0, review: 0, done: 0 }; order.push(id); }
      var r = by[id], n = daysAway(dueOf(t)), p = plainOf(t);
      if (isFinished(t)) {
        var at = new Date(t.completed_at || t.cancelled_at).getTime();
        if (t.completed_at && at >= ws) r.done++;
        return;
      }
      if (n !== null && n < 0) r.overdue++;
      if (n === 0) r.today++;
      if (p === 'doing') r.doing++;
      if (p === 'waiting') r.waiting++;
      if (p === 'review') r.review++;
    });
    order.sort(function (a, b) { return a ? (b ? by[a].name.localeCompare(by[b].name) : -1) : 1; });
    if (!order.length) { UI.emptyLine(box, 'No tasks.'); return; }
    var table = GRP.table('svc-row load-row', ['Task Owner', 'Overdue', 'Due today', 'In progress', 'Waiting', 'Review', 'Done this week']);
    order.forEach(function (id) {
      var r = by[id];
      var row = document.createElement('div');
      row.className = 'svc-row load-row';
      var cell = function (v, label, warn) {
        return '<span class="load-n' + (warn && v ? ' is-over' : '') + '"><span class="load-lab">' + label + '</span>' + (v || '<span class="mute">0</span>') + '</span>';
      };
      row.innerHTML = '<span class="svc-name"><b>' + esc(r.name) + '</b></span>' +
        cell(r.overdue, 'Overdue', true) + cell(r.today, 'Due today') + cell(r.doing, 'In progress') +
        cell(r.waiting, 'Waiting') + cell(r.review, 'Review') + cell(r.done, 'Done this week');
      table.appendChild(row);
    });
    box.appendChild(table);
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
      db.from('ops_tasks').select('*, clients(name, slug)').eq('id', id).single(),
      db.from('ops_task_checklist_items').select('*').eq('task_id', id).order('position'),
      db.from('ops_task_links').select('*').eq('task_id', id).order('created_at'),
      db.from('ops_work_sessions')
        .select('*, team_members!ops_work_sessions_team_member_id_fkey(name)')
        .eq('task_id', id).order('started_at', { ascending: false }),
      /* Enough history that a comment and the correction made to it a week
         later are both read. */
      db.from('ops_task_events').select('*').eq('task_id', id).order('created_at', { ascending: false }).limit(250),
      db.from('ops_task_assignees')
        .select('*, team_members!ops_task_assignees_team_member_id_fkey(name)')
        .eq('task_id', id).is('ended_at', null),
      db.from('ops_video_details').select('*').eq('task_id', id),
      /* The extension nobody has answered yet. Read with the task, because
         it is part of where the task stands and a second round trip would
         paint the rail twice. A refused read leaves no block rather than
         failing the record: the dates themselves are still true. */
      db.from('ops_due_requests').select('*').eq('task_id', id).eq('state', 'asked'),
      /* The live repeat rule set on this task, if any: the rail says so and
         the Repeat sheet opens on it. A refused read leaves no rule. */
      db.from('ops_recurring_rules').select('*').eq('source_task_id', id).eq('active', true)
    ]).then(function (r) {
      /* Who owns it is part of the record, so a refused read of the
         assignments is named rather than drawn as an unowned task. */
      var bad = r[0].error || (r[5] && r[5].error);
      if (bad || !r[0].data) {
        msg(msgHere('taskMsg'), (bad && bad.message) || 'That task could not be read.', 'err');
        return;
      }
      var t = r[0].data;
      state.due = (((r[7] && r[7].data) || [])[0]) || null;
      state.rule = (((r[8] && r[8].data) || [])[0]) || null;
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
      /* The month's engagement, where the task has one: production waits on
         it, so the rail says where it stands. Read after the task, because
         the task is what names it; a refused read leaves no block. */
      var go = function () { loadSession(function () { paintTask(); if (after) after(); }); };
      if (!t.engagement_id) { state.eng = null; state.engChecks = []; go(); return; }
      Promise.all([
        db.from('ops_engagements').select('*').eq('id', t.engagement_id),
        db.from('ops_engagement_checks').select('*').eq('engagement_id', t.engagement_id)
      ]).then(function (q) {
        state.eng = (q[0] && !q[0].error && q[0].data && q[0].data[0]) || null;
        state.engChecks = (q[1] && !q[1].error && q[1].data) || [];
        go();
      }, function () { state.eng = null; state.engChecks = []; go(); });
    }, function (e) {
      msg(msgHere('taskMsg'), (e && e.message) || String(e), 'err');
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
    var n = derive(t);
    paintIdentity(t, n);
    paintNextStep(t, n);
    paintOverview(t);
    paintChecklist();
    paintLinks();
    paintTime();
    paintLog();
    paintRail(t);
    paintMenu(t, n);
    paintDrawer(t);
    if (UI.fit) UI.fit();
  }

  function paintIdentity(t, n) {
    var mark = $('taskMark');
    /* The task number is what an invoice, a message and a spreadsheet row all
       name it by, so it heads the record in the token face and copies on a
       press, the way a serial does on the Register. */
    if (mark) {
      mark.textContent = serialOf(t);
      mark.setAttribute('aria-label', 'Copy ' + serialOf(t));
    }
    /* The name is the code and the description. The code is the database's
       and is drawn in the token face; the description is the team's, edited
       where it sits, and may be blank on a task that carries a code. A task
       from before the codes carries its old title as the description. */
    var code = $('taskCode'), desc = $('taskDesc');
    if (code) {
      code.textContent = t.code || '';
      code.hidden = !t.code;
    }
    if (desc) {
      var d = t.code ? (t.content_desc || '') : (t.content_desc || t.title || 'Untitled task');
      desc.textContent = d;
      desc.classList.toggle('is-blank', !d);
      if (!d) desc.textContent = 'No description';
    }
    var pen = $('taskDescEdit');
    if (pen) pen.hidden = !may('ops', 'work') || isFinished(t);
    /* Whose it is and what it makes. The owner is the rail's, named once
       under People, so the head does not say it a second time. */
    $('taskMeta').textContent = [
      whoseWord(t),
      metaFormat(t),
      TASK_TYPE_WORD[t.task_type] || ''
    ].filter(Boolean).join(' · ');
    var chip = $('taskStage');
    chip.className = 'chip ' + n.tone;
    chip.textContent = n.status;
    paintRun(t);
  }

  /* The timer is read beside the title while it runs, in minutes, because a
     second hand on a page somebody is working in is a distraction. */
  function paintRun(t) {
    var run = $('taskRun');
    if (!run) return;
    var s = state.session;
    var here = s && t && s.task_id === t.id;
    run.hidden = !here;
    run.textContent = here
      ? 'Working · ' + minutesWord(Math.round((Date.now() - new Date(s.started_at)) / 60000))
      : '';
  }

  // ---- One derived state ---------------------------------------------------
  /* WHERE THE TASK STANDS, SAID ONCE.
     The head's chip, the next-step panel, the stepper and the blockers are all
     drawn from this one object, built on every repaint from the task, its
     owner, its links and the month it belongs to. Nothing here is stored, so
     a revert cannot leave any of it lying.

     Two contradictions it exists to stop. A refusal to move to Ready used to
     say "needs an owner and a final due date" whichever of the two was
     missing, beside an owner the rail was naming. And the task's own stage
     "Content meeting scheduled" is a stage anybody can move to, while the
     meeting itself is the engagement's and is what production actually waits
     on, so the head could say scheduled while the month said not. The
     engagement is the truth, because it is what the database's gate reads. */
  function ownerName(t) {
    return (t.assignees || []).filter(function (a) { return a.responsibility === 'owner'; })
      .map(function (a) { return a.name; })[0] || '';
  }
  function engMeeting(e) {
    if (!e) return null;
    if (e.meeting_na) return 'na';
    if (!e.meeting_at) return 'none';
    return new Date(e.meeting_at).getTime() <= Date.now() ? 'held' : 'set';
  }
  function readyNeeds(t) {
    var out = [];
    if (!ownerId(t)) out.push('owner');
    if (!t.current_final_due_at) out.push('due');
    return out;
  }
  function productionNeeds(t) {
    var e = state.eng, out = [];
    if (!t.engagement_id || !e) return out;
    if (e.status === 'planning') out.push('planning');
    var mt = engMeeting(e);
    if (mt === 'none') out.push('meeting');
    else if (mt === 'set') out.push('meeting-held');
    return out;
  }
  /* The verb a move is named by: what the person is doing, not the stage it
     lands on. "Move to Ready for production" names a destination; "Mark
     ready" names the act. */
  function verbFor(key, t) {
    var s = state.stages[t.workflow_id + '|' + key];
    var g = s && s.stage_group;
    if (key === 'ready') return 'Mark ready';
    if (key === 'published') return 'Mark published';
    if (key === 'approved') return 'Mark approved';
    /* Both reviews send work back with the same two words; the step sheet
       names which loop it enters. A longer label wrapped in the half-width
       button a phone gives the card. */
    if (key === 'changes_requested' || g === 'revision') return 'Request changes';
    if (key === 'internal_review') return 'Send to AQC review';
    if (key === 'client_review' || g === 'client_review') return 'Send to client';
    if (key === 'scheduled') return 'Schedule';
    if (key === 'live') return 'Mark live';
    if (key === 'performance_review') return 'Review performance';
    if (key === 'taken_down') return 'Take down';
    if (key === 'completed') return 'Complete';
    if (g === 'internal_review') return 'Send for review';
    if (isWork(g)) return 'Mark in progress';
    if (g === 'ready') return 'Mark ready';
    if (g === 'delivered') return 'Mark delivered';
    if (g === 'done') return 'Complete task';
    if (g === 'waiting') return 'Put on hold';
    if (g === 'cancelled') return 'Cancel task';
    return (s && s.label) || sentence(key);
  }
  /* The stage the ordinary path goes to next. The workflow says which moves
     exist; this picks the one a person means. From planning that is Ready
     (the content meeting is the month's, not a stage anybody has to walk
     through); from a revision it is back to the review that sent it, never
     the nearest stage ahead; after a performance review it is Completed, and
     taking a post down is always the choice somebody makes and never the
     step a button offers first. */
  function nextOf(t) {
    var here = stageOf(t);
    var nexts = (here && here.next_stage_keys) || [];
    if (!here || !nexts.length) return null;
    var g = here.stage_group;
    if (g === 'intake' && nexts.indexOf('ready') > -1) return 'ready';
    if (t.stage_key === 'revision_internal' && nexts.indexOf('internal_review') > -1) return 'internal_review';
    if (t.stage_key === 'revision_client' && nexts.indexOf('client_review') > -1) return 'client_review';
    if (g === 'revision') {
      var act = nexts.filter(function (k) {
        var s = state.stages[t.workflow_id + '|' + k];
        return s && isWork(s.stage_group);
      })[0];
      if (act) return act;
    }
    if (g === 'performance' && nexts.indexOf('completed') > -1) return 'completed';
    var f = forwardOf(t, nexts);
    var fs = f && state.stages[t.workflow_id + '|' + f];
    return fs && !SIDE[fs.stage_group] ? f : null;
  }
  /* Every stage on the line, in the workflow's order. The lanes beside it
     and the two revision loops are not steps: they are where a task goes off
     the line and comes back. A post taken down is an ending somebody chose,
     and Published is the step Completed replaced, so each is on the line
     only for a task that is standing on it. */
  function lineOf(t) {
    var all = stagesOf(t.workflow_id);
    var hasCompleted = all.some(function (s) { return s.key === 'completed'; });
    return all.filter(function (s) {
      if (SIDE[s.stage_group] || s.stage_group === 'revision') return false;
      if (s.key === t.stage_key) return true;
      if (s.stage_group === 'taken_down') return false;
      if (s.key === 'published' && hasCompleted) return false;
      return true;
    });
  }
  /* Which round of a review or a revision this is, off the task's own
     history: the database writes the round on every move into one. */
  function roundOf(t) {
    var e = (state.detail.events || []).filter(function (x) {
      return x.event_type === 'stage_changed' && x.to_value && x.to_value.stage_key === t.stage_key;
    })[0];
    var r = e && e.detail && Number(e.detail.round);
    if (r) return r;
    return (state.detail.events || []).filter(function (x) {
      return x.event_type === 'stage_changed' && x.to_value && x.to_value.stage_key === t.stage_key;
    }).length || 1;
  }
  /* An action that moves the task: named for the act, toned by whether it
     hands the work to somebody else, and carrying the stage so the card can
     offer the Task Owner change on the same press. */
  function stepAct(t, key, label, tone) {
    return {
      label: label || verbFor(key, t), move: key,
      tone: tone || (handsOff(key, t) ? 'go' : ''),
      run: function (hand) { stepGo(t, key, hand); }
    };
  }
  /* The team sends drafts through each client's WhatsApp group, so a draft
     link is optional: the press that sends it records that it went there. */
  var WA_NOTE = 'Sent to the client on WhatsApp.';
  function linked() { return hasLink('draft') || hasLink('review'); }
  function waAct(t) {
    return {
      label: 'Sent on WhatsApp', move: 'client_review', tone: 'go',
      run: function (hand) { move('client_review', WA_NOTE, { assignee: hand && hand.who || null }); }
    };
  }
  function stepGo(t, key, hand) {
    var who = hand && hand.who || null;
    if (needsSay(t, key)) { openStep(t, key, { assignee: who }); return; }
    move(key, null, { assignee: who });
  }

  function derive(t) {
    var here = stageOf(t);
    var g = here ? here.stage_group : '';
    var work = may('ops', 'work'), manage = may('ops', 'manage');
    var n = {
      status: stageLabel(t), tone: stageTone(t),
      title: '', line: '', list: [], go: null, alt: null, blocked: false, rate: false
    };
    var mt = engMeeting(state.eng);
    /* The head says what is true of the meeting, not what the stage is
       called, where the two can differ. */
    if (t.stage_key === 'meeting_scheduled' && state.eng) {
      if (mt === 'none') { n.status = 'Meeting not scheduled'; n.tone = 'is-warn'; }
      else if (mt === 'na') n.status = 'No meeting this month';
      else if (mt === 'held') n.status = 'Meeting held';
      else n.status = 'Meeting ' + shortDate(state.eng.meeting_at);
    }

    if (isEveryday(t)) return deriveEveryday(t, n, work);
    if (t.cancelled_at) {
      n.title = 'Cancelled';
      n.line = 'Cancelled on ' + niceDate(t.cancelled_at) + '.';
      var why0 = lastNote('stage_changed', 'cancelled');
      if (why0) n.line += ' ' + why0;
      if (work && reopenTo(t)) n.alt = { label: 'Reopen', run: function () { askReopenTo(t); } };
      return n;
    }
    if (t.completed_at) {
      var down = g === 'taken_down';
      n.title = down ? 'Taken down' : 'Complete';
      n.line = (down ? 'Taken down on ' : 'Completed on ') + niceDate(t.completed_at) + '.';
      if (down) {
        var why = lastNote('stage_changed', t.stage_key);
        if (why) n.line += ' ' + why;
        if (work && hasNext(t, 'live')) n.alt = stepAct(t, 'live', 'Put it back live');
      }
      n.rate = true;
      return n;
    }
    var owner = ownerId(t);
    var assign = { label: 'Assign task owner', run: function () { factHere('dwOwnerChange', editOwner); } };
    var setDue = { label: 'Set due date', run: function () { factHere('dwDue', function () { editDate('final'); }); } };

    if (t.stage_key === 'blocked') {
      n.title = 'Blocked';
      n.line = 'Waiting on ' + (reasonWord(t.blocked_category) || 'something') +
        (t.blocked_note ? ': ' + t.blocked_note : '') + '.';
      var back = resumeTo(t);
      if (work && back) n.go = { label: 'Unblock', run: function () { move(back); } };
      return n;
    }
    if (g === 'waiting') {
      n.title = 'On hold';
      n.line = 'Pending next stage changes.';
      var res = resumeTo(t);
      if (work && res) n.go = { label: 'Resume', run: function () { move(res); } };
      return n;
    }

    var target = nextOf(t);
    /* Not ready for production: an owner and a final due date, which is the
       gate the database holds on Ready, and nothing else. */
    if (g === 'intake' || g === 'ready' || target === 'ready') {
      var need = readyNeeds(t);
      if (need.length) {
        n.blocked = true;
        n.title = 'Not ready to start';
        var words = { owner: 'Assign a task owner', due: 'Add a final due date' };
        n.list = need.length > 1 ? need.map(function (k) { return words[k]; }) : [];
        n.line = need.length > 1 ? 'Two items missing.'
          : (need[0] === 'owner' ? 'Assign a task owner to continue.' : 'Add a final due date to continue.');
        if (need[0] === 'owner') {
          if (manage) n.go = assign;
          else { n.line = 'Ask a manager to assign a task owner.'; if (need.length > 1 && work) n.go = setDue; }
        } else if (work) n.go = setDue;
        return n;
      }
    }
    if (!owner && work) {
      n.title = 'Nobody owns this task';
      n.line = manage ? 'Assign a task owner to continue.' : 'Ask a manager to assign a task owner.';
      if (manage) n.go = assign;
      return n;
    }

    /* The step itself. */
    if (g === 'intake' && target === 'ready') {
      n.title = 'Mark ready to start';
      n.line = 'Task owner and final due date set.';
      if (work) n.go = stepAct(t, 'ready');
      if (state.eng && mt === 'none' && work) {
        n.alt = { label: 'Schedule meeting', run: function () { openMeetFor(); } };
      }
      return n;
    }
    var tstage = target && state.stages[t.workflow_id + '|' + target];
    var tg = tstage && tstage.stage_group;
    if (isWork(tg) && !isWork(g) && g !== 'revision') {
      var pn = productionNeeds(t);
      if (pn.length) {
        /* The month is run from here: its two ticks, its meeting and
           Mark planning complete, so nobody leaves the task for the client
           record to open the work. */
        var eng = state.eng;
        var ck = checksOf(eng, state.engChecks);
        var open = ck.length - checksDone(ck);
        n.blocked = true;
        n.month = true;
        n.title = 'Not ready to start';
        n.line = open ? 'Tick ' + monthWord(eng.period) + '\u2019s readiness, then hold the content meeting.'
          : mt === 'none' ? 'Schedule the content meeting.'
          : mt === 'set' ? 'The work opens once the content meeting on ' + niceDate(eng.meeting_at) + ' is held.'
          : 'Readiness done and the meeting held.';
        if (work && !open && (mt === 'held' || mt === 'na') && eng.status === 'planning') {
          n.go = { label: 'Mark planning complete', run: function () { markMonthReady(t); } };
        }
        return n;
      }
      n.title = 'Start the work';
      n.line = 'Moves to ' + tstage.label + '.';
      if (work) n.go = stepAct(t, target);
      return n;
    }
    var round = (g === 'internal_review' || g === 'client_review' || g === 'revision') ? roundOf(t) : 0;
    var roundWord = round > 1 ? ', round ' + round : '';
    /* In progress, heading for AQC review: the work is sent to whoever
       checks it, with the draft the check needs. */
    if (isWork(g) && target === 'internal_review') {
      n.title = 'Send to AQC review';
      n.line = 'Send it for review when the draft is ready.';
      if (work) n.go = stepAct(t, 'internal_review');
      return n;
    }
    /* AQC review: pass it to the client, or send it back with what to
       change. The client sees the work only once it has passed. */
    if (g === 'internal_review') {
      n.title = 'AQC review' + roundWord;
      /* The draft goes to the client as the link on the task, or through the
         client's WhatsApp group; the press records which. */
      n.line = linked() || target !== 'client_review'
        ? 'Pass it to the client, or send it back with what to change.'
        : 'Pass it to the client on WhatsApp, or send it back with what to change.';
      if (work && target === 'client_review') n.go = linked() ? stepAct(t, target, 'Pass to client') : waAct(t);
      else if (work && target) n.go = stepAct(t, target);
      if (work && hasNext(t, 'revision_internal')) n.alt = stepAct(t, 'revision_internal');
      else if (work && hasNext(t, 'changes_requested')) n.alt = { label: 'Request changes', run: function () { askChanges(); } };
      return n;
    }
    if (g === 'revision') {
      var asked = lastNote('stage_changed', t.stage_key);
      if (t.stage_key === 'revision_internal' || t.stage_key === 'revision_client') {
        n.title = stageLabel(t) + roundWord;
        n.line = asked ? 'Requested: ' + asked : 'Make the changes, then send it back.';
        if (work && target === 'client_review' && !linked()) n.go = waAct(t);
        else if (work && target) n.go = stepAct(t, target);
        if (work && t.stage_key === 'revision_client' && hasNext(t, 'internal_review')) n.alt = stepAct(t, 'internal_review');
        return n;
      }
      n.title = 'Changes requested';
      n.line = asked ? 'Requested: ' + asked : 'Make the changes, then resend for review.';
      if (work && target) n.go = stepAct(t, target, 'Resume work');
      return n;
    }
    if (tg === 'client_review' || (tstage && tstage.key === 'client_review')) {
      n.title = 'Send to the client';
      n.line = linked() ? 'Send once it passes review.' : 'Send it on WhatsApp, or add the draft link below.';
      if (work) n.go = linked() ? stepAct(t, target) : waAct(t);
      if (work && hasNext(t, 'changes_requested')) n.alt = { label: 'Request changes', run: function () { askChanges(); } };
      return n;
    }
    if (isWork(g)) {
      var toWork = isWork(tg);
      n.title = toWork ? 'Next: ' + labelForKey(target) : 'Finish the draft';
      n.line = toWork ? 'Move on when this step is done.' : 'Send for review when ready.';
      if (work && target) n.go = stepAct(t, target, toWork ? 'Start ' + labelForKey(target).toLowerCase() : null);
      return n;
    }
    if (g === 'client_review') {
      n.title = 'Client review' + roundWord;
      n.line = 'Record the client\'s decision.';
      if (work && target) n.go = stepAct(t, target);
      if (work && hasNext(t, 'revision_client')) n.alt = stepAct(t, 'revision_client');
      else if (work && hasNext(t, 'changes_requested')) n.alt = { label: 'Request changes', run: function () { askChanges(); } };
      return n;
    }
    /* After the client said yes: a date to go out on, then the day it went
       out, then three days on, how it performed. */
    if (g === 'approved' && hasNext(t, 'scheduled')) {
      n.title = 'Approved';
      n.line = t.publish_at ? 'Scheduled publish date ' + niceDate(t.publish_at) + '.' : 'Set the publish date to schedule it.';
      if (work) n.go = stepAct(t, 'scheduled');
      if (work && hasNext(t, 'live')) n.alt = stepAct(t, 'live');
      return n;
    }
    if (g === 'scheduled') {
      var dn = daysAway(t.publish_at);
      n.title = 'Scheduled';
      n.line = t.publish_at
        ? (dn < 0 ? 'Was due out ' + niceDate(t.publish_at) + '. Confirm when it went live.'
          : dn === 0 ? 'Goes live today.' : 'Goes live ' + niceDate(t.publish_at) + '.')
        : 'No publish date set.';
      if (work && hasNext(t, 'live')) n.go = stepAct(t, 'live');
      return n;
    }
    if (g === 'live') {
      var rev = t.live_at ? plusDays(t.live_at, REVIEW_AFTER_DAYS) : null;
      var rn = daysAway(rev);
      n.title = 'Live';
      n.line = t.live_at
        ? 'Live since ' + niceDate(t.live_at) + '. ' + (rn !== null && rn > 0
            ? 'Review its performance from ' + niceDate(rev) + '.'
            : 'Its performance is due for review.')
        : 'Live.';
      if (work && hasNext(t, 'performance_review')) n.go = stepAct(t, 'performance_review');
      if (work && hasNext(t, 'taken_down')) n.alt = stepAct(t, 'taken_down');
      return n;
    }
    if (g === 'performance') {
      var req = state.detail.checklist.filter(function (c) { return c.required; });
      var open = req.filter(function (c) { return !c.completed_at; }).length;
      n.title = 'Performance review';
      n.line = open ? open + ' of ' + req.length + ' checks to go. Keep it live, or take it down if it is not working.'
        : 'Checks done. Complete it, or take it down.';
      if (work && !open && hasNext(t, 'completed')) n.go = stepAct(t, 'completed');
      if (work && hasNext(t, 'taken_down')) n.alt = stepAct(t, 'taken_down');
      return n;
    }
    if (target === 'published' || tg === 'delivered') {
      var finalKind = target === 'published' ? 'publish' : 'deliver';
      if (target === 'published' && !t.publish_at) {
        n.title = 'Schedule publishing';
        n.line = 'Set the agreed publish date.';
        if (work) n.go = { label: 'Schedule', run: function () { factHere('dwPublish', function () { editDate('publish'); }); } };
        if (work && hasLink('final')) n.alt = stepAct(t, target);
        return n;
      }
      if (!hasLink('final')) {
        n.blocked = true;
        n.title = finalKind === 'publish' ? 'Not ready to publish' : 'Not ready to deliver';
        n.line = 'Add the final link.';
        if (work) n.go = { label: 'Add final link', run: function () { addLinkHere('final'); } };
        return n;
      }
      n.title = finalKind === 'publish' ? 'Publish' : 'Deliver';
      n.line = t.publish_at ? 'Scheduled for ' + niceDate(t.publish_at) + '.' : 'Final link attached.';
      if (work) n.go = stepAct(t, target);
      return n;
    }
    if (tg === 'done' && !t.delivered_at && target !== 'completed') {
      n.title = 'Complete the task';
      n.line = 'No delivery recorded. A reason is required.';
      if (work) n.go = { label: 'Complete task', run: function () { askComplete(target); } };
      return n;
    }
    if (target) {
      n.title = tstage ? tstage.label : sentence(target);
      n.line = 'Next workflow step.';
      if (work) n.go = stepAct(t, target);
      return n;
    }
    n.title = stageLabel(t);
    n.line = 'No further steps.';
    return n;
  }
  /* An everyday task's next step is one of five words, and the button is the
     act: mark it in progress, finish it, send it for review, pick it up again. */
  function deriveEveryday(t, n, work) {
    var p = plainOf(t);
    n.status = PLAIN[p].word; n.tone = PLAIN[p].tone;
    /* An everyday task changes hands from its Task Owner row, not on a
       step: its steps are one person's day. */
    var go = function (label, key, tone) {
      return { label: label, tone: tone || '', run: function () { move(key); } };
    };
    if (p === 'cancelled') { n.title = 'Cancelled'; n.line = 'Cancelled on ' + niceDate(t.cancelled_at) + '.';
      if (work && reopenTo(t)) n.alt = { label: 'Reopen', run: function () { askReopenTo(t); } }; return n; }
    if (p === 'done') { n.title = 'Done'; n.line = 'Completed on ' + niceDate(t.completed_at) + '.'; n.rate = true;
      if (work) n.alt = { label: 'Reopen', run: function () { move('todo'); } }; return n; }
    if (!ownerId(t)) {
      n.title = 'Nobody owns this task';
      n.line = may('ops', 'manage') ? 'Assign a task owner to continue.' : 'Ask a manager to assign a task owner.';
    }
    if (!work) return n;
    if (p === 'todo') { n.title = n.title || 'To do'; n.go = go('Mark in progress', 'doing'); n.alt = go('Mark complete', 'complete'); }
    else if (p === 'doing') { n.title = n.title || 'In progress'; n.go = go('Mark complete', 'complete'); n.alt = go('Send for review', 'review'); }
    else if (p === 'waiting') { n.title = n.title || 'Waiting'; n.line = n.line || 'Pending next stage changes.'; n.go = go('Resume', 'doing'); n.alt = go('Mark complete', 'complete'); }
    else if (p === 'review') {
      n.title = n.title || 'Ready for review';
      n.go = go('Approve', 'complete');
      n.alt = { label: 'Request changes', run: function () {
        ADspaceConfirm.ask({ title: 'Request changes', body: 'Returns it to In progress and notifies the task owner.',
          go: 'Request changes', field: { label: 'What needs to change', rows: 3, need: 'Say what needs to change.' }
        }, function (why) { move('doing', why); });
      } };
    }
    return n;
  }
  /* A step that changes a fact uses the control the reader is looking at:
     the sheet's own row while the sheet is open, the record's otherwise. The
     step card reached for the record's controls from the sheet, where they
     are not on the screen, so Assign task owner and Set due date did
     nothing. A fact the sheet does not draw opens the full record. */
  function factHere(id, onRecord) {
    if (!state.drawer) { onRecord(); return; }
    var b = $(id);
    if (b) {
      try { b.scrollIntoView({ block: 'center' }); } catch (e) {}
      b.click();
      return;
    }
    openFull(state.drawer);
  }
  /* The two seeded workflows name their working stages `in_progress`; the
     content workflow names its own `active`. Both are the work in hand. */
  function isWork(g) { return g === 'active' || g === 'in_progress'; }
  function hasNext(t, key) {
    var s = stageOf(t);
    return Boolean(s && (s.next_stage_keys || []).indexOf(key) > -1);
  }
  /* Where a task comes back to from Blocked or On hold: the stage it left, if
     the workflow still allows the move, else the first stage on the line it
     may go to. */
  function resumeTo(t) {
    var s = stageOf(t);
    var nexts = (s && s.next_stage_keys) || [];
    var from = cameFrom(t);
    if (from && nexts.indexOf(from) > -1) return from;
    return nexts.filter(function (k) {
      var x = state.stages[t.workflow_id + '|' + k];
      return x && !SIDE[x.stage_group];
    })[0] || null;
  }
  function lastNote(type, toKey) {
    var e = (state.detail.events || []).filter(function (x) {
      return x.event_type === type && (!toKey || (x.to_value && x.to_value.stage_key === toKey));
    })[0];
    return (e && e.detail && e.detail.note) || '';
  }
  function monthLink(t) {
    var slug = t.clients && t.clients.slug;
    if (!slug) return null;
    return { label: 'Open the month', href: '/admin/?s=clients&client=' + encodeURIComponent(slug) + '&tab=work' };
  }
  /* The link a gate asks for is added where the reader is: in the sheet's
     own form, or the record's. */
  function addLinkHere(kind) {
    if (state.drawer) {
      openCardForm('dwLinkForm');
      var k = $('dwLinkKind'), u = $('dwLinkUrl');
      if (k) k.value = kind;
      if (u) { try { u.scrollIntoView({ block: 'center' }); } catch (e) {} u.focus(); }
      return;
    }
    openLinkForm(kind);
  }
  /* A timer is kept for the person who wants their own hours on a task, from
     the full record's ⋯. Stage time is what tracks the work. */
  function timerAct(t) {
    var s = state.session;
    if (s && s.task_id === t.id) {
      return { label: 'Stop timer', run: function () {
        call('ops_stop_work', { p_session: s.id, p_note: null }, msgHere('taskMsg'), function () {
          stopTick(); readTask(t.id);
        });
      } };
    }
    return { label: 'Start timer', run: function () { startWork(t); } };
  }
  /* One open session a person across every task: starting here stops the one
     running elsewhere. */
  function startWork(t, then) {
    call('ops_start_work', { p_task: t.id }, msgHere('taskMsg'), function () {
      loadSession(function () { startTick(); if (then) then(); else paintTask(); });
    });
  }

  // ---- The next step -------------------------------------------------------
  function paintNextStep(t, n) {
    paintSteps(t);
    paintNext(NEXT_REC(), t, n);
  }
  /* One filled action and one outlined beside it. Blue only where the move
     hands the work to somebody else; everything the team records about its
     own progress is the ink primary, as Add and Save are. */
  function actButton(a, primary, b) {
    var el;
    if (a.href) {
      el = document.createElement('a');
      el.href = a.href;
    } else {
      el = document.createElement('button');
      el.type = 'button';
      el.addEventListener('click', function () {
        var hand = handOf(b);
        if (hand.missing) { msg(b ? b.msg : msgHere(), 'Choose the new Task Owner.', 'err'); if (b && b.to) b.to.focus(); return; }
        a.run(hand);
      });
    }
    el.className = 'btn ' + (primary ? (a.tone === 'go' ? 'btn-go' : 'btn-primary') : '');
    el.textContent = a.label;
    var pre = (b && b.ids) || 'task';
    el.id = pre + (primary ? 'Go' : 'Alt');
    return el;
  }

  /* The workflow as a row of steps: done quiet, current named, next said. Not
     buttons: moving a stage is the next step's job, and any other move is in
     the ⋯ where it asks for a reason. */
  function paintSteps(t) {
    var box = $('taskSteps');
    var line = lineOf(t);
    var here = stageOf(t);
    var at = -1;
    if (here) {
      at = line.map(function (s) { return s.key; }).indexOf(here.key);
      if (at < 0 && here.stage_group === 'revision') {
        at = line.map(function (s) { return isWork(s.stage_group); }).indexOf(true);
      }
      if (at < 0) {
        var from = cameFrom(t);
        at = line.map(function (s) { return s.key; }).indexOf(from);
      }
    }
    if (!line.length || at < 0) { box.innerHTML = ''; box.hidden = true; return; }
    box.hidden = false;
    var target = nextOf(t);
    var done = isFinished(t) && !t.cancelled_at;
    var word = function (s) { return stepWord(s, state.eng); };
    box.innerHTML =
      '<ol class="tsteps-bar" aria-label="Workflow">' + line.map(function (s, i) {
        var cls = (done || i < at) ? 'is-done' : i === at ? 'is-now' : '';
        var said = word(s) + ((done || i < at) ? ', done' : i === at ? ', current' : '');
        return '<li class="' + cls + '"' + (i === at ? ' aria-current="step"' : '') + '><span class="sr">' + esc(said) + '</span></li>';
      }).join('') + '</ol>' +
      '<p class="tsteps-word">Step ' + (at + 1) + ' of ' + line.length + ' · <b>' + esc(word(line[at])) + '</b>' +
        (target && !done && target !== line[at].key
          ? '<span class="tsteps-next"> · Next: ' + esc(labelForKey(target)) + '</span>' : '') + '</p>';
  }
  function ownerId(t) {
    var a = (t.assignees || []).filter(function (x) { return x.responsibility === 'owner'; })[0];
    return (a && a.team_member_id) || null;
  }
  function hasLink(kind) {
    return state.detail.links.some(function (l) { return l.kind === kind && !l.archived_at; });
  }

  // ---- Overview ------------------------------------------------------------
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
    /* A section with nothing in it is not drawn: an empty brief printed "No
       brief was written." on every task made from a generated month. */
    var brief = (t.description || t.remarks)
      ? '<p class="ovnote">' + esc(t.description || '') + '</p>' +
        (t.remarks ? '<p class="ovnote mute">' + esc(t.remarks) + '</p>' : '')
      : '';

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

    var canBrief = may('ops', 'work') && !isFinished(t);
    box.innerHTML =
      (brief || canBrief ? '<section class="tsec"><div class="tsec-head"><h3 class="tsec-title">Brief</h3>' +
        (canBrief ? '<button class="btn btn-quiet btn-sm" data-a="brief" type="button">' + (t.description ? 'Edit' : 'Add') + '</button>' : '') +
        '</div>' + (brief || '<p class="qempty">No brief.</p>') + '</section>' : '') +
      (v ? '<section class="tsec"><div class="tsec-head"><h3 class="tsec-title">Video</h3>' +
        (may('ops', 'work')
          ? '<button class="btn btn-quiet btn-sm" data-a="footage" type="button">' +
            (v.footage_ready ? 'Mark footage not ready' : 'Mark footage ready') + '</button>' : '') +
        '</div>' + video + '</section>' : '');

    var bf = box.querySelector('[data-a="brief"]');
    if (bf) bf.addEventListener('click', function () {
      ADspaceConfirm.ask({
        title: t.description ? 'Edit brief' : 'Add brief', go: 'Save',
        field: { label: 'Brief', rows: 5, value: t.description || '', required: false }
      }, function (v) {
        call('ops_update_task', { p_task: t.id, p_payload: { description: v }, p_version: t.version }, 'taskMsg', function () {
          readTask(t.id, function () { msg('taskMsg', 'Brief saved.', 'ok'); });
        });
      });
    });
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
    var sec = $('taskCheckSec');
    if (sec) sec.hidden = !items.length;
    if (!items.length) { box.innerHTML = ''; return; }
    var can = may('ops', 'work');
    var t0 = state.task;
    var fin0 = t0 && isFinished(t0);
    box.innerHTML = '<div class="softpanel">' + items.map(function (c) {
      return '<div class="qitem qitem-mid" data-row="' + esc(c.id) + '"><label class="checkrow' + (c.completed_at ? ' is-done' : '') + '">' +
        '<input type="checkbox" data-item="' + esc(c.id) + '"' +
          (c.completed_at ? ' checked' : '') + (can ? '' : ' disabled') + '>' +
        '<span class="checkrow-label">' + esc(c.label) +
          (c.required ? ' <span class="tone is-warn">Required</span>' : '') + '</span>' +
        '<span class="checkrow-when">' + esc(c.completed_at ? niceTime(c.completed_at) : '') + '</span>' +
        '</label>' + (can && !fin0 && !c.required ? itemMenu(c.label, [['rename', 'Rename'], ['remove', 'Remove', true]]) : '') + '</div>';
    }).join('') + '</div>';
    Array.prototype.forEach.call(box.querySelectorAll('.qitem'), function (row) {
      var c = items.filter(function (x) { return x.id === row.getAttribute('data-row'); })[0];
      wireItemMenu(row, function (a) {
        if (a === 'rename') renameItem(state.task, c);
        if (a === 'remove') removeItem(state.task, c, $('taskCheck'), 'taskMsg');
      });
    });
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
          }, function () { cb.checked = !want; });
      });
    });
  }

  // ---- Links ---------------------------------------------------------------
  function paintLinks() {
    var box = $('taskLinks');
    if (!box) return;
    var live = state.detail.links.filter(function (l) { return !l.archived_at; });
    /* A section with nothing says so in one line, because an empty heading
       reads as a fault; Add link beside the heading is the way in. */
    if (!live.length) {
      box.innerHTML = '<p class="ovnote mute">No files or links.</p>';
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
          /* Correcting and taking off are the row's ⋯, as they are in the
             sheet: one way to change a link wherever it is drawn. */
          (can ? itemMenu(l.label || l.url, [['edit', 'Edit'], ['remove', 'Remove', true]]) : '') +
        '</span>';
      /* The ⋯ acts on this link. */
      wireItemMenu(row, function (a) {
        if (a === 'remove') { removeLink(l.id); return; }
        if (a !== 'edit') return;
        openLinkForm(l.kind);
        recLinkEditing = l.id;
        $('taskLinkUrl').value = l.url || '';
        $('taskLinkLabel').value = l.label || '';
        $('taskLinkSave').textContent = 'Save';
      });
      table.appendChild(row);
    });
    box.appendChild(table);
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

  var recLinkEditing = null;
  function openLinkForm(kind) {
    showPane('work', true);
    recLinkEditing = null;
    $('taskLinkSave').textContent = 'Save';
    $('taskLinkForm').hidden = false;
    if (typeof kind === 'string') $('taskLinkKind').value = kind;
    $('taskLinkUrl').value = '';
    $('taskLinkLabel').value = '';
    msg('taskLinkMsg', '');
    $('taskLinkUrl').focus();
  }

  // ---- Time ----------------------------------------------------------------
  /* HOW LONG THE WORK SAT IN EACH STAGE.
     The question a person actually asks of a task is not "who had the timer
     running" but "how long was this in Shooting" — so that is what the pane
     leads with. Nothing new is recorded for it: every stage change is already
     an `ops_task_events` row the record has read, and the durations fall out
     of walking them in order.

     A session somebody started and stopped is a different measure and stays
     below, named for what it is. The two are never summed, which is the rule
     this system has carried since phase 1: cycle time, stage time and active
     work are three things. */
  function stageSpans() {
    var ev = (state.detail.events || []).filter(function (e) {
      return e.event_type === 'stage_changed' || e.event_type === 'task_created';
    }).slice().sort(function (a, b) {
      return new Date(a.created_at) - new Date(b.created_at);
    });
    if (!ev.length) return [];
    var spans = [], open = null;
    ev.forEach(function (e) {
      var at = new Date(e.created_at).getTime();
      var to = (e.to_value && e.to_value.stage_key) || null;
      /* The creation event names the stage the task started in; where it does
         not, the first move's `from` does, which is the same fact. */
      if (!to && e.event_type === 'task_created') {
        to = (e.to_value && e.to_value.stage_key) || null;
      }
      if (open) { open.to = at; spans.push(open); open = null; }
      if (to) open = { key: to, from: at, to: null };
    });
    if (!open && ev.length) {
      var first = ev[0];
      if (first.from_value && first.from_value.stage_key) {
        open = { key: first.from_value.stage_key, from: new Date(first.created_at).getTime(), to: null };
      }
    }
    if (open) {
      var t = state.task;
      var end = t && (t.completed_at || t.cancelled_at);
      open.to = end ? new Date(end).getTime() : Date.now();
      open.running = !end;
      spans.push(open);
    }
    /* One row a stage, not one row a visit: a task that went back for a
       revision and forward again spent its time in that stage twice, and the
       figure being read is the total. The number of visits is worth saying,
       because three visits to Revision is the finding. */
    var by = {}, order = [];
    spans.forEach(function (s) {
      var mins = Math.max(0, Math.round((s.to - s.from) / 60000));
      if (!by[s.key]) { by[s.key] = { key: s.key, mins: 0, visits: 0, running: false }; order.push(s.key); }
      by[s.key].mins += mins;
      by[s.key].visits += 1;
      if (s.running) by[s.key].running = true;
    });
    return order.map(function (k) { return by[k]; });
  }

  /* One row a stage, with how many times the work came back to it: three
     visits to a revision is the finding, and the figure is the total. */
  function stageTable(spans) {
    var st = GRP.table('svc-row tsess-row', ['Stage', 'Visits', 'Time']);
    spans.forEach(function (s) {
      var row = document.createElement('div');
      row.className = 'svc-row tsess-row';
      row.innerHTML =
        '<span class="svc-name"><b>' + esc(labelForKey(s.key)) + '</b>' +
          (s.running ? '<small>still here</small>' : '') + '</span>' +
        '<span class="tsess-who">' + (s.visits > 1 ? esc(String(s.visits)) : '') + '</span>' +
        '<span class="tsess-mins">' + esc(minutesWord(s.mins)) + '</span>';
      st.appendChild(row);
    });
    var since = spans.reduce(function (a, s) { return a + s.mins; }, 0);
    var cyc = document.createElement('div');
    cyc.className = 'svc-row tsess-row is-total';
    cyc.innerHTML = '<span class="svc-name"><b>Since it was created</b></span>' +
      '<span class="tsess-who"></span><span class="tsess-mins">' + esc(minutesWord(since)) + '</span>';
    st.appendChild(cyc);
    return st;
  }
  function paintTime() {
    var box = $('taskTime');
    if (!box) return;
    box.innerHTML = '';

    var spans = stageSpans();
    if (spans.length) {
      var head = document.createElement('h3');
      head.className = 'ovsec-title';
      head.textContent = 'Time in each stage';
      box.appendChild(head);
      box.appendChild(stageTable(spans));
    }

    var rows = state.detail.sessions;
    var mins = rows.reduce(function (a, s) { return a + (Number(s.minutes) || 0); }, 0);
    var h2 = document.createElement('h3');
    h2.className = 'ovsec-title';
    h2.textContent = 'Recorded work';
    box.appendChild(h2);
    if (!rows.length) {
      var sub = document.createElement('div');
      box.appendChild(sub);
      UI.emptyLine(sub, 'No recorded work.');
      return;
    }
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
    assignment_changed: 'Owner changed', handover: 'Handed on', contributor_changed: 'Contributors changed',
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
    due_declined: 'Extension declined',
    renamed: 'Description changed', stage_skipped: 'Step skipped',
    recurrence_set: 'Recurrence set', recurrence_off: 'Recurrence stopped',
    publish_changed: 'Publish date changed', commented: 'Comment',
    live_confirmed: 'Went live', rated: 'Rated',
    details_changed: 'Details changed', file_changed: 'Link changed',
    comment_edited: 'Comment edited', comment_removed: 'Comment deleted', comment_restored: 'Comment restored'
  };
  /* The reason a date moved is a stored key and the sheet offers a word for
     it; the record printed the key. Named once, with sentence case as the
     fallback so a category added next year is still a word. */
  var REASON_WORD = {
    client_request: 'Client request', scope_change: 'Scope change',
    capacity: 'Internal capacity', pending_assets: 'Pending assets',
    pending_confirmation: 'Pending confirmation', correction: 'Incorrect date listed',
    initial: 'First set', rescheduled: 'Rescheduled'
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
      /* A review and a revision say which round they are, because the second
         time round is the finding. */
      return (from.stage_key ? labelForKey(from.stage_key) + ' to ' : '') + labelForKey(to.stage_key) +
        (Number(d.round) > 1 ? ', round ' + d.round : '') +
        (d.skip_reason ? ' · skipped: ' + d.skip_reason : '') + (d.note ? ' · ' + d.note : '');
    }
    if (e.event_type === 'live_confirmed') {
      return niceDate(to.live_at) + (from.scheduled && dateValue(from.scheduled) !== dateValue(to.live_at)
        ? ', scheduled ' + niceDate(from.scheduled) : '') + (d.reason ? ' · ' + d.reason : '');
    }
    if (e.event_type === 'rated') {
      return (from.rating ? from.rating + ' to ' : '') + to.rating + ' of 5' + (d.note ? ' · ' + d.note : '');
    }
    if (e.event_type === 'publish_changed') {
      return (from.value ? niceDate(from.value) + ' to ' : '') + (to.value ? niceDate(to.value) : 'none');
    }
    /* Who skipped what and why is written against every stage passed over. */
    if (e.event_type === 'stage_skipped') {
      return labelForKey(from.stage_key) + (d.reason ? ' · ' + d.reason : '');
    }
    if (e.event_type === 'renamed') {
      return (from.content_desc ? '"' + from.content_desc + '" to ' : '') + '"' + (to.content_desc || '') + '"';
    }
    /* A hand-on is an owner change made on a stage move, and reads as one:
       who to, at which step. */
    if (e.event_type === 'assignment_changed') {
      var who = nameOf(to.owner_id) || 'Nobody';
      var prev = nameOf(from.owner_id);
      return (d.handover ? (prev ? prev + ' to ' : '') + who + ' at ' + labelForKey(d.stage_key)
                         : (prev ? prev + ' to ' : 'To ') + who) + (d.note ? ' · ' + d.note : '');
    }
    if (e.event_type === 'due_changed') {
      return (to.kind === 'final' ? 'Final due' : 'First draft due') + ' ' +
        (from.value ? niceDate(from.value) + ' to ' : '') + niceDate(to.value) +
        (d.reason ? ' · ' + reasonWord(d.reason) : '');
    }
    if (e.event_type === 'work_stopped') return minutesWord(to.minutes);
    if (e.event_type === 'checklist_changed') {
      if (to.renamed) return (from.label ? from.label + ' to ' : '') + to.label;
      if (to.removed) return to.label + ' removed';
      if (to.added) return to.label + ' added';
      return to.label + (to.done ? ' ticked' : ' cleared');
    }
    if (e.event_type === 'details_changed') {
      var bits = [];
      if ('priority_level' in to) bits.push('Priority ' + (PRIORITY_WORD[String(from.priority_level)] || 'Normal') + ' to ' + (PRIORITY_WORD[String(to.priority_level)] || 'Normal'));
      if ('description' in to) bits.push(to.description ? 'Brief changed' : 'Brief cleared');
      return bits.join(' · ');
    }
    if (e.event_type === 'file_changed') return (to.label || '') + (to.kind && from.kind !== to.kind ? ' · ' + (LINK_WORD[to.kind] || to.kind) : '');
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
  function frow(label, value, extra) {
    return '<div><dt>' + esc(label) + '</dt><dd>' + value + (extra || '') + '</dd></div>';
  }
  function paintRail(t) {
    paintPeople(t);
    paintDates(t);
    paintDetails(t);
  }

  /* PEOPLE. The Task Owner is named here and nowhere else, with the one
     control that changes it beside the name. A change saves on the pick,
     says it is saving, says Saved, and puts the old name back if the
     database says no. Beside it, who created the task, because that is who
     set its dates and who a performance review goes back to. */
  function paintPeople(t) {
    var people = t.assignees || [];
    var who = ownerName(t);
    var made = nameOf(t.created_by);
    var client = t.clients && t.clients.name;
    var canOwn = may('ops', 'manage');
    var rows = frow('Task Owner',
      '<span class="towner" id="taskOwnerName">' + (who ? esc(who) : '<span class="mute">Nobody</span>') + '</span>' +
      '<select class="select select-sm towner-pick" id="taskOwner" aria-label="Task Owner" hidden></select>',
      canOwn ? '<button class="linkbtn" id="taskOwnerChange" type="button">' + (who ? 'Change' : 'Assign') + '</button>' : '');
    if (made) rows += frow('Created by', esc(made));
    if (client) {
      var slug = t.clients.slug;
      rows += frow(t.scope === 'lead' ? 'Lead' : 'Client',
        slug ? '<a class="tlink" href="/admin/?s=clients&client=' + encodeURIComponent(slug) + '">' + esc(client) + '</a>' : esc(client));
    }
    var rev = people.filter(function (a) { return a.responsibility === 'reviewer'; }).map(function (a) { return a.name; }).join(', ');
    var con = people.filter(function (a) { return a.responsibility === 'contributor'; }).map(function (a) { return a.name; }).join(', ');
    if (rev) rows += frow('Reviewer', esc(rev));
    if (con) rows += frow('Contributors', esc(con));
    $('taskPeople').innerHTML = rows;
    var ch = $('taskOwnerChange');
    if (ch) ch.addEventListener('click', editOwner);
  }

  function editOwner() {
    var t = state.task;
    if (!t || !may('ops', 'manage')) return;
    var name = $('taskOwnerName'), sel = $('taskOwner'), ch = $('taskOwnerChange');
    if (!sel) return;
    var was = ownerId(t);
    sel.innerHTML = (was ? '' : '<option value="">Choose a person</option>') + state.members.map(function (m) {
      return '<option value="' + esc(m.id) + '"' + (was === m.id ? ' selected' : '') + '>' + esc(m.name) + '</option>';
    }).join('');
    name.hidden = true; if (ch) ch.hidden = true;
    sel.hidden = false;
    msg('taskOwnerMsg', '');
    sel.focus();
    var put = function () { sel.hidden = true; name.hidden = false; if (ch) ch.hidden = false; };
    sel.onkeydown = function (e) { if (e.key === 'Escape') { e.stopPropagation(); put(); } };
    sel.onblur = function () { if (!sel.disabled) put(); };
    sel.onchange = function () {
      var pick = sel.value || null;
      if (!pick || pick === was) { put(); return; }
      sel.disabled = true;
      msg('taskOwnerMsg', 'Saving…', '');
      call('ops_assign_task', { p_task: t.id, p_owner: pick, p_version: t.version },
        'taskOwnerMsg', function (d) {
          applyTask(d);
          state.owners[t.id] = nameOf(pick);
          state.ownerIds[t.id] = pick;
          readTask(t.id, function () { msg('taskOwnerMsg', 'Saved.', 'ok'); });
        }, function () {
          /* The select showed the new name before anything was saved; a
             refusal puts back the owner the database still holds. */
          sel.disabled = false;
          sel.value = was || '';
          put();
        });
    };
  }

  /* DATES. Each date is a row that edits itself. A date that is not set yet
     is set from the picker on the row and saved on the pick. Moving a date
     that is already set is a replan, and a replan report reads its reason,
     so the row opens the sheet that asks for one; where the final date is
     somebody else's promise, that sheet asks them rather than moving it. */
  function paintDates(t) {
    var work = may('ops', 'work');
    var rows = [
      { k: 'first_draft', label: 'Draft due', v: t.current_first_draft_due_at, from: t.original_first_draft_due_at },
      { k: 'final', label: 'Final due', v: t.current_final_due_at, from: t.original_final_due_at },
      { k: 'publish', label: 'Scheduled publish', v: t.publish_at }
    ];
    var html = rows.map(function (r) {
      var over = r.k === 'final' && isLate(t);
      var moved = r.from && r.v && r.from !== r.v;
      var word = r.v ? esc(niceDate(r.v)) : '<span class="mute">Not set</span>';
      var inner = work && !isFinished(t)
        ? '<button class="tdate' + (over ? ' is-over' : '') + '" data-date="' + r.k + '" type="button" aria-label="' +
            esc(r.label + (r.v ? ', ' + niceDate(r.v) + '. Change' : ', not set. Set')) + '">' + word +
            '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg></button>'
        : '<span class="tdate-read' + (over ? ' is-over' : '') + '">' + word + '</span>';
      return '<div data-row="' + r.k + '"><dt>' + esc(r.label) + '</dt><dd>' + inner +
        (moved ? '<small>moved from ' + esc(niceDate(r.from)) + '</small>' : '') + '</dd></div>';
    }).join('');
    /* The timestamps that end a task are derived from its events, so each
       points at the Activity pane that holds the event. */
    [['Draft in', t.first_draft_submitted_at], ['Delivered', t.delivered_at], ['Completed', t.completed_at]]
      .filter(function (p) { return p[1]; }).forEach(function (p) {
        html += '<div><dt>' + esc(p[0]) + '</dt><dd><button class="tdate-src" data-src type="button">' +
          esc(niceDate(p[1])) + '</button></dd></div>';
      });
    if (state.eng && state.eng.meeting_at && !state.eng.meeting_na) {
      var ml = monthLink(t);
      html += '<div><dt>Content meeting</dt><dd>' + (ml
        ? '<a class="tdate-src" href="' + esc(ml.href) + '">' + esc(niceDate(state.eng.meeting_at)) + '</a>'
        : esc(niceDate(state.eng.meeting_at))) + '</dd></div>';
    }
    $('taskDates').innerHTML = html;
    Array.prototype.forEach.call($('taskDates').querySelectorAll('[data-date]'), function (b) {
      b.addEventListener('click', function () { editDate(b.getAttribute('data-date')); });
    });
    Array.prototype.forEach.call($('taskDates').querySelectorAll('[data-src]'), function (b) {
      b.addEventListener('click', function () { showPane('activity', true); });
    });
    paintDue(t);
  }

  function editDate(kind) {
    var t = state.task;
    if (!t || !may('ops', 'work')) return;
    var cur = kind === 'final' ? t.current_final_due_at
      : kind === 'first_draft' ? t.current_first_draft_due_at : t.publish_at;
    /* A commitment already set moves through the sheet that asks why. */
    if (kind !== 'publish' && cur) { openDue(kind); return; }
    if (kind === 'final' && needsAsking(t) && cur) { openDue(kind); return; }
    var row = $('taskDates').querySelector('[data-row="' + kind + '"] dd');
    if (!row) return;
    var keep = row.innerHTML;
    row.innerHTML = '<input class="input input-sm tdate-pick" type="date" aria-label="' +
      (kind === 'final' ? 'Final due' : kind === 'first_draft' ? 'Draft due' : 'Scheduled publish') + '">';
    var inp = row.querySelector('input');
    inp.value = dateValue(cur);
    if (kind === 'first_draft' && t.current_final_due_at) inp.setAttribute('max', dayBefore(t.current_final_due_at));
    msg('taskDatesMsg', '');
    var done = false;
    var back = function () { if (done) return; done = true; row.innerHTML = keep; paintDates(state.task); };
    inp.addEventListener('keydown', function (e) { if (e.key === 'Escape') { e.stopPropagation(); back(); } });
    inp.addEventListener('blur', function () { setTimeout(function () { if (!inp.disabled) back(); }, 150); });
    inp.addEventListener('change', function () {
      if (!inp.value && kind !== 'publish') return;
      inp.disabled = true;
      msg('taskDatesMsg', 'Saving…', '');
      var ok = function () { done = true; readTask(t.id, function () { msg('taskDatesMsg', 'Saved.', 'ok'); }); };
      var bad = function () { inp.disabled = false; back(); };
      if (kind === 'publish') {
        call('ops_set_publish_date', { p_task: t.id, p_at: inp.value ? inp.value + 'T00:00:00Z' : null, p_version: t.version },
          'taskDatesMsg', ok, bad);
      } else {
        /* A first date is not a replan, so it is filed as one. The database
           still decides whether this is a move or an ask. */
        call('ops_request_due_change', {
          p_task: t.id, p_kind: kind, p_value: inp.value + 'T00:00:00Z',
          p_reason: 'initial', p_note: null, p_version: t.version
        }, 'taskDatesMsg', function (out) {
          if (out && out.asked) state.said = 'Requested.';
          ok();
        }, bad);
      }
    });
    inp.focus();
    if (inp.showPicker) { try { inp.showPicker(); } catch (e) {} }
  }

  /* DETAILS, and the rest behind a fold: what a reader needs to place the
     task, then everything they might look up. */
  function paintDetails(t) {
    $('taskFacts').innerHTML = [
      ['Scope', t.scope === 'internal' ? 'Internal' : t.scope === 'lead' ? 'Lead' : 'Client'],
      ['Format', formatWord(t)],
      ['Content month', t.code_period ? monthWord(t.code_period) + (t.code_week ? ' · Week ' + t.code_week : '') : ''],
      ['Priority', PRIORITY_WORD[String(t.priority_level)] || String(t.priority_level || '')],
      ['Complexity', COMPLEX_WORD[t.complexity] || sentence(t.complexity)]
    ].filter(function (p) { return p[1]; }).map(function (p) { return frow(p[0], esc(p[1])); }).join('');
    var wf = state.workflows.filter(function (w) { return w.id === t.workflow_id; })[0];
    var e = state.eng;
    var ml = monthLink(t);
    var more = [
      ['Type', TASK_TYPE_WORD[t.task_type] || sentence(t.task_type)],
      ['Workflow', (wf && wf.name) || ''],
      ['Languages', (t.language_codes || []).join(', ')],
      ['Estimate', t.estimate_minutes ? minutesWord(t.estimate_minutes) : ''],
      ['Repeats', ruleWord(state.rule)],
      ['Added', niceDate(t.created_at)]
    ].filter(function (p) { return p[1]; }).map(function (p) { return frow(p[0], esc(p[1])); }).join('');
    if (e) {
      more += frow('Engagement', esc(monthWord(e.period)) + ' · ' + esc(wordOf(ENG_STATE, e.status)) +
        (ml ? ' <a class="tlink" href="' + esc(ml.href) + '">Open the month</a>' : ''));
      more += frow('Content meeting', esc(meetingWord(e)));
    }
    $('taskMore').innerHTML = more;
    $('taskMoreWrap').hidden = !more;
  }

  /* One forward move is the next step, and every other move the workflow
     allows is in the ⋯. Which move is forward is the workflow's own to say,
     never a list kept here: the next stage is the one nearest ahead of where
     the task stands by position. */
  /* The lanes beside the main line. A review stage is marked waiting because
     it waits on a reviewer, so "not waiting" is the wrong test for forward:
     it put Revision in front of Client review. What is beside the line is its
     own stage group, which is data the workflow already carries. */
  var SIDE = { blocked: 1, waiting: 1, kiv: 1, cancelled: 1 };
  function forwardOf(t, nexts) {
    var here = stageOf(t);
    var pos = here ? here.position : 0;
    /* A revision is where work is sent back and a take-down is an ending
       somebody chooses, so neither is ever the step forward, wherever the
       workflow puts them. */
    var ahead = nexts.map(function (k) {
      return state.stages[t.workflow_id + '|' + k];
    }).filter(function (s) {
      return s && s.position > pos && !SIDE[s.stage_group] &&
        s.stage_group !== 'revision' && s.stage_group !== 'taken_down';
    }).sort(function (a, b) { return a.position - b.position; });
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

  /* THE ⋯. Everything off the ordinary path, each item drawn only where the
     move exists for this task and the reader may make it. The database asks
     the same question again when the item is pressed. */
  function paintMenu(t, n) {
    var menu = $('taskMenu');
    if (!menu) return;
    var work = may('ops', 'work');
    var fin = isFinished(t);
    var back = cameFrom(t);
    var here = stageOf(t);
    var nexts = (here && here.next_stage_keys) || [];
    var rv = menu.querySelector('[data-a="revert"]');
    var canBack = work && back && nexts.indexOf(back) > -1 && !fin && t.stage_key !== 'blocked';
    rv.hidden = !canBack;
    if (canBack) rv.textContent = 'Revert to ' + labelForKey(back);
    menu.querySelector('[data-a="move"]').hidden = !work || fin || !nexts.length;
    menu.querySelector('[data-a="block"]').hidden = !work || t.stage_key === 'blocked' || fin;
    menu.querySelector('[data-a="duplicate"]').hidden = !work;
    menu.querySelector('[data-a="repeat"]').hidden = !work;
    menu.querySelector('[data-a="reopen"]').hidden = !work || !canReopen(t);
    menu.querySelector('[data-a="cancel"]').hidden = !work || fin || nexts.indexOf('cancelled') < 0;
    menu.querySelector('[data-a="handover"]').hidden = fin;
    var tm = menu.querySelector('[data-a="timer"]');
    if (tm) {
      tm.hidden = !work || fin;
      tm.textContent = state.session && state.session.task_id === t.id ? 'Stop timer' : 'Start timer';
    }
    var arch = menu.querySelector('[data-a="archive"]');
    arch.textContent = t.archived_at ? 'Restore' : 'Archive';
  }

  /* A move. `note` goes on the record with it; `o.assignee` hands the task
     to the next person on the same press, which is one event and one
     notification rather than a move and a reassignment a moment apart. */
  function move(next, note, o) {
    var t = state.task;
    if (!t) return;
    o = o || {};
    if (next === 'blocked') { openBlock(); return; }
    var fn = t.stage_key === 'blocked' ? 'ops_clear_blocked' : 'ops_transition_task';
    var args = t.stage_key === 'blocked'
      ? { p_task: t.id, p_next: next, p_version: t.version }
      : { p_task: t.id, p_next: next, p_version: t.version, p_note: note || null, p_assignee: o.assignee || null };
    var go = $(state.drawer ? 'dwGo' : 'taskGo');
    if (go) go.disabled = true;
    call(fn, args, msgHere(), function (d) {
      if (o.assignee) { state.owners[t.id] = nameOf(o.assignee); state.ownerIds[t.id] = o.assignee; }
      var word = isEveryday(t) ? (PLAIN[plainOfKey(next)] || {}).word || labelOfStage(t, next) : labelOfStage(t, next);
      readTask(t.id, function () {
        msg(msgHere(), 'Moved to ' + word + (o.assignee ? ', with ' + nameOf(o.assignee) : '') + '.', 'ok');
      });
    }, function () { if (go) go.disabled = false; });
  }
  /* A move backwards, or out of the line, takes a reason, asked on the page
     with the consequence stated first; the reason goes on the record. */
  function askBack(key) {
    ADspaceConfirm.ask({
      title: 'Revert to ' + labelForKey(key),
      body: 'The task goes back to ' + labelForKey(key) + '. The reason is kept in its Activity.',
      go: 'Revert', tone: 'warn',
      field: { label: 'Reason', rows: 2, need: 'A reason is required.' }
    }, function (why) { move(key, why); });
  }
  function askChanges() {
    ADspaceConfirm.ask({
      title: 'Request changes',
      body: 'Moves it to Changes requested and notifies the owner.',
      go: 'Request changes',
      field: { label: 'What needs to change', rows: 3, need: 'Say what needs to change.' }
    }, function (why) { move('changes_requested', why); });
  }
  function askComplete(key) {
    ADspaceConfirm.ask({
      title: 'Complete task',
      body: 'No delivery recorded. State how it was closed.',
      go: 'Complete task',
      field: { label: 'Reason', rows: 2, need: 'A reason is required.' }
    }, function (why) { move(key, why); });
  }
  function askCancel() {
    ADspaceConfirm.ask({
      title: 'Cancel task',
      body: 'Removes it from open work. It can be reopened.',
      go: 'Cancel task', tone: 'danger', cancel: 'Keep task',
      field: { label: 'Reason', rows: 2, need: 'A reason is required.' }
    }, function (why) { move('cancelled', why); });
  }

  function markMonthReady(t) {
    var e = state.eng;
    if (!e) return;
    call('ops_engagement_set_status', { p_engagement: e.id, p_status: 'ready', p_version: e.version }, msgHere(),
      function () { readTask(t.id, function () { msg(msgHere(), monthWord(e.period) + ' is ready.', 'ok'); }); });
  }
  /* The month inside a task's next step: the two ticks and the meeting,
     each acting on the month and repainting the task after. */
  function paintMonth(b, t, n) {
    var box = b.box.querySelector('.tnext-month');
    if (!n.month || !state.eng) { if (box) box.remove(); return; }
    if (!box) {
      box = document.createElement('div');
      box.className = 'tnext-month';
      b.list.parentNode.insertBefore(box, b.list.nextSibling);
    }
    var e = state.eng, can = may('ops', 'work');
    box.innerHTML = checksHtml(e, checksOf(e, state.engChecks), can) + meetHtml(e, can);
    wireChecks(box, e, b.msg, function () { readTask(t.id); });
    wireMeet(box, e, b.msg, function () { openMeetFor(); }, function () { readTask(t.id); });
  }

  /* The content meeting is the month's, so it is set on the month's record;
     from the task it opens the same sheet and repaints the task after. */
  function openMeetFor() {
    if (!state.eng) return;
    openMeet(state.eng);
    meetAfter = function () { readTask(state.task.id); };
  }

  /* A minute, not a second: the number is how long somebody has been at this,
     and a second hand on a page somebody is working in is a distraction with
     no answer in it. */
  function startTick() {
    if (state.tick) return;
    state.tick = setInterval(function () {
      if (!state.task || !state.session) { stopTick(); return; }
      paintRun(state.task);
    }, 60000);
  }
  function stopTick() {
    if (!state.tick) return;
    clearInterval(state.tick);
    state.tick = null;
  }

  /* `ops_reopen_task` puts a task back at its workflow's Revision stage, so it
     is offered only where the workflow has one. A content task goes back the
     way its own workflow allows (a finished post to its performance review,
     a post taken down back to live), through Move to another stage; an
     everyday task is reopened by its own tick. */
  function reopens(t) {
    return Boolean(state.stages[t.workflow_id + '|revision']);
  }
  /* Where a finished task goes back to when it is reopened: the stage it
     finished from, where the workflow still allows that move, else the
     first stage the workflow allows out of where it stands. Cancelled is
     the one ending every workflow lets a task leave, so a cancelled task can
     always come back; the cancel sheet has always said it could. */
  function reopenTo(t) {
    var s = stageOf(t);
    var nexts = ((s && s.next_stage_keys) || []).filter(function (k) { return k !== 'cancelled'; });
    var from = cameFrom(t);
    if (from && nexts.indexOf(from) > -1) return from;
    return nexts[0] || null;
  }
  function canReopen(t) {
    return Boolean(t && isFinished(t) && ((t.completed_at && reopens(t)) || reopenTo(t)));
  }
  function askReopenTo(t) {
    var to = reopenTo(t);
    if (!to) return;
    ADspaceConfirm.ask({
      title: 'Reopen task',
      body: 'It goes back to ' + labelForKey(to) + '. The reason is kept in its Activity.',
      go: 'Reopen',
      field: { label: 'Why it is being reopened', rows: 2, need: 'A reason is required.' }
    }, function (why) { move(to, why); });
  }
  /* Reopening needs a reason somebody else will read, asked on the page
     with the consequence stated first, from the sheet and the record alike. */
  function askReopen() {
    var t = state.task;
    if (!t) return;
    if (!(t.completed_at && reopens(t))) { askReopenTo(t); return; }
    ADspaceConfirm.ask({
      title: 'Reopen task',
      body: 'It goes back into open work at the stage it finished from.',
      go: 'Reopen',
      field: { label: 'Why it is being reopened', rows: 2, need: 'A reason is required.' }
    }, function (why) {
      call('ops_reopen_task', { p_task: t.id, p_reason: why, p_version: t.version }, msgHere('taskMsg'), function () {
        readTask(t.id);
      });
    });
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
  /* A function the database does not have yet is a migration nobody has
     run, and PostgREST's words for it name its schema cache. The console says
     what to do instead. */
  function dbWord(m) {
    m = String(m || '');
    return /Could not find the function|schema cache|PGRST202/i.test(m)
      ? 'This needs a database update. Ask an admin to run the latest migration.' : m;
  }
  function call(fn, args, msgId, then, onFail) {
    db.rpc(fn, args).then(function (r) {
      if (r.error) {
        msg(msgId, dbWord(r.error.message), 'err');
        if (onFail) onFail();
        return;
      }
      var d = r.data;
      if (d && d.error) {
        msg(msgId, said(d.error, state.task), 'err');
        if (d.error === 'stale' && d.task) { applyTask(d.task); paintTask(); }
        if (onFail) onFail();
        return;
      }
      msg(msgId, '');
      /* A write made while the drawer is open changes a row the list drew. */
      if (state.drawer) state.drawerDirty = true;
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
    $('tdelWhat').textContent = serialOf(t) + ' · ' + (t.title || 'Untitled task') +
      ' goes, with its ' + goes.join(', ') + '. There is no restore.';
    $('tdelConfirm').value = '';
    $('tdelReason').value = '';
    $('tdelConfirm').setAttribute('placeholder', serialOf(t));
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
  /* `swap` is the Task / Content deliverable switch: the other form takes
     the place of this one without arriving again, so the scrim does not fade
     back in and the card does not lift in from below (`.sheet.is-swap`). */
  function sheet(id, on, swap) {
    var el = $(id);
    if (!el) return;
    if (on) el.classList.toggle('is-swap', Boolean(swap));
    el.hidden = !on;
    document.body.classList.toggle('sheet-open', !!on);
    if (on) {
      var f = el.querySelector('input, select, textarea, button');
      if (f) f.focus();
    }
  }

  // ---- New task ------------------------------------------------------------
  /* Which clients a scope offers. Client is the working book of business
     (active, and paused on request); Lead is every record that has not yet
     become one. The database asks the same question again on save
     (`ops_scope_error`), so the list here is a courtesy and not the gate. */
  var CLIENT_STAGES = { active: 1 }, PAUSED_STAGES = { paused: 1 };
  var LEAD_STAGES = { lead: 1, contacted: 1, proposal: 1 };
  function clientsFor(scope, paused) {
    return state.clients.filter(function (c) {
      if (scope === 'lead') return LEAD_STAGES[c.stage];
      return CLIENT_STAGES[c.stage] || (paused && PAUSED_STAGES[c.stage]);
    });
  }
  function monthKey(d) {
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0');
  }
  function monthWord(key) {
    var m = /^(\d{4})-(\d{2})$/.exec(key || '');
    if (!m) return key || '';
    var d = new Date(Number(m[1]), Number(m[2]) - 1, 1);
    return d.toLocaleDateString('en-GB', { month: 'short', year: 'numeric' });
  }
  /* The week the code names is the planned publishing week of the content
     month: days 1 to 7 are week 1 and so on, week 5 for the tail. */
  function weekOfDay(iso) {
    var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso || '');
    if (!m) return null;
    return Math.min(5, Math.floor((Number(m[3]) - 1) / 7) + 1);
  }
  /* What the user touched is kept; what they did not is refilled from the
     publish date whenever it changes. */
  var ntTouched = {};
  /* Opened from the bar with nothing, or from a client record with the
     client, and from a month's card with its month and its engagement. */
  var ntPrefill = null;
  function openNew(prefill, swap) {
    if (!may('ops', 'work')) return;
    ntTouched = {};
    ntPrefill = (prefill && prefill.client) ? prefill : null;
    /* Made from a client record the task lands on that record's list, which
       the quick form does not do, so the choice is offered from My Work. */
    var nk = $('ntKind');
    if (nk) nk.hidden = Boolean(ntPrefill);
    var ow = $('ntOwner');
    var me = bridge.me && bridge.me();
    ow.innerHTML = '<option value="">Nobody yet</option>' + state.members.map(function (m) {
      return '<option value="' + esc(m.id) + '"' + (me && me.id === m.id ? ' selected' : '') + '>' + esc(m.name) + '</option>';
    }).join('');
    /* The content month: this one and the six after it, and the one before
       for work being keyed in late. */
    var now = new Date(), months = [];
    for (var i = -1; i <= 6; i++) months.push(new Date(now.getFullYear(), now.getMonth() + i, 1));
    $('ntPeriod').innerHTML = months.map(function (d) {
      var k = monthKey(d);
      return '<option value="' + k + '"' + (k === monthKey(now) ? ' selected' : '') + '>' + esc(monthWord(k)) + '</option>';
    }).join('');
    $('ntWeek').value = String(weekOfDay(now.toISOString()));
    $('ntDesc').value = '';
    $('ntBrief').value = '';
    $('ntPublish').value = '';
    $('ntDraft').value = '';
    $('ntFinal').value = '';
    $('ntScope').value = 'client';
    $('ntType').value = 'engagement';
    $('ntFormat').value = '';
    $('ntPaused').checked = false;
    $('ntPriority').value = '3';
    $('ntComplex').value = 'standard';
    if (ntPrefill) {
      var pc = ntPrefill.client;
      $('ntScope').value = LEAD_STAGES[pc.stage] ? 'lead' : 'client';
      if (pc.stage === 'paused') $('ntPaused').checked = true;
      if (ntPrefill.period && $('ntPeriod').querySelector('option[value="' + ntPrefill.period + '"]')) {
        $('ntPeriod').value = ntPrefill.period; ntTouched.period = true;
      }
    }
    ntScopeChanged();
    if (ntPrefill) {
      $('ntClient').value = ntPrefill.client.id;
      ntCodeHint();
    }
    msg('ntMsg', '');
    sheet('taskSheet', true, swap);
  }
  function ntScopeChanged() {
    var scope = $('ntScope').value;
    var was = $('ntClient').value;
    $('ntClientField').hidden = scope === 'internal';
    $('ntPausedWrap').hidden = scope !== 'client';
    $('ntClientLabel').textContent = scope === 'lead' ? 'Lead' : 'Client';
    var list = clientsFor(scope, $('ntPaused').checked);
    $('ntClient').innerHTML = '<option value="">' + (scope === 'lead' ? 'Choose a lead' : 'Choose a client') + '</option>' +
      list.map(function (c) {
        return '<option value="' + esc(c.id) + '"' + (c.id === was ? ' selected' : '') + '>' + esc(c.name) +
          (c.stage === 'paused' ? ' (paused)' : '') + '</option>';
      }).join('');
    /* An internal task carries no code, so the month and the week that build
       one have nothing to say; and engagement work is for a client. */
    $('ntCodeRow').hidden = scope === 'internal';
    if (scope !== 'client' && $('ntType').value === 'engagement' && !ntTouched.type) $('ntType').value = 'adhoc';
    if (scope === 'client' && !ntTouched.type) $('ntType').value = 'engagement';
    ntCodeHint();
  }
  /* The publish date seeds the month and the week the code is built from,
     unless the person has already chosen them. */
  function ntPublishChanged() {
    var v = $('ntPublish').value;
    if (v) {
      var k = v.slice(0, 7);
      if (!ntTouched.period && $('ntPeriod').querySelector('option[value="' + k + '"]')) $('ntPeriod').value = k;
      if (!ntTouched.week) $('ntWeek').value = String(weekOfDay(v));
    }
    ntCodeHint();
  }
  /* What the name will read as. The running number is the database's and is
     not guessed here, which is why it reads `nn`. */
  function ntCodeHint() {
    var line = $('ntCodeHint');
    if (!line) return;
    if ($('ntScope').value === 'internal') { line.hidden = true; line.textContent = ''; return; }
    var k = $('ntPeriod').value || '';
    var code = k.slice(2, 4) + k.slice(5, 7) + 'W' + ($('ntWeek').value || '1') + 'nn';
    var d = String($('ntDesc').value || '').trim();
    line.textContent = 'Named ' + code + (d ? ' ' + d : '') + '. The number is given on save.';
    line.hidden = false;
  }
  /* The same press twice is one task. The key is what makes the two presses
     the same act, so it is built from what was typed and not from a counter. */
  var ntKey = '';
  function createTask() {
    var scope = $('ntScope').value;
    var desc = String($('ntDesc').value || '').trim();
    if (scope === 'internal' && !desc) {
      msg('ntMsg', 'A description is required.', 'err'); $('ntDesc').focus(); return;
    }
    if (scope !== 'internal' && !$('ntClient').value) {
      msg('ntMsg', scope === 'lead' ? 'A lead is required.' : 'A client is required.', 'err');
      $('ntClient').focus(); return;
    }
    var draft = $('ntDraft').value, fin = $('ntFinal').value;
    if (draft && fin && draft >= fin) {
      msg('ntMsg', said('draft-not-before-final'), 'err'); $('ntDraft').focus(); return;
    }
    var payload = {
      scope: scope,
      client_id: scope === 'internal' ? null : $('ntClient').value,
      task_type: $('ntType').value || 'adhoc',
      content_desc: desc || null,
      deliverable_type: $('ntFormat').value || null,
      owner_id: $('ntOwner').value || null,
      description: String($('ntBrief').value || '').trim() || null,
      priority_level: Number($('ntPriority').value) || 3,
      complexity: $('ntComplex').value || null,
      publish_at: $('ntPublish').value ? $('ntPublish').value + 'T00:00:00Z' : null,
      first_draft_due_at: draft ? draft + 'T00:00:00Z' : null,
      final_due_at: fin ? fin + 'T00:00:00Z' : null,
      code_period: scope === 'internal' ? null : $('ntPeriod').value || null,
      code_week: scope === 'internal' ? null : Number($('ntWeek').value) || null,
      /* Made from a client record, the task joins the month's engagement
         where that month has one. */
      engagement_id: (ntPrefill && scope !== 'internal')
        ? ((cw.engs || []).filter(function (e) { return e.period === $('ntPeriod').value; })[0] || {}).id || null
        : null
    };
    if (!ntKey) ntKey = 'nt-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8);
    var btn = $('ntGo');
    btn.disabled = true;
    var fromClient = Boolean(ntPrefill);
    /* A client's content for a month belongs to that month, so the month is
       joined, or made, on the way in: nobody goes to the client record first
       to open it. Asked with nothing to change, the database answers the
       month as it stands. */
    if (scope === 'client' && payload.code_period && !payload.engagement_id) {
      db.rpc('ops_engagement_upsert', { p_payload: { client_id: payload.client_id, period: payload.code_period } }).then(function (r) {
        var d = r && r.data;
        if (d && d.id && !d.error) payload.engagement_id = d.id;
        makeTask();
      }, makeTask);
      return;
    }
    makeTask();
    function makeTask() {
    call('ops_create_task', { p_payload: payload, p_idem: ntKey }, 'ntMsg', function (t) {
      btn.disabled = false;
      ntKey = '';
      sheet('taskSheet', false);
      /* Made from a client record, the task takes its place on that record's
         list rather than carrying the person off to My Work. */
      if (fromClient && cw.box && cw.client && cw.client.id === payload.client_id) readClientWork();
      else openTask(t.id, true);
    }, function () { btn.disabled = false; });
    }
  }

  /* The description is edited where it sits: the pen becomes the tick, the
     code beside it never changes, and a blank is allowed on a task that has
     a code because the code is then the name. */
  function editDesc() {
    var t = state.task;
    if (!t || !window.ADspaceAsk) return;
    var host = $('taskDesc'), pen = $('taskDescEdit');
    var was = t.code ? (t.content_desc || '') : (t.content_desc || t.title || '');
    window.ADspaceAsk.rename(host, pen, {
      label: 'Content description', saveLabel: 'Save description', value: was,
      allowEmpty: Boolean(t.code), max: 160,
      save: function (v) {
        call('ops_set_content_desc', { p_task: t.id, p_desc: v, p_version: t.version }, 'taskMsg',
          function (d) {
            applyTask(d);
            readTask(t.id);
          });
      }
    });
  }
  function copyTitle() {
    var t = state.task;
    if (!t || !window.ADspaceCopy) return;
    window.ADspaceCopy.to($('taskCopyTitle'), t.title || '');
  }

  // ---- Duplicate, generate, repeat ---------------------------------------
  /* The content months a select offers: the one before this, this one and
     the six after, so work keyed in late and work planned ahead both fit. */
  function fillMonths(sel, chosen) {
    var now = new Date(), months = [];
    for (var i = -1; i <= 6; i++) months.push(monthKey(new Date(now.getFullYear(), now.getMonth() + i, 1)));
    if (chosen && months.indexOf(chosen) < 0) months.unshift(chosen);
    var pick = chosen || monthKey(now);
    sel.innerHTML = months.map(function (k) {
      return '<option value="' + k + '"' + (k === pick ? ' selected' : '') + '>' + esc(monthWord(k)) + '</option>';
    }).join('');
  }
  function fillOwners(sel, me) {
    sel.innerHTML = '<option value="">Nobody yet</option>' + state.members.map(function (m) {
      return '<option value="' + esc(m.id) + '"' + (me && me.id === m.id ? ' selected' : '') + '>' + esc(m.name) + '</option>';
    }).join('');
  }
  function fillClients(sel, paused, was) {
    var list = clientsFor('client', paused);
    sel.innerHTML = '<option value="">Choose a client</option>' + list.map(function (c) {
      return '<option value="' + esc(c.id) + '"' + (c.id === was ? ' selected' : '') + '>' + esc(c.name) +
        (c.stage === 'paused' ? ' (paused)' : '') + '</option>';
    }).join('');
  }

  /* DUPLICATE. A copy with a new code; the person says what else travels. */
  var dupKey = '';
  function openDup() {
    var t = state.task;
    if (!t || !may('ops', 'work')) return;
    dupKey = '';
    $('dupWhat').textContent = 'A copy of ' + (t.title || serialOf(t)) +
      ' with a new code. Its history, its time and its links stay here.';
    $('dupDesc').checked = true;
    $('dupDates').checked = false;
    $('dupPeople').checked = false;
    $('dupCodeRow').hidden = t.scope === 'internal';
    fillMonths($('dupPeriod'), t.code_period || null);
    $('dupWeek').value = String(t.code_week || weekOfDay(new Date().toISOString()));
    msg('dupMsg', '');
    sheet('dupSheet', true);
  }
  function doDup() {
    var t = state.task;
    if (!t) return;
    if (!dupKey) dupKey = 'dup-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8);
    var opts = {
      keep_desc: $('dupDesc').checked,
      copy_dates: $('dupDates').checked,
      copy_assignees: $('dupPeople').checked
    };
    if (t.scope !== 'internal') {
      opts.code_period = $('dupPeriod').value || null;
      opts.code_week = Number($('dupWeek').value) || null;
    }
    var btn = $('dupGo');
    btn.disabled = true;
    call('ops_duplicate_task', { p_task: t.id, p_opts: opts, p_idem: dupKey }, 'dupMsg', function (d) {
      btn.disabled = false;
      dupKey = '';
      sheet('dupSheet', false);
      openTask(d.id, true);
    }, function () { btn.disabled = false; });
  }

  /* GENERATE. A month of tasks for one client, or the month's recurring
     tasks. The codes are previewed from the database's own next number, so
     the preview and the run cannot disagree. */
  var genKey = '';
  function openGen() {
    if (!may('ops', 'work')) return;
    genKey = '';
    $('genWhat').value = 'month';
    fillMonths($('genPeriod'), null);
    $('genPaused').checked = false;
    fillClients($('genClient'), false, '');
    $('genCount').value = '8';
    $('genSpread').value = 'even';
    ['genW1', 'genW2', 'genW3', 'genW4', 'genW5'].forEach(function (id) { $(id).value = '0'; });
    $('genType').value = 'engagement';
    $('genFormat').value = '';
    $('genPriority').value = '3';
    $('genComplex').value = 'standard';
    fillOwners($('genOwner'), null);
    $('genOut').hidden = true; $('genOut').textContent = '';
    genWhatChanged();
    msg('genMsg', '');
    sheet('genSheet', true);
  }
  function genWhatChanged() {
    var recur = $('genWhat').value === 'recur';
    $('genMonthBox').hidden = recur;
    $('genRecurBox').hidden = !recur;
    $('genGo').textContent = recur ? 'Run' : 'Add tasks';
    $('genWeeksRow').hidden = $('genSpread').value !== 'set';
  }
  function genWeeks() {
    if ($('genSpread').value !== 'set') return null;
    return ['genW1', 'genW2', 'genW3', 'genW4', 'genW5'].map(function (id) {
      return Math.max(0, Math.floor(Number($(id).value) || 0));
    });
  }
  function genPayload() {
    var count = Math.floor(Number($('genCount').value) || 0);
    var weeks = genWeeks();
    if (weeks) {
      var sum = weeks.reduce(function (a, b) { return a + b; }, 0);
      if (sum !== count) { msg('genMsg', said('weeks-do-not-add-up') + ' The weeks come to ' + sum + '.', 'err'); return null; }
    }
    if (!$('genClient').value) { msg('genMsg', 'A client is required.', 'err'); $('genClient').focus(); return null; }
    if (count < 1 || count > 60) { msg('genMsg', said('bad-count'), 'err'); $('genCount').focus(); return null; }
    return {
      client_id: $('genClient').value,
      period: $('genPeriod').value,
      count: count,
      weeks: weeks,
      scope: 'client',
      task_type: $('genType').value || 'engagement',
      deliverable_type: $('genFormat').value || null,
      priority_level: Number($('genPriority').value) || 3,
      complexity: $('genComplex').value || null,
      owner_id: $('genOwner').value || null
    };
  }
  function genPreview() {
    var pl = genPayload();
    if (!pl) return;
    call('ops_generate_month', { p_payload: pl, p_dry_run: true }, 'genMsg', function (d) {
      var codes = ((d && d.tasks) || []).map(function (x) { return x.code; });
      var out = $('genOut');
      out.hidden = false;
      out.textContent = codes.length
        ? codes.length + (codes.length === 1 ? ' task: ' : ' tasks: ') + codes.join(', ')
        : 'Nothing would be made.';
    });
  }
  function doGen() {
    var btn = $('genGo');
    if ($('genWhat').value === 'recur') {
      btn.disabled = true;
      call('ops_generate_recurring', { p_period: $('genPeriod').value }, 'genMsg', function (d) {
        btn.disabled = false;
        sheet('genSheet', false);
        var n = (d && d.created) || 0, s = (d && d.skipped) || 0;
        msg('workMsg', (n === 1 ? '1 task added' : n + ' tasks added') + ' for ' + monthWord($('genPeriod').value) +
          (s ? ', ' + s + ' already there.' : '.'), 'ok');
        load();
      }, function () { btn.disabled = false; });
      return;
    }
    var pl = genPayload();
    if (!pl) return;
    if (!genKey) genKey = 'gen-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8);
    btn.disabled = true;
    call('ops_generate_month', { p_payload: pl, p_dry_run: false, p_idem: genKey }, 'genMsg', function (d) {
      btn.disabled = false;
      genKey = '';
      sheet('genSheet', false);
      var n = (d && d.count) || 0;
      var who = ($('genClient').selectedOptions[0] || {}).textContent || '';
      msg('workMsg', (n === 1 ? '1 task added' : n + ' tasks added') + ' for ' + who + ', ' + monthWord(pl.period) + '.', 'ok');
      load();
    }, function () { btn.disabled = false; });
  }

  /* REPEAT. The rule that copies this task on each date. */
  var FREQ_WORD = { weekly: 'Weekly', monthly: 'Monthly', custom: 'Every {n} days' };
  function ruleWord(r) {
    if (!r) return '';
    var w = r.frequency === 'custom' ? 'Every ' + (r.interval_days || '?') + ' days'
          : r.frequency === 'weekly' ? 'Weekly'
          : 'Monthly' + (r.day_of_month ? ' on the ' + r.day_of_month + ordinal(r.day_of_month) : '');
    if (r.ends_on) w += ' until ' + niceDate(r.ends_on);
    else if (r.max_count) w += ', ' + r.max_count + ' times';
    if (r.generated_count) w += ' · ' + r.generated_count + ' made';
    return w;
  }
  function ordinal(n) {
    n = Number(n) || 0;
    var s = ['th', 'st', 'nd', 'rd'], v = n % 100;
    return s[(v - 20) % 10] || s[v] || s[0];
  }
  function openRec() {
    var t = state.task;
    if (!t || !may('ops', 'work')) return;
    var r = state.rule;
    $('recWhat').textContent = (r ? 'Repeating: ' + ruleWord(r) + '.' : 'Creates a copy on each date with the same description, format and people.');
    $('recFreq').value = (r && r.frequency) || 'monthly';
    var day = r && r.day_of_month;
    if (!day && t.publish_at) { var m = /^\d{4}-\d{2}-(\d{2})/.exec(t.publish_at); day = m ? Math.min(28, Number(m[1])) : null; }
    $('recDay').value = day || '';
    $('recInterval').value = (r && r.interval_days) || '';
    $('recEnds').value = (r && r.ends_on) ? String(r.ends_on).slice(0, 10) : '';
    $('recMax').value = (r && r.max_count) || '';
    $('recWeek').value = (r && r.code_week) ? String(r.code_week) : '';
    $('recStop').hidden = !r;
    $('recGo').textContent = r ? 'Save' : 'Start repeating';
    recFreqChanged();
    msg('recMsg', '');
    sheet('recSheet', true);
  }
  function recFreqChanged() {
    var f = $('recFreq').value;
    $('recDayField').hidden = f !== 'monthly';
    $('recIntervalField').hidden = f !== 'custom';
  }
  function doRec() {
    var t = state.task;
    if (!t) return;
    var f = $('recFreq').value;
    if (f === 'custom' && !(Number($('recInterval').value) >= 1)) {
      msg('recMsg', said('interval-required'), 'err'); $('recInterval').focus(); return;
    }
    var payload = {
      frequency: f,
      day_of_month: f === 'monthly' ? (Number($('recDay').value) || null) : null,
      interval_days: f === 'custom' ? Number($('recInterval').value) : null,
      ends_on: $('recEnds').value || null,
      max_count: Number($('recMax').value) || null,
      code_week: Number($('recWeek').value) || null
    };
    var btn = $('recGo');
    btn.disabled = true;
    call('ops_set_recurring', { p_task: t.id, p_payload: payload }, 'recMsg', function () {
      btn.disabled = false;
      sheet('recSheet', false);
      readTask(t.id);
    }, function () { btn.disabled = false; });
  }
  function stopRec() {
    var t = state.task;
    if (!t) return;
    call('ops_set_recurring', { p_task: t.id, p_payload: { active: false } }, 'recMsg', function () {
      sheet('recSheet', false);
      readTask(t.id);
    });
  }

  // ---- The engagement: one client's work for one month -------------------
  /* The thirteen readiness questions, in the team's words, in the order the
     database seeds them. A key is stored; a word is read. */
  /* Two ticks (2026-09-24): the detailed checklists are the team's own
     forms, and the month records that each is done and who ticked it. */
  var CHECK_WORD = { onboarding: 'Onboarding checklist', pre_ads: 'Pre-advertising checklist' };
  var CHECK_ORDER = ['onboarding', 'pre_ads'];
  var CHECK_STATE = [
    ['not_started', 'Not started', 'is-off'], ['waiting_client', 'Waiting on client', 'is-warn'],
    ['in_progress', 'In progress', ''], ['ready', 'Ready', 'is-ok'], ['na', 'Not applicable', 'is-off']
  ];
  var ENG_STATE = [
    ['planning', 'Planning', 'is-off'], ['ready', 'Ready', 'is-ok'],
    ['in_production', 'In production', ''], ['completed', 'Completed', 'is-ok'], ['cancelled', 'Cancelled', 'is-off']
  ];
  var CHANNEL_WORD = { onsite: 'On site', google_meet: 'Google Meet', zoom: 'Zoom', other: 'Other' };
  function wordOf(list, key) {
    var hit = list.filter(function (x) { return x[0] === key; })[0];
    return hit ? hit[1] : sentence(key);
  }
  function toneOf(list, key) {
    var hit = list.filter(function (x) { return x[0] === key; })[0];
    return hit ? hit[2] : '';
  }
  function checkWord(k) { return CHECK_WORD[k] || sentence(k); }
  function checksOf(e, all) {
    return (all || []).filter(function (x) { return x.engagement_id === e.id; })
      .sort(function (a, b) { return CHECK_ORDER.indexOf(a.key) - CHECK_ORDER.indexOf(b.key); });
  }
  function checksDone(list) {
    return list.filter(function (x) { return x.state === 'ready' || x.state === 'na'; }).length;
  }
  /* THE MONTH'S READINESS: one tick a checklist, the person who ticked it
     named under it by the database, and Not needed for a checklist this
     month does not use. Drawn on the month's card and in a task's next
     step alike, so the month is run from wherever somebody is. */
  function checksHtml(e, list, can) {
    /* Readiness is onboarding, held on a client's first month only: a later
       month carries no checks and draws nothing here. */
    if (!list || !list.length) return '';
    return '<div class="eng-checks">' +
      '<div class="eng-checkhead"><span>Readiness</span><span class="eng-checkcount">' +
        checksDone(list) + ' of ' + list.length + ' done</span></div>' +
      list.map(function (x) {
        var done = x.state === 'ready', na = x.state === 'na';
        var by = (done || na) && x.owner_id ? nameOf(x.owner_id) : '';
        var when = (done || na) && x.updated_at ? shortDate(x.updated_at) : '';
        var line = done ? 'Ticked' + (by ? ' by ' + by : '') + (when ? ' · ' + when : '')
          : na ? 'Not needed' + (by ? ' · ' + by : '') + (when ? ' · ' + when : '') : '';
        return '<div class="mcheck' + (done ? ' is-done' : na ? ' is-na' : '') + '" data-key="' + esc(x.key) + '">' +
          (can
            ? '<button class="tcheck' + (done ? ' is-done' : '') + '" type="button" data-a="tick" aria-pressed="' + done + '"' +
                (na ? ' disabled' : '') + ' aria-label="' + esc(checkWord(x.key)) + '"></button>'
            : '<span class="tcheck' + (done ? ' is-done' : '') + '" aria-hidden="true"></span>') +
          '<span class="mcheck-lab"><span>' + esc(checkWord(x.key)) + '</span>' +
            (line ? '<small>' + esc(line) + '</small>' : '') + '</span>' +
          (can && !done
            ? '<button class="btn-quiet btn-sm mcheck-na" type="button" data-a="na">' + (na ? 'Needed' : 'Not needed') + '</button>'
            : '') +
        '</div>';
      }).join('') +
    '</div>';
  }
  /* A tick is sent on the press and the list repainted from the answer. */
  function wireChecks(root, e, sayIn, after) {
    Array.prototype.forEach.call(root.querySelectorAll('.mcheck'), function (row) {
      var key = row.getAttribute('data-key');
      var cur = row.classList.contains('is-done') ? 'ready' : row.classList.contains('is-na') ? 'na' : 'not_started';
      var send = function (to, btn) {
        if (btn) btn.disabled = true;
        call2('ops_engagement_set_check', { p_engagement: e.id, p_key: key, p_state: to }, sayIn, function (d) {
          after((d && d.checks) || []);
        }, function () { if (btn) btn.disabled = false; });
      };
      var tk = row.querySelector('[data-a="tick"]');
      if (tk) tk.addEventListener('click', function () { send(cur === 'ready' ? 'not_started' : 'ready', tk); });
      var na = row.querySelector('[data-a="na"]');
      if (na) na.addEventListener('click', function () { send(cur === 'na' ? 'not_started' : 'na', na); });
    });
  }
  /* What the engagement is waiting on, in one line. */
  function meetingWord(e) {
    if (!e) return '';
    if (e.meeting_na) return 'No meeting this month';
    if (!e.meeting_at) return 'Not scheduled';
    var when = niceTime(e.meeting_at);
    return when + (e.meeting_channel ? ' · ' + (CHANNEL_WORD[e.meeting_channel] || sentence(e.meeting_channel)) : '') +
      (e.meeting_owner_id ? ' · ' + nameOf(e.meeting_owner_id) : '');
  }
  function meetingHeld(e) {
    return Boolean(e && (e.meeting_na || (e.meeting_at && new Date(e.meeting_at) <= new Date())));
  }
  /* 11:30am, the way the message to a client writes a time. */
  function clock(v) {
    var d = new Date(v);
    if (isNaN(d.getTime())) return '';
    var h = d.getHours(), m = d.getMinutes();
    return ((h % 12) || 12) + ':' + String(m).padStart(2, '0') + (h < 12 ? 'am' : 'pm');
  }
  /* THE MESSAGE TO THE CLIENT, in the team's own template, filled from the
     month: the date, the time it starts and ends, the content month it is
     about, where it is held and the link. Written here and nowhere else, so
     the card and the task step copy the same words. */
  function clientMessage(e) {
    if (!e || !e.meeting_at || e.meeting_na) return '';
    var at = new Date(e.meeting_at);
    var end = new Date(at.getTime() + (Number(e.meeting_minutes) || 30) * 60000);
    var online = e.meeting_channel !== 'onsite';
    var lines = [
      'Meeting Schedule ' + (online ? '\u7ebf\u4e0a\u4f1a\u8bae' : '\u4f1a\u8bae'),
      '',
      'Date \u65e5\u671f: ' + String(at.getDate()).padStart(2, '0') + '/' + String(at.getMonth() + 1).padStart(2, '0') + '/' + at.getFullYear(),
      'Time \u65f6\u95f4: ' + clock(at) + ' \u2013 ' + clock(end),
      '',
      'Meeting Agenda \u6458\u8981:',
      '\u2022  ' + monthWord(e.period) + ' Content Discussion'
    ];
    if (e.meeting_channel) {
      lines.push('', 'Channel \u6e20\u9053:', CHANNEL_WORD[e.meeting_channel] || sentence(e.meeting_channel));
      if (e.meeting_link) lines.push('Link: ' + e.meeting_link);
    }
    return lines.join('\n');
  }
  /* The content meeting as it is drawn on the month's card and in a task's
     next step: when and where, the link once there is one, the button that
     books Google Meet on the shared calendar, and the message to the client
     with its Copy. */
  function meetHtml(e, can) {
    var set = e.meeting_at && !e.meeting_na;
    var bookable = can && set && e.meeting_channel === 'google_meet' && !e.meeting_link;
    return '<div class="eng-meet"><span class="eng-lab">Content meeting</span>' +
        '<span class="eng-meetword' + (meetingHeld(e) ? ' is-held' : '') + '">' + esc(meetingWord(e)) + '</span>' +
        (can ? '<span class="eng-meetacts">' +
          (bookable ? '<button class="btn btn-sm" data-a="book" type="button">Create Google Meet</button>' : '') +
          '<button class="btn btn-sm" data-a="meet" type="button">' + (e.meeting_at || e.meeting_na ? 'Change' : 'Set meeting') + '</button>' +
        '</span>' : '') +
      '</div>' +
      (set && e.meeting_link
        ? '<div class="eng-meetlink"><span class="eng-lab">Link</span>' +
            '<a class="ovlink" href="' + esc(e.meeting_link) + '" target="_blank" rel="noopener">' +
              esc(e.meeting_link.replace(/^https:\/\//, '')) + '</a></div>'
        : '') +
      (set
        ? '<div class="eng-meetmsg"><div class="eng-meetmsg-head"><span class="eng-lab">Message to client</span>' +
            '<span class="eng-meetacts">' +
              '<button class="btn btn-sm" data-a="msgshow" type="button" aria-expanded="false">Show</button>' +
              '<button class="btn btn-sm" data-a="msgcopy" type="button"><span>Copy</span></button>' +
            '</span></div>' +
            '<pre class="eng-meetmsg-text" hidden>' + esc(clientMessage(e)) + '</pre></div>'
        : '') +
      (meetWarn && meetWarn.id === e.id ? '<div class="msg warn eng-meetwarn">' + esc(meetWarn.text) + '</div>' : '');
  }
  function wireMeet(root, e, sayIn, open, after) {
    var mb = root.querySelector('[data-a="meet"]');
    if (mb) mb.addEventListener('click', open);
    var bk = root.querySelector('[data-a="book"]');
    if (bk) bk.addEventListener('click', function () {
      meetWarn = null;
      bk.disabled = true;
      bk.textContent = 'Booking';
      meetCall(e, 'create', function (d) {
        if (d && !d.error) { after(); return; }
        bk.disabled = false;
        bk.textContent = 'Create Google Meet';
        if (typeof sayIn === 'string') { msg(sayIn, meetSaid(d), 'warn'); return; }
        var m = sayIn && sayIn.querySelector('[data-a="msg"]');
        if (m) { m.textContent = meetSaid(d); m.className = 'msg warn'; }
      });
    });
    var sh = root.querySelector('[data-a="msgshow"]');
    var pre = root.querySelector('.eng-meetmsg-text');
    if (sh && pre) sh.addEventListener('click', function () {
      pre.hidden = !pre.hidden;
      sh.textContent = pre.hidden ? 'Show' : 'Hide';
      sh.setAttribute('aria-expanded', String(!pre.hidden));
    });
    var cp = root.querySelector('[data-a="msgcopy"]');
    if (cp) cp.addEventListener('click', function () {
      if (window.ADspaceCopy) window.ADspaceCopy.to(cp, clientMessage(e));
    });
  }

  /* THE CLIENT RECORD'S WORK PANE. The client's tasks by month, each month
     under its engagement record, drawn by this script because the words, the
     gates and the sheets are My Work's. Reads its own rows: a client record
     is opened for one client, and the queue's read is for a person. */
  var cw = { box: null, client: null, tasks: [], engs: [], checks: [], owners: {}, ownerIds: {},
             find: '', status: 'open', period: '', who: '' };
  function clientWork(box, client) {
    if (!box || !client) return;
    cw.box = box; cw.client = client;
    cw.find = ''; cw.status = 'open'; cw.period = ''; cw.who = '';
    UI.skeleton(box, 4);
    var ready = function () { readClientWork(); };
    if (!state.workflows.length) loadCatalogue(ready); else ready();
  }
  function readClientWork() {
    var box = cw.box, c = cw.client;
    Promise.all([
      db.from('ops_tasks').select('*, clients(name, slug)').eq('client_id', c.id).is('archived_at', null)
        .order('code_period', { ascending: false, nullsFirst: false })
        .order('current_final_due_at', { ascending: true, nullsFirst: false }).limit(600),
      db.from('ops_engagements').select('*').eq('client_id', c.id).order('period', { ascending: false }),
      db.from('ops_task_assignees')
        .select('task_id, responsibility, team_member_id, team_members!ops_task_assignees_team_member_id_fkey(name)')
        .is('ended_at', null)
    ]).then(function (r) {
      var bad = (r[0] && r[0].error) || (r[1] && r[1].error);
      if (bad) { UI.failLine(box, 'This client\'s work', bad.message, readClientWork); return; }
      cw.tasks = (r[0] && r[0].data) || [];
      cw.engs = (r[1] && r[1].data) || [];
      cw.owners = {}; cw.ownerIds = {};
      ((r[2] && r[2].data) || []).forEach(function (a) {
        if (a.responsibility !== 'owner') return;
        cw.owners[a.task_id] = (a.team_members && a.team_members.name) || '';
        cw.ownerIds[a.task_id] = a.team_member_id;
      });
      var ids = cw.engs.map(function (e) { return e.id; });
      if (!ids.length) { cw.checks = []; paintClientWork(); return; }
      db.from('ops_engagement_checks').select('*').in('engagement_id', ids).then(function (q) {
        cw.checks = (q && !q.error && q.data) || [];
        paintClientWork();
      }, function () { cw.checks = []; paintClientWork(); });
    }, function (e) {
      UI.failLine(box, 'This client\'s work', (e && e.message) || String(e), readClientWork);
    });
  }
  function cwPeriodOf(t) {
    return t.code_period || (t.current_final_due_at ? String(t.current_final_due_at).slice(0, 7) : '') || 'none';
  }
  function cwMatches(t) {
    if (cw.period && cwPeriodOf(t) !== cw.period) return false;
    if (cw.who && cw.ownerIds[t.id] !== cw.who) return false;
    var s = stageOf(t);
    if (cw.status === 'open' && isFinished(t)) return false;
    if (cw.status === 'done' && !isFinished(t)) return false;
    if (cw.status === 'late' && !isLate(t)) return false;
    if (cw.status === 'client_review' && !(s && s.stage_group === 'client_review')) return false;
    if (cw.status === 'internal_review' && !(s && s.stage_group === 'internal_review')) return false;
    if (cw.status === 'active' && !(s && s.is_active_work)) return false;
    if (cw.find) {
      var hay = [t.title, t.code, t.content_desc, formatWord(t), cw.owners[t.id], serialOf(t), stageLabel(t)].join(' ').toLowerCase();
      if (hay.indexOf(cw.find) < 0 && hay.indexOf('#' + cw.find) < 0) return false;
    }
    return true;
  }
  function paintClientWork() {
    var box = cw.box, c = cw.client;
    if (!box) return;
    var canWork = may('ops', 'work');
    /* The periods on the page: every engagement's month and every task's,
       newest first, so the select offers only months that hold something. */
    var periods = {};
    cw.engs.forEach(function (e) { periods[e.period] = 1; });
    cw.tasks.forEach(function (t) { periods[cwPeriodOf(t)] = 1; });
    var months = Object.keys(periods).filter(function (k) { return k !== 'none'; }).sort().reverse();
    var owners = {};
    cw.tasks.forEach(function (t) { if (cw.ownerIds[t.id]) owners[cw.ownerIds[t.id]] = cw.owners[t.id]; });

    box.innerHTML =
      '<div class="viewhead"><span class="headmark"><h2>Work</h2></span>' +
        (canWork
          ? '<button class="btn" id="cwEng" type="button">New month</button>' +
            '<button class="btn btn-primary" id="cwNew" type="button">' +
              '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>New task</button>'
          : '') +
      '</div>' +
      '<div class="workfilters">' +
        '<label class="cmdbar-find"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>' +
          '<input class="input input-sm" id="cwFind" type="search" placeholder="Search tasks" aria-label="Search tasks" autocomplete="off"></label>' +
        '<select class="select select-sm" id="cwStatus" aria-label="Filter by status">' +
          '<option value="open">Open work</option><option value="active">In progress</option>' +
          '<option value="internal_review">AQC review</option><option value="client_review">Client review</option>' +
          '<option value="late">Late</option><option value="done">Finished</option><option value="">Everything</option>' +
        '</select>' +
        '<select class="select select-sm" id="cwPeriod" aria-label="Filter by month"><option value="">Every month</option>' +
          months.map(function (k) { return '<option value="' + k + '">' + esc(monthWord(k)) + '</option>'; }).join('') +
        '</select>' +
        '<select class="select select-sm" id="cwWho" aria-label="Filter by owner"><option value="">Anybody</option>' +
          Object.keys(owners).map(function (id) { return '<option value="' + esc(id) + '">' + esc(owners[id]) + '</option>'; }).join('') +
        '</select>' +
        '<span class="cmdbar-count" id="cwCount"></span>' +
      '</div>' +
      '<div class="msg" id="cwMsg"></div>' +
      '<div id="cwList" data-narrow="860"></div>';
    if (UI.fit) UI.fit('#cwList');
    $('cwFind').value = cw.find; $('cwStatus').value = cw.status;
    $('cwPeriod').value = cw.period; $('cwWho').value = cw.who;
    $('cwFind').addEventListener('input', function () {
      var v = String(this.value || '').trim().toLowerCase();
      if (v === cw.find) return;
      cw.find = v; paintClientList();
    });
    $('cwStatus').addEventListener('change', function () { cw.status = this.value; paintClientList(); });
    $('cwPeriod').addEventListener('change', function () { cw.period = this.value; paintClientList(); });
    $('cwWho').addEventListener('change', function () { cw.who = this.value; paintClientList(); });
    var nb = $('cwNew');
    if (nb) nb.addEventListener('click', function () { openNew({ client: c }); });
    var eb = $('cwEng');
    if (eb) eb.addEventListener('click', function () { openEng(null, c); });
    paintClientList();
  }
  function paintClientList() {
    var list = $('cwList'), c = cw.client;
    if (!list) return;
    var rows = cw.tasks.filter(cwMatches);
    var count = $('cwCount');
    if (count) {
      count.textContent = !cw.tasks.length ? ''
        : rows.length === cw.tasks.length ? rows.length + (rows.length === 1 ? ' task' : ' tasks')
        : rows.length + ' of ' + cw.tasks.length;
    }
    list.innerHTML = '';
    /* A month is a card: the engagement's own facts at its head where one
       exists, the month's tasks under it. Newest month first, this month
       open, the rest shut, because a year of months is a page nobody
       scrolls. Tasks with no month go last under their own heading. */
    var by = {};
    rows.forEach(function (t) {
      var k = cwPeriodOf(t);
      (by[k] = by[k] || []).push(t);
    });
    var keys = Object.keys(by);
    cw.engs.forEach(function (e) {
      if (!cw.period || cw.period === e.period) { if (keys.indexOf(e.period) < 0) { keys.push(e.period); by[e.period] = []; } }
    });
    keys = keys.filter(function (k) { return k !== 'none'; }).sort().reverse().concat(by.none ? ['none'] : []);
    if (!keys.length) {
      UI.emptyLine(list, cw.tasks.length ? 'No matches.' : 'No tasks.',
        cw.tasks.length ? 'Clear the filters' : (may('ops', 'work') ? 'Add the first task' : ''),
        cw.tasks.length
          ? function () { cw.find = ''; cw.status = 'open'; cw.period = ''; cw.who = ''; paintClientWork(); }
          : function () { openNew({ client: c }); });
      return;
    }
    var thisMonth = monthKey(new Date());
    keys.forEach(function (k) {
      var eng = cw.engs.filter(function (e) { return e.period === k; })[0] || null;
      var trs = (by[k] || []).slice().sort(byPriority);
      var late = trs.filter(isLate).length;
      var open = trs.filter(function (t) { return !isFinished(t); }).length;
      var card = GRP.section({
        route: 'cwork', key: k, name: k === 'none' ? 'No month' : monthWord(k),
        count: trs.length,
        marks: (eng ? '<span class="tone ' + toneOf(ENG_STATE, eng.status) + '">' + esc(wordOf(ENG_STATE, eng.status)) + '</span>' : '') +
               (late ? '<span class="tone is-warn">' + late + ' late</span>' : ''),
        /* Open: this month, a month still being worked, a month still being
           planned (no tasks yet is exactly when its meeting is set), and a
           month somebody filtered to, which is the only card on the page. */
        shut: cw.period === k ? false
          : GRP.shut('cwork', k, k !== thisMonth && !(eng && eng.status !== 'completed' && (open || !trs.length)), false),
        table: function () {
          var wrap = document.createElement('div');
          if (eng) wrap.appendChild(engCard(eng));
          if (trs.length) {
            var table = GRP.table('svc-row task-row', ['', 'Task', 'Task Owner', 'Due', 'Stage', '']);
            GRP.more(table, trs, 30, 'tasks', function (t) { return rowOf(t, true); });
            wrap.appendChild(table);
          } else if (eng) {
            var line = document.createElement('div');
            UI.emptyLine(line, 'No tasks this month.', may('ops', 'work') ? 'Add a task' : '',
              function () { openNew({ client: c, period: k, engagement: eng }); });
            wrap.appendChild(line);
          }
          return wrap;
        }
      });
      list.appendChild(card);
    });
  }

  /* THE ENGAGEMENT CARD: the month's facts, the meeting, the readiness
     list. Everything in it is a control where the person may work the
     section and a fact where they may not. */
  function engCard(e) {
    var can = may('ops', 'work');
    var el = document.createElement('section');
    el.className = 'engcard';
    el.setAttribute('data-eng', e.id);
    var checks = checksOf(e, cw.checks);
    var facts = [
      ['Manager', nameOf(e.manager_id)],
      ['Planned', e.planned_count ? e.planned_count + (e.planned_count === 1 ? ' piece' : ' pieces') : ''],
      ['Files', e.drive_url ? '<a class="ovlink" href="' + esc(e.drive_url) + '" target="_blank" rel="noopener">Drive folder</a>' : '']
    ].filter(function (p) { return p[1]; });
    var items = [['edit', 'Edit']];
    if (may('ops', 'manage')) items.push(['delete', 'Delete', true]);
    el.innerHTML =
      '<div class="eng-head">' +
        '<div class="eng-who"><h3>' + esc(monthWord(e.period)) + '</h3>' +
          '<p class="eng-meta">' + facts.map(function (p) { return '<span><span class="eng-lab">' + esc(p[0]) + '</span> ' + p[1] + '</span>'; }).join('') + '</p></div>' +
        '<div class="eng-ctl">' +
          (can
            ? '<select class="select select-sm state-select ' + toneOf(ENG_STATE, e.status) + '" data-a="status" aria-label="Status of ' + esc(monthWord(e.period)) + '">' +
                ENG_STATE.map(function (s) { return '<option value="' + s[0] + '"' + (s[0] === e.status ? ' selected' : '') + '>' + esc(s[1]) + '</option>'; }).join('') +
              '</select>' + itemMenu(monthWord(e.period), items)
            : '<span class="tone ' + toneOf(ENG_STATE, e.status) + '">' + esc(wordOf(ENG_STATE, e.status)) + '</span>') +
        '</div>' +
      '</div>' +
      '<div class="msg" data-a="msg"></div>' +
      meetHtml(e, can) +
      '<div data-a="checks">' + checksHtml(e, checks, can) + '</div>';
    var st = el.querySelector('[data-a="status"]');
    if (st) st.addEventListener('change', function () {
      var want = st.value;
      call2('ops_engagement_set_status', { p_engagement: e.id, p_status: want, p_version: e.version }, el, function () {
        readClientWork();
      }, function () { st.value = e.status; });
    });
    var ctl = el.querySelector('.eng-ctl');
    if (ctl && ctl.querySelector('.kmenu-btn')) wireItemMenu(ctl, function (k) {
      if (k === 'edit') openEng(e, cw.client);
      if (k === 'delete') askDeleteMonth(e, cw.client, readClientWork);
    });
    wireMeet(el, e, el, function () { openMeet(e); }, readClientWork);
    /* The two ticks repaint themselves from the answer, never the list. */
    var box = el.querySelector('[data-a="checks"]');
    var paintChecks = function () {
      box.innerHTML = checksHtml(e, checksOf(e, cw.checks), can);
      wireChecks(box, e, el, function (fresh) {
        cw.checks = cw.checks.filter(function (x) { return x.engagement_id !== e.id; }).concat(fresh);
        paintChecks();
      });
    };
    paintChecks();
    return el;
  }
  /* Deleting a month: ops Manage, a reason, and the tasks it held stay. */
  function askDeleteMonth(e, client, after) {
    var n = e.task_count != null ? e.task_count
      : (cw.tasks || []).filter(function (t) { return t.engagement_id === e.id; }).length;
    window.ADspaceConfirm.ask({
      title: 'Delete ' + monthWord(e.period) + (client && client.name ? ' for ' + client.name : ''),
      body: (n ? (n === 1 ? 'Its task stays and leaves the month.' : 'Its ' + n + ' tasks stay and leave the month.') + ' ' : '') +
        (!checksOf(e, cw.checks).length ? 'The meeting goes with it.'
          : (cw.engs || []).some(function (x) { return x.id !== e.id; })
            ? 'Its readiness ticks move to the next month; the meeting goes with it.'
            : 'The readiness ticks and the meeting go with it.') +
        ' There is no restore.',
      go: 'Delete', tone: 'danger',
      field: { label: 'Reason', rows: 2, need: 'A reason is required.' }
    }, function (why) {
      db.rpc('ops_delete_engagement', { p_engagement: e.id, p_reason: why }).then(function (r) {
        var err = r.error ? r.error.message : (r.data && r.data.error ? said(r.data.error) : '');
        if (err) { window.ADspaceConfirm.ask({ title: 'Not deleted', body: err, go: 'Close', cancel: false }, function () {}); return; }
        if (after) after();
      }, function (x) {
        window.ADspaceConfirm.ask({ title: 'Not deleted', body: (x && x.message) || String(x), go: 'Close', cancel: false }, function () {});
      });
    });
  }
  /* A refusal is named on the card it was made on. */
  function call2(fn, args, el, then, onFail) {
    var m = typeof el === 'string' ? $(el) : el.querySelector('[data-a="msg"]');
    var say = function (text, tone) { if (m) { m.textContent = text || ''; m.className = 'msg ' + (text ? (tone || 'err') : ''); } };
    say('');
    db.rpc(fn, args).then(function (r) {
      if (r.error) { say(dbWord(r.error.message)); if (onFail) onFail(); return; }
      var d = r.data;
      if (d && d.error) { say(said(d.error)); if (onFail) onFail(); return; }
      if (then) then(d);
    }, function (e) { say((e && e.message) || String(e)); if (onFail) onFail(); });
  }

  /* The engagement's own facts: made for a month that has none, edited for
     one that has. */
  var engEditing = null;
  function openEng(e, client) {
    if (!may('ops', 'work')) return;
    engEditing = e || null;
    $('engTitle').textContent = e ? monthWord(e.period) + ' for ' + esc(client.name) : 'New month for ' + client.name;
    fillMonths($('engPeriod'), e ? e.period : null);
    $('engPeriod').disabled = Boolean(e);
    var me = bridge.me && bridge.me();
    $('engManager').innerHTML = state.members.map(function (m) {
      var pick = e ? m.id === e.manager_id : (me && me.id === m.id);
      return '<option value="' + esc(m.id) + '"' + (pick ? ' selected' : '') + '>' + esc(m.name) + '</option>';
    }).join('');
    $('engPlanned').value = e ? (e.planned_count || '') : '';
    $('engDrive').value = (e && e.drive_url) || '';
    msg('engMsg', '');
    sheet('engSheet', true);
  }
  function saveEng() {
    var c = cw.client;
    if (!c) return;
    var payload = {
      client_id: c.id, period: engEditing ? engEditing.period : $('engPeriod').value,
      manager_id: $('engManager').value || null,
      planned_count: Number($('engPlanned').value) || 0,
      drive_url: String($('engDrive').value || '').trim()
    };
    var btn = $('engGo');
    btn.disabled = true;
    call('ops_engagement_upsert', { p_payload: payload }, 'engMsg', function () {
      btn.disabled = false;
      sheet('engSheet', false);
      readClientWork();
    }, function () { btn.disabled = false; });
  }
  var meetEditing = null;
  var meetAfter = null;
  var meetWarn = null;
  function openMeet(e) {
    if (!may('ops', 'work')) return;
    meetEditing = e;
    meetWarn = null;
    meetAfter = null;
    var at = e.meeting_at ? new Date(e.meeting_at) : null;
    $('meetDate').value = at ? at.getFullYear() + '-' + String(at.getMonth() + 1).padStart(2, '0') + '-' + String(at.getDate()).padStart(2, '0') : '';
    $('meetTime').value = at ? String(at.getHours()).padStart(2, '0') + ':' + String(at.getMinutes()).padStart(2, '0') : '';
    /* Error prevention: a meeting first put in the diary is today or later. */
    if (!e.meeting_at) $('meetDate').setAttribute('min', monthKey(new Date()) + '-' + String(new Date().getDate()).padStart(2, '0'));
    else $('meetDate').removeAttribute('min');
    $('meetChannel').value = e.meeting_channel || 'google_meet';
    $('meetMinutes').value = String(e.meeting_minutes || 30);
    if (!$('meetMinutes').value) $('meetMinutes').value = '30';
    $('meetLink').value = e.meeting_link || '';
    $('meetBook').checked = true;
    var me = bridge.me && bridge.me();
    $('meetOwner').innerHTML = state.members.map(function (m) {
      var pick = e.meeting_owner_id ? m.id === e.meeting_owner_id : (me && me.id === m.id);
      return '<option value="' + esc(m.id) + '"' + (pick ? ' selected' : '') + '>' + esc(m.name) + '</option>';
    }).join('');
    $('meetNote').value = e.meeting_note || '';
    $('meetNa').checked = Boolean(e.meeting_na);
    meetNaChanged();
    msg('meetMsg', '');
    sheet('meetSheet', true);
  }
  function meetNaChanged() {
    var na = $('meetNa').checked;
    ['meetDate', 'meetTime', 'meetMinutes', 'meetChannel', 'meetOwner', 'meetLink', 'meetBook'].forEach(function (id) { $(id).disabled = na; });
    meetBookShown();
  }
  /* The calendar is offered only where it can do something: a Google Meet
     meeting with no link typed and no event on the calendar yet. Once there
     is an event, a moved meeting moves it without being asked. */
  function meetBookShown() {
    var e = meetEditing;
    var show = !$('meetNa').checked && $('meetChannel').value === 'google_meet' &&
      !String($('meetLink').value || '').trim() && !(e && e.meeting_event_id);
    $('meetBookLine').hidden = !show;
  }
  /* What the edge function answered, in the team's words. */
  function meetSaid(d) {
    var k = d && d.error;
    if (k === 'meet-not-set-up') {
      var miss = (d.missing || []).join(', ');
      return 'Google Meet is not connected yet' + (miss ? ': ' + miss + ' is not set in Supabase' : '') + '. Paste a link instead.';
    }
    /* Google turned the shared account's sign-in away: the word it gave says
       which secret to replace. */
    if (k === 'google-token') {
      var rs = String(d.reason || '');
      if (rs === 'invalid_grant') return 'Google refused the refresh token. Get a new one from OAuth Playground and replace GOOGLE_REFRESH_TOKEN.';
      if (rs === 'invalid_client' || rs === 'unauthorized_client') return 'Google refused the client ID or secret. Check GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET match the OAuth client the token was made with.';
      return 'Google refused the sign-in' + (rs ? ' (' + rs + ')' : '') + '.';
    }
    if (k === 'google-refused' && /accessNotConfigured|SERVICE_DISABLED/i.test(String(d.reason || ''))) {
      return 'The Google Calendar API is not enabled on the Google Cloud project.';
    }
    if (k === 'google-refused' && /insufficient|PERMISSION_DENIED|forbidden/i.test(String(d.reason || ''))) {
      return 'The refresh token does not carry calendar access. Make it again with the calendar.events scope.';
    }
    if (k === 'meet-pending') return 'The calendar event is booked and Google is still making its Meet link. Press Create Google Meet again in a moment.';
    if (k === 'unreachable') return 'Google Meet could not be reached. Try again, or paste a link.';
    if (k === 'slot-taken') {
      var span = d.start ? clock(d.start) + (d.end ? ' to ' + clock(d.end) : '') : '';
      return 'The shared calendar already has ' + (d.summary ? '\u201c' + d.summary + '\u201d' : 'a meeting') +
        (span ? ' at ' + span : '') + '. Choose another time.';
    }
    if (k === 'google-refused') return 'Google refused the booking' + (d.reason ? ' (' + d.reason + ')' : '') + '. Try again.';
    if (k === 'not-saved') return 'The event was made but its link was not saved. Try again.';
    return k ? said(k) : 'Google Meet could not be reached. Paste a link instead.';
  }
  /* Ask the shared calendar: `create` books the meeting or moves the event
     it already has, `delete` takes it off. */
  function meetCall(e, action, done) {
    if (!db.functions || !db.functions.invoke) { done({ error: 'meet-not-set-up' }); return; }
    db.functions.invoke('meet-create', { body: { engagementId: e.id, action: action } }).then(function (r) {
      if (r.error) { done({ error: 'unreachable' }); return; }
      done(r.data || {});
    }, function () { done({ error: 'unreachable' }); });
  }
  function saveMeet() {
    var e = meetEditing;
    if (!e) return;
    var na = $('meetNa').checked;
    var args = { p_engagement: e.id, p_note: String($('meetNote').value || '').trim() || null, p_na: na };
    var link = String($('meetLink').value || '').trim();
    var channel = $('meetChannel').value || null;
    if (!na) {
      if (!$('meetDate').value) { msg('meetMsg', said('no-date'), 'err'); $('meetDate').focus(); return; }
      if (link && !/^https:\/\/([a-z0-9-]+\.)*(meet\.google\.com|zoom\.us|teams\.microsoft\.com|teams\.live\.com)\//i.test(link)) {
        msg('meetMsg', said('bad-meeting-link'), 'err'); $('meetLink').focus(); return;
      }
      var when = new Date($('meetDate').value + 'T' + ($('meetTime').value || '10:00') + ':00');
      args.p_at = when.toISOString();
      args.p_channel = channel;
      args.p_owner = $('meetOwner').value || null;
      args.p_minutes = Number($('meetMinutes').value) || 30;
      args.p_link = link;
    } else { args.p_at = null; }
    /* What the shared calendar has to do after the save: take the event off
       where the month no longer meets on Google Meet, move it where it does,
       and book it where somebody asked for a link. */
    var calendar = null;
    if (e.meeting_event_id && (na || channel !== 'google_meet')) calendar = 'delete';
    else if (!na && channel === 'google_meet' && (e.meeting_event_id || (!link && $('meetBook').checked))) calendar = 'create';
    var btn = $('meetGo');
    btn.disabled = true;
    /* Opened from a task, the task repaints; from the month, the month. */
    var repaint = function () { if (meetAfter) meetAfter(); else readClientWork(); };
    var finish = function () {
      btn.disabled = false;
      sheet('meetSheet', false);
      repaint();
      meetAfter = null;
    };
    call('ops_engagement_set_meeting', args, 'meetMsg', function (fresh) {
      if (!calendar) { finish(); return; }
      if (fresh && fresh.id) meetEditing = fresh;
      msg('meetMsg', calendar === 'delete' ? 'Removing it from the shared calendar.' : 'Booking the shared calendar.');
      meetCall(e, calendar, function (d) {
        if (d && !d.error) { finish(); return; }
        /* Google not connected is not something this sheet can fix: the
           meeting is saved, the sheet closes, and the line says so under
           the meeting it is about. */
        if (!d || d.error === 'meet-not-set-up' || d.error === 'google-token' || d.error === 'meet-pending' || d.error === 'unreachable') {
          meetWarn = { id: e.id, text: 'Saved. ' + meetSaid(d) };
          finish();
          return;
        }
        /* A clash or a refusal can be put right here: the meeting is saved,
           the sheet stays open so the time can change, and the list behind
           it already shows the save. */
        btn.disabled = false;
        if (d && d.error === 'slot-taken') $('meetTime').focus();
        msg('meetMsg', 'Saved. ' + meetSaid(d), 'warn');
        meetBookShown();
        repaint();
      });
    }, function () { btn.disabled = false; });
  }

  /* MOVE TO ANOTHER STAGE. Every move the workflow allows from here, with
     the next person on the same move where the work changes hands. Passing
     over a step is an override: it is offered to ops Manage only, and the
     database refuses it to anybody else whatever the page sends. A move back
     takes a reason. */
  function openMove() {
    var t = state.task;
    if (!t || !may('ops', 'work')) return;
    var here = stageOf(t);
    var nexts = (here && here.next_stage_keys) || [];
    var manage = may('ops', 'manage');
    var opts = stagesOf(t.workflow_id).filter(function (s) {
      if (s.key === t.stage_key || s.key === 'blocked') return false;
      if (nexts.indexOf(s.key) > -1) return true;
      return manage && here && s.position > here.position && !SIDE[s.stage_group] && !SIDE[here.stage_group];
    });
    $('handStage').innerHTML = opts.map(function (s) {
      var skip = nexts.indexOf(s.key) < 0;
      var backw = !skip && here && s.position < here.position && !SIDE[s.stage_group];
      return '<option value="' + esc(s.key) + '" data-skip="' + (skip ? '1' : '') + '" data-back="' + (backw ? '1' : '') + '">' +
        esc(s.label) + (skip ? ' (skips a step)' : '') + '</option>';
    }).join('');
    var first = nextOf(t);
    if (first && opts.some(function (s) { return s.key === first; })) $('handStage').value = first;
    var owner = ownerId(t);
    $('handTo').innerHTML = '<option value="">Keep ' + esc(ownerName(t) || 'the owner') + '</option>' + state.members.filter(function (m) {
      return m.id !== owner;
    }).map(function (m) {
      return '<option value="' + esc(m.id) + '">' + esc(m.name) + '</option>';
    }).join('');
    $('handWhat').textContent = 'Now at ' + stageLabel(t) + '.';
    $('handSkip').value = '';
    $('handNote').value = '';
    handStageChanged();
    msg('handMsg', '');
    sheet('handSheet', true);
  }
  function handStageChanged() {
    var sel = $('handStage');
    var o = sel.options[sel.selectedIndex];
    var skip = Boolean(o && o.getAttribute('data-skip'));
    var back = Boolean(o && o.getAttribute('data-back'));
    $('handSkipRow').hidden = !(skip || back);
    $('handSkipLabel').textContent = skip ? 'Why the steps between are skipped' : 'Why it goes back';
  }
  function doHand() {
    var t = state.task;
    if (!t) return;
    var sel = $('handStage');
    var o = sel.options[sel.selectedIndex];
    if (!o) return;
    var skipping = Boolean(o.getAttribute('data-skip'));
    var backw = Boolean(o.getAttribute('data-back'));
    var reason = String($('handSkip').value || '').trim();
    if ((skipping || backw) && !reason) { msg('handMsg', said('reason-required'), 'err'); $('handSkip').focus(); return; }
    var note = String($('handNote').value || '').trim();
    if (sel.value === 'blocked') { sheet('handSheet', false); openBlock(); return; }
    var btn = $('handGo');
    btn.disabled = true;
    var to = $('handTo').value || null;
    call('ops_transition_task', {
      p_task: t.id, p_next: sel.value, p_version: t.version,
      p_note: (backw ? reason + (note ? ' · ' + note : '') : note) || null,
      p_assignee: to,
      p_skip_reason: skipping ? reason : null
    }, 'handMsg', function (d) {
      btn.disabled = false;
      sheet('handSheet', false);
      /* The queue behind the record agrees without a second read. */
      if (to) { state.owners[t.id] = nameOf(to); state.ownerIds[t.id] = to; }
      applyTask(d);
      readTask(t.id);
    }, function () { btn.disabled = false; });
  }

  /* HAND OVER TASK. Responsibility changes and the stage stays where it is.
     The sheet shows what the next person is taking on before it is made:
     what is left on the checklist and when it is owed. */
  function openGive() {
    var t = state.task;
    if (!t || !may('ops', 'manage')) return;
    var owner = ownerId(t);
    $('giveTo').innerHTML = '<option value="">Choose a person</option>' + state.members.filter(function (m) {
      return m.id !== owner;
    }).map(function (m) {
      return '<option value="' + esc(m.id) + '">' + esc(m.name) + '</option>';
    }).join('');
    $('giveNote').value = '';
    var open = state.detail.checklist.filter(function (c) { return !c.completed_at; });
    $('giveFacts').innerHTML =
      frow('Owner now', esc(ownerName(t) || 'Nobody')) +
      frow('Stage', esc(stageLabel(t)) + ' <span class="mute">stays as it is</span>') +
      frow('Final due', t.current_final_due_at ? esc(niceDate(t.current_final_due_at)) : '<span class="mute">Not set</span>') +
      (open.length ? frow('Still to do', '<ul class="givelist">' + open.map(function (c) {
        return '<li>' + esc(c.label) + '</li>'; }).join('') + '</ul>') : '');
    msg('giveMsg', '');
    sheet('giveSheet', true);
  }
  function doGive() {
    var t = state.task;
    if (!t) return;
    var to = $('giveTo').value;
    if (!to) { msg('giveMsg', 'Choose the new owner.', 'err'); $('giveTo').focus(); return; }
    var btn = $('giveGo');
    btn.disabled = true;
    call('ops_hand_over_task', {
      p_task: t.id, p_owner: to,
      p_note: String($('giveNote').value || '').trim() || null,
      p_version: t.version
    }, 'giveMsg', function (d) {
      btn.disabled = false;
      sheet('giveSheet', false);
      state.owners[t.id] = nameOf(to); state.ownerIds[t.id] = to;
      applyTask(d);
      readTask(t.id, function () { msg('taskOwnerMsg', 'Handed to ' + nameOf(to) + '.', 'ok'); });
    }, function () { btn.disabled = false; });
  }

  /* A task opened from a client record: the address first, because My Work
     reads it on entry, then the route. */
  function openTaskElsewhere(id) {
    openDrawer(id, { from: 'client' });
  }

  // ---- Wiring --------------------------------------------------------------
  function wire() {
    var find = $('workFind');
    if (find) {
      /* One control, one listener: `input` and `change` both fire for a
         keystroke and the second arrives on blur, which is how a Clear button
         once detached itself between mousedown and click. */
      var findWait = null;
      find.addEventListener('input', function () {
        var v = String(find.value || '').trim().toLowerCase();
        if (v === state.find) return;
        state.find = v;
        paint();
        /* Completed work is searched in the database, after a pause, so a
           search across a year of history does not ask on every keystroke. */
        if (state.filter === 'done' || state.filter === 'all') {
          clearTimeout(findWait);
          findWait = setTimeout(load, 350);
        }
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
    if (pd) pd.addEventListener('change', function () {
      state.period = pd.value;
      /* The period is the report's window as well as the queue's bound, so
         changing it re-asks whichever one is on the screen. */
      if (state.view === 'report') loadReport(true); else load();
    });
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
    if (nw) nw.addEventListener('click', function () { openQuick(); });

    // The bar's ⋯: many at once, from a template, several selected, the number
    var wmb = $('workMoreBtn'), wmn = $('workMore');
    if (wmb && wmn) {
      var shutWorkMore = function () { wmn.hidden = true; wmb.setAttribute('aria-expanded', 'false'); };
      wmb.addEventListener('click', function (e) {
        e.stopPropagation();
        var open = wmn.hidden;
        wmn.hidden = !open;
        wmb.setAttribute('aria-expanded', String(open));
        if (open && window.ADspaceMenu) window.ADspaceMenu.place(wmb, wmn);
      });
      document.addEventListener('click', function (e) {
        if (!e.target.closest || !e.target.closest('#workMoreWrap')) shutWorkMore();
      });
      if (window.ADspaceMenu && window.ADspaceMenu.onScroll) window.ADspaceMenu.onScroll(shutWorkMore);
      wmn.addEventListener('click', function (e) {
        var it = e.target.closest('.kmenu-item');
        if (!it) return;
        shutWorkMore();
        var a = it.getAttribute('data-a');
        if (a === 'bulk') openGen();
        if (a === 'template') openTpl();
        if (a === 'select') setSelecting(!state.selecting);
        if (a === 'numbering') openNumbering();
      });
    }
    // Several at once
    var bAll = $('workBulkAll');
    if (bAll) bAll.addEventListener('change', function () {
      var on = bAll.checked;
      state.picked = {};
      if (on) (state.shown || []).forEach(function (t) { state.picked[t.id] = 1; });
      Array.prototype.forEach.call(document.querySelectorAll('#workQueue .task-row[data-task]'), function (row) {
        var id = row.getAttribute('data-task');
        var cb = row.querySelector('.trow-pick');
        if (cb) cb.checked = Boolean(state.picked[id]);
        row.classList.toggle('is-picked', Boolean(state.picked[id]));
      });
      paintBulk();
    });
    var bDone = $('workBulkDone');
    if (bDone) bDone.addEventListener('click', function () { setSelecting(false); });
    var bDel = $('workBulkDelete');
    if (bDel) bDel.addEventListener('click', bulkDelete);
    var bOwn = $('workBulkOwner');
    if (bOwn) bOwn.addEventListener('click', bulkOwner);

    // Add task
    var qf = $('qkForm');
    if (qf) qf.addEventListener('submit', function (e) { e.preventDefault(); quickAdd(); });
    var qg = $('qkGo');
    if (qg) qg.addEventListener('click', quickAdd);
    ['qkClose', 'qkDone'].forEach(function (id) {
      var b = $(id); if (b) b.addEventListener('click', closeQuick);
    });
    var qfull = $('qkFull');
    /* The switch at the top of both forms. The form being switched to is
       drawn before this one goes, so the two change places in one frame. */
    if (qfull) qfull.addEventListener('click', function () {
      var made = qkMade;
      openNew(null, true);
      $('quickSheet').hidden = true;
      qkMade = 0;
      if (made) load();
    });
    var nq = $('ntQuick');
    if (nq) nq.addEventListener('click', function () {
      if (nq.disabled) return;
      nq.disabled = true;
      openQuick(null, 'taskSheet');
      setTimeout(function () { nq.disabled = false; }, 400);
    });

    // From template
    ['tplClose', 'tplCancel'].forEach(function (id) {
      var b = $(id); if (b) b.addEventListener('click', function () { sheet('tplSheet', false); });
    });
    var tg = $('tplGo');
    if (tg) tg.addEventListener('click', tplCreate);
    var tn = $('tplNew');
    if (tn) tn.addEventListener('click', function () { openTplEdit(null); });
    ['teClose', 'teCancel'].forEach(function (id) {
      var b = $(id); if (b) b.addEventListener('click', function () { sheet('tplEditSheet', false); sheet('tplSheet', true); });
    });
    var te = $('teGo');
    if (te) te.addEventListener('click', tplSave);

    // The task, opened from a list
    var dwc = $('dwClose');
    if (dwc) dwc.addEventListener('click', function () { closeDrawer(); });
    var dwBox = $('taskDrawer');
    /* The scrim beside the card closes it, unless words have been typed into
       the card: a click that misses by a few pixels is not a decision to
       throw them away. */
    if (dwBox) dwBox.addEventListener('mousedown', function (e) {
      if (e.target !== dwBox) return;
      if (drawerTyped()) return;
      closeDrawer();
    });
    var dwn = $('dwNo');
    if (dwn) dwn.addEventListener('click', function () { if (window.ADspaceCopy) window.ADspaceCopy.to(dwn, dwn.textContent); });
    var dwk = $('dwCheck');
    if (dwk) dwk.addEventListener('click', function () {
      var t = state.task;
      if (!t) return;
      var closing = plainOf(t) !== 'done';
      move(closing ? 'complete' : 'todo');
    });
    var dwf = $('dwFull');
    if (dwf) dwf.addEventListener('click', function (e) {
      if (e.metaKey || e.ctrlKey || e.shiftKey) return;
      e.preventDefault();
      if (state.drawer) openFull(state.drawer);
    });
    /* The tick opens the list of people; untouched, the step keeps the task
       with whoever has it. */
    [['dwHandTick', 'dwHandTo'], ['taskHandTick', 'taskHandTo']].forEach(function (pair) {
      var tick = $(pair[0]), to = $(pair[1]);
      if (!tick || !to) return;
      tick.addEventListener('change', function () {
        to.hidden = !tick.checked;
        if (tick.checked) to.focus();
      });
    });
    /* Each card's quiet action opens its small form; Cancel and Escape put
       the card back as it was. */
    [['dwCheckOpen', 'dwCheckForm', 'dwCheckAdd'], ['dwLinkOpen', 'dwLinkForm', 'dwLinkUrl'],
     ['dwCommentOpen', 'dwCommentForm', 'dwComment']].forEach(function (x) {
      var b = $(x[0]);
      if (b) b.addEventListener('click', function () {
        if (!$(x[1]).hidden) { closeCardForm(x[1]); return; }
        openCardForm(x[1]);
        $(x[2]).focus();
      });
    });
    var dde = $('dwDescEdit');
    if (dde) dde.addEventListener('click', function () {
      if (!$('dwDescForm').hidden) { closeCardForm('dwDescForm'); return; }
      openCardForm('dwDescForm');
      $('dwDescText').value = (state.task && state.task.description) || '';
      $('dwDescText').focus();
    });
    CARD_FORMS.forEach(function (id) {
      var f = $(id);
      if (!f) return;
      var c = f.querySelector('[data-a="cancel"]');
      if (c) c.addEventListener('click', function () { closeCardForm(id); });
      f.addEventListener('keydown', function (e) {
        if (e.key === 'Escape') { e.stopPropagation(); e.preventDefault(); closeCardForm(id); }
      });
    });
    var ddf = $('dwDescForm');
    if (ddf) ddf.addEventListener('submit', function (e) {
      e.preventDefault();
      var t = state.task;
      if (!t) return;
      call('ops_update_task', { p_task: t.id, p_payload: { description: String($('dwDescText').value || '').trim() }, p_version: t.version },
        'dwMsg', function () {
          closeCardForm('dwDescForm');
          readTask(t.id, function () { msg('dwMsg', 'Brief saved.', 'ok'); });
        });
    });
    var dcf = $('dwCheckForm');
    if (dcf) dcf.addEventListener('submit', function (e) {
      e.preventDefault();
      var t = state.task, inp = $('dwCheckAdd');
      var label = String(inp.value || '').trim();
      if (!t) return;
      if (!label) { msg('dwMsg', 'Say what needs doing.', 'err'); inp.focus(); return; }
      call('ops_add_checklist_item', { p_task: t.id, p_label: label }, 'dwMsg', function () {
        inp.value = '';
        /* The form stays open for the next item, the way a list is typed. */
        readTask(t.id, function () { $('dwCheckAdd').focus(); });
      });
    });
    var dlf = $('dwLinkForm');
    if (dlf) dlf.addEventListener('submit', function (e) {
      e.preventDefault();
      var t = state.task, url = String($('dwLinkUrl').value || '').trim();
      if (!t) return;
      if (!/^https?:\/\//i.test(url)) { msg('dwMsg', 'A link starts with https://', 'err'); $('dwLinkUrl').focus(); return; }
      var label = String($('dwLinkLabel').value || '').trim() || url.replace(/^https?:\/\//i, '').split(/[\/?#]/)[0];
      var editing = linkEditing;
      var fn = editing ? 'ops_update_link' : 'ops_add_link';
      var args = editing
        ? { p_link: editing, p_label: label, p_url: url, p_kind: $('dwLinkKind').value, p_version: t.version }
        : { p_task: t.id, p_kind: $('dwLinkKind').value, p_label: label, p_url: url, p_version: t.version };
      call(fn, args, 'dwMsg', function () {
        closeCardForm('dwLinkForm');
        readTask(t.id, function () { msg('dwMsg', editing ? 'Link saved.' : 'Link added.', 'ok'); });
      });
    });
    var dcm = $('dwCommentForm');
    if (dcm) dcm.addEventListener('submit', function (e) {
      e.preventDefault();
      var t = state.task, body = String($('dwComment').value || '').trim();
      if (!t) return;
      if (!body) { msg('dwMsg', 'A comment cannot be empty.', 'err'); $('dwComment').focus(); return; }
      call('ops_add_comment', { p_task: t.id, p_body: body }, 'dwMsg', function () {
        closeCardForm('dwCommentForm');
        readTask(t.id);
      });
    });
    var dte = $('dwTitleEdit');
    if (dte) dte.addEventListener('click', editSheetTitle);
    var dmb = $('dwMenuBtn'), dmn = $('dwMenu');
    if (dmb && dmn) {
      dmb.addEventListener('click', function (e) {
        e.stopPropagation();
        var open = dmn.hidden;
        dmn.hidden = !open;
        dmb.setAttribute('aria-expanded', String(open));
        if (open && window.ADspaceMenu) window.ADspaceMenu.place(dmb, dmn);
      });
      document.addEventListener('click', function (e) {
        if (!e.target.closest || !e.target.closest('#dwMenuWrap')) { dmn.hidden = true; dmb.setAttribute('aria-expanded', 'false'); }
      });
      dmn.addEventListener('click', function (e) {
        var it = e.target.closest('.kmenu-item');
        if (!it) return;
        dmn.hidden = true;
        dmb.setAttribute('aria-expanded', 'false');
        var a = it.getAttribute('data-a'), t = state.task;
        if (!t) return;
        if (a === 'revert') { var back = cameFrom(t); if (back) askBack(back); }
        if (a === 'full') openFull(t.id);
        if (a === 'handover') openGive();
        if (a === 'move') openMove();
        if (a === 'block') openBlock();
        if (a === 'repeat') openRec();
        if (a === 'duplicate') openDup();
        if (a === 'reopen') askReopen();
        if (a === 'cancel') askCancel();
        if (a === 'delete') openDelete();
      });
    }

    // The step that needs something said
    ['stepClose', 'stepCancel'].forEach(function (id) {
      var b = $(id); if (b) b.addEventListener('click', function () { sheet('stepSheet', false); });
    });
    var stepGoBtn = $('stepGo');
    if (stepGoBtn) stepGoBtn.addEventListener('click', doStep);
    var stepDay = $('stepDate');
    if (stepDay) stepDay.addEventListener('change', stepDateChanged);
    var stepTick = $('stepHandTick');
    if (stepTick) stepTick.addEventListener('change', function () {
      $('stepHandRow').hidden = !stepTick.checked;
      if (stepTick.checked) $('stepHandTo').focus();
    });

    var back = $('workBack');
    if (back) back.addEventListener('click', showList);
    var mk = $('taskMark');
    if (mk) mk.addEventListener('click', function () {
      if (window.ADspaceCopy) window.ADspaceCopy.to(mk, mk.textContent);
    });
    var pen = $('taskDescEdit');
    if (pen) pen.addEventListener('click', editDesc);
    var cpt = $('taskCopyTitle');
    if (cpt) cpt.addEventListener('click', copyTitle);

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
        if (a === 'revert') { var back = cameFrom(t); if (back) askBack(back); }
        if (a === 'move') openMove();
        if (a === 'handover') openGive();
        if (a === 'cancel') askCancel();
        if (a === 'block') openBlock();
        if (a === 'duplicate') openDup();
        if (a === 'repeat') openRec();
        if (a === 'timer') { var tl = timerAct(t); if (tl) tl.run(); }
        if (a === 'archive') {
          call('ops_archive_task', { p_task: t.id, p_on: !t.archived_at }, 'taskMsg', function () {
            showList();
          });
        }
        if (a === 'reopen') askReopen();
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
        closeDrawer(true);
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
      var editing = recLinkEditing;
      call(editing ? 'ops_update_link' : 'ops_add_link', editing
        ? { p_link: editing, p_label: String($('taskLinkLabel').value || '').trim(), p_url: url,
            p_kind: $('taskLinkKind').value, p_version: t.version }
        : { p_task: t.id, p_kind: $('taskLinkKind').value,
            p_label: String($('taskLinkLabel').value || '').trim(),
            p_url: url, p_version: t.version }, 'taskLinkMsg', function () {
        recLinkEditing = null;
        $('taskLinkForm').hidden = true;
        readTask(t.id);
      });
    });

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
    var np = $('ntPaused');
    if (np) np.addEventListener('change', ntScopeChanged);
    var nty = $('ntType');
    if (nty) nty.addEventListener('change', function () { ntTouched.type = true; });
    var npub = $('ntPublish');
    if (npub) npub.addEventListener('change', ntPublishChanged);
    var nper = $('ntPeriod');
    if (nper) nper.addEventListener('change', function () { ntTouched.period = true; ntCodeHint(); });
    var nwk = $('ntWeek');
    if (nwk) nwk.addEventListener('change', function () { ntTouched.week = true; ntCodeHint(); });
    var nd = $('ntDesc');
    if (nd) nd.addEventListener('input', ntCodeHint);
    var ng = $('ntGo');
    if (ng) ng.addEventListener('click', createTask);

    // Duplicate, generate, repeat
    ['dupClose', 'dupCancel'].forEach(function (id) {
      var b = $(id); if (b) b.addEventListener('click', function () { sheet('dupSheet', false); });
    });
    /* Every name here is its own: `wire()` is one function scope, and a
       handler above reads its element lazily, so a second `var gp` would
       hand Group by the Preview button. */
    var dupGoBtn = $('dupGo');
    if (dupGoBtn) dupGoBtn.addEventListener('click', doDup);
    ['genClose', 'genCancel'].forEach(function (id) {
      var b = $(id); if (b) b.addEventListener('click', function () { sheet('genSheet', false); });
    });
    var genWhatSel = $('genWhat');
    if (genWhatSel) genWhatSel.addEventListener('change', genWhatChanged);
    var genSpreadSel = $('genSpread');
    if (genSpreadSel) genSpreadSel.addEventListener('change', genWhatChanged);
    var genPausedTick = $('genPaused');
    if (genPausedTick) genPausedTick.addEventListener('change', function () {
      fillClients($('genClient'), genPausedTick.checked, $('genClient').value);
    });
    var genPreviewBtn = $('genPreview');
    if (genPreviewBtn) genPreviewBtn.addEventListener('click', genPreview);
    var genGoBtn = $('genGo');
    if (genGoBtn) genGoBtn.addEventListener('click', doGen);
    ['recClose', 'recCancel'].forEach(function (id) {
      var b = $(id); if (b) b.addEventListener('click', function () { sheet('recSheet', false); });
    });
    var recFreqSel = $('recFreq');
    if (recFreqSel) recFreqSel.addEventListener('change', recFreqChanged);
    var recGoBtn = $('recGo');
    if (recGoBtn) recGoBtn.addEventListener('click', doRec);
    var recStopBtn = $('recStop');
    if (recStopBtn) recStopBtn.addEventListener('click', stopRec);

    // The engagement, the meeting, the hand-over
    ['engClose', 'engCancel'].forEach(function (id) {
      var b = $(id); if (b) b.addEventListener('click', function () { sheet('engSheet', false); });
    });
    var engGoBtn = $('engGo');
    if (engGoBtn) engGoBtn.addEventListener('click', saveEng);
    ['meetClose', 'meetCancel'].forEach(function (id) {
      var b = $(id); if (b) b.addEventListener('click', function () { sheet('meetSheet', false); });
    });
    var meetGoBtn = $('meetGo');
    if (meetGoBtn) meetGoBtn.addEventListener('click', saveMeet);
    var meetNaTick = $('meetNa');
    if (meetNaTick) meetNaTick.addEventListener('change', meetNaChanged);
    ['meetChannel', 'meetLink'].forEach(function (id) {
      var el = $(id); if (el) el.addEventListener(id === 'meetLink' ? 'input' : 'change', meetBookShown);
    });
    ['handClose', 'handCancel'].forEach(function (id) {
      var b = $(id); if (b) b.addEventListener('click', function () { sheet('handSheet', false); });
    });
    var handStageSel = $('handStage');
    if (handStageSel) handStageSel.addEventListener('change', handStageChanged);
    var handGoBtn = $('handGo');
    if (handGoBtn) handGoBtn.addEventListener('click', doHand);
    ['giveClose', 'giveCancel'].forEach(function (id) {
      var b = $(id); if (b) b.addEventListener('click', function () { sheet('giveSheet', false); });
    });
    var giveGoBtn = $('giveGo');
    if (giveGoBtn) giveGoBtn.addEventListener('click', doGive);

    /* Captured, so it reads the confirm sheet before that sheet shuts itself
       on the same key; an inline picker's own Escape puts the picker back and
       is left to it. */
    document.addEventListener('keydown', function (e) {
      if (e.key !== 'Escape') return;
      if (e.target && e.target.closest && e.target.closest('.tinline-pick, .tdate-pick, .towner-pick')) return;
      /* A question asked over the task answers its own Escape first. */
      var ask = document.getElementById('askSheet');
      if (ask && !ask.hidden) return;
      /* So does an open ⋯: Escape shuts the menu and hands focus back to its
         button, and the sheet under it stays where it was. */
      var menus = Array.prototype.filter.call(document.querySelectorAll(
        '#workMore, #dwMenu, #taskMenu, .qitem .kmenu, .tlink-row .kmenu, #workQueue .team-act .kmenu, #cwList .team-act .kmenu'),
        function (m) { return !m.hidden; });
      if (menus.length) {
        menus.forEach(function (m) {
          m.hidden = true;
          var b = m.parentNode && m.parentNode.querySelector('.kmenu-btn');
          if (b) { b.setAttribute('aria-expanded', 'false'); try { b.focus(); } catch (x) {} }
        });
        e.stopPropagation();
        return;
      }
      var open = ['dueSheet', 'blockSheet', 'taskSheet', 'dupSheet', 'genSheet', 'recSheet',
       'engSheet', 'meetSheet', 'handSheet', 'giveSheet', 'tplSheet', 'tplEditSheet', 'stepSheet', 'tdelSheet'].filter(function (id) {
        return $(id) && !$(id).hidden;
      });
      open.forEach(function (id) { sheet(id, false); });
      if ($('quickSheet') && !$('quickSheet').hidden) { closeQuick(); return; }
      /* The task sheet shuts on Escape once nothing is open over it. */
      if (!open.length) closeDrawer();
    }, true);
    /* The task sheet keeps a keyboard inside it while it is the top layer,
       and hands focus back to the row it came from when it shuts. */
    document.addEventListener('keydown', function (e) {
      if (e.key !== 'Tab') return;
      var box = $('taskDrawer');
      if (!box || box.hidden) return;
      var over = document.querySelector('.sheet:not([hidden]):not(#taskDrawer)');
      if (over) return;
      var card = box.querySelector('.sheet-card');
      var f = Array.prototype.filter.call(card.querySelectorAll(
        'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), summary'),
        function (el) { return el.offsetParent !== null; });
      if (!f.length) return;
      var first = f[0], last = f[f.length - 1];
      if (!card.contains(document.activeElement)) { e.preventDefault(); first.focus(); return; }
      if (e.shiftKey && (document.activeElement === first || document.activeElement === card)) { e.preventDefault(); last.focus(); }
      else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
    });
  }

  /* Three panes: the work, what happened to it, and how long it took. An
     address from before, naming Overview, Checklist or Links, opens Work. */
  var PANES = { work: 1, activity: 1, time: 1 };
  function showPane(name, push) {
    state.pane = PANES[name] ? name : 'work';
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
    if (state.openId && state.pane !== 'work') q.pane = state.pane;
    if (!state.openId && state.view !== 'list') q.view = state.view;
    /* The task open beside the list travels too, so a reload or a copied
       link lands on the list with that task open. */
    if (!state.openId && state.drawer && state.drawerFrom === 'work') q.open = state.drawer;
    return q;
  }

  /* Finished work is the only thing the period bounds, so the select draws
     only while finished work can be on the page. Returns whether it is now
     showing, so a caller knows whether the read has to run again. */
  function showPeriod() {
    var pd = $('workPeriod');
    /* On the queue the period bounds the finished work, so it is drawn only
       while finished work can be on the page. On the report it is the window
       every figure is taken over, so it is always drawn there. */
    var on = state.view === 'report' || state.filter === 'done' || state.filter === 'all';
    if (pd) pd.hidden = !on;
    return on;
  }

  function enter() {
    var nw = $('workNew');
    if (nw) nw.hidden = !may('ops', 'work');
    /* The bar's ⋯ holds acts that need the work level at least; the next
       number is an admin's alone. */
    var more = $('workMoreWrap');
    if (more) more.hidden = !may('ops', 'work');
    var num = $('workMore') && $('workMore').querySelector('[data-a="numbering"]');
    if (num) num.hidden = !isAdmin();
    if (state.selecting && !may('ops', 'manage')) state.selecting = false;
    var vl = $('workViewLoad');
    if (vl) vl.hidden = !may('ops.all', 'view');
    /* Assigned, created and following are everybody's views. The whole
       team's queue is offered only where it can arrive: showing it where it
       cannot would offer a view that comes back empty and say nothing. */
    var all = $('workScopeAll');
    if (all) {
      var team = may('ops.all', 'view');
      all.hidden = !team;
      all.disabled = !team;
      if (!team && state.scope === 'all') { state.scope = 'mine'; if ($('workScope')) $('workScope').value = 'mine'; }
    }
    /* `ops.reports` is granted and never inherited, so a group given
       `ops: work` is not quietly handed the team's numbers. Hiding the button
       changes nothing the database does — `ops_report` refuses the same
       person — but offering a view that can only come back denied is a
       control somebody has to try before they learn it is not theirs. */
    var rv = $('workViewReport');
    if (rv) rv.hidden = !may('ops.reports', 'view');
    if (rv && rv.hidden && state.view === 'report') state.view = 'list';
    showPeriod();

    var params = new URLSearchParams(location.search);
    var want = params.get('task');
    var peek = params.get('open');
    var pane = params.get('pane') || 'work';
    applyView(params.get('view') || 'list');
    load();
    if (!want) {
      $('workList').hidden = false;
      $('workRec').hidden = true;
      state.openId = null;
      /* A task named in the address opens beside the list, as it did when
         the link was copied. */
      if (peek) loadCatalogue(function () { openDrawer(peek); });
      else if (bridge.setUrl) bridge.setUrl();
      return;
    }
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
    if (wrap.hidden) return;
    loadNotifs();
    /* The count was read once, when the console opened, so a change made
       while somebody was working never lit the bell until they reloaded. It
       is read again every minute while the tab is on the screen, and the
       moment somebody comes back to it. */
    if (!state.notifPoll) {
      state.notifPoll = setInterval(function () { if (!document.hidden) loadNotifs(); }, 60000);
      document.addEventListener('visibilitychange', function () { if (!document.hidden) loadNotifs(); });
    }
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
    /* A performance review is not a task: a released or answered month opens
       the person's own record, a dispute opens the team's month. */
    if (!x.task_id && /^perf\./.test(x.kind || '')) {
      if (x.kind === 'perf.disputed' && window.ADspacePerf) window.ADspacePerf.openTeam();
      else if (bridge.show) bridge.show('mine');
      return;
    }
    if (!x.task_id) return;
    /* On My Work the task opens beside the list; from anywhere else the
       address comes first, because My Work reads it on entry. */
    if ($('sectionWork') && !$('sectionWork').hidden && !$('workList').hidden) { openDrawer(x.task_id); return; }
    history.replaceState(null, '', '/admin/?s=work&open=' + encodeURIComponent(x.task_id));
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
    reload: function () { if (state.task) readTask(state.task.id); },
    /* The client record's Work pane: drawn by this script into that pane. */
    clientWork: clientWork
  };
  if (bridge.opsReady) bridge.opsReady();
  if (bridge.me && bridge.me()) signedIn();
})();
