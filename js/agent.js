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
 * `assistant.report`, `assistant.meeting`, `assistant.campaign`,
 * `assistant.set`, `assistant.whatsapp`, `assistant.schedule`).
 * Since 2026-11-13 (the user: "approve build both") it may book a month's
 * meeting, create a campaign, publish or unpublish a set, and send a
 * WhatsApp template to a client, each only behind its card; and schedule a
 * reminder or one of those for later (`agent_schedule_add`, run as the
 * colleague every five minutes). It never deletes, and never touches
 * money, billing, access or performance: those are not among its tools.
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
  var CHANNEL = { google_meet: 'Google Meet', onsite: 'On site', zoom: 'Zoom', other: 'Other' };
  var CAMP_STATE = { draft: 'Draft', open: 'Open for selection', production: 'In production', completed: 'Completed' };
  var MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
  function monthName(p) {
    var m = /^(\d{4})-(\d{2})/.exec(String(p || ''));
    return m ? MON[Number(m[2]) - 1] + ' ' + m[1] : String(p || '');
  }
  /* A moment as the console writes it: Tue 18 Nov, 3:00pm (Malaysia). */
  function whenWord(iso) {
    if (!iso || !CLOCK) return '';
    var d = CLOCK.day(iso);
    var wd = CLOCK.weekday ? ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][CLOCK.weekday(d)] + ' ' : '';
    return wd + CLOCK.date(d, { year: false }) + ', ' + CLOCK.clock(iso);
  }
  function validTime(v) { return /^([01]\d|2[0-3]):[0-5]\d$/.test(String(v || '')); }

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
    /* A client's content months in My Work: whether each is confirmed,
       and its meeting, so a meeting is booked on the right month. */
    client_months: function (a) {
      if (!may('ops')) return Promise.resolve(noAccess());
      return team().then(function () {
        return db.from('ops_engagements').select('id, period, status, meeting_at, meeting_channel, meeting_minutes, meeting_na, meeting_owner_id, meeting_event_id')
          .eq('client_id', a.client_id).order('period', { ascending: false }).limit(8);
      }).then(rows).then(function (list) {
        return { months: list.map(function (e) {
          return { month: e.period, name: monthName(e.period), state: e.status === 'cancelled' ? 'Cancelled' : e.status === 'completed' ? 'Completed' : 'Open',
            meeting: e.meeting_na ? 'Not needed this month' : e.meeting_at ? whenWord(e.meeting_at) + ' · ' + (CHANNEL[e.meeting_channel] || 'Meeting') +
              (e.meeting_owner_id ? ' · led by ' + nameOf(e.meeting_owner_id) : '') : 'Not set' };
        }) };
      });
    },
    /* A client's content sets in Content Review, where each one's posts
       stand, newest first. */
    list_sets: function (a) {
      if (!may('review.sets')) return Promise.resolve(noAccess());
      return db.from('batches').select('id, title, period, published, created_at').eq('client_id', a.client_id)
        .order('created_at', { ascending: false }).limit(12).then(rows).then(function (list) {
          if (!list.length) return { sets: [] };
          return db.rpc('review_set_counts', { p_sets: list.map(function (b) { return b.id; }) }).then(function (r) {
            var n = {};
            (r.data || []).forEach(function (x) { n[x.set_id] = x; });
            return { sets: list.map(function (b) {
              var c = n[b.id] || {};
              return { set_id: b.id, title: b.title, month: b.period ? monthName(b.period) : 'Ad hoc', state: b.published ? 'Published' : 'Draft',
                posts: c.n_posts || 0, approved: c.n_approved || 0, changes_requested: c.n_changes || 0, not_decided: c.n_undecided || 0 };
            }) };
          });
        });
    },
    list_campaigns: function (a) {
      if (!may('campaigns.campaigns')) return Promise.resolve(noAccess());
      var q = db.from('campaigns').select('id, title, state, slots, owner, campaign_code, clients(name)');
      if (a.client_id) q = q.eq('client_id', a.client_id);
      return q.order('created_at', { ascending: false }).limit(15).then(rows).then(function (list) {
        return { campaigns: list.map(function (c) {
          return { campaign_id: c.id, title: c.title || 'Untitled campaign', campaign_id_code: c.campaign_code || null,
            client: (c.clients && c.clients.name) || null, state: CAMP_STATE[c.state] || c.state, creators: c.slots, person_in_charge: c.owner || null };
        }) };
      });
    },
    /* A client's contacts, to name who a WhatsApp goes to: never a number
       or an email, only whether WhatsApp can reach them. */
    find_contacts: function (a) {
      if (!may('clients.contacts')) return Promise.resolve(noAccess());
      return db.from('client_contacts').select('id, salutation, name, role, is_primary, whatsapp, phone').eq('client_id', a.client_id)
        .is('archived_at', null).limit(20).then(rows).then(function (list) {
          return { contacts: list.map(function (k) {
            return { contact_id: k.id, name: [k.salutation, k.name].filter(Boolean).join(' '), role: k.role || null, primary: !!k.is_primary,
              whatsapp: !!((k.whatsapp && !/^@/.test(k.whatsapp)) || k.phone) };
          }) };
        });
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
    },

    /* A client month's meeting (2026-11-13, the user: "approve build
       both"): saved as the month's Meeting sheet saves it, then booked on
       the shared calendar by `meet-create` for a Google Meet; a slot the
       calendar holds is refused in the card and the month put back. */
    propose_meeting: {
      title: 'Book meeting', go: 'Book',
      card: function (a) {
        if (!may('ops', 'work')) return Promise.reject(new Error('You do not have permission to book meetings. Please ask an admin.'));
        if (!validDay(a.date) || !validTime(a.time)) return Promise.reject(new Error('Enter a valid date and time.'));
        var mins = Number(a.minutes) || 30;
        if (mins < 15 || mins > 240) return Promise.reject(new Error('Choose a length from 15 to 240 minutes.'));
        var at = CLOCK.at(a.date, a.time);
        var google = a.channel !== 'onsite';
        if (google && at.getTime() < nextSlot().getTime()) return Promise.reject(new Error('Choose a time from ' + whenWord(nextSlot().toISOString()) + '.'));
        return Promise.all([team(), db.from('clients').select('id, name, client_code, slug').eq('id', a.client_id).maybeSingle(),
          db.from('ops_engagements').select('id, period, status, meeting_at, meeting_channel, meeting_minutes, meeting_link, meeting_owner_id, meeting_event_id, meeting_na')
            .eq('client_id', a.client_id).eq('period', String(a.month || '').slice(0, 7)).maybeSingle()]).then(function (g) {
          var c = g[1].data, e = g[2].data;
          if (!c) throw new Error('That client could not be found.');
          if (!e) throw new Error('That client has no ' + monthName(a.month) + ' in My Work. Add the month first.');
          if (e.status === 'cancelled' || e.status === 'completed') throw new Error('That month is ' + e.status + '. Reopen it in My Work first.');
          var lead = a.led_by || (me() || {}).id;
          if (a.led_by && !nameOf(a.led_by)) throw new Error('That colleague could not be found. Ask again with their name.');
          a._client = c; a._eng = e; a._at = at; a._mins = mins; a._lead = lead; a._google = google;
          return [['Client', c.name + (c.client_code ? ' · ' + c.client_code : '')], ['Month', monthName(e.period)],
                  ['When', whenWord(at.toISOString()) + ' to ' + CLOCK.clock(new Date(at.getTime() + mins * 60000).toISOString())],
                  ['Channel', google ? 'Google Meet' : 'On site'], ['Led by', lead === (me() || {}).id ? 'You' : nameOf(lead)],
                  e.meeting_at && !e.meeting_na ? ['Replaces', whenWord(e.meeting_at)] : null];
        });
      },
      run: function (a) {
        var e = a._eng, c = a._client;
        var set = function (at, ch, owner, mins, link) {
          return db.rpc('ops_engagement_set_meeting', { p_engagement: e.id, p_at: at, p_channel: ch, p_owner: owner, p_note: null, p_na: false,
            p_minutes: mins, p_link: link }).then(rpcOk);
        };
        var meet = function (action) {
          return db.functions.invoke('meet-create', { body: { engagementId: e.id, action: action } })
            .then(function (r) { return r.error ? { error: 'unreachable' } : (r.data || {}); }, function () { return { error: 'unreachable' }; });
        };
        /* A pasted link is kept only for a channel that has one; the
           calendar makes a Google Meet's. */
        return set(a._at.toISOString(), a._google ? 'google_meet' : 'onsite', a._lead, a._mins, '').then(function () {
          /* On site takes the month's Google Meet off the calendar, as the
             sheet does when the channel changes. */
          if (!a._google) return e.meeting_event_id ? meet('delete').then(function () { return {}; }) : {};
          return meet('create');
        }).then(function (d) {
          if (d && d.error) {
            var back = e.meeting_at && !e.meeting_na
              ? set(e.meeting_at, e.meeting_channel, e.meeting_owner_id, e.meeting_minutes, e.meeting_link || '').then(function () {
                  return e.meeting_event_id ? meet('create') : null;
                }).catch(function () { return null; })
              : Promise.resolve();
            return back.then(function () {
              throw new Error('Not booked. ' + meetSaid(d) + (e.meeting_at && !e.meeting_na ? '' : ' The month keeps the time without a link.'));
            });
          }
          return db.from('ops_engagements').select('meeting_at, meeting_minutes, meeting_link').eq('id', e.id).maybeSingle();
        }).then(function (r) {
          var x = (r && r.data) || {};
          file('assistant.meeting', c.name, monthName(e.period) + ' meeting booked for ' + whenWord(a._at.toISOString()));
          var OPS = window.ADspaceOps;
          var message = OPS && OPS.meetingMessage ? OPS.meetingMessage({ at: a._at.toISOString(), minutes: a._mins, online: a._google,
            month: monthName(e.period), channel: a._google ? 'Google Meet' : 'On site', link: x.meeting_link || '' }) : '';
          return { said: 'Booked.', open: { kind: 'client_month', id: c.slug || c.id, label: 'Open month' },
            facts: x.meeting_link ? [['Link', x.meeting_link]] : null, copy: message || null,
            /* The month's meeting as it was: an event it had moves back;
               an event this booking made leaves the calendar first, so the
               link it had is written back after. */
            undo: function () {
              var had = e.meeting_at && !e.meeting_na;
              var gone = a._google && !e.meeting_event_id
                ? meet('delete').then(function (d) { if (d && d.error) throw new Error('Not undone. The Google Meet could not be removed from the calendar.'); })
                : Promise.resolve();
              return gone.then(function () {
                if (!had) return null;
                return set(e.meeting_at, e.meeting_channel, e.meeting_owner_id, e.meeting_minutes, e.meeting_link || '').then(function () {
                  return e.meeting_event_id ? meet('create') : null;
                });
              });
            } };
        });
      }
    },

    /* A creator campaign, made as New campaign makes it: a draft with no
       creators, the colleague's own link key. */
    propose_campaign: {
      title: 'Create campaign', go: 'Create',
      card: function (a) {
        if (!may('campaigns.campaigns', 'work')) return Promise.reject(new Error('You do not have permission to create campaigns. Please ask an admin.'));
        var title = String(a.title || '').trim();
        if (!/[\p{L}\p{N}]/u.test(title) || title.length > 120) return Promise.reject(new Error('Enter a campaign name.'));
        var slots = Number(a.creators);
        if (!(slots >= 1 && slots <= 200) || Math.floor(slots) !== slots) return Promise.reject(new Error('Enter 1 or more creators.'));
        return Promise.all([team(), db.from('clients').select('id, name, client_code, stage').eq('id', a.client_id).maybeSingle()]).then(function (g) {
          var c = g[1].data;
          if (!c) throw new Error('That client could not be found.');
          if (c.stage !== 'active') throw new Error('Campaigns are made for an Active client.');
          if (a.person_in_charge && !nameOf(a.person_in_charge)) throw new Error('That colleague could not be found. Ask again with their name.');
          a._client = c; a._title = title; a._slots = slots;
          a._owner = a.person_in_charge ? nameOf(a.person_in_charge) : (me() || {}).name || '';
          return [['Client', c.name + (c.client_code ? ' · ' + c.client_code : '')], ['Title', title], ['Creators', String(slots)],
                  ['Person in charge', a.person_in_charge && a.person_in_charge !== (me() || {}).id ? a._owner : 'You'],
                  ['Format', FORMAT[a.format] || 'Site visit'], ['State', 'Draft, no creators yet']];
        });
      },
      run: function (a) {
        return db.from('campaigns').insert({
          client_id: a._client.id, title: a._title, purpose: null, slots: a._slots, deadline: null,
          push_format: FORMAT[a.format] ? a.format : 'site_visit', deliverable: a.deliverable === 'graphic' ? 'graphic' : 'video',
          owner: a._owner || null, backups_open: false, access_token: API.accessToken(), state: 'draft',
          created_by: (bridge.actor && bridge.actor()) || null
        }).select('id').then(function (r) {
          if (r.error) throw new Error(r.error.message);
          if (!(r.data || []).length) throw new Error('Not saved. The database refused the request.');
          if (bridge.log) bridge.log('campaign.created', a._title, a._slots + ' creators');
          file('assistant.campaign', a._title, 'Campaign created for ' + a._client.name);
          return { said: 'Created.', open: { kind: 'campaign', id: r.data[0].id, label: 'Open campaign' } };
        });
      }
    },

    propose_publish_set: setMove(true),
    propose_unpublish_set: setMove(false),

    /* A WhatsApp template, through the composer's own path: the record's
       facts from `wa_compose_prepare`, Sent recently asked first, then
       `wa-send`, which files it before Meta is asked. Nothing goes without
       Send. */
    propose_whatsapp: {
      title: 'Send on WhatsApp', go: 'Send',
      card: function (a) { return waCard(a); },
      run: function (a) {
        return db.functions.invoke('wa-send', { body: { action: 'compose', to_kind: 'contact', to_id: a.contact_id, purpose: a._purpose,
          ref: a._ref, template: { name: a._tpl.name, language: a._tpl.language }, values: a._values, header_value: '', again: a._recent ? true : undefined } })
          .then(function (res) {
            var d = res && res.data;
            if (res.error || !d || d.error) {
              var code = (d && d.error) || 'wa-failed';
              if (code === 'recent') throw new Error('It was sent on WhatsApp moments ago. Ask again to see who sent it.');
              throw new Error(WA() && WA().said ? WA().said({ code: code }) : 'Not sent. Please try again.');
            }
            file('assistant.whatsapp', a._prep.subject || a._prep.client || '', (a._tplWord || a._tpl.name) + ' sent to ' + (d.to || a._prep.name));
            return { said: 'Sent.', open: a._prep.client_id ? { kind: 'client', id: a._prep.client_id, pane: 'account', label: 'Open client' } : null };
          });
      }
    },

    /* Something for later (2026-11-13): kept by `agent_schedule_add` and run
       every five minutes as the colleague, their access asked again then.
       A Google Meet is never scheduled: the calendar must answer at once. */
    propose_schedule: {
      title: function (a) { return SCHED_TITLE[a.kind] || 'Schedule'; },
      card: function (a) { return schedCard(a); },
      run: function (a) {
        return db.rpc('agent_schedule_add', { p_kind: a.kind, p_at: a._at.toISOString(), p_title: a._title, p_payload: a._payload,
          p_condition: a.condition || null, p_ref: a._cref || null }).then(function (r) {
          if (r.error) throw new Error(/function|schema cache/i.test(r.error.message || '') ? SAID['needs-update'] : r.error.message);
          var d = r.data || {};
          if (d.error) throw new Error(SCHED_SAID[d.error] || refusal(d.error));
          readSched();
          return { said: 'Scheduled.', undo: function () {
            return db.rpc('agent_schedule_cancel', { p_id: d.id }).then(rpcOk).then(function () { readSched(); });
          } };
        });
      }
    }
  };

  var FORMAT = { site_visit: 'Site visit', event: 'Event', seeding: 'Product seeding', tenant_trail: 'Tenant trail' };
  function WA() { return window.ADspaceWhatsApp; }

  /* The earliest a Google Meet can be booked: the next half hour, as the
     month's Meeting sheet holds it. */
  function nextSlot() { var half = 30 * 60000; return new Date(Math.floor(Date.now() / half) * half + half); }
  function meetSaid(d) {
    var k = d && d.error;
    if (k === 'slot-taken') return 'The shared calendar already has a meeting' + (d.start ? ' at ' + CLOCK.clock(d.start) + (d.end ? ' to ' + CLOCK.clock(d.end) : '') : '') + '. Choose another time.';
    if (k === 'meet-not-set-up') return 'Google Meet is not set up yet. Please contact an admin.';
    if (k === 'google-token' || k === 'google-refused') return 'Google Meet is not available at the moment. Please contact an admin.';
    if (k === 'meet-pending') return 'Google is still creating the link. Open the month and press Create Google Meet in a moment.';
    return 'Google Meet could not be reached. Try again.';
  }

  /* Publish or unpublish a content set, as the set's own head does. */
  function setMove(on) {
    return {
      title: on ? 'Publish set' : 'Unpublish set', go: on ? 'Publish' : 'Unpublish',
      card: function (a) {
        if (!may('review.sets', 'work')) return Promise.reject(new Error('You do not have permission to publish sets. Please ask an admin.'));
        return db.from('batches').select('id, title, period, published, client_id, clients(name)').eq('id', a.set_id).maybeSingle().then(function (r) {
          var b = r.data;
          if (!b) throw new Error('That set could not be found.');
          if (Boolean(b.published) === on) throw new Error(on ? 'That set is already published.' : 'That set is not published.');
          return db.rpc('review_set_counts', { p_sets: [b.id] }).then(function (q) {
            var n = ((q.data || [])[0] || {}).n_posts || 0;
            if (on && !n) throw new Error('That set holds no posts. Add assets before publishing.');
            a._set = b;
            return [['Set', b.title + ' · ' + n + (n === 1 ? ' post' : ' posts')], ['Client', (b.clients && b.clients.name) || ''],
                    ['Change', on ? 'Draft → Published' : 'Published → Draft'],
                    ['Client sees', on ? 'On the review link at once' : 'No longer on the review link']];
          });
        });
      },
      run: function (a) {
        var b = a._set, client = (b.clients && b.clients.name) || '';
        var go = function (next) {
          return db.from('batches').update({ published: next }).eq('id', b.id).select('id').then(function (r) {
            if (r.error) throw new Error(r.error.message);
            if (!(r.data || []).length) throw new Error('Not saved. The database refused the request.');
            if (bridge.log) bridge.log(next ? 'set.published' : 'set.withdrawn', client + ' — ' + b.title);
          });
        };
        return go(on).then(function () {
          file('assistant.set', client + ' — ' + b.title, on ? 'Published' : 'Unpublished');
          return { said: on ? 'Published.' : 'Unpublished.', open: { kind: 'set', id: b.id, label: 'Open set' },
            undo: function () { return go(!on); } };
        });
      }
    };
  }

  /* The WhatsApp card: the recipient and the record as the database names
     them, the template the purpose has on (else the one named), each
     variable filled as the composer fills it, and Sent recently. */
  function waCard(a) {
    var X = WA();
    var purpose = a.purpose;
    if (!X || !X.meta) return Promise.reject(new Error('WhatsApp is not available on this page. Open Messages.'));
    if (['approval', 'feedback', 'representative', 'message'].indexOf(purpose) < 0) return Promise.reject(new Error('Choose what the message is for.'));
    if (!X.may(purpose)) return Promise.reject(new Error('You do not have permission to send this on WhatsApp. Please ask an admin.'));
    var ref = purpose === 'approval' ? (a.ref || null) : null;
    if (purpose === 'approval' && !ref) return Promise.reject(new Error('Name the set or the booking that waits for approval.'));
    /* Which template each purpose has on is read afresh: it is changed in
       Settings while a page stays open. */
    var onNow = db.rpc('wa_templates_read').then(function (r) { return { list: ((r && r.data) || {}).templates || [] }; }, function () { return { list: [] }; });
    return Promise.all([db.rpc('wa_compose_prepare', { p_to_kind: 'contact', p_to: a.contact_id, p_purpose: purpose, p_ref: ref }), X.meta(), onNow]).then(function (g) {
      var prep = g[0].data || {};
      if (g[0].error) throw new Error(g[0].error.message);
      if (prep.error) throw new Error(X.said ? X.said({ code: prep.error }) : 'This message cannot be sent.');
      var meta = g[1] || {}, set = g[2] || {};
      if (meta.error) throw new Error(X.said ? X.said(meta.error) : 'The templates could not be read.');
      var list = (meta.list || []).filter(function (t) { return t.supported; });
      var mine = (set.list || []).filter(function (t) { return t.purpose === purpose && t.active && t.name; })[0];
      var tpl = a.template ? list.filter(function (t) { return t.name === a.template; })[0]
        : mine ? list.filter(function (t) { return t.name === mine.name && t.language === mine.lang; })[0] : null;
      if (!tpl) {
        if (purpose === 'message' || a.template) {
          state.notes.push('The templates the portal can send are: ' + list.filter(function (t) { return t.header !== 'DOCUMENT'; }).map(function (t) { return t.name; }).join(', ') + '.');
          throw new Error(a.template ? 'That template is not approved for the portal. Choose another.' : 'Name the template to send.');
        }
        throw new Error('The WhatsApp template for this message is off. An admin turns it on in Settings.');
      }
      if (tpl.header === 'DOCUMENT' || tpl.header_var) throw new Error('This template carries a file or a header of its own. Send it from its record.');
      if (X.badButton(tpl)) throw new Error('This template\'s link button cannot be filled. Choose another template.');
      return whatWaits(purpose, ref).then(function (what) {
        var link = prep.link ? location.origin + '/' + prep.link : '';
        var fill = function (v) {
          var low = String(v).toLowerCase();
          if (/^\d+$/.test(v)) return v === '1' ? prep.greeting || prep.name || '' : v === '2' ? prep.client || '' :
            v === '3' ? (purpose === 'approval' ? what : purpose === 'representative' ? prep.rep || '' : '') :
            v === '4' && purpose === 'approval' ? link : '';
          if (purpose === 'approval' && /link|url|approve/.test(low)) return link;
          if (purpose === 'representative' && /rep|sales|person|staff|colleague/.test(low)) return prep.rep || '';
          if (purpose === 'approval' && /what|item|waiting|set|draft|content/.test(low)) return what;
          if (/client|brand|company|business/.test(low)) return prep.client || '';
          if (/name|greet|salut|contact|recipient/.test(low)) return prep.greeting || prep.name || '';
          return '';
        };
        var values = {};
        (tpl.body_vars || []).forEach(function (v) { values[v] = fill(v); });
        var empty = Object.keys(values).filter(function (k) { return !values[k]; });
        if (empty.length) throw new Error('This template needs words the Assistant cannot fill. Send it from Messages.');
        var body = String(tpl.body || '').replace(/\{\{\s*([A-Za-z0-9_]+)\s*\}\}/g, function (m, v) { return values[v] || m; });
        var btns = (tpl.buttons || []).map(function (b) { return '[ ' + b.text + ' ]'; }).join('  ');
        a._purpose = purpose; a._ref = ref; a._tpl = tpl; a._values = values; a._prep = prep;
        a._tplWord = (purpose === 'approval' ? 'Approval reminder' : purpose === 'feedback' ? 'Feedback request' : purpose === 'representative' ? 'Representative' : tpl.name);
        return db.rpc('wa_sent_recently', { p_to_kind: 'contact', p_to: a.contact_id, p_purpose: purpose, p_ref: ref, p_template: tpl.name }).then(function (r) {
          var rec = r.data && r.data.recent ? r.data : null;
          a._recent = rec;
          var hours = (r.data && r.data.hours) || 24;
          return { facts: [['To', (prep.greeting || prep.name) + ' · ' + X.phone(prep.number)], ['Template', a._tplWord + (X.category(tpl.category) ? ' · ' + X.category(tpl.category) : '')],
                           ['Sent recently', rec ? 'Yes, ' + whenWord(rec.at) + (rec.by ? ' by ' + rec.by : '') : 'None in ' + hours + ' hours']],
                   preview: body + (tpl.footer ? '\n\n' + tpl.footer : '') + (btns ? '\n\n' + btns : ''),
                   warn: rec ? 'This was sent recently. Send it again only if it is still needed.' : '', go: rec ? 'Send again' : 'Send' };
        });
      });
    });
  }
  /* What waits on the client, as My Work's Remind words it. */
  function whatWaits(purpose, ref) {
    if (purpose !== 'approval') return Promise.resolve('');
    return db.from('batches').select('id, title').eq('id', ref).maybeSingle().then(function (r) {
      if (r.data) {
        return db.rpc('review_set_counts', { p_sets: [ref] }).then(function (q) {
          var n = ((q.data || [])[0] || {}).n_undecided || 0;
          return n + (n === 1 ? ' post' : ' posts') + (r.data.title ? ' in ' + r.data.title : '');
        });
      }
      return db.from('campaign_options').select('id, creators(name), campaigns(title)').eq('id', ref).maybeSingle().then(function (o) {
        var x = o.data || {};
        return ((x.creators && x.creators.name) || 'The creator') + '\'s draft for ' + (String((x.campaigns && x.campaigns.title) || '').trim() || 'your campaign');
      });
    });
  }

  /* ---- Something for later ------------------------------------------------- */
  var SCHED_TITLE = { reminder: 'Schedule reminder', mark_sent: 'Schedule mark as sent', add_task: 'Schedule task',
    publish_set: 'Schedule publish', unpublish_set: 'Schedule unpublish', whatsapp: 'Schedule WhatsApp' };
  var SCHED_KIND = { reminder: 'Reminder', mark_sent: 'Mark as sent', add_task: 'Add task', publish_set: 'Publish set',
    unpublish_set: 'Unpublish set', whatsapp: 'WhatsApp' };
  var SCHED_SAID = { 'bad-time': 'Choose a time from a minute from now to 92 days ahead.', 'bad-title': 'Enter what it is about.',
    'bad-condition': 'That condition cannot be checked. Ask again without it.', 'bad-payload': 'Something it needs is missing. Ask again.',
    'too-many': 'You have 50 runs waiting. Cancel one under Scheduled first.', 'wa-off': 'The WhatsApp template for this message is off. An admin turns it on in Settings.',
    'not-found': 'That record could not be found.', 'bad-kind': 'That cannot be scheduled.' };
  var COND = { set_undecided: 'The set still has posts the client has not decided', report_not_sent: 'The report is not yet marked as sent',
    task_open: 'The task is not yet finished' };
  function schedCard(a) {
    if (!SCHED_KIND[a.kind]) return Promise.reject(new Error('That cannot be scheduled. A Google Meet is booked straight away.'));
    if (!validDay(a.date) || !validTime(a.time)) return Promise.reject(new Error('Enter a valid date and time.'));
    var at = CLOCK.at(a.date, a.time);
    if (at.getTime() < Date.now() + 60000) return Promise.reject(new Error('Choose a time later than now.'));
    if (a.condition && !COND[a.condition]) return Promise.reject(new Error('That condition cannot be checked. Ask again without it.'));
    a._at = at;
    a._cref = a.condition === 'set_undecided' ? (a.set_id || a.ref) : a.condition === 'report_not_sent' ? a.report_id : a.condition === 'task_open' ? a.task_id : null;
    if (a.condition && !a._cref) return Promise.reject(new Error('Name the record the condition is about.'));
    var when = ['When', whenWord(at.toISOString())];
    var only = a.condition ? ['Only if', COND[a.condition]] : null;
    var done = function (what, title, payload, more) {
      a._title = String(a.title || title || '').trim().slice(0, 200) || title;
      a._payload = payload;
      return [when].concat(what, [only], more || []);
    };
    if (a.kind === 'reminder') {
      var text = String(a.message || '').trim();
      if (text.length < 2) return Promise.reject(new Error('Enter what to be reminded of.'));
      return Promise.resolve(done([['To', 'You, in the bell and on your phone']], text.slice(0, 120),
        { message: text.slice(0, 500), task_id: a.task_id || null, report_id: a.report_id || null, client_id: a.client_id || null }, [['Message', text]]));
    }
    if (a.kind === 'mark_sent') {
      return CHANGE.propose_mark_sent.card({ report_id: a.report_id, sent_on: a.date }).then(function (f) {
        var r = a._rep = f;
        return done([r[0], r[1], ['Sent', 'Marked as sent on the day it runs']], 'Mark ' + (r[0][1] || 'the report') + ' as sent', { report_id: a.report_id });
      });
    }
    if (a.kind === 'add_task') {
      var t = { title: a.task_title || a.title, client_id: a.client_id || null, owner_id: a.owner_id || null, due_date: a.due_date, priority: a.priority || 'normal', description: a.message || null };
      return CHANGE.propose_add_task.card(t).then(function (f) {
        var payload = { title: String(t.title || '').trim().slice(0, 200), workflow_key: 'task', scope: t.client_id ? 'client' : 'internal',
          client_id: t.client_id, engagement_id: null, task_type: 'adhoc', owner_id: t.owner_id || (me() || {}).id,
          final_due_at: t.due_date + 'T00:00:00Z', description: t.description, priority_level: PRIORITY[t.priority] || 3, checklist: [] };
        return done(f.filter(Boolean), 'Add task: ' + payload.title, payload);
      });
    }
    if (a.kind === 'publish_set' || a.kind === 'unpublish_set') {
      var on = a.kind === 'publish_set';
      return setMove(on).card({ set_id: a.set_id }).catch(function (e) {
        /* A set empty now may hold its posts by then; one published now is
           still refused. */
        if (on && /holds no posts/.test(e.message)) return [['Set', 'Holds no posts yet']];
        throw e;
      }).then(function (f) {
        return done([f[0], f[1], f[2]], (on ? 'Publish ' : 'Unpublish ') + String(f[0][1] || 'set').split(' · ')[0], { set_id: a.set_id });
      });
    }
    if (a.kind === 'whatsapp') {
      if (['approval', 'feedback', 'representative'].indexOf(a.purpose) < 0) return Promise.reject(new Error('Only an approval reminder, a feedback request or a representative\'s introduction can be scheduled.'));
      var w0 = { contact_id: a.contact_id, purpose: a.purpose, ref: a.ref, template: null };
      return waCard(w0).then(function (w) {
        return done([w.facts[0], w.facts[1]], w0._tplWord + ' to ' + (w0._prep.name || ''),
          { to_id: a.contact_id, purpose: a.purpose, ref: a.ref || null }, [['Sent recently', 'Checked again when it runs']]);
      });
    }
    return Promise.reject(new Error('That cannot be scheduled.'));
  }

  /* ---- Scheduled: the colleague's own runs ----------------------------------- */
  var sched = { rows: [], open: false };
  var STATE_WORD = { waiting: ['Waiting', 'is-warn'], running: ['Running', 'is-warn'], done: ['Done', 'is-ok'], skipped: ['Skipped', 'is-off'],
    failed: ['Failed', 'is-danger'], cancelled: ['Cancelled', 'is-off'] };
  function readSched() {
    return db.rpc('agent_schedule_list').then(function (r) {
      var d = r.data || {};
      sched.rows = r.error || d.error ? [] : (d.rows || []);
      sched.failed = Boolean(r.error || d.error);
      paintSched();
    }, function () { sched.rows = []; paintSched(); });
  }
  function schedRow(s) {
    var st = STATE_WORD[s.state] || [s.state, ''];
    return '<li class="ag-srow" data-id="' + esc(s.id) + '"><span class="ag-stitle">' + esc(s.title) + '</span>' +
      (s.state === 'waiting' ? '<button class="btn btn-sm" type="button" data-cancel="' + esc(s.id) + '">Cancel</button>'
        : '<span class="chip-state ' + st[1] + '">' + esc(st[0]) + '</span>') +
      '<span class="ag-smeta">' + esc(whenWord(s.run_at) + ' · ' + (SCHED_KIND[s.kind] || s.kind)) + '</span>' +
      (s.result && s.state !== 'waiting' ? '<span class="ag-sres">' + esc(s.result) + '</span>' : '') + '</li>';
  }
  function paintSched() {
    var waiting = sched.rows.filter(function (s) { return s.state === 'waiting'; });
    var b = $('agentSched'), n = $('agentSchedN'), boxEl = $('agentSchedBox'), home = $('agentSchedHome');
    if (b) {
      b.hidden = !sched.rows.length;
      if (n) { n.textContent = String(waiting.length); n.hidden = !waiting.length; }
      if (!sched.rows.length && sched.open) toggleSched(false);
    }
    if (boxEl) boxEl.querySelector('ul').innerHTML = sched.rows.length ? sched.rows.map(schedRow).join('') : '<li class="ag-snone">Nothing scheduled.</li>';
    if (home) {
      home.hidden = !waiting.length;
      home.querySelector('ul').innerHTML = waiting.map(schedRow).join('');
    }
  }
  function toggleSched(on) {
    sched.open = on == null ? !sched.open : on;
    var b = $('agentSched'), boxEl = $('agentSchedBox');
    if (boxEl) boxEl.hidden = !sched.open;
    if (b) b.setAttribute('aria-expanded', String(sched.open));
  }
  function cancelSched(id, btn0) {
    btn0.disabled = true;
    db.rpc('agent_schedule_cancel', { p_id: id }).then(rpcOk).then(function () {
      state.notes.push('The colleague cancelled a scheduled run.');
      return readSched();
    }).catch(function (e) {
      btn0.disabled = false;
      var li = btn0.closest('li');
      if (li && !li.querySelector('.msg')) { var m = document.createElement('span'); m.className = 'msg err ag-sres'; m.textContent = e.message; li.appendChild(m); }
    });
  }

  /* ---- Where a record opens: its own address, then its section ------------ */
  function addressOf(o) {
    var id = encodeURIComponent(o.id || '');
    switch (o.kind) {
      case 'client': return ['/admin/?client=' + id + (o.pane && o.pane !== 'overview' ? '&tab=' + encodeURIComponent(o.pane) : ''), 'clients'];
      case 'task': return ['/admin/?s=work&open=' + id, 'work'];
      case 'client_month': return ['/admin/?s=work&view=months&wc=' + id, 'work'];
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
    var title = typeof def.title === 'function' ? def.title(a) : def.title;
    var el = add('<h4>' + esc(title) + '</h4><div class="ag-card-body"></div>' +
      '<div class="ag-acts"><button type="button" class="btn btn-primary ag-yes">' + esc(def.go || 'Confirm') + '</button><button type="button" class="btn btn-quiet ag-no">Cancel</button></div>' +
      '<p class="msg ag-msg" role="status"></p>', 'ag-confirm');
    var yes = el.querySelector('.ag-yes'), no = el.querySelector('.ag-no'), msg = el.querySelector('.ag-msg');
    var facts = [];
    yes.disabled = true;
    def.card(a).then(function (got) {
      /* A card answers its facts, or its facts with the message as it will
         read, a warning, and its own word for the act. */
      var o = Array.isArray(got) ? { facts: got } : got;
      facts = o.facts.filter(Boolean);
      el.querySelector('.ag-card-body').innerHTML = factsHtml(facts) +
        (o.preview ? '<p class="ag-preview">' + esc(o.preview) + '</p>' : '') +
        (o.warn ? '<p class="msg warn">' + esc(o.warn) + '</p>' : '');
      if (o.go) yes.textContent = o.go;
      yes.disabled = false;
    }).catch(function (e) {
      el.querySelector('.ag-acts').remove();
      el.querySelector('.ag-card-body').innerHTML = '';
      msg.className = 'msg warn ag-msg'; msg.textContent = (e && e.message) || 'This change cannot be made. Ask again.';
      state.notes.push('The proposed change (' + title + ') could not be prepared: ' + msg.textContent);
    });
    no.addEventListener('click', function () {
      el.querySelector('.ag-acts').remove();
      msg.className = 'msg ag-msg'; msg.textContent = 'Cancelled.';
      state.notes.push('The colleague cancelled the proposed change: ' + title + '.');
    });
    yes.addEventListener('click', function () {
      yes.disabled = true; no.disabled = true;
      def.run(a).then(function (out) {
        el.querySelector('.ag-acts').remove();
        el.classList.add('is-done');
        var line = document.createElement('div');
        line.className = 'ag-done';
        line.innerHTML = '<span>' + esc(out.said) + '</span>';
        /* What the act made (a meeting's link) joins the facts. */
        if (out.facts) el.querySelector('.ag-card-body').innerHTML = factsHtml(facts.concat(out.facts));
        if (out.copy) {
          var cp = document.createElement('button');
          cp.type = 'button'; cp.className = 'btn btn-sm ag-copy'; cp.textContent = 'Copy message';
          cp.addEventListener('click', function () { if (window.ADspaceCopy) window.ADspaceCopy.to(cp, out.copy); });
          line.appendChild(cp);
        }
        if (out.undo) {
          var u = document.createElement('button');
          u.type = 'button'; u.className = 'btn btn-sm'; u.textContent = 'Undo';
          u.addEventListener('click', function () {
            u.disabled = true;
            out.undo().then(function () {
              line.innerHTML = '<span>Undone.</span>';
              state.notes.push('The colleague undid the change: ' + title + '.');
            }).catch(function (e) { u.disabled = false; msg.className = 'msg err ag-msg'; msg.textContent = (e && e.message) || 'Not undone.'; });
          });
          line.appendChild(u);
        }
        if (out.open) line.appendChild(openBtn(out.open));
        msg.replaceWith(line);
        state.notes.push('The colleague confirmed the change and it was made: ' + title + '. ' + out.said);
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
    readSched();
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
  $('agentSched') && $('agentSched').addEventListener('click', function () { toggleSched(); });
  ['agentSchedBox', 'agentSchedHome'].forEach(function (id) {
    var el = $(id);
    if (el) el.addEventListener('click', function (e) {
      var b = e.target.closest && e.target.closest('[data-cancel]');
      if (b && !b.disabled) cancelSched(b.getAttribute('data-cancel'), b);
    });
  });
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

  window.ADspaceAgent = { open: open, ask: function (t) { open(); ask(t); }, _tools: { read: READ, change: CHANGE }, scheduled: readSched };
})();
