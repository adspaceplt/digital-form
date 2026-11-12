/* ADspace Digital Portal — the Assistant (2026-11-13; the user: "ok approve,
 * all colleagues, build all phases", after the Assistant mockup).
 *
 * A colleague asks in words from Ask in the console's head (Ctrl + J). This
 * page holds the conversation and posts it to `portal-agent`, which asks
 * Claude with a fixed set of tools and hands back its answer. Every tool
 * Claude asks for runs here, through the colleague's own sign-in:
 *   - a read (find_clients, client_summary, list_tasks, waiting_on_me,
 *     list_reports, find_colleagues) makes the reads the screens make, under
 *     the same policies, and answers no-access where `may()` says so;
 *   - a change (propose_*) is drawn as a card of what will be written, from
 *     and to; nothing is written until Confirm, through the function the
 *     screen uses, and Undo stands where the screen offers one;
 *   - open_page draws a button to the record on its own screen.
 * Each confirmed change is filed in the Activity record under the colleague,
 * marked as made through the Assistant (`assistant.task`, `assistant.call`,
 * `assistant.report`). The assistant never deletes, sends to a client,
 * touches money, access or performance: those are not among its tools.
 */
(function () {
  'use strict';
  var bridge = window.ADspaceAdmin || {};
  var API = window.ADspaceAPI;
  var db = API && API.client;
  var SHEET = window.ADspaceSheet;
  var W = window.ADspaceWords || {};
  var esc = W.esc || function (s) { return String(s == null ? '' : s); };
  var CLOCK = window.ADspaceClock;
  function $(id) { return document.getElementById(id); }
  var btn = $('agentOpen'), box = $('agentSheet'), log = $('agentLog'), field = $('agentQ'),
      sendBtn = $('agentSend'), left = $('agentLeft'), chips = $('agentChips');
  if (!btn || !box || !log || !field || !db || !SHEET) return;

  function may(key, level) { return Boolean(bridge.may && bridge.may(key, level || 'view')); }
  function me() { return (bridge.me && bridge.me()) || null; }

  var state = { messages: [], press: '', busy: false, notes: [], said: 0 };
  var AI_GLYPH = '<svg class="spark" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 1l1.6 4.4L14 7l-4.4 1.6L8 13l-1.6-4.4L2 7l4.4-1.6z"/></svg>';

  /* ---- Words ---------------------------------------------------------------- */
  var SAID = {
    'ai-limit': 'The daily limit for the Assistant has been reached. It resets at 12:00am.',
    'ai-not-set-up': 'The Assistant is not set up yet. Please contact an admin.',
    'needs-update': 'This feature is not available yet. Please contact an admin.',
    'ai-key': 'The Assistant is not available at the moment. Please contact an admin.',
    'ai-credit': 'The Assistant is not available at the moment. Please contact an admin.',
    'ai-model': 'The Assistant is not available at the moment. Please contact an admin.',
    'ai-busy': 'The Assistant is busy. Try again in a minute.',
    'ai-slow': 'The answer took too long. Try a shorter question.',
    'ai-refused': 'The Assistant cannot help with that. Ask about a client, a task or a report.',
    'too-many-steps': 'That question needed too many steps. Ask about one thing at a time.',
    'expired': 'This question has expired. Please ask it again.',
    denied: 'You do not have permission to use the Assistant. Please ask an admin.'
  };
  function saidOf(code) { return SAID[code] || 'The Assistant could not answer. Try again.'; }
  var REASON = { client_request: 'Client request', scope_change: 'Scope change', capacity: 'Internal capacity',
                 pending_assets: 'Pending assets', pending_confirmation: 'Pending confirmation', correction: 'Incorrect date listed' };
  var KIND = { call: 'Call', visit: 'Site visit', meeting: 'Meeting', whatsapp: 'WhatsApp', email: 'Email', note: 'Note' };
  var PRIORITY = { urgent: 1, high: 2, medium: 4, normal: 3 };
  var PRIORITY_WORD = { 1: 'Urgent', 2: 'High', 3: 'Normal', 4: 'Medium', 5: 'Normal' };
  var STAGE = { lead: 'Lead', contacted: 'Contacted', proposal: 'Proposal sent', active: 'Active', paused: 'Paused', past: 'Past' };
  var REPORT_STATE = { draft: 'Draft', review: 'In review', confirmed: 'Confirmed', published: 'Published' };
  var REPORT_KIND = { social: 'Accounts Report', ads: 'Advertising Report' };

  /* ---- Days, Malaysia's ------------------------------------------------------ */
  function today() { return CLOCK ? CLOCK.today() : new Date(Date.now() + 8 * 3600e3).toISOString().slice(0, 10); }
  function dayWord(v) {
    if (!v) return '';
    var d = String(v).slice(0, 10);
    return CLOCK && CLOCK.date ? CLOCK.date(d) : d;
  }
  function addDays(d, n) { return CLOCK && CLOCK.addDays ? CLOCK.addDays(d, n) : new Date(Date.parse(d + 'T00:00:00Z') + n * 864e5).toISOString().slice(0, 10); }
  function validDay(v) { return /^\d{4}-\d{2}-\d{2}$/.test(String(v || '')) && !isNaN(Date.parse(v + 'T00:00:00Z')); }
  function taskNo(n) { return n ? '#WT' + String(n).padStart(5, '0') : ''; }

  /* ---- Who is who ------------------------------------------------------------ */
  var people = null;
  function team() {
    if (people) return Promise.resolve(people);
    return db.from('team_members').select('id, name, staff_code, active').then(function (r) {
      people = (r.data || []);
      return people;
    });
  }
  function nameOf(id) {
    var m = (people || []).filter(function (x) { return x.id === id; })[0];
    return m ? m.name : '';
  }

  /* ---- The reads: what the screens read, as the colleague -------------------- */
  /* A contact's email or number never goes to Claude, even typed into a
     call's notes: masked here as the function masks a question. A number is
     nine digits or more, or a Singapore number's 4 and 4; a date is not one. */
  function mask(v) {
    if (v == null) return v;
    return String(v).replace(/[\w.+-]+@[\w-]+(\.[\w-]+)+/g, '[email]')
      .replace(/\+?\d(?:[\s-]?\d){8,14}/g, '[number]')
      .replace(/\b[3689]\d{3}[\s-]?\d{4}\b/g, '[number]');
  }
  function clean(q) { return String(q || '').replace(/["\\%*,()]/g, ' ').replace(/\s+/g, ' ').trim(); }
  function noAccess() { return { error: 'no-access' }; }
  function rows(r) { if (r.error) throw r.error; return r.data || []; }

  var stages = null;
  function stageOf(t) {
    var s = stages && stages[t.workflow_id + '|' + t.stage_key];
    return s ? s.label : String(t.stage_key || '').replace(/_/g, ' ');
  }
  function loadStages() {
    if (stages) return Promise.resolve();
    return db.from('ops_workflow_stages').select('workflow_id, key, label').then(function (r) {
      stages = {};
      (r.data || []).forEach(function (s) { stages[s.workflow_id + '|' + s.key] = s; });
    });
  }
  var TASK_COLS = 'id, task_no, code, title, content_desc, client_id, workflow_id, stage_key, current_final_due_at, priority_level, completed_at, cancelled_at, archived_at, version, clients(name)';
  function taskRow(t, owners) {
    return { task_id: t.id, number: taskNo(t.task_no), code: t.code || null, title: t.title || t.content_desc || '',
      client: (t.clients && t.clients.name) || (t.client_id ? '' : 'Internal'), stage: stageOf(t),
      due: t.current_final_due_at ? dayWord(t.current_final_due_at) : 'No due date',
      past_due: !!(t.current_final_due_at && String(t.current_final_due_at).slice(0, 10) < today() && !t.completed_at),
      priority: PRIORITY_WORD[t.priority_level] || 'Normal', assigned_to: owners[t.id] || 'Unassigned',
      done: t.completed_at ? dayWord(t.completed_at) : undefined };
  }
  function ownersOf(ids) {
    if (!ids.length) return Promise.resolve({});
    return db.from('ops_task_assignees').select('task_id, team_member_id').in('task_id', ids.slice(0, 150))
      .eq('responsibility', 'owner').is('ended_at', null).then(function (r) {
        var o = {};
        (r.data || []).forEach(function (a) { o[a.task_id] = nameOf(a.team_member_id); });
        return o;
      });
  }

  var READ = {
    find_clients: function (a) {
      if (!may('clients')) return Promise.resolve(noAccess());
      var q = clean(a.query);
      if (q.length < 2) return Promise.resolve({ error: 'too-short' });
      var v = q.replace(/_/g, '\\\\_');
      return team().then(function () {
        return db.from('clients').select('id, name, client_code, stage, owner, sales_by, industry, market')
          .or('name.ilike."%' + v + '%",client_code.ilike."%' + v + '%"').limit(10);
      }).then(rows).then(function (list) {
        return { clients: list.map(function (c) {
          return { client_id: c.id, name: c.name, client_id_code: c.client_code || null, stage: STAGE[c.stage] || c.stage,
                   person_in_charge: c.owner || null, sales_by: nameOf(c.sales_by) || null, industry: c.industry || null, market: c.market || null };
        }) };
      });
    },
    client_summary: function (a) {
      if (!may('clients')) return Promise.resolve(noAccess());
      return Promise.all([team(), loadStages()]).then(function () {
        return db.from('clients').select('id, name, client_code, stage, stage_since, owner, sales_by, industry, market, slug').eq('id', a.client_id).maybeSingle();
      }).then(function (r) {
        if (r.error) throw r.error;
        var c = r.data;
        if (!c) return { error: 'not-found' };
        var out = { client_id: c.id, name: c.name, client_id_code: c.client_code || null, stage: STAGE[c.stage] || c.stage,
          since: dayWord(c.stage_since), person_in_charge: c.owner || null, sales_by: nameOf(c.sales_by) || null,
          industry: c.industry || null, market: c.market || null };
        var jobs = [];
        if (may('ops')) jobs.push(db.from('ops_tasks').select(TASK_COLS).eq('client_id', c.id).is('completed_at', null)
          .is('cancelled_at', null).is('archived_at', null).order('current_final_due_at', { ascending: true, nullsFirst: false }).limit(15)
          .then(function (t) {
            var list = t.data || [];
            return ownersOf(list.map(function (x) { return x.id; })).then(function (o) { out.open_tasks = list.map(function (x) { return taskRow(x, o); }); });
          }));
        if (may('clients.calls')) jobs.push(db.from('client_touches').select('kind, happened_at, contact_name, summary, next_action, next_at, by_whom, done_at')
          .eq('client_id', c.id).is('archived_at', null).order('happened_at', { ascending: false }).limit(5).then(function (t) {
            out.calls_and_visits = (t.data || []).map(function (x) {
              return { kind: KIND[x.kind] || x.kind, on: dayWord(x.happened_at), with: mask(x.contact_name) || null, summary: mask(x.summary),
                       next_action: x.next_action && !x.done_at ? mask(x.next_action) + (x.next_at ? ' by ' + dayWord(x.next_at) : '') : null, by: x.by_whom || null };
            });
          }));
        if (may('reports')) jobs.push(db.from('sm_reports').select('id, kind, period_start, period_end, status, sent_on, brand_name')
          .eq('client_id', c.id).order('period_start', { ascending: false }).limit(4).then(function (t) {
            out.reports = (t.data || []).map(reportRow);
          }));
        return Promise.all(jobs).then(function () { return out; });
      });
    },
    list_tasks: function (a) {
      if (!may('ops')) return Promise.resolve(noAccess());
      if (a.whose === 'everyone' && !may('ops.all')) return Promise.resolve({ error: 'no-access', why: 'Only your own tasks may be listed.' });
      var mine = a.whose === 'me' ? (me() || {}).id : a.whose === 'person' ? a.person_id : null;
      if (a.whose === 'person' && !a.person_id) return Promise.resolve({ error: 'person_id required' });
      if (a.whose === 'person' && a.person_id !== (me() || {}).id && !may('ops.all')) return Promise.resolve({ error: 'no-access', why: 'Only your own tasks may be listed.' });
      var ids = mine ? db.from('ops_task_assignees').select('task_id').eq('team_member_id', mine).eq('responsibility', 'owner').is('ended_at', null).limit(400)
        .then(function (r) { return rows(r).map(function (x) { return x.task_id; }); }) : Promise.resolve(null);
      return Promise.all([team(), loadStages(), ids]).then(function (got) {
        var only = got[2];
        if (only && !only.length) return { tasks: [] };
        var q = db.from('ops_tasks').select(TASK_COLS).is('archived_at', null).is('cancelled_at', null);
        if (only) q = q.in('id', only.slice(0, 400));
        if (a.client_id) q = q.eq('client_id', a.client_id);
        var t = today();
        if (a.show === 'done_this_month') q = q.gte('completed_at', t.slice(0, 7) + '-01T00:00:00+08:00').order('completed_at', { ascending: false });
        else {
          q = q.is('completed_at', null);
          if (a.show === 'past_due') q = q.lt('current_final_due_at', t + 'T00:00:00Z');
          if (a.show === 'due_this_week') q = q.gte('current_final_due_at', t + 'T00:00:00Z').lte('current_final_due_at', addDays(t, 7) + 'T23:59:59Z');
          q = q.order('current_final_due_at', { ascending: true, nullsFirst: false });
        }
        return q.limit(40).then(rows).then(function (list) {
          return ownersOf(list.map(function (x) { return x.id; })).then(function (o) {
            return { tasks: list.map(function (x) { return taskRow(x, o); }), shown: list.length, more: list.length === 40 };
          });
        });
      });
    },
    waiting_on_me: function () {
      var m = me();
      if (!m) return Promise.resolve(noAccess());
      var out = {}, jobs = [];
      if (may('ops')) jobs.push(db.from('ops_due_requests').select('id, task_id, wants_at, reason, asked_by, asked_at')
        .eq('decider_id', m.id).eq('state', 'asked').limit(20).then(function (r) {
          var list = r.data || [];
          if (!list.length) { out.extension_requests = []; return; }
          return Promise.all([team(), db.from('ops_tasks').select('id, task_no, title, content_desc, clients(name)').in('id', list.map(function (x) { return x.task_id; }))])
            .then(function (g) {
              var tasks = {};
              ((g[1] && g[1].data) || []).forEach(function (t) { tasks[t.id] = t; });
              out.extension_requests = list.map(function (x) {
                var t = tasks[x.task_id] || {};
                return { task_id: x.task_id, task: taskNo(t.task_no) + ' ' + (t.title || t.content_desc || ''), client: (t.clients && t.clients.name) || null,
                         asked_by: nameOf(x.asked_by), to: dayWord(x.wants_at), reason: REASON[x.reason] || x.reason, asked: dayWord(x.asked_at) };
              });
            });
        }));
      if (may('reports')) jobs.push(db.from('sm_reports').select('id, client_id, kind, period_start, period_end, status, sent_on, brand_name, clients(name)')
        .eq('reviewer_id', m.id).eq('status', 'review').limit(20).then(function (r) { out.reports_to_review = (r.data || []).map(reportRow); }));
      return Promise.all(jobs).then(function () { return out; });
    },
    list_reports: function (a) {
      if (!may('reports')) return Promise.resolve(noAccess());
      var q = db.from('sm_reports').select('id, client_id, kind, period_start, period_end, status, sent_on, brand_name, clients(name)');
      if (a.client_id) q = q.eq('client_id', a.client_id);
      if (a.status && a.status !== 'any') q = q.eq('status', a.status);
      if (a.period && /^\d{4}-\d{2}$/.test(a.period)) {
        var next = CLOCK && CLOCK.addMonths ? CLOCK.addMonths(a.period + '-01', 1) : '';
        q = q.gte('period_end', a.period + '-01');
        if (next) q = q.lt('period_end', next + '-01');
      }
      return q.order('period_start', { ascending: false }).limit(30).then(rows).then(function (list) { return { reports: list.map(reportRow) }; });
    },
    find_colleagues: function (a) {
      return Promise.all([team(), db.rpc('team_task_takers')]).then(function (g) {
        var takers = Array.isArray(g[1].data) ? g[1].data : null;
        var q = clean(a.query).toLowerCase();
        return { colleagues: (people || []).filter(function (m) {
          return m.active && (!takers || takers.indexOf(m.id) > -1) &&
            (!q || String(m.name || '').toLowerCase().indexOf(q) > -1 || String(m.staff_code || '').toLowerCase() === q);
        }).slice(0, 10).map(function (m) { return { person_id: m.id, name: m.name, employee_id: m.staff_code || null }; }) };
      });
    }
  };
  function reportRow(r) {
    return { report_id: r.id, client: (r.clients && r.clients.name) || null, brand: r.brand_name || null,
      kind: REPORT_KIND[r.kind] || r.kind, period: dayWord(r.period_start) + ' to ' + dayWord(r.period_end),
      status: REPORT_STATE[r.status] || r.status, sent: r.sent_on ? dayWord(r.sent_on) : (r.status === 'published' ? 'Not sent' : null) };
  }

  /* ---- The changes: drawn first, written only on Confirm --------------------- */
  function idem() { return 'ag-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8); }
  function rpcOk(r) {
    if (r.error) throw new Error(r.error.message || 'The database refused the request.');
    var d = r.data;
    if (d && d.error) throw new Error(refusal(d.error));
    return d;
  }
  function refusal(code) {
    var m = { denied: 'You do not have permission to do this. Please ask an admin.', 'not-owner': 'Only the person it is assigned to, or an admin, can move this task.',
      stale: 'Not saved. This task was changed by someone else. Ask again to see the latest version.', 'not-found': 'This task no longer exists.',
      'no-month': 'A client task needs a confirmed content month. Confirm the month in My Work first.',
      'priority-not-yours': 'Only the person who set the task can change its priority.', 'no-tasks': 'That colleague does not take tasks. Choose another colleague.',
      'bad-date': 'Choose a date from 14 Aug 2023 to 31 Dec 2099.', 'client-scope': 'You do not have permission to work on that client. Please ask an admin.' };
    return m[code] || 'Not saved. Please try again.';
  }
  function task(id) {
    return db.from('ops_tasks').select('id, task_no, title, content_desc, version, current_final_due_at, client_id, clients(name)').eq('id', id).maybeSingle()
      .then(function (r) { if (r.error) throw r.error; if (!r.data) throw new Error('That task no longer exists.'); return r.data; });
  }
  function taskName(t) { return (taskNo(t.task_no) + ' ' + (t.title || t.content_desc || '')).trim(); }
  function file(tag, subject, detail) { if (bridge.log) bridge.log(tag, subject, detail + ' · confirmed through the Assistant'); }

  /* Each change: `card(a)` answers the facts the card shows (or a reason it
     cannot be made); `run(a, facts)` writes it and answers an Undo where the
     screen offers one. */
  var CHANGE = {
    propose_add_task: {
      title: 'Add task',
      card: function (a) {
        if (!may('ops', 'work')) return Promise.reject(new Error('You do not have permission to add tasks. Please ask an admin.'));
        if (!validDay(a.due_date)) return Promise.reject(new Error('Enter a valid due date.'));
        return team().then(function () {
          if (!a.client_id) return null;
          return db.from('clients').select('id, name').eq('id', a.client_id).maybeSingle().then(function (r) { return r.data; });
        }).then(function (c) {
          if (a.client_id && !c) throw new Error('That client could not be found.');
          if (a.owner_id && !nameOf(a.owner_id)) throw new Error('That colleague could not be found. Ask again with their name.');
          a._client = c;
          var owner = a.owner_id || (me() || {}).id;
          return [['Task', a.title], ['For', c ? c.name : 'Internal'], ['Assigned to', nameOf(owner) || (me() || {}).name || 'Me'],
                  ['Due date', dayWord(a.due_date)], ['Priority', PRIORITY_WORD[PRIORITY[a.priority] || 3]],
                  a.description ? ['Brief', a.description] : null];
        });
      },
      run: function (a) {
        var payload = { title: String(a.title || '').trim().slice(0, 200), workflow_key: 'task', scope: a.client_id ? 'client' : 'internal',
          client_id: a.client_id || null, engagement_id: null, task_type: 'adhoc', owner_id: a.owner_id || (me() || {}).id,
          final_due_at: a.due_date + 'T00:00:00Z', description: a.description || null, priority_level: PRIORITY[a.priority] || 3, checklist: [] };
        return db.rpc('ops_create_task', { p_payload: payload, p_idem: a._idem || (a._idem = idem()) }).then(rpcOk).then(function (t) {
          file('assistant.task', a._client ? a._client.name : 'Internal', 'Task added: ' + payload.title);
          return { said: 'Task added.', open: t && t.id ? { kind: 'task', id: t.id, label: 'Open task' } : null };
        });
      }
    },
    propose_reassign_task: {
      title: 'Reassign',
      card: function (a) {
        return Promise.all([team(), task(a.task_id), db.from('ops_task_assignees').select('team_member_id').eq('task_id', a.task_id)
          .eq('responsibility', 'owner').is('ended_at', null).maybeSingle()]).then(function (g) {
          a._task = g[1]; a._was = g[2].data ? g[2].data.team_member_id : null;
          if (!nameOf(a.owner_id)) throw new Error('That colleague could not be found. Ask again with their name.');
          return [['Task', taskName(g[1])], ['Assigned to', (nameOf(a._was) || 'Unassigned') + ' → ' + (nameOf(a.owner_id) || 'Unknown')]];
        });
      },
      run: function (a) {
        return db.rpc('ops_assign_task', { p_task: a.task_id, p_owner: a.owner_id, p_version: a._task.version }).then(rpcOk).then(function () {
          file('assistant.task', (a._task.clients && a._task.clients.name) || 'Internal', taskName(a._task) + ' reassigned to ' + nameOf(a.owner_id));
          return { said: 'Reassigned.', open: { kind: 'task', id: a.task_id, label: 'Open task' },
            undo: a._was ? function () {
              return task(a.task_id).then(function (t) { return db.rpc('ops_assign_task', { p_task: a.task_id, p_owner: a._was, p_version: t.version }); }).then(rpcOk);
            } : null };
        });
      }
    },
    propose_due_date: {
      title: 'Change due date',
      card: function (a) {
        if (!validDay(a.due_date)) return Promise.reject(new Error('Enter a valid due date.'));
        return task(a.task_id).then(function (t) {
          a._task = t;
          return [['Task', taskName(t)], ['Due date', (t.current_final_due_at ? dayWord(t.current_final_due_at) : 'Not set') + ' → ' + dayWord(a.due_date)],
                  ['Reason', REASON[a.reason] || a.reason], a.note ? ['Note', a.note] : null];
        });
      },
      run: function (a) {
        return db.rpc('ops_request_due_change', { p_task: a.task_id, p_kind: 'final', p_value: a.due_date + 'T00:00:00Z',
          p_reason: a.reason, p_note: a.note || null, p_version: a._task.version }).then(rpcOk).then(function (d) {
          file('assistant.task', (a._task.clients && a._task.clients.name) || 'Internal',
            taskName(a._task) + (d && d.asked ? ' · extension requested to ' : ' · due date moved to ') + dayWord(a.due_date));
          return { said: d && d.asked ? 'Extension requested.' : 'Due date changed.', open: { kind: 'task', id: a.task_id, label: 'Open task' } };
        });
      }
    },
    propose_log_call: {
      title: 'Log call',
      card: function (a) {
        if (!may('clients.calls', 'work')) return Promise.reject(new Error('You do not have permission to log calls. Please ask an admin.'));
        if (!validDay(a.happened_on) || (a.next_on && !validDay(a.next_on))) return Promise.reject(new Error('Enter a valid date.'));
        return db.from('clients').select('id, name, stage, slug, stage_since').eq('id', a.client_id).maybeSingle().then(function (r) {
          if (!r.data) throw new Error('That client could not be found.');
          a._client = r.data;
          return [['Client', r.data.name], ['Type', KIND[a.kind] || a.kind], ['Date', dayWord(a.happened_on)], a.with ? ['Attendees', a.with] : null,
                  ['Summary', a.summary], a.next_action ? ['Action', a.next_action + (a.next_on ? ' · ' + dayWord(a.next_on) : '')] : null];
        });
      },
      run: function (a) {
        var row = { client_id: a.client_id, kind: a.kind, happened_at: a.happened_on, contact_name: a.with || null,
          summary: String(a.summary || '').slice(0, 4000), next_action: a.next_action || null, next_at: a.next_on || null,
          by_whom: (me() || {}).name || null };
        return db.from('client_touches').insert(row).select('id').then(function (r) {
          if (r.error) throw new Error(r.error.message);
          if (!(r.data || []).length) throw new Error('Not saved. The database refused the request.');
          var id = r.data[0].id, c = a._client;
          if (bridge.log) bridge.log('client.touch', c.name, (KIND[a.kind] || a.kind) + (a.next_action ? ' · next: ' + a.next_action : ''));
          file('assistant.call', c.name, (KIND[a.kind] || a.kind) + ' logged');
          /* The first call or visit is what makes a lead contacted, as the
             Calls and visits pane does. */
          var moved = (c.stage || 'lead') === 'lead'
            ? db.from('clients').update({ stage: 'contacted' }).eq('id', c.id).select('id').then(function (q) {
                if (q.error || !(q.data || []).length || !bridge.log) return;
                var CRM = window.ADspaceCRM;
                bridge.log('client.stage', c.name, CRM && CRM.contactedWord ? CRM.contactedWord(c) : 'Contacted');
              })
            : Promise.resolve();
          return moved.then(function () {
            return { said: 'Logged.', open: { kind: 'client', id: c.slug || c.id, pane: 'calls', label: 'Open Calls and visits' },
              undo: function () {
                return db.from('client_touches').update({ archived_at: new Date().toISOString() }).eq('id', id).select('id').then(function (q) {
                  if (q.error || !(q.data || []).length) throw new Error('Not undone. The database refused the request.');
                  if (bridge.log) bridge.log('client.touch_removed', c.name, KIND[a.kind] || a.kind);
                });
              } };
          });
        });
      }
    },
    propose_remark: {
      title: 'Add remark',
      card: function (a) {
        return task(a.task_id).then(function (t) { a._task = t; return [['Task', taskName(t)], ['Remark', a.text]]; });
      },
      run: function (a) {
        return db.rpc('ops_add_comment', { p_task: a.task_id, p_body: String(a.text || '').slice(0, 2000) }).then(rpcOk).then(function () {
          file('assistant.task', (a._task.clients && a._task.clients.name) || 'Internal', taskName(a._task) + ' · remark added');
          return { said: 'Remark added.', open: { kind: 'task', id: a.task_id, label: 'Open task' } };
        });
      }
    },
    propose_mark_sent: {
      title: 'Mark as sent',
      card: function (a) {
        if (!may('reports', 'work')) return Promise.reject(new Error('You do not have permission to mark reports as sent. Please ask an admin.'));
        if (!validDay(a.sent_on)) return Promise.reject(new Error('Enter a valid date.'));
        return db.from('sm_reports').select('id, kind, period_start, period_end, status, sent_on, brand_name, clients(name)').eq('id', a.report_id).maybeSingle()
          .then(function (r) {
            if (!r.data) throw new Error('That report could not be found.');
            if (r.data.status !== 'published') throw new Error('Only a published report can be marked as sent.');
            a._report = reportRow(r.data); a._was = r.data.sent_on || null;
            return [['Report', a._report.kind + ' · ' + a._report.period], ['Client', a._report.brand || a._report.client],
                    ['Sent', (a._was ? dayWord(a._was) : 'Not sent') + ' → ' + dayWord(a.sent_on)]];
          });
      },
      run: function (a) {
        return db.rpc('sm_report_sent', { p_id: a.report_id, p_on: a.sent_on }).then(rpcOk).then(function () {
          file('assistant.report', a._report.brand || a._report.client || '', a._report.kind + ' · ' + a._report.period + ' marked as sent ' + dayWord(a.sent_on));
          return { said: 'Marked as sent.', open: { kind: 'report', id: a.report_id, label: 'Open report' },
            undo: function () { return db.rpc('sm_report_sent', { p_id: a.report_id, p_on: a._was }).then(rpcOk); } };
        });
      }
    }
  };

  /* ---- Where a record opens: its own address, then its section ------------ */
  function addressOf(o) {
    var id = encodeURIComponent(o.id || '');
    switch (o.kind) {
      case 'client': return ['/admin/?client=' + id + (o.pane && o.pane !== 'overview' ? '&tab=' + encodeURIComponent(o.pane) : ''), 'clients'];
      case 'task': return ['/admin/?s=work&open=' + id, 'work'];
      case 'report': return ['/admin/?s=reports&report=' + id, 'reports'];
      case 'set': return ['/admin/?s=review&set=' + id, 'review'];
      case 'script': return ['/admin/?s=scripts&script=' + id, 'scripts'];
      case 'campaign': return ['/admin/?s=campaigns&campaign=' + id, 'campaigns'];
      case 'dashboard': return ['/admin/?s=dashboard', 'overview'];
      default: return ['/admin/?s=work', 'work'];
    }
  }
  function openRecord(o) {
    if (o.kind !== 'my_work' && o.kind !== 'dashboard' && !o.id) return;
    var to = addressOf(o);
    if (SHEET.isOpen(box)) SHEET.close();
    history.replaceState(null, '', to[0]);
    if (to[1] === 'review' && bridge.restore) bridge.restore();
    else if (bridge.show) bridge.show(to[1]);
  }

  /* ---- Drawing the conversation ------------------------------------------- */
  /* Claude's words as the console writes them: paragraphs, lines starting
     "- " as a list, **words** in weight. Escaped first. */
  function words(text) {
    var out = [], list = [];
    var flush = function () { if (list.length) { out.push('<ul>' + list.join('') + '</ul>'); list = []; } };
    String(text || '').split(/\n/).forEach(function (line) {
      var l = esc(line.trim()).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>');
      if (/^[-•*]\s+/.test(line.trim())) { list.push('<li>' + l.replace(/^[-•*]\s+/, '') + '</li>'); return; }
      flush();
      if (l) out.push('<p>' + l + '</p>');
    });
    flush();
    return out.join('');
  }
  function add(html, cls) {
    var el = document.createElement('div');
    el.className = cls;
    el.innerHTML = html;
    var empty = log.querySelector('.ag-empty');
    if (empty) empty.hidden = true;
    log.appendChild(el);
    log.scrollTop = log.scrollHeight;
    return el;
  }
  function factsHtml(f) {
    return '<dl class="ag-facts">' + f.filter(Boolean).map(function (x) { return '<dt>' + esc(x[0]) + '</dt><dd>' + esc(x[1]) + '</dd>'; }).join('') + '</dl>';
  }
  function openBtn(o) {
    var b = document.createElement('button');
    b.type = 'button'; b.className = 'btn btn-sm ag-open';
    b.innerHTML = esc(o.label || 'Open') + ' <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>';
    b.addEventListener('click', function () { openRecord(o); });
    return b;
  }

  function cardFor(use, def) {
    var a = use.input || {};
    var el = add('<h4>' + esc(def.title) + '</h4><div class="ag-card-body"></div>' +
      '<div class="ag-acts"><button type="button" class="btn btn-primary ag-yes">Confirm</button><button type="button" class="btn btn-quiet ag-no">Cancel</button></div>' +
      '<p class="msg ag-msg" role="status"></p>', 'ag-confirm');
    var yes = el.querySelector('.ag-yes'), no = el.querySelector('.ag-no'), msg = el.querySelector('.ag-msg');
    yes.disabled = true;
    def.card(a).then(function (f) {
      el.querySelector('.ag-card-body').innerHTML = factsHtml(f);
      yes.disabled = false;
    }).catch(function (e) {
      el.querySelector('.ag-acts').remove();
      el.querySelector('.ag-card-body').innerHTML = '';
      msg.className = 'msg warn ag-msg'; msg.textContent = (e && e.message) || 'This change cannot be made. Ask again.';
      state.notes.push('The proposed change (' + def.title + ') could not be prepared: ' + msg.textContent);
    });
    no.addEventListener('click', function () {
      el.querySelector('.ag-acts').remove();
      msg.className = 'msg ag-msg'; msg.textContent = 'Cancelled.';
      state.notes.push('The colleague cancelled the proposed change: ' + def.title + '.');
    });
    yes.addEventListener('click', function () {
      yes.disabled = true; no.disabled = true;
      def.run(a).then(function (out) {
        el.querySelector('.ag-acts').remove();
        el.classList.add('is-done');
        var line = document.createElement('div');
        line.className = 'ag-done';
        line.innerHTML = '<span>' + esc(out.said) + '</span>';
        if (out.open) line.appendChild(openBtn(out.open));
        if (out.undo) {
          var u = document.createElement('button');
          u.type = 'button'; u.className = 'btn btn-sm'; u.textContent = 'Undo';
          u.addEventListener('click', function () {
            u.disabled = true;
            out.undo().then(function () {
              line.innerHTML = '<span>Undone.</span>';
              state.notes.push('The colleague undid the change: ' + def.title + '.');
            }).catch(function (e) { u.disabled = false; msg.className = 'msg err ag-msg'; msg.textContent = (e && e.message) || 'Not undone.'; });
          });
          line.appendChild(u);
        }
        msg.replaceWith(line);
        state.notes.push('The colleague confirmed the change and it was made: ' + def.title + '. ' + out.said);
      }).catch(function (e) {
        yes.disabled = false; no.disabled = false;
        msg.className = 'msg err ag-msg'; msg.textContent = (e && e.message) || 'Not saved.';
      });
    });
    return el;
  }

  /* ---- Asking -------------------------------------------------------------- */
  function busy(on) {
    state.busy = on;
    sendBtn.disabled = on;
    field.disabled = on;
    var w = log.querySelector('.ag-wait');
    if (on && !w) add('<span class="ag-dots" aria-hidden="true"><i></i><i></i><i></i></span><span class="sr">Writing</span>', 'ag-wait');
    if (!on && w) w.remove();
  }
  function context() {
    var m = me() || {};
    var now = CLOCK && CLOCK.clock ? CLOCK.clock(new Date()) : '';
    return '\n\n(Today is ' + (CLOCK && CLOCK.weekday ? ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][CLOCK.weekday(today())] + ', ' : '') + dayWord(today()) + (now ? ', ' + now : '') +
      ' Malaysia time. The colleague asking is ' + (m.name || 'a colleague') + (m.id ? ', person_id ' + m.id : '') + '.)';
  }
  function ask(text) {
    text = String(text || '').trim();
    if (!text || state.busy) return;
    add('<p>' + esc(text) + '</p>', 'ag-me');
    var content = [];
    if (state.notes.length) { content.push({ type: 'text', text: '[' + state.notes.join(' ') + ']' }); state.notes = []; }
    content.push({ type: 'text', text: text + (state.messages.length ? '' : context()) });
    trim();
    state.mark = state.messages.length;
    state.messages.push({ role: 'user', content: content });
    state.press = '';
    if (chips) chips.hidden = true;
    step(0);
  }
  /* The conversation sent is kept to its last turns (the function takes 80
     messages at most), cut where a question of the colleague's begins, so a
     tool's answer never arrives without its call. */
  function trim() {
    if (state.messages.length <= 40) return;
    var i = state.messages.length - 40;
    while (i < state.messages.length && !(state.messages[i].role === 'user' &&
           state.messages[i].content.some(function (b) { return b.type === 'text'; }) &&
           !state.messages[i].content.some(function (b) { return b.type === 'tool_result'; }))) i++;
    state.messages = state.messages.slice(i);
  }
  function step(n) {
    busy(true);
    var mine = ++state.said;
    db.functions.invoke('portal-agent', { body: { messages: state.messages, press: state.press || undefined } }).then(function (res) {
      if (mine !== state.said) return;
      var d = res.data;
      if (typeof d === 'string') { try { d = JSON.parse(d); } catch (e) { d = null; } }
      if (res.error || !d) return fail('The Assistant could not be reached. Try again.');
      if (d.error) { if (d.error === 'ai-limit') showLeft(0); return fail(saidOf(d.error)); }
      if (d.press) state.press = d.press;
      if (typeof d.left === 'number') showLeft(d.left);
      var content = Array.isArray(d.content) ? d.content : [];
      state.messages.push({ role: 'assistant', content: content });
      busy(false);
      content.forEach(function (b) { if (b.type === 'text' && b.text) add(words(b.text), 'ag-ai'); });
      var uses = content.filter(function (b) { return b.type === 'tool_use'; });
      if (d.stop !== 'tool_use' || !uses.length) { field.disabled = false; if (!matchMedia('(pointer: coarse)').matches) field.focus(); return; }
      busy(true);
      Promise.all(uses.map(runTool)).then(function (results) {
        if (mine !== state.said) return;
        state.messages.push({ role: 'user', content: results });
        if (n >= 11) return fail(saidOf('too-many-steps'));
        step(n + 1);
      });
    }).catch(function () { if (mine === state.said) fail('The Assistant could not be reached. Try again.'); });
  }
  function fail(words0) {
    busy(false);
    add('<p>' + esc(words0) + '</p>', 'ag-ai is-err');
    /* The question that failed is taken out, so the next one starts clean
       (the conversation must end on a whole answer). */
    state.messages.length = Math.min(state.messages.length, state.mark || 0);
    state.press = '';
    field.disabled = false;
  }
  function result(use, body, isErr) {
    var r = { type: 'tool_result', tool_use_id: use.id, content: JSON.stringify(body).slice(0, 28000) };
    if (isErr) r.is_error = true;
    return r;
  }
  function runTool(use) {
    var name = use.name, a = use.input || {};
    if (READ[name]) {
      return READ[name](a).then(function (out) { return result(use, out, false); })
        .catch(function (e) { return result(use, { error: 'could-not-read', why: (e && e.message) || '' }, true); });
    }
    if (CHANGE[name]) {
      cardFor(use, CHANGE[name]);
      return Promise.resolve(result(use, { shown: 'The change is shown to the colleague as a card. Nothing is written until they confirm it.' }, false));
    }
    if (name === 'open_page') {
      var el = add('', 'ag-ai ag-opens');
      if (a.kind === 'my_work' || a.kind === 'dashboard' || a.id) el.appendChild(openBtn(a));
      return Promise.resolve(result(use, { shown: 'A button to open it is shown.' }, false));
    }
    return Promise.resolve(result(use, { error: 'unknown-tool' }, true));
  }

  function showLeft(n) {
    if (!left) return;
    left.textContent = n + ' left today';
    left.hidden = false;
  }
  function readLeft() {
    db.rpc('ai_agent_left').then(function (r) {
      var d = r.data || {};
      if (r.error || d.error) { if (left) left.hidden = true; return; }
      showLeft(d.left);
    }, function () {});
  }

  /* ---- The panel ----------------------------------------------------------- */
  function open() {
    if (!box.hidden) return;
    /* A desk types straight in; under a finger the card takes focus, as
       every sheet does, so the keyboard does not rise over it. */
    var desk = !matchMedia('(pointer: coarse)').matches;
    SHEET.show(box, { opener: btn, focus: desk ? '#agentQ' : null, onClose: function () { btn.setAttribute('aria-expanded', 'false'); } });
    btn.setAttribute('aria-expanded', 'true');
    readLeft();
  }
  function close() { if (SHEET.isOpen(box)) SHEET.close(); }
  function clear() {
    state.messages = []; state.press = ''; state.notes = []; state.said++;
    busy(false);
    Array.prototype.slice.call(log.children).forEach(function (c) { if (!c.classList.contains('ag-empty')) c.remove(); else c.hidden = false; });
    if (chips) chips.hidden = false;
    field.disabled = false;
  }
  btn.hidden = false;
  btn.addEventListener('click', open);
  $('agentClose') && $('agentClose').addEventListener('click', close);
  $('agentClear') && $('agentClear').addEventListener('click', clear);
  $('agentForm').addEventListener('submit', function (e) {
    e.preventDefault();
    var t = field.value;
    field.value = '';
    if (window.ADspaceGrow) window.ADspaceGrow.fit(field);
    ask(t);
  });
  field.addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) { e.preventDefault(); $('agentForm').requestSubmit(); }
  });
  if (chips) chips.addEventListener('click', function (e) {
    var c = e.target.closest('[data-ask]');
    if (c) ask(c.getAttribute('data-ask'));
  });
  document.addEventListener('keydown', function (e) {
    if ((e.metaKey || e.ctrlKey) && !e.altKey && (e.key === 'j' || e.key === 'J')) {
      if (document.querySelector('.sheet:not([hidden]):not(#agentSheet)')) return;
      e.preventDefault();
      if (box.hidden) open(); else close();
    }
  });

  window.ADspaceAgent = { open: open, ask: function (t) { open(); ask(t); }, _tools: { read: READ, change: CHANGE } };
})();
