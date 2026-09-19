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
    'not-blocked': 'This task is not blocked.'
  };
  function said(err) { return SAID[err] || ('Refused: ' + err + '.'); }

  // ---- State ---------------------------------------------------------------
  var state = {
    tasks: null, stages: {}, workflows: [], templates: [], members: [], clients: [],
    owners: {}, ownerIds: {},   // task id → the live owner's name, and their id
    find: '', scope: 'mine', filter: 'open', group: 'due', period: 'month', err: null,
    task: null,            // the open task, as ops_task_json returned it
    pane: 'overview',
    session: null,         // my one open work session, whichever task it is on
    detail: { checklist: [], links: [], sessions: [], events: [], video: null },
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
  function stageTone(t) {
    var s = stageOf(t);
    if (!s) return '';
    if (t.stage_key === 'blocked') return 'is-danger';
    if (t.stage_key === 'cancelled') return '';
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
      db.from('team_members').select('id, name, email, active').eq('active', true).order('name'),
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
        db.from('ops_task_assignees')
          .select('task_id, responsibility, team_member_id, team_members(name)')
          .is('ended_at', null)
      ]).then(function (r) {
        if (r[0] && r[0].error) {
          state.err = r[0].error;
          UI.failLine(box, 'Your tasks', r[0].error.message, load);
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

  function paint() {
    var box = $('workQueue');
    if (!box || !state.tasks) return;
    /* The count is read against the view somebody chose, not against every
       row the database sent: "Open work, mine" is where this route opens, so
       counting it as `5 of 6` would print a fraction on a screen nobody has
       filtered. The search is the narrowing, and it is what puts "of" on. */
    var all = state.tasks.filter(function (t) { return inFilter(t) && inScope(t); });
    var rows = all.filter(matches);
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
    var over = !isFinished(t) && daysAway(t.current_final_due_at) < 0;
    var meta = [(t.clients && t.clients.name) || (t.scope === 'internal' ? 'Internal' : ''),
                t.deliverable_type].filter(Boolean).join(' · ');
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
    var next = sel.value;
    if (!next) return;
    var back = function () { sel.value = ''; };
    rowNote(el, '');
    db.rpc('ops_transition_task',
      { p_task: t.id, p_next: next, p_version: t.version, p_note: null })
      .then(function (r) {
        if (r.error) { back(); rowNote(el, r.error.message); return; }
        var d = r.data;
        if (d && d.error) { back(); rowNote(el, said(d.error)); return; }
        /* The band a row belongs to can change with its stage, so the queue is
           repainted rather than the cell patched. */
        load();
      }, function (e) { back(); rowNote(el, (e && e.message) || String(e)); });
  }
  function rowNote(el, text) {
    var was = el.nextSibling;
    if (was && was.classList && was.classList.contains('task-note')) was.remove();
    if (!text) return;
    var note = document.createElement('div');
    note.className = 'msg err task-note';
    note.textContent = text;
    el.parentNode.insertBefore(note, el.nextSibling);
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
      db.from('ops_work_sessions').select('*, team_members(name)').eq('task_id', id).order('started_at', { ascending: false }),
      db.from('ops_task_events').select('*').eq('task_id', id).order('created_at', { ascending: false }).limit(60),
      db.from('ops_task_assignees').select('*, team_members(name)').eq('task_id', id).is('ended_at', null),
      db.from('ops_video_details').select('*').eq('task_id', id)
    ]).then(function (r) {
      if (r[0].error || !r[0].data) {
        msg('taskMsg', (r[0].error && r[0].error.message) || 'That task could not be read.', 'err');
        return;
      }
      var t = r[0].data;
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
      t.deliverable_type,
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
    reopened: 'Reopened', cancelled: 'Cancelled', archived: 'Archived', restored: 'Restored'
  };
  function eventDetail(e) {
    var d = e.detail || {}, to = e.to_value || {}, from = e.from_value || {};
    if (e.event_type === 'stage_changed') {
      return (from.stage_key ? labelForKey(from.stage_key) + ' to ' : '') + labelForKey(to.stage_key);
    }
    if (e.event_type === 'due_changed') {
      return (to.kind === 'final' ? 'Final due' : 'First draft due') + ' ' +
        (from.value ? niceDate(from.value) + ' to ' : '') + niceDate(to.value) +
        (d.reason ? ' · ' + String(d.reason).replace(/_/g, ' ') : '');
    }
    if (e.event_type === 'work_stopped') return minutesWord(to.minutes);
    if (e.event_type === 'checklist_changed') return to.label + (to.done ? ' ticked' : ' cleared');
    if (e.event_type === 'blocked') return d.category ? String(d.category).replace(/_/g, ' ') : '';
    if (e.event_type === 'file_added' || e.event_type === 'file_removed' || e.event_type === 'file_restored') {
      return to.label || to.kind || '';
    }
    return d.note || d.reason || '';
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
    $('taskDatesBlock').hidden = !rows.length && !may('ops', 'work');

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
      ['Deliverable', t.deliverable_type],
      ['Languages', (t.language_codes || []).join(', ')],
      ['Priority', String(t.priority_level)],
      ['Complexity', t.complexity || ''],
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
    var rest = nexts.filter(function (k) { return k !== first; });
    /* The head already carries the stage as its chip, so the rail does not say
       it again; and the move is a button at its own width, never a slab across
       the rail: full width it was the loudest thing on the page, louder than
       the overdue line above it, and on a phone it was the banner this
       portal's section heads have refused for months. */
    box.innerHTML =
      (can ? '<button class="btn btn-go railmove" data-go="' + esc(first) + '" type="button">Move to ' + esc(labelForKey(first)) + '</button>'
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
  var dueKind = 'final';
  function openDue(kind) {
    var t = state.task;
    if (!t) return;
    dueKind = kind || 'final';
    var was = dueKind === 'final' ? t.current_final_due_at : t.current_first_draft_due_at;
    $('dueWhat').textContent = (dueKind === 'final' ? 'Final due date' : 'First draft due date') +
      (was ? ', now ' + niceDate(was) + '.' : ', not set.') +
      ' The promise first made is kept either way.';
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
      });
    }

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

    // Sheets
    ['dueClose', 'dueCancel'].forEach(function (id) {
      var b = $(id); if (b) b.addEventListener('click', function () { sheet('dueSheet', false); });
    });
    var dg = $('dueGo');
    if (dg) dg.addEventListener('click', function () {
      var t = state.task;
      if (!t) return;
      if (!$('dueDate').value) { msg('dueMsg', 'A date is required.', 'err'); return; }
      call('ops_change_due_date', {
        p_task: t.id, p_kind: dueKind === 'final' ? 'final' : 'first_draft',
        p_value: $('dueDate').value + 'T00:00:00Z',
        p_reason: $('dueReason').value,
        p_note: String($('dueNote').value || '').trim() || null,
        p_version: t.version
      }, 'dueMsg', function () { sheet('dueSheet', false); readTask(t.id); });
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
    load();
    if (!want) { $('workList').hidden = false; $('workRec').hidden = true; if (bridge.setUrl) bridge.setUrl(); return; }
    loadCatalogue(function () {
      showPane(pane, false);
      openTask(want, false);
    });
  }

  wire();
  showPane('overview', false);
  window.ADspaceOps = { enter: enter, urlState: urlState };
  if (bridge.opsReady) bridge.opsReady();
})();
